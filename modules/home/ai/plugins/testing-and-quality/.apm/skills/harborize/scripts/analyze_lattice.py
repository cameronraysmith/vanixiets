#!/usr/bin/env python3
"""Aggregate rewards -> E(C) per cell, paired first/second differences.

Input: results.json = [{"condition": "a+b", "cell": "...", "task": "...",
                        "trial": 0, "reward": 1.0}, ...]
Coupling invariant: contrasts computed per (task, trial) then bootstrapped
over tasks. Never compares unpaired subsets (drops (task,trial) rows missing
in either arm of a contrast).
"""
import argparse, collections, itertools, json, math, random, statistics as st

def wilson(k, n, z=1.96):
    if n == 0: return (0.0, 0.0, 1.0)
    p = k / n; d = 1 + z*z/n
    c = (p + z*z/(2*n)) / d; hw = z*math.sqrt(p*(1-p)/n + z*z/(4*n*n)) / d
    return p, max(0, c-hw), min(1, c+hw)

def paired(rows, ca, cb):
    A = {(r["task"], r["trial"]): r["reward"] for r in rows if r["condition"] == ca}
    B = {(r["task"], r["trial"]): r["reward"] for r in rows if r["condition"] == cb}
    keys = sorted(set(A) & set(B))
    return [A[k] - B[k] for k in keys], keys

def boot_ci(diffs, keys, iters=2000, seed=0):
    by_task = collections.defaultdict(list)
    for d, (t, _) in zip(diffs, keys): by_task[t].append(d)
    tasks = list(by_task); rng = random.Random(seed); means = []
    for _ in range(iters):
        sample = [d for t in rng.choices(tasks, k=len(tasks)) for d in by_task[t]]
        means.append(st.mean(sample))
    means.sort()
    return means[int(.025*iters)], means[int(.975*iters)]

ap = argparse.ArgumentParser()
ap.add_argument("results"); ap.add_argument("--units", nargs="+", required=True)
a = ap.parse_args()
rows = json.load(open(a.results))
cells = sorted({r["cell"] for r in rows})
for cell in cells:
    cr = [r for r in rows if r["cell"] == cell]
    print(f"\n== {cell} ==")
    for c in sorted({r["condition"] for r in cr}):
        rs = [r["reward"] for r in cr if r["condition"] == c]
        p, lo, hi = wilson(sum(rs), len(rs))
        print(f"  E({c or 'none':<20}) = {p:.3f} [{lo:.3f},{hi:.3f}] n={len(rs)}")
    for u in a.units:
        d, k = paired(cr, u, "none")
        if d:
            lo, hi = boot_ci(d, k)
            base = st.mean([r["reward"] for r in cr if r["condition"]=="none"]) if any(r["condition"]=="none" for r in cr) else None
            ng = f" norm-gain={st.mean(d)/(1-base):.2f}" if base not in (None, 1) else ""
            print(f"  D({u}) = {st.mean(d):+.3f} [{lo:+.3f},{hi:+.3f}]{ng}")
    conds = {r["condition"] for r in cr}
    for u, v in itertools.combinations(a.units, 2):
        uv = "+".join(sorted([u, v]))
        if {uv, u, v, "none"} <= conds:
            def m(c): return st.mean([r["reward"] for r in cr if r["condition"] == c])
            d2 = m(uv) - m(u) - m(v) + m("none")
            tag = "synergy" if d2 > 0 else "interference" if d2 < 0 else "additive"
            print(f"  D2({u},{v}) = {d2:+.3f}  ({tag}; point est - pair via shared-task bootstrap for CI)")
