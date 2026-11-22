# A stand-in for Langfuse Cloud's OTLP endpoint in
# vmTests.x86_64-linux.fleet-ingress (agent-session-telemetry design D16).
# It answers POST <anything>/v1/traces as the mode in $SINK_DIR/mode says:
# `ok` (200, the default), `403`, `429` (with Retry-After: 1) or `413`; a
# stopped sink stands for Langfuse unreachable. Every request is appended
# to $SINK_DIR/requests.jsonl as one JSON line: the mode, the path, the
# Authorization, ingestion-version and content headers, the body's size,
# and the decoded ExportTraceServiceRequest.
import gzip
import json
import os
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

from google.protobuf.json_format import MessageToDict
from opentelemetry.proto.collector.trace.v1.trace_service_pb2 import (
    ExportTraceServiceRequest,
    ExportTraceServiceResponse,
)

SINK_DIR = os.environ["SINK_DIR"]
STATUS = {"ok": 200, "403": 403, "429": 429, "413": 413}


def mode():
    try:
        with open(os.path.join(SINK_DIR, "mode")) as f:
            return f.read().strip() or "ok"
    except FileNotFoundError:
        return "ok"


class Handler(BaseHTTPRequestHandler):
    def do_POST(self):
        body = self.rfile.read(int(self.headers.get("Content-Length", "0")))
        if self.headers.get("Content-Encoding") == "gzip":
            body = gzip.decompress(body)
        request = ExportTraceServiceRequest()
        request.ParseFromString(body)
        current = mode()
        record = {
            "mode": current,
            "path": self.path,
            "authorization": self.headers.get("Authorization"),
            "ingestion_version": self.headers.get("x-langfuse-ingestion-version"),
            "content_type": self.headers.get("Content-Type"),
            "bytes": len(body),
            "request": MessageToDict(request),
        }
        with open(os.path.join(SINK_DIR, "requests.jsonl"), "a") as f:
            f.write(json.dumps(record) + "\n")
        status = STATUS[current]
        answer = ExportTraceServiceResponse().SerializeToString() if status == 200 else b"refused by the sink"
        self.send_response(status)
        if status == 429:
            self.send_header("Retry-After", "1")
        self.send_header("Content-Type", "application/x-protobuf" if status == 200 else "text/plain")
        self.send_header("Content-Length", str(len(answer)))
        self.end_headers()
        self.wfile.write(answer)

    def log_message(self, *args):
        pass


ThreadingHTTPServer(("127.0.0.1", int(os.environ["SINK_PORT"])), Handler).serve_forever()
