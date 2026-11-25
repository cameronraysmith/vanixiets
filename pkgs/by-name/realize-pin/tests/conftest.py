from __future__ import annotations

import socket

import pytest


class _NoSocket(socket.socket):
    def __init__(self, *args: object, **kwargs: object) -> None:
        raise AssertionError("a test opened a socket")


@pytest.fixture(autouse=True)
def no_network(monkeypatch: pytest.MonkeyPatch) -> None:
    """Every test runs offline: opening a socket fails the test."""
    monkeypatch.setattr(socket, "socket", _NoSocket)
