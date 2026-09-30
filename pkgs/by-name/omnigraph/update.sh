#!/usr/bin/env nix-shell
#!nix-shell --pure -i bash -p curl jq cacert git nix-prefetch-github gnused coreutils
# shellcheck shell=bash
#
# Bumps pkgs/by-name/omnigraph to the latest upstream release: rewrites the
# version, rev (the peeled commit of the release tag) and src hash in
# package.nix, and blanks cargoHash.
# Invoked via `nix run .#update-omnigraph` (passthru.updateScript).
#
# rev stays a commit sha rather than the tag name because package.nix stamps
# OMNIGRAPH_SOURCE_VERSION from src.rev, which upstream sets to a commit sha.

set -euo pipefail

owner="ModernRelay"
repo="omnigraph"
fake_sri="sha256-0000000000000000000000000000000000000000000="

repo_root="$(git rev-parse --show-toplevel)"
pkg_nix="${repo_root}/pkgs/by-name/omnigraph/package.nix"

current_version="$(sed -n 's/^  version = "\(.*\)";$/\1/p' "$pkg_nix" | head -1)"
current_rev="$(sed -n 's/^    rev = "\(.*\)";$/\1/p' "$pkg_nix" | head -1)"
if [[ -z "$current_version" || -z "$current_rev" ]]; then
  echo "error: could not read the current version and rev from ${pkg_nix}" >&2
  exit 1
fi

release_json="$(curl -fsSL \
  -H "Accept: application/vnd.github+json" \
  "https://api.github.com/repos/${owner}/${repo}/releases/latest")"

tag="$(printf '%s' "$release_json" | jq -r '.tag_name')"
new_version="${tag#v}"
if [[ ! "$new_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "error: latest release tag is not a stable vX.Y.Z tag" >&2
  echo "observed: ${tag:-<empty>}" >&2
  exit 1
fi

# The commits endpoint peels annotated tags to the commit they point at.
new_rev="$(curl -fsSL \
  -H "Accept: application/vnd.github+json" \
  "https://api.github.com/repos/${owner}/${repo}/commits/${tag}" | jq -r '.sha')"
if [[ ! "$new_rev" =~ ^[0-9a-f]{40}$ ]]; then
  echo "error: could not resolve tag ${tag} to a commit sha" >&2
  exit 1
fi

if [[ "$current_rev" == "$new_rev" ]]; then
  echo "omnigraph is already at rev ${current_rev} (${current_version})"
  exit 0
fi

echo "Updating omnigraph: ${current_version} -> ${new_version}"

echo "Computing source hash for rev ${new_rev}..."
new_sri="$(nix-prefetch-github "$owner" "$repo" --rev "$new_rev" | jq -r '.hash')"
if [[ -z "$new_sri" || "$new_sri" == "null" ]]; then
  echo "error: nix-prefetch-github did not return a hash" >&2
  exit 1
fi

# package.nix carries two SRI lines. Anchor each rewrite on its indentation so
# the src hash and cargoHash cannot be confused.
sed -i'' -e "s|^  version = \"[^\"]*\";\$|  version = \"${new_version}\";|" "$pkg_nix"
sed -i'' -e "s|^    rev = \"[0-9a-f]\{40\}\";\$|    rev = \"${new_rev}\";|" "$pkg_nix"
sed -i'' -e "s|^  # rev is the v[0-9.]* tag peel|  # rev is the ${tag} tag peel|" "$pkg_nix"
sed -i'' -e "s|^    hash = \"sha256-[^\"]*\";\$|    hash = \"${new_sri}\";|" "$pkg_nix"
sed -i'' -e "s|^  cargoHash = \"sha256-[^\"]*\";\$|  cargoHash = \"${fake_sri}\";|" "$pkg_nix"

# Fail loudly if any rewrite did not take, rather than reporting success on a no-op.
grep -q "^  version = \"${new_version}\";\$" "$pkg_nix" \
  || { echo "error: version was not updated in package.nix" >&2; exit 1; }
grep -q "^    rev = \"${new_rev}\";\$" "$pkg_nix" \
  || { echo "error: rev was not updated in package.nix" >&2; exit 1; }
grep -q "^    hash = \"${new_sri}\";\$" "$pkg_nix" \
  || { echo "error: src hash was not updated in package.nix" >&2; exit 1; }
grep -q "^  cargoHash = \"${fake_sri}\";\$" "$pkg_nix" \
  || { echo "error: cargoHash was not reset in package.nix" >&2; exit 1; }

echo "Updated omnigraph to ${new_version}"
echo "  rev:      ${new_rev}"
echo "  src hash: ${new_sri}"
echo
echo "cargoHash was reset to the placeholder and must be recomputed:"
echo "  nix build .#omnigraph.cargoDeps"
echo "then copy the reported got: hash into cargoHash."
