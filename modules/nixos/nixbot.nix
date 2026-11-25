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
  # checks.x86_64-linux.nixbot-eval-record, which runs the patched runner,
  # and checks.x86_64-linux.nixbot-upload-local.
  #
  # A merge-queue batch reusing its PR build would otherwise never get
  # nixbot/effects, stalling gitea-mq until its check timeout.
  # A renamed or removed effect's last failed run would otherwise stay in
  # the web "N failing" count, since it never runs again to clear it.
  # Nothing would record an evaluation's memory peak against its ceiling,
  # its kills, or which evaluator ran: the evaluation-record patch logs one
  # `evaluation finished` JSON line per evaluation, which the dev-loop
  # collection copies into devloop.eval_run (modules/nixos/devloop-collection.nix).
  # It is written against upstream's names so it can be offered to
  # Mic92/nixbot. nixbot skips an attribute whose outputs are already in
  # the store (skipped_local), assuming, since buildbot-nix, that CI built
  # and uploaded them earlier or they came from the cache; magnetite also
  # builds outside nixbot (remote builds for stibnite and pyrite, agents'
  # builds), so those outputs never reached the cache (F81, 383
  # x86_64-linux check outputs in the week to 2026-11-19). The
  # upload-local-outputs patch relaxes that assumption in every build: it
  # queues the skipped outputs too, in one batch per build. Pull request
  # builds included, since a fast-forward landing reuses the pull request's
  # build for the default branch and runs nothing. cache-completeness.service
  # (modules/nixos/cache-completeness.nix) watches for misses at run time.
  #
  # Not patched: _dispatch_build (orchestrator.py) checks ancestry, awaits,
  # then registers, so gitea-mq's back-to-back pushes of one batch ref can
  # cancel the newest build as "superseded"; gitea-mq then bisects and the
  # batch reports flaky=true. Fails safe; seen once in 27 multi-PR batches
  # (2026-09-20..10-14), against a hot upstream file to carry a patch on.
  flake.lib.nixbotPatches = [
    ./nixbot-gated-reuse-effects-summary.patch
    ./nixbot-failing-effects-defined.patch
    ./nixbot-evaluation-record.patch
    ./nixbot-upload-local-outputs.patch
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
      # stock evaluator, whose patched `nix` it carries, and is what nixbot
      # evaluates with (services.nixbot.packages.nix-eval-jobs below).
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
              description = "iets as a nix-eval-jobs package for nixbot, built from this host's stock evaluator.";
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

        # Mac checks are required like every other check. They were
        # best-effort (ignoreFailure) until 2026-11-25, which let a real Mac
        # regression go green (build 2456) and left seven updates unproven
        # on 2026-11-24 (builds 3001-3008). The cost: with no Mac builder
        # reachable, nothing lands. In an emergency, `attribute =
        # "checks.x86_64-linux"` in nixbot.toml restricts nixbot to Linux
        # checks without a deploy. The alternative, telling an absent Mac
        # from a failed check, is analysed in commit 7b4f12bb. evalSystems
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
        # (the 16 cores) let darwin attributes, which wait on a remote Mac,
        # hold every slot while stibnite slept, so no x86_64-linux attribute
        # started for 2.5 h (builds 1381-1388). Local
        # CPU is capped by the daemon's max-jobs and each builder by its
        # nix.buildMachines maxJobs. Each attribute build holds one
        # auto-allocated uid range, so the bound is id-count / 65536
        # (8388608 / 65536 = 128).
        buildConcurrency = 128;

        # iets at 5 x 3072 (CAM-111 design D9 (a), the first capacity rung).
        # The paired replay of 2026-11-19 (20 commits, both evaluators in this
        # sandbox, logs/cam-111-replay/) gave identical derivations and cache
        # states, iets a median 3.2x faster than nix-eval-jobs (2.35.4), and
        # iets peaks of 16.6-20.0 GiB at 6 x 3072 against 15.0-17.8 GiB for
        # nix-eval-jobs. One cold first evaluation (e527ef7b) reached the 20G
        # MemoryHigh below, 90.2 % of its ceiling, and ran throttled. Five
        # workers lowered iets' peaks by 2.4-2.8 GiB, to 68-72 % of the
        # ceiling (77.6 % for a cold first evaluation), at no measurable cost
        # in wall time; 6 x 2560 saved as much but recycled workers more.
        # Workers recycle at max-memory-size, so workers x max-memory-size plus
        # the attribute in flight bounds the evaluation. The two-system
        # measurements behind the earlier 6 x 3072 are in
        # logs/magnetite-two-system-eval-experiment.md.
        evalWorkerCount = 5;
        evalMaxMemorySize = 3072;

        github = {
          enable = true;

          # Public identifiers of the dedicated application github.com/apps/sciexp-nixbot.
          appId = 4743700;
          oauthId = "Iv23lie8GaDpY0cPXGg4"; # gitleaks:allow

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

      # The service-wide backstop on the evaluation, set above iets' measured
      # peaks at 5 x 3072 (logs/cam-111-replay/) so that the evaluator's own
      # budget (the flags above) binds first. Throttling evaluator heaps at
      # this limit is what crawled with two systems, so it must not bind in
      # normal operation.
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
      # oom_score_adj 900 (modules/nixos/nix-eval-lock.nix). The evaluator is
      # iets (CAM-111): the wrapper sits over the iets package, which keeps
      # the name nix-eval-jobs and forwards the stock build's `nix` passthru,
      # so the patched nix CLI on the service PATH and the nixbot package
      # itself are unchanged. nixbot runs the bare name from the service PATH
      # inside its bwrap sandbox, which is why the lock lives under /etc/nix.
      # Reverting to the stock evaluator, the safety valve of CAM-111 design
      # D9, replaces config.vanixiets.nixbot.ietsEvaluator on the one line
      # below with options.services.nixbot.packages.nix-eval-jobs.default.
      services.nixbot.packages.nix-eval-jobs = lib.mkIf config.services.nixEvalLock.enable (
        config.services.nixEvalLock.wrap config.vanixiets.nixbot.ietsEvaluator
      );

      services.nixbot.packages.nixbot =
        options.services.nixbot.packages.nixbot.default.overridePythonAttrs
          (old: {
            patches = (old.patches or [ ]) ++ flakeLib.nixbotPatches;
          });
    };
}
