"""Drive ghq-writer-handler's report of a shallow boundary on a failed update over a socket pair, as its service would.

An update that fails while a commit the copy holds without its history lies
between the local branch and upstream's keeps git's refusal, names that commit
and the deepen that repairs it, and leaves the copy as the failed update left
it; an update failing for another reason, or whose finding fails, says nothing
of a boundary. The named deepen hides nothing the copy held, where a sized one
does; the next update then fast-forwards, or, where upstream rewrote its
branch, still fails, now without the line.
"""

import os
import re

from handler_fixtures import (
    ask,
    change,
    failures,
    file_cfg,
    finish,
    git,
    lazy_clone_of,
    offline,
    present,
    report,
    root,
    start,
    upstream,
)


def full_clone_of(bare, name):
    """A blobless clone of bare with its whole history under the root, after an update wrote its record."""
    clone_dir = os.path.join(root, "github.com", "o", name)
    git("clone", "-q", "--filter=blob:none", "--no-tags", f"file://{bare}", clone_dir)
    ask({"action": "get", "target": f"github.com/o/{name}", "update": True}, file_cfg)
    return clone_dir


def shallow_entries(clone_dir):
    try:
        with open(os.path.join(clone_dir, ".git", "shallow")) as handle:
            return set(handle.read().split())
    except FileNotFoundError:
        return set()


def held_boundaries(clone_dir):
    """The boundaries that have a parent and whose every parent the clone holds: history it holds and hides."""
    found = set()
    for commit in shallow_entries(clone_dir):
        parents = [line.split()[1] for line in offline(clone_dir, "cat-file", "-p", commit).stdout.splitlines()
                   if line.startswith("parent ")]
        if parents and all(present(clone_dir, parent) for parent in parents):
            found.add(commit)
    return found


def ref_counts(clone_dir):
    """The commit each branch and remote-tracking branch names, with the number of commits it reaches."""
    refs = git("for-each-ref", "--format=%(refname) %(objectname)", "refs/heads", "refs/remotes", cwd=clone_dir)
    return {ref: (oid, int(offline(clone_dir, "rev-list", "--count", oid).stdout or 0))
            for ref, oid in (line.split() for line in refs.splitlines())}


def lost(clone_dir, before):
    """The refs whose commit, as before, reaches fewer commits than it did, with both counts."""
    now = {ref: int(offline(clone_dir, "rev-list", "--count", oid).stdout or 0) for ref, (oid, _) in before.items()}
    return {ref: (count, now[ref]) for ref, (_, count) in before.items() if now[ref] < count}


def state(clone_dir):
    """.git/shallow's bytes, every ref but the remote-tracking ones, and the files under .git outside objects and logs."""
    git_dir = os.path.join(clone_dir, ".git")
    try:
        with open(os.path.join(git_dir, "shallow"), "rb") as handle:
            shallow = handle.read()
    except FileNotFoundError:
        shallow = None
    refs = git("for-each-ref", "--format=%(refname) %(objectname)", cwd=clone_dir).splitlines()
    files = {os.path.relpath(os.path.join(d, n), git_dir) for d, ds, fs in os.walk(git_dir) for n in fs}
    return (shallow, git("symbolic-ref", "HEAD", cwd=clone_dir), git("rev-parse", "HEAD", cwd=clone_dir),
            sorted(r for r in refs if not r.startswith("refs/remotes/")),
            {f for f in files if not f.startswith(("objects/", "logs/", "refs/remotes/"))})


def changed(before, after, bare, clone_dir):
    """What the request changed beyond the failed update's own fetch: origin's refs moving to upstream's, new
    FETCH_HEAD or ORIG_HEAD, and the history record's rewrite."""
    found = []
    if before[:4] != after[:4]:
        found.append(f"shallow, HEAD or a ref other than origin's: {before[:4]} -> {after[:4]}")
    if git("rev-parse", "origin/master", cwd=clone_dir) != git("rev-parse", "master", cwd=bare):
        found.append("origin/master is not upstream's master")
    added = after[4] - before[4] - {"FETCH_HEAD", "ORIG_HEAD"}
    if added:
        found.append(f"new files under .git: {sorted(added)}")
    return found


def report_lines(clone_dir, commit):
    path = os.path.realpath(clone_dir)
    return (f"shallow boundary between the local branch and upstream's: {path} (the copy holds {commit} without its"
            f" history, and it lies between the local branch and upstream's origin/master)\n"
            f"to repair it: ghq-sync --deepen 1000000 {path} then ghq-sync -u {path} (that deepen hides none of the"
            f" history the copy holds, where a smaller one can; if the update still fails with git's fast-forward"
            f" refusal and without this line, upstream rewrote its branch and this boundary was not the cause;"
            f" ghq-sync --help, under --deepen, says what the deepen costs and names the other repair)\n")


def blocked(name, clone_dir, bare, commit):
    """Update the clone, which holds the commit without its history between its branch and upstream's, and check the
    reply and what it changed."""
    before = state(clone_dir)
    reply = ask({"action": "get", "target": f"github.com/o/{name}", "update": True}, file_cfg)
    if reply["exit"] != 1 or not re.search(r"^fatal: ", reply["stderr"], re.MULTILINE):
        failures.append(f"{name}: an update with a boundary between the branches must keep git's refusal: {reply}")
    if not reply["stderr"].endswith(report_lines(clone_dir, commit)):
        failures.append(f"{name}: an update with a boundary between the branches must name it and the repair: {reply}")
    if " boundary=blocked" not in reply["log"]:
        failures.append(f"{name}: an update with a boundary between the branches must log boundary=blocked: "
                        f"{reply['log']}")
    failures.extend(f"{name}: an update with a boundary between the branches must write nothing of its own: {found}"
                    for found in changed(before, state(clone_dir), bare, clone_dir))


def deepened(name, clone_dir):
    """Deepen the clone as the report says, and check that it hid nothing; the refs' counts before it."""
    counts = ref_counts(clone_dir)
    deepen = ask({"action": "deepen", "depth": 1_000_000, "path": clone_dir}, file_cfg)
    if deepen["exit"] != 0 or lost(clone_dir, counts) or held_boundaries(clone_dir):
        failures.append(f"{name}: the deepen the report names must hide nothing: lost {lost(clone_dir, counts)}, "
                        f"hidden below {held_boundaries(clone_dir)}, {deepen}")
    if git("config", "--get", "remote.origin.partialclonefilter", cwd=clone_dir) != "blob:none":
        failures.append(f"{name}: the deepen must keep the clone's filter")
    return counts


def repaired(name, clone_dir, bare):
    """Deepen the clone as the report says, then update it, and check that both hid nothing and the update landed."""
    counts = deepened(name, clone_dir)
    update = ask({"action": "get", "target": f"github.com/o/{name}", "update": True}, file_cfg)
    if (update["exit"] != 0 or " boundary=" in update["log"] or lost(clone_dir, counts)
            or git("rev-parse", "HEAD", cwd=clone_dir) != git("rev-parse", "master", cwd=bare)
            or offline(clone_dir, "--no-lazy-fetch", "fsck", "--connectivity-only").returncode):
        failures.append(f"{name}: after the deepen the update must fast-forward, every ref keeping its history: "
                        f"lost {lost(clone_dir, counts)}, {update}")


def failing_git(raised, when):
    """A patch under which the handler's git raises the exception raised names for a call whose arguments hold when."""
    return ("orig = handler.git\n"
            "def git(path, env, *args, **kw):\n"
            f"    if {when!r} in args:\n"
            f"        raise {raised}\n"
            "    return orig(path, env, *args, **kw)\n"
            "handler.git = git\n")


# A depth-1 blobless clone fetches, with tags, a tag at depth 1 on a branch
# upstream has not merged; upstream's master then moves onto the tag's commit.
t_tree, t_bare, t_clone = lazy_clone_of("boundary-tag")
ask({"action": "get", "target": "github.com/o/boundary-tag", "update": True}, file_cfg)
git("checkout", "-q", "-b", "far", cwd=t_tree)
change(t_tree, "far", g="far\n")
git("tag", "t-far", cwd=t_tree)
git("checkout", "-q", "master", cwd=t_tree)
git("push", "-q", "up", "t-far", cwd=t_tree)
ask({"action": "get", "target": "github.com/o/boundary-tag", "tags": True}, file_cfg)
git("merge", "-q", "--ff-only", "far", cwd=t_tree)
git("push", "-q", "up", "master", cwd=t_tree)
blocked("boundary-tag", t_clone, t_bare, git("rev-parse", "t-far", cwd=t_tree))

# Finding the boundary never changes the update's outcome: with the finding's
# first git unable to start, or its gap listing timing out, the blocked update
# replies as git leaves it, with no line, no token and nothing written.
for fault, patch in (("a git that cannot start", failing_git("FileNotFoundError(2, 'No such file', 'git')",
                                                             "--symbolic-full-name")),
                     ("a listing that times out", failing_git("handler.TimedOut('git rev-list timed out')", "^HEAD"))):
    before = state(t_clone)
    reply = finish(*start({"action": "get", "target": "github.com/o/boundary-tag", "update": True}, file_cfg,
                          patch=patch))
    if (reply["exit"] != 1 or "fatal: " not in reply["stderr"] or "shallow boundary" in reply["stderr"]
            or " boundary=" in reply["log"] or " reason: ghq get exited 1" not in reply["log"]
            or changed(before, state(t_clone), t_bare, t_clone)):
        failures.append(f"with {fault} finding the boundary, the update must keep git's outcome alone: {reply}")

repaired("boundary-tag", t_clone, t_bare)

# A blobless clone with master's whole history fetches by id, at depth 1, the
# second commit of a branch grown from master's tip; upstream's master then
# moves onto it. A sized deepen of a twin clone lands on master's history, which
# the clone held, and hides it.
h_tree, h_bare = upstream("boundary-held")
git("config", "uploadpack.allowAnySHA1InWant", "true", cwd=h_bare)
for i in range(3):
    change(h_tree, f"held{i}", f=f"held{i}\n")
git("push", "-q", "up", "master", cwd=h_tree)
h_clones = {name: full_clone_of(h_bare, name) for name in ("boundary-held", "boundary-held-sized")}
change(h_tree, "late1", g="late1\n")
change(h_tree, "late2", g="late2\n")
late = git("rev-parse", "HEAD", cwd=h_tree)
git("push", "-q", "up", "master:refs/keep/late", cwd=h_tree)
for h_clone in h_clones.values():
    git("fetch", "-q", "--depth=1", "--no-tags", "origin", late, cwd=h_clone)
git("push", "-q", "up", "master", cwd=h_tree)
blocked("boundary-held", h_clones["boundary-held"], h_bare, late)
repaired("boundary-held", h_clones["boundary-held"], h_bare)
s_clone = h_clones["boundary-held-sized"]
s_counts = ref_counts(s_clone)
reply = ask({"action": "deepen", "depth": 2, "path": s_clone}, file_cfg)
if reply["exit"] != 0 or not lost(s_clone, s_counts):
    failures.append(f"a deepen of 2 below the late branch's tip must hide master's history, which the clone held: "
                    f"{ref_counts(s_clone)} {reply}")

# A blobless clone holding upstream's first three commits whole fetches the fifth
# by id at depth 1, and upstream's master moves to the sixth, the shape in which
# a fetch at the root's own depth makes the root a boundary.
r_tree, r_bare = upstream("boundary-root")
git("config", "uploadpack.allowAnySHA1InWant", "true", cwd=r_bare)
r_clone = full_clone_of(r_bare, "boundary-root")
for i in range(3):
    change(r_tree, f"root{i}", f=f"root{i}\n")
git("push", "-q", "up", "master", cwd=r_tree)
fifth = git("rev-parse", "master~1", cwd=r_tree)
git("fetch", "-q", "--depth=1", "--no-tags", "origin", fifth, cwd=r_clone)
blocked("boundary-root", r_clone, r_bare, fifth)
repaired("boundary-root", r_clone, r_bare)
if shallow_entries(r_clone):
    failures.append(f"the deepen the report names must leave no boundary, the root included: "
                    f"{shallow_entries(r_clone)}")

# Upstream rewrites master onto a branch forked three commits below the local
# tip, past a commit of that branch the clone fetched by id at depth 1. The
# clone cannot tell this from a branch that moved past the commit, so the
# update gets the two lines; the named deepen hides nothing, and the update
# after it still fails, now without the line.
w_tree, w_bare = upstream("boundary-rewritten")
git("config", "uploadpack.allowAnySHA1InWant", "true", cwd=w_bare)
for i in range(3):
    change(w_tree, f"kept{i}", f=f"kept{i}\n")
git("push", "-q", "up", "master", cwd=w_tree)
w_clone = full_clone_of(w_bare, "boundary-rewritten")
git("checkout", "-q", "-b", "far", "master~3", cwd=w_tree)
change(w_tree, "far1", g="far1\n")
far = git("rev-parse", "HEAD", cwd=w_tree)
git("push", "-q", "up", "far:refs/keep/far", cwd=w_tree)
git("fetch", "-q", "--depth=1", "--no-tags", "origin", far, cwd=w_clone)
change(w_tree, "far2", g="far2\n")
git("push", "-q", "-f", "up", "far:master", cwd=w_tree)
blocked("boundary-rewritten", w_clone, w_bare, far)
w_counts = deepened("boundary-rewritten", w_clone)
reply = ask({"action": "get", "target": "github.com/o/boundary-rewritten", "update": True}, file_cfg)
if (reply["exit"] != 1 or "shallow boundary" in reply["stderr"] or " boundary=" in reply["log"]
        or lost(w_clone, w_counts)):
    failures.append(f"after the deepen, an update upstream rewrote must still fail, without the line: {reply}")

# An update of a depth-1 clone, its boundary the local tip, that fails because
# upstream rewrote master says nothing of a boundary.
o_tree, _, o_clone = lazy_clone_of("boundary-other")
git("commit", "-q", "--amend", "-m", "rewritten", cwd=o_tree)
git("push", "-q", "-f", "up", "master", cwd=o_tree)
reply = ask({"action": "get", "target": "github.com/o/boundary-other", "update": True}, file_cfg)
if reply["exit"] == 0 or "shallow boundary" in reply["stderr"] or " boundary=" in reply["log"]:
    failures.append(f"an update failing for another reason must say nothing of a boundary: {reply}")

report("ghq-writer-handler: every boundary case behaved")
