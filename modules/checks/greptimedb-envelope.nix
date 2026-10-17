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
      # table that does not exist and must fail. The table rows run the
      # envelope's table clause (review F3) on recorded information_schema.tables
      # answers; v1.2.1 renders a table's ttl through humantime's Display, so
      # 365d comes back as several space-separated parts.
      rehearsalUrl = "http://greptimedb.rehearsal.invalid:4000";
      sqlHelper = self.lib.greptimedbSql pkgs {
        url = rehearsalUrl;
        user = "regulator";
      };
      tablesRegulator = self.lib.greptimedbEnvelopeTables pkgs {
        url = rehearsalUrl;
        databases = [
          "fleet"
          "devloop"
        ];
      };
      column = name: data_type: { inherit name data_type; };
      regionColumns = [
        (column "region_id" "UInt64")
        (column "sst_size" "UInt64")
      ];
      tableColumns = [
        (column "table_schema" "String")
        (column "table_name" "String")
        (column "create_options" "String")
      ];
      records = columns: rows: {
        output = [
          {
            records = {
              schema.column_schemas = columns;
              inherit rows;
              total_rows = builtins.length rows;
            };
          }
        ];
        execution_time_ms = 2;
      };
      regionQuery = "SELECT region_id, sst_size FROM information_schema.region_statistics";
      renamedRegionQuery = "SELECT region_id, sst_size FROM information_schema.region_statistic";
      tablesQuery = "SELECT table_schema, table_name, create_options FROM information_schema.tables WHERE table_schema IN ('fleet', 'devloop') AND table_type = 'BASE TABLE'";

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

      stubRow =
        {
          name,
          command,
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
            ${command} > "$TMPDIR/output" 2>&1 || code=$?
          kill "$stub_pid"
          wait "$stub_pid" || true
          stub_pid=
          cat "$TMPDIR/output"
          [ "$code" = ${toString exit} ] || miss "${name}: exit status $code, expected ${toString exit}"
          ${lib.concatMapStrings (line: ''
            grep -qF -- ${lib.escapeShellArg line} "$TMPDIR/output" \
              || miss ${lib.escapeShellArg "${name}: output lacks: ${line}"}
          '') expect}
          [ "$(cat "$TMPDIR/requests")" = ${lib.escapeShellArg "POST /v1/sql regulator ${sql}"} ] \
            || miss "${name}: stub saw: $(cat "$TMPDIR/requests")"
        '';

      sqlRow =
        row: stubRow (row // { command = "${lib.getExe sqlHelper} ${lib.escapeShellArg row.sql}"; });

      # `declared` is services.greptimedb.tableTtls, rendered as the module does.
      tableRow =
        {
          declared,
          rows,
          ...
        }@row:
        stubRow (
          builtins.removeAttrs row [
            "declared"
            "rows"
          ]
          // {
            command = "GREPTIMEDB_ENVELOPE_TABLE_TTLS_FILE=${self.lib.greptimedbTableTtlsFile pkgs declared} ${lib.getExe tablesRegulator}";
            sql = tablesQuery;
            httpStatus = 200;
            reply = records tableColumns rows;
          }
        );

      sqlRows = [
        {
          name = "a records result with rows passes and prints them as TSV";
          sql = regionQuery;
          httpStatus = 200;
          reply = records regionColumns [
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
          reply = records regionColumns [ ];
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

      tableRows = [
        {
          name = "tables on their databases' TTL pass with nothing declared";
          declared = { };
          rows = [
            [
              "fleet"
              "cpu"
              ""
            ]
          ];
          exit = 0;
          expect = [ ];
        }
        {
          name = "an undeclared table TTL fails";
          declared = { };
          rows = [
            [
              "fleet"
              "logs"
              "ttl=14days"
            ]
          ];
          exit = 1;
          expect = [
            "FAIL TTL: fleet.logs sets ttl=14days, which services.greptimedb.tableTtls does not declare"
          ];
        }
        {
          name = "a declared table TTL that matches passes";
          declared."fleet.logs" = "14d";
          rows = [
            [
              "fleet"
              "logs"
              "ttl=14days"
            ]
          ];
          exit = 0;
          expect = [ ];
        }
        {
          name = "a declared table TTL that differs fails";
          declared."fleet.logs" = "7d";
          rows = [
            [
              "fleet"
              "logs"
              "ttl=14days"
            ]
          ];
          exit = 1;
          expect = [
            "FAIL TTL: fleet.logs sets ttl=14days, services.greptimedb.tableTtls declares 7d"
          ];
        }
        {
          name = "a multi-part humantime rendering equals its declared TTL";
          declared."devloop.spans" = "365d";
          rows = [
            [
              "devloop"
              "spans"
              "ttl=11months 30days 3h 50m 24s append_mode=true"
            ]
          ];
          exit = 0;
          expect = [ ];
        }
        {
          name = "a declared table on its database's TTL fails";
          declared."fleet.logs" = "14d";
          rows = [
            [
              "fleet"
              "logs"
              ""
            ]
          ];
          exit = 1;
          expect = [
            "FAIL TTL: fleet.logs sets no ttl of its own, services.greptimedb.tableTtls declares 14d"
          ];
        }
        {
          name = "a declared table that does not exist yet is not judged";
          declared."fleet.logs" = "14d";
          rows = [
            [
              "fleet"
              "cpu"
              ""
            ]
          ];
          exit = 0;
          expect = [ ];
        }
        {
          name = "no base table fails";
          declared = { };
          rows = [ ];
          exit = 1;
          expect = [
            "greptimedb-sql: empty result"
            "FAIL R6.3: information_schema.tables gave no base table in 'fleet', 'devloop'"
          ];
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
            meta.description = "behavioural check: the envelope's SQL helper fails on an empty result and on a missing table, and its table clause accepts only declared table TTLs";
          }
          ''
            set -euo pipefail
            stub_pid=
            trap '[ -z "$stub_pid" ] || kill "$stub_pid" 2>/dev/null || true' EXIT
            fail() {
              echo "FAIL: $*" >&2
              exit 1
            }
            # Every row runs, so one build reports every miss.
            missed=0
            miss() {
              echo "MISS: $*" >&2
              missed=1
            }
            mkdir "$TMPDIR/credentials"
            printf '%s' 00112233445566778899aabbccddeeff > "$TMPDIR/credentials/regulator-password"

            ${lib.concatMapStrings sqlRow sqlRows}
            ${lib.concatMapStrings tableRow tableRows}
            [ "$missed" = 0 ]
            touch "$out"
          '';

      # R7.2 (review F2) over cgroup files recorded on magnetite on 2026-10-17
      # (memory.stat through `hugetlb`;
      # logs/s1-evidence/review-a-f2-recorded-cgroup-*.log): memory.peak
      # counts page cache and never falls within an invocation, so the
      # regulator reads throttling (memory.events `high`) and anonymous memory
      # (memory.stat `anon`) instead. Rows run in order against one state
      # directory, so each row's baseline is the previous row's run.
      recordedInvocation = "dbfc4564fbfb4623a29cb478c5e0cdf3";
      recordedAnon = 104235008;
      recordedPeak = 168730624;
      recordedMemoryEvents = high: ''
        low 0
        high ${toString high}
        max 0
        oom 0
        oom_kill 0
        oom_group_kill 0
      '';
      recordedMemoryStat = ''
        anon ${toString recordedAnon}
        file 42446848
        kernel 3784704
        kernel_stack 950272
        pagetables 2179072
        sec_pagetables 0
        percpu 8712
        sock 0
        vmalloc 53248
        shmem 8192
        zswap 0
        zswapped 0
        file_mapped 42422272
        file_dirty 0
        file_writeback 0
        swapcached 0
        anon_thp 0
        file_thp 0
        shmem_thp 0
        inactive_anon 30785536
        active_anon 73449472
        inactive_file 27271168
        active_file 15171584
        unevictable 4096
        slab_reclaimable 104616
        slab_unreclaimable 488752
        slab 593368
        hugetlb 0
      '';
      # Answers the two `systemctl show` queries for one running invocation.
      systemdStub = pkgs.writeShellScriptBin "systemctl" ''
        case "$*" in
          *--property=InvocationID*) echo ${recordedInvocation} ;;
          *--property=NRestarts*) echo 0 ;;
          *) exit 1 ;;
        esac
      '';
      memoryRegulator = self.lib.greptimedbEnvelopeMemory pkgs {
        unit = "greptimedb.service";
        systemdPackage = systemdStub;
      };
      gib = n: n * 1024 * 1024 * 1024;
      memoryRows = [
        {
          name = "a first run records a baseline and passes";
          high = 0;
          anonMax = gib 3;
          exit = 0;
          expect = [ ];
        }
        {
          name = "unchanged throttling passes while page cache lifts memory.peak over the threshold";
          high = 0;
          anonMax = recordedAnon + 1;
          exit = 0;
          expect = [ ];
        }
        {
          name = "a rise of memory.events high within one invocation fails";
          high = 3;
          anonMax = gib 3;
          exit = 1;
          expect = [
            "FAIL R7.2: memory.events high rose from 0 to 3; the store was throttled at MemoryHigh"
          ];
        }
        {
          name = "anonymous memory at the threshold fails";
          high = 3;
          anonMax = recordedAnon;
          exit = 1;
          expect = [
            "FAIL R7.2: memory.stat anon ${toString recordedAnon} >= GREPTIMEDB_ENVELOPE_ANON_MAX_BYTES ${toString recordedAnon}"
          ];
        }
      ];
      memoryRow =
        {
          name,
          high,
          anonMax,
          exit,
          expect,
        }:
        ''
          echo "--- ${name}"
          printf '%s' ${lib.escapeShellArg (recordedMemoryEvents high)} > "$cgroup/memory.events"
          code=0
          GREPTIMEDB_ENVELOPE_ANON_MAX_BYTES=${toString anonMax} STATE_DIRECTORY="$TMPDIR/state" \
            ${lib.getExe memoryRegulator} "$cgroup" > "$TMPDIR/output" 2>&1 || code=$?
          cat "$TMPDIR/output"
          [ "$code" = ${toString exit} ] || miss "${name}: exit status $code, expected ${toString exit}"
          [ "$(grep -c '^FAIL ' "$TMPDIR/output")" = ${toString (builtins.length expect)} ] \
            || miss "${name}: expected ${toString (builtins.length expect)} FAIL line(s)"
          ${lib.concatMapStrings (line: ''
            grep -qxF -- ${lib.escapeShellArg line} "$TMPDIR/output" \
              || miss ${lib.escapeShellArg "${name}: output lacks: ${line}"}
          '') expect}
        '';
      greptimedbMemoryRehearsal =
        pkgs.runCommand "greptimedb-memory-rehearsal"
          {
            nativeBuildInputs = [
              pkgs.coreutils
              pkgs.gnugrep
            ];
            meta.description = "behavioural check: R7.2 fails on throttling and on anonymous memory, not on page cache";
          }
          ''
            set -euo pipefail
            missed=0
            miss() {
              echo "MISS: $*" >&2
              missed=1
            }
            cgroup="$TMPDIR/cgroup"
            mkdir "$cgroup" "$TMPDIR/state"
            printf '%s' ${lib.escapeShellArg recordedMemoryStat} > "$cgroup/memory.stat"
            echo ${toString recordedPeak} > "$cgroup/memory.peak"

            ${lib.concatMapStrings memoryRow memoryRows}
            [ "$missed" = 0 ]
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
            # R7.2 regulates throttling and anonymous memory.
            test -e ${greptimedbMemoryRehearsal}
            touch "$out"
          '';
      };
    };
}
