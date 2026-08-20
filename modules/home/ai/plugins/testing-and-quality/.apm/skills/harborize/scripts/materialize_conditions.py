#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.12"
# dependencies = []
# ///
"""Materialize dir(C): copy exactly the unit folders in C into --dest.

The only sanctioned mechanism for varying conditions (grade discipline).

A unit is a skill or a plugin. A skill unit is one folder holding a SKILL.md.
A plugin unit is derived: the union of its member skills' folders, resolved
through the skill-name to plugin-name membership map that census.py emits. The
derivation is required because the deployed tree a harness actually reads is
flat -- one directory per skill, no plugin directories and no .apm/ paths --
so a plugin unit has no directory to point at. Source trees that do carry
plugin directories still resolve structurally through .apm/skills/ or skills/.

dir(C) belongs outside the task package, which is what the emitters document
and what the generated manifest does. --dest inside a package is permitted, so
that <task>/environment/skills works the way SkillsBench's own ablation driver
uses it, and is refused when a Dockerfile above it would copy it into an image.
Baking dir(C) into the build context makes the image vary with the condition,
which breaks the runtime on/off toggle and the grade-discipline invariant.

Materializing into <task>/environment/skills commits you to passing that same
path as bench's --skills-dir: benchflow's resolve_task_skill_policy treats the
bundled directory as stale and deletes it whenever a different --skills-dir is
given (benchflow src/benchflow/skill_policy.py).
"""

from __future__ import annotations

import argparse
import fnmatch
import json
import pathlib
import re
import shlex
import shutil
import sys

COPY_RE = re.compile(r"^\s*(?:COPY|ADD)\s+(?P<args>\S.*)$", re.IGNORECASE)


def load_membership(path: pathlib.Path) -> dict[str, str]:
    """Read a skill-name to plugin-name map from census output or a flat map."""
    data = json.loads(path.read_text())
    if not isinstance(data, dict):
        raise SystemExit(f"membership {path}: expected a JSON object")
    mapping: dict[str, str] = {}
    for key in ("membership", "plugin_membership"):
        explicit = data.get(key)
        if isinstance(explicit, dict):
            mapping.update(
                {k: v for k, v in explicit.items() if isinstance(v, str)}
            )
    skills = data.get("skills")
    if isinstance(skills, dict):
        for name, rec in skills.items():
            if isinstance(rec, dict) and isinstance(rec.get("plugin"), str):
                mapping.setdefault(name, rec["plugin"])
    plugins = data.get("plugins")
    if isinstance(plugins, dict):
        for plugin, members in plugins.items():
            if isinstance(members, list):
                for name in members:
                    if isinstance(name, str):
                        mapping.setdefault(name, plugin)
    if not mapping and all(isinstance(v, str) for v in data.values()):
        mapping = dict(data)
    if not mapping:
        raise SystemExit(f"membership {path}: no skill -> plugin mapping found")
    return mapping


def structural_skill_dirs(src: pathlib.Path) -> list[pathlib.Path]:
    """Skill folders nested under a plugin directory in a source-layout tree."""
    for base in (src / ".apm" / "skills", src / "skills", src):
        if base.is_dir():
            found = [d for d in sorted(base.iterdir()) if (d / "SKILL.md").is_file()]
            if found:
                return found
    return []


def derived_plugin_dirs(
    plugin: str, members: list[str], root: pathlib.Path
) -> list[pathlib.Path]:
    dirs, missing = [], []
    for name in members:
        d = root / name
        if (d / "SKILL.md").is_file():
            dirs.append(d)
        else:
            missing.append(name)
    if missing:
        raise SystemExit(
            f"plugin {plugin}: member skills absent from {root}: "
            f"{', '.join(missing)} -- the membership map and --skills-root must "
            f"describe the same tree"
        )
    return dirs


def resolve_unit(
    unit: str, root: pathlib.Path, membership: dict[str, str]
) -> list[pathlib.Path]:
    kind, sep, bare = unit.partition(":")
    if not sep or kind not in ("skill", "plugin"):
        kind, bare = "", unit
    src = root / bare
    as_skill = [src] if (src / "SKILL.md").is_file() else []
    members = sorted(s for s, p in membership.items() if p == bare)

    if kind == "skill":
        if not as_skill:
            raise SystemExit(f"unit {unit}: no SKILL.md at {src}")
        return as_skill
    if kind == "plugin":
        if members:
            return derived_plugin_dirs(bare, members, root)
        found = structural_skill_dirs(src)
        if found:
            return found
        raise SystemExit(
            f"unit {unit}: not a plugin in the membership map and no nested "
            f"SKILL.md under {src}"
        )
    if as_skill and members:
        raise SystemExit(
            f"unit {unit} names both a skill folder ({src}) and a plugin in the "
            f"membership map; disambiguate as skill:{bare} or plugin:{bare}"
        )
    if as_skill:
        return as_skill
    if members:
        return derived_plugin_dirs(bare, members, root)
    found = structural_skill_dirs(src)
    if found:
        return found
    known = f"{len(membership)} skills mapped" if membership else "no map given"
    raise SystemExit(
        f"unit {unit}: no SKILL.md at {src}, not a plugin in the membership map "
        f"({known}), and no nested SKILL.md under {src}"
    )


def _norm(source: str) -> str:
    p = source.strip().strip("\"'")
    while p.startswith("./"):
        p = p[2:]
    return p.rstrip("/")


def _copy_sources(args_text: str) -> list[str]:
    try:
        parts = shlex.split(args_text)
    except ValueError:
        return []
    parts = [p for p in parts if not p.startswith("--")]
    return parts[:-1] if len(parts) >= 2 else []


def _ingests(source: str, rel: str) -> bool:
    s = _norm(source)
    if s in ("", ".", "*"):
        return True
    if any(ch in s for ch in "*?["):
        return fnmatch.fnmatch(rel.split("/")[0], s.split("/")[0])
    return rel == s or rel.startswith(s + "/")


def build_context_conflict(dest: pathlib.Path) -> tuple[pathlib.Path, str] | None:
    """The nearest Dockerfile above dest that would copy dest into an image."""
    target = dest.resolve()
    for parent in target.parents:
        dockerfile = parent / "Dockerfile"
        if not dockerfile.is_file():
            continue
        rel = target.relative_to(parent).as_posix()
        text = re.sub(r"\\\s*\n", " ", dockerfile.read_text(errors="ignore"))
        for line in text.splitlines():
            m = COPY_RE.match(line)
            if m and any(_ingests(s, rel) for s in _copy_sources(m.group("args"))):
                return dockerfile, line.strip()
    return None


def prepare_dest(dest: pathlib.Path) -> None:
    conflict = build_context_conflict(dest)
    if conflict:
        dockerfile, line = conflict
        raise SystemExit(
            f"refusing: {dockerfile} would copy {dest} into the image "
            f"({line!r}); skills must be injected at runtime, never baked"
        )
    if dest.exists():
        stray = [
            e.name
            for e in sorted(dest.iterdir())
            if not (e.is_dir() and (e / "SKILL.md").is_file())
        ]
        if stray:
            raise SystemExit(
                f"refusing to replace {dest}: it holds entries that are not skill "
                f"folders ({', '.join(stray[:5])})"
            )
        shutil.rmtree(dest)
    dest.mkdir(parents=True)


def materialize(
    root: pathlib.Path,
    units: list[str],
    dest: pathlib.Path,
    membership: dict[str, str],
) -> list[pathlib.Path]:
    prepare_dest(dest)
    placed: dict[str, str] = {}
    out: list[pathlib.Path] = []
    for u in units:
        for d in resolve_unit(u, root, membership):
            if d.name in placed:
                raise SystemExit(
                    f"name collision materializing {u}: {d.name} already placed "
                    f"by {placed[d.name]} -- resolve before running"
                )
            placed[d.name] = u
            shutil.copytree(d, dest / d.name)
            out.append(dest / d.name)
    return out


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--skills-root", required=True)
    ap.add_argument("--units", nargs="*", default=[])
    ap.add_argument("--dest", required=True)
    ap.add_argument(
        "--membership",
        help="census.json (or a flat {skill: plugin} map) enabling plugin units "
        "over a flat deployed tree",
    )
    a = ap.parse_args()

    membership = (
        load_membership(pathlib.Path(a.membership)) if a.membership else {}
    )
    dirs = materialize(
        pathlib.Path(a.skills_root), a.units, pathlib.Path(a.dest), membership
    )
    for d in dirs:
        print(d)
    print(
        f"dir(C) = {a.dest} <- {sorted(a.units) or '{}'} [{len(dirs)} skills]",
        file=sys.stderr,
    )


if __name__ == "__main__":
    main()
