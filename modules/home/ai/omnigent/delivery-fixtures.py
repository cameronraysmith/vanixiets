from __future__ import annotations

import contextlib
import importlib.util
import json
import multiprocessing
import os
import pathlib
import subprocess
import sys
from types import SimpleNamespace
from unittest.mock import patch


def load(path):
    spec = importlib.util.spec_from_file_location("delivery", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def exercise(source, root):
    delivery = load(source)
    actual_uid = os.getuid()
    state = root / "receipt"
    secret = root / "delivered-static"
    declaration = {"workers": [{"user": "fixture", "files": [str(secret)]}]}
    policy = {"requiredFiles": [str(secret)]}
    manifest = "/nix/store/synthetic-manifest"
    events = []
    original_fstat = os.fstat
    original_lstat = pathlib.Path.lstat

    def root_metadata(info):
        return SimpleNamespace(st_mode=info.st_mode, st_uid=0)

    def observed_lstat(path):
        info = original_lstat(path)
        return root_metadata(info) if path == state or path.parent == state else info

    def install_material(command, check):
        events.append("installer")
        replacement = root / "next-static"
        replacement.write_bytes(b"synthetic static grant")
        replacement.chmod(0o400)
        os.replace(replacement, secret)
        return subprocess.CompletedProcess(command, 0)

    def rejected(operation):
        try:
            operation()
        except (delivery.DeliveryError, OSError):
            return
        raise AssertionError("accepted missing, stale or unsafe delivery")

    with contextlib.ExitStack() as stack:
        stack.enter_context(patch.object(delivery.os, "getuid", return_value=0))
        stack.enter_context(
            patch.object(
                delivery.os,
                "fstat",
                side_effect=lambda fd: root_metadata(original_fstat(fd)),
            )
        )
        stack.enter_context(patch.object(pathlib.Path, "lstat", observed_lstat))
        stack.enter_context(
            patch.object(
                delivery.pwd,
                "getpwnam",
                return_value=SimpleNamespace(pw_uid=actual_uid),
            )
        )
        stack.enter_context(
            patch.object(delivery, "boot_id", return_value="fixture-boot")
        )
        stack.enter_context(
            patch.object(delivery.subprocess, "run", side_effect=install_material)
        )

        def start():
            with patch.object(delivery.os, "getuid", return_value=actual_uid):
                delivery.ready(state, manifest, policy)
            events.append("host")

        rejected(start)
        assert "host" not in events
        assert (
            delivery.install(state, declaration, "/synthetic-installer", [manifest])
            == 0
        )
        start()
        assert events == ["installer", "host"]
        with patch.object(pathlib.Path, "exists", return_value=False):
            delivery.trusted_directory(state, True)
        assert state.stat().st_mode & 0o777 == 0o755
        assert (state / "lock").stat().st_mode & 0o777 == 0o600
        receipt = json.loads((state / "ready.json").read_text())
        assert receipt["manifest"] == manifest and receipt["boot"] == "fixture-boot"
        assert "synthetic static grant" not in json.dumps(receipt)
        rejected(lambda: delivery.ready(state, "/nix/store/other-manifest", policy))
        with patch.object(delivery, "boot_id", return_value="after-reboot"):
            rejected(start)
        with patch.object(
            delivery.subprocess, "run", return_value=subprocess.CompletedProcess([], 1)
        ):
            assert (
                delivery.install(state, declaration, "/synthetic-installer", [manifest])
                == 1
            )
        assert not (state / "ready.json").exists()
        rejected(start)
        assert (
            delivery.install(state, declaration, "/synthetic-installer", [manifest])
            == 0
        )
        secret.chmod(0o600)
        secret.write_bytes(b"partial replacement")
        secret.chmod(0o400)
        rejected(start)
        secret.unlink()
        rejected(start)
        with patch.object(
            delivery.subprocess, "run", return_value=subprocess.CompletedProcess([], 0)
        ):
            rejected(
                lambda: delivery.install(
                    state, declaration, "/synthetic-installer", [manifest]
                )
            )
        assert not (state / "ready.json").exists()
        assert (
            delivery.install(state, declaration, "/synthetic-installer", [manifest])
            == 0
        )
        secret.chmod(0o644)
        rejected(start)
        secret.chmod(0o400)
        with patch.object(delivery.os, "getuid", return_value=actual_uid + 10000):
            rejected(lambda: delivery.ready(state, manifest, policy))
        with patch.object(delivery.os, "getuid", return_value=actual_uid or 10000):
            rejected(
                lambda: delivery.install(
                    state, declaration, "/synthetic-installer", [manifest]
                )
            )
        start()

        context = multiprocessing.get_context("fork")
        first_entered, second_entered, release = (context.Event() for _ in range(3))

        def installer(entered, wait):
            def run(command, check):
                entered.set()
                if wait:
                    assert release.wait(10)
                return install_material(command, check)

            with patch.object(delivery.subprocess, "run", side_effect=run):
                assert (
                    delivery.install(
                        state, declaration, "/synthetic-installer", [manifest]
                    )
                    == 0
                )

        first = context.Process(target=installer, args=(first_entered, True))
        second = context.Process(target=installer, args=(second_entered, False))
        first.start()
        assert first_entered.wait(10)
        second.start()
        assert not second_entered.wait(0.3), (
            "concurrent installers entered the privileged effect"
        )
        release.set()
        for process in (first, second):
            process.join(10)
            assert process.exitcode == 0
        assert second_entered.is_set()
        start()

    mutated = root / "delivery-without-receipt-guard.py"
    original = pathlib.Path(source).read_text()
    guard = 'require(record["manifest"] == manifest and record["boot"] == boot_id())'
    assert guard in original
    mutated.write_text(original.replace(guard, "pass", 1))
    control = load(mutated)
    with contextlib.ExitStack() as stack:
        stack.enter_context(
            patch.object(
                control.os,
                "fstat",
                side_effect=lambda fd: root_metadata(original_fstat(fd)),
            )
        )
        stack.enter_context(patch.object(pathlib.Path, "lstat", observed_lstat))
        stack.enter_context(
            patch.object(control, "boot_id", return_value="after-reboot")
        )
        control.ready(state, "/nix/store/wrong-manifest", policy)
    print(
        "delivery fixtures passed: serialized installers, failure, partial replacement, stale receipt, reboot, owner/mode and guard-removal control"
    )


if __name__ == "__main__":
    exercise(sys.argv[1], pathlib.Path(sys.argv[2]))
