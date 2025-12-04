#!/usr/bin/env bash
# Extract SSH and Age public keys from Bitwarden for SOPS management
# Usage: extract-key-details.sh [key-name]
#   If key-name provided: Extract single key details
#   If no args: Extract all sops-* keys (excluding test keys)

set -euo pipefail

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# All production sops keys
SOPS_KEYS=(
  "sops-dev-ssh"
  "sops-ci-ssh"
  "sops-admin-user-ssh"
  "sops-raquel-user-ssh"
  "sops-stibnite-ssh"
  "sops-blackphos-ssh"
  "sops-orb-nixos-ssh"
)

extract_key_details() {
  local key_name="$1"

  echo "## $key_name"

  # Check if key exists
  if ! bw get item "$key_name" &>/dev/null; then
    echo -e "${RED}⊘ ERROR: Key '$key_name' not found in Bitwarden${NC}" >&2
    return 1
  fi

  # Get Bitwarden ID
  local bw_id
  bw_id=$(bw get item "$key_name" | jq -r '.id')
  echo "Bitwarden ID: $bw_id"

  # Get SSH Public key
  local ssh_pub
  ssh_pub=$(bw get item "$key_name" | jq -r '.sshKey.publicKey')
  echo "SSH Public: $ssh_pub"

  # Derive Age Public key
  local age_pub
  age_pub=$(echo "$ssh_pub" | ssh-to-age)
  echo "Age Public: $age_pub"

  # Validate age key format (age1 + 58 lowercase alphanumeric chars)
  if [[ $age_pub =~ ^age1[a-z0-9]{58}$ ]]; then
    echo -e "${GREEN}● Age key format valid${NC}"
  else
    echo -e "${RED}⊘ WARNING: Age key format invalid!${NC}" >&2
    echo "Expected: age1[a-z0-9]{58}" >&2
    echo "Got: $age_pub" >&2
    return 1
  fi

  echo ""
}

main() {
  echo "# SOPS Key Details Extraction - $(date)"
  echo ""

  if [ $# -eq 1 ]; then
    # Extract single key
    extract_key_details "$1"
  else
    # Extract all production keys
    local failed=0
    for key_name in "${SOPS_KEYS[@]}"; do
      if ! extract_key_details "$key_name"; then
        failed=1
      fi
    done

    if [ $failed -eq 1 ]; then
      echo -e "${RED}⊘ Some keys failed validation${NC}" >&2
      exit 1
    fi

    echo -e "${GREEN}● All keys extracted and validated successfully${NC}"
  fi
}

main "$@"
