#!/bin/bash
set -euo pipefail
mkdir -p /logs/verifier
python3 - <<'EOF'
import json

events = []
with open('/root/build-events.jsonl') as fh:
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
median = durations[len(durations) // 2]

summary = {
    'total_events': len(events),
    'failed_events': sum(1 for e in events if e['status'] == 'failed'),
    'per_pipeline': pipelines,
    'median_duration_ms': median,
}

with open('/logs/verifier/summary.json', 'w') as fh:
    json.dump(summary, fh, indent=2, sort_keys=True)
    fh.write('\n')
EOF
