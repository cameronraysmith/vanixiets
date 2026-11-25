# shellcheck shell=bash
# Hook: Gate mutating HTTP requests
# Every curl or wget command that mutates (a POST, PUT, DELETE or PATCH method,
# data, a form, an upload, --json, or one of these flags inside a short-option
# cluster such as -sd) asks, whatever its host; one that does not is allowed.
# curl and wget are matched as words anywhere in the command, so xargs, loops
# and environment-assignment prefixes reach the gate; a mention of either word
# beside a mutating flag over-asks rather than slips through.
# Outside the gate: other HTTP clients (httpie, xh, language runtimes) and
# proxies set in the session's environment or ~/.curlrc.
# PreToolUse:Bash (sync) -- reads JSON context from stdin.

set -euo pipefail

INPUT=$(cat)

TOOL_INPUT=$(echo "$INPUT" | jq -r '.tool_input // empty')
if [ -z "$TOOL_INPUT" ]; then
  exit 0
fi

COMMAND=$(echo "$TOOL_INPUT" | jq -r '.command // ""')

# curl or wget as a word, wherever it stands
HAS_CURL=false
HAS_WGET=false
if echo "$COMMAND" | grep -qE '(^|[^A-Za-z0-9_.-])curl([[:space:]]|$)'; then
  HAS_CURL=true
fi
if echo "$COMMAND" | grep -qE '(^|[^A-Za-z0-9_.-])wget([[:space:]]|$)'; then
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
  # A data, form or upload flag inside a short-option cluster (-sd, -dhi, -sF)
  # or a method flag there (-sXPOST)
  if [ -z "$REASON" ] && echo "$COMMAND" | grep -qE -- '(^|\s)-[A-Za-z0-9]*([dFT]|X\s*(POST|PUT|DELETE|PATCH))'; then
    REASON="curl with a mutating flag in an option cluster"
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

# Mutating request detected: notify before escalating to user
if [ -n "$REASON" ]; then
  BRIEF=$(echo "$COMMAND" | head -c 200)
  notify-permission-wait "Bash" "$BRIEF" &>/dev/null &

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
