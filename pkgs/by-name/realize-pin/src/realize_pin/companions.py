"""Edits of the companion kinds (design D3) and of the pin and JSON companion documents."""

from __future__ import annotations

import json
import re

from expression import Error, Ok, Result

from realize_pin.model import Json

_ITEM_START = re.compile(r"\s*-\s")


def render_json(document: Json) -> bytes:
    """Serialize a JSON document the way every pin and hash file is committed."""
    return (json.dumps(document, indent=2, ensure_ascii=False) + "\n").encode("utf-8")


def load_json_object(data: bytes, where: str) -> Result[dict[str, Json], str]:
    try:
        document: Json = json.loads(data.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError) as e:
        return Error(f"{where} is not JSON: {e}")
    if not isinstance(document, dict):
        return Error(f"{where} is not a JSON object")
    return Ok(document)


def set_apm_ref(text: str, git: str, rev: str) -> Result[str, str]:
    """Set the `ref:` of the apm.yml dependency whose `git:` is `git` to `rev`.

    The `ref:` line must belong to the same list item: it is searched for after
    the `git:` line and before the next item starts or the indentation drops.
    """
    lines = text.splitlines(keepends=True)
    git_line = re.compile(r"(\s*)(-\s+)?git:\s*" + re.escape(git) + r"\s*")
    for i, line in enumerate(lines):
        m = git_line.fullmatch(line.rstrip("\n"))
        if m is None:
            continue
        indent = len(m.group(1)) + len(m.group(2) or "")
        for j in range(i + 1, len(lines)):
            candidate = lines[j]
            stripped = candidate.lstrip(" ")
            if not stripped.strip() or stripped.startswith("#"):
                continue
            if _ITEM_START.match(candidate) or len(candidate) - len(stripped) < indent:
                break
            ref = re.fullmatch(r"(\s*ref:\s*)\S+(\s*)", candidate)
            if ref is not None:
                lines[j] = ref.group(1) + rev + ref.group(2)
                return Ok("".join(lines))
        return Error(f"the entry git: {git} has no ref: line")
    return Error(f"no entry git: {git}")


def set_in(document: dict[str, Json], path: tuple[str, ...], value: str) -> Result[None, str]:
    """Set the string at `path` in `document`; every intermediate must be an object."""
    node: dict[str, Json] = document
    for key in path[:-1]:
        child = node.get(key)
        if not isinstance(child, dict):
            return Error(f"{'.'.join(path)}: {key} is not an object")
        node = child
    node[path[-1]] = value
    return Ok(None)
