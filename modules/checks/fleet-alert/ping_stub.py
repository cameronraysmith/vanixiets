"""Loopback stand-in for healthchecks.io's Pinging API, for the dead-man's
external-ping legs of checks.x86_64-linux.fleet-alert (CAM-76, design D7).

Every request, whatever its method or path, is answered 200 with the --answer
body, as healthchecks.io answers 200 with "OK", "OK (not found)" or
"OK (rate limited)" (https://healthchecks.io/docs/http_api/). Each request is
appended to --log as "<METHOD> <path> body=<bytes>".
"""

import argparse
from http.server import BaseHTTPRequestHandler, HTTPServer

parser = argparse.ArgumentParser()
parser.add_argument("--answer", required=True)
parser.add_argument("--port-file", required=True)
parser.add_argument("--log", required=True)
args = parser.parse_args()


class Handler(BaseHTTPRequestHandler):
    def handle_any(self):
        length = int(self.headers.get("Content-Length", "0"))
        self.rfile.read(length)
        with open(args.log, "a") as log:
            log.write(f"{self.command} {self.path} body={length}\n")
        data = args.answer.encode()
        self.send_response(200)
        self.send_header("Content-Type", "text/plain; charset=utf-8")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        if self.command != "HEAD":
            self.wfile.write(data)

    do_GET = do_POST = do_HEAD = handle_any

    def log_message(self, *_):
        pass


server = HTTPServer(("127.0.0.1", 0), Handler)
with open(args.port_file, "w") as port_file:
    port_file.write(str(server.server_port))
server.serve_forever()
