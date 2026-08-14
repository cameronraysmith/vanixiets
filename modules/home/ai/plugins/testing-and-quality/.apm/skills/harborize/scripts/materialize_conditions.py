#!/usr/bin/env python3
"""Materialize dir(C): copy exactly the unit folders in C into --dest.

The ONLY sanctioned mechanism for varying conditions (grade discipline).
Refuses to run if dest is inside a task's environment/ in the canonical
package (skills must be injected at runtime, never baked).
"""
import argparse, pathlib, shutil, sys

ap = argparse.ArgumentParser()
ap.add_argument("--skills-root", required=True)
ap.add_argument("--units", nargs="*", default=[])
ap.add_argument("--dest", required=True)
a = ap.parse_args()

root, dest = pathlib.Path(a.skills_root), pathlib.Path(a.dest)
if "environment" in dest.parts:
    sys.exit("refusing: dest is inside environment/ (bake-in violation)")
if dest.exists():
    shutil.rmtree(dest)
dest.mkdir(parents=True)
def skill_dirs(src):
    """A unit is a skill folder (SKILL.md at root) or a plugin: any folder
    whose nested skill folders live under .apm/skills/, skills/, or one
    level down. Plugin units materialize as the union of their skills."""
    if (src / "SKILL.md").is_file():
        return [src]
    found = []
    for base in (src / ".apm" / "skills", src / "skills", src):
        if base.is_dir():
            found = [d for d in sorted(base.iterdir())
                     if (d / "SKILL.md").is_file()]
            if found:
                return found
    return found

for u in a.units:
    ds = skill_dirs(root / u)
    if not ds:
        sys.exit(f"unit {u}: no SKILL.md found at or under {root / u}")
    for d in ds:
        tgt = dest / d.name
        if tgt.exists():
            sys.exit(f"name collision materializing {u}: {d.name} already "
                     f"placed by another unit — resolve before running")
        shutil.copytree(d, tgt)
print(f"dir(C) = {dest} <- {sorted(a.units) or '{}'}")
