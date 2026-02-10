# Hook: Auto-log dispatch prompts to bead comments
# When a Task is dispatched whose prompt contains a BEAD_ID: marker,
# capture the prompt and log it as a DISPATCH comment on the bead.
# PostToolUse:Task (async) -- reads JSON context from stdin.

set -euo pipefail

# Guard: only run if .beads/ directory exists
REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || echo "")
if [ -z "$REPO_ROOT" ] || [ ! -d "$REPO_ROOT/.beads" ]; then
  exit 0
fi

INPUT=$(cat)
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty')

# Only process Task tool
[[ "$TOOL_NAME" != "Task" ]] && exit 0

# Extract prompt
PROMPT=$(echo "$INPUT" | jq -r '.tool_input.prompt // empty')
[[ -z "$PROMPT" ]] && exit 0

# Extract BEAD_ID from prompt (only log dispatches with a BEAD_ID marker)
BEAD_ID=$(echo "$PROMPT" | grep -oE 'BEAD_ID: [A-Za-z0-9._-]+' | head -1 | sed 's/BEAD_ID: //')
[[ -z "$BEAD_ID" ]] && exit 0

# Extract subagent_type for labeling (default to "task" if not present)
SUBAGENT_TYPE=$(echo "$INPUT" | jq -r '.tool_input.subagent_type // "task"')

# Truncate prompt at 2048 chars
TRUNCATED_PROMPT=$(echo "$PROMPT" | head -c 2048)

# Log dispatch to bead (fail silently)
bd comment "$BEAD_ID" "DISPATCH_PROMPT [$SUBAGENT_TYPE]:

$TRUNCATED_PROMPT" 2>/dev/null || true

exit 0
