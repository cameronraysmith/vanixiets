"""Write the Agent Skills discovery index for a tree of first-party skills.

usage: agent-skills-index.py <plugins-root> <out-dir>

<plugins-root> holds <group>/.apm/skills/<name>/SKILL.md. <out-dir> receives
index.json, <name>/SKILL.md for each skill that is only a SKILL.md, and
<name>.zip for each skill with supporting files, following
cloudflare/agent-skills-discovery-rfc v0.2.0 (README.md "Discovery Index",
"Integrity and Verification", "Archive Distribution").

The output is a function of the files' bytes, relative paths and executable
bits only: entries are sorted, zip members carry one fixed timestamp and a
mode of 0755 or 0644, and the zip is compressed at a fixed level.
"""

import hashlib
import io
import json
import re
import sys
import zipfile
from pathlib import Path

import yaml

SCHEMA = "https://schemas.agentskills.io/discovery/0.2.0/schema.json"
URL_BASE = "/.well-known/agent-skills"
NAME = re.compile(r"^[a-z0-9]+(-[a-z0-9]+)*$")
ZIP_EPOCH = (1980, 1, 1, 0, 0, 0)


def fail(message: str) -> None:
    sys.exit(f"agent-skills-index: {message}")


def frontmatter(skill_md: bytes, where: Path) -> dict:
    text = skill_md.decode("utf-8")
    match = re.match(r"---\n(.*?)\n---\n", text, re.DOTALL)
    if not match:
        fail(f"{where}: no YAML frontmatter")
    data = yaml.safe_load(match.group(1))
    if not isinstance(data, dict):
        fail(f"{where}: frontmatter is not a mapping")
    return data


def skill_files(skill_dir: Path) -> list[Path]:
    files = []
    for path in skill_dir.rglob("*"):
        if path.is_symlink():
            fail(f"{path}: symlinks are not published")
        if path.is_file():
            files.append(path.relative_to(skill_dir))
    return sorted(files, key=lambda p: (p.as_posix() != "SKILL.md", p.as_posix()))


def archive(skill_dir: Path, files: list[Path]) -> bytes:
    buffer = io.BytesIO()
    with zipfile.ZipFile(buffer, "w") as zf:
        for rel in files:
            path = skill_dir / rel
            info = zipfile.ZipInfo(rel.as_posix(), date_time=ZIP_EPOCH)
            info.create_system = 3
            mode = 0o755 if path.stat().st_mode & 0o100 else 0o644
            info.external_attr = (0o100000 | mode) << 16
            info.compress_type = zipfile.ZIP_DEFLATED
            zf.writestr(info, path.read_bytes(), compresslevel=9)
    return buffer.getvalue()


def main(plugins_root: Path, out: Path) -> None:
    skill_dirs = sorted(
        (d for d in plugins_root.glob("*/.apm/skills/*") if d.is_dir()),
        key=lambda d: d.name,
    )
    names = [d.name for d in skill_dirs]
    duplicates = sorted({n for n in names if names.count(n) > 1})
    if duplicates:
        fail(f"skill names in more than one group: {', '.join(duplicates)}")

    out.mkdir(parents=True)
    entries = []
    for skill_dir in skill_dirs:
        name = skill_dir.name
        skill_md = (skill_dir / "SKILL.md").read_bytes()
        meta = frontmatter(skill_md, skill_dir / "SKILL.md")
        if meta.get("name") != name:
            fail(f"{skill_dir}: frontmatter name {meta.get('name')!r} is not the directory name")
        if not NAME.match(name) or len(name) > 64:
            fail(f"{skill_dir}: {name!r} is not an Agent Skills name")
        description = meta.get("description")
        if not isinstance(description, str) or not description.strip():
            fail(f"{skill_dir}: no description")
        description = description.strip()
        if len(description) > 1024:
            fail(f"{skill_dir}: description is {len(description)} characters, over 1024")

        files = skill_files(skill_dir)
        if [f.as_posix() for f in files] == ["SKILL.md"]:
            kind, rel, artifact = "skill-md", f"{name}/SKILL.md", skill_md
        else:
            kind, rel, artifact = "archive", f"{name}.zip", archive(skill_dir, files)
        target = out / rel
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(artifact)
        entries.append(
            {
                "name": name,
                "type": kind,
                "description": description,
                "url": f"{URL_BASE}/{rel}",
                "digest": "sha256:" + hashlib.sha256(artifact).hexdigest(),
            }
        )

    index = {"$schema": SCHEMA, "skills": entries}
    (out / "index.json").write_text(json.dumps(index, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")


if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit(__doc__.split("\n\n")[1])
    main(Path(sys.argv[1]), Path(sys.argv[2]))
