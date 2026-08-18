#!/bin/bash
set -euo pipefail
mkdir -p /logs/verifier
SD=$(cd "$(dirname "$0")" && pwd)
python3 - "$SD/_deps/build-events.jsonl" <<'EOF'
import json
import sys

fixture = sys.argv[1]

events = []
with open(fixture) as fh:
    for line in fh:
        line = line.strip()
        if line:
            events.append(json.loads(line))

pipelines = {}
for event in events:
    stats = pipelines.setdefault(event['pipeline'], {'events': 0, 'failed': 0})
    stats['events'] += 1
    if event['status'] == 'failed':
        stats['failed'] += 1

durations = sorted(event['duration_ms'] for event in events)

expected = {
    'total_events': len(events),
    'failed_events': sum(1 for e in events if e['status'] == 'failed'),
    'per_pipeline': pipelines,
    'median_duration_ms': durations[len(durations) // 2],
}


def integers_only(node):
    if isinstance(node, bool):
        return False
    if isinstance(node, int):
        return True
    if isinstance(node, dict):
        return all(integers_only(v) for v in node.values())
    return False


try:
    with open('/logs/verifier/summary.json') as fh:
        actual = json.load(fh)
except Exception:
    actual = None

ok = actual is not None and integers_only(actual) and actual == expected
with open('/logs/verifier/reward.txt', 'w') as fh:
    fh.write('1\n' if ok else '0\n')
EOF
