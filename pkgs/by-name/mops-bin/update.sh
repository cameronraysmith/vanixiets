#!/usr/bin/env nix-shell
#!nix-shell --pure -i bash -p curl cacert git nix coreutils gnused gnugrep
# shellcheck shell=bash
#
# Usage: ./update.sh [VERSION]   (VERSION overrides the latest-tag lookup)

set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"
PKG_NIX="${REPO_ROOT}/pkgs/by-name/mops-bin/package.nix"

current_version="$(sed -n 's/.*version = "\(.*\)";/\1/p' "$PKG_NIX" | head -1)"

if [[ $# -ge 1 ]]; then
  latest_version="${1#cli-v}"
else
  # caffeinelabs/mops is a monorepo whose releases/latest need not be a CLI
  # release, so take the highest cli-vMAJOR.MINOR.PATCH tag instead; listing
  # tags with git also avoids the rate-limited api.github.com.
  latest_version="$(git ls-remote --tags --refs https://github.com/caffeinelabs/mops 'refs/tags/cli-v*' |
    sed -n 's|.*refs/tags/cli-v\([0-9]*\.[0-9]*\.[0-9]*\)$|\1|p' |
    sort -V | tail -1)"
fi

if [[ ! "$latest_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "error: no cli-vMAJOR.MINOR.PATCH tag found (got '${latest_version}')" >&2
  exit 1
fi

if [[ "$current_version" == "$latest_version" ]]; then
  echo "mops-bin is already at version ${current_version}; refreshing hash anyway"
else
  echo "Updating mops-bin: ${current_version} -> ${latest_version}"
  sed -i'' -e "s/version = \"${current_version}\"/version = \"${latest_version}\"/" "$PKG_NIX"
fi

# The release publishes no checksum file, so the hash is a prefetch of the
# asset.
url="https://github.com/caffeinelabs/mops/releases/download/cli-v${latest_version}/cli.tgz"
sri_hash="$(nix store prefetch-file --json --hash-type sha256 "$url" | sed -n 's/.*"hash":"\([^"]*\)".*/\1/p')"

if [[ ! "$sri_hash" =~ ^sha256- ]]; then
  echo "error: failed to compute hash for ${url}" >&2
  exit 1
fi

sed -i'' -e "s|hash = \"sha256-[^\"]*\"|hash = \"${sri_hash}\"|" "$PKG_NIX"
echo "  cli.tgz: ${sri_hash}"

echo "Updated mops-bin to ${latest_version}"
