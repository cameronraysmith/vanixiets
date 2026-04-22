#!/usr/bin/env bash
# shellcheck shell=bash
# release.sh - Production semantic-release runner for a monorepo package.
#
# Usage:
#   release <package-path> [--dry-run] [-- extra semantic-release args]
#   release info [<package-path>]
#   release --help
#
# Subcommands:
#   (default)  Run semantic-release against <package-path>. Tag/publish on
#              success; when --dry-run is passed, runs a preview without
#              the @semantic-release/github plugin so GITHUB_TOKEN is not
#              required.
#   info       Emit a JSON object describing the most recent release for
#              <package-path> (or the repo root when omitted). Fields:
#                { "version": "X.Y.Z", "tag": "pkg-vX.Y.Z", "released": true }
#              On no prior release: { "version": "unknown", "tag": "",
#              "released": false }.
#
# Flags:
#   --dry-run  Pass --dry-run and --no-ci to semantic-release and strip the
#              @semantic-release/github plugin from the invocation plugin
#              list. Mirrors the preview-version trick (no GITHUB_TOKEN
#              needed).
#   --help     Print this usage and exit 0.
#
# Environment:
#   GITHUB_TOKEN       Required by @semantic-release/github for production
#                      releases. Not consulted for --dry-run.
#   SOPS_AGE_KEY       Passthrough for semantic-release hooks that may
#                      decrypt secrets via sops. Not used directly.
#   DOCS_NODE_MODULES  Hermetic node_modules tree injected by release.nix.
#                      Must point at a directory containing a resolved
#                      node_modules/.bin/semantic-release.
#   GIT_USER_NAME,     Optional overrides for the git identity used by
#   GIT_USER_EMAIL     semantic-release commit/tag operations; defaults
#                      to `semantic-release` / `semantic-release@vanixiets.local`.

set -euo pipefail

usage() {
  cat <<'EOF'
usage: release <package-path> [--dry-run] [-- extra semantic-release args]
       release info [<package-path>]
       release --help

Run semantic-release against a monorepo package, or extract release info.

Subcommands:
  (default)  Run semantic-release for <package-path>.
  info       Emit release info JSON (version, tag, released) from latest
             git tag matching the package.

Flags:
  --dry-run  Dry-run (skips @semantic-release/github; no GITHUB_TOKEN needed).
  --help     Print this usage and exit.

Environment:
  GITHUB_TOKEN, SOPS_AGE_KEY, DOCS_NODE_MODULES, GIT_USER_NAME,
  GIT_USER_EMAIL (see release.sh header for details).
EOF
}

emit_release_info() {
  local package_path="${1:-}"
  local latest_tag=""
  local version=""

  if [ -n "$package_path" ]; then
    # Monorepo tag convention (semantic-release-monorepo): <pkg-name>-vX.Y.Z
    local package_name
    package_name=$(basename "$package_path")
    latest_tag=$(git tag --list "${package_name}-v*" --sort=-v:refname 2>/dev/null | head -1 || true)
  else
    latest_tag=$(git describe --tags --abbrev=0 2>/dev/null || true)
  fi

  if [ -n "$latest_tag" ]; then
    version=$(printf '%s\n' "$latest_tag" \
      | grep -oE '[0-9]+\.[0-9]+\.[0-9]+(-[a-zA-Z]+\.[0-9]+)?' \
      | head -1 || true)
    if [ -z "$version" ]; then
      version="unknown"
    fi
    jq -cn \
      --arg v "$version" \
      --arg t "$latest_tag" \
      '{version: $v, tag: $t, released: true}'
  else
    jq -cn '{version: "unknown", tag: "", released: false}'
  fi
}

# Handle top-level dispatch: --help, info subcommand, or fall through
# to the default "run semantic-release" mode.
if [ $# -eq 0 ]; then
  usage >&2
  exit 2
fi

case "$1" in
  -h|--help)
    usage
    exit 0
    ;;
  info)
    shift
    emit_release_info "${1:-}"
    exit 0
    ;;
esac

# Default mode: semantic-release runner.
# Parse positional arg + --dry-run flag; forward remaining args through to
# node ./node_modules/.bin/semantic-release.
dry_run=0
package_path=""
extra_args=()

while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run)
      dry_run=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    --)
      shift
      extra_args+=("$@")
      break
      ;;
    -*)
      extra_args+=("$1")
      shift
      ;;
    *)
      if [ -z "$package_path" ]; then
        package_path="$1"
      else
        extra_args+=("$1")
      fi
      shift
      ;;
  esac
done

if [ -z "$package_path" ]; then
  echo "error: missing required <package-path>" >&2
  usage >&2
  exit 2
fi

repo_root="$(git rev-parse --show-toplevel)"
cd "$repo_root"

if [ ! -d "$package_path" ]; then
  printf 'error: package path %q does not exist relative to %s\n' \
    "$package_path" "$repo_root" >&2
  exit 1
fi

# Configure a git identity if none is present so semantic-release can
# create tags/commits without a separate setup step. A pre-configured
# identity (e.g. from the caller's ~/.gitconfig) is preserved.
if [ -z "$(git config user.email 2>/dev/null || true)" ]; then
  git config user.email "${GIT_USER_EMAIL:-semantic-release@vanixiets.local}"
fi
if [ -z "$(git config user.name 2>/dev/null || true)" ]; then
  git config user.name "${GIT_USER_NAME:-semantic-release}"
fi

cd "$package_path"

# Guard node_modules slot against clobbering a developer's real install.
if [[ -e node_modules && ! -L node_modules ]]; then
  echo "error: $package_path/node_modules exists and is not a symlink; refusing to overwrite a local bun install" >&2
  exit 1
fi
trap 'rm -f "$PWD/node_modules"' EXIT
ln -snf "$DOCS_NODE_MODULES" node_modules

if [ "$dry_run" -eq 1 ]; then
  # Filter @semantic-release/github so GITHUB_TOKEN is not required for
  # a preview. Mirrors the plugin list used by preview-version.sh plus
  # the changelog + major-tag plugins that the package.json "release"
  # block declares (still safe under --dry-run: prepare/publish steps
  # are no-ops in dry-run mode).
  plugins="@semantic-release/commit-analyzer,@semantic-release/release-notes-generator,@semantic-release/changelog,semantic-release-major-tag"
  echo "running semantic-release (dry-run, no GitHub plugin) in ${package_path}..."
  node ./node_modules/.bin/semantic-release \
    --dry-run \
    --no-ci \
    --plugins "$plugins" \
    "${extra_args[@]}"
else
  # Production release path: semantic-release will create a tag and
  # publish a GitHub release when invoked. GITHUB_TOKEN is required.
  echo "running production semantic-release in ${package_path}..."
  node ./node_modules/.bin/semantic-release "${extra_args[@]}"
fi
