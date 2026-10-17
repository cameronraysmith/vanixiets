"""ACL and group-write detection, and the writer stop, in ghq-shared-migrate.

The plan refuses an administrator's tree in which any entry carries an ACL;
this checks the probe it relies on. On darwin an ACL is planted on a directory,
a file with a space in its name and a symlink, and each must be listed while
plain entries and a symlink's target are not. The Linux build sandbox has no
POSIX ACLs, so there it checks that their absence is reported as none; the NixOS
VM test covers a Linux ACL being refused.

On darwin, `everyone` (gid 12), a group whose members appear in no `gr_mem`
list and whose gid is no account's primary group, must resolve to many members,
so that an entry group-writable for it is refused.

The writer stop is checked with subprocess stubbed: a stop that leaves the
socket or the launchd job running must refuse and start the writer again, and a
restart that fails must say so.

Usage: python3 test_acl.py MIGRATE
"""

import contextlib
import importlib.machinery
import io
import types
import importlib.util
import os
import subprocess
import sys
import tempfile

loader = importlib.machinery.SourceFileLoader("migrate", sys.argv[1])
spec = importlib.util.spec_from_loader("migrate", loader)
m = importlib.util.module_from_spec(spec)
loader.exec_module(m)

with tempfile.TemporaryDirectory() as scratch:
    tree = os.path.join(scratch, "ghq")
    os.makedirs(os.path.join(tree, "repo", ".git"))
    plain = os.path.join(tree, "repo", "plain")
    spaced = os.path.join(tree, "repo", "with space")
    for path in (plain, spaced):
        open(path, "w").close()
    link = os.path.join(tree, "repo", "link")
    os.symlink("plain", link)
    found = m.acl_entries(tree)
    if found:
        sys.exit(f"entries without an ACL were listed: {found}")
    if not m.DARWIN:
        if subprocess.run(["setfacl", "-m", "u:65534:rwx", spaced], capture_output=True).returncode == 0:
            sys.exit("this filesystem supports POSIX ACLs; extend the test to plant and detect one")
        print("ghq-shared-migrate: no POSIX ACLs on this filesystem, and none reported")
    else:
        gitdir = os.path.join(tree, "repo", ".git")
        subprocess.run(["/bin/chmod", "+a", "everyone allow add_file,file_inherit,directory_inherit", gitdir], check=True)
        subprocess.run(["/bin/chmod", "+a", "everyone allow write", spaced], check=True)
        subprocess.run(["/bin/chmod", "-h", "+a", "everyone allow delete", link], check=True)
        found = m.acl_entries(tree)
        want = sorted([gitdir, spaced, link])
        if found != want:
            sys.exit(f"ACL probe listed {found}, expected {want}")
        print("ghq-shared-migrate: entries carrying an ACL are listed, and only those")

        # A build user cannot give a file to `everyone`, so the membership the check relies on is tested directly.
        members = m.group_members(12) or set()
        if len(members) < 2:
            sys.exit(f"the members of everyone (gid 12) were undercounted: {sorted(members)}")
        print(f"ghq-shared-migrate: everyone (gid 12) resolves to {len(members)} accounts, nested membership included")

class Stub:
    """subprocess, with each writer command answered by the next exit code its script gives (the last repeats)."""

    DEVNULL = subprocess.DEVNULL

    def __init__(self, answers):
        self.answers, self.calls = {key: list(codes) for key, codes in answers.items()}, []

    def run(self, argv, **_):
        self.calls.append(argv)
        for key, codes in self.answers.items():
            if key in argv:
                code = codes.pop(0) if len(codes) > 1 else codes[0]
                return types.SimpleNamespace(returncode=code, stdout="", stderr="stubbed failure")
        return types.SimpleNamespace(returncode=0, stdout="", stderr="")


def stopping(darwin, answers):
    stub, saved = Stub(answers), (m.DARWIN, m.subprocess, m.writer_pids)
    m.DARWIN, m.subprocess, m.writer_pids = darwin, stub, lambda uid: []
    stopper, err, outcome = m.WriterStopped({"uid": 1}), io.StringIO(), "entered"
    stopper.systemctl = sys.executable
    try:
        with contextlib.redirect_stderr(err):
            try:
                with stopper:
                    pass
            except SystemExit as error:
                outcome = str(error)
    finally:
        m.DARWIN, m.subprocess, m.writer_pids = saved
    return outcome, stub.calls, err.getvalue()


# A socket still active after the stop (Linux), or a job still loaded after bootout (darwin).
for darwin, answers, restart in [(False, {"is-active": [0], "stop": [1]}, "start"),
                                 (True, {"print": [0], "bootout": [1]}, "bootstrap")]:
    outcome, calls, _ = stopping(darwin, answers)
    if "could not be stopped" not in outcome or not any(restart in call for call in calls):
        sys.exit(f"a writer that kept running was not refused and restarted ({'darwin' if darwin else 'linux'}): {outcome} {calls}")
# A writer that stops, then fails to start again, is reported as not started.
for darwin, answers in [(False, {"is-active": [0, 3], "start": [1]}), (True, {"print": [0, 113], "bootstrap": [5]})]:
    outcome, calls, err = stopping(darwin, answers)
    if outcome != "entered" or "failed to start the writer again" not in err or "writer started again" in err:
        sys.exit(f"a failed restart was not reported ({'darwin' if darwin else 'linux'}): {outcome} {err!r}")
print("ghq-shared-migrate: a writer that will not stop is refused and restarted, and a failed restart is reported")
