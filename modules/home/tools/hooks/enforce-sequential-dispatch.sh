# shellcheck shell=bash
# Hook: Enforce sequential dispatch for bead-tagged tasks
# Prevents dispatching work on closed beads or beads with unresolved blockers.
# PreToolUse:Task (sync) -- reads JSON context from stdin.

set -euo pipefail

INPUT=$(cat)

# Extract prompt from Task tool input
PROMPT=$(echo "$INPUT" | jq -r '.tool_input.prompt // empty')
if [ -z "$PROMPT" ]; then
  exit 0
fi

# Look for BEAD_ID marker in prompt
BEAD_ID=$(echo "$PROMPT" | grep -oE 'BEAD_ID: [A-Za-z0-9._-]+' | head -1 | sed 's/BEAD_ID: //' || true)
if [ -z "$BEAD_ID" ]; then
  # No BEAD_ID marker; allow dispatch
  exit 0
fi

# Guard: only enforce if .beads/ directory exists
REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || echo "")
if [ -z "$REPO_ROOT" ] || [ ! -d "$REPO_ROOT/.beads" ]; then
  exit 0
fi

# === CHECK 1: Closed bead ===
BEAD_STATUS=$(bd show "$BEAD_ID" --json 2>/dev/null | jq -r '.[0].status // ""' 2>/dev/null || echo "")
if [ "$BEAD_STATUS" = "closed" ] || [ "$BEAD_STATUS" = "done" ]; then
  cat << EOF
{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"Bead $BEAD_ID is already $BEAD_STATUS. Create a new bead for follow-up work:\n  bd create \"Follow-up: [description]\" -d \"Follow-up to $BEAD_ID\"\n  bd dep relate <new-id> $BEAD_ID"}}
EOF
  exit 0
fi

# === CHECK 2: Blocked epic child ===
# Epic children have dots in their IDs (e.g., nix-d4o.2)
if echo "$BEAD_ID" | grep -qF '.'; then
  # Extract parent epic ID (everything before the last dot)
  EPIC_ID="${BEAD_ID%.*}"

  # Get blockers for this bead
  BLOCKERS=$(bd dep list "$BEAD_ID" --json 2>/dev/null || echo "[]")

  # Filter out the parent epic and any closed/done items
  UNRESOLVED=$(echo "$BLOCKERS" | jq -r --arg epic "$EPIC_ID" '
    [.[] | select(
      .id != $epic and
      .status != "closed" and
      .status != "done" and
      .direction == "blocked_by"
    )] | [.[].id] | join(", ")
  ' 2>/dev/null || echo "")

  if [ -n "$UNRESOLVED" ]; then
    cat << EOF
{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"Cannot dispatch $BEAD_ID -- unresolved blockers: $UNRESOLVED. Complete blocking tasks first."}}
EOF
    exit 0
  fi
fi

# === CHECK 3: Parent epic in_progress advisory ===
# When dispatching work on an epic child, verify the parent epic is in_progress.
# Soft warning only: outputs reminder to stderr but allows the dispatch to proceed.
if echo "$BEAD_ID" | grep -qF '.'; then
  EPIC_ID="${BEAD_ID%.*}"
  EPIC_STATUS=$(bd show "$EPIC_ID" --json 2>/dev/null | jq -r '.[0].status // ""' 2>/dev/null || echo "")

  if [ -n "$EPIC_STATUS" ] && [ "$EPIC_STATUS" != "in_progress" ] && [ "$EPIC_STATUS" != "closed" ] && [ "$EPIC_STATUS" != "done" ]; then
    echo "Parent epic $EPIC_ID is not yet in_progress (currently: $EPIC_STATUS). Consider running: bd update $EPIC_ID --status in_progress" >&2
  fi
fi

# === CHECK 4: Design doc ===
# If the parent epic has a design field, check the file exists
if echo "$BEAD_ID" | grep -qF '.'; then
  EPIC_ID="${BEAD_ID%.*}"
  DESIGN_DOC=$(bd show "$EPIC_ID" --json 2>/dev/null | jq -r '.[0].design // ""' 2>/dev/null || echo "")

  if [ -n "$DESIGN_DOC" ] && [ ! -f "$REPO_ROOT/$DESIGN_DOC" ]; then
    cat << EOF
{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"Design doc for epic $EPIC_ID not found at $DESIGN_DOC. Create the design document before dispatching work on $BEAD_ID."}}
EOF
    exit 0
  fi
fi

# All checks passed
exit 0
