#!/usr/bin/env python3
"""Generate the condition lattice design and run manifest.

Usage:
  python design_matrix.py --units skillA skillB skillC \
      --design marginals|pairs|factorial|full \
      [--pairs skillA:skillB ...] [--everything-on] [-k 3] \
      --cells cells.json --out design/

cells.json: [{"name": "claude-code+opus-5", "runner": "harbor",
              "agent": "claude-code", "model": "anthropic/claude-opus-5",
              "concurrency": 2, "env": {"CLAUDE_FORCE_OAUTH": "1"}}, ...]

Emits: design/conditions.json  (condition id -> sorted unit list)
       design/manifest.sh      (one runnable line per condition x cell,
                                trials via -k / repeated invocation)
Invariant (grade discipline): conditions differ only in dir(C); the manifest
varies only --skills-dir / --skill-mode and the ablation id.
"""
import argparse, itertools, json, pathlib, shlex

def conditions(units, design, pairs, everything_on):
    base = [frozenset()] + [frozenset([u]) for u in units]
    if design == "marginals":
        out = base
    elif design == "pairs":
        out = base + [frozenset(p) for p in pairs]
    elif design == "full":
        out = [frozenset(c) for r in range(len(units) + 1)
               for c in itertools.combinations(units, r)]
    elif design == "factorial":
        # Resolution-IV foldover of a one-factor-at-a-time core:
        # complements of singletons + empty + full. Main effects estimable
        # clear of two-way aliasing for moderate n; swap in a proper
        # generator table if n > 6.
        allu = frozenset(units)
        out = base + [allu - frozenset([u]) for u in units] + [allu]
    else:
        raise SystemExit(f"unknown design {design}")
    if everything_on:
        out.append(frozenset(units))
    seen, uniq = set(), []
    for c in out:
        if c not in seen:
            seen.add(c); uniq.append(c)
    return uniq

def cid(c):
    return "none" if not c else "+".join(sorted(c))

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--units", nargs="+", required=True)
    ap.add_argument("--design", required=True,
                    choices=["marginals", "pairs", "factorial", "full"])
    ap.add_argument("--pairs", nargs="*", default=[],
                    help="colon-separated unit pairs for --design pairs")
    ap.add_argument("--everything-on", action="store_true")
    ap.add_argument("-k", type=int, default=3)
    ap.add_argument("--task-dir", default="<task-dir>")
    ap.add_argument("--skills-root", default="<skills-root>",
                    help="dir containing one folder per unit")
    ap.add_argument("--cells", required=True)
    ap.add_argument("--out", default="design")
    a = ap.parse_args()

    pairs = [tuple(p.split(":")) for p in a.pairs]
    for p in pairs:
        assert all(u in a.units for u in p), f"unknown unit in pair {p}"
    conds = conditions(a.units, a.design, pairs, a.everything_on)
    cells = json.loads(pathlib.Path(a.cells).read_text())

    out = pathlib.Path(a.out); out.mkdir(parents=True, exist_ok=True)
    (out / "conditions.json").write_text(json.dumps(
        {cid(c): sorted(c) for c in conds}, indent=2))

    lines = ["#!/bin/bash", "set -euo pipefail",
             f"# {len(conds)} conditions x {len(cells)} cells x k={a.k} = "
             f"{len(conds) * len(cells) * a.k} runs"]
    for cell in cells:
        env = " ".join(f"{k}={shlex.quote(v)}" for k, v in
                       cell.get("env", {}).items())
        for c in conds:
            i = cid(c)
            mat = (f"python materialize_conditions.py --skills-root "
                   f"{a.skills_root} --units {' '.join(sorted(c))} "
                   f"--dest /tmp/cond-{i}") if c else "true  # empty condition"
            lines.append(mat)
            if cell["runner"] == "harbor":
                skills = f"--ak skills_dir=/tmp/cond-{i} " if c else ""
                lines.append(
                    f"{env} harbor run -p {a.task_dir} -a {cell['agent']} "
                    f"-m {cell['model']} -k {a.k} "
                    f"--n-concurrent {cell.get('concurrency', 2)} {skills}"
                    f"--job-name {cell['name']}__{i}")
            else:
                mode = (f"--skill-mode with-skill --skills-dir /tmp/cond-{i}"
                        if c else "--skill-mode no-skill")
                lines.append(
                    f"{env} bench eval run --tasks-dir {a.task_dir} "
                    f"--agent {cell['agent']} --model {cell['model']} "
                    f"{mode} --sandbox docker "
                    f"--run-id {cell['name']}__{i}  # repeat x{a.k}")
    (out / "manifest.sh").write_text("\n".join(lines) + "\n")
    print(f"{len(conds)} conditions -> {out}/conditions.json, {out}/manifest.sh")

if __name__ == "__main__":
    main()
