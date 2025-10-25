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

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Cleanup function
cleanup() {
  local exit_code=$?
  if [ -d "$WORKTREE_DIR" ]; then
    echo -e "\n${BLUE}cleaning up worktree...${NC}"
    git worktree remove --force "$WORKTREE_DIR" 2>/dev/null || true
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
  exec bun run test-release
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

# Create worktree at target branch
echo -e "${BLUE}creating temporary worktree at ${TARGET_BRANCH}...${NC}"
git worktree add --quiet "$WORKTREE_DIR" "$TARGET_BRANCH"

# Navigate to worktree
cd "$WORKTREE_DIR"

# Merge current branch (test merge, will be discarded)
echo -e "${BLUE}simulating merge of ${CURRENT_BRANCH} → ${TARGET_BRANCH}...${NC}"
if ! git merge --no-edit "$CURRENT_BRANCH" &>/dev/null; then
  echo -e "${RED}error: merge conflicts detected${NC}" >&2
  echo -e "${YELLOW}please resolve conflicts in your branch before previewing${NC}" >&2
  exit 1
fi

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
# Ensure we have path to original repo's node_modules
export PATH="$REPO_ROOT/node_modules/.bin:$PATH"

# Run semantic-release via bun with explicit reference to repo node_modules
if [ -n "$PACKAGE_PATH" ]; then
  # For package, use bun x from within the worktree package directory
  OUTPUT=$(NODE_PATH="$REPO_ROOT/node_modules" bun x --bun semantic-release --dry-run --no-ci --branches "$TARGET_BRANCH" 2>&1 || true)
else
  # For root package
  OUTPUT=$(cd "$WORKTREE_DIR" && NODE_PATH="$REPO_ROOT/node_modules" bun x --bun semantic-release --dry-run --no-ci --branches "$TARGET_BRANCH" 2>&1 || true)
fi

# Display relevant output
echo "$OUTPUT" | grep -v "^$" | grep -E "(semantic-release|Published|next release|Release note|version)" || true

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
