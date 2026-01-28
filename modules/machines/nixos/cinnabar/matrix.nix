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

          federation_domain_whitelist = [ ];

          database = {
            name = "psycopg2";
            # ensureDatabases creates with system locale (en_US.UTF-8).
            # Synapse requires C locale but NixOS enforces ensureDatabases
            # when ensureDBOwnership is set. allow_unsafe_locale is safe
            # for a private instance where text sort order is irrelevant.
            allow_unsafe_locale = true;
            args = {
              database = "matrix-synapse";
              user = "matrix-synapse";
              host = "/run/postgresql";
            };
          };
        };

        extraConfigFiles = [
          config.clan.core.vars.generators.synapse-registration-shared-secret.files."shared-secret.yaml".path
        ];
      };

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
          owner = config.users.users.cameron.name;
        };
        runtimeInputs = [
          pkgs.coreutils
          pkgs.xkcdpass
        ];
        script = ''
          xkcdpass -n 4 -d - > "$out"/password
        '';
      };

      # Register Matrix users on first boot
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
            adminUser = config.users.users.cameron.name;
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
              --user ${adminUser} \
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
