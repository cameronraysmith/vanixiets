#!/usr/bin/env bash
# shellcheck shell=bash
# Docs deployment dispatcher invoked via `nix run .#deploy-docs`.
# See `usage()` for caller-facing usage; this header documents the
# env-var contract only.
#
# Required (secret, caller-provided from the closed 4-key effects bundle —
# modules/effects/vanixiets/secrets.nix):
#   CLOUDFLARE_API_TOKEN     wrangler auth token (CONSUMED).
#   CLOUDFLARE_ACCOUNT_ID    Cloudflare account id (CONSUMED;
#                            account-scoped ops require this).
#   GITHUB_TOKEN             not consumed here; bundle homogeneity
#                            (consumed by release.sh).
#   SOPS_AGE_KEY             not consumed here; bundle homogeneity
#                            (consumed by k3d-bootstrap-secrets.sh).
# Required (config, injected by deploy.nix):
#   DOCS_PAYLOAD             vanixiets-docs derivation outPath
#                            ($out/{dist/, .wrangler/, wrangler.jsonc}).
#   DOCS_NODE_MODULES        vanixiets-docs-deps node_modules tree.
# Optional (env-first with git-fallback): every GIT_* consumer is
# `${GIT_X:-$(git … 2>/dev/null || true)}` so the script runs both
# inside the buildbot-effects bwrap sandbox (no .git bind-mounted; env
# pre-populated by the effect preamble) and from a live worktree (env
# unset; git fallback resolves locally):
#   GIT_REV, GIT_REV_SHORT, GIT_REV_SHORT12, GIT_BRANCH,
#   GIT_COMMIT_MSG, GIT_WORKTREE_STATUS.
# Optional (env-first with bash-builtin / shelled-fallback): the bwrap
# sandbox lacks `hostname`/`whoami` on PATH, so DEPLOY_HOST falls back to
# `${HOSTNAME%%.*}` (bash builtin populated from gethostname(2)) and
# DEPLOY_DEPLOYER falls back to GITHUB_ACTOR → `whoami 2>/dev/null`
# → "unknown".
# Optional (caller debugging / overrides):
#   WRANGLER, DEPLOY_DOCS_DEBUG, GITHUB_ACTIONS / GITHUB_ACTOR /
#   GITHUB_WORKFLOW (when GITHUB_ACTIONS is set, the production deploy
#   message uses GITHUB_WORKFLOW (default "CI") as deploy context
#   instead of DEPLOY_HOST).

set -euo pipefail

usage() {
  cat <<'EOF'
usage: deploy-docs preview <branch>
       deploy-docs production
       deploy-docs --help

Deploy the nix-built vanixiets-docs payload to Cloudflare Workers.

Subcommands:
  preview <branch>   Upload a Cloudflare Workers preview version tagged with
                     the current HEAD short SHA, aliased at b-<sanitized-branch>.
                     <branch> defaults to `git branch --show-current`; explicit
                     value required when HEAD is detached.
  production         Promote the existing preview version matching the current
                     HEAD short SHA to 100% production traffic, or fall back
                     to a direct deploy of the nix-built payload when no
                     matching preview exists.

Flags:
  --help, -h         Print this usage and exit 0.

Environment contract (see top-of-file header for full details):
  Required (secret, caller-provided from the closed 4-key effects bundle):
    CLOUDFLARE_API_TOKEN   wrangler auth token (CONSUMED)
    CLOUDFLARE_ACCOUNT_ID  Cloudflare account id (CONSUMED; account-scoped ops)
    GITHUB_TOKEN           bundle homogeneity (not consumed by deploy.sh)
    SOPS_AGE_KEY           bundle homogeneity (not consumed by deploy.sh)
  Required (config, injected by deploy.nix):
    DOCS_PAYLOAD           path to the vanixiets-docs derivation output
    DOCS_NODE_MODULES      path to vanixiets-docs-deps node_modules tree
  Optional (env-first with shelled-fallback):
    GIT_REV, GIT_REV_SHORT, GIT_REV_SHORT12, GIT_BRANCH,
    GIT_COMMIT_MSG, GIT_WORKTREE_STATUS
                     git metadata; supplied by effect preamble when no
                     .git is reachable; otherwise resolved via `git ...`.
    DEPLOY_HOST      short hostname; fallback `${HOSTNAME%%.*}` (bash
                     builtin, no external binary).
    DEPLOY_DEPLOYER  actor identity; fallback chain GITHUB_ACTOR →
                     `whoami 2>/dev/null` → "unknown".
  Optional (caller debugging / overrides):
    WRANGLER, DEPLOY_DOCS_DEBUG
    GITHUB_ACTIONS / GITHUB_ACTOR / GITHUB_WORKFLOW
                     When GITHUB_ACTIONS is set, the production deploy
                     message uses the GitHub Actions context (workflow
                     name) instead of DEPLOY_HOST.

Examples:
  nix run .#deploy-docs -- preview my-feature-branch
  nix run .#deploy-docs -- production
EOF
}

mode="${1:-}"
case "$mode" in
  -h | --help)
    usage
    exit 0
    ;;
esac

if [[ -z "$mode" ]]; then
  echo "error: missing subcommand" >&2
  echo "usage: deploy-docs preview <branch> | deploy-docs production" >&2
  echo "(run with --help for full usage and env-var contract)" >&2
  exit 2
fi
shift

# Env-var contract guards: fail fast before any wrangler / filesystem work.
: "${DOCS_PAYLOAD:?DOCS_PAYLOAD not set; deploy.nix must pass the nix-built payload}"
[[ -d "$DOCS_PAYLOAD" ]] || { echo "error: DOCS_PAYLOAD=$DOCS_PAYLOAD is not a directory" >&2; exit 1; }
: "${DOCS_NODE_MODULES:?DOCS_NODE_MODULES not set; deploy.nix must expose vanixiets-docs-deps via runtimeEnv}"
: "${CLOUDFLARE_API_TOKEN:?CLOUDFLARE_API_TOKEN is required (see deploy.sh header for caller mechanisms: effect preamble, direnv, caller-side sops wrapper, or GHA env)}"
: "${CLOUDFLARE_ACCOUNT_ID:?CLOUDFLARE_ACCOUNT_ID is required (see deploy.sh header for caller mechanisms: effect preamble, direnv, caller-side sops wrapper, or GHA env)}"

# Hermetic wrangler via bun-managed node_modules (vanixiets-docs-deps derivation).
# The `${WRANGLER:-...}` fallback allows test harnesses (e.g. the no-op wrangler stub
# used to exercise the post-condition error paths) to override the hermetic
# binary without rewriting this script.
export WRANGLER="${WRANGLER:-$DOCS_NODE_MODULES/.bin/wrangler}"

# Invoke wrangler via real node, not the .bin/wrangler shebang:
# bun's .bin wrappers point at bun-with-fake-node/bin/node (bun in node-
# compat mode), but bun's fetch() on linux-x64 silently hangs on keep-
# alive connection reuse to api.cloudflare.com — wrangler `versions
# upload` / `versions deploy` exit 0 with no Worker Version ID produced
# and no error. Prefixing `node` forces real-node (undici) runtime.
# Matches pkgs/by-name/vanixiets-docs/package.nix:141 (astro) and :248
# (playwright) precedent for tools with known bun incompatibilities.
# Empirical: diagnosed 2026-04-22 via magnetite linux-x64 reproducer;
# same machine + wrangler runs fine under real node, hangs under bun.

# Wrangler is invoked with absolute `--config "$WRANGLER_CONFIG"`, so no
# `cd` into the worktree is required (and would fail inside the bwrap
# sandbox, which does not bind-mount the working tree).

# Materialise a writable copy of the nix payload: wrangler reads
# .wrangler/deploy/config.json (configPath resolves against the config
# file's location) and may write state to .wrangler/ during deploy.
tmpdir=$(mktemp -d -t deploy-docs.XXXXXX)
if [[ -n "${DEPLOY_DOCS_DEBUG:-}" ]]; then
  echo "[deploy-docs] DEBUG: preserving tmpdir at $tmpdir" >&2
  trap 'echo "[deploy-docs] DEBUG: tmpdir preserved at '\''$tmpdir'\''" >&2' EXIT
else
  trap 'rm -rf "$tmpdir"' EXIT
fi
cp -R "$DOCS_PAYLOAD"/. "$tmpdir/"
chmod -R u+w "$tmpdir"

# Astro generates dist/server/wrangler.json with real resolved relative paths
# (main: "entry.mjs", assets.directory: "../client") during build.
# .wrangler/deploy/config.json in the payload explicitly references this as the
# deploy-time config. Use it directly — no jq rewrite needed, and no dependency
# on node_modules to resolve the @astrojs/cloudflare/entrypoints/server specifier
# present in the source wrangler.jsonc.
wrangler_config="$tmpdir/dist/server/wrangler.json"

# Commit metadata: env-first with errexit-tolerant git fallback so a
# missing .git (bwrap sandbox) surfaces as empty strings rather than
# aborting; the env-first path supplies authoritative values in that case.
commit_sha="${GIT_REV:-$(git rev-parse HEAD 2>/dev/null || true)}"
commit_tag="${GIT_REV_SHORT12:-$(git rev-parse --short=12 HEAD 2>/dev/null || true)}"
commit_short="${GIT_REV_SHORT:-$(git rev-parse --short HEAD 2>/dev/null || true)}"
current_branch="${GIT_BRANCH:-$(git branch --show-current 2>/dev/null || true)}"

# Resolve deployer / deploy_host with env-first / bash-builtin /
# shelled-fallback. Bash builtin `$HOSTNAME` is populated from
# gethostname(2) at shell startup, so `${HOSTNAME%%.*}` mimics
# `hostname -s` without shelling out — required because the bwrap
# sandbox lacks `hostname` on PATH.
deploy_host="${DEPLOY_HOST:-${HOSTNAME%%.*}}"
deployer="${DEPLOY_DEPLOYER:-${GITHUB_ACTOR:-$(whoami 2>/dev/null || echo unknown)}}"

if [[ -n "${GITHUB_ACTIONS:-}" ]]; then
  deploy_context="${GITHUB_WORKFLOW:-CI}"
  deploy_msg="Deployed by ${deployer} from ${current_branch} via ${deploy_context}"
else
  deploy_msg="Deployed by ${deployer} from ${current_branch} on ${deploy_host}"
fi

case "$mode" in
  preview)
    branch="${1:-${current_branch:-}}"
    if [[ -z "$branch" ]]; then
      echo "error: preview requires a <branch> argument" >&2
      echo "usage: deploy-docs preview <branch>" >&2
      exit 2
    fi

    safe_branch=$(echo "$branch" \
      | tr '/' '-' \
      | tr -c 'a-zA-Z0-9-' '-' \
      | sed 's/--*/-/g; s/^-//; s/-$//' \
      | cut -c1-40)

    # Env-first / errexit-tolerant git fallback so a missing .git leaves
    # commit_msg empty; the effect preamble supplies authoritative values.
    commit_msg="${GIT_COMMIT_MSG:-$(git log -1 --pretty=format:'%s' 2>/dev/null || true)}"
    if [[ -n "${GIT_WORKTREE_STATUS:-}" ]]; then
      git_status="$GIT_WORKTREE_STATUS"
    elif git diff-index --quiet HEAD -- 2>/dev/null; then
      git_status="clean"
    else
      # Non-zero from `git diff-index` covers both "dirty worktree" and
      # "not a git repository" — collapse both to "dirty" so downstream
      # version_message is always well-formed.
      git_status="dirty"
    fi
    version_message="[${branch}] ${commit_msg} (${commit_tag}, ${git_status})"

    echo "Deploying preview for branch: ${branch}"
    echo "Sanitized alias: b-${safe_branch}"
    echo "Commit: ${commit_short} (${git_status})"
    echo "Full SHA: ${commit_sha}"
    echo "Tag: ${commit_tag}"
    echo "Message: ${commit_msg}"
    echo ""

    export VERSION_TAG="$commit_tag"
    export VERSION_MESSAGE="$version_message"
    export SAFE_BRANCH="$safe_branch"
    export WRANGLER_CONFIG="$wrangler_config"

    # Capture wrangler's machine-readable NDJSON event log via
    # WRANGLER_OUTPUT_FILE_PATH (supported by wrangler >= 3.x; confirmed on
    # 4.84.1 by grepping `WRANGLER_OUTPUT_FILE_PATH` + `type: "version-upload"`
    # in packages/docs/node_modules/wrangler/wrangler-dist/cli.js). The
    # previous revision of this script used `--json` on `wrangler versions
    # upload`, but wrangler 4.84.x does NOT accept `--json` on that subcommand
    # (GHA re-run against cd-via-effects @ 6ce9fca2 exited 1 with "Unknown
    # argument: json"); `--json` is only supported on the `versions list` and
    # `deployments list` subcommands. The NDJSON stream is emitted to the file
    # named by WRANGLER_OUTPUT_FILE_PATH; each line is a JSON object with a
    # `type` discriminator. For `versions upload` we look for the
    # `version-upload` event, which carries `version_id`, `worker_tag`,
    # `preview_url`, and `preview_alias_url`.
    #
    # Three post-conditions enforce the no-silent-success invariant:
    #   (a) the NDJSON event log contains a `type == "version-upload"` entry
    #       with a non-empty `version_id` (primary authoritative source)
    #   (b) `wrangler versions list --json` contains an entry whose
    #       annotations["workers/tag"] matches $commit_tag (server-side
    #       persistence cross-check)
    #   (c) only then is the user-visible success block echoed, including the
    #       authoritative Worker Version ID parsed from (a).
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
    printf '>> wrangler upload command: node %s --config %s versions upload --preview-alias %s --tag %s --message %q\n' \
      "$WRANGLER" "$WRANGLER_CONFIG" "b-${SAFE_BRANCH}" "$VERSION_TAG" "$VERSION_MESSAGE" >&2

    set +e
    node "$WRANGLER" --config "$WRANGLER_CONFIG" versions upload \
        --preview-alias "b-${SAFE_BRANCH}" \
        --tag "$VERSION_TAG" \
        --message "$VERSION_MESSAGE" \
      > >(tee "$wrangler_upload_stdout") \
      2> >(tee "$wrangler_upload_stderr" >&2)
    wrangler_upload_rc=$?
    set -e

    unset WRANGLER_OUTPUT_FILE_PATH

    # Post-condition (a): extract a non-empty Worker Version ID.
    # Primary: NDJSON `version-upload` event. Fallback: stdout line
    # `Worker Version ID: <uuid>`. (b) cross-checks server-side persistence.
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
      echo "  post-condition (a) failed: neither WRANGLER_OUTPUT_FILE_PATH NDJSON" >&2
      echo "                              event log nor wrangler stdout contained" >&2
      echo "                              a recognizable Worker Version ID" >&2
      echo "  wrangler exit code:    $wrangler_upload_rc" >&2
      echo "  raw wrangler event log: $wrangler_upload_ndjson" >&2
      echo "  raw wrangler stdout:   $wrangler_upload_stdout" >&2
      echo "  raw wrangler stderr:   $wrangler_upload_stderr" >&2
      echo "  hints:" >&2
      echo "    - confirm CLOUDFLARE_API_TOKEN and CLOUDFLARE_ACCOUNT_ID are exported by" >&2
      echo "      the caller (see deploy.sh env-var contract header for caller mechanisms)" >&2
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

    # Post-condition (b): cross-check via versions list that the upload landed
    # server-side with the expected commit tag annotation. The `| cat` pipe
    # ensures wrangler's stdout is delivered through a pipe-shaped fd before
    # being redirected to disk (observed empirically: `wrangler ... --json >
    # file` intermittently produces zero bytes whereas `wrangler ... --json |
    # cat > file` reliably produces the full JSON output, which suggests
    # wrangler inspects stdout before emitting when the fd points directly at
    # a file).
    wrangler_list_json="$tmpdir/wrangler-versions-list.json"

    node "$WRANGLER" --config "$WRANGLER_CONFIG" versions list --json \
      | cat > "$wrangler_list_json"

    matched_count=$(jq --arg tag "$commit_tag" \
      '[.[] | select(.annotations["workers/tag"] == $tag)] | length' \
      "$wrangler_list_json" 2>/dev/null || echo 0)
    if [[ "$matched_count" -lt 1 ]]; then
      echo "" >&2
      echo "error: uploaded version with tag ${commit_tag} not found in versions list" >&2
      echo "  post-condition (b) failed: wrangler versions list returned no entries" >&2
      echo "                              with annotations[\"workers/tag\"] == ${commit_tag}" >&2
      echo "  raw versions list output: $wrangler_list_json" >&2
      echo "  hint: wrangler reported a version_id locally but the Cloudflare API did" >&2
      echo "        not persist it; inspect the raw versions list for surrounding entries" >&2
      exit 1
    fi

    echo ""
    echo "Version uploaded successfully"
    echo "  Worker Version ID: ${version_id}"
    echo "  Tag: ${commit_tag}"
    echo "  Full SHA: ${commit_sha}"
    echo "  Message: ${version_message}"
    echo "  Preview URL: https://b-${safe_branch}-infra-docs.sciexp.workers.dev"
    ;;

  production)
    echo "Deploying to production from branch: ${current_branch}"
    echo "Current commit: ${commit_short}"
    echo "Full SHA: ${commit_sha}"
    echo "Looking for existing version with tag: ${commit_tag}"
    echo "Deployment message: ${deploy_msg}"
    echo ""

    export WRANGLER_CONFIG="$wrangler_config"

    # Query for an existing version uploaded from this commit (via preview).
    # Capture versions list to a tempfile so post-condition verification can
    # reuse it. `| cat >` routes through a pipe-shaped fd — see the preview
    # subcommand's equivalent comment for the empirical rationale.
    wrangler_list_json="$tmpdir/wrangler-versions-list.json"

    node "$WRANGLER" --config "$WRANGLER_CONFIG" versions list --json \
      | cat > "$wrangler_list_json"

    existing_version=$(jq -r --arg tag "$commit_tag" \
      '.[] | select(.annotations["workers/tag"] == $tag) | .id' \
      "$wrangler_list_json" 2>/dev/null | head -1 || true)

    if [[ -n "$existing_version" ]]; then
      echo "found existing version: ${existing_version}"
      echo "  this version was already built and tested in preview"
      echo "  promoting to 100% production traffic..."
      echo ""

      export DEPLOYMENT_MESSAGE="$deploy_msg"
      export EXISTING_VERSION="$existing_version"

      # Post-condition verification mirrors the preview path: capture
      # wrangler's NDJSON event log via WRANGLER_OUTPUT_FILE_PATH, assert a
      # non-empty deployment_id on the `version-deploy` event, then cross-check
      # via `wrangler deployments list --json` before declaring success. Like
      # `versions upload`, `versions deploy` does NOT accept `--json` on
      # wrangler 4.84.x — the event log is the authoritative machine-readable
      # output channel. Detects wrangler's silent-exit failure mode when the
      # CI-detection branch exits 0 without performing the promotion.
      deploy_ndjson="$tmpdir/wrangler-versions-deploy.ndjson"
      deploy_stdout="$tmpdir/wrangler-versions-deploy.stdout"
      : > "$deploy_ndjson"
      : > "$deploy_stdout"
      export WRANGLER_OUTPUT_FILE_PATH="$deploy_ndjson"

      node "$WRANGLER" --config "$WRANGLER_CONFIG" versions deploy \
          "${EXISTING_VERSION}@100%" \
          --yes \
          --message "$DEPLOYMENT_MESSAGE" \
        | tee "$deploy_stdout"

      unset WRANGLER_OUTPUT_FILE_PATH

      deployment_id=""
      if [[ -s "$deploy_ndjson" ]]; then
        deployment_id=$(
          jq -rs '
            map(select(type == "object" and (.type // "") == "version-deploy"))
            | .[0].deployment_id // empty
          ' "$deploy_ndjson" 2>/dev/null || true
        )
      fi
      if [[ -z "$deployment_id" ]]; then
        # stdout fallback: match `Deployment ID: <uuid>` / `deployment_id: <uuid>`.
        deployment_id=$(
          grep -oiE '(Deployment ID|deployment_id)[[:space:]]*:[[:space:]]*[a-f0-9-]+' \
            "$deploy_stdout" 2>/dev/null \
            | awk '{print $NF}' \
            | head -1 || true
        )
      fi
      if [[ -z "$deployment_id" ]]; then
        echo "" >&2
        echo "error: wrangler exited 0 but produced no Deployment ID" >&2
        echo "  post-condition (a) failed: neither WRANGLER_OUTPUT_FILE_PATH NDJSON" >&2
        echo "                              event log nor wrangler stdout contained" >&2
        echo "                              a recognizable Deployment ID" >&2
        echo "  raw wrangler event log: $deploy_ndjson" >&2
        echo "  raw wrangler stdout:   $deploy_stdout" >&2
        echo "  hints:" >&2
        echo "    - confirm CLOUDFLARE_API_TOKEN and CLOUDFLARE_ACCOUNT_ID are exported by" >&2
        echo "      the caller (see deploy.sh env-var contract header for caller mechanisms)" >&2
        echo "    - if linux-x64 regression, confirm wrangler invoked under real node and" >&2
        echo "      not bun-fake-node (see deploy.sh node invocation rationale)" >&2
        echo "    - inspect the wrangler internal log dumped below / raw capture paths above for any output" >&2
        exit 1
      fi

      deployments_list_json="$tmpdir/wrangler-deployments-list.json"

      node "$WRANGLER" --config "$WRANGLER_CONFIG" deployments list --json \
        | cat > "$deployments_list_json"

      found_count=$(jq --arg did "$deployment_id" --arg vid "$existing_version" \
        '[.[] | select(
           .id == $did
           or .deployment_id == $did
           or ((.versions // []) | map(.version_id // .id // "") | index($vid) != null)
         )] | length' \
        "$deployments_list_json" 2>/dev/null || echo 0)
      if [[ "$found_count" -lt 1 ]]; then
        echo "" >&2
        echo "error: deployment ${deployment_id} (version ${existing_version}) not found in deployments list" >&2
        echo "  post-condition (b) failed: wrangler deployments list returned no" >&2
        echo "                              entries matching the just-deployed id/version" >&2
        echo "  raw deployments list output: $deployments_list_json" >&2
        echo "  hint: wrangler reported a deployment locally but the Cloudflare API did" >&2
        echo "        not persist it; inspect the raw deployments list for surrounding entries" >&2
        exit 1
      fi

      echo ""
      echo "successfully promoted version ${existing_version} to production"
      echo "  Deployment ID: ${deployment_id}"
      echo "  tag: ${commit_tag}"
      echo "  full SHA: ${commit_sha}"
      echo "  deployed by: ${deploy_msg}"
      echo "  production URL: https://infra.cameronraysmith.net"
    else
      echo "warning: no existing version found with tag: ${commit_tag}"
      echo "  this should only happen if:"
      echo "    - this is the first deployment"
      echo "    - commit was made directly on main (not recommended)"
      echo "    - version was cleaned up (retention policy)"
      echo ""
      echo "  falling back to direct deploy of the nix-built payload..."
      echo ""

      export DEPLOYMENT_MESSAGE="$deploy_msg"

      # Fallback direct-deploy: same post-condition pattern, but the
      # NDJSON event is `type == "deploy"` carrying `version_id` (no
      # deployment_id field on this event type). `wrangler deploy` does
      # NOT accept `--json` on wrangler 4.84.x; WRANGLER_OUTPUT_FILE_PATH
      # is the authoritative machine-readable channel.
      deploy_ndjson="$tmpdir/wrangler-deploy.ndjson"
      deploy_stdout="$tmpdir/wrangler-deploy.stdout"
      : > "$deploy_ndjson"
      : > "$deploy_stdout"
      export WRANGLER_OUTPUT_FILE_PATH="$deploy_ndjson"

      node "$WRANGLER" --config "$WRANGLER_CONFIG" deploy \
          --message "$DEPLOYMENT_MESSAGE" \
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
        echo "error: wrangler exited 0 but produced no Deployment Version ID (fallback direct deploy)" >&2
        echo "  post-condition (a) failed: neither WRANGLER_OUTPUT_FILE_PATH NDJSON" >&2
        echo "                              event log nor wrangler stdout contained" >&2
        echo "                              a recognizable version_id" >&2
        echo "  raw wrangler event log: $deploy_ndjson" >&2
        echo "  raw wrangler stdout:   $deploy_stdout" >&2
        echo "  hints:" >&2
        echo "    - confirm CLOUDFLARE_API_TOKEN and CLOUDFLARE_ACCOUNT_ID are exported by" >&2
        echo "      the caller (see deploy.sh env-var contract header for caller mechanisms)" >&2
        echo "    - if linux-x64 regression, confirm wrangler invoked under real node and" >&2
        echo "      not bun-fake-node (see deploy.sh node invocation rationale)" >&2
        echo "    - inspect the wrangler internal log dumped below / raw capture paths above for any output" >&2
        exit 1
      fi
      # Reuse deployment_id slot below (it now holds the just-deployed version_id
      # since `wrangler deploy` emits no server-assigned deployment id directly).
      deployment_id="$deploy_version_id"

      deployments_list_json="$tmpdir/wrangler-deployments-list.json"

      node "$WRANGLER" --config "$WRANGLER_CONFIG" deployments list --json \
        | cat > "$deployments_list_json"

      found_count=$(jq --arg vid "$deploy_version_id" \
        '[.[] | select(
           .id == $vid
           or .deployment_id == $vid
           or ((.versions // []) | map(.version_id // .id // "") | index($vid) != null)
         )] | length' \
        "$deployments_list_json" 2>/dev/null || echo 0)
      if [[ "$found_count" -lt 1 ]]; then
        echo "" >&2
        echo "error: deployment for version ${deploy_version_id} not found in deployments list (fallback direct deploy)" >&2
        echo "  post-condition (b) failed: wrangler deployments list returned no" >&2
        echo "                              entries matching the just-deployed version_id" >&2
        echo "  raw deployments list output: $deployments_list_json" >&2
        echo "  hint: wrangler reported a deployment locally but the Cloudflare API did" >&2
        echo "        not persist it; inspect the raw deployments list for surrounding entries" >&2
        exit 1
      fi

      echo ""
      echo "deployed nix-built payload directly to production"
      echo "  Deployment Version ID: ${deployment_id}"
      echo "  tag: ${commit_tag}"
      echo "  full SHA: ${commit_sha}"
      echo "  deployed by: ${deploy_msg}"
      echo "  production URL: https://infra.cameronraysmith.net"
      echo "  warning: this version was not tested in preview first"
    fi
    ;;

  *)
    echo "error: unknown subcommand '$mode'" >&2
    echo "usage: deploy-docs preview <branch> | deploy-docs production" >&2
    echo "(run with --help for full usage and env-var contract)" >&2
    exit 2
    ;;
esac
