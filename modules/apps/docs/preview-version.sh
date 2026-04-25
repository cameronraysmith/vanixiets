#!/usr/bin/env bash
# shellcheck shell=bash
# preview-version.sh - Preview semantic-release version after merging to target branch
#
# Usage:
#   nix run .#preview-version -- [target-branch] [package-path]
#
# Examples:
#   nix run .#preview-version                         # Preview root version on main
#   nix run .#preview-version -- main packages/docs   # Preview docs package version on main
#   nix run .#preview-version -- beta packages/docs   # Preview docs version on beta
#
# This script simulates merging the current branch into the target branch and
# runs semantic-release in dry-run mode to preview what version would be released.
#
# Hermetic: DOCS_NODE_MODULES (set by preview-version.nix) points to a read-only
# node_modules tree produced by the vanixiets-docs-deps derivation. This script
# links it into the worktree's package directory and invokes semantic-release
# directly via node_modules/.bin, bypassing any need for bun or a prior
# `bun install`.
#
# Env-var contract (per ADR-002 / env-var-contract-design.md §2.2):
#   Required (config, injected by preview-version.nix runtimeEnv):
#     DOCS_NODE_MODULES   store path of the vanixiets-docs-deps node_modules
#                         tree (hosts node_modules/.bin/semantic-release).
#   Optional (caller-provided):
#     CURRENT_BRANCH      bookmark/branch name to attach HEAD to when invoked
#                         from a jj-colocated detached-HEAD setup.
#
# This script does NOT require secret env vars (CLOUDFLARE_API_TOKEN,
# CLOUDFLARE_ACCOUNT_ID, GITHUB_TOKEN, SOPS_AGE_KEY). semantic-release is
# invoked in --dry-run with @semantic-release/github filtered out of the
# plugin list, so no secret env required for any caller (direnv dotenv,
# `sops exec-env` wrapper, GHA `env:` block, or M4 effect preamble
# reading HERCULES_CI_SECRETS_JSON).

set -euo pipefail

: "${DOCS_NODE_MODULES:?DOCS_NODE_MODULES not set; preview-version.nix must expose vanixiets-docs-deps via runtimeEnv}"

usage() {
  cat <<'EOF'
usage: preview-version [target-branch] [package-path]
       preview-version --help

Preview the semantic-release version that would be published after merging
the current branch into <target-branch>. Simulates the merge via
`git merge-tree --write-tree`, runs semantic-release in --dry-run / --no-ci
mode against a temporary worktree, and prints the next version (or a
no-bump / unsupported-branch notice).

Positional arguments:
  target-branch   Release branch to simulate merging into (default: main).
  package-path    Monorepo package directory relative to the repo root
                  (e.g., packages/docs). Defaults to the root package.

Flags:
  --help, -h      Print this usage and exit 0.

Environment:
  DOCS_NODE_MODULES   (required) Absolute path to the vanixiets-docs-deps
                      node_modules tree, provided by preview-version.nix.
                      Symlinked into the temporary worktree so
                      semantic-release and its plugins are resolvable.
  CURRENT_BRANCH      (optional) Bookmark/branch name to attach HEAD to when
                      invoked from a jj-colocated detached-HEAD setup. When
                      set while HEAD is detached, the script checks out the
                      branch for the run and restores detached state on exit.

Examples:
  nix run .#preview-version                         # root package on main
  nix run .#preview-version -- main packages/docs   # docs package on main
  nix run .#preview-version -- beta packages/docs   # docs package on beta
EOF
}

case "${1:-}" in
  -h | --help)
    usage
    exit 0
    ;;
esac

# Configuration
TARGET_BRANCH="${1:-main}"
PACKAGE_PATH="${2:-}"
REPO_ROOT=$(git rev-parse --show-toplevel)
WORKTREE_DIR=$(mktemp -d "${TMPDIR:-/tmp}/semantic-release-preview.XXXXXX")

# Save original target branch HEAD for restoration
ORIGINAL_TARGET_HEAD=""
ORIGINAL_REMOTE_HEAD=""

# Track which node_modules symlink(s) we created so cleanup can remove them.
WORKTREE_NODE_MODULES_LINK=""
LOCAL_NODE_MODULES_LINK=""

# Local bare clone used to redirect semantic-release verifyAuth's
# `git push --dry-run HEAD:<target-branch>` away from the GitHub remote
# (which can short-circuit semantic-release on branch-protection rejection
# or token-permission mismatch — see m5-01i mission notes).
# Populated AFTER `git update-ref` so the bare's refs/heads/<target-branch>
# captures TEMP_COMMIT, allowing the dry-run push to be a no-op fast-forward
# against a quiescent file:// remote with no auth and no protection.
PREVIEW_BARE_DIR=""
PREVIEW_BARE=""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Resolve CURRENT_BRANCH with jj-colocated detached-HEAD awareness.
#
# Precedence:
#   1. CURRENT_BRANCH env var override (jj callers export their bookmark name).
#      When set AND HEAD is detached, we temporarily attach to that branch and
#      capture the original commit sha so cleanup can restore detached state.
#   2. Otherwise, `git branch --show-current`.
#      When that returns empty (detached HEAD), we fail fast with instructions
#      rather than silently continuing with an empty branch name (which would
#      break `git merge-tree` and downstream ref operations).
ORIGINAL_HEAD_SHA=""
WE_ATTACHED_HEAD=0
if [ -n "${CURRENT_BRANCH:-}" ]; then
  # Env-var override path.
  DETECTED_BRANCH=$(git branch --show-current)
  if [ -z "$DETECTED_BRANCH" ]; then
    # HEAD is detached; attach to the provided branch so git operations that
    # rely on an attached HEAD work, and remember how to restore detached state.
    ORIGINAL_HEAD_SHA=$(git rev-parse --verify HEAD)
    echo -e "${BLUE}CURRENT_BRANCH=${CURRENT_BRANCH} override; attaching HEAD for duration of preview${NC}" >&2
    if ! git checkout --quiet "$CURRENT_BRANCH"; then
      echo -e "${RED}error: failed to checkout branch '${CURRENT_BRANCH}' (set via CURRENT_BRANCH env var)${NC}" >&2
      exit 1
    fi
    WE_ATTACHED_HEAD=1
  fi
  # If HEAD was already attached, we honor CURRENT_BRANCH as-is without
  # performing any checkout dance (per task spec).
else
  CURRENT_BRANCH=$(git branch --show-current)
  if [ -z "$CURRENT_BRANCH" ]; then
    echo -e "${RED}error: HEAD is detached and CURRENT_BRANCH env var is not set${NC}" >&2
    echo -e "${YELLOW}this is common in jj-colocated repositories where git HEAD is detached by default.${NC}" >&2
    echo -e "${YELLOW}to proceed, either:${NC}" >&2
    echo -e "${YELLOW}  - export CURRENT_BRANCH=<bookmark-name>  (recommended for jj callers)${NC}" >&2
    echo -e "${YELLOW}  - git checkout <bookmark-name>           (attach HEAD then re-run)${NC}" >&2
    exit 1
  fi
fi

# Cleanup function (invoked via `trap cleanup EXIT INT TERM` below)
# shellcheck disable=SC2329
cleanup() {
  local exit_code=$?

  # Remove any node_modules symlinks we created. Only unlink if still a symlink
  # (guards against manual replacement mid-run).
  if [ -n "$WORKTREE_NODE_MODULES_LINK" ] && [ -L "$WORKTREE_NODE_MODULES_LINK" ]; then
    rm -f "$WORKTREE_NODE_MODULES_LINK"
  fi
  if [ -n "$LOCAL_NODE_MODULES_LINK" ] && [ -L "$LOCAL_NODE_MODULES_LINK" ]; then
    rm -f "$LOCAL_NODE_MODULES_LINK"
  fi

  # Always restore target branch to original state if we modified it
  if [ -n "$ORIGINAL_TARGET_HEAD" ]; then
    echo -e "\n${BLUE}restoring ${TARGET_BRANCH} to original state...${NC}"
    git update-ref "refs/heads/$TARGET_BRANCH" "$ORIGINAL_TARGET_HEAD" 2>/dev/null || true
  fi

  # Always restore remote-tracking branch to original state if we modified it
  if [ -n "$ORIGINAL_REMOTE_HEAD" ]; then
    git update-ref "refs/remotes/origin/$TARGET_BRANCH" "$ORIGINAL_REMOTE_HEAD" 2>/dev/null || true
  fi

  # Clean up worktree
  if [ -d "$WORKTREE_DIR" ]; then
    echo -e "${BLUE}cleaning up worktree...${NC}"
    git worktree remove --force "$WORKTREE_DIR" 2>/dev/null || true
    # Prune any stale worktree references
    git worktree prune 2>/dev/null || true
  fi

  # Clean up local bare clone created for semantic-release verifyAuth
  # redirection (see m5-01i fix).
  if [ -n "$PREVIEW_BARE_DIR" ] && [ -d "$PREVIEW_BARE_DIR" ]; then
    rm -rf "$PREVIEW_BARE_DIR"
  fi

  # Restore detached HEAD if we attached it via the CURRENT_BRANCH override path.
  # Gated on WE_ATTACHED_HEAD so this is a no-op in the normal attached-HEAD flow.
  # Must cd to REPO_ROOT first because cleanup may be triggered while cwd is
  # inside the now-removed worktree, in which case git cannot locate the repo.
  if [ "${WE_ATTACHED_HEAD:-0}" -eq 1 ] && [ -n "$ORIGINAL_HEAD_SHA" ] && [ -n "$REPO_ROOT" ]; then
    echo -e "${BLUE}restoring detached HEAD at ${ORIGINAL_HEAD_SHA}...${NC}" >&2
    ( cd "$REPO_ROOT" && git checkout --quiet --detach "$ORIGINAL_HEAD_SHA" ) || true
  fi

  exit "$exit_code"
}

trap cleanup EXIT INT TERM

# link_docs_node_modules <target-dir>: symlink DOCS_NODE_MODULES into the given
# directory's node_modules slot, guarding against clobbering a real install.
# Echoes the resulting symlink path so callers can record it for cleanup.
link_docs_node_modules() {
  local target_dir="$1"
  local slot="$target_dir/node_modules"
  if [[ -e "$slot" && ! -L "$slot" ]]; then
    echo -e "${RED}error: ${slot} exists and is not a symlink; refusing to overwrite a local bun install${NC}" >&2
    exit 1
  fi
  ln -snf "$DOCS_NODE_MODULES" "$slot"
  echo "$slot"
}

# Validation
if [ "$CURRENT_BRANCH" == "$TARGET_BRANCH" ]; then
  echo -e "${YELLOW}already on target branch ${TARGET_BRANCH}${NC}"
  echo -e "${YELLOW}running test-release instead of preview${NC}\n"
  if [ -n "$PACKAGE_PATH" ]; then
    cd "$REPO_ROOT/$PACKAGE_PATH"
  else
    cd "$REPO_ROOT"
  fi
  LOCAL_NODE_MODULES_LINK=$(link_docs_node_modules "$PWD")
  exec node ./node_modules/.bin/semantic-release --dry-run --no-ci
fi

# Display what we're doing
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}semantic-release version preview${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo -e "current branch:  ${GREEN}${CURRENT_BRANCH}${NC}"
echo -e "target branch:   ${GREEN}${TARGET_BRANCH}${NC}"
if [ -n "$PACKAGE_PATH" ]; then
  echo -e "package:         ${GREEN}${PACKAGE_PATH}${NC}"
else
  echo -e "package:         ${GREEN}(root)${NC}"
fi
echo -e "${BLUE}───────────────────────────────────────────────────────────────${NC}\n"

# Verify target branch exists
if ! git show-ref --verify --quiet "refs/heads/$TARGET_BRANCH"; then
  echo -e "${RED}error: target branch '${TARGET_BRANCH}' does not exist${NC}" >&2
  exit 1
fi

# Save original target branch HEAD before any modifications
ORIGINAL_TARGET_HEAD=$(git rev-parse "$TARGET_BRANCH")

# Save original remote-tracking branch HEAD before any modifications
ORIGINAL_REMOTE_HEAD=$(git rev-parse "origin/$TARGET_BRANCH" 2>/dev/null || echo "")

# Create merge tree to test if merge is possible
echo -e "${BLUE}simulating merge of ${CURRENT_BRANCH} → ${TARGET_BRANCH}...${NC}"

# Perform merge-tree operation to test if merge is possible.
#
# The `if ! MERGE_OUTPUT=$(...)` form is deliberate: under `set -e`, a
# failing command substitution in a bare assignment (`VAR=$(cmd)`) does
# NOT cause the script to exit in every bash version/mode and does not
# propagate `$?` reliably when combined with `inherit_errexit` — the prior
# pattern of `VAR=$(cmd); RC=$?` was fragile. Guard the assignment with
# `if !` so merge-conflict detection is explicit and independent of
# errexit semantics.
if ! MERGE_OUTPUT=$(git merge-tree --write-tree "$TARGET_BRANCH" "$CURRENT_BRANCH" 2>&1); then
  echo -e "${RED}error: merge conflicts detected${NC}" >&2
  echo -e "${YELLOW}please resolve conflicts in your branch before previewing${NC}" >&2
  echo -e "\n${YELLOW}conflict details:${NC}" >&2
  echo "$MERGE_OUTPUT" >&2
  exit 1
fi

# Extract tree hash from merge-tree output (first line)
MERGE_TREE=$(echo "$MERGE_OUTPUT" | head -1)

if [ -z "$MERGE_TREE" ]; then
  echo -e "${RED}error: failed to create merge tree${NC}" >&2
  exit 1
fi

# Create temporary merge commit
echo -e "${BLUE}creating temporary merge commit...${NC}"
TEMP_COMMIT=$(git commit-tree -p "$TARGET_BRANCH" -p "$CURRENT_BRANCH" \
  -m "Temporary merge for semantic-release preview" "$MERGE_TREE")

if [ -z "$TEMP_COMMIT" ]; then
  echo -e "${RED}error: failed to create temporary merge commit${NC}" >&2
  exit 1
fi

# Temporarily update target branch to point to merge commit
# This allows semantic-release to analyze the correct commit history
# The cleanup function will ALWAYS restore the original branch HEAD
echo -e "${BLUE}temporarily updating ${TARGET_BRANCH} ref for analysis...${NC}"
git update-ref "refs/heads/$TARGET_BRANCH" "$TEMP_COMMIT"

# Also update remote-tracking branch to match (so semantic-release sees them as synchronized)
git update-ref "refs/remotes/origin/$TARGET_BRANCH" "$TEMP_COMMIT"

# Capture the post-update-ref state into a local bare clone so semantic-release's
# `verifyAuth` can run `git push --dry-run HEAD:<target-branch>` against a
# quiescent file:// remote instead of the GitHub origin (m5-01i fix).
#
# The bare must be cloned from $REPO_ROOT (cwd's local refs at clone time
# include the just-updated refs/heads/<target-branch> = TEMP_COMMIT). Cloning
# from $REPO_ROOT — not WORKTREE_DIR which has not been created yet — is what
# makes verifyAuth's push a trivial no-op fast-forward.
#
# Without this redirect, semantic-release v25.0.3's `lib/git.js:205-211`
# performs a real network round-trip to GitHub, which short-circuits the run
# whenever branch protection or token-permission mismatches reject the
# dry-run push (then `lib/git.js:282-290` strict-=== compare against
# TEMP_COMMIT can never succeed and `index.js:84-100` bails with "behind
# the remote one"), preventing analyzeCommits from ever firing.
echo -e "${BLUE}creating local bare clone for semantic-release repository-url override...${NC}"
PREVIEW_BARE_DIR=$(mktemp -d "${TMPDIR:-/tmp}/preview-bare.XXXXXX")
PREVIEW_BARE="$PREVIEW_BARE_DIR/preview.git"
git clone --quiet --bare "$REPO_ROOT" "$PREVIEW_BARE"

# Create worktree at target branch (now pointing to merge commit)
echo -e "${BLUE}creating temporary worktree at ${TARGET_BRANCH}...${NC}"
git worktree add --quiet "$WORKTREE_DIR" "$TARGET_BRANCH"

# Navigate to worktree
cd "$WORKTREE_DIR"

# Link the hermetic vanixiets-docs-deps tree into the worktree's package dir.
# (bun install is no longer required here.)
if [ -n "$PACKAGE_PATH" ]; then
  if [ ! -d "$PACKAGE_PATH" ]; then
    echo -e "${RED}error: package path '${PACKAGE_PATH}' does not exist${NC}" >&2
    exit 1
  fi
  WORKTREE_NODE_MODULES_LINK=$(link_docs_node_modules "$WORKTREE_DIR/$PACKAGE_PATH")
  cd "$PACKAGE_PATH"
else
  WORKTREE_NODE_MODULES_LINK=$(link_docs_node_modules "$WORKTREE_DIR")
fi

# Run semantic-release in dry-run mode
echo -e "\n${BLUE}running semantic-release analysis...${NC}\n"

# Capture output and parse version
# Exclude @semantic-release/github to avoid GitHub token requirement for preview
# This is safe because dry-run skips publish/success/fail steps anyway
PLUGINS="@semantic-release/commit-analyzer,@semantic-release/release-notes-generator"

# Forensic banner (m5-01i): confirms the verifyAuth-redirect bare clone is
# engaged in production logs. Stable banner namespace; kept structurally
# similar to RELEASE-CLONE-PR-HEAD / RELEASE-CLONE-PR-DISPATCH.
echo "RELEASE-PREVIEW-BARE: $PREVIEW_BARE"

OUTPUT=$(GITHUB_REF="refs/heads/$TARGET_BRANCH" node ./node_modules/.bin/semantic-release --dry-run --no-ci --repository-url "file://$PREVIEW_BARE" --branches "$TARGET_BRANCH" --plugins "$PLUGINS" 2>&1 || true)

# Display semantic-release summary (filter out verbose plugin repetition)
echo "$OUTPUT" | grep -v "^$" | grep -vE "(No more plugins|does not provide step)" | \
  grep -E "(semantic-release|Running|analyzing|Found.*commits|release version|Release note|Features|Bug Fixes|Breaking Changes|Published|\*\s)" || true

echo -e "\n${BLUE}═══════════════════════════════════════════════════════════════${NC}"

# Extract and display the next version
if echo "$OUTPUT" | grep -q "There are no relevant changes"; then
  echo -e "${YELLOW}no version bump required${NC}"
  echo -e "no semantic commits found since last release"
elif echo "$OUTPUT" | grep -q "is not configured to publish from"; then
  echo -e "${YELLOW}cannot determine version${NC}"
  echo -e "branch ${TARGET_BRANCH} is not in release configuration"
elif VERSION=$(echo "$OUTPUT" | grep -oP 'next release version is \K[0-9]+\.[0-9]+\.[0-9]+(-[a-z]+\.[0-9]+)?' | head -1); then
  echo -e "${GREEN}next version: ${VERSION}${NC}"

  # Extract release type if available
  if TYPE=$(echo "$OUTPUT" | grep -oP 'Release type: \K[a-z]+' | head -1); then
    echo -e "release type: ${TYPE}"
  fi
else
  echo -e "${YELLOW}could not parse version from output${NC}"
  echo -e "check the semantic-release output above for details"
fi

echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}\n"

# Preview completed successfully - exit 0 regardless of whether a version bump is pending.
# "No version bump required" is a valid outcome, not an error.
exit 0
