#!/usr/bin/env bash
# shellcheck shell=bash
# release.sh - semantic-release runner for a monorepo package.
# See `usage()` for caller-facing usage; this header documents the env-var
# contract only.
#
# There is one plugin set: the package.json "release" block. Arguments after
# `--` pass through to semantic-release, so `-- --dry-run` rehearses that same
# plugin set with semantic-release's own dry run.
#
# Required (secret):
#   GITHUB_TOKEN         @semantic-release/github auth for tag push and
#                        release publish; its verifyConditions step needs it
#                        under --dry-run too.
# Required (config, injected by release.nix runtimeEnv):
#   DOCS_NODE_MODULES    vanixiets-docs-deps node_modules tree hosting
#                        node_modules/.bin/semantic-release.
# Optional (CI-mode signalling; required by env-ci on the effect path):
#   CI                   "true" tells semantic-release / env-ci that the
#                        run is non-interactive CI. Required in the
#                        buildbot-effects bwrap sandbox (not a recognised
#                        CI provider; semantic-release would otherwise
#                        abort `running on a CI environment is required`).
# Optional (repo-root resolution; env-first with errexit-tolerant fallback):
#   RELEASE_REPO_ROOT    absolute path to the working tree's repo root.
#                        Required in the bwrap sandbox (no .git bind-mount;
#                        `git rev-parse --show-toplevel` would fail).
#                        Fallback: git rev-parse --show-toplevel || pwd.
# Optional (git identity; env-first, NO .git/config writes — bwrap mounts
# /nix/store ro-bind, so `git config user.email …` would fail to lock
# .git/config). git honours these natively without any config write.
# Defaults applied by the release-packages program:
#   GIT_AUTHOR_NAME      / GIT_AUTHOR_EMAIL    (semantic-release@vanixiets.local)
#   GIT_COMMITTER_NAME   / GIT_COMMITTER_EMAIL (semantic-release@vanixiets.local)

set -euo pipefail

: "${DOCS_NODE_MODULES:?DOCS_NODE_MODULES not set; release.nix must expose vanixiets-docs-deps via runtimeEnv}"

usage() {
  cat <<'EOF'
usage: release <package-path> [-- extra semantic-release args]
       release info [<package-path>]
       release --help

Run semantic-release against a monorepo package, or extract release info.

Subcommands:
  (default)  Run semantic-release for <package-path> with the package.json
             plugin set. Arguments after `--` pass through to
             semantic-release, e.g. `release packages/docs -- --dry-run`.
  info       Emit release info JSON (version, tag, released) from latest
             git tag matching the package.

Flags:
  --help     Print this usage and exit.

Environment:
  GITHUB_TOKEN, DOCS_NODE_MODULES, RELEASE_REPO_ROOT, CI,
  GIT_AUTHOR_NAME, GIT_AUTHOR_EMAIL, GIT_COMMITTER_NAME, GIT_COMMITTER_EMAIL
  (see release.sh header for details).
EOF
}

emit_release_info() {
  local package_path="${1:-}"
  local latest_tag=""
  local version=""

  if [ -n "$package_path" ]; then
    # Monorepo tag convention (semantic-release-monorepo):
    # <package.json name>-vX.Y.Z, e.g. @vanixiets/docs-v0.7.0.
    local repo_root package_name
    repo_root="${RELEASE_REPO_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
    package_name=$(jq -r .name "${repo_root}/${package_path}/package.json")
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

package_path=""
extra_args=()

while [ $# -gt 0 ]; do
  case "$1" in
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

# Repo-root resolution: env-first, then error-tolerant git fallback, then
# pwd. Required because the buildbot-effects bwrap sandbox does not bind-
# mount the working tree's .git, so `git rev-parse --show-toplevel` would
# fail with `fatal: not a git repository` (exit 128) and abort the script.
# release-packages sets RELEASE_REPO_ROOT="$PWD" so this branch resolves
# without invoking git. Local-shell callers leave RELEASE_REPO_ROOT unset,
# exercising the git fallback against the live worktree.
repo_root="${RELEASE_REPO_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
cd "$repo_root"

if [ ! -d "$package_path" ]; then
  printf 'error: package path %q does not exist relative to %s\n' \
    "$package_path" "$repo_root" >&2
  exit 1
fi

# Git identity: exported via GIT_AUTHOR_* / GIT_COMMITTER_* env vars rather
# than written to .git/config. Required because the buildbot-effects bwrap
# sandbox renders .git read-only (mounts /nix/store ro-bind only) and
# `git config user.email "…"` would fail with `error: could not lock config
# file .git/config`. git honours these env vars natively without any config
# write. Each export uses parameter-expansion default chaining so a pre-set
# value (release-packages or caller env) is preserved unchanged.
export GIT_AUTHOR_NAME="${GIT_AUTHOR_NAME:-semantic-release}"
export GIT_AUTHOR_EMAIL="${GIT_AUTHOR_EMAIL:-semantic-release@vanixiets.local}"
export GIT_COMMITTER_NAME="${GIT_COMMITTER_NAME:-semantic-release}"
export GIT_COMMITTER_EMAIL="${GIT_COMMITTER_EMAIL:-semantic-release@vanixiets.local}"

cd "$package_path"

# Contract guard: fail fast on missing GITHUB_TOKEN BEFORE any node_modules
# mutation so the error points at the contract rather than at an opaque
# state-mutation side effect.
: "${GITHUB_TOKEN:?GITHUB_TOKEN is required by @semantic-release/github (see release.sh header for caller mechanisms)}"

# Guard node_modules slot against clobbering a developer's real install.
# Only an empty slot or a pre-existing symlink is safe to clobber.
if [[ -e node_modules && ! -L node_modules ]]; then
  echo "error: $package_path/node_modules exists and is not a symlink; refusing to overwrite a local bun install" >&2
  exit 1
fi

trap 'rm -f "$PWD/node_modules"' EXIT
ln -snf "$DOCS_NODE_MODULES" node_modules

echo "running semantic-release in ${package_path}..."
node ./node_modules/.bin/semantic-release "${extra_args[@]}"
