#!/usr/bin/env bash
# shellcheck shell=bash
# Docs deployment dispatcher invoked via `nix run .#deploy-docs`.
#
# Environment inputs (set by deploy.nix):
#   DOCS_PAYLOAD       absolute path to the vanixiets-docs derivation output
#                      ({dist/,.wrangler/,wrangler.jsonc} layout)
#   SOPS_SECRETS_FILE  absolute path to secrets/shared.yaml under $inputs.self
#
# Usage:
#   deploy-docs preview <branch>
#   deploy-docs production
#   deploy-docs --help
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

Environment contract (populated by deploy.nix; required at runtime):
  DOCS_PAYLOAD       Absolute path to the vanixiets-docs derivation output
                     ($out/{dist/, .wrangler/, wrangler.jsonc}).
  SOPS_SECRETS_FILE  Absolute path to secrets/shared.yaml under $inputs.self;
                     source of Cloudflare credentials via `sops exec-env`.
  DOCS_NODE_MODULES  Absolute path to the vanixiets-docs-deps node_modules
                     tree (hosts the hermetic wrangler binary).

Optional environment:
  GITHUB_ACTIONS / GITHUB_ACTOR / GITHUB_WORKFLOW
                     When set, the production deploy message is prefixed with
                     the GitHub Actions context; otherwise whoami and hostname
                     are used.

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

if [[ -z "${DOCS_PAYLOAD:-}" ]]; then
  echo "error: DOCS_PAYLOAD not set; deploy.nix must pass the nix-built payload" >&2
  exit 1
fi
if [[ ! -d "$DOCS_PAYLOAD" ]]; then
  echo "error: DOCS_PAYLOAD=$DOCS_PAYLOAD is not a directory" >&2
  exit 1
fi
if [[ -z "${SOPS_SECRETS_FILE:-}" ]]; then
  echo "error: SOPS_SECRETS_FILE not set; deploy.nix must interpolate secrets path" >&2
  exit 1
fi
if [[ ! -f "$SOPS_SECRETS_FILE" ]]; then
  echo "error: SOPS_SECRETS_FILE=$SOPS_SECRETS_FILE does not exist" >&2
  exit 1
fi
if [[ -z "${DOCS_NODE_MODULES:-}" ]]; then
  echo "error: DOCS_NODE_MODULES not set; deploy.nix must expose vanixiets-docs-deps" >&2
  exit 1
fi

# Hermetic wrangler via bun-managed node_modules (vanixiets-docs-deps derivation).
# Must be exported so sops exec-env subshells inherit it for single-quoted command strings.
# The `${WRANGLER:-...}` fallback allows test harnesses (e.g. the no-op wrangler stub
# used to exercise the post-condition error paths for VAL-WRITESHELL-DOCS-010) to
# override the hermetic binary without rewriting this script.
export WRANGLER="${WRANGLER:-$DOCS_NODE_MODULES/.bin/wrangler}"

# Resolve repo root so git metadata commands work independently of callsite.
repo_root=$(git rev-parse --show-toplevel)
cd "$repo_root"

# Materialise a writable copy of the nix payload. wrangler reads
# .wrangler/deploy/config.json whose configPath ("../../dist/server/wrangler.json")
# resolves against the config file's location, and wrangler may write state to
# .wrangler/ during deploy — both require a writable tree outside /nix/store.
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

# Commit metadata shared by preview and production subcommands.
commit_sha=$(git rev-parse HEAD)
commit_tag=$(git rev-parse --short=12 HEAD)
commit_short=$(git rev-parse --short HEAD)
current_branch=$(git branch --show-current || true)

# Compose deploy message (prefer GitHub Actions context, fall back to local).
if [[ -n "${GITHUB_ACTIONS:-}" ]]; then
  deployer="${GITHUB_ACTOR:-github-actions}"
  deploy_context="${GITHUB_WORKFLOW:-CI}"
  deploy_msg="Deployed by ${deployer} from ${current_branch} via ${deploy_context}"
else
  deployer=$(whoami)
  deploy_host=$(hostname -s)
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

    # Sanitize branch name for Cloudflare alias (valid subdomain component):
    #   replace / with -, collapse runs, strip leading/trailing -, cap at 40 chars.
    safe_branch=$(echo "$branch" \
      | tr '/' '-' \
      | tr -c 'a-zA-Z0-9-' '-' \
      | sed 's/--*/-/g; s/^-//; s/-$//' \
      | cut -c1-40)

    commit_msg=$(git log -1 --pretty=format:'%s')
    git_status=$(git diff-index --quiet HEAD -- && echo "clean" || echo "dirty")
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
    # Three post-conditions enforce the no-silent-success invariant
    # (VAL-WRITESHELL-DOCS-010):
    #   (a) the NDJSON event log contains a `type == "version-upload"` entry
    #       with a non-empty `version_id` (primary authoritative source)
    #   (b) `wrangler versions list --json` contains an entry whose
    #       annotations["workers/tag"] matches $commit_tag (server-side
    #       persistence cross-check)
    #   (c) only then is the user-visible success block echoed, including the
    #       authoritative Worker Version ID parsed from (a).
    wrangler_upload_ndjson="$tmpdir/wrangler-versions-upload.ndjson"
    wrangler_upload_stdout="$tmpdir/wrangler-versions-upload.stdout"
    : > "$wrangler_upload_ndjson"
    : > "$wrangler_upload_stdout"
    export WRANGLER_OUTPUT_FILE_PATH="$wrangler_upload_ndjson"

    # Tee stdout so we can both display wrangler output live AND parse it as a
    # fallback version_id source (Option B). Observed 2026-04-22: wrangler
    # 4.84.1 occasionally completes the `/versions` upload (server-side
    # version is persisted, `Worker Version ID: ...` is logged to stdout) but
    # then hangs/terminates on the subsequent `/workers/subdomain` GET
    # request, preventing the `writeOutput({type: "version-upload", ...})`
    # call from firing. Capturing stdout in parallel lets us recover the
    # authoritative version_id even in that partial-completion case.
    #
    # shellcheck disable=SC2016  # single-quoted $VARs are intentional; expanded by sops-wrapped subshell
    sops exec-env "$SOPS_SECRETS_FILE" '
      "$WRANGLER" --config "$WRANGLER_CONFIG" versions upload \
        --preview-alias "b-${SAFE_BRANCH}" \
        --tag "$VERSION_TAG" \
        --message "$VERSION_MESSAGE"
    ' | tee "$wrangler_upload_stdout"

    unset WRANGLER_OUTPUT_FILE_PATH

    # Post-condition (a): extract a non-empty Worker Version ID.
    #   Primary source:   NDJSON `version-upload` event (Option A)
    #   Fallback source:  stdout line `Worker Version ID: <uuid>` (Option B)
    # The cross-check in post-condition (b) below guarantees the version
    # actually persisted server-side regardless of which source produced it.
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
      echo "" >&2
      echo "error: wrangler exited 0 but produced no Worker Version ID" >&2
      echo "  post-condition (a) failed: neither WRANGLER_OUTPUT_FILE_PATH NDJSON" >&2
      echo "                              event log nor wrangler stdout contained" >&2
      echo "                              a recognizable Worker Version ID" >&2
      echo "  raw wrangler event log: $wrangler_upload_ndjson" >&2
      echo "  raw wrangler stdout:   $wrangler_upload_stdout" >&2
      echo "  hints:" >&2
      echo "    - confirm CF_API_TOKEN (and CLOUDFLARE_ACCOUNT_ID) are present in" >&2
      echo "      $SOPS_SECRETS_FILE" >&2
      echo "    - if running in GHA, wrangler's CI-detection branch may have" >&2
      echo "      silently exited; rerun with WRANGLER_LOG=debug for stderr trace" >&2
      echo "    - inspect the raw NDJSON and stdout paths above for any output" >&2
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

    # shellcheck disable=SC2016  # single-quoted $VARs are intentional; expanded by sops-wrapped subshell
    sops exec-env "$SOPS_SECRETS_FILE" '
      "$WRANGLER" --config "$WRANGLER_CONFIG" versions list --json
    ' | cat > "$wrangler_list_json"

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
      echo "        not persist it; retry with WRANGLER_LOG=debug or inspect the raw" >&2
      echo "        versions list for surrounding entries" >&2
      exit 1
    fi

    # Post-condition (c): authoritative success echo with parsed Worker Version ID.
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
    # Capture versions list to a tempfile so post-condition verification below
    # can reuse it (avoids a second API call purely for the existing-version
    # lookup) and any diagnostic error messages can reference the raw JSON.
    # `| cat >` is used instead of `>` to route wrangler's stdout through a
    # pipe-shaped fd; see the preview subcommand's equivalent comment for the
    # empirical rationale.
    wrangler_list_json="$tmpdir/wrangler-versions-list.json"

    # shellcheck disable=SC2016  # single-quoted $VARs are intentional; expanded by sops-wrapped subshell
    sops exec-env "$SOPS_SECRETS_FILE" '
      "$WRANGLER" --config "$WRANGLER_CONFIG" versions list --json
    ' | cat > "$wrangler_list_json"

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
      # output channel. Detects wrangler's silent-exit failure mode
      # (VAL-WRITESHELL-DOCS-010 + diagnostic session 45961bc9) when the
      # CI-detection branch exits 0 without actually performing the promotion.
      deploy_ndjson="$tmpdir/wrangler-versions-deploy.ndjson"
      deploy_stdout="$tmpdir/wrangler-versions-deploy.stdout"
      : > "$deploy_ndjson"
      : > "$deploy_stdout"
      export WRANGLER_OUTPUT_FILE_PATH="$deploy_ndjson"

      # shellcheck disable=SC2016  # single-quoted $VARs are intentional; expanded by sops-wrapped subshell
      sops exec-env "$SOPS_SECRETS_FILE" '
        "$WRANGLER" --config "$WRANGLER_CONFIG" versions deploy \
          "${EXISTING_VERSION}@100%" \
          --yes \
          --message "$DEPLOYMENT_MESSAGE"
      ' | tee "$deploy_stdout"

      unset WRANGLER_OUTPUT_FILE_PATH

      # Post-condition (a): extract a non-empty Deployment ID. Primary source
      # is the NDJSON `version-deploy` event (Option A); fallback is stdout
      # parsing for a recognizable deployment identifier (Option B).
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
        # stdout fallback: match patterns like "Deployment ID: <uuid>" or
        # "deployment_id: <uuid>" that wrangler prints on the console.
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
        echo "    - confirm CF_API_TOKEN (and CLOUDFLARE_ACCOUNT_ID) are present in" >&2
        echo "      $SOPS_SECRETS_FILE" >&2
        echo "    - if running in GHA, wrangler's CI-detection branch may have" >&2
        echo "      silently exited; rerun with WRANGLER_LOG=debug for stderr trace" >&2
        exit 1
      fi

      # Post-condition (b): cross-check via deployments list that the deploy
      # landed server-side. `| cat >` empirically required — see preview path
      # comment for the rationale.
      deployments_list_json="$tmpdir/wrangler-deployments-list.json"

      # shellcheck disable=SC2016  # single-quoted $VARs are intentional; expanded by sops-wrapped subshell
      sops exec-env "$SOPS_SECRETS_FILE" '
        "$WRANGLER" --config "$WRANGLER_CONFIG" deployments list --json
      ' | cat > "$deployments_list_json"

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
        echo "        not persist it; retry with WRANGLER_LOG=debug" >&2
        exit 1
      fi

      # Post-condition (c): authoritative success echo with parsed Deployment ID.
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

      # Fallback direct-deploy: same post-condition pattern, but the relevant
      # NDJSON event is `type == "deploy"` which carries `version_id` (no
      # deployment_id field on this event type — see wrangler cli.js
      # writeOutput block for `deploy`). `wrangler deploy` does NOT accept
      # `--json` on wrangler 4.84.x; WRANGLER_OUTPUT_FILE_PATH is the
      # authoritative machine-readable channel.
      deploy_ndjson="$tmpdir/wrangler-deploy.ndjson"
      deploy_stdout="$tmpdir/wrangler-deploy.stdout"
      : > "$deploy_ndjson"
      : > "$deploy_stdout"
      export WRANGLER_OUTPUT_FILE_PATH="$deploy_ndjson"

      # shellcheck disable=SC2016  # single-quoted $VARs are intentional; expanded by sops-wrapped subshell
      sops exec-env "$SOPS_SECRETS_FILE" '
        "$WRANGLER" --config "$WRANGLER_CONFIG" deploy \
          --message "$DEPLOYMENT_MESSAGE"
      ' | tee "$deploy_stdout"

      unset WRANGLER_OUTPUT_FILE_PATH

      # Post-condition (a): extract the just-deployed version_id. Primary
      # source: NDJSON `deploy` event (Option A). Fallback: stdout grep
      # (Option B) for the "Current Version ID: <uuid>" or similar line
      # wrangler prints on direct deploy.
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
        echo "    - confirm CF_API_TOKEN (and CLOUDFLARE_ACCOUNT_ID) are present in" >&2
        echo "      $SOPS_SECRETS_FILE" >&2
        echo "    - if running in GHA, wrangler's CI-detection branch may have" >&2
        echo "      silently exited; rerun with WRANGLER_LOG=debug for stderr trace" >&2
        exit 1
      fi
      # Reuse deployment_id slot below (it now holds the just-deployed version_id
      # since `wrangler deploy` emits no server-assigned deployment id directly).
      deployment_id="$deploy_version_id"

      deployments_list_json="$tmpdir/wrangler-deployments-list.json"

      # shellcheck disable=SC2016  # single-quoted $VARs are intentional; expanded by sops-wrapped subshell
      sops exec-env "$SOPS_SECRETS_FILE" '
        "$WRANGLER" --config "$WRANGLER_CONFIG" deployments list --json
      ' | cat > "$deployments_list_json"

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
        echo "        not persist it; retry with WRANGLER_LOG=debug" >&2
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
