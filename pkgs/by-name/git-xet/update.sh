#!/usr/bin/env nix-shell
#!nix-shell --pure -i bash -p curl jq cacert git nix
# shellcheck shell=bash

set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"
PKG_NIX="${REPO_ROOT}/pkgs/by-name/git-xet/package.nix"

current_version="$(sed -n 's/.*version = "\(.*\)";/\1/p' "$PKG_NIX" | head -1)"

# Filter for git-xet-v* tags (monorepo has separate hf-xet v* tags)
latest_tag="$(curl -fsSL \
  -H "Accept: application/vnd.github+json" \
  "https://api.github.com/repos/huggingface/xet-core/releases" \
  | jq -r '[.[] | select(.tag_name | startswith("git-xet-v"))] | .[0].tag_name')"
latest_version="${latest_tag#git-xet-v}"

if [[ "$current_version" == "$latest_version" ]]; then
  echo "git-xet is already at version ${current_version}"
  exit 0
fi

echo "Updating git-xet: ${current_version} -> ${latest_version}"

# Update version string
sed -i'' -e "s/version = \"${current_version}\"/version = \"${latest_version}\"/" "$PKG_NIX"

# Platform map: nix system -> release archive name
declare -A platform_map=(
  ["x86_64-linux"]="git-xet-linux-x86_64"
  ["aarch64-linux"]="git-xet-linux-aarch64"
  ["x86_64-darwin"]="git-xet-macos-x86_64"
  ["aarch64-darwin"]="git-xet-macos-aarch64"
)

# Known-wrong but valid SRI hash to trigger fetchzip hash mismatch errors.
# An empty hash may not produce the "got:" diagnostic we need to parse.
BOGUS_HASH="sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="

tmplog="$(mktemp)"
trap 'rm -f "$tmplog"' EXIT

for platform in "${!platform_map[@]}"; do
  archive="${platform_map[$platform]}"

  # Set bogus hash for this platform so fetchzip reports the correct one
  sed -i'' -e "/${archive}/{ n; s|hash = \"sha256-[^\"]*\"|hash = \"${BOGUS_HASH}\"|; }" "$PKG_NIX"

  echo "Computing fetchzip hash for ${platform}..."
  # nix build output goes to temp file; show download progress on stderr
  nix build --impure --no-link --expr "
    (builtins.getFlake \"${REPO_ROOT}\").packages.${platform}.git-xet.passthru.sources.\"${platform}\"
  " > "$tmplog" 2>&1 || true

  sri_hash="$(sed -n 's/.*got: *//p' "$tmplog" | tr -d '[:space:]')"

  if [[ -z "$sri_hash" ]]; then
    echo "error: failed to compute hash for ${platform}" >&2
    echo "nix output:" >&2
    cat "$tmplog" >&2
    exit 1
  fi

  sed -i'' -e "/${archive}/{ n; s|hash = \"${BOGUS_HASH}\"|hash = \"${sri_hash}\"|; }" "$PKG_NIX"

  echo "  ${platform}: ${sri_hash}"
done

echo "Updated git-xet to ${latest_version}"
