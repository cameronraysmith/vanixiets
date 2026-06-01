# shellcheck shell=bash
# Hook: WorktreeRemove -- tear down the isolation worktree
# Companion to jj-worktree-create. Removes whatever that hook created:
#   - jj workspace (path has .jj and no .git): forget it, then rm -rf the path.
#   - git worktree (otherwise): git worktree remove --force, falling back to rm -rf.
# Best-effort: this event cannot block, so failures are tolerated and never
# propagated.
#
# Stdin is JSON: {session_id, transcript_path, cwd, hook_event_name,
# name, worktree_path}.
# WorktreeRemove (sync) -- reads JSON context from stdin.

set -euo pipefail

INPUT=$(cat)

WORKTREE_PATH=$(echo "$INPUT" | jq -r '.worktree_path // empty' 2>/dev/null || true)
if [ -z "$WORKTREE_PATH" ]; then
  exit 0
fi

CWD=$(echo "$INPUT" | jq -r '.cwd // empty' 2>/dev/null || true)
if [ -z "$CWD" ]; then
  CWD="$PWD"
fi

if [ -d "$WORKTREE_PATH/.jj" ] && [ ! -e "$WORKTREE_PATH/.git" ]; then
  # jj workspace: forget by basename from the main repo's cwd, then remove.
  WS_NAME=$(basename "$WORKTREE_PATH")
  jj --repository "$CWD" workspace forget "$WS_NAME" >/dev/null 2>&1 \
    || jj workspace forget "$WS_NAME" >/dev/null 2>&1 \
    || true
  rm -rf "$WORKTREE_PATH" >/dev/null 2>&1 || true
  exit 0
fi

# git worktree: prefer git's own removal, fall back to rm -rf.
git worktree remove --force "$WORKTREE_PATH" >/dev/null 2>&1 \
  || rm -rf "$WORKTREE_PATH" >/dev/null 2>&1 \
  || true
exit 0
