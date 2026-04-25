#!/usr/bin/env bash
# shellcheck shell=bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: setup-user [--help]

Generates an age keypair for sops-nix secrets on the current user at
~/.config/sops/age/keys.txt and prints the public key. If the file
already exists, re-prints the public key and exits 0 WITHOUT
regenerating. Mode 0600 on the private key.

First-time setup: after running, back up the contents of keys.txt to
Bitwarden as a secure note `age-key-<username>`, and send the public
key to the admin for addition to `.sops.yaml`.
EOF
}

case "${1:-}" in
  -h|--help)
    usage
    exit 0
    ;;
esac

key_dir="${HOME}/.config/sops/age"
key_file="${key_dir}/keys.txt"

printf '\n=== Age key setup ===\n\n'

if [ -f "$key_file" ]; then
  printf '⚠  Age key already exists at %s\n' "$key_file"
  printf 'To regenerate, manually delete the file first.\n'
  printf '\nYour public key is:\n'
  if ! age-keygen -y "$key_file" 2>/dev/null; then
    printf 'Error reading existing key (is the file corrupted?)\n' >&2
    exit 1
  fi
  exit 0
fi

mkdir -p "$key_dir"
age-keygen -o "$key_file"
chmod 600 "$key_file"

printf '\n● Age key generated successfully!\n\n'
printf 'Your public key is:\n'
age-keygen -y "$key_file"

cat <<'EOF'

⚠  IMPORTANT: Back up your private key to Bitwarden!
  1. Copy the content of ~/.config/sops/age/keys.txt
  2. Store in Bitwarden as a secure note: `age-key-<username>`
  3. Send your PUBLIC key (shown above) to the admin

See docs/new-user-host.md for complete setup instructions.
EOF
