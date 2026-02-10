# Hook: Quality gate for subagent and task completion
# Validates bead status updates, committed changes, and branch push state.
# SubagentStop and TaskCompleted (sync) -- reads JSON context from stdin.

set -euo pipefail

INPUT=$(cat)

# Locate BEAD_ID from agent transcript if available
BEAD_ID=""
TRANSCRIPT_PATH=$(echo "$INPUT" | jq -r '.agent_transcript_path // empty')

if [ -n "$TRANSCRIPT_PATH" ] && [ -f "$TRANSCRIPT_PATH" ]; then
  BEAD_ID=$(tail -n 200 "$TRANSCRIPT_PATH" | grep -oE 'BEAD_ID: [A-Za-z0-9._-]+' | tail -1 | sed 's/BEAD_ID: //' || echo "")
fi

# If no transcript path, try extracting from task context
if [ -z "$BEAD_ID" ]; then
  BEAD_ID=$(echo "$INPUT" | jq -r '.bead_id // empty' 2>/dev/null || echo "")
fi

# If no BEAD_ID found, approve (not bead-related work)
if [ -z "$BEAD_ID" ]; then
  echo '{"decision":"approve"}'
  exit 0
fi

# Guard: if .beads/ doesn't exist, approve
REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || echo "")
if [ -z "$REPO_ROOT" ] || [ ! -d "$REPO_ROOT/.beads" ]; then
  echo '{"decision":"approve"}'
  exit 0
fi

# === CHECK 1: Bead status updated ===
BEAD_STATUS=$(bd show "$BEAD_ID" --json 2>/dev/null | jq -r '.[0].status // ""' 2>/dev/null || echo "")
if [ "$BEAD_STATUS" = "open" ]; then
  cat << EOF
{"decision":"block","reason":"Bead $BEAD_ID status is still 'open'. Update status before completing:\n  bd update $BEAD_ID --status=in_progress"}
EOF
  exit 0
fi

# === CHECK 2: Uncommitted changes ===
DIRTY=$(git status --porcelain 2>/dev/null || echo "")
if [ -n "$DIRTY" ]; then
  cat << EOF
{"decision":"block","reason":"Uncommitted changes detected. Commit all work before completing."}
EOF
  exit 0
fi

# === CHECK 3: Branch pushed ===
HAS_REMOTE=$(git remote get-url origin 2>/dev/null || echo "")
if [ -n "$HAS_REMOTE" ]; then
  CURRENT_BRANCH=$(git symbolic-ref --short HEAD 2>/dev/null || echo "")
  if [ -n "$CURRENT_BRANCH" ]; then
    UPSTREAM=$(git rev-parse --abbrev-ref "${CURRENT_BRANCH}@{upstream}" 2>/dev/null || echo "")
    if [ -z "$UPSTREAM" ]; then
      cat << EOF
{"decision":"block","reason":"Branch not pushed to remote. Push before completing:\n  git push -u origin $CURRENT_BRANCH"}
EOF
      exit 0
    fi

    # Check if local is ahead of remote
    AHEAD=$(git rev-list "${UPSTREAM}..${CURRENT_BRANCH}" --count 2>/dev/null || echo "0")
    if [ "$AHEAD" != "0" ]; then
      cat << EOF
{"decision":"block","reason":"Branch has $AHEAD unpushed commit(s). Push before completing:\n  git push origin $CURRENT_BRANCH"}
EOF
      exit 0
    fi
  fi
fi

# All checks passed
echo '{"decision":"approve"}'
exit 0
