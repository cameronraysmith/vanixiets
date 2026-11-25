"""Realize one version of one package pin (design D4, D5)."""

from __future__ import annotations

import hashlib
from collections.abc import Callable, Mapping
from dataclasses import dataclass, field
from enum import StrEnum

from expression import Error, Ok, Result

from realize_pin.capabilities import (
    CargoDeps,
    Capabilities,
    Custom,
    Files,
    FodAttr,
    GoModules,
    Http,
    NpmDeps,
    Sri,
    Src,
    fod_attr_path,
)
from realize_pin.companions import load_json_object, render_json, set_apm_ref, set_in
from realize_pin.digest import checksum_digest, hex_to_sri
from realize_pin.model import (
    ATTR_NAME,
    COMMIT,
    SRI_SHA256,
    ApmRef,
    Artifact,
    CargoDepsHash,
    Companion,
    DepsHash,
    File,
    FileValue,
    FixedOutputHash,
    GitCommit,
    GithubRelease,
    GoDepsHash,
    Json,
    NoDepsHash,
    Npm,
    NpmDepsHash,
    Pin,
    Plan,
    PlanArtifact,
    PlanAsset,
    PlanFetchFromGitHub,
    PlanFile,
    PlanFileValue,
    PlanPlatformBinaries,
    PlanRuntimeFetch,
    PlanUpstreamFile,
    PlatformBinaries,
    Prefetch,
    Pypi,
    RemoteSkillHashes,
    RuntimeFetch,
    SourceBuild,
    VendorJson,
    VendorText,
    file_value_pattern,
    parse_pin,
    parse_plan,
)
from realize_pin.policy import (
    PolicyHttp,
    allowed_hosts,
    allowed_paths,
    check_url,
    pin_path,
    source_url,
)

DEADLINE_SECONDS = 600.0


class Step(StrEnum):
    EVALUATE = "evaluate"
    REV = "resolve rev"
    HASH = "hash artifacts"
    FILE_VALUE = "fileValue"
    PROBE = "runtimeFetch probe"
    APM_REF = "apmRef"
    DEPS_HASH = "depsHash"
    FIXED_OUTPUT_HASH = "fixedOutputHash"
    SKILL_HASH = "remoteSkillHashes"
    WRITE = "write"
    CONFINE = "confine"
    DEADLINE = "deadline"
    RESTORE = "restore"


@dataclass(frozen=True)
class RealizeError:
    package: str
    step: Step
    message: str

    def render(self) -> str:
        return f"realize-pin: {self.package}: {self.step}: {self.message}"


@dataclass(frozen=True)
class Deadline:
    clock: Callable[[], float]
    expires_at: float

    @staticmethod
    def start(clock: Callable[[], float], seconds: float = DEADLINE_SECONDS) -> Deadline:
        return Deadline(clock, clock() + seconds)

    def remaining(self) -> Result[float, str]:
        left = self.expires_at - self.clock()
        if left <= 0:
            return Error(f"the {DEADLINE_SECONDS:.0f} s deadline passed")
        return Ok(left)


def _digest(data: bytes | None) -> str | None:
    return None if data is None else hashlib.sha256(data).hexdigest()


@dataclass
class Journal:
    """Writes confined to `allowed`, each file snapshotted before its first write."""

    files: Files
    allowed: frozenset[str]
    snapshots: dict[str, bytes | None] = field(default_factory=lambda: {})

    def write(self, path: str, data: bytes) -> Result[None, str]:
        if path not in self.allowed:
            return Error(f"refused to write {path}: outside the allowed set")
        if path not in self.snapshots:
            before = self.files.read(path)
            if before.is_error():
                return Error(before.error)
            self.snapshots[path] = before.ok
        return self.files.write(path, data)

    def restore(self) -> list[str]:
        """Put every written file back as it was; return the paths that failed."""
        failed: list[str] = []
        for path, data in self.snapshots.items():
            done = self.files.remove(path) if data is None else self.files.write(path, data)
            if done.is_error():
                failed.append(f"{path}: {done.error}")
        return failed

    def changed(self) -> list[str]:
        changed: list[str] = []
        for path, data in self.snapshots.items():
            now = self.files.read(path)
            if now.is_error() or now.ok != data:
                changed.append(path)
        return sorted(changed)


@dataclass(frozen=True)
class Realization:
    package: str
    version: str
    changed: tuple[str, ...]


@dataclass(frozen=True)
class _Run:
    package: str
    version: str
    caps: Capabilities
    deadline: Deadline
    hosts: frozenset[str]
    http: Http
    journal: Journal

    def fail(self, step: Step, message: str) -> RealizeError:
        return RealizeError(self.package, step, message)

    def timeout(self, step: Step) -> Result[float, RealizeError]:
        left = self.deadline.remaining()
        if left.is_error():
            return Error(self.fail(Step.DEADLINE, f"{left.error} before {step}"))
        return Ok(left.ok)


def realize(package: str, version: str, caps: Capabilities, deadline: Deadline) -> Result[Realization, RealizeError]:
    """Rewrite `package`'s pin and companions for `version`, or change nothing."""
    evaluated = _evaluate(package, version, caps, deadline)
    if evaluated.is_error():
        return Error(evaluated.error)
    pin, plan = evaluated.ok
    allowed = allowed_paths(pin)
    if allowed.is_error():
        return Error(RealizeError(package, Step.EVALUATE, allowed.error))
    hosts = allowed_hosts(pin, plan)
    run = _Run(
        package,
        version,
        caps,
        deadline,
        hosts,
        PolicyHttp(caps.http, hosts),
        Journal(caps.files, allowed.ok),
    )
    baseline = _status_snapshot(run)
    if baseline.is_error():
        return Error(baseline.error)
    applied = _apply(run, pin, plan)
    if applied.is_error():
        return Error(_restored(run, applied.error))
    confined = _confine(run, baseline.ok)
    if confined.is_error():
        return Error(_restored(run, confined.error))
    finished = run.timeout(Step.WRITE)
    if finished.is_error():
        return Error(_restored(run, finished.error))
    return Ok(Realization(package, version, tuple(run.journal.changed())))


def _restored(run: _Run, error: RealizeError) -> RealizeError:
    failed = run.journal.restore()
    if failed:
        return RealizeError(error.package, error.step, f"{error.message}; restore failed for {', '.join(failed)}")
    return error


def _evaluate(package: str, version: str, caps: Capabilities, deadline: Deadline) -> Result[tuple[Pin, Plan], RealizeError]:
    def fail(message: str) -> Result[tuple[Pin, Plan], RealizeError]:
        return Error(RealizeError(package, Step.EVALUATE, message))

    t = deadline.remaining()
    if t.is_error():
        return fail(t.error)
    raw_pin = caps.nix.eval_pin(package, t.ok)
    if raw_pin.is_error():
        return fail(raw_pin.error)
    pin = parse_pin(raw_pin.ok)
    if pin.is_error():
        return fail(pin.error)
    if pin.ok.name != package:
        return fail(f"the pin names {pin.ok.name!r}")
    t = deadline.remaining()
    if t.is_error():
        return fail(t.error)
    raw_plan = caps.nix.eval_plan(package, version, t.ok)
    if raw_plan.is_error():
        return fail(raw_plan.error)
    plan = parse_plan(raw_plan.ok)
    if plan.is_error():
        return fail(plan.error)
    if plan.ok.version != version:
        return fail(f"the plan is for {plan.ok.version!r}, not {version!r}")
    if set(plan.ok.artifacts) != set(pin.ok.artifacts):
        return fail(f"the plan's artifacts {sorted(plan.ok.artifacts)} differ from the pin's {sorted(pin.ok.artifacts)}")
    return Ok((pin.ok, plan.ok))


def _content_digests(run: _Run, paths: frozenset[str]) -> Result[dict[str, str | None], RealizeError]:
    digests: dict[str, str | None] = {}
    for path in sorted(paths):
        data = run.caps.files.read(path)
        if data.is_error():
            return Error(run.fail(Step.CONFINE, data.error))
        digests[path] = _digest(data.ok)
    return Ok(digests)


def _status_snapshot(run: _Run) -> Result[dict[str, str | None], RealizeError]:
    """Each path git lists as changed before any write, with its content digest."""
    t = run.timeout(Step.CONFINE)
    if t.is_error():
        return Error(t.error)
    changed = run.caps.git.changed_paths(t.ok)
    if changed.is_error():
        return Error(run.fail(Step.CONFINE, changed.error))
    return _content_digests(run, changed.ok)


def _confine(run: _Run, baseline: Mapping[str, str | None]) -> Result[None, RealizeError]:
    """Fail on any path outside the allowed set that is newly changed or whose content moved."""
    t = run.timeout(Step.CONFINE)
    if t.is_error():
        return Error(t.error)
    changed = run.caps.git.changed_paths(t.ok)
    if changed.is_error():
        return Error(run.fail(Step.CONFINE, changed.error))
    candidates = (changed.ok | frozenset(baseline)) - run.journal.allowed
    now = _content_digests(run, candidates)
    if now.is_error():
        return Error(now.error)
    strays = sorted(p for p in candidates if p not in baseline or now.ok[p] != baseline[p])
    if strays:
        return Error(run.fail(Step.CONFINE, f"changed outside the allowed set: {', '.join(strays)}"))
    return Ok(None)


def _apply(run: _Run, pin: Pin, plan: Plan) -> Result[None, RealizeError]:
    rev = _resolve_rev(run, pin, plan)
    if rev.is_error():
        return Error(rev.error)
    pin_doc = _read_object(run, pin_path(pin.name), Step.WRITE)
    if pin_doc.is_error():
        return Error(pin_doc.error)
    doc = pin_doc.ok
    doc["version"] = run.version
    if rev.ok is not None:
        doc["rev"] = rev.ok
    written = _write_object(run, pin_path(pin.name), doc)
    if written.is_error():
        return Error(written.error)
    for name, artifact in pin.artifacts.items():
        realized = _realize_artifact(run, name, artifact, plan)
        if realized.is_error():
            return Error(realized.error)
        for path, value in realized.ok:
            done = set_in(doc, ("artifacts", name, *path), value)
            if done.is_error():
                return Error(run.fail(Step.HASH, done.error))
        written = _write_object(run, pin_path(pin.name), doc)
        if written.is_error():
            return Error(written.error)
    for companion in pin.companions:
        match companion.kind:
            case ApmRef(git=git):
                done = _write_apm_ref(run, companion.path, git, rev.ok)
                if done.is_error():
                    return Error(done.error)
            case FixedOutputHash() | RemoteSkillHashes():
                pass
    for name, artifact in pin.artifacts.items():
        match artifact:
            case SourceBuild(deps_hash=deps):
                done = _realize_deps_hash(run, pin.name, doc, name, deps)
                if done.is_error():
                    return Error(done.error)
            case PlatformBinaries() | FileValue() | RuntimeFetch() | File():
                pass
    for companion in pin.companions:
        match companion.kind:
            case FixedOutputHash():
                done = _realize_fixed_output_hash(run, companion, companion.kind)
                if done.is_error():
                    return Error(done.error)
            case ApmRef() | RemoteSkillHashes():
                pass
    # After every fixedOutputHash: the compose these hashes come from builds
    # from the apm.yml refs and the apmDepsHash written above.
    for companion in pin.companions:
        match companion.kind:
            case RemoteSkillHashes():
                done = _realize_remote_skill_hashes(run, companion, companion.kind)
                if done.is_error():
                    return Error(done.error)
            case ApmRef() | FixedOutputHash():
                pass
    # The final write: checks.<system>.pin-realized fails any pin whose
    # realizedVersion differs from its version, so a run that stops before
    # this point, restored or not, never leaves the new version marked realized.
    doc["realizedVersion"] = run.version
    return _write_object(run, pin_path(pin.name), doc)


def _resolve_rev(run: _Run, pin: Pin, plan: Plan) -> Result[str | None, RealizeError]:
    """The `rev` to write: the release tag's commit, preferring the peeled line of an annotated tag.

    A gitCommit pin's version is its commit, so the version must be one, and no `rev` is written.
    """
    match pin.source:
        case GitCommit():
            if COMMIT.fullmatch(run.version) is None:
                return Error(run.fail(Step.REV, f"{run.version!r} is not a 40-character commit"))
            return Ok(None)
        case GithubRelease():
            if pin.rev is None:
                return Ok(None)
            tag = plan.tag
            if tag is None:
                return Error(run.fail(Step.REV, "the plan has no tag"))
            t = run.timeout(Step.REV)
            if t.is_error():
                return Error(t.error)
            peeled = f"refs/tags/{tag}^{{}}"
            plain = f"refs/tags/{tag}"
            listed = run.caps.git.ls_remote(source_url(pin.source), (peeled, plain), t.ok)
            if listed.is_error():
                return Error(run.fail(Step.REV, listed.error))
            refs: dict[str, str] = {}
            for line in listed.ok.splitlines():
                fields = line.split("\t")
                if len(fields) == 2:
                    refs[fields[1]] = fields[0]
            rev = refs.get(peeled) or refs.get(plain)
            if rev is None or COMMIT.fullmatch(rev) is None:
                return Error(run.fail(Step.REV, f"git ls-remote lists no commit for {plain}"))
            return Ok(rev)
        case Npm() | Pypi() | VendorJson() | VendorText():
            if pin.rev is None:
                return Ok(None)
            return Error(run.fail(Step.REV, "rev needs a githubRelease source"))


type _Writes = list[tuple[tuple[str, ...], str]]


def _plan_kind(planned: PlanArtifact) -> str:
    match planned:
        case PlanPlatformBinaries():
            return "platformBinaries"
        case PlanFetchFromGitHub():
            return "sourceBuild"
        case PlanFileValue():
            return "fileValue"
        case PlanRuntimeFetch():
            return "runtimeFetch"
        case PlanFile():
            return "file"


def _mismatch(run: _Run, name: str, planned: PlanArtifact, pinned: str) -> RealizeError:
    return run.fail(Step.HASH, f"{name}: the plan has {_plan_kind(planned)} where the pin has {pinned}")


def _realize_artifact(run: _Run, name: str, artifact: Artifact, plan: Plan) -> Result[_Writes, RealizeError]:
    """The values to write under the pin's `artifacts.<name>` for the planned version."""
    planned = plan.artifacts[name]
    match artifact:
        case PlatformBinaries(platforms=platforms):
            match planned:
                case PlanPlatformBinaries(platforms=planned_platforms):
                    if set(planned_platforms) != set(platforms):
                        return Error(
                            run.fail(Step.HASH, f"{name}: plan systems {sorted(planned_platforms)} differ from pin systems {sorted(platforms)}")
                        )
                    hashes: _Writes = []
                    for system in sorted(planned_platforms):
                        sri = _hash_asset(run, f"{name}.{system}", planned_platforms[system])
                        if sri.is_error():
                            return Error(sri.error)
                        hashes.append((("platformBinaries", "hashes", system), sri.ok))
                    return Ok(hashes)
                case _:
                    return Error(_mismatch(run, name, planned, "platformBinaries"))
        case SourceBuild():
            match planned:
                case PlanFetchFromGitHub():
                    attr = _source_attr(name)
                    if attr.is_error():
                        return Error(run.fail(Step.HASH, attr.error))
                    got = _fod_hash(run, Step.HASH, run.package, attr.ok)
                    if got.is_error():
                        return Error(got.error)
                    return Ok([(("sourceBuild", "hash"), got.ok)])
                case _:
                    return Error(_mismatch(run, name, planned, "sourceBuild"))
        case FileValue():
            match planned:
                case PlanFileValue(url=url, regex=regex):
                    value = _file_value(run, name, url, regex)
                    if value.is_error():
                        return Error(value.error)
                    return Ok([(("fileValue", "value"), value.ok)])
                case _:
                    return Error(_mismatch(run, name, planned, "fileValue"))
        case RuntimeFetch():
            match planned:
                case PlanRuntimeFetch(probe_url=url):
                    probed = _probe(run, name, url)
                    if probed.is_error():
                        return Error(probed.error)
                    return Ok([])
                case _:
                    return Error(_mismatch(run, name, planned, "runtimeFetch"))
        case File():
            match planned:
                case PlanFile(asset=asset):
                    sri = _hash_asset(run, name, asset)
                    if sri.is_error():
                        return Error(sri.error)
                    return Ok([(("file", "hash"), sri.ok)])
                case _:
                    return Error(_mismatch(run, name, planned, "file"))


def _file_value(run: _Run, name: str, url: str, regex: str) -> Result[str, RealizeError]:
    """The one group `regex` captures from the whole body at `url`."""
    pattern = file_value_pattern(regex, f"{name}.fileValue.regex")
    if pattern.is_error():
        return Error(run.fail(Step.FILE_VALUE, pattern.error))
    t = run.timeout(Step.FILE_VALUE)
    if t.is_error():
        return Error(t.error)
    body = run.http.request("GET", url, t.ok)
    if body.is_error():
        return Error(run.fail(Step.FILE_VALUE, f"{name}: {body.error}"))
    try:
        text = body.ok.decode("utf-8")
    except UnicodeDecodeError as e:
        return Error(run.fail(Step.FILE_VALUE, f"{name}: {url} is not UTF-8: {e}"))
    matched = pattern.ok.fullmatch(text)
    if matched is None:
        return Error(run.fail(Step.FILE_VALUE, f"{name}: the body of {url} does not match {regex!r}: {text[:80]!r}"))
    value = matched.group(1)
    if not value:
        return Error(run.fail(Step.FILE_VALUE, f"{name}: {regex!r} captured an empty value from {url}"))
    return Ok(value)


def _probe(run: _Run, name: str, url: str) -> Result[None, RealizeError]:
    """A runtime-fetched artifact has no hash; the version exists when its probe URL answers."""
    t = run.timeout(Step.PROBE)
    if t.is_error():
        return Error(t.error)
    body = run.http.request("GET", url, t.ok)
    if body.is_error():
        return Error(run.fail(Step.PROBE, f"{name}: {run.version} not found: {body.error}"))
    return Ok(None)


def _hash_asset(run: _Run, where: str, asset: PlanAsset) -> Result[str, RealizeError]:
    match asset.checksum:
        case PlanUpstreamFile(url=url, format=fmt):
            t = run.timeout(Step.HASH)
            if t.is_error():
                return Error(t.error)
            body = run.http.request("GET", url, t.ok)
            if body.is_error():
                return Error(run.fail(Step.HASH, f"{where}: {body.error}"))
            hex_digest = checksum_digest(body.ok, fmt)
            if hex_digest.is_error():
                return Error(run.fail(Step.HASH, f"{where}: {url}: {hex_digest.error}"))
            sri = hex_to_sri(hex_digest.ok)
            if sri.is_error():
                return Error(run.fail(Step.HASH, f"{where}: {url}: {sri.error}"))
            return Ok(sri.ok)
        case Prefetch():
            return _prefetch(run, where, asset.url)


def _prefetch(run: _Run, where: str, url: str) -> Result[str, RealizeError]:
    checked = check_url(url, run.hosts)
    if checked.is_error():
        return Error(run.fail(Step.HASH, f"{where}: {checked.error}"))
    t = run.timeout(Step.HASH)
    if t.is_error():
        return Error(t.error)
    sri = run.caps.nix.prefetch(url, t.ok)
    if sri.is_error():
        return Error(run.fail(Step.HASH, f"{where}: {sri.error}"))
    if SRI_SHA256.fullmatch(sri.ok) is None:
        return Error(run.fail(Step.HASH, f"{where}: prefetch returned {sri.ok!r}"))
    return Ok(sri.ok)


def _read_object(run: _Run, path: str, step: Step) -> Result[dict[str, Json], RealizeError]:
    data = run.caps.files.read(path)
    if data.is_error():
        return Error(run.fail(step, data.error))
    if data.ok is None:
        return Error(run.fail(step, f"{path} does not exist"))
    doc = load_json_object(data.ok, path)
    if doc.is_error():
        return Error(run.fail(step, doc.error))
    return Ok(doc.ok)


def _write_object(run: _Run, path: str, doc: dict[str, Json]) -> Result[None, RealizeError]:
    done = run.journal.write(path, render_json(doc))
    if done.is_error():
        return Error(run.fail(Step.WRITE, done.error))
    return Ok(None)


def _write_apm_ref(run: _Run, path: str, git: str, rev: str | None) -> Result[None, RealizeError]:
    if rev is None:
        return Error(run.fail(Step.APM_REF, f"{path}: an apmRef companion needs the pin's rev"))
    data = run.caps.files.read(path)
    if data.is_error():
        return Error(run.fail(Step.APM_REF, data.error))
    if data.ok is None:
        return Error(run.fail(Step.APM_REF, f"{path} does not exist"))
    edited = set_apm_ref(data.ok.decode("utf-8"), git, rev)
    if edited.is_error():
        return Error(run.fail(Step.APM_REF, f"{path}: {edited.error}"))
    done = run.journal.write(path, edited.ok.encode("utf-8"))
    if done.is_error():
        return Error(run.fail(Step.APM_REF, done.error))
    return Ok(None)


def _fod_hash(run: _Run, step: Step, package: str, attr: FodAttr) -> Result[Sri, RealizeError]:
    """The hash of `package`'s fixed-output derivation `attr`, from the hasher."""
    t = run.timeout(step)
    if t.is_error():
        return Error(t.error)
    got = run.caps.hasher.hash(package, attr, t.ok)
    if got.is_error():
        return Error(run.fail(step, f"{package}.{fod_attr_path(attr)}: {got.error}"))
    return Ok(got.ok)


def _source_attr(name: str) -> Result[FodAttr, str]:
    if name == "src":
        return Ok(Src())
    if ATTR_NAME.fullmatch(name) is None:
        return Error(f"artifact {name!r} is not an attribute name")
    return Ok(Custom(name))


def _deps_attr(deps: DepsHash) -> tuple[str, FodAttr] | None:
    match deps:
        case NpmDepsHash():
            return ("npm", NpmDeps())
        case CargoDepsHash():
            return ("cargo", CargoDeps())
        case GoDepsHash():
            return ("go", GoModules())
        case NoDepsHash():
            return None


def _realize_deps_hash(run: _Run, package: str, doc: dict[str, Json], name: str, deps: DepsHash) -> Result[None, RealizeError]:
    target = _deps_attr(deps)
    if target is None:
        return Ok(None)
    tag, attr = target
    got = _fod_hash(run, Step.DEPS_HASH, package, attr)
    if got.is_error():
        return Error(got.error)
    done = set_in(doc, ("artifacts", name, "sourceBuild", "depsHash", tag, "hash"), got.ok)
    if done.is_error():
        return Error(run.fail(Step.DEPS_HASH, done.error))
    return _write_object(run, pin_path(package), doc)


def _realize_fixed_output_hash(run: _Run, companion: Companion, kind: FixedOutputHash) -> Result[None, RealizeError]:
    loaded = _read_object(run, companion.path, Step.FIXED_OUTPUT_HASH)
    if loaded.is_error():
        return Error(loaded.error)
    got = _fod_hash(run, Step.FIXED_OUTPUT_HASH, kind.package, Custom(kind.fod_attr))
    if got.is_error():
        return Error(got.error)
    doc = loaded.ok
    doc[kind.attr] = got.ok
    return _write_object(run, companion.path, doc)


def _realize_remote_skill_hashes(run: _Run, companion: Companion, kind: RemoteSkillHashes) -> Result[None, RealizeError]:
    """Rewrite `remote.<skill>` for each of `kind.skills`; never add or remove a skill."""
    loaded = _read_object(run, companion.path, Step.SKILL_HASH)
    if loaded.is_error():
        return Error(loaded.error)
    doc = loaded.ok
    remote = doc.get("remote")
    if not isinstance(remote, dict):
        return Error(run.fail(Step.SKILL_HASH, f"{companion.path}: remote is not an object"))
    missing = [skill for skill in kind.skills if skill not in remote]
    if missing:
        return Error(
            run.fail(
                Step.SKILL_HASH,
                f"{companion.path}: remote records no {', '.join(missing)}; "
                + "a new remote skill is a reviewed change made with `just agents-skills-index`",
            )
        )
    t = run.timeout(Step.SKILL_HASH)
    if t.is_error():
        return Error(t.error)
    got = run.caps.skills.hash(kind.skills, t.ok)
    if got.is_error():
        return Error(run.fail(Step.SKILL_HASH, f"{kind.git}: {got.error}"))
    for skill in kind.skills:
        sri = got.ok.get(skill)
        if sri is None:
            return Error(run.fail(Step.SKILL_HASH, f"{kind.git}: no hash for skill {skill}"))
        done = set_in(doc, ("remote", skill), sri)
        if done.is_error():
            return Error(run.fail(Step.SKILL_HASH, done.error))
    return _write_object(run, companion.path, doc)
