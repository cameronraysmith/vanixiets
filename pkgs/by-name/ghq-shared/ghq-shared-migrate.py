"""Move administrators' ghq trees into the host's shared tree, set other accounts' trees aside, or roll either back.

Usage:
  ghq-shared-migrate [--apply] ACCOUNT...       plan (default) or move in place, in order
  ghq-shared-migrate --set-aside ACCOUNT...     rename each ~/ghq aside and list what to reclone
  ghq-shared-migrate --rollback ACCOUNT...      undo, for these accounts

Run as root. Only an administrator of the host (a member of wheel on NixOS, of
admin on darwin) may have its tree moved in place: such an account can already
run code as the writer and as every participant, so nothing in its tree needs
cleaning before others read it, provided that only it could have written that
tree. --apply therefore refuses any other account, and any tree holding an entry
owned by another account, an entry other accounts can write through its mode or
an ACL, or a hard link to a file outside the tree; the plan lists each one, and
nothing changes. While a tree moves, it, and the shared root, are closed to
every account but root, and the writer's socket is stopped.

The first ACCOUNT is the primary: when the shared root is empty and on the same
filesystem as that account's home, its whole ~/ghq is renamed to the root, an
O(1) operation. Every other repository is moved in by rename on the same
filesystem or copied (reflink or clonefile where available) across filesystems.
Where accounts hold the same repository, the deeper clone is kept. Whatever is
not moved in stays in ~/ghq.pre-shared-<date>, untouched. Everything moved in
becomes owned by the writer, gains group read, and loses group write, every
permission for others and any setuid, setgid or sticky bit. Repositories with
uncommitted changes or commits on no remote are listed before anything moves;
they move as they are.

--set-aside renames an account's ~/ghq to ~/ghq.pre-shared-<date>, still owned
by the account, links ~/ghq to the shared root, and prints each repository's
upstream URL with the ghq-sync command that reclones it through the writer; it
runs only `git config --get` in that tree.

Each step is recorded under the state directory, root-owned 0700, before it is
taken, with the prior ownership and modes; that includes the parent directories
it creates and every change of the shared root's owner or mode. --rollback undoes each recorded step
that took effect, restores ownership and modes, and gives the account whatever
the writer has created in its tree since; it records each step it undoes, so a
rollback that stopped part way can be run again. It also reads the records of
earlier versions of this tool, which kept rewritten configuration and removed
hooks as "sanitise" steps. Deleting ~/ghq.pre-shared-<date> or the state
directory is a separate, operator-authorized step this tool never takes.
"""

import argparse
import datetime
import grp
import json
import os
import pwd
import shlex
import shutil
import stat
import subprocess
import sys
import time
import urllib.parse

DARWIN = sys.platform == "darwin"
ROOT = os.path.normpath(os.environ.get("GHQ_SHARED_ROOT", "/var/lib/ghq"))
WRITER = os.environ.get("GHQ_SHARED_WRITER", "_ghq" if DARWIN else "ghq")
STATE = os.environ.get("GHQ_SHARED_STATE", "/var/lib/ghq-migration")
ADMIN_GROUP = "admin" if DARWIN else "wheel"
GIT = "@git@"
GETFACL = "@getfacl@"
CP = ["/bin/cp", "-c", "-pR"] if DARWIN else ["@cp@", "-a", "--reflink=auto"]
WRITER_LABEL = "org.vanixiets.ghq-writer"
WRITER_PLIST = f"/Library/LaunchDaemons/{WRITER_LABEL}.plist"
WRITER_UNIT = "/etc/systemd/system/ghq-writer@.service"
# Run as root once the tree is closed and the writer stopped, before the move; the NixOS test probes from here.
HOOK = os.environ.get("GHQ_SHARED_MIGRATE_HOOK")
GIT_TIMEOUT = 600


def say(*parts):
    print(*parts, flush=True)


def progress(message):
    print(f"ghq-shared-migrate: {message}", file=sys.stderr, flush=True)


class Phase:
    """Announce a phase's start and end, with elapsed time, on stderr."""

    def __init__(self, name):
        self.name = name

    def __enter__(self):
        self.start = time.monotonic()
        progress(f"{self.name}: start")
        return self

    def __exit__(self, *_):
        progress(f"{self.name}: done in {time.monotonic() - self.start:.1f}s")


class Walk:
    """Count entries in a long walk; the clock is read only every 4096 entries."""

    CHECK = 4096
    INTERVAL = 5.0

    def __init__(self, name, top):
        self.name, self.top, self.count = name, top, 0
        self.start = self.last = time.monotonic()

    def tick(self, entry):
        self.count += 1
        if self.count % self.CHECK:
            return
        now = time.monotonic()
        if now - self.last < self.INTERVAL:
            return
        self.last = now
        rate = self.count / (now - self.start)
        rel = os.path.relpath(entry, self.top)
        progress(f"{self.name}: {self.count} entries, {rate:.0f}/s, at {'/'.join(rel.split('/')[:3])}")


def entries_below(top):
    """Every entry below top, top itself last; symlinks are listed, never followed."""
    for directory, subdirs, files in os.walk(top, topdown=False):
        for name in [*files, *subdirs]:
            yield os.path.join(directory, name)
    yield top


def read_jsonl(path):
    """Every record in a JSON-lines file; a last line cut short by a crash is a step never taken, and is ignored."""
    with open(path) as handle:
        lines = [line for line in handle.read().split("\n") if line.strip()]
    records = []
    for index, line in enumerate(lines):
        try:
            records.append(json.loads(line))
        except json.JSONDecodeError:
            if index != len(lines) - 1:
                raise
    return records


def masked(mode):
    mode = stat.S_IMODE(mode) & 0o777
    readable = stat.S_IRGRP | (stat.S_IXGRP if mode & stat.S_IXUSR else 0)
    return (mode | readable) & ~(stat.S_IWGRP | stat.S_IRWXO)


def account_info(name):
    entry = pwd.getpwnam(name)
    return {"name": name, "uid": entry.pw_uid, "gid": entry.pw_gid, "home": entry.pw_dir}


def is_admin(account):
    """The same answer `id -Gn ACCOUNT` gives: membership, primary or supplementary, of the admin group."""
    try:
        gid = grp.getgrnam(ADMIN_GROUP).gr_gid
    except KeyError:
        return False
    return gid in os.getgrouplist(account["name"], account["gid"])


def acl_entries(tree):
    """Every entry below tree, tree included, that carries an ACL; symlinks are examined, never followed.

    An ACL can grant write to a group or to everyone beyond what the mode bits
    show, so a tree carrying one would let a less-privileged participant write
    the shared tree. Darwin's find tests for an extended ACL directly; on Linux
    getfacl lists only entries with more than the base ACL, and a filesystem
    without ACL support has none.
    """
    if DARWIN:
        result = subprocess.run(["/usr/bin/find", "-P", tree, "-acl", "-print0"], capture_output=True)
        if result.returncode:
            raise RuntimeError(f"find -acl failed on {tree}: {result.stderr.decode(errors='replace').strip()}")
        return sorted(filter(None, result.stdout.decode(errors="surrogateescape").split("\0")))
    result = subprocess.run([GETFACL, "-R", "-P", "-s", "-p", tree], capture_output=True)
    found = [line.removeprefix("# file: ") for line in result.stdout.decode(errors="surrogateescape").splitlines()
             if line.startswith("# file: ")]
    errors = [line for line in result.stderr.decode(errors="replace").splitlines() if "Operation not supported" not in line]
    if result.returncode and errors:
        raise RuntimeError(f"getfacl failed on {tree}: {' '.join(errors)}")
    return sorted(found)


def group_members(gid, cache={}):
    """Every account in group gid, as the system resolves membership (nested groups included), or None if unknown."""
    if gid not in cache:
        try:
            # getgrouplist takes a C int; darwin's nobody-style gids above 2**31 pass as their negative.
            cache[gid] = {entry.pw_name for entry in pwd.getpwall()
                          if gid in os.getgrouplist(entry.pw_name, entry.pw_gid - (1 << 32) * (entry.pw_gid >= 1 << 31))}
        except OSError:
            cache[gid] = None
    return cache[gid]


def private_group(gid, account):
    try:
        return gid == account["gid"] and grp.getgrgid(gid).gr_name == account["name"]
    except KeyError:
        return False


def exposure(tree, account):
    """Every entry another account could have written: owned by it, writable by it, or a hard link reaching outside.

    An administrator's tree moves as it is only because the administrator gains
    nothing from what it wrote itself; anything another account could have
    written would carry that account's configuration to every reader.
    """
    found, inodes = [], {}
    for entry in entries_below(tree):
        st = os.lstat(entry)
        if st.st_uid not in (account["uid"], 0):
            found.append((entry, f"owned by uid {st.st_uid}"))
        if not stat.S_ISLNK(st.st_mode):
            if st.st_mode & stat.S_IWOTH:
                found.append((entry, "writable by every account"))
            elif st.st_mode & stat.S_IWGRP:
                members = group_members(st.st_gid)
                if members is None and not private_group(st.st_gid, account):
                    found.append((entry, f"writable by group {st.st_gid}, whose members cannot be determined"))
                elif members is not None and members - {account["name"]}:
                    found.append((entry, f"writable by group {st.st_gid}, which has other members"))
        if not stat.S_ISDIR(st.st_mode) and st.st_nlink > 1:
            inodes.setdefault((st.st_dev, st.st_ino), [st.st_nlink, []])[1].append(entry)
    for nlink, paths in inodes.values():
        if len(paths) < nlink:
            found += [(path, f"hard link with {nlink - len(paths)} link(s) outside the tree") for path in paths]
    found += [(path, "carries an ACL") for path in acl_entries(tree)]
    return sorted(found)


def as_account(account, *args):
    """Run git as the account in a session of its own, with no terminal, no input and a time limit."""
    env = {"HOME": account["home"], "PATH": "/usr/bin:/bin", "LANG": "C.UTF-8", "GIT_TERMINAL_PROMPT": "0"}
    try:
        result = subprocess.run(
            [GIT, "--no-optional-locks", "-c", "core.fsmonitor=false", *args],
            user=account["uid"],
            group=account["gid"],
            extra_groups=[],
            env=env,
            stdin=subprocess.DEVNULL,
            capture_output=True,
            text=True,
            start_new_session=True,
            timeout=GIT_TIMEOUT,
        )
    except subprocess.TimeoutExpired:
        return None
    return result.stdout.strip() if result.returncode == 0 else None


def repositories(tree):
    found = []
    for directory, subdirs, files in os.walk(tree):
        if ".git" in subdirs or ".git" in files:
            found.append(os.path.relpath(directory, tree))
            subdirs[:] = []
        else:
            subdirs[:] = [d for d in subdirs if not os.path.islink(os.path.join(directory, d))]
    return sorted(found)


def inspect_config(account, path):
    """What a tree set aside needs: its upstream URL and whether it is lazy, read with `git config --get` alone."""
    gitdir = os.path.join(path, ".git")
    partial = bool(as_account(account, "-C", path, "config", "--get-regexp", r"^remote\..*\.(promisor|partialclonefilter)$"))
    return {
        "path": path,
        "gitfile": os.path.isfile(gitdir),
        "url": as_account(account, "-C", path, "config", "--get", "remote.origin.url"),
        "lazy": partial or os.path.isfile(os.path.join(gitdir, "shallow")),
    }


def inspect(account, path):
    info = {"path": path, "gitfile": os.path.isfile(os.path.join(path, ".git"))}
    shallow = as_account(account, "-C", path, "rev-parse", "--is-shallow-repository") == "true"
    partial = bool(as_account(account, "-C", path, "config", "--get-regexp", r"^remote\..*\.(promisor|partialclonefilter)$"))
    count = as_account(account, "-C", path, "rev-list", "--count", "HEAD")
    info.update(
        url=as_account(account, "-C", path, "config", "--get", "remote.origin.url"),
        lazy=shallow or partial,
        count=int(count) if count and count.isdigit() else 0,
        dirty=bool(as_account(account, "-C", path, "status", "--porcelain", "--untracked-files=no")),
        local_only=as_account(account, "-C", path, "rev-list", "--count", "--branches", "--not", "--remotes") not in (None, "0"),
    )
    info["rank"] = (0 if shallow else 1 if partial else 2, info["count"])
    return info


def plan(accounts, date):
    root_empty = not os.path.exists(ROOT) or not os.listdir(ROOT)
    root_parent_dev = os.stat(os.path.dirname(ROOT)).st_dev
    entries, holders = [], {}
    for index, account in enumerate(accounts):
        tree = os.path.join(account["home"], "ghq")
        if os.path.islink(tree) or not os.path.isdir(tree):
            say(f"{account['name']}: {tree} is not a directory; nothing to move")
            continue
        same_volume = os.stat(tree).st_dev == root_parent_dev
        admin = is_admin(account)
        look = inspect if admin else inspect_config
        with Phase(f"plan {account['name']}"):
            found = repositories(tree)
            repos, last = {}, time.monotonic()
            for k, rel in enumerate(found, 1):
                repos[rel] = look(account, os.path.join(tree, rel))
                if k == len(found) or time.monotonic() - last >= 2.0:
                    last = time.monotonic()
                    progress(f"plan {account['name']}: inspected {k}/{len(found)} repositories")
        entries.append({
            "account": account,
            "admin": admin,
            "refusals": exposure(tree, account) if admin else [],
            "tree": tree,
            "top": [os.lstat(tree).st_uid, os.lstat(tree).st_gid, stat.S_IMODE(os.lstat(tree).st_mode)],
            "aside": os.path.join(account["home"], f"ghq.pre-shared-{date}"),
            "rename_whole": index == 0 and root_empty and same_volume,
            "same_volume": same_volume,
            "repos": repos,
        })
        if admin:
            for rel, info in repos.items():
                if not info["gitfile"]:
                    holders.setdefault(rel, []).append((info["rank"], -index, account["name"]))
    if os.path.isdir(ROOT):
        for rel in repositories(ROOT):
            holders.setdefault(rel, []).append(((9, 0), 1, "<shared root>"))
    winners = {rel: max(candidates)[2] for rel, candidates in holders.items()}
    return entries, winners


def writer_protocols():
    """The protocols the writer accepts, from its own configuration; https when that cannot be found."""
    try:
        if DARWIN:
            import plistlib
            with open(WRITER_PLIST, "rb") as handle:
                config = plistlib.load(handle)["ProgramArguments"][1]
        else:
            with open(WRITER_UNIT) as handle:
                config = next(word for line in handle if line.startswith("ExecStart=")
                              for word in line.split() if word.endswith(".json"))
        with open(config) as handle:
            return set(json.load(handle)["allowedProtocols"])
    except (OSError, KeyError, IndexError, StopIteration, ValueError):
        return {"https"}


def printable(text):
    return text.isprintable() and not any(c.isspace() for c in text)


def reclone_commands(entry, protocols):
    """The ghq-sync command that reacquires each repository through the writer, or why there is none.

    Every value comes from the account's own tree, so each is checked before it
    is printed: non-printable text is refused, credentials are removed, and a
    protocol the writer refuses is reported rather than turned into a command.
    """
    lines = []
    for rel, info in entry["repos"].items():
        where = shlex.quote(rel) if printable(rel) else "<a repository with a non-printable path>"
        url = info["url"]
        if not url:
            lines.append(f"  {where}: no upstream URL; it stays only in {entry['aside']}")
            continue
        if not printable(url):
            lines.append(f"  {where}: not reacquirable: its upstream URL holds non-printable characters")
            continue
        try:
            parts = urllib.parse.urlsplit(url)
        except ValueError:
            lines.append(f"  {where}: not reacquirable: {shlex.quote(url.split('@')[-1])} is not a URL the writer accepts")
            continue
        if not parts.scheme or "://" not in url:
            lines.append(f"  {where}: not reacquirable: {shlex.quote(url.split('@')[-1])} is not a URL the writer accepts")
            continue
        clean = urllib.parse.urlunsplit(parts._replace(netloc=parts.netloc.rsplit("@", 1)[-1]))
        if parts.scheme not in protocols:
            lines.append(f"  {where}: not reacquirable: the writer does not accept {parts.scheme} ({shlex.quote(clean)})")
            continue
        lines.append(f"  ghq-sync {'' if info['lazy'] else '--full '}{shlex.quote(clean)}")
    return lines


def report(entries, winners, set_aside):
    protocols = writer_protocols()
    for entry in entries:
        name = entry["account"]["name"]
        if set_aside:
            say(f"{name}: {entry['tree']} ({len(entry['repos'])} repositories) is renamed to {entry['aside']};"
                f" reclone through the writer, as {name}:")
            for line in reclone_commands(entry, protocols):
                say(line)
            continue
        if not entry["admin"]:
            say(f"{name}: refused: not an administrator ({ADMIN_GROUP}) of this host, so its tree is not moved in place;"
                f" use --set-aside {name}, which leaves these to reclone through the writer, as {name}:")
            for line in reclone_commands(entry, protocols):
                say(line)
            continue
        if entry["refusals"]:
            say(f"{name}: refused: {len(entry['refusals'])} entries in {entry['tree']} could have been written by another"
                f" account, which would then write the shared tree; correct them and rerun:")
            for path, reason in entry["refusals"]:
                say(f"  refused: {path if printable(path) else repr(path)}: {reason}")
            continue
        mode = "rename whole tree" if entry["rename_whole"] else "rename per repository" if entry["same_volume"] else "copy per repository"
        say(f"{name}: {entry['tree']} ({len(entry['repos'])} repositories; {mode})")
        for rel, info in entry["repos"].items():
            flags = []
            if info["gitfile"]:
                flags.append("has a .git file; stays aside")
            else:
                if info["dirty"]:
                    flags.append("uncommitted changes")
                if info["local_only"]:
                    flags.append("commits on no remote")
                if winners.get(rel) != name:
                    flags.append(f"kept aside; {winners.get(rel)} holds the deeper clone")
            if flags:
                say(f"  {rel}: {', '.join(flags)}")


class Manifest:
    def __init__(self, account, date):
        self.dir = os.path.join(STATE, account["name"])
        os.makedirs(STATE, mode=0o700, exist_ok=True)
        os.chmod(STATE, 0o700)
        os.mkdir(self.dir, 0o700)
        self.path = os.path.join(self.dir, "manifest.jsonl")
        self.handle = open(self.path, "a")
        self.record({"op": "begin", "date": date, "time": time.time(), "account": account})

    def record(self, step):
        self.handle.write(json.dumps(step) + "\n")
        self.handle.flush()
        os.fsync(self.handle.fileno())


def ensure_parents(path, stop, owner, manifest):
    missing = []
    parent = os.path.dirname(path)
    while parent != stop and not os.path.isdir(parent):
        missing.append(parent)
        parent = os.path.dirname(parent)
    if missing:
        manifest.record({"op": "mkdirs", "paths": list(reversed(missing))})
    for directory in reversed(missing):
        os.mkdir(directory, 0o750)
        os.chown(directory, owner["uid"], owner["gid"])


def prune_empty(path, stop):
    while path != stop and path.startswith(stop + "/") and os.path.isdir(path) and not os.listdir(path):
        os.rmdir(path)
        path = os.path.dirname(path)


def place(source, destination, same_volume, manifest, owner, stop):
    ensure_parents(destination, stop, owner, manifest)
    if same_volume:
        manifest.record({"op": "rename", "src": source, "dst": destination})
        os.rename(source, destination)
        return
    # The copy is made under a name of its own, so rollback removes only what it made.
    made = f"{destination}.ghq-shared-migrate-copy"
    if os.path.lexists(made):
        raise RuntimeError(f"{made} already exists")
    manifest.record({"op": "copy", "src": source, "dst": destination, "made": made})
    subprocess.run([*CP, source, made], check=True)
    manifest.record({"op": "rename", "src": made, "dst": destination})
    os.rename(made, destination)


def fix_ownership(path, writer, manifest, sidecar, hold=False):
    """Record every entry's owner and mode, then hand the tree to the writer with masked modes.

    With hold, the top stays 0700 until link_root opens it to the writer's group.
    """
    recorded = {}
    for entry in entries_below(path):
        st = os.lstat(entry)
        recorded[os.path.relpath(entry, path)] = [st.st_uid, st.st_gid, stat.S_IMODE(st.st_mode)]
    os.makedirs(sidecar, mode=0o700, exist_ok=True)
    with open(os.path.join(sidecar, "ownership.json"), "w") as handle:
        json.dump(recorded, handle)
        handle.flush()
        os.fsync(handle.fileno())
    manifest.record({"op": "ownership", "path": path, "sidecar": sidecar})
    walk = Walk("ownership", path)
    for entry in entries_below(path):
        walk.tick(entry)
        st = os.lstat(entry)
        os.lchown(entry, writer["uid"], writer["gid"])
        if hold and entry == path:
            os.chmod(entry, 0o700)
        elif not stat.S_ISLNK(st.st_mode):
            # chown clears setuid and setgid on Linux; masking keeps chmod from setting them again.
            os.chmod(entry, masked(st.st_mode))


def set_mode(path, uid, gid, mode, manifest):
    """Change a directory's owner and mode, recording the prior ones first."""
    st = os.lstat(path)
    manifest.record({"op": "chmod", "path": path, "uid": st.st_uid, "gid": st.st_gid, "mode": stat.S_IMODE(st.st_mode)})
    os.chown(path, uid, gid)
    os.chmod(path, mode)


def link_root(entry, writer, manifest):
    account = entry["account"]
    set_mode(ROOT, writer["uid"], writer["gid"], 0o750, manifest)
    manifest.record({"op": "symlink", "path": entry["tree"]})
    os.symlink(ROOT, entry["tree"])
    os.lchown(entry["tree"], account["uid"], account["gid"])


def migrate(entry, winners, writer, date):
    account = entry["account"]
    name = account["name"]
    manifest = Manifest(account, date)
    moved = []
    # Nothing in the tree, and nothing under the shared root, is reachable by any
    # account but root until link_root opens the root to the writer's group.
    uid, gid, mode = entry["top"]
    set_mode(entry["tree"], uid, gid, 0o700, manifest)
    if not entry["rename_whole"]:
        set_mode(ROOT, 0, 0, 0o700, manifest)
        if HOOK:
            subprocess.run(HOOK, shell=True, check=True)
    if entry["rename_whole"]:
        with Phase(f"rename {name}"):
            if os.path.isdir(ROOT):
                manifest.record({"op": "rmdir-root", "path": ROOT})
                os.rmdir(ROOT)
            manifest.record({"op": "rename", "src": entry["tree"], "dst": ROOT})
            os.rename(entry["tree"], ROOT)
            if HOOK:
                subprocess.run(HOOK, shell=True, check=True)
            manifest.record({"op": "mkdir", "path": entry["aside"]})
            os.makedirs(entry["aside"], mode=0o700, exist_ok=True)
            os.chown(entry["aside"], account["uid"], account["gid"])
            for rel, info in entry["repos"].items():
                if info["gitfile"] or winners.get(rel) != name:
                    place(os.path.join(ROOT, rel), os.path.join(entry["aside"], rel), True, manifest, account, entry["aside"])
                else:
                    moved.append(rel)
        with Phase(f"ownership {name}"):
            fix_ownership(ROOT, writer, manifest, os.path.join(manifest.dir, "root"), hold=True)
    else:
        with Phase(f"{'rename' if entry['same_volume'] else 'copy'} and ownership {name}"):
            for rel, info in entry["repos"].items():
                if info["gitfile"] or winners.get(rel) != name:
                    continue
                if os.path.lexists(os.path.join(ROOT, rel)):
                    say(f"  {rel}: {os.path.join(ROOT, rel)} appeared after the plan; stays aside")
                    continue
                place(os.path.join(entry["tree"], rel), os.path.join(ROOT, rel), entry["same_volume"], manifest, writer, ROOT)
                fix_ownership(os.path.join(ROOT, rel), writer, manifest, os.path.join(manifest.dir, "repos", rel))
                moved.append(rel)
            manifest.record({"op": "rename", "src": entry["tree"], "dst": entry["aside"]})
            os.rename(entry["tree"], entry["aside"])
            # The tree's own mode comes back with it; only its place changed.
            set_mode(entry["aside"], uid, gid, mode, manifest)
    with Phase(f"link {name}"):
        link_root(entry, writer, manifest)
    manifest.record({"op": "end"})
    say(f"{name}: moved {len(moved)} repositories into {ROOT}; everything else is in {entry['aside']}")


def set_aside(entry, writer, date):
    account = entry["account"]
    manifest = Manifest(account, date)
    with Phase(f"set aside {account['name']}"):
        manifest.record({"op": "rename", "src": entry["tree"], "dst": entry["aside"]})
        os.rename(entry["tree"], entry["aside"])
        link_root(entry, writer, manifest)
    manifest.record({"op": "end"})
    say(f"{account['name']}: {entry['tree']} is now {entry['aside']} and ~/ghq links to {ROOT}")


def writer_pids(uid):
    if DARWIN:
        result = subprocess.run(["/usr/bin/pgrep", "-U", str(uid)], capture_output=True, text=True)
        return result.stdout.split()
    found = []
    for pid in filter(str.isdigit, os.listdir("/proc")):
        try:
            with open(f"/proc/{pid}/status") as handle:
                if any(line.startswith("Uid:") and line.split()[1] == str(uid) for line in handle):
                    found.append(pid)
        except OSError:
            pass
    return found


class WriterStopped:
    """Stop the writer's socket, and any handler it started, for as long as root changes the shared tree.

    Root walks the tree by path, so a writer running meanwhile could swap an
    entry for a symlink and redirect a chown or chmod. The writer comes back on
    exit, error or not, if it was running before.
    """

    def __init__(self, writer):
        self.writer, self.running = writer, False
        self.systemctl = shutil.which("systemctl") or "/run/current-system/sw/bin/systemctl"

    def __enter__(self):
        if DARWIN:
            loaded = lambda: subprocess.run(["/bin/launchctl", "print", f"system/{WRITER_LABEL}"],
                                            capture_output=True).returncode == 0
            self.running = loaded()
            if self.running:
                subprocess.run(["/bin/launchctl", "bootout", f"system/{WRITER_LABEL}"], check=False)
            still = self.running and loaded()
        elif os.path.exists(self.systemctl):
            active = lambda: subprocess.run([self.systemctl, "is-active", "--quiet", "ghq-writer.socket"]).returncode == 0
            self.running = active()
            subprocess.run([self.systemctl, "stop", "ghq-writer.socket", "ghq-writer@*.service"], check=False)
            still = active()
        else:
            still = False
        if still:
            self.__exit__(None, None, None)
            sys.exit("ghq-shared-migrate: refused: the writer could not be stopped; nothing changed")
        progress("writer stopped")
        if pids := writer_pids(self.writer["uid"]):
            self.__exit__(None, None, None)
            sys.exit(f"ghq-shared-migrate: refused: processes of the writer are running ({' '.join(pids)}); nothing changed")
        return self

    def __exit__(self, *_):
        if not self.running:
            return
        if DARWIN:
            result = subprocess.run(["/bin/launchctl", "bootstrap", "system", WRITER_PLIST], capture_output=True, text=True)
        else:
            result = subprocess.run([self.systemctl, "start", "ghq-writer.socket"], capture_output=True, text=True)
        self.running = False
        if result.returncode:
            progress(f"failed to start the writer again (exit {result.returncode}): {result.stderr.strip()};"
                     f" start it by hand")
        else:
            progress("writer started again")


def standing(name):
    return os.path.lexists(os.path.join(STATE, name))


def run(entries, winners, writer, date, step):
    # A second manifest for an account would share the first one's sidecar.
    held = [entry["account"]["name"] for entry in entries if standing(entry["account"]["name"])]
    if held:
        sys.exit(f"ghq-shared-migrate: refused: {', '.join(held)} already migrated and not rolled back"
                 f" (see {STATE}); roll back first; nothing changed")
    for index, entry in enumerate(entries):
        try:
            step(entry)
        except BaseException as error:
            names = [e["account"]["name"] for e in entries[:index + 1]]
            print(f"ghq-shared-migrate: failed while handling {entry['account']['name']}: {error!r};"
                  f" roll back with: ghq-shared-migrate --rollback {' '.join(names)}", file=sys.stderr, flush=True)
            raise


def restore_ownership(path, sidecar, account, writer):
    """Give back each recorded owner and mode, and the account every other writer-owned entry."""
    record = os.path.join(sidecar, "ownership.json")
    if not os.path.lexists(path) or not os.path.exists(record):
        return
    with open(record) as handle:
        recorded = json.load(handle)
    walk = Walk("restore ownership", path)
    for entry in entries_below(path):
        walk.tick(entry)
        st = os.lstat(entry)
        rel = os.path.relpath(entry, path)
        if rel in recorded:
            uid, gid, mode = recorded[rel]
            os.lchown(entry, uid, gid)
            if not stat.S_ISLNK(st.st_mode):
                os.chmod(entry, mode)
        elif st.st_uid == writer["uid"]:
            os.lchown(entry, account["uid"], account["gid"])


def undo(step, account, writer):
    """Undo one recorded step; a step that never took effect, or was already undone, changes nothing."""
    op = step["op"]
    if op == "symlink":
        if os.path.islink(step["path"]):
            os.unlink(step["path"])
    elif op == "sanitise":
        # Written by earlier versions of this tool: the original configuration file or hook.
        if os.path.lexists(step["kept"]) and os.path.isdir(os.path.dirname(step["path"])):
            # A symlink at the destination would redirect root's write; the file it replaces is restored, not followed.
            if os.path.islink(step["path"]):
                os.unlink(step["path"])
            shutil.copy2(step["kept"], step["path"], follow_symlinks=False)
    elif op == "ownership":
        restore_ownership(step["path"], step["sidecar"], account, writer)
    elif op == "rename":
        if not os.path.lexists(step["src"]) and os.path.lexists(step["dst"]):
            os.makedirs(os.path.dirname(step["src"]), exist_ok=True)
            os.rename(step["dst"], step["src"])
            prune_empty(os.path.dirname(step["dst"]), ROOT)
    elif op == "copy":
        # Earlier versions copied straight to dst; this one copies to "made" and renames it into place.
        made = step.get("made", step["dst"])
        if os.path.lexists(made):
            shutil.rmtree(made)
            prune_empty(os.path.dirname(made), ROOT)
    elif op == "mkdirs":
        for path in reversed(step["paths"]):
            if os.path.isdir(path) and not os.path.islink(path) and not os.listdir(path):
                os.rmdir(path)
    elif op == "chmod":
        if os.path.isdir(step["path"]) and not os.path.islink(step["path"]):
            os.chown(step["path"], step["uid"], step["gid"])
            os.chmod(step["path"], step["mode"])
    elif op == "mkdir":
        if os.path.isdir(step["path"]):
            for directory, _subdirs, _files in sorted(os.walk(step["path"]), reverse=True):
                prune_empty(directory, os.path.dirname(step["path"]))
    elif op == "rmdir-root":
        if not os.path.lexists(step["path"]):
            os.mkdir(step["path"], 0o750)
            os.chown(step["path"], writer["uid"], writer["gid"])
            os.chmod(step["path"], 0o750)


def rollback(names, writer):
    order, cleared = [], set()
    for name in os.listdir(STATE) if os.path.isdir(STATE) else []:
        path = os.path.join(STATE, name, "manifest.jsonl")
        if ".rolled-back-" in name:
            continue
        steps = read_jsonl(path) if os.path.isfile(path) else []
        if not steps:
            # A run that stopped before recording anything took no step; clearing it lets apply run again.
            if name in names:
                os.rename(os.path.join(STATE, name), os.path.join(STATE, f"{name}.rolled-back-{datetime.datetime.now():%Y%m%d%H%M%S}"))
                say(f"{name}: no step was taken; cleared")
                cleared.add(name)
            continue
        # Records of earlier versions carry no start time; their file's modification time stands in.
        order.append((steps[0]["date"], steps[0].get("time", os.path.getmtime(path)), name, steps))
    order.sort()
    selected = [item for item in order if item[2] in names]
    for name in sorted(set(names) - {item[2] for item in selected} - cleared):
        say(f"{name}: nothing to roll back")
    if not selected:
        return
    later = {item[2] for item in order[order.index(selected[0]):]}
    if missing := later - set(names):
        sys.exit(f"roll back {', '.join(sorted(missing))} too: they ran after {selected[0][2]}")
    for _date, _mtime, name, steps in reversed(selected):
        # Each undone step is recorded, so a rollback run again resumes where the last one stopped.
        journal = os.path.join(STATE, name, "undone.jsonl")
        done = set()
        if os.path.exists(journal):
            done = set(read_jsonl(journal))
        with Phase(f"rollback {name}"), open(journal, "a") as log:
            for index in reversed(range(len(steps))):
                if index in done:
                    continue
                undo(steps[index], steps[0]["account"], writer)
                log.write(json.dumps(index) + "\n")
                log.flush()
                os.fsync(log.fileno())
        os.rename(os.path.join(STATE, name), os.path.join(STATE, f"{name}.rolled-back-{datetime.datetime.now():%Y%m%d%H%M%S}"))
        say(f"{name}: rolled back")


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    action = parser.add_mutually_exclusive_group()
    action.add_argument("--apply", action="store_true")
    action.add_argument("--set-aside", action="store_true")
    action.add_argument("--rollback", action="store_true")
    parser.add_argument("accounts", nargs="+", metavar="ACCOUNT")
    args = parser.parse_args()
    if os.geteuid() != 0:
        sys.exit("ghq-shared-migrate must run as root")
    writer = {"uid": pwd.getpwnam(WRITER).pw_uid, "gid": grp.getgrnam(WRITER).gr_gid}
    if args.rollback:
        with WriterStopped(writer):
            rollback(args.accounts, writer)
        return
    date = datetime.date.today().strftime("%Y%m%d")
    entries, winners = plan([account_info(name) for name in args.accounts], date)
    report(entries, winners, args.set_aside)
    if args.set_aside:
        run(entries, winners, writer, date, lambda entry: set_aside(entry, writer, date))
        return
    if not args.apply:
        say("dry run: nothing changed; rerun with --apply" + (" or --set-aside" if any(not e["admin"] for e in entries) else ""))
        return
    refused = [entry["account"]["name"] for entry in entries if not entry["admin"]]
    if refused:
        sys.exit(f"ghq-shared-migrate: refused: {', '.join(refused)} not an administrator ({ADMIN_GROUP}) of this host;"
                 f" nothing changed; use --set-aside for them")
    exposed = [entry["account"]["name"] for entry in entries if entry["refusals"]]
    if exposed:
        sys.exit(f"ghq-shared-migrate: refused: the tree of {', '.join(exposed)} holds entries another account could have"
                 f" written (listed above); nothing changed")
    with WriterStopped(writer):
        run(entries, winners, writer, date, lambda entry: migrate(entry, winners, writer, date))


if __name__ == "__main__":
    main()
