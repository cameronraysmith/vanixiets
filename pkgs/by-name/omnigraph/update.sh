#!/usr/bin/env nix-shell
#!nix-shell --pure -i bash -p curl jq cacert git nix nix-prefetch-github gnused gnugrep coreutils
# shellcheck shell=bash
#
# Bumps pkgs/by-name/omnigraph to the latest upstream release: rewrites the
# version and the three per-platform archive hashes in package.nix, reading each
# hash from the release's own <asset>.sha256 file, and the hash of skillSrc, the
# tagged source tree that supplies the upstream agent skill.
# Invoked via `nix run .#update-omnigraph` (passthru.updateScript).

set -euo pipefail

owner="ModernRelay"
repo="omnigraph"

repo_root="$(git rev-parse --show-toplevel)"
pkg_nix="${repo_root}/pkgs/by-name/omnigraph/package.nix"

current_version="$(sed -n 's/^  version = "\(.*\)";$/\1/p' "$pkg_nix" | head -1)"
if [[ -z "$current_version" ]]; then
  echo "error: could not read the current version from ${pkg_nix}" >&2
  exit 1
fi

# releases/latest excludes drafts and prereleases.
tag="$(curl -fsSL \
  -H "Accept: application/vnd.github+json" \
  "https://api.github.com/repos/${owner}/${repo}/releases/latest" | jq -r '.tag_name')"
new_version="${tag#v}"
if [[ ! "$new_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "error: latest release tag is not a stable vX.Y.Z tag" >&2
  echo "observed: ${tag:-<empty>}" >&2
  exit 1
fi

if [[ "$current_version" == "$new_version" ]]; then
  echo "omnigraph is already at ${current_version}; refreshing hashes anyway"
else
  echo "Updating omnigraph: ${current_version} -> ${new_version}"
fi

sed -i'' -e "s|^  version = \"[^\"]*\";\$|  version = \"${new_version}\";|" "$pkg_nix"
grep -q "^  version = \"${new_version}\";\$" "$pkg_nix" \
  || { echo "error: version was not updated in package.nix" >&2; exit 1; }

for asset in omnigraph-linux-x86_64 omnigraph-linux-arm64 omnigraph-macos-arm64; do
  # The .sha256 asset holds `<hex digest>  <asset>.tar.gz`.
  hex="$(curl -fsSL \
    "https://github.com/${owner}/${repo}/releases/download/${tag}/${asset}.sha256" \
    | cut -d' ' -f1)"
  if [[ ! "$hex" =~ ^[0-9a-f]{64}$ ]]; then
    echo "error: ${asset}.sha256 at ${tag} does not hold a sha256 hex digest" >&2
    echo "observed: ${hex:-<empty>}" >&2
    exit 1
  fi
  sri="$(nix --extra-experimental-features nix-command \
    hash convert --hash-algo sha256 --to sri "$hex")"

  # Each url line names its asset; the hash sits on the line right after it.
  sed -i'' -e "\|/${asset}\.tar\.gz\";\$|{ n; s|^        hash = \"sha256-[^\"]*\";\$|        hash = \"${sri}\";|; }" "$pkg_nix"
  grep -A1 "/${asset}\.tar\.gz\";\$" "$pkg_nix" | grep -qF "        hash = \"${sri}\";" \
    || { echo "error: ${asset} hash was not updated in package.nix" >&2; exit 1; }

  echo "  ${asset}: ${sri}"
done

skill_sri="$(nix-prefetch-github "$owner" "$repo" --rev "$tag" | jq -r '.hash')"
if [[ ! "$skill_sri" =~ ^sha256- ]]; then
  echo "error: nix-prefetch-github did not return a hash for ${tag}" >&2
  exit 1
fi
# skillSrc's hash is the line after its `tag =` line, indented one level less
# than the archive hashes.
sed -i'' -e "/^      tag = \"v\${finalAttrs.version}\";\$/{ n; s|^      hash = \"sha256-[^\"]*\";\$|      hash = \"${skill_sri}\";|; }" "$pkg_nix"
grep -A1 "^      tag = \"v\${finalAttrs.version}\";\$" "$pkg_nix" | grep -qF "      hash = \"${skill_sri}\";" \
  || { echo "error: skillSrc hash was not updated in package.nix" >&2; exit 1; }
echo "  skillSrc: ${skill_sri}"

echo "Updated omnigraph to ${new_version}"
