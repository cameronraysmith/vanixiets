"""Frozen dataclasses mirroring the pin type (design D3) and the fetch plan (design D2).

Each union of the Nix type is an `attrTag`, so its JSON form is an object with
exactly one key naming the tag.  The parsers below accept only that form and
reject unknown tags, so every value that reaches the realizer belongs to one
of the closed unions declared here.
"""

from __future__ import annotations

import re
from collections.abc import Callable, Mapping
from dataclasses import dataclass

from expression import Error, Ok, Result

type Json = None | bool | int | float | str | list[Json] | dict[str, Json]

PACKAGE_NAME = re.compile(r"[a-z0-9][a-z0-9-]*")
VERSION = re.compile(r"[0-9A-Za-z][0-9A-Za-z.+_-]*")
COMMIT = re.compile(r"[0-9a-f]{40}")
SRI_SHA256 = re.compile(r"sha256-[A-Za-z0-9+/]{43}=")
ATTR_NAME = re.compile(r"[A-Za-z_][A-Za-z0-9_'-]*")
# A skill's directory name under .claude/skills, so never a path.
SKILL_NAME = re.compile(r"[a-z0-9][a-z0-9-]*")


# source


@dataclass(frozen=True)
class GithubRelease:
    owner: str
    repo: str
    tag_template: str


@dataclass(frozen=True)
class Npm:
    package: str


@dataclass(frozen=True)
class Pypi:
    package: str


@dataclass(frozen=True)
class VendorJson:
    url: str
    pointer: str


@dataclass(frozen=True)
class VendorText:
    url: str
    regex: str


@dataclass(frozen=True)
class GitCommit:
    owner: str
    repo: str
    branch: str


type Source = GithubRelease | Npm | Pypi | VendorJson | VendorText | GitCommit


# checksum


@dataclass(frozen=True)
class Sha256Sum:
    pass


@dataclass(frozen=True)
class JsonPointerTemplate:
    pointer_template: str


type ChecksumFormat = Sha256Sum | JsonPointerTemplate


@dataclass(frozen=True)
class UpstreamFile:
    url_template: str
    format: ChecksumFormat


@dataclass(frozen=True)
class Prefetch:
    pass


type Checksum = UpstreamFile | Prefetch


# depsHash


@dataclass(frozen=True)
class NpmDepsHash:
    hash: str


@dataclass(frozen=True)
class CargoDepsHash:
    hash: str


@dataclass(frozen=True)
class GoDepsHash:
    hash: str


@dataclass(frozen=True)
class NoDepsHash:
    pass


type DepsHash = NpmDepsHash | CargoDepsHash | GoDepsHash | NoDepsHash


# fetcher


@dataclass(frozen=True)
class FetchFromGitHub:
    owner: str
    repo: str


type Fetcher = FetchFromGitHub


# artifacts


@dataclass(frozen=True)
class PlatformBinaries:
    url_template: str
    platforms: Mapping[str, str]
    checksum: Checksum
    hashes: Mapping[str, str]


@dataclass(frozen=True)
class SourceBuild:
    fetcher: Fetcher
    hash: str
    deps_hash: DepsHash


@dataclass(frozen=True)
class FileValue:
    """A string read from a file of the release: the one group `regex` captures from its whole body."""

    url_template: str
    regex: str
    value: str


@dataclass(frozen=True)
class RuntimeFetch:
    """An artifact the program fetches when it runs, so it has no hash; the probe tells whether a version exists."""

    probe_url_template: str


@dataclass(frozen=True)
class File:
    """One release asset that is the same on every platform, with one hash."""

    url_template: str
    checksum: Checksum
    hash: str


type Artifact = PlatformBinaries | SourceBuild | FileValue | RuntimeFetch | File


# companions


@dataclass(frozen=True)
class ApmRef:
    git: str


@dataclass(frozen=True)
class FixedOutputHash:
    package: str
    attr: str
    fod_attr: str


@dataclass(frozen=True)
class RemoteSkillHashes:
    """The installed hash of each of `skills`, the skills the apm.yml entry `git` selects."""

    git: str
    skills: tuple[str, ...]


type CompanionKind = ApmRef | FixedOutputHash | RemoteSkillHashes


@dataclass(frozen=True)
class Companion:
    path: str
    kind: CompanionKind


@dataclass(frozen=True)
class Pin:
    """A package pin; `realized_version` is the version realize-pin last completed, None before its first run."""

    name: str
    version: str
    realized_version: str | None
    source: Source
    artifacts: Mapping[str, Artifact]
    rev: str | None
    companions: tuple[Companion, ...]


# plan


@dataclass(frozen=True)
class PlanSha256Sum:
    asset: str


@dataclass(frozen=True)
class PlanJsonPointer:
    pointer: str


type PlanChecksumFormat = PlanSha256Sum | PlanJsonPointer


@dataclass(frozen=True)
class PlanUpstreamFile:
    url: str
    format: PlanChecksumFormat


type PlanChecksum = PlanUpstreamFile | Prefetch


@dataclass(frozen=True)
class PlanAsset:
    """One planned download: a platform's binary, or a `file` artifact."""

    url: str
    checksum: PlanChecksum


@dataclass(frozen=True)
class PlanPlatformBinaries:
    platforms: Mapping[str, PlanAsset]


@dataclass(frozen=True)
class PlanFetchFromGitHub:
    owner: str
    repo: str
    tag: str


@dataclass(frozen=True)
class PlanFileValue:
    url: str
    regex: str


@dataclass(frozen=True)
class PlanRuntimeFetch:
    probe_url: str


@dataclass(frozen=True)
class PlanFile:
    asset: PlanAsset


type PlanArtifact = PlanPlatformBinaries | PlanFetchFromGitHub | PlanFileValue | PlanRuntimeFetch | PlanFile


@dataclass(frozen=True)
class Plan:
    version: str
    tag: str | None
    artifacts: Mapping[str, PlanArtifact]


# parsing


def _obj(value: Json, where: str) -> Result[dict[str, Json], str]:
    if isinstance(value, dict):
        return Ok(value)
    return Error(f"{where}: expected an object")


def _str(obj: Mapping[str, Json], key: str, where: str) -> Result[str, str]:
    value = obj.get(key)
    if isinstance(value, str):
        return Ok(value)
    return Error(f"{where}.{key}: expected a string")


def _str_map(obj: Mapping[str, Json], key: str, where: str) -> Result[dict[str, str], str]:
    value = obj.get(key)
    if not isinstance(value, dict):
        return Error(f"{where}.{key}: expected an object of strings")
    out: dict[str, str] = {}
    for k, v in value.items():
        if not isinstance(v, str):
            return Error(f"{where}.{key}.{k}: expected a string")
        out[k] = v
    return Ok(out)


def _tag(value: Json, where: str, tags: tuple[str, ...]) -> Result[tuple[str, dict[str, Json]], str]:
    """Split an attrTag value into its single tag and that tag's fields."""
    obj = _obj(value, where)
    if obj.is_error():
        return Error(obj.error)
    keys = list(obj.ok)
    if len(keys) != 1:
        return Error(f"{where}: expected exactly one tag of {', '.join(tags)}, got {keys}")
    tag = keys[0]
    if tag not in tags:
        return Error(f"{where}: unknown tag {tag!r}, expected one of {', '.join(tags)}")
    fields = _obj(obj.ok[tag], f"{where}.{tag}")
    if fields.is_error():
        return Error(fields.error)
    return Ok((tag, fields.ok))


_SOURCE_FIELDS: dict[str, tuple[tuple[str, ...], Callable[[list[str]], Source]]] = {
    "githubRelease": (("owner", "repo", "tagTemplate"), lambda v: GithubRelease(v[0], v[1], v[2])),
    "npm": (("package",), lambda v: Npm(v[0])),
    "pypi": (("package",), lambda v: Pypi(v[0])),
    "vendorJson": (("url", "pointer"), lambda v: VendorJson(v[0], v[1])),
    "vendorText": (("url", "regex"), lambda v: VendorText(v[0], v[1])),
    "gitCommit": (("owner", "repo", "branch"), lambda v: GitCommit(v[0], v[1], v[2])),
}


def parse_source(value: Json) -> Result[Source, str]:
    split = _tag(value, "source", tuple(_SOURCE_FIELDS))
    if split.is_error():
        return Error(split.error)
    tag, f = split.ok
    names, build = _SOURCE_FIELDS[tag]
    values: list[str] = []
    for name in names:
        got = _str(f, name, f"source.{tag}")
        if got.is_error():
            return Error(got.error)
        values.append(got.ok)
    return Ok(build(values))


def parse_checksum(value: Json, where: str) -> Result[Checksum, str]:
    split = _tag(value, where, ("upstreamFile", "prefetch"))
    if split.is_error():
        return Error(split.error)
    tag, f = split.ok
    if tag == "prefetch":
        return Ok(Prefetch())
    w = f"{where}.upstreamFile"
    url = _str(f, "urlTemplate", w)
    if url.is_error():
        return Error(url.error)
    fmt = _tag(f.get("format"), f"{w}.format", ("sha256sum", "jsonPointer"))
    if fmt.is_error():
        return Error(fmt.error)
    fmt_tag, fmt_fields = fmt.ok
    if fmt_tag == "sha256sum":
        return Ok(UpstreamFile(url.ok, Sha256Sum()))
    pointer = _str(fmt_fields, "pointerTemplate", f"{w}.format.jsonPointer")
    if pointer.is_error():
        return Error(pointer.error)
    return Ok(UpstreamFile(url.ok, JsonPointerTemplate(pointer.ok)))


def parse_deps_hash(value: Json, where: str) -> Result[DepsHash, str]:
    split = _tag(value, where, ("npm", "cargo", "go", "none"))
    if split.is_error():
        return Error(split.error)
    tag, f = split.ok
    if tag == "none":
        return Ok(NoDepsHash())
    h = _str(f, "hash", f"{where}.{tag}")
    if h.is_error():
        return Error(h.error)
    deps: dict[str, Callable[[str], DepsHash]] = {"npm": NpmDepsHash, "cargo": CargoDepsHash, "go": GoDepsHash}
    return Ok(deps[tag](h.ok))


def file_value_pattern(regex: str, where: str) -> Result[re.Pattern[str], str]:
    """Compile a `fileValue` regex, which must capture exactly one group."""
    try:
        pattern = re.compile(regex)
    except re.error as e:
        return Error(f"{where}: {regex!r} is not a regular expression: {e}")
    if pattern.groups != 1:
        return Error(f"{where}: {regex!r} captures {pattern.groups} groups, not exactly one")
    return Ok(pattern)


def parse_artifact(value: Json, where: str) -> Result[Artifact, str]:
    split = _tag(value, where, ("platformBinaries", "sourceBuild", "fileValue", "runtimeFetch", "file"))
    if split.is_error():
        return Error(split.error)
    tag, f = split.ok
    w = f"{where}.{tag}"
    if tag == "fileValue":
        url = _str(f, "urlTemplate", w)
        regex = _str(f, "regex", w)
        got = _str(f, "value", w)
        for r in (url, regex, got):
            if r.is_error():
                return Error(r.error)
        pattern = file_value_pattern(regex.ok, f"{w}.regex")
        if pattern.is_error():
            return Error(pattern.error)
        return Ok(FileValue(url.ok, regex.ok, got.ok))
    if tag == "runtimeFetch":
        probe = _str(f, "probeUrlTemplate", w)
        if probe.is_error():
            return Error(probe.error)
        return Ok(RuntimeFetch(probe.ok))
    if tag == "file":
        url = _str(f, "urlTemplate", w)
        h = _str(f, "hash", w)
        for r in (url, h):
            if r.is_error():
                return Error(r.error)
        checksum = parse_checksum(f.get("checksum"), f"{w}.checksum")
        if checksum.is_error():
            return Error(checksum.error)
        return Ok(File(url.ok, checksum.ok, h.ok))
    if tag == "platformBinaries":
        url = _str(f, "urlTemplate", w)
        platforms = _str_map(f, "platforms", w)
        hashes = _str_map(f, "hashes", w)
        checksum = parse_checksum(f.get("checksum"), f"{w}.checksum")
        for r in (url, platforms, hashes):
            if r.is_error():
                return Error(r.error)
        if checksum.is_error():
            return Error(checksum.error)
        if set(platforms.ok) != set(hashes.ok):
            return Error(f"{w}: platforms {sorted(platforms.ok)} and hashes {sorted(hashes.ok)} name different systems")
        return Ok(PlatformBinaries(url.ok, platforms.ok, checksum.ok, hashes.ok))
    fetcher = _tag(f.get("fetcher"), f"{w}.fetcher", ("fetchFromGitHub",))
    if fetcher.is_error():
        return Error(fetcher.error)
    _, ff = fetcher.ok
    owner = _str(ff, "owner", f"{w}.fetcher.fetchFromGitHub")
    repo = _str(ff, "repo", f"{w}.fetcher.fetchFromGitHub")
    h = _str(f, "hash", w)
    for r in (owner, repo, h):
        if r.is_error():
            return Error(r.error)
    deps = parse_deps_hash(f.get("depsHash"), f"{w}.depsHash")
    if deps.is_error():
        return Error(deps.error)
    return Ok(SourceBuild(FetchFromGitHub(owner.ok, repo.ok), h.ok, deps.ok))


def parse_companion(value: Json, where: str) -> Result[Companion, str]:
    obj = _obj(value, where)
    if obj.is_error():
        return Error(obj.error)
    path = _str(obj.ok, "path", where)
    if path.is_error():
        return Error(path.error)
    kind = _tag(obj.ok.get("kind"), f"{where}.kind", ("apmRef", "fixedOutputHash", "remoteSkillHashes"))
    if kind.is_error():
        return Error(kind.error)
    tag, f = kind.ok
    if tag == "apmRef":
        git = _str(f, "git", f"{where}.kind.apmRef")
        if git.is_error():
            return Error(git.error)
        return Ok(Companion(path.ok, ApmRef(git.ok)))
    if tag == "remoteSkillHashes":
        return _parse_remote_skill_hashes(path.ok, f, f"{where}.kind.remoteSkillHashes")
    w = f"{where}.kind.fixedOutputHash"
    package = _str(f, "package", w)
    attr = _str(f, "attr", w)
    fod_attr = _str(f, "fodAttr", w)
    for r in (package, attr, fod_attr):
        if r.is_error():
            return Error(r.error)
    if PACKAGE_NAME.fullmatch(package.ok) is None:
        return Error(f"{w}.package: {package.ok!r} is not a package name")
    if ATTR_NAME.fullmatch(fod_attr.ok) is None:
        return Error(f"{w}.fodAttr: {fod_attr.ok!r} is not an attribute name")
    return Ok(Companion(path.ok, FixedOutputHash(package.ok, attr.ok, fod_attr.ok)))


def _parse_remote_skill_hashes(path: str, f: Mapping[str, Json], w: str) -> Result[Companion, str]:
    git = _str(f, "git", w)
    if git.is_error():
        return Error(git.error)
    raw = f.get("skills")
    if not isinstance(raw, list) or not raw:
        return Error(f"{w}.skills: expected a non-empty list of skill names")
    skills: list[str] = []
    for i, skill in enumerate(raw):
        if not isinstance(skill, str) or SKILL_NAME.fullmatch(skill) is None:
            return Error(f"{w}.skills.{i}: {skill!r} is not a skill name")
        if skill in skills:
            return Error(f"{w}.skills.{i}: {skill!r} is listed twice")
        skills.append(skill)
    return Ok(Companion(path, RemoteSkillHashes(git.ok, tuple(skills))))


def parse_pin(value: Json) -> Result[Pin, str]:
    """Parse the JSON of `passthru.pin` into a `Pin`."""
    obj = _obj(value, "pin")
    if obj.is_error():
        return Error(obj.error)
    o = obj.ok
    name = _str(o, "name", "pin")
    version = _str(o, "version", "pin")
    if name.is_error():
        return Error(name.error)
    if version.is_error():
        return Error(version.error)
    source = parse_source(o.get("source"))
    if source.is_error():
        return Error(source.error)
    raw_artifacts = _obj(o.get("artifacts"), "pin.artifacts")
    if raw_artifacts.is_error():
        return Error(raw_artifacts.error)
    if not raw_artifacts.ok:
        return Error("pin.artifacts: expected at least one artifact")
    artifacts: dict[str, Artifact] = {}
    for key, raw in raw_artifacts.ok.items():
        artifact = parse_artifact(raw, f"pin.artifacts.{key}")
        if artifact.is_error():
            return Error(artifact.error)
        artifacts[key] = artifact.ok
    raw_rev = o.get("rev")
    rev: str | None = None
    if raw_rev is not None:
        if not isinstance(raw_rev, str) or COMMIT.fullmatch(raw_rev) is None:
            return Error("pin.rev: expected a 40-character hexadecimal commit or null")
        rev = raw_rev
    raw_companions = o.get("companions", [])
    if not isinstance(raw_companions, list):
        return Error("pin.companions: expected a list")
    companions: list[Companion] = []
    for i, raw in enumerate(raw_companions):
        companion = parse_companion(raw, f"pin.companions.{i}")
        if companion.is_error():
            return Error(companion.error)
        companions.append(companion.ok)
    raw_realized = o.get("realizedVersion")
    if raw_realized is not None and not isinstance(raw_realized, str):
        return Error("pin.realizedVersion: expected a string or null")
    return Ok(Pin(name.ok, version.ok, raw_realized, source.ok, artifacts, rev, tuple(companions)))


def parse_plan_checksum(value: Json, where: str) -> Result[PlanChecksum, str]:
    split = _tag(value, where, ("upstreamFile", "prefetch"))
    if split.is_error():
        return Error(split.error)
    tag, f = split.ok
    if tag == "prefetch":
        return Ok(Prefetch())
    w = f"{where}.upstreamFile"
    url = _str(f, "url", w)
    if url.is_error():
        return Error(url.error)
    fmt = _tag(f.get("format"), f"{w}.format", ("sha256sum", "jsonPointer"))
    if fmt.is_error():
        return Error(fmt.error)
    fmt_tag, fmt_fields = fmt.ok
    if fmt_tag == "sha256sum":
        asset = _str(fmt_fields, "asset", f"{w}.format.sha256sum")
        if asset.is_error():
            return Error(asset.error)
        return Ok(PlanUpstreamFile(url.ok, PlanSha256Sum(asset.ok)))
    pointer = _str(fmt_fields, "pointer", f"{w}.format.jsonPointer")
    if pointer.is_error():
        return Error(pointer.error)
    return Ok(PlanUpstreamFile(url.ok, PlanJsonPointer(pointer.ok)))


def _parse_plan_asset(value: Json, where: str) -> Result[PlanAsset, str]:
    entry = _obj(value, where)
    if entry.is_error():
        return Error(entry.error)
    url = _str(entry.ok, "url", where)
    if url.is_error():
        return Error(url.error)
    checksum = parse_plan_checksum(entry.ok.get("checksum"), f"{where}.checksum")
    if checksum.is_error():
        return Error(checksum.error)
    return Ok(PlanAsset(url.ok, checksum.ok))


def parse_plan_artifact(value: Json, where: str) -> Result[PlanArtifact, str]:
    split = _tag(value, where, ("platformBinaries", "sourceBuild", "fileValue", "runtimeFetch", "file"))
    if split.is_error():
        return Error(split.error)
    tag, f = split.ok
    w = f"{where}.{tag}"
    if tag == "fileValue":
        url = _str(f, "url", w)
        regex = _str(f, "regex", w)
        for r in (url, regex):
            if r.is_error():
                return Error(r.error)
        pattern = file_value_pattern(regex.ok, f"{w}.regex")
        if pattern.is_error():
            return Error(pattern.error)
        return Ok(PlanFileValue(url.ok, regex.ok))
    if tag == "runtimeFetch":
        probe = _str(f, "probeUrl", w)
        if probe.is_error():
            return Error(probe.error)
        return Ok(PlanRuntimeFetch(probe.ok))
    if tag == "file":
        asset = _parse_plan_asset(f, w)
        if asset.is_error():
            return Error(asset.error)
        return Ok(PlanFile(asset.ok))
    if tag == "platformBinaries":
        platforms: dict[str, PlanAsset] = {}
        for system, raw in f.items():
            asset = _parse_plan_asset(raw, f"{w}.{system}")
            if asset.is_error():
                return Error(asset.error)
            platforms[system] = asset.ok
        return Ok(PlanPlatformBinaries(platforms))
    fetcher = _tag(f, w, ("fetchFromGitHub",))
    if fetcher.is_error():
        return Error(fetcher.error)
    _, ff = fetcher.ok
    fw = f"{w}.fetchFromGitHub"
    owner = _str(ff, "owner", fw)
    repo = _str(ff, "repo", fw)
    tag_value = _str(ff, "tag", fw)
    for r in (owner, repo, tag_value):
        if r.is_error():
            return Error(r.error)
    return Ok(PlanFetchFromGitHub(owner.ok, repo.ok, tag_value.ok))


def parse_plan(value: Json) -> Result[Plan, str]:
    """Parse the JSON of `passthru.pinPlan <version>` into a `Plan`."""
    obj = _obj(value, "plan")
    if obj.is_error():
        return Error(obj.error)
    o = obj.ok
    version = _str(o, "version", "plan")
    if version.is_error():
        return Error(version.error)
    raw_tag = o.get("tag")
    if raw_tag is not None and not isinstance(raw_tag, str):
        return Error("plan.tag: expected a string or null")
    raw_artifacts = _obj(o.get("artifacts"), "plan.artifacts")
    if raw_artifacts.is_error():
        return Error(raw_artifacts.error)
    artifacts: dict[str, PlanArtifact] = {}
    for key, raw in raw_artifacts.ok.items():
        artifact = parse_plan_artifact(raw, f"plan.artifacts.{key}")
        if artifact.is_error():
            return Error(artifact.error)
        artifacts[key] = artifact.ok
    return Ok(Plan(version.ok, raw_tag, artifacts))
