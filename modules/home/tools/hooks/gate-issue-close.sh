# shellcheck shell=bash
# Hook: Self-verification gate for issue closure
# Intercepts `bd close` commands and verifies acceptance criteria before allowing closure.
# Extracts verification commands from acceptance_criteria field code blocks and inline code,
# executes them, and blocks closure if any command fails.
# Issues without acceptance_criteria or with only prose criteria pass through.
# PreToolUse:Bash (sync) -- reads JSON context from stdin.

set -euo pipefail

INPUT=$(cat)

# Only check Bash commands containing "bd close"
TOOL_INPUT=$(echo "$INPUT" | jq -r '.tool_input // empty')
if [ -z "$TOOL_INPUT" ]; then
  exit 0
fi

COMMAND=$(echo "$TOOL_INPUT" | jq -r '.command // ""')

if ! echo "$COMMAND" | grep -qE 'bd\s+close'; then
  exit 0
fi

# Extract the ID being closed
CLOSE_ID=$(echo "$COMMAND" | sed -E 's/.*bd[[:space:]]+close[[:space:]]+([A-Za-z0-9._-]+).*/\1/')

if [ -z "$CLOSE_ID" ]; then
  exit 0
fi

# Skip epics (handled by validate-epic-close)
ISSUE_JSON=$(bd show "$CLOSE_ID" --json 2>/dev/null || echo "[]")
ISSUE_TYPE=$(echo "$ISSUE_JSON" | jq -r '.[0].issue_type // ""' 2>/dev/null || echo "")

if [ "$ISSUE_TYPE" = "epic" ]; then
  exit 0
fi

# Extract acceptance_criteria
ACCEPTANCE_CRITERIA=$(echo "$ISSUE_JSON" | jq -r '.[0].acceptance_criteria // ""' 2>/dev/null || echo "")

# If no acceptance_criteria, allow closure
if [ -z "$ACCEPTANCE_CRITERIA" ]; then
  exit 0
fi

# Extract verification commands from code blocks and inline code.
# Strategy:
#   1. Fenced code blocks: ```bash ... ``` or ``` ... ``` (multiline)
#   2. Inline code: `command here` (single backtick pairs)
# Filter to lines that look like executable commands (start with a common command token).

EXTRACTED_COMMANDS=""

# Extract from fenced code blocks (```...```)
# Use sed to extract content between ``` markers
FENCED=$(echo "$ACCEPTANCE_CRITERIA" | sed -n '/^```/,/^```/{/^```/d;p}')
if [ -n "$FENCED" ]; then
  EXTRACTED_COMMANDS="$FENCED"
fi

# Extract from inline code (`...`)
# Match single-backtick pairs, excluding those inside fenced blocks
INLINE=$(echo "$ACCEPTANCE_CRITERIA" | grep -oE '`[^`]+`' | sed 's/^`//;s/`$//' || true)
if [ -n "$INLINE" ]; then
  if [ -n "$EXTRACTED_COMMANDS" ]; then
    EXTRACTED_COMMANDS="$EXTRACTED_COMMANDS"$'\n'"$INLINE"
  else
    EXTRACTED_COMMANDS="$INLINE"
  fi
fi

# If no code was extracted, allow closure (prose-only criteria)
if [ -z "$EXTRACTED_COMMANDS" ]; then
  exit 0
fi

# Filter to lines that look like executable shell commands.
# Heuristic: starts with a known command prefix or path-like token.
# This avoids treating variable names, descriptions, or partial fragments as commands.
COMMAND_PREFIXES='(bd |nix |git |make |just |cargo |pytest |npm |npx |yarn |pnpm |bash |sh |zsh |test |echo |cat |ls |cd |mkdir |rm |cp |mv |grep |rg |fd |jq |curl |wget |python |node |deno |bun |tofu |terraform |kubectl |helm |docker |podman |gh |[.]/)'

RUNNABLE_COMMANDS=""
while IFS= read -r line; do
  # Skip empty lines and comments
  trimmed=$(echo "$line" | sed 's/^[[:space:]]*//')
  if [ -z "$trimmed" ] || [[ "$trimmed" == \#* ]]; then
    continue
  fi
  # Check if line starts with a recognized command prefix
  if echo "$trimmed" | grep -qE "^${COMMAND_PREFIXES}"; then
    if [ -n "$RUNNABLE_COMMANDS" ]; then
      RUNNABLE_COMMANDS="$RUNNABLE_COMMANDS"$'\n'"$trimmed"
    else
      RUNNABLE_COMMANDS="$trimmed"
    fi
  fi
done <<< "$EXTRACTED_COMMANDS"

# If no runnable commands found, allow closure (criteria are prose descriptions)
if [ -z "$RUNNABLE_COMMANDS" ]; then
  exit 0
fi

# Execute each command and collect results
PASS_COUNT=0
FAIL_COUNT=0
RESULTS=""

while IFS= read -r cmd; do
  if [ -z "$cmd" ]; then
    continue
  fi

  # Execute the command, capturing output and exit code
  CMD_OUTPUT=""
  CMD_EXIT=0
  CMD_OUTPUT=$(timeout 30 bash -c "$cmd" 2>&1) || CMD_EXIT=$?

  if [ "$CMD_EXIT" -eq 0 ]; then
    PASS_COUNT=$((PASS_COUNT + 1))
    RESULTS="${RESULTS}PASS: ${cmd}\n"
  else
    FAIL_COUNT=$((FAIL_COUNT + 1))
    # Truncate output to avoid oversized JSON
    TRUNCATED_OUTPUT=$(echo "$CMD_OUTPUT" | head -20)
    RESULTS="${RESULTS}FAIL (exit ${CMD_EXIT}): ${cmd}\n  Output: ${TRUNCATED_OUTPUT}\n"
  fi
done <<< "$RUNNABLE_COMMANDS"

# If all commands passed, allow closure
if [ "$FAIL_COUNT" -eq 0 ]; then
  # Format verification summary for the closure reason
  VERIFY_SUMMARY="Self-verification gate: ${PASS_COUNT}/${PASS_COUNT} commands passed."
  cat << EOF
{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow","permissionDecisionReason":"${VERIFY_SUMMARY} Include verification results in the closure reason."}}
EOF
  exit 0
fi

# Some commands failed: block closure
TOTAL=$((PASS_COUNT + FAIL_COUNT))
ESCAPED_RESULTS=$(printf '%s' "$RESULTS" | sed 's/\\/\\\\/g' | sed 's/"/\\"/g' | sed ':a;N;$!ba;s/\n/\\n/g')

cat << EOF
{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"Self-verification gate: ${FAIL_COUNT}/${TOTAL} commands failed. Fix failures before closing ${CLOSE_ID}.\n\nResults:\n${ESCAPED_RESULTS}\n\nEither fix the issues and retry closure, or escalate with failure details."}}
EOF
exit 0
