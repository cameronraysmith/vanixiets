# Behavioural check of nixbot-evaluation-record.patch: every evaluation the
# runner starts logs exactly one `evaluation finished` record, on success,
# failure and timeout, with the evaluation cgroup's counters read before the
# cgroup is removed, the evaluator's kill lines counted, and no text from the
# evaluator's output. Run by checks.x86_64-linux.nixbot-eval-record against
# the patched nixbot package.
from __future__ import annotations

import asyncio
import json
import logging
from pathlib import Path

import pytest

from nixbot import nix_eval
from nixbot.log import JsonFormatter
from nixbot.nix_eval import CgroupLimiter, EvalError, EvalRunner, EvalSettings
from nixbot.repo_config import BranchConfig

PEAK = 123_456_789
LIMIT_MIB = 3 * (2 + 1)
SECRET = "checks.x86_64-linux.secret-attribute"


class FixtureLimiter(CgroupLimiter):
    """A plain directory stands in for the delegated cgroup subtree; each
    evaluation cgroup gets the counter files the kernel would provide."""

    def new_eval_cgroup(self, limit_mib: int) -> Path:
        path = super().new_eval_cgroup(limit_mib)
        (path / "memory.peak").write_text(f"{PEAK}\n")
        (path / "memory.events").write_text(
            "low 0\nhigh 0\nmax 2\noom 1\noom_kill 1\noom_group_kill 0\n"
        )
        (path / "cpu.stat").write_text(
            "usage_usec 9000000\nuser_usec 7000000\nsystem_usec 2000000\n"
        )
        return path

    async def cleanup(self, path: Path) -> None:
        # The kernel drops a cgroup's files with it; a record written after
        # this point would find none of them.
        for file in path.iterdir():
            file.unlink()
        await super().cleanup(path)


def evaluate(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
    caplog: pytest.LogCaptureFixture,
    body: str,
    *,
    limiter: CgroupLimiter | None = None,
    timeout: float = 30,
) -> tuple[list[dict[str, object]], BaseException | None]:
    script = tmp_path / "nix-eval-jobs"
    script.write_text("#!/bin/sh\n" + body)
    script.chmod(0o755)
    monkeypatch.setattr(nix_eval, "build_full_command", lambda *_a: [str(script)])
    settings = EvalSettings(
        gc_roots_dir=tmp_path / "gcroots",
        sandbox=False,
        systemd_scope=limiter is not None,
        timeout=timeout,
        worker_count=2,
        max_memory_size_mib=3,
        build_id=4242,
    )
    caplog.set_level(logging.INFO, logger="nixbot.nix_eval")
    error: BaseException | None = None
    try:
        asyncio.run(EvalRunner(limiter).run(tmp_path, BranchConfig(), settings))
    except EvalError as e:
        error = e
    formatter = JsonFormatter()
    records = [
        json.loads(formatter.format(r))
        for r in caplog.records
        if r.getMessage() == "evaluation finished"
    ]
    return records, error


def test_success_with_cgroup(tmp_path, monkeypatch, caplog):
    monkeypatch.setenv("NIXBOT_EVALUATOR", "iets 0.2.0")
    limiter = FixtureLimiter(tmp_path / "cgroup")
    (tmp_path / "cgroup").mkdir()
    records, error = evaluate(tmp_path, monkeypatch, caplog, "exit 0\n", limiter=limiter)
    assert error is None
    assert len(records) == 1
    r = records[0]
    assert r["msg"] == "evaluation finished"
    assert r["build_id"] == 4242
    assert r["evaluator"] == "iets"
    assert r["evaluator_version"] == "0.2.0"
    assert r["workers"] == 2
    assert r["max_memory_mib"] == 3
    assert r["memory_max_bytes"] == LIMIT_MIB * 1024 * 1024
    assert r["memory_peak_bytes"] == PEAK
    assert r["oom_kill"] == 1
    assert r["user_ms"] == 7000
    assert r["system_ms"] == 2000
    assert isinstance(r["wall_ms"], int)
    assert r["budget_kills"] == 0
    assert r["worker_kills"] == 0
    assert r["exit_status"] == 0
    assert "ts" in r


def test_default_evaluator_name(tmp_path, monkeypatch, caplog):
    monkeypatch.delenv("NIXBOT_EVALUATOR", raising=False)
    records, _ = evaluate(tmp_path, monkeypatch, caplog, "exit 0\n")
    assert len(records) == 1
    assert records[0]["evaluator"] == "nix-eval-jobs"
    assert records[0]["evaluator_version"] is None


def test_failure_is_recorded(tmp_path, monkeypatch, caplog):
    limiter = FixtureLimiter(tmp_path / "cgroup")
    (tmp_path / "cgroup").mkdir()
    records, error = evaluate(
        tmp_path, monkeypatch, caplog, "echo 'error: broken' >&2\nexit 1\n", limiter=limiter
    )
    assert isinstance(error, EvalError)
    assert len(records) == 1
    assert records[0]["exit_status"] == 1
    assert records[0]["memory_peak_bytes"] == PEAK


def test_kill_lines_are_counted_and_no_text_is_kept(tmp_path, monkeypatch, caplog):
    body = (
        "echo \"memory budget of 18432 MiB exceeded (19000 MiB in use), "
        f"killing worker 42 ('{SECRET}', 4000 MiB)\" >&2\n"
        "echo 'evaluation worker 43 was killed (system out of memory?)' >&2\n"
        f"echo 'error: while evaluating {SECRET}' >&2\n"
        "exit 0\n"
    )
    records, error = evaluate(tmp_path, monkeypatch, caplog, body)
    assert error is None
    assert len(records) == 1
    r = records[0]
    assert r["budget_kills"] == 1
    assert r["worker_kills"] == 1
    assert SECRET not in json.dumps(r)


def test_timeout_is_recorded(tmp_path, monkeypatch, caplog):
    records, error = evaluate(tmp_path, monkeypatch, caplog, "exec sleep 60\n", timeout=0.5)
    assert isinstance(error, EvalError)
    assert "timed out" in str(error)
    assert len(records) == 1
    assert records[0]["exit_status"] != 0


def test_without_cgroup_the_cgroup_fields_are_absent(tmp_path, monkeypatch, caplog):
    records, _ = evaluate(tmp_path, monkeypatch, caplog, "exit 0\n")
    assert len(records) == 1
    for key in ("memory_max_bytes", "memory_peak_bytes", "oom_kill", "user_ms", "system_ms"):
        assert key not in records[0]


def test_cgroup_is_removed_after_the_record(tmp_path, monkeypatch, caplog):
    limiter = FixtureLimiter(tmp_path / "cgroup")
    (tmp_path / "cgroup").mkdir()
    records, _ = evaluate(tmp_path, monkeypatch, caplog, "exit 0\n", limiter=limiter)
    assert records[0]["memory_peak_bytes"] == PEAK
    assert not any((tmp_path / "cgroup").glob("eval-*"))
