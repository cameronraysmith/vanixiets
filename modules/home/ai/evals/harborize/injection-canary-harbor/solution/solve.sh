#!/bin/bash
set -euo pipefail
out=/logs/verifier/canary-output.txt
mkdir -p /logs/verifier
: > "$out"
for root in /harbor/skills "$HOME/.claude/skills" "$HOME/.codex/skills" \
            "$HOME/.opencode/skills" "$HOME/.agents/skills" /skills; do
  [ -d "$root" ] || continue
  for f in "$root"/*/SKILL.md; do
    [ -f "$f" ] || continue
    grep -ho 'HARBORIZE-CANARY-[A-Z0-9]*' "$f" >> "$out" || true
  done
done
sort -u -o "$out" "$out"
