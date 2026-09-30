#!/usr/bin/env bash
# shellcheck shell=bash
# release-packages.sh - semantic-release for every monorepo package at a main rev,
# or, in plan mode, the forecast of what merging a pull request would release.
#
# Runs in the nixbot effect sandbox, which binds no working tree, so the
# program clones the repository itself and releases from that clone.
#
# Merge-queue batches land by fast-forwarding main, possibly several in quick
# succession, so main may have moved past --rev by the time this runs. A rev
# that is an ancestor of origin/main skips with exit 0 and leaves the release
# to the run for the newer rev, which sees the same commits; a rev outside
# main's history is refused.
#
# The GITHUB_TOKEN (the effects PAT, Read+Write) is the release authority.
# semantic-release's get-git-auth-url.js reads GIT_CREDENTIALS as
# user:password. The username must not be `x-access-token`: GitHub reserves it
# for App installation tokens (ghs_*) and routes fine-grained PATs into the
# wrong validator, failing git push with "Invalid username or token" while API
# calls succeed. `oauth2` is the conventional username for PATs over HTTPS.
#
# Git identity and CI=true go through the environment: env-ci aborts outside
# a recognised CI without CI=true, and the sandbox cannot write .git/config.
#
# RELEASE_PACKAGES_LIST, RELEASE_PACKAGES_RELEASE, RELEASE_PACKAGES_CHECK_RUN
# and RELEASE_PACKAGES_PULL_REQUEST are the list-packages-json, release,
# github-check-run and github-pull-request programs, injected by
# release-packages.nix runtimeEnv.
#
# Plan mode runs on a pull request with nixbot's read-only forge installation
# token and never the release PAT. It analyses the pull request's commits on a
# simulated merge commit while every file, and with it the semantic-release
# config and plugins (resolved from the working tree), comes from main: HEAD is
# the merge, the index and worktree are main's tree. semantic-release runs with
# --dry-run against a throwaway bare copy of main that git's url.insteadOf
# substitutes for the GitHub URL, and every other https remote is rewritten to
# a path that does not exist, so no git operation reaches the network.
#
# nixbot delivers pull_request effects in no guaranteed order, after a merge
# as readily as before it, and the event is a delivery-time snapshot. Plan
# mode therefore asks GitHub whether the pull request is still open at the
# event's head and, if not, completes the check run neutral without cloning.

set -euo pipefail

usage() {
  cat <<'EOF'
usage: release-packages --rev <40-hex>
       release-packages plan
       release-packages --help

Clone the repository at <rev> as branch main and run the release app for
every package list-packages-json reports. Skips (exit 0) when <rev> is an
ancestor of origin/main; fails when <rev> is not in main's history.

plan forecasts, for the nixbot pull_request event, the release each package
would get if the pull request merged, and reports it as the release-plan
check run on the pull request head. When the pull request is no longer open
at the event's head, plan skips (exit 0) and completes the check run neutral.

Environment:
  GITHUB_TOKEN               --rev: required; release authority for tags and
                             releases. plan: never read.
  GITHUB_FORGE_TOKEN         plan: required; nixbot's installation token.
  NIXBOT_EVENT_KIND, NIXBOT_EVENT_JSON, NIXBOT_PR_NUMBER, NIXBOT_PR_HEAD
                             plan: the pull_request event from nixbot.
  GITHUB_API_URL             plan: API base, default https://api.github.com
  RELEASE_PACKAGES_REPO_URL  clone URL, default
                             https://github.com/cameronraysmith/vanixiets.git
EOF
}

readonly plan_repo=cameronraysmith/vanixiets
readonly plan_repo_url=https://github.com/cameronraysmith/vanixiets

check_run_id=""
plan_tmp=""
plan_summary=""
plan_skipped=""
plan_failure=""

# Completes the check run from the exit status; reporting never changes it.
plan_exit() {
  local rc=$? conclusion=failure title="Release plan failed" summary="$plan_failure"
  trap - EXIT
  if [ -n "$check_run_id" ]; then
    if [ "$rc" -eq 0 ] && [ -n "$plan_skipped" ]; then
      conclusion=neutral title="Release plan skipped" summary="$plan_summary"
    elif [ "$rc" -eq 0 ]; then
      conclusion=success title="Release plan" summary="$plan_summary"
    elif [ -z "$summary" ]; then
      summary="release-packages plan exited with status $rc."
    fi
    "$RELEASE_PACKAGES_CHECK_RUN" complete --repo "$plan_repo" --id "$check_run_id" \
      --conclusion "$conclusion" --title "$title" --summary "$summary" ||
      echo "warning: could not complete check run $check_run_id" >&2
  fi
  [ -z "$plan_tmp" ] || rm -rf "$plan_tmp"
  exit "$rc"
}

plan_fail() {
  plan_failure="$1"
  echo "error: $1" >&2
  exit 1
}

# bump <last|none> <next>: the semver component that changed.
plan_bump() {
  local last=$1 next=$2 semver='^([0-9]+)\.([0-9]+)\.([0-9]+)(-.+)?$'
  local lmaj lmin
  [[ "$next" =~ $semver ]] || return 1
  [ "$last" != none ] || { echo initial; return 0; }
  [ -z "${BASH_REMATCH[4]}" ] || { echo prerelease; return 0; }
  local nmaj=${BASH_REMATCH[1]} nmin=${BASH_REMATCH[2]}
  [[ "$last" =~ $semver ]] || return 1
  lmaj=${BASH_REMATCH[1]} lmin=${BASH_REMATCH[2]}
  if [ "$nmaj" != "$lmaj" ]; then
    echo major
  elif [ "$nmin" != "$lmin" ]; then
    echo minor
  else
    echo patch
  fi
}

plan() {
  [ $# -eq 0 ] || { echo "error: plan takes no arguments" >&2; exit 1; }
  # The release PAT must not reach anything plan mode runs.
  unset GITHUB_TOKEN GH_TOKEN GIT_CREDENTIALS

  if [ "${NIXBOT_EVENT_KIND:-}" != pull_request ]; then
    echo "error: plan expects a pull_request event, got '${NIXBOT_EVENT_KIND:-}'" >&2
    exit 1
  fi
  if [ -z "${GITHUB_FORGE_TOKEN:-}" ]; then
    echo "error: GITHUB_FORGE_TOKEN is required" >&2
    exit 1
  fi
  if [ -z "${NIXBOT_EVENT_JSON:-}" ] || [ ! -r "$NIXBOT_EVENT_JSON" ]; then
    echo "error: NIXBOT_EVENT_JSON is not a readable file: '${NIXBOT_EVENT_JSON:-}'" >&2
    exit 1
  fi
  local pr head
  pr="$(jq -r '.pullRequest.number // "" | tostring' "$NIXBOT_EVENT_JSON")"
  head="$(jq -r '.pullRequest.headRev // "" | tostring' "$NIXBOT_EVENT_JSON")"
  if ! [[ "$pr" =~ ^[0-9]+$ && "$head" =~ ^[0-9a-f]{40}$ ]]; then
    echo "error: malformed pull_request event (number '$pr', headRev '$head')" >&2
    exit 1
  fi
  if [ "${NIXBOT_PR_NUMBER:-}" != "$pr" ] || [ "${NIXBOT_PR_HEAD:-}" != "$head" ]; then
    echo "error: NIXBOT_PR_NUMBER/NIXBOT_PR_HEAD (${NIXBOT_PR_NUMBER:-}/${NIXBOT_PR_HEAD:-}) disagree with the event (#$pr at $head)" >&2
    exit 1
  fi

  plan_tmp="$(mktemp -d -t release-plan.XXXXXX)"
  trap plan_exit EXIT
  check_run_id="$("$RELEASE_PACKAGES_CHECK_RUN" create --repo "$plan_repo" --name release-plan --head-sha "$head")"

  local pr_state
  pr_state="$("$RELEASE_PACKAGES_PULL_REQUEST" state --repo "$plan_repo" --number "$pr" --head-sha "$head")" ||
    plan_fail "cannot read the state of pull request #$pr"
  if [ "$pr_state" != current ]; then
    plan_skipped=1
    plan_summary="pull request #$pr is $pr_state; no forecast"
    echo "RELEASE-PLAN: skipped ($pr_state)"
    return 0
  fi

  export GIT_AUTHOR_NAME=semantic-release
  export GIT_AUTHOR_EMAIL=semantic-release@vanixiets.local
  export GIT_COMMITTER_NAME=semantic-release
  export GIT_COMMITTER_EMAIL=semantic-release@vanixiets.local

  local clone_url="${RELEASE_PACKAGES_REPO_URL:-${plan_repo_url}.git}"
  local clone_dir="$plan_tmp/clone" bare="$plan_tmp/origin.git"
  echo "RELEASE-PLAN-CLONE-START: $clone_url #$pr $head"
  git clone --quiet "$clone_url" "$clone_dir" || plan_fail "cannot clone $clone_url"
  git -C "$clone_dir" fetch --quiet --tags origin \
    '+refs/heads/main:refs/remotes/origin/main' "+refs/pull/$pr/head:refs/remotes/origin/pull/$pr" ||
    plan_fail "cannot fetch main and refs/pull/$pr/head from $clone_url"
  local fetched
  fetched="$(git -C "$clone_dir" rev-parse "refs/remotes/origin/pull/$pr^{commit}")"
  [ "$fetched" = "$head" ] ||
    plan_fail "refs/pull/$pr/head is $fetched, not the event's head $head"

  local merge_out merge_rc=0 tree merge_rev main_rev
  main_rev="$(git -C "$clone_dir" rev-parse origin/main)"
  merge_out="$(git -C "$clone_dir" merge-tree --write-tree origin/main "$head")" || merge_rc=$?
  case "$merge_rc" in
    0) tree="$merge_out" ;;
    1) plan_fail "pull request #$pr conflicts with main at $main_rev; no release plan until it merges cleanly." ;;
    *) plan_fail "git merge-tree of pull request #$pr and main failed (exit $merge_rc)" ;;
  esac
  merge_rev="$(git -C "$clone_dir" commit-tree "$tree" -p origin/main -p "$head" \
    -m "Simulated merge of pull request #$pr into main for the release plan")"

  git init --quiet --bare --initial-branch=main "$bare"
  git -C "$clone_dir" push --quiet "$bare" 'refs/remotes/origin/main:refs/heads/main' 'refs/tags/*:refs/tags/*'

  export HOME="$plan_tmp/home"
  mkdir "$HOME"
  export GIT_CONFIG_GLOBAL="$HOME/.gitconfig"
  export GIT_CONFIG_NOSYSTEM=1
  git config --global url."file://$bare".insteadOf "$plan_repo_url"
  git config --global --add url."file://$bare".insteadOf "$plan_repo_url.git"
  git config --global url."file://$plan_tmp/no-network/".insteadOf https://
  git config --global --add url."file://$plan_tmp/no-network/".insteadOf http://
  git -C "$clone_dir" remote set-url origin "$plan_repo_url.git"

  git -C "$clone_dir" checkout --quiet -B main "$merge_rev"
  git -C "$clone_dir" read-tree --reset -u origin/main
  if ! {
    [ "$(git -C "$clone_dir" rev-parse HEAD)" = "$merge_rev" ] &&
      git -C "$clone_dir" diff --quiet origin/main -- &&
      git -C "$clone_dir" diff --cached --quiet origin/main -- &&
      [ -z "$(git -C "$clone_dir" ls-files --others)" ]
  }; then
    plan_fail "the working tree is not main's tree at $main_rev after read-tree; refusing to run the pull request's files"
  fi

  echo "RELEASE-PACKAGES-ACTION: plan (#$pr at $head onto main at $main_rev)"

  export CI=true
  export GIT_BRANCH=main
  export RELEASE_REPO_ROOT="$clone_dir"
  cd "$clone_dir"
  local packages_json
  packages_json="$("$RELEASE_PACKAGES_LIST")" || plan_fail "list-packages-json failed on main's tree"
  echo "packages discovered: $packages_json"

  local rows="" failures="" name path log rc clean last next bump tail
  local idx=0
  while IFS=$'\t' read -r name path; do
    [ -n "$path" ] || continue
    idx=$((idx + 1))
    log="$plan_tmp/release-$idx.log"
    echo "RELEASE-PACKAGE-ITERATION: $path"
    rc=0
    GITHUB_TOKEN="$GITHUB_FORGE_TOKEN" "$RELEASE_PACKAGES_RELEASE" "$path" -- --dry-run --no-ci </dev/null 2>&1 |
      tee "$log" || rc=$?
    clean="$(sed 's/\x1b\[[0-9;]*m//g' "$log")"
    tail="$(printf '%s\n' "$clean" | tail -n 40)"
    tail="${tail//"$GITHUB_FORGE_TOKEN"/[secure]}"
    if [ "$rc" -ne 0 ]; then
      echo "RELEASE-PACKAGE-FAILURE: $path (exit $rc)"
      failures+=$'\n'"### \`$name\` (\`$path\`): semantic-release exited $rc"$'\n\n```\n'"$tail"$'\n```\n'
      continue
    fi

    last="$(printf '%s\n' "$clean" | sed -nE 's/.*Found git tag .* associated with version ([^ ]+) on branch .*/\1/p')"
    if [ -z "$last" ] && printf '%s\n' "$clean" | grep -qF 'No git tag version found on branch'; then
      last=none
    fi
    next="$(printf '%s\n' "$clean" | sed -nE 's/.*[Tt]he next release version is ([^ ]+).*/\1/p')"
    if [ -z "$next" ] && printf '%s\n' "$clean" | grep -qF 'no new version is released'; then
      next="no release"
      bump=none
    elif [ -n "$next" ]; then
      bump="$(plan_bump "$last" "$next")" || bump=""
    fi
    if [ -z "$last" ] || [ -z "$next" ] || [ -z "$bump" ] || [[ "$last" == *$'\n'* || "$next" == *$'\n'* ]]; then
      echo "RELEASE-PACKAGE-FAILURE: $path (unparseable semantic-release output)"
      failures+=$'\n'"### \`$name\` (\`$path\`): no last release or next version in the semantic-release output"$'\n\n```\n'"$tail"$'\n```\n'
      continue
    fi

    echo "RELEASE-PLAN: $name $last -> $next"
    rows+="| $name | $last | $next | $bump |"$'\n'
  done < <(printf '%s\n' "$packages_json" | jq -r '.[] | [.name, .path] | @tsv')

  if [ -n "$failures" ]; then
    plan_fail "The release plan for pull request #$pr failed."$'\n'"$failures"
  fi
  plan_summary="Releases if pull request #$pr (\`${head:0:12}\`) merges into main at \`${main_rev:0:12}\`, per semantic-release \`--dry-run\` with main's configuration."$'\n\n'"| package | last | next | bump |"$'\n'"| --- | --- | --- | --- |"$'\n'"$rows"
}

if [ "${1:-}" = plan ]; then
  shift
  plan "$@"
  exit 0
fi

rev=""
while [ $# -gt 0 ]; do
  case "$1" in
    --rev)
      [ $# -ge 2 ] || { echo "error: --rev requires a value" >&2; exit 1; }
      rev="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "error: unexpected argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

if [[ ! "$rev" =~ ^[0-9a-f]{40}$ ]]; then
  echo "error: --rev must be a 40-character lowercase hex commit, got '${rev}'" >&2
  exit 1
fi

if [ -z "${GITHUB_TOKEN:-}" ]; then
  echo "error: GITHUB_TOKEN is required" >&2
  exit 1
fi

branch=main
clone_url="${RELEASE_PACKAGES_REPO_URL:-https://github.com/cameronraysmith/vanixiets.git}"
clone_dir="$(mktemp -d -t release-packages-clone.XXXXXX)"
trap 'rm -rf "$clone_dir"' EXIT

echo "RELEASE-CLONE-START: $clone_url $rev"
git clone --quiet "$clone_url" "$clone_dir"
git -C "$clone_dir" fetch --quiet --tags origin
git -C "$clone_dir" checkout --quiet -B "$branch" "$rev"

git -C "$clone_dir" fetch --quiet origin "$branch"
head_rev="$(git -C "$clone_dir" rev-parse HEAD)"
remote_rev="$(git -C "$clone_dir" rev-parse "origin/$branch")"
if [ "$head_rev" != "$remote_rev" ]; then
  if git -C "$clone_dir" merge-base --is-ancestor "$head_rev" "$remote_rev"; then
    echo "RELEASE-PACKAGES-ACTION: superseded (main moved to $remote_rev)"
    exit 0
  fi
  echo "error: $head_rev is not on origin/$branch ($remote_rev); refusing to release a rev outside main's history" >&2
  exit 1
fi

echo "RELEASE-PACKAGES-ACTION: release"

export GIT_CREDENTIALS="oauth2:${GITHUB_TOKEN}"
export CI=true
export GIT_BRANCH="$branch"
export RELEASE_REPO_ROOT="$clone_dir"
export GIT_AUTHOR_NAME=semantic-release
export GIT_AUTHOR_EMAIL=semantic-release@vanixiets.local
export GIT_COMMITTER_NAME=semantic-release
export GIT_COMMITTER_EMAIL=semantic-release@vanixiets.local

# list-packages-json resolves the repo root with git rev-parse --show-toplevel.
cd "$clone_dir"
packages_json="$("$RELEASE_PACKAGES_LIST")"
echo "packages discovered: $packages_json"

failed_packages=()
while IFS= read -r pkg_path; do
  [ -z "$pkg_path" ] && continue
  echo "RELEASE-PACKAGE-ITERATION: $pkg_path"
  rc=0
  "$RELEASE_PACKAGES_RELEASE" "$pkg_path" </dev/null || rc=$?
  if [ "$rc" -eq 0 ]; then
    echo "RELEASE-PACKAGE-OK: $pkg_path"
  else
    echo "RELEASE-PACKAGE-FAILURE: $pkg_path (exit $rc)"
    failed_packages+=("$pkg_path")
  fi
done < <(printf '%s\n' "$packages_json" | jq -r '.[].path')

if [ "${#failed_packages[@]}" -gt 0 ]; then
  echo "error: ${#failed_packages[@]} package(s) failed: ${failed_packages[*]}" >&2
  exit 1
fi
