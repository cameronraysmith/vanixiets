# Helpers for vmTests.x86_64-linux.fleet-ingress (design D12). The test
# driver runs this file and then each case string of the `cases` list in
# modules/vm-tests/fleet-ingress.nix, in order. Every case prints
# `=== case <name>` first and `ok: <name>` last, and leaves every unit
# running with no mutant drop-in.
import datetime as dt
import json
import re
import shlex
import time

INGRESS = "opentelemetry-collector"
AGENT = "agent-collector"
INGRESS_PORT = 8888
AGENT_PORT = 8889
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
        wait_telemetry(INGRESS_PORT if unit == INGRESS else AGENT_PORT)
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
    store.wait_until_succeeds("bash -c 'echo > /dev/tcp/127.0.0.1/4318'", timeout=60)
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


start_all()
store.wait_for_unit("multi-user.target")
