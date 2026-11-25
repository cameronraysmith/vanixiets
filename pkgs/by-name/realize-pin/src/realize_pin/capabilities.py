"""The capabilities the realizer acts through (design D4).

The entry point passes real implementations (`adapters`); the offline tests pass
fakes.  Every method returns a `Result`, so no exception crosses a capability
boundary.  `timeout` is the seconds left before the realizer's deadline.
"""

from __future__ import annotations

from collections.abc import Mapping
from dataclasses import dataclass
from typing import Literal, NewType, Protocol, runtime_checkable

from expression import Error, Ok, Result

from realize_pin.model import SRI_SHA256, Json

type Method = Literal["GET", "HEAD"]

Sri = NewType("Sri", str)


def sri(text: str) -> Result[Sri, str]:
    """The only constructor of `Sri`: a SHA-256 hash in SRI form."""
    if SRI_SHA256.fullmatch(text) is None:
        return Error(f"{text!r} is not a SHA-256 SRI hash")
    return Ok(Sri(text))


@dataclass(frozen=True)
class Src:
    pass


@dataclass(frozen=True)
class CargoDeps:
    pass


@dataclass(frozen=True)
class GoModules:
    pass


@dataclass(frozen=True)
class NpmDeps:
    pass


@dataclass(frozen=True)
class Custom:
    """A fixed-output derivation reachable as `.#<package>.<name>`."""

    name: str


type FodAttr = Src | CargoDeps | GoModules | NpmDeps | Custom


def fod_attr_path(attr: FodAttr) -> str:
    """The attribute path of the fixed-output derivation on its package."""
    match attr:
        case Src():
            return "src"
        case CargoDeps():
            return "cargoDeps.vendorStaging"
        case GoModules():
            return "goModules"
        case NpmDeps():
            return "npmDeps"
        case Custom(name=name):
            return name


@runtime_checkable
class Http(Protocol):
    def request(self, method: Method, url: str, timeout: float) -> Result[bytes, str]:
        """Send `method` to `url` and return the response body."""
        ...


@runtime_checkable
class Nix(Protocol):
    def eval_pin(self, package: str, timeout: float) -> Result[Json, str]:
        """Evaluate `.#<package>.passthru.pin` to JSON."""
        ...

    def eval_plan(self, package: str, version: str, timeout: float) -> Result[Json, str]:
        """Evaluate `.#<package>.passthru.pinPlan "<version>"` to JSON."""
        ...

    def prefetch(self, url: str, timeout: float) -> Result[str, str]:
        """Add the file at `url` to the store and return its SRI hash."""
        ...


@runtime_checkable
class FixedOutputHasher(Protocol):
    def hash(self, package: str, attr: FodAttr, timeout: float) -> Result[Sri, str]:
        """The hash `.#<package>`'s fixed-output derivation `attr` has in the current tree.

        Writes nothing in the repository: the realizer records the hash itself.
        """
        ...


@runtime_checkable
class SkillHasher(Protocol):
    def hash(self, skills: tuple[str, ...], timeout: float) -> Result[Mapping[str, Sri], str]:
        """The `nix hash path` of each of `skills` as the skill compose installs it from the current tree.

        Builds the compose without its committed skill index, so a skill whose
        recorded hash is stale does not fail the build.  Writes nothing in the
        repository: the realizer records the hashes itself.
        """
        ...


@runtime_checkable
class Git(Protocol):
    def ls_remote(self, url: str, refs: tuple[str, ...], timeout: float) -> Result[str, str]:
        """Return `git ls-remote <url> <refs>` output."""
        ...

    def changed_paths(self, timeout: float) -> Result[frozenset[str], str]:
        """Return the repository-relative paths `git status --porcelain` lists."""
        ...


@runtime_checkable
class Files(Protocol):
    def read(self, path: str) -> Result[bytes | None, str]:
        """Return the content of the repository-relative `path`, or None if absent."""
        ...

    def write(self, path: str, data: bytes) -> Result[None, str]:
        """Replace the content of the repository-relative `path`."""
        ...

    def remove(self, path: str) -> Result[None, str]:
        """Delete the repository-relative `path` if it exists."""
        ...


@dataclass(frozen=True)
class Capabilities:
    http: Http
    nix: Nix
    hasher: FixedOutputHasher
    skills: SkillHasher
    git: Git
    files: Files
