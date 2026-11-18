#!/usr/bin/env nix-shell
#!nix-shell --pure -i bash -p curl cacert git nix coreutils gnused gawk gnugrep
# shellcheck shell=bash
#
# Usage: ./update.sh [VERSION]   (VERSION overrides the latest-release lookup)

set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"
PKG_NIX="${REPO_ROOT}/pkgs/by-name/mergify-cli-bin/package.nix"
APM_YML="${REPO_ROOT}/modules/home/ai/plugins/version-control-and-forge/apm.yml"

current_version="$(sed -n 's/.*version = "\(.*\)";/\1/p' "$PKG_NIX" | head -1)"

if [[ $# -ge 1 ]]; then
  latest_url="argument"
  latest_version="$1"
else
  # Tag discovery deliberately avoids api.github.com, which is rate-limited on
  # the shared egress: the unauthenticated releases/latest URL 302s to the tag
  # page, so the redirect target names the release.
  latest_url="$(curl -fsIL -o /dev/null -w '%{url_effective}' \
    "https://github.com/Mergifyio/mergify-cli/releases/latest")"
  latest_version="${latest_url##*/}"
fi

# Tags are bare calver with no `v` prefix (for example 2026.8.31.1); reject
# anything else rather than stamping a redirect that landed somewhere unexpected.
if [[ ! "$latest_version" =~ ^[0-9]{4}\.[0-9]+\.[0-9]+(\.[0-9]+)?$ ]]; then
  echo "error: ${latest_url} names no calver tag" >&2
  exit 1
fi

if [[ "$current_version" == "$latest_version" ]]; then
  echo "mergify-cli-bin is already at version ${current_version}; refreshing hashes anyway"
else
  echo "Updating mergify-cli-bin: ${current_version} -> ${latest_version}"
  sed -i'' -e "s/version = \"${current_version}\"/version = \"${latest_version}\"/" "$PKG_NIX"
fi

# Hashes come from the release's own SHA256SUMS asset (one hex line per asset),
# so the recorded hash is upstream's published digest rather than whatever a
# prefetch happened to download.
sha256sums="$(curl -fsSL \
  "https://github.com/Mergifyio/mergify-cli/releases/download/${latest_version}/SHA256SUMS")"

# Platform map: nix system -> Rust target triple (asset is
# mergify-<version>-<triple>.tar.gz)
declare -A platform_map=(
  ["x86_64-linux"]="x86_64-unknown-linux-gnu"
  ["aarch64-linux"]="aarch64-unknown-linux-gnu"
  ["x86_64-darwin"]="x86_64-apple-darwin"
  ["aarch64-darwin"]="aarch64-apple-darwin"
)

for platform in "${!platform_map[@]}"; do
  triple="${platform_map[$platform]}"
  asset="mergify-${latest_version}-${triple}.tar.gz"

  hex_hash="$(awk -v asset="$asset" '$2 == asset { print $1 }' <<<"$sha256sums")"

  if [[ -z "$hex_hash" ]]; then
    echo "error: SHA256SUMS carries no line for ${asset}" >&2
    exit 1
  fi

  sri_hash="$(nix hash convert --hash-algo sha256 --to sri "$hex_hash")"

  # Anchor on this platform's `triple = "<triple>";` line, advance to the
  # immediately-following `hash =` line, and substitute. Each triple is unique
  # to a single block in package.nix, so exactly one hash line is rewritten.
  sed -i'' -e "/triple = \"${triple}\";/{ n; s|hash = \"sha256-[^\"]*\"|hash = \"${sri_hash}\"|; }" "$PKG_NIX"

  echo "  ${platform}: ${sri_hash} (${asset})"
done

# Record the commit the release tag points at and move the mergify-stack skill's
# apm.yml ref with it (structure-release-alignment-mergify-cli requires them
# equal). An annotated tag lists both the tag object and its peeled `^{}`
# commit; a lightweight tag lists only the commit. Prefer the peeled line.
tag_refs="$(git ls-remote "https://github.com/Mergifyio/mergify-cli" "refs/tags/${latest_version}^{}" "refs/tags/${latest_version}")"
source_rev="$(printf '%s\n' "$tag_refs" | grep -F '^{}' | cut -f1 || true)"
if [[ -z "$source_rev" ]]; then
  source_rev="$(printf '%s\n' "$tag_refs" | head -1 | cut -f1)"
fi

if [[ ! "$source_rev" =~ ^[0-9a-f]{40}$ ]]; then
  echo "error: failed to resolve a commit for tag ${latest_version}" >&2
  exit 1
fi

sed -i'' -e "s|sourceRev = \"[0-9a-f]\{40\}\"|sourceRev = \"${source_rev}\"|" "$PKG_NIX"
sed -i'' -e "/git: Mergifyio\/mergify-cli\$/{ n; s|ref: [0-9a-f]\{40\}|ref: ${source_rev}|; }" "$APM_YML"

if ! grep -qF "sourceRev = \"${source_rev}\"" "$PKG_NIX" || ! grep -qF "ref: ${source_rev}" "$APM_YML"; then
  echo "error: failed to rewrite sourceRev in ${PKG_NIX} or the Mergifyio/mergify-cli ref in ${APM_YML}" >&2
  exit 1
fi
echo "  sourceRev and apm.yml ref: ${source_rev}"
echo "  update apmDepsHash in pkgs/by-name/apm-skills-compose/package.nix from the next apm-deps build's hash mismatch"

echo "Updated mergify-cli-bin to ${latest_version}"
