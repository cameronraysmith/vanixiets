#!/usr/bin/env nix-shell
#!nix-shell --pure -i bash -p curl jq cacert git nix
#
# regenerate pkgs/by-name/quarto-bin/manifest.json from the latest quarto-cli release.
# quarto publishes no upstream checksum manifest, so per-platform SRI hashes are
# computed by prefetching each release tarball.
#
# update: nix run .#update-quarto
# source: https://github.com/quarto-dev/quarto-cli

set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"
MANIFEST="${REPO_ROOT}/pkgs/by-name/quarto-bin/manifest.json"

tag="$(curl -fsSL https://api.github.com/repos/quarto-dev/quarto-cli/releases/latest | jq -r .tag_name)"
version="${tag#v}"

prefetch() {
  local asset="$1"
  local url="https://github.com/quarto-dev/quarto-cli/releases/download/v${version}/quarto-${version}-${asset}.tar.gz"
  nix store prefetch-file --json "$url" | jq -r .hash
}

amd64_hash="$(prefetch linux-amd64)"
arm64_hash="$(prefetch linux-arm64)"
macos_hash="$(prefetch macos)"

jq -n \
  --arg version "$version" \
  --arg amd64 "$amd64_hash" \
  --arg arm64 "$arm64_hash" \
  --arg macos "$macos_hash" \
  '{
    version: $version,
    platforms: {
      "x86_64-linux":   { asset: "linux-amd64", hash: $amd64 },
      "aarch64-linux":  { asset: "linux-arm64", hash: $arm64 },
      "aarch64-darwin": { asset: "macos",       hash: $macos },
      "x86_64-darwin":  { asset: "macos",       hash: $macos }
    }
  }' > "$MANIFEST"
