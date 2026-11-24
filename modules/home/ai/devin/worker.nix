# Devin Outposts workers: one option surface, two service backends.
#
# An outpost is a named QUEUE of sessions in Devin Cloud, not a machine. A
# worker is a process that watches one queue, claims a session, and executes
# every command, file edit, and repository operation locally while Devin's
# planning loop stays in their cloud; it needs outbound HTTPS only. N workers
# on one outpost therefore serve N concurrent sessions.
#
# That is why `outposts` is a registry of queues and `workers` is a count, and
# why queues are NOT named per machine index. Naming them `stibnite-1`,
# `stibnite-2` would partition the queue: a session dispatched to a busy queue
# would wait while its sibling queue sat idle, because the operator picks a
# queue when starting the session and cannot know which worker is free.
# Concurrency belongs on the worker count.
#
# Which queue a host serves is named per host, never derived. `outpost` has no
# default: enabling the service without naming a queue fails evaluation and
# names the host. The tempting inference -- serve the queue whose platform
# matches this host -- is wrong here, because this repository carries six
# NixOS machines and four darwin ones, so it would put every linux host that
# enabled the service onto the same linux queue. Those workers would serve
# another machine's sessions perfectly well, since N workers on one queue
# serve N concurrent sessions, which is exactly why nothing would report it.
# `platform` validates the pairing a host names; it never picks one.
#
# Per host the platform decides the supervisor:
#
#   * darwin gets a launchd USER AGENT, deliberately not a system daemon.
#     Devin's computer-use features drive the machine's existing desktop
#     session and need Screen Recording (screenshots) and Accessibility
#     (input) granted to the worker process. A system daemon has no desktop
#     session, so those features would fail with no configuration error to
#     point at. Note that macOS keys those grants to the executable, which is
#     a store path here: a CLI version bump changes the path and the grants
#     have to be given again.
#
#   * linux gets a user-scoped systemd service. A user manager stops with the
#     last login session, so a host serving a queue with nobody logged in also
#     needs `users.users.<name>.linger = true`. That is a NixOS-level option
#     this module cannot reach from home-manager; for the machines in this
#     repository the clan users inventory already sets it (see
#     modules/clan/inventory/services/users/cameron.nix, which lingers
#     cameron on magnetite among others), so the seam is closed at the layer
#     that owns system users rather than duplicated here.
#
# The two supervisors do not reach exact parity on restart, and the difference
# is stated here rather than implied away. systemd stops a worker that exits
# with the config-error code and retries anything else after 30s
# (`RestartPreventExitStatus`). launchd has no per-exit-code equivalent, and
# its `KeepAlive` dictionary conditions are ORed, so only one is usable:
# `PathState` on the token file. What darwin therefore does on a missing token
# is stop -- there is no path to keep alive, so no respawn -- and start on its
# own once the secret is rendered there. What it does NOT do is distinguish a
# token file that exists but is empty or unreadable: the launcher still refuses
# to start, and launchd still respawns it, every 30s under the
# `ThrottleInterval` set here rather than at its ten-second floor. That case is
# a slow loop on darwin where linux would stop.
#
# Each worker instance gets its own working directory because a session's
# repositories are checked out under `$(pwd)/repos`: two workers sharing a
# directory would race on the same checkout. Each also gets its own explicit
# acceptor id, since the upstream default is generated per worker DATA
# directory -- which the instances on one host share -- and an id must never
# be shared, across instances or across machines.
#
# One token file per queue, for rotation rather than for containment. The web
# UI issues a token when an outpost is created, but a token issued for one
# outpost lists every outpost through the account-level endpoint: measured
# against the live account, these credentials are account-scoped for reads
# despite being issued per outpost. Separate files therefore buy independent
# rotation, not blast-radius containment, and no registry entry may fall back
# to a sibling's file -- a queue without its own token refuses to start, so a
# worker never runs addressed at one queue with another queue's credential.
#
# Rotating one, in three steps:
#
#   1. Rotate the token in the Devin UI for that outpost. No rebuild is
#      needed for this step alone -- nothing in this repository holds the
#      value, and the running worker still holds the old one.
#   2. Replace that one key's value in
#      secrets/home-manager/users/crs58/secrets.yaml. The other outpost's key
#      is a separate entry and is not touched.
#   3. Re-activate that host so the new value reaches the worker's runtime
#      path, then restart the worker service
#      (`launchctl kickstart -k gui/$UID/devin-worker-1` on darwin,
#      `systemctl --user restart devin-worker-1` on linux).
#
# Step 3's restart is not optional: the launcher reads the token from the file
# once, at process start, so a running worker keeps using the old value until
# it is restarted, however current the file on disk has become.
{ ... }:
{
  flake.modules.homeManager.devin =
    {
      config,
      lib,
      pkgs,
      # Supplied as a specialArg by home-manager's NixOS and nix-darwin
      # modules, absent in a standalone home configuration.
      osConfig ? null,
      ...
    }:
    let
      cfg = config.services.devin-worker;

      hostOutpostPlatform = if pkgs.stdenv.hostPlatform.isDarwin then "macos" else "linux";

      # Which host serves which queue is a deployment decision, so it is named
      # rather than derived. `platform` validates the pairing; it does not pick
      # it. Deriving the queue from the platform looked adequate while one
      # darwin and one linux host had queues, but this repository already
      # carries six NixOS machines and four darwin ones: under that rule every
      # further linux host that enabled the service would default onto
      # magnetite's queue and silently serve its sessions, which Devin permits
      # -- N workers on one queue serve N concurrent sessions -- and so would
      # not surface as an error anywhere.
      hostLabel =
        if osConfig != null then
          osConfig.networking.hostName
        else
          "${config.home.username or "this user"}@${pkgs.stdenv.hostPlatform.system}";

      selected = if cfg.outpost == null then null else cfg.outposts.${cfg.outpost} or null;

      # Neither a match nor a mismatch: whether a queue with no platform can
      # serve this host is unproven here, so the module reports the state and
      # leaves the worker's own OS validation as the authority at claim time.
      selectedPlatformUnset = selected != null && selected.platform == null;

      # Both resolve to a harmless empty value when the registry entry is
      # missing or incomplete, so the assertions below are what report the
      # problem rather than an evaluation error from deep inside the launcher.
      selectedOutpostId =
        if selected == null then "" else (if selected.id == null then "" else selected.id);

      selectedTokenFile = if selected == null then null else selected.tokenFile;

      indices = lib.genList (index: index + 1) cfg.workers;

      unitName = index: "devin-worker-${toString index}";

      workDir = index: "${cfg.workRoot}/${cfg.outpost}-${toString index}";

      logFile = index: "${cfg.stateDir}/${unitName index}.log";

      # Exit code the launcher uses for a missing credential, distinguishing a
      # permanently misconfigured worker from a transient failure so systemd
      # can decline to restart it. EX_CONFIG from sysexits(3).
      configErrorExit = 78;

      launcher =
        index:
        pkgs.writeShellApplication {
          name = unitName index;
          runtimeInputs = [
            cfg.package
            pkgs.coreutils
            # Required, not optional: every repository operation in a session
            # is a git invocation on this machine.
            pkgs.git
          ];
          meta.description = "Devin Outposts worker ${toString index} for the ${toString cfg.outpost} queue";
          text = ''
            work_dir=${lib.escapeShellArg (workDir index)}
            install -d -m 0700 "$work_dir/repos"

            # The token reaches the process from a sops-rendered file read
            # here, at start, and never from the unit definition: a launchd
            # plist and a systemd unit both land in the world-readable Nix
            # store, so a credential written into either is a credential
            # published to every user on the machine.
            #
            # This queue's own file, with no shared option to fall back to, so
            # a queue whose file is missing refuses to start rather than
            # running with a sibling's credential. That is addressing
            # discipline, not isolation: the credentials are account-scoped
            # for reads.
            token_file=${lib.escapeShellArg (if selectedTokenFile == null then "" else selectedTokenFile)}
            if [ ! -s "$token_file" ]; then
              echo "${unitName index}: no Outposts token for the ${toString cfg.outpost} queue at '$token_file'." >&2
              echo "${unitName index}: set services.devin-worker.outposts.${toString cfg.outpost}.tokenFile to the sops-nix path holding that outpost's worker token." >&2
              echo "${unitName index}: refusing to start. Without a token the CLI would fall back to the operator's interactive login, authenticating as a person rather than this machine and implicitly creating an outpost upstream." >&2
              exit ${toString configErrorExit}
            fi
            DEVIN_OUTPOSTS_TOKEN="$(cat "$token_file")"
            export DEVIN_OUTPOSTS_TOKEN

            # Stable across restarts, distinct per instance, and carrying the
            # machine's own name so it cannot collide with a worker elsewhere
            # in the fleet. Read at runtime rather than at eval time because
            # home-manager has no hostname to read.
            nodename="$(uname -n)"
            DEVIN_WORKER_ACCEPTOR_ID="''${nodename%%.*}-${cfg.outpost}-${toString index}"
            export DEVIN_WORKER_ACCEPTOR_ID

            # Addressed by id rather than by name: a name can be renamed in
            # the web UI, and a stale name would surface as a failure at claim
            # time on a machine nobody is watching, while the id is stable for
            # the queue's lifetime.
            cd "$work_dir"
            exec devin worker start --outpost=${lib.escapeShellArg selectedOutpostId} ${lib.escapeShellArgs cfg.extraArgs}
          '';
        };

      # launchd and a user systemd unit both start with a minimal PATH, and a
      # session shells out to whatever the repository's own tooling needs.
      servicePath = lib.concatStringsSep ":" (
        [ "${config.home.profileDirectory}/bin" ]
        ++ lib.optionals pkgs.stdenv.hostPlatform.isDarwin [
          "/usr/local/bin"
          "/opt/homebrew/bin"
        ]
        ++ [
          "/usr/bin"
          "/bin"
          "/usr/sbin"
          "/sbin"
        ]
      );
    in
    {
      options.services.devin-worker = {
        enable = lib.mkEnableOption ''
          long-running Devin Outposts workers serving one outpost queue on this
          host. Off by default: a worker is owned execution capacity that
          claims sessions and runs them with this user's permissions, so
          enabling it is a per-host decision taken alongside minting its token
        '';

        package = lib.mkPackageOption pkgs "devin-cli" { };

        outposts = lib.mkOption {
          type = lib.types.attrsOf (
            lib.types.submodule {
              options = {
                id = lib.mkOption {
                  type = lib.types.nullOr lib.types.str;
                  default = null;
                  example = "outpost_env-0123456789abcdef0123456789abcdef";
                  description = ''
                    Stable identifier the web UI issues for the queue, of the
                    form `outpost_env-<32 hex>`. `devin worker start
                    --outpost=` accepts either a name or an id, and this
                    module passes the id: the name is the operator's label and
                    can be changed in the UI, at which point a name-addressed
                    worker would keep polling and fail when it tried to claim,
                    on a machine nobody is watching.

                    Null until the queue exists, because the id is issued
                    rather than chosen. Enabling a worker for an entry with no
                    id fails evaluation, naming the outpost: a queue that
                    cannot be addressed is not a working default. Fill it in
                    here, beside the platform, once the queue is created --
                    the id is an identifier, not a credential.
                  '';
                };

                tokenFile = lib.mkOption {
                  type = lib.types.nullOr lib.types.path;
                  default = null;
                  example = lib.literalExpression ''config.sops.secrets."devin-outposts-token-magnetite".path'';
                  description = ''
                    Path to a file holding this queue's worker token, normally
                    a sops-nix secret rendered at activation.

                    One file per queue, for rotation rather than for
                    containment. The web UI issues a token when an outpost is
                    created, but a token issued for one outpost lists every
                    outpost through the account-level endpoint -- measured
                    against the live account -- so these credentials are
                    account-scoped for reads despite being issued per outpost.
                    Separate files buy independent rotation, not a smaller
                    blast radius.

                    There is deliberately no host-level or module-level token
                    option, so a queue whose file is missing cannot fall back
                    to a sibling's: it refuses to start, and a worker never
                    runs addressed at one queue holding another's credential.

                    The token is a bearer credential, so it must never be
                    written into a Nix store path: not into a rendered
                    configuration file, and not into a launchd plist's
                    EnvironmentVariables or a systemd unit's Environment, both
                    of which are store files readable by every user on the
                    machine. The launcher reads this file at start and passes
                    the value through DEVIN_OUTPOSTS_TOKEN.

                    Left null in the registry defaults deliberately: minting
                    the token is an account-level action for the operator, and
                    until it exists this option has nothing correct to point
                    at.
                  '';
                };

                platform = lib.mkOption {
                  type = lib.types.nullOr (
                    lib.types.enum [
                      "linux"
                      "macos"
                      "windows"
                    ]
                  );
                  default = null;
                  description = ''
                    Machine platform the queue was created for, or null when
                    the outpost was created without one -- which the account
                    permits, and which the reference reads as the account
                    default rather than as a particular OS.

                    A platform that names a different OS than this host is a
                    mismatch and fails evaluation: the worker validates the
                    machine's OS against the outpost's platform, and failing
                    here beats discovering it as sessions are claimed and
                    released. A null platform is neither a match nor a
                    mismatch. Whether a queue with no platform can serve this
                    host is not established, so it is reported as its own
                    state -- a warning naming the outpost -- and the worker's
                    own validation remains the authority at claim time.
                  '';
                };

                description = lib.mkOption {
                  type = lib.types.str;
                  default = "";
                  description = "Human-readable description, as shown for the outpost in the Devin web app.";
                };
              };
            }
          );
          default = { };
          description = ''
            Outpost queues this repository knows about, keyed by the name they
            carry in Devin Cloud. Recording them here is a declaration, not a
            creation: creating and deleting an outpost is an account-level
            action taken through the web app or `devin worker outpost create`,
            and nothing in this module reaches upstream to do it.

            The fleet's own queues are populated by this module's config layer
            rather than by this option's default, because an option default is
            replaced wholesale by any definition: a caller adding one entry's
            `id` or `tokenFile` through a default-carried registry would drop
            every other entry, and drop the `platform` of the entry it was
            editing. Definitions merge, so with the registry in the config
            layer a caller writing `outposts."magnetite".tokenFile = ...`
            adds to it. Overriding a value this module sets needs
            `lib.mkForce`, since the module's own entries are `lib.mkDefault`.
          '';
        };

        outpost = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          example = "magnetite";
          description = ''
            Queue this host's workers serve, named per host. Required whenever
            the service is enabled: enabling without it fails evaluation and
            names the host.

            There is deliberately no default to infer it from. Which machine
            serves which queue is a deployment decision, not a computable
            fact, and the obvious inference -- take the queue whose platform
            matches this host -- is actively wrong at fleet scale: with six
            NixOS machines in this repository, every linux host that enabled
            the service would land on the same linux queue and quietly serve
            another machine's sessions. Devin allows that, since N workers on
            one queue serve N concurrent sessions, so nothing upstream would
            report it.
          '';
        };

        workers = lib.mkOption {
          type = lib.types.ints.positive;
          default = 1;
          description = ''
            Number of worker instances on this host, and therefore the number
            of sessions it serves concurrently; further sessions wait in the
            queue. Each instance gets its own working directory and acceptor
            id.

            Raising this above one on a macOS host is only useful for sessions
            that do not use computer use: instances share the machine's single
            desktop session, so two of them driving mouse and keyboard would
            fight over it.
          '';
        };

        workRoot = lib.mkOption {
          type = lib.types.path;
          default = "${config.home.homeDirectory}/devin/workers";
          defaultText = lib.literalExpression ''"''${config.home.homeDirectory}/devin/workers"'';
          description = ''
            Parent directory of the per-instance working directories, each
            `<workRoot>/<outpost>-<index>`. Sessions check their repositories
            out under an instance's `repos` subdirectory and are free to write
            anywhere beneath it, so this is deliberately a plain directory in
            the user's home rather than anything this repository manages
            declaratively.
          '';
        };

        stateDir = lib.mkOption {
          type = lib.types.path;
          default = "${config.xdg.stateHome}/devin-worker";
          defaultText = lib.literalExpression ''"''${config.xdg.stateHome}/devin-worker"'';
          description = "Directory holding each instance's service log.";
        };

        extraArgs = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
          example = [ "--poll-interval-secs=15" ];
          description = "Extra arguments appended to `devin worker start`.";
        };
      };

      config = lib.mkMerge [
        # Unconditional, and pure data: the registry has to be readable for
        # `outpost` to resolve its default, and describing a queue commits this
        # host to nothing.
        {
          # Read from the live account through the fleet API, not assumed:
          # both queues carry the bare machine name as their label, and both
          # were created with a platform. Addressing by id is what makes the
          # label a display detail rather than a claim-time failure.
          services.devin-worker.outposts = {
            "stibnite" = {
              id = lib.mkDefault "outpost_env-2955ae307356487b869030ddb4fc45f7";
              platform = lib.mkDefault "macos";
              description = lib.mkDefault "Apple silicon workstation with a live desktop session for computer use";
            };
            "magnetite" = {
              id = lib.mkDefault "outpost_env-4e8894859f8443258b52e992d4f2d112";
              platform = lib.mkDefault "linux";
              description = lib.mkDefault "x86_64 server capacity for headless sessions";
            };
          };
        }

        (lib.mkIf cfg.enable {
          assertions = [
            {
              assertion = cfg.outpost != null;
              message = ''
                services.devin-worker is enabled on ${hostLabel} but services.devin-worker.outpost is
                unset, so this host has not been told which queue it serves. Name it, e.g.
                services.devin-worker.outpost = "magnetite"; known queues are
                ${lib.concatStringsSep ", " (lib.attrNames cfg.outposts)}.

                There is no default on purpose. Inferring the queue from this host's platform would
                put every linux host in this repository on the same queue, serving another machine's
                sessions without any error to notice.
              '';
            }
            {
              assertion = cfg.outpost == null || selected != null;
              message = ''
                services.devin-worker.outpost is "${toString cfg.outpost}", which is not a key of
                services.devin-worker.outposts (${lib.concatStringsSep ", " (lib.attrNames cfg.outposts)}).
              '';
            }
            {
              assertion =
                cfg.outpost == null
                || selected == null
                || selected.platform == null
                || selected.platform == hostOutpostPlatform;
              message = ''
                services.devin-worker.outpost "${toString cfg.outpost}" is registered for platform
                "${toString (selected.platform or null)}" but this host is "${hostOutpostPlatform}". The worker
                validates the machine's OS against the outpost's platform and refuses to serve a mismatch.
              '';
            }
            {
              assertion = cfg.outpost == null || selected == null || selected.id != null;
              message = ''
                services.devin-worker.outposts.${toString cfg.outpost}.id is null, so this host has no
                stable address for the queue it is meant to serve. The web UI issues the id as
                outpost_env-<32 hex> when the outpost is created; set it beside that entry's platform.

                The name is not used as the address on purpose: renaming the outpost in the UI would
                leave a name-addressed worker failing at claim time rather than here.
              '';
            }
            {
              assertion = cfg.outpost == null || selected == null || selected.tokenFile != null;
              message = ''
                services.devin-worker is enabled but
                services.devin-worker.outposts.${toString cfg.outpost}.tokenFile is null.
                Point it at the sops-nix path holding that outpost's own worker token, e.g.

                  sops.secrets."devin-outposts-token-<host>" = { mode = "0400"; };
                  services.devin-worker.outposts."${toString cfg.outpost}".tokenFile =
                    config.sops.secrets."devin-outposts-token-<host>".path;

                No entry falls back to another's file, so this cannot be satisfied by a sibling
                queue's token even though the credentials are account-scoped for reads. Starting
                without one is not a fallback worth taking: the CLI would authenticate as the
                operator's personal login and implicitly create an outpost upstream.
              '';
            }
          ];

          warnings = lib.optional selectedPlatformUnset ''
            services.devin-worker.outposts."${toString cfg.outpost}" carries no platform, so this
            host's agreement with it is unestablished rather than confirmed: the account permits an
            outpost without a platform and the reference reads that as the account default. This is
            neither a match nor a mismatch here, and the worker's own OS validation is the authority
            when it claims a session. Set the platform on the outpost upstream, and on this entry, to
            have the disagreement caught at evaluation instead.
          '';

          # launchd opens the log file and systemd enters the working directory
          # before the launcher runs, so neither can be left to the launcher to
          # create on first start.
          home.activation.devinWorkerDirectories =
            lib.hm.dag.entryBefore
              [
                "setupLaunchAgents"
                "reloadSystemd"
              ]
              ''
                $DRY_RUN_CMD install -d -m 0700 ${lib.escapeShellArg cfg.stateDir} ${
                  lib.escapeShellArgs (map (index: workDir index) indices)
                }
              '';

          launchd.agents = lib.mkIf pkgs.stdenv.hostPlatform.isDarwin (
            lib.listToAttrs (
              map (
                index:
                lib.nameValuePair (unitName index) {
                  enable = true;
                  # computer use drives the desktop session; see the header.
                  domain = "gui";
                  config = {
                    ProgramArguments = [ (lib.getExe (launcher index)) ];
                    RunAtLoad = true;
                    # launchd has no per-exit-code equivalent of systemd's
                    # RestartPreventExitStatus, and its dictionary conditions
                    # are ORed, so exactly one is meaningful. PathState on the
                    # token file is the one that matches the failure this
                    # module actually produces: with no secret rendered there
                    # is nothing to keep alive, so the worker stops instead of
                    # respawning at launchd's floor, and it starts on its own
                    # once the path appears. A plain `true` here would loop a
                    # tokenless worker every ten seconds forever.
                    KeepAlive =
                      if selectedTokenFile == null then
                        true
                      else
                        {
                          PathState.${toString selectedTokenFile} = true;
                        };
                    # Matches RestartSec on the systemd side for the failures
                    # that do respawn; also lifts launchd's ten-second floor.
                    ThrottleInterval = 30;
                    WorkingDirectory = workDir index;
                    StandardOutPath = logFile index;
                    StandardErrorPath = logFile index;
                    # Not "Background": that class caps CPU and I/O priority,
                    # and a session on this worker runs the repository's builds
                    # and tests.
                    ProcessType = "Standard";
                    # PATH only. A credential here would be a store-published
                    # credential; see the outpost entry's tokenFile.
                    EnvironmentVariables.PATH = servicePath;
                  };
                }
              ) indices
            )
          );

          systemd.user.services = lib.mkIf pkgs.stdenv.hostPlatform.isLinux (
            lib.listToAttrs (
              map (
                index:
                lib.nameValuePair (unitName index) {
                  Unit.Description = "Devin Outposts worker ${toString index} serving the ${toString cfg.outpost} queue";
                  Service = {
                    ExecStart = lib.getExe (launcher index);
                    WorkingDirectory = workDir index;
                    Restart = "on-failure";
                    # A worker that cannot authenticate stays down instead of
                    # polling the API on a loop; every other failure is treated
                    # as transient and retried on a slow cadence.
                    RestartPreventExitStatus = configErrorExit;
                    RestartSec = 30;
                    Environment = [ "PATH=${servicePath}" ];
                  };
                  Install.WantedBy = [ "default.target" ];
                }
              ) indices
            )
          );
        })
      ];
    };
}
