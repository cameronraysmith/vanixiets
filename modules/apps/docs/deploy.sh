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
set -euo pipefail

mode="${1:-}"
if [[ -z "$mode" ]]; then
  echo "error: missing subcommand" >&2
  echo "usage: deploy-docs preview <branch> | deploy-docs production" >&2
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
  echo "error: DOCS_NODE_MODULES not set; deploy.nix must expose docs-node-modules" >&2
  exit 1
fi

# Hermetic wrangler via bun-managed node_modules (docs-node-modules derivation).
# Must be exported so sops exec-env subshells inherit it for single-quoted command strings.
export WRANGLER="$DOCS_NODE_MODULES/.bin/wrangler"

# Resolve repo root so git metadata commands work independently of callsite.
repo_root=$(git rev-parse --show-toplevel)
cd "$repo_root"

# Materialise a writable copy of the nix payload. wrangler reads
# .wrangler/deploy/config.json whose configPath ("../../dist/server/wrangler.json")
# resolves against the config file's location, and wrangler may write state to
# .wrangler/ during deploy — both require a writable tree outside /nix/store.
tmpdir=$(mktemp -d -t deploy-docs.XXXXXX)
trap 'rm -rf "$tmpdir"' EXIT
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

    # shellcheck disable=SC2016  # single-quoted $VARs are intentional; expanded by sops-wrapped subshell
    sops exec-env "$SOPS_SECRETS_FILE" '
      "$WRANGLER" --config "$WRANGLER_CONFIG" versions upload \
        --preview-alias "b-${SAFE_BRANCH}" \
        --tag "$VERSION_TAG" \
        --message "$VERSION_MESSAGE"
    '

    echo ""
    echo "Version uploaded successfully"
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
    # shellcheck disable=SC2016  # single-quoted $VARs are intentional; expanded by sops-wrapped subshell
    existing_version=$(sops exec-env "$SOPS_SECRETS_FILE" '
      "$WRANGLER" --config "$WRANGLER_CONFIG" versions list --json
    ' | jq -r --arg tag "$commit_tag" \
      '.[] | select(.annotations["workers/tag"] == $tag) | .id' | head -1)

    if [[ -n "$existing_version" ]]; then
      echo "found existing version: ${existing_version}"
      echo "  this version was already built and tested in preview"
      echo "  promoting to 100% production traffic..."
      echo ""

      export DEPLOYMENT_MESSAGE="$deploy_msg"

      # shellcheck disable=SC2016  # single-quoted $VARs are intentional; expanded by sops-wrapped subshell
      if sops exec-env "$SOPS_SECRETS_FILE" '
        "$WRANGLER" --config "$WRANGLER_CONFIG" versions deploy \
          "'"$existing_version"'@100%" \
          --yes \
          --message "$DEPLOYMENT_MESSAGE"
      '; then
        echo ""
        echo "successfully promoted version ${existing_version} to production"
        echo "  tag: ${commit_tag}"
        echo "  full SHA: ${commit_sha}"
        echo "  deployed by: ${deploy_msg}"
        echo "  production URL: https://infra.cameronraysmith.net"
      else
        echo ""
        echo "error: failed to promote version ${existing_version}" >&2
        echo "  deployment was cancelled or failed" >&2
        exit 1
      fi
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

      # shellcheck disable=SC2016  # single-quoted $VARs are intentional; expanded by sops-wrapped subshell
      if sops exec-env "$SOPS_SECRETS_FILE" '
        "$WRANGLER" --config "$WRANGLER_CONFIG" deploy --message "$DEPLOYMENT_MESSAGE"
      '; then
        echo ""
        echo "deployed nix-built payload directly to production"
        echo "  warning: this version was not tested in preview first"
      else
        echo ""
        echo "error: failed to deploy" >&2
        exit 1
      fi
    fi
    ;;

  *)
    echo "error: unknown subcommand '$mode'" >&2
    echo "usage: deploy-docs preview <branch> | deploy-docs production" >&2
    exit 2
    ;;
esac
