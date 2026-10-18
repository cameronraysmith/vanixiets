"""Loopback stand-in for GreptimeDB's PromQL instant-query API.

checks.x86_64-linux.fleet-alert runs the evaluator against this server
(design D19; fleet-alerting-interface "The evaluator queries the fleet
database as the regulators' store account"). It serves GET and POST
/v1/prometheus/api/v1/query from responses[<step>][<query>], where <step>
is the content of --step-file, read per request, and each answer is a
Prometheus JSON body or {"status": <code>} for an error. It answers 404 to
any other path, 400 without `x-greptime-db-name: fleet`, and 401 to any
account but `regulator` with the fixture password. A query with no answer
gets 500 and an UNEXPECTED line. If two connections are ever open at once
it prints a VIOLATION line and exits 1, so a leg fails if the evaluator
queries concurrently (design D13). Everything it records is a line on
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

QUERY_PATH = "/v1/prometheus/api/v1/query"
FIXTURE_USER = "regulator"
# The same value checks.x86_64-linux.fleet-alert writes to the fixture
# credentials' regulator-password.
FIXTURE_PASSWORD = "00112233445566778899aabbccddeeff"


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--responses", required=True)
    parser.add_argument("--step-file", required=True)
    parser.add_argument("--port-file", required=True)
    args = parser.parse_args()
    with open(args.responses) as f:
        responses = json.load(f)

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
            if url.path != QUERY_PATH:
                return self.reply(404, {"status": "error", "error": "not found"})
            if self.headers.get("x-greptime-db-name") != "fleet":
                return self.reply(400, {"status": "error", "error": "database is not fleet"})
            if self.credentials() != (FIXTURE_USER, FIXTURE_PASSWORD):
                return self.reply(401, {"status": "error", "error": "unauthorized"})
            with open(args.step_file) as f:
                step = f.read().strip()
            query = form.get("query", [""])[0]
            record(f"REQUEST {step} {query}")
            body = responses.get(step, {}).get(query)
            if body is None:
                record(f"UNEXPECTED {step} {query}")
                return self.reply(500, {"status": "error", "error": "no fixture for this query"})
            if set(body) == {"status"} and isinstance(body["status"], int):
                return self.reply(body["status"], {"status": "error", "errorType": "fixture", "error": "replayed error"})
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
