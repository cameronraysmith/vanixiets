#!/usr/bin/env bash
# shellcheck shell=bash
# Backward-compat shim — the authoritative implementation now lives at
# modules/apps/cluster/k3d-test-coverage.{nix,sh} (flake app
# `k3d-test-coverage`). This shim is preserved so that out-of-tree
# consumers pinning the legacy `scripts/k3d-test-coverage.sh` path (e.g.,
# the `hash-sources` entry in `.github/workflows/test-cluster.yaml`)
# continue to work during the M1→M5 transition. Once M5 drops the legacy
# path from workflow hash sources, this file may be deleted outright.
set -euo pipefail
exec nix run --accept-flake-config --no-warn-dirty \
  "$(git rev-parse --show-toplevel 2>/dev/null || echo .)#k3d-test-coverage" \
  -- "$@"
