#!/usr/bin/env nix-shell
#!nix-shell --pure -i bash -p curl jq cacert git cargo rustc pkg-config cmake perl gnumake
# shellcheck shell=bash

set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"
PKG_DIR="${REPO_ROOT}/pkgs/by-name/xsra"
PKG_NIX="${PKG_DIR}/package.nix"

current_version="$(sed -n 's/.*version = "\(.*\)";/\1/p' "$PKG_NIX" | head -1)"

latest_tag="$(curl -fsSL \
  -H "Accept: application/vnd.github+json" \
  "https://api.github.com/repos/ArcInstitute/xsra/releases/latest" \
  | jq -r '.tag_name')"
latest_version="${latest_tag#xsra-}"

if [[ "$current_version" == "$latest_version" ]]; then
  echo "xsra is already at version ${current_version}"
  exit 0
fi

echo "Updating xsra: ${current_version} -> ${latest_version}"

# Fetch new source and generate Cargo.lock
workdir="$(mktemp -d)"
trap 'rm -rf "$workdir"' EXIT

echo "Fetching source for tag ${latest_tag}..."
curl -fsSL \
  "https://github.com/ArcInstitute/xsra/archive/refs/tags/${latest_tag}.tar.gz" \
  | tar -xz -C "$workdir" --strip-components=1

echo "Generating Cargo.lock..."
cargo generate-lockfile --manifest-path "${workdir}/Cargo.toml"
cp "${workdir}/Cargo.lock" "${PKG_DIR}/Cargo.lock"

# Compute new src hash
echo "Computing source hash..."
new_hash="$(nix-prefetch-url --unpack \
  "https://github.com/ArcInstitute/xsra/archive/refs/tags/${latest_tag}.tar.gz" \
  2>/dev/null)"
new_sri="$(nix-hash --to-sri --type sha256 "$new_hash")"

# Update package.nix
sed -i'' -e "s/version = \"${current_version}\"/version = \"${latest_version}\"/" "$PKG_NIX"
sed -i'' -e "s|hash = \"sha256-.*\"|hash = \"${new_sri}\"|" "$PKG_NIX"

echo "Updated xsra to ${latest_version}"
echo "  src hash: ${new_sri}"
echo "  Cargo.lock regenerated"
