#!/usr/bin/env bash
# Approve all open PRs with optional exclusions
set -euo pipefail

show_help() {
  cat <<'HELP'
Approve all open pull requests with optional exclusions

Usage: gh-approve-open-prs [OPTIONS] [EXCLUDE...]

Approves all open PRs in the current repository, optionally excluding
specific PR numbers.

Arguments:
  EXCLUDE...    PR numbers to exclude from approval (optional)

Options:
  -n, --dry-run    Show what would be approved without approving
  -h, --help       Show this help message

Examples:
  gh-approve-open-prs                    # Approve all open PRs
  gh-approve-open-prs 158 191            # Approve all except #158 and #191
  gh-approve-open-prs -n                 # Dry run: list PRs that would be approved
  gh-approve-open-prs -n 158             # Dry run excluding #158

Requirements:
  - GitHub CLI (gh) must be authenticated
  - Must be run inside a git repository with a GitHub remote
HELP
}

dry_run=false
exclude_prs=()

# Parse arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)
      show_help
      exit 0
      ;;
    -n|--dry-run)
      dry_run=true
      shift
      ;;
    -*)
      echo "Error: Unknown option: $1" >&2
      echo "Try 'gh-approve-open-prs --help' for more information." >&2
      exit 1
      ;;
    *)
      if ! [[ "$1" =~ ^[0-9]+$ ]]; then
        echo "Error: PR number must be a positive integer: $1" >&2
        exit 1
      fi
      exclude_prs+=("$1")
      shift
      ;;
  esac
done

# Get all open PR numbers
all_prs=$(gh pr list --state open --json number --jq '.[].number' 2>/dev/null)

if [[ -z "$all_prs" ]]; then
  echo "No open PRs found."
  exit 0
fi

# Filter out excluded PRs
prs_to_approve=()
while IFS= read -r pr; do
  skip=false
  for excl in "${exclude_prs[@]}"; do
    if [[ "$pr" == "$excl" ]]; then
      skip=true
      break
    fi
  done
  if ! $skip; then
    prs_to_approve+=("$pr")
  fi
done <<< "$all_prs"

if [[ ${#prs_to_approve[@]} -eq 0 ]]; then
  echo "No PRs to approve after exclusions."
  exit 0
fi

# Show what will be approved
echo "PRs to approve: ${prs_to_approve[*]}"
if [[ ${#exclude_prs[@]} -gt 0 ]]; then
  echo "Excluded PRs: ${exclude_prs[*]}"
fi
echo

if $dry_run; then
  echo "[Dry run] Would approve ${#prs_to_approve[@]} PR(s):"
  for pr in "${prs_to_approve[@]}"; do
    title=$(gh pr view "$pr" --json title --jq '.title' 2>/dev/null)
    echo "  #$pr - $title"
  done
  exit 0
fi

# Approve PRs
approved=0
failed=0
for pr in "${prs_to_approve[@]}"; do
  echo "Approving PR #$pr..."
  if gh pr review "$pr" --approve; then
    ((++approved))
  else
    echo "Warning: Failed to approve PR #$pr" >&2
    ((++failed))
  fi
done

echo
echo "Approved: $approved, Failed: $failed"
