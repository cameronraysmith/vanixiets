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

Usage: ghq-writer-handler CONFIG.json, where CONFIG holds "root", "group",
"allowedProtocols", "lockDir" and optionally "lockTimeout".
"""

import datetime
import fcntl
import grp
import hashlib
import json
import os
import pwd
import re
import signal
import socket
import struct
import subprocess
import sys
import time

GHQ = "@ghq@"
GHQ_SYNC = "@ghqSync@"
TOOL_PATH = "@toolPath@"

# Longer than any single git command the handler runs may take (their timeout
# below), so a waiter outlasts every step of a slow fetch it queues behind.
LOCK_TIMEOUT = 3600
# EX_TEMPFAIL from sysexits.h: the repository is busy or its lock unavailable.
BUSY = 75

MAX_REQUEST = 4096
READ_TIMEOUT = 30
TARGET = re.compile(r"[A-Za-z0-9][A-Za-z0-9._~:/@+%-]*\Z")
# A revision: a ref name, an object name, or either with ~N or ^N suffixes. No
# range, reflog, search or option syntax.
REVISION = re.compile(r"[A-Za-z0-9][A-Za-z0-9._/+-]*(?:[~^][0-9]*)*\Z")
SCHEME = re.compile(r"([A-Za-z][A-Za-z0-9+.-]*)://")
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
    entries = protocols + LFS_POLICY
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


def git(path, env, *args, stdin=None):
    return subprocess.run(["git", "-C", path, *args], env=env, input=stdin, capture_output=True, timeout=3600)


def shallow_tags(path, env):
    """Fetch remote tags into a shallow clone without moving its history boundary.

    A tags-only fetch at --depth=1 marks every fetched tag commit as a shallow
    boundary, including tags inside the history already present, which cuts a
    deepened branch back to depth 1. So tags whose commits are present are fetched
    without --depth (only the tag objects travel), and only tags whose commits are
    absent are fetched at depth 1. The tracked branches are fetched first: a tag
    ahead of the local tip would otherwise land as a depth-1 boundary inside the
    branch's future history, where the next update's fetch stops, leaving no merge
    base and failing its fast-forward. A tag that moved upstream is not forced,
    matching plain `git fetch --tags`, which rejects it as clobbering.
    """
    results = [git(path, env, "fetch", "--no-tags", "origin")]
    if results[-1].returncode:
        return results
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


def run_get(request, argv, config, env):
    """ghq get, with the default-branch and tag fetches the request and clone shape call for."""
    results = []
    path = repo_dir(request["target"], config["root"])
    if path and request.get("update") is True:
        results.extend(follow_default_branch(path, env))
    full = path and git(path, env, "rev-parse", "--is-shallow-repository").stdout.strip() == b"false"
    if path and full and request.get("update") is True:
        results.append(git(path, env, "fetch", "--tags", "origin"))
    results.append(subprocess.run(argv, env=env, stdin=subprocess.DEVNULL, capture_output=True, timeout=3600))
    if request.get("tags") is True:
        path = repo_dir(request["target"], config["root"])
        if path and git(path, env, "rev-parse", "--is-shallow-repository").stdout.strip() == b"true":
            results.extend(shallow_tags(path, env))
        elif path and not (full and request.get("update") is True):
            results.append(git(path, env, "fetch", "--tags", "origin"))
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
        self.gone = self.notes = False

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
        return {"stdout": "", "stderr": f"ghq-writer: uid {session.uid} is not a member of {config['group']}\n", "exit": 13}
    try:
        if raw is None:
            raise Refused(f"no complete request within {READ_TIMEOUT} s")
        if len(raw) > MAX_REQUEST:
            raise Refused("request exceeds 4 KiB")
        request = json.loads(raw)
        argv = command(request, config)
        repo = repository(request, config["root"])
    except (Refused, ValueError) as refusal:
        return {"stdout": "", "stderr": f"ghq-writer: refused: {refusal}\n", "exit": 2}
    session.verb, session.repo = verb(request), repo
    session.log("start")
    try:
        held = hold(config, session)
    except Busy as busy:
        return {"stdout": "", "stderr": f"{busy}\n", "exit": BUSY}
    except OSError as error:
        return {"stdout": "", "stderr": f"ghq-writer: cannot open the lock for {repo} in {config['lockDir']}: {error.strerror}\n", "exit": BUSY}
    try:
        env = environment(config)
        if request["action"] == "get":
            results = run_get(request, argv, config, env)
        else:
            results = [subprocess.run(argv, env=env, stdin=subprocess.DEVNULL, capture_output=True, timeout=3600)]
    finally:
        os.close(held)
    return {
        "stdout": "".join(r.stdout.decode(errors="replace") for r in results),
        "stderr": "".join(r.stderr.decode(errors="replace") for r in results),
        "exit": next((r.returncode for r in results if r.returncode), 0),
    }


def main():
    # launchd does not apply a job's Umask to the inetd-style instances it starts per
    # connection, so the handler sets the writer's umask itself: nothing it writes
    # is group-writable or open to others, on any host.
    os.umask(0o027)
    with open(sys.argv[1]) as handle:
        config = json.load(handle)
    session = Session(socket.socket(fileno=0))
    reply = serve(session, config)
    session.send(reply)
    session.conn.close()
    session.log(f"exit status={reply['exit']} duration={time.monotonic() - session.started:.3f}s")


if __name__ == "__main__":
    main()
