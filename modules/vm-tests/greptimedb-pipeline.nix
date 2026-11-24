# Runtime pipeline test for the telemetry store and its collector
# (openspec/changes/stand-up-greptimedb-on-magnetite, design D13, tasks 6.1).
#
# What this establishes, in one systemd-nspawn container on a builder that
# advertises uid-range (pyrite or magnetite):
#   1. greptimedb-bin answers /health and serves its embedded dashboard at
#      /dashboard/ (R1.1's runtime side);
#   2. greptimedb-schema creates magnetite's databases with their TTLs, and a
#      re-run with a changed TTL changes the stored TTL (F1);
#   3. the users file written by magnetite's real greptimedb-users generator is
#      enforced: no or wrong credentials are 401, a write-only read and a
#      read-only write (perses and regulator) are 403, permitted calls are 200;
#   4. an OTLP point entering the agent pipeline crosses the forward and
#      routing connectors into `fleet` and no other database, and reads back
#      through PromQL with x-greptime-db-name carrying host_name;
#   5. the systemd receiver reaches D-Bus under DynamicUser, and an
#      omnigent-host-<owner> unit is stored only under its alias;
#   6. a point emitted while greptimedb.service is stopped reaches the store
#      once it starts again;
#   7. the hourly envelope's table clause, run as the regulator against this
#      store, fails on a table created with an undeclared ttl and on one
#      created with sst_format='primary_key' (R6.3), and passes once both
#      are dropped (review F8).
#   8. greptimedb-schema creates agent.session_event with its bloom
#      full-text index on prompt and response and uploads its pipeline,
#      whose dry run keeps a listed event's listed keys, nulls a value of
#      the wrong type and drops an unlisted event (agent-session-telemetry
#      design D5).
#
# What it does not establish: R2 storage (the S3 stanza is magnetite's host
# configuration; the store here uses its default File storage), the ZFS
# envelope, the OOM kill order (a container shares the build host's kernel;
# see greptimedb-oom-order), ntfy delivery, or anything about magnetite's
# deployed credentials. It lives in the non-gating vmTests lane: on-demand
# evidence, not pull-request coverage.
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
      # Size class: medium, by what the test waits on rather than by its
      # time (declare-test-size-classes, requirement "A size class
      # constrains what a test may wait on...", scenario "A small test
      # sleeps"). Its last leg, a point emitted while the store is stopped,
      # waits for the collector's otlphttp exporter to retry the send after
      # the store starts again (retry_on_failure: 5 s initial interval with
      # backoff, at most 60 s), and that retry is what the leg proves, so
      # the wait stays and the test may not be small. The script measured
      # 13 to 16 s on 2026-11-22
      # (logs/darwin-ast-vmtest-c0-greptimedb-pipeline-20261122-212504.log).
      testSizes.vmTests = lib.optionalAttrs (system == "x86_64-linux") {
        greptimedb-pipeline = {
          class = "medium";
          reason = "its store-restart leg waits on the collector exporter's retry interval, which is the behaviour it proves";
        };
      };
      vmTests = lib.optionalAttrs (system == "x86_64-linux") {
        greptimedb-pipeline =
          let
            # perSystem `pkgs` lacks the flake overlay that carries
            # greptimedb-bin and ntfy-send.
            nodePkgs = import inputs.nixpkgs {
              inherit system;
              config.allowUnfree = true;
              overlays = [ self.overlays.default ];
            };
            # Databases, TTLs and the users generator are read from the machine
            # that declares them, so an inventory change cannot drift past this
            # test silently.
            reference = self.nixosConfigurations.magnetite.config;
            inherit (reference.services.greptimedb) databases;
            usersGenerator = reference.clan.core.vars.generators.greptimedb-users;
            schema = self.lib.otelCollectorSchema;
            owner = lib.head (lib.attrNames schema.ownerAliases);
            alias = schema.ownerAliases.${owner};
            changedTtl = "7d";
            vars = "/run/greptimedb-test-vars";
            credentialConsumers = [
              "greptimedb.service"
              "greptimedb-schema.service"
              "opentelemetry-collector.service"
            ];
            pki = self.lib.otelTestPki pkgs;
          in
          assert lib.assertMsg (
            databases ? fleet && databases.fleet != changedTtl
          ) "greptimedb-pipeline: magnetite must declare fleet with a TTL other than ${changedTtl}";
          pkgs.testers.runNixOSTest {
            name = "greptimedb-pipeline";
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
                # The schema oneshot's command as it would be built with
                # fleet's TTL changed; installed at runtime as a drop-in,
                # because an nspawn node cannot switch to a specialisation.
                changedSchemaExecStart =
                  (extendModules {
                    modules = [ { services.greptimedb.databases.fleet = lib.mkForce changedTtl; } ];
                  }).config.systemd.services.greptimedb-schema.serviceConfig.ExecStart;

                # The hourly envelope's table clause (R6.3 and declared table
                # TTLs) as greptimedb-envelope.service runs it, with this
                # container's declared TTLs, reading as the regulator account.
                envelopeTables = pkgs.writeShellScriptBin "greptimedb-test-envelope-tables" ''
                  export CREDENTIALS_DIRECTORY=${vars}
                  export GREPTIMEDB_ENVELOPE_TABLE_TTLS_FILE=${config.systemd.services.greptimedb-envelope.environment.GREPTIMEDB_ENVELOPE_TABLE_TTLS_FILE}
                  exec ${
                    lib.getExe (
                      self.lib.greptimedbEnvelopeTables pkgs {
                        url = "http://${config.services.greptimedb.settings.http.addr}";
                        databases = lib.attrNames config.services.greptimedb.databases;
                      }
                    )
                  }
                '';
              in
              {
                imports = [
                  self.modules.nixos.greptimedb
                  self.modules.nixos.otel-collector-agent
                  self.modules.nixos.otel-collector-ingress
                ];
                system.stateVersion = lib.trivial.release;
                environment.systemPackages = [
                  pkgs.curl
                  envelopeTables
                ];

                services.greptimedb = {
                  enable = true;
                  inherit databases;
                  # agent.session_event and its pipeline as magnetite declares
                  # them (agent-session-telemetry design D5).
                  tables.agent = reference.services.greptimedb.tables.agent;
                  pipelines.agent = reference.services.greptimedb.pipelines.agent;
                };

                # Credentials come from magnetite's own generator script, run
                # at boot, so no credential value exists in the repository and
                # the users file has exactly the deployed shape. The netrc
                # files keep passwords out of the test driver's command log.
                systemd.services.greptimedb-test-vars = {
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
                    printf 'machine 127.0.0.1 login admin password %s\n' 0000 > ${vars}/wrong.netrc
                  '';
                };
                systemd.services.greptimedb.serviceConfig.LoadCredential = [ "users:${vars}/users" ];
                systemd.services.greptimedb-schema.serviceConfig.LoadCredential = [
                  "admin-password:${vars}/admin-password"
                ];
                systemd.services.opentelemetry-collector.serviceConfig.LoadCredential = [
                  "collector-password:${vars}/collector-password"
                  "otel-cert:${pki}/ingress.crt"
                  "otel-key:${pki}/ingress.key"
                ];

                # The ingress receivers on loopback (4322 is the test's own
                # otlp entry; 4321 is otlp/loopback, the agent-session
                # unit's hand-off) with throwaway certificates, never the real vars,
                # and the agent's notified-unit assertion satisfied; the
                # envelopes are fleet-ingress's subject, so their timers stay
                # off.
                vanixiets.otelCollector.caFile = "${pki}/ca.crt";
                # As on magnetite: the ingress routes agent events, so
                # logs/ingress exists, fed by the agent-session unit over
                # otlp/loopback; the unit loads the test's certificate as
                # the clan role loads otel-cert.
                vanixiets.otelCollector.agentTelemetry = true;
                services.opentelemetry-collector.settings.receivers."otlp/mesh".protocols.http.endpoint =
                  lib.mkForce "127.0.0.1:4319";
                services.opentelemetry-collector.settings.receivers."otlp/mesh-tincr".protocols.http.endpoint =
                  lib.mkForce "127.0.0.1:4320";
                services.observability-notify.units = [
                  "opentelemetry-collector"
                  "otel-envelope"
                  "otel-agent-session"
                  "otel-agent-session-envelope"
                ];
                systemd.timers.otel-envelope.wantedBy = lib.mkForce [ ];
                systemd.timers.otel-agent-session-envelope.wantedBy = lib.mkForce [ ];
                systemd.services.otel-agent-session.serviceConfig.LoadCredential = [
                  "otel-cert:${pki}/ingress.crt"
                  "otel-key:${pki}/ingress.key"
                ];

                # A loopback OTLP entry into the agent pipeline that stamps
                # host.name and vanixiets.database, so a synthetic point takes
                # the same forward and routing path as host metrics.
                services.opentelemetry-collector.settings = {
                  receivers.otlp.protocols.http.endpoint = "127.0.0.1:4322";
                  service.pipelines."metrics/host".receivers = [ "otlp" ];
                };

                # An owner-named unit inside the allow-list pattern; only its
                # alias may reach the store.
                systemd.services."omnigent-host-${owner}" = {
                  description = "Stand-in for an Omnigent host unit named by its owner";
                  wantedBy = [ "multi-user.target" ];
                  serviceConfig.ExecStart = "${pkgs.coreutils}/bin/sleep infinity";
                };

                environment.etc."greptimedb-test/schema-changed-ttl.conf".text = ''
                  [Service]
                  ExecStart=
                  ${lib.concatMapStringsSep "\n" (command: "ExecStart=${command}") (
                    lib.toList changedSchemaExecStart
                  )}
                '';
              };
            testScript = ''
              import datetime as dt
              import json
              import re
              import shlex

              VARS = "${vars}"
              DATABASES = json.loads(${builtins.toJSON (builtins.toJSON databases)})
              CHANGED_TTL = "${changedTtl}"
              OWNER = "${owner}"
              ALIAS_UNIT = "omnigent-host-${alias}.service"
              DROP_IN = "/run/systemd/system/greptimedb-schema.service.d/zz-changed-ttl.conf"


              def request(path, netrc=None, db=None, params=()):
                  cmd = ["curl", "-sS", "-o", "/tmp/response", "-w", "%{http_code}", "--get"]
                  if netrc is not None:
                      cmd += ["--netrc-file", f"{VARS}/{netrc}.netrc"]
                  if db is not None:
                      cmd += ["-H", f"x-greptime-db-name: {db}"]
                  for key, value in params:
                      cmd += ["--data-urlencode", f"{key}={value}"]
                  cmd.append(f"http://127.0.0.1:4000{path}")
                  status = int(store.succeed(shlex.join(cmd)))
                  return status, store.succeed("cat /tmp/response")


              def sql_status(user, db, statement):
                  return request("/v1/sql", netrc=user, db=db, params=[("sql", statement)])[0]


              def sql(db, statement, user="admin"):
                  status, body = request("/v1/sql", netrc=user, db=db, params=[("sql", statement)])
                  assert status == 200, (statement, status, body)
                  # A statement without rows (DDL, DML) answers {"affectedrows": n}
                  # instead of {"records": ...} (src/servers/src/http.rs:395-400 at v1.2.1).
                  output = json.loads(body)["output"][0]
                  return output["records"]["rows"] if "records" in output else output["affectedrows"]


              def promql_status(query, db="fleet"):
                  status, body = request(
                      "/v1/prometheus/api/v1/query", netrc="perses", db=db, params=[("query", query)]
                  )
                  result = json.loads(body)["data"]["result"] if status == 200 else []
                  return status, result


              def promql(query, db="fleet"):
                  status, result = promql_status(query, db)
                  assert status == 200, (query, status)
                  return result


              def ttl(db):
                  rows = sql("public", f"SHOW CREATE DATABASE {db}")
                  match = re.search(r"ttl = '([^']+)'", rows[0][1])
                  assert match is not None, (db, rows)
                  return match.group(1)


              def emit(probe):
                  now = store.succeed("date +%s%N").strip()
                  point = {
                      "asDouble": 1.0,
                      "timeUnixNano": now,
                      "attributes": [{"key": "probe", "value": {"stringValue": probe}}],
                  }
                  metric = {"name": "s1_probe", "gauge": {"dataPoints": [point]}}
                  scope = {"scope": {"name": "greptimedb-pipeline"}, "metrics": [metric]}
                  payload = json.dumps(
                      {"resourceMetrics": [{"resource": {"attributes": []}, "scopeMetrics": [scope]}]}
                  )
                  store.succeed(
                      "curl -sSf -H 'Content-Type: application/json' "
                      f"--data {shlex.quote(payload)} http://127.0.0.1:4322/v1/metrics"
                  )


              def restart_probe_count():
                  status, body = request(
                      "/v1/sql",
                      netrc="admin",
                      db="fleet",
                      params=[("sql", "SELECT count(*) FROM s1_probe WHERE probe = 'restart'")],
                  )
                  if status != 200:
                      return 0
                  return json.loads(body)["output"][0]["records"]["rows"][0][0]


              start_all()
              store.wait_for_unit("greptimedb.service")
              store.wait_until_succeeds(
                  "curl -sf http://127.0.0.1:4000/health", timeout=dt.timedelta(minutes=2)
              )
              store.wait_for_unit("greptimedb-schema.service")
              store.wait_for_unit("opentelemetry-collector.service")
              hostname = store.succeed("hostname").strip()

              with subtest("the store answers /health and serves its embedded dashboard"):
                  status, _ = request("/health")
                  assert status == 200, status
                  status, body = request("/dashboard/")
                  assert status == 200, status
                  assert "<html" in body.lower(), body[:200]

              with subtest("the schema oneshot creates each database with its TTL"):
                  for db, want in DATABASES.items():
                      sql("public", f"CREATE DATABASE IF NOT EXISTS ttl_reference_{db} WITH (ttl = '{want}')")
                      assert ttl(db) == ttl(f"ttl_reference_{db}"), (db, ttl(db), want)

              # agent-session-telemetry design D5: the schema job's table and
              # pipeline, read back as the regulator and run through the
              # store's own dry run (src/servers/src/http/event.rs:603-690 at
              # v1.2.1) with records shaped as the OTLP logs handler hands them
              # to a pipeline (src/servers/src/otlp/logs.rs:142-197).
              with subtest("the schema oneshot creates agent.session_event with its index, and its pipeline keeps only listed events and keys"):
                  create = sql("agent", "SHOW CREATE TABLE session_event", user="regulator")[0][1]
                  print(create)
                  for column in ("prompt", "response"):
                      assert re.search(
                          rf"\"{column}\" STRING NULL FULLTEXT INDEX WITH\(analyzer = 'English', backend = 'bloom', case_sensitive = 'false'",
                          create,
                      ), (column, create)
                  assert "append_mode = 'false'" in create and "sst_format = 'flat'" in create, create
                  # SHOW CREATE TABLE renders the database's ttl into the
                  # table's WITH; create_options lists only the table's own
                  # options, as greptimedb-envelope's table clause reads them.
                  options = sql("agent", "SELECT create_options FROM information_schema.tables WHERE table_schema = 'agent' AND table_name = 'session_event'", user="regulator")[0][0]
                  print(f"create_options: {options}")
                  assert "ttl" not in options, options
                  assert 'PRIMARY KEY ("host_name", "session_id", "event_sequence")' in create, create
                  ns = 1_800_000_000_000_000_000
                  resource = {"service.name": "claude-code", "host.name": "store-probe", "user.name": "cameron", "user.email": "canary-email@example.com"}
                  records = [
                      {"Timestamp": ns, "ResourceAttributes": resource, "Body": "canary-body", "LogAttributes": {
                          "event.name": "user_prompt", "event.sequence": 1, "session.id": "s1", "prompt": "canary admitted prompt",
                          "prompt_text": "canary admitted prompt", "prompt_length": 22, "user.email": "canary-email@example.com"}},
                      {"Timestamp": ns + 1, "ResourceAttributes": resource, "LogAttributes": {
                          "event.name": "api_request_body", "event.sequence": 2, "session.id": "s1", "body": "canary-raw"}},
                      {"Timestamp": ns + 2, "ResourceAttributes": resource, "LogAttributes": {
                          "event.name": "tool_result", "event.sequence": 3, "session.id": "s1", "tool_name": "Bash",
                          "success": "true", "duration_ms": "12", "error_type": 5, "tool_output": "canary-output"}},
                  ]
                  payload = json.dumps({"pipeline_name": "agent_session_event", "data": json.dumps(records)})
                  store.succeed(f"cat > /tmp/dryrun.json <<'EOF'\n{payload}\nEOF")
                  status = store.succeed(
                      f"curl -sS -o /tmp/dryrun-answer -w '%{{http_code}}' --netrc-file {VARS}/admin.netrc "
                      "-H 'Content-Type: application/json' --data @/tmp/dryrun.json "
                      "'http://127.0.0.1:4000/v1/pipelines/_dryrun?db=agent'"
                  ).strip()
                  answer = store.succeed("cat /tmp/dryrun-answer")
                  print(f"dry run: {status} {answer}")
                  assert status == "200", (status, answer)
                  [result] = json.loads(answer)
                  table_columns = [row[0] for row in sql("agent", "SELECT column_name FROM information_schema.columns WHERE table_schema = 'agent' AND table_name = 'session_event' ORDER BY column_name", user="regulator")]
                  pipeline_columns = sorted(column["name"] for column in result["schema"])
                  assert pipeline_columns == table_columns, (pipeline_columns, table_columns)
                  rows = [{cell["key"]: cell["value"] for cell in row} for row in result["rows"]]
                  assert [row["event_name"] for row in rows] == ["user_prompt", "tool_result"], rows
                  prompt, tool = rows
                  assert prompt["prompt"] == "canary admitted prompt" and prompt["user_name"] == "cameron", prompt
                  assert prompt["host_name"] == "store-probe" and prompt["event_sequence"] == 1, prompt
                  assert tool["duration_ms"] == 12 and tool["success"] is True and tool["error_type"] is None, tool
                  assert "canary-" not in json.dumps(rows).replace("canary admitted prompt", ""), rows

              with subtest("a re-run with a changed TTL alters the stored TTL"):
                  sql(
                      "public",
                      f"CREATE DATABASE IF NOT EXISTS ttl_reference_changed WITH (ttl = '{CHANGED_TTL}')",
                  )
                  store.succeed(
                      f"install -D -m 0444 /etc/greptimedb-test/schema-changed-ttl.conf {DROP_IN}",
                      "systemctl daemon-reload",
                      "systemctl restart greptimedb-schema.service",
                  )
                  assert ttl("fleet") == ttl("ttl_reference_changed"), ttl("fleet")
                  assert ttl("fleet") != ttl("ttl_reference_fleet"), ttl("fleet")
                  for db in DATABASES:
                      if db != "fleet":
                          assert ttl(db) == ttl(f"ttl_reference_{db}"), (db, ttl(db))
                  store.succeed(f"rm {DROP_IN}", "systemctl daemon-reload")

              with subtest("the users file is enforced per role"):
                  read = "SHOW TABLES"

                  def create(user):
                      return f"CREATE TABLE IF NOT EXISTS auth_{user} (ts TIMESTAMP TIME INDEX)"

                  assert request("/v1/sql", db="public", params=[("sql", read)])[0] == 401
                  assert sql_status("wrong", "public", read) == 401
                  assert sql_status("admin", "public", read) == 200
                  assert sql_status("admin", "public", create("admin")) == 200
                  assert sql_status("perses", "public", read) == 200
                  assert sql_status("perses", "public", create("perses")) == 403
                  assert sql_status("regulator", "public", read) == 200
                  assert sql_status("regulator", "public", create("regulator")) == 403
                  assert sql_status("collector", "public", read) == 403
                  assert sql_status("collector", "public", create("collector")) == 200

              with subtest("an OTLP point is routed into fleet and read back through PromQL"):
                  emit("ingest")
                  retry(
                      lambda _last: len(promql_status('s1_probe{probe="ingest"}')[1]) > 0,
                      timeout=dt.timedelta(minutes=3),
                  )
                  series = promql('s1_probe{probe="ingest"}')
                  assert series[0]["metric"]["host_name"] == hostname, series
                  for db in DATABASES:
                      if db != "fleet":
                          tables = [row[0] for row in sql(db, "SHOW TABLES")]
                          assert "s1_probe" not in tables, (db, tables)

              with subtest("the envelope's table clause fails on an undeclared table TTL and on the legacy format"):

                  def envelope_tables():
                      return store.execute("greptimedb-test-envelope-tables 2>&1")

                  def passes(stage):
                      code, output = envelope_tables()
                      assert code == 0 and "FAIL" not in output, (stage, code, output)

                  def fails_with(stage, line):
                      code, output = envelope_tables()
                      print(f"{stage}: exit {code}: {output.strip()}")
                      assert code == 1, (stage, code, output)
                      fails = [l for l in output.splitlines() if l.startswith("FAIL ")]
                      assert len(fails) == 1 and fails[0].startswith(line), (stage, output)

                  passes("before the controls")
                  sql("fleet", "CREATE TABLE s1_ttl_control (ts TIMESTAMP TIME INDEX, v DOUBLE) WITH (ttl = '1d')")
                  fails_with("undeclared ttl", "FAIL TTL: fleet.s1_ttl_control sets ttl=")
                  sql("fleet", "DROP TABLE s1_ttl_control")
                  sql(
                      "fleet",
                      "CREATE TABLE s1_format_control (ts TIMESTAMP TIME INDEX, v DOUBLE) WITH (sst_format = 'primary_key')",
                  )
                  fails_with(
                      "legacy format",
                      "FAIL R6.3: fleet.s1_format_control uses the legacy sst_format=primary_key",
                  )
                  sql("fleet", "DROP TABLE s1_format_control")
                  passes("after both controls are dropped")

              with subtest("the systemd receiver stores unit state under DynamicUser, owners only as aliases"):
                  dynamic = store.succeed("systemctl show -P DynamicUser opentelemetry-collector.service")
                  assert dynamic.strip() == "yes", dynamic
                  # The receiver scrapes once when the collector starts and
                  # then every 60 s; with the unit active before a restart,
                  # that first scrape stores it, so the case waits for the
                  # event rather than for the next tick of the interval
                  # (declare-test-size-classes design D14).
                  store.wait_for_unit(f"omnigent-host-{OWNER}.service")
                  store.succeed("systemctl restart opentelemetry-collector.service")
                  store.wait_for_unit("opentelemetry-collector.service")
                  unit_query = f'systemd_unit_state{{host_name="{hostname}",systemd_unit_name="{ALIAS_UNIT}"}}'
                  retry(
                      lambda _last: len(promql_status(unit_query)[1]) > 0,
                      timeout=dt.timedelta(minutes=5),
                  )
                  states = promql(unit_query)
                  assert any(state["value"][1] == "1" for state in states), states
                  names = [row[0] for row in sql("fleet", "SELECT DISTINCT systemd_unit_name FROM systemd_unit_state")]
                  assert ALIAS_UNIT in names, names
                  assert not any(OWNER in name for name in names), names

              with subtest("a point emitted while the store is stopped arrives after it starts"):
                  store.succeed("systemctl stop greptimedb.service")
                  store.fail("curl -sf http://127.0.0.1:4000/health")
                  emit("restart")
                  store.succeed("systemctl start greptimedb.service")
                  store.wait_until_succeeds(
                      "curl -sf http://127.0.0.1:4000/health", timeout=dt.timedelta(minutes=2)
                  )
                  retry(lambda _last: restart_probe_count() >= 1, timeout=dt.timedelta(minutes=5))
            '';
          };
      };
    };
}
