# shellcheck shell=bash
# Hook: Forward permission prompts to ntfy
# Enables awareness of blocked agents from mobile or remote contexts.
# Notification:permission_prompt (async) -- reads JSON context from stdin.

set -euo pipefail

REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || echo "")

INPUT=$(cat)

# Extract tool info from the permission prompt event
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // "unknown"')

# Extract a brief description from tool_input depending on the tool type.
# Bash: the command being run. Edit/Write: the file path. Other: first string value.
BRIEF=""
case "$TOOL_NAME" in
  Bash)
    BRIEF=$(echo "$INPUT" | jq -r '.tool_input.command // empty' | head -c 200)
    ;;
  Edit|Write|MultiEdit)
    BRIEF=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')
    ;;
  *)
    # Best effort: grab the first string value from tool_input
    BRIEF=$(echo "$INPUT" | jq -r '[.tool_input | to_entries[] | select(.value | type == "string") | .value][0] // empty' | head -c 200)
    ;;
esac

if [ -z "$BRIEF" ]; then
  BRIEF="(no details available)"
fi

# Derive ntfy topic from hostname; repo name is metadata only
NTFY_TOPIC=$(hostname -s)
REPO_NAME=$(basename "$REPO_ROOT")

# Build notification message
MESSAGE="Claude Code needs permission to use ${TOOL_NAME}: ${BRIEF}"

# Send notification to ntfy.zt through ntfy-send, which verifies the server's
# certificate and times out after 5 seconds; best-effort, never fail the hook.
ntfy-send "$MESSAGE" "$NTFY_TOPIC" \
  -H "Title: Permission: ${TOOL_NAME}" \
  -H "Priority: default" \
  -H "Tags: lock,${REPO_NAME}" 2>/dev/null || true

# Notification is best-effort; never fail the hook
exit 0
