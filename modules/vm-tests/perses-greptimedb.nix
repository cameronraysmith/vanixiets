# Runtime test of the dashboard service's read path (CAM-73 design D12).
#
# One systemd-nspawn container on a builder that advertises uid-range
# (magnetite) runs GreptimeDB with magnetite's databases, devloop tables and
# store accounts, Perses from flake.modules.nixos.perses, and nginx with the
# module's vhost on plain HTTP. No Kanidm runs, so the test replaces the
# providers with native login and adds a test-only provisioning folder
# (perses-greptimedb/) holding one native User and greptimedb-sql-open, the
# SQL datasource without allowHeaders. The module's assertion is held to
# exactly the serving-predicate failures those overrides explain (native
# login, no OIDC provider, no TLS), so every other clause holds here as on
# magnetite.
#
# What it establishes: an unauthenticated request is refused; the
# provisioned user logs in; the provisioned set is exactly the committed
# dashboards after a planted view and a restart; dashboard writes are
# refused; PromQL and SQL reads through the two datasources return data and
# a caller's database header is overwritten; every committed view's query
# succeeds and each PromQL query returns series, while a view with one
# query naming an absent series fails that case; an INSERT through the SQL
# datasource is refused by the store; the four out-of-pattern routes, sent
# as written, are refused by Perses before any request is made; a caller's
# x-greptime-auth carrying the admin credential reaches the store as perses
# through nginx and sent directly to Perses, and as admin through
# greptimedb-sql-open sent directly (the negative control), so allowHeaders
# is what protects the store from a caller that bypasses nginx and the
# strip works on its own; /metrics is 404 through nginx and 200 directly.
#
# What it does not establish: Kanidm's refusal and admission, TLS and ACME,
# R2 storage, OOM behaviour (a container shares the host's kernel), or that
# a chart renders the values it reads. It lives in the non-gating vmTests
# lane: on-demand evidence, not pull-request coverage.
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
        perses-greptimedb =
          let
            nodePkgs = import inputs.nixpkgs {
              inherit system;
              config.allowUnfree = true;
              overlays = [ self.overlays.default ];
            };
            reference = self.nixosConfigurations.magnetite.config;
            inherit (reference.services.greptimedb) databases;
            usersGenerator = reference.clan.core.vars.generators.greptimedb-users;
            referenceClient = reference.services.kanidm.provision.systems.oauth2.perses;
            schema = self.lib.otelCollectorSchema;
            vars = "/run/perses-test-vars";
            domain = "obs.scientistexperience.net";
            resourcesDir = ../nixos/perses/resources;
            testFolder = builtins.path {
              path = ./perses-greptimedb;
              name = "perses-test-provisioning";
            };
            readJSON = dir: name: lib.importJSON (dir + "/${name}");
            dashboards = lib.genAttrs [ "fleet-hosts" "devloop" ] (
              name: readJSON resourcesDir "dashboard-${name}.json"
            );
            committedSql = readJSON resourcesDir "globaldatasource-sql.json";
            openSql = readJSON ./perses-greptimedb "globaldatasource-sql-open.json";
            # Kanidm is absent, so its client is copied from magnetite for the
            # predicate's client clauses.
            client = {
              inherit (referenceClient)
                displayName
                originUrl
                originLanding
                preferShortUsername
                scopeMaps
                ;
            };
            credentialConsumers = [
              "greptimedb.service"
              "greptimedb-schema.service"
              "perses.service"
            ];
            json2pb =
              pkgs.writers.writePython3Bin "otlp-json-to-pb"
                {
                  libraries = [ pkgs.python3Packages.opentelemetry-proto ];
                }
                ''
                  import sys

                  from google.protobuf import json_format
                  from opentelemetry.proto.collector.metrics.v1 import metrics_service_pb2

                  request = metrics_service_pb2.ExportMetricsServiceRequest()
                  json_format.Parse(sys.stdin.read(), request)
                  sys.stdout.buffer.write(request.SerializeToString())
                '';
          in
          # The bypass control's datasource is the committed SQL datasource
          # without allowHeaders under another name, and nothing else.
          assert lib.assertMsg
            (
              openSql == lib.updateManyAttrsByPath [
                {
                  path = [
                    "metadata"
                    "name"
                  ];
                  update = _: "greptimedb-sql-open";
                }
                {
                  path = [
                    "spec"
                    "plugin"
                    "spec"
                    "proxy"
                    "spec"
                  ];
                  update = s: removeAttrs s [ "allowHeaders" ];
                }
              ] committedSql
            )
            "perses-greptimedb: globaldatasource-sql-open.json must be globaldatasource-sql.json without allowHeaders, named greptimedb-sql-open";
          pkgs.testers.runNixOSTest {
            name = "perses-greptimedb";
            requiredFeatures = {
              nixos-test = true;
              uid-range = true;
            };
            node.pkgs = lib.mkForce nodePkgs;
            containers.machine =
              { pkgs, ... }:
              {
                imports = [
                  self.modules.nixos.greptimedb
                  self.modules.nixos.perses
                ];
                system.stateVersion = lib.trivial.release;
                environment.systemPackages = [
                  pkgs.curl
                  pkgs.jq
                  json2pb
                ];

                services.greptimedb = {
                  enable = true;
                  inherit databases;
                  tables.devloop = reference.services.greptimedb.tables.devloop;
                };

                # Credentials from magnetite's own users generator script, run
                # at boot, and a fixed-length throwaway encryption key; the
                # netrc files keep passwords out of the driver's command log.
                systemd.services.perses-test-vars = {
                  description = "Test credentials for the store and Perses";
                  requiredBy = credentialConsumers;
                  before = credentialConsumers;
                  path = [
                    pkgs.bash
                    pkgs.coreutils
                    pkgs.openssl
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
                    printf '%s' "$(openssl rand -hex 16)" > ${vars}/encryption-key
                  '';
                };
                systemd.services.greptimedb.serviceConfig.LoadCredential = [ "users:${vars}/users" ];
                systemd.services.greptimedb-schema.serviceConfig.LoadCredential = [
                  "admin-password:${vars}/admin-password"
                ];
                systemd.services.perses.serviceConfig.LoadCredential = [
                  "encryption-key:${vars}/encryption-key"
                  "perses-password:${vars}/perses-password"
                ];

                services.perses.settings = {
                  security.authentication.providers = lib.mkForce {
                    enable_native = true;
                    oidc = [ ];
                  };
                  provisioning.folders = [ "${testFolder}" ];
                };
                services.kanidm.provision.systems.oauth2.perses = client;

                services.nginx = {
                  enable = true;
                  recommendedProxySettings = true;
                  virtualHosts.${domain} = {
                    forceSSL = lib.mkForce false;
                    enableACME = lib.mkForce false;
                  };
                };

                vanixiets.perses.acceptedServingFailures = [
                  "2: native login must be disabled"
                  "3: exactly one OIDC provider must be configured"
                  "9: the vhost must set forceSSL and enableACME"
                ];
              };
            testScript = ''
              import copy
              import datetime as dt
              import json
              import shlex

              VARS = "${vars}"
              DOMAIN = "${domain}"
              PROMOTE = "${lib.concatStringsSep ";" schema.promotedResourceAttributes}"
              DASHBOARDS = json.loads(${builtins.toJSON (builtins.toJSON dashboards)})
              USER = json.loads(${builtins.toJSON (builtins.toJSON (readJSON ./perses-greptimedb "user-tester.json"))})
              LOGIN = USER["metadata"]["name"]
              PASSWORD = USER["spec"]["nativeProvider"]["password"]
              NGINX = "http://127.0.0.1"
              DIRECT = "http://127.0.0.1:8095"
              REFUSED = "you are not allowed to use this endpoint"
              # The store's PermissionDenied (GreptimeTeam/greptimedb@v1.2.1:
              # src/auth/src/error.rs:86-90), so a refusal is the store's own.
              NOT_AUTHORIZED = "User is not authorized to perform this action"
              ADMIN_AUTH = (
                  '-H "x-greptime-auth: Basic $(printf \'admin:%s\' "$(cat ${vars}/admin-password)" | base64 -w0)"'
              )

              cookie = ""


              def ok(message):
                  print(f"ok: {message}")


              def curl(url, *args, base=NGINX, auth=True, raw=""):
                  """Run curl in the container; return (status, body)."""
                  cmd = ["curl", "-sS", "--path-as-is", "-o", "/tmp/response", "-w", "%{http_code}"]
                  if base == NGINX:
                      cmd += ["-H", f"Host: {DOMAIN}"]
                  if auth and cookie:
                      cmd += ["-H", f"Cookie: {cookie}"]
                  cmd += list(args)
                  cmd.append(base + url)
                  line = shlex.join(cmd) + (" " + raw if raw else "")
                  status = int(machine.succeed(line))
                  return status, machine.succeed("cat /tmp/response")


              def login():
                  global cookie
                  body = json.dumps({"login": LOGIN, "password": PASSWORD})
                  status = machine.succeed(
                      "curl -sS -o /dev/null -w '%{http_code}' -c /tmp/jar -H 'Content-Type: application/json' "
                      f"--data {shlex.quote(body)} {DIRECT}/api/auth/providers/native/login"
                  )
                  assert status == "200", status
                  pairs = []
                  for line in machine.succeed("cat /tmp/jar").splitlines():
                      fields = line.split("\t")
                      if len(fields) == 7 and (not line.startswith("#") or line.startswith("#HttpOnly_")):
                          pairs.append(f"{fields[5]}={fields[6]}")
                  assert pairs, "no session cookie"
                  cookie = "; ".join(pairs)


              def dashboards():
                  status, body = curl("/api/v1/projects/fleet/dashboards")
                  assert status == 200, (status, body)
                  return sorted(d["metadata"]["name"] for d in json.loads(body))


              def promql(path, query, base=NGINX, extra=()):
                  now = int(machine.succeed("date +%s"))
                  return curl(
                      f"/proxy/globaldatasources/greptimedb-promql{path}",
                      "--data-urlencode", f"query={query}",
                      "--data-urlencode", f"start={now - 900}",
                      "--data-urlencode", f"end={now}",
                      "--data-urlencode", "step=60",
                      *extra,
                      base=base,
                  )


              def sql(statement, datasource="greptimedb-sql", base=NGINX, raw=""):
                  return curl(
                      f"/proxy/globaldatasources/{datasource}/v1/sql",
                      "--data-urlencode", f"sql={statement}",
                      base=base,
                      raw=raw,
                  )


              def store_user(datasource, base, raw=""):
                  status, body = sql('SELECT current_user() AS "u"', datasource, base, raw)
                  assert status == 200, (datasource, base, status, body)
                  return json.loads(body)["output"][0]["records"]["rows"][0][0]


              def store_sql(statement, db, netrc="admin"):
                  out = machine.succeed(
                      f"curl -sS --fail-with-body --netrc-file {VARS}/{netrc}.netrc "
                      f"-H 'x-greptime-db-name: {db}' --data-urlencode {shlex.quote('sql=' + statement)} "
                      "http://127.0.0.1:4000/v1/sql"
                  )
                  return json.loads(out)["output"][0]


              def views_failures(views):
                  """Every committed query through its datasource; the failures."""
                  now_ms = int(machine.succeed("date +%s").strip()) * 1000
                  failures = []
                  for view in views.values():
                      for panel_name, panel in view["spec"]["panels"].items():
                          for query in panel["spec"]["queries"]:
                              plugin = query["spec"]["plugin"]
                              spec = plugin["spec"]
                              text = spec["query"].replace("$host_name", ".*")
                              text = text.replace("$__from", str(now_ms - 30 * 86400 * 1000))
                              text = text.replace("$__to", str(now_ms + 86400 * 1000))
                              name = spec["datasource"]["name"]
                              if plugin["kind"] == "PrometheusTimeSeriesQuery":
                                  status, body = curl(
                                      f"/proxy/globaldatasources/{name}/api/v1/query",
                                      "--data-urlencode", f"query={text}",
                                  )
                                  good = (
                                      status == 200
                                      and json.loads(body).get("status") == "success"
                                      and len(json.loads(body)["data"]["result"]) > 0
                                  )
                              else:
                                  status, body = curl(
                                      f"/proxy/globaldatasources/{name}/v1/sql",
                                      "--data-urlencode", f"sql={text}",
                                  )
                                  good = status == 200 and len(json.loads(body)["output"][0]["records"]["rows"]) > 0
                              if not good:
                                  failures.append((view["metadata"]["name"], panel_name, text, status, body[:300]))
                  return failures


              def emit_fleet(host):
                  """OTLP gauges for every series the fleet-hosts view reads, written as collector."""
                  now = int(machine.succeed("date +%s").strip())
                  times = [now - 840 + 30 * i for i in range(29)]

                  def attrs(pairs):
                      return [{"key": k, "value": {"stringValue": v}} for k, v in pairs.items()]

                  def metric(name, points):
                      return {"name": name, "gauge": {"dataPoints": points}}

                  def series(value, labels=None):
                      return [
                          {"asDouble": float(value(i)), "timeUnixNano": str(t * 1_000_000_000), "attributes": attrs(labels or {})}
                          for i, t in enumerate(times)
                      ]

                  def resource(extra, metrics):
                      return {
                          "resource": {"attributes": attrs({"host.name": host, **extra})},
                          "scopeMetrics": [{"scope": {"name": "perses-greptimedb"}, "metrics": metrics}],
                      }

                  host_metrics = [
                      metric("system_memory_usage_bytes", series(lambda i: 4e9, {"state": "used"}) + series(lambda i: 2e9, {"state": "free"})),
                      metric("system_linux_memory_available_bytes", series(lambda i: 8e9)),
                      metric("system_paging_usage_bytes", series(lambda i: 1e8, {"state": "used"}) + series(lambda i: 9e8, {"state": "free"})),
                      metric("node_vmstat_oom_kill", series(lambda i: i)),
                      metric(
                          "system_filesystem_usage_bytes",
                          series(lambda i: 5e9, {"mountpoint": "/", "state": "used"})
                          + series(lambda i: 5e9, {"mountpoint": "/", "state": "free"}),
                      ),
                      metric(
                          "node_zfs_zpool_state",
                          series(lambda i: 1, {"zpool": "zroot", "state": "online"})
                          + series(lambda i: 0, {"zpool": "zroot", "state": "degraded"}),
                      ),
                      metric("node_zfs_arc_size", series(lambda i: 3e9)),
                      metric("node_zfs_arc_c_min", series(lambda i: 1e9)),
                      metric("node_zfs_arc_c_max", series(lambda i: 8e9)),
                      metric("node_zfs_arc_hits", series(lambda i: 1000 * i)),
                      metric("node_zfs_arc_misses", series(lambda i: 10 * i)),
                      metric("up", series(lambda i: 1, {"job": "node"}) + series(lambda i: 1, {"job": "smartctl"})),
                      metric("smartctl_device_critical_warning_total", series(lambda i: 0, {"device": "nvme0"})),
                      metric("smartctl_device_percentage_used_total", series(lambda i: 3, {"device": "nvme0"})),
                  ]
                  payload = {
                      "resourceMetrics": [
                          resource({}, host_metrics),
                          resource({"process.executable.name": "greptime"}, [metric("process_memory_usage_bytes", series(lambda i: 2e8))]),
                          resource({"process.executable.name": "perses"}, [metric("process_memory_usage_bytes", series(lambda i: 7e7))]),
                          resource(
                              {"systemd.unit.name": "demo-failed.service"},
                              [
                                  metric(
                                      "systemd_unit_state",
                                      series(lambda i: 1, {"systemd_unit_active_state": "failed"})
                                      + series(lambda i: 0, {"systemd_unit_active_state": "active"}),
                                  )
                              ],
                          ),
                          resource({"systemd.unit.name": "demo.service"}, [metric("systemd_service_restarts_total", series(lambda i: i))]),
                      ]
                  }
                  machine.succeed(f"cat > /tmp/fleet.json <<'EOF'\n{json.dumps(payload)}\nEOF")
                  machine.succeed(
                      "otlp-json-to-pb < /tmp/fleet.json > /tmp/fleet.pb && "
                      f"curl -sS --fail-with-body --netrc-file {VARS}/collector.netrc "
                      "-H 'Content-Type: application/x-protobuf' -H 'x-greptime-db-name: fleet' "
                      f"-H {shlex.quote('x-greptime-otlp-metric-promote-resource-attrs: ' + PROMOTE)} "
                      "--data-binary @/tmp/fleet.pb http://127.0.0.1:4000/v1/otlp/v1/metrics"
                  )


              def emit_devloop(host):
                  """Rows into each devloop table the devloop view reads, written as collector."""
                  now = dt.datetime.fromtimestamp(int(machine.succeed("date +%s").strip()), dt.timezone.utc)

                  def at(hours):
                      return (now - dt.timedelta(hours=hours)).strftime("'%Y-%m-%d %H:%M:%S'")

                  statements = [
                      'INSERT INTO "ci_build" ("build_id", "created_at", "started_at", "finished_at", "status", "pr_number", "branch") VALUES '
                      f"(1, {at(3)}, {at(2.9)}, {at(2)}, 'succeeded', 10, 'pr-10'), (2, {at(2)}, {at(1.9)}, {at(1)}, 'failed', 11, 'pr-11')",
                      'INSERT INTO "batch_event" ("batch", "msg", "ts") VALUES '
                      f"(1, 'batch formed', {at(3)}), (1, 'batch done', {at(2)})",
                      'INSERT INTO "ci_attribute" ("build_id", "attr", "status", "finished_at") VALUES '
                      f"(1, 'checks.x', 'succeeded', {at(2)}), (2, 'checks.y', 'failed', {at(1)})",
                      'INSERT INTO "deploy_record" ("host", "closure", "previous_closure", "ts") VALUES '
                      f"('{host}', 'closure-b', 'closure-a', {at(1)})",
                  ]
                  for statement in statements:
                      store_sql(statement, "devloop", netrc="collector")


              start_all()
              machine.wait_for_unit("greptimedb.service")
              machine.wait_until_succeeds(
                  "curl -sf http://127.0.0.1:4000/health", timeout=dt.timedelta(minutes=2)
              )
              machine.wait_for_unit("greptimedb-schema.service")
              machine.wait_for_unit("perses.service")
              machine.wait_for_unit("nginx.service")
              machine.wait_until_succeeds(
                  f"[ \"$(curl -s -o /dev/null -w '%{{http_code}}' {DIRECT}/api/v1/projects)\" = 401 ]",
                  timeout=dt.timedelta(minutes=3),
              )
              host = machine.succeed("hostname").strip()
              emit_fleet(host)
              emit_devloop(host)
              machine.wait_until_succeeds(
                  f"curl -sf --netrc-file {VARS}/perses.netrc -H 'x-greptime-db-name: fleet' "
                  "--data-urlencode 'query=system_memory_usage_bytes' "
                  "http://127.0.0.1:4000/v1/prometheus/api/v1/query | jq -e '.data.result | length > 0'",
                  timeout=dt.timedelta(minutes=2),
              )

              with subtest("1: a request without a session is refused"):
                  status, _ = curl("/api/v1/projects", auth=False)
                  assert status == 401, status
                  ok("GET /api/v1/projects without a session answers 401")

              with subtest("2: the provisioned user logs in"):
                  login()
                  ok("native login as the provisioned user answers 200")

              with subtest("3: the provisioned set is exactly the committed views"):
                  retry(lambda _last: dashboards() == ["devloop", "fleet-hosts"], timeout=dt.timedelta(minutes=1))
                  ok(f"fleet lists {dashboards()}")

              with subtest("4: a view planted in the database is gone after a restart"):
                  planted = copy.deepcopy(DASHBOARDS["devloop"])
                  planted["metadata"]["name"] = "planted"
                  machine.succeed(
                      "install -d /var/lib/perses/db/dashboards/fleet && "
                      f"cat > /var/lib/perses/db/dashboards/fleet/planted.json <<'EOF'\n{json.dumps(planted)}\nEOF"
                  )
                  machine.succeed("chown -R --reference=/var/lib/perses/db /var/lib/perses/db/dashboards")
                  assert "planted" in dashboards(), dashboards()
                  ok("the planted view is listed before the restart")
                  machine.succeed("systemctl restart perses.service")
                  machine.wait_for_unit("perses.service")
                  machine.wait_until_succeeds(
                      f"[ \"$(curl -s -o /dev/null -w '%{{http_code}}' {DIRECT}/api/v1/projects)\" = 401 ]",
                      timeout=dt.timedelta(minutes=3),
                  )
                  login()
                  retry(lambda _last: dashboards() == ["devloop", "fleet-hosts"], timeout=dt.timedelta(minutes=1))
                  ok(f"after the restart fleet lists {dashboards()}")

              with subtest("5: dashboard writes are refused"):
                  body = shlex.quote(json.dumps(DASHBOARDS["fleet-hosts"]))
                  for method, path in [
                      ("POST", "/api/v1/projects/fleet/dashboards"),
                      ("PUT", "/api/v1/projects/fleet/dashboards/fleet-hosts"),
                      ("DELETE", "/api/v1/projects/fleet/dashboards/fleet-hosts"),
                  ]:
                      status, text = curl(path, "-X", method, "-H", "Content-Type: application/json", raw=f"--data {body}" if method != "DELETE" else "")
                      assert status in (404, 405), (method, status, text)
                      ok(f"{method} {path} answers {status}")
                  assert dashboards() == ["devloop", "fleet-hosts"], dashboards()
                  ok("the provisioned set is unchanged")

              with subtest("6: PromQL reads through greptimedb-promql"):
                  status, body = promql("/api/v1/query_range", "system_memory_usage_bytes")
                  result = json.loads(body)["data"]["result"]
                  assert status == 200 and result and all(s["metric"].get("host_name") == host for s in result), (status, body)
                  ok(f"query_range returns {len(result)} series with host_name {host}")
                  # GreptimeDB answers label values only with match[], which the
                  # view's variable sends from its matchers.
                  status, body = curl(
                      "/proxy/globaldatasources/greptimedb-promql/api/v1/label/host_name/values",
                      "--get",
                      "--data-urlencode", "match[]=system_memory_usage_bytes",
                  )
                  assert status == 200 and host in json.loads(body)["data"], (status, body)
                  ok(f"label values of host_name over system_memory_usage_bytes include {host}")

              with subtest("7: a caller's database header is overwritten"):
                  status, body = promql("/api/v1/query_range", "system_memory_usage_bytes", extra=("-H", "x-greptime-db-name: devloop"))
                  result = json.loads(body)["data"]["result"]
                  assert status == 200 and result, (status, body)
                  ok("with x-greptime-db-name: devloop the query still returns the fleet series")

              with subtest("8: SQL reads through greptimedb-sql, and the store refuses an INSERT"):
                  count = 'SELECT count(*) FROM "devloop"."ci_build"'
                  status, body = sql(count)
                  assert status == 200 and json.loads(body)["output"][0]["records"]["rows"][0][0] == 2, (status, body)
                  ok("a qualified devloop count returns the 2 rows written")
                  insert = 'INSERT INTO "devloop"."ci_build" ("build_id", "finished_at") VALUES (99, now())'
                  refused, body = sql(insert)
                  assert refused == 403 and NOT_AUTHORIZED in body, (refused, body)
                  print(f"INSERT through greptimedb-sql: {refused} {body.strip()}")
                  status, body = sql(count)
                  assert json.loads(body)["output"][0]["records"]["rows"][0][0] == 2, body
                  ok(f"the store refuses the INSERT with {refused} and the count is unchanged")

              with subtest("9: routes outside the anchored patterns are refused by Perses"):
                  for path in [
                      "/api/v1/admin/tsdb/delete_series",
                      "/api/v1/query/../../../../v1/sql",
                      "/x/api/v1/query",
                      "/api/v1/admin/tsdb/delete_series/api/v1/series",
                  ]:
                      status, body = curl(
                          f"/proxy/globaldatasources/greptimedb-promql{path}",
                          "--data-urlencode", "match[]=system_memory_usage_bytes",
                          "--data-urlencode", "sql=SELECT 1",
                      )
                      assert status == 403 and REFUSED in body, (path, status, body)
                      ok(f"POST {path} answers 403 from Perses' endpoint check, before any request to the store")
                  status, body = promql("/api/v1/query", "system_memory_usage_bytes")
                  assert status == 200 and json.loads(body)["data"]["result"], body
                  ok("the fleet series are still stored")

              with subtest("10, 11: a caller's x-greptime-auth reaches the store as perses"):
                  assert store_user("greptimedb-sql", NGINX) == "perses"
                  for base, where in [(NGINX, "through nginx"), (DIRECT, "sent directly to Perses")]:
                      user = store_user("greptimedb-sql", base, ADMIN_AUTH)
                      assert user == "perses", (where, user)
                      ok(f"with the admin x-greptime-auth {where}, greptimedb-sql reaches the store as {user}")
                      status, body = sql('INSERT INTO "devloop"."ci_build" ("build_id", "finished_at") VALUES (98, now())', base=base, raw=ADMIN_AUTH)
                      assert status == 403 and NOT_AUTHORIZED in body, (where, status, body)
                      ok(f"an INSERT with the admin x-greptime-auth {where} is refused by the store with {status}")

              with subtest("12: negative control: without allowHeaders the bypass reaches the store as admin"):
                  user = store_user("greptimedb-sql-open", DIRECT, ADMIN_AUTH)
                  assert user == "admin", user
                  ok("bypass reached the store as admin")
                  user = store_user("greptimedb-sql-open", NGINX, ADMIN_AUTH)
                  assert user == "perses", user
                  ok("through nginx the same request reaches the store as perses: the strip works on its own")

              with subtest("13: /metrics is hidden at the vhost"):
                  status, _ = curl("/metrics", auth=False)
                  assert status == 404, status
                  status, _ = curl("/metrics", auth=False, base=DIRECT)
                  assert status == 200, status
                  ok("/metrics answers 404 through nginx and 200 directly")

              with subtest("14: every committed view's query succeeds"):
                  failures = views_failures(DASHBOARDS)
                  assert failures == [], json.dumps(failures, indent=1)
                  count = sum(len(p["spec"]["queries"]) for v in DASHBOARDS.values() for p in v["spec"]["panels"].values())
                  ok(f"all {count} committed queries succeed, and every PromQL query returns series")
                  mutant = copy.deepcopy(DASHBOARDS)
                  first = mutant["fleet-hosts"]["spec"]["panels"]["memory"]["spec"]["queries"][0]
                  first["spec"]["plugin"]["spec"]["query"] = "system_memory_usage_bytes_nope"
                  failures = views_failures({"fleet-hosts": mutant["fleet-hosts"]})
                  assert len(failures) == 1 and failures[0][2] == "system_memory_usage_bytes_nope", failures
                  ok("views case rejects the mutant view query")
            '';
          };
      };
    };
}
