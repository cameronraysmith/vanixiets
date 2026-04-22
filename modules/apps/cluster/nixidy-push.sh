#!/usr/bin/env bash
# shellcheck shell=bash
# Sync the ./result/ tree produced by nixidy-build into the private
# local-k3d manifest repo, then commit and push any diff.
#
# Usage:
#   nixidy-push [--help]
#
# Environment:
#   LOCAL_K3D_REPO   path to the local-k3d manifest repo
#                    (default: $HOME/projects/nix-workspace/local-k3d)
set -euo pipefail

case "${1:-}" in
  -h|--help)
    cat <<'EOF'
Usage: nixidy-push [--help]

Prerequisites:
  - `nixidy-build` has run in the current directory, producing ./result
  - The LOCAL_K3D_REPO directory exists and has a configured git remote

rsync copies result/ → $LOCAL_K3D_REPO/ with --delete, dereferencing
nix-store symlinks and normalizing permissions. Exits 0 cleanly when
there is nothing to push (no changes detected).

Environment:
  LOCAL_K3D_REPO   target repo path
                   (default: $HOME/projects/nix-workspace/local-k3d)
EOF
    exit 0
    ;;
esac

LOCAL_K3D_REPO="${LOCAL_K3D_REPO:-$HOME/projects/nix-workspace/local-k3d}"

if [[ ! -d "result" ]]; then
  echo "Error: result/ directory not found. Run 'just nixidy-build' first." >&2
  exit 1
fi

if [[ ! -d "$LOCAL_K3D_REPO" ]]; then
  echo "Error: local-k3d repo not found at $LOCAL_K3D_REPO" >&2
  echo "Clone it with: git clone git@github.com:cameronraysmith/local-k3d.git $LOCAL_K3D_REPO" >&2
  exit 1
fi

echo "Syncing rendered manifests to $LOCAL_K3D_REPO..."
# -L dereferences symlinks (nix store paths) to copy actual content
# --checksum compares by content hash (Nix store files have epoch timestamps)
# --chmod fixes read-only permissions from nix store
rsync -aL --delete --checksum --chmod=Du+w,Fu+w --exclude='.git' result/ "$LOCAL_K3D_REPO/"

echo "Committing and pushing to local-k3d repo..."
cd "$LOCAL_K3D_REPO"
git add -A
if git diff --cached --quiet; then
  echo "No changes to push."
else
  git commit -m "chore: update rendered manifests from vanixiets"
  git push
  echo "Manifests pushed to local-k3d repo."
fi
