"""Carry out one request against the shared ghq tree, as its sole writer.

Started once per connection by a socket-activated service (systemd Accept=yes,
launchd inetdCompatibility), with the connection on file descriptor 0. Reads one
JSON request, refuses anything outside a fixed action set, runs ghq or ghq-sync
without a shell, and writes one JSON reply {"stdout", "stderr", "exit"}.

Usage: ghq-writer-handler CONFIG.json, where CONFIG holds "root", "group" and
"allowedProtocols".
"""

import grp
import json
import os
import pwd
import re
import socket
import struct
import subprocess
import sys

GHQ = "@ghq@"
GHQ_SYNC = "@ghqSync@"
TOOL_PATH = "@toolPath@"

MAX_REQUEST = 4096
TARGET = re.compile(r"[A-Za-z0-9][A-Za-z0-9._~:/@+%-]*\Z")
SCHEME = re.compile(r"([A-Za-z][A-Za-z0-9+.-]*)://")
ACTIONS = {"get", "deepen", "promote"}


class Refused(Exception):
    pass


def peer_uid(conn):
    if sys.platform.startswith("linux"):
        size = struct.calcsize("3i")
        _pid, uid, _gid = struct.unpack("3i", conn.getsockopt(socket.SOL_SOCKET, socket.SO_PEERCRED, size))
        return uid
    # darwin: getsockopt(SOL_LOCAL=0, LOCAL_PEERCRED=1) returns struct xucred,
    # whose first two fields are cr_version and cr_uid.
    return struct.unpack_from("=II", conn.getsockopt(0, 1, 76))[1]


def authorized(uid, group):
    try:
        account = pwd.getpwuid(uid)
        members = grp.getgrnam(group)
    except KeyError:
        return False
    return account.pw_gid == members.gr_gid or account.pw_name in members.gr_mem


def check_target(target, allowed):
    if not isinstance(target, str) or len(target) > 512 or not TARGET.match(target):
        raise Refused("target must start with a letter or digit and use only A-Za-z0-9._~:/@+%-")
    if "::" in target or ".." in target.split("/"):
        raise Refused("target may not contain '::' or a '..' segment")
    scheme = SCHEME.match(target)
    if scheme and scheme.group(1).lower() not in allowed:
        raise Refused(f"protocol {scheme.group(1)!r} is not allowed")
    return target


def check_path(path, root):
    if not isinstance(path, str) or len(path) > 4096:
        raise Refused("path must be a string")
    real = os.path.realpath(path)
    if not real.startswith(os.path.realpath(root) + os.sep) or not os.path.isdir(real):
        raise Refused("path must be a directory inside the shared root")
    return real


def command(request, config):
    if not isinstance(request, dict) or request.get("action") not in ACTIONS:
        raise Refused("action must be one of get, deepen, promote")
    action = request["action"]
    if action == "get":
        argv = [GHQ, "get"]
        if request.get("lazy") is True:
            argv += ["--shallow", "--partial", "blobless", "--no-recursive"]
        if request.get("update") is True:
            argv.append("-u")
        return argv + [check_target(request.get("target"), config["allowedProtocols"])]
    path = check_path(request.get("path"), config["root"])
    if action == "deepen":
        depth = request.get("depth")
        if type(depth) is not int or not 0 < depth <= 1_000_000:
            raise Refused("depth must be a positive integer")
        return [GHQ_SYNC, "--deepen", str(depth), path]
    return [GHQ_SYNC, "--full", path]


def environment(config):
    protocols = ["protocol.allow=never"] + [f"protocol.{p}.allow=always" for p in config["allowedProtocols"]]
    env = {
        "PATH": TOOL_PATH,
        "HOME": "/var/empty",
        "LANG": "C.UTF-8",
        "GHQ_ROOT": config["root"],
        "GHQ_SYNC_NO_ZOXIDE": "1",
        "GIT_CONFIG_NOSYSTEM": "1",
        "GIT_CONFIG_GLOBAL": "/dev/null",
        "GIT_TERMINAL_PROMPT": "0",
        "GIT_CONFIG_COUNT": str(len(protocols)),
    }
    for i, entry in enumerate(protocols):
        key, value = entry.split("=", 1)
        env[f"GIT_CONFIG_KEY_{i}"] = key
        env[f"GIT_CONFIG_VALUE_{i}"] = value
    return env


def serve(conn, config):
    uid = peer_uid(conn)
    # Read before refusing, so an unauthorized caller gets a reply rather than a reset.
    raw = conn.makefile("rb").readline(MAX_REQUEST + 1)
    if not authorized(uid, config["group"]):
        return {"stdout": "", "stderr": f"ghq-writer: uid {uid} is not a member of {config['group']}\n", "exit": 13}, uid, None
    try:
        if len(raw) > MAX_REQUEST:
            raise Refused("request exceeds 4 KiB")
        request = json.loads(raw)
        argv = command(request, config)
    except (Refused, ValueError) as refusal:
        return {"stdout": "", "stderr": f"ghq-writer: refused: {refusal}\n", "exit": 2}, uid, None
    result = subprocess.run(argv, env=environment(config), stdin=subprocess.DEVNULL, capture_output=True, timeout=3600)
    reply = {
        "stdout": result.stdout.decode(errors="replace"),
        "stderr": result.stderr.decode(errors="replace"),
        "exit": result.returncode,
    }
    return reply, uid, argv


def main():
    with open(sys.argv[1]) as handle:
        config = json.load(handle)
    conn = socket.socket(fileno=0)
    reply, uid, argv = serve(conn, config)
    print(f"ghq-writer: uid={uid} argv={argv} exit={reply['exit']}", file=sys.stderr)
    conn.sendall(json.dumps(reply).encode() + b"\n")
    conn.close()


if __name__ == "__main__":
    main()
