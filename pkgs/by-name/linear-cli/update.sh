#!/usr/bin/env nix-shell
#!nix-shell --pure -i bash -p curl jq cacert git nix gnused coreutils gnugrep
# shellcheck shell=bash
#
# Update linear-cli (schpet/linear-cli) to the latest release.
#
# Rewrites, in package.nix:
#   1. the `version = "...";` line
#   2. the four prebuilt-binary `hash = "...";` lines (one per platform, paired
#      to each preceding `url` line)
#   3. the `skillSrc` fetchFromGitHub `rev = "...";` line (the 40-hex commit the
#      v$VERSION tag points at) and the `hash = "...";` line following it
#
# and, in modules/home/ai/plugins/planning-and-development/apm.yml, the `ref:`
# line of the `git: schpet/linear-cli` entry, which must equal the skillSrc rev
# (the apm-skills-compose drift guard enforces it).
#
# Usage: ./update.sh [VERSION]   (VERSION overrides the latest-release lookup)

set -euo pipefail

REPO="schpet/linear-cli"
REPO_ROOT="$(git rev-parse --show-toplevel)"
PKG_NIX="${REPO_ROOT}/pkgs/by-name/linear-cli/package.nix"
APM_YML="${REPO_ROOT}/modules/home/ai/plugins/planning-and-development/apm.yml"

current_version="$(sed -n 's/.*version = "\(.*\)";/\1/p' "$PKG_NIX" | head -1)"

if [[ $# -ge 1 ]]; then
  latest_version="${1#v}"
else
  latest_tag="$(curl -fsSL \
    -H "Accept: application/vnd.github+json" \
    "https://api.github.com/repos/${REPO}/releases/latest" \
    | jq -r .tag_name)"
  latest_version="${latest_tag#v}"
fi

if [[ -z "$latest_version" || "$latest_version" == "null" ]]; then
  echo "error: failed to discover a release tag from GitHub" >&2
  exit 1
fi

if [[ "$current_version" == "$latest_version" ]]; then
  echo "linear-cli is already at version ${current_version}; refreshing hashes anyway"
else
  echo "Updating linear-cli: ${current_version} -> ${latest_version}"
  sed -i'' -e "s/version = \"${current_version}\"/version = \"${latest_version}\"/" "$PKG_NIX"
fi

# Platform map: nix system -> release artifact filename (URL leaf segment).
declare -A platform_map=(
  ["aarch64-darwin"]="linear-aarch64-apple-darwin.tar.xz"
  ["x86_64-darwin"]="linear-x86_64-apple-darwin.tar.xz"
  ["x86_64-linux"]="linear-x86_64-unknown-linux-gnu.tar.xz"
  ["aarch64-linux"]="linear-aarch64-unknown-linux-gnu.tar.xz"
)

for platform in "${!platform_map[@]}"; do
  artifact="${platform_map[$platform]}"
  url="https://github.com/${REPO}/releases/download/v${latest_version}/${artifact}"

  echo "Prefetching ${platform} (${artifact})..."
  sri_hash="$(nix store prefetch-file --json --hash-type sha256 "$url" | jq -r .hash)"

  if [[ -z "$sri_hash" || "$sri_hash" == "null" ]]; then
    echo "error: failed to compute hash for ${platform} from ${url}" >&2
    exit 1
  fi

  # Match the URL line (which contains the artifact filename), advance to the
  # following `hash =` line, and substitute. Layout in package.nix is one url
  # line immediately followed by one hash line per platform.
  sed -i'' -e "/${artifact}/{ n; s|hash = \"sha256-[^\"]*\"|hash = \"${sri_hash}\"|; }" "$PKG_NIX"

  if ! grep -qF "hash = \"${sri_hash}\"" "$PKG_NIX"; then
    echo "error: failed to rewrite the ${platform} hash in ${PKG_NIX}" >&2
    exit 1
  fi
  echo "  ${platform}: ${sri_hash}"
done

# Resolve the commit the v$VERSION tag points at. An annotated tag lists both the
# tag object and its peeled `^{}` commit; a lightweight tag lists only the
# commit. Prefer the peeled line.
echo "Resolving v${latest_version} tag commit..."
tag_refs="$(git ls-remote "https://github.com/${REPO}" "refs/tags/v${latest_version}^{}" "refs/tags/v${latest_version}")"
src_rev="$(printf '%s\n' "$tag_refs" | grep -F '^{}' | cut -f1 || true)"
if [[ -z "$src_rev" ]]; then
  src_rev="$(printf '%s\n' "$tag_refs" | head -1 | cut -f1)"
fi

if [[ ! "$src_rev" =~ ^[0-9a-f]{40}$ ]]; then
  echo "error: failed to resolve a commit for tag v${latest_version}" >&2
  exit 1
fi

# Source tree hash for the `skillSrc` fetchFromGitHub block. Rewrite the 40-hex
# `rev = "...";` line, advance to the following `hash =` line, and substitute.
echo "Prefetching source tree (v${latest_version} = ${src_rev})..."
src_raw="$(nix-prefetch-url --unpack "https://github.com/${REPO}/archive/${src_rev}.tar.gz")"
src_sri="$(nix hash to-sri --type sha256 "$src_raw")"

if [[ -z "$src_sri" || "$src_sri" == "null" ]]; then
  echo "error: failed to compute source-tree hash for v${latest_version}" >&2
  exit 1
fi

sed -i'' -e "/rev = \"[0-9a-f]\{40\}\";/{ s|rev = \"[0-9a-f]\{40\}\"|rev = \"${src_rev}\"|; n; s|hash = \"sha256-[^\"]*\"|hash = \"${src_sri}\"|; }" "$PKG_NIX"

if ! grep -qF "hash = \"${src_sri}\"" "$PKG_NIX"; then
  echo "error: failed to rewrite the skillSrc hash in ${PKG_NIX}" >&2
  exit 1
fi
echo "  skillSrc: ${src_rev} ${src_sri}"

# Keep the apm marketplace pin in step with the skillSrc rev: match the
# `git: schpet/linear-cli` entry, advance to its following `ref:` line, and
# substitute.
sed -i'' -e "/git: schpet\/linear-cli\$/{ n; s|ref: [0-9a-f]\{40\}|ref: ${src_rev}|; }" "$APM_YML"

if ! grep -qF "ref: ${src_rev}" "$APM_YML"; then
  echo "error: failed to rewrite the schpet/linear-cli ref in ${APM_YML}" >&2
  exit 1
fi
echo "  apm.yml ref: ${src_rev}"

echo "Updated linear-cli to ${latest_version}"
