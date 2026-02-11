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

# Allow --force override
if echo "$COMMAND" | grep -qE -- '--force'; then
  exit 0
fi

# Extract the ID being closed (handles: bd close ID, bd close ID && ..., etc.)
CLOSE_ID=$(echo "$COMMAND" | sed -E 's/.*bd[[:space:]]+close[[:space:]]+([A-Za-z0-9._-]+).*/\1/')

if [ -z "$CLOSE_ID" ]; then
  exit 0
fi

# === CHECK 1: PR merge validation ===
# Find branch matching our ID-descriptor convention (dots replaced by dashes)
HAS_REMOTE=$(git remote get-url origin 2>/dev/null || echo "")
if [ -n "$HAS_REMOTE" ]; then
  BRANCH_PATTERN=$(echo "$CLOSE_ID" | tr '.' '-')
  MATCHING_BRANCH=$(git branch -a --list "*${BRANCH_PATTERN}*" 2>/dev/null | head -1 | sed 's/^[* ]*//' | sed 's|remotes/origin/||')

  if [ -n "$MATCHING_BRANCH" ]; then
    # Branch exists -- check for merged PR
    if command -v gh >/dev/null 2>&1; then
      MERGED_PR=$(gh pr list --head "$MATCHING_BRANCH" --state merged --json number --jq '.[0].number' 2>/dev/null || echo "")

      if [ -z "$MERGED_PR" ]; then
        cat << EOF
{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"Cannot close bead '$CLOSE_ID' -- branch '$MATCHING_BRANCH' has no merged PR. Create and merge a PR first, or use 'bd close $CLOSE_ID --force' to override."}}
EOF
        exit 0
      fi
    fi
  fi
fi

# === CHECK 2: Epic children validation ===
ISSUE_TYPE=$(bd show "$CLOSE_ID" --json 2>/dev/null | jq -r '.[0].issue_type // ""' 2>/dev/null || echo "")

if [ "$ISSUE_TYPE" != "epic" ]; then
  exit 0
fi

# This is an epic -- check if all children are complete
INCOMPLETE=$(bd list --json 2>/dev/null | jq -r --arg epic "$CLOSE_ID" '
  [.[] | select((.id | startswith($epic + ".")) and .status != "done" and .status != "closed")] | length
' 2>/dev/null || echo "0")

if [ "$INCOMPLETE" != "0" ] && [ "$INCOMPLETE" != "" ]; then
  INCOMPLETE_LIST=$(bd list --json 2>/dev/null | jq -r --arg epic "$CLOSE_ID" '
    [.[] | select((.id | startswith($epic + ".")) and .status != "done" and .status != "closed")] | .[] | "\(.id) (\(.status))"
  ' 2>/dev/null | tr '\n' ', ' | sed 's/,$//' || true)

  cat << EOF
{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"Cannot close epic '$CLOSE_ID' -- has $INCOMPLETE incomplete children: $INCOMPLETE_LIST. Mark all children as done first."}}
EOF
  exit 0
fi

# All checks passed, allow close
exit 0
