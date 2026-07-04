# shellcheck shell=bash
# Hook: Lightweight session start grounding
# Surfaces uncommitted changes and open PRs.
# SessionStart (sync) -- reads JSON context from stdin, outputs plain text to stdout.

set -euo pipefail

# Consume stdin (SessionStart provides session context)
cat > /dev/null

# Track whether we've output anything
HAS_OUTPUT=false

# Guard: check for git repo
IN_GIT_REPO=false
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  IN_GIT_REPO=true
fi

REPO_ROOT=""
if [ "$IN_GIT_REPO" = true ]; then
  REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || echo "")
fi

# Not inside a git repo: nothing to report
if [ "$IN_GIT_REPO" = false ]; then
  exit 0
fi

# === Dirty repo warning ===
if [ "$IN_GIT_REPO" = true ]; then
  DIRTY=$(git status --porcelain 2>/dev/null || echo "")
  if [ -n "$DIRTY" ]; then
    CHANGED_COUNT=$(echo "$DIRTY" | wc -l | tr -d ' ')
    echo "Warning: $CHANGED_COUNT uncommitted change(s) in working tree."
    echo "  Implementation work should happen in .worktrees/ for isolation."
    HAS_OUTPUT=true
  fi
fi

# === Worktree cleanup suggestions ===
if [ "$IN_GIT_REPO" = true ] && [ -d "$REPO_ROOT/.worktrees" ]; then
  for worktree in $(git worktree list --porcelain 2>/dev/null | grep "^worktree.*\.worktrees/" | sed 's/^worktree //'); do
    WT_BASENAME=$(basename "$worktree")
    if git branch --merged main 2>/dev/null | grep -q "$WT_BASENAME"; then
      if [ "$HAS_OUTPUT" = true ]; then echo ""; fi
      echo "Merged worktree $WT_BASENAME can be cleaned up:"
      echo "  git worktree remove $worktree"
      HAS_OUTPUT=true
    fi
  done
fi

# === Open PR reminder ===
if [ "$IN_GIT_REPO" = true ] && command -v gh >/dev/null 2>&1; then
  OPEN_PRS=$(gh pr list --author "@me" --state open --json number,title,headRefName --jq '.[] | "#\(.number) \(.title) [\(.headRefName)]"' 2>/dev/null || echo "")
  if [ -n "$OPEN_PRS" ]; then
    if [ "$HAS_OUTPUT" = true ]; then echo ""; fi
    echo "Open PRs:"
    echo "$OPEN_PRS"
    HAS_OUTPUT=true
  fi
fi

exit 0
