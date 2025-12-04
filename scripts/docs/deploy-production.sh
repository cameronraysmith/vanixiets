#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# Documentation Production Deployment Script
# ============================================================================
# Deploy documentation to Cloudflare Workers production environment.
# Attempts version promotion if a CI build exists for the current commit,
# falls back to direct deploy if not.
#
# Usage:
#   deploy-production.sh [--dry-run]
#
# Options:
#   --help, -h      Show this help message
#   --dry-run       Show what would be done without executing
#
# Examples:
#   deploy-production.sh
#   deploy-production.sh --dry-run
# ============================================================================

# Working directory normalization
cd "$(git rev-parse --show-toplevel)"

# Help flag
if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    cat <<EOF
Usage: $0 [--dry-run]

Deploy documentation to Cloudflare Workers production environment.
Attempts version promotion if CI build exists, falls back to direct deploy.

Options:
    --help, -h      Show this help message
    --dry-run       Show what would be done without executing

Workflow:
    1. Look for existing version with matching commit tag
    2. If found: promote to 100% production traffic
    3. If not found: build and deploy directly (with warning)

Example:
    $0
    $0 --dry-run
EOF
    exit 0
fi

# Dry-run flag
DRY_RUN=false
if [[ "${1:-}" == "--dry-run" ]]; then
    DRY_RUN=true
    shift
fi

# Change to docs package directory
cd packages/docs

# Get commit metadata
CURRENT_SHA=$(git rev-parse HEAD)
CURRENT_TAG=$(git rev-parse --short=12 HEAD)
CURRENT_SHORT=$(git rev-parse --short HEAD)
CURRENT_BRANCH=$(git branch --show-current)

# Build deployment message (works in both CI and local)
if [ -n "${GITHUB_ACTIONS:-}" ]; then
    # Running in GitHub Actions
    DEPLOYER="${GITHUB_ACTOR:-github-actions}"
    DEPLOY_CONTEXT="${GITHUB_WORKFLOW:-CI}"
    DEPLOY_MSG="Deployed by ${DEPLOYER} from ${CURRENT_BRANCH} via ${DEPLOY_CONTEXT}"
else
    # Running locally
    DEPLOYER=$(whoami)
    DEPLOY_HOST=$(hostname -s)
    DEPLOY_MSG="Deployed by ${DEPLOYER} from ${CURRENT_BRANCH} on ${DEPLOY_HOST}"
fi

echo "Deploying to production from branch: ${CURRENT_BRANCH}"
echo "Current commit: ${CURRENT_SHORT}"
echo "Full SHA: ${CURRENT_SHA}"
echo "Looking for existing version with tag: ${CURRENT_TAG}"
echo "Deployment message: ${DEPLOY_MSG}"
echo ""

# Query for existing version with matching tag (take most recent if multiple)
if [[ "$DRY_RUN" == "true" ]]; then
    echo "[DRY RUN] Would query: bunx wrangler versions list --json"
    EXISTING_VERSION=""
else
    EXISTING_VERSION=$(sops exec-env ../../secrets/shared.yaml \
        "bunx wrangler versions list --json" | \
        jq -r --arg tag "$CURRENT_TAG" \
        '.[] | select(.annotations["workers/tag"] == $tag) | .id' | head -1)
fi

if [ -n "$EXISTING_VERSION" ]; then
    echo "found existing version: ${EXISTING_VERSION}"
    echo "  this version was already built and tested in preview"
    echo "  promoting to 100% production traffic..."
    echo ""

    # Export for use in sops exec-env
    export DEPLOYMENT_MESSAGE="${DEPLOY_MSG}"

    if [[ "$DRY_RUN" == "true" ]]; then
        echo "[DRY RUN] Would execute: bunx wrangler versions deploy ${EXISTING_VERSION}@100% --yes --message \"${DEPLOY_MSG}\""
        echo ""
        echo "[DRY RUN] Would have promoted version ${EXISTING_VERSION} to production"
    else
        if sops exec-env ../../secrets/shared.yaml "
            bunx wrangler versions deploy ${EXISTING_VERSION}@100% --yes --message \"\$DEPLOYMENT_MESSAGE\"
        "; then
            echo ""
            echo "successfully promoted version ${EXISTING_VERSION} to production"
            echo "  tag: ${CURRENT_TAG}"
            echo "  full SHA: ${CURRENT_SHA}"
            echo "  deployed by: ${DEPLOY_MSG}"
            echo "  production URL: https://infra.cameronraysmith.net"
        else
            echo ""
            echo "error: failed to promote version ${EXISTING_VERSION}"
            echo "  deployment was cancelled or failed"
            exit 1
        fi
    fi
else
    echo "warning: no existing version found with tag: ${CURRENT_TAG}"
    echo "  this should only happen if:"
    echo "    - this is the first deployment"
    echo "    - commit was made directly on main (not recommended)"
    echo "    - version was cleaned up (retention policy)"
    echo ""
    echo "  falling back to direct build and deploy..."
    echo ""

    if [[ "$DRY_RUN" == "true" ]]; then
        echo "[DRY RUN] Would execute: bun run build && bunx wrangler deploy"
        echo ""
        echo "[DRY RUN] Would have built and deployed new version directly to production"
    else
        if sops exec-env ../../secrets/shared.yaml "
            echo 'Building...'
            bun run build
            echo 'Deploying...'
            bunx wrangler deploy
        "; then
            echo ""
            echo "built and deployed new version directly to production"
            echo "  warning: this version was not tested in preview first"
        else
            echo ""
            echo "error: failed to build and deploy"
            exit 1
        fi
    fi
fi
