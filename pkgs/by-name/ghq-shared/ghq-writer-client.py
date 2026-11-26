"""Send one request to the shared ghq tree's writer and relay its reply.

Usage:
  ghq-writer-client get [--lazy] [--update] [--tags] TARGET
  ghq-writer-client deepen N PATH
  ghq-writer-client promote PATH
  ghq-writer-client hydrate REV PATH
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
    if len(argv) == 3 and argv[0] == "hydrate":
        return {"action": "hydrate", "rev": argv[1], "path": os.path.realpath(argv[2])}
    raise SystemExit(__doc__)


def main():
    # The second line asks for notes; a writer predating them reads only the first.
    payload = json.dumps(request(sys.argv[1:])).encode() + b'\n{"accept": ["note"]}\n'
    reply = None
    try:
        with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as conn:
            conn.connect(SOCKET)
            conn.sendall(payload)
            conn.shutdown(socket.SHUT_WR)
            # The writer may send {"note": ...} lines, such as a wait for the
            # repository, before its one reply.
            for line in conn.makefile("rb"):
                message = json.loads(line)
                if "note" in message:
                    sys.stderr.write(message["note"])
                    sys.stderr.flush()
                else:
                    reply = message
    except OSError as error:
        print(f"ghq-writer: cannot reach the shared-tree writer at {SOCKET}: {error}", file=sys.stderr)
        sys.exit(69)
    except ValueError:
        reply = None
    if reply is None:
        print("ghq-writer: the writer closed the connection without a reply", file=sys.stderr)
        sys.exit(70)
    sys.stdout.write(reply["stdout"])
    sys.stderr.write(reply["stderr"])
    sys.exit(reply["exit"])


if __name__ == "__main__":
    main()
