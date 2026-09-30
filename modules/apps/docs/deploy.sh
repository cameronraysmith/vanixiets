#!/usr/bin/env bash
# shellcheck shell=bash
# Docs deployment invoked via `nix run .#deploy-docs`; see usage() for the
# interface. The program owns every derived value (short SHAs, messages,
# alias sanitisation) so callers pass only the commit, the alias and, for a
# pull request preview, the payload nixbot built. Only the Cloudflare
# secrets come from the environment.
#
# Set by deploy.nix: builtin_payload (config.packages.vanixiets-docs) and
# DOCS_NODE_MODULES (vanixiets-docs-deps node_modules tree).
# Test seams: WRANGLER (wrangler JS entrypoint run under node),
# DEPLOY_DOCS_MAIN_SHA_URL (main's head as JSON `.sha`), DEPLOY_DOCS_DEBUG
# (keep the tmpdir).

set -euo pipefail

usage() {
  cat <<'EOF'
usage: deploy-docs production --rev <sha> [--deployed-by <name>]
       deploy-docs preview --rev <sha> --alias <name> [--payload <dir>] [--deployed-by <name>]
       deploy-docs --help

Deploy the nix-built vanixiets-docs payload to Cloudflare Workers.

Subcommands:
  production   Deploy the built-in payload to 100% of production traffic.
               Exits 0 without deploying, printing
               `DEPLOY-DOCS-ACTION: superseded (main is <sha>)`, when main's
               head is not --rev: the run for the newer main deploys it.
  preview      Upload a preview version aliased at b-<sanitized alias> and
               print `DEPLOY-DOCS-PREVIEW-URL: <url>`.

Flags:
  --rev <sha>          full 40-hex commit the payload was built from (required)
  --alias <name>       preview alias, sanitized to [a-zA-Z0-9-] and at most
                       40 characters (preview only, required)
  --payload <dir>      vanixiets-docs build to preview instead of the built-in
                       one; treated as untrusted (preview only)
  --deployed-by <name> deployer recorded in the version message
                       (default: nixbot)
  --help, -h           print this usage and exit 0

Environment:
  CLOUDFLARE_API_TOKEN, CLOUDFLARE_ACCOUNT_ID   required
  WRANGLER, DEPLOY_DOCS_MAIN_SHA_URL, DEPLOY_DOCS_DEBUG   optional overrides

Examples:
  nix run .#deploy-docs -- production --rev "$(git rev-parse HEAD)"
  nix run .#deploy-docs -- preview --rev "$(git rev-parse HEAD)" --alias my-branch
EOF
}

usage_error() {
  echo "error: $*" >&2
  echo "(run deploy-docs --help for usage)" >&2
  exit 2
}

mode="${1:-}"
case "$mode" in
  -h | --help)
    usage
    exit 0
    ;;
  production | preview) ;;
  "") usage_error "missing subcommand (production or preview)" ;;
  *) usage_error "unknown subcommand '$mode'" ;;
esac
shift

deployed_by=nixbot
while [[ $# -gt 0 ]]; do
  case "$1" in
    -h | --help)
      usage
      exit 0
      ;;
    --rev | --alias | --payload | --deployed-by)
      [[ $# -ge 2 ]] || usage_error "$1 requires a value"
      case "$1" in
        --rev) rev="$2" ;;
        --alias) preview_alias="$2" ;;
        --payload) payload="$2" ;;
        --deployed-by) deployed_by="$2" ;;
      esac
      shift 2
      ;;
    *) usage_error "unexpected argument '$1'" ;;
  esac
done

[[ -v rev ]] || usage_error "--rev is required"
[[ "$rev" =~ ^[0-9a-f]{40}$ ]] || usage_error "--rev must be a full 40-hex commit SHA, got '$rev'"
[[ -n "$deployed_by" ]] || usage_error "--deployed-by must not be empty"

case "$mode" in
  production)
    # Production ships the custom-domain config of the payload it deploys,
    # so only main's own build may reach it.
    [[ ! -v preview_alias ]] || usage_error "--alias is only valid for preview"
    [[ ! -v payload ]] || usage_error "--payload is only valid for preview"
    payload="$builtin_payload"
    ;;
  preview)
    [[ -n "${preview_alias:-}" ]] || usage_error "preview requires a non-empty --alias"
    safe_alias=$(printf '%s' "$preview_alias" \
      | tr '/' '-' \
      | tr -c 'a-zA-Z0-9-' '-' \
      | sed 's/--*/-/g; s/^-//; s/-$//' \
      | cut -c1-40)
    [[ -n "$safe_alias" ]] || usage_error "--alias '$preview_alias' has no [a-zA-Z0-9] characters"
    payload="${payload:-$builtin_payload}"
    ;;
esac

# Secret guards precede every filesystem and network step.
: "${CLOUDFLARE_API_TOKEN:?CLOUDFLARE_API_TOKEN is required}"
: "${CLOUDFLARE_ACCOUNT_ID:?CLOUDFLARE_ACCOUNT_ID is required}"
: "${DOCS_NODE_MODULES:?DOCS_NODE_MODULES not set; deploy.nix must expose vanixiets-docs-deps via runtimeEnv}"
[[ -d "$payload" ]] || { echo "error: payload $payload is not a directory" >&2; exit 1; }

commit_short="${rev:0:7}"
commit_tag="${rev:0:12}"

# Hermetic wrangler via bun-managed node_modules (vanixiets-docs-deps derivation).
# The `${WRANGLER:-...}` fallback lets a test harness substitute a stub
# wrangler entrypoint (run under node like the real one) without rewriting
# this script; every invocation below goes through `run_wrangler`, which runs
# from another directory, hence the absolute path.
WRANGLER="$(realpath "${WRANGLER:-$DOCS_NODE_MODULES/.bin/wrangler}")"
export WRANGLER

# The only Worker this script may touch. The payload's config is build
# output of whatever tree was built, including an untrusted pull request's,
# so its `name` is checked rather than trusted.
worker_name="infra-docs"

tmpdir=$(mktemp -d -t deploy-docs.XXXXXX)
if [[ -n "${DEPLOY_DOCS_DEBUG:-}" ]]; then
  echo "[deploy-docs] DEBUG: preserving tmpdir at $tmpdir" >&2
  trap 'echo "[deploy-docs] DEBUG: tmpdir preserved at '\''$tmpdir'\''" >&2' EXIT
else
  trap 'rm -rf "$tmpdir"' EXIT
fi

# wrangler loads `.env` and `.env.local` from its working directory into
# process.env before running any command, and such a file can redirect the
# API base URL and with it the token. It therefore runs from a directory this
# script created empty, with `--env-file` naming an empty file so no default
# env file is consulted at all.
wrangler_cwd="$tmpdir/cwd"
wrangler_env_file="$tmpdir/empty.env"
mkdir "$wrangler_cwd"
: > "$wrangler_env_file"

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
# `deploy`/`versions upload` as env files, so the subcommand leads and the
# global options follow in --opt=value form.
run_wrangler() {
  (
    cd "$wrangler_cwd"
    node "$WRANGLER" "$@" --config="$wrangler_config" --env-file="$wrangler_env_file"
  )
}

# wrangler's asset manifest stats files through symlinks, so a payload link
# to a secret on the runner would be published as an asset; devices and
# fifos have no place in a static site either. Refuse before copying, and
# copy without dereferencing.
unexpected_entry="$(find "$payload" ! -type f ! -type d -print -quit)"
if [[ -n "$unexpected_entry" ]]; then
  echo "error: payload entry is neither a regular file nor a directory: $unexpected_entry" >&2
  exit 1
fi

case "$mode" in
  preview)
    # A preview payload is an untrusted pull request's build output, and a
    # wrangler config is code: `build.command` runs as a shell command during
    # `versions upload`, and `main` would ship a Worker script holding the
    # Worker's bindings. Only the static assets are taken from the payload.
    # The config is written here from a fixed shape; the compatibility
    # settings and observability carry no code and are taken from the
    # payload so they follow packages/docs/wrangler.jsonc, but only after
    # their shape is checked.
    assets_dir="$tmpdir/assets"
    cp -RP "$payload/dist/client" "$assets_dir"
    chmod -R u+w "$assets_dir"

    mkdir "$tmpdir/config"
    wrangler_config="$tmpdir/config/wrangler.json"
    if ! jq -e --arg name "$worker_name" --arg dir "$assets_dir" '
      if (.compatibility_date | type == "string" and test("^[0-9]{4}-[0-9]{2}-[0-9]{2}$"))
        and (.compatibility_flags | type == "array" and all(type == "string" and test("^[a-z0-9_]+$")))
        and (.observability | . == null or (type == "object" and keys == ["enabled"] and (.enabled | type == "boolean")))
      then
        {
          name: $name,
          compatibility_date,
          compatibility_flags,
          assets: { directory: $dir },
          workers_dev: false,
          preview_urls: true
        } + (if .observability == null then {} else { observability } end)
      else
        error("unexpected compatibility or observability settings")
      end
    ' "$assets_dir/wrangler.json" > "$wrangler_config"; then
      echo "error: cannot derive a preview config from $payload/dist/client/wrangler.json" >&2
      exit 1
    fi
    ;;
  production)
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
    ;;
esac

case "$mode" in
  preview)
    version_message="[b-${safe_alias}] ${commit_tag} deployed by ${deployed_by}"
    preview_url="https://b-${safe_alias}-${worker_name}.sciexp.workers.dev"

    echo "Deploying preview: b-${safe_alias} (alias ${preview_alias})"
    echo "Commit: ${rev}"
    echo "Payload: ${payload}"
    echo ""

    # Capture wrangler's machine-readable NDJSON event log via
    # WRANGLER_OUTPUT_FILE_PATH (supported by wrangler >= 3.x; confirmed on
    # 4.84.1 by grepping `WRANGLER_OUTPUT_FILE_PATH` + `type: "version-upload"`
    # in packages/docs/node_modules/wrangler/wrangler-dist/cli.js). wrangler
    # 4.84.x does NOT accept `--json` on `versions upload` ("Unknown
    # argument: json"); `--json` is only supported on the `versions list` and
    # `deployments list` subcommands. The NDJSON stream is emitted to the file
    # named by WRANGLER_OUTPUT_FILE_PATH; each line is a JSON object with a
    # `type` discriminator. For `versions upload` we look for the
    # `version-upload` event, which carries `version_id`, `worker_tag`,
    # `preview_url`, and `preview_alias_url`.
    #
    # Success is only echoed once a non-empty Worker Version ID has been
    # recovered, enforcing the no-silent-success invariant.
    wrangler_upload_ndjson="$tmpdir/wrangler-versions-upload.ndjson"
    wrangler_upload_stdout="$tmpdir/wrangler-versions-upload.stdout"
    wrangler_upload_stderr="$tmpdir/wrangler-versions-upload.stderr"
    : > "$wrangler_upload_ndjson"
    : > "$wrangler_upload_stdout"
    : > "$wrangler_upload_stderr"
    export WRANGLER_OUTPUT_FILE_PATH="$wrangler_upload_ndjson"
    # Note: WRANGLER_LOG=debug was observed to deterministically terminate
    # wrangler 4.84.1 mid-fetch (process exits 0 after POST
    # /assets-upload-session request, before response; on GHA similar early
    # termination at GET /workers/services/<name>). Upload then never
    # completes. Do NOT re-enable without gating it to a retry-only code
    # path. Wrangler's internal log file at ~/.wrangler/logs/wrangler-*.log
    # is written at default level regardless and is captured on failure.

    # Tee stdout so we both display wrangler output live AND parse it as a
    # fallback version_id source when the NDJSON event stream from
    # WRANGLER_OUTPUT_FILE_PATH doesn't produce the expected
    # `type:"version-upload"` event. Retained as defense-in-depth against
    # future wrangler silent-success regressions.
    printf '>> wrangler upload command (cwd %s): node %s versions upload --name %s --preview-alias %s --tag %s --message %q --config=%s --env-file=%s\n' \
      "$wrangler_cwd" "$WRANGLER" "$worker_name" "b-${safe_alias}" "$commit_tag" "$version_message" "$wrangler_config" "$wrangler_env_file" >&2

    set +e
    run_wrangler versions upload \
        --name "$worker_name" \
        --preview-alias "b-${safe_alias}" \
        --tag "$commit_tag" \
        --message "$version_message" \
      > >(tee "$wrangler_upload_stdout") \
      2> >(tee "$wrangler_upload_stderr" >&2)
    wrangler_upload_rc=$?
    set -e

    unset WRANGLER_OUTPUT_FILE_PATH

    # Extract a non-empty Worker Version ID. Primary: NDJSON
    # `version-upload` event. Fallback: stdout line `Worker Version ID: <uuid>`.
    version_id=""
    if [[ -s "$wrangler_upload_ndjson" ]]; then
      version_id=$(
        jq -rs '
          map(select(type == "object" and (.type // "") == "version-upload"))
          | .[0].version_id // empty
        ' "$wrangler_upload_ndjson" 2>/dev/null || true
      )
    fi
    if [[ -z "$version_id" ]]; then
      version_id=$(
        grep -oE 'Worker Version ID: [a-f0-9-]+' "$wrangler_upload_stdout" 2>/dev/null \
          | awk '{print $NF}' \
          | head -1 || true
      )
    fi
    if [[ -z "$version_id" ]]; then
      # Relax errexit for the entire diagnostic dump block. grep/sed/cat/head
      # failures here (missing stdout match, empty NDJSON, nonexistent log
      # file) must not abort before every dump section fires — the script's
      # fail contract is satisfied by the explicit `exit 1` at the end of
      # this block, not by intermediate pipeline exit codes.
      set +e
      echo "" >&2
      echo "error: wrangler exited 0 but produced no Worker Version ID" >&2
      echo "  neither WRANGLER_OUTPUT_FILE_PATH NDJSON" >&2
      echo "  event log nor wrangler stdout contained a recognizable Worker Version ID" >&2
      echo "  wrangler exit code:    $wrangler_upload_rc" >&2
      echo "  raw wrangler event log: $wrangler_upload_ndjson" >&2
      echo "  raw wrangler stdout:   $wrangler_upload_stdout" >&2
      echo "  raw wrangler stderr:   $wrangler_upload_stderr" >&2
      echo "  hints:" >&2
      echo "    - confirm CLOUDFLARE_API_TOKEN and CLOUDFLARE_ACCOUNT_ID are exported by" >&2
      echo "      the caller" >&2
      echo "    - if linux-x64 regression, confirm wrangler invoked under real node and" >&2
      echo "      not bun-fake-node (see deploy.sh node invocation rationale)" >&2
      echo "    - inspect the wrangler internal log dumped below / raw NDJSON and stdout paths above for any output" >&2
      echo "" >&2
      # Locate wrangler's internal log file by glob + newest mtime across
      # platform-specific candidate locations. The log file contains full
      # HTTP request/response bodies and any internal stack traces — most
      # informative diagnostic source when NDJSON/stdout/stderr are empty.
      wrangler_log_path=""
      for candidate_dir in "$HOME/.wrangler/logs" "$HOME/.config/.wrangler/logs"; do
        if [[ -d "$candidate_dir" ]]; then
          # Filename `wrangler-YYYY-MM-DD_HH-MM-SS_mmm.log` is
          # zero-padded and lex-sortable, so `sort | tail -1` picks newest.
          newest=$(find "$candidate_dir" -maxdepth 1 -type f -name 'wrangler-*.log' 2>/dev/null | sort | tail -1 || true)
          if [[ -n "$newest" ]]; then
            wrangler_log_path="$newest"
            break
          fi
        fi
      done
      if [[ -n "$wrangler_log_path" && -f "$wrangler_log_path" ]]; then
        echo "--- begin wrangler internal log ($wrangler_log_path) ---" >&2
        cat "$wrangler_log_path" >&2 || true
        echo "--- end wrangler internal log ---" >&2
      else
        echo "wrangler internal log: no file found under \$HOME/.wrangler/logs or \$HOME/.config/.wrangler/logs" >&2
      fi
      echo "--- begin raw wrangler NDJSON ($wrangler_upload_ndjson) ---" >&2
      cat "$wrangler_upload_ndjson" >&2 || true
      echo "--- end raw wrangler NDJSON ---" >&2
      echo "--- begin raw wrangler stdout ($wrangler_upload_stdout) ---" >&2
      cat "$wrangler_upload_stdout" >&2 || true
      echo "--- end raw wrangler stdout ---" >&2
      echo "--- begin raw wrangler stderr ($wrangler_upload_stderr) ---" >&2
      cat "$wrangler_upload_stderr" >&2 || true
      echo "--- end raw wrangler stderr ---" >&2
      set -e
      exit 1
    fi

    echo ""
    echo "Version uploaded successfully"
    echo "  Worker Version ID: ${version_id}"
    echo "  Tag: ${commit_tag}"
    echo "  Full SHA: ${rev}"
    echo "  Message: ${version_message}"
    echo "  Preview URL: ${preview_url}"
    echo "DEPLOY-DOCS-PREVIEW-URL: ${preview_url}"
    ;;

  production)
    # gitea-mq lands batches by fast-forwarding main, possibly several in
    # quick succession, and each landing runs this effect under a shared
    # lock. A run whose commit is no longer main's head must not overwrite a
    # newer deploy; the run for main's head deploys the newer tree. The
    # effect sandbox has no checkout, so main's head comes from the forge.
    main_sha_url="${DEPLOY_DOCS_MAIN_SHA_URL:-https://api.github.com/repos/cameronraysmith/vanixiets/commits/main}"
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
    # The `| cat >` routes wrangler's stdout through a pipe-shaped fd:
    # `wrangler ... --json > file` was observed to intermittently produce
    # zero bytes, whereas `| cat > file` reliably produces the full output.
    deployments_list_json="$tmpdir/wrangler-deployments-list.json"

    run_wrangler deployments list --name "$worker_name" --json \
      | cat > "$deployments_list_json"

    found_count=$(jq --arg vid "$deploy_version_id" \
      '[.[] | select((.versions // []) | any((.version_id // .id) == $vid and .percentage == 100))] | length' \
      "$deployments_list_json" 2>/dev/null || echo 0)
    if [[ "$found_count" -lt 1 ]]; then
      echo "" >&2
      echo "error: version ${deploy_version_id} is not at 100% in deployments list" >&2
      echo "  raw deployments list output: $deployments_list_json" >&2
      echo "  hint: wrangler reported a deploy locally but the Cloudflare API did" >&2
      echo "        not persist it; inspect the raw deployments list for surrounding entries" >&2
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
    ;;
esac
