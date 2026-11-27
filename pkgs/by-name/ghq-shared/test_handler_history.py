"""Drive ghq-writer-handler's history fetch over a socket pair, as its service would.

A request that brings commits into a blobless clone's branches or below a
removed shallow boundary makes each readable as a diff, up to the history
limit, with the filter the clone records; a request that brings in nothing walks
nothing; tags fetched at depth 1 stay unhydrated until a branch reaches them;
every failure in the history phases, whatever it raises, leaves the request's
outcome and logs history=failed; a first acquisition fetches nothing more.
"""

import json
import os
import subprocess
import sys

from handler_fixtures import (
    ask,
    brought_in,
    change,
    config,
    failures,
    file_cfg,
    finish,
    git,
    history_lines,
    history_token,
    lazy_clone_of,
    offline,
    packs,
    put,
    report,
    root,
    start,
    unreadable,
    upstream,
    work,
)

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
if any("--merges" in call["argv"] or "--no-write-fetch-head" in call["argv"] for call in recorded) or not 0 < checked < 7:
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
if (reply["exit"] != 0 or f"history hydrate failed: {os.path.realpath(d_clone)} (walk: git fetch exited " not in reply["stdout"]
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

def clone_of(bare, name):
    """A depth-1 blobless clone of bare under the root, where target github.com/o/<name> names it."""
    clone_dir = os.path.join(root, "github.com", "o", name)
    git("clone", "-q", "--depth", "1", "--filter=blob:none", "--no-tags", f"file://{bare}", clone_dir)
    return clone_dir


def recorded_calls(path):
    with open(path) as handle:
        return [json.loads(line) for line in handle]


# A deepen also moves the remote-tracking branch to the commits upstream gained
# since the last update: those, and the deepened ones but the new deepest, are
# readable as diffs. The clone also holds a shallow boundary for each of 200
# root commits fetched at depth 1, which the walk excludes: no git the handler
# starts gets one of them as an argument, and the walk's git log reads them on
# standard input, so their number is bounded by no argument list.
t_tree, t_bare = upstream("history-deepen-tip")
git("config", "uploadpack.allowAnySHA1InWant", "true", cwd=t_bare)
marks = os.path.join(work, "history-deepen-tip-marks")
plain_env = dict(os.environ, GIT_CONFIG_NOSYSTEM="1", GIT_CONFIG_GLOBAL="/dev/null")
subprocess.run(["git", "fast-import", "--quiet", f"--export-marks={marks}"], cwd=t_bare, env=plain_env, check=True,
               input="".join(f"reset refs/roots\ncommit refs/roots\nmark :{i + 1}\ncommitter t <t@t> {i} +0000\n"
                             "data 0\n\n" for i in range(200)).encode())
with open(marks) as handle:
    root_ids = [line.split()[1] for line in handle]
t_clone = clone_of(t_bare, "history-deepen-tip")
subprocess.run(["git", "-c", "protocol.file.allow=always", "fetch", "-q", "--depth", "1", "--stdin", "origin"],
               cwd=t_clone, env=plain_env, check=True, input="".join(f"{oid}\n" for oid in root_ids).encode())
for i in range(3):
    change(t_tree, f"tip{i}", f=f"tip{i}\n")
git("push", "-q", "up", "master", cwd=t_tree)
with open(os.path.join(t_clone, ".git", "shallow")) as handle:
    held_boundaries = set(handle.read().split())
deepen_calls = os.path.join(work, "history-deepen-tip-calls.jsonl")
reply = finish(*start({"action": "deepen", "depth": 2, "path": t_clone}, file_cfg,
                      recording.replace(repr(calls), repr(deepen_calls))))
tip = offline(t_clone, "rev-list", "HEAD..origin/master").stdout.split()
deepened = offline(t_clone, "rev-list", "HEAD").stdout.split()
if (not set(root_ids) <= held_boundaries or reply["exit"] != 0 or len(tip) != 3 or len(deepened) != 3
        or not (history_token(reply) or "").startswith("hydrated:")):
    failures.append(f"deepen-tip fixture: the deepen must move origin/master by 3 and deepen by 2 past 200 boundaries: "
                    f"{tip} {deepened} {reply}")
if unreadable(t_clone, tip + deepened[:2]):
    failures.append(f"a deepen must make the commits it moved origin/master to readable: "
                    f"unreadable {unreadable(t_clone, tip + deepened[:2])}")
roots_set = set(root_ids)
deepen_recorded = recorded_calls(deepen_calls)
in_argv = [call["argv"][:6] for call in deepen_recorded if any(arg.lstrip("^") in roots_set for arg in call["argv"])]
on_stdin = [call for call in deepen_recorded if "log" in call["argv"] and "--stdin" in call["argv"]
            and roots_set <= {line.lstrip("^") for line in call["stdin"].split()}]
if in_argv or not on_stdin:
    failures.append(f"the walk must give git the clone's boundaries on standard input and never as arguments: "
                    f"{len(in_argv)} calls with a boundary in argv {in_argv[:2]}, {len(on_stdin)} git log --stdin calls")

# A get with tags of a shallow clone fetches its branches first: the commits
# origin/master gains are readable, while a tag commit fetched at depth 1 is
# left for ghq-sync --hydrate.
u_tree, u_bare = upstream("history-tags")
u_clone = clone_of(u_bare, "history-tags")
o_clone = clone_of(u_bare, "history-tag-timeout")
for i in range(2):
    change(u_tree, f"gain{i}", f=f"gain{i}\n")
git("checkout", "-q", "-b", "far", "HEAD~3", cwd=u_tree)
change(u_tree, "far", f="far\n")
git("tag", "t-far", cwd=u_tree)
git("checkout", "-q", "master", cwd=u_tree)
git("push", "-q", "up", "master", "t-far", cwd=u_tree)
reply = ask({"action": "get", "target": "github.com/o/history-tags", "tags": True}, file_cfg)
gained = offline(u_clone, "rev-list", "HEAD..origin/master").stdout.split()
if (reply["exit"] != 0 or len(gained) != 2 or unreadable(u_clone, gained)
        or not (history_token(reply) or "").startswith("hydrated:")):
    failures.append(f"a get with tags must make the commits origin/master gained readable: {gained} "
                    f"unreadable {unreadable(u_clone, gained)}, {reply}")
if offline(u_clone, "rev-parse", "-q", "--verify", "t-far^{commit}").returncode or not unreadable(u_clone, ["t-far"]):
    failures.append("a tag commit fetched at depth 1 must arrive and stay unhydrated")

# A command after the history fetch that outlasts the command timeout, here the
# fetch of a tag at depth 1, whose upload-pack hangs, leaves the history fetch's
# status line in the reply and its token on the exit log line. The limit of 2 s
# leaves every other command of the request, each through a Python upload-pack
# wrapper, a margin to finish within it.
stalled_ids = os.path.join(work, "stalled-ids")
put(stalled_ids, git("rev-parse", "t-far", cwd=u_tree) + "\n")
stalling = os.path.join(work, "stalling-upload-pack")
put(stalling, f"#!{sys.executable}\n" + """import os, subprocess, sys, time
stalled = open(STALLED).read().split()
child = subprocess.Popen(["git", "upload-pack", *sys.argv[1:]], stdin=subprocess.PIPE)
seen = b""
while chunk := os.read(0, 65536):
    seen += chunk
    if any(oid.encode() in seen for oid in stalled):
        time.sleep(60)
    child.stdin.write(chunk)
    child.stdin.flush()
child.stdin.close()
sys.exit(child.wait())
""".replace("STALLED", repr(stalled_ids)))
os.chmod(stalling, 0o755)
git("config", "remote.origin.uploadpack", stalling, cwd=o_clone)
reply = finish(*start({"action": "get", "target": "github.com/o/history-tag-timeout", "update": True, "tags": True,
                       "lazy": True}, config(protocols=("file",), command_timeout=2)), within=60)
if (reply["exit"] != 124 or not (history_token(reply) or "").startswith("hydrated:")
        or f"hydrated history: {os.path.realpath(o_clone)} (" not in reply["stdout"]
        or " reason: timed out after 2 s running git fetch" not in reply["log"]):
    failures.append(f"a timeout after the history fetch must keep its status line and token: {reply}")

# The history fetch passes the filter the clone records, and a promisor clone
# that records none gets no history fetch, which would record one. An error
# starting git in the history walk is the history fetch's failure, not the
# request's. The three clones share one upstream.
k_tree, k_bare = upstream("history-filter")
k_clone = clone_of(k_bare, "history-limit-filter")
v_clone = clone_of(k_bare, "history-no-filter")
w_clone = clone_of(k_bare, "history-oserror")
git("config", "remote.origin.partialclonefilter", "blob:limit=1", cwd=k_clone)
git("config", "--unset-all", "remote.origin.partialclonefilter", cwd=v_clone)
old = git("rev-parse", "HEAD", cwd=k_clone)
for i in range(2):
    change(k_tree, f"kept{i}", f=f"kept{i}\n")
git("push", "-q", "up", "master", cwd=k_tree)
reply = ask({"action": "get", "target": "github.com/o/history-limit-filter", "update": True}, file_cfg)
if (reply["exit"] != 0 or unreadable(k_clone, brought_in(k_clone, old))
        or git("config", "--get", "remote.origin.partialclonefilter", cwd=k_clone) != "blob:limit=1"):
    failures.append(f"the history fetch must keep the clone's recorded filter: "
                    f"{offline(k_clone, 'config', '--get-all', 'remote.origin.partialclonefilter').stdout!r} {reply}")
no_filter_calls = os.path.join(work, "history-no-filter-calls.jsonl")
reply = finish(*start({"action": "get", "target": "github.com/o/history-no-filter", "update": True}, file_cfg,
                      recording.replace(repr(calls), repr(no_filter_calls))))
history_calls = [call["argv"] for call in recorded_calls(no_filter_calls)
                 if "--no-write-fetch-head" in call["argv"] or "log" in call["argv"]]
expected = f"history not hydrated: {os.path.realpath(v_clone)} (the clone records no partial-clone filter;"
recorded_filter = offline(v_clone, "config", "--get-all", "remote.origin.partialclonefilter")
if (reply["exit"] != 0 or expected not in reply["stdout"] or history_token(reply) != "not-hydrated"
        or recorded_filter.returncode != 1 or history_calls):
    failures.append(f"a promisor clone recording no filter must get no history fetch and keep its configuration: "
                    f"{recorded_filter.stdout!r} {history_calls} {reply}")
failing_log = ("real_run = handler.run\n"
               "def run(argv, env, *rest, **options):\n"
               "    if 'log' in argv:\n"
               "        raise OSError(7, 'Argument list too long', 'git')\n"
               "    return real_run(argv, env, *rest, **options)\n"
               "handler.run = run\n")
reply = finish(*start({"action": "get", "target": "github.com/o/history-oserror", "update": True}, file_cfg, failing_log))
if (reply["exit"] != 0 or history_token(reply) != "failed" or " reason: " in reply["log"]
        or f"history hydrate failed: {os.path.realpath(w_clone)} (walk: OSError)" not in reply["stdout"]):
    failures.append(f"an error starting git in the history walk must leave the update's exit status: {reply}")

# A request that brings no commit in walks nothing, lists nothing and fetches
# nothing, whichever refs it moved: upstream force-resets master to an ancestor
# the copy holds, adds a branch at a commit the copy holds, and deletes one. The
# copy is blobless with its whole history and every branch.
z_tree, z_bare = upstream("history-nothing")
git("branch", "other", cwd=z_tree)
git("push", "-q", "up", "other", cwd=z_tree)
z_clone = os.path.join(root, "github.com", "o", "history-nothing")
git("clone", "-q", "--filter=blob:none", "--no-tags", f"file://{z_bare}", z_clone)
git("config", "fetch.prune", "true", cwd=z_clone)
for case, move in (("a force-reset to an ancestor", ["push", "-q", "--force", "up", "HEAD~1:master"]),
                   ("a new branch at a commit the copy holds", ["push", "-q", "up", "HEAD~2:refs/heads/again"]),
                   ("a deleted branch", ["push", "-q", "up", ":other"])):
    git(*move, cwd=z_tree)
    before_refs = git("for-each-ref", "--format=%(refname) %(objectname)", "refs/remotes", cwd=z_clone)
    nothing_calls = os.path.join(work, f"history-nothing-{len(case)}.jsonl")
    reply = finish(*start({"action": "get", "target": "github.com/o/history-nothing", "update": True}, file_cfg,
                          recording.replace(repr(calls), repr(nothing_calls))))
    walked = [call["argv"] for call in recorded_calls(nothing_calls)
              if "log" in call["argv"] or "--no-write-fetch-head" in call["argv"]]
    moved = git("for-each-ref", "--format=%(refname) %(objectname)", "refs/remotes", cwd=z_clone) != before_refs
    if reply["exit"] != 0 or not moved or history_lines(reply) or history_token(reply) or walked:
        failures.append(f"{case} brings in nothing and must walk nothing: moved {moved}, walked {walked}, {reply}")

# Nothing in the history phases fails a request: a remote-tracking ref whose
# name is not UTF-8, held packed, is read like any other; an exception raised
# while reading the refs before the fetch, or while walking after it, ends as
# history=failed naming the phase and the exception's type alone, with the
# update done and no traceback.
x_tree, x_bare = upstream("history-guarded")
x_clones = {name: clone_of(x_bare, name) for name in ("history-latin1", "history-snapshot-error", "history-walk-error")}
with open(os.path.join(x_clones["history-latin1"], ".git", "packed-refs"), "ab") as handle:
    head_id = git("rev-parse", "HEAD", cwd=x_clones["history-latin1"])
    handle.write(head_id.encode() + b" refs/remotes/origin/caf\xe9\n")
change(x_tree, "guarded", f="guarded\n")
git("push", "-q", "up", "master", cwd=x_tree)
upstream_head = git("rev-parse", "master", cwd=x_tree)
reply = ask({"action": "get", "target": "github.com/o/history-latin1", "update": True}, file_cfg)
if (reply["exit"] != 0 or git("rev-parse", "HEAD", cwd=x_clones["history-latin1"]) != upstream_head
        or not (history_token(reply) or "").startswith("hydrated:")):
    failures.append(f"a ref name that is not UTF-8 must not fail the update or its history fetch: {reply}")
for name, phase, patch in (
        ("history-snapshot-error", "snapshot",
         "def branch_refs(*args):\n    raise RuntimeError('injected <secret>')\nhandler.branch_refs = branch_refs\n"),
        ("history-walk-error", "walk",
         "def missing_blobs(*args):\n    raise LookupError('injected <secret>')\nhandler.missing_blobs = missing_blobs\n")):
    reply = finish(*start({"action": "get", "target": f"github.com/o/{name}", "update": True}, file_cfg, patch))
    kind = "RuntimeError" if phase == "snapshot" else "LookupError"
    expected = f"history hydrate failed: {os.path.realpath(x_clones[name])} ({phase}: {kind})\n"
    if (reply["exit"] != 0 or expected not in reply["stdout"] or history_token(reply) != "failed"
            or " reason: " in reply["log"] or "Traceback" in reply["log"] or "secret" in reply["log"] + reply["stdout"]
            or git("rev-parse", "HEAD", cwd=x_clones[name]) != upstream_head):
        failures.append(f"an exception in the history {phase} must end as history=failed and leave the update: {reply}")

# A commit that only a tag fetched at depth 1 reaches stays unhydrated; once
# upstream merges its branch, a branch commit the update brings in reaches it,
# and it is hydrated like any other.
y_tree, y_bare, y_clone = lazy_clone_of("history-tag-merged")
git("checkout", "-q", "-b", "far", "HEAD~2", cwd=y_tree)
change(y_tree, "far", g="far\n")
git("tag", "t-merged", cwd=y_tree)
git("checkout", "-q", "master", cwd=y_tree)
git("push", "-q", "up", "master", "t-merged", cwd=y_tree)
reply = ask({"action": "get", "target": "github.com/o/history-tag-merged", "tags": True}, file_cfg)
if reply["exit"] != 0 or not unreadable(y_clone, ["t-merged"]):
    failures.append(f"a tag commit only a tag reaches must stay unhydrated: {reply}")
git("merge", "-q", "--no-ff", "-m", "merge far", "far", cwd=y_tree)
git("push", "-q", "up", "master", cwd=y_tree)
reply = ask({"action": "get", "target": "github.com/o/history-tag-merged", "update": True}, file_cfg)
if reply["exit"] != 0 or unreadable(y_clone, ["HEAD", "t-merged"]):
    failures.append(f"once a branch commit the update brings in reaches a tag's commit, it must be hydrated: "
                    f"unreadable {unreadable(y_clone, ['HEAD', 't-merged'])}, {reply}")

# A boundary present when a request begins counts as held, though the record,
# written by the walk before a tag fetch at depth 1 added it, does not name it:
# once upstream's master moves onto that tag's commit, the next update, whose
# fast-forward onto a depth-1 boundary fails while origin/master moves, walks
# nothing, rather than listing the commit's whole tree as a root commit's.
b_tree, _, b_clone = lazy_clone_of("history-start-boundary")
ask({"action": "get", "target": "github.com/o/history-start-boundary", "update": True}, file_cfg)
git("checkout", "-q", "-b", "far", cwd=b_tree)
change(b_tree, "far", g="far\n")
git("tag", "t-start", cwd=b_tree)
git("checkout", "-q", "master", cwd=b_tree)
git("push", "-q", "up", "t-start", cwd=b_tree)
ask({"action": "get", "target": "github.com/o/history-start-boundary", "tags": True}, file_cfg)
tag_commit = git("rev-parse", "t-start", cwd=b_tree)
with open(os.path.join(b_clone, ".git", "shallow")) as handle:
    tag_held = tag_commit in handle.read().split()
git("merge", "-q", "--ff-only", "far", cwd=b_tree)
git("push", "-q", "up", "master", cwd=b_tree)
reply = ask({"action": "get", "target": "github.com/o/history-start-boundary", "update": True}, file_cfg)
if not tag_held or git("rev-parse", "origin/master", cwd=b_clone) != tag_commit:
    failures.append(f"start-boundary fixture: the tag's commit must be a boundary and origin/master move onto it: {reply}")
elif history_lines(reply) or history_token(reply):
    failures.append(f"a branch moving onto a boundary present when the request began must walk nothing: {reply}")

# Every commit an update brings in reads as `git show` reads it, merges included,
# with rename detection on, as lazygit's --find-renames=50% has it: on a merge it
# diffs the merge against each parent and reads the blobs of the paths added or
# deleted there. The files gone, big and big3 enter history before the copies
# are cloned, and master deletes them, so no checkout fetches their blobs and no
# first-parent diff in the update names them; same holds gone's content, so that
# blob is present. master merges side, whose side of the diff still holds big
# (a file the first parent's side deleted), then side2b and side3 at once, whose
# third parent alone holds big3; other merges side2, whose side lacks x, which
# other added before the copies were cloned and no checkout of master fetched (a
# file added only on the mainline side). The update leaves four blobs to fetch:
# those of s2, big, big3 and x. A limit of 3 must then fetch none and say so, as
# for any range past it; a limit of 4 hydrates every one.
def lines(name):
    return "".join(f"{name} line {i}\n" for i in range(20))


def unreadable_shown(clone_dir, commits):
    """The commits a plain `git show`, with git's default rename detection, cannot read."""
    return [c for c in commits if offline(clone_dir, "--no-lazy-fetch", "show", c).returncode]


m_tree, m_bare = upstream("history-merges")
change(m_tree, "gone", gone=lines("same"), same=lines("same"))
m_bases = [git("rev-parse", "HEAD", cwd=m_tree)]
for name in ("big", "big3"):
    change(m_tree, name, **{name: lines(name)})
    m_bases.append(git("rev-parse", "HEAD", cwd=m_tree))
for branch, base in (("side2", 0), ("side2b", 0), ("side", 1), ("side3", 2)):
    git("checkout", "-q", "-b", branch, m_bases[base], cwd=m_tree)
    change(m_tree, branch, **{branch.replace("side", "s"): lines(branch)})
git("checkout", "-q", "master", cwd=m_tree)
for name in ("gone", "big", "big3"):
    os.remove(os.path.join(m_tree, name))
change(m_tree, "trim", new=lines("new"))
git("checkout", "-q", "-b", "other", cwd=m_tree)
change(m_tree, "x", x=lines("x"))
git("checkout", "-q", "master", cwd=m_tree)
git("push", "-q", "up", "master", "other", cwd=m_tree)
m_clones = {}
for name in ("history-merges", "history-merges-over", "history-merges-at"):
    m_clones[name] = os.path.join(root, "github.com", "o", name)
    git("clone", "-q", "--filter=blob:none", "--no-tags", f"file://{m_bare}", m_clones[name])
m_old = git("for-each-ref", "--format=^%(objectname)", "refs/remotes/origin", cwd=m_clones["history-merges"]).split()
git("merge", "-q", "--no-ff", "-m", "merge side", "side", cwd=m_tree)
git("merge", "-q", "--no-ff", "-m", "merge side2b and side3", "side2b", "side3", cwd=m_tree)
git("checkout", "-q", "other", cwd=m_tree)
git("merge", "-q", "--no-ff", "-m", "merge side2", "side2", cwd=m_tree)
git("checkout", "-q", "master", cwd=m_tree)
git("push", "-q", "up", "master", "other", cwd=m_tree)
for name, limit in (("history-merges", None), ("history-merges-over", 3), ("history-merges-at", 4)):
    clone_dir = m_clones[name]
    reply = ask({"action": "get", "target": f"github.com/o/{name}", "update": True},
                file_cfg if limit is None else config(protocols=("file",), history_limit=limit))
    gained = offline(clone_dir, "rev-list", "origin/master", "origin/other", *m_old).stdout.split()
    merged = offline(clone_dir, "rev-list", "--merges", "--parents", "origin/master", "origin/other", *m_old).stdout
    if reply["exit"] != 0 or len(gained) != 7 or sorted(len(m.split()) for m in merged.splitlines()) != [3, 3, 4]:
        failures.append(f"merge fixture: the update must bring in 7 commits, two merges and an octopus: {gained} {merged} {reply}")
    elif limit == 3:
        expected = (f"history not hydrated: {os.path.realpath(clone_dir)} (more than 3 blobs missing;"
                    " ghq-sync --hydrate REV makes a revision readable)\n")
        if expected not in reply["stdout"] or history_token(reply) != "not-hydrated" or len(unreadable(clone_dir, gained)) < 4:
            failures.append(f"the blobs a merge's other sides need must count against the history limit: "
                            f"unreadable {unreadable(clone_dir, gained)}, {reply}")
    elif unreadable(clone_dir, gained) or unreadable_shown(clone_dir, gained) or history_token(reply) != "hydrated:4":
        failures.append(f"every merge an update brings in must read with rename detection{'' if limit is None else ' at the limit'}: "
                        f"unreadable {unreadable(clone_dir, gained)}, by plain git show {unreadable_shown(clone_dir, gained)}, {reply}")

# A walk that ends `history not hydrated` still advances the record: the next
# update of the limit-3 clone, bringing nothing in, walks nothing, rather than
# walking the range past the limit again.
reply = ask({"action": "get", "target": "github.com/o/history-merges-over", "update": True},
            config(protocols=("file",), history_limit=3))
if reply["exit"] != 0 or history_lines(reply) or history_token(reply):
    failures.append(f"a walk past the limit must advance the record, so the next update walks nothing: {reply}")

# The writer hydrates, at the next request for a copy, what an earlier request
# brought in and did not hydrate. Its record is the copy's
# .git/ghq-writer-hydrated, naming the refs and shallow boundaries the last
# complete walk ended with.
RECORD = os.path.join(".git", "ghq-writer-hydrated")


def recorded_refs(clone_dir):
    """The refs the copy's record names, or None when it has none."""
    try:
        with open(os.path.join(clone_dir, RECORD)) as handle:
            return sorted(line.split()[1:] for line in handle if line.startswith("ref "))
    except FileNotFoundError:
        return None


def record_version(clone_dir):
    """The record's inode and modification time, which a rewrite changes, or None when it has none."""
    try:
        found = os.stat(os.path.join(clone_dir, RECORD))
    except FileNotFoundError:
        return None
    return found.st_ino, found.st_mtime_ns


def current_refs(clone_dir):
    return sorted(line.split()
                  for line in git("for-each-ref", "--format=%(objectname) %(refname)", "refs/heads", "refs/remotes",
                                  cwd=clone_dir).splitlines())


def update(name, cfg=file_cfg, patch=None):
    return finish(*start({"action": "get", "target": f"github.com/o/{name}", "update": True, "lazy": True}, cfg, patch),
                  within=60)


def left_behind(name, failing):
    """An update whose fetch moves origin/master and which then fails as failing says, and the next update, which
    brings nothing more in; the second's reply, and the commits the first brought in."""
    tree, _, clone_dir = lazy_clone_of(name)
    if update(name)["exit"] != 0:
        failures.append(f"{name}: the first update must succeed")
    for i in range(2):
        change(tree, f"{name}{i}", f=f"{name}{i}\n")
    git("push", "-q", "up", "master", cwd=tree)
    old = git("rev-parse", "HEAD", cwd=clone_dir)
    first = failing(tree, clone_dir)
    if (git("rev-parse", "origin/master", cwd=clone_dir) != git("rev-parse", "master", cwd=tree)
            or git("rev-parse", "HEAD", cwd=clone_dir) != old
            or not unreadable(clone_dir, offline(clone_dir, "rev-list", "HEAD..origin/master").stdout.split())):
        failures.append(f"{name}: the failing update must move origin/master alone and hydrate nothing: {first}")
    git("config", "--unset", "remote.origin.uploadpack", cwd=clone_dir)
    second = update(name)
    return second, clone_dir, brought_in(clone_dir, old)


def timed_out(tree, clone_dir):
    """The checkout's on-demand fetch of the new tip's blob stalls past the command timeout."""
    put(stalled_ids, git("rev-parse", "master:f", cwd=tree) + "\n")
    git("config", "remote.origin.uploadpack", stalling, cwd=clone_dir)
    reply = update(os.path.basename(clone_dir), config(protocols=("file",), command_timeout=2))
    if reply["exit"] != 124 or history_lines(reply):
        failures.append(f"the timed-out update must end before its history fetch: {reply}")
    return reply


def refused(tree, clone_dir):
    """The remote stops serving blobs after the update's fetch: the checkout and the history fetch both fail."""
    put(refused_ids, "\n".join(git("rev-parse", f"master~{n}:f", cwd=tree) for n in (0, 1)) + "\n")
    git("config", "remote.origin.uploadpack", refusing, cwd=clone_dir)
    reply = update(os.path.basename(clone_dir))
    if reply["exit"] in (0, None) or "history hydrate failed:" not in reply["stdout"]:
        failures.append(f"the refused update must fail, and its history fetch with it: {reply}")
    return reply


for name, failing in (("history-left-timeout", timed_out), ("history-left-refused", refused)):
    reply, clone_dir, commits = left_behind(name, failing)
    if (reply["exit"] != 0 or len(commits) != 2 or unreadable(clone_dir, commits)
            or not (history_token(reply) or "").startswith("hydrated:") or recorded_refs(clone_dir) != current_refs(clone_dir)):
        failures.append(f"{name}: the next update must hydrate what the failed one brought in and record its refs: "
                        f"{commits} unreadable {unreadable(clone_dir, commits)}, {reply}")

# A copy with no record gets one before the request's first fetch, from the refs
# the copy holds then, so a request killed with SIGKILL between its fetch and its
# history fetch leaves its commits to the next request. A request that brings
# nothing in leaves the record as it is. A record naming a commit the copy no
# longer holds is read without it: git's gc keeps the commits of a promisor pack,
# so a force-push and a gc do not remove one, and the case writes an id no
# object has into the record instead.
killing = "import os, signal\ndef walk_history(*args):\n    os.kill(os.getpid(), signal.SIGKILL)\nhandler.walk_history = walk_history\n"
k_tree, _, k_clone = lazy_clone_of("history-killed")
held_refs = current_refs(k_clone)
for i in range(2):
    change(k_tree, f"killed{i}", f=f"killed{i}\n")
git("push", "-q", "up", "master", cwd=k_tree)
old = git("rev-parse", "HEAD", cwd=k_clone)
reply = update("history-killed", patch=killing)
if reply["exit"] is not None or recorded_refs(k_clone) != held_refs:
    failures.append(f"a copy with no record must get one, naming the refs it held, before the request's first fetch: {reply}")
reply = update("history-killed")
commits = brought_in(k_clone, old)
if (reply["exit"] != 0 or len(commits) != 2 or unreadable(k_clone, commits)
        or not (history_token(reply) or "").startswith("hydrated:") or recorded_refs(k_clone) != current_refs(k_clone)):
    failures.append(f"the update after a killed one must hydrate what the killed one brought in: "
                    f"{commits} unreadable {unreadable(k_clone, commits)}, {reply}")
record_stat = record_version(k_clone)
reply = update("history-killed")
if (reply["exit"] != 0 or history_lines(reply) or history_token(reply) or record_stat is None
        or record_version(k_clone) != record_stat):
    failures.append(f"an update that brings nothing in must leave the record as it is: {reply}")
for i in range(2):
    change(k_tree, f"killed again{i}", f=f"killed again{i}\n")
git("push", "-q", "up", "master", cwd=k_tree)
old = git("rev-parse", "HEAD", cwd=k_clone)
update("history-killed", patch=killing)
vanished = subprocess.run(["git", "hash-object", "--stdin"], input=b"no such commit\n", capture_output=True,
                          check=True).stdout.decode().strip()
with open(os.path.join(k_clone, RECORD), "a") as handle:
    handle.write(f"ref {vanished} refs/remotes/origin/vanished\nshallow {vanished}\n")
reply = update("history-killed")
commits = brought_in(k_clone, old)
if (reply["exit"] != 0 or len(commits) != 2 or unreadable(k_clone, commits)
        or not (history_token(reply) or "").startswith("hydrated:") or recorded_refs(k_clone) != current_refs(k_clone)):
    failures.append(f"a record naming a commit the copy lacks must not fail the update or its history fetch: "
                    f"{commits} unreadable {unreadable(k_clone, commits)}, {reply}")

report("ghq-writer-handler: every history case behaved")
