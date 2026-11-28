"""Fixtures shared by the handler's test scripts, test_handler.py, test_handler_history.py and test_handler_boundary.py.

Importing this module reads the handler's path from the command line and makes
a scratch root; each script drives ghq-writer-handler over a socket pair, as its
service would, collects failures here and ends with report.
"""

import grp
import hashlib
import json
import os
import re
import socket
import subprocess
import sys
import tempfile

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


failures = []


def put(path, text):
    with open(path, "w") as handle:
        handle.write(text)


def lfs_pointer(content):
    return f"version https://git-lfs.github.com/spec/v1\noid sha256:{hashlib.sha256(content).hexdigest()}\nsize {len(content)}\n"


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


def report(done):
    """Exit with every failure collected, or print done."""
    if failures:
        sys.exit("\n".join(failures))
    print(done)
