"""Loopback stand-in for GreptimeDB's PromQL instant-query and SQL APIs.

checks.x86_64-linux.fleet-alert runs the evaluator against this server
(S3 design D19, S2 design D17; fleet-alerting-interface "The evaluator
queries each rule's database as the regulators' store account"). It serves
GET and POST /v1/prometheus/api/v1/query, the query in `query` and the
database in the `x-greptime-db-name` header, and GET and POST /v1/sql, the
query in `sql` and the database in `db` (GreptimeTeam/greptimedb@v1.2.1
src/servers/src/http/handler.rs:118-140), from responses[<step>][<query>],
where <step> is the content of --step-file, read per request. A PromQL
answer is a Prometheus JSON body. An SQL answer is {"records": {"schema":
..., "rows": ...}}, replayed as {"output": [{"records": ...}],
"execution_time_ms": 0} (src/servers/src/http/result/
greptime_result_v1.rs:29-38, src/servers/src/http.rs:291-338, 395-400).
{"status": <code>} is an error on either path. --databases maps each query
to the database its rule declares.

Every request on either path is recorded as REQUEST <step> <path>
<database or -> <query> before it is judged. It answers 404 to any other
path, 401 to any account but `regulator` with the fixture password, and
400 to a query sent to a database other than its own. A query with no
declared database, no answer, or an answer of the other path's kind gets
500 and an UNEXPECTED line. If two connections are ever open at once it
prints a VIOLATION line and exits 1, so a leg fails if the evaluator
queries concurrently (S3 design D13). Everything it records is a line on
stdout: REQUEST, UNEXPECTED, VIOLATION.
"""

import argparse
import base64
import binascii
import json
import os
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlsplit

PROMQL_PATH = "/v1/prometheus/api/v1/query"
SQL_PATH = "/v1/sql"
FIXTURE_USER = "regulator"
# The same value checks.x86_64-linux.fleet-alert writes to the fixture
# credentials' regulator-password.
FIXTURE_PASSWORD = "00112233445566778899aabbccddeeff"


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--responses", required=True)
    parser.add_argument("--databases", required=True)
    parser.add_argument("--step-file", required=True)
    parser.add_argument("--port-file", required=True)
    args = parser.parse_args()
    with open(args.responses) as f:
        responses = json.load(f)
    with open(args.databases) as f:
        databases = json.load(f)

    lock = threading.Lock()
    connections = {"open": 0}

    def record(line):
        print(line, flush=True)

    class Server(ThreadingHTTPServer):
        daemon_threads = True

        # Counted from accept, so a client holding a connection without
        # sending counts as one open request.
        def process_request(self, request, client_address):
            with lock:
                connections["open"] += 1
                if connections["open"] > 1:
                    record("VIOLATION two requests open at once")
                    os._exit(1)
            super().process_request(request, client_address)

    class Handler(BaseHTTPRequestHandler):
        def setup(self):
            super().setup()
            self.counted = True

        # Released before the answer is sent, so the evaluator's next query,
        # which starts only after it has read this answer, never overlaps.
        def release(self):
            if self.counted:
                self.counted = False
                with lock:
                    connections["open"] -= 1

        def finish(self):
            try:
                super().finish()
            finally:
                self.release()

        def reply(self, code, body):
            data = json.dumps(body).encode()
            self.release()
            self.send_response(code)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)

        def credentials(self):
            auth = self.headers.get("Authorization", "")
            if not auth.startswith("Basic "):
                return None
            try:
                user, _, password = base64.b64decode(auth[6:]).decode().partition(":")
            except (binascii.Error, UnicodeDecodeError):
                return None
            return user, password

        def answer(self):
            url = urlsplit(self.path)
            form = parse_qs(url.query)
            if self.command == "POST":
                length = int(self.headers.get("Content-Length") or 0)
                form.update(parse_qs(self.rfile.read(length).decode()))
            if url.path == PROMQL_PATH:
                query = form.get("query", [""])[0]
                database = self.headers.get("x-greptime-db-name")
            elif url.path == SQL_PATH:
                query = form.get("sql", [""])[0]
                database = form.get("db", [None])[0]
            else:
                return self.reply(404, {"status": "error", "error": "not found"})
            with open(args.step_file) as f:
                step = f.read().strip()
            record(f"REQUEST {step} {url.path} {database or '-'} {query}")
            if self.credentials() != (FIXTURE_USER, FIXTURE_PASSWORD):
                return self.reply(401, {"status": "error", "error": "unauthorized"})
            declared = databases.get(query)
            if declared is None:
                record(f"UNEXPECTED {step} {query}")
                return self.reply(500, {"status": "error", "error": "no database is declared for this query"})
            if database != declared:
                return self.reply(400, {"status": "error", "error": f"this query belongs to {declared}"})
            body = responses.get(step, {}).get(query)
            if body is None:
                record(f"UNEXPECTED {step} {query}")
                return self.reply(500, {"status": "error", "error": "no fixture for this query"})
            if set(body) == {"status"} and isinstance(body["status"], int):
                return self.reply(body["status"], {"status": "error", "errorType": "fixture", "error": "replayed error"})
            if (url.path == SQL_PATH) != (set(body) == {"records"}):
                record(f"UNEXPECTED {step} {query}")
                return self.reply(500, {"status": "error", "error": "the fixture answers the other path"})
            if url.path == SQL_PATH:
                return self.reply(200, {"output": [body], "execution_time_ms": 0})
            return self.reply(200, body)

        do_GET = answer
        do_POST = answer

        def log_message(self, *args):
            pass

    server = Server(("127.0.0.1", 0), Handler)
    with open(args.port_file, "w") as f:
        f.write(str(server.server_port))
    server.serve_forever()


if __name__ == "__main__":
    main()
