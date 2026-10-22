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
              "devloop-reconcile.service"
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

            # Task 4: an attribute rendered at runtime by a container path.
            currentSystemLink = "/run/devloop-ingest/current-system";
            # replaceOnce NAME FROM TO TEXT: TEXT with its one FROM replaced.
            replaceOnce =
              name: from: to: text:
              assert lib.assertMsg (
                builtins.length (lib.splitString from text) == 2
              ) "devloop-ingest: mutant ${name} must match exactly once";
              builtins.replaceStrings [ from ] [ to ] text;
            # A list option cannot be edited in place, so the receiver
            # mutants below rebuild a whole list; the container asserts that
            # each rebuilt list, given the real values, equals its
            # configuration's, so a mutant differs only where it says.
            queryElement = table: sql: {
              inherit sql;
              tracking_column = "finished_at";
              tracking_start_value = "1970-01-01T00:00:00.000000Z";
              logs = [
                {
                  body_column = "body";
                  attribute_columns = map (
                    column: column.name
                  ) self.lib.otelCollectorSchema.devloop.tables.${table}.columns;
                }
              ];
            };
            journaldOperators = [
              {
                type = "key_value_parser";
                id = "parse-message";
                parse_from = "body.MESSAGE";
              }
              {
                type = "retain";
                id = "keep-list";
                fields = map (key: "attributes.${key}") devloop.batchEventKeys;
              }
              {
                type = "remove";
                id = "drop-body";
                field = "body";
              }
            ];
            # Configuration mutants: name -> { unit (without .service);
            # module }. Each is rendered as a drop-in of the unit's ExecStart
            # under the container's extendModules. Task 4 (design D11): one
            # collector mutant per D11 row whose change is the collector's
            # configuration.
            unitMutants = {
              # C1: an attribute query that omits cached = true rows.
              omitCached = {
                unit = "opentelemetry-collector";
                module =
                  { lib, ... }:
                  {
                    services.opentelemetry-collector.settings.receivers."sqlquery/ci_attribute".queries = lib.mkForce [
                      (queryElement "ci_attribute" (
                        replaceOnce "omitCached" "WHERE " "WHERE NOT cached AND " devloop.queries.ci_attribute
                      ))
                    ];
                  };
              };
              # C2: a build query that omits rows with a null pr_number.
              omitNullPr = {
                unit = "opentelemetry-collector";
                module =
                  { lib, ... }:
                  {
                    services.opentelemetry-collector.settings.receivers."sqlquery/ci_build".queries = lib.mkForce [
                      (queryElement "ci_build" (
                        replaceOnce "omitNullPr" "WHERE " "WHERE pr_number IS NOT NULL AND " devloop.queries.ci_build
                      ))
                    ];
                  };
              };
              # C3: the gitea-mq receiver without key_value_parser.
              noKeyValueParser = {
                unit = "opentelemetry-collector";
                module =
                  { lib, ... }:
                  {
                    services.opentelemetry-collector.settings.receivers."journald/gitea-mq".operators = lib.mkForce (
                      lib.drop 1 journaldOperators
                    );
                  };
              };
              # C6: file_log/deploy-record reading another path.
              deployRecordOtherPath = {
                unit = "opentelemetry-collector";
                module =
                  { lib, ... }:
                  {
                    services.opentelemetry-collector.settings.receivers."file_log/deploy-record".include = lib.mkForce [
                      "/var/log/deploy-record-other.jsonl"
                    ];
                  };
              };
            };

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

            # Task 4 (tasks.md 4.6; design D11, D16): devloop-reconcile, as
            # its unit runs, passes on the unmutated collection after the
            # overlap re-reads, with an attribute restarted and with it
            # finished again after the window, and fails naming its clause
            # for each of D11's eight mutants. Every leg starts from the
            # day's journal emptied of earlier stub lines, the tables and
            # cursors reset, one deploy record and the stub's lines, so the
            # window holds only that leg's events.
            reconcile = ''
              import datetime
              import re
              import time

              print("=== case reconcile")
              CURRENT_SYSTEM = "${currentSystemLink}"
              DAY_CONF = "/run/systemd/system/devloop-reconcile.service.d/zz-day.conf"
              STUB_LINES = "/run/devloop-ingest/gitea-mq-lines"
              FIXTURE_LINES = "/etc/devloop-ingest/gitea-mq-lines.txt"
              EMPTY_LINES = "/etc/devloop-ingest/gitea-mq-empty.txt"
              REAL_RECORD = "/etc/devloop-ingest/deploy-record"
              SWAPPED_RECORD = "/etc/devloop-ingest/mutants/snippet-swaps-closures"
              BATCH = "msg=\"batch (formed|built|landed|bisecting|done)\""
              CLAUSES = [
                  "C1 attributes",
                  "C2 builds",
                  "C3 batch-lines",
                  "C4 batch-liveness",
                  "C5 batch-fields",
                  "C6 deploys",
                  "C7 current-system",
              ]
              TABLES = ["ci_attribute", "ci_build", "batch_event", "deploy_record"]
              VARS = config()["vars"]
              RESTARTED = "checks.x86_64-linux.reconcile-restarted"


              # C7's wait prints this on stderr before each 10 s retry; the
              # verdict lines are the seven clause lines alone.
              WAITING = "devloop-reconcile: C7 current-system: waiting for "
              VERDICT = re.compile(r"^devloop-reconcile: C[1-7] [a-z-]+: (ok$|FAIL )")
              WAITS = {"n": 0}


              def reconcile(day, during=None):
                  store.succeed(
                      "mkdir -p /run/systemd/system/devloop-reconcile.service.d",
                      f"printf '[Service]\\nEnvironment=DEVLOOP_RECONCILE_DAY=%s\\n' {day} > {DAY_CONF}",
                      "systemctl daemon-reload",
                  )
                  if during is None:
                      store.execute("systemctl start devloop-reconcile.service")
                  else:
                      store.succeed("systemctl start --no-block devloop-reconcile.service")
                      during()
                      store.wait_until_succeeds(
                          'test "$(systemctl show -P ActiveState devloop-reconcile.service)" != activating',
                          timeout=300,
                      )
                  invocation = store.succeed("systemctl show -P InvocationID devloop-reconcile.service").strip()
                  status = int(store.succeed("systemctl show -P ExecMainStatus devloop-reconcile.service").strip())
                  journal = f"journalctl --no-pager -o cat _SYSTEMD_INVOCATION_ID={invocation}"
                  if status in (0, 1):
                      store.wait_until_succeeds(f"{journal} | grep -q '^devloop-reconcile: C7 current-system: [oF]'", timeout=60)
                  output = store.succeed(journal).splitlines()
                  lines = [l for l in output if VERDICT.match(l)]
                  WAITS["n"] = sum(1 for l in output if l.startswith(WAITING))
                  print(f"reconcile {day}: exit {status}, {WAITS['n']} C7 waits")
                  for line in lines:
                      print(line)
                  return status, lines


              def passes(stage, status, lines):
                  assert status == 0, (stage, status, lines)
                  assert lines == [f"devloop-reconcile: {clause}: ok" for clause in CLAUSES], (stage, lines)
                  print(f"reconcile passes: {stage}")


              def rejected(name, expected, status, lines):
                  fails = sorted(l.split(": ")[1] for l in lines if ": FAIL " in l)
                  assert status == 1 and fails == sorted(expected), (name, expected, status, lines)
                  print(f"mutant {name} rejected: " + " | ".join(l for l in lines if ": FAIL " in l))


              def batch_lines(command):
                  return int(store.succeed(f"{command} | grep -cE '{BATCH}' || true").strip())


              def activate(record, closure):
                  # As activation does: the snippet, then the relink.
                  store.succeed(f"{record} {closure}", f"ln -sfn {closure} {CURRENT_SYSTEM}")


              def fresh_leg(silent=False):
                  store.succeed("systemctl stop gitea-mq.service")
                  # Earlier stub lines would otherwise stay in the day (C3, C4).
                  # The container cannot set the journal directory's setgid
                  # bit (systemd-tmpfiles' fchmod is refused at boot), so the
                  # file journald opens on rotation is root:root; chgrp gives
                  # it the group the collector and the reconcile read through,
                  # as tmpfiles' `z .../system.journal` line does at boot.
                  store.succeed(
                      "journalctl --rotate",
                      "sleep 2",
                      "journalctl --vacuum-time=1s",
                      "chgrp systemd-journal /var/log/journal/*/system.journal",
                  )
                  reset_devloop()
                  stub = EMPTY_LINES if silent else FIXTURE_LINES
                  store.succeed(
                      "mkdir -p /run/devloop-ingest",
                      f"ln -sfn {stub} {STUB_LINES}",
                      f"ln -sfn {X0} {CURRENT_SYSTEM}",
                  )


              def start_sources(record=REAL_RECORD, silent=False, mutant=None):
                  activate(record, X1)
                  store.succeed("systemctl restart gitea-mq.service")
                  want = 0 if silent else batch_lines(f"cat {FIXTURE_LINES}")
                  retry(
                      lambda _last: batch_lines("journalctl --no-pager -o cat -u gitea-mq.service") == want,
                      timeout=datetime.timedelta(minutes=1),
                  )
                  collector_restart(mutant)


              def settle(touched=()):
                  expected = {
                      "ci_attribute": int(psql("SELECT count(*) FROM build_attributes WHERE finished_at IS NOT NULL").strip()),
                      "ci_build": int(psql("SELECT count(*) FROM builds WHERE finished_at IS NOT NULL").strip()),
                      "batch_event": batch_lines(f"cat {FIXTURE_LINES}"),
                      "deploy_record": 1,
                  }
                  for table in TABLES:
                      if table not in touched:
                          wait_rows(table, expected[table])
                          assert send_failed(table) == 0, (table, send_failed(table))
                  if touched:
                      # Two further 60 s polls of the mutated receiver.
                      time.sleep(130)


              # The case runs about 45 minutes; it starts at least an hour
              # before 00:00 UTC so every leg's events fall in one UTC day.
              to_midnight = int(store.succeed("echo $(( 86400 - $(date -u +%s) % 86400 ))").strip())
              if to_midnight < 3600:
                  print(f"reconcile: {to_midnight} s before 00:00 UTC; waiting for the next day")
                  time.sleep(to_midnight + 60)
              DAY = utc_today()
              NEXT_DAY = (datetime.date.fromisoformat(DAY) + datetime.timedelta(days=1)).isoformat()
              X0 = store.succeed("readlink -f /run/current-system").strip()
              X1 = store.succeed("readlink -f /run/current-system/sw").strip()
              assert X0 != X1, (X0, X1)
              assert int(store.succeed(f"grep -cE 'msg=\"batch built\"' {FIXTURE_LINES}").strip()) > 0
              assert int(store.succeed(f"grep -cE 'msg=\"batch done\".* landed=.* ejected=.* builds=.* flaky=' {FIXTURE_LINES}").strip()) > 0

              with subtest("devloop-reconcile passes after the overlap re-reads and a restarted attribute"):
                  fresh_leg()
                  nixbot_rows(
                      "INSERT INTO builds (id, project_id, number, commit_sha, branch, pr_number, status, created_at, started_at, finished_at) "
                      "OVERRIDING SYSTEM VALUE VALUES "
                      "(9201, 1, 9201, 'c9201', 'pr-9201', 9201, 'succeeded', now() - interval '3 minutes', now() - interval '2 minutes', now()), "
                      "(9202, 1, 9202, 'c9202', 'gitea-mq/batch/9202', NULL, 'succeeded', now() - interval '3 minutes', now() - interval '2 minutes', now())"
                  )
                  nixbot_rows(
                      "INSERT INTO build_attributes (build_id, attr, system, status, cached, started_at, finished_at) VALUES "
                      "(9201, 'checks.x86_64-linux.reconcile-pass', 'x86_64-linux', 'succeeded', false, now() - interval '1 minute', now()), "
                      "(9201, 'checks.x86_64-linux.reconcile-cached', 'x86_64-linux', 'skipped_local', true, NULL, now()), "
                      f"(9202, '{RESTARTED}', 'x86_64-linux', 'succeeded', false, now() - interval '1 minute', now())"
                  )
                  start_sources()
                  # A row younger than five minutes is re-read on every 60 s
                  # poll (design D6), so 190 s gives each new row three reads.
                  time.sleep(190)
                  settle()
                  for table in TABLES:
                      rows, keys = key_counts(table)
                      assert rows == keys, (table, rows, keys)
                  passes("after the overlap re-reads", *reconcile(DAY))
                  nixbot_rows(
                      "UPDATE build_attributes SET status = 'building', started_at = now(), finished_at = NULL "
                      f"WHERE build_id = 9202 AND attr = '{RESTARTED}'"
                  )
                  passes("an attribute restarted and not finished again", *reconcile(DAY))
                  nixbot_rows(
                      f"UPDATE build_attributes SET status = 'succeeded', finished_at = '{NEXT_DAY}T00:30:00Z' "
                      f"WHERE build_id = 9202 AND attr = '{RESTARTED}'"
                  )
                  retry(
                      lambda _last: gsql(f"SELECT count(*) FROM ci_attribute WHERE \"attr\" = '{RESTARTED}'")[0][0] == 2,
                      timeout=datetime.timedelta(minutes=3),
                  )
                  passes("the attribute finished again after the window", *reconcile(DAY))
                  assert WAITS["n"] == 0, WAITS

                  # C7's wait: a deploy whose record is not yet shipped when
                  # the run starts is shipped during the wait, and the run passes.
                  store.succeed("systemctl stop opentelemetry-collector.service")
                  activate(REAL_RECORD, X0)
                  since = store.succeed("date +%s").strip()

                  def ship_during_wait():
                      store.wait_until_succeeds(
                          f"journalctl --no-pager -o cat -u devloop-reconcile.service --since=@{since} | grep -qF '{WAITING}'",
                          timeout=120,
                      )
                      store.succeed("systemctl start opentelemetry-collector.service")

                  passes("a deploy record shipped during C7's wait", *reconcile(DAY, during=ship_during_wait))
                  assert WAITS["n"] >= 1, WAITS

              with subtest("each of D11's mutants fails devloop-reconcile naming its clause"):
                  # C1: an attribute query that omits cached = true rows.
                  fresh_leg()
                  start_sources(mutant="omitCached")
                  settle(touched=["ci_attribute"])
                  rejected("omitCached", ["C1 attributes"], *reconcile(DAY))

                  # C1: ci_attribute in append mode keeps the overlap's re-reads.
                  fresh_leg()
                  admin_sql('DROP TABLE "ci_attribute"')
                  admin_sql(store.succeed("cat /etc/devloop-ingest/mutants/append-mode-ci_attribute.sql"))
                  start_sources()
                  nixbot_rows(
                      "INSERT INTO build_attributes (build_id, attr, system, status, cached, finished_at) VALUES "
                      "(9201, 'checks.x86_64-linux.reconcile-append-1', 'x86_64-linux', 'succeeded', false, now()), "
                      "(9201, 'checks.x86_64-linux.reconcile-append-2', 'x86_64-linux', 'succeeded', false, now())"
                  )
                  retry(
                      lambda _last: key_counts("ci_attribute")[0] > key_counts("ci_attribute")[1],
                      timeout=datetime.timedelta(minutes=4),
                  )
                  settle(touched=["ci_attribute"])
                  rejected("appendModeAttribute", ["C1 attributes"], *reconcile(DAY))

                  # C2: a build query that omits rows with a null pr_number.
                  fresh_leg()
                  start_sources(mutant="omitNullPr")
                  settle(touched=["ci_build"])
                  rejected("omitNullPr", ["C2 builds"], *reconcile(DAY))

                  # C3: no key_value_parser, so no row carries msg, and none is batch built.
                  fresh_leg()
                  start_sources(mutant="noKeyValueParser")
                  settle(touched=["batch_event"])
                  rejected("noKeyValueParser", ["C3 batch-lines", "C4 batch-liveness"], *reconcile(DAY))

                  # C4: a stub gitea-mq printing nothing while batch builds exist.
                  batch_builds = int(psql(
                      "SELECT count(*) FROM builds WHERE starts_with(branch, 'gitea-mq/batch/') "
                      f"AND finished_at >= '{DAY}T00:00:00Z' AND finished_at < '{NEXT_DAY}T00:00:00Z'"
                  ).strip())
                  assert batch_builds > 0, batch_builds
                  fresh_leg(silent=True)
                  start_sources(silent=True)
                  settle(touched=["batch_event"])
                  rejected("silentStub", ["C4 batch-liveness"], *reconcile(DAY))

                  # C5: a devloop_batch_event pipeline that drops flaky.
                  fresh_leg()
                  store.succeed(
                      f"curl -sSf --netrc-file {VARS}/admin.netrc -X POST "
                      "'http://127.0.0.1:4000/v1/pipelines/devloop_batch_event?db=devloop' "
                      "-F file=@/etc/devloop-ingest/mutants/pipeline-without-flaky.yaml"
                  )
                  start_sources()
                  settle()
                  rejected("pipelineWithoutFlaky", ["C5 batch-fields"], *reconcile(DAY))

                  # C6: file_log/deploy-record reading another path; C7 then has
                  # no row, waits the full 120 s because the file's last line
                  # names the current system, and fails.
                  fresh_leg()
                  start_sources(mutant="deployRecordOtherPath")
                  settle(touched=["deploy_record"])
                  rejected("deployRecordOtherPath", ["C6 deploys", "C7 current-system"], *reconcile(DAY))
                  assert WAITS["n"] == 12, WAITS

                  # C7: a snippet writing the previous closure as closure; the
                  # file's last line then names another system, so no wait.
                  fresh_leg()
                  start_sources(record=SWAPPED_RECORD)
                  settle()
                  rejected("snippetSwapsClosures", ["C7 current-system"], *reconcile(DAY))
                  assert WAITS["n"] == 0, WAITS

              store.succeed(
                  f"rm -f {DAY_CONF}",
                  "systemctl daemon-reload",
                  f"ln -sfn {FIXTURE_LINES} {STUB_LINES}",
                  "systemctl restart gitea-mq.service",
              )
              reset_devloop()
              collector_restart()
              assert utc_today() == DAY, (DAY, utc_today())
              print("ok: reconcile")
            '';

            # The burn rule as fleet-alert's evaluator sends it (design D1,
            # D16); the notified units shape only SystemdUnitFailed.
            burnAlertRule =
              lib.findFirst (r: r.alert == "PullRequestQueueWaitBurn")
                (throw "devloop-ingest: no PullRequestQueueWaitBurn rule")
                (self.lib.fleetAlertRules {
                  inherit lib;
                  notifiedUnits = [ ];
                }).rules;
            burnRule = ''
              print("=== case burnRule", flush=True)
              import datetime

              BURN_EXPR = json.loads(${builtins.toJSON (builtins.toJSON burnAlertRule.expr)})
              BURN_DB = ${builtins.toJSON burnAlertRule.database}
              assert ${builtins.toJSON burnAlertRule.language} == "sql", "PullRequestQueueWaitBurn is not an SQL rule"
              assert BURN_DB == "devloop", BURN_DB

              # ci_build holds exactly the rows each load writes as admin.
              reset_devloop()
              store.succeed("systemctl stop opentelemetry-collector.service")
              BURN_NOW = int(store.succeed("date -u +%s").strip())


              def burn_time(epoch):
                  return datetime.datetime.fromtimestamp(epoch, datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


              def burn_row(build_id, pr_number, wait_minutes, finished_hours_ago=2):
                  """A build finished finished_hours_ago h ago, started 5 min before,
                  created wait_minutes before it started; None never started."""
                  finished = BURN_NOW - finished_hours_ago * 3600
                  if wait_minutes is None:
                      created, started, status = finished - 600, "NULL", "cancelled"
                  else:
                      started_at = finished - 300
                      created = started_at - wait_minutes * 60
                      started, status = "'" + burn_time(started_at) + "'", "success"
                  pr = "NULL" if pr_number is None else str(pr_number)
                  branch = "main" if pr_number is None else f"pr-{pr_number}"
                  return (
                      f"({build_id}, '{burn_time(created)}', {started}, '{burn_time(finished)}', "
                      f"1000, '{status}', {pr}, '{branch}')"
                  )


              def burn_prs(first, slow, fast):
                  """slow pull-request builds that waited 90 min, then fast ones that waited 45,
                  close enough to the hour that a 30 min threshold counts them as slow."""
                  return [burn_row(first + i, 100 + first + i, 90) for i in range(slow)] + [
                      burn_row(first + slow + i, 100 + first + slow + i, 45) for i in range(fast)
                  ]


              def burn_restarted(build_id, pr_number):
                  """A pull-request build restarted after a fast first attempt: nixbot's
                  restart keeps created_at and resets started_at and finished_at
                  (Mic92/nixbot@d020013fa nixbot/nixbot/db_gen/maintenance.py:96-123),
                  so the second row's wait is over an hour."""
                  created = BURN_NOW - 4 * 3600
                  branch = f"pr-{pr_number}"
                  return [
                      f"({build_id}, '{burn_time(created)}', '{burn_time(created + 600)}', "
                      f"'{burn_time(created + 900)}', 1000, 'failure', {pr_number}, '{branch}')",
                      f"({build_id}, '{burn_time(created)}', '{burn_time(created + 5400)}', "
                      f"'{burn_time(created + 5700)}', 1000, 'success', {pr_number}, '{branch}')",
                  ]


              def burn_load(rows):
                  admin_sql('TRUNCATE TABLE "ci_build"', db=BURN_DB)
                  admin_sql(
                      'INSERT INTO "ci_build" ("build_id", "created_at", "started_at", "finished_at", '
                      '"eval_duration_ms", "status", "pr_number", "branch") VALUES ' + ", ".join(rows),
                      db=BURN_DB,
                  )
                  stored = gsql('SELECT count(*) FROM "ci_build"', db=BURN_DB)
                  assert stored == [[len(rows)]], (stored, len(rows))


              def burn_mutant(name, old, new):
                  assert old in BURN_EXPR, f"mutant {name} found nothing to replace"
                  return BURN_EXPR.replace(old, new)


              BURN_MUTANTS = {
                  "noPullRequestFilter": burn_mutant("noPullRequestFilter", "c.pr_number IS NOT NULL AND ", ""),
                  "noStartedFilter": burn_mutant("noStartedFilter", "c.started_at IS NOT NULL AND ", ""),
                  "minimumNine": burn_mutant("minimumNine", "count(*) >= 10", "count(*) >= 9"),
                  "noWindow": burn_mutant("noWindow", " AND c.finished_at >= now() - INTERVAL '24 hours'", ""),
                  "shareAtLeastATenth": burn_mutant("shareAtLeastATenth", "* 10 > count(*)", "* 10 >= count(*)"),
                  "everyAttempt": burn_mutant("everyAttempt", " AND c.finished_at = f.first_finished", ""),
                  "thresholdHalfHour": burn_mutant("thresholdHalfHour", "INTERVAL '1 hour'", "INTERVAL '30 minutes'"),
              }


              def burn_mutants_reject(load, names):
                  for name in names:
                      got = gsql(BURN_MUTANTS[name], db=BURN_DB)
                      assert len(got) == 1, f"mutant {name} accepted on {load}: {got}"
                      print(f"mutant {name} rejected: {load} gave {got}", flush=True)


              # 10 pull-request builds of which 2 waited over an hour: one row, 0.2,
              # in a column named value, which the evaluator requires.
              burn_load(burn_prs(1, 2, 8))
              rows = gsql(BURN_EXPR, db=BURN_DB)
              print(f"load 1: 10 builds, 2 waited over an hour: {rows}", flush=True)
              assert len(rows) == 1 and abs(rows[0][0] - 0.2) < 1e-9, rows
              named = gsql(f'SELECT "value" FROM ({BURN_EXPR}) AS burn', db=BURN_DB)
              assert named == rows, (named, rows)

              # 9 of which 2 did, beside a slow build with no pull request and a
              # pull-request build that never started: no row.
              burn_load(burn_prs(11, 2, 7) + [burn_row(20, None, 90), burn_row(21, 121, None)])
              rows = gsql(BURN_EXPR, db=BURN_DB)
              print(f"load 2: 9 builds, 2 waited over an hour: {rows}", flush=True)
              assert rows == [], rows
              burn_mutants_reject("load 2", ["noPullRequestFilter", "noStartedFilter", "minimumNine"])

              # 10 of which 1 did, the tenth a build restarted after a fast first
              # attempt whose second attempt waited over an hour, beside a slow
              # pull-request build that finished 25 h ago: no row.
              burn_load(burn_prs(31, 1, 8) + burn_restarted(40, 140) + [burn_row(50, 150, 90, finished_hours_ago=25)])
              rows = gsql(BURN_EXPR, db=BURN_DB)
              print(f"load 3: 10 builds, 1 waited over an hour, 1 restarted: {rows}", flush=True)
              assert rows == [], rows
              burn_mutants_reject("load 3", ["noWindow", "shareAtLeastATenth", "everyAttempt", "thresholdHalfHour"])

              # Leave the store as every earlier case does: tables reset and the
              # collector running.
              reset_devloop()
              collector_restart()
              print("ok: burnRule", flush=True)
            '';

            cases = [
              firstStart
              noAutoCreate
              overlap
              tableShape
              switch
              documentedQueries
              reconcile
              burnRule
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
              let
                # The deploy-record snippet as the reconcile case runs it,
                # reading the previous closure from a scratch link that the
                # case relinks after each run, as activation relinks
                # /run/current-system after its snippets (design D9).
                deployRecord = self.lib.deployRecordScript {
                  inherit pkgs;
                  hostName = config.networking.hostName;
                  currentSystem = currentSystemLink;
                };
                # C7's mutant: the same snippet's line with closure and
                # previous_closure swapped, appended to the real file.
                mutantLine = self.lib.deployRecordScript {
                  inherit pkgs;
                  hostName = config.networking.hostName;
                  file = "/run/devloop-ingest/mutant-line.jsonl";
                  currentSystem = currentSystemLink;
                };
                snippetSwapsClosures = pkgs.writeShellScript "deploy-record-swapped" ''
                  set -euo pipefail
                  rm -f /run/devloop-ingest/mutant-line.jsonl
                  ${mutantLine} "$1"
                  line=$(cat /run/devloop-ingest/mutant-line.jsonl)
                  swapped=$(printf '%s\n' "$line" | ${pkgs.gnused}/bin/sed -E 's/"closure":"([^"]*)","previous_closure":"([^"]*)"/"closure":"\2","previous_closure":"\1"/')
                  if [ "$swapped" = "$line" ]; then
                    echo "snippetSwapsClosures: nothing swapped in $line" >&2
                    exit 1
                  fi
                  printf '%s\n' "$swapped" >> /var/log/deploy-record.jsonl
                '';
              in
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

                # Task 4's mutants rebuild these lists; they must equal the
                # configuration's when given the real values.
                assertions = [
                  {
                    assertion =
                      let
                        receivers = config.services.opentelemetry-collector.settings.receivers;
                      in
                      receivers."sqlquery/ci_attribute".queries == [
                        (queryElement "ci_attribute" devloop.queries.ci_attribute)
                      ]
                      && receivers."sqlquery/ci_build".queries == [ (queryElement "ci_build" devloop.queries.ci_build) ]
                      && receivers."journald/gitea-mq".operators == journaldOperators;
                    message = "devloop-ingest: queryElement or journaldOperators no longer rebuilds the collector's receiver lists, so a Task 4 mutant would change more than its clause";
                  }
                ];

                # The reconcile under test: devloop-collection's unit with
                # the container's credential and the scratch current-system
                # link; started by the case, never by its timer.
                systemd.services.devloop-reconcile.serviceConfig = {
                  LoadCredential = [ "regulator-password:${vars}/regulator-password" ];
                  ExecStart = lib.mkForce (
                    lib.getExe (
                      self.lib.devloopReconcile pkgs {
                        psql = lib.getExe' config.services.postgresql.package "psql";
                        journalctl = lib.getExe' config.systemd.package "journalctl";
                        hostName = config.networking.hostName;
                        currentSystem = currentSystemLink;
                      }
                    )
                  );
                };
                systemd.timers.devloop-reconcile.wantedBy = lib.mkForce [ ];

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
                  "devloop-ingest/deploy-record".source = deployRecord;
                  "devloop-ingest/mutants/snippet-swaps-closures".source = snippetSwapsClosures;
                  # C1's table mutant: ci_attribute in append mode.
                  "devloop-ingest/mutants/append-mode-ci_attribute.sql".text =
                    replaceOnce "appendModeAttribute" "'append_mode' = 'false'" "'append_mode' = 'true'"
                      devloop.ddl.ci_attribute;
                  # C5's pipeline mutant: devloop_batch_event without flaky.
                  "devloop-ingest/mutants/pipeline-without-flaky.yaml".text =
                    replaceOnce "pipelineWithoutFlaky"
                      "        .flaky = if a.flaky == null || a.flaky == \"\" { null } else { to_bool!(a.flaky) }\n"
                      ""
                      devloop.pipelines.batch_event;
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
