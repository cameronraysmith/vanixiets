# Gitea self-hosted git forge for magnetite
#
# Provides clan vars generators for Gitea credentials and configures
# the Gitea service with GitHub OAuth2 authentication, PostgreSQL database,
# and nginx reverse proxy.
# Generators define the credential slots; values are populated via:
#   - gitea-github-oauth: manual `clan vars set` (OAuth client credentials from GitHub)
#   - gitea-admin-password: auto-generated (initial admin account password)
#   - buildbot-gitea-webhook-secret: auto-generated (for buildbot-nix .11 integration)
#   - buildbot-gitea-token: manual `clan vars set` (Gitea API token for buildbot, post-deploy)
{
  config,
  inputs,
  ...
}:
{
  flake.modules.nixos.gitea =
    {
      config,
      pkgs,
      lib,
      ...
    }:
    {
      # GitHub OAuth credentials (populated manually via clan vars set)
      clan.core.vars.generators.gitea-github-oauth = {
        files."client-id" = {
          owner = "gitea";
        };
        files."client-secret" = {
          owner = "gitea";
        };
        script = ''
          echo "Gitea GitHub OAuth: populate via clan vars set" >&2
          exit 1
        '';
      };

      # Admin account password (auto-generated, used for initial account creation)
      clan.core.vars.generators.gitea-admin-password = {
        files."password" = {
          owner = "gitea";
        };
        runtimeInputs = [ pkgs.openssl ];
        script = ''
          openssl rand -hex 24 > $out/password
        '';
      };

      # Buildbot webhook secret for Gitea forge integration (auto-generated, consumed by .11)
      clan.core.vars.generators.buildbot-gitea-webhook-secret = {
        files."secret" = {
          owner = "buildbot";
        };
        runtimeInputs = [ pkgs.openssl ];
        script = ''
          openssl rand -hex 32 > $out/secret
        '';
      };

      # Buildbot Gitea API token (populated manually via clan vars set after Gitea deploy)
      clan.core.vars.generators.buildbot-gitea-token = {
        files."token" = {
          owner = "buildbot";
        };
        script = ''
          echo "buildbot Gitea API token: populate via clan vars set after Gitea is deployed" >&2
          exit 1
        '';
      };

      # Gitea service configuration
      services.gitea = {
        enable = true;

        # PostgreSQL database (shared instance, auto-merged with buildbot and niks3)
        database = {
          type = "postgres";
          host = "/run/postgresql";
          port = 5432;
        };

        # Large file storage
        lfs.enable = true;

        settings = {
          server = {
            HTTP_PORT = 3002;
            DOMAIN = "git.scientistexperience.net";
            ROOT_URL = "https://git.scientistexperience.net";
            LANDING_PAGE = "explore";
          };

          # Actions CI enabled for Gitea Actions runner
          actions.ENABLED = true;

          # Minimal logging
          log.LEVEL = "Error";

          # Registration policy: GitHub OAuth only, no form-based registration
          service = {
            DISABLE_REGISTRATION = false;
            ALLOW_ONLY_EXTERNAL_REGISTRATION = true;
          };

          # OAuth2 client settings (Gitea as OAuth2 consumer via GitHub)
          oauth2_client = {
            ENABLE_AUTO_REGISTRATION = true;
            USERNAME = "nickname";
            ACCOUNT_LINKING = "auto";
          };

          # Disable OpenID (not needed with GitHub OAuth)
          openid = {
            ENABLE_OPENID_SIGNIN = false;
            ENABLE_OPENID_SIGNUP = false;
          };

          # Persistent sessions in PostgreSQL
          session = {
            PROVIDER = "db";
            COOKIE_SECURE = true;
          };

          # Prometheus metrics endpoint
          metrics.ENABLED = true;
        };
      };

      # nginx reverse proxy with ACME TLS
      services.nginx.virtualHosts."git.scientistexperience.net" = {
        forceSSL = true;
        enableACME = true;
        locations."/".extraConfig = ''
          proxy_pass http://localhost:3002;
        '';
      };

      # Post-start: create admin user and GitHub OAuth auth source (idempotent)
      systemd.services.gitea.serviceConfig.ExecStartPost =
        let
          exe = lib.getExe config.services.gitea.package;
          clientIdFile = config.clan.core.vars.generators.gitea-github-oauth.files."client-id".path;
          clientSecretFile = config.clan.core.vars.generators.gitea-github-oauth.files."client-secret".path;
          adminPasswordFile = config.clan.core.vars.generators.gitea-admin-password.files."password".path;
        in
        lib.mkAfter [
          (pkgs.writeShellScript "gitea-setup" ''
            # Wait for Gitea to be ready (up to 30 seconds)
            for i in $(seq 1 30); do
              ${exe} admin auth list 2>/dev/null && break
              sleep 1
            done

            # Create admin user if not exists
            if ! ${exe} admin user list | grep -q 'cameronraysmith'; then
              ${exe} admin user create \
                --username cameronraysmith \
                --email cameron.ray.smith@gmail.com \
                --password "$(cat ${adminPasswordFile})" \
                --admin \
                --must-change-password=false
            fi

            # Create GitHub OAuth auth source if not exists
            if ! ${exe} admin auth list | grep -q 'github'; then
              ${exe} admin auth add-oauth \
                --name github \
                --provider github \
                --key "$(cat ${clientIdFile})" \
                --secret "$(cat ${clientSecretFile})"
            fi
          '')
        ];
    };
}
