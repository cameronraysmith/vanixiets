#!/usr/bin/env bash
# shellcheck shell=bash
# Verify the host's nix installation, flakes support, direnv presence,
# and flake metadata. Mirrors `make verify` from the repo-root Makefile,
# minus the devShell build (which is expensive and duplicates what
# `nix flake check` already covers).
#
# Idempotent / pure: does not mutate state.
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: verify [--help]

Audits the current host for a working nix + flakes + direnv setup and
validates that the invoking flake parses. Exits 0 on success, 1 if nix
or flakes are missing or the flake fails to parse. Prints a status line
per check. Read-only; does not mutate any system state.

Equivalent to `make verify` but invokable from a nix-only shell (no
dependency on GNU make).
EOF
}

case "${1:-}" in
  -h|--help)
    usage
    exit 0
    ;;
esac

failed=0

printf '\n=== Verifying installation ===\n\n'

# Check 1: nix binary
printf 'Checking nix installation: '
if command -v nix >/dev/null 2>&1; then
  printf '● nix found at %s\n' "$(command -v nix)"
  nix --version
else
  printf '⊘ nix not found\n'
  # shellcheck disable=SC2016  # backticks in string are literal output, not command substitution
  printf '  Run `make install-nix` from a nix-free shell to install nix.\n'
  failed=1
fi
printf '\n'

# Check 2: flakes support
printf 'Checking nix flakes support: '
if nix flake --help >/dev/null 2>&1; then
  printf '● flakes enabled\n'
else
  printf '⊘ flakes not enabled\n'
  failed=1
fi
printf '\n'

# Check 3: direnv (optional)
printf 'Checking direnv installation: '
if command -v direnv >/dev/null 2>&1; then
  printf '● direnv found at %s\n' "$(command -v direnv)"
else
  printf '⚠  direnv not found (optional but recommended)\n'
  # shellcheck disable=SC2016  # backticks in string are literal output, not command substitution
  printf '  Run `nix run .#bootstrap` to install.\n'
fi
printf '\n'

# Check 4: flake metadata parseable
printf 'Checking flake validity: '
if nix --accept-flake-config flake metadata . >/dev/null 2>&1; then
  printf '● flake is valid\n'
else
  printf '⊘ flake has errors\n'
  failed=1
fi
printf '\n'

# Check 5: surface /etc/nix/nix.conf for auditability (match make verify)
printf '/etc/nix/nix.conf:\n'
printf '==================\n'
if [ -f /etc/nix/nix.conf ]; then
  cat /etc/nix/nix.conf
else
  printf '(file not found)\n'
fi
printf '==================\n'

if [ -f /etc/nix/nix.custom.conf ]; then
  printf '\n/etc/nix/nix.custom.conf:\n'
  printf '==================\n'
  cat /etc/nix/nix.custom.conf
  printf '==================\n'
fi
printf '\n'

if [ "$failed" -eq 0 ]; then
  printf '● All verification checks passed!\n\n'
  exit 0
else
  printf '⊘ One or more verification checks failed.\n\n' >&2
  exit 1
fi
