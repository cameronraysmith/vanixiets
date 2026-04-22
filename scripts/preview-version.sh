#!/usr/bin/env bash
# preview-version.sh - Thin shim over the preview-version flake app.
#
# The authoritative implementation lives at modules/apps/preview-version/ (via
# modules/apps/docs/preview-version.{nix,sh}), invoked through the flake app
# `.#preview-version`. This shim is retained so out-of-tree callers that still
# reference `./scripts/preview-version.sh` (notably `package.json:18`) keep
# working.
#
# Usage:
#   ./scripts/preview-version.sh [target-branch] [package-path]
#
# Forwards all arguments to `nix run .#preview-version --`.

set -euo pipefail

exec nix run --accept-flake-config --no-warn-dirty .#preview-version -- "$@"
