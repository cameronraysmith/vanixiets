#!/usr/bin/env bash
# Start a named, backgrounded Claude Code session (visible in `claude agents`)
set -euo pipefail

case "${1:-}" in
  -h|--help)
    cat <<'HELP'
claude-name-background [name] [claude args...]

Start a backgrounded Claude Code session with a name so it shows up in
`claude agents`. If [name] is omitted (or the first argument is a flag),
a name is generated from the current directory and time.

  claude-name-background                     # auto-named: <dir>-HHMMSS
  claude-name-background review-auth         # named "review-auth"
  claude-name-background fix-flake -p "..."  # named, extra args passed to claude
HELP
    exit 0
    ;;
esac

# First non-flag arg is the session name; otherwise auto-generate one.
if [ "$#" -gt 0 ] && [ "${1#-}" = "$1" ]; then
  name="$1"
  shift
else
  name="$(basename "$PWD")-$(date +%H%M%S)"
fi

exec claude --bg --name "$name" "$@"
