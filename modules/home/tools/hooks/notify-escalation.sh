# shellcheck shell=bash
# Hook: Send ntfy notification when escalation=pending is set
# Detects bd update commands that write escalation | pending to the signal table
# and sends a curl notification to ntfy.zt with issue ID and escalation context.
# PostToolUse:Bash (async) -- reads JSON context from stdin.

set -euo pipefail

# Guard: only run if .beads/ directory exists
REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || echo "")
if [ -z "$REPO_ROOT" ] || [ ! -d "$REPO_ROOT/.beads" ]; then
  exit 0
fi

INPUT=$(cat)
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty')

# Only process Bash tool
[[ "$TOOL_NAME" != "Bash" ]] && exit 0

# Extract the command that was executed
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')
[[ -z "$COMMAND" ]] && exit 0

# Only process bd update commands
echo "$COMMAND" | grep -qE 'bd\s+update\s+' || exit 0

# Check that the command sets escalation to pending in the signal table.
# The signal table format is: | escalation | pending | ... |
# The notes argument may use literal or escaped pipe characters.
echo "$COMMAND" | grep -qE 'escalation\s*\|?\s*pending' || exit 0

# Extract the issue ID (argument after "bd update")
ISSUE_ID=$(echo "$COMMAND" | sed -E 's/.*bd[[:space:]]+update[[:space:]]+([A-Za-z0-9._-]+)[[:space:]]+.*/\1/')
[[ -z "$ISSUE_ID" || "$ISSUE_ID" == "$COMMAND" ]] && exit 0

# Derive ntfy topic from hostname; repo name is metadata only
NTFY_TOPIC=$(hostname -s)
REPO_NAME=$(basename "$REPO_ROOT")

# Extract escalation context from the issue notes for the notification summary.
# Read the current issue state to get the escalation-context section.
ISSUE_JSON=$(bd show "$ISSUE_ID" --json 2>/dev/null || echo "[]")
ISSUE_TITLE=$(echo "$ISSUE_JSON" | jq -r '.[0].title // "unknown"' 2>/dev/null || echo "unknown")
NOTES=$(echo "$ISSUE_JSON" | jq -r '.[0].notes // ""' 2>/dev/null || echo "")

# Extract escalation question from <!-- escalation-context --> section
ESCALATION_SUMMARY=""
if echo "$NOTES" | grep -q 'escalation-context'; then
  ESCALATION_SUMMARY=$(echo "$NOTES" | sed -n '/<!-- escalation-context -->/,/<!-- \/escalation-context -->/p' | grep -v '<!--' | head -5 | tr '\n' ' ' | head -c 200)
fi

# Build notification message
MESSAGE="Escalation pending on ${ISSUE_ID}: ${ISSUE_TITLE}"
if [ -n "$ESCALATION_SUMMARY" ]; then
  MESSAGE="${MESSAGE}

${ESCALATION_SUMMARY}"
fi

# Send notification to ntfy.zt
# Uses curl so it works from both local and remote SSH sessions over zerotier.
# Timeout after 5 seconds to avoid blocking if ntfy is unreachable.
curl -sfk -m 5 \
  -H "Title: Escalation: ${ISSUE_ID}" \
  -H "Priority: high" \
  -H "Tags: warning,${REPO_NAME}" \
  -d "$MESSAGE" \
  "https://ntfy.zt/${NTFY_TOPIC}" 2>/dev/null || true

# Notification is best-effort; never fail the hook
exit 0
