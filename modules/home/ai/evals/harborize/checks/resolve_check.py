import json
import sys

from harbor.skills import compute_skill_digest, resolve_skills

root = sys.argv[1]
resolved = resolve_skills([root])
print(json.dumps([
    {"name": s.name, "source": str(s.source), "digest": compute_skill_digest(s.source)}
    for s in resolved
], indent=2))
