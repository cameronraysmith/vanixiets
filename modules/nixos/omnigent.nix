{ config, ... }:
let
  acp = config.flake.lib.omnigentACP;
  flakeLib = config.flake.lib;
  flakeUsers = config.flake.users;
in
{
  flake.modules.nixos.omnigent =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.services.omnigent;
      stateDirectory = "/var/lib/omnigent";
      configDirectory = pkgs.writeTextDir "config.yaml" (builtins.toJSON { inherit acp; });
      adminList = pkgs.writeText "omnigent-admins" ''
        cameron.ray.smith@gmail.com
      '';
      # The operator's decision in openspec/changes/omnigent-login-grant-lifetime
      # (design D1): unattended workers re-consent every 90 days instead of 30.
      grantMaxLifetimeDays = 90;

      collect = config.services.opentelemetry-collector.enable;
      collectorPipelines = config.services.opentelemetry-collector.settings.service.pipelines;
      expiringRule =
        lib.findFirst (r: r.alert == "OmnigentLoginGrantExpiring")
          (throw "omnigent: fleetAlertRules has no OmnigentLoginGrantExpiring")
          (flakeLib.fleetAlertRules { inherit lib; }).rules;
      expectedHosts = lib.concatMap (p: p.expectedHosts) expiringRule.presence;

      # The columns the collector's role may read: no token hash, code or id.
      grantColumns = [
        "user_id"
        "client_id"
        "status"
        "approved_at"
      ];
      sqlLiteral = text: "'${lib.replaceStrings [ "'" ] [ "''" ] text}'";
      # Each owner's login identity becomes its alias, as omnigent-host-<owner>
      # units do (ADR-003 item 17), so no address becomes a label value.
      ownerCases = lib.mapAttrsToList (
        owner: alias: "WHEN ${sqlLiteral flakeUsers.${owner}.meta.email} THEN ${sqlLiteral alias}"
      ) flakeLib.otelCollectorSchema.ownerAliases;
      # Earliest expiry per owner over redeemed (status 4,
      # omnigent/db/enum_codecs.py:88-94) CLI login grants, the refusal at
      # omnigent/server/routes/device_auth.py:522-525 in 0.22.0: a superseded
      # grant counts until the server purges it, so the series fails toward
      # alerting (design D3).
      grantExpirySql = lib.concatStringsSep " " [
        "SELECT CASE user_id ${lib.concatStringsSep " " ownerCases} ELSE 'unaliased' END AS omnigent_owner,"
        "min(approved_at)::bigint + ${toString (grantMaxLifetimeDays * 86400)} AS expires_at"
        "FROM device_grants"
        "WHERE client_id = 'omnigent-cli' AND status = 4 AND approved_at IS NOT NULL"
        "GROUP BY 1"
      ];
    in
    {
      options.services.omnigent = {
        enable = lib.mkEnableOption "the Omnigent server";
        package = lib.mkPackageOption pkgs "omnigent" { };
        domain = lib.mkOption {
          type = lib.types.str;
          description = "Public hostname used for HTTPS and the OIDC callback.";
        };
        port = lib.mkOption {
          type = lib.types.port;
          default = 6767;
          description = "Loopback HTTP port served behind nginx.";
        };
        environmentFiles = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
          description = "Runtime environment files, including the OIDC client secret carrier.";
        };
        cookieSecretGenerator = lib.mkOption {
          type = lib.types.str;
          default = "omnigent-cookie-secret";
          description = "Clan vars generator name for the server cookie secret.";
        };
        oidc = {
          issuer = lib.mkOption {
            type = lib.types.str;
            description = "OIDC issuer URL for the confidential server client.";
          };
          clientId = lib.mkOption {
            type = lib.types.str;
            description = "Confidential OIDC client identifier.";
          };
          allowedDomains = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = [ ];
            description = "Optional email-domain restriction; an empty list leaves admission to the IdP.";
          };
        };
      };

      config = lib.mkIf cfg.enable {
        assertions = lib.optionals collect [
          {
            assertion = builtins.elem config.networking.hostName expectedHosts;
            message = "omnigent: ${config.networking.hostName} collects its login grants' expiry, so OmnigentLoginGrantExpiring's presence in modules/nixos/fleet-alert/rules.nix must expect it; it expects ${builtins.toJSON expectedHosts}.";
          }
          {
            assertion = (collectorPipelines."metrics/host".exporters or [ ]) != [ ];
            message = "omnigent: the login grants' expiry joins the collector's metrics/host pipeline, which on ${config.networking.hostName} has no exporter; the host needs the otel-collector agent role.";
          }
        ];

        users.users.omnigent = {
          isSystemUser = true;
          group = "omnigent";
          home = stateDirectory;
        };
        users.groups.omnigent = { };

        services.postgresql = {
          enable = true;
          ensureDatabases = [ "omnigent" ];
          ensureUsers = [
            {
              name = "omnigent";
              ensureDBOwnership = true;
            }
          ]
          # Peer-authenticated as the collector's DynamicUser, as
          # devloop-collection's readers are; omnigent-pg-grants grants it
          # grantColumns and nothing else.
          ++ lib.optional collect { name = "opentelemetry-collector"; };
        };

        # omnigent.service creates device_grants through its own migrations, so
        # wait up to 300 s for the columns, then grant, once per boot. A grant
        # lost to a later migration empties the series, which
        # RuleSignalMissing reports (design D4).
        systemd.services.omnigent-pg-grants = lib.mkIf collect {
          description = "Column grant on omnigent's device_grants for the collector";
          after = [
            "postgresql.target"
            "omnigent.service"
          ];
          wantedBy = [ "multi-user.target" ];
          path = [ config.services.postgresql.package ];
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
            User = "postgres";
            Group = "postgres";
          };
          script = ''
            deadline=$((SECONDS + 300))
            until [ "$(psql -XAtq -d omnigent -c "SELECT count(*) FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'device_grants' AND column_name IN (${
              lib.concatMapStringsSep ", " sqlLiteral grantColumns
            })" 2>/dev/null)" = ${toString (builtins.length grantColumns)} ]; do
              if [ "$SECONDS" -ge "$deadline" ]; then
                echo "omnigent-pg-grants: after 300 s omnigent's device_grants still lacks one of ${lib.concatStringsSep ", " grantColumns}" >&2
                exit 1
              fi
              sleep 5
            done
            psql -XAtq -d omnigent -v ON_ERROR_STOP=1 -c ${lib.escapeShellArg ''GRANT SELECT (${lib.concatMapStringsSep ", " (c: ''"${c}"'') grantColumns}) ON "device_grants" TO "opentelemetry-collector";''}
          '';
        };

        services.opentelemetry-collector.settings = lib.mkIf collect {
          receivers."sqlquery/omnigent-grants" = {
            driver = "postgres";
            datasource = "host=/run/postgresql dbname=omnigent user=opentelemetry-collector sslmode=disable";
            collection_interval = "60s";
            queries = [
              {
                sql = grantExpirySql;
                metrics = [
                  {
                    metric_name = "omnigent_login_grant_expiry_timestamp_seconds";
                    value_column = "expires_at";
                    attribute_columns = [ "omnigent_owner" ];
                    data_type = "gauge";
                    value_type = "int";
                  }
                ];
              }
            ];
          };
          # The pipeline's resource/agent stamps host.name and the fleet database.
          service.pipelines."metrics/host".receivers = [ "sqlquery/omnigent-grants" ];
        };

        clan.core.vars.generators.${cfg.cookieSecretGenerator} = {
          files.env = {
            secret = true;
            owner = "omnigent";
            group = "omnigent";
            mode = "0400";
            restartUnits = [ "omnigent.service" ];
          };
          runtimeInputs = [ pkgs.openssl ];
          script = ''
            secret="$(openssl rand -hex 32)"
            printf 'OMNIGENT_OIDC_COOKIE_SECRET=%s\n' "$secret" > "$out/env"
          '';
        };

        systemd.services.omnigent = {
          description = "Omnigent server";
          path = [ pkgs.lsof ];
          wantedBy = [ "multi-user.target" ];
          after = [
            "network-online.target"
            "postgresql.target"
          ];
          wants = [ "network-online.target" ];
          requires = [ "postgresql.target" ];
          environment = {
            HOME = stateDirectory;
            OMNIGENT_DATA_DIR = stateDirectory;
            OMNIGENT_CONFIG_HOME = configDirectory;
            OMNIGENT_AUTH_ENABLED = "1";
            OMNIGENT_AUTH_PROVIDER = "oidc";
            OMNIGENT_DOMAIN = cfg.domain;
            OMNIGENT_OIDC_ISSUER = cfg.oidc.issuer;
            OMNIGENT_OIDC_CLIENT_ID = cfg.oidc.clientId;
            OMNIGENT_ADMIN_LIST_PATH = adminList;
            # CLI-login tickets are process-local in Omnigent v0.12.0.
            WEB_CONCURRENCY = "1";
            # Read once at mount (device_auth.py:123-156, :408 in 0.22.0); the
            # default 30 days stopped every worker on 2026-10-15 (design D1).
            OMNIGENT_GRANT_MAX_LIFETIME_DAYS = toString grantMaxLifetimeDays;
          }
          // lib.optionalAttrs (cfg.oidc.allowedDomains != [ ]) {
            OMNIGENT_OIDC_ALLOWED_DOMAINS = lib.concatStringsSep "," cfg.oidc.allowedDomains;
          };
          serviceConfig = {
            ExecStart = lib.escapeShellArgs [
              (lib.getExe cfg.package)
              "server"
              "--host"
              "127.0.0.1"
              "--port"
              (toString cfg.port)
              "--no-open"
              "--database-uri"
              "postgresql+psycopg:///omnigent?host=/run/postgresql"
              "--artifact-location"
              "${stateDirectory}/artifacts"
            ];
            User = "omnigent";
            Group = "omnigent";
            StateDirectory = "omnigent";
            StateDirectoryMode = "0700";
            WorkingDirectory = stateDirectory;
            EnvironmentFile = cfg.environmentFiles ++ [
              config.clan.core.vars.generators.${cfg.cookieSecretGenerator}.files.env.path
            ];
            Restart = "on-failure";
            RestartSec = 5;
            MemoryHigh = "2G";
            MemoryMax = "3G";
            UMask = "0077";
            NoNewPrivileges = true;
            PrivateTmp = true;
            ProtectSystem = "strict";
            ProtectHome = true;
            ProtectKernelTunables = true;
            ProtectKernelModules = true;
            ProtectKernelLogs = true;
            ProtectControlGroups = true;
            RestrictSUIDSGID = true;
            RestrictAddressFamilies = [
              "AF_UNIX"
              "AF_INET"
              "AF_INET6"
            ];
          };
        };

        services.nginx = {
          enable = true;
          virtualHosts.${cfg.domain} = {
            enableACME = true;
            forceSSL = true;
            locations."/" = {
              proxyPass = "http://127.0.0.1:${toString cfg.port}";
              proxyWebsockets = true;
              extraConfig = ''
                proxy_read_timeout 1d;
                proxy_send_timeout 1d;
                proxy_buffering off;
              '';
            };
            # Omnigent v0.19.0 deploy guidance: a cli-poll query can carry the ticket
            # and PKCE verifier that together redeem an approved login.
            locations."= /auth/cli-poll" = {
              proxyPass = "http://127.0.0.1:${toString cfg.port}";
              extraConfig = ''
                access_log off;
              '';
            };
          };
        };
      };
    };
}
