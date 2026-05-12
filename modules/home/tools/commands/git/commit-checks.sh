#!/usr/bin/env bash
# Show commit-keyed checks for GitHub or Gitea remotes.
#
# Usage:
#   commit-checks [<sha>] [--repo owner/repo] [--json]
#
# Defaults: sha=HEAD, repo auto-detected from origin.

set -euo pipefail

usage() {
  cat <<'EOF'
Usage: commit-checks [<sha>] [--repo owner/repo] [--json]

Show commit-keyed checks for GitHub or Gitea remotes. Forge dispatch is by
the origin remote hostname (*github.com* → gh; otherwise → tea).

Defaults:
  sha    HEAD
  repo   auto-detected from origin
EOF
}

sha=""
repo=""
as_json=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo)
      repo="${2:?--repo requires a value}"
      shift 2
      ;;
    --json)
      as_json=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    -*)
      printf 'commit-checks: unknown flag: %s\n' "$1" >&2
      usage >&2
      exit 2
      ;;
    *)
      if [[ -z "$sha" ]]; then
        sha="$1"
        shift
      else
        printf 'commit-checks: unexpected positional argument: %s\n' "$1" >&2
        usage >&2
        exit 2
      fi
      ;;
  esac
done

if [[ -z "$sha" ]]; then
  sha="$(git rev-parse HEAD)"
fi

origin_url="$(git remote get-url origin 2>/dev/null || true)"
if [[ -z "$origin_url" ]]; then
  printf 'commit-checks: no origin remote configured\n' >&2
  exit 1
fi

case "$origin_url" in
  *github.com*) forge=github ;;
  *)            forge=gitea  ;;
esac

if [[ -z "$repo" ]]; then
  case "$forge" in
    github)
      repo="$(gh repo view --json nameWithOwner --jq .nameWithOwner)"
      ;;
    gitea)
      path="${origin_url%.git}"
      path="${path#*://}"
      path="${path#*@}"
      repo="${path#*[:/]}"
      ;;
  esac
fi

owner="${repo%%/*}"
name="${repo##*/}"

fetch_github() {
  local cr_json st_json
  cr_json="$(gh api "repos/$owner/$name/commits/$sha/check-runs" --paginate)"
  st_json="$(gh api "repos/$owner/$name/commits/$sha/status")"

  jq -c -n \
    --argjson cr "$cr_json" \
    --argjson st "$st_json" '
    def to_int($t): if $t == null then null else ($t | fromdateiso8601) end;
    def elapsed_seconds($s; $e):
      if $s == null or $e == null then null
      else (to_int($e) - to_int($s))
      end;
    ($cr.check_runs | map({
      name:      .name,
      state:     (if .status == "completed" then .conclusion else .status end),
      source:    "check-run",
      elapsed_s: elapsed_seconds(.started_at; .completed_at),
      url:       .html_url
    }))
    +
    ($st.statuses | map({
      name:      .context,
      state:     .state,
      source:    "status",
      elapsed_s: null,
      url:       .target_url
    }))
    | .[]
  '
}

fetch_gitea() {
  local sts_json acts_json
  sts_json="$(tea api "/repos/$owner/$name/commits/$sha/statuses")"
  acts_json="$(tea api "/repos/$owner/$name/actions/runs?head_sha=$sha" 2>/dev/null || printf '{"workflow_runs":[]}')"

  jq -c -n \
    --argjson sts "$sts_json" \
    --argjson acts "$acts_json" '
    def to_int($t): if $t == null then null else ($t | fromdateiso8601) end;
    def elapsed_seconds($s; $e):
      if $s == null or $e == null then null
      else (to_int($e) - to_int($s))
      end;
    ($sts | group_by(.context) | map(
      ([.[] | select(.status != "pending")] | sort_by(.created_at) | last) as $end
      | (if $end != null
         then [.[] | select(.status == "pending" and .created_at <= $end.created_at)]
              | sort_by(.created_at) | last
         else null end) as $start
      | {
          name:      .[0].context,
          state:     (if $end != null then $end.status
                      else (sort_by(.created_at) | last | .status) end),
          source:    "status",
          elapsed_s: (if $end != null and $start != null
                      then to_int($end.created_at) - to_int($start.created_at)
                      else null end),
          url:       (if $end != null then $end.target_url
                      else (sort_by(.created_at) | last | .target_url) end)
        }
    ))
    +
    (($acts.workflow_runs // []) | map({
      name:      .name,
      state:     .status,
      source:    "actions",
      elapsed_s: elapsed_seconds(.started_at; .stopped_at),
      url:       .html_url
    }))
    | .[]
  '
}

if [[ "$forge" == github ]]; then
  records="$(fetch_github | jq -s '.')"
else
  records="$(fetch_gitea | jq -s '.')"
fi

if (( as_json )); then
  printf '%s\n' "$records" | jq '.'
  exit 0
fi

printf '%s\n' "$records" | jq -r '
  def fmt_elapsed:
    if . == null then "—"
    elif . == 0 then "0s"
    else
      (. / 60 | floor) as $m
      | (. - $m * 60 | floor) as $s
      | if $m == 0 then "\($s)s"
        elif $s == 0 then "\($m)m"
        else "\($m)m \($s)s" end
    end;
  (["NAME", "STATE", "SOURCE", "ELAPSED", "URL"]),
  (.[] | [.name, .state, .source, (.elapsed_s | fmt_elapsed), (.url // "")])
  | @tsv
' | column -t -s "$(printf '\t')"
