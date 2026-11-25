"""Offline realizations of the stage-1 pins from recorded upstream content (task 3.3)."""

from __future__ import annotations

import json
import re
from collections.abc import Callable
from dataclasses import dataclass
from pathlib import Path
from urllib.parse import urlsplit

import pytest
from expression import Result

from fakes import FIXTURES, Clock, FakeEvalHasher, FakeGit, FakeHasher, FakeHttp, FakeNix, FakeSkillHasher, RecordingFiles
from realize_pin.adapters import TreeFiles
from realize_pin.capabilities import Capabilities, CargoDeps, Custom, Files, FodAttr, NpmDeps, Src
from realize_pin.cli import main
from realize_pin.model import Json
from realize_pin.policy import pin_path
from realize_pin.realize import Deadline, Realization, RealizeError, Step, realize

RECORDED = (
    "ic-wasm-bin",
    "icp-cli-bin",
    "omnigraph",
    "mergify-cli-bin",
    "moshi-hook",
    "claude-code",
    "greptimedb-bin",
    "ouroboros",
    "tmux-command-palette",
)
APM = "modules/home/ai/plugins/version-control-and-forge/apm.yml"
HASHES = "pkgs/by-name/apm-skills-compose/hashes.json"
SKILLS = "pkgs/by-name/apm-skills-compose/skills.json"
MERGIFY_SKILL = "mergify-stack"
MERGIFY_REV = "e7c1ebbc281361f0b2b7827cf583f57339c97ebc"
UNRELATED_DIRTY = "notes/scratch.txt"
STALE_SRI = "sha256-" + "B" * 43 + "="
SRI = re.compile(r"sha256-[A-Za-z0-9+/]{43}=")


def _load(path: Path) -> Json:
    value: Json = json.loads(path.read_text())
    return value


def _plan(package: str) -> dict[str, Json]:
    plan = _load(FIXTURES / package / "plan.json")
    assert isinstance(plan, dict)
    return plan


def committed(package: str) -> dict[str, bytes]:
    """The files a realization of the recorded release must produce."""
    d = FIXTURES / package
    files = {pin_path(package): (d / "pin.json").read_bytes()}
    if package == "mergify-cli-bin":
        files[APM] = (d / "apm.yml").read_bytes()
        files[HASHES] = (d / "hashes.json").read_bytes()
        files[SKILLS] = (d / "skills.json").read_bytes()
    return files


def _stale_skill_index(data: bytes) -> bytes:
    """The skill index before a mergify release: only mergify's own skill hash differs."""
    doc = json.loads(data)
    doc["remote"][MERGIFY_SKILL] = STALE_SRI
    return (json.dumps(doc, indent=2, ensure_ascii=False) + "\n").encode()


def stale(files: dict[str, bytes]) -> dict[str, bytes]:
    """The same files at an older version, realized there: every digest, rev, file value and version moved."""
    out: dict[str, bytes] = {}
    for path, data in files.items():
        if path == SKILLS:
            out[path] = _stale_skill_index(data)
            continue
        text = SRI.sub(STALE_SRI, data.decode()).replace(MERGIFY_REV, "0" * 40)
        if path.endswith("pin.json"):
            doc = json.loads(text)
            doc["version"] = "0.0.1"
            doc["realizedVersion"] = "0.0.1"
            for artifact in doc["artifacts"].values():
                if "fileValue" in artifact:
                    artifact["fileValue"]["value"] = "0.0.0"
            text = json.dumps(doc, indent=2, ensure_ascii=False) + "\n"
        out[path] = text.encode()
    return out


@dataclass
class Scenario:
    root: Path
    package: str
    version: str
    http: FakeHttp
    nix: FakeNix
    hasher: FakeHasher
    skills: FakeSkillHasher
    git: FakeGit
    clock: Clock

    def capabilities(self, files: Files | None = None) -> Capabilities:
        return Capabilities(
            http=self.http,
            nix=self.nix,
            hasher=self.hasher,
            skills=self.skills,
            git=self.git,
            files=TreeFiles(self.root) if files is None else files,
        )

    def run(self, files: Files | None = None) -> Result[Realization, RealizeError]:
        return realize(self.package, self.version, self.capabilities(files), Deadline.start(self.clock))

    def tree(self) -> dict[str, bytes]:
        return {str(p.relative_to(self.root)): p.read_bytes() for p in self.root.rglob("*") if p.is_file()}


def scenario(
    package: str,
    root: Path,
    files: dict[str, bytes],
    bodies: dict[str, bytes] | None = None,
    hashes: dict[tuple[str, FodAttr], str | Exception] | None = None,
    plan: dict[str, Json] | None = None,
) -> Scenario:
    for path, data in files.items():
        target = root / path
        target.parent.mkdir(parents=True, exist_ok=True)
        _ = target.write_bytes(data)
    dirty = root / UNRELATED_DIRTY
    dirty.parent.mkdir(parents=True, exist_ok=True)
    _ = dirty.write_text("work in progress of another session\n")
    d = FIXTURES / package
    recorded = _load(d / "recorded.json")
    assert isinstance(recorded, dict)
    served: dict[str, bytes] = {}
    for url, name in recorded.items():
        assert isinstance(name, str)
        served[url] = (d / "upstream" / name).read_bytes()
    if bodies is not None:
        served.update(bodies)
    planned = plan if plan is not None else _plan(package)
    version = planned["version"]
    assert isinstance(version, str)
    remotes: dict[str, str] = {}
    answers: dict[tuple[str, FodAttr], str | Exception] = {}
    if package == "omnigraph":
        answers[("omnigraph", Custom("skillSrc"))] = "sha256-fDjXKhh/jAXST0SGoPsGkFDIZtpGF9NxCxGd7H4snBA="
    if package == "tmux-command-palette":
        answers[("tmux-command-palette", Src())] = "sha256-zkQhWRd4AiH9XjfRausvB2MNR3xXirYJA13OtvQ4oGQ="
    skill_answers: dict[str, str | Exception] = {}
    if package == "mergify-cli-bin":
        remotes["https://github.com/Mergifyio/mergify-cli"] = (d / "ls-remote.txt").read_text()
        answers[("apm-skills-compose", Custom("deps"))] = "sha256-4ELGyWHWhpyAODdyXvNbf4heYCBhwjDiFP6Plgm3Td8="
        skill_answers[MERGIFY_SKILL] = json.loads((d / "skills.json").read_text())["remote"][MERGIFY_SKILL]
    if hashes is not None:
        answers.update(hashes)

    def ready(fod_package: str, attr: FodAttr) -> str | None:
        """nix-update builds from the tree: the pin and every apm.yml ref must already be at the release."""
        doc = json.loads((root / pin_path(package)).read_text())
        if doc["version"] != version:
            return f"{pin_path(package)} is at {doc['version']}"
        apm = root / APM
        if package == "mergify-cli-bin" and MERGIFY_REV not in apm.read_text():
            return f"{APM} is not at {MERGIFY_REV}"
        return None

    def skills_ready() -> str | None:
        """The compose builds from the tree: the apm.yml ref and apmDepsHash must already be realized."""
        not_ready = ready("apm-skills-compose", Custom("deps"))
        if not_ready is not None:
            return not_ready
        if STALE_SRI in (root / HASHES).read_text():
            return f"{HASHES} still holds the stale apmDepsHash"
        return None

    return Scenario(
        root=root,
        package=package,
        version=version,
        http=FakeHttp(served),
        nix=FakeNix(root, {version: planned}),
        hasher=FakeHasher(answers, ready),
        skills=FakeSkillHasher(skill_answers, skills_ready),
        git=FakeGit(root, dict(files), remotes),
        clock=Clock(),
    )


def _plan_urls(node: Json) -> set[str]:
    if isinstance(node, dict):
        urls = {v for k, v in node.items() if k in ("url", "probeUrl") and isinstance(v, str)}
        for v in node.values():
            urls |= _plan_urls(v)
        return urls
    if isinstance(node, list):
        out: set[str] = set()
        for v in node:
            out |= _plan_urls(v)
        return out
    return set()


def assert_requests_within_policy(s: Scenario) -> None:
    allowed = _plan_urls(_plan(s.package))
    if allowed:
        assert s.http.requests, "the realization fetched nothing"
    for method, url in s.http.requests:
        assert method in ("GET", "HEAD")
        assert urlsplit(url).hostname != "api.github.com"
        assert url in allowed, f"{url} is not in {s.package}'s plan"
    for remote, _ in s.git.calls:
        assert urlsplit(remote).hostname == "github.com"


@pytest.mark.parametrize("package", RECORDED)
def test_realizes_recorded_release(package: str, tmp_path: Path) -> None:
    s = scenario(package, tmp_path, stale(committed(package)))
    result = s.run()
    assert result.is_ok(), result.error.render() if result.is_error() else ""
    tree = s.tree()
    for path, data in committed(package).items():
        assert tree[path] == data, f"{path} differs from the committed content"
    assert sorted(result.ok.changed) == sorted(committed(package))
    assert tree[UNRELATED_DIRTY] == b"work in progress of another session\n"
    assert_requests_within_policy(s)


@pytest.mark.parametrize("package", RECORDED)
def test_second_run_changes_nothing(package: str, tmp_path: Path) -> None:
    s = scenario(package, tmp_path, stale(committed(package)))
    assert s.run().is_ok()
    after_first = s.tree()
    second = s.run()
    assert second.is_ok(), second.error.render() if second.is_error() else ""
    assert second.ok.changed == ()
    assert s.tree() == after_first


def test_checksum_file_missing_a_platform(tmp_path: Path) -> None:
    sums = (FIXTURES / "mergify-cli-bin" / "upstream" / "SHA256SUMS").read_text()
    without = "".join(line + "\n" for line in sums.splitlines() if "x86_64-apple-darwin" not in line)
    url = "https://github.com/Mergifyio/mergify-cli/releases/download/2026.9.16.1/SHA256SUMS"
    s = scenario("mergify-cli-bin", tmp_path, stale(committed("mergify-cli-bin")), bodies={url: without.encode()})
    before = s.tree()
    result = s.run()
    assert result.is_error()
    assert result.error.step == Step.HASH
    assert "x86_64-darwin" in result.error.render()
    assert "mergify-cli-bin" in result.error.render()
    assert s.tree() == before


def _realized_version(data: bytes) -> Json:
    doc: Json = json.loads(data)
    assert isinstance(doc, dict)
    return doc.get("realizedVersion")


@pytest.mark.parametrize("package", RECORDED)
def test_realization_marks_the_version_realized(package: str, tmp_path: Path) -> None:
    s = scenario(package, tmp_path, stale(committed(package)))
    result = s.run()
    assert result.is_ok(), result.error.render() if result.is_error() else ""
    doc = _pin_doc(tmp_path, package)
    assert isinstance(doc, dict)
    assert doc["realizedVersion"] == doc["version"] == s.version


def test_artifact_failure_never_marks_the_version_realized(tmp_path: Path) -> None:
    """The restore puts pin.json back byte for byte, and no state written before it marks the new version
    realized, so a run killed before its restore still fails pin-realized."""
    sums = (FIXTURES / "mergify-cli-bin" / "upstream" / "SHA256SUMS").read_text()
    without = "".join(line + "\n" for line in sums.splitlines() if "x86_64-apple-darwin" not in line)
    url = "https://github.com/Mergifyio/mergify-cli/releases/download/2026.9.16.1/SHA256SUMS"
    s = scenario("mergify-cli-bin", tmp_path, stale(committed("mergify-cli-bin")), bodies={url: without.encode()})
    files = RecordingFiles(TreeFiles(tmp_path))
    before = s.tree()
    result = s.run(files)
    assert result.is_error()
    assert result.error.step == Step.HASH
    assert s.tree() == before
    pin_writes = [data for path, data in files.writes if path == pin_path("mergify-cli-bin")]
    assert any(json.loads(data)["version"] == s.version for data in pin_writes), "the version never moved"
    assert [_realized_version(data) for data in pin_writes] == ["0.0.1"] * len(pin_writes)


@pytest.mark.parametrize("package", RECORDED)
def test_realizing_the_current_version_keeps_it_realized(package: str, tmp_path: Path) -> None:
    s = scenario(package, tmp_path, committed(package))
    before = s.tree()
    result = s.run()
    assert result.is_ok(), result.error.render() if result.is_error() else ""
    assert result.ok.changed == ()
    assert s.tree() == before
    doc = _pin_doc(tmp_path, package)
    assert isinstance(doc, dict)
    assert doc["realizedVersion"] == doc["version"] == s.version


def test_realization_adds_a_missing_realized_version(tmp_path: Path) -> None:
    files = stale(committed("ic-wasm-bin"))
    path = pin_path("ic-wasm-bin")
    doc = json.loads(files[path])
    del doc["realizedVersion"]
    files[path] = (json.dumps(doc, indent=2) + "\n").encode()
    s = scenario("ic-wasm-bin", tmp_path, files)
    result = s.run()
    assert result.is_ok(), result.error.render() if result.is_error() else ""
    assert _realized_version((tmp_path / path).read_bytes()) == s.version


def _git_commit_plan(version: str) -> dict[str, Json]:
    plan = _plan("tmux-command-palette")
    plan["version"] = version
    plan["artifacts"] = {
        "src": {"sourceBuild": {"fetchFromGitHub": {"owner": "lost-melody", "repo": "tmux-command-palette", "rev": version}}}
    }
    return plan


def test_git_commit_pin_records_no_rev(tmp_path: Path) -> None:
    """A gitCommit pin's version is its commit; Renovate rewrites only that field, so no `rev` may shadow it."""
    s = scenario("tmux-command-palette", tmp_path, stale(committed("tmux-command-palette")))
    result = s.run()
    assert result.is_ok(), result.error.render() if result.is_error() else ""
    doc = _pin_doc(tmp_path, "tmux-command-palette")
    assert isinstance(doc, dict)
    assert "rev" not in doc
    assert doc["version"] == doc["realizedVersion"] == s.version
    assert s.git.calls == []


@pytest.mark.parametrize("version", ["main", "dbcaf76", "DBCAF7666A05B7AF34F3BA38C0A67A751188DF7A"])
def test_git_commit_pin_refuses_a_version_that_is_no_commit(version: str, tmp_path: Path) -> None:
    s = scenario("tmux-command-palette", tmp_path, stale(committed("tmux-command-palette")), plan=_git_commit_plan(version))
    before = s.tree()
    result = s.run()
    assert result.is_error()
    assert result.error.step == Step.REV
    assert "is not a 40-character commit" in result.error.message
    assert s.tree() == before


def test_hasher_error(tmp_path: Path) -> None:
    failure: dict[tuple[str, FodAttr], str | Exception] = {
        ("apm-skills-compose", Custom("deps")): RuntimeError("nix-update failed: builder for apm-deps failed")
    }
    s = scenario("mergify-cli-bin", tmp_path, stale(committed("mergify-cli-bin")), hashes=failure)
    before = s.tree()
    result = s.run()
    assert result.is_error()
    assert result.error.step == Step.FIXED_OUTPUT_HASH
    assert "apm-skills-compose.deps" in result.error.message
    assert s.tree() == before


def test_hasher_timeout_exits_non_zero(tmp_path: Path, capsys: pytest.CaptureFixture[str]) -> None:
    timeout: dict[tuple[str, FodAttr], str | Exception] = {
        ("apm-skills-compose", Custom("deps")): TimeoutError("nix-update ran past the deadline")
    }
    s = scenario("mergify-cli-bin", tmp_path, stale(committed("mergify-cli-bin")), hashes=timeout)
    before = s.tree()
    code = main(["mergify-cli-bin", s.version], capabilities=lambda _root: s.capabilities(), clock=s.clock)
    assert code != 0
    err = capsys.readouterr().err
    assert "mergify-cli-bin" in err
    assert "apm-skills-compose.deps" in err
    assert "ran past the deadline" in err
    assert s.tree() == before


def test_write_outside_the_allowed_set(tmp_path: Path) -> None:
    s = scenario("ic-wasm-bin", tmp_path, stale(committed("ic-wasm-bin")))
    before = s.tree()

    def stray() -> None:
        _ = (tmp_path / "result").write_text("a build left this behind\n")

    s.http.on_request = stray
    result = s.run()
    assert result.is_error()
    assert result.error.step == Step.CONFINE
    assert "result" in result.error.message
    after = s.tree()
    assert after.pop("result") == b"a build left this behind\n"
    assert after == before


def test_write_to_a_file_that_was_already_dirty(tmp_path: Path) -> None:
    s = scenario("ic-wasm-bin", tmp_path, stale(committed("ic-wasm-bin")))
    before = s.tree()

    def stray() -> None:
        with (tmp_path / UNRELATED_DIRTY).open("a") as f:
            _ = f.write("appended by a step of the realizer\n")

    s.http.on_request = stray
    result = s.run()
    assert result.is_error()
    assert result.error.step == Step.CONFINE
    assert UNRELATED_DIRTY in result.error.message
    after = s.tree()
    del after[UNRELATED_DIRTY], before[UNRELATED_DIRTY]
    assert after == before


def test_deadline_passes(tmp_path: Path) -> None:
    s = scenario("mergify-cli-bin", tmp_path, stale(committed("mergify-cli-bin")))
    before = s.tree()

    def slow_hash() -> None:
        s.clock.now += 601

    s.hasher.on_hash = slow_hash
    result = s.run()
    assert result.is_error()
    assert result.error.step == Step.DEADLINE
    assert s.tree() == before


def test_forge_api_host_is_refused(tmp_path: Path) -> None:
    plan = _plan("ic-wasm-bin")
    text = json.dumps(plan).replace(
        "https://github.com/dfinity/ic-wasm/releases/download/1.0.0/ic-wasm-x86_64-unknown-linux-gnu.tar.xz.sha256",
        "https://api.github.com/repos/dfinity/ic-wasm/releases/tags/1.0.0",
    )
    s = scenario("ic-wasm-bin", tmp_path, stale(committed("ic-wasm-bin")), plan=json.loads(text))
    before = s.tree()
    result = s.run()
    assert result.is_error()
    assert "api.github.com" in result.error.message
    assert all(urlsplit(url).hostname != "api.github.com" for _, url in s.http.requests)
    assert s.tree() == before


type Ready = Callable[[str, FodAttr], str | None]


def _deps_pin(deps: str) -> dict[str, Json]:
    return {
        "name": "deps-demo",
        "version": "0.0.1",
        "realizedVersion": "0.0.1",
        "source": {"githubRelease": {"owner": "example", "repo": "deps-demo", "tagTemplate": "v{version}"}},
        "artifacts": {
            "src": {
                "sourceBuild": {
                    "fetcher": {"fetchFromGitHub": {"owner": "example", "repo": "deps-demo"}},
                    "hash": STALE_SRI,
                    "depsHash": {deps: {"hash": STALE_SRI}},
                }
            }
        },
        "companions": [],
    }


DEPS_PLAN: dict[str, Json] = {
    "version": "1.2.3",
    "tag": "v1.2.3",
    "artifacts": {"src": {"sourceBuild": {"fetchFromGitHub": {"owner": "example", "repo": "deps-demo", "tag": "v1.2.3"}}}},
}
DEPS_SRC = "sha256-" + "C" * 43 + "="
DEPS_GOT = "sha256-" + "D" * 43 + "="


def _deps_scenario(root: Path, deps: str, hasher: Callable[[Ready], FakeHasher]) -> Scenario:
    files = {pin_path("deps-demo"): (json.dumps(_deps_pin(deps), indent=2) + "\n").encode()}
    for path, data in files.items():
        (root / path).parent.mkdir(parents=True, exist_ok=True)
        _ = (root / path).write_bytes(data)

    def ready(package: str, attr: FodAttr) -> str | None:
        """The dependency derivation unpacks src, so src must already carry its realized hash."""
        source = json.loads((root / pin_path("deps-demo")).read_text())["artifacts"]["src"]["sourceBuild"]
        if attr != Src() and source["hash"] != DEPS_SRC:
            return f"src is at {source['hash']}"
        return None

    return Scenario(
        root=root,
        package="deps-demo",
        version="1.2.3",
        http=FakeHttp({}),
        nix=FakeNix(root, {"1.2.3": DEPS_PLAN}),
        hasher=hasher(ready),
        skills=FakeSkillHasher({}),
        git=FakeGit(root, files),
        clock=Clock(),
    )


def _assert_deps_realized(root: Path, deps: str) -> None:
    doc = json.loads((root / pin_path("deps-demo")).read_text())
    assert doc["version"] == doc["realizedVersion"] == "1.2.3"
    assert doc["artifacts"]["src"]["sourceBuild"]["hash"] == DEPS_SRC
    assert doc["artifacts"]["src"]["sourceBuild"]["depsHash"][deps]["hash"] == DEPS_GOT


def test_source_and_deps_hash_from_the_hasher(tmp_path: Path) -> None:
    s = _deps_scenario(
        tmp_path, "npm", lambda ready: FakeHasher({("deps-demo", Src()): DEPS_SRC, ("deps-demo", NpmDeps()): DEPS_GOT}, ready)
    )
    result = s.run()
    assert result.is_ok(), result.error.render() if result.is_error() else ""
    _assert_deps_realized(tmp_path, "npm")
    assert s.hasher.calls == [("deps-demo", Src()), ("deps-demo", NpmDeps())]


def test_cargo_deps_hash_is_the_vendor_staging_hash(tmp_path: Path) -> None:
    """`fetchCargoVendor` makes `cargoDeps` a plain `runCommand`; its fixed-output derivation is `vendorStaging`."""
    paths = {"deps-demo.src": DEPS_SRC, "deps-demo.cargoDeps.vendorStaging": DEPS_GOT}
    s = _deps_scenario(tmp_path, "cargo", lambda ready: FakeEvalHasher({}, ready, paths=paths))
    result = s.run()
    assert result.is_ok(), result.error.render() if result.is_error() else ""
    _assert_deps_realized(tmp_path, "cargo")
    assert s.hasher.calls == [("deps-demo", Src()), ("deps-demo", CargoDeps())]


GREPTIME_VERSION = "https://raw.githubusercontent.com/GreptimeTeam/greptimedb/v1.2.1/src/servers/dashboard/VERSION"
OUROBOROS_PROBE = "https://pypi.org/pypi/ouroboros-ai/0.55.3/json"


def _without(s: Scenario, url: str) -> None:
    """Serve `url` as missing, as a 404 would."""
    assert isinstance(s.http.bodies, dict)
    del s.http.bodies[url]


def _pin_doc(root: Path, package: str) -> Json:
    return _load(root / pin_path(package))


def test_file_value_reads_the_version_file_at_the_tag(tmp_path: Path) -> None:
    s = scenario("greptimedb-bin", tmp_path, stale(committed("greptimedb-bin")))
    result = s.run()
    assert result.is_ok(), result.error.render() if result.is_error() else ""
    doc = json.loads((tmp_path / pin_path("greptimedb-bin")).read_text())
    assert doc["artifacts"]["dashboard"]["fileValue"]["value"] == "0.13.13"
    assert ("GET", GREPTIME_VERSION) in s.http.requests


def test_file_value_body_that_does_not_match(tmp_path: Path) -> None:
    s = scenario("greptimedb-bin", tmp_path, stale(committed("greptimedb-bin")), bodies={GREPTIME_VERSION: b"nightly\n"})
    before = s.tree()
    result = s.run()
    assert result.is_error()
    assert result.error.step == Step.FILE_VALUE
    assert "does not match" in result.error.message
    assert s.tree() == before


def test_file_value_missing_restores_the_pin(tmp_path: Path) -> None:
    s = scenario("greptimedb-bin", tmp_path, stale(committed("greptimedb-bin")))
    _without(s, GREPTIME_VERSION)
    before = s.tree()
    result = s.run()
    assert result.is_error()
    assert result.error.step == Step.FILE_VALUE
    assert "404" in result.error.message
    assert s.tree() == before


def test_runtime_fetch_probe_writes_only_the_version(tmp_path: Path) -> None:
    files = stale(committed("ouroboros"))
    s = scenario("ouroboros", tmp_path, files)
    old = _pin_doc(tmp_path, "ouroboros")
    result = s.run()
    assert result.is_ok(), result.error.render() if result.is_error() else ""
    new = _pin_doc(tmp_path, "ouroboros")
    assert isinstance(old, dict) and isinstance(new, dict)
    assert new.pop("version") == new.pop("realizedVersion") == "0.55.3"
    assert old.pop("version") == old.pop("realizedVersion") == "0.0.1"
    assert new == old
    assert result.ok.changed == (pin_path("ouroboros"),)
    assert s.http.requests == [("GET", OUROBOROS_PROBE)]


def test_runtime_fetch_probe_missing_restores_the_pin(tmp_path: Path) -> None:
    s = scenario("ouroboros", tmp_path, stale(committed("ouroboros")))
    _without(s, OUROBOROS_PROBE)
    before = s.tree()
    result = s.run()
    assert result.is_error()
    assert result.error.step == Step.PROBE
    assert "0.55.3 not found" in result.error.message
    assert s.tree() == before


def test_plan_without_a_pinned_artifact_is_refused(tmp_path: Path) -> None:
    plan = _plan("greptimedb-bin")
    artifacts = plan["artifacts"]
    assert isinstance(artifacts, dict)
    del artifacts["dashboard"]
    s = scenario("greptimedb-bin", tmp_path, stale(committed("greptimedb-bin")), plan=plan)
    before = s.tree()
    result = s.run()
    assert result.is_error()
    assert result.error.step == Step.EVALUATE
    assert "differ" in result.error.message
    assert s.tree() == before


def test_plan_of_another_artifact_kind_is_refused(tmp_path: Path) -> None:
    plan = _plan("greptimedb-bin")
    artifacts = plan["artifacts"]
    assert isinstance(artifacts, dict)
    artifacts["dashboard"] = {"runtimeFetch": {"probeUrl": GREPTIME_VERSION}}
    s = scenario("greptimedb-bin", tmp_path, stale(committed("greptimedb-bin")), plan=plan)
    before = s.tree()
    result = s.run()
    assert result.is_error()
    assert result.error.step == Step.HASH
    assert "dashboard: the plan has runtimeFetch where the pin has fileValue" in result.error.message
    assert s.tree() == before


FILE_URL = "https://github.com/caffeinelabs/mops/releases/download/cli-v3.9.0/cli.tgz"
FILE_SUMS = FILE_URL + ".sha256"
EMPTY_HEX = "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
EMPTY_SRI = "sha256-47DEQpj8HBSa+/TImW+5JCeuQeRkm5NMpJWZG3hSuFU="


def _file_scenario(
    root: Path,
    checksum: dict[str, Json],
    planned_checksum: dict[str, Json],
    bodies: dict[str, bytes] | None = None,
    prefetches: dict[str, str] | None = None,
) -> Scenario:
    """mops-bin's pin at an older version, with its single `file` artifact checked by `checksum`."""
    pin: dict[str, Json] = {
        "name": "mops-bin",
        "version": "0.0.1",
        "realizedVersion": "0.0.1",
        "source": {"githubRelease": {"owner": "caffeinelabs", "repo": "mops", "tagTemplate": "cli-v{version}"}},
        "artifacts": {
            "cli": {
                "file": {
                    "urlTemplate": "https://github.com/caffeinelabs/mops/releases/download/{tag}/cli.tgz",
                    "checksum": checksum,
                    "hash": STALE_SRI,
                }
            }
        },
        "companions": [],
    }
    plan: dict[str, Json] = {
        "version": "3.9.0",
        "tag": "cli-v3.9.0",
        "artifacts": {"cli": {"file": {"url": FILE_URL, "checksum": planned_checksum}}},
    }
    files = {pin_path("mops-bin"): (json.dumps(pin, indent=2) + "\n").encode()}
    for path, data in files.items():
        (root / path).parent.mkdir(parents=True, exist_ok=True)
        _ = (root / path).write_bytes(data)
    return Scenario(
        root=root,
        package="mops-bin",
        version="3.9.0",
        http=FakeHttp(bodies or {}),
        nix=FakeNix(root, {"3.9.0": plan}, prefetches or {}),
        hasher=FakeHasher({}),
        skills=FakeSkillHasher({}),
        git=FakeGit(root, files),
        clock=Clock(),
    )


def _sums_scenario(root: Path, sums: bytes) -> Scenario:
    return _file_scenario(
        root,
        {"upstreamFile": {"urlTemplate": "{url}.sha256", "format": {"sha256sum": {}}}},
        {"upstreamFile": {"url": FILE_SUMS, "format": {"sha256sum": {"asset": "cli.tgz"}}}},
        bodies={FILE_SUMS: sums},
    )


def test_file_hash_from_a_prefetch(tmp_path: Path) -> None:
    s = _file_scenario(tmp_path, {"prefetch": {}}, {"prefetch": {}}, prefetches={FILE_URL: EMPTY_SRI})
    result = s.run()
    assert result.is_ok(), result.error.render() if result.is_error() else ""
    assert result.ok.changed == (pin_path("mops-bin"),)
    doc = json.loads((tmp_path / pin_path("mops-bin")).read_text())
    assert doc["version"] == "3.9.0"
    assert doc["artifacts"]["cli"]["file"]["hash"] == EMPTY_SRI
    assert doc["artifacts"]["cli"]["file"]["checksum"] == {"prefetch": {}}
    assert s.http.requests == []


def test_file_hash_from_a_checksum_file(tmp_path: Path) -> None:
    s = _sums_scenario(tmp_path, f"{EMPTY_HEX}  cli.tgz\n".encode())
    result = s.run()
    assert result.is_ok(), result.error.render() if result.is_error() else ""
    doc = json.loads((tmp_path / pin_path("mops-bin")).read_text())
    assert doc["version"] == "3.9.0"
    assert doc["artifacts"]["cli"]["file"]["hash"] == EMPTY_SRI
    assert s.http.requests == [("GET", FILE_SUMS)]


def test_file_checksum_without_its_line_restores_the_pin(tmp_path: Path) -> None:
    s = _sums_scenario(tmp_path, f"{EMPTY_HEX}  cli-arm64.tgz\n".encode())
    before = s.tree()
    result = s.run()
    assert result.is_error()
    assert result.error.step == Step.HASH
    assert "cli: " in result.error.message
    assert "no line for cli.tgz" in result.error.message
    assert s.tree() == before


def test_mergify_rewrites_only_its_remote_skill_hash_after_the_fixed_output_hash(tmp_path: Path) -> None:
    s = scenario("mergify-cli-bin", tmp_path, stale(committed("mergify-cli-bin")))
    before = json.loads(s.tree()[SKILLS])
    order: list[str] = []
    s.hasher.on_hash = lambda: order.append("fixedOutputHash")
    s.skills.on_hash = lambda: order.append("remoteSkillHashes")
    result = s.run()
    assert result.is_ok(), result.error.render() if result.is_error() else ""
    assert order == ["fixedOutputHash", "remoteSkillHashes"]
    assert s.skills.calls == [(MERGIFY_SKILL,)]
    after_bytes = s.tree()[SKILLS]
    assert after_bytes == committed("mergify-cli-bin")[SKILLS]
    after = json.loads(after_bytes)
    assert after["names"] == before["names"]
    changed = {k for k in after["remote"].keys() | before["remote"].keys() if after["remote"].get(k) != before["remote"].get(k)}
    assert changed == {MERGIFY_SKILL}
    assert SKILLS in result.ok.changed


def test_remote_skill_missing_from_the_index_restores_every_file(tmp_path: Path) -> None:
    files = stale(committed("mergify-cli-bin"))
    index = json.loads(files[SKILLS])
    del index["remote"][MERGIFY_SKILL]
    files[SKILLS] = (json.dumps(index, indent=2, ensure_ascii=False) + "\n").encode()
    s = scenario("mergify-cli-bin", tmp_path, files)
    before = s.tree()
    result = s.run()
    assert result.is_error()
    assert result.error.step == Step.SKILL_HASH
    assert f"remote records no {MERGIFY_SKILL}" in result.error.message
    assert s.skills.calls == []
    assert s.tree() == before


def test_skill_hasher_error_restores_every_file(tmp_path: Path) -> None:
    s = scenario("mergify-cli-bin", tmp_path, stale(committed("mergify-cli-bin")))
    s.skills.answers = {MERGIFY_SKILL: RuntimeError("builder for apm-skills-compose failed")}
    before = s.tree()
    result = s.run()
    assert result.is_error()
    assert result.error.step == Step.SKILL_HASH
    assert "Mergifyio/mergify-cli: builder for apm-skills-compose failed" in result.error.message
    assert s.tree() == before
