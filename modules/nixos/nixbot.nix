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
#     registration.
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

        buildSystems = [ "x86_64-linux" ];

        # 6 evaluation workers on magnetite, below both nixbot's own 16-core
        # auto-sizing heuristic of 8 and the 20 used by clan-infra, the upstream
        # reference deployment, because the memory cap has to stay enforceable.
        # nixbot evaluates inside a cgroup capped at evalMaxMemorySize x
        # (workers + 1), and exceeding that cap fails the pull request
        # permanently with no retry, unlike an attribute build. A cap above the
        # memory magnetite can supply cannot fire before magnetite itself is
        # exhausted, so the count is bounded by arithmetic rather than by its 16
        # cores: at the 2048 MiB per worker chosen just below, 6 caps the
        # evaluation tree at 14 GiB, where 8 would imply 18 GiB and 20 would
        # imply 43 GiB. magnetite has 30.6 GiB of RAM, and 17 GiB of it were
        # free when nixbot was deployed there in August 2026, measured with
        # kanidm, postgres, nginx and buildbot-nix already resident. To revise
        # the count, read MemAvailable from /proc/meminfo on magnetite under
        # that same resident set and keep evalMaxMemorySize x (workers + 1)
        # below it.
        #
        # evalWorkerCount is nix-eval-jobs' --workers, so it shortens a single
        # evaluation instead of overlapping several. Overlapping would need
        # nixbot's eval_concurrency setting, which nixbot's NixOS module does
        # not expose, so evaluations stay serial across pull requests and each
        # one's latency adds to the total. The measurements behind 6 are in
        # cameronraysmith/vanixiets PR 2869.
        evalWorkerCount = 6;
        evalMaxMemorySize = 2048;

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
    };
}
