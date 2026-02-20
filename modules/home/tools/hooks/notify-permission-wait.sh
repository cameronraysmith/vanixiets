# shellcheck shell=bash
# Helper: Send push notification when a permission prompt is about to block.
# Called in the background by gate hooks before they return "ask".
# Usage: notify-permission-wait <tool_name> <brief_description>

set -euo pipefail

TOOL_NAME="${1:-unknown}"
BRIEF="${2:-(no details)}"

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
  # Last resort: use top-level directory name
  REPO_NAME=$(basename "$(git rev-parse --show-toplevel 2>/dev/null || pwd)")
fi

MESSAGE="Waiting for permission: ${TOOL_NAME}: ${BRIEF}"

# Best-effort delivery; never fail the caller.
curl -sfk -m 5 \
  -H "Title: Permission: ${TOOL_NAME}" \
  -H "Priority: default" \
  -H "Tags: lock,${REPO_NAME}" \
  -d "$MESSAGE" \
  "https://ntfy.zt/${REPO_NAME}" &>/dev/null || true
