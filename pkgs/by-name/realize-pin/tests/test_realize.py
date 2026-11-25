"""Offline realizations of the stage-1 pins from recorded upstream content (task 3.3)."""

from __future__ import annotations

import json
import re
from dataclasses import dataclass
from pathlib import Path
from urllib.parse import urlsplit

import pytest
from expression import Result

from fakes import FIXTURES, Clock, FakeGit, FakeHasher, FakeHttp, FakeNix
from realize_pin.adapters import TreeFiles
from realize_pin.capabilities import Capabilities, Custom, FodAttr, NpmDeps, Src
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
)
APM = "modules/home/ai/plugins/version-control-and-forge/apm.yml"
HASHES = "pkgs/by-name/apm-skills-compose/hashes.json"
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
    return files


def stale(files: dict[str, bytes]) -> dict[str, bytes]:
    """The same files at an older version: every digest, rev, file value and version moved."""
    out: dict[str, bytes] = {}
    for path, data in files.items():
        text = SRI.sub(STALE_SRI, data.decode()).replace(MERGIFY_REV, "0" * 40)
        if path.endswith("pin.json"):
            doc = json.loads(text)
            doc["version"] = "0.0.1"
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
    git: FakeGit
    clock: Clock

    def capabilities(self) -> Capabilities:
        return Capabilities(http=self.http, nix=self.nix, hasher=self.hasher, git=self.git, files=TreeFiles(self.root))

    def run(self) -> Result[Realization, RealizeError]:
        return realize(self.package, self.version, self.capabilities(), Deadline.start(self.clock))

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
    if package == "mergify-cli-bin":
        remotes["https://github.com/Mergifyio/mergify-cli"] = (d / "ls-remote.txt").read_text()
        answers[("apm-skills-compose", Custom("deps"))] = "sha256-4ELGyWHWhpyAODdyXvNbf4heYCBhwjDiFP6Plgm3Td8="
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

    return Scenario(
        root=root,
        package=package,
        version=version,
        http=FakeHttp(served),
        nix=FakeNix(root, {version: planned}),
        hasher=FakeHasher(answers, ready),
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


DEPS_PIN: dict[str, Json] = {
    "name": "deps-demo",
    "version": "0.0.1",
    "source": {"githubRelease": {"owner": "example", "repo": "deps-demo", "tagTemplate": "v{version}"}},
    "artifacts": {
        "src": {
            "sourceBuild": {
                "fetcher": {"fetchFromGitHub": {"owner": "example", "repo": "deps-demo"}},
                "hash": STALE_SRI,
                "depsHash": {"npm": {"hash": STALE_SRI}},
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


def _deps_scenario(root: Path, npm: str | Exception) -> Scenario:
    files = {pin_path("deps-demo"): (json.dumps(DEPS_PIN, indent=2) + "\n").encode()}
    for path, data in files.items():
        (root / path).parent.mkdir(parents=True, exist_ok=True)
        _ = (root / path).write_bytes(data)

    def ready(package: str, attr: FodAttr) -> str | None:
        """npmDeps unpacks src, so src must already carry its realized hash."""
        source = json.loads((root / pin_path("deps-demo")).read_text())["artifacts"]["src"]["sourceBuild"]
        if attr == NpmDeps() and source["hash"] != DEPS_SRC:
            return f"src is at {source['hash']}"
        return None

    return Scenario(
        root=root,
        package="deps-demo",
        version="1.2.3",
        http=FakeHttp({}),
        nix=FakeNix(root, {"1.2.3": DEPS_PLAN}),
        hasher=FakeHasher({("deps-demo", Src()): DEPS_SRC, ("deps-demo", NpmDeps()): npm}, ready),
        git=FakeGit(root, files),
        clock=Clock(),
    )


def test_source_and_deps_hash_from_the_hasher(tmp_path: Path) -> None:
    s = _deps_scenario(tmp_path, DEPS_GOT)
    result = s.run()
    assert result.is_ok(), result.error.render() if result.is_error() else ""
    doc = json.loads((tmp_path / pin_path("deps-demo")).read_text())
    assert doc["version"] == "1.2.3"
    assert doc["artifacts"]["src"]["sourceBuild"]["hash"] == DEPS_SRC
    assert doc["artifacts"]["src"]["sourceBuild"]["depsHash"]["npm"]["hash"] == DEPS_GOT
    assert s.hasher.calls == [("deps-demo", Src()), ("deps-demo", NpmDeps())]


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
    assert new.pop("version") == "0.55.3"
    assert old.pop("version") == "0.0.1"
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
