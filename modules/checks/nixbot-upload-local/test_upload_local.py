# Behavioural check of nixbot-upload-local-outputs.patch (F81). nixbot
# skips an attribute whose outputs are already in the store
# (skipped_local), assuming an earlier build built and uploaded them or they
# came from the cache; outputs built on the host another way then never
# reached the cache. In every build, pull requests, pushes to the default
# branch and to other branches (gitea-mq's batches) alike, the skipped
# attributes' outputs, all of them, now go to every uploader in one batch; a
# buildDependenciesOnly attribute publishes nothing, and built attributes
# keep their own upload. Drives build_attributes with a fake orchestrator
# and uploader; the database, which yields like real I/O, and the forge are
# stubbed. Run by checks.x86_64-linux.nixbot-upload-local against the
# patched nixbot package.
from __future__ import annotations

import asyncio
from pathlib import Path
from types import SimpleNamespace

import pytest

from nixbot import build_run, db
from nixbot.build_scheduler import BuildOutcome
from nixbot.db_gen import builds as q
from nixbot.models import CacheStatus, NixEvalJobSuccess

SYSTEM = "x86_64-linux"


class FakeUploader:
    """Groups the paths queued without the event loop running in between,
    which the real uploader takes up together."""

    name = "fake"

    def __init__(self) -> None:
        self.batches: list[list[str]] = []
        self._open: list[str] | None = None

    def enqueue_nowait(self, drv_path: str) -> None:
        if self._open is None:
            self._open = []
            self.batches.append(self._open)
            asyncio.get_running_loop().call_soon(self._close)
        self._open.append(drv_path)

    def _close(self) -> None:
        self._open = None


def job(
    attr: str,
    status: CacheStatus,
    outputs: dict[str, str | None],
    extra: dict[str, bool] | None = None,
) -> NixEvalJobSuccess:
    return NixEvalJobSuccess(
        attr=attr,
        attr_path=[attr],
        cache_status=status,
        needed_builds=[],
        needed_substitutes=[],
        drv_path=f"/nix/store/{attr:a<32}-{attr}.drv",
        name=attr,
        outputs=outputs,
        system=SYSTEM,
        extra_value=extra,
    )


async def run(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
    branch: str,
    pr_number: int | None,
) -> list[list[str]]:
    async def noop(*_args: object, **_kwargs: object) -> None:
        return None

    async def complete(*_args: object, **_kwargs: object) -> None:
        await asyncio.sleep(0)

    async def aggregate(*_args: object, **_kwargs: object) -> tuple[str, int]:
        return "success", 1

    async def statuses(*_args: object, **_kwargs: object) -> list[object]:
        return []

    monkeypatch.setattr(db, "complete_attribute", complete)
    monkeypatch.setattr(db, "aggregate_build", aggregate)
    monkeypatch.setattr(q, "attribute_statuses", statuses)
    monkeypatch.setattr(build_run, "after_build", noop)

    async def build(self: object, job: NixEvalJobSuccess) -> BuildOutcome:
        return BuildOutcome.success

    # A built attribute uploads in _after_success, which is not under test.
    monkeypatch.setattr(build_run._OrchestratorExecutor, "build", build)

    uploader = FakeUploader()
    o = SimpleNamespace(
        pool=None,
        cancel_events={},
        failed_build_cache=None,
        config=SimpleNamespace(
            cache_failed_builds=False, build_systems=[SYSTEM], url="https://ci"
        ),
        uploaders=[uploader],
        post_process_skipped=noop,
        reporter=SimpleNamespace(build_finished=noop),
        finish_linked=noop,
        release_run=lambda _build_id: None,
    )
    event = SimpleNamespace(
        repo=SimpleNamespace(forge="gitea", name="repo", default_branch="main"),
        branch=branch,
        pr_number=pr_number,
    )
    build_record = SimpleNamespace(id_=1, number=1, project_id=1)
    jobs = [
        job(
            "local",
            CacheStatus.local,
            {"out": "/nix/store/local-out", "dev": "/nix/store/local-dev"},
        ),
        job("local2", CacheStatus.local, {"out": "/nix/store/local2-out"}),
        job(
            "depsonly",
            CacheStatus.local,
            {"out": "/nix/store/depsonly-out"},
            {"buildDependenciesOnly": True},
        ),
        job("impure", CacheStatus.local, {"out": None}),
        job("built", CacheStatus.not_built, {"out": "/nix/store/built-out"}),
    ]
    await build_run.build_attributes(
        o, event, build_record, tmp_path, jobs, credentials=None
    )
    return uploader.batches


@pytest.mark.parametrize(
    ("branch", "pr_number"),
    [("main", None), ("feature", 7), ("main", 8), ("gitea-mq/batch/1", None)],
    ids=["main", "pull-request", "pull-request-from-main", "other-branch"],
)
def test_local_outputs_are_queued_in_one_batch(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
    branch: str,
    pr_number: int | None,
) -> None:
    batches = asyncio.run(run(tmp_path, monkeypatch, branch, pr_number))
    assert [sorted(b) for b in batches] == [
        ["/nix/store/local-dev", "/nix/store/local-out", "/nix/store/local2-out"]
    ]
