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
# Env-var contract (per ADR-002 / env-var-contract-design.md §2.3):
#   Required (secret, production path only — not --dry-run):
#     GITHUB_TOKEN          @semantic-release/github auth for tag push and
#                           release publish. Filtered-out plugin list under
#                           --dry-run means no token is consulted in that mode.
#   Required (config, injected by release.nix runtimeEnv):
#     DOCS_NODE_MODULES     vanixiets-docs-deps node_modules tree hosting
#                           node_modules/.bin/semantic-release.
#   Optional (all modes):
#     SOPS_AGE_KEY          reserved passthrough for sops-decrypt hooks
#                           (no consumer in the current tree; declared but
#                           NOT enforced via :? guard — see ADR-002, which
#                           REJECTS SOPS_AGE_KEY as a general pattern).
#     GIT_USER_NAME         git identity; default: semantic-release
#     GIT_USER_EMAIL        git identity; default: semantic-release@vanixiets.local
#
#   Caller mechanisms:
#     - Local dev dry-run:  `nix run .#release -- packages/<pkg> --dry-run`
#                           needs no secret env (plugin filter strips github)
#     - Local dev prod:     caller-side sops wrapper (decrypt
#                           secrets/shared.yaml before the nix run) OR
#                           direnv dotenv (.envrc `dotenv` + .env)
#     - GHA env:            step `env:` block populates GITHUB_TOKEN from
#                           the repo secrets (package-release.yaml)
#     - M4 effect:          production-release-packages effect preamble
#                           extracts GITHUB_TOKEN from HERCULES_CI_SECRETS_JSON
#                           and exports before invoking the app program path
#
# Secret passing rule (per ADR-002): NO secrets are passed as CLI flags.
# Authentication flows exclusively through the inherited environment.

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

# Production-path env-var contract guard: fail fast on missing GITHUB_TOKEN
# BEFORE any node_modules / workspace mutation so the error points at the
# contract rather than at an opaque state-mutation side effect. Gated on
# dry_run so the dry-run path (with @semantic-release/github filtered out)
# continues to work without any secret env.
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
  # publish a GitHub release when invoked. GITHUB_TOKEN is enforced via
  # the early :? guard above (placed before node_modules setup so failure
  # modes are contract-first).
  echo "running production semantic-release in ${package_path}..."
  node ./node_modules/.bin/semantic-release "${extra_args[@]}"
fi
