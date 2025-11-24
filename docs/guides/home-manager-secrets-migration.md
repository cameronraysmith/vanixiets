# Home-Manager Secrets Migration Guide

**Last Updated**: 2025-11-24 (Story 2.4)
**Target Audience**: Engineers migrating user secrets from test-clan to infra, onboarding new users
**Companion Guide**: [Age Key Management](./age-key-management.md) - detailed operational workflows

## Overview

This guide documents the two-tier secrets architecture and migration workflow for home-manager user secrets in the infra repository.
Story 2.4 completed the migration of home-manager secrets from test-clan (validated in Epic 1) to infra (production deployment in Epic 2+).

### Two-Tier Secrets Architecture

The infra repository uses a two-tier secrets architecture that separates concerns between system-level and user-level secrets:

```
Tier 1: System-Level Secrets (clan vars)
├── Location: vars/
├── Format: clan vars generators
├── Encryption: Machine age keys (sops/machines/)
├── Decryption: NixOS activation via clan vars module
├── Examples: SSH host keys, zerotier identities, user password hashes
└── Scope: NixOS machines (cinnabar, electrum)

Tier 2: User-Level Secrets (sops-nix)
├── Location: secrets/home-manager/users/
├── Format: sops-encrypted YAML
├── Encryption: User age keys (.sops.yaml)
├── Decryption: home-manager activation via sops-nix module
├── Examples: GitHub tokens, SSH signing keys, API keys, atuin keys
└── Scope: All platforms (darwin + linux home-manager)
```

### Why Two Tiers?

Clan vars (Tier 1) are designed for NixOS system configuration and use the `_class` parameter which is incompatible with home-manager modules.
sops-nix (Tier 2) provides a home-manager compatible solution that works across darwin and linux platforms.

This architecture was validated in Epic 1 Story 1.10C and ensures:
- Clean separation between system and user secrets
- Platform-agnostic user secrets (same pattern on darwin and NixOS)
- Independent user secret management (users can manage their own secrets)
- Bitwarden as single source of truth for key derivation

## User Setup Process

Each user requires three corresponding age key deployments to access their secrets.

### Three-Context Correspondence

For sops-nix to work correctly, the user's age key must be consistent across:

| Context | Location | Purpose |
|---------|----------|---------|
| 1. Clan user | `sops/users/{user}/key.json` | Public key stored in repository |
| 2. .sops.yaml | Anchors section | Public key for encryption rules |
| 3. Workstation | `~/.config/sops/age/keys.txt` | Private key for decryption |

All three contexts must reference the SAME age keypair derived from the user's SSH key in Bitwarden.

### SSH Key to Age Key Derivation

The derivation is deterministic: same SSH key always produces same age key.

```bash
# Prerequisites
export BW_SESSION=$(bw unlock --raw)

# Extract age public key (for clan user + .sops.yaml)
age_pub=$(bw get item "sops-{username}-ssh" | jq -r '.sshKey.publicKey' | ssh-to-age)

# Extract age private key (for workstation keyfile)
age_priv=$(bw get item "sops-{username}-ssh" | jq -r '.sshKey.privateKey' | ssh-to-age -private-key)

# Validate correspondence
derived_pub=$(age-keygen -y <<< "$age_priv")
if [ "$age_pub" = "$derived_pub" ]; then
  echo "Age keys correspond correctly"
fi
```

### Creating Clan User

```bash
cd ~/projects/nix-workspace/infra

# Create clan user with age public key
clan secrets users add {username} --age-key "$age_pub"

# Verify
cat sops/users/{username}/key.json
# Should show: [{"publickey": "age1...", "type": "age"}]
```

### Deploying Workstation Key

The private key must be deployed to the user's workstation:

```bash
# On user's workstation
mkdir -p ~/.config/sops/age

# Create or append to keyfile
cat >> ~/.config/sops/age/keys.txt <<EOF
# User identity key ({username}) - $(date)
# public key: $age_pub
$age_priv
EOF

# Set secure permissions
chmod 600 ~/.config/sops/age/keys.txt
```

For detailed workflows, see [Age Key Management - Section 6](./age-key-management.md#6-epic-2-6-new-user-onboarding-workflow).

## .sops.yaml Configuration

The `.sops.yaml` file defines which age keys can encrypt/decrypt each secrets file.

### Key Anchors Section

Define age public keys as YAML anchors:

```yaml
keys:
  # Admin/recovery key (can decrypt everything)
  - &admin age1vy7wsnf8eg5229evq3ywup285jzk9cntsx5hhddjtwsjh0kf4c6s9fmalv

  # Developer key (repository-wide access)
  - &dev age1js028xag70wpwpp47elpq50mjjv7zn7sxuwuhk8yltkjzqzdvq5qq8w8cy

  # User identity keys
  - &admin-user age1vn8fpkmkzkjttcuc3prq3jrp7t5fsrdqey74ydu5p88keqmcupvs8jtmv8  # crs58/cameron
  - &raquel-user age12w0rmmskrds6m334w7qrcmpms5lpe3llah6wf8ry5jtatvuxku2sarl8ut  # raquel
```

### Creation Rules for Home-Manager Secrets

Add creation rules for each user's secrets directory:

```yaml
creation_rules:
  # crs58 home-manager secrets
  - path_regex: secrets/home-manager/users/crs58/.*\.yaml$
    key_groups:
      - age:
        - *admin
        - *dev
        - *admin-user

  # raquel home-manager secrets
  - path_regex: secrets/home-manager/users/raquel/.*\.yaml$
    key_groups:
      - age:
        - *admin
        - *dev
        - *raquel-user
```

### Adding a New User to .sops.yaml

1. Add user's age public key as anchor in `keys:` section
2. Add creation_rule for `secrets/home-manager/users/{username}/.*\.yaml$`
3. Include `*admin`, `*dev`, and `*{username}-user` in key_groups

## secrets.yaml Creation

### Directory Structure

```
secrets/
└── home-manager/
    └── users/
        ├── crs58/
        │   └── secrets.yaml    # 8 secrets
        └── raquel/
            └── secrets.yaml    # 5 secrets
```

### Creating Initial Secrets File

```bash
mkdir -p secrets/home-manager/users/{username}

# Create plaintext template
cat > secrets/home-manager/users/{username}/secrets.yaml <<EOF
github-token: PLACEHOLDER_TOKEN
ssh-signing-key: |
  -----BEGIN OPENSSH PRIVATE KEY-----
  PLACEHOLDER
  -----END OPENSSH PRIVATE KEY-----
ssh-public-key: |
  ssh-ed25519 PLACEHOLDER
bitwarden-email: user@example.com
atuin-key: PLACEHOLDER_ATUIN_KEY
EOF

# Encrypt in-place (uses .sops.yaml rules)
sops -e -i secrets/home-manager/users/{username}/secrets.yaml

# Verify encryption
head -5 secrets/home-manager/users/{username}/secrets.yaml
# Should show: ENC[AES256_GCM,data:...]
```

### Editing Encrypted Secrets

```bash
# Opens in $EDITOR, decrypts for editing, re-encrypts on save
sops secrets/home-manager/users/{username}/secrets.yaml
```

### Expected Secrets Per User

**crs58/cameron (8 secrets)**:
- github-token
- ssh-signing-key
- ssh-public-key
- glm-api-key
- firecrawl-api-key
- huggingface-token
- bitwarden-email
- atuin-key

**raquel (5 secrets)**:
- github-token
- ssh-signing-key
- ssh-public-key
- bitwarden-email
- atuin-key

## Validation Workflow

### Three-Context Correspondence Check

This validation is REQUIRED before any re-encryption or migration operation.

```bash
# Context 1: Extract from sops/users/
clan_key=$(jq -r '.[0].publickey' sops/users/{username}/key.json)

# Context 2: Extract from .sops.yaml
sops_key=$(grep "&{username}-user" .sops.yaml | awk '{print $NF}')

# Context 3: Derive from workstation private key
workstation_key=$(age-keygen -y < ~/.config/sops/age/keys.txt | grep {expected_prefix})

# Validate all match
if [ "$clan_key" = "$sops_key" ] && [ "$clan_key" = "$workstation_key" ]; then
  echo "All three contexts match"
else
  echo "MISMATCH DETECTED - DO NOT PROCEED"
  echo "Clan:        $clan_key"
  echo ".sops.yaml:  $sops_key"
  echo "Workstation: $workstation_key"
fi
```

### Re-encryption with Updated Keys

When migrating secrets or adding new recipients:

```bash
# Re-encrypt single file with updated .sops.yaml rules
sops updatekeys -y secrets/home-manager/users/{username}/secrets.yaml

# Re-encrypt all user secrets
for user in crs58 raquel; do
  sops updatekeys -y secrets/home-manager/users/$user/secrets.yaml
done
```

### Decryption Test

```bash
# Test decryption (requires matching private key in keyfile)
sops -d secrets/home-manager/users/{username}/secrets.yaml

# Verify secret count
sops -d secrets/home-manager/users/{username}/secrets.yaml | grep -E "^[a-z]" | wc -l
```

### Home-Manager Build Test

```bash
# Darwin platforms
nix build .#homeConfigurations.aarch64-darwin.{username}.activationPackage --no-link

# Linux platforms
nix build .#homeConfigurations.x86_64-linux.{username}.activationPackage --no-link

# Verify no sops-related errors in output
```

## Troubleshooting

### "Failed to get the data key required to decrypt"

**Cause**: Private key in `~/.config/sops/age/keys.txt` doesn't match any public key in the encrypted file.

**Solution**:
1. Check which keys can decrypt the file:
   ```bash
   head -50 secrets/home-manager/users/{username}/secrets.yaml | grep "recipient:"
   ```
2. Verify your keyfile has a corresponding private key:
   ```bash
   age-keygen -y < ~/.config/sops/age/keys.txt
   ```
3. If mismatch, re-derive from Bitwarden and update keyfile.

### "no key could be found"

**Cause**: `~/.config/sops/age/keys.txt` doesn't exist or is empty.

**Solution**:
```bash
export BW_SESSION=$(bw unlock --raw)
mkdir -p ~/.config/sops/age
age_priv=$(bw get item "sops-{username}-ssh" | jq -r '.sshKey.privateKey' | ssh-to-age -private-key)
echo "$age_priv" > ~/.config/sops/age/keys.txt
chmod 600 ~/.config/sops/age/keys.txt
```

### Re-encryption Doesn't Change Recipients

**Cause**: Using wrong sops command.

**Solution**: Use `sops updatekeys` not `sops -e -i`:
```bash
# Correct: updates recipients based on .sops.yaml
sops updatekeys -y secrets/home-manager/users/{username}/secrets.yaml

# Wrong: re-encrypts with same recipients
sops -e -i secrets/home-manager/users/{username}/secrets.yaml
```

### Build Fails with "sops.secrets" Errors

**Cause**: User module not properly importing sops-nix or defaultSopsFile path incorrect.

**Solution**: Verify user module configuration:
```nix
# modules/home/users/{username}/default.nix
{ lib, flake, ... }:
{
  flake.modules.homeManager."users/{username}" = { config, pkgs, flake, ... }: {
    sops = {
      # Must use flake.inputs.self for repository-relative path
      defaultSopsFile = flake.inputs.self + "/secrets/home-manager/users/{username}/secrets.yaml";
      secrets = {
        github-token = { };
        # ... other secrets
      };
    };
  };
}
```

### Darwin Build Fails with Missing `flake` Attribute

**Cause**: `extraSpecialArgs` not configured in darwin home-manager configuration.

**Solution**: See [Age Key Management - Section 8.4](./age-key-management.md#84-error-attribute-flake-missing-nix-build).

## Example: Onboarding christophersmith

This example demonstrates the complete workflow for onboarding a new user (christophersmith for argentum machine in Epic 4).

### Step 1: Generate SSH Key in Bitwarden

1. Login to Bitwarden Web UI (vault.bitwarden.com)
2. Create new item: Type = "SSH Key"
3. Name: `sops-christophersmith-ssh`
4. Click "Generate SSH Key" (ED25519 recommended)
5. Save

### Step 2: Derive Age Keys

```bash
export BW_SESSION=$(bw unlock --raw)
username="christophersmith"

# Derive age keys
age_pub=$(bw get item "sops-${username}-ssh" | jq -r '.sshKey.publicKey' | ssh-to-age)
age_priv=$(bw get item "sops-${username}-ssh" | jq -r '.sshKey.privateKey' | ssh-to-age -private-key)

# Validate format
if [[ $age_pub =~ ^age1[a-z0-9]{58}$ ]]; then
  echo "Valid age public key: $age_pub"
fi
```

### Step 3: Add Clan User

```bash
cd ~/projects/nix-workspace/infra

clan secrets users add "$username" --age-key "$age_pub"

# Verify
cat sops/users/$username/key.json

# Commit
git add sops/users/$username/
git commit -m "chore(epic-4): add clan user $username"
```

### Step 4: Update .sops.yaml

Edit `.sops.yaml`:

```yaml
keys:
  # ... existing keys ...
  - &christophersmith-user age1...  # Add the age_pub value

creation_rules:
  # ... existing rules ...

  # christophersmith home-manager secrets
  - path_regex: secrets/home-manager/users/christophersmith/.*\.yaml$
    key_groups:
      - age:
        - *admin
        - *dev
        - *christophersmith-user
```

Commit:
```bash
git add .sops.yaml
git commit -m "chore(epic-4): add christophersmith to .sops.yaml"
```

### Step 5: Create Secrets File

```bash
mkdir -p secrets/home-manager/users/$username

cat > secrets/home-manager/users/$username/secrets.yaml <<EOF
github-token: PLACEHOLDER
ssh-signing-key: |
  PLACEHOLDER
ssh-public-key: |
  PLACEHOLDER
bitwarden-email: christophersmith@example.com
atuin-key: PLACEHOLDER
EOF

# Encrypt
sops -e -i secrets/home-manager/users/$username/secrets.yaml

# Commit
git add secrets/home-manager/users/$username/
git commit -m "chore(epic-4): add encrypted secrets for $username"
```

### Step 6: Create User Module

```bash
mkdir -p modules/home/users/$username

cat > modules/home/users/$username/default.nix <<'EOF'
{ lib, flake, ... }:
{
  flake.modules.homeManager."users/christophersmith" = { config, pkgs, flake, ... }: {
    sops = {
      defaultSopsFile = flake.inputs.self + "/secrets/home-manager/users/christophersmith/secrets.yaml";
      secrets = {
        github-token = { };
        ssh-signing-key = { mode = "0400"; };
        ssh-public-key = { };
        bitwarden-email = { };
        atuin-key = { };
      };
    };

    home.stateVersion = "23.11";
    home.username = lib.mkDefault "christophersmith";
  };
}
EOF

git add modules/home/users/$username/
git commit -m "feat(epic-4): create christophersmith home-manager module"
```

### Step 7: Deploy Private Key to Workstation

On christophersmith's argentum machine:

```bash
export BW_SESSION=$(bw unlock --raw)
mkdir -p ~/.config/sops/age

age_priv=$(bw get item "sops-christophersmith-ssh" | jq -r '.sshKey.privateKey' | ssh-to-age -private-key)
echo "# christophersmith identity key - $(date)" >> ~/.config/sops/age/keys.txt
echo "$age_priv" >> ~/.config/sops/age/keys.txt

chmod 600 ~/.config/sops/age/keys.txt
```

### Step 8: Validate

```bash
# Test decryption
sops -d secrets/home-manager/users/christophersmith/secrets.yaml

# Test build (darwin)
nix build .#homeConfigurations.aarch64-darwin.christophersmith.activationPackage --no-link
```

## Migration Notes

### Story 2.4 Migration Summary

Story 2.4 migrated home-manager secrets from test-clan to infra:

1. **Pre-migration state**: Secrets files copied in Story 2.3 but encrypted with TEST-CLAN age keys
2. **Key correspondence validated**: Three-context check passed for crs58 and raquel
3. **Re-encryption**: Used `sops updatekeys -y` to re-encrypt with INFRA age keys
4. **Testing**: Darwin builds succeeded, NixOS config evaluation succeeded

### Files Affected

- `secrets/home-manager/users/crs58/secrets.yaml` - re-encrypted
- `secrets/home-manager/users/raquel/secrets.yaml` - re-encrypted

### Backup Location

Pre-migration backup preserved at: `secrets/home-manager.backup-pre-2.4/`

## References

- [Age Key Management Guide](./age-key-management.md) - comprehensive operational workflows
- [Secrets and Vars Architecture](../architecture/secrets-and-vars-architecture.md) - architectural documentation
- [sops-nix Documentation](https://github.com/Mic92/sops-nix)
- [age Encryption](https://age-encryption.org/)
- [Story 1.10C Work Item](../notes/development/work-items/1-10c-establish-sops-nix-secrets-home-manager.md) - sops-nix validation
