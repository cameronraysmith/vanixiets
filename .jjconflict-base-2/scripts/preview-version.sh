#!/usr/bin/env bash
# preview-version.sh - Preview semantic-release version after merging to target branch
#
# Usage:
#   ./scripts/preview-version.sh [target-branch] [package-path]
#
# Examples:
#   ./scripts/preview-version.sh                    # Preview root version on main
#   ./scripts/preview-version.sh main packages/docs # Preview docs package version on main
#   ./scripts/preview-version.sh beta packages/docs # Preview docs version on beta
#
# This script simulates merging the current branch into the target branch and
# runs semantic-release in dry-run mode to preview what version would be released.

set -euo pipefail

# Configuration
TARGET_BRANCH="${1:-main}"
PACKAGE_PATH="${2:-}"
CURRENT_BRANCH=$(git branch --show-current)
REPO_ROOT=$(git rev-parse --show-toplevel)
WORKTREE_DIR=$(mktemp -d "${TMPDIR:-/tmp}/semantic-release-preview.XXXXXX")

# Save original target branch HEAD for restoration
ORIGINAL_TARGET_HEAD=""
ORIGINAL_REMOTE_HEAD=""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Cleanup function
cleanup() {
  local exit_code=$?

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

  exit $exit_code
}

trap cleanup EXIT INT TERM

# Validation
if [ "$CURRENT_BRANCH" == "$TARGET_BRANCH" ]; then
  echo -e "${YELLOW}already on target branch ${TARGET_BRANCH}${NC}"
  echo -e "${YELLOW}running test-release instead of preview${NC}\n"
  if [ -n "$PACKAGE_PATH" ]; then
    cd "$REPO_ROOT/$PACKAGE_PATH"
  fi
  exec nix develop -c bun run test-release
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

# Perform merge-tree operation to test if merge is possible
MERGE_OUTPUT=$(git merge-tree --write-tree "$TARGET_BRANCH" "$CURRENT_BRANCH" 2>&1)
MERGE_EXIT=$?

if [ $MERGE_EXIT -ne 0 ]; then
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

# Create worktree at target branch (now pointing to merge commit)
echo -e "${BLUE}creating temporary worktree at ${TARGET_BRANCH}...${NC}"
git worktree add --quiet "$WORKTREE_DIR" "$TARGET_BRANCH"

# Navigate to worktree
cd "$WORKTREE_DIR"

# Install dependencies in worktree (bun uses global cache, so this is fast)
echo -e "${BLUE}installing dependencies in worktree...${NC}"
nix develop -c bun install --silent

# Navigate to package if specified
if [ -n "$PACKAGE_PATH" ]; then
  if [ ! -d "$PACKAGE_PATH" ]; then
    echo -e "${RED}error: package path '${PACKAGE_PATH}' does not exist${NC}" >&2
    exit 1
  fi
  cd "$PACKAGE_PATH"
fi

# Run semantic-release in dry-run mode
echo -e "\n${BLUE}running semantic-release analysis...${NC}\n"

# Capture output and parse version
# Exclude @semantic-release/github to avoid GitHub token requirement for preview
# This is safe because dry-run skips publish/success/fail steps anyway
PLUGINS="@semantic-release/commit-analyzer,@semantic-release/release-notes-generator"

if [ -n "$PACKAGE_PATH" ]; then
  # For monorepo packages, check if package.json has specific plugins configured
  OUTPUT=$(GITHUB_REF="refs/heads/$TARGET_BRANCH" nix develop -c bun run semantic-release --dry-run --no-ci --branches "$TARGET_BRANCH" --plugins "$PLUGINS" 2>&1 || true)
else
  # For root package
  OUTPUT=$(GITHUB_REF="refs/heads/$TARGET_BRANCH" nix develop -c bun run semantic-release --dry-run --no-ci --branches "$TARGET_BRANCH" --plugins "$PLUGINS" 2>&1 || true)
fi

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
