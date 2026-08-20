"""Resolve a condition directory through the installed Harbor CLI's own skills API.

Run with the interpreter that backs the `harbor` entrypoint rather than a bare
`python3`, because the proposition this check witnesses is that the *installed*
CLI resolves the directory:

    "$(sed -n '1s|^#!||p' "$(command -v harbor)")" checks/resolve_check.py <dir>

The house PEP-723 header is deliberately absent. `uv run --script` always builds
an isolated environment, so a `dependencies = ["harbor"]` declaration would
resolve a second copy of Harbor and stop measuring the CLI under test.
"""

import json
import sys

from harbor.skills import compute_skill_digest, resolve_skills


def main() -> int:
    if len(sys.argv) != 2:
        print(f"usage: {sys.argv[0]} <condition-dir>", file=sys.stderr)
        return 2
    resolved = resolve_skills([sys.argv[1]])
    print(json.dumps([
        {"name": s.name, "source": str(s.source), "digest": compute_skill_digest(s.source)}
        for s in resolved
    ], indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
