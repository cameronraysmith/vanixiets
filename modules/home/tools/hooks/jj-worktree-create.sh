# shellcheck shell=bash
# Hook: WorktreeCreate -- supply the isolation worktree path
# Replaces Claude Code's default `git worktree add` behavior for all three
# worktree-isolation entry paths (the --worktree launch flag, the EnterWorktree
# tool, and subagent isolation="worktree").
#
# Every repository gets a git worktree under <root>/.claude/worktrees/<name> on
# a fresh branch worktree-<name>. In a jj-managed repository, setting
# CLAUDE_JJ_WORKSPACE_ISOLATION=1 selects a jj workspace at that path instead.
# jj 0.46.0 and later colocates that workspace by default (a git worktree with
# .git beside .jj), keeping flake fidelity; a non-colocated jj workspace has no
# .git, so nix flake evaluation there degrades to a revisionless path: source
# (jj-vcs/jj#4436).
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
    # From a colocated repository with git.colocate=true the workspace is
    # colocated; otherwise it has only .jj and no .git.
    # jj workspace add does not create intermediate parent directories, so the
    # .claude/worktrees/ parent must exist first (git worktree add creates it).
    mkdir -p "$(dirname "$DEST")"
    jj --repository "$JJ_ROOT" workspace add --name "$NAME" "$DEST" >&2
    echo "$DEST"
    exit 0
  fi
  # Colocation means .git sits beside .jj at the same root. Tested by existence
  # rather than by comparing `git rev-parse --show-toplevel` against JJ_ROOT:
  # git resolves symlinks in that output and JJ_ROOT comes from the payload cwd
  # unresolved, so the string comparison rejects every colocated repository
  # reached through a symlinked path. A jj workspace or a non-colocated repo has
  # no .git here and is still rejected, as is a .jj nested inside an outer git
  # repository whose root lies further up.
  if [ ! -e "$JJ_ROOT/.git" ]; then
    echo "WorktreeCreate: jj repository '$JJ_ROOT' is not colocated with git, so it has no git worktrees." >&2
    exit 1
  fi
  # worktree-<name> is branched from the primary's detached HEAD, so it can sit
  # on a commit jj later rewrites; jj then moves the bookmark and this worktree's
  # HEAD detaches at the old commit, files and index untouched. Reattach with
  # `git symbolic-ref HEAD refs/heads/worktree-<name>` -- never `git checkout -f`,
  # which discards uncommitted work.
  git -C "$JJ_ROOT" worktree add -b "worktree-$NAME" "$DEST" >&2
  echo "$DEST"
  exit 0
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
