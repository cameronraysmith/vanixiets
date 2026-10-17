# GreptimeDB telemetry store (design D3 to D7).
#
# Site-neutral and free of clan vars, so the runtime tests import it with
# their own credentials. The host supplies LoadCredential (`users` for the
# store, `admin-password` for the schema job), the R2 EnvironmentFile, the
# [storage] object-store stanza and `databases`; without a stanza the store
# uses GreptimeDB's local `File` storage under data_home. The memory envelope,
# listeners, worker pools and usage reporting are fixed here, and R7.1
# (modules/checks/greptimedb-envelope.nix) asserts them on magnetite.
{ config, ... }:
let
  flakeLib = config.flake.lib;
in
{
  flake.modules.nixos.greptimedb =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.services.greptimedb;
      settingsFormat = pkgs.formats.toml { };
      configFile = settingsFormat.generate "greptimedb.toml" cfg.settings;

      # MemoryHigh as systemd parses it: a G suffix is a power of 1024.
      memoryHigh = config.systemd.services.greptimedb.serviceConfig.MemoryHigh;
      memoryHighGiB = builtins.match "([0-9]+)G" memoryHigh;

      envelope = flakeLib.greptimedbEnvelope pkgs {
        url = "http://${cfg.settings.http.addr}";
        databases = lib.attrNames cfg.databases;
        unit = "greptimedb.service";
        loadedUsersHashFile = "/run/greptimedb/loaded-users.sha256";
        zfsPackage = config.boot.zfs.package;
        systemdPackage = config.systemd.package;
      };

      httpUrl = "http://${cfg.settings.http.addr}";

      # Static-user hardening following modules/nixos/omnigent.nix:147-161.
      hardening = {
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

      # Records which users file the running store loaded, for R7.4: the
      # envelope compares it with the generator's public users-sha256. A
      # sha256 of 256-bit hex passwords is not reversible, so neither hash
      # leaks anything usable. Written via rename so a restart with a
      # preserved runtime directory never writes into a 0444 file.
      recordLoadedUsers = pkgs.writeShellApplication {
        name = "greptimedb-record-loaded-users";
        runtimeInputs = [ pkgs.coreutils ];
        text = ''
          sha256sum < "$CREDENTIALS_DIRECTORY/users" | cut -d ' ' -f 1 > /run/greptimedb/loaded-users.sha256.tmp
          chmod 0444 /run/greptimedb/loaded-users.sha256.tmp
          mv -f /run/greptimedb/loaded-users.sha256.tmp /run/greptimedb/loaded-users.sha256
        '';
      };

      # CREATE ... IF NOT EXISTS is a no-op on an existing database, so the
      # ALTER is what applies a changed TTL (design F1).
      schemaStatements = lib.concatMap (database: [
        "CREATE DATABASE IF NOT EXISTS ${database}"
        "ALTER DATABASE ${database} SET 'ttl'='${cfg.databases.${database}}'"
      ]) (lib.attrNames cfg.databases);

      # The store has no readiness notification, so the job polls /health
      # (design F7). The password reaches curl on stdin through the printf
      # builtin, never on a command line.
      schema = pkgs.writeShellApplication {
        name = "greptimedb-schema";
        runtimeInputs = [
          pkgs.coreutils
          pkgs.curl
        ];
        text = ''
          password="$(cat "$CREDENTIALS_DIRECTORY/admin-password")"

          attempt=0
          until curl --silent --fail --output /dev/null ${httpUrl}/health; do
            attempt=$((attempt + 1))
            if [ "$attempt" -ge 60 ]; then
              echo "greptimedb-schema: ${httpUrl}/health did not answer within 120 s" >&2
              exit 1
            fi
            sleep 2
          done

          sql() {
            printf 'user = "admin:%s"\n' "$password" |
              curl --silent --show-error --fail-with-body --config - \
                --data-urlencode "sql=$1" ${httpUrl}/v1/sql
            echo
          }

          ${lib.concatMapStringsSep "\n" (statement: "sql ${lib.escapeShellArg statement}") schemaStatements}
        '';
      };
    in
    {
      options.services.greptimedb = {
        enable = lib.mkEnableOption "the GreptimeDB telemetry store";
        package = lib.mkPackageOption pkgs "greptimedb-bin" { };
        settings = lib.mkOption {
          inherit (settingsFormat) type;
          default = { };
          description = "GreptimeDB standalone configuration, rendered to TOML (upstream config/standalone.example.toml).";
        };
        databases = lib.mkOption {
          type = lib.types.attrsOf lib.types.str;
          default = { };
          example = {
            fleet = "30d";
          };
          description = "Databases the schema job creates, each mapped to the TTL it sets with ALTER DATABASE.";
        };
      };

      config = lib.mkIf cfg.enable {
        assertions = [
          {
            assertion = lib.hasPrefix "127." cfg.settings.grpc.bind_addr;
            message = "services.greptimedb.settings.grpc.bind_addr must be in 127.0.0.0/8: GreptimeDB 1.2.1 has no switch to disable gRPC (design D4).";
          }
          {
            assertion = memoryHighGiB != null;
            message = "services.greptimedb: greptimedb.service MemoryHigh must be whole gibibytes (\"<n>G\"); greptimedb-envelope derives its memory.peak threshold from it";
          }
        ];

        users.users.greptimedb = {
          isSystemUser = true;
          group = "greptimedb";
        };
        users.groups.greptimedb = { };

        services.greptimedb.settings = {
          enable_telemetry = false;
          user_provider = "static_user_provider:file:/run/credentials/greptimedb.service/users";
          max_in_flight_write_bytes = "128MB";
          write_bytes_exhausted_policy = "wait";
          max_concurrent_queries = 8;
          runtime = {
            global_rt_size = 4;
            compact_rt_size = 2;
          };
          http = {
            addr = "127.0.0.1:4000";
            enable_api_server = false;
          };
          grpc.bind_addr = "127.0.0.1:4001";
          mysql.enable = false;
          postgres.enable = false;
          opentsdb.enable = false;
          influxdb.enable = false;
          prom_store.enable = false;
          jaeger.enable = false;
          query.memory_pool_size = "512MB";
          storage.data_home = "/var/lib/greptimedb";
          region_engine = [
            {
              mito = {
                global_write_buffer_size = "256MB";
                scan_memory_limit = "512MB";
                scan_memory_on_exhausted = "fail";
                experimental_compaction_memory_limit = "256MB";
                max_background_compactions = 2;
                max_background_flushes = 2;
                page_cache_size = "256MB";
                sst_meta_cache_size = "64MB";
                vector_cache_size = "32MB";
                selector_result_cache_size = "32MB";
                range_result_cache_size = "32MB";
                prefilter_result_cache_size = "32MB";
                # ADR-007: the write cache is capped at 4 GiB on the 16G dataset.
                write_cache_size = "4GiB";
              };
            }
          ];
          # Journal only.
          logging.dir = "";
          # ADR-007: no event recorder, so no unrequested 90-day table.
          event_recorder.event_types = [ ];
        };

        systemd.services.greptimedb = {
          description = "GreptimeDB telemetry store";
          wantedBy = [ "multi-user.target" ];
          after = [ "network.target" ];
          startLimitIntervalSec = 0;
          # A missing dataset fails the unit instead of filling the root dataset.
          unitConfig.RequiresMountsFor = [ "/var/lib/greptimedb" ];
          serviceConfig = hardening // {
            ExecStartPre = lib.getExe recordLoadedUsers;
            ExecStart = "${lib.getExe cfg.package} standalone start --config-file ${configFile}";
            User = "greptimedb";
            Group = "greptimedb";
            StateDirectory = "greptimedb";
            StateDirectoryMode = "0700";
            RuntimeDirectory = "greptimedb";
            RuntimeDirectoryMode = "0755";
            WorkingDirectory = "/var/lib/greptimedb";
            Restart = "on-failure";
            RestartSec = 30;
            # Kill order under host OOM: evaluator 900, store 500, collector 300.
            MemoryHigh = "3G";
            MemoryMax = "4G";
            MemorySwapMax = "0";
            OOMScoreAdjust = 500;
            CPUWeight = 20;
          };
        };

        systemd.services.greptimedb-schema = {
          description = "GreptimeDB databases and retention";
          wantedBy = [ "multi-user.target" ];
          requires = [ "greptimedb.service" ];
          after = [ "greptimedb.service" ];
          partOf = [ "greptimedb.service" ];
          serviceConfig = hardening // {
            Type = "oneshot";
            RemainAfterExit = true;
            ExecStart = lib.getExe schema;
            User = "greptimedb";
            Group = "greptimedb";
          };
        };

        # Runtime envelope (design D12), run hourly as the regulator account.
        # The host supplies LoadCredential=regulator-password and the
        # GREPTIMEDB_ENVELOPE_{DATASET,QUOTA_BYTES,RESERVATION_BYTES,USERS_SHA256_FILE}
        # environment, so this module stays free of clan vars. /dev/zfs stays
        # visible (no PrivateDevices) for `zfs get`, and systemd-journal lets
        # the run read the unit's OOM records.
        systemd.services.greptimedb-envelope = {
          description = "GreptimeDB runtime envelope";
          after = [ "greptimedb.service" ];
          environment = {
            GREPTIMEDB_ENVELOPE_MEMORY_PEAK_MAX_BYTES = toString (
              lib.toInt (builtins.head memoryHighGiB) * 1024 * 1024 * 1024
            );
            GREPTIMEDB_ENVELOPE_DISK_USED_MAX_PERCENT = "80";
            GREPTIMEDB_ENVELOPE_SST_MAX_BYTES = toString (50 * 1024 * 1024 * 1024);
          };
          serviceConfig = {
            Type = "oneshot";
            ExecStart = lib.getExe envelope;
            DynamicUser = true;
            SupplementaryGroups = [ "systemd-journal" ];
            StateDirectory = "greptimedb-envelope";
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

        systemd.timers.greptimedb-envelope = {
          description = "Hourly GreptimeDB runtime envelope";
          wantedBy = [ "timers.target" ];
          timerConfig = {
            OnCalendar = "hourly";
            Persistent = true;
            RandomizedDelaySec = "5m";
          };
        };
      };
    };
}
