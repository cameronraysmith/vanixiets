# Matrix Synapse configuration for cinnabar
# ZeroTier-only private access (no federation)
# Caddy reverse proxies to localhost:8008
{ ... }:
{
  flake.modules.nixos."machines/nixos/cinnabar" =
    {
      config,
      pkgs,
      lib,
      ...
    }:
    {
      # PostgreSQL database for Synapse
      services.postgresql = {
        enable = true;
        ensureDatabases = [ "matrix-synapse" ];
        ensureUsers = [
          {
            name = "matrix-synapse";
            ensureDBOwnership = true;
          }
        ];
      };

      # Matrix Synapse homeserver
      services.matrix-synapse = {
        enable = true;
        settings = {
          server_name = "matrix.zt";

          listeners = [
            {
              port = 8008;
              bind_addresses = [
                "::1"
                "127.0.0.1"
              ];
              type = "http";
              tls = false;
              x_forwarded = true;
              resources = [
                {
                  names = [ "client" ];
                  compress = true;
                }
              ];
            }
          ];

          # No federation (ZeroTier-only private instance)
          federation_domain_whitelist = [ ];

          database = {
            name = "psycopg2";
            args = {
              database = "matrix-synapse";
              user = "matrix-synapse";
              host = "/run/postgresql";
              # ensureDatabases creates with system locale (en_US.UTF-8).
              # Synapse requires C locale but NixOS enforces ensureDatabases
              # when ensureDBOwnership is set. accept_unsafe_locale is safe
              # for a private instance where text sort order is irrelevant.
              allow_unsafe_locale = true;
            };
          };
        };

        extraConfigFiles = [
          config.clan.core.vars.generators.synapse-registration-shared-secret.files."shared-secret.yaml".path
        ];
      };

      # Clan vars generators for secrets
      clan.core.vars.generators.synapse-registration-shared-secret = {
        files."shared-secret.yaml" = {
          neededFor = "services";
          owner = "matrix-synapse";
        };
        runtimeInputs = [
          pkgs.coreutils
          pkgs.pwgen
        ];
        script = ''
          SECRET=$(pwgen -s 32 1)
          echo "registration_shared_secret: \"$SECRET\"" > "$out"/shared-secret.yaml
        '';
      };

      clan.core.vars.generators.matrix-password-cameron = {
        files."password".neededFor = "services";
        runtimeInputs = [
          pkgs.coreutils
          pkgs.xkcdpass
        ];
        script = ''
          xkcdpass -n 4 -d - > "$out"/password
        '';
      };

      clan.core.vars.generators.matrix-password-clawd = {
        files."password" = {
          neededFor = "services";
          owner = "clawdbot";
        };
        runtimeInputs = [
          pkgs.coreutils
          pkgs.xkcdpass
        ];
        script = ''
          xkcdpass -n 4 -d - > "$out"/password
        '';
      };

      # Oneshot service to register users after Synapse starts
      systemd.services.matrix-synapse-register-users = {
        description = "Register Matrix Synapse users";
        after = [ "matrix-synapse.service" ];
        requires = [ "matrix-synapse.service" ];
        wantedBy = [ "multi-user.target" ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
        };
        path = [ config.services.matrix-synapse.package ];
        script =
          let
            sharedSecretFile =
              config.clan.core.vars.generators.synapse-registration-shared-secret.files."shared-secret.yaml".path;
            cameronPasswordFile =
              config.clan.core.vars.generators.matrix-password-cameron.files."password".path;
            clawdPasswordFile = config.clan.core.vars.generators.matrix-password-clawd.files."password".path;
          in
          ''
            SHARED_SECRET=$(${lib.getExe' pkgs.gnused "sed"} -n 's/^registration_shared_secret: "\(.*\)"$/\1/p' ${sharedSecretFile})

            register_new_matrix_user \
              --exists-ok \
              --admin \
              --user cameron \
              --password "$(cat ${cameronPasswordFile})" \
              --shared-secret "$SHARED_SECRET" \
              http://localhost:8008

            register_new_matrix_user \
              --exists-ok \
              --no-admin \
              --user clawd \
              --password "$(cat ${clawdPasswordFile})" \
              --shared-secret "$SHARED_SECRET" \
              http://localhost:8008
          '';
      };
    };
}
