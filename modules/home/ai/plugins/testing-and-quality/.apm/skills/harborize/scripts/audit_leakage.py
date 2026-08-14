#!/usr/bin/env python3
"""Non-triviality audit: check that skill content cannot satisfy the verifier
by copying (square_S must not derive phi).

Heuristics (flag, human reviews):
 1. Literal expectation strings from verifier tests/checks found in any skill file.
 2. Oracle solve.sh similarity to any single skill-bundled script (token Jaccard).
 3. Verifier expected-output files byte-identical to any skill asset.
Exit 1 on any flag.
"""
import argparse, pathlib, re, sys

def tokens(t): return set(re.findall(r"[A-Za-z0-9_./-]{4,}", t))
def read_all(root, exts=(".py",".sh",".md",".toml",".txt",".json")):
    for p in pathlib.Path(root).rglob("*"):
        if p.is_file() and p.suffix in exts:
            try: yield p, p.read_text(errors="ignore")
            except OSError: pass

ap = argparse.ArgumentParser()
ap.add_argument("skills", nargs="+")
ap.add_argument("--task", required=True)
a = ap.parse_args()
task = pathlib.Path(a.task)
flags = []

# 1. expectation strings (quoted literals in verifier code) present in skills
ver_lits = set()
for d in ("verifier", "tests"):
    if (task / d).exists():
        for _, t in read_all(task / d):
            ver_lits |= {m for m in re.findall(r"[\"']([^\"']{8,})[\"']", t)
                         if not m.startswith(("/logs", "/tests", "/app"))}
skill_texts = [(p, t) for s in a.skills for p, t in read_all(s)]
for lit in ver_lits:
    for p, t in skill_texts:
        if lit in t:
            flags.append(f"verifier literal {lit!r} appears in {p}")

# 2. oracle vs skill scripts
for d in ("oracle", "solution"):
    o = task / d / "solve.sh"
    if o.exists():
        ot = tokens(o.read_text(errors="ignore"))
        for p, t in skill_texts:
            if p.suffix in (".sh", ".py"):
                st = tokens(t)
                j = len(ot & st) / max(1, len(ot | st))
                if j > 0.6:
                    flags.append(f"oracle ~ {p} (Jaccard {j:.2f}) - "
                                 "parameterize inputs or the skill IS the answer key")

# 3. byte-identical expected outputs
import hashlib
def h(p): return hashlib.sha256(p.read_bytes()).hexdigest()
ver_files = {h(p): p for d in ("verifier","tests") if (task/d).exists()
             for p in (task/d).rglob("*") if p.is_file()}
for s in a.skills:
    for p in pathlib.Path(s).rglob("*"):
        if p.is_file() and h(p) in ver_files:
            flags.append(f"{p} byte-identical to verifier file {ver_files[h(p)]}")

if flags:
    print("LEAKAGE FLAGS:"); [print(" -", f) for f in flags]; sys.exit(1)
print("non-triviality audit: clean")
