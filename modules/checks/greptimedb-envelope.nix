# Evaluation-time regulator for the telemetry store on magnetite (design D11):
# R7.1, R1.1 (amended), R1.4, R6.4's storage clause, R8.2, the PromQL read
# path (charter v13) and the users-file check.
#
# Every clause reads magnetite's evaluated configuration, so it judges what
# deploys rather than a transcription of it. Mutants are pure functions over
# the extracted `view`, never re-evaluations of the host, so each costs a few
# attribute updates instead of a NixOS fixpoint. The check asserts that the
# real view fails no clause and that every mutant fails the clause it targets,
# following modules/checks/omnigent-environment.nix:98-118. The users-file
# clause runs the greptimedb-users generator in the build sandbox, because the
# store skips a malformed users line silently (design F2).
{ self, lib, ... }:
{
  perSystem =
    { pkgs, system, ... }:
    let
      magnetite = self.nixosConfigurations.magnetite.config;
      store = magnetite.services.greptimedb;
      usersGenerator = magnetite.clan.core.vars.generators.greptimedb-users;

      # R8.2: magnetite's worker accounts are its omnigent workers
      # (ADR-008: "magnetite's two worker accounts").
      workerUsers = map (worker: worker.user) (
        lib.attrValues (lib.filterAttrs (_: worker: worker.enable) magnetite.services.omnigent-host.workers)
      );

      # R8.2 credential-holder clause, as data: for each greptimedb-users
      # secret, the units (systemd.services attribute names) allowed to load
      # it; an empty list means no unit may.
      credentialHolders = {
        users = [ "greptimedb" ];
        admin-password = [ "greptimedb-schema" ];
        collector-password = [ "opentelemetry-collector" ];
        perses-password = [ ];
        regulator-password = [ "greptimedb-envelope" ];
      };

      # Runtime regulators treat absent evidence as failure (5.2; F3). The
      # envelope's every query goes through self.lib.greptimedbSql, so this
      # builds that function the way modules/nixos/greptimedb.nix does and
      # runs it against recorded GreptimeDB v1.2.1 /v1/sql answers served by a
      # loopback stub (curl reaches it through http_proxy, as in
      # omnigraph-readiness-rehearsal.nix). Shapes: GreptimedbV1Response and
      # HttpRecordsOutput (src/servers/src/http/result/greptime_result_v1.rs:30-39,
      # src/servers/src/http.rs:331-400), ErrorResponse
      # (src/servers/src/http/result/error_result.rs:25-30); TableNotFound is
      # code 4001 answered as HTTP 400 (src/servers/src/error.rs:933-957), with
      # the message tests/cases/standalone/common/catalog/schema.result:135
      # records. The renamed-table row is the mutant: the regulator queries a
      # table that does not exist and must fail.
      sqlHelper = self.lib.greptimedbSql pkgs {
        url = "http://greptimedb.rehearsal.invalid:4000";
        user = "regulator";
      };
      regionColumns = [
        {
          name = "region_id";
          data_type = "UInt64";
        }
        {
          name = "sst_size";
          data_type = "UInt64";
        }
      ];
      records = rows: {
        output = [
          {
            records = {
              schema.column_schemas = regionColumns;
              inherit rows;
              total_rows = builtins.length rows;
            };
          }
        ];
        execution_time_ms = 2;
      };
      regionQuery = "SELECT region_id, sst_size FROM information_schema.region_statistics";
      renamedRegionQuery = "SELECT region_id, sst_size FROM information_schema.region_statistic";

      sqlStub = pkgs.writeText "greptimedb-sql-stub.py" ''
        import base64, sys
        from http.server import BaseHTTPRequestHandler, HTTPServer
        from urllib.parse import parse_qs, urlsplit

        port_path, log_path, status, reply = sys.argv[1], sys.argv[2], int(sys.argv[3]), sys.argv[4]

        class Handler(BaseHTTPRequestHandler):
            def answer(self):
                length = int(self.headers.get("Content-Length", "0"))
                form = parse_qs(self.rfile.read(length).decode())
                auth = self.headers.get("Authorization", "")
                user = "-"
                if auth.startswith("Basic "):
                    user = base64.b64decode(auth[6:]).decode().split(":", 1)[0]
                with open(log_path, "a") as log:
                    log.write(" ".join([self.command, urlsplit(self.path).path, user, form.get("sql", ["-"])[0]]) + "\n")
                data = reply.encode()
                self.send_response(status)
                self.send_header("Content-Type", "application/json")
                self.send_header("Content-Length", str(len(data)))
                self.end_headers()
                self.wfile.write(data)

            do_GET = answer
            do_POST = answer

            def log_message(self, *args):
                pass

        server = HTTPServer(("127.0.0.1", 0), Handler)
        with open(port_path, "w") as f:
            f.write(str(server.server_port))
        server.serve_forever()
      '';

      sqlRow =
        {
          name,
          sql,
          httpStatus,
          reply,
          exit,
          expect,
        }:
        ''
          echo "--- ${name}"
          rm -f "$TMPDIR/port" "$TMPDIR/requests" "$TMPDIR/output"
          touch "$TMPDIR/requests"
          python3 ${sqlStub} "$TMPDIR/port" "$TMPDIR/requests" ${toString httpStatus} ${lib.escapeShellArg (builtins.toJSON reply)} &
          stub_pid=$!
          for _ in $(seq 100); do [ -s "$TMPDIR/port" ] && break; sleep 0.1; done
          [ -s "$TMPDIR/port" ] || fail "sql stub did not start"
          code=0
          env -u no_proxy -u NO_PROXY -u HTTP_PROXY \
            CREDENTIALS_DIRECTORY="$TMPDIR/credentials" \
            http_proxy="http://127.0.0.1:$(cat "$TMPDIR/port")" \
            ${lib.getExe sqlHelper} ${lib.escapeShellArg sql} > "$TMPDIR/output" 2>&1 || code=$?
          kill "$stub_pid"
          wait "$stub_pid" || true
          stub_pid=
          cat "$TMPDIR/output"
          [ "$code" = ${toString exit} ] || fail "${name}: exit status $code, expected ${toString exit}"
          ${lib.concatMapStrings (line: ''
            grep -qF -- ${lib.escapeShellArg line} "$TMPDIR/output" \
              || fail ${lib.escapeShellArg "${name}: output lacks: ${line}"}
          '') expect}
          [ "$(cat "$TMPDIR/requests")" = ${lib.escapeShellArg "POST /v1/sql regulator ${sql}"} ] \
            || fail "${name}: stub saw: $(cat "$TMPDIR/requests")"
        '';

      sqlRows = [
        {
          name = "a records result with rows passes and prints them as TSV";
          sql = regionQuery;
          httpStatus = 200;
          reply = records [
            [
              4398046511104
              1048576
            ]
          ];
          exit = 0;
          expect = [ "4398046511104\t1048576" ];
        }
        {
          name = "an empty records result fails";
          sql = regionQuery;
          httpStatus = 200;
          reply = records [ ];
          exit = 1;
          expect = [ "greptimedb-sql: empty result: ${regionQuery}" ];
        }
        {
          name = "a renamed table fails on TableNotFound";
          sql = renamedRegionQuery;
          httpStatus = 400;
          reply = {
            code = 4001;
            error = "Failed to plan SQL: Table not found: greptime.information_schema.region_statistic";
            execution_time_ms = 0;
          };
          exit = 1;
          expect = [ "greptimedb-sql: HTTP 400: 4001 Failed to plan SQL: Table not found" ];
        }
      ];

      greptimedbSqlRehearsal =
        pkgs.runCommand "greptimedb-sql-rehearsal"
          {
            nativeBuildInputs = [
              pkgs.coreutils
              pkgs.gnugrep
              pkgs.python3
            ];
            meta.description = "behavioural check: the envelope's SQL helper fails on an empty result and on a missing table";
          }
          ''
            set -euo pipefail
            stub_pid=
            trap '[ -z "$stub_pid" ] || kill "$stub_pid" 2>/dev/null || true' EXIT
            fail() {
              echo "FAIL: $*" >&2
              exit 1
            }
            mkdir "$TMPDIR/credentials"
            printf '%s' 00112233445566778899aabbccddeeff > "$TMPDIR/credentials/regulator-password"

            ${lib.concatMapStrings sqlRow sqlRows}
            touch "$out"
          '';

      # LoadCredential entries are "<id>:<source path>". Holders are matched on
      # the source path, because each unit chooses its own id, and an unrelated
      # unit (kanidm-site-branding) already loads an "admin-password" id.
      credentialSource = entry: lib.concatStringsSep ":" (lib.drop 1 (lib.splitString ":" entry));
      holdersOf =
        loadCredentials: path:
        lib.naturalSort (
          lib.attrNames (
            lib.filterAttrs (
              _: entries: lib.any (entry: credentialSource entry == path) entries
            ) loadCredentials
          )
        );

      # ADR-007 Decision: every memory knob, set to a fixed size so the store
      # does not size itself from magnetite's RAM.
      memoryKnobs = {
        top = {
          max_in_flight_write_bytes = "128MB";
          write_bytes_exhausted_policy = "wait";
          max_concurrent_queries = 8;
        };
        query = {
          memory_pool_size = "512MB";
        };
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
        };
      };

      mitoOf =
        settings:
        (lib.findFirst (engine: engine ? mito) { mito = { }; } (settings.region_engine or [ ])).mito;
      knobsOf = settings: {
        top = lib.intersectAttrs memoryKnobs.top settings;
        query = lib.intersectAttrs memoryKnobs.query (settings.query or { });
        mito = lib.intersectAttrs memoryKnobs.mito (mitoOf settings);
      };
      isLoopback = addr: lib.hasPrefix "127." addr;

      # disko declares the dataset for installation only; the boot oneshots
      # enforce greptimedbDataset on the live host. The clause keeps the two
      # from drifting apart.
      oneshotCommand = unit: magnetite.systemd.services.${unit}.serviceConfig.ExecStart;

      view = {
        inherit (store) package settings;
        unit = magnetite.systemd.services.greptimedb.serviceConfig;
        usersFiles = lib.filterAttrs (_: file: file.secret) usersGenerator.files;
        loadCredentials = lib.mapAttrs (
          _: service: lib.toList (service.serviceConfig.LoadCredential or [ ])
        ) magnetite.systemd.services;
        disko = magnetite.disko.devices.zpool.zroot.datasets."root/greptimedb";
        zfsOneshots = {
          quota = oneshotCommand "zfs-set-root-greptimedb-quota";
          reservation = oneshotCommand "zfs-set-root-greptimedb-reservation";
          noautosnap = oneshotCommand "zfs-assert-root-greptimedb-noautosnap";
        };
      };

      clauses =
        v:
        let
          s = v.settings;
          storage = s.storage or { };
        in
        {
          # R7.1 (A7:135)
          memoryMax = (v.unit.MemoryMax or null) == "4G";
          memoryHigh = (v.unit.MemoryHigh or null) == "3G";
          memorySwapMax = toString (v.unit.MemorySwapMax or "unset") == "0";
          oomScoreAdjust = (v.unit.OOMScoreAdjust or null) == 500;
          memoryKnobs = knobsOf s == memoryKnobs;
          listenersLoopback =
            isLoopback (s.http.addr or "")
            && isLoopback (s.grpc.bind_addr or "")
            && (!(s.http.enable_api_server or false) || isLoopback (s.http.api_server_addr or ""));
          protocolsDisabled = lib.all (protocol: (s.${protocol}.enable or true) == false) [
            "mysql"
            "postgres"
            "opentsdb"
            "influxdb"
            "jaeger"
          ];
          userProvider =
            (s.user_provider or null) == "static_user_provider:file:/run/credentials/greptimedb.service/users";
          # Also R1.4 (A1:103-104); GreptimeDB reports usage when the key is absent.
          telemetryDisabled = (s.enable_telemetry or true) == false;
          usersRestartUnits = builtins.elem "greptimedb.service" (v.usersFiles.users.restartUnits or [ ]);

          # R1.1, amended: a stable release that declares the embedded dashboard.
          stableRelease = builtins.match "[0-9]+\\.[0-9]+\\.[0-9]+" (v.package.version or "") != null;
          embedsDashboard = (v.package.passthru.embedsDashboard or false) == true;

          # R6.4, storage clause (A6:138)
          storageDisableEc2Metadata = (storage.disable_ec2_metadata or false) == true;
          storageRegion = (storage.region or null) == "auto";
          storagePathStyle = (storage.enable_virtual_host_style or true) == false;
          storageBucket = (storage.bucket or null) == "sciexp";
          storageRoot = (storage.root or "") == "projects/vanixiets/observability/store/";

          # R8.2 (A8:139)
          usersFilesNonWorker =
            workerUsers != [ ]
            && v.usersFiles ? users
            && lib.all (file: file.mode == "0400" && !(builtins.elem file.owner workerUsers)) (
              lib.attrValues v.usersFiles
            );
          httpLoopback = isLoopback (s.http.addr or "");

          # Disk envelope (ADR-007 E7.3): disko's install-time declaration
          # equals what the boot oneshots enforce, and mounts at data_home.
          diskoMatchesDataset =
            lib.hasSuffix "/bin/zfs set quota=${v.disko.options.quota or "unset"} zroot/root/greptimedb" v.zfsOneshots.quota
            && lib.hasSuffix "/bin/zfs set reservation=${v.disko.options.reservation or "unset"} zroot/root/greptimedb" v.zfsOneshots.reservation
            && lib.hasSuffix "/bin/zfs set com.sun:auto-snapshot=${v.disko.options."com.sun:auto-snapshot" or "unset"} zroot/root/greptimedb" v.zfsOneshots.noautosnap
            && (v.disko.options.mountpoint or null) == (s.storage.data_home or "")
            && v.disko.mountpoint == (s.storage.data_home or "");
          credentialHolders =
            lib.mapAttrs (
              name: _: holdersOf v.loadCredentials usersGenerator.files.${name}.path
            ) credentialHolders == credentialHolders;

          # PromQL read path (charter v13): GreptimeDB v1.2.1 registers the
          # PromQL query API only when prom_store is enabled
          # (src/frontend/src/server.rs:130-158).
          promqlApi = (s.prom_store.enable or false) == true;
        };

      failures = v: lib.attrNames (lib.filterAttrs (_: holds: !holds) (clauses v));

      withSettings = f: v: v // { settings = f v.settings; };
      withStorage = f: withSettings (settings: settings // { storage = f settings.storage; });
      withMito =
        f:
        withSettings (
          settings:
          settings
          // {
            region_engine = map (
              engine: if engine ? mito then engine // { mito = f engine.mito; } else engine
            ) (settings.region_engine or [ ]);
          }
        );

      mutants = {
        # R7.1, the seven of A7:136
        dropMemoryMax = {
          clause = "memoryMax";
          apply = v: v // { unit = removeAttrs v.unit [ "MemoryMax" ]; };
        };
        dropPageCacheSize = {
          clause = "memoryKnobs";
          apply = withMito (mito: removeAttrs mito [ "page_cache_size" ]);
        };
        httpOnAllInterfaces = {
          clause = "listenersLoopback";
          apply = withSettings (settings: lib.recursiveUpdate settings { http.addr = "0.0.0.0:4000"; });
        };
        mysqlReenabled = {
          clause = "protocolsDisabled";
          apply = withSettings (settings: lib.recursiveUpdate settings { mysql.enable = true; });
        };
        userProviderRemoved = {
          clause = "userProvider";
          apply = withSettings (settings: removeAttrs settings [ "user_provider" ]);
        };
        # Also R1.4's mutant, "key omitted".
        telemetryOmitted = {
          clause = "telemetryDisabled";
          apply = withSettings (settings: removeAttrs settings [ "enable_telemetry" ]);
        };
        restartUnitsRemoved = {
          clause = "usersRestartUnits";
          apply =
            v:
            v
            // {
              usersFiles = v.usersFiles // {
                users = removeAttrs v.usersFiles.users [ "restartUnits" ];
              };
            };
        };

        # R1.1
        prereleasePackage = {
          clause = "stableRelease";
          apply =
            v:
            v
            // {
              package = v.package.overrideAttrs (_: {
                version = "1.3.0-beta.2";
              });
            };
        };
        pinnedNixpkgsPackage = {
          clause = "embedsDashboard";
          apply = v: v // { package = pkgs.greptimedb; };
        };

        # R6.4
        ec2MetadataNotDisabled = {
          clause = "storageDisableEc2Metadata";
          apply = withStorage (storage: removeAttrs storage [ "disable_ec2_metadata" ]);
        };
        emptyStorageRoot = {
          clause = "storageRoot";
          apply = withStorage (storage: storage // { root = ""; });
        };

        # R8.2 (A8:140)
        workerOwnsCollectorPassword = {
          clause = "usersFilesNonWorker";
          apply =
            v:
            v
            // {
              usersFiles = v.usersFiles // {
                collector-password = v.usersFiles.collector-password // {
                  owner = builtins.head workerUsers;
                };
              };
            };
        };
        # Disk envelope
        diskoQuotaDiffers = {
          clause = "diskoMatchesDataset";
          apply = v: v // { disko = lib.recursiveUpdate v.disko { options.quota = "32G"; }; };
        };

        secondAdminPasswordHolder = {
          clause = "credentialHolders";
          apply =
            v:
            v
            // {
              loadCredentials = v.loadCredentials // {
                nixbot = v.loadCredentials.nixbot ++ [
                  "admin-password:${usersGenerator.files.admin-password.path}"
                ];
              };
            };
        };

        # PromQL read path
        promStoreDisabled = {
          clause = "promqlApi";
          apply = withSettings (settings: lib.recursiveUpdate settings { prom_store.enable = false; });
        };
      };

      missed = lib.attrNames (
        lib.filterAttrs (_: mutant: !(builtins.elem mutant.clause (failures (mutant.apply view)))) mutants
      );

      # Users-file clause: run the generator exactly as clan does
      # (finalScript: PATH from runtimeInputs plus coreutils, then the script)
      # and require four `<user>:<mode>=<hex>` lines, then show the oracle
      # rejects a fifth line and a password containing `=`.
      usersFileCheck = ''
        valid_users_file() {
          [ "$(wc -l < "$1")" -eq 4 ] || return 1
          [ "$(cut -d '=' -f 1 "$1" | tr '\n' ' ')" = "admin:rw collector:wo perses:ro regulator:ro " ] || return 1
          ! grep -Evq '^(admin:rw|collector:wo|perses:ro|regulator:ro)=[0-9a-f]{32,}$' "$1"
        }

        generated="$TMPDIR/greptimedb-users"
        mkdir "$generated"
        out="$generated" bash ${usersGenerator.finalScript}

        if ! valid_users_file "$generated/users"; then
          echo "greptimedb-users emitted a malformed users file:" >&2
          sed 's/=.*/=<redacted>/' "$generated/users" >&2
          exit 1
        fi
        for pair in admin:rw collector:wo perses:ro regulator:ro; do
          user="''${pair%%:*}"
          if [ "$(grep "^$pair=" "$generated/users" | cut -d '=' -f 2)" != "$(cat "$generated/$user-password")" ]; then
            echo "greptimedb-users: $user-password differs from its users line" >&2
            exit 1
          fi
        done
        if [ "$(sha256sum < "$generated/users" | cut -d ' ' -f 1)" != "$(cat "$generated/users-sha256")" ]; then
          echo "greptimedb-users: users-sha256 is not the sha256 of users" >&2
          exit 1
        fi

        cp "$generated/users" fifth-line
        printf 'extra:rw=%s\n' "$(cat "$generated/admin-password")" >> fifth-line
        sed '1s/^\(admin:rw=..\)/\1=/' "$generated/users" > password-with-equals
        for mutant in fifth-line password-with-equals; do
          if valid_users_file "$mutant"; then
            echo "users-file oracle accepted mutant $mutant" >&2
            exit 1
          fi
        done
      '';
    in
    {
      checks = lib.optionalAttrs (system == "x86_64-linux") {
        greptimedb-envelope =
          assert lib.assertMsg (
            failures view == [ ]
          ) "greptimedb envelope clauses failed on magnetite: ${builtins.toJSON (failures view)}";
          assert lib.assertMsg (
            missed == [ ]
          ) "greptimedb-envelope oracle accepted mutants: ${builtins.toJSON missed}";
          pkgs.runCommand "greptimedb-envelope" { } ''
            ${usersFileCheck}
            # 5.2: the envelope's SQL helper fails on absent evidence.
            test -e ${greptimedbSqlRehearsal}
            touch "$out"
          '';
      };
    };
}
