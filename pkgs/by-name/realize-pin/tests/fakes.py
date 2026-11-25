"""Fake capabilities fed recorded upstream content (task 3.1).

`Files` is the real `TreeFiles` rooted in a temporary tree.  The fake `Git`
compares that tree with the content it was given as committed, as
`git status --porcelain` compares the working tree with HEAD.
"""

from __future__ import annotations

import json
from collections.abc import Callable, Mapping
from dataclasses import dataclass, field
from pathlib import Path
from typing import override

from expression import Error, Ok, Result

from realize_pin.capabilities import FixedOutputHasher, FodAttr, Git, Http, Method, Nix, SkillHasher, Sri, sri
from realize_pin.model import Json
from realize_pin.policy import pin_path

FIXTURES = Path(__file__).parent / "fixtures"


@dataclass
class FakeHttp(Http):
    """Serves recorded bodies by URL and records every request it receives."""

    bodies: Mapping[str, bytes]
    requests: list[tuple[Method, str]] = field(default_factory=lambda: [])
    on_request: Callable[[], None] | None = None

    @override
    def request(self, method: Method, url: str, timeout: float) -> Result[bytes, str]:
        self.requests.append((method, url))
        if self.on_request is not None:
            self.on_request()
        body = self.bodies.get(url)
        if body is None:
            return Error(f"{method} {url}: HTTP 404")
        return Ok(body)


@dataclass
class FakeNix(Nix):
    """Evaluates the pin from the tree, the plan from fixtures, and answers prefetches."""

    root: Path
    plans: Mapping[str, Json]
    prefetches: Mapping[str, str] = field(default_factory=lambda: {})

    @override
    def eval_pin(self, package: str, timeout: float) -> Result[Json, str]:
        path = self.root / pin_path(package)
        if not path.exists():
            return Error(f"flake has no {package}.passthru.pin")
        value: Json = json.loads(path.read_text())
        return Ok(value)

    @override
    def eval_plan(self, package: str, version: str, timeout: float) -> Result[Json, str]:
        plan = self.plans.get(version)
        if plan is None:
            return Error(f"no plan for {version}")
        return Ok(plan)

    @override
    def prefetch(self, url: str, timeout: float) -> Result[str, str]:
        hashed = self.prefetches.get(url)
        if hashed is None:
            return Error(f"error: unable to download '{url}': HTTP error 404")
        return Ok(hashed)


@dataclass
class FakeHasher(FixedOutputHasher):
    """Answers each (package, attribute) with a recorded hash or a recorded failure.

    `ready` stands for nix-update building from the current tree: it names what
    in the tree is not yet at the realized version, and the hash then fails.
    """

    answers: Mapping[tuple[str, FodAttr], str | Exception]
    ready: Callable[[str, FodAttr], str | None] = lambda package, attr: None
    calls: list[tuple[str, FodAttr]] = field(default_factory=lambda: [])
    on_hash: Callable[[], None] | None = None

    @override
    def hash(self, package: str, attr: FodAttr, timeout: float) -> Result[Sri, str]:
        self.calls.append((package, attr))
        if self.on_hash is not None:
            self.on_hash()
        not_ready = self.ready(package, attr)
        if not_ready is not None:
            return Error(f"hash mismatch building from a stale tree: {not_ready}")
        answer = self.answers.get((package, attr))
        if answer is None:
            return Error(f"no recorded hash for {package} {attr}")
        if isinstance(answer, Exception):
            return Error(str(answer))
        return sri(answer)


@dataclass
class FakeSkillHasher(SkillHasher):
    """Answers each skill with a recorded installed hash, or fails as a stale tree would.

    `ready` stands for the compose building from the current tree: it names
    what in the tree is not yet at the realized version, and the hash then fails.
    """

    answers: Mapping[str, str | Exception]
    ready: Callable[[], str | None] = lambda: None
    calls: list[tuple[str, ...]] = field(default_factory=lambda: [])
    on_hash: Callable[[], None] | None = None

    @override
    def hash(self, skills: tuple[str, ...], timeout: float) -> Result[Mapping[str, Sri], str]:
        self.calls.append(skills)
        if self.on_hash is not None:
            self.on_hash()
        not_ready = self.ready()
        if not_ready is not None:
            return Error(f"the compose builds from a stale tree: {not_ready}")
        hashes: dict[str, Sri] = {}
        for skill in skills:
            answer = self.answers.get(skill)
            if answer is None:
                return Error(f"the compose installs no skill {skill}")
            if isinstance(answer, Exception):
                return Error(str(answer))
            checked = sri(answer)
            if checked.is_error():
                return Error(checked.error)
            hashes[skill] = checked.ok
        return Ok(hashes)


@dataclass
class FakeGit(Git):
    """Answers ls-remote from recordings and status by comparing the tree with `committed`."""

    root: Path
    committed: Mapping[str, bytes]
    remotes: Mapping[str, str] = field(default_factory=lambda: {})
    calls: list[tuple[str, tuple[str, ...]]] = field(default_factory=lambda: [])

    @override
    def ls_remote(self, url: str, refs: tuple[str, ...], timeout: float) -> Result[str, str]:
        self.calls.append((url, refs))
        listed = self.remotes.get(url)
        if listed is None:
            return Error(f"fatal: repository '{url}' not found")
        return Ok("".join(line + "\n" for line in listed.splitlines() if line.split("\t")[-1] in refs))

    @override
    def changed_paths(self, timeout: float) -> Result[frozenset[str], str]:
        present = {str(p.relative_to(self.root)): p.read_bytes() for p in self.root.rglob("*") if p.is_file()}
        paths = {p for p, data in present.items() if self.committed.get(p) != data}
        paths |= {p for p in self.committed if p not in present}
        return Ok(frozenset(paths))


class Clock:
    """A monotonic clock the test advances by hand."""

    def __init__(self) -> None:
        self.now = 1000.0

    def __call__(self) -> float:
        return self.now
