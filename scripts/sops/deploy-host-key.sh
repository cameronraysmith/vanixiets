#!/usr/bin/env bash
# Deploy host SSH key from Bitwarden to /etc/ssh/ssh_host_ed25519_key
# Usage: deploy-host-key.sh <hostname>
#   hostname: stibnite, blackphos, or orb-nixos

set -euo pipefail

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

if [ $# -ne 1 ]; then
  echo "Usage: $0 <hostname>" >&2
  echo "  hostname: stibnite, blackphos, or orb-nixos" >&2
  exit 1
fi

HOSTNAME="$1"
BW_KEY_NAME="sops-${HOSTNAME}-ssh"
PRIVATE_KEY_PATH="/etc/ssh/ssh_host_ed25519_key"
PUBLIC_KEY_PATH="/etc/ssh/ssh_host_ed25519_key.pub"

# Determine OS type for SSH restart
detect_os() {
  if [ -f /etc/os-release ]; then
    # NixOS/Linux
    echo "nixos"
  elif [ "$(uname)" = "Darwin" ]; then
    echo "darwin"
  else
    echo "unknown"
  fi
}

OS_TYPE=$(detect_os)

echo -e "${YELLOW}=== Deploying host key for $HOSTNAME ===${NC}"
echo ""

# Verify key exists in Bitwarden
echo "Checking Bitwarden for key: $BW_KEY_NAME"
if ! bw get item "$BW_KEY_NAME" &>/dev/null; then
  echo -e "${RED}⊘ ERROR: Key '$BW_KEY_NAME' not found in Bitwarden${NC}" >&2
  exit 1
fi
echo -e "${GREEN}● Key found in Bitwarden${NC}"
echo ""

# Backup existing keys
echo "Creating backup of existing host keys..."
if [ -f "$PRIVATE_KEY_PATH" ]; then
  sudo cp "$PRIVATE_KEY_PATH" "${PRIVATE_KEY_PATH}.old"
  echo "  Backed up: ${PRIVATE_KEY_PATH}.old"
fi
if [ -f "$PUBLIC_KEY_PATH" ]; then
  sudo cp "$PUBLIC_KEY_PATH" "${PUBLIC_KEY_PATH}.old"
  echo "  Backed up: ${PUBLIC_KEY_PATH}.old"
fi
echo ""

# Deploy private key
echo "Deploying private key from Bitwarden..."
bw get item "$BW_KEY_NAME" | jq -r '.sshKey.privateKey' | sudo tee "$PRIVATE_KEY_PATH" > /dev/null
sudo chmod 600 "$PRIVATE_KEY_PATH"
echo -e "${GREEN}● Private key deployed with permissions 600${NC}"

# Deploy public key
echo "Deploying public key from Bitwarden..."
bw get item "$BW_KEY_NAME" | jq -r '.sshKey.publicKey' | sudo tee "$PUBLIC_KEY_PATH" > /dev/null
sudo chmod 644 "$PUBLIC_KEY_PATH"
echo -e "${GREEN}● Public key deployed with permissions 644${NC}"
echo ""

# Verify key integrity
echo "Verifying key integrity..."
if sudo ssh-keygen -lf "$PUBLIC_KEY_PATH" &>/dev/null; then
  echo -e "${GREEN}● Key integrity verified${NC}"
  sudo ssh-keygen -lf "$PUBLIC_KEY_PATH"
else
  echo -e "${RED}⊘ ERROR: Key integrity check failed${NC}" >&2
  echo "Restoring from backup..." >&2
  sudo cp "${PRIVATE_KEY_PATH}.old" "$PRIVATE_KEY_PATH"
  sudo cp "${PUBLIC_KEY_PATH}.old" "$PUBLIC_KEY_PATH"
  exit 1
fi
echo ""

# Restart SSH service (if running)
echo "Restarting SSH service (if running)..."
if [ "$OS_TYPE" = "darwin" ]; then
  if sudo launchctl list | grep -q com.openssh.sshd; then
    sudo launchctl kickstart -kp system/com.openssh.sshd
    echo -e "${GREEN}● SSH service restarted (Darwin)${NC}"
  else
    echo -e "${YELLOW}⚠️  SSH service not running (sshd not loaded)${NC}"
    echo -e "${YELLOW}   Host key deployed but SSH server not active${NC}"
  fi
elif [ "$OS_TYPE" = "nixos" ]; then
  if sudo systemctl is-active --quiet sshd; then
    sudo systemctl restart sshd
    echo -e "${GREEN}● SSH service restarted (NixOS)${NC}"
  else
    echo -e "${YELLOW}⚠️  SSH service not running${NC}"
    echo -e "${YELLOW}   Host key deployed but SSH server not active${NC}"
  fi
else
  echo -e "${YELLOW}⚠️  Unknown OS type - please restart SSH manually if needed${NC}"
fi
echo ""

echo -e "${GREEN}=== Host key deployment complete ===${NC}"
echo ""
echo "Verification steps:"
echo "  1. Host key deployed to ${PRIVATE_KEY_PATH}"
echo "  2. Fingerprint: $(sudo ssh-keygen -lf ${PUBLIC_KEY_PATH} 2>/dev/null | awk '{print $2}')"
echo "  3. Backups at ${PRIVATE_KEY_PATH}.old (safe to delete after verification)"
if sudo launchctl list 2>/dev/null | grep -q com.openssh.sshd || sudo systemctl is-active --quiet sshd 2>/dev/null; then
  echo "  4. Test SSH access from another terminal/machine"
else
  echo "  4. SSH server not active (key available for sops-nix/future use)"
fi
