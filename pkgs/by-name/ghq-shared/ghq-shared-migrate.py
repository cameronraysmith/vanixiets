"""Move per-account ghq trees into the host's shared tree, or roll that back.

Usage:
  ghq-shared-migrate [--apply] ACCOUNT...      plan (default) or apply, in order
  ghq-shared-migrate --rollback ACCOUNT...     undo, for these accounts

Run as root. The first ACCOUNT is the primary: when the shared root is empty and
on the same filesystem as that account's home, its whole ~/ghq is renamed to the
root, an O(1) operation. Every other repository is moved in by rename on the
same filesystem or copied (reflink or clonefile where available) across
filesystems. Where accounts hold the same repository, the deeper clone is kept.
Whatever is not moved in stays in ~/ghq.pre-shared-<date>, untouched.

Everything moved in becomes owned by the writer, gains group read, loses group
write and every permission for others, and has every .git/config (and config.worktree, and submodule configs)
rewritten to an allow-list of keys and every non-sample hook removed. Originals,
a manifest of every step and the prior ownership and modes are kept under the
state directory, root-owned 0700, outside the shared root, so --rollback
restores each account exactly. Repositories with uncommitted changes or
commits on no remote are listed before anything moves; they move as they are.
Deleting ~/ghq.pre-shared-<date> or the state directory is a separate,
operator-authorized step this tool never takes.
"""

import argparse
import datetime
import fnmatch
import grp
import json
import os
import pwd
import shutil
import stat
import subprocess
import sys
import time

DARWIN = sys.platform == "darwin"
ROOT = os.environ.get("GHQ_SHARED_ROOT", "/var/lib/ghq")
WRITER = os.environ.get("GHQ_SHARED_WRITER", "_ghq" if DARWIN else "ghq")
STATE = os.environ.get("GHQ_SHARED_STATE", "/var/lib/ghq-migration")
GIT = "@git@"
CP = ["/bin/cp", "-c", "-pR"] if DARWIN else ["@cp@", "-a", "--reflink=auto"]

ALLOWED_KEYS = [
    "core.repositoryformatversion",
    "core.bare",
    "core.filemode",
    "core.logallrefupdates",
    "core.ignorecase",
    "core.precomposeunicode",
    "core.symlinks",
    "extensions.*",
    "remote.*.url",
    "remote.*.fetch",
    "remote.*.promisor",
    "remote.*.partialclonefilter",
    "remote.*.tagopt",
    "branch.*.remote",
    "branch.*.merge",
    "submodule.*.url",
    "submodule.*.active",
]


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

    def __init__(self, name, root):
        self.name, self.root, self.count = name, root, 0
        self.start = self.last = time.monotonic()

    def tick(self, path):
        self.count += 1
        if self.count % self.CHECK:
            return
        now = time.monotonic()
        if now - self.last < self.INTERVAL:
            return
        self.last = now
        rel = os.path.relpath(path, self.root).split(os.sep)
        where = os.sep.join(rel[:3]) if rel[0] != "." else "."
        rate = self.count / (now - self.start)
        progress(f"{self.name}: {self.count} entries, {rate:.0f}/s, at {where}")


def account_info(name):
    entry = pwd.getpwnam(name)
    return {"name": name, "uid": entry.pw_uid, "gid": entry.pw_gid, "home": entry.pw_dir}


def as_account(account, *args):
    env = {"HOME": account["home"], "PATH": "/usr/bin:/bin", "LANG": "C.UTF-8", "GIT_TERMINAL_PROMPT": "0"}
    result = subprocess.run(
        [GIT, "--no-optional-locks", *args],
        user=account["uid"],
        group=account["gid"],
        extra_groups=[],
        env=env,
        capture_output=True,
        text=True,
    )
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


def inspect(account, path):
    gitdir = os.path.join(path, ".git")
    info = {"path": path, "gitfile": os.path.isfile(gitdir)}
    if info["gitfile"]:
        return info
    shallow = as_account(account, "-C", path, "rev-parse", "--is-shallow-repository") == "true"
    partial = bool(as_account(account, "-C", path, "config", "--get-regexp", r"^remote\..*\.(promisor|partialclonefilter)$"))
    count = as_account(account, "-C", path, "rev-list", "--count", "HEAD")
    info.update(
        shallow=shallow,
        partial=partial,
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
        with Phase(f"plan {account['name']}"):
            found = repositories(tree)
            repos, last = {}, time.monotonic()
            for k, rel in enumerate(found, 1):
                repos[rel] = inspect(account, os.path.join(tree, rel))
                if k == len(found) or time.monotonic() - last >= 2.0:
                    last = time.monotonic()
                    progress(f"plan {account['name']}: inspected {k}/{len(found)} repositories")
        entries.append({
            "account": account,
            "tree": tree,
            "aside": os.path.join(account["home"], f"ghq.pre-shared-{date}"),
            "rename_whole": index == 0 and root_empty and same_volume,
            "same_volume": same_volume,
            "repos": repos,
        })
        for rel, info in repos.items():
            if not info["gitfile"]:
                holders.setdefault(rel, []).append((info["rank"], -index, account["name"]))
    if os.path.isdir(ROOT):
        for rel in repositories(ROOT):
            holders.setdefault(rel, []).append(((9, 0), 1, "<shared root>"))
    winners = {rel: max(candidates)[2] for rel, candidates in holders.items()}
    return entries, winners


def report(entries, winners):
    for entry in entries:
        name = entry["account"]["name"]
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
        os.makedirs(self.dir, mode=0o700, exist_ok=True)
        os.chmod(STATE, 0o700)
        self.path = os.path.join(self.dir, "manifest.jsonl")
        self.handle = open(self.path, "a")
        self.record({"op": "begin", "date": date, "account": account})

    def record(self, step):
        self.handle.write(json.dumps(step) + "\n")
        self.handle.flush()
        os.fsync(self.handle.fileno())


def fix_ownership(path, writer, manifest, sidecar):
    exceptions = {}
    walk = Walk("ownership", path)
    for directory, subdirs, files in os.walk(path):
        for name in [*subdirs, *files, ""] if directory == path else [*subdirs, *files]:
            entry = os.path.join(directory, name) if name else directory
            walk.tick(entry)
            st = os.lstat(entry)
            exceptions[os.path.relpath(entry, path)] = [st.st_uid, st.st_gid, stat.S_IMODE(st.st_mode)]
            os.lchown(entry, writer["uid"], writer["gid"])
            if not stat.S_ISLNK(st.st_mode):
                mode = stat.S_IMODE(st.st_mode)
                readable = stat.S_IRGRP | (stat.S_IXGRP if mode & stat.S_IXUSR else 0)
                os.chmod(entry, (mode | readable) & ~(stat.S_IWGRP | stat.S_IRWXO))
    os.makedirs(sidecar, mode=0o700, exist_ok=True)
    with open(os.path.join(sidecar, "ownership.json"), "w") as handle:
        json.dump(exceptions, handle)
    manifest.record({"op": "ownership", "path": path, "sidecar": sidecar})


def sanitise(path, sidecar, manifest):
    gitdir = os.path.join(path, ".git")
    for directory, subdirs, files in os.walk(gitdir):
        rel = os.path.relpath(directory, gitdir)
        for name in files:
            source = os.path.join(directory, name)
            is_config = name in ("config", "config.worktree") and (rel == "." or rel.startswith("modules"))
            is_hook = os.path.basename(directory) == "hooks" and not name.endswith(".sample")
            if not (is_config or is_hook):
                continue
            kept = os.path.join(sidecar, "git", rel, name)
            os.makedirs(os.path.dirname(kept), mode=0o700, exist_ok=True)
            shutil.copy2(source, kept, follow_symlinks=False)
            manifest.record({"op": "sanitise", "path": source, "kept": kept})
            if is_hook:
                os.unlink(source)
                continue
            listing = subprocess.run(
                [GIT, "config", "--file", source, "--list", "--null"],
                capture_output=True, check=True, env={"GIT_CONFIG_NOSYSTEM": "1", "HOME": "/var/empty"},
            ).stdout.decode()
            fresh = source + ".sanitised"
            open(fresh, "w").close()
            for item in filter(None, listing.split("\0")):
                key, _, value = item.partition("\n")
                if any(fnmatch.fnmatchcase(key, pattern) for pattern in ALLOWED_KEYS):
                    subprocess.run([GIT, "config", "--file", fresh, "--add", key, value], check=True,
                                   env={"GIT_CONFIG_NOSYSTEM": "1", "HOME": "/var/empty"})
            shutil.copymode(source, fresh)
            owner = os.lstat(source)
            os.chown(fresh, owner.st_uid, owner.st_gid)
            os.replace(fresh, source)


def ensure_parents(path, stop, owner):
    missing = []
    parent = os.path.dirname(path)
    while parent != stop and not os.path.isdir(parent):
        missing.append(parent)
        parent = os.path.dirname(parent)
    for directory in reversed(missing):
        os.mkdir(directory, 0o750)
        os.chown(directory, owner["uid"], owner["gid"])


def prune_empty(path, stop):
    while path != stop and os.path.isdir(path) and not os.listdir(path):
        os.rmdir(path)
        path = os.path.dirname(path)


def place(source, destination, same_volume, manifest, owner, stop):
    ensure_parents(destination, stop, owner)
    if same_volume:
        os.rename(source, destination)
        manifest.record({"op": "rename", "src": source, "dst": destination})
    else:
        subprocess.run([*CP, source, destination], check=True)
        manifest.record({"op": "copy", "src": source, "dst": destination})


def apply(entries, winners, writer, date):
    for entry in entries:
        account = entry["account"]
        name = account["name"]
        manifest = Manifest(account, date)
        moved = []
        if entry["rename_whole"]:
            with Phase(f"rename {name}"):
                if os.path.isdir(ROOT):
                    os.rmdir(ROOT)
                    manifest.record({"op": "rmdir-root", "path": ROOT})
                os.rename(entry["tree"], ROOT)
                manifest.record({"op": "rename", "src": entry["tree"], "dst": ROOT})
                os.makedirs(entry["aside"], mode=0o700, exist_ok=True)
                os.chown(entry["aside"], account["uid"], account["gid"])
                manifest.record({"op": "mkdir", "path": entry["aside"]})
                for rel, info in entry["repos"].items():
                    if info["gitfile"] or winners.get(rel) != name:
                        place(os.path.join(ROOT, rel), os.path.join(entry["aside"], rel), True, manifest, account, entry["aside"])
                    else:
                        moved.append(rel)
            with Phase(f"ownership {name}"):
                fix_ownership(ROOT, writer, manifest, os.path.join(manifest.dir, "root"))
        else:
            with Phase(f"{'rename' if entry['same_volume'] else 'copy'} and ownership {name}"):
                for rel, info in entry["repos"].items():
                    if info["gitfile"] or winners.get(rel) != name:
                        continue
                    place(os.path.join(entry["tree"], rel), os.path.join(ROOT, rel), entry["same_volume"], manifest, writer, ROOT)
                    fix_ownership(os.path.join(ROOT, rel), writer, manifest, os.path.join(manifest.dir, "repos", rel))
                    moved.append(rel)
                os.rename(entry["tree"], entry["aside"])
                manifest.record({"op": "rename", "src": entry["tree"], "dst": entry["aside"]})
        with Phase(f"sanitise {name}"):
            last = time.monotonic()
            for k, rel in enumerate(moved, 1):
                sanitise(os.path.join(ROOT, rel), os.path.join(manifest.dir, "repos", rel), manifest)
                if k == len(moved) or time.monotonic() - last >= 2.0:
                    last = time.monotonic()
                    progress(f"sanitise {name}: {k}/{len(moved)} repositories")
        with Phase(f"link {name}"):
            os.chown(ROOT, writer["uid"], writer["gid"])
            os.chmod(ROOT, 0o750)
            link = entry["tree"]
            os.symlink(ROOT, link)
            os.lchown(link, account["uid"], account["gid"])
            manifest.record({"op": "symlink", "path": link})
        manifest.record({"op": "end"})
        say(f"{name}: moved {len(moved)} repositories into {ROOT}; everything else is in {entry['aside']}")


def restore_ownership(path, sidecar):
    with open(os.path.join(sidecar, "ownership.json")) as handle:
        recorded = json.load(handle)
    walk = Walk("restore ownership", path)
    for rel, (uid, gid, mode) in recorded.items():
        entry = os.path.normpath(os.path.join(path, rel))
        walk.tick(entry)
        if not os.path.lexists(entry):
            continue
        os.lchown(entry, uid, gid)
        if not os.path.islink(entry):
            os.chmod(entry, mode)


def rollback(names, writer):
    order = []
    for name in os.listdir(STATE) if os.path.isdir(STATE) else []:
        if ".rolled-back-" in name:
            continue
        with open(os.path.join(STATE, name, "manifest.jsonl")) as handle:
            steps = [json.loads(line) for line in handle]
        order.append((steps[0]["date"], os.path.getmtime(os.path.join(STATE, name, "manifest.jsonl")), name, steps))
    order.sort()
    selected = [item for item in order if item[2] in names]
    later = {item[2] for item in order[order.index(selected[0]):]} if selected else set()
    if missing := later - set(names):
        sys.exit(f"roll back {', '.join(sorted(missing))} too: they were migrated after {selected[0][2]}")
    for _date, _mtime, name, steps in reversed(selected):
        with Phase(f"rollback {name}"):
            for step in reversed(steps):
                op = step["op"]
                if op == "symlink" and os.path.islink(step["path"]):
                    os.unlink(step["path"])
                elif op == "sanitise":
                    shutil.copy2(step["kept"], step["path"], follow_symlinks=False)
                elif op == "ownership":
                    restore_ownership(step["path"], step["sidecar"])
                elif op == "rename":
                    os.makedirs(os.path.dirname(step["src"]), exist_ok=True)
                    os.rename(step["dst"], step["src"])
                    prune_empty(os.path.dirname(step["dst"]), ROOT)
                elif op == "copy":
                    shutil.rmtree(step["dst"])
                    prune_empty(os.path.dirname(step["dst"]), ROOT)
                elif op == "mkdir":
                    for directory, _subdirs, _files in sorted(os.walk(step["path"]), reverse=True):
                        prune_empty(directory, os.path.dirname(step["path"]))
                elif op == "rmdir-root":
                    os.mkdir(step["path"], 0o750)
                    os.chown(step["path"], writer["uid"], writer["gid"])
            os.rename(os.path.join(STATE, name), os.path.join(STATE, f"{name}.rolled-back-{datetime.datetime.now():%Y%m%d%H%M%S}"))
        say(f"{name}: rolled back")


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    action = parser.add_mutually_exclusive_group()
    action.add_argument("--apply", action="store_true")
    action.add_argument("--rollback", action="store_true")
    parser.add_argument("accounts", nargs="+")
    args = parser.parse_args()
    if os.geteuid() != 0:
        sys.exit("ghq-shared-migrate must run as root")
    writer = {"uid": pwd.getpwnam(WRITER).pw_uid, "gid": grp.getgrnam(WRITER).gr_gid}
    if args.rollback:
        rollback(args.accounts, writer)
        return
    date = datetime.date.today().strftime("%Y%m%d")
    accounts = [account_info(name) for name in args.accounts]
    entries, winners = plan(accounts, date)
    report(entries, winners)
    if not args.apply:
        say("dry run: nothing changed; rerun with --apply")
        return
    apply(entries, winners, writer, date)


if __name__ == "__main__":
    main()
