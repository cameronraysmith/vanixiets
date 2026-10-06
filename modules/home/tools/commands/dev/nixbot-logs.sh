#!/usr/bin/env bash
# shellcheck shell=bash
# Fetch nixbot build logs over nixbot's public HTTP API.
#
# Wrapped form: invoked as `nixbot-logs <subcommand> ...` after activation
# via writeShellApplication in ./nixbot-logs.nix.
#
# Direct execution: `./modules/home/tools/commands/dev/nixbot-logs.sh show`
# requires curl and jq on PATH.
#
# The API surface is self-documented by each instance at GET /llms.txt, and
# upstream in nixbot/web/app.py (LLMS_TXT).
set -euo pipefail

url="${NIXBOT_URL:-https://nixbot.scientistexperience.net}"
repo="${NIXBOT_REPO:-cameronraysmith/vanixiets}"
forge="${NIXBOT_FORGE:-github}"
token="${NIXBOT_TOKEN:-}"

tail_lines=""
drv=""
ansi=0
as_json=0
dir=""
full=0
failed_only=0
include_empty=0
limit=20
page=1
filter_branch=""
filter_pr=""
filter_status=""
filter_commit=""

# Client-side failure vocabulary, mirroring nixbot's AttributeStatus enum in
# nixbot/build_scheduler.py. Upstream TERMINAL_FAILURES is the first four;
# ignored_failure is a real build failure whose log is still worth reading,
# so it is included here.
failure_statuses=(failed failed_eval dependency_failed cached_failure ignored_failure)

usage() {
  cat <<'HELP'
Fetch nixbot build logs, statuses, and effect logs over nixbot's HTTP API

Usage: nixbot-logs SUBCOMMAND [ARGS] [OPTIONS]

Subcommands:
  builds                  List builds for the repository, newest first
  show [BUILD]            Build summary: per-attribute and per-effect status
  log ATTR [BUILD]        Print one attribute's build log as text
  effect NAME [BUILD]     Print one effect's log as text ('effect:NAME' sugar)
  failures [BUILD]        Print every failed attribute's log in one command
  toc ATTR [BUILD]        Per-derivation log table of contents for an attribute
  download [BUILD]        Write one file per attribute into a directory
  queue                   Global build queue across all repositories

BUILD is a build number or the literal 'latest' (the default when omitted).
Unlike buildbot, nixbot addresses a build by repository plus one build
number; there is no builder id and no per-step decomposition. Attributes,
including 'effect:<name>' attributes, take the place of buildbot steps.

Options:
  --repo OWNER/NAME  Repository (default: cameronraysmith/vanixiets)
  --url URL          nixbot instance (default: the deployed instance)
  --forge FORGE      Forge segment of the API path (default: github)
  --token TOKEN      Bearer token; only needed for private repositories
  --tail N           Last N lines only (log, effect, failures)
  --drv DRV          Restrict a log to one derivation (store path or name)
  --ansi             Keep ANSI colour escapes instead of stripping them
  --json             Emit raw API JSON (builds, show, failures, toc, queue)
  --limit N          Max builds to list, paging as needed (default: 20)
  --page N           First page of the build list to fetch (default: 1)
  --branch B         Filter the build list by branch
  --pr N             Filter the build list by pull request number
  --status S         Filter the build list by build status
  --commit SHA       Filter the build list by commit sha prefix
  --dir DIR          Output directory for 'download'
  --failed-only      'download': only failed attributes and effects
  --empty            'download': also write attributes that produced no log
  --full             'failures': complete logs instead of the API's tails
  -h, --help         This help

Environment:
  NIXBOT_URL    Override the instance URL.
  NIXBOT_REPO   Override the repository as OWNER/NAME.
  NIXBOT_FORGE  Override the forge path segment (default: github).
  NIXBOT_TOKEN  Bearer token for private repositories. Anonymous access
                works for public repositories, so leaving this unset is
                the normal case rather than a degraded one.

Examples:
  # What failed in the most recent build, with logs, in one command
  nixbot-logs failures

  # Same, but complete logs rather than the API's 50-line tails
  nixbot-logs failures --full > logs/nixbot-failures.log

  # Find the build for a commit, then read one check's log
  nixbot-logs builds --commit ad6a9e5
  nixbot-logs log checks.x86_64-linux.effects-interpreter 1 --tail 200

  # Effect logs; the 'effect:' attribute prefix is added for you
  nixbot-logs effect default.deploy-docs
  nixbot-logs log 'effect:default.deploy-docs'   # equivalent

  # Whole build to one file per attribute, for offline search
  nixbot-logs download 1 --dir logs/nixbot-1
  rg "error:" logs/nixbot-1

Mapping a PR check row to a build number:
  nixbot posts checks named nixbot/nix-eval and nixbot/nix-build whose
  target URL ends in /repos/<forge>/<owner>/<name>/builds/<BUILD>. The
  build number is also resolvable from the commit alone:
    nixbot-logs builds --commit "$(git rev-parse --short HEAD)"

Privacy: captured logs may include build output, worker names, and store
paths. Review before sharing publicly.
HELP
}

die() {
  local code="$1"
  shift
  printf 'Error: %s\n' "$*" >&2
  exit "$code"
}

args=()
while [ "$#" -gt 0 ]; do
  if [[ "$1" == --*=* ]]; then
    set -- "${1%%=*}" "${1#*=}" "${@:2}"
  fi
  case "$1" in
    -h | --help)
      usage
      exit 0
      ;;
    --repo)
      repo="${2:?--repo needs a value}"
      shift 2
      ;;
    --url)
      url="${2:?--url needs a value}"
      shift 2
      ;;
    --forge)
      forge="${2:?--forge needs a value}"
      shift 2
      ;;
    --token)
      token="${2:?--token needs a value}"
      shift 2
      ;;
    --tail)
      tail_lines="${2:?--tail needs a value}"
      shift 2
      ;;
    --drv)
      drv="${2:?--drv needs a value}"
      shift 2
      ;;
    --limit)
      limit="${2:?--limit needs a value}"
      shift 2
      ;;
    --page)
      page="${2:?--page needs a value}"
      shift 2
      ;;
    --branch)
      filter_branch="${2:?--branch needs a value}"
      shift 2
      ;;
    --pr)
      filter_pr="${2:?--pr needs a value}"
      shift 2
      ;;
    --status)
      filter_status="${2:?--status needs a value}"
      shift 2
      ;;
    --commit)
      filter_commit="${2:?--commit needs a value}"
      shift 2
      ;;
    --dir)
      dir="${2:?--dir needs a value}"
      shift 2
      ;;
    --ansi)
      ansi=1
      shift
      ;;
    --json)
      as_json=1
      shift
      ;;
    --full)
      full=1
      shift
      ;;
    --failed-only)
      failed_only=1
      shift
      ;;
    --empty)
      include_empty=1
      shift
      ;;
    --)
      shift
      args+=("$@")
      break
      ;;
    -*)
      die 2 "unknown option '$1'; try 'nixbot-logs --help'"
      ;;
    *)
      args+=("$1")
      shift
      ;;
  esac
done

subcommand="${args[0]-}"
if [ -z "$subcommand" ]; then
  usage >&2
  die 2 "a subcommand is required"
fi

numeric_opts=("$limit" "$page")
[ -n "$tail_lines" ] && numeric_opts+=("$tail_lines")
[ -n "$filter_pr" ] && numeric_opts+=("$filter_pr")
for candidate in "${numeric_opts[@]}"; do
  case "$candidate" in
    "" | *[!0-9]*) die 2 "numeric option value expected, got '$candidate'" ;;
  esac
done

owner="${repo%%/*}"
name="${repo#*/}"
if [ -z "$owner" ] || [ -z "$name" ] || [ "$owner" = "$repo" ] || [[ "$name" == */* ]]; then
  die 2 "--repo must be OWNER/NAME, got '$repo'"
fi

url="${url%/}"

curl_opts=(-sS --connect-timeout 10 --max-time 900)
[ -n "$token" ] && curl_opts+=(-H "Authorization: Bearer $token")

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# Percent-encode the characters that would otherwise change the meaning of a
# path segment. '/' is deliberately preserved: nixbot's log routes use a
# :path converter precisely because attribute names contain slashes, while
# effect attributes ('effect:<name>') require the colon encoded or the route
# does not match at all.
enc() {
  local s="$1"
  s="${s//%/%25}"
  s="${s//:/%3A}"
  s="${s//\#/%23}"
  s="${s//\?/%3F}"
  s="${s//&/%26}"
  s="${s// /%20}"
  printf '%s' "$s"
}

repo_path() { printf '%s' "/api/repos/$forge/$owner/$name$1"; }

# req PATH WHAT -> body on stdout, or a clear diagnostic and exit.
req() {
  local path="$1" what="$2" code body detail
  body="$(mktemp "$tmp/body.XXXXXX")"
  code=$(curl "${curl_opts[@]}" -o "$body" -w '%{http_code}' -- "$url$path") ||
    die 5 "cannot reach $url while fetching $what"
  case "$code" in
    2*)
      cat "$body"
      return 0
      ;;
    404) die 4 "$what not found on $url" ;;
    401 | 403)
      die 6 "$what: not authorized. Public repositories need no credentials; for a private one set NIXBOT_TOKEN (create a token at $url/settings/tokens)."
      ;;
    5*) die 5 "$what: nixbot returned HTTP $code (server error)" ;;
    *)
      detail=$(jq -r '.detail? // empty' "$body" 2>/dev/null || true)
      die 5 "$what: nixbot returned HTTP $code${detail:+ ($detail)}"
      ;;
  esac
}

# req_soft PATH -> body on stdout, nonzero on any non-2xx. For per-item
# fetches during a bulk download, where one missing log must not abort.
req_soft() {
  local path="$1" code body
  body="$(mktemp "$tmp/soft.XXXXXX")"
  code=$(curl "${curl_opts[@]}" -o "$body" -w '%{http_code}' -- "$url$path") || return 1
  case "$code" in
    2*)
      cat "$body"
      return 0
      ;;
    *) return 1 ;;
  esac
}

resolve_build() {
  local want="${1:-latest}" number
  if [ "$want" = latest ] || [ -z "$want" ]; then
    number=$(req "$(repo_path /builds)" "repository $repo" |
      jq -r '.items[0].number // empty')
    [ -n "$number" ] || die 4 "no builds recorded for $repo on $url"
    printf '%s' "$number"
    return 0
  fi
  case "$want" in
    *[!0-9]*) die 2 "BUILD must be a positive integer or 'latest', got '$want'" ;;
  esac
  printf '%s' "$want"
}

log_query() {
  local q=""
  [ -n "$tail_lines" ] && q="${q}&tail=$tail_lines"
  [ -n "$drv" ] && q="${q}&drv=$(enc "$drv")"
  [ "$ansi" -eq 1 ] && q="${q}&ansi=1"
  [ -n "$q" ] && printf '?%s' "${q#&}"
  return 0
}

# As log_query, minus --tail: 'failures --full' asks for whole logs while
# --tail still governs the summary the API returns.
untailed_log_query() {
  local q=""
  [ -n "$drv" ] && q="${q}&drv=$(enc "$drv")"
  [ "$ansi" -eq 1 ] && q="${q}&ansi=1"
  [ -n "$q" ] && printf '?%s' "${q#&}"
  return 0
}

failure_status_json() {
  printf '%s\n' "${failure_statuses[@]}" | jq -R -s 'split("\n") | map(select(. != ""))'
}

is_failure_status() {
  local candidate="$1" known
  for known in "${failure_statuses[@]}"; do
    [ "$candidate" = "$known" ] && return 0
  done
  return 1
}

print_eval_warnings() {
  jq -r '
    (.eval_warnings // [])
    | if length == 0 then empty
      else "=== EVAL WARNINGS ===", (.[] | "  [\(.level)] x\(.count) \(.message)"), ""
      end' <<<"$1"
}

attr_missing() {
  local build="$1" attr="$2"
  case "$attr" in
    effect:*)
      die 4 "build $build of $repo has no effect '${attr#effect:}'; run 'nixbot-logs show $build' to list its effects"
      ;;
    *)
      die 4 "build $build of $repo has no attribute '$attr'; run 'nixbot-logs show $build' to list its attributes"
      ;;
  esac
}

failed_effect_names() {
  jq -r --argjson failures "$(failure_status_json)" \
    '.effects[] | select(.status | IN($failures[])) | .name' <<<"$1"
}

cmd_builds() {
  local pg="$page" filters="" query body collected='[]' has_next count
  [ -n "$filter_branch" ] && filters="$filters&branch=$(enc "$filter_branch")"
  [ -n "$filter_pr" ] && filters="$filters&pr_number=$filter_pr"
  [ -n "$filter_status" ] && filters="$filters&status=$(enc "$filter_status")"
  [ -n "$filter_commit" ] && filters="$filters&commit=$(enc "$filter_commit")"

  while :; do
    query="page=$pg$filters"
    body=$(req "$(repo_path /builds)?$query" "repository $repo")
    collected=$(jq --argjson acc "$collected" '$acc + .items' <<<"$body")
    has_next=$(jq -r '.has_next' <<<"$body")
    count=$(jq 'length' <<<"$collected")
    [ "$has_next" = true ] && [ "$count" -lt "$limit" ] || break
    pg=$((pg + 1))
  done
  collected=$(jq --argjson n "$limit" '.[:$n]' <<<"$collected")

  if [ "$as_json" -eq 1 ]; then
    printf '%s\n' "$collected"
    return 0
  fi
  if [ "$(jq 'length' <<<"$collected")" -eq 0 ]; then
    printf 'No builds matched for %s on %s.\n' "$repo" "$url" >&2
    return 0
  fi

  printf '%-6s %-12s %-6s %-26s %-9s %s\n' \
    BUILD STATUS PR BRANCH COMMIT FINISHED
  jq -r '.[] | [
      .number,
      .status,
      (if .pr_number == null then "-" else "#\(.pr_number)" end),
      (.branch | if (. // "") == "" then "-" else . end),
      (((.commit_sha // "")[0:8]) | if . == "" then "-" else . end),
      (.finished_at // .started_at // "-")
    ] | @tsv' <<<"$collected" |
    while IFS=$'\t' read -r number status pr branch commit finished; do
      printf '%-6s %-12s %-6s %-26s %-9s %s\n' \
        "$number" "$status" "$pr" "$branch" "$commit" "$finished"
    done
}

cmd_show() {
  local build detail
  build=$(resolve_build "${args[1]-latest}")
  detail=$(req "$(repo_path "/builds/$build")" "build $build of $repo")

  if [ "$as_json" -eq 1 ]; then
    printf '%s\n' "$detail"
    return 0
  fi

  jq -r --arg repo "$repo" --arg url "$url" --arg forge "$forge" '
    .build as $b
    | "=== BUILD \($b.number) of \($repo) ===",
      "status:   \($b.status)",
      "branch:   \($b.branch)\(if $b.pr_number == null then "" else " (PR #\($b.pr_number) by \($b.pr_author // "?"))" end)",
      "commit:   \($b.commit_sha)",
      "started:  \($b.started_at // "-")",
      "finished: \($b.finished_at // "-")",
      (if $b.error == null then empty else "error:    \($b.error)" end),
      "url:      \($url)/repos/\($forge)/\($repo)/builds/\($b.number)",
      ""' <<<"$detail"

  print_eval_warnings "$(jq '.build' <<<"$detail")"

  jq -r '
    "=== ATTRIBUTES (\(.attributes | length)) ===",
    ("counts: " + ([.attributes[].status] | group_by(.) | map("\(.[0])=\(length)") | join("  "))),
    ""' <<<"$detail"
  printf '%-18s %-9s %s\n' STATUS LOGBYTES ATTR
  jq -r '.attributes[] | [.status, (.log_size // 0), .attr] | @tsv' <<<"$detail" |
    while IFS=$'\t' read -r status size attr; do
      printf '%-18s %-9s %s\n' "$status" "$size" "$attr"
    done

  printf '\n=== EFFECTS (%s) ===\n' "$(jq '.effects | length' <<<"$detail")"
  if [ "$(jq '.effects | length' <<<"$detail")" -gt 0 ]; then
    printf '%-18s %-30s %s\n' STATUS NAME FINISHED
    jq -r '.effects[] | [.status, .name, (.finished_at // "-")] | @tsv' <<<"$detail" |
      while IFS=$'\t' read -r status effect finished; do
        printf '%-18s %-30s %s\n' "$status" "$effect" "$finished"
      done
  fi
}

cmd_log() {
  local attr="${args[1]-}" build text status
  [ -n "$attr" ] || die 2 "ATTR is required: nixbot-logs log ATTR [BUILD]"
  build=$(resolve_build "${args[2]-latest}")
  if text=$(req_soft "$(repo_path "/builds/$build/logs/$(enc "$attr")/text")$(log_query)"); then
    printf '%s\n' "$text"
    return 0
  fi
  # A missing log body is two different situations, which the table-of-contents
  # endpoint separates: 200 with an empty derivation list for an attribute that
  # never produced a log (cached, or built on this machine), against 404
  # "unknown attribute" for one that is not in the build at all.
  status=$(req_soft "$(repo_path "/builds/$build/logs/$(enc "$attr")")" |
    jq -r '.status // "unknown"') || attr_missing "$build" "$attr"
  printf 'Note: %s produced no log in build %s (status: %s).\n' \
    "$attr" "$build" "$status" >&2
}

cmd_effect() {
  local effect="${args[1]-}"
  [ -n "$effect" ] || die 2 "NAME is required: nixbot-logs effect NAME [BUILD]"
  case "$effect" in
    effect:*) : ;;
    *) effect="effect:$effect" ;;
  esac
  args=(log "$effect" "${args[2]-latest}")
  cmd_log
}

cmd_toc() {
  local attr="${args[1]-}" build toc
  [ -n "$attr" ] || die 2 "ATTR is required: nixbot-logs toc ATTR [BUILD]"
  build=$(resolve_build "${args[2]-latest}")
  toc=$(req "$(repo_path "/builds/$build/logs/$(enc "$attr")")" \
    "log table of contents for '$attr' in build $build of $repo")
  if [ "$as_json" -eq 1 ]; then
    printf '%s\n' "$toc"
    return 0
  fi
  jq -r '"=== \(.attr) (\(.status)) ==="' <<<"$toc"
  printf '%-4s %-10s %-6s %-7s %-24s %s\n' IDX STATUS LINES MS PHASES DERIVATION
  jq -r '.derivations[]? | [
      .idx,
      .status,
      (.n // 0),
      (if (.t0 // null) == null or (.t1 // null) == null then "-" else (.t1 - .t0) end),
      (((.ph // []) | map(if type == "array" then .[0] else tostring end) | join(","))
       | if . == "" then "-" else . end),
      (.name // .drv // "-")
    ] | @tsv' <<<"$toc" |
    while IFS=$'\t' read -r idx status lines elapsed phases derivation; do
      printf '%-4s %-10s %-6s %-7s %-24s %s\n' \
        "$idx" "$status" "$lines" "$elapsed" "$phases" "$derivation"
    done
}

cmd_failures() {
  local build summary detail effects count attr status error
  build=$(resolve_build "${args[1]-latest}")
  summary=$(req "$(repo_path "/builds/$build/failures")?tail=${tail_lines:-50}" \
    "failure summary for build $build of $repo")
  detail=$(req "$(repo_path "/builds/$build")" "build $build of $repo")
  effects=$(failed_effect_names "$detail")

  if [ "$as_json" -eq 1 ]; then
    jq --argjson failed_effects \
      "$(printf '%s' "$effects" | jq -R -s 'split("\n") | map(select(. != ""))')" \
      '. + {failed_effects: $failed_effects}' <<<"$summary"
    return 0
  fi

  count=$(jq '.failures | length' <<<"$summary")
  jq -r --arg build "$build" --arg repo "$repo" '
    "=== BUILD \($build) of \($repo): \(.status) ===",
    (if .error == null then empty else "error: \(.error)" end),
    ""' <<<"$summary"
  print_eval_warnings "$summary"

  if [ "$count" -eq 0 ] && [ -z "$effects" ]; then
    printf 'No failed attributes or effects in build %s of %s (status: %s).\n' \
      "$build" "$repo" "$(jq -r '.status' <<<"$summary")" >&2
    return 0
  fi

  while IFS=$'\t' read -r attr status error; do
    [ -n "$attr" ] || continue
    printf '=== FAILED ATTRIBUTE: %s (%s) ===\n' "$attr" "$status"
    [ "$error" != null ] && [ -n "$error" ] && printf 'error: %s\n' "$error"
    printf '\n'
    if [ "$full" -eq 1 ]; then
      req_soft "$(repo_path "/builds/$build/logs/$(enc "$attr")/text")$(untailed_log_query)" ||
        printf '(no log stored for attribute %s)\n' "$attr"
    else
      jq -r --arg attr "$attr" \
        '.failures[] | select(.attr == $attr) | .log_tail // "(no log captured)"' \
        <<<"$summary"
    fi
    printf '\n'
  done < <(jq -r '.failures[] | [.attr, .status,
    (if (.error // "") == "" then "null" else .error end)] | @tsv' <<<"$summary")

  while IFS= read -r effect; do
    [ -n "$effect" ] || continue
    printf '=== FAILED EFFECT: %s ===\n' "$effect"
    req_soft "$(repo_path "/builds/$build/logs/$(enc "effect:$effect")/text")$(log_query)" ||
      printf '(no log available for effect %s)\n' "$effect"
    printf '\n'
  done <<<"$effects"
}

cmd_download() {
  local build detail target attr status size effect filename
  local written=0 skipped=0 empty=0
  build=$(resolve_build "${args[1]-latest}")
  detail=$(req "$(repo_path "/builds/$build")" "build $build of $repo")
  target="${dir:-nixbot-$owner-$name-$build}"
  mkdir -p "$target"
  printf '%s\n' "$detail" >"$target/build.json"

  while IFS=$'\t' read -r status size attr; do
    [ -n "$attr" ] || continue
    if [ "$failed_only" -eq 1 ] && ! is_failure_status "$status"; then
      skipped=$((skipped + 1))
      continue
    fi
    if [ "$size" -eq 0 ] && [ "$include_empty" -eq 0 ]; then
      empty=$((empty + 1))
      continue
    fi
    filename="${attr//\//_}"
    filename="${filename//:/_}"
    if req_soft "$(repo_path "/builds/$build/logs/$(enc "$attr")/text")$(log_query)" \
      >"$target/$filename.log"; then
      written=$((written + 1))
    else
      rm -f "$target/$filename.log"
      printf 'Note: no log stored for attribute %s\n' "$attr" >&2
    fi
  done < <(jq -r '.attributes[] | [.status, (.log_size // 0), .attr] | @tsv' <<<"$detail")

  while IFS=$'\t' read -r status effect; do
    [ -n "$effect" ] || continue
    if [ "$failed_only" -eq 1 ] && ! is_failure_status "$status"; then
      skipped=$((skipped + 1))
      continue
    fi
    filename="effect-${effect//\//_}"
    if req_soft "$(repo_path "/builds/$build/logs/$(enc "effect:$effect")/text")$(log_query)" \
      >"$target/$filename.log"; then
      written=$((written + 1))
    else
      rm -f "$target/$filename.log"
      printf 'Note: no log stored for effect %s\n' "$effect" >&2
    fi
  done < <(jq -r '.effects[] | [.status, .name] | @tsv' <<<"$detail")

  printf 'Wrote %s log file(s) to %s (build.json holds the full build detail).\n' \
    "$written" "$target" >&2
  if [ "$empty" -gt 0 ]; then
    printf '%s attribute(s) produced no log (cached or built locally); pass --empty to write them anyway.\n' \
      "$empty" >&2
  fi
  if [ "$skipped" -gt 0 ]; then
    printf '%s non-failed item(s) skipped by --failed-only.\n' "$skipped" >&2
  fi
}

cmd_queue() {
  local queue
  queue=$(req "/api/queue" "global build queue")
  if [ "$as_json" -eq 1 ]; then
    printf '%s\n' "$queue"
    return 0
  fi
  if [ "$(jq 'length' <<<"$queue")" -eq 0 ]; then
    printf 'Queue is empty on %s.\n' "$url" >&2
    return 0
  fi
  printf '%-6s %-12s %-5s %-30s %s\n' BUILD STATUS POS REPO BRANCH
  jq -r '.[] | [
      .number, .status, (.queue_position // "run"),
      "\(.owner)/\(.project_name)",
      (.branch | if (. // "") == "" then "-" else . end)
    ] | @tsv' <<<"$queue" |
    while IFS=$'\t' read -r number status position queued_repo branch; do
      printf '%-6s %-12s %-5s %-30s %s\n' \
        "$number" "$status" "$position" "$queued_repo" "$branch"
    done
}

case "$subcommand" in
  builds) cmd_builds ;;
  show) cmd_show ;;
  log) cmd_log ;;
  effect) cmd_effect ;;
  failures) cmd_failures ;;
  toc) cmd_toc ;;
  download) cmd_download ;;
  queue) cmd_queue ;;
  *) die 2 "unknown subcommand '$subcommand'; try 'nixbot-logs --help'" ;;
esac
