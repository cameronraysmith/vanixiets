# shellcheck shell=bash
# Helper: Send push notification when a permission prompt is about to block.
# Called in the background by gate hooks before they return "ask".
# Usage: notify-permission-wait <tool_name> <brief_description>

set -euo pipefail

TOOL_NAME="${1:-unknown}"
BRIEF="${2:-(no details)}"

# Derive ntfy topic from hostname; repo name is metadata only
NTFY_TOPIC=$(hostname -s)
REPO_NAME=$(basename "$(git rev-parse --show-toplevel 2>/dev/null || pwd)")
MESSAGE="Waiting for permission: ${TOOL_NAME}: ${BRIEF}"

# Best-effort delivery; never fail the caller.
curl -sfk -m 5 \
  -H "Title: Permission: ${TOOL_NAME}" \
  -H "Priority: default" \
  -H "Tags: lock,${REPO_NAME}" \
  -d "$MESSAGE" \
  "https://ntfy.zt/${NTFY_TOPIC}" &>/dev/null || true
