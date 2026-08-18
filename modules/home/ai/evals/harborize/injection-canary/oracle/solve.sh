#!/bin/bash
set -euo pipefail
out=/logs/verifier/canary-output.txt
mkdir -p /logs/verifier
: > "$out"
# These roots are the oracle discovery-path union, not the adapter registration
# destinations; no adapter registration runs on the oracle path.
# HOME is defaulted because under set -u a container exporting none aborts here
# before any output is written, which reads downstream as a false canary alarm.
home=${HOME:-/root}
for root in /harbor/skills "$home/.claude/skills" "$home/.codex/skills" \
            "$home/.opencode/skills" "$home/.agents/skills" /skills; do
  [ -d "$root" ] || continue
  for f in "$root"/*/SKILL.md; do
    [ -f "$f" ] || continue
    grep -ho 'HARBORIZE-CANARY-[A-Z0-9]*' "$f" >> "$out" || true
  done
done
sort -u -o "$out" "$out"
