# nixbot CI service for magnetite, serving the fleet's GitHub repositories.
# It replaced buildbot-nix, which no longer runs anywhere in the fleet.
#
# Credential generator catalog (slots; values populated as marked):
#   - nixbot-github-app-secret-key: manual `clan vars set` (GitHub App PEM key)
#   - nixbot-github-oauth-secret: manual `clan vars set` (OAuth client secret)
#   - nixbot-github-webhook-secret: auto-generated
# Each names nixbot.service in restartUnits because the unit snapshots its
# credentials at start, so a rotation without a restart leaves the running
# service holding the superseded value.
#
# Settings carried over from the period nixbot ran beside buildbot-nix:
#   - github.topic is null; its default "build-with-buildbot" one-shot-imports
#     every repository carrying that topic on an empty DB.
#   - nginx.enable stays true, so the service listens only on
#     /run/nixbot/web.sock and binds no TCP port.
#   - A dedicated GitHub App: nixbot needs Checks write and the
#     check_run/check_suite events. It also needs Pull requests: Read and
#     write, because the browser-evidence effect comments through
#     /api/v1/pr-comment and GitHub answers 403 to that comment with
#     read-only access (nixbot docs/GITHUB.md).
#
# The webhook secret has two sources and they must agree. The application was
# registered through GitHub's App manifest flow, which generated a webhook
# secret of its own; the nixbot-github-webhook-secret generator below
# independently generates a different one. This generator is authoritative, so
# the application's webhook secret must be replaced with its value at
# deployment, or every delivery fails signature validation.
{
  config,
  inputs,
  ...
}:
let
  flakeLib = config.flake.lib;
  flakeModules = config.flake.modules.nixos;
in
{
  # The patches nixbot is built with, in application order. Shared with
  # checks.x86_64-linux.nixbot-eval-record, which runs the patched runner.
  #
  # A merge-queue batch reusing its PR build would otherwise never get
  # nixbot/effects, stalling gitea-mq until its check timeout. An
  # ignoreFailure attribute whose dependency failed would otherwise fail
  # the build (dependency_failed) instead of being ignored. Without
  # optional_build_grace (nixbot.toml) a build waits for every
  # ignoreFailure attribute, up to the 3 h build timeout on a sleeping Mac.
  # A renamed or removed effect's last failed run would otherwise stay in
  # the web "N failing" count, since it never runs again to clear it.
  # Nothing would record an evaluation's memory peak against its ceiling,
  # its kills, or which evaluator ran: the evaluation-record patch logs one
  # `evaluation finished` JSON line per evaluation, which the dev-loop
  # collection copies into devloop.eval_run (modules/nixos/devloop-collection.nix).
  # It is written against upstream's names so it can be offered to
  # Mic92/nixbot.
  #
  # Not patched: _dispatch_build (orchestrator.py) checks ancestry, awaits,
  # then registers, so gitea-mq's back-to-back pushes of one batch ref can
  # cancel the newest build as "superseded"; gitea-mq then bisects and the
  # batch reports flaky=true. Fails safe; seen once in 27 multi-PR batches
  # (2026-09-20..10-14), against a hot upstream file to carry a patch on.
  flake.lib.nixbotPatches = [
    ./nixbot-gated-reuse-effects-summary.patch
    ./nixbot-ignore-failure-dependents.patch
    ./nixbot-abandon-optional-attributes.patch
    ./nixbot-failing-effects-defined.patch
    ./nixbot-evaluation-record.patch
  ];

  flake.modules.nixos.nixbot =
    {
      config,
      lib,
      options,
      pkgs,
      ...
    }:
    {
      # The host nixbot evaluates on also measures what competes with those
      # evaluations for its memory (CAM-111 design D11), which is why the
      # budget comes with this module rather than with the host.
      #
      # The iets evaluator (CAM-111 design D3) is built from this host's own
      # stock evaluator and exposed read-only, so it can be built and checked
      # on the host without being selected: nothing on the host refers to it,
      # and services.nixbot.packages.nix-eval-jobs below stays the stock one.
      imports = [
        flakeModules.magnetite-memory-budget
        (
          {
            lib,
            options,
            pkgs,
            ...
          }:
          {
            options.vanixiets.nixbot.ietsEvaluator = lib.mkOption {
              type = lib.types.package;
              readOnly = true;
              default =
                flakeLib.mkNixEvalJobsIets pkgs inputs.iets.packages.${pkgs.stdenv.hostPlatform.system}.default
                  options.services.nixbot.packages.nix-eval-jobs.default;
              defaultText = lib.literalExpression "flake.lib.mkNixEvalJobsIets pkgs inputs.iets.packages.\${system}.default options.services.nixbot.packages.nix-eval-jobs.default";
              description = "iets as a nix-eval-jobs package for nixbot, built from this host's stock evaluator; not selected.";
            };
          }
        )
      ];

      # GitHub App private key (populated manually via clan vars set)
      clan.core.vars.generators.nixbot-github-app-secret-key = {
        files."key.pem" = {
          owner = "nixbot";
          restartUnits = [ "nixbot.service" ];
        };
        script = ''
          echo "nixbot GitHub App private key: populate via clan vars set" >&2
          exit 1
        '';
      };

      # GitHub OAuth secret (populated manually via clan vars set)
      clan.core.vars.generators.nixbot-github-oauth-secret = {
        files."secret" = {
          owner = "nixbot";
          restartUnits = [ "nixbot.service" ];
        };
        script = ''
          echo "nixbot GitHub OAuth secret: populate via clan vars set" >&2
          exit 1
        '';
      };

      clan.core.vars.generators.nixbot-github-webhook-secret = {
        files."secret" = {
          owner = "nixbot";
          restartUnits = [ "nixbot.service" ];
        };
        runtimeInputs = [ pkgs.openssl ];
        script = ''
          openssl rand -hex 32 > $out/secret
        '';
      };

      services.nixbot = {
        enable = true;
        domain = "nixbot.scientistexperience.net";

        admins = [ "github:cameronraysmith" ];

        # aarch64-darwin is built best-effort on whichever Mac magnetite can
        # reach (modules/checks/nixbot-best-effort-darwin.nix). evalSystems
        # matters because nixbot.toml's attribute is "checks": it is what
        # keeps aarch64-linux, which no builder here serves, unevaluated
        # (nixbot/nixbot/nix/select.nix:37-50).
        buildSystems = [
          "x86_64-linux"
          "aarch64-darwin"
        ];
        evalSystems = [
          "x86_64-linux"
          "aarch64-darwin"
        ];

        # Caps concurrent `nix build` client processes, not CPU: the default
        # (the 16 cores) let best-effort darwin attributes, which wait on a
        # remote Mac, hold every slot while stibnite slept, so no
        # x86_64-linux attribute started for 2.5 h (builds 1381-1388). Local
        # CPU is capped by the daemon's max-jobs and each builder by its
        # nix.buildMachines maxJobs. Each attribute build holds one
        # auto-allocated uid range, so the bound is id-count / 65536
        # (8388608 / 65536 = 128).
        buildConcurrency = 128;

        # 6 x 3072 MiB, measured on the two-system scope (311 attributes, 75 GiB
        # of evaluator allocation in total; nix-eval-jobs runs Boehm with
        # GC_DONT_GC=1, so a worker's heap only grows until it is recycled):
        #
        #   6 x 3072   341 s   peak 18.7 GB   24 restarts   no swap   fastest
        #   5 x 4096   419 s   peak 21.6 GB   20 restarts   no swap
        #   4 x 4096   476 s   peak 16.0 GB   16 restarts   no swap
        #   8 x 2048   505 s   peak 16.3 GB   42 restarts   no swap
        #   8 x 1536   727 s   peak 12.9 GB   64 restarts   (MemoryHigh 12G)
        #   8 x 4096   aborted at 186/311 after 163 s: 0 restarts, 42 GB in
        #              zram (9.2 GB real), 2.7 GB left on the host
        #
        # The x86-only optimum (8 x 4096 under MemoryHigh 12G, 131.5 s for 144
        # attributes) never recycled because resident memory was held below the
        # limit and the heaps spilled ~31 GiB into zram. With aarch64-darwin the
        # heaps need ~75-85 GiB, which no zram size can back in 30.6 GiB of RAM,
        # and that regime crawled to nixbot's 60-minute timeout (build 1115).
        # Here workers recycle instead, and nix-eval-jobs' own budget (workers x
        # max-memory-size, plus the attribute in flight) is the bound, so
        # MemoryHigh below sits above the measured peak and does not bind. At
        # peak about 8 GB stays free for concurrent local builds.
        # logs/magnetite-two-system-eval-experiment.md.
        evalWorkerCount = 6;
        evalMaxMemorySize = 3072;

        github = {
          enable = true;

          # Public identifiers of the dedicated application github.com/apps/sciexp-nixbot.
          appId = 4743700;
          oauthId = "Iv23lie8GaDpY0cPXGg4";

          appSecretKeyFile =
            config.clan.core.vars.generators.nixbot-github-app-secret-key.files."key.pem".path;
          webhookSecretFile =
            config.clan.core.vars.generators.nixbot-github-webhook-secret.files."secret".path;
          oauthSecretFile = config.clan.core.vars.generators.nixbot-github-oauth-secret.files."secret".path;

          # Default is "build-with-buildbot", which one-shot-imports every
          # repository carrying that topic against an empty DB.
          topic = null;

          # nixbot serves only the repositories named here. Entries are
          # forge-local names, without the "github:" prefix that
          # perRepoSecretFiles keys carry.
          repoAllowlist = [
            "cameronraysmith/vanixiets"
            "sciexp/ironstar"
          ];
        };

        # Hold pull requests from outside the repositories until a maintainer
        # approves CI for them. Upstream's default also trusts CONTRIBUTOR,
        # which is anyone with a previously merged pull request; dropping it
        # gates them too. Pull requests whose head branch lives in the base
        # repository, renovate's and the flake updater's included, are always
        # trusted, since pushing that branch already needed write access
        # (nixbot/nixbot/approval.py:31-38). A held pull request is approved
        # with its check run's button or
        # `POST /api/repos/github/<owner>/<repo>/pulls/<N>/approve`.
        prApproval = {
          enable = true;
          trustedAssociations = [
            "OWNER"
            "MEMBER"
            "COLLABORATOR"
          ];
        };

        # The module creates the vhost proxying to /run/nixbot/web.sock and this
        # flag makes it forceSSL + enableACME.
        nginx.enableACME = true;

        database.createLocally = true;

        # Push successful builds to the fleet's binary cache. Without it the
        # service builds correctly and uploads nothing: the uploader set
        # defaults to the empty list, so no upload is attempted and no signal
        # is emitted anywhere. The public URL
        # rather than a local socket keeps the endpoint reachable from future
        # remote builders.
        #
        # This option surface is ours; the mechanism behind it is not. Upstream
        # implements these four settings by registering an entry in
        # services.nixbot.uploaders (nixosModules/niks3.nix), a whole-closure
        # push queue that replaced the per-attribute post-build step it used to
        # emit. Uploader failures are logged and never fail a build, which is
        # the same bargain the incumbent's warnOnly post-build step takes.
        niks3 = {
          enable = true;
          serverUrl = "https://niks3.scientistexperience.net";
          authTokenFile = config.clan.core.vars.generators.niks3-api-token.files."token".path;
          package = inputs.niks3.packages.${config.nixpkgs.hostPlatform.system}.niks3;
        };
      };

      # Prometheus endpoint: loopback and ZeroTier mesh only
      services.nginx.virtualHosts.${config.services.nixbot.domain}.locations =
        flakeLib.nginxMetricsLocation
          config.services.nginx.virtualHosts.${config.services.nixbot.domain};

      # Loopback-only scrape endpoint for magnetite's collector (design D9).
      # nixbot binds no TCP port, and a scrape through the public vhost's
      # /metrics would not arrive from loopback.
      services.nginx.virtualHosts."nixbot-metrics-loopback" = {
        listen = [
          {
            addr = "127.0.0.1";
            port = 9180;
          }
        ];
        locations."/metrics".proxyPass = "http://unix:/run/nixbot/web.sock";
      };

      # The service-wide backstop on the evaluation, set above its measured
      # 18.7 GB peak at 6 x 3072 so that nix-eval-jobs' own budget binds first
      # (the evaluator flags above). Throttling evaluator heaps at this limit is
      # what crawled with two systems, so it must not bind in normal operation.
      # MemoryMax is deliberately absent: nixbot runs each eval in a delegated
      # cgroup leaf, and when a parent limit binds, the kernel declares OOM at
      # the service and picks the largest process in the whole subtree, the
      # nixbot daemon included (measured in a replica,
      # logs/nixbot-memorymax-oom-victim.md).
      # No ManagedOOM* knob either: systemd-oomd kills a descendant cgroup of
      # the unit, and the daemon's own `main` sits beside the eval leaves, so the
      # same victim risk applies and was not measured away.
      systemd.services.nixbot.serviceConfig.MemoryHigh = "20G";

      # nixbot forwards NIX_* into its evaluator sandbox and has no option for
      # extra evaluation arguments, so the setting is scoped to its unit.
      systemd.services.nixbot.environment.NIX_CONFIG = "allow-import-from-derivation = false";

      # Names the evaluator in each `evaluation finished` record
      # (nixbot-evaluation-record.patch) as "<evaluator> <version>": a wrapped
      # evaluator's `unwrapped.evaluator`, or nix-eval-jobs for nixbot's own.
      systemd.services.nixbot.environment.NIXBOT_EVALUATOR =
        let
          evaluator = config.services.nixbot.packages.nix-eval-jobs;
        in
        "${evaluator.unwrapped.evaluator or "nix-eval-jobs"} ${evaluator.version}";

      # Every evaluation queues on the host evaluation lock and runs at
      # oom_score_adj 900 (modules/nixos/nix-eval-lock.nix). The wrapper sits
      # over the evaluator nixbot would otherwise use, its own patched build,
      # and forwards that build's `nix` passthru, so the patched nix CLI on the
      # service PATH and the nixbot package itself are unchanged. nixbot runs
      # the bare name from the service PATH inside its bwrap sandbox, which is
      # why the lock lives under /etc/nix.
      services.nixbot.packages.nix-eval-jobs = lib.mkIf config.services.nixEvalLock.enable (
        config.services.nixEvalLock.wrap options.services.nixbot.packages.nix-eval-jobs.default
      );

      services.nixbot.packages.nixbot =
        options.services.nixbot.packages.nixbot.default.overridePythonAttrs
          (old: {
            patches = (old.patches or [ ]) ++ flakeLib.nixbotPatches;
          });
    };
}
