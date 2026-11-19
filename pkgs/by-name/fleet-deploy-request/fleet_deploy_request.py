"""fleet-deploy-request: the deployer's forced command (design D1-D12).

sshd runs `fleet-deploy-request <requester>` for every connection to the
deployer account, with the requested command in SSH_ORIGINAL_COMMAND:

    deploy <machine> [<commit>] [--session <id>]

Every request ends in exactly one exit status, recorded in requests.jsonl and
posted to the fleet-deploy topic by fleet-deploy-notify on the deployer host:

    0 deployed   3 refused   4 busy   5 unreachable
    6 failed     7 unhealthy 8 rolled-back

The configuration (FLEET_DEPLOY_CONFIG, JSON) is rendered from
flake.lib.fleetDeployer.requestConfig. Four steps can be replaced by commands
named in it, which the VM test uses in place of the forge's flake, the binary
cache and clan: resolveCommand, cacheCheckCommand, varsCheckCommand and
deployCommand.
"""

from __future__ import annotations

import fcntl
import json
import os
import re
import shlex
import subprocess
import sys
import tempfile
import time
import uuid
from pathlib import Path

STATUS = {
    "deployed": 0,
    "refused": 3,
    "busy": 4,
    "unreachable": 5,
    "failed": 6,
    "unhealthy": 7,
    "rolled-back": 8,
}

COMMIT = re.compile(r"[0-9a-f]{7,40}")
SESSION = re.compile(r"[A-Za-z0-9._-]{1,64}")
NAME = re.compile(r"[a-z][a-z0-9-]{0,62}")


class Outcome(Exception):
    def __init__(self, outcome: str, reason: str):
        super().__init__(reason)
        self.outcome = outcome
        self.reason = reason


def parse(command: str, requester: str, config: dict) -> dict:
    """Parse and authorize one request; raise Outcome('refused') otherwise."""
    words = command.split(" ") if command else []
    if any(w == "" for w in words) or len(command) > 200:
        raise Outcome("refused", "malformed command")
    if not words or words[0] != "deploy":
        raise Outcome("refused", "the only command is: deploy <machine> [<commit>] [--session <id>]")
    rest = words[1:]
    session = None
    if "--session" in rest:
        i = rest.index("--session")
        if i + 2 != len(rest) or not SESSION.fullmatch(rest[i + 1]):
            raise Outcome("refused", "--session takes one id of at most 64 [A-Za-z0-9._-]")
        session = rest[i + 1]
        rest = rest[:i]
    if not 1 <= len(rest) <= 2:
        raise Outcome("refused", "expected: deploy <machine> [<commit>]")
    machine = rest[0]
    commit = rest[1] if len(rest) == 2 else None
    if not NAME.fullmatch(machine) or machine not in config["targets"]:
        raise Outcome("refused", f"{machine!r} is not a deploy target")
    if commit is not None and not COMMIT.fullmatch(commit):
        raise Outcome("refused", "a commit is 7-40 lowercase hexadecimal digits")
    if machine not in config["requesters"].get(requester, []):
        raise Outcome("refused", f"{requester} may not deploy {machine}")
    return {"machine": machine, "commit": commit, "session": session}


def say(message: str) -> None:
    print(f"fleet-deploy: {message}", flush=True)


def run(argv: list[str], **kwargs) -> subprocess.CompletedProcess:
    return subprocess.run(argv, **kwargs)


def output(argv: list[str], **kwargs) -> str:
    return subprocess.run(argv, check=True, capture_output=True, text=True, **kwargs).stdout.strip()


class Deployer:
    def __init__(self, config: dict, requester: str):
        self.config = config
        self.requester = requester
        self.state = Path(config["stateDir"])
        self.run_dir = Path(config["runDir"])
        self.ssh_key = self.state / "keys" / "id_ed25519"
        self.age_key = self.state / "keys" / "age.key"
        self.mirror = self.state / "mirror.git"
        self.id = uuid.uuid4().hex[:12]

    # -- records ---------------------------------------------------------
    def record(self, entry: dict) -> None:
        path = self.state / "requests.jsonl"
        fd = os.open(path, os.O_WRONLY | os.O_APPEND | os.O_CREAT, 0o600)
        with os.fdopen(fd, "a") as f:
            fcntl.flock(f, fcntl.LOCK_EX)
            f.write(json.dumps(entry, sort_keys=True) + "\n")

    # -- ssh to a target ---------------------------------------------------
    def ssh(self, target: str, command: str, timeout: int | None = None, **kwargs):
        argv = [
            "ssh",
            "-i", str(self.ssh_key),
            "-o", "IdentitiesOnly=yes",
            "-o", "BatchMode=yes",
            "-o", f"ConnectTimeout={self.config['probeTimeout']}",
            "-o", "ForwardAgent=no",
            target,
            command,
        ]
        return run(argv, timeout=timeout, **kwargs)

    def reachable(self, target: str) -> bool:
        try:
            return self.ssh(target, "true", timeout=self.config["probeTimeout"] + 5,
                            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode == 0
        except subprocess.TimeoutExpired:
            return False

    def root(self, machine: str, command: str) -> str:
        return command if self.config["targets"][machine]["deployUser"] == "root" else f"sudo {command}"

    # -- the commit gate ---------------------------------------------------
    def fetch(self) -> str:
        if not (self.mirror / "HEAD").exists():
            run(["git", "init", "--quiet", "--bare", str(self.mirror)], check=True)
        run(["git", "-C", str(self.mirror), "fetch", "--quiet", "--no-tags", self.config["forge"],
             "+refs/heads/main:refs/heads/main"], check=True)
        return output(["git", "-C", str(self.mirror), "rev-parse", "refs/heads/main"])

    def gate(self, commit: str | None) -> str:
        head = self.fetch()
        if commit is None:
            return head
        try:
            full = output(["git", "-C", str(self.mirror), "rev-parse", "--verify", "--quiet",
                           f"{commit}^{{commit}}"])
        except subprocess.CalledProcessError:
            raise Outcome("refused", f"{commit} is not a commit of main")
        if run(["git", "-C", str(self.mirror), "merge-base", "--is-ancestor", full, head]).returncode != 0:
            raise Outcome("refused", f"{commit} is not merged into main")
        return full

    # -- locks -------------------------------------------------------------
    def lock(self, path: Path, wait: int):
        path.parent.mkdir(parents=True, exist_ok=True)
        f = open(path, "a")
        deadline = time.monotonic() + wait
        while True:
            try:
                fcntl.flock(f, fcntl.LOCK_EX | fcntl.LOCK_NB)
                return f
            except BlockingIOError:
                if time.monotonic() >= deadline:
                    f.close()
                    return None
                time.sleep(1)

    def slot(self, wait: int):
        deadline = time.monotonic() + wait
        while True:
            for n in range(self.config["slots"]):
                f = self.lock(self.run_dir / "slot" / str(n), 0)
                if f is not None:
                    return f
            if time.monotonic() >= deadline:
                return None
            time.sleep(1)

    # -- resolution, vars check, deploy ------------------------------------
    def resolve(self, tree: str, machine: str) -> dict:
        custom = self.config.get("resolveCommand")
        if custom:
            return json.loads(output([custom, tree, machine]))
        cls = self.config["targets"][machine]["class"]
        flake = f"path:{tree}"
        if cls == "nixos":
            closure = output(["nix", "eval", "--raw",
                              f"{flake}#nixosConfigurations.{machine}.config.system.build.toplevel.outPath"])
            target = output(["nix", "eval", "--raw",
                             f"{flake}#clan.inventory.machines.{machine}.deploy.targetHost"])
        else:
            closure = output(["nix", "eval", "--raw", f"{flake}#darwinConfigurations.{machine}.system.outPath"])
            target = output(["nix", "eval", "--raw",
                             f"{flake}#darwinConfigurations.{machine}.config.clan.core.networking.targetHost"])
        return {"closure": closure, "targetHost": target}

    def cached(self, closure: str) -> bool:
        custom = self.config.get("cacheCheckCommand")
        argv = [custom, closure] if custom else ["nix", "path-info", "--store", self.config["cacheStore"], closure]
        return run(argv, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode == 0

    def vars_check(self, tree: str) -> None:
        custom = self.config.get("varsCheckCommand")
        for machine in self.config["machines"]:
            argv = [custom, tree, machine] if custom else ["clan", "vars", "check", "--flake", tree, machine]
            if run(argv, env=self.env()).returncode != 0:
                raise Outcome("refused", f"clan vars check failed for {machine}; nothing is generated here")

    def env(self) -> dict:
        # os.environ is already private_environment's; clan also gets the key.
        env = dict(os.environ)
        env["SOPS_AGE_KEY_FILE"] = str(self.age_key)
        env["CLAN_NO_COMMIT"] = "1"
        return env

    def deploy(self, tree: str, machine: str, target: str, closure: str) -> bool:
        custom = self.config.get("deployCommand")
        argv = ([custom, tree, machine, target, closure] if custom else
                ["clan", "machines", "update", "--flake", tree, machine, "--target-host", target])
        return run(argv, env=self.env()).returncode == 0

    # -- rollback watcher (D10) --------------------------------------------
    def arm(self, machine: str, target: str) -> None:
        c = self.config
        cls = c["targets"][machine]["class"]
        watch = "/run/current-system/sw/bin/fleet-deploy-watch"
        args = f"{self.id} {c['activationWait']} {c['confirmWindow']}"
        if cls == "nixos":
            command = (f"systemctl stop 'fleet-deploy-watch-*' ; "
                       f"systemd-run --quiet --collect --unit fleet-deploy-watch-{self.id} {watch} {args}")
        else:
            command = (f"{watch} --stop-stale ; "
                       f"launchctl submit -l org.vanixiets.fleet-deploy-watch.{self.id} -- {watch} {args}")
            command = f"sudo sh -c {shlex.quote(command)}"
        if self.ssh(target, command).returncode != 0:
            raise Outcome("failed", "could not arm the rollback watcher on the target")

    def disarm(self, machine: str, target: str) -> None:
        cls = self.config["targets"][machine]["class"]
        command = (f"systemctl stop fleet-deploy-watch-{self.id}" if cls == "nixos"
                   else f"launchctl remove org.vanixiets.fleet-deploy-watch.{self.id}")
        self.ssh(target, self.root(machine, command), stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

    def confirm(self, machine: str, target: str) -> bool:
        cls = self.config["targets"][machine]["class"]
        directory = "/run/fleet-deploy" if cls == "nixos" else "/var/run/fleet-deploy"
        command = self.root(machine, f"touch {directory}/{self.id}.confirmed")
        return self.ssh(target, command).returncode == 0

    # -- health (D11) --------------------------------------------------------
    def health(self, machine: str, target: str, closure: str) -> list[str]:
        problems = []
        cls = self.config["targets"][machine]["class"]
        last = self.ssh(target, "tail -n 1 /var/log/deploy-record.jsonl", capture_output=True, text=True)
        try:
            if json.loads(last.stdout)["closure"] != closure:
                problems.append("the newest deploy record names another closure")
        except (ValueError, KeyError, TypeError):
            problems.append("no readable deploy record")
        if cls == "nixos":
            failed = self.ssh(target, "systemctl --failed --no-legend --plain", capture_output=True, text=True)
            units = [line.split()[0] for line in failed.stdout.splitlines() if line.strip()]
            problems += [f"failed unit {u}" for u in units]
        else:
            jobs = self.ssh(target, "sudo launchctl list", capture_output=True, text=True)
            for line in jobs.stdout.splitlines()[1:]:
                parts = line.split()
                if len(parts) == 3 and parts[2].startswith("org.nixos.") and parts[1] not in ("0", "-"):
                    problems.append(f"launchd job {parts[2]} last exited {parts[1]}")
        return problems

    # -- the request ---------------------------------------------------------
    def handle(self, request: dict) -> tuple[str, str, dict]:
        machine = request["machine"]
        extra: dict = {}
        commit = self.gate(request["commit"])
        extra["commit"] = commit
        say(f"{machine} at {commit}")

        tree = tempfile.mkdtemp(prefix="deploy-", dir=self.state / "trees")
        run(["git", "-C", str(self.mirror), "worktree", "add", "--quiet", "--detach", tree, commit], check=True)
        try:
            # Evaluation and the deploy each hold one of the slots, which bound
            # cinnabar's memory; the target is probed before its lock is taken.
            slot = self.slot(self.config["lockWait"])
            if slot is None:
                raise Outcome("busy", "every deploy slot stayed taken")
            resolved = self.resolve(tree, machine)
            closure, target = resolved["closure"], resolved["targetHost"]
            extra["closure"] = closure
            say(f"closure {closure}, target {target}")
            if self.config["targets"][machine]["class"] == "nixos" and not self.cached(closure):
                raise Outcome("refused", f"{closure} is not in {self.config['cacheStore']}: CI has not built it")
            self.vars_check(tree)
            slot.close()
            if not self.reachable(target):
                raise Outcome("unreachable", f"{target} did not answer within {self.config['probeTimeout']} s")
            host_lock = self.lock(self.run_dir / "lock" / machine, self.config["lockWait"])
            if host_lock is None:
                raise Outcome("busy", f"another deploy of {machine} held the lock for {self.config['lockWait']} s")
            slot = self.slot(self.config["lockWait"])
            if slot is None:
                raise Outcome("busy", "every deploy slot stayed taken")
            self.arm(machine, target)
            if not self.deploy(tree, machine, target, closure):
                self.disarm(machine, target)
                raise Outcome("failed", "the deploy command failed")
            slot.close()
            say(f"activated; settling {self.config['settle']} s")
            time.sleep(self.config["settle"])
            if not (self.reachable(target) and self.confirm(machine, target)):
                say("the target does not answer; its watcher rolls it back")
                time.sleep(self.config["confirmWindow"] + 30)
                raise Outcome("rolled-back", f"{target} stopped answering after activation")
            problems = self.health(machine, target, closure)
            if problems:
                raise Outcome("unhealthy", "; ".join(problems))
            return "deployed", f"{machine} runs {closure}", extra
        finally:
            run(["git", "-C", str(self.mirror), "worktree", "remove", "--force", tree],
                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

    def main(self, command: str) -> int:
        (self.state / "trees").mkdir(parents=True, exist_ok=True)
        entry = {
            "ts": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
            "id": self.id,
            "requester": self.requester,
            "command": command[:200],
            "session": None,
            "machine": None,
            "commit": None,
            "closure": None,
        }
        try:
            request = parse(command, self.requester, self.config)
            entry.update(machine=request["machine"], session=request["session"], commit=request["commit"])
            outcome, reason, extra = self.handle(request)
            entry.update(extra)
        except Outcome as o:
            outcome, reason = o.outcome, o.reason
        except Exception as e:  # noqa: BLE001 - every request ends in one recorded status
            outcome, reason = "failed", f"{type(e).__name__}: {e}"
        entry.update(outcome=outcome, reason=reason, finished=time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()))
        self.record(entry)
        say(f"{outcome}: {reason}")
        return STATUS[outcome]


def private_environment(state: Path) -> None:
    """Replace the inherited environment with the account's own.

    sshd, runuser or su can hand this account another user's runtime
    directory, no HOME or an unwritable TMPDIR, and clan and nix write their
    caches there (clan's under XDG_RUNTIME_DIR). Every subprocess inherits
    os.environ, so it is rebuilt once, before any of them runs: only PATH and
    FLEET_DEPLOY_CONFIG (both set by the wrapper) survive, and HOME,
    XDG_RUNTIME_DIR, XDG_CACHE_HOME and TMPDIR point into the state
    directory, the two directories created 0700.
    """
    keep = {k: os.environ[k] for k in ("PATH", "FLEET_DEPLOY_CONFIG") if k in os.environ}
    runtime, tmp = state / "runtime", state / "tmp"
    for directory in (runtime, tmp):
        directory.mkdir(mode=0o700, exist_ok=True)
        directory.chmod(0o700)
    os.environ.clear()
    os.environ.update(keep)
    os.environ.update(
        HOME=str(state),
        XDG_RUNTIME_DIR=str(runtime),
        XDG_CACHE_HOME=str(state / ".cache"),
        TMPDIR=str(tmp),
    )


def main() -> int:
    config = json.loads(Path(os.environ["FLEET_DEPLOY_CONFIG"]).read_text())
    command = os.environ.get("SSH_ORIGINAL_COMMAND", "")
    if len(sys.argv) == 3 and sys.argv[1] == "--parse":
        # The fixture check: parse SSH_ORIGINAL_COMMAND for one requester.
        try:
            print(json.dumps(parse(command, sys.argv[2], config)))
            return 0
        except Outcome as o:
            print(o.reason)
            return STATUS[o.outcome]
    if len(sys.argv) != 2 or not NAME.fullmatch(sys.argv[1]):
        print("usage: fleet-deploy-request <requester>", file=sys.stderr)
        return STATUS["refused"]
    private_environment(Path(config["stateDir"]))
    return Deployer(config, sys.argv[1]).main(command)


if __name__ == "__main__":
    sys.exit(main())
