#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.12"
# dependencies = []
# ///
"""Generate the condition lattice design and run manifest.

Usage:
  design_matrix.py --units skillA skillB skillC \
      --design marginals|pairs|foldover|full \
      [--pairs skillA:skillB ...] [--from-census census.json --top-pairs 3] \
      [--everything-on] [-k 3] --cells cells.json --out design/

cells.json: [{"name": "claude-code+opus-5", "runner": "harbor",
              "agent": "claude-code", "model": "anthropic/claude-opus-5",
              "concurrency": 2, "env": {"CLAUDE_FORCE_OAUTH": "1"}},
             {"name": "codex+luna", "runner": "benchflow",
              "agent": "codex", "model": "gpt-5.6-luna"}, ...]

`runner` is "harbor" or "benchflow". `concurrency` and `env` are copied into
the manifest verbatim; this script knows nothing about authentication pools,
and SKILL.md Phase 5 governs which cells may appear in a reported run batch.

Emits: design/conditions.json  (condition id -> sorted unit list)
       design/manifest.sh      (one runnable block per condition x cell)
       design/jobs.json        ({runner, cell, condition, path} per job, the
                                shape collect_rewards.py --job-index consumes)
       design/selection.json   (pair ranking provenance, with --from-census)

Job directories are laid out per runner under --jobs-root: harbor at
<jobs-root>/harbor/<cell>__<id>, bench at <jobs-root>/bench/<cell>__<id>/trial-NN.
Harbor's -o/--jobs-dir is emitted explicitly rather than left to its configured
default, so the manifest and design/jobs.json agree on where output landed.
Paths in design/jobs.json are written exactly as the manifest spells them, so
they resolve against the directory the manifest and the collector are run from.

Injection is the single mechanism that varies between conditions. Harbor takes
`--skill <host-path>`; `--ak skills_dir=` is a container-side path that fails
silently against a host one. BenchFlow takes `--skills-dir <host-path>` under
`--skill-mode with-skill`, and `--skill-mode no-skill` alone for C = empty.
See references/emitters.md for the contract and the upstream anchors.

A cells.json naming a Harbor adapter that does not read the injected directory
is refused here rather than run: that failure is invisible at every later
stage, so the allowlist below is the only gate that catches it, and it costs
nothing because it runs before any container starts.

Invariant (grade discipline): conditions differ only in dir(C); the manifest
varies only the injected directory and the ablation id.
"""

from __future__ import annotations

import argparse
import itertools
import json
import pathlib
import shlex

MATERIALIZE = pathlib.Path(__file__).resolve().parent / "materialize_conditions.py"


def conditions(units, design, pairs, everything_on):
    """Condition sets for a design.

    `foldover` is the empty set, every singleton, every singleton's complement,
    and the full set, giving |C| = 2n + 2. It is not a fractional factorial: it
    carries no defining relation and no resolution claim. At n = 3 it coincides
    with the full factorial. At n >= 4 it contains no two-element subsets, so
    analyze_lattice.py can compute no second difference from it — {u}, {v} and
    {u,v} must all be present for that. Use `pairs` or `full` when interactions
    are the question.
    """
    base = [frozenset()] + [frozenset([u]) for u in units]
    if design == "marginals":
        out = base
    elif design == "pairs":
        out = base + [frozenset(p) for p in pairs]
    elif design == "full":
        out = [frozenset(c) for r in range(len(units) + 1)
               for c in itertools.combinations(units, r)]
    elif design == "foldover":
        allu = frozenset(units)
        out = base + [allu - frozenset([u]) for u in units] + [allu]
    else:
        raise SystemExit(f"unknown design {design}")
    if everything_on:
        out.append(frozenset(units))
    seen, uniq = set(), []
    for c in out:
        if c not in seen:
            seen.add(c)
            uniq.append(c)
    return uniq


def cid(c):
    return "none" if not c else "+".join(sorted(c))


def cond_dir(ident):
    """dir(C) for a condition id.

    Unit names reach here verbatim from --units, and the census's own
    `<external>` sentinel contains shell redirection metacharacters, so every
    interpolation of this path into the manifest is quoted.
    """
    return f"/tmp/cond-{ident}"


RUNNERS = ("harbor", "benchflow")

# Registered Harbor agents whose adapter reads the injected skills directory
# and registers it into a discovery path. Regenerate at a new harbor revision
# by intersecting the factory registry with the adapters that read the dir:
#   rg -n 'AgentName\.[A-Z_0-9]+: ' src/harbor/agents/factory.py
#   rg -l 'self\.skills_dir' src/harbor/agents/ --type py
# The second command yields module paths; map each back to its registry name
# through factory.py and drop agents/base.py, which is the definition site.
# Derived at harbor ac398bbda7c4c1073461797d3b95c2455cc671b5: 39 registered,
# 22 consuming, 17 that accept the upload and never register it.
HARBOR_SKILL_CONSUMING_AGENTS = frozenset({
    "antigravity-cli", "antigravity-sdk", "claude-code", "cline-cli", "codex",
    "copilot-cli", "cursor-cli", "eve", "fx", "gemini-cli", "goose",
    "grok-build", "hermes", "kimi-cli", "kimi-code", "mimo", "openclaw",
    "opencode", "pi", "qwen-coder", "terminus-2", "vibe",
})

# Harbor routes every agent name carrying this prefix through AgentName.ACP
# (src/harbor/agents/factory.py:167-175), and acp is one of the 17.
ACP_SHORTHAND_PREFIX = "acp:"


def check_harbor_agents(cells, path):
    """Refuse a cell whose Harbor adapter would drop the injected skills.

    Harbor uploads the skills per trial regardless of adapter, and a
    non-consuming adapter never registers them into a discovery path. Nothing
    raises, the run exits 0, and every condition in that cell collapses to the
    empty condition.

    lock.json cannot detect this. The lock is written in Trial.__init__ (harbor
    src/harbor/trial/trial.py:104), before the skills are resolved at :107 and
    long before they are uploaded at :411, and _build_agent_skill_locks
    (src/harbor/models/job/lock.py:462-475) calls only host-side functions, so
    a cell that delivers nothing still writes a fully populated lock. Nothing
    written after the run separates this failure from a real negative result
    either, so refusing here, before any container starts, is the only cheap
    place it can be caught.
    """
    problems = []
    for i, cell in enumerate(cells):
        if cell["runner"] != "harbor":
            continue
        agent = str(cell["agent"])
        if agent.startswith(ACP_SHORTHAND_PREFIX):
            problems.append(
                f"entry {i} ({cell['name']!r}) names harbor agent {agent!r}: "
                "harbor routes every acp: shorthand through AgentName.ACP, "
                "which does not read the injected skills directory, so this "
                "cell drops skills on the harbor arm while a benchflow arm "
                "for the same agent works"
            )
        elif agent not in HARBOR_SKILL_CONSUMING_AGENTS:
            problems.append(
                f"entry {i} ({cell['name']!r}) names harbor agent {agent!r}, "
                "whose adapter does not read the injected skills directory: "
                "harbor uploads the skills and nothing registers them, with "
                "no error and no log line, so every condition in this cell "
                "collapses to the empty condition"
            )
    if problems:
        raise SystemExit(
            f"cells {path}: refusing to emit a manifest.\n"
            + "\n".join(f"  {problem}" for problem in problems)
            + "\nAdapters that consume injected skills at harbor "
            "ac398bbda7c4c1073461797d3b95c2455cc671b5: "
            + ", ".join(sorted(HARBOR_SKILL_CONSUMING_AGENTS))
        )


def load_cells(path):
    """Read cells.json, refusing a shape design/jobs.json could not describe.

    `runner` is restricted to the two spellings collect_rewards.py accepts, so
    design/jobs.json can be handed to it as --job-index without translation.
    The adapter gate in check_harbor_agents runs from here rather than from
    main, so no caller can reach a manifest without passing it.
    """
    cells = json.loads(pathlib.Path(path).read_text())
    if not isinstance(cells, list) or not cells:
        raise SystemExit(f"cells {path}: expected a non-empty JSON list")
    names = set()
    for i, cell in enumerate(cells):
        if not isinstance(cell, dict):
            raise SystemExit(f"cells {path}: entry {i} is not an object")
        missing = [k for k in ("name", "runner", "agent", "model") if k not in cell]
        if missing:
            raise SystemExit(
                f"cells {path}: entry {i} is missing {', '.join(missing)}"
            )
        if cell["runner"] not in RUNNERS:
            raise SystemExit(
                f"cells {path}: entry {i} has runner {cell['runner']!r}; "
                f"expected one of {', '.join(RUNNERS)}"
            )
        if cell["name"] in names:
            raise SystemExit(f"cells {path}: duplicate cell name {cell['name']!r}")
        names.add(cell["name"])
    check_harbor_agents(cells, path)
    return cells


def load_census(path):
    """Read one census document: census.py writes one tree per --root/--out.

    Pass the DEPLOYED tree's census. It is the evaluation subject, and ranking
    over the source tree understates selection competition because the deployed
    tree carries skills the source tree does not.
    """
    data = json.loads(pathlib.Path(path).read_text())
    if not isinstance(data, dict) or not isinstance(data.get("skills"), dict):
        seen = (", ".join(sorted(map(str, data)))[:120]
                if isinstance(data, dict) else type(data).__name__)
        raise SystemExit(
            f"census {path}: expected a census document with a 'skills' "
            f"mapping (top-level keys: {seen})"
        )
    return data


def unit_tokens(unit, census):
    """Description-token set for a unit, unioning members for a plugin unit.

    Mirrors materialize_conditions.resolve_unit, including its refusal of a
    bare name that is both a skill and a plugin, so pair selection and
    materialization cannot disagree about what a unit denotes.
    """
    skills = census["skills"]
    kind, sep, bare = unit.partition(":")
    if not sep or kind not in ("skill", "plugin"):
        kind, bare = "", unit

    def skill_toks(name):
        return set(skills.get(name, {}).get("desc_toks") or [])

    as_skill = isinstance(skills.get(bare), dict)
    members = sorted(
        name for name, rec in skills.items()
        if isinstance(rec, dict) and rec.get("plugin") == bare
    )
    if not members:
        listed = (census.get("plugins") or {}).get(bare)
        if isinstance(listed, list):
            members = sorted(m for m in listed if isinstance(m, str))

    if kind == "skill":
        if not as_skill:
            raise SystemExit(f"unit {unit}: no such skill in the census")
        return skill_toks(bare)
    if kind == "plugin":
        if not members:
            raise SystemExit(f"unit {unit}: no such plugin in the census")
        return set().union(*(skill_toks(m) for m in members))
    if as_skill and members:
        raise SystemExit(
            f"unit {unit} names both a skill and a plugin in the census; "
            f"disambiguate as skill:{bare} or plugin:{bare}"
        )
    if as_skill:
        return skill_toks(bare)
    if members:
        return set().union(*(skill_toks(m) for m in members))
    raise SystemExit(
        f"unit {unit}: absent from the census as a skill and as a plugin"
    )


def parse_pair(spec, units):
    """Split a --pairs spec into two declared units.

    A unit name may itself contain a colon (`plugin:<name>`), so the separator
    is the colon whose two sides are both declared in --units.
    """
    known = set(units)
    hits = [
        (spec[:i], spec[i + 1:])
        for i, ch in enumerate(spec)
        if ch == ":" and spec[:i] in known and spec[i + 1:] in known
    ]
    if len(hits) == 1:
        return hits[0]
    if not hits:
        raise SystemExit(
            f"--pairs {spec!r}: expected <unit>:<unit> with both sides declared "
            f"in --units"
        )
    raise SystemExit(f"--pairs {spec!r}: ambiguous split, matches {hits}")


def rank_pairs(units, census):
    """Unit pairs by descending description-token Jaccard, name-tie-broken."""
    toks = {u: unit_tokens(u, census) for u in units}
    scored = []
    for a, b in itertools.combinations(sorted(units), 2):
        union = toks[a] | toks[b]
        scored.append((len(toks[a] & toks[b]) / len(union) if union else 0.0, a, b))
    return sorted(scored, key=lambda s: (-s[0], s[1], s[2]))


def harbor_line(env, cell, task_dir, k, ident, has_skills, jobs_dir):
    skill = (
        f"--skill {shlex.quote(cond_dir(ident))} " if has_skills else ""
    )
    job_name = f"{cell['name']}__{ident}"
    return (
        f"{env}harbor run -p {shlex.quote(task_dir)} -a {cell['agent']} "
        f"-m {cell['model']} -k {k} "
        f"--n-concurrent {cell.get('concurrency', 2)} {skill}"
        f"-o {shlex.quote(jobs_dir)} --job-name {shlex.quote(job_name)}"
    )


def bench_block(env, cell, task_dir, k, ident, has_skills, jobs_dir):
    mode = (
        f"--skill-mode with-skill --skills-dir {shlex.quote(cond_dir(ident))}"
        if has_skills else "--skill-mode no-skill"
    )
    jobs = shlex.quote(f"{jobs_dir}/{cell['name']}__{ident}")
    return [
        f"for t in $(seq -w 1 {k}); do",
        f"  {env}bench eval run --tasks-dir {shlex.quote(task_dir)} "
        f"--agent {cell['agent']} --model {cell['model']} "
        f"{mode} --sandbox docker "
        f"--concurrency {cell.get('concurrency', 2)} "
        f'--jobs-dir {jobs}/trial-"$t"',
        "done",
    ]


def runner_jobs_dir(jobs_root, runner):
    return f"{jobs_root}/{'harbor' if runner == 'harbor' else 'bench'}"


def build_manifest(conds, cells, a, membership):
    """Manifest lines plus the job index describing where each job will land.

    Harbor lines carry HARBOR_TELEMETRY=0 unless the cell sets it. Harbor's
    telemetry derives uses_skills from the requested skill list
    (src/harbor/telemetry.py:239) without consulting the effective directory or
    the adapter, so it reports a run that delivered nothing as skill-bearing;
    the manifest declines to publish that classification rather than correct it.
    """
    mem = f" --membership {shlex.quote(membership)}" if membership else ""
    lines = [
        "#!/bin/bash",
        "set -euo pipefail",
        f"# {len(conds)} conditions x {len(cells)} cells x k={a.k} = "
        f"{len(conds) * len(cells) * a.k} runs",
        "# bench k is an outer loop: --trials is inert without --matrix.",
    ]
    jobs = []
    for cell in cells:
        cell_env = cell.get("env", {})
        if cell["runner"] == "harbor":
            cell_env = {"HARBOR_TELEMETRY": "0", **cell_env}
        env = "".join(f"{k}={shlex.quote(v)} " for k, v in cell_env.items())
        jobs_dir = runner_jobs_dir(a.jobs_root, cell["runner"])
        for c in conds:
            ident = cid(c)
            lines.append(
                f"uv run --script {shlex.quote(str(MATERIALIZE))} "
                f"--skills-root {shlex.quote(a.skills_root)} "
                f"--units {' '.join(shlex.quote(u) for u in sorted(c))} "
                f"--dest {shlex.quote(cond_dir(ident))}{mem}"
                if c else "true  # empty condition: nothing to materialize"
            )
            if cell["runner"] == "harbor":
                lines.append(
                    harbor_line(env, cell, a.task_dir, a.k, ident, bool(c),
                                jobs_dir)
                )
            else:
                lines.extend(
                    bench_block(env, cell, a.task_dir, a.k, ident, bool(c),
                                jobs_dir)
                )
            jobs.append({
                "runner": cell["runner"],
                "cell": cell["name"],
                "condition": ident,
                "path": f"{jobs_dir}/{cell['name']}__{ident}",
            })
    return lines, jobs


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--units", nargs="+", required=True)
    ap.add_argument("--design", required=True,
                    choices=["marginals", "pairs", "foldover", "full"])
    ap.add_argument("--pairs", nargs="*", default=[],
                    help="colon-separated unit pairs for --design pairs")
    ap.add_argument("--from-census",
                    help="census.json for the DEPLOYED tree: ranks pairs for "
                         "--top-pairs and is passed to "
                         "materialize_conditions.py as --membership, which "
                         "plugin units over a flat tree require")
    ap.add_argument("--top-pairs", type=int, default=0,
                    help="add the N highest-overlap unit pairs, on top of any "
                         "--pairs the user named")
    ap.add_argument("--everything-on", action="store_true")
    ap.add_argument("-k", type=int, default=3)
    ap.add_argument("--task-dir", default="<task-dir>")
    ap.add_argument("--skills-root", default="<skills-root>",
                    help="dir containing one folder per unit")
    ap.add_argument("--jobs-root", default="runs",
                    help="job-output prefix; harbor lands under "
                         "<root>/harbor and bench under <root>/bench, which "
                         "collect_rewards.py reads as --harbor-jobs and "
                         "--benchflow-jobs")
    ap.add_argument("--cells", required=True)
    ap.add_argument("--out", default="design")
    a = ap.parse_args()

    if a.top_pairs and not a.from_census:
        raise SystemExit("--top-pairs requires --from-census")

    pairs = [parse_pair(p, a.units) for p in a.pairs]

    ranking = census = None
    if a.from_census:
        census = load_census(a.from_census)
        ranking = rank_pairs(a.units, census)
        for _, x, y in ranking[:a.top_pairs]:
            if (x, y) not in pairs and (y, x) not in pairs:
                pairs.append((x, y))

    conds = conditions(a.units, a.design, pairs, a.everything_on)
    cells = load_cells(a.cells)

    out = pathlib.Path(a.out)
    out.mkdir(parents=True, exist_ok=True)
    (out / "conditions.json").write_text(json.dumps(
        {cid(c): sorted(c) for c in conds}, indent=2) + "\n")
    if ranking is not None:
        (out / "selection.json").write_text(json.dumps({
            "census": str(pathlib.Path(a.from_census).resolve()),
            "census_provenance": census.get("provenance"),
            "top_pairs": a.top_pairs,
            "ranking": [
                {"jaccard": round(j, 4), "pair": [x, y]} for j, x, y in ranking
            ],
            "selected": [list(p) for p in pairs],
        }, indent=2) + "\n")

    membership = (
        str(pathlib.Path(a.from_census).resolve()) if a.from_census else None
    )
    lines, jobs = build_manifest(conds, cells, a, membership)
    manifest = out / "manifest.sh"
    manifest.write_text("\n".join(lines) + "\n")
    manifest.chmod(0o755)
    (out / "jobs.json").write_text(
        json.dumps({"jobs_root": a.jobs_root, "jobs": jobs}, indent=2) + "\n"
    )
    print(
        f"{len(conds)} conditions, {len(jobs)} jobs -> {out}/conditions.json, "
        f"{manifest}, {out}/jobs.json"
    )


if __name__ == "__main__":
    main()
