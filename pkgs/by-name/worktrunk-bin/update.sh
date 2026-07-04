#!/usr/bin/env nix-shell
#!nix-shell --pure -i bash -p curl jq cacert nix
# shellcheck shell=bash

set -euo pipefail

# Resolve package.nix relative to this script so the updater edits the correct
# file regardless of the caller's working directory (e.g. nixpkgs update
# machinery, which does not cd into the package directory).
SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
PKG_NIX="${SCRIPT_DIR}/package.nix"

current_version="$(sed -n 's/.*version = "\(.*\)";/\1/p' "$PKG_NIX" | head -1)"

# Filter the release list to bare semver tags (vMAJOR.MINOR.PATCH) so that a
# pre-release or sibling tag cannot be mistaken for the latest release.
latest_tag="$(curl -fsSL \
  -H "Accept: application/vnd.github+json" \
  "https://api.github.com/repos/max-sixty/worktrunk/releases?per_page=100" \
  | jq -r '[.[] | select(.tag_name | test("^v[0-9]+\\.[0-9]+\\.[0-9]+$"))] | .[0].tag_name')"
latest_version="${latest_tag#v}"

if [[ -z "$latest_version" || "$latest_version" == "null" ]]; then
  echo "error: failed to discover a semver tag from GitHub releases" >&2
  exit 1
fi

if [[ "$current_version" == "$latest_version" ]]; then
  echo "worktrunk-bin is already at version ${current_version}; refreshing hashes anyway"
else
  echo "Updating worktrunk-bin: ${current_version} -> ${latest_version}"
  sed -i'' -e "s/version = \"${current_version}\"/version = \"${latest_version}\"/" "$PKG_NIX"
fi

# Platform map: nix system -> cargo-dist target triple (asset is
# worktrunk-<triple>.tar.xz)
declare -A platform_map=(
  ["x86_64-linux"]="x86_64-unknown-linux-musl"
  ["aarch64-linux"]="aarch64-unknown-linux-musl"
  ["x86_64-darwin"]="x86_64-apple-darwin"
  ["aarch64-darwin"]="aarch64-apple-darwin"
)

for platform in "${!platform_map[@]}"; do
  asset="${platform_map[$platform]}"
  url="https://github.com/max-sixty/worktrunk/releases/download/v${latest_version}/worktrunk-${asset}.tar.xz"

  echo "Prefetching ${platform} (worktrunk-${asset}.tar.xz)..."
  sri_hash="$(nix store prefetch-file --json --hash-type sha256 "$url" | jq -r .hash)"

  if [[ -z "$sri_hash" || "$sri_hash" == "null" ]]; then
    echo "error: failed to compute hash for ${platform} from ${url}" >&2
    exit 1
  fi

  # Anchor on this platform's `asset = "<triple>";` line, advance to the
  # immediately-following `hash =` line, and substitute. Each triple is unique
  # to a single block in package.nix, so exactly one hash line is rewritten.
  sed -i'' -e "/asset = \"${asset}\";/{ n; s|hash = \"sha256-[^\"]*\"|hash = \"${sri_hash}\"|; }" "$PKG_NIX"

  echo "  ${platform}: ${sri_hash}"
done

echo "Updated worktrunk-bin to ${latest_version}"
