# shellcheck shell=bash
# Hook: Redirect rm to rip (rm-improved)
# Denies Bash commands using rm and instructs the agent to use rip instead.
# PreToolUse:Bash (sync) -- reads JSON context from stdin.

set -euo pipefail

INPUT=$(cat)

TOOL_INPUT=$(echo "$INPUT" | jq -r '.tool_input // empty')
if [ -z "$TOOL_INPUT" ]; then
  exit 0
fi

COMMAND=$(echo "$TOOL_INPUT" | jq -r '.command // ""')

# Match rm as the first token, or preceded by common shell constructs
# (&&, ||, ;, |, $(), backticks). Skip if the command doesn't contain rm.
if ! echo "$COMMAND" | grep -qE '(^|[;&|]\s*|&&\s*|\|\|?\s*|\$\(\s*)rm\s'; then
  exit 0
fi

cat << 'EOF'
{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"Do not use rm. Use rip instead (rm-improved, rip2). It moves files to a graveyard (~/.local/share/graveyard) instead of deleting permanently.\n\nUsage: rip <files>...\n  rip -s          # list buried files in current directory\n  rip -u          # restore last buried file\n  rip -u <file>   # restore specific file\n\nReplace your rm command with rip and retry."}}
EOF
exit 0
