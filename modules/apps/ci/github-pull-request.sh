#!/usr/bin/env bash
# shellcheck shell=bash
# Reports whether a pull request is still open at a given head. nixbot
# delivers pull_request effects in no guaranteed order and their payload is a
# delivery-time snapshot, so PR-triggered effects ask GitHub for the current
# state before acting instead of trusting the event.
#
# Test seam: GITHUB_API_URL (API base).

set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  github-pull-request state --repo <owner/name> --number <N> --head-sha <sha>

state prints exactly one word on stdout:
  current      the pull request is open and its head is --head-sha
  closed       the pull request is closed (including merged)
  superseded   the pull request is open at a different head

Environment:
  GITHUB_FORGE_TOKEN   required; the forge installation token
  GITHUB_API_URL       API base (default https://api.github.com)
EOF
}

usage_error() {
  echo "github-pull-request: $*" >&2
  usage >&2
  exit 1
}

mode="${1:-}"
case "$mode" in
  state) shift ;;
  -h | --help)
    usage
    exit 0
    ;;
  *) usage_error "unknown mode '${mode}'" ;;
esac

repo="" number="" head_sha=""
while [[ $# -gt 0 ]]; do
  [[ $# -ge 2 ]] || usage_error "$1 needs a value"
  case "$1" in
    --repo) repo=$2 ;;
    --number) number=$2 ;;
    --head-sha) head_sha=$2 ;;
    *) usage_error "unknown option '$1' for $mode" ;;
  esac
  shift 2
done

[[ "$repo" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || usage_error "--repo must be owner/name, got '$repo'"
[[ "$number" =~ ^[1-9][0-9]*$ ]] || usage_error "--number must be a positive integer, got '$number'"
[[ "$head_sha" =~ ^[0-9a-f]{40}$ ]] || usage_error "--head-sha must be 40 hex digits, got '$head_sha'"

: "${GITHUB_FORGE_TOKEN:?GITHUB_FORGE_TOKEN is required}"

url="${GITHUB_API_URL:-https://api.github.com}/repos/$repo/pulls/$number"
response="$(
  curl --fail-with-body -sS --retry 3 "$url" \
    -H "Authorization: Bearer $GITHUB_FORGE_TOKEN" \
    -H 'Accept: application/vnd.github+json' \
    -H 'X-GitHub-Api-Version: 2022-11-28'
)" || {
  echo "github-pull-request: GET $url failed${response:+: $response}" >&2
  exit 1
}

jq -er --arg sha "$head_sha" '
  if .state == "closed" then "closed"
  elif .state == "open" and (.head.sha | strings) == $sha then "current"
  elif .state == "open" and (.head.sha | strings) then "superseded"
  else error("unrecognised pull request state")
  end' <<<"$response" || {
  echo "github-pull-request: the pull request response carries no usable state or head sha: $response" >&2
  exit 1
}
