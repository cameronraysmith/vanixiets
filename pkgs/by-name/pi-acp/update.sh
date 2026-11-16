#!/usr/bin/env nix-shell
#!nix-shell --pure -i bash -p curl jq cacert git nix
# shellcheck shell=bash

# Update pkgs/by-name/pi-acp to the latest npm release of pi-acp:
#   1. resolve the version from the registry's latest dist-tag (upstream tags
#      each release v<version> on GitHub, which is what the package builds),
#   2. write manifest.json and the GitHub source hash into package.nix,
#   3. run one build cycle to learn the new npmDepsHash from the mismatch
#      (a no-op when the dependency closure is unchanged), then a verifying
#      build. That build also applies atomic-sqlite-sessions.patch and runs
#      upstream's tests; a patch that no longer applies must be rebased by
#      hand (see package.nix for what it does).

set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"
PKG_DIR="${REPO_ROOT}/pkgs/by-name/pi-acp"

version="$(curl -fsSL "https://registry.npmjs.org/pi-acp" | jq -r '.["dist-tags"].latest')"
[ -n "$version" ] || { echo "error: empty latest version" >&2; exit 1; }
echo "updating pi-acp to ${version}"

jq -n --arg version "$version" '{version: $version}' > "$PKG_DIR/manifest.json"

src_hash="$(nix flake prefetch --json "github:svkozak/pi-acp/v${version}" | jq -r .hash)"
sed -i -E "s|(hash = )\"sha256-[A-Za-z0-9+/=]+\";|\1\"${src_hash}\";|" "$PKG_DIR/package.nix"
echo "wrote src hash ${src_hash}"

# npmDepsHash: a bumped closure makes the committed hash mismatch; the error
# carries the correct value. An unchanged closure builds clean and skips this.
got="$(nix build --no-link "$REPO_ROOT#pi-acp" 2>&1 || true)"
got="$(printf '%s' "$got" | grep -oE 'got: +sha256-[A-Za-z0-9+/=]+' | head -1 | tr -d ' ' | sed 's/^got://' || true)"
if [ -n "$got" ]; then
  sed -i -E "s|(npmDepsHash = )\"sha256-[A-Za-z0-9+/=]+\";|\1\"${got}\";|" "$PKG_DIR/package.nix"
  echo "wrote npmDepsHash ${got}"
fi

echo "verifying build"
nix build -L --no-link "$REPO_ROOT#pi-acp"
echo "pi-acp updated to ${version}; run the checks before pushing"
