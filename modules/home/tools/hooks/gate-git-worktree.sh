# shellcheck shell=bash
# Hook: Deny `git worktree add` in jj-managed repositories
# Raw git worktrees are never wanted in a jj repo, even when the
# CLAUDE_JJ_WORKSPACE_ISOLATION escape hatch is on (that hatch creates a jj
# workspace via the WorktreeCreate hook, not a git worktree). This deny is
# therefore unconditional with respect to the env flag.
# Only `git worktree add` is denied; `git worktree list/remove/prune` are allowed.
# In a pure-git repository this hook exits silently (allow), so git-native
# worktree workflows are untouched.
# PreToolUse:Bash (sync) -- reads JSON context from stdin.

set -euo pipefail

INPUT=$(cat)

COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // ""' 2>/dev/null || true)
if [ -z "$COMMAND" ]; then
  exit 0
fi

CWD=$(echo "$INPUT" | jq -r '.cwd // empty' 2>/dev/null || true)
if [ -z "$CWD" ]; then
  CWD="$PWD"
fi

# --- jj-mode detection ---
# Walk up from cwd looking for .jj/. Empty if not jj-managed.
JJ_ROOT=""
dir="$CWD"
while [ "$dir" != "/" ]; do
  if [ -d "$dir/.jj" ]; then
    JJ_ROOT="$dir"
    break
  fi
  dir=$(dirname "$dir")
done

if [ -z "$JJ_ROOT" ]; then
  # Not a jj repo; git worktrees are documented git-native workflow.
  exit 0
fi

# Match `git ... worktree ... add` (the create form only). The intervening
# tokens allow global options like -C/--no-pager between git and worktree.
if echo "$COMMAND" | grep -qE '(^|[;&|]\s*|&&\s*|\|\|?\s*|\$\(\s*)git(\s+\S+)*\s+worktree(\s+\S+)*\s+add(\s|$)'; then
  REDIRECT_MSG="Worktree creation is blocked in jj mode. Parallel chains of work use the diamond workflow's development join, not git worktrees. If you genuinely need an isolated working copy, use 'jj workspace add' instead. See ~/.claude/skills/jj-version-control/diamond-workflow.md (Development join section) and ~/.claude/skills/jj-summary/SKILL.md."
  cat << EOF
{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"git worktree add is disabled in jj-managed repositories. $REDIRECT_MSG"}}
EOF
  exit 0
fi

# All other git worktree subcommands (list/remove/prune) and everything else allow.
exit 0
