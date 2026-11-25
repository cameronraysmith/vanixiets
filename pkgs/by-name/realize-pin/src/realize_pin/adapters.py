"""Real capabilities: urllib for Http, the nix, nix-update and git executables, the repository tree.

Child processes get an environment reduced to `_PASSED_ENV`, so a token in the
caller's environment never reaches nix or git, and urllib is built without the
environment's proxy settings.
"""

from __future__ import annotations

import json
import os
import subprocess
import tempfile
import time
import urllib.error
import urllib.request
from collections.abc import Mapping
from dataclasses import dataclass
from pathlib import Path
from typing import override

from expression import Error, Ok, Result

from realize_pin.capabilities import (
    CargoDeps,
    Custom,
    Files,
    FixedOutputHasher,
    FodAttr,
    Git,
    GoModules,
    Http,
    Method,
    Nix,
    NpmDeps,
    SkillHasher,
    Sri,
    Src,
    fod_attr_path,
    sri,
)
from realize_pin.model import Json

_PASSED_ENV = (
    "PATH",
    "HOME",
    "TMPDIR",
    "LANG",
    "LC_ALL",
    "NIX_REMOTE",
    "NIX_SSL_CERT_FILE",
    "SSL_CERT_FILE",
    "XDG_CACHE_HOME",
    "XDG_CONFIG_HOME",
    "XDG_DATA_HOME",
    "XDG_STATE_HOME",
)
_MAX_BODY = 16 * 1024 * 1024
_NIX_FLAGS = ("--extra-experimental-features", "nix-command flakes", "--option", "access-tokens", "")


def child_env() -> dict[str, str]:
    env = {name: os.environ[name] for name in _PASSED_ENV if name in os.environ}
    env["GIT_TERMINAL_PROMPT"] = "0"
    return env


@dataclass(frozen=True)
class _Ran:
    code: int
    stdout: bytes
    stderr: str


def _run(argv: tuple[str, ...], cwd: Path, timeout: float) -> Result[_Ran, str]:
    try:
        done = subprocess.run(argv, cwd=cwd, env=child_env(), capture_output=True, timeout=timeout, check=False)
    except subprocess.TimeoutExpired:
        return Error(f"{argv[0]} {argv[1]} ran past the deadline")
    except OSError as e:
        return Error(f"{argv[0]}: {e}")
    return Ok(_Ran(done.returncode, done.stdout, done.stderr.decode("utf-8", "replace")))


def _tail(text: str, lines: int = 20) -> str:
    return "\n".join(text.strip().splitlines()[-lines:])


def _output(argv: tuple[str, ...], root: Path, deadline: float, what: str) -> Result[str, str]:
    """The stripped stdout of `argv`, run in `root` with the time left before `deadline` (monotonic)."""
    ran = _run(argv, root, max(deadline - time.monotonic(), 0.001))
    if ran.is_error():
        return Error(ran.error)
    if ran.ok.code != 0:
        return Error(f"{what}: {_tail(ran.ok.stderr)}")
    return Ok(ran.ok.stdout.decode().strip())


def parse_porcelain(output: bytes) -> frozenset[str]:
    """Paths of `git status --porcelain=v1 -z`, including a rename's source."""
    paths: set[str] = set()
    entries = output.decode("utf-8", "surrogateescape").split("\0")
    i = 0
    while i < len(entries):
        entry = entries[i]
        i += 1
        if len(entry) < 4:
            continue
        paths.add(entry[3:])
        if entry[0] in "RC" or entry[1] in "RC":
            if i < len(entries) and entries[i]:
                paths.add(entries[i])
            i += 1
    return frozenset(paths)


@dataclass(frozen=True)
class NixCli(Nix):
    root: Path

    def _json(self, argv: tuple[str, ...], timeout: float) -> Result[Json, str]:
        ran = _run(argv, self.root, timeout)
        if ran.is_error():
            return Error(ran.error)
        if ran.ok.code != 0:
            return Error(_tail(ran.ok.stderr))
        try:
            value: Json = json.loads(ran.ok.stdout)
        except json.JSONDecodeError as e:
            return Error(f"nix printed no JSON: {e}")
        return Ok(value)

    @override
    def eval_pin(self, package: str, timeout: float) -> Result[Json, str]:
        return self._json(("nix", "eval", *_NIX_FLAGS, "--json", f".#{package}.passthru.pin"), timeout)

    @override
    def eval_plan(self, package: str, version: str, timeout: float) -> Result[Json, str]:
        apply = f"f: f {json.dumps(version)}"
        return self._json(("nix", "eval", *_NIX_FLAGS, "--json", f".#{package}.passthru.pinPlan", "--apply", apply), timeout)

    @override
    def prefetch(self, url: str, timeout: float) -> Result[str, str]:
        value = self._json(("nix", "store", "prefetch-file", *_NIX_FLAGS, "--json", "--hash-type", "sha256", url), timeout)
        if value.is_error():
            return Error(value.error)
        h = value.ok.get("hash") if isinstance(value.ok, dict) else None
        return Ok(h) if isinstance(h, str) else Error("nix store prefetch-file printed no hash")


def nix_update_selection(attr: FodAttr) -> tuple[str, ...]:
    """nix-update flags that recompute only `attr`'s hash."""
    match attr:
        case Src():
            return ("--src-only",)
        case CargoDeps() | GoModules() | NpmDeps():
            return ("--no-src",)
        case Custom(name=name):
            return ("--no-src", "--custom-dep", name)


@dataclass(frozen=True)
class NixUpdateHasher(FixedOutputHasher):
    """Recompute a fixed-output hash with nix-update, which edits no working-tree file.

    nix-update has no print-only mode: it computes the hash by building the
    derivation with an empty `outputHash`, then replaces the current hash with
    it in the file it edits.  `--override-filename` points that edit at a
    scratch file holding only the current hash, which is read back.  The
    scratch file lives in the repository's git directory, outside the working
    tree: nix-update ends by running `git diff` on the edited file's directory
    inside the repository and fails on a path outside it, while git status and
    jj never see the git directory.
    """

    root: Path

    @override
    def hash(self, package: str, attr: FodAttr, timeout: float) -> Result[Sri, str]:
        deadline = time.monotonic() + timeout

        def output(argv: tuple[str, ...], what: str) -> Result[str, str]:
            return _output(argv, self.root, deadline, what)

        target = f"{package}.{fod_attr_path(attr)}"
        current = output(("nix", "eval", *_NIX_FLAGS, "--raw", f".#{target}.outputHash"), f"evaluating {target}.outputHash")
        if current.is_error():
            return Error(current.error)
        system = output(
            ("nix", "eval", *_NIX_FLAGS, "--impure", "--raw", "--expr", "builtins.currentSystem"), "evaluating builtins.currentSystem"
        )
        if system.is_error():
            return Error(system.error)
        git_dir = output(("git", "rev-parse", "--absolute-git-dir"), "locating the git directory")
        if git_dir.is_error():
            return Error(git_dir.error)
        with tempfile.TemporaryDirectory(prefix="realize-pin-", dir=git_dir.ok) as scratch:
            hash_file = Path(scratch) / "hash.json"
            _ = hash_file.write_text(json.dumps({"hash": current.ok}) + "\n")
            argv = (
                "nix-update",
                "--flake",
                "--file",
                str(self.root),
                "--version=skip",
                "--override-filename",
                str(hash_file),
                "--system",
                system.ok,
                "--option",
                "access-tokens",
                "",
                *nix_update_selection(attr),
                package,
            )
            ran = output(argv, "nix-update")
            if ran.is_error():
                return Error(ran.error)
            try:
                written: Json = json.loads(hash_file.read_text())
            except (OSError, json.JSONDecodeError) as e:
                return Error(f"nix-update left no readable hash: {e}")
        value = written.get("hash") if isinstance(written, dict) else None
        if not isinstance(value, str):
            return Error("nix-update left no hash")
        return sri(value)


_UNINDEXED_COMPOSE = "apm-skills-compose.unindexed"


@dataclass(frozen=True)
class ComposeSkillHasher(SkillHasher):
    """Hash installed remote skills from the compose built without its committed index.

    The same computation as `just agents-skills-index` and the compose's tree
    oracle: `nix hash path` of `<out>/.claude/skills/<skill>`.  The build reads
    the working tree, so it sees the `apm.yml` ref and the `apmDepsHash` the
    realizer wrote before it; `passthru.unindexed` skips the index comparison,
    which would otherwise fail on the very hashes being recomputed.
    """

    root: Path

    @override
    def hash(self, skills: tuple[str, ...], timeout: float) -> Result[Mapping[str, Sri], str]:
        deadline = time.monotonic() + timeout
        out = _output(
            ("nix", "build", *_NIX_FLAGS, "--no-link", "--print-out-paths", f".#{_UNINDEXED_COMPOSE}"),
            self.root,
            deadline,
            f"building {_UNINDEXED_COMPOSE}",
        )
        if out.is_error():
            return Error(out.error)
        hashes: dict[str, Sri] = {}
        for skill in skills:
            directory = Path(out.ok) / ".claude" / "skills" / skill
            if not directory.is_dir():
                return Error(f"{_UNINDEXED_COMPOSE} installs no skill {skill}")
            got = _output(("nix", "hash", "path", *_NIX_FLAGS, str(directory)), self.root, deadline, f"hashing {skill}")
            if got.is_error():
                return Error(got.error)
            checked = sri(got.ok)
            if checked.is_error():
                return Error(f"{skill}: {checked.error}")
            hashes[skill] = checked.ok
        return Ok(hashes)


@dataclass(frozen=True)
class GitCli(Git):
    root: Path

    @override
    def ls_remote(self, url: str, refs: tuple[str, ...], timeout: float) -> Result[str, str]:
        ran = _run(("git", "ls-remote", url, *refs), self.root, timeout)
        if ran.is_error():
            return Error(ran.error)
        if ran.ok.code != 0:
            return Error(_tail(ran.ok.stderr))
        return Ok(ran.ok.stdout.decode("utf-8", "replace"))

    @override
    def changed_paths(self, timeout: float) -> Result[frozenset[str], str]:
        ran = _run(("git", "status", "--porcelain=v1", "-z", "--untracked-files=all"), self.root, timeout)
        if ran.is_error():
            return Error(ran.error)
        if ran.ok.code != 0:
            return Error(_tail(ran.ok.stderr))
        return Ok(parse_porcelain(ran.ok.stdout))


@dataclass(frozen=True)
class TreeFiles(Files):
    root: Path

    def _resolve(self, path: str) -> Result[Path, str]:
        target = (self.root / path).resolve()
        if not target.is_relative_to(self.root.resolve()):
            return Error(f"{path} resolves outside the repository")
        return Ok(target)

    @override
    def read(self, path: str) -> Result[bytes | None, str]:
        target = self._resolve(path)
        if target.is_error():
            return Error(target.error)
        try:
            return Ok(target.ok.read_bytes())
        except FileNotFoundError:
            return Ok(None)
        except OSError as e:
            return Error(f"{path}: {e}")

    @override
    def write(self, path: str, data: bytes) -> Result[None, str]:
        target = self._resolve(path)
        if target.is_error():
            return Error(target.error)
        try:
            _ = target.ok.write_bytes(data)
        except OSError as e:
            return Error(f"{path}: {e}")
        return Ok(None)

    @override
    def remove(self, path: str) -> Result[None, str]:
        target = self._resolve(path)
        if target.is_error():
            return Error(target.error)
        try:
            target.ok.unlink(missing_ok=True)
        except OSError as e:
            return Error(f"{path}: {e}")
        return Ok(None)


@dataclass(frozen=True)
class UrllibHttp(Http):
    """HTTPS through urllib, ignoring the environment's proxies; redirects followed."""

    @override
    def request(self, method: Method, url: str, timeout: float) -> Result[bytes, str]:
        opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
        req = urllib.request.Request(url, method=method, headers={"User-Agent": "realize-pin"})
        try:
            with opener.open(req, timeout=timeout) as response:
                body: bytes = response.read(_MAX_BODY + 1)
        except urllib.error.HTTPError as e:
            return Error(f"{method} {url}: HTTP {e.code}")
        except (urllib.error.URLError, OSError) as e:
            return Error(f"{method} {url}: {e}")
        if len(body) > _MAX_BODY:
            return Error(f"{method} {url}: body exceeds {_MAX_BODY} bytes")
        return Ok(body)
