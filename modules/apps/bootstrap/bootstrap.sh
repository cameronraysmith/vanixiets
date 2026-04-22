#!/usr/bin/env bash
# shellcheck shell=bash
# Re-run the bootstrap flow (direnv install + status report) on a host
# that already has nix installed.
#
# Chicken-and-egg: `make bootstrap` is the real first-contact installer;
# it installs nix itself. This flake app runs UNDER nix, so by definition
# nix is already present. Treat this app as the post-nix half of
# bootstrap: it ensures direnv is installed and reports status.
#
# Idempotent: re-runs produce no new state when direnv is already present.
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: bootstrap [--help]

Idempotent post-nix bootstrap: installs direnv via `nix profile install`
if it is missing, then reports the tool versions. Assumes nix is already
installed (that is the precondition of `nix run`). For a clean-host
first-contact install, use `make bootstrap` instead (installs nix first,
then direnv).

Mirrors the `make bootstrap` target in the repo-root Makefile for the
direnv half of the flow; the nix-installer half is skipped because it
cannot run from inside a nix sandbox.
EOF
}

case "${1:-}" in
  -h|--help)
    usage
    exit 0
    ;;
esac

printf '=== Bootstrap (nix-present host) ===\n\n'

# Step 1: confirm nix (cannot be missing since we're running under nix,
# but surface the version for parity with `make verify`).
if command -v nix >/dev/null 2>&1; then
  printf '● nix found at %s\n' "$(command -v nix)"
  nix --version
else
  # Unreachable under `nix run`, but keep the guard for defence in depth.
  printf '⊘ nix not found on PATH (unexpected inside a nix sandbox)\n' >&2
  # shellcheck disable=SC2016  # backticks in string are literal output, not command substitution
  printf 'Run `make bootstrap` from a nix-free shell to install nix first.\n' >&2
  exit 1
fi
printf '\n'

# Step 2: install direnv if missing. `nix profile install` is idempotent
# against the same attribute path; we guard with `command -v` for a
# cleaner no-op output when direnv is already on PATH.
if command -v direnv >/dev/null 2>&1; then
  printf '● direnv already installed at %s\n' "$(command -v direnv)"
else
  # shellcheck disable=SC2016  # backticks in string are literal output, not command substitution
  printf 'Installing direnv via `nix profile install nixpkgs#direnv`...\n'
  nix --accept-flake-config profile install nixpkgs#direnv
  printf '● direnv installed\n'
fi
printf '\n'

printf '=== ● Bootstrap complete ===\n\n'
printf 'Next steps:\n'
# shellcheck disable=SC2016  # backticks in strings are literal output, not command substitution
printf '  1. Run `nix run .#verify` to audit your installation.\n'
# shellcheck disable=SC2016
printf '  2. Run `nix run .#setup-user` once to generate your age key.\n'
# shellcheck disable=SC2016
printf '  3. Run `nix develop` to enter the development environment.\n'
printf '\n'
printf 'See https://direnv.net/docs/hook.html to add direnv to your shell.\n'
