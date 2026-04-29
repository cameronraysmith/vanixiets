#!/usr/bin/env bash
# List Claude Code npm package versions with tags and release times
set -euo pipefail

case "${1:-}" in
  -h|--help)
    cat <<'HELP'
List Claude Code npm package versions with tags and release times

Usage: ccvers [LIMIT]

Shows recent versions of @anthropic-ai/claude-code package with:
  - Release timestamp in Eastern Time (EDT/EST)
  - Version number
  - Distribution tags (latest, next, etc.) if applicable

Arguments:
  LIMIT    Number of recent versions to show (default: 20)

Examples:
  ccvers       # Show last 20 versions
  ccvers 10    # Show last 10 versions
  ccvers 50    # Show last 50 versions
HELP
    exit 0
    ;;
esac

limit="${1:-20}"

npm view @anthropic-ai/claude-code --json | jq -r '
  ."dist-tags" as $tags |
  .time as $times |
  .versions[] |
  . as $v |
  ($tags | to_entries | map(select(.value == $v) | .key) | join(", ")) as $labels |
  $times[$v] as $timestamp |
  if ($labels | length) > 0 then
    "\($timestamp)|\($v)|(\($labels))"
  else
    "\($timestamp)|\($v)|"
  end
' | sort -t'|' -k2Vr | head -"$limit" | awk -F'|' '{
  cmd = "TZ=America/New_York date -d \""$1"\" \"+%Y-%m-%d %H:%M %Z\""
  cmd | getline eastern
  close(cmd)
  printf "%s  %s %s\n", eastern, $2, $3
}'
