#!/usr/bin/env nix-shell
#!nix-shell --pure -i bash -p curl jq cacert git nix
# shellcheck shell=bash

set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"
PKG_NIX="${REPO_ROOT}/pkgs/by-name/uncomment-bin/package.nix"

current_version="$(sed -n 's/.*version = "\(.*\)";/\1/p' "$PKG_NIX" | head -1)"

# Filter the release list to bare semver tags (vMAJOR.MINOR.PATCH) so that a
# pre-release or the floating major tag (`v3`, itself published as a release)
# cannot be mistaken for the latest CLI release, then take the highest version:
# the API's order is not version order (`v3` is listed ahead of v3.10.4).
latest_tag="$(curl -fsSL \
  -H "Accept: application/vnd.github+json" \
  "https://api.github.com/repos/polylint/uncomment/releases?per_page=100" \
  | jq -r '[.[] | select(.prerelease | not) | select(.tag_name | test("^v[0-9]+\\.[0-9]+\\.[0-9]+$")) | .tag_name]
      | max_by(ltrimstr("v") | split(".") | map(tonumber))')"
latest_version="${latest_tag#v}"

if [[ -z "$latest_version" || "$latest_version" == "null" ]]; then
  echo "error: failed to discover a semver tag from GitHub releases" >&2
  exit 1
fi

if [[ "$current_version" == "$latest_version" ]]; then
  echo "uncomment-bin is already at version ${current_version}; refreshing hashes anyway"
else
  echo "Updating uncomment-bin: ${current_version} -> ${latest_version}"
  sed -i'' -e "s/version = \"${current_version}\"/version = \"${latest_version}\"/" "$PKG_NIX"
fi

# Platform map: nix system -> Rust target triple (release asset stem)
declare -A platform_map=(
  ["x86_64-linux"]="x86_64-unknown-linux-gnu"
  ["aarch64-linux"]="aarch64-unknown-linux-gnu"
  ["x86_64-darwin"]="x86_64-apple-darwin"
  ["aarch64-darwin"]="aarch64-apple-darwin"
)

for platform in "${!platform_map[@]}"; do
  triple="${platform_map[$platform]}"
  url="https://github.com/polylint/uncomment/releases/download/v${latest_version}/uncomment-${triple}.tar.gz"

  echo "Prefetching ${platform} (${triple})..."
  sri_hash="$(nix store prefetch-file --json --hash-type sha256 "$url" | jq -r .hash)"

  if [[ -z "$sri_hash" || "$sri_hash" == "null" ]]; then
    echo "error: failed to compute hash for ${platform} from ${url}" >&2
    exit 1
  fi

  # Anchor on this platform's `name = "<triple>";` line, advance to the
  # immediately-following `hash =` line, and substitute. Each triple is unique
  # to a single block in package.nix, so exactly one hash line is rewritten.
  sed -i'' -e "/name = \"${triple}\";/{ n; s|hash = \"sha256-[^\"]*\"|hash = \"${sri_hash}\"|; }" "$PKG_NIX"

  echo "  ${platform}: ${sri_hash}"
done

# Build-verify every flake system this package targets, intersected with the
# systems this script already knows how to fetch hashes for, so a
# platform-specific runtime regression (e.g. a newly required shared library)
# fails the update instead of surviving unnoticed.
flake_systems_json="$(nix eval --json --apply builtins.attrNames "${REPO_ROOT}#packages")"
mapfile -t flake_systems < <(printf '%s' "$flake_systems_json" | jq -r '.[]')

build_systems=()
for system in "${flake_systems[@]}"; do
  if [[ -v platform_map[$system] ]]; then
    build_systems+=("$system")
  fi
done

declare -A build_results=()
build_failed=0

for system in "${build_systems[@]}"; do
  echo "Building uncomment-bin for ${system}..."
  if output="$(nix build --no-link "${REPO_ROOT}#packages.${system}.uncomment-bin" 2>&1)"; then
    build_results["$system"]="ok"
  elif printf '%s' "$output" | grep -qE 'required system|unable to start any build'; then
    build_results["$system"]="skipped (no builder available)"
    echo "warning: no builder available for ${system}; skipping build verification" >&2
  else
    build_results["$system"]="FAILED"
    build_failed=1
    echo "error: build failed for ${system}:" >&2
    echo "$output" >&2
  fi
done

echo "Build verification summary:"
for system in "${build_systems[@]}"; do
  echo "  ${system}: ${build_results[$system]}"
done

if [[ "$build_failed" -eq 1 ]]; then
  echo "error: build verification failed for one or more systems" >&2
  exit 1
fi

echo "Updated uncomment-bin to ${latest_version}"
