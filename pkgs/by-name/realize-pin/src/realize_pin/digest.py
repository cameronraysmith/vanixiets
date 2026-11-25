"""Reading a digest out of an upstream checksum file and converting it to SRI."""

from __future__ import annotations

import base64
import json
import re

from expression import Error, Ok, Result

from realize_pin.model import Json, PlanChecksumFormat, PlanJsonPointer, PlanSha256Sum

_HEX = re.compile(r"[0-9a-fA-F]{64}")


def hex_to_sri(hex_digest: str) -> Result[str, str]:
    """Convert a SHA-256 hex digest to its SRI form."""
    if _HEX.fullmatch(hex_digest) is None:
        return Error(f"{hex_digest!r} is not a SHA-256 hex digest")
    return Ok("sha256-" + base64.b64encode(bytes.fromhex(hex_digest)).decode("ascii"))


def sha256sum_digest(text: str, asset: str) -> Result[str, str]:
    """Return the digest of the line naming `asset`, or of a sole bare digest line.

    Lines are `<hex>  <name>` or `<hex> *<name>`.  A file whose only line names a
    different asset is an error rather than that asset's digest.
    """
    lines = [line.split() for line in text.splitlines() if line.strip()]
    for fields in lines:
        if len(fields) >= 2 and fields[1].removeprefix("*") == asset:
            return Ok(fields[0])
    if len(lines) == 1 and len(lines[0]) == 1:
        return Ok(lines[0][0])
    return Error(f"no line for {asset}")


def json_pointer(document: Json, pointer: str) -> Result[Json, str]:
    """Resolve an RFC 6901 pointer in `document`."""
    if pointer == "":
        return Ok(document)
    if not pointer.startswith("/"):
        return Error(f"pointer {pointer!r} does not start with /")
    node = document
    for raw in pointer[1:].split("/"):
        token = raw.replace("~1", "/").replace("~0", "~")
        if isinstance(node, dict):
            if token not in node:
                return Error(f"pointer {pointer!r}: no key {token!r}")
            node = node[token]
        elif isinstance(node, list):
            if not token.isdigit() or int(token) >= len(node):
                return Error(f"pointer {pointer!r}: no index {token!r}")
            node = node[int(token)]
        else:
            return Error(f"pointer {pointer!r}: {token!r} indexes a scalar")
    return Ok(node)


def checksum_digest(body: bytes, fmt: PlanChecksumFormat) -> Result[str, str]:
    """Read the hex digest that `fmt` selects from a checksum file's `body`."""
    try:
        text = body.decode("utf-8")
    except UnicodeDecodeError:
        return Error("checksum file is not UTF-8")
    match fmt:
        case PlanSha256Sum(asset=asset):
            return sha256sum_digest(text, asset)
        case PlanJsonPointer(pointer=pointer):
            try:
                document: Json = json.loads(text)
            except json.JSONDecodeError as e:
                return Error(f"checksum file is not JSON: {e}")
            value = json_pointer(document, pointer)
            if value.is_error():
                return Error(value.error)
            if not isinstance(value.ok, str):
                return Error(f"pointer {pointer!r} names no string")
            return Ok(value.ok)
