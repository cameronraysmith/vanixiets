#!/usr/bin/env python3
"""Marketplace census: 100%-coverage static pass over every plugin and skill.
Emits stratification for sampled dynamic evaluation + overlap matrices."""
import itertools, json, pathlib, re, sys, collections

root = pathlib.Path(sys.argv[1])  # plugins dir
out = {}
def toks(s): return set(re.findall(r"[a-z]{3,}", s.lower()))
skills = {}
for plugin in sorted(d for d in root.iterdir() if d.is_dir()):
    pskills = []
    for base in (plugin/".apm"/"skills", plugin/"skills", plugin):
        cands = [d for d in sorted(base.iterdir()) if (d/"SKILL.md").is_file()] if base.is_dir() else []
        if cands: break
    for s in cands:
        t = (s/"SKILL.md").read_text(errors="ignore")
        fm = t.split("---")[1] if t.startswith("---") else ""
        desc = (re.search(r"^description:\s*(.+)$", fm, re.M) or [None,""])[1] if fm else ""
        body = t.split("---",2)[-1]
        rec = {
          "plugin": plugin.name, "lines": len(t.splitlines()),
          "cmd_style": "disable-model-invocation: true" in fm,
          "env_coupling": sorted(set(re.findall(r"~/[\w./-]+|/home/[\w./-]+", t)))[:5],
          "has_scripts": (s/"scripts").is_dir(),
          "has_refs": (s/"references").is_dir(),
          "desc_toks": sorted(toks(desc)),
          "decidability_guess": ("decidable" if re.search(
             r"\b(file|commit|build|test|yaml|json|config|flake|lint|check)\b", desc, re.I)
             else "subjective"),
        }
        skills[s.name] = rec; pskills.append(s.name)
    out[plugin.name] = pskills

def jac(a,b):
    A,B = set(skills[a]["desc_toks"]), set(skills[b]["desc_toks"])
    return len(A&B)/max(1,len(A|B))
intra = sorted(((jac(a,b),p,a,b) for p,ss in out.items()
                for a,b in itertools.combinations(ss,2)), reverse=True)[:8]
inter = sorted(((jac(a,b),skills[a]["plugin"],a,skills[b]["plugin"],b)
                for a,b in itertools.combinations(skills,2)
                if skills[a]["plugin"]!=skills[b]["plugin"]), reverse=True)[:8]
n_cmd = sum(1 for r in skills.values() if r["cmd_style"])
n_env = sum(1 for r in skills.values() if r["env_coupling"])
n_dec = sum(1 for r in skills.values() if r["decidability_guess"]=="decidable")
print(f"plugins={len(out)} skills={len(skills)} cmd_style={n_cmd} "
      f"env_coupled={n_env} decidable~={n_dec} subjective~={len(skills)-n_dec}")
print("plugin sizes:", {p: len(s) for p,s in out.items()})
print("\ntop intra-plugin overlap (interference candidates within plugins):")
[print(f"  {j:.2f} [{p}] {a} : {b}") for j,p,a,b in intra]
print("\ntop inter-plugin overlap (cross-plugin trigger competition):")
[print(f"  {j:.2f} {pa}/{a} : {pb}/{b}") for j,pa,a,pb,b in inter]
json.dump({"plugins": out, "skills": skills}, open("/tmp/census.json","w"), indent=1)
