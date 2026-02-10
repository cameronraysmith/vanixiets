# shellcheck shell=bash
# Hook: Nudge clarification on short prompts
# Injects a system-reminder referencing the Session Protocol assessment.
# UserPromptSubmit (sync) -- reads JSON context from stdin, outputs plain text to stdout.

set -euo pipefail

INPUT=$(cat)

# Extract prompt text
PROMPT_TEXT=$(echo "$INPUT" | jq -r '.prompt // empty')
if [ -z "$PROMPT_TEXT" ]; then
  exit 0
fi

# Measure character length
CHAR_LEN=${#PROMPT_TEXT}

if [ "$CHAR_LEN" -lt 50 ]; then
  cat << 'EOF'
<system-reminder>
Short prompt detected. Before proceeding, apply the Session Protocol assessment:
1. Is your context optimally primed to design a workflow DAG of subagent Tasks?
2. Are there ambiguities requiring clarification before proceeding?
3. Would local access to external source code or documentation improve this work?
4. Should you present your task decomposition for approval before dispatching?
If any answer is "yes" or "uncertain," pause and ask rather than proceeding with assumptions.
</system-reminder>
EOF
elif [ "$CHAR_LEN" -lt 200 ]; then
  cat << 'EOF'
<system-reminder>
Consider whether this request has implicit ambiguities that the Session Protocol assessment would surface.
</system-reminder>
EOF
fi

exit 0
