#!/usr/bin/env bash
# Create a private GitHub fork of current repository
set -euo pipefail

case "${1:-}" in
  -h|--help)
    cat <<'HELP'
Create a private fork of current repository

Usage: gfork

Creates a private GitHub repository as a fork:
  1. Renames 'origin' remote to 'upstream'
  2. Creates new private repo on your GitHub account
  3. Sets the new repo as 'origin'
  4. Pushes current branch to new origin

Requirements:
  - Must be run inside a git repository
  - GitHub CLI (gh) must be authenticated

Interactive:
  - Prompts for confirmation or new repo name
HELP
    exit 0
    ;;
esac

if ! command -v gh &> /dev/null; then
  echo "Error: GitHub CLI (gh) is not installed" >&2
  exit 1
fi

if ! git rev-parse --is-inside-work-tree &> /dev/null; then
  echo "Error: Not inside a git repository" >&2
  exit 1
fi

echo "Current remotes:"
git remote -v

echo
echo "Renaming origin to upstream..."
git remote rename origin upstream 2>/dev/null || echo "Note: No 'origin' remote to rename"

repo_name=$(basename "$(git rev-parse --show-toplevel)")
gh_username=$(gh api user --jq .login 2>/dev/null)

if [ -z "$gh_username" ]; then
  echo "Error: Could not get GitHub username. Please run 'gh auth login'" >&2
  exit 1
fi

echo "Creating repo: $gh_username/$repo_name"
printf "Press enter to continue or type new name: "
read -r new_name

final_name="${new_name:-$repo_name}"
echo "Creating private repository: $gh_username/$final_name"

if gh repo create "$gh_username/$final_name" --private --push -r origin -s .; then
  echo "Successfully created and pushed to private repository: $gh_username/$final_name"
  echo "Updated remotes:"
  git remote -v
else
  echo "Error: Failed to create repository" >&2
  exit 1
fi
