#!/usr/bin/env nix-shell
#!nix-shell -i bash -p curl jq cacert git nodejs_22 nix-prefetch-scripts
# shellcheck shell=bash

set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"
PKG_DIR="${REPO_ROOT}/pkgs/by-name/beads-ui"
PKG_NIX="${PKG_DIR}/package.nix"

current_version="$(sed -n 's/.*version = "\(.*\)";/\1/p' "$PKG_NIX" | head -1)"

latest_version="$(curl -fsSL \
  -H "Accept: application/vnd.github+json" \
  "https://api.github.com/repos/mantoni/beads-ui/releases/latest" \
  | jq -r '.tag_name | ltrimstr("v")')"

if [[ "$current_version" == "$latest_version" ]]; then
  echo "beads-ui is already at version ${current_version}"
  exit 0
fi

echo "Updating beads-ui: ${current_version} -> ${latest_version}"

# Compute new source hash
echo "Computing source hash..."
new_hash="$(nix-prefetch-url --unpack \
  "https://github.com/mantoni/beads-ui/archive/refs/tags/v${latest_version}.tar.gz" \
  2>/dev/null)"
new_sri="$(nix-hash --to-sri --type sha256 "$new_hash")"

# Regenerate package-lock.json with complete registry metadata
workdir="$(mktemp -d)"
trap 'rm -rf "$workdir"' EXIT

echo "Fetching source..."
curl -fsSL \
  "https://github.com/mantoni/beads-ui/archive/refs/tags/v${latest_version}.tar.gz" \
  | tar -xz -C "$workdir" --strip-components=1

echo "Regenerating package-lock.json..."
(cd "$workdir" && npm install --package-lock-only --ignore-scripts 2>/dev/null)
cp "$workdir/package-lock.json" "${PKG_DIR}/package-lock.json"

# Update version and src hash in package.nix
sed -i'' -e "s/version = \"${current_version}\"/version = \"${latest_version}\"/" "$PKG_NIX"
sed -i'' -e "s|hash = \"sha256-[A-Za-z0-9+/=]*\"|hash = \"${new_sri}\"|" "$PKG_NIX"

# Compute new npmDepsHash via dummy-hash-and-build
DUMMY_HASH="sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="
sed -i'' -e "s|npmDepsHash = \"sha256-[A-Za-z0-9+/=]*\"|npmDepsHash = \"${DUMMY_HASH}\"|" "$PKG_NIX"

echo "Computing npmDepsHash (this triggers a build that will fail with the correct hash)..."
correct_hash="$(nix build ".#beads-ui" 2>&1 \
  | grep -o 'got:.*sha256-[A-Za-z0-9+/=]*' \
  | head -1 \
  | sed 's/got:[[:space:]]*//')" || true

if [[ -z "$correct_hash" ]]; then
  echo "ERROR: Could not extract npmDepsHash from build output."
  echo "Manual intervention required. The version and src hash have been updated."
  echo "Set npmDepsHash to lib.fakeHash and run: nix build .#beads-ui"
  exit 1
fi

sed -i'' -e "s|npmDepsHash = \"${DUMMY_HASH}\"|npmDepsHash = \"${correct_hash}\"|" "$PKG_NIX"

echo "Updated beads-ui to ${latest_version}"
echo "  src hash: ${new_sri}"
echo "  npmDepsHash: ${correct_hash}"
echo "  package-lock.json regenerated"
echo "Review changes with: git diff"
