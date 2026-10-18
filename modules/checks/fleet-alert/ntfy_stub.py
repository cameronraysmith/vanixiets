"""Loopback stand-in for ntfy 2.28.0's publish and poll endpoints, for the
fleet-deadman legs of checks.x86_64-linux.fleet-alert (tasks.md 5.1).

POST /<topic> answers --probe-status, with ntfy's error body for 403
(binwiederhier/ntfy@v2.28.0 server/errors.go:156, raised by authorizeTopic in
server/server_middleware.go:153-171). GET /<topic>/json?poll=1&since=10m
answers --poll-status, and on 200 the --poll-body file, one JSON message per
line (server/server.go:1484-1489, 1749-1782). The probe and the poll are
anonymous (ADR-009 R9.4), so a request carrying an Authorization header gets
400. Every request is appended to --log as "<METHOD> <path>?<query> auth=<yes|no>".
"""

import argparse
import json
from http.server import BaseHTTPRequestHandler, HTTPServer
from urllib.parse import parse_qs, urlsplit

parser = argparse.ArgumentParser()
parser.add_argument("--topic", required=True)
parser.add_argument("--probe-status", type=int, required=True)
parser.add_argument("--poll-status", type=int, required=True)
parser.add_argument("--poll-body", required=True)
parser.add_argument("--port-file", required=True)
parser.add_argument("--log", required=True)
args = parser.parse_args()


def error(status, message):
    return json.dumps({"code": status * 100 + 1, "http": status, "error": message})


class Handler(BaseHTTPRequestHandler):
    def reply(self, status, body):
        data = body.encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def record(self):
        url = urlsplit(self.path)
        authorized = "Authorization" in self.headers
        with open(args.log, "a") as log:
            log.write(f"{self.command} {url.path}?{url.query} auth={'yes' if authorized else 'no'}\n")
        return url, authorized

    def do_POST(self):
        url, authorized = self.record()
        self.rfile.read(int(self.headers.get("Content-Length", "0")))
        if authorized:
            return self.reply(400, error(400, "stub: Authorization on an anonymous request"))
        if url.path != f"/{args.topic}":
            return self.reply(404, error(404, "page not found"))
        if 200 <= args.probe_status < 300:
            return self.reply(
                args.probe_status,
                json.dumps({"id": "probe", "time": 0, "event": "message", "topic": args.topic, "message": "probe"}),
            )
        return self.reply(args.probe_status, error(args.probe_status, "forbidden" if args.probe_status == 403 else "stub"))

    def do_GET(self):
        url, authorized = self.record()
        query = parse_qs(url.query)
        if authorized:
            return self.reply(400, error(400, "stub: Authorization on an anonymous request"))
        if url.path != f"/{args.topic}/json" or query.get("poll") != ["1"] or query.get("since") != ["10m"]:
            return self.reply(404, error(404, "page not found"))
        if args.poll_status != 200:
            return self.reply(args.poll_status, error(args.poll_status, "stub"))
        with open(args.poll_body) as body:
            return self.reply(200, body.read())

    def log_message(self, *_):
        pass


server = HTTPServer(("127.0.0.1", 0), Handler)
with open(args.port_file, "w") as port_file:
    port_file.write(str(server.server_port))
server.serve_forever()
