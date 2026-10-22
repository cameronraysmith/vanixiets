# On-demand runtime test of S2's collection path
# (openspec/changes/stand-up-devloop-collection, design D16; tasks.md 3.9,
# 4.6, 5.6).
#
# One systemd-nspawn container on a builder advertising uid-range
# (magnetite) runs PostgreSQL with the nixbot input's migrations, applied by
# a stand-in nixbot.service that devloop-pg-grants orders after; GreptimeDB
# with magnetite's databases, the devloop tables and pipelines and the
# credentials of magnetite's greptimedb-users generator; the collector with
# both roles and devloop-collection; a stub gitea-mq.service printing the
# lines of /run/devloop-ingest/gitea-mq-lines; and the deploy-record
# activation snippet. testScript is helpers.py followed by `cases`, in order.
#
# What it establishes: each devloop exporter's first send succeeds when the
# store, its schema job and the collector start together, and fails when the
# schema job has not created its table (auto_create_table=false); each stored
# table equals the allow-list; overlap re-reads leave one row per key; lines
# outside the five batch messages are not stored; one activation appends one
# deploy record naming both closures and reaches the store; the documented
# queries answer on GreptimeDB 1.2.1.
#
# What it does not establish: the collector's keep-list (`retain`) and body
# removal, which are defence in depth with no test here, because the
# pre-created DDL and each pipeline's VRL reset (`. = {}` and one assignment
# per allow-listed field) decide the stored columns whatever the record
# carries; the collector's order after the schema job, which R3.1's
# schemaOrderDropped mutant judges; nixbot itself (the stand-in only migrates),
# magnetite's journal retention, deployed credentials or storage, the OOM
# order, or a configuration switch the container cannot perform: the
# switch case prints a `limitation:` line when it falls back to running the
# activation script. A configuration mutant is installed at runtime as a
# drop-in, because an nspawn node cannot switch to a specialisation.
{ self, inputs, ... }:
{
  perSystem =
    {
      pkgs,
      lib,
      system,
      ...
    }:
    {
      vmTests = lib.optionalAttrs (system == "x86_64-linux") {
        devloop-ingest =
          let
            # perSystem `pkgs` lacks the flake overlay that carries
            # greptimedb-bin.
            nodePkgs = import inputs.nixpkgs {
              inherit system;
              config.allowUnfree = true;
              overlays = [ self.overlays.default ];
            };
            reference = self.nixosConfigurations.magnetite.config;
            inherit (reference.services.greptimedb) databases;
            usersGenerator = reference.clan.core.vars.generators.greptimedb-users;
            schema = self.lib.otelCollectorSchema;
            devloop = self.lib.devloopCollection;
            vars = "/run/devloop-ingest-vars";
            credentialConsumers = [
              "greptimedb.service"
              "greptimedb-schema.service"
              "opentelemetry-collector.service"
            ];

            # nixbot's rows at boot: build 9001 is a pull-request build whose
            # three attributes finish in one transaction (a finished_at tie),
            # one abandoned by the marker and one an ignored_failure with
            # error text; build 9002 is a merge-queue build with no
            # pull-request number and one cached attribute.
            baselineFixtures = pkgs.writeText "devloop-ingest-baseline.sql" ''
              INSERT INTO projects (id, forge, forge_repo_id, owner, name, default_branch, url)
              OVERRIDING SYSTEM VALUE
              VALUES (1, 'gitea', '1', 'crs58', 'vanixiets', 'main', 'https://gitea.zt/crs58/vanixiets');
              INSERT INTO builds (id, project_id, number, commit_sha, branch, pr_number, status, created_at, started_at, finished_at, eval_duration_ms, eval_completed)
              OVERRIDING SYSTEM VALUE
              VALUES
                (9001, 1, 1, 'a000000000000000000000000000000000009001', 'pr/9001', 9001, 'failed', now() - interval '30 minutes', now() - interval '25 minutes', now() - interval '10 minutes', 4200, true),
                (9002, 1, 2, 'b000000000000000000000000000000000009002', 'gitea-mq/batch/1', NULL, 'succeeded', now() - interval '29 minutes', now() - interval '28 minutes', now() - interval '11 minutes', 3100, true);
              INSERT INTO build_attributes (build_id, attr, system, drv_path, outputs, status, cached, error, started_at, finished_at, eval_wall_ms, eval_alloc_bytes)
              VALUES
                (9001, 'checks.x86_64-linux.pass', 'x86_64-linux', '/nix/store/00000000000000000000000000000001-pass.drv', '{"out": "/nix/store/00000000000000000000000000000001-pass"}', 'succeeded', false, NULL, now() - interval '20 minutes', now() - interval '12 minutes', 900, 1048576),
                (9001, 'checks.x86_64-linux.abandoned', 'x86_64-linux', '/nix/store/00000000000000000000000000000002-abandoned.drv', NULL, 'ignored_failure', false, '${devloop.abandonMarker}', NULL, now() - interval '12 minutes', NULL, NULL),
                (9001, 'checks.x86_64-linux.broken', 'x86_64-linux', '/nix/store/00000000000000000000000000000003-broken.drv', NULL, 'ignored_failure', false, 'error: builder for broken failed with exit code 1', now() - interval '19 minutes', now() - interval '12 minutes', 700, 524288),
                (9002, 'checks.x86_64-linux.cached', 'x86_64-linux', '/nix/store/00000000000000000000000000000004-cached.drv', '{"out": "/nix/store/00000000000000000000000000000004-cached"}', 'skipped_local', true, NULL, NULL, now() - interval '13 minutes', 50, 65536);
            '';

            # Prints one line at a time, so the journal gives each line its
            # own __REALTIME_TIMESTAMP.
            giteaMqStub = pkgs.writeShellScript "gitea-mq-stub" ''
              while IFS= read -r line; do
                printf '%s\n' "$line"
                sleep 0.05
              done < /run/devloop-ingest/gitea-mq-lines
            '';

            # Configuration mutants: name -> { unit (without .service);
            # module }. Each is rendered as a drop-in of the unit's ExecStart
            # under the container's extendModules (Task 4 adds entries).
            unitMutants = { };

            firstStart = ''
              print("=== case firstStart")
              start_all()
              store.wait_for_unit("multi-user.target")
              for table in config()["tables"]:
                  retry(
                      lambda _last, t=table: _count(t) > 0 and _sent(t) > 0,
                      timeout=dt.timedelta(minutes=5),
                  )
                  failed = send_failed(table)
                  assert failed == 0, (table, failed)
                  print(f"ok: firstStart: otlp_http/devloop_{table} sent {_sent(table)}, send_failed 0")
              type_names = {
                  "int64": "Int64",
                  "string": "String",
                  "boolean": "Boolean",
                  "timestamp": "TimestampMicrosecond",
              }
              for table, spec in config()["tables"].items():
                  desc = gsql(f'DESC TABLE "{table}"')
                  got = [(row[0], row[1], row[5]) for row in desc]
                  want = [
                      (
                          column["name"],
                          type_names[column["type"]],
                          "TIMESTAMP" if column["name"] == spec["timeIndex"]
                          else "TAG" if column["name"] in spec["primaryKey"]
                          else "FIELD",
                      )
                      for column in spec["columns"]
                  ]
                  assert got == want, (table, got, want)
                  assert "body" not in [row[0] for row in desc], (table, desc)
                  print(f"ok: firstStart: DESC TABLE {table} equals the allow-list")
              print("ok: firstStart")
            '';

            noAutoCreate = ''
              print("=== case noAutoCreate")
              reset_devloop()
              admin_sql('DROP TABLE "ci_build"')
              collector_restart()
              retry(lambda _last: send_failed("ci_build") > 0, timeout=dt.timedelta(minutes=5))
              tables = [row[0] for row in gsql("SHOW TABLES")]
              assert "ci_build" not in tables, tables
              for table in ("ci_attribute", "batch_event"):
                  retry(lambda _last, t=table: _sent(t) > 0, timeout=dt.timedelta(minutes=5))
                  assert send_failed(table) == 0, (table, send_failed(table))
              print(
                  "mutant noAutoCreate rejected: otlp_http/devloop_ci_build send_failed "
                  f"{send_failed('ci_build')} when the schema job's tables lack ci_build, and no table was created"
              )
              reset_devloop()
              collector_restart()
              retry(lambda _last: _sent("ci_build") > 0, timeout=dt.timedelta(minutes=5))
              assert send_failed("ci_build") == 0, send_failed("ci_build")
              print("ok: noAutoCreate")
            '';

            overlap = ''
              print("=== case overlap")
              utc_today()
              reset_devloop()
              collector_restart()
              wait_rows("ci_attribute", int(psql("SELECT count(*) FROM build_attributes").strip()))
              nixbot_rows(
                  "INSERT INTO builds (id, project_id, number, commit_sha, branch, pr_number, status, created_at, started_at, finished_at, eval_completed) "
                  "OVERRIDING SYSTEM VALUE VALUES (9101, 1, 9101, 'c000000000000000000000000000000000009101', 'pr/9101', 9101, 'succeeded', now() - interval '3 minutes', now() - interval '2 minutes', now(), true); "
                  "INSERT INTO build_attributes (build_id, attr, system, status, cached, started_at, finished_at) VALUES "
                  "(9101, 'checks.x86_64-linux.overlap-a', 'x86_64-linux', 'succeeded', false, now() - interval '1 minute', now()), "
                  "(9101, 'checks.x86_64-linux.overlap-b', 'x86_64-linux', 'succeeded', false, now() - interval '1 minute', now()), "
                  "(9101, 'checks.x86_64-linux.overlap-c', 'x86_64-linux', 'skipped_local', true, NULL, now())"
              )
              # The counters are read once the new rows are stored, so idle
              # re-reads of the cursor's tie before the insert cannot meet the
              # bound; every later poll re-reads the three attribute rows and
              # the build row while they are under 5 min old (design D6), so
              # two more polls send at least 6 and 2 more records.
              retry(
                  lambda _last: gsql('SELECT count(*) FROM "ci_attribute" WHERE "build_id" = 9101') == [[3]]
                  and gsql('SELECT count(*) FROM "ci_build" WHERE "build_id" = 9101') == [[1]],
                  timeout=dt.timedelta(minutes=3),
              )
              attributes_before = _sent("ci_attribute")
              builds_before = _sent("ci_build")
              retry(
                  lambda _last: _sent("ci_attribute") >= attributes_before + 6
                  and _sent("ci_build") >= builds_before + 2,
                  timeout=dt.timedelta(minutes=4),
              )
              for table in ("ci_attribute", "ci_build"):
                  rows, distinct = key_counts(table)
                  assert rows == distinct, (table, rows, distinct)
              assert gsql('SELECT count(*) FROM "ci_attribute" WHERE "build_id" = 9101') == [[3]]
              assert gsql('SELECT count(*) FROM "ci_build" WHERE "build_id" = 9101') == [[1]]
              print(
                  f"ok: overlap: ci_attribute sent {_sent('ci_attribute') - attributes_before} and ci_build "
                  f"{_sent('ci_build') - builds_before} records after the rows were stored; one row per key"
              )
              print("ok: overlap")
            '';

            tableShape = ''
              print("=== case tableShape")
              pattern = re.compile(r'msg="(batch (formed|built|landed|bisecting|done))"')
              want = {}
              for line in store.succeed("cat /etc/devloop-ingest/gitea-mq-lines.txt").splitlines():
                  match = pattern.search(line)
                  if match:
                      want[match.group(1)] = want.get(match.group(1), 0) + 1
              printed = int(store.succeed(
                  "journalctl -u gitea-mq.service -o cat | grep -cE 'msg=\"batch (formed|built|landed|bisecting|done)\"'"
              ).strip())
              assert printed == sum(want.values()), (printed, want)
              wait_rows("batch_event", sum(want.values()))
              got = {row[0]: row[1] for row in gsql('SELECT "msg", count(*) FROM "batch_event" GROUP BY "msg"')}
              assert got == want, (got, want)
              assert gsql("SELECT count(*) FROM \"batch_event\" WHERE \"msg\" = 'batch reconcile build failed'") == [[0]]
              columns = [row[0] for row in gsql('DESC TABLE "batch_event"')]
              for key in ("extra_key", "branch", "time", "level", "current", "pending", "prs", "left", "right", "err", "repos"):
                  assert key not in columns, (key, columns)
              assert gsql("SELECT \"members\" FROM \"batch_event\" WHERE \"batch\" = 3 AND \"msg\" = 'batch formed'") == [[1]]
              assert gsql("SELECT \"flaky\", \"ejected\" FROM \"batch_event\" WHERE \"batch\" = 2 AND \"msg\" = 'batch done'") == [[True, 2]]
              print(f"ok: tableShape: batch_event per msg {got}; the reconcile line is not stored")
              # The receiver's journalctl reads every retained boot: under
              # --follow, systemd 261 otherwise reads only the current one.
              argv = store.succeed("pgrep -a journalctl").splitlines()
              assert any("--boot=all" in line.split() and "gitea-mq.service" in line.split() for line in argv), argv
              print("ok: tableShape: the receiver's journalctl runs with --boot=all")

              # The CI rows as stored against nixbot's source rows, read by
              # psql; abandoned against the fixture's intent.
              retry(
                  lambda _last: gsql('SELECT count(*) FROM "ci_attribute" WHERE "build_id" IN (9001, 9002)') == [[4]],
                  timeout=dt.timedelta(minutes=4),
              )
              source = []
              for line in psql(
                  "SELECT a.build_id, a.attr, a.status, a.cached, coalesce(a.outputs ->> 'out', '''), "
                  "(extract(epoch FROM a.finished_at) * 1000000)::bigint, coalesce(b.pr_number::text, ''') "
                  "FROM build_attributes a JOIN builds b ON b.id = a.build_id "
                  "WHERE a.build_id IN (9001, 9002) ORDER BY a.build_id, a.attr"
              ).splitlines():
                  build, attr, status, cached, out, finished, pr = line.split("|")
                  source.append([int(build), attr, status, cached == "t", out or None, int(finished), int(pr) if pr else None])
              stored = gsql(
                  'SELECT "build_id", "attr", "status", "cached", "outputs_out", "finished_at", "pr_number", "abandoned" '
                  'FROM "ci_attribute" WHERE "build_id" IN (9001, 9002) ORDER BY "build_id", "attr"'
              )
              assert [row[:7] for row in stored] == source, (stored, source)
              abandoned = {row[1]: row[7] for row in stored}
              assert abandoned == {
                  "checks.x86_64-linux.abandoned": True,
                  "checks.x86_64-linux.broken": False,
                  "checks.x86_64-linux.pass": False,
                  "checks.x86_64-linux.cached": False,
              }, abandoned
              broken = gsql("SELECT * FROM \"ci_attribute\" WHERE \"attr\" = 'checks.x86_64-linux.broken'")
              assert not any("builder for broken failed" in str(value) for value in broken[0]), broken
              print("ok: tableShape: ci_attribute equals nixbot's rows, abandoned only for the marker, no error text")
              print("ok: tableShape")
            '';

            switch = ''
              print("=== case switch")

              def record_lines():
                  text = store.succeed(f"cat {DEPLOY_RECORD} 2>/dev/null || true")
                  return [json.loads(line) for line in text.splitlines() if line.strip()]

              original = store.succeed("readlink -f /run/current-system").strip()
              variant = store.succeed("readlink -f /etc/devloop-ingest/variant-system").strip()
              before = record_lines()
              code, output = store.execute(f"{variant}/bin/switch-to-configuration test 2>&1")
              added = record_lines()[len(before):]
              switched = code == 0
              if code != 0 and not added:
                  print(
                      f"limitation: switch-to-configuration test exited {code} in the nspawn container "
                      f"before activation ({output.strip().splitlines()[-1] if output.strip() else 'no output'}); "
                      f"running {variant}/activate, which sets systemConfig={variant} (design D16)"
                  )
                  store.succeed(f"{variant}/activate")
                  added = record_lines()[len(before):]
              elif code != 0:
                  print(f"limitation: switch-to-configuration test exited {code} after activation appended its line")
              assert len(added) == 1, added
              line = added[0]
              assert set(line) == {"host", "closure", "previous_closure", "ts"}, line
              assert line["host"] == "store", line
              assert line["closure"] == variant, (line, variant)
              assert line["previous_closure"] == original, (line, original)
              assert re.fullmatch(r"\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ", line["ts"]), line
              print(f"ok: switch: one line, closure {variant}, previous_closure {original}")

              # Back to the original system, one second later so the second
              # record has its own (host, ts) key.
              store.succeed("sleep 1.1")
              if switched:
                  store.succeed(f"{original}/bin/switch-to-configuration test")
              else:
                  store.succeed(f"{original}/activate")
              lines = record_lines()
              assert lines[-1]["closure"] == original and lines[-1]["previous_closure"] == variant, lines[-1]
              wait_rows("deploy_record", len(lines))
              stored = gsql('SELECT "closure", "previous_closure" FROM "deploy_record" WHERE "host" = \'store\' ORDER BY "ts"')
              assert stored[-2:] == [[variant, original], [original, variant]], stored
              print("ok: switch: both records reached deploy_record")
              print("ok: switch")
            '';

            documentedQueries = ''
              print("=== case documentedQueries")
              reset_devloop()
              t0 = dt.datetime.fromtimestamp(int(store.succeed("date -u +%s").strip()) - 7200, dt.timezone.utc)

              def at(seconds):
                  return (t0 + dt.timedelta(seconds=seconds)).strftime("%Y-%m-%dT%H:%M:%S.%fZ")

              admin_sql(
                  'INSERT INTO "batch_event" ("batch", "msg", "members", "landed", "ejected", "builds", "flaky", "ts") VALUES '
                  f"(9001, 'batch formed', 2, NULL, NULL, NULL, NULL, '{at(0)}'), "
                  f"(9001, 'batch done', NULL, 2, 0, 1, false, '{at(600)}'), "
                  f"(9002, 'batch formed', 3, NULL, NULL, NULL, NULL, '{at(60)}'), "
                  f"(9002, 'batch landed', NULL, NULL, NULL, NULL, NULL, '{at(600)}'), "
                  f"(9002, 'batch done', NULL, 1, 2, 2, true, '{at(1860)}'), "
                  f"(9003, 'batch formed', 1, NULL, NULL, NULL, NULL, '{at(120)}')"
              )
              builds = [
                  f"({601 + k}, '{at(0)}', '{at(60 * k)}', '{at(60 * k + 60)}', 'succeeded', 7, 'pr/7')"
                  for k in range(11)
              ]
              builds.append(f"(612, '{at(0)}', '{at(9999)}', '{at(10059)}', 'succeeded', NULL, 'main')")
              builds.append(f"(613, '{at(0)}', NULL, '{at(30)}', 'cancelled', 7, 'pr/7')")
              # Build 605 restarted: nixbot keeps created_at and resets the
              # start, so the rerun row waits 5000 s and must not count.
              builds.append(f"(605, '{at(0)}', '{at(5000)}', '{at(5060)}', 'succeeded', 7, 'pr/7')")
              admin_sql(
                  'INSERT INTO "ci_build" ("build_id", "created_at", "started_at", "finished_at", "status", "pr_number", "branch") VALUES '
                  + ", ".join(builds)
              )
              attributes = [
                  (501, "a", "succeeded", False, False, "A"),
                  (501, "b", "skipped_local", True, False, "B"),
                  (502, "a", "failed", False, False, "C"),
                  (503, "a", "failed", False, False, "D"),
                  (504, "a", "succeeded", False, False, "D"),
                  (505, "a", "ignored_failure", False, True, "E"),
                  (505, "b", "succeeded", False, False, "F"),
                  (506, "a", "dependency_failed", False, False, "G"),
                  (507, "a", "ignored_failure", False, False, "H"),
                  (509, "a", "failed_eval", False, False, None),
              ]
              admin_sql(
                  'INSERT INTO "ci_attribute" ("build_id", "attr", "status", "cached", "abandoned", "drv_path", "finished_at") VALUES '
                  + ", ".join(
                      f"({build}, 'checks.x86_64-linux.{attr}', '{status}', {str(cached).lower()}, {str(abandoned).lower()}, "
                      + (f"'/nix/store/0000000000000000000000000000000{drv}-{drv}.drv'" if drv else "NULL")
                      + f", '{at(3000 + build)}')"
                      for build, attr, status, cached, abandoned, drv in attributes
                  )
              )

              def close(a, b):
                  return abs(a - b) < 1e-6

              questions = config()["questions"]
              formation = gsql(questions["formationToLand"])
              print(f"formationToLand: {formation}")
              assert [row[0] for row in formation] == [9001, 9002], formation
              assert close(formation[0][1], 600.0) and close(formation[1][1], 1800.0), formation
              wait = gsql(questions["queueWait"])
              print(f"queueWait: {wait}")
              assert gsql('SELECT count(*) FROM "ci_build" WHERE "build_id" = 605') == [[2]]
              assert len(wait) == 1 and wait[0][3] == 11, wait
              assert close(wait[0][0], 300.0) and close(wait[0][1], 540.0) and close(wait[0][2], 594.0), wait
              print("ok: documentedQueries: queueWait counts build 605's first attempt only, not its 5000 s rerun")
              outcome = gsql(questions["buildOutcome"])
              print(f"buildOutcome: {outcome}")
              assert outcome == [
                  [501, "passed"], [502, "failed"], [503, "passed"], [504, "passed"], [505, "passed"],
                  [506, "failed"], [507, "failed"], [509, "failed"],
              ], outcome
              print("ok: documentedQueries: each of the three questions returns its fixture answer")
              reset_devloop()
              collector_restart()
              print("ok: documentedQueries")
            '';

            cases = [
              firstStart
              noAutoCreate
              overlap
              tableShape
              switch
              documentedQueries
            ];
          in
          pkgs.testers.runNixOSTest {
            name = "devloop-ingest";
            requiredFeatures = {
              nixos-test = true;
              uid-range = true;
            };
            node.pkgs = lib.mkForce nodePkgs;
            containers.store =
              {
                config,
                extendModules,
                pkgs,
                ...
              }:
              {
                imports = [
                  self.modules.nixos.greptimedb
                  self.modules.nixos.otel-collector-agent
                  self.modules.nixos.otel-collector-ingress
                  self.modules.nixos.devloop-collection
                  self.modules.nixos.deploy-record
                  # Marks the switch case's second system, so it does not
                  # build a variant of itself.
                  {
                    options.devloopIngest.isVariant = lib.mkOption {
                      type = lib.types.bool;
                      default = false;
                      internal = true;
                    };
                  }
                ];
                system.stateVersion = lib.trivial.release;
                environment.systemPackages = [ pkgs.curl ];

                services.greptimedb = {
                  enable = true;
                  inherit databases;
                };

                # magnetite's PostgreSQL; the stand-in nixbot.service applies
                # the nixbot input's migrations, as nixbot's own start does,
                # and devloop-pg-grants orders after it.
                services.postgresql = {
                  enable = true;
                  inherit (reference.services.postgresql) package;
                  ensureDatabases = [ "nixbot" ];
                };
                systemd.services.nixbot = {
                  description = "Stand-in for nixbot: the input's migrations and the baseline rows";
                  wantedBy = [ "multi-user.target" ];
                  after = [ "postgresql.target" ];
                  requires = [ "postgresql.target" ];
                  path = [
                    config.services.postgresql.package
                    pkgs.bash
                  ];
                  serviceConfig = {
                    Type = "oneshot";
                    RemainAfterExit = true;
                    User = "postgres";
                    Group = "postgres";
                  };
                  script = "bash ${./devloop-ingest/nixbot-schema.sh} ${inputs.nixbot}/nixbot/nixbot/migrations ${baselineFixtures}";
                };

                # gitea-mq writes slog text to stdout under its own unit
                # (logs/s2/grounding.md §2.1); the stub does the same with
                # the lines its runtime symlink names, which a case may point
                # at gitea-mq-empty.txt.
                systemd.services.gitea-mq = {
                  description = "Stand-in for gitea-mq: prints fixture slog lines";
                  wantedBy = [ "multi-user.target" ];
                  serviceConfig = {
                    Type = "oneshot";
                    RemainAfterExit = true;
                    ExecStart = "${giteaMqStub}";
                  };
                };
                systemd.tmpfiles.rules = [
                  "d /run/devloop-ingest 0755 root root -"
                  "L+ /run/devloop-ingest/gitea-mq-lines - - - - /etc/devloop-ingest/gitea-mq-lines.txt"
                ];

                # Credentials from magnetite's own generator script, run at
                # boot, so no credential value exists in the repository; the
                # netrc files keep passwords out of the driver's log.
                systemd.services.devloop-ingest-vars = {
                  description = "Test credentials from magnetite's greptimedb-users generator";
                  requiredBy = credentialConsumers;
                  before = credentialConsumers;
                  path = [
                    pkgs.bash
                    pkgs.coreutils
                  ];
                  serviceConfig = {
                    Type = "oneshot";
                    RemainAfterExit = true;
                  };
                  script = ''
                    install -d -m 0700 ${vars}
                    out=${vars} bash ${usersGenerator.finalScript}
                    for user in admin collector perses regulator; do
                      printf 'machine 127.0.0.1 login %s password %s\n' \
                        "$user" "$(cat "${vars}/$user-password")" > "${vars}/$user.netrc"
                    done
                  '';
                };
                systemd.services.greptimedb.serviceConfig.LoadCredential = [ "users:${vars}/users" ];
                systemd.services.greptimedb-schema.serviceConfig.LoadCredential = [
                  "admin-password:${vars}/admin-password"
                ];
                systemd.services.opentelemetry-collector.serviceConfig.LoadCredential = [
                  "collector-password:${vars}/collector-password"
                ];

                environment.etc = {
                  "devloop-ingest/gitea-mq-lines.txt".source = ./devloop-ingest/gitea-mq-lines.txt;
                  "devloop-ingest/gitea-mq-empty.txt".text = "";
                  # The switch case's second system: nixpkgs' nspawn module
                  # disallows `specialisation`, so the variant is this
                  # configuration extended, linked from /etc.
                  "devloop-ingest/variant-system" = lib.mkIf (!config.devloopIngest.isVariant) {
                    source =
                      (extendModules {
                        modules = [
                          {
                            devloopIngest.isVariant = true;
                            environment.etc."devloop-ingest/variant".text = "devloop-switch";
                          }
                        ];
                      }).config.system.build.toplevel;
                  };
                  "devloop-ingest/config.json".text = builtins.toJSON {
                    inherit vars;
                    psql = "${config.services.postgresql.package}/bin/psql";
                    inherit (schema.devloop) tables;
                    inherit (devloop) questions abandonMarker batchEventKeys;
                  };
                }
                // lib.concatMapAttrs (name: mutant: {
                  "devloop-ingest/mutants/${name}.unit".text = mutant.unit;
                  "devloop-ingest/mutants/${name}.conf".text = ''
                    [Service]
                    ExecStart=
                    ${lib.concatMapStringsSep "\n" (command: "ExecStart=${command}") (
                      lib.toList
                        (extendModules { modules = [ mutant.module ]; })
                        .config.systemd.services.${mutant.unit}.serviceConfig.ExecStart
                    )}
                  '';
                }) unitMutants;
              };
            testScript = builtins.readFile ./devloop-ingest/helpers.py + lib.concatStringsSep "\n" cases;
          };
      };
    };
}
