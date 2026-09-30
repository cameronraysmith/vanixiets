#!/usr/bin/env bash
# shellcheck shell=bash
# Creates and completes GitHub check runs for nixbot effects, which post no
# commit status of their own. One implementation keeps every effect's
# requests identical in shape and authenticated only by nixbot's forge token.
#
# Test seam: GITHUB_API_URL (API base).

set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  github-check-run create --repo <owner/name> --name <check> --head-sha <sha>
  github-check-run complete --repo <owner/name> --id <id>
      --conclusion <success|neutral|failure> --title <title> --summary <summary>
      [--details-url <url>]

create prints the new check run's numeric id on stdout.

Environment:
  GITHUB_FORGE_TOKEN   required; the forge installation token
  GITHUB_API_URL       API base (default https://api.github.com)
EOF
}

usage_error() {
  echo "github-check-run: $*" >&2
  usage >&2
  exit 1
}

mode="${1:-}"
case "$mode" in
  create | complete) shift ;;
  -h | --help)
    usage
    exit 0
    ;;
  *) usage_error "unknown mode '${mode}'" ;;
esac

repo="" name="" head_sha="" id="" conclusion="" title="" summary="" details_url=""
have_title="" have_summary=""
while [[ $# -gt 0 ]]; do
  [[ $# -ge 2 ]] || usage_error "$1 needs a value"
  case "$mode:$1" in
    *:--repo) repo=$2 ;;
    create:--name) name=$2 ;;
    create:--head-sha) head_sha=$2 ;;
    complete:--id) id=$2 ;;
    complete:--conclusion) conclusion=$2 ;;
    complete:--title) title=$2 have_title=1 ;;
    complete:--summary) summary=$2 have_summary=1 ;;
    complete:--details-url) details_url=$2 ;;
    *) usage_error "unknown option '$1' for $mode" ;;
  esac
  shift 2
done

[[ "$repo" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || usage_error "--repo must be owner/name, got '$repo'"
if [[ "$mode" == create ]]; then
  [[ -n "$name" ]] || usage_error "--name is required"
  [[ "$head_sha" =~ ^[0-9a-f]{40}$ ]] || usage_error "--head-sha must be 40 hex digits, got '$head_sha'"
else
  [[ "$id" =~ ^[0-9]+$ ]] || usage_error "--id must be numeric, got '$id'"
  case "$conclusion" in
    success | neutral | failure) ;;
    *) usage_error "--conclusion must be success, neutral or failure, got '$conclusion'" ;;
  esac
  [[ -n "$have_title" ]] || usage_error "--title is required"
  [[ -n "$have_summary" ]] || usage_error "--summary is required"
fi

: "${GITHUB_FORGE_TOKEN:?GITHUB_FORGE_TOKEN is required}"

# request <method> <path> <json body>: prints the response body; a non-2xx
# response is reported with its body and exits 1.
request() {
  local method=$1 url="${GITHUB_API_URL:-https://api.github.com}/repos/$repo/$2" response
  response="$(
    curl --fail-with-body -sS --retry 3 -X "$method" "$url" \
      -H "Authorization: Bearer $GITHUB_FORGE_TOKEN" \
      -H 'Accept: application/vnd.github+json' \
      -H 'X-GitHub-Api-Version: 2022-11-28' \
      -H 'Content-Type: application/json' \
      --data @- <<<"$3"
  )" || {
    echo "github-check-run: $method $url failed${response:+: $response}" >&2
    exit 1
  }
  printf '%s\n' "$response"
}

if [[ "$mode" == create ]]; then
  body="$(jq -n --arg name "$name" --arg sha "$head_sha" '{name: $name, head_sha: $sha, status: "in_progress"}')"
  response="$(request POST check-runs "$body")"
  jq -er '.id | numbers' <<<"$response" || {
    echo "github-check-run: the check-runs response carries no numeric id: $response" >&2
    exit 1
  }
else
  body="$(jq -n --arg conclusion "$conclusion" --arg title "$title" --arg summary "$summary" --arg url "$details_url" '{
    status: "completed",
    conclusion: $conclusion,
    output: {title: $title, summary: $summary}
  } + (if $url == "" then {} else {details_url: $url} end)')"
  request PATCH "check-runs/$id" "$body" >/dev/null
fi
