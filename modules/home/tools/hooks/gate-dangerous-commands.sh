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

  Git: push and destructive operations (matches through global options like -C, --no-pager)
    git [-C path] [--global-opts...] push
    git [-C path] [--global-opts...] reset --hard *
    git [-C path] [--global-opts...] clean *
    git [-C path] [--global-opts...] checkout [--] .
    git [-C path] [--global-opts...] restore [--staged] .
    git [-C path] [--global-opts...] branch -D *
    git [-C path] [--global-opts...] stash drop/clear

  Jujutsu: push (matches through global options like -R, --no-pager)
    jj [-R path] [--global-opts...] git push

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
Git patterns match through global options (-C, -c, --git-dir, --work-tree, --no-pager, etc.).
Jujutsu patterns match through global options (-R, --repository, --at-op, --no-pager, etc.).
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

# Match git subcommand accounting for global options between 'git' and the subcommand.
# Without this, patterns like 'git push' are bypassed by 'git -C /path push'.
# Enumerates git global options explicitly because flags with vs without arguments
# cannot be distinguished by regex without knowing which is which.
git_cmd_match() {
  local flag_arg='-[Cc]\s+\S+|--git-dir(=|\s)\S+|--work-tree(=|\s)\S+|--namespace(=|\s)\S+|--exec-path(=|\s)\S+|--config-env(=|\s)\S+'
  local flag_no_arg='--no-pager|--bare|--paginate|-p|--no-replace-objects|--literal-pathspecs|--glob-pathspecs|--noglob-pathspecs|--icase-pathspecs|--no-optional-locks|--no-lazy-fetch'
  local git_opts="(\s+(${flag_arg}|${flag_no_arg}))*"
  echo "$COMMAND" | grep -qE "(^|[;&|]\s*|&&\s*|\|\|?\s*|\\\$\(\s*)git${git_opts}\s+$1"
}

# Match jj subcommand accounting for global options between 'jj' and the subcommand.
# Without this, patterns like 'jj git push' are bypassed by 'jj -R /path git push'.
jj_cmd_match() {
  local flag_arg='-R\s+\S+|--repository(=|\s)\S+|--at-op(eration)?(=|\s)\S+|--color(=|\s)\S+|--config(=|\s)\S+|--config-file(=|\s)\S+'
  local flag_no_arg='--no-pager|--quiet|--verbose|--debug|--ignore-working-copy'
  local jj_opts="(\s+(${flag_arg}|${flag_no_arg}))*"
  echo "$COMMAND" | grep -qE "(^|[;&|]\s*|&&\s*|\|\|?\s*|\\\$\(\s*)jj${jj_opts}\s+$1"
}

# Fire-and-forget NOTICE via ntfy-send when a relaxed gate arm permits an action
# that previously escalated. Backgrounded with disown so PreToolUse stays sync-fast.
# Reads $COMMAND from outer scope; first arg is a short category label.
notify_permitted() {
  local category="$1"
  local brief repo_name
  brief=$(echo "$COMMAND" | head -c 200)
  repo_name=$(basename "$(git rev-parse --show-toplevel 2>/dev/null || pwd)")
  ntfy-send \
    "claude-code permitted ${category}: ${brief}" \
    "" \
    -H "Title: NOTICE: ${category}" \
    -H "Priority: low" \
    -H "Tags: information_source,${repo_name}" \
    >/dev/null 2>&1 &
  disown
}

# Inspect git push args (everything after 'push'); return 0 if safe to auto-permit.
# Escalates on: bare push, --force/--force-with-lease, --all/--mirror/--tags,
# delete refspec (:branch), or any token referencing main/master/default ref.
push_is_safe() {
  local args="$1"
  [[ -z "${args// }" ]] && return 1
  echo "$args" | grep -qE '(^|[[:space:]])(-f\b|--force\b|--force-with-lease\b|--all\b|--mirror\b|--tags\b)' && return 1
  echo "$args" | grep -qE '(^|[[:space:]]):[^[:space:]]' && return 1
  local default_ref
  default_ref=$(git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null | sed 's|^origin/||')
  default_ref="${default_ref:-main}"
  echo "$args" | grep -qE "(^|[[:space:]:/])(${default_ref}|main|master)([[:space:]:/]|\$)" && return 1
  return 0
}

# Inspect jj git push args; return 0 if safe to auto-permit.
# Escalates on: bare push, --all-bookmarks/--deleted, --force*, or bookmark
# targeting main/master/trunk.
jj_push_is_safe() {
  local args="$1"
  [[ -z "${args// }" ]] && return 1
  echo "$args" | grep -qE '(^|[[:space:]])(--all-bookmarks\b|--deleted\b|--force-with-lease\b|-f\b|--force\b)' && return 1
  echo "$args" | grep -qE '(-b|--bookmark)([[:space:]=]+)(main|master|trunk)\b' && return 1
  return 0
}

REASON=""

# --- Privilege escalation ---
cmd_match 'sudo\s' && REASON="sudo requires approval"

# --- Git: push and destructive operations ---
# Uses git_cmd_match to handle global options (e.g. -C, --no-pager) between 'git' and subcommand.
# Push to non-default refs auto-permits with a NOTICE; pushes to main/master or with
# destructive flags continue to escalate.
if [ -z "$REASON" ]; then
  if git_cmd_match 'push(\s|$)'; then
    PUSH_ARGS=$(echo "$COMMAND" | sed -nE 's/.*\bgit\b[^|;&>]*\bpush\b[[:space:]]*([^|;&>]*).*/\1/p')
    if push_is_safe "$PUSH_ARGS"; then
      notify_permitted "git push (non-default ref)"
    else
      REASON="git push requires approval"
    fi
  fi
fi
if [ -z "$REASON" ]; then
  if jj_cmd_match 'git\s+push(\s|$)'; then
    JPUSH_ARGS=$(echo "$COMMAND" | sed -nE 's/.*\bjj\b[^|;&>]*\bgit[[:space:]]+push\b[[:space:]]*([^|;&>]*).*/\1/p')
    if jj_push_is_safe "$JPUSH_ARGS"; then
      notify_permitted "jj git push (non-default bookmark)"
    else
      REASON="jj git push requires approval"
    fi
  fi
fi
if [ -z "$REASON" ]; then
  git_cmd_match 'reset\s+--hard' && REASON="git reset --hard discards commits/changes"
fi
if [ -z "$REASON" ]; then
  git_cmd_match 'clean\s' && REASON="git clean removes untracked files"
fi
if [ -z "$REASON" ]; then
  git_cmd_match 'checkout( --)? \.' && REASON="git checkout . discards unstaged changes"
fi
if [ -z "$REASON" ]; then
  git_cmd_match 'restore( --staged)? \.' && REASON="git restore . discards or unstages all changes"
fi
if [ -z "$REASON" ]; then
  git_cmd_match 'branch\s+-D\s' && REASON="git branch -D force-deletes a branch"
fi
if [ -z "$REASON" ]; then
  git_cmd_match 'stash\s+(drop|clear)' && REASON="git stash drop/clear permanently loses stashed work"
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
  # gh pr create in canonical draft form (-d, -b "" or '', -B main|master) auto-permits
  # with NOTICE. All other gh pr/issue mutations escalate as before.
  if cmd_match 'gh pr create\b'; then
    has_draft=false
    has_empty_body=false
    targets_main=false
    echo "$COMMAND" | grep -qE '(^|[[:space:]])(-d|--draft)([[:space:]]|$)' && has_draft=true
    echo "$COMMAND" | grep -qE "(^|[[:space:]])(-b|--body)[[:space:]]+(\"\"|'')([[:space:]]|$)" && has_empty_body=true
    echo "$COMMAND" | grep -qE '(^|[[:space:]])(-B|--base)[[:space:]]+(main|master)([[:space:]]|$)' && targets_main=true
    if $has_draft && $has_empty_body && $targets_main; then
      notify_permitted "gh pr create (draft, base=main, empty body)"
    else
      REASON="gh pr create (non-canonical form) requires approval"
    fi
  elif cmd_match 'gh (pr|issue) (create|comment|merge|close|edit|review)\b'; then
    REASON="mutating gh pr/issue operation"
  fi
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
# ssh/scp/rsync targeting *.zt zerotier-VPN hosts auto-permit with NOTICE.
# All -J jump hosts (comma-list) must also be .zt. Other destinations escalate.
if [ -z "$REASON" ]; then
  if cmd_match 'ssh\s'; then
    # Match ssh ... [user@]host.zt (destination at end-of-token boundary)
    if echo "$COMMAND" | grep -qE '(^|[;&|]\s*|&&\s*|\|\|?\s*|\$\(\s*)ssh([[:space:]]+(-[A-Za-z][^[:space:]]*|-[A-Za-z][[:space:]]+[^[:space:]-][^[:space:]]*))*[[:space:]]+([A-Za-z0-9._-]+@)?[A-Za-z0-9_-]+(\.[A-Za-z0-9_-]+)*\.zt([[:space:]]|$)'; then
      jump_ok=true
      if echo "$COMMAND" | grep -qE '(^|[[:space:]])-J[[:space:]]'; then
        for h in $(echo "$COMMAND" | sed -nE 's/.*[[:space:]]-J[[:space:]]+([^[:space:]]+).*/\1/p' | tr ',' ' '); do
          [[ "$h" =~ \.zt$ ]] || { jump_ok=false; break; }
        done
      fi
      if $jump_ok; then
        notify_permitted "ssh to .zt host"
      else
        REASON="ssh -J jump host not on .zt domain"
      fi
    else
      REASON="remote shell access"
    fi
  fi
fi
if [ -z "$REASON" ]; then
  if cmd_match 'scp\s'; then
    # scp uses host:path syntax; permit when at least one .zt: destination present
    if echo "$COMMAND" | grep -qE '(^|[[:space:]])([A-Za-z0-9._-]+@)?[A-Za-z0-9_-]+(\.[A-Za-z0-9_-]+)*\.zt:'; then
      notify_permitted "scp to/from .zt host"
    else
      REASON="remote file transfer"
    fi
  fi
fi
if [ -z "$REASON" ]; then
  if cmd_match 'rsync\s'; then
    # rsync uses host:path syntax (over ssh); permit when at least one .zt: destination present
    if echo "$COMMAND" | grep -qE '(^|[[:space:]])([A-Za-z0-9._-]+@)?[A-Za-z0-9_-]+(\.[A-Za-z0-9_-]+)*\.zt:'; then
      notify_permitted "rsync to/from .zt host"
    else
      REASON="remote sync"
    fi
  fi
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
