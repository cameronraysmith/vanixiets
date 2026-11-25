"""Drive ghq-writer-handler over a socket pair, as its service would.

Every refused request class must be refused without touching the shared root,
an unauthorized caller must be refused, and one accepted request (deepen over a
file:// fixture) must change the repository it names. An update that changes an
LFS path fast-forwards to its pointer file, and hydrate fetches the blobs a
revision needs.
"""

import grp
import hashlib
import importlib.machinery
import json
import os
import socket
import subprocess
import sys
import tempfile
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


def config(group=own_group, protocols=("https",)):
    path = os.path.join(work, f"config-{group}-{'-'.join(protocols)}.json")
    with open(path, "w") as handle:
        json.dump({"root": root, "group": group, "allowedProtocols": list(protocols)}, handle)
    return path


def ask(request, cfg):
    ours, theirs = socket.socketpair()
    # launchd starts each inetd-style handler with umask 022 whatever the job's Umask
    # key says; the handler must set the writer's umask itself.
    proc = subprocess.Popen([HANDLER, cfg], stdin=theirs, stdout=theirs, preexec_fn=lambda: os.umask(0o022))
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
