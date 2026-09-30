#!/usr/bin/env bash
# shellcheck shell=bash
# release-packages.sh - semantic-release for every monorepo package at a main rev.
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
# RELEASE_PACKAGES_LIST and RELEASE_PACKAGES_RELEASE are the list-packages-json
# and release programs, injected by release-packages.nix runtimeEnv.

set -euo pipefail

usage() {
  cat <<'EOF'
usage: release-packages --rev <40-hex>
       release-packages --help

Clone the repository at <rev> as branch main and run the release app for
every package list-packages-json reports. Skips (exit 0) when <rev> is an
ancestor of origin/main; fails when <rev> is not in main's history.

Environment:
  GITHUB_TOKEN               required; release authority for tags and releases.
  RELEASE_PACKAGES_REPO_URL  clone URL, default
                             https://github.com/cameronraysmith/vanixiets.git
EOF
}

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
