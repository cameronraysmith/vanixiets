"""Drive ghq-writer-handler over a socket pair, as its service would.

Every refused request class must be refused without touching the shared root,
an unauthorized caller must be refused, and one accepted request (deepen over a
file:// fixture) must change the repository it names.
"""

import grp
import importlib.machinery
import json
import os
import socket
import subprocess
import sys
import tempfile
import types

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
    "ext transport with arguments": {"action": "get", "target": "ext::sh -c id"},
    "ext transport": {"action": "get", "target": "ext::sh"},
    "empty host": {"action": "get", "target": "https:///etc/ghq"},
    "file scheme": {"action": "get", "target": "file:///etc"},
    "dotdot segment": {"action": "get", "target": "github.com/../../etc"},
    "unknown action": {"action": "create", "target": "github.com/a/b"},
    "zero depth": {"action": "deepen", "depth": 0, "path": clone},
    "string depth": {"action": "deepen", "depth": "1", "path": clone},
    "path outside root": {"action": "promote", "path": work},
    "oversized": b'{"action":"get","target":"' + b"a" * 5000 + b'"}',
    "not json": b"get github.com/a/b",
    "unknown field": {"action": "get", "target": "github.com/a/b", "force": True},
    "tags not boolean": {"action": "get", "target": "github.com/a/b", "tags": "yes"},
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


# Tags. Upstream: main with 8 commits, lightweight v-in at main~1 (inside the
# history a deepened clone holds), annotated a-side on a side branch.
def commit(cwd, n, prefix):
    for i in range(n):
        git("commit", "-q", "--allow-empty", "-m", f"{prefix}{i}", cwd=cwd)

tagged = os.path.join(work, "tagged")
os.makedirs(tagged)
git("init", "-q", "-b", "main", cwd=tagged)
commit(tagged, 8, "m")
git("tag", "v-in", "HEAD~1", cwd=tagged)
git("checkout", "-q", "-b", "side", "HEAD~5", cwd=tagged)
commit(tagged, 2, "s")
git("tag", "-a", "-m", "annotated", "a-side", cwd=tagged)
git("checkout", "-q", "main", cwd=tagged)
url = f"file://{tagged}"
tags_cfg = config(protocols=("file",))

def tags(path):
    return set(git("tag", cwd=path).split())

shallow = os.path.join(root, "github.com", "o", "tagged")
git("clone", "-q", "--depth", "1", "--no-tags", "--filter=blob:none", url, shallow)
git("fetch", "-q", "--deepen", "3", cwd=shallow)
depth = git("rev-list", "--count", "HEAD", cwd=shallow)
reply = ask({"action": "get", "target": "github.com/o/tagged", "update": True}, tags_cfg)
if reply["exit"] != 0 or "a-side" in tags(shallow):
    failures.append(f"shallow update without tags must not fetch off-branch tags: {reply} {tags(shallow)}")
reply = ask({"action": "get", "target": "github.com/o/tagged", "update": True, "tags": True}, tags_cfg)
got = git("rev-list", "--count", "HEAD", cwd=shallow)
if reply["exit"] != 0 or not {"v-in", "a-side"} <= tags(shallow):
    failures.append(f"shallow --tags must fetch every tag: {reply} {tags(shallow)}")
if got != depth:
    failures.append(f"shallow --tags moved the history boundary: {depth} -> {got}")
os.environ["GIT_NO_LAZY_FETCH"] = "1"
if git("rev-list", "--count", "a-side", cwd=shallow) != "1":
    failures.append("an absent tag's commit must arrive at depth 1")
if git("cat-file", "-t", "a-side", cwd=shallow) != "tag":
    failures.append("an annotated tag must arrive as a tag object")

old = git("rev-parse", "v-in", cwd=shallow)
git("tag", "-f", "v-in", "HEAD~2", cwd=tagged)
reply = ask({"action": "get", "target": "github.com/o/tagged", "update": True, "tags": True}, tags_cfg)
if reply["exit"] == 0 or git("rev-parse", "v-in", cwd=shallow) != old:
    failures.append(f"a moved tag must be rejected, not forced, as plain git fetch --tags does: {reply}")

plain = os.path.join(root, "github.com", "o", "plain")
git("clone", "-q", "--depth", "1", f"file://{fixture}", plain)
reply = ask({"action": "get", "target": "github.com/o/plain", "update": True, "tags": True}, tags_cfg)
if reply["exit"] != 0:
    failures.append(f"--tags with no remote tags must be a no-op: {reply}")

full = os.path.join(root, "github.com", "o", "full")
git("clone", "-q", "--no-tags", url, full)
git("checkout", "-q", "side", cwd=tagged)
commit(tagged, 1, "n")
git("tag", "t-new", cwd=tagged)
git("checkout", "-q", "main", cwd=tagged)
reply = ask({"action": "get", "target": "github.com/o/full", "update": True}, tags_cfg)
if reply["exit"] != 0 or "t-new" not in tags(full):
    failures.append(f"a full clone must fetch tags on plain update: {reply}")

# Tag fetches act only on a clone inside the root: not through a symbolic link
# out of it, and not for a bare name, which ghq resolves under its user owner.
outside = os.path.join(work, "outside")
git("clone", "-q", "--no-tags", url, outside)
os.symlink(outside, os.path.join(root, "github.com", "o", "escape"))
ask({"action": "get", "target": "github.com/o/escape", "tags": True}, tags_cfg)
if tags(outside):
    failures.append(f"a tag fetch followed a link out of the root: {tags(outside)}")
bare = os.path.join(root, "bare")
git("clone", "-q", "--no-tags", url, bare)
ask({"action": "get", "target": "bare", "tags": True}, tags_cfg)
if tags(bare):
    failures.append(f"a bare target must not name <root>/<target>: {tags(bare)}")

# A connection that never completes its request is closed with a refusal.
ours, theirs = socket.socketpair()
proc = subprocess.Popen([HANDLER, config()], stdin=theirs, stdout=theirs, stderr=subprocess.PIPE)
theirs.close()
ours.sendall(b'{"action": "get"')
try:
    _, log = proc.communicate(timeout=90)
    reply = json.loads(b"".join(iter(lambda: ours.recv(65536), b"")))
    if reply["exit"] != 2 or "refused" not in reply["stderr"] or b"Traceback" in log:
        failures.append(f"idle connection: {reply} {log!r}")
except subprocess.TimeoutExpired:
    proc.kill()
    failures.append("an idle connection held its handler past the read timeout")

# ls-remote output that is not "<sha>\t<ref>" is a failed tag fetch, not a crash.
loader = importlib.machinery.SourceFileLoader("handler", HANDLER)
handler = types.ModuleType("handler")
loader.exec_module(handler)
handler.git = lambda path, env, *args, stdin=None: subprocess.CompletedProcess(args, 0, b"garbage\n", b"")
try:
    results = handler.shallow_tags(shallow, {})
    if not results or not results[-1].returncode or b"garbage" not in results[-1].stderr:
        failures.append(f"malformed ls-remote output must fail the tag fetch: {results}")
except ValueError as error:
    failures.append(f"malformed ls-remote output raised: {error!r}")

if failures:
    sys.exit("\n".join(failures))
print("ghq-writer-handler: all request classes behaved")
