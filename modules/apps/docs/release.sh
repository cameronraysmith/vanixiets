# release.sh - Production semantic-release runner for a monorepo package.
#
# Usage:
#   nix run .#release -- <package-path> [extra semantic-release args...]
#
# Examples:
#   nix run .#release -- packages/docs
#
# Hermetic: DOCS_NODE_MODULES (set by release.nix) points to a read-only
# node_modules tree produced by the vanixiets-docs-deps derivation. This script
# links it into the target package directory and invokes semantic-release
# directly via node_modules/.bin, bypassing any need for bun or a prior
# `bun install`.
#
# Required environment (pass through from caller; CI-only):
#   GITHUB_TOKEN - required by @semantic-release/github to publish tags/releases.

package_path="${1:?usage: release <package-path> [extra semantic-release args...]}"
shift

repo_root="$(git rev-parse --show-toplevel)"
cd "$repo_root"

if [ ! -d "$package_path" ]; then
  printf 'error: package path %q does not exist relative to %s\n' \
    "$package_path" "$repo_root" >&2
  exit 1
fi

cd "$package_path"

# Guard against clobbering a real local node_modules from a developer's
# bun install; only proceed if the slot is empty or already our symlink.
if [[ -e node_modules && ! -L node_modules ]]; then
  echo "error: $package_path/node_modules exists and is not a symlink; refusing to overwrite a local bun install" >&2
  exit 1
fi
trap 'rm -f "$PWD/node_modules"' EXIT
ln -snf "$DOCS_NODE_MODULES" node_modules

# This is a real release path: semantic-release will create a tag and publish
# a GitHub release when invoked. Use `preview-version` (dry-run) or
# `test-release` for previewing.
echo "running production semantic-release in ${package_path}..."
exec node ./node_modules/.bin/semantic-release "$@"
