# shellcheck shell=bash
# Hook: Enforce feature branch before file edits
# Prevents editing tracked files on main/master branch.
# Allows configuration, plan, and issue tracking files unconditionally.
# PreToolUse:Edit|Write|MultiEdit (sync) -- reads JSON context from stdin.

set -euo pipefail

INPUT=$(cat)

# Extract file path from tool input
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

# Allow edits if no file path (shouldn't happen, but fail open)
if [ -z "$FILE_PATH" ]; then
  exit 0
fi

# Allow list: always permit edits to these paths
if echo "$FILE_PATH" | grep -qE '(/\.claude/|CLAUDE\.md$|CLAUDE\.local\.md$|/plans/|/\.beads/)'; then
  exit 0
fi

# Allow edits within .worktrees/ (worktrees are the standard isolation mechanism)
if echo "$FILE_PATH" | grep -qE '/\.worktrees/'; then
  exit 0
fi

# Allow if CWD is inside a .worktrees/ directory
CWD=$(pwd)
if echo "$CWD" | grep -qE '/\.worktrees/'; then
  exit 0
fi

# Check if we're in a git repo
if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  exit 0
fi

# Get current branch name
BRANCH=$(git symbolic-ref --short HEAD 2>/dev/null || echo "")
if [ -z "$BRANCH" ]; then
  # Detached HEAD or other non-branch state; allow the edit
  exit 0
fi

# Block edits on main or master
if [ "$BRANCH" = "main" ] || [ "$BRANCH" = "master" ]; then
  cat << EOF
{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"Cannot edit files on $BRANCH branch. Create a worktree for your bead:\n  git worktree add .worktrees/{ID}-descriptor -b {ID}-descriptor\n  cd .worktrees/{ID}-descriptor\n(e.g. git worktree add .worktrees/nix-btd-2-my-task -b nix-btd-2-my-task)\nOr create a feature branch:\n  git checkout -b {ID}-descriptor\nThen retry the edit."}}
EOF
  exit 0
fi

# On a feature branch; allow the edit
exit 0
