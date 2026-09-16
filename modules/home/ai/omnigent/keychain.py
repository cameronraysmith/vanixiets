from __future__ import annotations

import fcntl
import json
import os
import pwd
import shlex
import stat
import subprocess
import sys
from pathlib import Path


class KeychainError(Exception):
    pass


def require(condition: bool) -> None:
    if not condition:
        raise KeychainError("worker Keychain preparation failed")


def owned(path: Path, directory: bool = False) -> None:
    info = path.lstat()
    require(info.st_uid == os.getuid())
    require(stat.S_ISDIR(info.st_mode) if directory else stat.S_ISREG(info.st_mode))
    require(stat.S_IMODE(info.st_mode) & 0o077 == 0)


def security(arguments: list[str], secret: bool = False) -> str:
    # One command per stdin invocation preserves security(1)'s failure status.
    result = subprocess.run(
        ["/usr/bin/security", "-i"] if secret else ["/usr/bin/security", *arguments],
        input=shlex.join(arguments) + "\n" if secret else None,
        text=True,
        stdout=subprocess.DEVNULL if secret else subprocess.PIPE,
        stderr=subprocess.DEVNULL,
        timeout=30,
        check=False,
    )
    require(result.returncode == 0)
    return result.stdout or ""


def prepare(policy: dict[str, str]) -> None:
    account = pwd.getpwnam(policy["user"])
    home = Path(policy["home"])
    require(os.getuid() != 0 and os.getuid() == account.pw_uid)
    require(str(home) == account.pw_dir)
    owned(home, True)
    password_file = Path(policy["passwordFile"])
    # SOPS paths can traverse its generation symlink; the file itself must be regular.
    info = password_file.stat()
    require(stat.S_ISREG(info.st_mode) and info.st_uid == os.getuid())
    require(stat.S_IMODE(info.st_mode) == 0o400)
    password = password_file.read_text().strip()
    require(len(password) == 64 and all(c in "0123456789abcdef" for c in password))
    directory = home / "Library/Keychains"
    for path in [home / "Library", directory]:
        if not path.exists() and not path.is_symlink():
            path.mkdir(mode=0o700)
        info = path.lstat()
        require(stat.S_ISDIR(info.st_mode) and info.st_uid == os.getuid())
        require(stat.S_IMODE(info.st_mode) & 0o022 == 0)
    lock = directory / ".omnigent.lock"
    descriptor = os.open(lock, os.O_CREAT | os.O_RDWR | os.O_NOFOLLOW, 0o600)
    try:
        owned(lock)
        fcntl.flock(descriptor, fcntl.LOCK_EX)
        keychain = directory / "omnigent.keychain-db"
        if keychain.exists() or keychain.is_symlink():
            owned(keychain)
        else:
            previous_mask = os.umask(0o077)
            try:
                security(
                    ["create-keychain", "-p", password, str(keychain)], secret=True
                )
            finally:
                os.umask(previous_mask)
            owned(keychain)
        security(["unlock-keychain", "-p", password, str(keychain)], secret=True)
        security(["show-keychain-info", str(keychain)])
        # The unattended worker cannot answer a sleep/timeout unlock prompt.
        security(["set-keychain-settings", str(keychain)])
        paths = shlex.split(security(["list-keychains", "-d", "user"]))
        if str(keychain) not in paths:
            security(["list-keychains", "-d", "user", "-s", *paths, str(keychain)])
        security(["default-keychain", "-d", "user", "-s", str(keychain)])
    finally:
        os.close(descriptor)


def main() -> None:
    try:
        prepare(json.loads(Path(sys.argv[1]).read_text()))
    except (KeychainError, OSError, ValueError, KeyError, subprocess.SubprocessError):
        print(
            "worker Keychain preparation failed; existing credentials preserved",
            file=sys.stderr,
        )
        raise SystemExit(1) from None


if __name__ == "__main__":
    main()
