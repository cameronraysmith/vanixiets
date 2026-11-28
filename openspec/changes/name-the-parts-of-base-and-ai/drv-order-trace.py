#!/usr/bin/env python3
"""drv-order-trace.py BEFORE.drv AFTER.drv: follows both derivations down their
changed inputs (`nix-stock derivation show`) and accepts only a derivation whose
fields are equal once changed paths are substituted, the order of
structuredAttrs.chosenOutputs (same entries) in the profile builds in PROFILES,
the order of the three gh-dash `prs` keybindings (m, M, C), and the order of
lines within each section of a Brewfile whose sections are the same. Anything
else, or an input that cannot be paired, is rejected; exits 1 on any. Same-named
inputs are paired by shared input derivations, then by closure overlap."""
import json
import re
import subprocess
import sys
from collections import Counter

PROFILES = {
    "system-path.drv",
    "system-applications.drv",
    "home-manager-path.drv",
    "home-manager-fonts.drv",
    "home-manager-applications.drv",
}
GH_DASH = "gh-dash-config.yml.drv"
GH_DASH_BINDINGS = Counter({("m", "enqueue"): 1, ("M", "enqueue stack"): 1, ("C", "code review"): 1})
BREWFILE = "Brewfile.drv"

cache = {}


def show(p):
    if p not in cache:
        out = subprocess.run(
            ["nix-stock", "derivation", "show", p], capture_output=True, text=True, check=True
        ).stdout
        d = json.loads(out)
        d = d.get("derivations", d)
        cache[p] = next(iter(d.values()))
    return cache[p]


closures = {}


def closure(p):
    if p not in closures:
        out = subprocess.run(["nix-store", "-qR", p], capture_output=True, text=True, check=True).stdout
        closures[p] = set(out.split())
    return closures[p]


def full(p):
    return p if p.startswith("/nix/store/") else "/nix/store/" + p


def name(p):
    return re.sub(r"^(/nix/store/)?[a-z0-9]{32}-", "", p)


def inputs(d):
    i = d.get("inputDrvs") or d.get("inputs", {}).get("drvs", {})
    return [full(x) for x in i]


def outpaths(d):
    return {k: full(v["path"]) for k, v in d.get("outputs", {}).items() if isinstance(v, dict) and v.get("path")}


def flatten(o, pre=""):
    if isinstance(o, dict):
        r = {}
        for k, v in o.items():
            r.update(flatten(v, f"{pre}.{k}" if pre else k))
        return r
    return {pre: o}


def same_entries(x, y):
    return isinstance(x, list) and isinstance(y, list) and Counter(map(json.dumps, x)) == Counter(map(json.dumps, y))


def brewfile_sections(text):
    sections = []
    for line in text.split("\n"):
        if line.startswith("# "):
            sections.append((line, Counter()))
        elif sections:
            sections[-1][1][line] += 1
        else:
            return None
    return sections


def judge(drv, field, x, y):
    if drv in PROFILES and field == "structuredAttrs.chosenOutputs" and same_entries(x, y):
        return "accepted", f"{field}: same {len(x)} entries, order differs"
    if drv == GH_DASH and field == "structuredAttrs.value.keybindings.prs" and same_entries(x, y):
        got = Counter((b.get("key"), b.get("name")) for b in x)
        if got == GH_DASH_BINDINGS:
            return "accepted", f"{field}: the three declared bindings, order differs"
    if drv == BREWFILE and field == "structuredAttrs.text" and isinstance(x, str) and isinstance(y, str):
        sx, sy = brewfile_sections(x), brewfile_sections(y)
        if sx is not None and sx == sy:
            return "accepted", f"{field}: the same lines in each of the same {len(sx)} sections, order differs"
    return "REJECTED", f"{field}: {str(x)[:200]!r} -> {str(y)[:200]!r}"


seen = set()
lines = []
rejected = False


def walk(a, b, depth=0):
    global rejected
    if a == b or (a, b) in seen:
        return
    seen.add((a, b))
    da, db = show(a), show(b)
    ga, gb = {}, {}
    for x in inputs(da):
        ga.setdefault(name(x), []).append(x)
    for y in inputs(db):
        gb.setdefault(name(y), []).append(y)
    a2b, changed, problems = {}, [], []
    for n in sorted(set(ga) | set(gb)):
        xs = [x for x in ga.get(n, []) if x not in gb.get(n, [])]
        ys = [y for y in gb.get(n, []) if y not in ga.get(n, [])]
        while xs and ys:
            x, y = max(
                ((x, y) for x in xs for y in ys),
                key=lambda p: (
                    len(set(inputs(show(p[0]))) & set(inputs(show(p[1])))),
                    len(closure(p[0]) & closure(p[1])),
                ),
            )
            xs.remove(x)
            ys.remove(y)
            changed.append(n)
            walk(x, y, depth + 1)
            a2b[x] = y
            oa, ob = outpaths(show(x)), outpaths(show(y))
            a2b.update({oa[k]: ob[k] for k in oa if k in ob})
        if xs or ys:
            problems.append(f"input {n}: {len(xs)} before only, {len(ys)} after only")
    oa, ob = outpaths(da), outpaths(db)
    a2b.update({oa[k]: ob[k] for k in oa if k in ob})
    strip = ("outputs", "inputDrvs", "inputs", "name")
    text = json.dumps({k: v for k, v in da.items() if k not in strip})
    for x, y in a2b.items():
        text = text.replace(x, y)
    fa = flatten(json.loads(text))
    fb = flatten({k: v for k, v in db.items() if k not in strip})
    verdicts = [judge(name(a), k, fa.get(k), fb.get(k)) for k in sorted(set(fa) | set(fb)) if fa.get(k) != fb.get(k)]
    verdicts += [("REJECTED", p) for p in problems]
    if any(v == "REJECTED" for v, _ in verdicts):
        rejected = True
    lines.append((depth, name(a), changed, verdicts))


walk(full(sys.argv[1]), full(sys.argv[2]))
for depth, n, changed, verdicts in sorted(lines, key=lambda r: -r[0]):
    print(f"{n} (depth {depth})")
    if changed:
        print(f"  changed inputs: {', '.join(changed)}")
    for v, text in verdicts:
        print(f"  {v}: {text}")
    if not verdicts:
        print("  own fields equal once changed inputs are substituted")
print("RESULT:", "REJECTED" if rejected else "every difference is a declared reorder")
sys.exit(1 if rejected else 0)
