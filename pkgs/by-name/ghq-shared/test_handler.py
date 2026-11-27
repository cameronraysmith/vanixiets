"""Drive ghq-writer-handler over a socket pair, as its service would.

Every refused request class must be refused without touching the shared root,
an unauthorized caller must be refused, and one accepted request (deepen over a
file:// fixture) must change the repository it names. An update that changes an
LFS path fast-forwards to its pointer file, and hydrate fetches the blobs a
revision needs. Requests for one repository run one after another, the later one
telling its caller it waits and giving up after the lock timeout; requests for
different repositories overlap; a caller that disconnects leaves its update to
finish, with no traceback, and its lock released. A command that fails, or
outlasts the command timeout, and an unexpected error each end with a reply and
an exit log line giving the reason, naming neither the target nor a command's
arguments; a timed-out command is stopped with every process it started.
"""

import errno
import grp
import hashlib
import importlib.machinery
import json
import os
import re
import shutil
import signal
import socket
import subprocess
import sys
import tempfile
import time
import types

HANDLER = sys.argv[1]
# Fixtures carry no permission for others, so any such permission in the root
# below was written by the handler.
os.umask(0o077)
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


locks = os.path.join(work, "locks")
os.makedirs(locks)


def config(group=own_group, protocols=("https",), lock_timeout=None, command_timeout=None, history_limit=None):
    path = os.path.join(work, f"config-{group}-{'-'.join(protocols)}-{lock_timeout}-{command_timeout}-{history_limit}.json")
    settings = {"root": root, "group": group, "allowedProtocols": list(protocols), "lockDir": locks}
    if lock_timeout is not None:
        settings["lockTimeout"] = lock_timeout
    if command_timeout is not None:
        settings["commandTimeout"] = command_timeout
    if history_limit is not None:
        settings["historyLimit"] = history_limit
    with open(path, "w") as handle:
        json.dump(settings, handle)
    return path


# Runs the handler after executing a patch against it as a module, for faults no
# request can cause.
DRIVER = ("import importlib.machinery, sys, types\n"
          "loader = importlib.machinery.SourceFileLoader('handler', sys.argv[1])\n"
          "handler = types.ModuleType('handler')\n"
          "loader.exec_module(handler)\n"
          "exec(sys.argv[3], {'handler': handler})\n"
          "sys.argv = sys.argv[1:3]\n"
          "handler.main()\n")


def start(request, cfg, patch=None):
    ours, theirs = socket.socketpair()
    argv = [HANDLER, cfg] if patch is None else [sys.executable, "-c", DRIVER, HANDLER, cfg, patch]
    # launchd starts each inetd-style handler with umask 022 whatever the job's Umask
    # key says; the handler must set the writer's umask itself.
    proc = subprocess.Popen(argv, stdin=theirs, stdout=theirs, stderr=subprocess.PIPE,
                            preexec_fn=lambda: os.umask(0o022))
    theirs.close()
    ours.sendall((request if isinstance(request, bytes) else json.dumps(request).encode()) + b"\n")
    ours.shutdown(socket.SHUT_WR)
    return proc, ours


def finish(proc, ours, within=None):
    """The handler's reply, exit None when it sent none, with the notes sent before it and its log lines.

    A handler that has not replied within `within` seconds is killed.
    """
    messages = []
    ours.settimeout(within)
    with ours, ours.makefile("rb") as lines:
        try:
            messages = [json.loads(line) for line in lines]
        except TimeoutError:
            proc.kill()
    _, log = proc.communicate()
    reply = messages[-1] if messages else {"stdout": "", "stderr": "", "exit": None}
    reply["notes"] = [message["note"] for message in messages[:-1]]
    reply["log"] = log.decode()
    return reply


def ask(request, cfg):
    return finish(*start(request, cfg))


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
    "hydrate range": {"action": "hydrate", "rev": "main..HEAD", "path": clone},
    "hydrate option": {"action": "hydrate", "rev": "-x", "path": clone},
    "hydrate reflog": {"action": "hydrate", "rev": "HEAD@{1}", "path": clone},
    "hydrate tree path": {"action": "hydrate", "rev": "HEAD:f", "path": clone},
    "hydrate empty rev": {"action": "hydrate", "rev": "", "path": clone},
    "hydrate rev not a string": {"action": "hydrate", "rev": 1, "path": clone},
    "hydrate path outside root": {"action": "hydrate", "rev": "HEAD", "path": work},
    "hydrate unknown field": {"action": "hydrate", "rev": "HEAD", "path": clone, "depth": 1},
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

# A tag ahead of a shallow clone's tip, fetched by --tags without -u, must not
# become a boundary that leaves the next update with no merge base.
ahead = os.path.join(work, "ahead")
os.makedirs(ahead)
git("init", "-q", "-b", "main", cwd=ahead)
commit(ahead, 2, "a")
behind = os.path.join(root, "github.com", "o", "ahead")
git("clone", "-q", "--depth", "1", "--no-tags", "--filter=blob:none", f"file://{ahead}", behind)
commit(ahead, 3, "b")
git("tag", "-a", "-m", "release", "v-ahead", cwd=ahead)
commit(ahead, 1, "c")
reply = ask({"action": "get", "target": "github.com/o/ahead", "tags": True}, tags_cfg)
if reply["exit"] != 0 or "v-ahead" not in tags(behind):
    failures.append(f"shallow --tags must fetch a tag ahead of the tip: {reply} {tags(behind)}")
reply = ask({"action": "get", "target": "github.com/o/ahead", "update": True}, tags_cfg)
if reply["exit"] != 0 or git("rev-parse", "HEAD", cwd=behind) != git("rev-parse", "main", cwd=ahead):
    failures.append(f"an update after shallow --tags must fast-forward past a tag ahead of the tip: {reply}")

# The fixtures below need the lazy fetches a blobless checkout makes.
os.environ.pop("GIT_NO_LAZY_FETCH")


def put(path, text):
    with open(path, "w") as handle:
        handle.write(text)


def lfs_pointer(content):
    return f"version https://git-lfs.github.com/spec/v1\noid sha256:{hashlib.sha256(content).hexdigest()}\nsize {len(content)}\n"


# LFS: the writer runs no LFS filter, even in a clone whose own configuration
# requires git-lfs, which is not on the writer's PATH; LFS paths hold pointer
# files, and an update that changes one fast-forwards. The control clone, with
# the same configuration and no policy, fails the same update.
lfs_up = os.path.join(work, "lfs-up")
os.makedirs(lfs_up)
git("init", "-q", "-b", "main", cwd=lfs_up)
put(os.path.join(lfs_up, ".gitattributes"), "*.bin filter=lfs diff=lfs merge=lfs -text\n")
put(os.path.join(lfs_up, "a.bin"), lfs_pointer(b"one"))
git("add", ".", cwd=lfs_up)
git("commit", "-q", "-m", "one", cwd=lfs_up)
lfs_clone = os.path.join(root, "github.com", "o", "lfs")
lfs_control = os.path.join(work, "lfs-control")
for repo in (lfs_clone, lfs_control):
    git("clone", "-q", f"file://{lfs_up}", repo)
    git("config", "filter.lfs.process", "git-lfs filter-process", cwd=repo)
    git("config", "filter.lfs.required", "true", cwd=repo)
put(os.path.join(lfs_up, "a.bin"), lfs_pointer(b"two"))
git("commit", "-q", "-am", "two", cwd=lfs_up)
reply = ask({"action": "get", "target": "github.com/o/lfs", "update": True}, tags_cfg)
with open(os.path.join(lfs_clone, "a.bin")) as handle:
    checked_out = handle.read()
if reply["exit"] != 0 or checked_out != lfs_pointer(b"two") or git("rev-parse", "HEAD", cwd=lfs_clone) != git("rev-parse", "HEAD", cwd=lfs_up):
    failures.append(f"an update changing an LFS path must fast-forward to its pointer: {reply} {checked_out!r}")
control = subprocess.run(
    ["git", "-c", "protocol.file.allow=always", "pull", "-q", "--ff-only"], cwd=lfs_control, capture_output=True,
    env=dict(os.environ, GIT_CONFIG_NOSYSTEM="1", GIT_CONFIG_GLOBAL="/dev/null"),
)
if control.returncode == 0:
    failures.append("control: the LFS fixture's update succeeded without the writer's policy, so the case is vacuous")

# Hydrate: every object a revision's tree needs arrives in the blobless clone,
# over an allowed protocol only, and a revision the clone lacks is skipped.
blobs = os.path.join(work, "blobs")
os.makedirs(blobs)
git("init", "-q", "-b", "main", cwd=blobs)
git("config", "uploadpack.allowFilter", "true", cwd=blobs)
for i in range(3):
    put(os.path.join(blobs, "f"), f"v{i}\n")
    git("add", "f", cwd=blobs)
    git("commit", "-q", "-m", f"v{i}", cwd=blobs)
lazy = os.path.join(root, "github.com", "o", "blobs")
git("clone", "-q", "--depth", "1", "--filter=blob:none", f"file://{blobs}", lazy)
git("fetch", "-q", "--deepen", "2", cwd=lazy)


def show_local(rev):
    return subprocess.run(
        ["git", "show", f"{rev}:f"], cwd=lazy, capture_output=True, text=True,
        env=dict(os.environ, GIT_NO_LAZY_FETCH="1", GIT_CONFIG_NOSYSTEM="1", GIT_CONFIG_GLOBAL="/dev/null"),
    )


if show_local("HEAD~2").returncode == 0:
    failures.append("hydrate: HEAD~2's blob was present before hydrating, so the case is vacuous")
reply = ask({"action": "hydrate", "rev": "HEAD~2", "path": lazy}, config(protocols=("https",)))
if "failed:" not in reply["stdout"] or show_local("HEAD~2").returncode == 0:
    failures.append(f"hydrate over a protocol not allowed must fail: {reply}")
reply = ask({"action": "hydrate", "rev": "HEAD~2", "path": lazy}, tags_cfg)
shown = show_local("HEAD~2")
if reply["exit"] != 0 or "hydrated:" not in reply["stdout"] or shown.stdout != "v0\n":
    failures.append(f"hydrate must make HEAD~2's blobs present: {reply} {shown}")
reply = ask({"action": "hydrate", "rev": "no-such-tag", "path": lazy}, tags_cfg)
if "skip:" not in reply["stdout"]:
    failures.append(f"hydrate of a revision the clone lacks must be skipped: {reply}")


# A default branch renamed upstream. Each upstream starts on master; then either
# master is renamed to main (the old branch is gone) or main is added with a new
# commit and made the default while master stays (the old branch still exists).
def upstream(name):
    work_tree = os.path.join(work, f"{name}-src")
    bare = os.path.join(work, f"{name}.git")
    os.makedirs(work_tree)
    git("init", "-q", "-b", "master", cwd=work_tree)
    for i in range(3):
        put(os.path.join(work_tree, "f"), f"{name}{i}\n")
        git("add", "f", cwd=work_tree)
        git("commit", "-q", "-m", f"{name}{i}", cwd=work_tree)
    git("clone", "-q", "--bare", work_tree, bare)
    git("config", "uploadpack.allowFilter", "true", cwd=bare)
    git("remote", "add", "up", bare, cwd=work_tree)
    return work_tree, bare


def make_default(work_tree, bare, keep_old):
    git("checkout", "-q", "-b", "main", cwd=work_tree)
    put(os.path.join(work_tree, "f"), "on main\n")
    git("commit", "-q", "-am", "on main", cwd=work_tree)
    git("push", "-q", "up", "main", cwd=work_tree)
    git("symbolic-ref", "HEAD", "refs/heads/main", cwd=bare)
    if not keep_old:
        git("branch", "-q", "-D", "master", cwd=bare)


def head_branch(path):
    return git("symbolic-ref", "--short", "-q", "HEAD", cwd=path)


renamed = {}
for case, keep_old in (("gone", False), ("kept", True)):
    work_tree, bare = upstream(f"default-{case}")
    lazy_clone = os.path.join(root, "github.com", "o", f"default-{case}")
    git("clone", "-q", "--depth", "1", "--filter=blob:none", "--no-tags", f"file://{bare}", lazy_clone)
    renamed[case] = (work_tree, bare, lazy_clone)
# Full clones of the old-branch-kept upstream: one on the old default, one on the
# old default with a local change, and one on a feature branch an operator works on.
_, kept_bare, _ = renamed["kept"]
full_default = os.path.join(root, "github.com", "o", "default-full")
full_dirty = os.path.join(root, "github.com", "o", "default-dirty")
full_feature = os.path.join(root, "github.com", "o", "default-feature")
for path in (full_default, full_dirty, full_feature):
    git("clone", "-q", "--no-tags", f"file://{kept_bare}", path)
put(os.path.join(full_dirty, "f"), "local change\n")
git("checkout", "-q", "-b", "feature", cwd=full_feature)
for case, keep_old in (("gone", False), ("kept", True)):
    work_tree, bare, _ = renamed[case]
    make_default(work_tree, bare, keep_old)

for case in ("gone", "kept"):
    work_tree, bare, lazy_clone = renamed[case]
    reply = ask({"action": "get", "target": f"github.com/o/default-{case}", "update": True}, tags_cfg)
    if (reply["exit"] != 0 or head_branch(lazy_clone) != "main"
            or git("rev-parse", "HEAD", cwd=lazy_clone) != git("rev-parse", "main", cwd=bare)
            or "default branch: master -> main" not in reply["stdout"]):
        failures.append(f"a lazy clone must follow the default branch to main (old branch {case}): {reply} {head_branch(lazy_clone)}")
    if git("rev-parse", "--is-shallow-repository", cwd=lazy_clone) != "true" or git("rev-list", "--count", "HEAD", cwd=lazy_clone) != "1":
        failures.append(f"following the default branch must keep the clone's depth (old branch {case})")
    if git("config", "--get", "remote.origin.partialclonefilter", cwd=lazy_clone) != "blob:none":
        failures.append(f"following the default branch must keep the clone's filter (old branch {case})")
reply = ask({"action": "get", "target": "github.com/o/default-full", "update": True}, tags_cfg)
if (reply["exit"] != 0 or head_branch(full_default) != "main"
        or git("symbolic-ref", "refs/remotes/origin/HEAD", cwd=full_default) != "refs/remotes/origin/main"
        or git("rev-parse", "HEAD", cwd=full_default) != git("rev-parse", "main", cwd=kept_bare)):
    failures.append(f"a clean full clone on the old default must switch to the new one: {reply} {head_branch(full_default)}")
feature_head = git("rev-parse", "HEAD", cwd=full_feature)
reply = ask({"action": "get", "target": "github.com/o/default-feature", "update": True}, tags_cfg)
if (head_branch(full_feature) != "feature" or git("rev-parse", "HEAD", cwd=full_feature) != feature_head
        or git("symbolic-ref", "refs/remotes/origin/HEAD", cwd=full_feature) != "refs/remotes/origin/main"
        or "kept feature" not in reply["stdout"]):
    failures.append(f"a full clone on a feature branch must stay put while origin/HEAD follows: {reply} {head_branch(full_feature)}")
reply = ask({"action": "get", "target": "github.com/o/default-dirty", "update": True}, tags_cfg)
if head_branch(full_dirty) != "master" or "kept master" not in reply["stdout"]:
    failures.append(f"a full clone with local changes must stay on its branch: {reply} {head_branch(full_dirty)}")

# Writer umask: whatever umask the service starts the handler with, nothing it
# writes carries a permission for others or group write.
exposed = [os.path.join(d, n) for d, ds, fs in os.walk(root) for n in ds + fs
           if not os.path.islink(os.path.join(d, n)) and os.lstat(os.path.join(d, n)).st_mode & 0o027]
if exposed:
    failures.append(f"the handler wrote {len(exposed)} entries open to others or group-writable, e.g. {exposed[:3]}")

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

# Serialisation. Each fixture clone fetches through an upload-pack that sleeps
# before serving and records the window it slept in, so the windows show whether
# two requests' fetches from one remote, or from two, overlapped.
windows = os.path.join(work, "windows")
slow_pack = os.path.join(work, "slow-upload-pack")
put(slow_pack, f"#!{sys.executable}\n" + """import os, sys, time
def mark(event):
    with open(WINDOWS, "a") as handle:
        handle.write(f"{event} {os.getpid()} {sys.argv[-1]} {time.time()}\\n")
mark("begin")
time.sleep(1)
mark("end")
os.execvp("git", ["git", "upload-pack", *sys.argv[1:]])
""".replace("WINDOWS", repr(windows)))
os.chmod(slow_pack, 0o755)
serial = {}
for name in ("serial-a", "serial-b"):
    work_tree, bare = upstream(name)
    clone_dir = os.path.join(root, "github.com", "o", name)
    git("clone", "-q", f"file://{bare}", clone_dir)
    git("config", "remote.origin.uploadpack", slow_pack, cwd=clone_dir)
    serial[name] = (work_tree, bare, clone_dir)


def advance(name):
    work_tree, _, _ = serial[name]
    git("commit", "-q", "--allow-empty", "-m", "advance", cwd=work_tree)
    git("push", "-q", "up", "master", cwd=work_tree)


def slept(name):
    """Each sleep window of name's upload-pack, as (begin, end)."""
    begun, spans = {}, []
    with open(windows) as handle:
        for line in handle:
            event, pid, path, stamp = line.split()
            if path.rstrip("/").endswith(f"/{name}.git"):
                if event == "begin":
                    begun[pid] = float(stamp)
                else:
                    spans.append((begun.pop(pid), float(stamp)))
    return spans


def overlap(first, second):
    return any(a < d and c < b for a, b in first for c, d in second)


def wait_for_fetch():
    """Return once a fetch has started, so the next request finds its lock held."""
    for _ in range(300):
        if os.path.exists(windows) and os.path.getsize(windows):
            return
        time.sleep(0.1)
    sys.exit("no fixture fetch began within 30 s")


def up_to_date(name):
    _, bare, clone_dir = serial[name]
    return git("rev-parse", "HEAD", cwd=clone_dir) == git("rev-parse", "master", cwd=bare)


def update(spelling, cfg=None):
    return {"action": "get", "target": spelling, "update": True}, cfg or config(protocols=("file",))


def run_client(target):
    """ghq-writer-client get --update target, against a listener handing each connection to the handler."""
    code = ("import importlib.machinery, sys, types\n"
            "loader = importlib.machinery.SourceFileLoader('client', sys.argv[1])\n"
            "client = types.ModuleType('client')\n"
            "loader.exec_module(client)\n"
            "client.SOCKET = sys.argv[2]\n"
            "sys.argv = ['ghq-writer-client', 'get', '--update', sys.argv[3]]\n"
            "client.main()\n")
    path = os.path.join(work, "w.sock")
    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as listener:
        listener.bind(path)
        listener.listen()
        caller = subprocess.Popen([sys.executable, "-c", code, os.path.join(os.path.dirname(HANDLER), "ghq-writer-client"), path, target],
                                  stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        conn, _ = listener.accept()
        with conn:
            served = subprocess.Popen([HANDLER, config(protocols=("file",))], stdin=conn, stdout=conn, stderr=subprocess.PIPE)
    os.unlink(path)
    out, err = caller.communicate()
    served.communicate()
    return caller.returncode, out.decode(), err.decode()


# Two updates of one repository, the second spelled owner/repo and sent through
# the client: the second waits, says so, and fetches only after the first is done.
advance("serial-a")
first = start(*update("github.com/o/serial-a"))
wait_for_fetch()
status, out, err = run_client("o/serial-a")
first = finish(*first)
if first["exit"] != 0 or status != 0 or not up_to_date("serial-a"):
    failures.append(f"concurrent updates of one repository must both succeed: {first} / {status} {out!r} {err!r}")
if not err.startswith("ghq-writer: waiting up to 3600 s for github.com/o/serial-a,"):
    failures.append(f"a request waiting for its repository must tell its caller first: {err!r}")
spans = sorted(slept("serial-a"))
if len(spans) < 4 or any(overlap([x], [y]) for i, x in enumerate(spans) for y in spans[i + 1:]):
    failures.append(f"two updates of one repository fetched at the same time: {spans}")

# Updates of two repositories run side by side.
os.unlink(windows)
advance("serial-a")
advance("serial-b")
pair = [start(*update(f"github.com/o/{name}")) for name in ("serial-a", "serial-b")]
replies = [finish(*request) for request in pair]
if any(reply["exit"] != 0 or " waiting " in reply["log"] for reply in replies) or not overlap(slept("serial-a"), slept("serial-b")):
    failures.append(f"updates of two repositories must overlap without waiting: {replies} {slept('serial-a')} {slept('serial-b')}")

# A request still waiting when the lock timeout passes gives up, saying why. Its
# caller sends no {"accept": ["note"]} line, as clients predating notes do not,
# so it receives its reply alone.
os.unlink(windows)
advance("serial-a")
first = start(*update("github.com/o/serial-a"))
wait_for_fetch()
impatient = ask(*update("github.com/o/serial-a", config(protocols=("file",), lock_timeout=1)))
first = finish(*first)
if (impatient["exit"] != 75 or first["exit"] != 0
        or "gave up after 1 s waiting for github.com/o/serial-a" not in impatient["stderr"]):
    failures.append(f"a request must give up after the lock timeout: {impatient}")
if impatient["notes"]:
    failures.append(f"a caller that does not accept notes must receive none: {impatient['notes']}")

# A caller that disconnects: the update finishes, the handler logs the
# disconnection rather than a traceback, and the lock is free once it exits.
os.unlink(windows)
advance("serial-a")
proc, ours = start(*update("github.com/o/serial-a"))
ours.close()
_, log = proc.communicate(timeout=300)
log = log.decode()
after = ask(*update("github.com/o/serial-a"))
if (proc.returncode != 0 or "Traceback" in log or "caller disconnected" not in log
        or "exit status=0" not in log or not up_to_date("serial-a")):
    failures.append(f"a disconnected caller's update must finish quietly: {proc.returncode} {log!r}")
if after["exit"] != 0 or after["notes"]:
    failures.append(f"a disconnected caller's handler must release its lock at exit: {after}")

# Log lines: a UTC timestamp, the handler's pid, the caller, verb and repository,
# at start and exit; a waiting request logs its wait too.
stamp = r"\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d\.\d{3}Z ghq-writer pid=\d+ uid=\d+ user=\S+ caller-pid=\S+"
line = rf"{stamp} verb=get\+update repo=github\.com/o/serial-a"
for pattern in (rf"^{line} start$", rf"^{line} caller disconnected$", rf"^{line} exit status=0 duration=\d+\.\d{{3}}s$"):
    if not re.search(pattern, log, re.M):
        failures.append(f"log line {pattern!r} missing: {log!r}")
if not re.search(rf"^{line} waiting held-by: pid=\d+ verb=get\+update since=\S+Z$", impatient["log"], re.M):
    failures.append(f"a waiting request must log its wait: {impatient['log']!r}")
if "file://" in log + impatient["log"]:
    failures.append("log lines must name the repository, not the target or its remote URL")

loader = importlib.machinery.SourceFileLoader("handler", HANDLER)
handler = types.ModuleType("handler")
loader.exec_module(handler)

# The writer's git reads no global or system configuration, so the readers'
# gitdir includes, which refuse every transport beneath the root, never apply to it.
writer_env = handler.environment({"root": root, "allowedProtocols": ["https"]})
if (writer_env.get("GIT_CONFIG_GLOBAL") != "/dev/null" or writer_env.get("GIT_CONFIG_NOSYSTEM") != "1"
        or writer_env.get("HOME") != "/var/empty"):
    failures.append(f"the writer's git must read no global or system configuration: {writer_env}")

# ls-remote output that is not "<sha>\t<ref>" is a failed tag fetch, not a crash.
handler.git = lambda path, env, *args, stdin=None: subprocess.CompletedProcess(args, 0, b"garbage\n", b"")
try:
    results = handler.shallow_tags(shallow, {})
    if not results or not results[-1].returncode or b"garbage" not in results[-1].stderr:
        failures.append(f"malformed ls-remote output must fail the tag fetch: {results}")
except ValueError as error:
    failures.append(f"malformed ls-remote output raised: {error!r}")

# Every spelling of a repository, and a repository not cloned yet, names one
# lock; two names differing only in case share it.
_, _, serial_a = serial["serial-a"]
os.makedirs(os.path.join(serial_a, "sub"))
root_link = os.path.join(work, "root-link")
os.symlink(root, root_link)
spellings = [
    ({"action": "get", "target": target}, base)
    for target in ("github.com/o/serial-a", "o/serial-a", "https://u:secret@github.com/o/serial-a.git",
                   "git@github.com:o/serial-a.git", "github.com/o/serial-a/")
    for base in (root, root_link)
] + [
    ({"action": "deepen", "depth": 1, "path": os.path.join(base, "github.com", "o", "serial-a", "sub")}, root)
    for base in (root, root_link)
]
names = {handler.repository(request, base) for request, base in spellings}
if names != {"github.com/o/serial-a"}:
    failures.append(f"spellings of one repository must name one lock: {names}")
if handler.repository({"action": "get", "target": "github.com/o/not-yet"}, root) != "github.com/o/not-yet":
    failures.append("a repository not cloned yet must have a lock name")
try:
    handler.repository({"action": "get", "target": "bare"}, root)
    failures.append("a bare target, which names no directory under the root, must be refused")
except handler.Refused:
    pass


def session(repo):
    return types.SimpleNamespace(repo=repo, verb="get", notes=False, log=lambda event: None, send=lambda message: None)


held = handler.hold({"lockDir": locks}, session("github.com/o/serial-a"))
try:
    handler.hold({"lockDir": locks, "lockTimeout": 0.2}, session("github.com/O/Serial-A"))
    failures.append("two names differing only in case must share one lock")
except handler.Busy:
    pass
finally:
    os.close(held)

# A command that outlasts the command timeout. The remote's packed-refs is a FIFO
# with no writer, so whatever reads the remote's refs blocks, as on a stalled
# connection. The get clones over https with invented credentials, rewritten to
# the local remote by configuration added to the handler's git environment: git
# clone ignores remote.origin.uploadpack and runs upload-pack from its own exec
# path, so no upload-pack wrapper can stand in for the remote under ghq.
_, hang_bare = upstream("hang")
hang_step = os.path.join(root, "github.com", "o", "hang-step")
git("clone", "-q", f"file://{hang_bare}", hang_step)
hang_fifo = os.path.join(hang_bare, "packed-refs")
os.unlink(hang_fifo)
os.mkfifo(hang_fifo)
hang_cfg = config(protocols=("https", "file"), command_timeout=1)
rewrite = f"url.file://{hang_bare.removesuffix('.git')}.insteadOf=https://u:secret@github.com/o/hang"
through_rewrite = f"handler.LFS_POLICY = handler.LFS_POLICY + [{rewrite!r}]"


def left_running():
    """Whether a process still reads the hung remote; probing releases it."""
    time.sleep(1)
    try:
        os.close(os.open(hang_fifo, os.O_WRONLY | os.O_NONBLOCK))
    except OSError as error:
        if error.errno == errno.ENXIO:
            return False
        raise
    return True


def lock_free(repo):
    try:
        os.close(handler.hold({"lockDir": locks, "lockTimeout": 0.2}, session(repo)))
        return True
    except handler.Busy:
        return False


def ended_without_target(case, reply, repo, verb, status, reason, own_output=False):
    """The reply and the exit log line of a failed request, neither naming its target.

    A failed command's reply carries the command's own output, which may name the
    target the caller gave; only the log is checked then.
    """
    line = rf"^{stamp} verb={re.escape(verb)} repo={re.escape(repo)} exit status={status} duration=\d+\.\d{{3}}s reason: {reason}$"
    if reply["exit"] in (None, 0) or not re.search(line, reply["log"], re.M):
        failures.append(f"{case}: the caller must get a failure reply and the log an exit line matching {line!r}: {reply}")
    for text in ("secret", "https://", "file://", "Traceback"):
        if text in reply["log"] or (text in reply["stderr"] and not own_output):
            failures.append(f"{case}: {text!r} must not reach the log or the reply's message: {reply}")
    if not lock_free(repo):
        failures.append(f"{case}: the repository's lock must be free afterwards")


# A get whose clone outlasts the command timeout: ghq and the git it started are
# stopped, and git removes its partial clone.
reply = finish(*start({"action": "get", "target": "https://u:secret@github.com/o/hang.git"}, hang_cfg, through_rewrite),
               within=30)
ended_without_target("a timed-out get", reply, "github.com/o/hang", "get", 124, "timed out after 1 s running ghq get")
if left_running():
    failures.append("a timed-out get must stop every process it started")
if os.path.exists(os.path.join(root, "github.com", "o", "hang")):
    failures.append("a timed-out get must leave no partial clone")

# A git step that outlasts the command timeout: an update's first step lists the remote.
reply = finish(*start({"action": "get", "target": "https://u:secret@github.com/o/hang-step.git", "update": True}, hang_cfg),
               within=30)
ended_without_target("a timed-out git step", reply, "github.com/o/hang-step", "get+update", 124,
                     "timed out after 1 s running git ls-remote")
if left_running():
    failures.append("a timed-out git step must stop every process it started")

# A command that fails: the update of a clone whose remote is gone fails at its
# first fetch.
_, gone_bare = upstream("gone")
git("clone", "-q", f"file://{gone_bare}", os.path.join(root, "github.com", "o", "gone"))
shutil.rmtree(gone_bare)
reply = ask({"action": "get", "target": "https://u:secret@github.com/o/gone.git", "update": True},
            config(protocols=("https", "file")))
ended_without_target("a failed command", reply, "github.com/o/gone", "get+update", r"(\d+)", r"git fetch exited \1",
                     own_output=True)

# An unexpected error whose message holds the target: the handler exits non-zero
# after replying and logging the error's type and its message with the target
# replaced.
boom = ("def boom(request, *rest):\n"
        "    raise RuntimeError(f\"cannot reach {request['target']}\")\n"
        "handler.run_get = boom\n")
proc, ours = start({"action": "get", "target": "https://u:secret@github.com/o/hang.git"}, hang_cfg, boom)
reply = finish(proc, ours)
ended_without_target("an unexpected error", reply, "github.com/o/hang", "get", 70,
                     r"unexpected RuntimeError: cannot reach <target>")
if proc.returncode == 0:
    failures.append(f"an unexpected error must end the handler with a non-zero status: {reply}")


def maintained(name, hook_sleep):
    """A blobless clone of a new upstream, its packs all promisor packs, with a
    pre-auto-gc hook that records its pid in <work>/<name>.pids.

    git maintenance runs the hook twice: in its need check, before it would
    detach, and in the gc it then starts, after. The second run sleeps
    hook_sleep seconds, so a sleeping hook marks maintenance's background work.
    """
    work_tree, bare = upstream(name)
    clone_dir = os.path.join(root, "github.com", "o", name)
    git("clone", "-q", "--filter=blob:none", f"file://{bare}", clone_dir)
    pids = os.path.join(work, f"{name}.pids")
    hook = os.path.join(clone_dir, ".git", "hooks", "pre-auto-gc")
    os.makedirs(os.path.dirname(hook), exist_ok=True)
    put(hook, f"#!{sys.executable}\nimport os, time\n"
              f"with open({pids!r}, 'a') as handle:\n    handle.write(f'{{os.getpid()}}\\n')\n"
              f"if len(open({pids!r}).readlines()) > 1:\n    time.sleep({hook_sleep})\n")
    os.chmod(hook, 0o755)
    return work_tree, bare, clone_dir, pids


def alive(pids):
    """The recorded pids still running, zombies aside."""
    found = []
    for pid in (int(line) for line in open(pids)) if os.path.exists(pids) else ():
        try:
            os.kill(pid, 0)
        except ProcessLookupError:
            continue
        stat = f"/proc/{pid}/stat"
        if not os.path.exists(stat) or open(stat).read().rsplit(")", 1)[1].split()[0] != "Z":
            found.append(pid)
    return found


def packs(clone_dir):
    return sorted(n for n in os.listdir(os.path.join(clone_dir, ".git", "objects", "pack")) if n.endswith(".pack"))


def present(clone_dir, obj):
    return subprocess.run(["git", "cat-file", "-e", obj], cwd=clone_dir, capture_output=True,
                          env=dict(os.environ, GIT_NO_LAZY_FETCH="1", GIT_CONFIG_NOSYSTEM="1",
                                   GIT_CONFIG_GLOBAL="/dev/null")).returncode == 0


# Auto maintenance after an update runs gc in the foreground, inside the request:
# the promisor packs of a blobless clone past gc.autoPackLimit are consolidated
# before the handler exits, no process the request started outlives it, and the
# blobs hydrated for an older commit and for a commit that a forced update leaves
# unreachable are still present.
m_tree, m_bare, m_clone, m_pids = maintained("maint", 0)
old_blob = git("rev-parse", "master~2:f", cwd=m_tree)
git("checkout", "-q", "-b", "side", cwd=m_tree)
put(os.path.join(m_tree, "f"), "doomed\n")
git("commit", "-q", "-am", "doomed", cwd=m_tree)
doomed_blob = git("rev-parse", "side:f", cwd=m_tree)
git("push", "-q", "up", "side", cwd=m_tree)
git("fetch", "-q", "origin", cwd=m_clone)
for rev in ("master~2", "origin/side"):
    reply = ask({"action": "hydrate", "rev": rev, "path": m_clone}, tags_cfg)
    if reply["exit"] != 0:
        failures.append(f"maintenance fixture: hydrate {rev} failed: {reply}")
if not (present(m_clone, old_blob) and present(m_clone, doomed_blob)):
    failures.append("maintenance fixture: the hydrated blobs are absent before the update, so the case is vacuous")
git("reset", "-q", "--hard", "master", cwd=m_tree)
git("commit", "-q", "--allow-empty", "-m", "side rewritten", cwd=m_tree)
git("push", "-q", "--force", "up", "side", cwd=m_tree)
git("checkout", "-q", "master", cwd=m_tree)
git("commit", "-q", "--allow-empty", "-m", "advance", cwd=m_tree)
git("push", "-q", "up", "master", cwd=m_tree)
for key, value in (("gc.autoPackLimit", "2"), ("gc.reflogExpireUnreachable", "now"), ("gc.pruneExpire", "now")):
    git("config", key, value, cwd=m_clone)
before_packs = packs(m_clone)
reply = ask({"action": "get", "target": "github.com/o/maint", "update": True}, tags_cfg)
after_packs = packs(m_clone)
if reply["exit"] != 0 or not os.path.exists(m_pids) or len(after_packs) > 2:
    failures.append(f"an update past gc.autoPackLimit must consolidate the packs before the handler exits: "
                    f"{len(before_packs)} -> {len(after_packs)} packs, hook ran: {os.path.exists(m_pids)}, {reply}")
if alive(m_pids):
    failures.append(f"maintenance must not outlive the request that started it: {alive(m_pids)} still running")
if not (present(m_clone, old_blob) and present(m_clone, doomed_blob)):
    failures.append("maintenance must keep hydrated blobs, of an older commit and of a commit left unreachable")
pack_dir = os.path.join(m_clone, ".git", "objects", "pack")
written = [os.path.join(pack_dir, n) for n in os.listdir(pack_dir)
           if n.startswith("pack-") and n.rsplit(".", 1)[0] + ".pack" not in before_packs]
exposed = [p for p in written if os.lstat(p).st_mode & 0o027 or not os.lstat(p).st_mode & 0o040]
if exposed or not written:
    failures.append("maintenance must write packs readable by the group and by no one else: "
                    f"{[(os.path.basename(p), oct(os.lstat(p).st_mode & 0o777)) for p in written]}")
if not lock_free("github.com/o/maint"):
    failures.append("maintenance: the repository's lock must be free afterwards")

# A timed-out command's stop ends the maintenance it started: the update's fetch
# runs gc, whose pre-auto-gc hook outlasts the command timeout. The clone's own
# maintenance.strategy=gc makes git run gc whatever the handler sets.
s_tree, _, s_clone, s_pids = maintained("maint-slow", 60)
git("config", "maintenance.strategy", "gc", cwd=s_clone)
git("config", "gc.autoPackLimit", "1", cwd=s_clone)
git("commit", "-q", "--allow-empty", "-m", "advance", cwd=s_tree)
git("push", "-q", "up", "master", cwd=s_tree)
reply = finish(*start({"action": "get", "target": "github.com/o/maint-slow", "update": True},
                      config(protocols=("file",), command_timeout=3)), within=60)
time.sleep(1)
running = alive(s_pids)
if not os.path.exists(s_pids) or running or reply["exit"] != 124:
    failures.append(f"a timed-out command's stop must end the maintenance it started: hook ran: "
                    f"{os.path.exists(s_pids)}, still running: {running}, {reply}")
for pid in running:
    os.kill(pid, signal.SIGKILL)


def change(work_tree, message, **files):
    for name, text in files.items():
        put(os.path.join(work_tree, name), text)
    git("add", "-A", cwd=work_tree)
    git("commit", "-q", "-m", message, cwd=work_tree)


def lazy_clone_of(name):
    """A new upstream and a depth-1 blobless clone of it under the root."""
    work_tree, bare = upstream(name)
    clone_dir = os.path.join(root, "github.com", "o", name)
    git("clone", "-q", "--depth", "1", "--filter=blob:none", "--no-tags", f"file://{bare}", clone_dir)
    return work_tree, bare, clone_dir


def offline(clone_dir, *args):
    return subprocess.run(["git", *args], cwd=clone_dir, capture_output=True, text=True,
                          env=dict(os.environ, GIT_NO_LAZY_FETCH="1", GIT_CONFIG_NOSYSTEM="1",
                                   GIT_CONFIG_GLOBAL="/dev/null"))


def unreadable(clone_dir, commits):
    """The commits whose diff, as lazygit's Patch pane shows it, needs a blob the clone lacks."""
    return [c for c in commits if offline(clone_dir, "--no-lazy-fetch", "show", "--find-renames=50%", "--submodule",
                                          "--stat", "--decorate", "-p", c).returncode]


def brought_in(clone_dir, old):
    return offline(clone_dir, "rev-list", f"{old}..HEAD").stdout.split()


def history_token(reply):
    found = re.search(r" exit status=\d+ duration=\d+\.\d{3}s history=(\S+)", reply["log"])
    return found and found.group(1)


def history_lines(reply):
    return [line for line in reply["stdout"].splitlines()
            if line.startswith(("hydrated history:", "history not hydrated:", "history hydrate failed:"))]


file_cfg = config(protocols=("file",))

# An update of a blobless clone makes every commit it brought in readable as a
# diff with lazy fetching disabled: a merge whose first-parent diff (h, added on
# the side branch) and combined diff (g, resolved differently from both parents)
# both need blobs, then a renamed default branch. gc.autoPackLimit 1 makes the
# maintenance after each fetch consolidate every pack, the range hydrate's
# included, so its blobs must survive a gc that prunes at once.
h_tree, h_bare, h_clone = lazy_clone_of("history")
git("fetch", "-q", "--deepen", "2", cwd=h_clone)
for key, value in (("gc.autoPackLimit", "1"), ("gc.pruneExpire", "now")):
    git("config", key, value, cwd=h_clone)
with open(os.path.join(h_clone, ".git", "shallow")) as handle:
    h_boundary = handle.read()
change(h_tree, "four", f="four\n")
git("checkout", "-q", "-b", "side", cwd=h_tree)
change(h_tree, "side", g="side\n", h="from side\n")
git("checkout", "-q", "master", cwd=h_tree)
change(h_tree, "master", g="master\n")
subprocess.run(["git", "-c", "user.name=t", "-c", "user.email=t@t", "merge", "-q", "--no-ff", "side"], cwd=h_tree,
               capture_output=True, env=dict(os.environ, GIT_CONFIG_NOSYSTEM="1", GIT_CONFIG_GLOBAL="/dev/null"))
change(h_tree, "merge side", g="resolved\n")
change(h_tree, "six", f="six\n")
git("push", "-q", "up", "master", cwd=h_tree)
old = git("rev-parse", "HEAD", cwd=h_clone)
reply = ask({"action": "get", "target": "github.com/o/history", "update": True, "lazy": True}, file_cfg)
commits = brought_in(h_clone, old)
merges = offline(h_clone, "rev-list", "--merges", f"{old}..HEAD").stdout.split()
if reply["exit"] != 0 or len(commits) != 5 or len(merges) != 1:
    failures.append(f"history fixture: the update must bring in 5 commits with one merge: {commits} {merges} {reply}")
if unreadable(h_clone, commits) or f"hydrated history: {os.path.realpath(h_clone)} (" not in reply["stdout"]:
    failures.append(f"an update must make every commit it brought in readable as a diff: "
                    f"unreadable {unreadable(h_clone, commits)}, {reply}")
with open(os.path.join(h_clone, ".git", "shallow")) as handle:
    if handle.read() != h_boundary:
        failures.append("an update's history hydrate must keep the clone's shallow boundaries")
if git("config", "--get", "remote.origin.partialclonefilter", cwd=h_clone) != "blob:none":
    failures.append("an update's history hydrate must keep the clone's filter")
if not (history_token(reply) or "").startswith("hydrated:"):
    failures.append(f"the exit log line must carry history=hydrated:<n>: {reply['log']!r}")
if len(packs(h_clone)) > 1:
    failures.append(f"the maintenance after the history fetch must consolidate its pack: {packs(h_clone)}")
git("branch", "-q", "-m", "master", "main", cwd=h_bare)
git("symbolic-ref", "HEAD", "refs/heads/main", cwd=h_bare)
git("branch", "-q", "-m", "master", "main", cwd=h_tree)
change(h_tree, "seven", f="seven\n")
change(h_tree, "eight", f="eight\n")
git("push", "-q", "up", "main", cwd=h_tree)
old = git("rev-parse", "HEAD", cwd=h_clone)
reply = ask({"action": "get", "target": "github.com/o/history", "update": True, "lazy": True}, file_cfg)
commits = brought_in(h_clone, old)
if (reply["exit"] != 0 or "default branch: master -> main" not in reply["stdout"] or len(commits) != 2
        or unreadable(h_clone, commits) or "hydrated history:" not in reply["stdout"]):
    failures.append(f"an update following a renamed default branch must make its new commits readable: "
                    f"{commits} unreadable {unreadable(h_clone, commits)}, {reply}")

# An update of a full clone, or one that brings in nothing, walks no history.
n_tree, n_bare = upstream("history-full")
n_clone = os.path.join(root, "github.com", "o", "history-full")
git("clone", "-q", "--no-tags", f"file://{n_bare}", n_clone)
change(n_tree, "more", f="more\n")
git("push", "-q", "up", "master", cwd=n_tree)
for case, target in (("a full clone", "github.com/o/history-full"), ("an update bringing in nothing", "github.com/o/history")):
    reply = ask({"action": "get", "target": target, "update": True, "lazy": True}, file_cfg)
    if reply["exit"] != 0 or history_lines(reply) or history_token(reply):
        failures.append(f"{case} must walk no history: {reply}")

# An update bringing in more missing blobs than the limit fetches none and says
# so, and its walk stops once the count passes the limit: no merge listing runs,
# and fewer ids are checked than the first-parent listing names (seven).
l_tree, _, l_clone = lazy_clone_of("history-limit")
for i in range(6):
    change(l_tree, f"limit{i}", f=f"limit{i}\n")
git("push", "-q", "up", "master", cwd=l_tree)
calls = os.path.join(work, "history-limit-calls.jsonl")
recording = ("import json, os\n"
             "real_run = handler.run\n"
             "def run(argv, env, *rest, **options):\n"
             "    stdin = options.get('stdin', rest[0] if rest else None) or b''\n"
             f"    with open({calls!r}, 'a') as handle:\n"
             "        handle.write(json.dumps({'argv': [os.fsdecode(a) for a in argv], 'stdin': stdin.decode()}) + '\\n')\n"
             "    return real_run(argv, env, *rest, **options)\n"
             "handler.run = run\n")
old = git("rev-parse", "HEAD", cwd=l_clone)
reply = finish(*start({"action": "get", "target": "github.com/o/history-limit", "update": True, "lazy": True},
                      config(protocols=("file",), history_limit=2), recording))
with open(calls) as handle:
    recorded = [json.loads(line) for line in handle]
checked = sum(len(call["stdin"].split()) for call in recorded if "--batch-check" in " ".join(call["argv"]))
expected = (f"history not hydrated: {os.path.realpath(l_clone)} (more than 2 blobs missing;"
            " ghq-sync --hydrate REV makes a revision readable)\n")
if (reply["exit"] != 0 or expected not in reply["stdout"] or history_token(reply) != "not-hydrated"
        or git("rev-parse", "HEAD", cwd=l_clone) != git("rev-parse", "master", cwd=l_tree)):
    failures.append(f"an update past the history limit must succeed and say it hydrated nothing: {reply}")
if len(unreadable(l_clone, brought_in(l_clone, old))) < 3:
    failures.append("an update past the history limit must fetch no blob for its range")
if any("--merges" in call["argv"] or "--stdin" in call["argv"] for call in recorded) or not 0 < checked < 7:
    failures.append(f"the walk must stop once the count passes the limit: {checked} ids checked, {recorded}")

# A history fetch that fails leaves the update's exit status and says so: the
# remote's upload-pack refuses any request that wants a blob of the range's
# older commits, which only the history fetch asks for.
d_tree, _, d_clone = lazy_clone_of("history-refused")
for i in range(3):
    change(d_tree, f"refused{i}", f=f"refused{i}\n")
git("push", "-q", "up", "master", cwd=d_tree)
refused_ids = os.path.join(work, "refused-ids")
put(refused_ids, "\n".join(git("rev-parse", f"master~{n}:f", cwd=d_tree) for n in (1, 2)) + "\n")
refusing = os.path.join(work, "refusing-upload-pack")
put(refusing, f"#!{sys.executable}\n" + """import os, subprocess, sys
refused = open(REFUSED).read().split()
child = subprocess.Popen(["git", "upload-pack", *sys.argv[1:]], stdin=subprocess.PIPE)
seen = b""
while chunk := os.read(0, 65536):
    seen += chunk
    if any(oid.encode() in seen for oid in refused):
        child.kill()
        sys.exit(1)
    child.stdin.write(chunk)
    child.stdin.flush()
child.stdin.close()
sys.exit(child.wait())
""".replace("REFUSED", repr(refused_ids)))
os.chmod(refusing, 0o755)
git("config", "remote.origin.uploadpack", refusing, cwd=d_clone)
old = git("rev-parse", "HEAD", cwd=d_clone)
reply = ask({"action": "get", "target": "github.com/o/history-refused", "update": True, "lazy": True}, file_cfg)
if (reply["exit"] != 0 or f"history hydrate failed: {os.path.realpath(d_clone)} (git fetch exited " not in reply["stdout"]
        or history_token(reply) != "failed" or " reason: " in reply["log"]
        or git("rev-parse", "HEAD", cwd=d_clone) != git("rev-parse", "master", cwd=d_tree)):
    failures.append(f"a failed history fetch must leave the update's exit status and say so: {reply}")
if not unreadable(d_clone, brought_in(d_clone, old)):
    failures.append("history fixture: the refused blobs arrived, so the failure case is vacuous")

# A deepen makes every commit it brought in, but the new deepest, readable as a diff.
e_tree, e_bare = upstream("history-deepen")
for i in range(3):
    change(e_tree, f"deepen{i}", f=f"deepen{i}\n")
git("push", "-q", "up", "master", cwd=e_tree)
e_clone = os.path.join(root, "github.com", "o", "history-deepen")
git("clone", "-q", "--depth", "1", "--filter=blob:none", "--no-tags", f"file://{e_bare}", e_clone)
old_boundary = git("rev-parse", "HEAD", cwd=e_clone)
reply = ask({"action": "deepen", "depth": 2, "path": e_clone}, file_cfg)
deepened = offline(e_clone, "rev-list", "HEAD").stdout.split()
if (reply["exit"] != 0 or len(deepened) != 3 or deepened[0] != old_boundary
        or f"hydrated history: {os.path.realpath(e_clone)} (" not in reply["stdout"]):
    failures.append(f"a deepen must make the commits it brought in readable: {deepened} {reply}")
if unreadable(e_clone, deepened[:2]):
    failures.append(f"a deepen must make every commit it brought in but the new deepest readable: "
                    f"unreadable {unreadable(e_clone, deepened[:2])}")
if git("config", "--get", "remote.origin.partialclonefilter", cwd=e_clone) != "blob:none":
    failures.append("a deepen's history hydrate must keep the clone's filter")

# A first lazy acquisition fetches no blob beyond its tip's tree: the clone
# holds one commit and only the blobs of that commit's tree, and the reply holds
# no history line.
a_tree, a_bare = upstream("first")
change(a_tree, "g", g="first g\n")
git("push", "-q", "up", "master", cwd=a_tree)
first_cfg = config(protocols=("https", "file"))
first_rewrite = f"url.file://{a_bare.removesuffix('.git')}.insteadOf=https://github.com/o/first"
reply = finish(*start({"action": "get", "target": "https://github.com/o/first.git", "lazy": True}, first_cfg,
                      f"handler.LFS_POLICY = handler.LFS_POLICY + [{first_rewrite!r}]"))
a_clone = os.path.join(root, "github.com", "o", "first")
held = offline(a_clone, "cat-file", "--batch-all-objects", "--batch-check=%(objectname) %(objecttype)").stdout.split("\n")
held_blobs = {line.split()[0] for line in held if line.endswith(" blob")}
tip_blobs = {line.split()[2] for line in offline(a_clone, "ls-tree", "-r", "HEAD").stdout.splitlines()}
listed = offline(a_clone, "rev-list", "--objects", "--missing=print", "HEAD").stdout.splitlines()
if (reply["exit"] != 0 or history_lines(reply) or offline(a_clone, "rev-list", "--count", "HEAD").stdout.strip() != "1"
        or any(line.startswith("?") for line in listed) or not held_blobs or held_blobs != tip_blobs):
    failures.append(f"a first lazy acquisition must fetch nothing beyond its tip's tree: "
                    f"blobs {held_blobs} tip {tip_blobs} listed {listed} {reply}")

# Hydrating a commit and then each of its parents makes its diff readable, and
# the commit alone does not: with historyLimit 0 the update hydrates no range.
g_tree, _, g_clone = lazy_clone_of("history-parents")
for i in range(3):
    change(g_tree, f"parents{i}", f=f"parents{i}\n")
git("push", "-q", "up", "master", cwd=g_tree)
reply = ask({"action": "get", "target": "github.com/o/history-parents", "update": True, "lazy": True},
            config(protocols=("file",), history_limit=0))
commit_x = git("rev-parse", "HEAD~1", cwd=g_clone)
parent_x = git("rev-parse", "HEAD~2", cwd=g_clone)
if "history not hydrated:" not in reply["stdout"] or not unreadable(g_clone, [commit_x]):
    failures.append(f"historyLimit 0 must leave the range unhydrated, so the case is not vacuous: {reply}")
ask({"action": "hydrate", "rev": commit_x, "path": g_clone}, file_cfg)
if not unreadable(g_clone, [commit_x]):
    failures.append("hydrating a commit alone must not make its diff readable while a parent's blob is missing")
ask({"action": "hydrate", "rev": parent_x, "path": g_clone}, file_cfg)
if unreadable(g_clone, [commit_x]):
    failures.append("hydrating a commit and its parent must make its diff readable")

if failures:
    sys.exit("\n".join(failures))
print("ghq-writer-handler: all request classes behaved")
