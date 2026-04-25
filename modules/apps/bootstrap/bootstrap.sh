#!/usr/bin/env bash
# shellcheck shell=bash
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

# Confirm nix even though running under nix means it must be present.
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

# command -v guard yields cleaner no-op output than relying on nix profile install idempotence.
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
