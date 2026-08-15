#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.12"
# dependencies = []
# ///
"""Marketplace census: a full static pass over every skill in one tree.

Emits a per-skill record set, a skill-to-plugin membership map, and
lexical-overlap rankings used to nominate candidate pairs for interference
conditions.

The census runs over either of two subjects and reports which one it read.
The source tree, laid out as <root>/<group>/.apm/skills/<skill>/SKILL.md, is
the refactor subject.  The deployed tree, a flat <root>/<skill>/SKILL.md, is
the evaluation subject; selection-competition figures must be computed from
it, since the deployed tree carries skills the source tree does not.

A plugin is a derived aggregate unit: the union of its member skills' flat
directories, resolved through the membership map rather than through
directory structure, because the deployed tree has no plugin directories.
For a flat root, pass --membership-from pointing at a source census; skills
absent from it are recorded under the EXTERNAL sentinel rather than dropped
or guessed.

Frontmatter is parsed without a YAML dependency so this script can run inside
a hermetic derivation.  The parser covers plain, single- and double-quoted,
folded (>, >-, >+) and literal (|, |-, |+) scalars, and plain scalars
continued across indented lines.

Usage:
  census.py --root <tree> --out <path.json> [--membership-from <census.json>]
            [--layout auto|nested|flat] [--top-intra N] [--top-inter N]
            [--timestamp ISO8601]
"""

import argparse
import collections
import itertools
import json
import os
import pathlib
import re
import subprocess
import sys

__version__ = "0.2.0"

EXTERNAL = "<external>"
"""Membership value for a skill in the censused tree that no plugin in the
reference census claims: a remote apm dependency, or a locally added skill."""

_BLOCK = re.compile(r"^([|>])[+\-\d]*\s*(?:#.*)?$")
_WORD = re.compile(r"[a-z]{3,}")
_DECIDABLE = re.compile(
    r"\b(file|commit|build|test|yaml|json|config|flake|lint|check)\b", re.I)


def frontmatter(text):
    """Return the raw YAML frontmatter block, or "" if there is none."""
    if not text.startswith("---") or text[3:4] not in ("\n", "\r"):
        return ""
    rest = text[3:]
    end = re.search(r"^(---|\.\.\.)\s*$", rest, re.M)
    return rest[:end.start()] if end else rest


def _unquote(s):
    quote = s[0]
    body = s[1:-1] if len(s) > 1 and s[-1] == quote else s[1:]
    if quote == "'":
        return body.replace("''", "'")
    escapes = {"n": "\n", "t": "\t", "r": "\r", '"': '"', "\\": "\\"}
    return re.sub(r"\\(.)", lambda m: escapes.get(m.group(1), m.group(1)), body)


def scalar(fm, key):
    """Return the value of a top-level frontmatter key as flat text."""
    lines = fm.splitlines()
    pattern = re.compile(rf"^{re.escape(key)}:(.*)$")
    for i, line in enumerate(lines):
        match = pattern.match(line)
        if not match:
            continue
        head = match.group(1).strip()
        block = _BLOCK.match(head) if head else None
        if block:
            return _block_scalar(lines[i + 1:], block.group(1))
        continuation = []
        for nxt in lines[i + 1:]:
            if not nxt.strip() or not nxt[:1].isspace():
                break
            continuation.append(nxt.strip())
        if head[:1] in ("'", '"'):
            return _unquote(" ".join([head] + continuation))
        if not continuation:
            head = re.sub(r"\s+#.*$", "", head)
        return " ".join([head] + continuation).strip()
    return ""


def _block_scalar(rest, style):
    body = []
    for line in rest:
        if line.strip() and not line[:1].isspace():
            break
        body.append(line)
    while body and not body[-1].strip():
        body.pop()
    if not body:
        return ""
    indent = min(len(c) - len(c.lstrip()) for c in body if c.strip())
    body = [c[indent:] if len(c) >= indent else "" for c in body]
    if style == "|":
        return "\n".join(body)
    folded, para = [], []
    for chunk in body:
        if chunk.strip():
            para.append(chunk if chunk[:1].isspace() else chunk.strip())
        else:
            folded.extend([" ".join(para), ""])
            para = []
    folded.append(" ".join(para))
    return "\n".join(folded).strip("\n")


def tokens(s):
    return set(_WORD.findall(s.lower()))


def _skill_dirs(base):
    if not base.is_dir():
        return []
    return [d for d in sorted(base.iterdir()) if (d / "SKILL.md").is_file()]


def discover(root, layout):
    """Return (resolved_layout, [(skill_dir, plugin_name_or_None)]).

    Symlinked skill directories are followed and included; the link target is
    recorded per skill so a self-referencing deployment is visible in the
    output rather than silently counted as an ordinary directory.
    """
    if layout == "auto":
        layout = "flat" if _skill_dirs(root) else "nested"
    if layout == "flat":
        return layout, [(d, None) for d in _skill_dirs(root)]
    found = []
    for plugin in sorted(d for d in root.iterdir() if d.is_dir()):
        for base in (plugin / ".apm" / "skills", plugin / "skills", plugin):
            dirs = _skill_dirs(base)
            if dirs:
                found.extend((d, plugin.name) for d in dirs)
                break
    return layout, found


def record(skill_dir, root):
    text = (skill_dir / "SKILL.md").read_text(errors="ignore")
    fm = frontmatter(text)
    desc = scalar(fm, "description")
    return {
        "plugin": None,
        "path": os.path.relpath(skill_dir, root),
        "symlink": (os.readlink(skill_dir) if skill_dir.is_symlink() else None),
        "lines": len(text.splitlines()),
        "cmd_style": "disable-model-invocation: true" in fm,
        "env_coupling": sorted(set(re.findall(r"~/[\w./-]+|/home/[\w./-]+",
                                              text)))[:5],
        "has_scripts": (skill_dir / "scripts").is_dir(),
        "has_refs": (skill_dir / "references").is_dir(),
        "description": desc,
        "desc_toks": sorted(tokens(desc)),
        "decidability_guess": ("decidable" if _DECIDABLE.search(desc)
                               else "subjective"),
    }


def load_membership(path):
    data = json.loads(pathlib.Path(path).read_text())
    known = {name: rec.get("plugin") for name, rec in data["skills"].items()}
    return {k: v for k, v in known.items() if v and v != EXTERNAL}


def jaccard(a, b):
    A, B = set(a), set(b)
    return len(A & B) / max(1, len(A | B))


def overlaps(skills, plugins, top_intra, top_inter):
    """Rank skill pairs by description-token Jaccard and cut the top N.

    The cut is a nomination device for choosing which pairs to inspect and
    which interference conditions to spend budget on.  It is a ranking of
    lexical similarity between two description fields.  It is not a
    significance threshold, carries no test, and a pair's presence or absence
    is not evidence that the two skills do or do not interfere at run time.
    """
    def toks(name):
        return skills[name]["desc_toks"]

    intra = sorted(
        ((jaccard(toks(a), toks(b)), p, a, b)
         for p, members in plugins.items()
         for a, b in itertools.combinations(members, 2)),
        key=lambda r: (-r[0], r[1], r[2], r[3]))[:top_intra]
    cross = (tuple(sorted((a, b))) for a, b in itertools.combinations(skills, 2)
             if skills[a]["plugin"] != skills[b]["plugin"])
    inter = sorted(
        ((jaccard(toks(a), toks(b)), skills[a]["plugin"], a,
          skills[b]["plugin"], b) for a, b in cross),
        key=lambda r: (-r[0], r[2], r[4]))[:top_inter]
    return (
        [{"jaccard": round(j, 4), "plugin": p, "a": a, "b": b}
         for j, p, a, b in intra],
        [{"jaccard": round(j, 4), "plugin_a": pa, "a": a,
          "plugin_b": pb, "b": b} for j, pa, a, pb, b in inter],
    )


def git_info(path):
    def run(*args):
        try:
            proc = subprocess.run(["git", "-C", str(path), *args],
                                  capture_output=True, text=True, check=True)
        except (OSError, subprocess.CalledProcessError):
            return None
        return proc.stdout.strip() or None
    return run("rev-parse", "HEAD"), run("log", "-1", "--format=%cI")


def build(root, layout, membership_from, top_intra, top_inter, timestamp):
    layout, found = discover(root, layout)
    if not found:
        raise SystemExit(f"no SKILL.md found under {root} (layout={layout})")
    counts = collections.Counter(d.name for d, _ in found)
    dupes = sorted(n for n, c in counts.items() if c > 1)
    if dupes:
        raise SystemExit(f"duplicate skill names under {root}: {dupes}")
    skills = {d.name: record(d, root) for d, _ in found}
    membership = {d.name: p for d, p in found if p}
    if layout == "flat":
        if not membership_from:
            print("warning: no --membership-from for a flat root; plugin "
                  f"membership resolves to {EXTERNAL} for every skill",
                  file=sys.stderr)
        known = load_membership(membership_from) if membership_from else {}
        membership = {name: known.get(name, EXTERNAL) for name in skills}
    for name, plugin in membership.items():
        skills[name]["plugin"] = plugin

    plugins = {}
    for name in sorted(skills):
        plugins.setdefault(skills[name]["plugin"], []).append(name)
    plugins = {p: plugins[p] for p in sorted(plugins)}

    intra, inter = overlaps(skills, plugins, top_intra, top_inter)
    revision, revision_date = git_info(root)
    return {
        "provenance": {
            "script_version": __version__,
            "root": str(root),
            "layout": layout,
            "revision": revision,
            "revision_date": revision_date,
            "timestamp": timestamp or revision_date,
            "membership_source": (str(pathlib.Path(membership_from).resolve())
                                  if membership_from else None),
            "n_skills": len(skills),
            "n_plugins": sum(1 for p in plugins if p != EXTERNAL),
            "n_external": sum(1 for v in membership.values() if v == EXTERNAL),
            "n_empty_desc": sum(1 for r in skills.values()
                                if not r["desc_toks"]),
            "top_intra": top_intra,
            "top_inter": top_inter,
        },
        "plugins": plugins,
        "membership": dict(sorted(membership.items())),
        "skills": skills,
        "overlap": {"intra": intra, "inter": inter},
    }


def report(census):
    prov = census["provenance"]
    skills, plugins = census["skills"], census["plugins"]
    decidable = sum(1 for r in skills.values()
                    if r["decidability_guess"] == "decidable")
    print(f"root={prov['root']} layout={prov['layout']} rev={prov['revision']}")
    print(f"plugins={prov['n_plugins']} skills={prov['n_skills']} "
          f"external={prov['n_external']} empty_desc={prov['n_empty_desc']} "
          f"cmd_style={sum(1 for r in skills.values() if r['cmd_style'])} "
          f"env_coupled={sum(1 for r in skills.values() if r['env_coupling'])} "
          f"decidable~={decidable} subjective~={len(skills) - decidable}")
    print("plugin sizes:", {p: len(s) for p, s in plugins.items()})
    print(f"\ntop {prov['top_intra']} intra-plugin overlap "
          "(interference candidates within plugins):")
    for r in census["overlap"]["intra"]:
        print(f"  {r['jaccard']:.2f} [{r['plugin']}] {r['a']} : {r['b']}")
    print(f"\ntop {prov['top_inter']} inter-plugin overlap "
          "(cross-plugin trigger competition):")
    for r in census["overlap"]["inter"]:
        print(f"  {r['jaccard']:.2f} {r['plugin_a']}/{r['a']} : "
              f"{r['plugin_b']}/{r['b']}")


def main(argv=None):
    ap = argparse.ArgumentParser(
        description="Static census of a skill tree.",
        formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("root_positional", nargs="?", metavar="ROOT",
                    help="deprecated positional form of --root")
    ap.add_argument("--root", help="tree to census (source plugins dir or "
                                   "deployed flat skills dir)")
    ap.add_argument("--out", required=True, help="path to write census JSON")
    ap.add_argument("--layout", default="auto",
                    choices=["auto", "nested", "flat"])
    ap.add_argument("--membership-from", metavar="CENSUS.JSON",
                    help="source census used to resolve skill-to-plugin "
                         "membership for a flat root")
    ap.add_argument("--top-intra", type=int, default=8)
    ap.add_argument("--top-inter", type=int, default=8)
    ap.add_argument("--timestamp", help="ISO 8601 stamp for provenance; "
                                        "defaults to the root repository's "
                                        "HEAD committer date")
    a = ap.parse_args(argv)

    root = a.root or a.root_positional
    if not root:
        ap.error("--root is required")
    root = pathlib.Path(root).expanduser()
    if not root.is_dir():
        ap.error(f"root is not a directory: {root}")

    census = build(root, a.layout, a.membership_from, a.top_intra,
                   a.top_inter, a.timestamp)
    out = pathlib.Path(a.out).expanduser()
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(census, indent=1) + "\n")
    report(census)
    print(f"\nwrote {out}")


if __name__ == "__main__":
    main()
