# shellcheck shell=bash
# Hook: Send ntfy notification when the last child of an epic is closed
# Detects bd close commands and checks if the parent epic's children are all closed,
# then sends a curl notification to ntfy.zt indicating the epic is ready for review.
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

# Only process bd close commands
echo "$COMMAND" | grep -qE 'bd\s+close' || exit 0

# Extract the issue ID (argument after "bd close")
ISSUE_ID=$(echo "$COMMAND" | sed -E 's/.*bd[[:space:]]+close[[:space:]]+([A-Za-z0-9._-]+).*/\1/')
[[ -z "$ISSUE_ID" || "$ISSUE_ID" == "$COMMAND" ]] && exit 0

# Get issue metadata
ISSUE_JSON=$(bd show "$ISSUE_ID" --json 2>/dev/null || echo "[]")

# Skip if the closed issue is itself an epic
ISSUE_TYPE=$(echo "$ISSUE_JSON" | jq -r '.[0].issue_type // empty' 2>/dev/null || echo "")
[[ "$ISSUE_TYPE" == "epic" ]] && exit 0

# Find the parent epic via parent-child dependency
PARENT_EPIC_ID=$(echo "$ISSUE_JSON" | jq -r '[.[0].dependencies[] | select(.type == "parent-child")] | .[0].id // empty' 2>/dev/null || echo "")
[[ -z "$PARENT_EPIC_ID" ]] && exit 0

# Check if all children of the parent epic are now closed
EPIC_JSON=$(bd show "$PARENT_EPIC_ID" --json 2>/dev/null || echo "[]")
OPEN_CHILDREN=$(echo "$EPIC_JSON" | jq '[.[0].dependencies[] | select(.type == "parent-child") | select(.status != "closed")] | length' 2>/dev/null || echo "1")

# If any children are still open, do not notify
[[ "$OPEN_CHILDREN" -ne 0 ]] && exit 0

# All children are closed; prepare notification
EPIC_TITLE=$(echo "$EPIC_JSON" | jq -r '.[0].title // "unknown"' 2>/dev/null || echo "unknown")

# Derive ntfy topic from git remote repo name
REMOTE_URL=""
for remote in origin upstream; do
  REMOTE_URL=$(git remote get-url "$remote" 2>/dev/null || true)
  if [ -n "$REMOTE_URL" ]; then
    break
  fi
done

# Fall back to first available remote
if [ -z "$REMOTE_URL" ]; then
  FIRST_REMOTE=$(git remote 2>/dev/null | head -1 || true)
  if [ -n "$FIRST_REMOTE" ]; then
    REMOTE_URL=$(git remote get-url "$FIRST_REMOTE" 2>/dev/null || true)
  fi
fi

# Extract repo name from URL, stripping .git suffix
if [ -n "$REMOTE_URL" ]; then
  REPO_NAME=$(basename -s .git "$REMOTE_URL")
else
  # Last resort: use directory name
  REPO_NAME=$(basename "$REPO_ROOT")
fi

NTFY_TOPIC="$REPO_NAME"

# Build notification message
MESSAGE="All children of ${PARENT_EPIC_ID} (${EPIC_TITLE}) are closed. Epic is ready for System 5 review and closure."

# Send notification to ntfy.zt
# Uses curl so it works from both local and remote SSH sessions over zerotier.
# Timeout after 5 seconds to avoid blocking if ntfy is unreachable.
curl -sf -m 5 \
  -H "Title: Epic ready: ${PARENT_EPIC_ID}" \
  -H "Priority: default" \
  -H "Tags: checkmark,${REPO_NAME}" \
  -d "$MESSAGE" \
  "https://ntfy.zt/${NTFY_TOPIC}" 2>/dev/null || true

# Notification is best-effort; never fail the hook
exit 0
