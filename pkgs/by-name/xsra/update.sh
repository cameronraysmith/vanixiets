#!/usr/bin/env nix-shell
#!nix-shell --pure -i bash -p curl jq cacert git nix-prefetch-github cargo rustc pkg-config cmake perl gnumake
# shellcheck shell=bash
#
# Bumps pkgs/by-name/xsra to the latest upstream release: rewrites the
# version and src hash in package.nix and regenerates Cargo.lock.
# Invoked via `nix run .#update-xsra` (passthru.updateScript).

set -euo pipefail

owner="ArcInstitute"
repo="xsra"

repo_root="$(git rev-parse --show-toplevel)"
pkg_dir="${repo_root}/pkgs/by-name/xsra"
pkg_nix="${pkg_dir}/package.nix"

current_version="$(sed -n 's/.*version = "\(.*\)";/\1/p' "$pkg_nix" | head -1)"

latest_tag="$(curl -fsSL \
  -H "Accept: application/vnd.github+json" \
  "https://api.github.com/repos/${owner}/${repo}/releases/latest" \
  | jq -r '.tag_name')"
latest_version="${latest_tag#"${repo}"-}"

if [[ -z "$latest_version" || "$latest_version" == "null" ]]; then
  echo "error: could not resolve latest release tag from the GitHub API" >&2
  exit 1
fi

if [[ "$current_version" == "$latest_version" ]]; then
  echo "xsra is already at version ${current_version}"
  exit 0
fi

echo "Updating xsra: ${current_version} -> ${latest_version}"

# Compute the src hash with the tool that mirrors fetchFromGitHub exactly,
# so the value matches what the derivation expects without a build round-trip.
echo "Computing source hash for tag ${latest_tag}..."
new_sri="$(nix-prefetch-github "$owner" "$repo" --rev "$latest_tag" | jq -r '.hash')"
if [[ -z "$new_sri" || "$new_sri" == "null" ]]; then
  echo "error: nix-prefetch-github did not return a hash" >&2
  exit 1
fi

# Regenerate Cargo.lock from the new source.
workdir="$(mktemp -d)"
trap 'rm -rf "$workdir"' EXIT

echo "Fetching source for tag ${latest_tag}..."
curl -fsSL \
  "https://github.com/${owner}/${repo}/archive/refs/tags/${latest_tag}.tar.gz" \
  | tar -xz -C "$workdir" --strip-components=1

echo "Generating Cargo.lock..."
cargo generate-lockfile --manifest-path "${workdir}/Cargo.toml"
cp "${workdir}/Cargo.lock" "${pkg_dir}/Cargo.lock"

# Rewrite package.nix.
sed -i'' -e "s/version = \"${current_version}\"/version = \"${latest_version}\"/" "$pkg_nix"
sed -i'' -e "s|hash = \"sha256-.*\"|hash = \"${new_sri}\"|" "$pkg_nix"

# Fail loudly if either rewrite did not take, rather than reporting success on a no-op.
grep -q "version = \"${latest_version}\"" "$pkg_nix" \
  || { echo "error: version was not updated in package.nix" >&2; exit 1; }
grep -q "hash = \"${new_sri}\"" "$pkg_nix" \
  || { echo "error: hash was not updated in package.nix" >&2; exit 1; }

echo "Updated xsra to ${latest_version}"
echo "  src hash: ${new_sri}"
echo "  Cargo.lock regenerated"
