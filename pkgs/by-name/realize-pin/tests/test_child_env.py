"""The child environment: a fixed nixpkgs search path, never the caller's."""

from __future__ import annotations

import pytest

from realize_pin.adapters import child_env


def test_child_env_sets_the_wrapper_nixpkgs_and_drops_the_host_nix_path(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("REALIZE_PIN_NIXPKGS", "/nix/store/0000000000000000000000000000000-source")
    monkeypatch.setenv("NIX_PATH", "nixpkgs=/host/nixpkgs:other=/host/other")
    env = child_env()
    assert env["NIX_PATH"] == "nixpkgs=/nix/store/0000000000000000000000000000000-source"
    assert "REALIZE_PIN_NIXPKGS" not in env


def test_child_env_refuses_to_run_without_the_wrapper_nixpkgs(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.delenv("REALIZE_PIN_NIXPKGS", raising=False)
    monkeypatch.setenv("NIX_PATH", "nixpkgs=/host/nixpkgs")
    with pytest.raises(RuntimeError, match="REALIZE_PIN_NIXPKGS"):
        _ = child_env()
