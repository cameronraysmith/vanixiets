# buildbot-nix CI service for magnetite.
#
# Credential generator catalog (slots; values populated as marked):
#   - buildbot-github-app-secret-key: manual `clan vars set` (GitHub App PEM key)
#   - buildbot-github-oauth-secret: manual `clan vars set` (OAuth client secret)
#   - buildbot-github-webhook-secret: auto-generated
#   - buildbot-worker: auto-generated (worker password + workers.json)
#   - buildbot-oauth2-cookie-secret: auto-generated (oauth2-proxy cookie encryption)
#   - buildbot-http-basic-auth-password: auto-generated (oauth2-proxy to buildbot internal auth)
# Gitea-specific credentials live in gitea.nix:
#   - buildbot-gitea-token: manual `clan vars set` (API token with write:repository, write:user)
#   - buildbot-gitea-webhook-secret: auto-generated
# Per-repo effects secrets for github:cameronraysmith/vanixiets are wired in
# modules/effects/vanixiets/secrets.nix (flake module `effects-vanixiets-secrets`).
{
  config,
  inputs,
  ...
}:
{
  flake.modules.nixos.buildbot =
    {
      config,
      pkgs,
      lib,
      ...
    }:
    {
      # GitHub App private key (populated manually via clan vars set)
      clan.core.vars.generators.buildbot-github-app-secret-key = {
        files."key.pem" = {
          owner = "buildbot";
        };
        script = ''
          echo "buildbot GitHub App private key: populate via clan vars set" >&2
          exit 1
        '';
      };

      # GitHub OAuth secret (populated manually via clan vars set)
      clan.core.vars.generators.buildbot-github-oauth-secret = {
        files."secret" = {
          owner = "buildbot";
        };
        script = ''
          echo "buildbot GitHub OAuth secret: populate via clan vars set" >&2
          exit 1
        '';
      };

      clan.core.vars.generators.buildbot-github-webhook-secret = {
        files."secret" = {
          owner = "buildbot";
        };
        runtimeInputs = [ pkgs.openssl ];
        script = ''
          openssl rand -hex 32 > $out/secret
        '';
      };

      # oauth2-proxy cookie encryption secret (auto-generated, must be 16 or 32 chars)
      clan.core.vars.generators.buildbot-oauth2-cookie-secret = {
        files."secret" = {
          owner = "buildbot";
        };
        runtimeInputs = [ pkgs.openssl ];
        script = ''
          openssl rand -base64 48 | tr -dc 'a-zA-Z0-9' | head -c 32 > $out/secret
        '';
      };

      # HTTP basic auth password for oauth2-proxy to buildbot internal communication.
      clan.core.vars.generators.buildbot-http-basic-auth-password = {
        files."secret" = {
          owner = "buildbot";
        };
        runtimeInputs = [ pkgs.openssl ];
        script = ''
          openssl rand -hex 24 > $out/secret
        '';
      };

      # Worker credentials (auto-generated password + workers.json)
      # CX53: 16 logical CPUs (nproc) — cores must match for correct worker count
      clan.core.vars.generators.buildbot-worker = {
        files."password" = {
          owner = "buildbot";
        };
        files."workers.json" = {
          owner = "buildbot";
        };
        runtimeInputs = [
          pkgs.openssl
          pkgs.jq
        ];
        script = ''
          password=$(openssl rand -hex 24)
          echo -n "$password" > $out/password
          jq -n --arg pass "$password" \
            '[{"name": "magnetite", "pass": $pass, "cores": 16}]' > $out/workers.json
        '';
      };

      services.buildbot-nix.master = {
        enable = true;
        domain = "buildbot.scientistexperience.net";
        useHTTPS = true;

        workersFile = config.clan.core.vars.generators.buildbot-worker.files."workers.json".path;

        buildSystems = [ "x86_64-linux" ];

        admins = [ "cameronraysmith" ];

        httpBasicAuthPasswordFile =
          config.clan.core.vars.generators.buildbot-http-basic-auth-password.files."secret".path;

        accessMode.fullyPrivate = {
          backend = "github";
          clientId = "Iv23liFu66NnDcfRGDHs";
          clientSecretFile =
            config.clan.core.vars.generators.buildbot-github-oauth-secret.files."secret".path;
          cookieSecretFile =
            config.clan.core.vars.generators.buildbot-oauth2-cookie-secret.files."secret".path;
        };

        github = {
          enable = true;
          appId = 3305657;
          appSecretKeyFile =
            config.clan.core.vars.generators.buildbot-github-app-secret-key.files."key.pem".path;
          webhookSecretFile =
            config.clan.core.vars.generators.buildbot-github-webhook-secret.files."secret".path;
          topic = "build-with-buildbot";
          userAllowlist = [
            "sciexp"
            "cameronraysmith"
          ];
        };

        gitea = {
          enable = true;
          instanceUrl = "https://git.scientistexperience.net";
          tokenFile = config.clan.core.vars.generators.buildbot-gitea-token.files."token".path;
          webhookSecretFile =
            config.clan.core.vars.generators.buildbot-gitea-webhook-secret.files."secret".path;
          topic = "build-with-buildbot";
        };

        # evalWorkerCount × evalMaxMemorySize = 8 GB peak; headroom for niks3 + PostgreSQL + nginx on 32 GB CX53.
        evalWorkerCount = 4;
        evalMaxMemorySize = 2048;

        # niks3 binary cache integration (push built paths after successful builds)
        # Uses public URL to support future remote workers (e.g. cinnabar)
        niks3 = {
          enable = true;
          serverUrl = "https://niks3.scientistexperience.net";
          authTokenFile = config.clan.core.vars.generators.niks3-api-token.files."token".path;
          package = inputs.niks3.packages.${config.nixpkgs.hostPlatform.system}.niks3;
        };
      };

      # TLS termination via nginx reverse proxy
      services.nginx.virtualHosts.${config.services.buildbot-nix.master.domain} = {
        forceSSL = true;
        enableACME = true;
      };

      # Local worker on magnetite (colocated with master)
      services.buildbot-nix.worker = {
        enable = true;
        workerPasswordFile = config.clan.core.vars.generators.buildbot-worker.files."password".path;
      };

      # Allow buildbot worker connections via ZeroTier (for remote workers)
      networking.firewall.interfaces."zt+" = {
        allowedTCPPorts = [ 9989 ];
      };
    };
}
