#!/usr/bin/env python3
"""Observe worker identity and executable access without reading credential files."""
import argparse
import contextlib
import grp
import json
import os
import pathlib
import plistlib
import pwd
import subprocess
import tempfile


def run(argv):
    return subprocess.run(argv, text=True, capture_output=True, check=False)


def account(user):
    try:
        entry = pwd.getpwnam(user)
    except KeyError:
        return None
    return {"uid": entry.pw_uid, "gid": entry.pw_gid, "home": entry.pw_dir}


def as_user(user, environment, argv):
    command = ["env", "-i", *(f"{key}={value}" for key, value in environment.items()), *argv]
    if os.uname().sysname == "Darwin":
        return run(["sudo", "-n", "-u", user, "--", *command])
    return run(["runuser", "-u", user, "--", *command])


def observe(host, workers, running):
    result = {}
    for name, worker in workers.items():
        user, home = worker["user"], worker["home"]
        entry = account(user)
        row = {"account": entry, "configuredHome": home}
        result[name] = row
        if entry is None:
            continue
        groups = [grp.getgrgid(gid).gr_name for gid in os.getgrouplist(user, entry["gid"])]
        row["groups"] = groups
        row["homePrivate"] = pathlib.Path(home).is_dir() and (os.stat(home).st_mode & 0o077) == 0 and os.stat(home).st_uid == entry["uid"]
        row["nonAdmin"] = entry["uid"] != 0 and not set(groups).intersection({"wheel", "admin", "docker", "disk", "kvm"})
        if not running:
            continue
        if host == "stibnite":
            label = f"org.nixos.omnigent-host-{name}"
            job = run(["launchctl", "print", f"system/{label}"])
            row["active"] = job.returncode == 0 and "state = running" in job.stdout
            path = pathlib.Path("/Library/LaunchDaemons") / f"{label}.plist"
            with path.open("rb") as handle:
                plist = plistlib.load(handle)
            row["configuredUser"] = plist.get("UserName")
            environment = plist.get("EnvironmentVariables", {})
            pid = next((line.strip().split(" = ", 1)[1] for line in job.stdout.splitlines() if line.strip().startswith("pid = ")), "")
            actual_uid = run(["ps", "-o", "uid=", "-p", pid]) if pid.isdigit() else None
            row["actualUid"] = int(actual_uid.stdout.strip()) if actual_uid and actual_uid.returncode == 0 and actual_uid.stdout.strip().isdigit() else None
        else:
            unit = f"omnigent-host-{name}.service"
            row["active"] = run(["systemctl", "is-active", "--quiet", unit]).returncode == 0
            pid = run(["systemctl", "show", unit, "-p", "MainPID", "--value"]).stdout.strip()
            row["configuredUser"] = run(["systemctl", "show", unit, "-p", "User", "--value"]).stdout.strip()
            environment = {}
            row["actualUid"] = None
            if pid.isdigit() and pid != "0":
                status = pathlib.Path(f"/proc/{pid}/status").read_text()
                row["actualUid"] = int(next(line for line in status.splitlines() if line.startswith("Uid:")).split()[2])
                # Read only selectors; never emit or persist the rest of the process environment.
                for item in pathlib.Path(f"/proc/{pid}/environ").read_bytes().split(b"\0"):
                    key, _, value = item.partition(b"=")
                    if key in (b"PATH", b"HOME", b"USER", b"LOGNAME", b"XDG_CONFIG_HOME"):
                        environment[key.decode()] = value.decode()
        environment = {key: value for key, value in environment.items() if key in ("PATH", "HOME", "USER", "LOGNAME", "XDG_CONFIG_HOME")}
        row["homeMatches"] = environment.get("HOME") == home
        row["tools"] = {}
        for tool in ("sh", "bash", "which", "python3", "git", "gh", "linear", "rg", "fd", "direnv", "nix", "atomic", "omp"):
            found = as_user(user, environment, ["/bin/sh", "-c", 'command -v "$1"', "probe", tool])
            row["tools"][tool] = found.stdout.strip() if found.returncode == 0 else None
        shell = as_user(user, environment, ["sh", "-c", "printf shell-ok"])
        row["shellWorks"] = shell.returncode == 0 and shell.stdout == "shell-ok"
        identity = as_user(user, environment, ["gh", "api", "user", "--jq", ".login"])
        row["githubLogin"] = identity.stdout.strip() if identity.returncode == 0 else None
        row["linearIdentityCommandSucceeded"] = as_user(user, environment, ["linear", "auth", "whoami"]).returncode == 0
    return result


def canaries(workers):
    checks = []
    with contextlib.ExitStack() as stack:
        for name, worker in workers.items():
            owner = account(worker["user"])
            if not owner:
                raise RuntimeError("Worker account missing")
            directory = stack.enter_context(tempfile.TemporaryDirectory(prefix=".omnigent-canary-", dir=worker["home"]))
            path = pathlib.Path(directory) / "public-test-data"
            path.write_text("This is a harmless permission-test canary.\n")
            os.chmod(directory, 0o700)
            os.chmod(path, 0o600)
            os.chown(path, owner["uid"], owner["gid"])
            os.chown(directory, owner["uid"], owner["gid"])
            for peer, other in workers.items():
                probe = as_user(other["user"], {"PATH": "/usr/bin:/bin", "HOME": other["home"]}, ["/bin/sh", "-c", 'test -r "$1"', "probe", str(path)])
                checks.append({"owner": name, "reader": peer, "readable": probe.returncode == 0, "passed": (probe.returncode == 0) == (peer == name)})
    return checks


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("mode", choices=("collision", "prepared", "running", "canaries"))
    parser.add_argument("host", choices=("magnetite", "pyrite", "stibnite"))
    parser.add_argument("workers")
    args = parser.parse_args()
    workers = json.loads(args.workers)
    if args.mode == "canaries":
        observations = canaries(workers)
        passed = all(item["passed"] for item in observations)
    else:
        observations = observe(args.host, workers, args.mode == "running")
        if args.mode == "collision":
            passed = all(row["account"] is None or row["account"]["home"] == row["configuredHome"] for row in observations.values())
        else:
            passed = all(row["account"] is not None and row["account"]["home"] == row["configuredHome"] and row["homePrivate"] and row["nonAdmin"] for row in observations.values())
            if args.mode == "running":
                passed = passed and all(row["active"] and row["configuredUser"] == workers[name]["user"] and row["actualUid"] == row["account"]["uid"] and row["homeMatches"] and row["shellWorks"] and all(row["tools"].values()) and row["githubLogin"] and row["linearIdentityCommandSucceeded"] for name, row in observations.items())
    print(json.dumps({"mode": args.mode, "host": args.host, "passed": bool(passed), "observations": observations}))
    raise SystemExit(0 if passed else 1)


if __name__ == "__main__":
    main()
