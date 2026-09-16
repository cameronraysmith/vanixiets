from __future__ import annotations

import importlib.util
import os
import pathlib
import subprocess
import sys
from types import SimpleNamespace
from unittest.mock import patch


def exercise(source, root):
    spec = importlib.util.spec_from_file_location("keychain", source)
    helper = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(helper)
    home = root / "home"
    home.mkdir(mode=0o700)
    password = root / "password"
    password.write_text("a" * 64)
    password.chmod(0o400)
    policy = {"user": "fixture", "home": str(home), "passwordFile": str(password)}
    keychain = home / "Library/Keychains/omnigent.keychain-db"
    calls = []

    def security(command, **kwargs):
        import shlex

        assert "a" * 64 not in " ".join(command)
        calls.append((command, kwargs))
        if command[-1] == "-i":
            assert kwargs["stdout"] == subprocess.DEVNULL
            assert kwargs["stderr"] == subprocess.DEVNULL
            assert kwargs["input"].count("\n") == 1
            arguments = shlex.split(kwargs["input"])
            if arguments[0] == "create-keychain":
                previous_mask = os.umask(0o077)
                os.umask(previous_mask)
                assert previous_mask == 0o077
                keychain.write_text("preserved OAuth fixture")
                assert keychain.stat().st_mode & 0o777 == 0o600
        return subprocess.CompletedProcess(command, 0, '"/unrelated.keychain-db"\n')

    with (
        patch.object(
            helper.pwd,
            "getpwnam",
            return_value=SimpleNamespace(pw_uid=os.getuid(), pw_dir=str(home)),
        ),
        patch.object(helper.subprocess, "run", side_effect=security),
    ):
        helper.prepare(policy)
        original = keychain.read_bytes()
        helper.prepare(policy)
        assert keychain.read_bytes() == original
        assert sum("create-keychain" in (c[1].get("input") or "") for c in calls) == 1
        assert any("/unrelated.keychain-db" in c[0] for c in calls)
        for overrides in [
            {"pw_uid": os.getuid() + 1, "pw_dir": str(home)},
            {"pw_uid": os.getuid(), "pw_dir": "/different-home"},
        ]:
            with patch.object(
                helper.pwd, "getpwnam", return_value=SimpleNamespace(**overrides)
            ):
                before = len(calls)
                try:
                    helper.prepare(policy)
                except helper.KeychainError:
                    pass
                else:
                    raise AssertionError("wrong user/home accepted")
                assert len(calls) == before
        password.chmod(0o644)
        try:
            helper.prepare(policy)
        except helper.KeychainError:
            pass
        else:
            raise AssertionError("public password file accepted")
        password.chmod(0o400)
        with patch.object(
            helper.subprocess, "run", return_value=subprocess.CompletedProcess([], 51)
        ) as failed:
            try:
                helper.prepare(policy)
            except helper.KeychainError:
                pass
            else:
                raise AssertionError("unlock failure accepted")
            assert failed.call_count == 1
            assert failed.call_args.kwargs["input"].startswith("unlock-keychain ")
        assert keychain.read_bytes() == original
        keychain.unlink()
        keychain.symlink_to(password)
        try:
            helper.prepare(policy)
        except helper.KeychainError:
            pass
        else:
            raise AssertionError("symlink accepted")
    print(
        "keychain fixtures passed: repeat preservation, secret stdin, search list preservation, unlock failure, symlink"
    )


if __name__ == "__main__":
    exercise(sys.argv[1], pathlib.Path(sys.argv[2]))
