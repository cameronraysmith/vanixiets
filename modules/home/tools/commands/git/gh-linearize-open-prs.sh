#!/usr/bin/env bash
# Linearize commits from open PR branches onto a new jj bookmark.
# Fetches each open PR's head branch as a remote-tracking bookmark, then
# rebases the unique commits of each branch onto a growing chain tip.
set -euo pipefail

show_help() {
  cat <<'HELP'
Linearize commits from open PR branches onto a new jj bookmark

Usage: gh-linearize-open-prs [OPTIONS]

Fetches every open PR's head branch into the local jj repo as a remote-
tracking bookmark, then sequentially rebases each branch's branch-unique
commits onto a growing chain tip. The TARGET bookmark advances to the
chain tip after each successful rebase.

Options:
  -b, --base BASE          Base ref to start the chain (default: main)
  -t, --target TARGET      Target bookmark name (default: linearized-prs)
  -f, --filter JQ          Optional jq filter applied to gh pr list output
                           (e.g. '.[] | select(.headRefName | startswith("update-"))')
  -h, --help               Show this help message

Behavior:
  - Pauses on rebase conflict; resolve manually with `jj resolve`, then re-run.
  - Existing TARGET bookmark is rejected unless --reset is passed.
  - Remote bookmarks (origin/...) are immutable in jj, so PR branches are
    never modified — only local copies are rewritten during rebase.

Examples:
  gh-linearize-open-prs
  gh-linearize-open-prs --base main --target preview-merged
  gh-linearize-open-prs --filter '.[] | select(.headRefName | startswith("update-"))'
HELP
}

base="main"
target="linearized-prs"
filter='.[]'
reset=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help) show_help; exit 0 ;;
    -b|--base) base="$2"; shift 2 ;;
    -t|--target) target="$2"; shift 2 ;;
    -f|--filter) filter="$2"; shift 2 ;;
    --reset) reset=true; shift ;;
    -*)
      echo "Error: Unknown option: $1" >&2
      echo "Try 'gh-linearize-open-prs --help' for more information." >&2
      exit 1
      ;;
    *)
      echo "Error: Unexpected argument: $1" >&2
      exit 1
      ;;
  esac
done

# Collect open PR head branches via the chosen filter
mapfile -t branches < <(
  gh pr list --state open --limit 200 --json number,headRefName \
    | jq -r "${filter} | .headRefName"
)

if [[ ${#branches[@]} -eq 0 ]]; then
  echo "No open PRs match the filter; nothing to linearize."
  exit 0
fi

echo "Linearizing ${#branches[@]} PR branches onto ${target} starting from ${base}..."

# Refuse to overwrite an existing bookmark unless --reset
if jj bookmark list --quiet "${target}" 2>/dev/null | grep -q "${target}"; then
  if ! $reset; then
    echo "Error: bookmark ${target} already exists; pass --reset to overwrite." >&2
    exit 1
  fi
  jj bookmark delete "${target}"
fi

# Fetch each PR head branch as a remote-tracking bookmark.
# Pass branches comma-separated to a single fetch call.
jj git fetch --branch "$(IFS=,; printf '%s' "${branches[*]}")"

# Anchor: empty change on the base, with target bookmark on it
jj new "${base}"
jj bookmark create "${target}" -r @

for branch in "${branches[@]}"; do
  echo "  Rebasing ${branch}@origin onto chain tip..."
  if ! jj rebase -b "${branch}@origin" -d "${target}" --skip-emptied; then
    echo "Conflict during rebase of ${branch}." >&2
    echo "Resolve with: jj resolve" >&2
    echo "Then re-run: gh-linearize-open-prs ..." >&2
    exit 1
  fi
  jj bookmark move "${target}" --to "heads(${base}..mutable())"
done

echo "Done. Bookmark ${target} points to the linearized chain tip."
