#!/usr/bin/env nix-shell
#!nix-shell -i bash -p curl jq cacert git nix gnused
# shellcheck shell=bash

set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"
PKG_NIX="${REPO_ROOT}/pkgs/by-name/langfuse-cli/package.nix"

current_version="$(sed -n 's/.*version = "\(.*\)";/\1/p' "$PKG_NIX" | head -1)"
latest_version="$(curl -fsSL "https://registry.npmjs.org/@langfuse/cli/latest" | jq -r '.version')"

if [[ "$current_version" == "$latest_version" ]]; then
  echo "langfuse-cli is already at version ${current_version}"
  exit 0
fi

echo "Updating langfuse-cli: ${current_version} -> ${latest_version}"
new_sri="$(nix store prefetch-file --json \
  "https://registry.npmjs.org/@langfuse/cli/-/cli-${latest_version}.tgz" | jq -r .hash)"

sed -i'' -e "s/version = \"${current_version}\"/version = \"${latest_version}\"/" "$PKG_NIX"
sed -i'' -e "s|hash = \"sha256-[A-Za-z0-9+/=]*\"|hash = \"${new_sri}\"|" "$PKG_NIX"

echo "Review the allow-list in modules/apps/langfuse-query.sh against the new contract:"
echo "  nix build .#checks.x86_64-linux.langfuse-query"
