readonly repo=cameronraysmith/vanixiets
readonly docs_attr=checks.x86_64-linux.package-vanixiets-docs
readonly github_api="${GITHUB_API_URL:-https://api.github.com}"

check_run_id=""
error=""
preview_url=""

die() {
  error="$*"
  echo "error: $*" >&2
  exit 1
}

github() {
  local method=$1 path=$2
  curl -fsS --retry 3 -X "$method" "$github_api/repos/$repo/$path" \
    -H "Authorization: Bearer $GITHUB_FORGE_TOKEN" \
    -H 'Accept: application/vnd.github+json' \
    -H 'X-GitHub-Api-Version: 2022-11-28' \
    -H 'Content-Type: application/json' \
    --data @-
}

# Why: reporting is best effort, so neither a failed PATCH nor this trap's own
# commands may change the exit status the preview produced.
report() {
  local rc=$?
  trap - EXIT
  if [ -n "$check_run_id" ]; then
    local body
    if [ "$rc" -eq 0 ]; then
      body="$(jq -n --arg url "$preview_url" --arg rev "$head_rev" --arg pr "$pr" '{
        status: "completed",
        conclusion: "success",
        details_url: $url,
        output: {
          title: "Docs preview deployed",
          summary: "Docs preview of \($rev[0:12]) for pull request #\($pr): \($url)"
        }
      }')"
    else
      body="$(jq -n --arg error "${error:-docs-preview exited with status $rc}" --arg rev "$head_rev" '{
        status: "completed",
        conclusion: "failure",
        output: {
          title: "Docs preview failed",
          summary: "Docs preview of \($rev[0:12]) failed: \($error)"
        }
      }')"
    fi
    github PATCH "check-runs/$check_run_id" <<<"$body" >/dev/null ||
      echo "warning: could not complete check run $check_run_id" >&2
  fi
  exit "$rc"
}

if [ "${NIXBOT_EVENT_KIND:-}" != pull_request ]; then
  die "expected a pull_request event, got ${NIXBOT_EVENT_KIND:-none}"
fi
for var in NIXBOT_API_URL NIXBOT_EVENT_JSON GITHUB_FORGE_TOKEN; do
  [ -n "${!var:-}" ] || die "$var is not set"
done
pr="${NIXBOT_PR_NUMBER:-}"
head_rev="${NIXBOT_PR_HEAD:-}"
build_number="$(jq -r '.build.number // empty' "$NIXBOT_EVENT_JSON")" ||
  die "cannot read the build number from $NIXBOT_EVENT_JSON"
if ! [[ "$pr" =~ ^[0-9]+$ && "$head_rev" =~ ^[0-9a-f]{40}$ && "$build_number" =~ ^[0-9]+$ ]]; then
  die "malformed event (pr=$pr head=$head_rev build=$build_number)"
fi

trap report EXIT

echo "=== docs-preview (pull request #$pr at ${head_rev:0:12}, build $build_number) ==="

check_run_id="$(
  jq -n --arg sha "$head_rev" '{name: "docs-preview", head_sha: $sha, status: "in_progress"}' |
    github POST check-runs | jq -er '.id'
)" || {
  check_run_id=""
  echo "warning: could not create the docs-preview check run" >&2
}

# The store path nixbot built for this pull request, by build number from the
# event: nothing from the pull request is evaluated.
build_url="$NIXBOT_API_URL/api/repos/github/$repo/builds/$build_number"
build_json="$(curl -fsS --retry 3 "$build_url")" ||
  die "cannot fetch nixbot build $build_number from $build_url"
build_status="$(jq -r '.build.status // "missing"' <<<"$build_json")" ||
  die "nixbot build $build_number response is not JSON"
[ "$build_status" = succeeded ] ||
  die "nixbot build $build_number is $build_status, not succeeded"
attribute="$(jq -c --arg attr "$docs_attr" 'first(.attributes[]? | select(.attr == $attr)) // empty' <<<"$build_json")"
[ -n "$attribute" ] ||
  die "nixbot build $build_number has no attribute $docs_attr"
attr_status="$(jq -r '.status' <<<"$attribute")"
case "$attr_status" in
  succeeded | skipped_local) ;;
  *) die "nixbot build $build_number attribute $docs_attr is $attr_status" ;;
esac
payload="$(jq -r '.outputs.out // empty' <<<"$attribute")"
[[ "$payload" =~ ^/nix/store/[0-9a-z]{32}-[^/]+$ ]] ||
  die "nixbot build $build_number attribute $docs_attr has no store path output: $payload"
nix-store --realise "$payload" >/dev/null ||
  die "cannot realise $payload"

deploy_log="$(mktemp -t docs-preview.XXXXXX)"
"$deploy_docs" preview --rev "$head_rev" --alias "pr-$pr" --payload "$payload" 2>&1 | tee "$deploy_log" ||
  die "deploy-docs preview failed for $payload"
url_lines="$(grep -E '^DEPLOY-DOCS-PREVIEW-URL: https://[^[:space:]]+$' "$deploy_log" || true)"
if [ -z "$url_lines" ] || [ "$(wc -l <<<"$url_lines")" -ne 1 ]; then
  die "deploy-docs preview did not print exactly one DEPLOY-DOCS-PREVIEW-URL line"
fi
preview_url="${url_lines#DEPLOY-DOCS-PREVIEW-URL: }"
