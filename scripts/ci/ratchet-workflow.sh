#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# Ratchet Workflow Script
# ============================================================================
# Run sethvargo/ratchet actions on GitHub Actions workflow files to pin,
# unpin, update, or upgrade action versions.
#
# Usage:
#   ratchet-workflow.sh <action> [workflow...]
#
# Arguments:
#   action      Action to perform: pin, unpin, update, upgrade
#   workflow    Workflow files to process (optional, defaults to GHA_WORKFLOWS
#               env var or ./.github/workflows/flake.yaml)
#
# Environment Variables:
#   GHA_WORKFLOWS   Space-separated list of workflow files to process
#   RATCHET_BASE    Base ratchet command (default: ratchet)
#
# Examples:
#   ratchet-workflow.sh pin
#   ratchet-workflow.sh update ./.github/workflows/flake.yaml
#   GHA_WORKFLOWS="./.github/workflows/*.yaml" ratchet-workflow.sh upgrade
# ============================================================================

# Working directory normalization
cd "$(git rev-parse --show-toplevel)"

# Help flag
if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    cat <<EOF
Usage: $0 <action> [workflow...]

Run ratchet action on GitHub Actions workflow files.

Arguments:
    action          Action to perform: pin, unpin, update, upgrade
    workflow        Workflow files to process (default: \$GHA_WORKFLOWS or ./.github/workflows/flake.yaml)

Actions:
    pin             Pin action versions to commit SHAs
    unpin           Unpin action versions back to semantic versions
    update          Update pinned actions to latest versions
    upgrade         Upgrade actions across major versions (review carefully)

Environment Variables:
    GHA_WORKFLOWS   Space-separated list of workflow files to process
    RATCHET_BASE    Base ratchet command (default: ratchet)

Examples:
    $0 pin
    $0 update ./.github/workflows/flake.yaml ./.github/workflows/docs.yaml
    GHA_WORKFLOWS="./.github/workflows/*.yaml" $0 upgrade
EOF
    exit 0
fi

# Parse action argument
ACTION="${1:-}"

if [[ -z "$ACTION" ]]; then
    echo "error: action required"
    echo "valid actions: pin, unpin, update, upgrade"
    echo "run with --help for usage"
    exit 1
fi

shift

# Use remaining arguments as workflows, or fall back to environment variable, or default
if [[ $# -gt 0 ]]; then
    WORKFLOWS="$*"
else
    WORKFLOWS="${GHA_WORKFLOWS:-./.github/workflows/flake.yaml}"
fi

RATCHET_BASE="${RATCHET_BASE:-ratchet}"

# Validate action
case "$ACTION" in
    pin|unpin|update|upgrade)
        ;;
    *)
        echo "error: unknown action '$ACTION'"
        echo "valid actions: pin, unpin, update, upgrade"
        echo "run with --help for usage"
        exit 1
        ;;
esac

# Process each workflow
for workflow in $WORKFLOWS; do
    if [[ ! -f "$workflow" ]]; then
        echo "warning: workflow file not found: $workflow"
        continue
    fi
    echo "running ratchet $ACTION on $workflow..."
    eval "$RATCHET_BASE $ACTION $workflow"
done

echo ""
echo "successfully completed ratchet $ACTION on all workflows"
