# moshi-hook, the Moshi companion daemon, as a member of the ai aggregate.
#
# One option surface, two service backends: `services.moshi-hook` describes the
# daemon once and the platform decides whether it is realized as a launchd user
# agent or a user-scoped systemd service. Both run the same launcher script, so
# the pairing gate, the state layout, and the failure behaviour are identical
# and only the supervisor differs.
#
# The daemon is per-user, not per-machine: it owns a Unix socket that the user's
# agent processes post hook events to, and a WebSocket carrying that user's
# Moshi pairing. Nothing about it belongs to a system-wide service manager, so
# home-manager -- which reaches every host in this repository where agent sessions
# run -- is the layer that carries it.
#
# Upstream defaults the macOS secret store to Keychain, which cannot be reached
# from an SSH session against a locked login keychain, and this daemon exists to
# be driven from a phone over SSH. Setting MOSHI_STATE_DIR switches the store to
# `<state>/secrets.json` on macOS as well as Linux (`status --json` then
# reports `"secretStore":"file"`), which is what makes one launcher work on
# both platforms.
{ ... }:
{
  flake.modules.homeManager.ai =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.services.moshi-hook;

      # Every caller has to agree on the state directory, not just the service:
      # the hook entries `moshi-hook install` writes are executed by the agent
      # processes, `moshi-hook status` is run by hand, and the Moshi iOS app
      # probes the host over SSH. A caller that missed the override would look
      # for a different socket and, on macOS, a different secret store. Binding
      # the environment to the package rather than to the service makes every
      # entry point agree by construction.
      wrapped = pkgs.symlinkJoin {
        name = "moshi-hook-wrapped-${lib.getVersion cfg.package}";
        inherit (cfg.package) meta;
        paths = [ cfg.package ];
        preferLocalBuild = true;
        nativeBuildInputs = [ pkgs.makeWrapper ];
        postBuild = ''
          wrapProgram $out/bin/moshi-hook \
            --set-default MOSHI_STATE_DIR ${lib.escapeShellArg cfg.stateDir} \
            --set-default MOSHI_SOCKET_PATH ${lib.escapeShellArg cfg.socketPath}

          # symlinkJoin resolves the upstream `moshi` alias against the
          # unwrapped package, so it has to be re-pointed at the wrapper or the
          # documented `moshi <dir>` entry point would run with the daemon's
          # own default state directory instead of the configured one.
          ln -sfn moshi-hook $out/bin/moshi
        '';
      };

      launcher = pkgs.writeShellApplication {
        name = "moshi-hook-service";
        runtimeInputs = [
          wrapped
          pkgs.coreutils
          pkgs.jq
        ];
        meta.description = "Pair moshi-hook if needed, then run the daemon in the foreground";
        text = ''
          install -d -m 0700 ${lib.escapeShellArg cfg.stateDir}

          ${lib.optionalString (cfg.pairingTokenFile != null) ''
            token="$(cat ${lib.escapeShellArg cfg.pairingTokenFile} 2>/dev/null || true)"

            if [ -z "$token" ]; then
              # A blank secret is the not-yet-paired state, not an error.
              # sops-nix validates every declared key when the generation is
              # built, so the key has to exist before the token does; it is
              # seeded blank and replaced with the real token from the app.
              echo "moshi-hook: no pairing token in ${cfg.pairingTokenFile}; starting unpaired" >&2
            elif [ "$(moshi-hook status --json | jq -r '.paired')" != "true" ]; then
              # Gated on the reported pairing state rather than run every start:
              # `pair` rotates the host secret, so an unconditional call would
              # invalidate the credential the app already holds on every boot.
              #
              # The token goes through the environment rather than --token so it
              # never appears in this host's process listing.
              if MOSHI_PAIRING_TOKEN="$token" moshi-hook pair --store file; then
                echo "moshi-hook: paired with Moshi" >&2
              else
                # An unpaired daemon still serves the local socket and gateway,
                # and re-reads the keystore on each reconnect, so a failed pair
                # is worth reporting but not worth refusing to start over.
                echo "moshi-hook: pairing failed; starting unpaired" >&2
              fi
            fi
          ''}

          exec moshi-hook serve
        '';
      };

      # The Moshi app resolves the daemon over SSH from ~/.local/bin, ~/bin, and
      # the Homebrew prefixes before consulting the login shell's PATH, so a
      # profile-only install reads as "not installed" on the phone. These links
      # also give `moshi-hook install` a generation-stable path to record into
      # the agent hook entries; invoked through the profile it would record a
      # store path that the next generation invalidates.
      localBin = ".local/bin";
      localBinAbs = "${config.home.homeDirectory}/${localBin}";
    in
    {
      options.services.moshi-hook = {
        enable = lib.mkEnableOption "the moshi-hook daemon bridging local coding agents to the Moshi app";

        package = lib.mkPackageOption pkgs "moshi-hook" { };

        pairingTokenFile = lib.mkOption {
          type = lib.types.nullOr lib.types.path;
          default = null;
          example = lib.literalExpression ''config.sops.secrets."moshi-pairing-token".path'';
          description = ''
            Path to a file holding the pairing token copied from Moshi's
            Settings -> Hooks screen, normally a sops-nix secret rendered at
            activation. The launcher reads it only when the daemon reports
            itself unpaired, and passes it through `MOSHI_PAIRING_TOKEN` so it
            never reaches the process listing.

            The token is a bearer credential for registering this host, so it
            must not be written into a Nix store path. When null the daemon
            still starts and serves the local socket; it just has no Moshi
            pairing, and `moshi-hook pair` can be run by hand.
          '';
        };

        stateDir = lib.mkOption {
          type = lib.types.path;
          default = "${config.xdg.stateHome}/moshi";
          defaultText = lib.literalExpression ''"''${config.xdg.stateHome}/moshi"'';
          description = ''
            Directory holding the daemon's log, its lockfile, and -- because
            this module always takes the file-backed secret store -- the
            `secrets.json` carrying the host ID and host secret that pairing
            produces.

            The same path is used on both platforms rather than following the
            macOS `~/Library/Application Support/Moshi` default. Nothing reads
            the upstream default once the package wrapper sets
            MOSHI_STATE_DIR, and one path keeps the two backends' semantics
            genuinely identical.
          '';
        };

        socketPath = lib.mkOption {
          type = lib.types.path;
          default = "${cfg.stateDir}/moshi-hook.sock";
          defaultText = lib.literalExpression ''"''${config.services.moshi-hook.stateDir}/moshi-hook.sock"'';
          description = ''
            Unix socket the installed agent hooks post events to. Set
            explicitly rather than left to the daemon, which would otherwise
            place it under `$XDG_RUNTIME_DIR` on Linux and beside the state
            directory on macOS.

            Keep this well inside the platform's `sun_path` limit (104 bytes on
            darwin, 108 on Linux); the daemon cannot bind a longer path.
          '';
        };

        usageCollection = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = ''
            Whether the daemon reports per-agent hook usage upstream. Off by
            default: a minute-interval poll that starts failing silently turns
            into pure background load, since every exec of non-Apple code on
            macOS is a Gatekeeper adjudication, and a continuously-failing poll
            did exactly that on 2026-09-03.
          '';
        };
      };

      config = lib.mkMerge [
        { services.moshi-hook.enable = lib.mkDefault true; }

        (lib.mkIf cfg.enable {
          home.packages = [ wrapped ];

          home.file = {
            "${localBin}/moshi-hook".source = config.lib.file.mkOutOfStoreSymlink "${wrapped}/bin/moshi-hook";
            "${localBin}/moshi".source = config.lib.file.mkOutOfStoreSymlink "${wrapped}/bin/moshi";
          };
          # `~/.config/moshi/config.toml` is upstream's only control surface for
          # usage_collection -- there is no `moshi-hook daemon` flag and no
          # MOSHI_* environment variable for it. Because this module now owns
          # that file, `moshi-hook set usage-collection` will fail against a
          # read-only store path; that is accepted, since this repository is
          # the source of truth for the setting, not the CLI.
          xdg.configFile."moshi/config.toml".text = ''
            [gateway]
            usage_collection = ${lib.boolToString cfg.usageCollection}
          '';

          launchd.agents.moshi-hook = lib.mkIf pkgs.stdenv.hostPlatform.isDarwin {
            enable = true;
            config = {
              ProgramArguments = [ (lib.getExe launcher) ];
              RunAtLoad = true;
              KeepAlive = true;
              ProcessType = "Background";
              StandardOutPath = "${cfg.stateDir}/service.log";
              StandardErrorPath = "${cfg.stateDir}/service.log";
              # launchd starts agents with a minimal PATH. The daemon shells out
              # to tmux, zellij, and herdr to decide whether a session is inside
              # a multiplexer, and on macOS to scutil to pick up the system HTTP
              # proxy; none of those are reachable without this.
              EnvironmentVariables.PATH = lib.concatStringsSep ":" [
                "${config.home.profileDirectory}/bin"
                "/usr/bin"
                "/bin"
                "/usr/sbin"
                "/sbin"
              ];
            };
          };

          # Named to match what upstream's own documentation tells operators to
          # restart: `systemctl --user restart moshi-hook.service`.
          #
          # Bound to the user session, so it runs from first login to last
          # logout. That covers the case this daemon is for -- an SSH session
          # running agents -- but a host that should hold its Moshi connection
          # with nobody logged in needs `users.users.<name>.linger = true`,
          # which is a NixOS-level setting this module cannot reach from
          # home-manager.
          systemd.user.services.moshi-hook = lib.mkIf pkgs.stdenv.hostPlatform.isLinux {
            Unit = {
              Description = "Moshi companion daemon for local coding agents";
              After = [ "network-online.target" ];
              Wants = [ "network-online.target" ];
            };
            Service = {
              ExecStart = lib.getExe launcher;
              Restart = "on-failure";
              RestartSec = 5;
              Environment = [ "PATH=${config.home.profileDirectory}/bin:/usr/bin:/bin" ];
            };
            Install.WantedBy = [ "default.target" ];
          };

          # Agent-hook reconciliation.
          #
          # managedConfigs rewrites the claude, codex, devin, and pi configs
          # wholesale on every activation, dropping the hooks `moshi-hook
          # install` added; this entry runs after it so moshi re-adds them.
          # Those agents declare the hook subtrees as externalPaths, which keeps
          # them out of managedConfigs' dropped-key report. `install` is
          # additive and idempotent, so a second run leaves each file unchanged.
          home.activation.moshiHookReconcile =
            lib.hm.dag.entryBetween
              [
                "setupLaunchAgents"
                "reloadSystemd"
              ]
              [
                "writeBoundary"
                "linkGeneration"
                "managedConfigs"
              ]
              ''
                $DRY_RUN_CMD install -d -m 0700 ${lib.escapeShellArg cfg.stateDir}

                # Reported, not swallowed, and not fatal: a malformed config file
                # belonging to an agent this repository does not manage would otherwise
                # be able to fail an entire generation switch.
                if ! $DRY_RUN_CMD ${localBinAbs}/moshi-hook install; then
                  warnEcho "moshi-hook install failed; agent hooks may be stale. Re-run ${localBinAbs}/moshi-hook install"
                fi
              '';
        })
      ];
    };
}
