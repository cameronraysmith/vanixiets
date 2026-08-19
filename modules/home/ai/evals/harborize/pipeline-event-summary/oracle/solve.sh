#!/bin/bash
set -euo pipefail
mkdir -p /logs/artifacts
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
mid = len(durations) // 2
if len(durations) % 2:
    median = durations[mid]
else:
    median = (durations[mid - 1] + durations[mid]) // 2

summary = {
    'total_events': len(events),
    'failed_events': sum(1 for e in events if e['status'] == 'failed'),
    'per_pipeline': pipelines,
    'median_duration_ms': median,
}

with open('/logs/artifacts/summary.json', 'w') as fh:
    json.dump(summary, fh, indent=2, sort_keys=True)
    fh.write('\n')
EOF
