#!/usr/bin/env nix-shell
#!nix-shell --pure -i bash -p curl jq cacert git nix
# shellcheck shell=bash
#
# Usage: ./update.sh [VERSION]   (VERSION overrides the latest-release lookup)

set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"
PKG_NIX="${REPO_ROOT}/pkgs/by-name/worktrunk-bin/package.nix"
APM_YML="${REPO_ROOT}/modules/home/ai/plugins/version-control-and-forge/apm.yml"

current_version="$(sed -n 's/.*version = "\(.*\)";/\1/p' "$PKG_NIX" | head -1)"

if [[ $# -ge 1 ]]; then
  latest_version="${1#v}"
else
  # Filter the release list to bare semver tags (vMAJOR.MINOR.PATCH) so that a
  # pre-release or sibling tag cannot be mistaken for the latest release.
  latest_tag="$(curl -fsSL \
    -H "Accept: application/vnd.github+json" \
    "https://api.github.com/repos/max-sixty/worktrunk/releases?per_page=100" \
    | jq -r '[.[] | select(.tag_name | test("^v[0-9]+\\.[0-9]+\\.[0-9]+$"))] | .[0].tag_name')"
  latest_version="${latest_tag#v}"
fi

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

# Record the commit the release tag points at and move the worktrunk skills'
# apm.yml ref with it (structure-release-alignment-worktrunk requires them
# equal). An annotated tag lists both the tag object and its peeled `^{}`
# commit; a lightweight tag lists only the commit. Prefer the peeled line.
tag_refs="$(git ls-remote "https://github.com/max-sixty/worktrunk" "refs/tags/v${latest_version}^{}" "refs/tags/v${latest_version}")"
source_rev="$(printf '%s\n' "$tag_refs" | grep -F '^{}' | cut -f1 || true)"
if [[ -z "$source_rev" ]]; then
  source_rev="$(printf '%s\n' "$tag_refs" | head -1 | cut -f1)"
fi

if [[ ! "$source_rev" =~ ^[0-9a-f]{40}$ ]]; then
  echo "error: failed to resolve a commit for tag v${latest_version}" >&2
  exit 1
fi

sed -i'' -e "s|sourceRev = \"[0-9a-f]\{40\}\"|sourceRev = \"${source_rev}\"|" "$PKG_NIX"
sed -i'' -e "/git: max-sixty\/worktrunk\$/{ n; s|ref: [0-9a-f]\{40\}|ref: ${source_rev}|; }" "$APM_YML"

if ! grep -qF "sourceRev = \"${source_rev}\"" "$PKG_NIX" || ! grep -qF "ref: ${source_rev}" "$APM_YML"; then
  echo "error: failed to rewrite sourceRev in ${PKG_NIX} or the max-sixty/worktrunk ref in ${APM_YML}" >&2
  exit 1
fi
echo "  sourceRev and apm.yml ref: ${source_rev}"
echo "  update apmDepsHash in pkgs/by-name/apm-skills-compose/package.nix from the next apm-deps build's hash mismatch"

echo "Updated worktrunk-bin to ${latest_version}"
