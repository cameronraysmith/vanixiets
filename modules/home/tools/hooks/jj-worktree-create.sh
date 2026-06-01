# shellcheck shell=bash
# Hook: WorktreeCreate -- supply the isolation worktree path
# Replaces Claude Code's default `git worktree add` behavior for all three
# worktree-isolation entry paths (the --worktree launch flag, the EnterWorktree
# tool, and subagent isolation="worktree").
#
# In a jj-managed repository, a raw git worktree is NEVER created:
#   - default: abort isolation (exit 1) so work happens in place in the
#     colocated working copy (the jj development join).
#   - CLAUDE_JJ_WORKSPACE_ISOLATION=1: redirect isolation to a jj workspace
#     created under <jj_root>/.claude/worktrees/<name>.
# In a pure-git repository, reproduce the documented default: create a git
# worktree under <git_root>/.claude/worktrees/<name>.
#
# Stdin is JSON: {session_id, transcript_path, cwd, hook_event_name, name}.
# Success: print the created worktree's absolute path on stdout, exit 0.
# Abort: print a message to stderr, exit non-zero.
# WorktreeCreate (sync) -- reads JSON context from stdin.

set -euo pipefail

INPUT=$(cat)

NAME=$(echo "$INPUT" | jq -r '.name // empty' 2>/dev/null || true)
CWD=$(echo "$INPUT" | jq -r '.cwd // empty' 2>/dev/null || true)
if [ -z "$CWD" ]; then
  CWD="$PWD"
fi
if [ -z "$NAME" ]; then
  echo "WorktreeCreate: no worktree name supplied; cannot create isolation worktree." >&2
  exit 1
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

if [ -n "$JJ_ROOT" ]; then
  DEST="$JJ_ROOT/.claude/worktrees/$NAME"
  if [ "${CLAUDE_JJ_WORKSPACE_ISOLATION:-0}" = "1" ]; then
    # Escape hatch: redirect harness isolation to a jj workspace.
    # The added workspace has only .jj (no .git); that is expected for this path.
    # jj workspace add does not create intermediate parent directories, so the
    # .claude/worktrees/ parent must exist first (git worktree add creates it).
    mkdir -p "$(dirname "$DEST")"
    jj --repository "$JJ_ROOT" workspace add --name "$NAME" "$DEST" >&2
    echo "$DEST"
    exit 0
  fi
  echo "Worktree isolation is disabled in jj-managed repositories -- work in place in the colocated working copy (the jj development join), or set CLAUDE_JJ_WORKSPACE_ISOLATION=1 to use a jj workspace, or run 'jj workspace add' manually. NEVER a git worktree." >&2
  exit 1
fi

# --- pure-git repository ---
# Reproduce Claude Code's documented default worktree-isolation behavior.
ROOT=$(git -C "$CWD" rev-parse --show-toplevel 2>/dev/null || true)
if [ -z "$ROOT" ]; then
  echo "WorktreeCreate: cwd '$CWD' is neither a jj nor a git repository; cannot create isolation worktree." >&2
  exit 1
fi
DEST="$ROOT/.claude/worktrees/$NAME"
git -C "$ROOT" worktree add -b "worktree-$NAME" "$DEST" >&2
echo "$DEST"
exit 0
