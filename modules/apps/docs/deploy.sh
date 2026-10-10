#!/usr/bin/env bash
# shellcheck shell=bash
# Docs deployment invoked via `nix run .#deploy-docs` and the `docs` effect;
# see usage() for the interface. The program owns every derived value (short
# SHAs, messages, Preview name sanitisation) so callers pass only the commit,
# the Preview name and, for a manual preview, a payload. Secrets come only
# from the environment.
#
# Set by deploy.nix: builtin_payload (config.packages.vanixiets-docs),
# DOCS_NODE_MODULES (vanixiets-docs-deps node_modules tree),
# DEPLOY_DOCS_CHECK_RUN (the github-check-run program) and
# DEPLOY_DOCS_PULL_REQUEST (the github-pull-request program).
# Test seams: WRANGLER (wrangler JS entrypoint run under node),
# DEPLOY_DOCS_MAIN_SHA_URL (main's head as JSON `.sha`), GITHUB_API_URL
# (GitHub API base, read by github-check-run and github-pull-request),
# DEPLOY_DOCS_DEBUG (keep the tmpdir). nix-store honours NIX_REMOTE, so a
# rehearsal realises payloads against a chroot store.

set -euo pipefail

usage() {
  cat <<'EOF'
usage: deploy-docs production --rev <sha> [--deployed-by <name>]
       deploy-docs preview --rev <sha> --name <name> [--payload <dir>] [--deployed-by <name>]
       deploy-docs pull-request
       deploy-docs pull-request-closed
       deploy-docs versions [--limit <n>]
       deploy-docs deployments [--limit <n>]
       deploy-docs tail
       deploy-docs --help

Deploy the nix-built vanixiets-docs payload to the infra-docs Cloudflare Worker.

Subcommands:
  production           Deploy the built-in payload to 100% of production
                       traffic. Exits 0 without deploying, printing
                       `DEPLOY-DOCS-ACTION: superseded (main is <sha>)`, when
                       main's head is not --rev: the run for the newer main
                       deploys it.
  preview              Deploy a Cloudflare Preview named after --name and
                       print `DEPLOY-DOCS-PREVIEW-URL: <url>`.
  pull-request         nixbot pull_request event: preview the docs nixbot
                       built for the pull request as Preview pr-<number>,
                       reported as the `docs-preview` check run on its head.
                       Prints `DEPLOY-DOCS-PREVIEW: skipped (<state>)` and
                       deploys nothing unless the pull request is open at
                       that head, and deletes the Preview again, printing
                       `DEPLOY-DOCS-PREVIEW: withdrawn (closed during
                       upload)`, when it closed during the upload.
  pull-request-closed  nixbot pull_request_closed event: delete Preview
                       pr-<number>, printing
                       `DEPLOY-DOCS-PREVIEW: deleted (pr-<number>)`, or
                       `DEPLOY-DOCS-PREVIEW: absent (pr-<number>)` when none
                       exists.
  versions             List the newest Worker versions.
  deployments          List the newest Worker deployments.
  tail                 Stream the Worker's live logs.

Flags:
  --rev <sha>          full 40-hex commit the payload was built from
                       (production and preview, required)
  --name <name>        Preview name, sanitized to lowercase [a-z0-9-] and at
                       most 40 characters (preview only, required)
  --payload <dir>      vanixiets-docs build to preview instead of the built-in
                       one; treated as untrusted (preview only)
  --deployed-by <name> deployer recorded in the deployment message
                       (default: nixbot)
  --limit <n>          rows to list, newest first (default: 10)
  --help, -h           print this usage and exit 0

Environment:
  CLOUDFLARE_API_TOKEN, CLOUDFLARE_ACCOUNT_ID   required
  NIXBOT_EVENT_KIND, NIXBOT_EVENT_JSON, NIXBOT_PR_NUMBER, NIXBOT_PR_HEAD,
  NIXBOT_API_URL, GITHUB_FORGE_TOKEN   set by nixbot for the event modes
  WRANGLER, DEPLOY_DOCS_MAIN_SHA_URL, GITHUB_API_URL, DEPLOY_DOCS_DEBUG
                                                optional overrides

Examples:
  nix run .#deploy-docs -- production --rev "$(git rev-parse HEAD)"
  nix run .#deploy-docs -- preview --rev "$(git rev-parse HEAD)" --name my-branch
  nix run .#deploy-docs -- versions --limit 5
EOF
}

usage_error() {
  echo "error: $*" >&2
  echo "(run deploy-docs --help for usage)" >&2
  exit 2
}

# `error` becomes the failure summary of the pull-request check run.
error=""
die() {
  error="$*"
  echo "error: $*" >&2
  exit 1
}

mode="${1:-}"
case "$mode" in
  -h | --help)
    usage
    exit 0
    ;;
  production | preview | pull-request | pull-request-closed | versions | deployments | tail) ;;
  "") usage_error "missing subcommand" ;;
  *) usage_error "unknown subcommand '$mode'" ;;
esac
shift

deployed_by=nixbot
limit=10
while [[ $# -gt 0 ]]; do
  case "$1" in
    -h | --help)
      usage
      exit 0
      ;;
    --rev | --name | --payload | --deployed-by | --limit)
      [[ $# -ge 2 ]] || usage_error "$1 requires a value"
      case "$mode:$1" in
        production:--rev | preview:--rev) rev="$2" ;;
        preview:--name) preview_name="$2" ;;
        preview:--payload) payload="$2" ;;
        production:--deployed-by | preview:--deployed-by) deployed_by="$2" ;;
        versions:--limit | deployments:--limit) limit="$2" ;;
        *) usage_error "$1 is not valid for $mode" ;;
      esac
      shift 2
      ;;
    *) usage_error "unexpected argument '$1'" ;;
  esac
done

sanitize_preview_name() {
  printf '%s' "$1" \
    | tr '[:upper:]' '[:lower:]' \
    | tr -c 'a-z0-9-' '-' \
    | sed 's/--*/-/g; s/^-//' \
    | cut -c1-40 \
    | sed 's/-$//'
}

case "$mode" in
  production | preview)
    [[ -v rev ]] || usage_error "--rev is required"
    [[ "$rev" =~ ^[0-9a-f]{40}$ ]] || usage_error "--rev must be a full 40-hex commit SHA, got '$rev'"
    [[ -n "$deployed_by" ]] || usage_error "--deployed-by must not be empty"
    ;;
  versions | deployments)
    [[ "$limit" =~ ^[1-9][0-9]*$ ]] || usage_error "--limit must be a positive integer, got '$limit'"
    ;;
esac
if [[ "$mode" == preview ]]; then
  [[ -n "${preview_name:-}" ]] || usage_error "preview requires a non-empty --name"
  safe_name="$(sanitize_preview_name "$preview_name")"
  [[ -n "$safe_name" ]] || usage_error "--name '$preview_name' has no [a-z0-9] characters"
  payload="${payload:-$builtin_payload}"
fi

# Secret guards precede every filesystem and network step.
: "${CLOUDFLARE_API_TOKEN:?CLOUDFLARE_API_TOKEN is required}"
: "${CLOUDFLARE_ACCOUNT_ID:?CLOUDFLARE_ACCOUNT_ID is required}"
: "${DOCS_NODE_MODULES:?DOCS_NODE_MODULES not set; deploy.nix must expose vanixiets-docs-deps via runtimeEnv}"
: "${DEPLOY_DOCS_CHECK_RUN:?DEPLOY_DOCS_CHECK_RUN not set; deploy.nix must expose github-check-run via runtimeEnv}"
: "${DEPLOY_DOCS_PULL_REQUEST:?DEPLOY_DOCS_PULL_REQUEST not set; deploy.nix must expose github-pull-request via runtimeEnv}"

# The only Worker this script may touch. Payload configs are build output of
# whatever tree was built, including an untrusted pull request's, so their
# `name` is checked or replaced rather than trusted.
readonly worker_name="infra-docs"
readonly repo=cameronraysmith/vanixiets

# Hermetic wrangler via bun-managed node_modules (vanixiets-docs-deps derivation).
# The `${WRANGLER:-...}` fallback lets a test harness substitute a stub
# wrangler entrypoint (run under node like the real one) without rewriting
# this script; every invocation below goes through `run_wrangler`, which runs
# from another directory, hence the absolute path.
WRANGLER="$(realpath "${WRANGLER:-$DOCS_NODE_MODULES/.bin/wrangler}")"
export WRANGLER

# Reporting is best effort, so neither a failed check-run PATCH nor this
# trap's own commands may change the exit status the run produced.
check_run_id=""
on_exit() {
  local rc=$?
  trap - EXIT
  if [[ -n "$check_run_id" ]]; then
    report_check_run "$rc" || echo "warning: could not complete check run $check_run_id" >&2
  fi
  if [[ -n "${DEPLOY_DOCS_DEBUG:-}" ]]; then
    echo "[deploy-docs] DEBUG: tmpdir preserved at '$tmpdir'" >&2
  else
    rm -rf "$tmpdir"
  fi
  exit "$rc"
}

tmpdir=$(mktemp -d -t deploy-docs.XXXXXX)
[[ -z "${DEPLOY_DOCS_DEBUG:-}" ]] || echo "[deploy-docs] DEBUG: preserving tmpdir at $tmpdir" >&2
trap on_exit EXIT

# wrangler loads `.env` and `.env.local` from its working directory into
# process.env before running any command, and such a file can redirect the
# API base URL and with it the token. It therefore runs from a directory this
# script created empty, with `--env-file` naming an empty file so no default
# env file is consulted at all.
wrangler_cwd="$tmpdir/cwd"
wrangler_env_file="$tmpdir/empty.env"
mkdir "$wrangler_cwd"
: > "$wrangler_env_file"

# Commands that read no payload run against this config: it names the Worker
# and carries the `previews` block `wrangler preview` requires, and nothing a
# command could execute.
minimal_config="$tmpdir/minimal/wrangler.json"
mkdir "$tmpdir/minimal"
jq -n --arg name "$worker_name" '{name: $name, previews: {}}' > "$minimal_config"

# Invoke wrangler via real node, not the .bin/wrangler shebang:
# bun's .bin wrappers point at bun-with-fake-node/bin/node (bun in node-
# compat mode), but bun's fetch() on linux-x64 silently hangs on keep-
# alive connection reuse to api.cloudflare.com — wrangler `versions
# upload` / `deploy` exit 0 with no Worker Version ID produced
# and no error. Prefixing `node` forces real-node (undici) runtime.
# Matches pkgs/by-name/vanixiets-docs/package.nix:141 (astro) and :248
# (playwright) precedent for tools with known bun incompatibilities.
# Empirical: diagnosed 2026-04-22 via magnetite linux-x64 reproducer;
# same machine + wrangler runs fine under real node, hangs under bun.
#
# --env-file is an array option: before the subcommand it swallows
# `deploy`/`preview` as env files, so the subcommand leads and the global
# options follow in --opt=value form.
run_wrangler() {
  (
    cd "$wrangler_cwd" &&
      node "$WRANGLER" "$@" --config="$wrangler_config" --env-file="$wrangler_env_file"
  )
}

# wrangler's asset manifest stats files through symlinks, so a payload link
# to a secret on the runner would be published as an asset; devices and
# fifos have no place in a static site either. Refuse before copying, and
# copy without dereferencing.
check_payload() {
  local payload=$1 unexpected_entry
  [[ -d "$payload" ]] || die "payload $payload is not a directory"
  unexpected_entry="$(find "$payload" ! -type f ! -type d -print -quit)"
  [[ -z "$unexpected_entry" ]] ||
    die "payload entry is neither a regular file nor a directory: $unexpected_entry"
}

# A preview payload may be an untrusted pull request's build output, and a
# wrangler config is code: `build.command` runs as a shell command, and
# `main` would ship a Worker script holding the Worker's bindings. Only the
# static assets are taken from the payload. The config is written here from
# a fixed shape; the compatibility settings carry no code and are taken from
# the payload so they follow packages/docs/wrangler.jsonc, but only after
# their shape is checked. `--ignore-base-config` keeps the dashboard's
# Preview base config from merging bindings into the Preview.
# Sets preview_url.
deploy_preview() {
  local name=$1 payload=$2 assets_dir message ndjson
  check_payload "$payload"

  assets_dir="$tmpdir/assets"
  cp -RP "$payload/dist/client" "$assets_dir" ||
    die "cannot copy the assets of $payload/dist/client"
  chmod -R u+w "$assets_dir"

  mkdir "$tmpdir/config"
  wrangler_config="$tmpdir/config/wrangler.json"
  jq -e --arg name "$worker_name" --arg dir "$assets_dir" '
    if (.compatibility_date | type == "string" and test("^[0-9]{4}-[0-9]{2}-[0-9]{2}$"))
      and (.compatibility_flags | type == "array" and all(type == "string" and test("^[a-z0-9_]+$")))
    then
      {
        name: $name,
        compatibility_date,
        compatibility_flags,
        assets: { directory: $dir },
        workers_dev: false,
        preview_urls: true,
        previews: {}
      }
    else
      error("unexpected compatibility settings")
    end
  ' "$assets_dir/wrangler.json" > "$wrangler_config" ||
    die "cannot derive a preview config from $payload/dist/client/wrangler.json"

  message="[${name}] ${rev:0:12} deployed by ${deployed_by}"
  echo "Deploying Preview: ${name}"
  echo "Commit: ${rev}"
  echo "Payload: ${payload}"
  echo ""

  # `wrangler preview` reports the Preview it deployed as the NDJSON record
  # `type == "preview"` in the file named by WRANGLER_OUTPUT_FILE_PATH.
  ndjson="$tmpdir/wrangler-preview.ndjson"
  : > "$ndjson"
  WRANGLER_OUTPUT_FILE_PATH="$ndjson" run_wrangler preview \
    --name "$name" \
    --worker-name "$worker_name" \
    --tag "${rev:0:12}" \
    --message "$message" \
    --ignore-base-config ||
    die "wrangler preview failed for $payload"

  preview_url="$(jq -rs '
    first(.[] | select(type == "object" and .type == "preview")) | .preview_urls[0]? // empty
  ' "$ndjson")" ||
    die "wrangler preview event log $ndjson is not NDJSON"
  [[ "$preview_url" =~ ^https://[^[:space:]]+$ ]] ||
    die "wrangler preview reported no Preview URL in $ndjson"
  echo "DEPLOY-DOCS-PREVIEW-URL: ${preview_url}"
}

deploy_production() {
  # Production ships the custom-domain config of the payload it deploys,
  # so only main's own build may reach it.
  local payload="$builtin_payload"
  check_payload "$payload"
  local commit_short="${rev:0:7}"
  local commit_tag="${rev:0:12}"

  # Production deploys main's own build, whose config carries the routes
  # and custom domain. @astrojs/cloudflare 14's assets-only static build
  # generates the resolved config at dist/client/wrangler.json; the
  # payload's .wrangler/deploy/config.json points at it, and wrangler may
  # write state beside it, hence the writable copy.
  mkdir "$tmpdir/payload"
  cp -RP "$payload"/. "$tmpdir/payload/"
  chmod -R u+w "$tmpdir/payload"
  wrangler_config="$tmpdir/payload/dist/client/wrangler.json"

  config_worker_name="$(jq -r '.name // empty' "$wrangler_config" 2>/dev/null || true)"
  if [[ "$config_worker_name" != "$worker_name" ]]; then
    echo "error: payload wrangler config names Worker '${config_worker_name}', expected '${worker_name}'" >&2
    echo "  config: $wrangler_config" >&2
    exit 1
  fi

  # gitea-mq lands batches by fast-forwarding main, possibly several in
  # quick succession, and each landing runs this effect under a shared
  # lock. A run whose commit is no longer main's head must not overwrite a
  # newer deploy; the run for main's head deploys the newer tree. The
  # effect sandbox has no checkout, so main's head comes from the forge.
  main_sha_url="${DEPLOY_DOCS_MAIN_SHA_URL:-https://api.github.com/repos/$repo/commits/main}"
  if ! main_sha="$(curl -fsS -H 'Accept: application/vnd.github+json' "$main_sha_url" | jq -re .sha)"; then
    echo "error: could not resolve main's head commit from ${main_sha_url}" >&2
    exit 1
  fi
  if [[ "$main_sha" != "$rev" ]]; then
    echo "DEPLOY-DOCS-ACTION: superseded (main is ${main_sha})"
    exit 0
  fi

  deploy_msg="Deployed by ${deployed_by} from main at ${commit_short}"
  echo "Deploying to production: ${rev}"
  echo "Deployment message: ${deploy_msg}"
  echo ""

  # `wrangler deploy` emits a `type == "deploy"` NDJSON event carrying
  # `version_id`. It does NOT accept `--json` on wrangler 4.84.x;
  # WRANGLER_OUTPUT_FILE_PATH is the authoritative machine-readable
  # channel, with the stdout version line as fallback.
  deploy_ndjson="$tmpdir/wrangler-deploy.ndjson"
  deploy_stdout="$tmpdir/wrangler-deploy.stdout"
  : > "$deploy_ndjson"
  : > "$deploy_stdout"
  export WRANGLER_OUTPUT_FILE_PATH="$deploy_ndjson"

  run_wrangler deploy \
      --name "$worker_name" \
      --message "$deploy_msg" \
    | tee "$deploy_stdout"

  unset WRANGLER_OUTPUT_FILE_PATH

  deploy_version_id=""
  if [[ -s "$deploy_ndjson" ]]; then
    deploy_version_id=$(
      jq -rs '
        map(select(type == "object" and (.type // "") == "deploy"))
        | .[0].version_id // empty
      ' "$deploy_ndjson" 2>/dev/null || true
    )
  fi
  if [[ -z "$deploy_version_id" ]]; then
    deploy_version_id=$(
      grep -oiE '(Current Version ID|Worker Version ID|version_id)[[:space:]]*:[[:space:]]*[a-f0-9-]+' \
        "$deploy_stdout" 2>/dev/null \
        | awk '{print $NF}' \
        | head -1 || true
    )
  fi
  if [[ -z "$deploy_version_id" ]]; then
    echo "" >&2
    echo "error: wrangler exited 0 but produced no Worker Version ID" >&2
    echo "  neither WRANGLER_OUTPUT_FILE_PATH NDJSON event log nor wrangler" >&2
    echo "  stdout contained a recognizable version_id" >&2
    echo "  raw wrangler event log: $deploy_ndjson" >&2
    echo "  raw wrangler stdout:   $deploy_stdout" >&2
    echo "  hints:" >&2
    echo "    - confirm CLOUDFLARE_API_TOKEN and CLOUDFLARE_ACCOUNT_ID are exported by" >&2
    echo "      the caller" >&2
    echo "    - if linux-x64 regression, confirm wrangler invoked under real node and" >&2
    echo "      not bun-fake-node (see deploy.sh node invocation rationale)" >&2
    exit 1
  fi

  # Cross-check server-side that the new version carries 100% of traffic.
  # The deployments list lags the deploy that wrangler just reported, so a
  # single immediate read can miss a deployment that did persist; poll it
  # within a bounded budget. The `| cat >` routes wrangler's stdout through
  # a pipe-shaped fd: `wrangler ... --json > file` was observed to
  # intermittently produce zero bytes, whereas `| cat > file` reliably
  # produces the full output.
  deployments_list_json="$tmpdir/wrangler-deployments-list.json"
  verify_attempts="${DEPLOY_DOCS_VERIFY_ATTEMPTS:-12}"
  verify_interval="${DEPLOY_DOCS_VERIFY_INTERVAL:-5}"
  listed_percentage=""
  for ((attempt = 1; attempt <= verify_attempts; attempt++)); do
    run_wrangler deployments list --name "$worker_name" --json \
      | cat > "$deployments_list_json"
    listed_percentage=$(jq -r --arg vid "$deploy_version_id" '
      [.[] | (.versions // [])[] | select((.version_id // .id) == $vid) | .percentage]
      | max // empty
    ' "$deployments_list_json" 2>/dev/null || true)
    if [[ "$listed_percentage" == 100 ]]; then
      break
    fi
    if ((attempt < verify_attempts)); then
      sleep "$verify_interval"
    fi
  done
  if [[ "$listed_percentage" != 100 ]]; then
    echo "" >&2
    if [[ -z "$listed_percentage" ]]; then
      echo "error: version ${deploy_version_id} is not in the deployments list after ${verify_attempts} reads" >&2
    else
      echo "error: version ${deploy_version_id} is at ${listed_percentage}% in the deployments list after ${verify_attempts} reads, expected 100%" >&2
    fi
    echo "  raw deployments list output: $deployments_list_json" >&2
    exit 1
  fi

  echo ""
  echo "deployed nix-built payload to production"
  echo "  Worker Version ID: ${deploy_version_id}"
  echo "  tag: ${commit_tag}"
  echo "  full SHA: ${rev}"
  echo "  message: ${deploy_msg}"
  echo "  production URL: https://infra.cameronraysmith.net"
  echo "DEPLOY-DOCS-ACTION: deploy (version ${deploy_version_id})"
}

# A run that ends without deploying sets both; the check run then completes
# neutral with them.
neutral_title=""
neutral_summary=""
preview_url=""
report_check_run() {
  local rc=$1
  if [[ "$rc" -eq 0 && -n "$neutral_title" ]]; then
    "$DEPLOY_DOCS_CHECK_RUN" complete --repo "$repo" --id "$check_run_id" \
      --conclusion neutral --title "$neutral_title" --summary "$neutral_summary"
  elif [[ "$rc" -eq 0 ]]; then
    "$DEPLOY_DOCS_CHECK_RUN" complete --repo "$repo" --id "$check_run_id" \
      --conclusion success --title "Docs preview deployed" \
      --summary "Docs preview of ${rev:0:12} for pull request #$pr: $preview_url" \
      --details-url "$preview_url"
  else
    "$DEPLOY_DOCS_CHECK_RUN" complete --repo "$repo" --id "$check_run_id" \
      --conclusion failure --title "Docs preview failed" \
      --summary "Docs preview of ${rev:0:12} failed: ${error:-deploy-docs pull-request exited with status $rc}"
  fi
}

# nixbot may deliver a pull request's events in any order, a merge's
# pull_request_closed before the pull_request of its last push among them,
# and the event payload is a snapshot from delivery time. So the pull
# request's state is read from GitHub itself into pr_state: current, closed
# or superseded (open at another head).
pr_state=""
read_pull_request_state() {
  pr_state="$("$DEPLOY_DOCS_PULL_REQUEST" state --repo "$repo" --number "$pr" --head-sha "$rev")" ||
    die "cannot read the state of pull request #$pr"
  case "$pr_state" in
    current | closed | superseded) ;;
    *) die "unexpected state '$pr_state' of pull request #$pr" ;;
  esac
}

# Runs from the default branch whatever pull request the event is about. The
# pull request contributes data only: its number, head rev, and the docs
# payload nixbot already built for it, located through nixbot's build API and
# realised by store path. Nothing from the pull request is evaluated or run
# while the Cloudflare token is readable; the payload's bytes are untrusted,
# which deploy_preview accounts for. Event effects post no commit status, so
# the outcome is the `docs-preview` check run on the head commit.
pull_request() {
  local docs_attr=checks.x86_64-linux.package-vanixiets-docs
  local build_number is_fork writer who reason build_url build_json build_status attribute attr_status payload

  [[ "${NIXBOT_EVENT_KIND:-}" == pull_request ]] ||
    die "expected a pull_request event, got ${NIXBOT_EVENT_KIND:-none}"
  for var in NIXBOT_API_URL NIXBOT_EVENT_JSON GITHUB_FORGE_TOKEN; do
    [[ -n "${!var:-}" ]] || die "$var is not set"
  done
  pr="${NIXBOT_PR_NUMBER:-}"
  rev="${NIXBOT_PR_HEAD:-}"
  build_number="$(jq -r '.build.number // empty' "$NIXBOT_EVENT_JSON")" ||
    die "cannot read the build number from $NIXBOT_EVENT_JSON"
  if ! [[ "$pr" =~ ^[0-9]+$ && "$rev" =~ ^[0-9a-f]{40}$ && "$build_number" =~ ^[0-9]+$ ]]; then
    die "malformed event (pr=$pr head=$rev build=$build_number)"
  fi

  echo "=== docs-preview (pull request #$pr at ${rev:0:12}, build $build_number) ==="

  check_run_id="$("$DEPLOY_DOCS_CHECK_RUN" create --repo "$repo" --name docs-preview --head-sha "$rev")" || {
    check_run_id=""
    echo "warning: could not create the docs-preview check run" >&2
  }

  # Only a pull request still open at the event's head gets a Preview.
  read_pull_request_state
  if [[ "$pr_state" != current ]]; then
    neutral_title="Docs preview skipped"
    neutral_summary="pull request #$pr is $pr_state; no preview"
    echo "DEPLOY-DOCS-PREVIEW: skipped ($pr_state)"
    exit 0
  fi

  # A head branch in this repository took write access to push, which bots
  # hold without reporting it; a fork's content is previewed with our token
  # only once a writer has acted on or authored the pull request.
  is_fork="$(jq -r '.pullRequest.isFork | if type == "boolean" then . else "invalid" end' "$NIXBOT_EVENT_JSON")" ||
    die "cannot read pullRequest.isFork from $NIXBOT_EVENT_JSON"
  case "$is_fork" in
    false) ;;
    true)
      writer="$(jq -r '
        def level: {none: 0, read: 1, write: 2, admin: 3}[. // "none"] // 0;
        [.actor.permission, .pullRequest.author.permission] | map(level) | max >= 2
      ' "$NIXBOT_EVENT_JSON")" ||
        die "cannot read the actor and author permissions from $NIXBOT_EVENT_JSON"
      if [[ "$writer" != true ]]; then
        who="$(jq -r '
          [{role: "actor", s: .actor}, {role: "author", s: .pullRequest.author}]
          | map(select(.s.name) | "\(.role) \(.s.name): \(.s.permission // "none")")
          | if . == [] then "no actor or author reported" else join(", ") end
        ' "$NIXBOT_EVENT_JSON")" ||
          die "cannot read the actor and author from $NIXBOT_EVENT_JSON"
        reason="pull request #$pr comes from a fork and neither its actor nor its author has write access ($who)"
        neutral_title="Docs preview skipped"
        neutral_summary="Docs preview of ${rev:0:12} skipped: $reason. A maintainer can preview it by adding any label to the pull request."
        echo "skipped: $reason"
        exit 0
      fi
      ;;
    *) die "event has no boolean pullRequest.isFork" ;;
  esac

  # The store path nixbot built for this pull request, by build number from
  # the event: nothing from the pull request is evaluated.
  build_url="$NIXBOT_API_URL/api/repos/github/$repo/builds/$build_number"
  build_json="$(curl -fsS --retry 3 "$build_url")" ||
    die "cannot fetch nixbot build $build_number from $build_url"
  build_status="$(jq -r '.build.status // "missing"' <<<"$build_json")" ||
    die "nixbot build $build_number response is not JSON"
  [[ "$build_status" == succeeded ]] ||
    die "nixbot build $build_number is $build_status, not succeeded"
  attribute="$(jq -c --arg attr "$docs_attr" 'first(.attributes[]? | select(.attr == $attr)) // empty' <<<"$build_json")"
  [[ -n "$attribute" ]] ||
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

  deploy_preview "pr-$pr" "$payload"

  # A close delivered during the upload has already run its delete, so the
  # Preview just deployed would outlive the pull request. A newer head's run
  # replaces a superseded one under the same name.
  read_pull_request_state
  if [[ "$pr_state" == closed ]]; then
    delete_preview "pr-$pr"
    neutral_title="Docs preview withdrawn"
    neutral_summary="pull request #$pr closed during the upload; Preview pr-$pr deleted"
    echo "DEPLOY-DOCS-PREVIEW: withdrawn (closed during upload)"
  fi
}

# Every pull request's Preview is deleted on close, whether or not one was
# deployed: a fork skip or failed build leaves none, which wrangler reports
# as the Cloudflare API error 10025 in its `command-failed` NDJSON record,
# the code wrangler itself reads as "Preview not found".
pull_request_closed() {
  [[ "${NIXBOT_EVENT_KIND:-}" == pull_request_closed ]] ||
    die "expected a pull_request_closed event, got ${NIXBOT_EVENT_KIND:-none}"
  pr="${NIXBOT_PR_NUMBER:-}"
  [[ "$pr" =~ ^[0-9]+$ ]] || die "malformed event (pr=$pr)"
  delete_preview "pr-$pr"
}

delete_preview() {
  local name=$1 ndjson code
  wrangler_config="$minimal_config"
  ndjson="$tmpdir/wrangler-preview-delete.ndjson"
  : > "$ndjson"
  if WRANGLER_OUTPUT_FILE_PATH="$ndjson" run_wrangler preview delete \
    --name "$name" \
    --skip-confirmation \
    --worker-name "$worker_name"; then
    echo "DEPLOY-DOCS-PREVIEW: deleted ($name)"
    return
  fi
  code="$(jq -rs 'first(.[] | select(type == "object" and .type == "command-failed")) | .code // empty' "$ndjson")" ||
    die "wrangler preview delete event log $ndjson is not NDJSON"
  [[ "$code" == 10025 ]] || die "wrangler preview delete failed for $name"
  echo "DEPLOY-DOCS-PREVIEW: absent ($name)"
}

# wrangler lists oldest first; `--json` output is captured through a pipe for
# the reason given in deploy_production.
list_versions() {
  local json="$tmpdir/wrangler-versions-list.json"
  wrangler_config="$minimal_config"
  run_wrangler versions list --name "$worker_name" --json | cat > "$json"
  jq -r --argjson n "$limit" '
    ["VERSION", "CREATED", "TAG", "MESSAGE"],
    (reverse | .[:$n][] | [
      .id,
      .metadata.created_on,
      (.annotations["workers/tag"] // "-"),
      (.annotations["workers/message"] // "-")
    ])
    | @tsv
  ' "$json"
}

list_deployments() {
  local json="$tmpdir/wrangler-deployments-list.json"
  wrangler_config="$minimal_config"
  run_wrangler deployments list --name "$worker_name" --json | cat > "$json"
  jq -r --argjson n "$limit" '
    ["CREATED", "DEPLOYMENT", "VERSIONS", "MESSAGE"],
    (reverse | .[:$n][] | [
      .created_on,
      .id,
      ([.versions[]? | "\(.version_id) \(.percentage)%"] | join(", ")),
      (.annotations["workers/message"] // "-")
    ])
    | @tsv
  ' "$json"
}

case "$mode" in
  production) deploy_production ;;
  preview) deploy_preview "$safe_name" "$payload" ;;
  pull-request) pull_request ;;
  pull-request-closed) pull_request_closed ;;
  versions) list_versions ;;
  deployments) list_deployments ;;
  tail)
    wrangler_config="$minimal_config"
    run_wrangler tail "$worker_name"
    ;;
esac
