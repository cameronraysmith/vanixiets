#!/usr/bin/env bash
# Update .sops.yaml with keys from Bitwarden
# Extracts age public keys and generates complete .sops.yaml structure

set -euo pipefail

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

SOPS_YAML=".sops.yaml"
BACKUP_SUFFIX=".backup-$(date +%Y%m%d-%H%M%S)"

# Admin recovery key (not in Bitwarden - preserved from existing)
ADMIN_RECOVERY_KEY="age1vy7wsnf8eg5229evq3ywup285jzk9cntsx5hhddjtwsjh0kf4c6s9fmalv" # gitleaks:allow - age public key

echo -e "${YELLOW}=== Updating .sops.yaml from Bitwarden ===${NC}"
echo ""

# Extract age public key from Bitwarden
get_age_key() {
  local bw_name="$1"
  local ssh_pub
  local age_pub

  ssh_pub=$(bw get item "$bw_name" | jq -r '.sshKey.publicKey')
  age_pub=$(echo "$ssh_pub" | ssh-to-age)

  # Validate format
  if [[ ! $age_pub =~ ^age1[a-z0-9]{58}$ ]]; then
    echo -e "${RED}⊘ ERROR: Invalid age key format for $bw_name: $age_pub${NC}" >&2
    exit 1
  fi

  echo "$age_pub"
}

echo "Extracting age keys from Bitwarden..."

# Repository keys
DEV_KEY=$(get_age_key "sops-dev-ssh")
echo "  dev: $DEV_KEY"

CI_KEY=$(get_age_key "sops-ci-ssh")
echo "  ci: $CI_KEY"

# User identity keys
ADMIN_USER_KEY=$(get_age_key "sops-admin-user-ssh")
echo "  admin-user: $ADMIN_USER_KEY"

RAQUEL_USER_KEY=$(get_age_key "sops-raquel-user-ssh")
echo "  raquel-user: $RAQUEL_USER_KEY"

# Host keys
STIBNITE_KEY=$(get_age_key "sops-stibnite-ssh")
echo "  stibnite: $STIBNITE_KEY"

BLACKPHOS_KEY=$(get_age_key "sops-blackphos-ssh")
echo "  blackphos: $BLACKPHOS_KEY"

ORB_NIXOS_KEY=$(get_age_key "sops-orb-nixos-ssh")
echo "  orb-nixos: $ORB_NIXOS_KEY"

echo ""
echo "Creating backup: ${SOPS_YAML}${BACKUP_SUFFIX}"
cp "$SOPS_YAML" "${SOPS_YAML}${BACKUP_SUFFIX}"

echo "Generating new .sops.yaml..."

cat > "$SOPS_YAML" << EOF
keys:
  # Repository-specific keys (working on infra source)
  - &dev $DEV_KEY      # from sops-dev-ssh in Bitwarden
  - &ci $CI_KEY        # from sops-ci-ssh in Bitwarden

  # Admin recovery key (offline, not in Bitwarden)
  - &admin $ADMIN_RECOVERY_KEY

  # User identity keys (from config.nix)
  - &admin-user $ADMIN_USER_KEY  # from sops-admin-user-ssh (cameron/crs58/runner/jovyan)
  - &raquel-user $RAQUEL_USER_KEY  # from sops-raquel-user-ssh (raquel)

  # Host keys (generated in Bitwarden, deployed to /etc/ssh/)
  - &stibnite $STIBNITE_KEY     # from sops-stibnite-ssh
  - &blackphos $BLACKPHOS_KEY   # from sops-blackphos-ssh
  - &orb-nixos $ORB_NIXOS_KEY   # from sops-orb-nixos-ssh

creation_rules:
  # User-specific secrets
  - path_regex: users/crs58/.*\.yaml$
    key_groups:
      - age:
        - *admin
        - *dev
        - *admin-user

  - path_regex: users/raquel/.*\.yaml$
    key_groups:
      - age:
        - *admin
        - *dev
        - *raquel-user

  # Host-specific secrets
  - path_regex: hosts/stibnite/.*\.yaml$
    key_groups:
      - age:
        - *admin
        - *dev
        - *admin-user
        - *stibnite

  - path_regex: hosts/blackphos/.*\.yaml$
    key_groups:
      - age:
        - *admin
        - *dev
        - *admin-user
        - *blackphos

  - path_regex: hosts/orb-nixos/.*\.yaml$
    key_groups:
      - age:
        - *admin
        - *dev
        - *admin-user
        - *orb-nixos

  # Shared secrets (services/, shared.yaml) - all hosts + CI for deployment
  - path_regex: (services/.*\.yaml$|shared\.yaml$)
    key_groups:
      - age:
        - *admin
        - *dev
        - *ci
        - *admin-user
        - *stibnite
        - *blackphos
        - *orb-nixos

  # Fallback
  - path_regex: .*\.yaml$
    key_groups:
      - age:
        - *admin
        - *dev
        - *admin-user
        - *stibnite
        - *blackphos
        - *orb-nixos
EOF

echo -e "${GREEN}● .sops.yaml updated successfully${NC}"
echo ""
echo "Summary:"
echo "  - 8 keys total (2 repo + 1 admin + 2 user + 3 host)"
echo "  - 7 creation rules (2 user + 3 host + 1 shared + 1 fallback)"
echo "  - Backup saved: ${SOPS_YAML}${BACKUP_SUFFIX}"
echo ""
echo "Next steps:"
echo "  1. Review .sops.yaml for correctness"
echo "  2. Re-encrypt secrets with: sops updatekeys secrets/*.yaml"
echo "  3. Validate with: just validate-secrets"
