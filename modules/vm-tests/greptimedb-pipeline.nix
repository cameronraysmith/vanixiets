# Runtime pipeline test for the telemetry store and its collector
# (openspec/changes/stand-up-greptimedb-on-magnetite, design D13, tasks 6.1).
#
# What this establishes, in one systemd-nspawn container on a builder that
# advertises uid-range (magnetite):
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
#      once it starts again.
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
              in
              {
                imports = [
                  self.modules.nixos.greptimedb
                  self.modules.nixos.otel-collector-agent
                  self.modules.nixos.otel-collector-ingress
                ];
                system.stateVersion = lib.trivial.release;
                environment.systemPackages = [ pkgs.curl ];

                services.greptimedb = {
                  enable = true;
                  inherit databases;
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
                ];

                # A loopback OTLP entry into the agent pipeline that stamps
                # host.name and vanixiets.database, so a synthetic point takes
                # the same forward and routing path as host metrics.
                services.opentelemetry-collector.settings = {
                  receivers.otlp.protocols.http.endpoint = "127.0.0.1:4318";
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
                      f"--data {shlex.quote(payload)} http://127.0.0.1:4318/v1/metrics"
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

              with subtest("the systemd receiver stores unit state under DynamicUser, owners only as aliases"):
                  dynamic = store.succeed("systemctl show -P DynamicUser opentelemetry-collector.service")
                  assert dynamic.strip() == "yes", dynamic
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
