# release.sh - Production semantic-release runner for a monorepo package.
#
# Usage:
#   nix run .#release -- <package-path> [extra semantic-release args...]
#
# Examples:
#   nix run .#release -- packages/docs
#
# Mirrors the body of the `release-package` recipe in the repository's
# justfile (production branch; dry_run=false), but without the `cd
# packages/{{package}}` shorthand — the caller supplies a full package path
# relative to the repository root so this wrapper is usable for any monorepo
# package, not just those rooted at packages/.
#
# Runtime dependencies (bun, nodejs, git) are provided on PATH via the
# wrapping writeShellApplication; no `nix develop` prefix is required.
#
# Required environment (pass through from caller; CI-only):
#   GITHUB_TOKEN - required by @semantic-release/github to publish tags/releases.
#
# The caller must have already populated node_modules/ via `bun install`
# before invoking this app.

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

# This is a real release path: semantic-release will create a tag and publish
# a GitHub release when invoked. Use `preview-version` (dry-run) or
# `test-release` for previewing.
echo "running production semantic-release in ${package_path}..."
exec bun run release "$@"
