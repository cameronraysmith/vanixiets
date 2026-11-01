"""Loopback stand-in for a collector's telemetry endpoint and a scrape target.

checks.x86_64-linux.otel-envelope runs otel-envelope against this stub
(design D7). On 127.0.0.1:$STUB_PORT it serves GET /metrics from the file
named in $STUB_FIXTURE, re-read on each request, as Prometheus text; /ok
with 200; /slow with 200 after 15 s, longer than the script's 10 s probe
limit; anything else with 404. A closed port stands for a stopped
exporter, so the check stops the stub instead of serving an error.

With $STUB_STORE set it also answers POST /v1/sql as GreptimeDB 1.2.1's
HTTP API does, one records result, for each query of the budget clauses B1
to B6: within every limit for host electrum, whose notifier instance is
otel-envelope's and whose fleet ttl is 30d, except that `breach` puts B1
over its limit. Any other statement is a 400.
"""

import json
import os
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs

# (fragment of the statement, rows), first match wins: the unit query's
# `NOT LIKE` before the notifier query's `LIKE`.
ANSWERS = [
    ("count(DISTINCT __tsid)", lambda store: [[100000 if store == "breach" else 100]]),
    ("semantic_type = 'TAG'", lambda store: [["host_name"]]),
    ('SELECT count(DISTINCT "host_name")', lambda store: [[3]]),
    ("count(DISTINCT process_executable_name)", lambda store: [["electrum", 5]]),
    ("NOT LIKE 'observability-notify@%'", lambda store: [["electrum", 5]]),
    ("column_name = 'launchd_label'", lambda store: [[0]]),
    (
        "LIKE 'observability-notify@%'",
        lambda store: [["electrum", "observability-notify@otel-envelope.service.service"]],
    ),
    ("FROM devloop.", lambda store: [[0]]),
    ("information_schema.schemata", lambda store: [["fleet", "'ttl'='30d'\n"]]),
]


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == "/metrics":
            with open(os.environ["STUB_FIXTURE"], "rb") as f:
                self.answer(200, f.read(), "text/plain; version=0.0.4")
        elif self.path == "/ok":
            self.answer(200, b"ok\n")
        elif self.path == "/slow":
            time.sleep(15)
            self.answer(200, b"slow\n")
        else:
            self.answer(404, b"not found\n")

    def do_POST(self):
        store = os.environ.get("STUB_STORE")
        length = int(self.headers.get("Content-Length", 0))
        sql = parse_qs(self.rfile.read(length).decode()).get("sql", [""])[0]
        if store and self.path == "/v1/sql":
            for fragment, rows in ANSWERS:
                if fragment in sql:
                    body = {"output": [{"records": {"schema": {}, "rows": rows(store)}}]}
                    self.answer(200, json.dumps(body).encode(), "application/json")
                    return
        body = {"code": 4001, "error": f"the stub has no answer for: {sql}"}
        self.answer(400, json.dumps(body).encode(), "application/json")

    def answer(self, status, body, content_type="text/plain"):
        try:
            self.send_response(status)
            self.send_header("Content-Type", content_type)
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
        except (BrokenPipeError, ConnectionResetError):
            # The client gave up first, as the script does on /slow.
            pass

    def log_message(self, format, *args):
        pass


ThreadingHTTPServer.daemon_threads = True
ThreadingHTTPServer(("127.0.0.1", int(os.environ["STUB_PORT"])), Handler).serve_forever()
