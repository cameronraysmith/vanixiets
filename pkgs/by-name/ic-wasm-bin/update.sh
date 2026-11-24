#!/usr/bin/env nix-shell
#!nix-shell --pure -i bash -p curl cacert git nix coreutils gnused gawk
# shellcheck shell=bash
#
# Usage: ./update.sh [VERSION]   (VERSION overrides the latest-release lookup)

set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"
PKG_NIX="${REPO_ROOT}/pkgs/by-name/ic-wasm-bin/package.nix"

current_version="$(sed -n 's/.*version = "\(.*\)";/\1/p' "$PKG_NIX" | head -1)"

if [[ $# -ge 1 ]]; then
  latest_url="argument"
  latest_version="${1#v}"
else
  # Tag discovery deliberately avoids api.github.com, which is rate-limited on
  # the shared egress: the unauthenticated releases/latest URL 302s to the tag
  # page, so the redirect target names the release.
  latest_url="$(curl -fsIL -o /dev/null -w '%{url_effective}' \
    "https://github.com/dfinity/ic-wasm/releases/latest")"
  latest_version="${latest_url##*/}"
fi

# Tags are bare semver with no `v` prefix (for example 1.0.0); reject anything
# else rather than stamping a redirect that landed somewhere unexpected.
if [[ ! "$latest_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "error: ${latest_url} names no semver tag" >&2
  exit 1
fi

if [[ "$current_version" == "$latest_version" ]]; then
  echo "ic-wasm-bin is already at version ${current_version}; refreshing hashes anyway"
else
  echo "Updating ic-wasm-bin: ${current_version} -> ${latest_version}"
  sed -i'' -e "s/version = \"${current_version}\"/version = \"${latest_version}\"/" "$PKG_NIX"
fi

# Platform map: nix system -> Rust target triple (asset is
# ic-wasm-<triple>.tar.xz)
declare -A platform_map=(
  ["x86_64-linux"]="x86_64-unknown-linux-gnu"
  ["aarch64-linux"]="aarch64-unknown-linux-gnu"
  ["x86_64-darwin"]="x86_64-apple-darwin"
  ["aarch64-darwin"]="aarch64-apple-darwin"
)

for platform in "${!platform_map[@]}"; do
  triple="${platform_map[$platform]}"
  asset="ic-wasm-${triple}.tar.xz"

  # Hashes come from cargo-dist's per-asset .sha256 file, so the recorded hash
  # is upstream's published digest rather than whatever a prefetch downloaded.
  hex_hash="$(curl -fsSL \
    "https://github.com/dfinity/ic-wasm/releases/download/${latest_version}/${asset}.sha256" |
    awk '{ print $1 }')"

  if [[ ! "$hex_hash" =~ ^[0-9a-f]{64}$ ]]; then
    echo "error: ${asset}.sha256 carries no sha256 digest" >&2
    exit 1
  fi

  sri_hash="$(nix hash convert --hash-algo sha256 --to sri "$hex_hash")"

  # Anchor on this platform's `triple = "<triple>";` line, advance to the
  # immediately-following `hash =` line, and substitute.
  sed -i'' -e "/triple = \"${triple}\";/{ n; s|hash = \"sha256-[^\"]*\"|hash = \"${sri_hash}\"|; }" "$PKG_NIX"

  echo "  ${platform}: ${sri_hash} (${asset})"
done

echo "Updated ic-wasm-bin to ${latest_version}"
