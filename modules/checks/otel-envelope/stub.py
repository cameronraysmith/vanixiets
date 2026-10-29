"""Loopback stand-in for a collector's telemetry endpoint and a scrape target.

checks.x86_64-linux.otel-envelope runs otel-envelope against this stub
(design D7). On 127.0.0.1:$STUB_PORT it serves GET /metrics from the file
named in $STUB_FIXTURE, re-read on each request, as Prometheus text; /ok
with 200; /slow with 200 after 15 s, longer than the script's 10 s probe
limit; anything else with 404. A closed port stands for a stopped
exporter, so the check stops the stub instead of serving an error.
"""

import os
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer


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
