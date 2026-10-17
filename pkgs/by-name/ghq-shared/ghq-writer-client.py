"""Send one request to the shared ghq tree's writer and relay its reply.

Usage:
  ghq-writer-client get [--lazy] [--update] [--tags] TARGET
  ghq-writer-client deepen N PATH
  ghq-writer-client promote PATH
"""

import json
import os
import socket
import sys

SOCKET = "@socket@"


def request(argv):
    if argv[:1] == ["get"]:
        flags, target = argv[1:-1], argv[-1:]
        if not target or any(flag not in ("--lazy", "--update", "--tags") for flag in flags):
            raise SystemExit(__doc__)
        return {
            "action": "get",
            "target": target[0],
            "lazy": "--lazy" in flags,
            "update": "--update" in flags,
            "tags": "--tags" in flags,
        }
    if len(argv) == 3 and argv[0] == "deepen" and argv[1].isdigit():
        return {"action": "deepen", "depth": int(argv[1]), "path": os.path.realpath(argv[2])}
    if len(argv) == 2 and argv[0] == "promote":
        return {"action": "promote", "path": os.path.realpath(argv[1])}
    raise SystemExit(__doc__)


def main():
    payload = json.dumps(request(sys.argv[1:])).encode() + b"\n"
    try:
        with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as conn:
            conn.connect(SOCKET)
            conn.sendall(payload)
            conn.shutdown(socket.SHUT_WR)
            data = b"".join(iter(lambda: conn.recv(65536), b""))
    except OSError as error:
        print(f"ghq-writer: cannot reach the shared-tree writer at {SOCKET}: {error}", file=sys.stderr)
        sys.exit(69)
    try:
        reply = json.loads(data)
    except ValueError:
        print("ghq-writer: the writer closed the connection without a reply", file=sys.stderr)
        sys.exit(70)
    sys.stdout.write(reply["stdout"])
    sys.stderr.write(reply["stderr"])
    sys.exit(reply["exit"])


if __name__ == "__main__":
    main()
