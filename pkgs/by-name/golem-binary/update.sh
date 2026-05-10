#!/usr/bin/env nix-shell
#!nix-shell --pure -i bash -p curl jq cacert git nix
# shellcheck shell=bash

set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"
PKG_NIX="${REPO_ROOT}/pkgs/by-name/golem-binary/package.nix"

current_version="$(sed -n 's/.*version = "\(.*\)";/\1/p' "$PKG_NIX" | head -1)"

# golemcloud/golem is a monorepo: /releases/latest may return tags from
# sibling components (e.g. golem-ts-v1.1.0 from the TypeScript SDK).
# Filter to bare semver tags (vMAJOR.MINOR.PATCH) which mark CLI/server releases.
latest_tag="$(curl -fsSL \
  -H "Accept: application/vnd.github+json" \
  "https://api.github.com/repos/golemcloud/golem/releases?per_page=100" \
  | jq -r '[.[] | select(.tag_name | test("^v[0-9]+\\.[0-9]+\\.[0-9]+$"))] | .[0].tag_name')"
latest_version="${latest_tag#v}"

if [[ -z "$latest_version" || "$latest_version" == "null" ]]; then
  echo "error: failed to discover a semver tag from GitHub releases" >&2
  exit 1
fi

if [[ "$current_version" == "$latest_version" ]]; then
  echo "golem-binary is already at version ${current_version}; refreshing hashes anyway"
else
  echo "Updating golem-binary: ${current_version} -> ${latest_version}"
  sed -i'' -e "s/version = \"${current_version}\"/version = \"${latest_version}\"/" "$PKG_NIX"
fi

# Platform map: nix system -> release artifact filename (URL leaf segment)
declare -A platform_map=(
  ["x86_64-linux"]="golem-x86_64-unknown-linux-gnu"
  ["aarch64-linux"]="golem-aarch64-unknown-linux-gnu"
  ["x86_64-darwin"]="golem-x86_64-apple-darwin"
  ["aarch64-darwin"]="golem-aarch64-apple-darwin"
)

for platform in "${!platform_map[@]}"; do
  artifact="${platform_map[$platform]}"
  url="https://github.com/golemcloud/golem/releases/download/v${latest_version}/${artifact}"

  echo "Prefetching ${platform} (${artifact})..."
  sri_hash="$(nix store prefetch-file --json --hash-type sha256 "$url" | jq -r .hash)"

  if [[ -z "$sri_hash" || "$sri_hash" == "null" ]]; then
    echo "error: failed to compute hash for ${platform} from ${url}" >&2
    exit 1
  fi

  # Match the URL line (which contains the artifact filename), advance to the
  # following `hash =` line, and substitute. Layout in package.nix is one
  # url line immediately followed by one hash line per platform.
  sed -i'' -e "/${artifact}/{ n; s|hash = \"sha256-[^\"]*\"|hash = \"${sri_hash}\"|; }" "$PKG_NIX"

  echo "  ${platform}: ${sri_hash}"
done

echo "Updated golem-binary to ${latest_version}"
