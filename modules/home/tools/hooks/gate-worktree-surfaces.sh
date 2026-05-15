# shellcheck shell=bash
# Hook: Gate worktree-creating tool surfaces in jj mode
# Blocks EnterWorktree, ExitWorktree, and Task dispatches with
# tool_input.isolation == "worktree" whenever the repository at cwd
# is jj-managed (a .jj/ directory exists at cwd or any ancestor).
# Parallel work in jj mode uses the diamond workflow's development
# join, not git worktrees -- see jj-version-control/diamond-workflow.md.
# Note: the "join N=k: ..." description prefix is a project convention
# used in this repo's diamond-workflow tooling; see ~/.claude/skills/jj-version-control/SKILL.md.
# PreToolUse (sync) -- reads JSON context from stdin.

set -euo pipefail

INPUT=$(cat)

TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null || true)
if [ -z "$TOOL_NAME" ]; then
  exit 0
fi

# --- jj-mode detection ---
# Walk up from cwd looking for .jj/. Empty if not jj-managed.
JJ_ROOT=""
dir=$(pwd)
while [ "$dir" != "/" ]; do
  if [ -d "$dir/.jj" ]; then
    JJ_ROOT="$dir"
    break
  fi
  dir=$(dirname "$dir")
done

if [ -z "$JJ_ROOT" ]; then
  # Not a jj repo; worktrees are documented git-native workflow.
  exit 0
fi

REDIRECT_MSG="Worktrees are blocked in jj mode. Parallel chains of work use the diamond workflow's development join, not git worktrees. See ~/.claude/skills/jj-version-control/diamond-workflow.md (Development join section) and ~/.claude/skills/jj-summary/SKILL.md."

case "$TOOL_NAME" in
  EnterWorktree|ExitWorktree)
    cat << EOF
{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"$TOOL_NAME is disabled in jj-managed repositories. $REDIRECT_MSG"}}
EOF
    exit 0
    ;;
  Task)
    ISOLATION=$(echo "$INPUT" | jq -r '.tool_input.isolation // empty' 2>/dev/null || true)
    if [ "$ISOLATION" = "worktree" ]; then
      cat << EOF
{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"Task dispatch with isolation=\"worktree\" is disabled in jj-managed repositories. Drop the isolation parameter (the subagent will inherit cwd and operate against the same jj working copy) or route parallel work through a new chain on the diamond development join. $REDIRECT_MSG"}}
EOF
      exit 0
    fi
    ;;
esac

# All other cases allow.
exit 0
