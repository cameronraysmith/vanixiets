# Helpers for vmTests.x86_64-linux.devloop-ingest (design D16). The test
# driver runs this file and then each case string of the `cases` list in
# modules/vm-tests/devloop-ingest.nix, in order. Every case prints
# `=== case <name>` first and `ok: <name>` last, prints
# `mutant <name> rejected: <reason>` for each mutant it shows rejected, and
# leaves the collector running with no mutant drop-in.
import datetime as dt
import json
import re
import shlex

COLLECTOR = "opentelemetry-collector"
DEPLOY_RECORD = "/var/log/deploy-record.jsonl"
_CONFIG = None


def config():
    """/etc/devloop-ingest/config.json, rendered by the container module."""
    global _CONFIG
    if _CONFIG is None:
        _CONFIG = json.loads(store.succeed("cat /etc/devloop-ingest/config.json"))
    return _CONFIG


def _sql(user, query, db):
    cmd = [
        "curl", "-sS", "-o", "/tmp/devloop-sql-response", "-w", "%{http_code}",
        "--netrc-file", f"{config()['vars']}/{user}.netrc",
        "--data-urlencode", f"sql={query}",
        f"http://127.0.0.1:4000/v1/sql?db={db}",
    ]
    status = int(store.succeed(shlex.join(cmd)))
    return status, store.succeed("cat /tmp/devloop-sql-response")


def _output(user, query, db):
    status, body = _sql(user, query, db)
    assert status == 200, (user, query, status, body)
    # A statement without rows answers {"affectedrows": n} instead of
    # {"records": ...} (GreptimeTeam/greptimedb@v1.2.1:src/servers/src/http.rs:395-400).
    output = json.loads(body)["output"][0]
    return output["records"]["rows"] if "records" in output else output["affectedrows"]


def gsql(query, db="devloop"):
    """A read as the store's `regulator` account; returns records.rows."""
    return _output("regulator", query, db)


def admin_sql(query, db="devloop"):
    """A statement as the store's `admin` account."""
    return _output("admin", query, db)


def psql(query, role="postgres"):
    """psql -XAt on nixbot as `postgres`, under SET ROLE for another role."""
    role_statement = [] if role == "postgres" else ["-c", f'SET ROLE "{role}"']
    cmd = [
        "runuser", "-u", "postgres", "--", config()["psql"],
        "-XAtq", "-v", "ON_ERROR_STOP=1", "-d", "nixbot", *role_statement, "-c", query,
    ]
    return store.succeed(shlex.join(cmd))


def nixbot_rows(sql):
    """Fixture inserts into nixbot's database as `postgres`."""
    return psql(sql)


def collector_restart(mutant=None):
    """Remove every mutant drop-in, install `mutant`'s when given, reload,
    restart each unit that had or gets a drop-in, then the collector, and
    wait until it serves its internal telemetry."""
    units = store.succeed(
        'for f in /run/systemd/system/*.service.d/zz-mutant.conf; do '
        '[ -e "$f" ] && basename "$(dirname "$f")" .service.d; done; true'
    ).split()
    store.succeed("rm -f /run/systemd/system/*.service.d/zz-mutant.conf")
    if mutant is not None:
        unit = store.succeed(f"cat /etc/devloop-ingest/mutants/{mutant}.unit").strip()
        store.succeed(
            f"install -D -m 0444 /etc/devloop-ingest/mutants/{mutant}.conf "
            f"/run/systemd/system/{unit}.service.d/zz-mutant.conf"
        )
        units.append(unit)
    store.succeed("systemctl daemon-reload")
    for unit in sorted(set(units) - {COLLECTOR}):
        store.succeed(f"systemctl restart {unit}.service")
    store.succeed(f"systemctl restart {COLLECTOR}.service")
    store.wait_for_unit(f"{COLLECTOR}.service")
    retry(
        lambda _last: store.execute("curl -sSf -o /dev/null http://localhost:8888/metrics")[0] == 0,
        timeout=dt.timedelta(minutes=2),
    )


def reset_devloop():
    """Stop the collector, delete its file_storage directory (cursors and
    queues), drop the four tables as admin, rerun the schema job and empty
    the deploy-record file. The journald receiver then re-reads the stub's
    journal from its beginning. The collector stays stopped."""
    store.succeed(
        f"systemctl stop {COLLECTOR}.service",
        "rm -rf /var/lib/opentelemetry-collector/queue",
    )
    for table in config()["tables"]:
        admin_sql(f'DROP TABLE IF EXISTS "{table}"')
    store.succeed(
        "systemctl restart greptimedb-schema.service",
        f": > {DEPLOY_RECORD}",
    )


def _otel_metric(name, label, value):
    """The sum of a counter over the series whose `label` equals `value`
    in the collector's internal telemetry; 0 when no series exists."""
    text = store.succeed("curl -sS http://localhost:8888/metrics")
    pattern = re.compile("^" + re.escape(name) + r"\{([^}]*)\} (\S+)$")
    total = 0.0
    for line in text.splitlines():
        match = pattern.match(line)
        if match and f'{label}="{value}"' in match.group(1):
            total += float(match.group(2))
    return int(total)


def send_failed(table):
    return _otel_metric(
        "otelcol_exporter_send_failed_log_records", "exporter", f"otlp_http/devloop_{table}"
    )


def _sent(table):
    return _otel_metric(
        "otelcol_exporter_sent_log_records", "exporter", f"otlp_http/devloop_{table}"
    )


def _count(table):
    status, body = _sql("regulator", f'SELECT count(*) FROM "{table}"', "devloop")
    if status != 200:
        return 0
    return json.loads(body)["output"][0]["records"]["rows"][0][0]


def wait_rows(table, n, timeout=240):
    """Wait until the table holds at least n rows; return its count."""
    retry(lambda _last: _count(table) >= n, timeout=dt.timedelta(seconds=timeout))
    return _count(table)


def key_counts(table):
    """(rows, distinct keys), a key being the primary key and the time index,
    the identity under which a non-append table keeps one row."""
    spec = config()["tables"][table]
    key = ", ".join(f'"{c}"' for c in spec["primaryKey"] + [spec["timeIndex"]])
    rows = gsql(f'SELECT count(*) FROM "{table}"')[0][0]
    distinct = gsql(f'SELECT count(*) FROM (SELECT DISTINCT {key} FROM "{table}") AS k')[0][0]
    return rows, distinct


def utc_today():
    """The container's UTC date. Within 10 minutes of 00:00 UTC it first
    waits until 5 s after midnight, so a case's fixture rows and any window
    a later case derives from this date fall in one UTC day."""
    now = int(store.succeed("date -u +%s").strip())
    into_day = now % 86400
    if into_day >= 86400 - 600:
        wait = 86400 - into_day + 5
        print(f"utc_today: {wait} s before 00:00 UTC; waiting for the next day")
        store.succeed(f"sleep {wait}")
    return store.succeed("date -u +%F").strip()
