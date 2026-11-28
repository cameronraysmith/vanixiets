"""Carry out one request against the shared ghq tree, as its sole writer.

Started once per connection by a socket-activated service (systemd Accept=yes,
launchd inetdCompatibility), with the connection on file descriptor 0. Reads one
JSON request, refuses anything outside a fixed action set, runs ghq or ghq-sync
without a shell, and writes one JSON reply {"stdout", "stderr", "exit"}. To a
client that sends {"accept": ["note"]} on a second line, lines {"note": TEXT}
may precede the reply while the request waits for its repository.

Requests for one repository run one at a time: each holds an exclusive flock on
a lock file in CONFIG's lockDir, named by the repository's path under the root,
for the whole operation. A request waits at most lockTimeout seconds for it.
A caller that disconnects does not stop the operation; its reply is dropped.

Git runs with no LFS filter, whatever a repository's own configuration says, so
every working tree holds LFS pointer files exactly as committed; readers' git
configuration applies the same policy to the shared root.

Every request leaves one log line on standard error at start, while it waits
and at exit, carrying the time, the handler's pid, the caller's uid and pid, the
verb and the repository, never the target as given, which may hold credentials.
The exit line of a failed request ends with its reason, naming any command by
its program and subcommand only.

Each command runs in a process group of its own; one that outlasts
commandTimeout seconds is stopped with every process it started, and its
request ends with a reply and an exit line like any other failure. Git's
automatic maintenance runs in the foreground with the gc strategy, so it is part
of the command, under the repository's lock.

A get of a clone already present, and a deepen, of a blobless clone then fetch,
still under the lock, every missing blob that the diff of each commit the
request brought into the clone's branches and remote-tracking branches, or below
a shallow boundary it removed, reads, as `git show` shows a commit with rename
detection, merges included, with the filter the clone records, unless more than
historyLimit are missing or the clone records no filter. What a request brought
in is measured from the refs and boundaries the clone's last complete history
walk ended with, recorded in .git/ghq-writer-hydrated, so a later request
hydrates what one that failed or was killed after its fetch left behind; a clone
with no record gets one from its refs before the request's first fetch. A
request that brought no commit in walks nothing. A commit only a tag fetched at
depth 1 reaches is left as it arrives, until a commit a branch gains reaches it;
`ghq-sync --hydrate TAG` makes one readable. One status line says what the
history fetch did. Any exception while reading the clone's refs before the
request or walking after it is the history fetch's failure: the request's exit
status stays as its other commands set it, and the exit log line adds
history=hydrated:<n>, history=not-hydrated or history=failed, on every path
after the history fetch.

An update that fails while a commit the clone holds without its history lies
between the local branch and its upstream keeps git's refusal and exit status;
two lines after it name that commit and the deepen that repairs it, and say
that an update still refused a fast-forward after it without that line
means upstream rewrote its branch. Finding the commit reads the clone and writes nothing; any
failure while finding it, a time-out included, reports nothing. The exit log
line adds boundary=blocked.

Usage: ghq-writer-handler CONFIG.json, where CONFIG holds "root", "group",
"allowedProtocols", "lockDir" and optionally "lockTimeout", "commandTimeout"
and "historyLimit".
"""

import datetime
import fcntl
import grp
import hashlib
import json
import os
import pwd
import re
import selectors
import signal
import socket
import struct
import subprocess
import sys
import time

GHQ = "@ghq@"
GHQ_SYNC = "@ghqSync@"
TOOL_PATH = "@toolPath@"

# The longest any one command the handler runs may take, unless CONFIG's
# commandTimeout says otherwise.
COMMAND_TIMEOUT = 3600
command_timeout = COMMAND_TIMEOUT
# As long as any single command may take, so a waiter outlasts every step of a
# slow fetch it queues behind.
LOCK_TIMEOUT = 3600
# EX_TEMPFAIL from sysexits.h: the repository is busy or its lock unavailable.
BUSY = 75
# The status timeout(1) exits with when its command outlasts its limit.
TIMED_OUT = 124
# EX_SOFTWARE from sysexits.h: the handler failed in a way it does not expect.
INTERNAL = 70
# Seconds a timed-out command has after SIGTERM, for git to remove a partial
# clone, before SIGKILL.
STOP_GRACE = 10
# The most missing blobs an update's or deepen's history fetch takes, unless
# CONFIG's historyLimit says otherwise; past it nothing is fetched.
HISTORY_LIMIT = 100_000
# The most blob ids checked against a clone at once while its history is listed.
CHECK_BATCH = 10_000
# The listings whose raw lines name the blobs lazygit's Patch pane reads:
# `git show --stat -p` diffs a commit against its first parent and shows a
# merge's combined diff. Without rename detection no blob is read to list them.
HISTORY_LISTINGS = (["--diff-merges=first-parent"], ["--merges", "--cc"])
# Rename detection on a merge also diffs it against each parent after the first
# and reads the blobs of the paths added or deleted there, which neither listing
# names when the merge and its first parent agree on the path.
MERGE_SIDES = ["diff-tree", "--stdin", "-r", "--raw", "--no-abbrev", "--no-renames", "--no-commit-id",
               "--diff-filter=AD"]
GITLINK = b"160000"
# The refs and shallow boundaries a clone's last complete history walk ended
# with, under its .git, which only the writer can write.
RECORD = "ghq-writer-hydrated"
RECORD_LINE = re.compile(rb"(?:ref ([0-9a-f]{40}|[0-9a-f]{64}) (refs/\S+)|shallow ([0-9a-f]{40}|[0-9a-f]{64}))\Z")

MAX_REQUEST = 4096
READ_TIMEOUT = 30
TARGET = re.compile(r"[A-Za-z0-9][A-Za-z0-9._~:/@+%-]*\Z")
# A revision: a ref name, an object name, or either with ~N or ^N suffixes. No
# range, reflog, search or option syntax.
REVISION = re.compile(r"[A-Za-z0-9][A-Za-z0-9._/+-]*(?:[~^][0-9]*)*\Z")
SCHEME = re.compile(r"([A-Za-z][A-Za-z0-9+.-]*)://")
USERINFO = re.compile(r"://[^/\s]*@")
FIELDS = {
    "get": {"action", "target", "lazy", "update", "tags"},
    "deepen": {"action", "depth", "path"},
    "promote": {"action", "path"},
    "hydrate": {"action", "rev", "path"},
}
BOOLEANS = ("lazy", "update", "tags")
# Command-scope configuration outranks a repository's own, so this holds even in
# a clone whose .git/config names git-lfs. Readers' git applies the same keys to
# the shared root (modules/home/development/repository-acquisition.nix).
LFS_POLICY = [
    "filter.lfs.process=",
    "filter.lfs.clean=",
    "filter.lfs.smudge=",
    "filter.lfs.required=false",
]

# Automatic maintenance after a fetch runs in the foreground, inside the command:
# detached, it would leave the command's process group and go on writing the
# repository after the lock is released, out of reach of a timed-out command's
# stop. The gc strategy consolidates promisor packs once gc.autoPackLimit is
# passed; git's default for automatic maintenance, the geometric strategy, decides
# whether to repack from non-promisor packs only, so the packs of a blobless
# clone, all promisor packs, would accumulate without bound.
MAINTENANCE_POLICY = [
    "maintenance.autoDetach=false",
    "gc.autoDetach=false",
    "maintenance.strategy=gc",
]


class Refused(Exception):
    pass


def peer(conn):
    """The caller's uid, and its pid when the platform reports one."""
    if sys.platform.startswith("linux"):
        size = struct.calcsize("3i")
        pid, uid, _gid = struct.unpack("3i", conn.getsockopt(socket.SOL_SOCKET, socket.SO_PEERCRED, size))
        return uid, pid
    # darwin: getsockopt(SOL_LOCAL=0, LOCAL_PEERCRED=1) returns struct xucred,
    # whose first two fields are cr_version and cr_uid; LOCAL_PEERPID=2 the pid.
    uid = struct.unpack_from("=II", conn.getsockopt(0, 1, 76))[1]
    try:
        pid = struct.unpack("=i", conn.getsockopt(0, 2, 4))[0]
    except OSError:
        pid = None
    return uid, pid


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
    if scheme and not target[scheme.end():].split("/", 1)[0].rpartition("@")[2]:
        raise Refused("target URL has no host")
    return target


def check_path(path, root):
    if not isinstance(path, str) or len(path) > 4096:
        raise Refused("path must be a string")
    real = os.path.realpath(path)
    if not real.startswith(os.path.realpath(root) + os.sep) or not os.path.isdir(real):
        raise Refused("path must be a directory inside the shared root")
    return real


def check_revision(rev):
    if not isinstance(rev, str) or len(rev) > 256 or not REVISION.match(rev):
        raise Refused("rev must be a ref or object name, optionally with ~N or ^N, starting with a letter or digit")
    if ".." in rev or rev.endswith((".lock", "/", ".")) or "//" in rev or "/." in rev:
        raise Refused("rev may not contain '..' or name a malformed ref")
    return rev


def command(request, config):
    if not isinstance(request, dict) or request.get("action") not in FIELDS:
        raise Refused("action must be one of get, deepen, promote, hydrate")
    action = request["action"]
    unknown = set(request) - FIELDS[action]
    if unknown:
        raise Refused(f"unknown field(s) for {action}: {', '.join(sorted(unknown))}")
    for flag in BOOLEANS:
        if flag in request and type(request[flag]) is not bool:
            raise Refused(f"{flag} must be a boolean")
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
    if action == "hydrate":
        return [GHQ_SYNC, "--hydrate", check_revision(request.get("rev")), path]
    return [GHQ_SYNC, "--full", path]


def environment(config):
    protocols = ["protocol.allow=never"] + [f"protocol.{p}.allow=always" for p in config["allowedProtocols"]]
    entries = protocols + LFS_POLICY + MAINTENANCE_POLICY
    env = {
        "PATH": TOOL_PATH,
        "HOME": "/var/empty",
        "LANG": "C.UTF-8",
        "GHQ_ROOT": config["root"],
        "GHQ_SYNC_NO_ZOXIDE": "1",
        "GIT_CONFIG_NOSYSTEM": "1",
        "GIT_CONFIG_GLOBAL": "/dev/null",
        "GIT_TERMINAL_PROMPT": "0",
        "GIT_CONFIG_COUNT": str(len(entries)),
    }
    for i, entry in enumerate(entries):
        key, value = entry.split("=", 1)
        env[f"GIT_CONFIG_KEY_{i}"] = key
        env[f"GIT_CONFIG_VALUE_{i}"] = value
    return env


def clone_path(target, root):
    """The directory ghq clones target into, cloned or not, or None when it is not inside root."""
    name = re.sub(r"^[A-Za-z][A-Za-z0-9+.-]*://", "", target)
    if "://" not in target and re.match(r"^[^/]+@[^/:]+:", name):
        name = name.split("@", 1)[1].replace(":", "/", 1)
    name = name.split("@", 1)[-1] if "@" in name.split("/", 1)[0] else name
    name = re.sub(r"\.git/?$", "", name).rstrip("/")
    if name.count("/") == 1:
        name = "github.com/" + name
    # ghq resolves a name without "/" under its github.com user owner, not <root>/<name>.
    if "/" not in name:
        return None
    path = os.path.realpath(os.path.join(root, name))
    if not path.startswith(os.path.realpath(root) + os.sep):
        return None
    return path


def repo_dir(target, root):
    """The clone directory ghq uses for target, or None when it is not cloned."""
    path = clone_path(target, root)
    return path if path and os.path.isdir(os.path.join(path, ".git")) else None


def repository(request, root):
    """The repository a valid request writes, as its path relative to root.

    A get names the directory ghq clones into, which need not exist yet; any
    other action names the repository enclosing its path, as ghq-sync acts on.
    Symbolic links are resolved, so every spelling of a path yields one name.
    """
    real_root = os.path.realpath(root)
    if request["action"] == "get":
        path = clone_path(request["target"], root)
        if path is None:
            raise Refused("target must name a repository inside the shared root, as owner/repo, host/owner/repo or a URL")
    else:
        path = top = os.path.realpath(request["path"])
        while top != real_root and not os.path.isdir(os.path.join(top, ".git")):
            top = os.path.dirname(top)
        if top != real_root:
            path = top
    return os.path.relpath(path, real_root)


def verb(request):
    return "+".join([request["action"], *(flag for flag in BOOLEANS if request.get(flag) is True)])


class Busy(Exception):
    pass


def wait_for(fd, timeout):
    def expire(_signum, _frame):
        raise TimeoutError

    previous = signal.signal(signal.SIGALRM, expire)
    signal.setitimer(signal.ITIMER_REAL, timeout)
    try:
        fcntl.flock(fd, fcntl.LOCK_EX)
    finally:
        signal.setitimer(signal.ITIMER_REAL, 0)
        signal.signal(signal.SIGALRM, previous)


def hold(config, session):
    """Take the session's repository lock, waiting for it; closing the result releases it.

    The lock file is named by the repository's path case-folded, since darwin's
    file system is case-insensitive: two spellings of one clone must share a lock,
    and on a case-sensitive host two clones differing only in case merely queue.
    Lock files are never removed, so a waiter never holds a lock on an unlinked
    file while another request creates a fresh one.
    """
    name = hashlib.sha256(session.repo.casefold().encode()).hexdigest()
    fd = os.open(os.path.join(config["lockDir"], f"{name}.lock"), os.O_RDWR | os.O_CREAT, 0o600)
    try:
        fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError:
        timeout = config.get("lockTimeout", LOCK_TIMEOUT)
        holder = os.pread(fd, 512, 0).decode(errors="replace").strip() or "pid=-"
        session.log(f"waiting held-by: {holder}")
        if session.notes:
            session.send({"note": f"ghq-writer: waiting up to {timeout} s for {session.repo}, in use by another request ({holder})\n"})
        try:
            wait_for(fd, timeout)
        except TimeoutError:
            os.close(fd)
            raise Busy(f"ghq-writer: gave up after {timeout} s waiting for {session.repo}, still in use by another request ({holder}); try again later") from None
    os.ftruncate(fd, 0)
    os.pwrite(fd, f"pid={os.getpid()} verb={session.verb} since={utc_now()}\n".encode(), 0)
    return fd


class TimedOut(Exception):
    pass


def label(argv):
    """A command as its program and subcommand only: its other arguments may hold the target."""
    words = argv.split() if isinstance(argv, str) else [os.fsdecode(word) for word in argv]
    if not words:
        return "-"
    program, rest = os.path.basename(words[0]), words[1:]
    while program == "git" and rest[:1] in (["-C"], ["-c"]):
        rest = rest[2:]
    return " ".join([program, *rest[:1]])


def signal_group(pgid, signum):
    """Send signum to a process group; False when no process is left in it."""
    try:
        os.killpg(pgid, signum)
    except (ProcessLookupError, PermissionError):
        # darwin answers EPERM, not ESRCH, for a group whose members have all exited.
        return False
    return True


def stop(child):
    """Stop a command and every process it started, which share its process group.

    subprocess's own timeout kills only the command, so a git that ghq started
    would go on writing the repository after its request ended. SIGTERM lets git
    remove a partial clone; whatever is still running STOP_GRACE seconds later is
    killed.
    """
    deadline = time.monotonic() + STOP_GRACE
    signal_group(child.pid, signal.SIGTERM)
    try:
        child.wait(STOP_GRACE)
    except subprocess.TimeoutExpired:
        pass
    while time.monotonic() < deadline and signal_group(child.pid, 0):
        time.sleep(0.1)
    signal_group(child.pid, signal.SIGKILL)
    child.wait()


def run(argv, env, stdin=None, lines=None):
    """Run a command in a process group of its own, stopping it past command_timeout.

    Its output is captured, unless `lines` is given: then each line of standard
    output goes to `lines` as it arrives, and the command is stopped as soon as
    `lines` returns False.
    """
    with subprocess.Popen(argv, env=env, stdin=subprocess.DEVNULL if stdin is None else subprocess.PIPE,
                          stdout=subprocess.PIPE, stderr=subprocess.PIPE, process_group=0) as child:
        try:
            if lines is None:
                out, err = child.communicate(stdin, timeout=command_timeout)
            else:
                out, err = b"", stream(child, lines, stdin)
        except subprocess.TimeoutExpired:
            stop(child)
            raise TimedOut(f"timed out after {command_timeout} s running {label(argv)}") from None
    return subprocess.CompletedProcess(argv, child.returncode, out, err)


def stream(child, lines, stdin=None):
    """Pass each line of child's standard output to lines until it returns False, then stop child; its standard error.

    stdin, when given, is written to child as it reads it, alongside its output.
    """
    deadline = time.monotonic() + command_timeout
    pending, err = b"", b""
    with selectors.DefaultSelector() as selector:
        selector.register(child.stdout, selectors.EVENT_READ)
        selector.register(child.stderr, selectors.EVENT_READ)
        if stdin is not None:
            unsent = memoryview(stdin)
            os.set_blocking(child.stdin.fileno(), False)
            selector.register(child.stdin, selectors.EVENT_WRITE)
        try:
            while selector.get_map():
                remaining = deadline - time.monotonic()
                ready = selector.select(remaining) if remaining > 0 else []
                if not ready:
                    raise subprocess.TimeoutExpired(child.args, command_timeout)
                for key, _ in ready:
                    if key.fileobj is child.stdin:
                        try:
                            unsent = unsent[os.write(key.fd, unsent[:65536]):]
                        except BlockingIOError:
                            continue
                        except BrokenPipeError:
                            unsent = unsent[:0]
                        if not unsent:
                            selector.unregister(child.stdin)
                            child.stdin.close()
                        continue
                    chunk = os.read(key.fd, 65536)
                    if not chunk:
                        selector.unregister(key.fileobj)
                    elif key.fileobj is child.stderr:
                        err += chunk
                    else:
                        *complete, pending = (pending + chunk).split(b"\n")
                        if not all(map(lines, complete)):
                            stop(child)
                            return err
        except subprocess.TimeoutExpired:
            raise
        except BaseException:
            stop(child)
            raise
    if pending:
        lines(pending)
    child.wait()
    return err


def git(path, env, *args, stdin=None, lines=None):
    return run(["git", "-C", path, *args], env, stdin, lines)


def shallow_tags(path, env):
    """Fetch remote tags into a shallow clone without moving its history boundary.

    A tags-only fetch at --depth=1 marks every fetched tag commit as a shallow
    boundary, including tags inside the history already present, which cuts a
    deepened branch back to depth 1. So tags whose commits are present are fetched
    without --depth (only the tag objects travel), and only tags whose commits are
    absent are fetched at depth 1. The caller fetches the tracked branches first:
    a tag ahead of the local tip would otherwise land as a depth-1 boundary inside
    the branch's future history, where the next update's fetch stops, leaving no
    merge base and failing its fast-forward. A tag that moved upstream is not
    forced, matching plain `git fetch --tags`, which rejects it as clobbering.
    """
    results = []
    listed = git(path, env, "ls-remote", "--tags", "origin")
    if listed.returncode:
        return results + [listed]
    tag_object, tag_commit = {}, {}
    for line in listed.stdout.decode().splitlines():
        sha, tab, ref = line.partition("\t")
        if not tab:
            message = f"ghq-writer: unexpected ls-remote output: {line!r}\n"
            return results + [subprocess.CompletedProcess(listed.args, 1, b"", message.encode())]
        if ref.endswith("^{}"):
            tag_commit[ref[:-3]] = sha
        else:
            tag_object[ref] = sha
            tag_commit.setdefault(ref, sha)
    if not tag_object:
        return results
    local = git(path, env, "for-each-ref", "--format=%(refname) %(objectname)", "refs/tags")
    have = dict(line.split(" ", 1) for line in local.stdout.decode().splitlines() if line)
    wanted = sorted(ref for ref, sha in tag_object.items() if have.get(ref) != sha)
    if not wanted:
        return results
    # In a partial clone, asking about a missing object would fetch it from the
    # promisor remote and make every tag look present.
    probe = git(path, {**env, "GIT_NO_LAZY_FETCH": "1"}, "cat-file", "--batch-check=%(objectname)",
                stdin="".join(f"{tag_commit[ref]}^{{commit}}\n" for ref in wanted).encode())
    present = set(probe.stdout.decode().split())
    near = [ref for ref in wanted if tag_commit[ref] in present]
    far = [ref for ref in wanted if tag_commit[ref] not in present]
    for refs, depth in ((near, []), (far, ["--depth=1"])):
        if refs:
            spec = "".join(f"{ref}:{ref}\n" for ref in refs).encode()
            results.append(git(path, env, "fetch", "--no-tags", *depth, "--stdin", "origin", stdin=spec))
    return results


def note(text):
    return subprocess.CompletedProcess([], 0, text.encode(), b"")


def follow_default_branch(path, env):
    """Follow a change of the remote's default branch before an update.

    The remote's HEAD names its default branch without credentials. A clone that
    fetches one branch (every lazy clone) is pointed at the new default, fetched
    at its current depth, and checked out on it, since its old branch may be gone.
    A full clone gets origin/HEAD moved, and changes branch only when it was on
    the previous default and has no local change; a clone on any other branch, or
    with changes, stays where it is. One status line reports what happened.
    """
    listed = git(path, env, "ls-remote", "--symref", "origin", "HEAD")
    match = re.match(rb"ref: refs/heads/(\S+)\tHEAD\n", listed.stdout)
    if listed.returncode or not match:
        return []
    new = match.group(1).decode()
    if git(path, env, "check-ref-format", "--branch", new).returncode:
        return []
    refspecs = git(path, env, "config", "--get-all", "remote.origin.fetch").stdout.decode().split()
    single = [m.group(1) for m in map(re.compile(r"\+?refs/heads/([^*:]+):refs/remotes/origin/\1\Z").match, refspecs) if m]
    current = git(path, env, "symbolic-ref", "--short", "-q", "HEAD").stdout.decode().strip()
    if single and len(single) == len(refspecs):
        old = single[0] if len(single) == 1 else current
        if new in single:
            return []
        depth = []
        if git(path, env, "rev-parse", "--is-shallow-repository").stdout.strip() == b"true":
            depth = ["--depth", git(path, env, "rev-list", "--count", "HEAD").stdout.decode().strip()]
        results = [git(path, env, "remote", "set-branches", "origin", new),
                   git(path, env, "fetch", "--no-tags", *depth, "origin", new)]
        if any(r.returncode for r in results):
            return results
        results.append(git(path, env, "checkout", "-q", "-B", new, f"origin/{new}"))
        if not results[-1].returncode:
            results.append(note(f"default branch: {old} -> {new}; checked out {new}\n"))
        return results
    previous = git(path, env, "symbolic-ref", "-q", "--short", "refs/remotes/origin/HEAD").stdout.decode().strip()
    old = previous.removeprefix("origin/")
    fetched = git(path, env, "-c", "remote.origin.followRemoteHEAD=always", "fetch", "--no-tags", "origin")
    if fetched.returncode or not old or old == new:
        return [fetched]
    results = [fetched]
    dirty = git(path, env, "status", "--porcelain").stdout.strip()
    if current == old and not dirty:
        local = git(path, env, "rev-parse", "-q", "--verify", f"refs/heads/{new}").returncode == 0
        switch = ["checkout", "-q", new] if local else ["checkout", "-q", "--track", "-b", new, f"origin/{new}"]
        results.append(git(path, env, *switch))
        if not results[-1].returncode:
            results.append(note(f"default branch: {old} -> {new}; checked out {new}\n"))
            return results
    why = "local changes" if dirty and current == old else "not the previous default"
    results.append(note(f"default branch: {old} -> {new}; kept {current or 'a detached HEAD'} ({why})\n"))
    return results


class History(subprocess.CompletedProcess):
    """A history fetch's status line, with exit status zero, and its outcome for the exit log line."""

    def __init__(self, outcome, line, err=b""):
        super().__init__([], 0, line.encode(), err)
        self.outcome = outcome


class HistoryFailed(Exception):
    def __init__(self, reason, err=b""):
        super().__init__(reason)
        self.err = err


def blobless(path, env):
    return git(path, env, "config", "--type=bool", "--get", "remote.origin.promisor").stdout.strip() == b"true"


def boundaries(path):
    """The commits a shallow clone's history stops at."""
    try:
        with open(os.path.join(path, ".git", "shallow")) as handle:
            return set(handle.read().split())
    except FileNotFoundError:
        return set()


# git counts a commit at exactly the requested depth below a boundary as a new
# boundary, which hides held history when it lands on a commit the clone holds;
# no copy's history is as deep as the largest depth a request accepts.
FULL_DEEPEN = 1_000_000


def blocking_boundary(path, env):
    """A boundary between the local branch and its upstream, and that upstream's name, or None.

    A boundary lies between them when the local branch is not an ancestor of
    its upstream and upstream's commits past it reach that boundary; upstream
    may have moved past it or rewritten its branch, which the clone cannot
    tell apart. Reads only; any failure finds none, so the update's outcome is
    git's alone.
    """
    try:
        start = boundaries(path)
        if not start:
            return None
        quiet = {**env, "GIT_NO_LAZY_FETCH": "1"}
        tracking = git(path, quiet, "rev-parse", "--symbolic-full-name", "@{upstream}")
        upstream_ref = tracking.stdout.strip().decode(errors="replace")
        if tracking.returncode or not upstream_ref:
            return None
        if git(path, quiet, "merge-base", "--is-ancestor", "HEAD", upstream_ref).returncode != 1:
            return None
        gap = git(path, quiet, "rev-list", upstream_ref, "^HEAD")
        if gap.returncode:
            return None
        held = [commit for commit in gap.stdout.decode().split() if commit in start]
        return (held[0], upstream_ref.removeprefix("refs/remotes/")) if held else None
    except Exception:
        return None


def branch_refs(path, env):
    """The commit each of the clone's branches and remote-tracking branches names, by ref name, both as bytes.

    A ref name need not be UTF-8, so neither is decoded.
    """
    listed = git(path, {**env, "GIT_NO_LAZY_FETCH": "1"}, "for-each-ref", "--format=%(objectname) %(refname)",
                 "refs/heads", "refs/remotes")
    if listed.returncode:
        raise HistoryFailed(f"{label(listed.args)} exited {listed.returncode}", listed.stderr)
    return {ref: oid for oid, _, ref in (line.partition(b" ") for line in listed.stdout.splitlines() if line)}


class Unread:
    """What history_before keeps when reading the clone's history failed."""

    def __init__(self, failure):
        self.failure = failure


def history_failed(path, phase, failure):
    """The status line of a history phase that raised failure: the handler's own failures by their message, any
    other exception by its type alone, whose message may hold anything."""
    reason = str(failure) if isinstance(failure, (HistoryFailed, TimedOut)) else type(failure).__name__
    return History("failed", f"history hydrate failed: {path} ({phase}: {reason})\n", getattr(failure, "err", b""))


def read_record(path):
    """The branch refs, by name, and shallow boundaries the clone's record names, or None when it has none.

    Ref names and ids are bytes, boundaries text, as branch_refs and boundaries
    give them.
    """
    try:
        with open(os.path.join(path, ".git", RECORD), "rb") as handle:
            lines = handle.read().splitlines()
    except FileNotFoundError:
        return None
    refs, shallow = {}, set()
    for line in lines:
        parsed = RECORD_LINE.match(line)
        if not parsed:
            raise HistoryFailed(f"{RECORD} holds a line that is neither a ref nor a boundary")
        oid, ref, boundary = parsed.groups()
        if boundary:
            shallow.add(boundary.decode())
        else:
            refs[ref] = oid
    return refs, shallow


def write_record(path, refs, shallow):
    """Replace the clone's record in one rename, so a request stopped at any point leaves the old record or the new."""
    record = os.path.join(path, ".git", RECORD)
    staged = f"{record}.new"
    with open(staged, "wb") as handle:
        handle.write(b"".join(b"ref " + oid + b" " + ref + b"\n" for ref, oid in sorted(refs.items())))
        handle.write("".join(f"shallow {commit}\n" for commit in sorted(shallow)).encode())
        handle.flush()
        os.fsync(handle.fileno())
    os.replace(staged, record)


def history_before(path, env):
    """What a blobless clone held before a request changes it; None for any other clone.

    That is the refs and boundaries its record names, which its last complete
    history walk ended with, and the boundaries it has now. A clone with no
    record gets one from the refs and boundaries it has now, written before the
    request's first fetch. Any exception reading them is kept as Unread, for the
    walk to report: the request goes on without a walk. Exception, not
    BaseException: SystemExit and KeyboardInterrupt are requests to stop the
    handler, which the history fetch has no business absorbing.
    """
    try:
        if not blobless(path, env):
            return None
        start = boundaries(path)
        recorded = read_record(path)
        if recorded is None:
            recorded = branch_refs(path, env), start
            write_record(path, *recorded)
        return recorded, start
    except Exception as failure:
        return Unread(failure)


def gains_commits(path, env, revisions):
    """Whether revisions, given on standard input, name any commit."""
    listed = git(path, {**env, "GIT_NO_LAZY_FETCH": "1"}, "rev-list", "--max-count=1", "--stdin",
                 stdin="".join(f"{revision}\n" for revision in revisions).encode())
    if listed.returncode:
        raise HistoryFailed(f"{label(listed.args)} exited {listed.returncode}", listed.stderr)
    return bool(listed.stdout.strip())


def walk_history(path, env, config, before):
    """The history fetch of what a blobless clone gained since its last complete walk, or None when it gained nothing.

    What it gained is the commits its branches and remote-tracking branches
    reach that neither a recorded ref nor a recorded or present shallow boundary
    reached, and those from each such boundary since removed down to, and
    excluding, the boundaries now present; a request killed or failed after its
    fetch leaves its commits to the next. A ref moved to a commit the clone
    already held, or deleted, brings in nothing. A recorded commit the clone no
    longer holds is left out. The walked range excludes only what the recorded
    refs reached, so a commit that only a tag reached, at depth 1, is walked once
    a commit a branch gained reaches it; one only a tag reaches is not. Unless the
    walk fails, the record then names the refs and boundaries the walk saw. Any
    exception is the history fetch's failure, never the request's.
    """
    if isinstance(before, Unread):
        return history_failed(path, "snapshot", before.failure)
    try:
        (old_refs, recorded_boundaries), start = before
        old_boundaries = recorded_boundaries | start
        new_refs, new_boundaries = branch_refs(path, env), boundaries(path)
        reached = {oid.decode() for oid in old_refs.values()}
        moved = {oid.decode() for ref, oid in new_refs.items() if old_refs.get(ref) != oid} - reached
        removed = old_boundaries - new_boundaries
        if moved or removed:
            lacking = {oid.decode() for oid in absent(path, {**env, "GIT_NO_LAZY_FETCH": "1"},
                                                     [c.encode() for c in sorted(reached | old_boundaries)])}
            reached, old_boundaries, removed = reached - lacking, old_boundaries - lacking, removed - lacking
        ranges = []
        if moved and gains_commits(path, env, sorted(moved) + [f"^{c}" for c in sorted(reached | old_boundaries)]):
            ranges.append(sorted(moved) + [f"^{commit}" for commit in sorted(reached)])
        if removed:
            ranges.append(sorted(removed) + [f"^{commit}" for commit in sorted(new_boundaries)])
        history = hydrate_history(path, env, config, ranges) if ranges else None
        if (new_refs, new_boundaries) != (old_refs, recorded_boundaries):
            write_record(path, new_refs, new_boundaries)
        return history
    except Exception as failure:
        return history_failed(path, "walk", failure)


def absent(path, env, ids):
    """Those of ids the clone lacks; env must disable lazy fetching."""
    checked = git(path, env, "cat-file", "--batch-check=%(objectname)", stdin=b"".join(oid + b"\n" for oid in ids))
    if checked.returncode:
        raise HistoryFailed(f"{label(checked.args)} exited {checked.returncode}", checked.stderr)
    return [line.split()[0] for line in checked.stdout.splitlines() if line.endswith(b" missing")]


def merge_sides(path, env, given):
    """A line `<merge> <parent>` for each merge among the revisions given and each of its parents after the first."""
    merges = git(path, env, "rev-list", "--merges", "--parents", "--stdin", stdin=given)
    if merges.returncode:
        raise HistoryFailed(f"{label(merges.args)} exited {merges.returncode}", merges.stderr)
    return b"".join(merge + b" " + parent + b"\n"
                    for merge, _, *others in (line.split() for line in merges.stdout.splitlines()) for parent in others)


def missing_blobs(path, env, ranges, limit):
    """The blobs the clone lacks that the diffs of the commits in ranges read, or None once more than limit are counted.

    Each range is a list of revisions, `^` marking an excluded one, given to git
    on standard input, as a range may name every boundary of a clone. The blobs
    are those of the two listings, and for each merge those of the paths added or
    deleted between each parent after the first and the merge, all under one
    count. env must disable lazy fetching. Gitlinks and null ids name no blob.
    """
    seen, batch, missing = set(), [], []

    def check():
        missing.extend(absent(path, env, batch))
        batch.clear()
        return len(missing) <= limit

    def take(line):
        meta = line.partition(b"\t")[0]
        parents = len(meta) - len(meta.lstrip(b":"))
        fields = meta[parents:].split()
        for mode, oid in zip(fields[:parents + 1], fields[parents + 1:2 * parents + 2]):
            if mode != GITLINK and oid.strip(b"0") and oid not in seen:
                seen.add(oid)
                batch.append(oid)
        # No batch is larger than could take the count past the limit, so the walk
        # stops as soon as it does; none is smaller than a sixteenth of the ids
        # seen, so a long walk near the limit still checks in few batches.
        if len(batch) >= min(CHECK_BATCH, max(limit - len(missing) + 1, len(seen) // 16)):
            return check()
        return True

    def within(*args, stdin):
        """Whether the count is still within the limit after the raw lines of git's args, given stdin, are taken."""
        listed = git(path, env, *args, stdin=stdin, lines=take)
        if len(missing) > limit:
            return False
        if listed.returncode:
            raise HistoryFailed(f"{label(listed.args)} exited {listed.returncode}", listed.stderr)
        return True

    for revisions in ranges:
        given = "".join(f"{revision}\n" for revision in revisions).encode()
        for listing in HISTORY_LISTINGS:
            if not within("log", *listing, "--raw", "--no-abbrev", "--no-renames", "--format=", "--stdin", "--",
                          stdin=given):
                return None
        sides = merge_sides(path, env, given)
        if sides and not within(*MERGE_SIDES, stdin=sides):
            return None
    return missing if check() else None


def fetch_blobs(path, env, missing, blob_filter):
    """Fetch missing blobs by id as ghq-sync --hydrate does, a pass at a time while the set shrinks; how many arrived.

    The fetch passes the filter the clone records, which it would otherwise
    replace. An empty --stdin fetch would fetch the remote's default refspec, so
    none runs.
    """
    fetched = 0
    while missing:
        got = git(path, env, "-c", "fetch.negotiationAlgorithm=noop", "fetch", "--no-tags", "--no-write-fetch-head",
                  "--recurse-submodules=no", f"--filter={blob_filter}", "--stdin", "origin",
                  stdin=b"".join(oid + b"\n" for oid in missing))
        if got.returncode:
            raise HistoryFailed(f"{label(got.args)} exited {got.returncode}", got.stderr)
        still = absent(path, {**env, "GIT_NO_LAZY_FETCH": "1"}, missing)
        fetched += len(missing) - len(still)
        if len(still) == len(missing):
            raise HistoryFailed(f"{len(still)} blobs still missing after a fetch")
        missing = still
    return fetched


def hydrate_history(path, env, config, ranges):
    """Make the commits in ranges readable as diffs, up to the history limit; its status line.

    A promisor clone that records no filter, as a `ghq-sync --full` whose
    refetch failed leaves one, gets no fetch, which would record one.
    """
    limit = config.get("historyLimit", HISTORY_LIMIT)
    recorded = git(path, env, "config", "--get", "remote.origin.partialclonefilter")
    if recorded.returncode == 1:
        return History("not-hydrated", f"history not hydrated: {path} (the clone records no partial-clone filter;"
                                       " ghq-sync --hydrate REV makes a revision readable)\n")
    if recorded.returncode:
        raise HistoryFailed(f"{label(recorded.args)} exited {recorded.returncode}", recorded.stderr)
    missing = missing_blobs(path, {**env, "GIT_NO_LAZY_FETCH": "1"}, ranges, limit)
    if missing is None:
        return History("not-hydrated", f"history not hydrated: {path} (more than {limit} blobs missing;"
                                       " ghq-sync --hydrate REV makes a revision readable)\n")
    fetched = fetch_blobs(path, env, missing, recorded.stdout.strip().decode())
    return History(f"hydrated:{fetched}", f"hydrated history: {path} ({fetched} objects fetched)\n")


def run_get(request, argv, config, env, session):
    """ghq get, with the default-branch and tag fetches the request and clone shape call for.

    For a blobless clone already present, every fetch that can move a branch or
    remote-tracking branch runs first, then the history fetch, recorded on
    session as soon as it returns, then the fetch of tags at depth 1.
    """
    results = []
    path = repo_dir(request["target"], config["root"])
    before = history_before(path, env) if path else None
    update = path and request.get("update") is True
    if update:
        results.extend(follow_default_branch(path, env))
    full = path and git(path, env, "rev-parse", "--is-shallow-repository").stdout.strip() == b"false"
    if update and full:
        results.append(git(path, env, "fetch", "--tags", "origin"))
    results.append(run(argv, env))
    blocked = update and results[-1].returncode and blocking_boundary(path, env)
    if blocked:
        session.boundary = True
        commit, branch = blocked
        results.append(subprocess.CompletedProcess([], 0, b"", (
            f"shallow boundary between the local branch and upstream's: {path} (the copy holds {commit} without"
            f" its history, and it lies between the local branch and upstream's {branch})\n"
            f"to repair it: ghq-sync --deepen {FULL_DEEPEN} {path} then ghq-sync -u {path} (that deepen hides none"
            " of the history the copy holds, where a smaller one can; if the update still fails with git's"
            " fast-forward refusal and without this line, upstream rewrote its branch and this boundary was not the"
            " cause; ghq-sync --help, under --deepen, says what the deepen costs and names the other repair)\n"
            ).encode()))
    shallow = None
    if request.get("tags") is True:
        tagged = repo_dir(request["target"], config["root"])
        if tagged and git(tagged, env, "rev-parse", "--is-shallow-repository").stdout.strip() == b"true":
            results.append(git(tagged, env, "fetch", "--no-tags", "origin"))
            shallow = tagged if results[-1].returncode == 0 else None
        elif tagged and not (full and update):
            results.append(git(tagged, env, "fetch", "--tags", "origin"))
    if before is not None:
        session.history = walk_history(path, env, config, before)
        if session.history:
            results.append(session.history)
    if shallow:
        results.extend(shallow_tags(shallow, env))
    return results


def run_deepen(argv, path, config, env, session):
    """ghq-sync --deepen, then, for a blobless clone, its history fetch, recorded on session as soon as it returns.

    `git fetch --deepen` also moves the remote-tracking branch to what upstream
    gained, which the history fetch covers with the deepened range.
    """
    before = history_before(path, env)
    results = [run(argv, env)]
    if before is not None:
        session.history = walk_history(path, env, config, before)
        if session.history:
            results.append(session.history)
    return results


def utc_now():
    return datetime.datetime.now(datetime.timezone.utc).isoformat(timespec="milliseconds").replace("+00:00", "Z")


class Session:
    """One connection: its caller, its log lines and the messages sent back."""

    def __init__(self, conn):
        self.conn = conn
        self.started = time.monotonic()
        self.uid, self.caller_pid = peer(conn)
        self.verb = self.repo = "-"
        self.target = self.reason = None
        self.gone = self.notes = False
        self.history = None
        self.boundary = False

    def log(self, event):
        try:
            user = pwd.getpwuid(self.uid).pw_name
        except KeyError:
            user = "-"
        print(f"{utc_now()} ghq-writer pid={os.getpid()} uid={self.uid} user={user}"
              f" caller-pid={self.caller_pid or '-'} verb={self.verb} repo={self.repo} {event}",
              file=sys.stderr, flush=True)

    def send(self, message):
        """Send one line to the caller, unless it has gone: the operation outlives it."""
        if self.gone:
            return
        try:
            self.conn.sendall(json.dumps(message).encode() + b"\n")
        except OSError:
            self.gone = True
            self.log("caller disconnected")

    def fail(self, status, reason, message):
        """A failure's reply, with any history fetch's status line; the reason, which must not hold the target, goes on
        the exit log line."""
        self.reason = reason
        history = self.history or History(None, "")
        return {"stdout": history.stdout.decode(errors="replace"),
                "stderr": history.stderr.decode(errors="replace") + message, "exit": status}


def describe(error, target):
    """An exception's type and message, naming neither the target nor a command's arguments."""
    if isinstance(error, subprocess.TimeoutExpired):
        return f"TimeoutExpired: {label(error.cmd)} after {error.timeout} s"
    if isinstance(error, subprocess.CalledProcessError):
        return f"CalledProcessError: {label(error.cmd)} exited {error.returncode}"
    message = " ".join(str(error).split())
    if target:
        message = message.replace(target, "<target>")
    return f"{type(error).__name__}: {USERINFO.sub('://<credentials>@', message)}"


def serve(session, config):
    conn = session.conn
    # Under per-connection activation an idle connection holds a handler process.
    conn.settimeout(READ_TIMEOUT)
    reader = conn.makefile("rb")
    # Read before refusing, so an unauthorized caller gets a reply rather than a reset.
    try:
        raw = reader.readline(MAX_REQUEST + 1)
    except TimeoutError:
        raw = None
    # A client that relays notes says so on a second line, {"accept": ["note"]}:
    # a handler predating notes reads only the first line, and a client predating
    # them, which parses everything it receives as one reply, sends none.
    try:
        options = json.loads(reader.readline(MAX_REQUEST + 1)) if raw and raw.endswith(b"\n") else {}
    except (TimeoutError, ValueError):
        options = {}
    session.notes = isinstance(options, dict) and isinstance(options.get("accept"), list) and "note" in options["accept"]
    if not authorized(session.uid, config["group"]):
        return session.fail(13, f"not a member of {config['group']}",
                            f"ghq-writer: uid {session.uid} is not a member of {config['group']}\n")
    try:
        if raw is None:
            raise Refused(f"no complete request within {READ_TIMEOUT} s")
        if len(raw) > MAX_REQUEST:
            raise Refused("request exceeds 4 KiB")
        request = json.loads(raw)
        if isinstance(request, dict) and isinstance(request.get("target"), str):
            session.target = request["target"]
        argv = command(request, config)
        repo = repository(request, config["root"])
    except (Refused, ValueError) as refusal:
        return session.fail(2, "refused", f"ghq-writer: refused: {refusal}\n")
    session.verb, session.repo = verb(request), repo
    session.log("start")
    try:
        held = hold(config, session)
    except Busy as busy:
        return session.fail(BUSY, "gave up waiting for the lock", f"{busy}\n")
    except OSError as error:
        return session.fail(BUSY, f"cannot open the lock: {error.strerror}",
                            f"ghq-writer: cannot open the lock for {repo} in {config['lockDir']}: {error.strerror}\n")
    try:
        env = environment(config)
        if request["action"] == "get":
            results = run_get(request, argv, config, env, session)
        elif request["action"] == "deepen":
            results = run_deepen(argv, os.path.join(os.path.realpath(config["root"]), repo), config, env, session)
        else:
            results = [run(argv, env)]
    except TimedOut as timeout:
        return session.fail(TIMED_OUT, str(timeout), f"ghq-writer: {timeout}\n")
    finally:
        os.close(held)
    failed = next((r for r in results if r.returncode), None)
    if failed:
        session.reason = f"{label(failed.args)} exited {failed.returncode}"
    return {
        "stdout": "".join(r.stdout.decode(errors="replace") for r in results),
        "stderr": "".join(r.stderr.decode(errors="replace") for r in results),
        "exit": failed.returncode if failed else 0,
    }


def main():
    # launchd does not apply a job's Umask to the inetd-style instances it starts per
    # connection, so the handler sets the writer's umask itself: nothing it writes
    # is group-writable or open to others, on any host.
    os.umask(0o027)
    with open(sys.argv[1]) as handle:
        config = json.load(handle)
    global command_timeout
    command_timeout = config.get("commandTimeout", COMMAND_TIMEOUT)
    session = Session(socket.socket(fileno=0))
    status = 0
    try:
        reply = serve(session, config)
    except Exception as error:
        reply = session.fail(INTERNAL, f"unexpected {describe(error, session.target)}",
                             "ghq-writer: the writer failed unexpectedly; its log names the error\n")
        status = INTERNAL
    session.send(reply)
    session.conn.close()
    history = f" history={session.history.outcome}" if session.history else ""
    boundary = " boundary=blocked" if session.boundary else ""
    reason = f" reason: {session.reason}" if session.reason else ""
    session.log(f"exit status={reply['exit']} duration={time.monotonic() - session.started:.3f}s{history}{boundary}"
                f"{reason}")
    sys.exit(status)


if __name__ == "__main__":
    main()
