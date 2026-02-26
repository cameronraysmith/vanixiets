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

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  cat << 'HELPEOF'
gate-dangerous-commands: PreToolUse hook returning "ask" for dangerous Bash commands.

Companion hooks (not listed here):
  redirect-rm-to-rip   denies rm, redirects to rip (rm-improved)
  gate-mutating-http   allows safe curl/wget GETs, asks for mutations

Gated patterns (each returns permissionDecision "ask"):

  Privilege escalation
    sudo *

  Git: push and destructive operations
    git push
    git reset --hard *
    git clean *
    git checkout [--] .
    git restore [--staged] .
    git branch -D *
    git stash drop/clear

  GitHub CLI: mutating operations
    gh api * (except actions/runs/*/logs)
    gh pr create/comment/merge/close/edit/review
    gh issue create/comment/merge/close/edit/review
    gh repo create/delete/rename
    gh release create/delete
    gh workflow run
    gh gist create

  Nix: arbitrary code execution
    nix run *
    nix shell *

  Infrastructure mutation
    tofu/terraform apply/destroy
    kubectl apply/create/delete/exec
    helm install/upgrade/uninstall

  Remote access
    ssh *
    scp *
    rsync *

  Container publishing
    docker/podman push *

  Process management
    kill/killall/pkill *

  Destructive file operations (rm bypass vectors)
    find ... -delete
    find ... -exec rm
    xargs ... rm

  Raw writes and secure deletion
    dd *
    truncate *
    shred *

Patterns match commands at start-of-line or after shell operators (&&, ||, ;, |, $()).
Commands not matching any pattern fall through to blanket Bash allow.
HELPEOF
  exit 0
fi

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
  if cmd_match 'gh api\s'; then
    # Block gh api mutations that would bypass gated gh subcommands.
    # Read-only calls (bare endpoint, -X GET) pass through ungated.
    if echo "$COMMAND" | grep -qiE '(-X|--method)\s+(POST|PUT|PATCH|DELETE)\b'; then
      REASON="gh api with mutating HTTP method"
    elif echo "$COMMAND" | grep -qE '\s--input[\s=]'; then
      REASON="gh api with --input (implies mutation)"
    elif echo "$COMMAND" | grep -qE '\s(-f|-F|--raw-field)\s'; then
      if ! echo "$COMMAND" | grep -qiE '(-X|--method)\s+GET\b'; then
        REASON="gh api with field flags (defaults to POST)"
      fi
    fi
  fi
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

# Match found: notify before escalating to user approval
BRIEF=$(echo "$COMMAND" | head -c 200)
notify-permission-wait "Bash" "$BRIEF" &>/dev/null &
disown

cat << EOF
{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":"$REASON"}}
EOF
exit 0
