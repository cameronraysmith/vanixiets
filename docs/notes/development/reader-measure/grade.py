#!/usr/bin/env python3
"""Tally a re-measure against the baseline.

Input: a JSON list of runs, each {"set": "lookup"|"hard", "id": <n or task id>,
"arm": "tree"|"commands", "files": int, "searches": int, "right": bool,
"citedRule": bool (placement only), "misledByText": bool (lookup only)},
graded by hand against lookup.json and hard.json. Output: per target, the
count of runs meeting it beside the baseline, and the sample size.
"""
import json
import statistics
import sys
from pathlib import Path

here = Path(__file__).parent
baseline = json.loads((here / "baseline.json").read_text())
runs = json.loads(Path(sys.argv[1]).read_text())


def med_max(xs):
    return (statistics.median(xs), max(xs)) if xs else (None, None)


look = [r for r in runs if r["set"] == "lookup" and r.get("arm", "tree") == "tree"]
base = baseline["lookup"]
print(f"lookup (tree arm): {len(look)} runs")
print(f"  right: {sum(r['right'] for r in look)} of {len(look)} (baseline {sum(b['right'] for b in base)} of {len(base)})")
print(f"  files median/max: {med_max([r['files'] for r in look])} (baseline {med_max([b['files'] for b in base])})")
print(f"  searches median/max: {med_max([r['searches'] for r in look])} (baseline {med_max([b['searches'] for b in base])})")
print(f"  misled by a repository text: {sum(r.get('misledByText', False) for r in look)}")

hard_base = {h["id"]: h for h in baseline["hard"]}
for task in sorted({r["id"] for r in runs if r["set"] == "hard"}):
    for arm in ("tree", "commands"):
        rs = [r for r in runs if r["set"] == "hard" and r["id"] == task and r.get("arm", "tree") == arm]
        if not rs:
            continue
        b = hard_base.get(task, {})
        line = f"{task} ({arm}): complete {sum(r['right'] for r in rs)} of {len(rs)}"
        if task.startswith("PL"):
            line += f", rule cited {sum(r.get('citedRule', False) for r in rs)} of {len(rs)}"
        line += f"; files median {statistics.median([r['files'] for r in rs])}"
        line += f" (baseline complete {b.get('complete')} of {b.get('runs')}, files median {statistics.median(b['files']) if b else None})"
        print(line)
