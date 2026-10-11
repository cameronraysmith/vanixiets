#!/usr/bin/env bash
# Report every open PR against the queue's required-check set and authorize
# gitea-mq by enabling GitHub native auto-merge on the ones that are green.
#
# The required set is derived from the live forge configuration (active branch
# rulesets that cover the target branch, unioned with classic protection), the
# same source gitea-mq uses (internal/monitor/monitor.go::ResolveRequiredChecks,
# internal/github/forge.go::GetRequiredChecks). The queue's own context is
# excluded: it is posted only after enqueue, so requiring it would deadlock.
set -euo pipefail

show_help() {
  cat <<'HELP'
Report required-check status for open PRs and authorize the merge queue

Usage: gh-queue-open-prs [OPTIONS] [EXCLUDE...]

Reads the required status checks from the repository's live branch rulesets
and classic protection, evaluates every open PR against that set, prints one
verdict line per PR, then enables GitHub native auto-merge on each green,
eligible PR. Enabling auto-merge is the enqueue signal: gitea-mq picks the PR
up, tests it in a batch, and lands it asynchronously.

Arguments:
  EXCLUDE...               PR numbers to leave untouched

Options:
  -n, --dry-run            Report only; change nothing
  -l, --limit N            Authorize at most N PRs this run (0 = no cap)
  -m, --merge-method M     rebase | merge | squash (default: rebase)
  -b, --base BRANCH        Target branch (default: repository default branch)
      --require CONTEXT    Override the derived required set (repeatable)
      --queue-check NAME   Queue-owned context to exclude (default: gitea-mq)
      --pending            Also authorize PRs whose required checks are still
                           running; auto-merge waits for them
      --approve            Submit an approving review alongside authorization
      --fetch-limit N      Max open PRs to fetch (default: 200)
  -h, --help               Show this help message

Verdicts:
  green         every required check passed; eligible for authorization
  pending       at least one required check queued, running, or not yet posted
  failing       at least one required check failed
  queued        auto-merge already enabled; left alone
  stacked       carries the queue label, or targets a branch other than BASE;
                stack members are authorized by labelling the topmost PR only
  conflicting   not mergeable against BASE; rebase it first
  draft         draft PR

Examples:
  gh-queue-open-prs -n                 # report only
  gh-queue-open-prs                    # authorize every green PR
  gh-queue-open-prs -l 20              # authorize at most one batch worth
  gh-queue-open-prs 2956               # authorize all green PRs except #2956
  gh-queue-open-prs --approve -l 5     # approve and authorize five

Requirements:
  - GitHub CLI (gh) authenticated with repo scope
  - Run inside a git repository with a GitHub remote
HELP
}

dry_run=false
approve=false
allow_pending=false
limit=0
fetch_limit=200
merge_method="rebase"
base=""
queue_check="gitea-mq"
exclude_prs=()
require_override=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h | --help)
      show_help
      exit 0
      ;;
    -n | --dry-run)
      dry_run=true
      shift
      ;;
    -l | --limit)
      limit="$2"
      shift 2
      ;;
    -m | --merge-method)
      merge_method="$2"
      shift 2
      ;;
    -b | --base)
      base="$2"
      shift 2
      ;;
    --require)
      require_override+=("$2")
      shift 2
      ;;
    --queue-check)
      queue_check="$2"
      shift 2
      ;;
    --pending)
      allow_pending=true
      shift
      ;;
    --approve)
      approve=true
      shift
      ;;
    --fetch-limit)
      fetch_limit="$2"
      shift 2
      ;;
    -*)
      echo "Error: Unknown option: $1" >&2
      echo "Try 'gh-queue-open-prs --help' for more information." >&2
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

case "$merge_method" in
  rebase | merge | squash) ;;
  *)
    echo "Error: --merge-method must be rebase, merge, or squash: $merge_method" >&2
    exit 1
    ;;
esac

for n in "$limit" "$fetch_limit"; do
  [[ "$n" =~ ^[0-9]+$ ]] || {
    echo "Error: numeric option value expected: $n" >&2
    exit 1
  }
done

repo=$(gh repo view --json nameWithOwner --jq '.nameWithOwner')
repo_json=$(gh api "repos/$repo")
default_branch=$(jq -r '.default_branch' <<<"$repo_json")
[[ -n "$base" ]] || base="$default_branch"

if [[ "$(jq -r '.allow_auto_merge' <<<"$repo_json")" != "true" ]]; then
  echo "Error: $repo does not allow auto-merge; enable it in repository settings." >&2
  exit 1
fi

method_allowed=$(jq -r --arg m "$merge_method" '
  {rebase: .allow_rebase_merge, merge: .allow_merge_commit, squash: .allow_squash_merge}[$m]
' <<<"$repo_json")
if [[ "$method_allowed" != "true" ]]; then
  echo "Error: $repo does not allow the $merge_method merge method." >&2
  exit 1
fi

# Required-check set: active branch rulesets covering BASE, plus classic
# protection, minus the queue-owned context.
if [[ ${#require_override[@]} -gt 0 ]]; then
  mapfile -t required < <(printf '%s\n' "${require_override[@]}" | sort -u)
  required_source="--require"
else
  ruleset_ids=$(gh api "repos/$repo/rulesets" \
    --jq '.[] | select(.target == "branch" and .enforcement == "active") | .id')
  contexts=$(
    for id in $ruleset_ids; do
      gh api "repos/$repo/rulesets/$id" \
        | jq -r --arg base "$base" --arg default "$default_branch" '
          (((.conditions.ref_name.include) // []) | any(
              . == "~ALL"
              or (. == "~DEFAULT_BRANCH" and $base == $default)
              or . == ("refs/heads/" + $base)
            )) as $covers
          | select($covers)
          | .rules[]?
          | select(.type == "required_status_checks")
          | .parameters.required_status_checks[]?.context
        '
    done
    if classic=$(gh api "repos/$repo/branches/$base/protection" \
      --jq '.required_status_checks.contexts[]?' 2>/dev/null); then
      printf '%s\n' "$classic"
    fi
  )
  mapfile -t required < <(printf '%s\n' "$contexts" | sed '/^$/d' | sort -u | grep -vxF "$queue_check" || true)
  required_source="forge configuration"
fi

if [[ ${#required[@]} -eq 0 ]]; then
  echo "Error: no required checks derived from $required_source for $base." >&2
  echo "The landing gate would be empty; pass --require explicitly if intended." >&2
  exit 1
fi

echo "Repository:      $repo"
echo "Target branch:   $base"
echo "Queue context:   $queue_check (excluded; posted after enqueue)"
echo "Required checks: ${required[*]}  [$required_source]"
echo "Merge method:    $merge_method --auto"
echo

prs_json=$(gh pr list --state open --base "$base" --limit "$fetch_limit" \
  --json number,title,isDraft,baseRefName,mergeable,autoMergeRequest,labels,statusCheckRollup)
# gh --base filters server-side; stack members targeting other branches are
# fetched separately so they are reported rather than silently dropped.
stacked_json=$(gh pr list --state open --limit "$fetch_limit" \
  --json number,title,baseRefName \
  | jq --arg base "$base" '[.[] | select(.baseRefName != $base)]')

report=$(jq -r \
  --argjson required "$(printf '%s\n' "${required[@]}" | jq -R . | jq -s .)" \
  --argjson exclude "$(printf '%s\n' "${exclude_prs[@]+"${exclude_prs[@]}"}" | jq -R 'select(length > 0) | tonumber' | jq -s .)" \
  --arg label "$queue_check" '
  def passing: ["SUCCESS", "NEUTRAL", "SKIPPED"];
  def failing: ["FAILURE", "ERROR", "CANCELLED", "TIMED_OUT", "ACTION_REQUIRED", "STARTUP_FAILURE"];

  .[]
  | . as $pr
  | ([$required[]
      | . as $ctx
      | ([$pr.statusCheckRollup[]? | select((.name // .context) == $ctx)] | last) as $e
      | if $e == null then
          { ctx: $ctx, state: "missing", kind: "pending" }
        elif ($e.__typename == "CheckRun" and $e.status != "COMPLETED") then
          { ctx: $ctx, state: ($e.status | ascii_downcase), kind: "pending" }
        else
          (($e.conclusion // $e.state // "") | ascii_upcase) as $st
          | { ctx: $ctx,
              state: $st,
              kind: (if passing | index($st) then "pass"
                     elif failing | index($st) then "fail"
                     else "pending" end) }
        end
     ]) as $checks
  | (if any($checks[]; .kind == "fail") then "failing"
     elif any($checks[]; .kind == "pending") then "pending"
     else "green" end) as $checkVerdict
  | (if $pr.isDraft then "draft"
     elif ($exclude | index($pr.number)) then "excluded"
     elif $pr.autoMergeRequest != null then "queued"
     elif ([$pr.labels[].name] | index($label)) then "stacked"
     elif $pr.mergeable == "CONFLICTING" then "conflicting"
     else $checkVerdict end) as $verdict
  | [ ($pr.number | tostring),
      $verdict,
      ([$checks[] | select(.kind != "pass") | .ctx + "=" + .state] | join(",") | if . == "" then "-" else . end),
      $pr.title
    ] | @tsv
' <<<"$prs_json")

stacked_report=$(jq -r '.[] | [(.number | tostring), "stacked", "base=" + .baseRefName, .title] | @tsv' <<<"$stacked_json")

if [[ -n "$stacked_report" ]]; then
  report=$(printf '%s\n%s' "$report" "$stacked_report")
fi

printf '%-7s %-12s %-14s %s\n' "PR" "VERDICT" "BLOCKERS" "TITLE"
while IFS=$'\t' read -r num verdict blockers title; do
  [[ -n "$num" ]] || continue
  printf '%-7s %-12s %-14s %s\n' "#$num" "$verdict" "$blockers" "$title"
done <<<"$report"
echo

green=()
pending=()
while IFS=$'\t' read -r num verdict _ _; do
  [[ -n "$num" ]] || continue
  case "$verdict" in
    green) green+=("$num") ;;
    pending) pending+=("$num") ;;
  esac
done <<<"$report"

candidates=("${green[@]+"${green[@]}"}")
if $allow_pending; then
  candidates+=("${pending[@]+"${pending[@]}"}")
fi

if [[ ${#candidates[@]} -eq 0 ]]; then
  echo "Nothing to authorize."
  exit 0
fi

if [[ "$limit" -gt 0 && ${#candidates[@]} -gt "$limit" ]]; then
  candidates=("${candidates[@]:0:$limit}")
  echo "Limiting authorization to $limit PR(s)."
fi

echo "Authorizing: ${candidates[*]}"
if $dry_run; then
  echo "[Dry run] Would enable auto-merge (--auto --$merge_method) on ${#candidates[@]} PR(s)."
  if $approve; then echo "[Dry run] Would also approve those PRs."; fi
  exit 0
fi

authorized=0
failed=0
for pr in "${candidates[@]}"; do
  if $approve; then
    gh pr review "$pr" --approve || echo "Warning: failed to approve PR #$pr" >&2
  fi
  echo "Enqueueing PR #$pr..."
  if gh pr merge "$pr" --auto "--$merge_method"; then
    authorized=$((authorized + 1))
  else
    echo "Warning: failed to enable auto-merge on PR #$pr" >&2
    failed=$((failed + 1))
  fi
done

echo
echo "Authorized: $authorized, Failed: $failed"
echo "Landing now belongs to the queue; watch the $queue_check status on each PR."
