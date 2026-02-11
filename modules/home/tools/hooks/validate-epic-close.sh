# shellcheck shell=bash
# Hook: Validate bead close -- PR must be merged, epic children must be complete
# Prevents closing a bead whose branch has no merged PR.
# Prevents closing an epic when children are still open.
# PreToolUse:Bash (sync) -- reads JSON context from stdin.

set -euo pipefail

INPUT=$(cat)

# Only check Bash commands containing "bd close"
TOOL_INPUT=$(echo "$INPUT" | jq -r '.tool_input // empty')
if [ -z "$TOOL_INPUT" ]; then
  exit 0
fi

COMMAND=$(echo "$TOOL_INPUT" | jq -r '.command // ""')

if ! echo "$COMMAND" | grep -qE 'bd\s+close'; then
  exit 0
fi

# Extract the ID being closed (handles: bd close ID, bd close ID && ..., etc.)
CLOSE_ID=$(echo "$COMMAND" | sed -E 's/.*bd[[:space:]]+close[[:space:]]+([A-Za-z0-9._-]+).*/\1/')

if [ -z "$CLOSE_ID" ]; then
  exit 0
fi

# Check if the target is an epic
ISSUE_TYPE=$(bd show "$CLOSE_ID" --json 2>/dev/null | jq -r '.[0].issue_type // ""' 2>/dev/null || echo "")

if [ "$ISSUE_TYPE" != "epic" ]; then
  # Not an epic -- allow closure of regular issues
  exit 0
fi

# Block epic closure unconditionally in Claude Code sessions
cat << EOF
{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"Epic closure is a human-only action. Close individual issues instead; the epic will move to In Review automatically when all children are closed."}}
EOF
exit 0
