#!/usr/bin/env bash
# shellcheck shell=bash
# release.sh - Production semantic-release runner for a monorepo package.
# See `usage()` for caller-facing usage; this header documents the env-var
# contract only.
#
# Required (secret, production path only — not --dry-run):
#   GITHUB_TOKEN         @semantic-release/github auth for tag push and
#                        release publish. Filtered-out plugin list under
#                        --dry-run means no token is consulted in that mode.
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
# Defaults applied by the effect preamble:
#   GIT_AUTHOR_NAME      / GIT_AUTHOR_EMAIL    (semantic-release@vanixiets.local)
#   GIT_COMMITTER_NAME   / GIT_COMMITTER_EMAIL (semantic-release@vanixiets.local)
#   GIT_USER_NAME / GIT_USER_EMAIL — transitional aliases that seed the
#                        quartet when the GIT_AUTHOR_* / GIT_COMMITTER_*
#                        forms are unset.

set -euo pipefail

: "${DOCS_NODE_MODULES:?DOCS_NODE_MODULES not set; release.nix must expose vanixiets-docs-deps via runtimeEnv}"

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
  GITHUB_TOKEN, DOCS_NODE_MODULES, RELEASE_REPO_ROOT, CI,
  GIT_AUTHOR_NAME, GIT_AUTHOR_EMAIL, GIT_COMMITTER_NAME, GIT_COMMITTER_EMAIL,
  GIT_USER_NAME, GIT_USER_EMAIL (see release.sh header for details).
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

# Repo-root resolution: env-first, then error-tolerant git fallback, then
# pwd. Required because the buildbot-effects bwrap sandbox does not bind-
# mount the working tree's .git, so `git rev-parse --show-toplevel` would
# fail with `fatal: not a git repository` (exit 128) and abort the script.
# The effect preamble sets RELEASE_REPO_ROOT="$PWD" so this branch resolves
# without invoking git. Local-shell and GHA paths set RELEASE_REPO_ROOT
# to empty, exercising the git fallback against the live worktree.
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
# write. Transitional aliases GIT_USER_NAME/GIT_USER_EMAIL seed the quartet
# when the new vars are unset, preserving existing local/GHA caller
# behaviour. Each export uses parameter-expansion default chaining so a
# pre-set value (effect preamble or caller env) is preserved unchanged.
export GIT_AUTHOR_NAME="${GIT_AUTHOR_NAME:-${GIT_USER_NAME:-semantic-release}}"
export GIT_AUTHOR_EMAIL="${GIT_AUTHOR_EMAIL:-${GIT_USER_EMAIL:-semantic-release@vanixiets.local}}"
export GIT_COMMITTER_NAME="${GIT_COMMITTER_NAME:-${GIT_USER_NAME:-semantic-release}}"
export GIT_COMMITTER_EMAIL="${GIT_COMMITTER_EMAIL:-${GIT_USER_EMAIL:-semantic-release@vanixiets.local}}"

cd "$package_path"

# Production-path contract guard: fail fast on missing GITHUB_TOKEN
# BEFORE any node_modules mutation so the error points at the contract
# rather than at an opaque state-mutation side effect. Gated on dry_run.
if [ "$dry_run" -ne 1 ]; then
  : "${GITHUB_TOKEN:?GITHUB_TOKEN is required for production semantic-release (see release.sh header for caller mechanisms; not needed for --dry-run)}"
fi

# Guard node_modules slot against clobbering a developer's real install.
# Production (non-dry-run): strict — refuse to overwrite a real node_modules
# directory. Only an empty slot or a pre-existing symlink is safe to clobber.
# Dry-run: proceed safely via two strategies that NEVER mutate the
# developer's real install in place:
#   (b) reuse the existing node_modules directly if it already contains a
#       usable semantic-release binary (common when the dev ran `bun install`
#       to completion), or
#   (a) move the existing node_modules aside to a tempdir, symlink
#       DOCS_NODE_MODULES in its place for the duration of the run, and
#       atomically restore the original on EXIT (including on error/SIGINT).
nm_exists_real=0
if [[ -e node_modules && ! -L node_modules ]]; then
  nm_exists_real=1
fi

if [ "$nm_exists_real" -eq 1 ] && [ "$dry_run" -ne 1 ]; then
  echo "error: $package_path/node_modules exists and is not a symlink; refusing to overwrite a local bun install" >&2
  exit 1
fi

if [ "$nm_exists_real" -eq 1 ] && [ -x node_modules/.bin/semantic-release ]; then
  # Dry-run strategy (b): reuse existing node_modules in place.
  echo "dry-run: reusing existing node_modules (.bin/semantic-release present)" >&2
elif [ "$nm_exists_real" -eq 1 ]; then
  # Dry-run strategy (a): move existing node_modules aside, symlink for the
  # duration of the run, restore atomically on exit.
  backup_dir="$(mktemp -d)"
  echo "dry-run: moving existing node_modules to ${backup_dir} (restored on exit)" >&2
  mv node_modules "${backup_dir}/node_modules"
  # shellcheck disable=SC2064
  trap "rm -f '${PWD}/node_modules'; mv '${backup_dir}/node_modules' '${PWD}/node_modules' 2>/dev/null || true; rmdir '${backup_dir}' 2>/dev/null || true" EXIT
  ln -snf "$DOCS_NODE_MODULES" node_modules
else
  # Slot is empty or already a symlink — safe to (re)link.
  trap 'rm -f "$PWD/node_modules"' EXIT
  ln -snf "$DOCS_NODE_MODULES" node_modules
fi

if [ "$dry_run" -eq 1 ]; then
  # Filter @semantic-release/github so GITHUB_TOKEN is not required for
  # preview; safe under --dry-run (prepare/publish steps are no-ops).
  # Mirrors preview-version.sh plus changelog + major-tag plugins from
  # the package.json "release" block.
  plugins="@semantic-release/commit-analyzer,@semantic-release/release-notes-generator,@semantic-release/changelog,semantic-release-major-tag"
  echo "running semantic-release (dry-run, no GitHub plugin) in ${package_path}..."
  node ./node_modules/.bin/semantic-release \
    --dry-run \
    --no-ci \
    --plugins "$plugins" \
    "${extra_args[@]}"
else
  # GITHUB_TOKEN is enforced via the early :? guard above (placed before
  # node_modules setup so failure modes are contract-first).
  echo "running production semantic-release in ${package_path}..."
  node ./node_modules/.bin/semantic-release "${extra_args[@]}"
fi
