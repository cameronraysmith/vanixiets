#!/usr/bin/env bash
# Regenerate ~/.config/sops/age/keys.txt from Bitwarden
# Implements deliverable-4: Just recipe for age config regeneration
# Usage: sync-age-keys.sh [--deploy-host-keys]

set -euo pipefail

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

DEPLOY_HOST_KEYS=false

# Parse arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --deploy-host-keys)
      DEPLOY_HOST_KEYS=true
      shift
      ;;
    *)
      echo "Usage: $0 [--deploy-host-keys]" >&2
      exit 1
      ;;
  esac
done

# Determine current user and host
CURRENT_USER=$(whoami)
CURRENT_HOST=$(hostname -s)

# Determine age keys directory
# Use XDG_CONFIG_HOME if set, otherwise default to ~/.config
# This matches sops.age.keyFile = "${config.xdg.configHome}/sops/age/keys.txt"
XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
AGE_KEYS_DIR="$XDG_CONFIG_HOME/sops/age"
AGE_KEYS_FILE="$AGE_KEYS_DIR/keys.txt"

echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}  SOPS Age Keys Synchronization${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"
echo ""

# Helper function
check_pass() {
  echo -e "${GREEN}● $1${NC}"
}

# Get SSH private key from Bitwarden and convert to age private key
get_age_private_key() {
  local bw_name="$1"
  local ssh_private
  local age_private

  if ! bw get item "$bw_name" &>/dev/null; then
    echo -e "${RED}⊘ ERROR: Key '$bw_name' not found in Bitwarden${NC}" >&2
    return 1
  fi

  ssh_private=$(bw get item "$bw_name" | jq -r '.sshKey.privateKey')
  age_private=$(echo "$ssh_private" | ssh-to-age -private-key)

  # Validate format
  if [[ ! $age_private =~ ^AGE-SECRET-KEY-[0-9A-Z]+$ ]]; then
    echo -e "${RED}⊘ ERROR: Invalid age private key format${NC}" >&2
    return 1
  fi

  echo "$age_private"
}

# Get SSH public key from Bitwarden and convert to age public key
get_age_public_key() {
  local bw_name="$1"
  local ssh_pub
  local age_pub

  if ! bw get item "$bw_name" &>/dev/null; then
    echo -e "${RED}⊘ ERROR: Key '$bw_name' not found in Bitwarden${NC}" >&2
    return 1
  fi

  ssh_pub=$(bw get item "$bw_name" | jq -r '.sshKey.publicKey')
  age_pub=$(echo "$ssh_pub" | ssh-to-age)

  # Validate format
  if [[ ! $age_pub =~ ^age1[a-z0-9]{58}$ ]]; then
    echo -e "${RED}⊘ ERROR: Invalid age public key format${NC}" >&2
    return 1
  fi

  echo "$age_pub"
}

echo "Current environment:"
echo "  User: $CURRENT_USER"
echo "  Host: $CURRENT_HOST"
echo "  Age keys file: $AGE_KEYS_FILE"
echo ""

# Create backup if file exists
if [ -f "$AGE_KEYS_FILE" ]; then
  BACKUP_FILE="${AGE_KEYS_FILE}.backup-$(date +%Y%m%d-%H%M%S)"
  echo "Creating backup: $BACKUP_FILE"
  cp "$AGE_KEYS_FILE" "$BACKUP_FILE"
fi

# Create directory if it doesn't exist
mkdir -p "$AGE_KEYS_DIR"

# Start building keys.txt
echo "# SOPS Age Keys - Generated $(date)" > "$AGE_KEYS_FILE"
echo "# DO NOT COMMIT THIS FILE" >> "$AGE_KEYS_FILE"
echo "" >> "$AGE_KEYS_FILE"

# 1. Add repository development key (all developers need this)
echo "Extracting repository development key..."
DEV_KEY_PRIVATE=$(get_age_private_key "sops-dev-ssh")
DEV_KEY_PUBLIC=$(get_age_public_key "sops-dev-ssh")
echo "# Repository development key" >> "$AGE_KEYS_FILE"
echo "# public key: $DEV_KEY_PUBLIC" >> "$AGE_KEYS_FILE"
echo "$DEV_KEY_PRIVATE" >> "$AGE_KEYS_FILE"
echo "" >> "$AGE_KEYS_FILE"
check_pass "Repository dev key added"

# 2. Add user identity key based on current user
echo "Extracting user identity key for $CURRENT_USER..."

case "$CURRENT_USER" in
  cameron|crs58|runner|jovyan)
    USER_KEY_PRIVATE=$(get_age_private_key "sops-admin-user-ssh")
    USER_KEY_PUBLIC=$(get_age_public_key "sops-admin-user-ssh")
    echo "# User identity key (admin-user)" >> "$AGE_KEYS_FILE"
    echo "# public key: $USER_KEY_PUBLIC" >> "$AGE_KEYS_FILE"
    echo "$USER_KEY_PRIVATE" >> "$AGE_KEYS_FILE"
    check_pass "Admin user identity key added"
    ;;
  raquel)
    USER_KEY_PRIVATE=$(get_age_private_key "sops-raquel-user-ssh")
    USER_KEY_PUBLIC=$(get_age_public_key "sops-raquel-user-ssh")
    echo "# User identity key (raquel-user)" >> "$AGE_KEYS_FILE"
    echo "# public key: $USER_KEY_PUBLIC" >> "$AGE_KEYS_FILE"
    echo "$USER_KEY_PRIVATE" >> "$AGE_KEYS_FILE"
    check_pass "Raquel user identity key added"
    ;;
  *)
    echo -e "${YELLOW}⚠️  Unknown user: $CURRENT_USER (skipping user identity key)${NC}"
    ;;
esac
echo "" >> "$AGE_KEYS_FILE"

# 3. Add host key based on current host
echo "Extracting host key for $CURRENT_HOST..."

case "$CURRENT_HOST" in
  stibnite|blackphos|orb-nixos)
    HOST_KEY_PRIVATE=$(get_age_private_key "sops-${CURRENT_HOST}-ssh")
    HOST_KEY_PUBLIC=$(get_age_public_key "sops-${CURRENT_HOST}-ssh")
    echo "# Host key ($CURRENT_HOST)" >> "$AGE_KEYS_FILE"
    echo "# public key: $HOST_KEY_PUBLIC" >> "$AGE_KEYS_FILE"
    echo "$HOST_KEY_PRIVATE" >> "$AGE_KEYS_FILE"
    check_pass "Host key for $CURRENT_HOST added"

    # Deploy to /etc/ssh if requested
    if [ "$DEPLOY_HOST_KEYS" = true ]; then
      echo ""
      echo -e "${YELLOW}Deploying host key to /etc/ssh/...${NC}"
      if ! $(dirname "$0")/deploy-host-key.sh "$CURRENT_HOST"; then
        echo -e "${RED}⊘ Host key deployment failed${NC}" >&2
        exit 1
      fi
    fi
    ;;
  *)
    echo -e "${YELLOW}⚠️  Unknown host: $CURRENT_HOST (skipping host key)${NC}"
    ;;
esac

echo ""
echo -e "${GREEN}● Age keys synchronization complete${NC}"
echo ""
echo "Keys file: $AGE_KEYS_FILE"
echo "Keys added:"
echo "  - Repository dev key (all users)"
echo "  - User identity key (based on $CURRENT_USER)"
echo "  - Host key (based on $CURRENT_HOST)"

if [ "$DEPLOY_HOST_KEYS" = true ]; then
  echo "  - Host key deployed to /etc/ssh/"
fi

echo ""
echo "Next steps:"
echo "  1. Test decryption: sops -d secrets/shared.yaml"
echo "  2. Keep backup until verified"
