#!/usr/bin/env nix-shell
#!nix-shell --pure -i bash -p curl jq cacert git nix
# shellcheck shell=bash

set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"
PKG_NIX="${REPO_ROOT}/pkgs/by-name/greptimedb-bin/package.nix"

current_version="$(sed -n 's/.*version = "\(.*\)";/\1/p' "$PKG_NIX" | head -1)"
current_dashboard="$(sed -n 's/.*dashboardVersion = "\(.*\)";/\1/p' "$PKG_NIX" | head -1)"

# GreptimeDB publishes nightlies, alphas and betas as GitHub prereleases beside
# its stable tags, and can cut a patch on an older line after a newer minor.
# Keep only published, non-prerelease bare semver tags (vMAJOR.MINOR.PATCH) and
# take the numerically highest, not the most recently created.
latest_tag="$(curl -fsSL \
  -H "Accept: application/vnd.github+json" \
  "https://api.github.com/repos/GreptimeTeam/greptimedb/releases?per_page=100" \
  | jq -r '[.[] | select(.draft == false and .prerelease == false) | .tag_name | select(test("^v[0-9]+\\.[0-9]+\\.[0-9]+$"))] | sort_by(ltrimstr("v") | split(".") | map(tonumber)) | last')"
latest_version="${latest_tag#v}"

if [[ -z "$latest_version" || "$latest_version" == "null" ]]; then
  echo "error: failed to discover a stable semver tag from GitHub releases" >&2
  exit 1
fi

if [[ "$current_version" == "$latest_version" ]]; then
  echo "greptimedb-bin is already at version ${current_version}; refreshing hash and dashboard version anyway"
else
  echo "Updating greptimedb-bin: ${current_version} -> ${latest_version}"
  sed -i'' -e "s/version = \"${current_version}\"/version = \"${latest_version}\"/" "$PKG_NIX"
fi

asset="greptime-linux-amd64-v${latest_version}.tar.gz"
url="https://github.com/GreptimeTeam/greptimedb/releases/download/v${latest_version}/${asset}"

echo "Prefetching x86_64-linux (${asset})..."
sri_hash="$(nix store prefetch-file --json --hash-type sha256 "$url" | jq -r .hash)"

if [[ -z "$sri_hash" || "$sri_hash" == "null" ]]; then
  echo "error: failed to compute hash for x86_64-linux from ${url}" >&2
  exit 1
fi

# The url line names the asset as greptime-linux-amd64-v${finalAttrs.version};
# advance to the immediately-following `hash =` line and substitute.
sed -i'' -e "/greptime-linux-amd64-v/{ n; s|hash = \"sha256-[^\"]*\"|hash = \"${sri_hash}\"|; }" "$PKG_NIX"

echo "  x86_64-linux: ${sri_hash}"

# The release embeds the dashboard named by src/servers/dashboard/VERSION at its
# tag (for example "v0.13.13"); record it without the leading v.
dashboard_version="$(curl -fsSL \
  "https://raw.githubusercontent.com/GreptimeTeam/greptimedb/v${latest_version}/src/servers/dashboard/VERSION" \
  | tr -d '[:space:]')"
dashboard_version="${dashboard_version#v}"

if ! [[ "$dashboard_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "error: unexpected dashboard VERSION '${dashboard_version}' at v${latest_version}" >&2
  exit 1
fi

sed -i'' -e "s/dashboardVersion = \"[^\"]*\"/dashboardVersion = \"${dashboard_version}\"/" "$PKG_NIX"

if [[ "$current_dashboard" != "$dashboard_version" ]]; then
  echo "  dashboardVersion: ${current_dashboard} -> ${dashboard_version} (re-check the percli lint schema pin)"
else
  echo "  dashboardVersion: ${dashboard_version}"
fi

echo "Updated greptimedb-bin to ${latest_version}"
