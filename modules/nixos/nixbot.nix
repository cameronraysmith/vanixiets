# nixbot CI service for magnetite, serving the fleet's GitHub repositories.
# The buildbot-nix server is still resident on magnetite but no longer serves
# either of them; it keeps only its Gitea repositories.
#
# Credential generator catalog (slots; values populated as marked):
#   - nixbot-github-app-secret-key: manual `clan vars set` (GitHub App PEM key)
#   - nixbot-github-oauth-secret: manual `clan vars set` (OAuth client secret)
#   - nixbot-github-webhook-secret: auto-generated
# Each names nixbot.service in restartUnits because the unit snapshots its
# credentials at start, so a rotation without a restart leaves the running
# service holding the superseded value.
#
# Coexistence constraints (buildbot still runs, serving Gitea repositories):
#   - statusContextPrefix is left at its default "nixbot"; buildbot's contexts
#     are "buildbot/...", so the two verdict namespaces stay distinct.
#   - github.topic is null; its default "build-with-buildbot" is the topic
#     buildbot's repositories carry, and it one-shot-imports on an empty DB.
#   - nginx.enable stays true, so the service listens only on
#     /run/nixbot/web.sock and binds no TCP port (its TCP fallback default
#     8010 is also the nixpkgs buildbot default).
#   - A dedicated GitHub App, not buildbot's (id 3305657, buildbot.nix:129):
#     nixbot needs Checks write and the check_run/check_suite events, which
#     buildbot-nix does not, so sharing would edit a running service's
#     registration. It also needs Pull requests: Read and write, because the
#     browser-evidence effect comments through /api/v1/pr-comment and GitHub
#     answers 403 to that comment with read-only access (nixbot docs/GITHUB.md).
#
# The webhook secret has two sources and they must agree. The application was
# registered through GitHub's App manifest flow, which generated a webhook
# secret of its own; the nixbot-github-webhook-secret generator below
# independently generates a different one. This generator is authoritative, so
# the application's webhook secret must be replaced with its value at
# deployment, or every delivery fails signature validation.
{
  inputs,
  ...
}:
{
  flake.modules.nixos.nixbot =
    {
      config,
      lib,
      options,
      pkgs,
      ...
    }:
    {
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

          # Default is "build-with-buildbot", the topic the incumbent's
          # repositories carry, and it one-shot-imports against an empty DB.
          topic = null;

          # nixbot serves only the repositories named here, and it serves both
          # of the fleet's GitHub repositories: buildbot's own GitHub
          # repoAllowlist is empty (buildbot.nix:149). Entries are forge-local
          # names, without the "github:" prefix that perRepoSecretFiles keys
          # carry.
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
        # flag makes it forceSSL + enableACME. The incumbent aspect writes that
        # vhost override by hand only because buildbot-nix has no such option.
        nginx.enableACME = true;

        database.createLocally = true;

        # Push successful builds to the fleet's binary cache, mirroring
        # buildbot.nix:158-163. Without it the service builds correctly and
        # uploads nothing: the uploader set defaults to the empty list, so no
        # upload is attempted and no signal is emitted anywhere. The public URL
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
      # extra evaluation arguments; scoped here so buildbot-nix is unaffected.
      systemd.services.nixbot.environment.NIX_CONFIG = "allow-import-from-derivation = false";

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
    };
}
