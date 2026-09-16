from __future__ import annotations

import fcntl
import json
import os
import pwd
import stat
import subprocess
import sys
import tempfile
from pathlib import Path
from typing import Any


class DeliveryError(Exception):
    pass


def require(condition: bool) -> None:
    if not condition:
        raise DeliveryError("worker credential delivery is not ready")


def boot_id() -> str:
    if sys.platform == "darwin":
        return subprocess.check_output(
            ["/usr/sbin/sysctl", "-n", "kern.bootsessionuuid"], text=True
        ).strip()
    return Path("/proc/sys/kernel/random/boot_id").read_text().strip()


def stamp(path: str, uid: int) -> list[int]:
    info = os.stat(path)
    require(stat.S_ISREG(info.st_mode) and info.st_uid == uid)
    require(stat.S_IMODE(info.st_mode) == 0o400 and info.st_size > 0)
    return [info.st_dev, info.st_ino, info.st_size, info.st_mtime_ns]


def trusted_directory(directory: Path, create: bool) -> None:
    if create:
        previous_mask = os.umask(0o022)
        try:
            directory.mkdir(mode=0o755, exist_ok=True)
        finally:
            os.umask(previous_mask)
    info = directory.lstat()
    require(
        stat.S_ISDIR(info.st_mode)
        and info.st_uid == 0
        and stat.S_IMODE(info.st_mode) == 0o755
    )


def lock(directory: Path) -> int:
    trusted_directory(directory, True)
    descriptor = os.open(
        directory / "lock", os.O_RDWR | os.O_CREAT | os.O_NOFOLLOW, 0o600
    )
    info = os.fstat(descriptor)
    require(
        info.st_uid == 0
        and stat.S_ISREG(info.st_mode)
        and stat.S_IMODE(info.st_mode) == 0o600
    )
    fcntl.flock(descriptor, fcntl.LOCK_EX)
    return descriptor


def install(
    directory: Path, declaration: dict[str, Any], executable: str, arguments: list[str]
) -> int:
    if any(argument.startswith("-check-mode=") for argument in arguments):
        return subprocess.run([executable, *arguments], check=False).returncode
    require(os.getuid() == 0)
    descriptor = lock(directory)
    receipt = directory / "ready.json"
    try:
        if "-ignore-passwd" in arguments:
            return subprocess.run([executable, *arguments], check=False).returncode
        receipt.unlink(missing_ok=True)
        result = subprocess.run([executable, *arguments], check=False)
        if result.returncode != 0:
            return result.returncode
        require(len(arguments) == 1 and arguments[0].startswith("/nix/store/"))
        files = {}
        for worker in declaration["workers"]:
            uid = pwd.getpwnam(worker["user"]).pw_uid
            for path in worker["files"]:
                files[path] = stamp(path, uid)
        record = {"manifest": arguments[0], "boot": boot_id(), "files": files}
        fd, temporary = tempfile.mkstemp(dir=directory, prefix=".ready-")
        try:
            with os.fdopen(fd, "w") as stream:
                json.dump(record, stream)
                stream.flush()
                os.fchmod(stream.fileno(), 0o444)
                os.fsync(stream.fileno())
            os.replace(temporary, receipt)
        finally:
            Path(temporary).unlink(missing_ok=True)
        return 0
    finally:
        os.close(descriptor)


def ready(directory: Path, manifest: str, policy: dict[str, Any]) -> None:
    trusted_directory(directory, False)
    receipt = directory / "ready.json"
    info = receipt.lstat()
    require(
        stat.S_ISREG(info.st_mode)
        and info.st_uid == 0
        and stat.S_IMODE(info.st_mode) == 0o444
    )
    snapshot = receipt.read_bytes()
    record = json.loads(snapshot)
    require(record["manifest"] == manifest and record["boot"] == boot_id())
    for path in policy["requiredFiles"]:
        require(record["files"].get(path) == stamp(path, os.getuid()))
        require(os.access(path, os.R_OK))
    require(receipt.read_bytes() == snapshot)


def main() -> None:
    try:
        mode, state, declaration, executable, *arguments = sys.argv[1:]
        document = json.loads(Path(declaration).read_text())
        if mode == "install":
            raise SystemExit(install(Path(state), document, executable, arguments))
        require(mode == "ready")
        ready(Path(state), executable, document)
    except (DeliveryError, OSError, ValueError, KeyError, TypeError):
        print("worker credential delivery is not ready", file=sys.stderr)
        raise SystemExit(1) from None


if __name__ == "__main__":
    main()
