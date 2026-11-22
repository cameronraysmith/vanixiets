# Helpers for vmTests.x86_64-linux.fleet-ingress (design D12). The test
# driver runs this file and then each case string of the `cases` list in
# modules/vm-tests/fleet-ingress.nix, in order. Every case prints
# `=== case <name>` first and `ok: <name>` last, and leaves every unit
# running with no mutant drop-in.
import base64
import datetime as dt
import hashlib
import json
import os
import re
import shlex
import time

INGRESS = "opentelemetry-collector"
AGENT = "agent-collector"
INGRESS_PORT = 8888
AGENT_PORT = 8889
SESSION = "otel-agent-session"
SESSION_PORT = 8890
CONFIG = None


def config():
    """/etc/fleet-ingress/config.json, rendered by the container module."""
    global CONFIG
    if CONFIG is None:
        CONFIG = json.loads(store.succeed("cat /etc/fleet-ingress/config.json"))
    return CONFIG


def _request(path, db, params):
    cmd = [
        "curl", "-sS", "-o", "/tmp/fleet-ingress-response", "-w", "%{http_code}", "--get",
        "--netrc-file", f"{config()['vars']}/regulator.netrc",
        "-H", f"x-greptime-db-name: {db}",
    ]
    for key, value in params:
        cmd += ["--data-urlencode", f"{key}={value}"]
    cmd.append(f"http://127.0.0.1:4000{path}")
    status = int(store.succeed(shlex.join(cmd)))
    return status, store.succeed("cat /tmp/fleet-ingress-response")


def gsql(sql, db="fleet"):
    """A read as the store's `regulator` account; returns records.rows."""
    status, body = _request("/v1/sql", db, [("sql", sql)])
    assert status == 200, (sql, status, body)
    return json.loads(body)["output"][0]["records"]["rows"]


def promql(expr, db="fleet"):
    """An instant PromQL query as `regulator`; returns data.result."""
    status, body = _request("/v1/prometheus/api/v1/query", db, [("query", expr)])
    assert status == 200, (expr, status, body)
    return json.loads(body)["data"]["result"]


def nonce_hits(*nonces):
    """Every string and JSON column of every table of every database, read
    as `regulator`: `<db>.<table>.<column>` -> rows whose value holds any of
    the nonces. A JSON column is read through json_to_string, since a cast
    of its binary value is refused."""
    columns = gsql(
        "SELECT table_schema, table_name, column_name, lower(data_type) FROM information_schema.columns "
        "WHERE lower(data_type) IN ('string', 'json') AND table_schema NOT IN ('information_schema', 'greptime_private', 'pg_catalog')",
        "agent",
    )
    hits = {}
    for schema, table, column, kind in columns:
        value = f'json_to_string("{column}")' if kind == "json" else f'"{column}"'
        held = " OR ".join(f"{value} LIKE '%{nonce}%'" for nonce in nonces)
        count = gsql(f"SELECT count(*) FROM \"{schema}\".\"{table}\" WHERE {held}", schema)[0][0]
        if count:
            hits[f"{schema}.{table}.{column}"] = count
    tables = {(schema, table) for schema, table, _, _ in columns}
    print(f"  scanned {len(columns)} string and JSON columns of {len(tables)} tables; nonce found in {hits}", flush=True)
    return hits


def metric(port, name_regex, labels=None):
    """The sum over the series of a collector's telemetry endpoint whose name
    matches name_regex and whose labels include every `labels` pair; 0 when
    none exists or the endpoint does not answer."""
    code, text = store.execute(f"curl -sS --max-time 10 http://127.0.0.1:{port}/metrics")
    if code != 0:
        return 0
    pattern = re.compile(r"^(" + name_regex + r")\{([^}]*)\} (\S+)$")
    total = 0.0
    for line in text.splitlines():
        match = pattern.match(line)
        if match and all(f'{k}="{v}"' in match.group(2) for k, v in (labels or {}).items()):
            total += float(match.group(3))
    return int(total)


def send_failed():
    """Every exporter's send_failed on both collectors."""
    return {
        port: metric(port, r"otelcol_exporter_send_failed_[a-z_]+")
        for port in (INGRESS_PORT, AGENT_PORT)
    }


def agent_sent():
    return metric(AGENT_PORT, "otelcol_exporter_sent_metric_points", {"exporter": "otlp_http/ingress"})


def mesh_accepted():
    return metric(INGRESS_PORT, "otelcol_receiver_accepted_metric_points", {"receiver": "otlp/mesh"})


def stable_pair():
    """The agent's sent and the ingress's accepted totals on otlp/mesh, read
    while the agent sends nothing in between."""
    while True:
        before = agent_sent()
        accepted = mesh_accepted()
        if agent_sent() == before:
            return before, accepted
        time.sleep(1)


def agent_queue():
    return metric(AGENT_PORT, "otelcol_exporter_queue_size", {"exporter": "otlp_http/ingress"})


def envelope(unit):
    """Start the envelope unit once; return its exit code and the
    `otel-envelope:` lines of that run."""
    store.execute(f"systemctl start {unit}.service")
    code = int(store.succeed(f"systemctl show -p ExecMainStatus --value {unit}.service"))
    invocation = store.succeed(f"systemctl show -p InvocationID --value {unit}.service").strip()
    lines = [
        line
        for line in store.succeed(f"journalctl _SYSTEMD_INVOCATION_ID={invocation} -o cat").splitlines()
        if line.startswith("otel-envelope:")
    ]
    for line in lines:
        print(f"  {unit}: {line}", flush=True)
    print(f"  {unit}: exit {code}", flush=True)
    return code, lines


def failing(lines):
    """The clauses a run failed, e.g. ["C1 telemetry"]."""
    return [m.group(1) for m in (re.match(r"otel-envelope: (C[1-4] [a-z]+): FAIL", l) for l in lines) if m]


def wait_telemetry(port, timeout=120):
    store.wait_until_succeeds(
        f"curl -sSf -o /dev/null http://127.0.0.1:{port}/metrics", timeout=timeout
    )


def collector_with(unit, mutant, wait=True):
    """Install /etc/fleet-ingress/mutants/<mutant>.conf as the unit's
    zz-mutant.conf drop-in, or remove it when mutant is None; reload and
    restart, then wait for the unit's telemetry; with wait False the start
    may fail, as a mutant meant to fail it does."""
    drop_in = f"/run/systemd/system/{unit}.service.d/zz-mutant.conf"
    if mutant is None:
        store.succeed(f"rm -f {drop_in}")
    else:
        store.succeed(f"install -D -m 0444 /etc/fleet-ingress/mutants/{mutant}.conf {drop_in}")
    store.succeed("systemctl daemon-reload")
    if wait:
        store.succeed(f"systemctl restart {unit}.service")
        wait_telemetry({INGRESS: INGRESS_PORT, AGENT: AGENT_PORT, SESSION: SESSION_PORT}[unit])
    else:
        store.execute(f"systemctl restart {unit}.service")


def wait_drained(timeout=600):
    """Wait until the agent's metrics queue is empty."""
    store.wait_until_succeeds(
        "test \"$(curl -sS http://127.0.0.1:%d/metrics | "
        "grep -E '^otelcol_exporter_queue_size\\{[^}]*exporter=\"otlp_http/ingress\"' | "
        "awk '{ s += $2 } END { print s + 0 }')\" = 0" % AGENT_PORT,
        timeout=timeout,
    )


def fresh_start():
    """The store, its schema job and both collectors running with no mutant
    drop-in, freshly started; each collector's first send succeeds and no
    exporter has a send_failed (S1-R6)."""
    store.succeed(
        f"rm -f /run/systemd/system/{INGRESS}.service.d/zz-mutant.conf "
        f"/run/systemd/system/{AGENT}.service.d/zz-mutant.conf",
        "systemctl daemon-reload",
        "systemctl start greptimedb.service prometheus-node-exporter.service",
    )
    store.wait_until_succeeds("curl -sf http://127.0.0.1:4000/health", timeout=120)
    store.succeed(f"systemctl restart greptimedb-schema.service {INGRESS}.service")
    wait_telemetry(INGRESS_PORT)
    store.wait_until_succeeds("bash -c 'echo > /dev/tcp/127.0.0.1/4319'", timeout=60)
    store.succeed(f"systemctl restart {AGENT}.service")
    wait_telemetry(AGENT_PORT)
    wait_for(lambda: agent_sent() > 0, "the agent's first send", 180)
    wait_for(
        lambda: metric(INGRESS_PORT, "otelcol_exporter_sent_metric_points", {"exporter": "otlp_http/fleet"}) > 0,
        "the ingress's first send to the store",
        180,
    )
    failed = send_failed()
    assert failed == {INGRESS_PORT: 0, AGENT_PORT: 0}, failed
    print(f"  fresh start: send_failed {failed}", flush=True)


def wait_for(predicate, what, timeout):
    """Poll predicate every 5 s until it holds, failing after timeout s."""
    deadline = time.monotonic() + timeout
    while not predicate():
        assert time.monotonic() < deadline, f"timed out after {timeout} s waiting for {what}"
        time.sleep(5)


# Langfuse Cloud's stand-in (agent-session-telemetry design D16).
def sink_mode(mode):
    """Set the sink's answer: ok, 403, 429 or 413."""
    store.succeed(f"printf %s {mode} > {config()['sinkDir']}/mode")


def sink_records(marker=None):
    """The sink's recorded requests, those whose text holds marker if given."""
    code, text = store.execute(f"cat {config()['sinkDir']}/requests.jsonl")
    if code != 0:
        return []
    return [json.loads(line) for line in text.splitlines() if line.strip() and (marker is None or marker in line)]


def sink_spans(records):
    """{span id (hex): (resource attributes, span attributes, span)} over
    the records' decoded requests; AnyValues as MessageToDict renders them."""
    spans = {}
    for record in records:
        for rs in record["request"].get("resourceSpans", []):
            resource = {a["key"]: a.get("value", {}) for a in rs.get("resource", {}).get("attributes", [])}
            for ss in rs.get("scopeSpans", []):
                for span in ss.get("spans", []):
                    attributes = {a["key"]: a.get("value", {}) for a in span.get("attributes", [])}
                    spans[base64.b64decode(span["spanId"]).hex()] = (resource, attributes, span)
    return spans


def langfuse_basic():
    """The Basic credential of the test's Langfuse key pair."""
    public = store.succeed(f"cat {config()['vars']}/langfuse-public-key")
    secret = store.succeed(f"cat {config()['vars']}/langfuse-secret-key")
    return "Basic " + base64.b64encode(f"{public}:{secret}".encode()).decode()


start_all()
store.wait_for_unit("multi-user.target")
