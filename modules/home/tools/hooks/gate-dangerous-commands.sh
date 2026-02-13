# shellcheck shell=bash
# Hook: Gate dangerous commands
# Returns permissionDecision "ask" for commands with external side effects,
# destructive potential, or arbitrary code execution capability.
# Commands not matching any pattern exit silently, falling through to the
# blanket Bash allow in the permission system.
#
# Companion hooks handle specific domains:
#   redirect-rm-to-rip: denies rm, redirects to rip (rm-improved)
#   gate-mutating-http: allows safe curl/wget GETs, asks for mutations
#
# PreToolUse:Bash (sync) -- reads JSON context from stdin.

set -euo pipefail

INPUT=$(cat)

TOOL_INPUT=$(echo "$INPUT" | jq -r '.tool_input // empty')
if [ -z "$TOOL_INPUT" ]; then
  exit 0
fi

COMMAND=$(echo "$TOOL_INPUT" | jq -r '.command // ""')
if [ -z "$COMMAND" ]; then
  exit 0
fi

# Match a command token at start-of-line or after shell operators (&&, ||, ;, |, $())
cmd_match() {
  echo "$COMMAND" | grep -qE "(^|[;&|]\s*|&&\s*|\|\|?\s*|\\\$\(\s*)$1"
}

REASON=""

# --- Privilege escalation ---
cmd_match 'sudo\s' && REASON="sudo requires approval"

# --- Git: push and destructive operations ---
if [ -z "$REASON" ]; then
  cmd_match 'git push(\s|$)' && REASON="git push requires approval"
fi
if [ -z "$REASON" ]; then
  cmd_match 'git reset --hard' && REASON="git reset --hard discards commits/changes"
fi
if [ -z "$REASON" ]; then
  cmd_match 'git clean\s' && REASON="git clean removes untracked files"
fi
if [ -z "$REASON" ]; then
  echo "$COMMAND" | grep -qE '(^|[;&|]\s*|&&\s*|\|\|?\s*|\$\(\s*)git checkout( --)? \.' \
    && REASON="git checkout . discards unstaged changes"
fi
if [ -z "$REASON" ]; then
  echo "$COMMAND" | grep -qE '(^|[;&|]\s*|&&\s*|\|\|?\s*|\$\(\s*)git restore( --staged)? \.' \
    && REASON="git restore . discards or unstages all changes"
fi
if [ -z "$REASON" ]; then
  cmd_match 'git branch -D\s' && REASON="git branch -D force-deletes a branch"
fi
if [ -z "$REASON" ]; then
  cmd_match 'git stash (drop|clear)' && REASON="git stash drop/clear permanently loses stashed work"
fi

# --- GitHub CLI: mutating operations ---
if [ -z "$REASON" ]; then
  cmd_match 'gh api\s' && REASON="gh api can make arbitrary mutations"
fi
if [ -z "$REASON" ]; then
  cmd_match 'gh (pr|issue) (create|comment|merge|close|edit|review)\b' \
    && REASON="mutating gh pr/issue operation"
fi
if [ -z "$REASON" ]; then
  cmd_match 'gh repo (create|delete|rename)\b' && REASON="mutating gh repo operation"
fi
if [ -z "$REASON" ]; then
  cmd_match 'gh release (create|delete)\b' && REASON="mutating gh release operation"
fi
if [ -z "$REASON" ]; then
  cmd_match 'gh workflow run\b' && REASON="gh workflow run triggers CI"
fi
if [ -z "$REASON" ]; then
  cmd_match 'gh gist create\b' && REASON="gh gist create may expose code publicly"
fi

# --- Nix: arbitrary code execution ---
if [ -z "$REASON" ]; then
  cmd_match 'nix (run|shell)\s' && REASON="nix run/shell executes arbitrary code"
fi

# --- Infrastructure mutation ---
if [ -z "$REASON" ]; then
  cmd_match '(tofu|terraform) (apply|destroy)' && REASON="infrastructure mutation"
fi
if [ -z "$REASON" ]; then
  cmd_match 'kubectl (apply|create|delete|exec)\s' && REASON="kubectl cluster mutation"
fi
if [ -z "$REASON" ]; then
  cmd_match 'helm (install|upgrade|uninstall)\s' && REASON="helm release mutation"
fi

# --- Remote access ---
if [ -z "$REASON" ]; then
  cmd_match 'ssh\s' && REASON="remote shell access"
fi
if [ -z "$REASON" ]; then
  cmd_match 'scp\s' && REASON="remote file transfer"
fi
if [ -z "$REASON" ]; then
  cmd_match 'rsync\s' && REASON="remote sync"
fi

# --- Container publishing ---
if [ -z "$REASON" ]; then
  cmd_match '(docker|podman) push\s' && REASON="container image push to registry"
fi

# --- Process management ---
if [ -z "$REASON" ]; then
  cmd_match '(kill|killall|pkill)\s' && REASON="process termination"
fi

# --- Destructive file operations (rm bypass vectors) ---
if [ -z "$REASON" ]; then
  echo "$COMMAND" | grep -qE 'find\s.*-delete' && REASON="find -delete removes files"
fi
if [ -z "$REASON" ]; then
  echo "$COMMAND" | grep -qE 'find\s.*-exec.*\brm\b' && REASON="find -exec rm removes files"
fi
if [ -z "$REASON" ]; then
  echo "$COMMAND" | grep -qE '(^|[|])\s*xargs\s.*\brm\b' && REASON="xargs rm removes files"
fi

# --- Raw writes and secure deletion ---
if [ -z "$REASON" ]; then
  cmd_match 'dd\s' && REASON="dd performs raw writes"
fi
if [ -z "$REASON" ]; then
  cmd_match 'truncate\s' && REASON="truncate zeroes out files"
fi
if [ -z "$REASON" ]; then
  cmd_match 'shred\s' && REASON="shred securely deletes files"
fi

# No match: exit silently, falls through to blanket Bash allow
if [ -z "$REASON" ]; then
  exit 0
fi

# Match found: escalate to user approval
cat << EOF
{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":"$REASON"}}
EOF
exit 0
