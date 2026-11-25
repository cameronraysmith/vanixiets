"""Pure helpers: digests, companion edits, parsing, confinement, the command line."""

from __future__ import annotations

import json

import pytest

from fakes import FIXTURES
from realize_pin.adapters import nix_update_selection, parse_porcelain
from realize_pin.capabilities import CargoDeps, Custom, GoModules, NpmDeps, Src, sri
from realize_pin.cli import main
from realize_pin.companions import set_apm_ref
from realize_pin.digest import hex_to_sri, json_pointer, sha256sum_digest
from realize_pin.model import Json, parse_pin
from realize_pin.policy import allowed_paths


def _pin(**changes: Json) -> dict[str, Json]:
    doc: Json = json.loads((FIXTURES / "mergify-cli-bin" / "pin.json").read_text())
    assert isinstance(doc, dict)
    doc.update(changes)
    return doc


def test_hex_to_sri_matches_the_committed_hash() -> None:
    sri = hex_to_sri("f6d40d67596fbe91a5f2c2cdbac2ace162305246dd35bcd30e34230e7f91dff8")
    assert sri.is_ok() and sri.ok == "sha256-9tQNZ1lvvpGl8sLNusKs4WIwUkbdNbzTDjQjDn+R3/g="
    assert hex_to_sri("f6d4").is_error()


def test_sha256sum_reads_the_named_line() -> None:
    text = "aa  other.tar.gz\n" + "b" * 64 + " *wanted.tar.gz\n"
    got = sha256sum_digest(text, "wanted.tar.gz")
    assert got.is_ok() and got.ok == "b" * 64
    assert sha256sum_digest(text, "missing.tar.gz").is_error()
    assert sha256sum_digest("c" * 64 + "  other.tar.gz\n", "wanted.tar.gz").is_error()
    bare = sha256sum_digest("c" * 64 + "\n", "wanted.tar.gz")
    assert bare.is_ok() and bare.ok == "c" * 64


def test_json_pointer() -> None:
    doc: Json = {"platforms": {"linux-x64": {"checksum": "abc"}}, "a/b": [1, 2]}
    got = json_pointer(doc, "/platforms/linux-x64/checksum")
    assert got.is_ok() and got.ok == "abc"
    escaped = json_pointer(doc, "/a~1b/1")
    assert escaped.is_ok() and escaped.ok == 2
    assert json_pointer(doc, "/platforms/darwin-arm64/checksum").is_error()


def test_set_apm_ref_moves_only_the_named_entry() -> None:
    text = (FIXTURES / "mergify-cli-bin" / "apm.yml").read_text()
    rev = "1" * 40
    edited = set_apm_ref(text, "Mergifyio/mergify-cli", rev)
    assert edited.is_ok()
    changed = [(a, b) for a, b in zip(text.splitlines(), edited.ok.splitlines(), strict=True) if a != b]
    assert changed == [("      ref: e7c1ebbc281361f0b2b7827cf583f57339c97ebc", f"      ref: {rev}")]
    assert set_apm_ref(text, "nobody/nothing", rev).is_error()


def test_parse_pin_rejects_an_unknown_source_tag() -> None:
    parsed = parse_pin(_pin(source={"gitlabRelease": {"owner": "a", "repo": "b"}}))
    assert parsed.is_error() and "gitlabRelease" in parsed.error


def test_parse_pin_rejects_a_platform_without_a_hash() -> None:
    doc = _pin()
    artifacts = doc["artifacts"]
    assert isinstance(artifacts, dict)
    binaries = artifacts["binaries"]
    assert isinstance(binaries, dict)
    pb = binaries["platformBinaries"]
    assert isinstance(pb, dict)
    hashes = pb["hashes"]
    assert isinstance(hashes, dict)
    del hashes["x86_64-darwin"]
    parsed = parse_pin(doc)
    assert parsed.is_error() and "hashes" in parsed.error


@pytest.mark.parametrize(
    "path",
    [
        "../outside/apm.yml",
        "modules/../pkgs/by-name/x/hashes.json",
        "/etc/passwd",
        "pkgs/by-name/mergify-cli-bin/extra.json",
        "pkgs/by-name/apm-skills-compose/package.nix",
    ],
)
def test_allowed_paths_rejects_companion_paths(path: str) -> None:
    kind: dict[str, Json] = {"package": "apm-skills-compose", "attr": "h", "fodAttr": "deps"}
    doc = _pin(companions=[{"path": path, "kind": {"fixedOutputHash": kind}}])
    pin = parse_pin(doc)
    assert pin.is_ok()
    assert allowed_paths(pin.ok).is_error()


def test_allowed_paths_of_mergify() -> None:
    pin = parse_pin(_pin())
    assert pin.is_ok()
    allowed = allowed_paths(pin.ok)
    assert allowed.is_ok()
    assert allowed.ok == {
        "pkgs/by-name/mergify-cli-bin/pin.json",
        "modules/home/ai/plugins/version-control-and-forge/apm.yml",
        "pkgs/by-name/apm-skills-compose/hashes.json",
    }


def test_parse_porcelain() -> None:
    out = b" M a.txt\0?? dir/new.txt\0R  moved.txt\0original.txt\0"
    assert parse_porcelain(out) == {"a.txt", "dir/new.txt", "moved.txt", "original.txt"}


def test_nix_update_selection() -> None:
    assert nix_update_selection(Src()) == ("--src-only",)
    assert nix_update_selection(NpmDeps()) == ("--no-src",)
    assert nix_update_selection(CargoDeps()) == ("--no-src",)
    assert nix_update_selection(GoModules()) == ("--no-src",)
    assert nix_update_selection(Custom("deps")) == ("--no-src", "--custom-dep", "deps")


def test_sri_accepts_only_sha256_sri() -> None:
    assert sri("sha256-4ELGyWHWhpyAODdyXvNbf4heYCBhwjDiFP6Plgm3Td8=").is_ok()
    assert sri("sha256:4ELGyWHWhpyAODdyXvNbf4heYCBhwjDiFP6Plgm3Td8").is_error()
    assert sri("").is_error()


@pytest.mark.parametrize("fod_attr", [None, "", "passthru.deps", "1deps"])
def test_fixed_output_hash_needs_an_attribute_name(fod_attr: str | None) -> None:
    kind: dict[str, Json] = {"package": "apm-skills-compose", "attr": "apmDepsHash"}
    if fod_attr is not None:
        kind["fodAttr"] = fod_attr
    doc = _pin(companions=[{"path": "pkgs/by-name/apm-skills-compose/hashes.json", "kind": {"fixedOutputHash": kind}}])
    parsed = parse_pin(doc)
    assert parsed.is_error() and "fodAttr" in parsed.error


def test_help_prints_usage(capsys: pytest.CaptureFixture[str]) -> None:
    with pytest.raises(SystemExit) as exited:
        _ = main(["--help"])
    assert exited.value.code == 0
    assert "realize-pin <package> <version>" in capsys.readouterr().out


@pytest.mark.parametrize("args", [["ic-wasm-bin", "1.0.0;id"], ["IC", "1.0.0"], ["ic-wasm-bin"]])
def test_rejects_arguments(args: list[str], capsys: pytest.CaptureFixture[str]) -> None:
    with pytest.raises(SystemExit) as exited:
        _ = main(args)
    assert exited.value.code == 2
    assert "realize-pin <package> <version>" in capsys.readouterr().err
