# Matrix Synapse configuration for cinnabar
# ZeroTier-only private access (no federation)
# Caddy reverse proxies to localhost:8008
{ pkgs, config, ... }:
{
  flake.modules.nixos."machines/nixos/cinnabar" = {
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
      # UTF8 encoding with C collation for Synapse compatibility
      initialScript = pkgs.writeText "synapse-init.sql" ''
        ALTER DATABASE "matrix-synapse" SET lc_messages TO 'C';
        ALTER DATABASE "matrix-synapse" SET lc_monetary TO 'C';
        ALTER DATABASE "matrix-synapse" SET lc_numeric TO 'C';
        ALTER DATABASE "matrix-synapse" SET lc_time TO 'C';
      '';
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
        echo "registration_shared_secret: \"$SECRET\"" > $out/shared-secret.yaml
      '';
    };

    clan.core.vars.generators.matrix-password-cameron = {
      files."password".neededFor = "services";
      runtimeInputs = [
        pkgs.coreutils
        pkgs.xkcdpass
      ];
      script = ''
        xkcdpass -n 4 -d - > $out/password
      '';
    };

    clan.core.vars.generators.matrix-password-clawd = {
      files."password".neededFor = "services";
      runtimeInputs = [
        pkgs.coreutils
        pkgs.xkcdpass
      ];
      script = ''
        xkcdpass -n 4 -d - > $out/password
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
          # Extract shared secret from YAML file
          SHARED_SECRET=$(${pkgs.gnused}/bin/sed -n 's/^registration_shared_secret: "\(.*\)"$/\1/p' ${sharedSecretFile})

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
