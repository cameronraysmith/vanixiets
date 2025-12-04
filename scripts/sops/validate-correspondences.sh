#!/usr/bin/env bash
# Validate SOPS key correspondences across config.nix, Bitwarden, and .sops.yaml
# Implements comprehensive validation from unified-plan deliverable-5

set -euo pipefail

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

FAILED=0

print_header() {
  echo ""
  echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"
  echo -e "${BLUE}  $1${NC}"
  echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"
  echo ""
}

check_pass() {
  echo -e "${GREEN}● $1${NC}"
}

check_fail() {
  echo -e "${RED}⊘ $1${NC}" >&2
  FAILED=1
}

check_warn() {
  echo -e "${YELLOW}⚠️  $1${NC}"
}

# Get age key from Bitwarden
get_age_from_bw() {
  local bw_name="$1"
  if ! bw get item "$bw_name" &>/dev/null; then
    echo "NOT_FOUND"
    return 1
  fi
  local ssh_pub
  ssh_pub=$(bw get item "$bw_name" | jq -r '.sshKey.publicKey')
  echo "$ssh_pub" | ssh-to-age
}

# Get age key from .sops.yaml by anchor
get_age_from_sops_yaml() {
  local anchor="$1"
  # Extract the age key from the same line as the anchor
  # Format: - &anchor age1... # comment
  # Use -- to prevent grep from treating - as an option
  grep -- "- &${anchor} " .sops.yaml | awk '{print $3}'
}

print_header "SOPS Key Correspondence Validation"

# ============================================================================
# 1. User Identity Keys Validation
# ============================================================================

print_header "1. User Identity Keys"

echo "Checking baseIdentity.sshKey → sops-admin-user-ssh → &admin-user..."

# Read SSH key from config.nix
BASE_SSH_KEY=$(grep 'sshKey =' config.nix | head -1 | cut -d'"' -f2)
echo "  config.nix baseIdentity.sshKey: $BASE_SSH_KEY"

# Get from Bitwarden (strip comment if present)
ADMIN_USER_BW_SSH=$(bw get item "sops-admin-user-ssh" | jq -r '.sshKey.publicKey' 2>/dev/null | awk '{print $1" "$2}' || echo "NOT_FOUND")
echo "  Bitwarden sops-admin-user-ssh: $ADMIN_USER_BW_SSH"

# Get age key from Bitwarden
ADMIN_USER_BW_AGE=$(get_age_from_bw "sops-admin-user-ssh" || echo "NOT_FOUND")
echo "  Derived age key: $ADMIN_USER_BW_AGE"

# Get from .sops.yaml
ADMIN_USER_YAML_AGE=$(get_age_from_sops_yaml "admin-user")
echo "  .sops.yaml &admin-user: $ADMIN_USER_YAML_AGE"

# Validate correspondence
if [ "$BASE_SSH_KEY" = "$ADMIN_USER_BW_SSH" ]; then
  check_pass "baseIdentity.sshKey matches Bitwarden sops-admin-user-ssh"
else
  check_fail "baseIdentity.sshKey does NOT match Bitwarden"
fi

if [ "$ADMIN_USER_BW_AGE" = "$ADMIN_USER_YAML_AGE" ]; then
  check_pass "Bitwarden age key matches .sops.yaml &admin-user"
else
  check_fail "Bitwarden age key does NOT match .sops.yaml"
fi

echo ""
echo "Checking raquel.sshKey → sops-raquel-user-ssh → &raquel-user..."

# Read raquel SSH key from config.nix
RAQUEL_SSH_KEY=$(grep -A5 'raquel = {' config.nix | grep 'sshKey =' | cut -d'"' -f2)
echo "  config.nix raquel.sshKey: $RAQUEL_SSH_KEY"

# Get from Bitwarden (strip comment if present)
RAQUEL_USER_BW_SSH=$(bw get item "sops-raquel-user-ssh" | jq -r '.sshKey.publicKey' 2>/dev/null | awk '{print $1" "$2}' || echo "NOT_FOUND")
echo "  Bitwarden sops-raquel-user-ssh: $RAQUEL_USER_BW_SSH"

# Get age key from Bitwarden
RAQUEL_USER_BW_AGE=$(get_age_from_bw "sops-raquel-user-ssh" || echo "NOT_FOUND")
echo "  Derived age key: $RAQUEL_USER_BW_AGE"

# Get from .sops.yaml
RAQUEL_USER_YAML_AGE=$(get_age_from_sops_yaml "raquel-user")
echo "  .sops.yaml &raquel-user: $RAQUEL_USER_YAML_AGE"

# Validate correspondence
if [ "$RAQUEL_SSH_KEY" = "$RAQUEL_USER_BW_SSH" ]; then
  check_pass "raquel.sshKey matches Bitwarden sops-raquel-user-ssh"
else
  check_fail "raquel.sshKey does NOT match Bitwarden"
fi

if [ "$RAQUEL_USER_BW_AGE" = "$RAQUEL_USER_YAML_AGE" ]; then
  check_pass "Bitwarden age key matches .sops.yaml &raquel-user"
else
  check_fail "Bitwarden age key does NOT match .sops.yaml"
fi

# ============================================================================
# 2. Host Keys Validation
# ============================================================================

print_header "2. Host Keys"

for host in stibnite blackphos orb-nixos; do
  echo "Checking $host → sops-${host}-ssh → &${host}..."

  # Get from Bitwarden
  HOST_BW_AGE=$(get_age_from_bw "sops-${host}-ssh" || echo "NOT_FOUND")
  if [ "$HOST_BW_AGE" = "NOT_FOUND" ]; then
    check_fail "sops-${host}-ssh NOT found in Bitwarden"
    continue
  fi
  echo "  Bitwarden sops-${host}-ssh age key: $HOST_BW_AGE"

  # Get from .sops.yaml
  HOST_YAML_AGE=$(get_age_from_sops_yaml "$host")
  echo "  .sops.yaml &${host}: $HOST_YAML_AGE"

  # Validate correspondence
  if [ "$HOST_BW_AGE" = "$HOST_YAML_AGE" ]; then
    check_pass "Bitwarden age key matches .sops.yaml &${host}"
  else
    check_fail "Bitwarden age key does NOT match .sops.yaml"
  fi

  echo ""
done

# ============================================================================
# 3. Repository Keys Validation
# ============================================================================

print_header "3. Repository Keys"

for key in dev ci; do
  echo "Checking sops-${key}-ssh → &${key}..."

  # Get from Bitwarden
  REPO_BW_AGE=$(get_age_from_bw "sops-${key}-ssh" || echo "NOT_FOUND")
  if [ "$REPO_BW_AGE" = "NOT_FOUND" ]; then
    check_fail "sops-${key}-ssh NOT found in Bitwarden"
    continue
  fi
  echo "  Bitwarden sops-${key}-ssh age key: $REPO_BW_AGE"

  # Get from .sops.yaml
  REPO_YAML_AGE=$(get_age_from_sops_yaml "$key")
  echo "  .sops.yaml &${key}: $REPO_YAML_AGE"

  # Validate correspondence
  if [ "$REPO_BW_AGE" = "$REPO_YAML_AGE" ]; then
    check_pass "Bitwarden age key matches .sops.yaml &${key}"
  else
    check_fail "Bitwarden age key does NOT match .sops.yaml"
  fi

  echo ""
done

# ============================================================================
# 4. CI Test Configs Validation
# ============================================================================

print_header "4. CI Test Configs (Should Have NO Keys)"

for config in blackphos-nixos stibnite-nixos; do
  echo "Checking $config should NOT have Bitwarden key..."

  if bw list items --search "sops-${config}-ssh" 2>/dev/null | jq -e '.[] | select(.name == "sops-'${config}'-ssh")' &>/dev/null; then
    check_fail "$config has unexpected key in Bitwarden: sops-${config}-ssh"
  else
    check_pass "$config correctly has NO key in Bitwarden"
  fi
done

# ============================================================================
# 5. Summary
# ============================================================================

print_header "Validation Summary"

if [ $FAILED -eq 0 ]; then
  echo -e "${GREEN}● All correspondence validations passed${NC}"
  exit 0
else
  echo -e "${RED}⊘ Some validations failed${NC}" >&2
  exit 1
fi
