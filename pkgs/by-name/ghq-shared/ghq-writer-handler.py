"""Carry out one request against the shared ghq tree, as its sole writer.

Started once per connection by a socket-activated service (systemd Accept=yes,
launchd inetdCompatibility), with the connection on file descriptor 0. Reads one
JSON request, refuses anything outside a fixed action set, runs ghq or ghq-sync
without a shell, and writes one JSON reply {"stdout", "stderr", "exit"}.

Git runs with no LFS filter, whatever a repository's own configuration says, so
every working tree holds LFS pointer files exactly as committed; readers' git
configuration applies the same policy to the shared root.

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


def repo_dir(target, root):
    """The clone directory ghq uses for target, or None when it is not cloned."""
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
    return path if os.path.isdir(os.path.join(path, ".git")) else None


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


def serve(conn, config):
    uid = peer_uid(conn)
    # Under per-connection activation an idle connection holds a handler process.
    conn.settimeout(READ_TIMEOUT)
    # Read before refusing, so an unauthorized caller gets a reply rather than a reset.
    try:
        raw = conn.makefile("rb").readline(MAX_REQUEST + 1)
    except TimeoutError:
        raw = None
    if not authorized(uid, config["group"]):
        return {"stdout": "", "stderr": f"ghq-writer: uid {uid} is not a member of {config['group']}\n", "exit": 13}, uid, None
    try:
        if raw is None:
            raise Refused(f"no complete request within {READ_TIMEOUT} s")
        if len(raw) > MAX_REQUEST:
            raise Refused("request exceeds 4 KiB")
        request = json.loads(raw)
        argv = command(request, config)
    except (Refused, ValueError) as refusal:
        return {"stdout": "", "stderr": f"ghq-writer: refused: {refusal}\n", "exit": 2}, uid, None
    env = environment(config)
    if request["action"] == "get":
        results = run_get(request, argv, config, env)
    else:
        results = [subprocess.run(argv, env=env, stdin=subprocess.DEVNULL, capture_output=True, timeout=3600)]
    reply = {
        "stdout": "".join(r.stdout.decode(errors="replace") for r in results),
        "stderr": "".join(r.stderr.decode(errors="replace") for r in results),
        "exit": next((r.returncode for r in results if r.returncode), 0),
    }
    return reply, uid, argv


def main():
    # launchd does not apply a job's Umask to the inetd-style instances it starts per
    # connection, so the handler sets the writer's umask itself: nothing it writes
    # is group-writable or open to others, on any host.
    os.umask(0o027)
    with open(sys.argv[1]) as handle:
        config = json.load(handle)
    conn = socket.socket(fileno=0)
    reply, uid, argv = serve(conn, config)
    print(f"ghq-writer: uid={uid} argv={argv} exit={reply['exit']}", file=sys.stderr)
    conn.sendall(json.dumps(reply).encode() + b"\n")
    conn.close()


if __name__ == "__main__":
    main()
