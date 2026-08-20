#!/bin/bash
set -euo pipefail
mkdir -p /logs/verifier
python3 - <<'EOF'
import json

# Hand-derived by reading environment/build-events.jsonl record by record, and
# deliberately not recomputed here: a verifier that reruns the oracle's own
# algorithm agrees with a wrong oracle and cannot fail on one.
expected = {
    'total_events': 15,
    'failed_events': 5,
    'per_pipeline': {
        'alpha': {'events': 6, 'failed': 2},
        'beta': {'events': 5, 'failed': 2},
        'gamma': {'events': 4, 'failed': 1},
    },
    'median_duration_ms': 450,
}

# Write the failing reward before reading anything. A verifier that dies partway
# leaves no reward file, and both runners treat that as a trial-level crash
# rather than as a score, so a hostile or oversized submission would void the
# trial instead of scoring 0.
with open('/logs/verifier/reward.txt', 'w') as fh:
    fh.write('0\n')


def integers_only(node):
    if isinstance(node, bool):
        return False
    if isinstance(node, int):
        return True
    if isinstance(node, dict):
        return all(integers_only(v) for v in node.values())
    return False


try:
    with open('/logs/artifacts/summary.json') as fh:
        actual = json.load(fh)
    # Inside the guard on purpose: integers_only recurses, so a deeply nested
    # submission raises RecursionError here rather than at the parse.
    ok = integers_only(actual) and actual == expected
except Exception:
    ok = False

if ok:
    with open('/logs/verifier/reward.txt', 'w') as fh:
        fh.write('1\n')
EOF
