#!/usr/bin/env bash
# preview-version.sh - Thin shim over the preview-version flake app.
#
# The authoritative implementation lives at
# modules/apps/docs/preview-version.{nix,sh} and is invoked through the
# flake app `.#preview-version`. This shim is retained so out-of-tree
# callers that still reference `./scripts/preview-version.sh` (notably
# `package.json:18`) keep working. Run `nix run .#preview-version -- --help`
# for usage and arguments.

set -euo pipefail

exec nix run --accept-flake-config --no-warn-dirty .#preview-version -- "$@"
