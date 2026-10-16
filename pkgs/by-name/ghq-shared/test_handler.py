"""Drive ghq-writer-handler over a socket pair, as its service would.

Every refused request class must be refused without touching the shared root,
an unauthorized caller must be refused, and one accepted request (deepen over a
file:// fixture) must change the repository it names.
"""

import grp
import json
import os
import socket
import subprocess
import sys
import tempfile

HANDLER = sys.argv[1]
work = tempfile.mkdtemp()
root = os.path.join(work, "root")
os.makedirs(root)
own_group = grp.getgrgid(os.getgid()).gr_name


def git(*args, cwd=None):
    env = dict(os.environ, GIT_CONFIG_NOSYSTEM="1", GIT_CONFIG_GLOBAL="/dev/null")
    return subprocess.run(
        ["git", "-c", "protocol.file.allow=always", "-c", "user.name=t", "-c", "user.email=t@t", *args],
        cwd=cwd, env=env, check=True, capture_output=True, text=True,
    ).stdout.strip()


def config(group=own_group, protocols=("https",)):
    path = os.path.join(work, f"config-{group}-{'-'.join(protocols)}.json")
    with open(path, "w") as handle:
        json.dump({"root": root, "group": group, "allowedProtocols": list(protocols)}, handle)
    return path


def ask(request, cfg):
    ours, theirs = socket.socketpair()
    proc = subprocess.Popen([HANDLER, cfg], stdin=theirs, stdout=theirs)
    theirs.close()
    ours.sendall((request if isinstance(request, bytes) else json.dumps(request).encode()) + b"\n")
    ours.shutdown(socket.SHUT_WR)
    data = b"".join(iter(lambda: ours.recv(65536), b""))
    proc.wait()
    return json.loads(data)


def snapshot():
    return sorted(os.path.join(d, n) for d, ds, fs in os.walk(root) for n in ds + fs)


fixture = os.path.join(work, "fixture")
os.makedirs(fixture)
git("init", "-q", "-b", "main", cwd=fixture)
for i in range(3):
    git("commit", "-q", "--allow-empty", "-m", f"c{i}", cwd=fixture)
clone = os.path.join(root, "example.com", "o", "r")
git("clone", "-q", "--depth", "1", f"file://{fixture}", clone)

before = snapshot()
refused = {
    "leading dash": {"action": "get", "target": "-x"},
    "ext transport": {"action": "get", "target": "ext::sh -c id"},
    "file scheme": {"action": "get", "target": "file:///etc"},
    "dotdot segment": {"action": "get", "target": "github.com/../../etc"},
    "unknown action": {"action": "create", "target": "github.com/a/b"},
    "zero depth": {"action": "deepen", "depth": 0, "path": clone},
    "string depth": {"action": "deepen", "depth": "1", "path": clone},
    "path outside root": {"action": "promote", "path": work},
    "oversized": b'{"action":"get","target":"' + b"a" * 5000 + b'"}',
    "not json": b"get github.com/a/b",
}
failures = []
for name, request in refused.items():
    reply = ask(request, config())
    if reply["exit"] != 2 or "refused" not in reply["stderr"]:
        failures.append(f"{name}: {reply}")
reply = ask({"action": "deepen", "depth": 1, "path": clone}, config(group="ghq-test-absent-group"))
if reply["exit"] != 13:
    failures.append(f"unauthorized caller: {reply}")
if snapshot() != before:
    failures.append("a refused request changed the shared root")

depth_before = git("rev-list", "--count", "HEAD", cwd=clone)
reply = ask({"action": "deepen", "depth": 1, "path": clone}, config(protocols=("file",)))
depth_after = git("rev-list", "--count", "HEAD", cwd=clone)
if reply["exit"] != 0 or "deepened:" not in reply["stdout"] or int(depth_after) <= int(depth_before):
    failures.append(f"accepted deepen: {reply} ({depth_before} -> {depth_after})")

reply = ask({"action": "deepen", "depth": 1, "path": clone}, config(protocols=("https",)))
if "failed:" not in reply["stdout"]:
    failures.append(f"file protocol not allowed must fail the fetch: {reply}")

if failures:
    sys.exit("\n".join(failures))
print("ghq-writer-handler: all request classes behaved")
