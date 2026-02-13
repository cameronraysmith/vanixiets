# shellcheck shell=bash
# Hook: Gate mutating HTTP requests
# Auto-approves safe (read-only) curl/wget commands.
# Returns "ask" for mutating requests so the user is prompted.
# Does not cover httpie (http/https commands) or xh which use positional method
# arguments -- add patterns if these tools enter the workflow.
# PreToolUse:Bash (sync) -- reads JSON context from stdin.

set -euo pipefail

INPUT=$(cat)

TOOL_INPUT=$(echo "$INPUT" | jq -r '.tool_input // empty')
if [ -z "$TOOL_INPUT" ]; then
  exit 0
fi

COMMAND=$(echo "$TOOL_INPUT" | jq -r '.command // ""')

# Check if the command contains curl or wget as a token
HAS_CURL=false
HAS_WGET=false
if echo "$COMMAND" | grep -qE '(^|[;&|]\s*|&&\s*|\|\|?\s*|\$\(\s*)curl\s'; then
  HAS_CURL=true
fi
if echo "$COMMAND" | grep -qE '(^|[;&|]\s*|&&\s*|\|\|?\s*|\$\(\s*)wget\s'; then
  HAS_WGET=true
fi

# Not a curl/wget command; don't interfere
if ! $HAS_CURL && ! $HAS_WGET; then
  exit 0
fi

REASON=""

# --- curl mutation detection ---
if $HAS_CURL; then
  # Explicit mutating method flags
  if echo "$COMMAND" | grep -qiE -- '-X\s*(POST|PUT|DELETE|PATCH)'; then
    REASON="curl with mutating HTTP method"
  fi
  if [ -z "$REASON" ] && echo "$COMMAND" | grep -qiE -- '--request\s*(POST|PUT|DELETE|PATCH)'; then
    REASON="curl with mutating HTTP method"
  fi
  # No-space variant: -XPOST, -XPUT, etc.
  if [ -z "$REASON" ] && echo "$COMMAND" | grep -qiE -- '-X(POST|PUT|DELETE|PATCH)'; then
    REASON="curl with mutating HTTP method"
  fi
  # Implicit POST via data flags
  if [ -z "$REASON" ] && echo "$COMMAND" | grep -qE -- '(\s-d\s|--data\b|--data-raw\b|--data-binary\b|--data-urlencode\b)'; then
    REASON="curl with data payload (implicit POST)"
  fi
  # Implicit POST via form upload
  if [ -z "$REASON" ] && echo "$COMMAND" | grep -qE -- '(\s-F\s|--form\b)'; then
    REASON="curl with form upload (implicit POST)"
  fi
  # Implicit PUT via file upload
  if [ -z "$REASON" ] && echo "$COMMAND" | grep -qE -- '(\s-T\s|--upload-file\b)'; then
    REASON="curl with file upload (implicit PUT)"
  fi
  # Implicit POST via --json flag
  if [ -z "$REASON" ] && echo "$COMMAND" | grep -qE -- '--json\b'; then
    REASON="curl with --json (implicit POST)"
  fi
fi

# --- wget mutation detection ---
if $HAS_WGET && [ -z "$REASON" ]; then
  if echo "$COMMAND" | grep -qE -- '(--post-data\b|--post-file\b)'; then
    REASON="wget with POST data"
  fi
  if [ -z "$REASON" ] && echo "$COMMAND" | grep -qiE -- '--method=(POST|PUT|DELETE|PATCH)'; then
    REASON="wget with mutating HTTP method"
  fi
fi

# Mutating request detected: escalate to user
if [ -n "$REASON" ]; then
  cat << EOF
{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":"$REASON"}}
EOF
  exit 0
fi

# No mutating indicators detected; auto-approve as read-only
cat << 'EOF'
{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow"}}
EOF
exit 0
