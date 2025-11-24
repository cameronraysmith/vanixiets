# Age Key Management and sops-nix Operations

**Last Updated**: 2025-11-16 (Story 1.10C)
**Target Audience**: Epic 2-6 engineers onboarding new users across 6 machines
**Reference Implementation**: `~/projects/nix-workspace/infra/justfile`, `~/projects/nix-workspace/infra/scripts/sops/`

## Overview

This guide documents the operational workflow for managing age encryption keys derived from SSH keys stored in Bitwarden.
Understanding this architecture is critical for Epic 2-6 migration where we'll onboard 4+ users across 6 machines (darwin laptops + NixOS servers).

### Key Insight: ONE SSH Keypair → ONE Age Keypair → THREE Usage Contexts

Each user has a single SSH keypair stored in Bitwarden (`sops-{username}-ssh`) that derives ONE age keypair used in three distinct contexts:

1. **infra repository**: sops-nix home-manager secrets (`~/.config/sops/age/keys.txt` on workstations)
2. **clan user management**: System-level secrets via clan-core (`sops/users/{username}/key.json`)
3. **test-clan repository**: sops-nix home-manager secrets (Epic 1 validation, same pattern as infra)

### Architecture: Bitwarden as Source of Truth

```
┌──────────────────────────────────────────────────────────────────┐
│ Bitwarden (Source of Truth)                                     │
│   - sops-dev-ssh (repository key, all developers)               │
│   - sops-admin-user-ssh (cameron/crs58/jovyan/runner identity)  │
│   - sops-raquel-user-ssh (raquel identity)                      │
│   - sops-{hostname}-ssh (host keys: stibnite, blackphos, etc.)  │
└──────────────────────────────────────────────────────────────────┘
                            ↓
                    bw CLI + ssh-to-age
                            ↓
┌──────────────────────────────────────────────────────────────────┐
│ Derived Age Keys (AGE-SECRET-KEY-* format)                      │
│   - Repository dev key (shared by all developers)               │
│   - User identity keys (per-user, unique)                       │
│   - Host keys (per-machine, unique)                             │
└──────────────────────────────────────────────────────────────────┘
                            ↓
        ┌───────────────────┴───────────────────┐
        ↓                                       ↓
┌─────────────────────┐              ┌─────────────────────┐
│ ~/.config/sops/age/ │              │ clan users/         │
│   keys.txt          │              │   {user}/key.json   │
│                     │              │                     │
│ sops-nix decryption │              │ clan vars secrets   │
│ (home-manager)      │              │ (NixOS/darwin)      │
└─────────────────────┘              └─────────────────────┘
```

## 1. SSH-to-Age Derivation Pattern

### 1.1 Understanding the Derivation

Age keys are **deterministically derived** from SSH keys using the `ssh-to-age` tool:

```bash
# Extract SSH private key from Bitwarden
ssh_private=$(bw get item "sops-admin-user-ssh" | jq -r '.sshKey.privateKey')

# Derive age PRIVATE key
age_private=$(echo "$ssh_private" | ssh-to-age -private-key)
# Output format: AGE-SECRET-KEY-1ABCDEF... (uppercase, 74 chars)

# Extract SSH public key from Bitwarden
ssh_public=$(bw get item "sops-admin-user-ssh" | jq -r '.sshKey.publicKey')

# Derive age PUBLIC key
age_public=$(echo "$ssh_public" | ssh-to-age)
# Output format: age1abcdef... (lowercase, 62 chars: age1 + 58 alphanumeric)
```

**Critical properties**:
- **Deterministic**: Same SSH key → same age key (every time)
- **One-way**: Cannot derive SSH key from age key
- **Validated format**: Age public keys MUST match regex `^age1[a-z0-9]{58}$`

### 1.2 Validation Commands

```bash
# Validate age public key format
age_pub="age1vn8fpkmkzkjttcuc3prq3jrp7t5fsrdqey74ydu5p88keqmcupvs8jtmv8"
if [[ $age_pub =~ ^age1[a-z0-9]{58}$ ]]; then
  echo "✅ Valid age public key"
else
  echo "❌ Invalid format"
fi

# Validate age private key format
age_priv="AGE-SECRET-KEY-1ABCDEFGHIJKLMNOP..."
if [[ $age_priv =~ ^AGE-SECRET-KEY-[0-9A-Z]+$ ]]; then
  echo "✅ Valid age private key"
else
  echo "❌ Invalid format"
fi

# Derive public key from private key (verification)
age-keygen -y <<< "$age_priv"
# Should output: age1vn8fpkmkzkjttcuc3prq3jrp7t5fsrdqey74ydu5p88keqmcupvs8jtmv8
```

## 2. Bitwarden CLI Workflow

### 2.1 Prerequisites

```bash
# Install Bitwarden CLI
nix-shell -p bitwarden-cli

# Login (one-time, persists session)
bw login

# Unlock vault (generates BW_SESSION token)
export BW_SESSION=$(bw unlock --raw)

# Verify access
bw status
# Should show: {"status":"unlocked",...}
```

### 2.2 Extract Age Keys from Bitwarden

The infra repository provides automated scripts via justfile:

```bash
cd ~/projects/nix-workspace/infra

# Extract and display all SOPS key details
just sops-extract-keys
# Shows SSH public + derived age public for all sops-* keys

# Extract single key details
just sops-extract-keys "sops-admin-user-ssh"

# Regenerate ~/.config/sops/age/keys.txt from Bitwarden
just sops-sync-keys
# Creates keys.txt with: dev key + user identity + host key
# Backs up existing file to keys.txt.backup-YYYYMMDD-HHMMSS
```

### 2.3 Manual Age Key Extraction

If justfile scripts unavailable (e.g., in test-clan), use manual workflow:

```bash
# Ensure BW_SESSION is set
export BW_SESSION=$(bw unlock --raw)

# Extract SSH private key
ssh_priv=$(bw get item "sops-admin-user-ssh" | jq -r '.sshKey.privateKey')

# Derive age private key
age_priv=$(echo "$ssh_priv" | ssh-to-age -private-key)

# Extract SSH public key
ssh_pub=$(bw get item "sops-admin-user-ssh" | jq -r '.sshKey.publicKey')

# Derive age public key
age_pub=$(echo "$ssh_pub" | ssh-to-age)

# Display results
echo "Age Public:  $age_pub"
echo "Age Private: $age_priv"

# Verify public key derivation from private key
age-keygen -y <<< "$age_priv"
# Should match $age_pub
```

## 3. Clan User Creation Workflow

Clan uses age public keys for system-level secrets management.
The public key is stored in `sops/users/{username}/key.json`.

### 3.1 Create Clan User with Age Key

```bash
cd ~/projects/nix-workspace/test-clan  # or infra

# Extract age public key from Bitwarden
age_pub=$(bw get item "sops-admin-user-ssh" | jq -r '.sshKey.publicKey' | ssh-to-age)

# Create clan user (creates sops/users/crs58/ directory + key.json)
clan secrets users add crs58 --age-key "$age_pub"

# Verify user created
cat sops/users/crs58/key.json
# Should show:
# [
#   {
#     "publickey": "age1vn8fpkmkzkjttcuc3prq3jrp7t5fsrdqey74ydu5p88keqmcupvs8jtmv8",
#     "type": "age"
#   }
# ]
```

### 3.2 Validate Clan User Age Key

```bash
# Extract age public key from clan user file
clan_age_pub=$(jq -r '.[0].publickey' sops/users/crs58/key.json)

# Compare with Bitwarden-derived age key
bw_age_pub=$(bw get item "sops-admin-user-ssh" | jq -r '.sshKey.publicKey' | ssh-to-age)

if [ "$clan_age_pub" = "$bw_age_pub" ]; then
  echo "✅ Clan user age key matches Bitwarden"
else
  echo "❌ MISMATCH - keys do not correspond!"
  echo "Clan:      $clan_age_pub"
  echo "Bitwarden: $bw_age_pub"
fi
```

## 4. Age Key Correspondence Validation

**Critical for Epic 2-6**: Ensure age keys are consistent across all three contexts.

### 4.1 Three-Context Validation

```bash
# Context 1: infra sops-nix (user's workstation age private key)
# Extract from ~/.config/sops/age/keys.txt
workstation_age_priv=$(grep "AGE-SECRET-KEY" ~/.config/sops/age/keys.txt | grep -v "^#" | tail -1)
workstation_age_pub=$(age-keygen -y <<< "$workstation_age_priv")

# Context 2: clan users (clan user public key)
clan_age_pub=$(jq -r '.[0].publickey' ~/projects/nix-workspace/test-clan/sops/users/crs58/key.json)

# Context 3: test-clan sops-nix (public key in .sops.yaml)
testclan_age_pub=$(grep "crs58-user" ~/projects/nix-workspace/test-clan/.sops.yaml | awk '{print $NF}')

# Validate all three match
if [ "$workstation_age_pub" = "$clan_age_pub" ] && [ "$clan_age_pub" = "$testclan_age_pub" ]; then
  echo "✅ Age keys correspond across all three contexts"
  echo "   Workstation: $workstation_age_pub"
  echo "   Clan user:   $clan_age_pub"
  echo "   test-clan:   $testclan_age_pub"
else
  echo "❌ CRITICAL: Age key mismatch detected!"
  echo "   Workstation: $workstation_age_pub"
  echo "   Clan user:   $clan_age_pub"
  echo "   test-clan:   $testclan_age_pub"
  echo ""
  echo "Action: Re-run age key derivation from Bitwarden source of truth"
fi
```

### 4.2 Automated Correspondence Validation (infra)

The infra repository provides automated validation:

```bash
cd ~/projects/nix-workspace/infra

# Validate all key correspondences (config.nix ↔ Bitwarden ↔ .sops.yaml)
just sops-validate-correspondences

# Output shows:
# - Bitwarden SSH keys
# - Derived age public keys
# - .sops.yaml key anchors
# - config.nix key references
# - ✅/❌ correspondence status
```

## 5. sops-nix .sops.yaml Configuration

The `.sops.yaml` file defines multi-user encryption rules using age public keys.

### 5.1 Extract Age Public Keys from Clan

```bash
cd ~/projects/nix-workspace/test-clan

# Extract crs58 age public key
jq -r '.[0].publickey' sops/users/crs58/key.json
# Output: age1vn8fpkmkzkjttcuc3prq3jrp7t5fsrdqey74ydu5p88keqmcupvs8jtmv8

# Extract raquel age public key
jq -r '.[0].publickey' sops/users/raquel/key.json
# Output: age12w0rmmskrds6m334w7qrcmpms5lpe3llah6wf8ry5jtatvuxku2sarl8ut

# Extract admin recovery key (from infra or Bitwarden)
bw get item "sops-dev-ssh" | jq -r '.sshKey.publicKey' | ssh-to-age
# Output: age1vy7wsnf8eg5229evq3ywup285jzk9cntsx5hhddjtwsjh0kf4c6s9fmalv
```

### 5.2 Configure .sops.yaml

Create `.sops.yaml` in repository root:

```yaml
keys:
  # Admin recovery key (can decrypt all secrets)
  - &admin age1vy7wsnf8eg5229evq3ywup285jzk9cntsx5hhddjtwsjh0kf4c6s9fmalv

  # User age keys (extracted from sops/users/*/key.json)
  - &crs58-user age1vn8fpkmkzkjttcuc3prq3jrp7t5fsrdqey74ydu5p88keqmcupvs8jtmv8
  - &raquel-user age12w0rmmskrds6m334w7qrcmpms5lpe3llah6wf8ry5jtatvuxku2sarl8ut

creation_rules:
  # crs58/cameron user secrets (8 secrets: development + ai + shell)
  - path_regex: secrets/home-manager/users/crs58/.*\.yaml$
    key_groups:
      - age:
          - *admin
          - *crs58-user

  # raquel user secrets (5 secrets: development + shell, no ai)
  - path_regex: secrets/home-manager/users/raquel/.*\.yaml$
    key_groups:
      - age:
          - *admin
          - *raquel-user
```

### 5.3 Verify Private Keys Exist in Shared Keyfile

```bash
# User must have corresponding private key in ~/.config/sops/age/keys.txt
# Extract public keys from private keys in keyfile
grep "AGE-SECRET-KEY" ~/.config/sops/age/keys.txt | grep -v "^#" | while read priv_key; do
  age-keygen -y <<< "$priv_key"
done

# Should include:
# age1vy7wsnf8eg5229evq3ywup285jzk9cntsx5hhddjtwsjh0kf4c6s9fmalv (admin)
# age1vn8fpkmkzkjttcuc3prq3jrp7t5fsrdqey74ydu5p88keqmcupvs8jtmv8 (crs58-user)
```

## 6. Epic 2-6 New User Onboarding Workflow

This is the **critical path** for Epic 2-6 migration (onboarding 4+ users across 6 machines).

### 6.1 Prerequisites

- Bitwarden CLI installed and authenticated (`bw status` shows unlocked)
- `ssh-to-age` tool installed (`nix-shell -p ssh-to-age`)
- Access to infra repository (`~/projects/nix-workspace/infra/`)
- Access to target repository (test-clan or infra depending on Epic)

### 6.2 Step-by-Step Workflow

#### Step 1: Generate SSH Key in Bitwarden

**Platform**: Bitwarden Web UI (vault.bitwarden.com)

1. Create new item: Type = "SSH Key"
2. Name: `sops-{username}-ssh` (e.g., `sops-christophersmith-ssh`)
3. Click "Generate SSH Key" button
4. Key type: ED25519 (recommended) or RSA 4096
5. Save item

#### Step 2: Derive Age Keys

```bash
# Ensure Bitwarden CLI is unlocked
export BW_SESSION=$(bw unlock --raw)

# Derive age public key
username="christophersmith"
age_pub=$(bw get item "sops-${username}-ssh" | jq -r '.sshKey.publicKey' | ssh-to-age)

# Validate format
if [[ $age_pub =~ ^age1[a-z0-9]{58}$ ]]; then
  echo "✅ Valid age public key: $age_pub"
else
  echo "❌ Invalid age key format!"
  exit 1
fi
```

#### Step 3: Add User to Clan

```bash
cd ~/projects/nix-workspace/test-clan  # or ~/projects/nix-workspace/infra

# Create clan user
clan secrets users add "$username" --age-key "$age_pub"

# Verify creation
cat "sops/users/${username}/key.json"

# Commit clan user
git add "sops/users/${username}/"
git commit -m "chore(epic-2): add clan user $username with age key"
```

#### Step 4: Configure User's Local Age Keyfile

**Platform**: User's workstation (darwin laptop or NixOS machine)

```bash
# Run on user's machine as the user
export BW_SESSION=$(bw unlock --raw)

# Create age keys directory
mkdir -p ~/.config/sops/age

# Extract age private key
username="christophersmith"
age_priv=$(bw get item "sops-${username}-ssh" | jq -r '.sshKey.privateKey' | ssh-to-age -private-key)

# Create keys.txt (or append if exists)
cat >> ~/.config/sops/age/keys.txt <<EOF
# User identity key ($username) - Generated $(date)
# public key: $(age-keygen -y <<< "$age_priv")
$age_priv

EOF

# Verify file permissions
chmod 600 ~/.config/sops/age/keys.txt

# Test decryption capability
sops -d ~/path/to/encrypted/secret.yaml
# Should succeed if user has access via .sops.yaml rules
```

#### Step 5: Update .sops.yaml for New User

```bash
cd ~/projects/nix-workspace/test-clan

# Add user's age public key to .sops.yaml
cat >> .sops.yaml <<EOF
  - &${username}-user $age_pub
EOF

# Add creation_rules for user's secrets
cat >> .sops.yaml <<EOF

  # $username user secrets
  - path_regex: secrets/home-manager/users/$username/.*\.yaml$
    key_groups:
      - age:
          - *admin
          - *${username}-user
EOF

# Commit .sops.yaml
git add .sops.yaml
git commit -m "chore(epic-2): add $username to .sops.yaml for home-manager secrets"
```

#### Step 6: Create User's Secrets File

```bash
mkdir -p "secrets/home-manager/users/$username"

# Create initial secrets file (unencrypted)
cat > "secrets/home-manager/users/$username/secrets.yaml" <<EOF
github-token: PLACEHOLDER
ssh-signing-key: |
  PLACEHOLDER
bitwarden-email: user@example.com
atuin-key: PLACEHOLDER
EOF

# Encrypt secrets file
sops -e -i "secrets/home-manager/users/$username/secrets.yaml"

# Verify encryption
file "secrets/home-manager/users/$username/secrets.yaml"
# Should show: ASCII text (sops-encrypted)

# Commit encrypted secrets
git add "secrets/home-manager/users/$username/"
git commit -m "chore(epic-2): add encrypted secrets for $username"
```

#### Step 7: Create User's sops-nix Module

```bash
mkdir -p "modules/home/users/$username"

cat > "modules/home/users/$username/default.nix" <<'EOF'
{ lib, flake, ... }:
{
  flake.modules.homeManager."users/{username}" = { config, pkgs, flake, ... }: {
    sops = {
      defaultSopsFile = flake.inputs.self + "/secrets/home-manager/users/{username}/secrets.yaml";
      secrets = {
        github-token = { };
        ssh-signing-key = { mode = "0400"; };
        ssh-public-key = { };
        bitwarden-email = { };
        atuin-key = { };
        # Add ai secrets if needed:
        # glm-api-key = { };
        # firecrawl-api-key = { };
        # huggingface-token = { };
      };
    };

    home.stateVersion = "23.11";
    home.username = lib.mkDefault "{username}";
  };
}
EOF

# Replace {username} placeholder
sed -i '' "s/{username}/$username/g" "modules/home/users/$username/default.nix"

# Commit user module
git add "modules/home/users/$username/"
git commit -m "feat(epic-2): create $username home-manager user module"
```

#### Step 8: Validate End-to-End

```bash
# Build user's home configuration
nix build ".#homeConfigurations.aarch64-darwin.$username.activationPackage" --no-link

# Verify secrets decrypt on user's machine
sops -d "secrets/home-manager/users/$username/secrets.yaml"
# Should show decrypted YAML with placeholder values
```

### 6.3 Onboarding Checklist

For each new user in Epic 2-6:

- [ ] Generate SSH key in Bitwarden (`sops-{username}-ssh`)
- [ ] Derive age public key via `bw` + `ssh-to-age`
- [ ] Add clan user: `clan secrets users add {username} --age-key {age_pub}`
- [ ] Configure user's `~/.config/sops/age/keys.txt` on their workstation
- [ ] Update `.sops.yaml` with user's age public key + creation_rules
- [ ] Create encrypted secrets file: `secrets/home-manager/users/{username}/secrets.yaml`
- [ ] Create user module: `modules/home/users/{username}/default.nix`
- [ ] Build validation: `nix build .#homeConfigurations.{system}.{username}.activationPackage`
- [ ] Decryption validation: `sops -d secrets/home-manager/users/{username}/secrets.yaml`

## 7. sops-nix Operations

### 7.1 Adding New Secrets

```bash
# Edit encrypted file (opens in $EDITOR)
sops secrets/home-manager/users/crs58/secrets.yaml

# Add new key-value pair in YAML editor:
# new-api-key: sk-proj-xxxxxxxxxxxx

# Save and exit - sops re-encrypts automatically
```

### 7.2 Multi-User Encryption

When secrets are encrypted for multiple users (via `.sops.yaml` rules):

```bash
# Encrypt file for first time (uses .sops.yaml rules)
sops -e secrets/home-manager/users/crs58/secrets.yaml > secrets/home-manager/users/crs58/secrets.yaml.enc
mv secrets/home-manager/users/crs58/secrets.yaml.enc secrets/home-manager/users/crs58/secrets.yaml

# Or in-place encryption
sops -e -i secrets/home-manager/users/crs58/secrets.yaml

# Verify who can decrypt
sops -d secrets/home-manager/users/crs58/secrets.yaml
# Succeeds if you have private key for: admin OR crs58-user
```

### 7.3 Secret Rotation

```bash
# Update encryption keys after adding new user or rotating keys
cd ~/projects/nix-workspace/test-clan

# Re-encrypt single file with updated .sops.yaml
sops updatekeys secrets/home-manager/users/crs58/secrets.yaml

# Re-encrypt all secrets in directory
find secrets/ -name "*.yaml" -type f -exec sops updatekeys {} \;

# Or using fd (faster)
fd -e yaml . secrets/ -x sops updatekeys {}
```

### 7.4 Key Rotation Workflow

When rotating user's SSH/age keys (security incident, key compromise):

```bash
# Step 1: Generate new SSH key in Bitwarden (Web UI)
# New item: sops-{username}-ssh (overwrites old key)

# Step 2: Derive new age keys
export BW_SESSION=$(bw unlock --raw)
username="crs58"
new_age_pub=$(bw get item "sops-${username}-ssh" | jq -r '.sshKey.publicKey' | ssh-to-age)

# Step 3: Update clan user
clan secrets users add "$username" --age-key "$new_age_pub"  # Overwrites

# Step 4: Update user's ~/.config/sops/age/keys.txt
# (User must run: just sops-sync-keys on their workstation)

# Step 5: Update .sops.yaml
# Edit .sops.yaml and replace old age public key with new_age_pub

# Step 6: Re-encrypt all secrets
sops updatekeys -y secrets/home-manager/users/${username}/secrets.yaml

# Step 7: Verify decryption with new key
sops -d secrets/home-manager/users/${username}/secrets.yaml
```

## 8. Troubleshooting

### 8.1 "Failed to get the data key required to decrypt"

**Symptom**: `sops -d` fails with data key error

**Cause**: Private key in `~/.config/sops/age/keys.txt` doesn't match public key in `.sops.yaml`

**Solution**:
```bash
# Verify private key derives correct public key
grep "AGE-SECRET-KEY" ~/.config/sops/age/keys.txt | while read key; do
  age-keygen -y <<< "$key"
done
# Should include public key from .sops.yaml

# If missing, re-derive from Bitwarden
export BW_SESSION=$(bw unlock --raw)
age_priv=$(bw get item "sops-admin-user-ssh" | jq -r '.sshKey.privateKey' | ssh-to-age -private-key)
echo "$age_priv" >> ~/.config/sops/age/keys.txt
```

### 8.2 "no key could be found to decrypt"

**Symptom**: sops cannot find any matching private key

**Cause**: `~/.config/sops/age/keys.txt` doesn't exist or is empty

**Solution**:
```bash
# Check if file exists
ls -la ~/.config/sops/age/keys.txt

# If missing, regenerate from Bitwarden
cd ~/projects/nix-workspace/infra
just sops-sync-keys

# Or manually create for single user
export BW_SESSION=$(bw unlock --raw)
mkdir -p ~/.config/sops/age
age_priv=$(bw get item "sops-admin-user-ssh" | jq -r '.sshKey.privateKey' | ssh-to-age -private-key)
echo "$age_priv" > ~/.config/sops/age/keys.txt
chmod 600 ~/.config/sops/age/keys.txt
```

### 8.3 "invalid age public key format"

**Symptom**: Age key validation fails with format error

**Cause**: Incorrect SSH key type or corrupted derivation

**Solution**:
```bash
# Verify SSH key in Bitwarden is ED25519 or RSA
bw get item "sops-admin-user-ssh" | jq -r '.sshKey.keyType'

# Re-derive age key
ssh_pub=$(bw get item "sops-admin-user-ssh" | jq -r '.sshKey.publicKey')
age_pub=$(echo "$ssh_pub" | ssh-to-age)

# Validate format
if [[ $age_pub =~ ^age1[a-z0-9]{58}$ ]]; then
  echo "✅ Valid: $age_pub"
else
  echo "❌ Invalid format - regenerate SSH key in Bitwarden"
fi
```

### 8.4 "Error: attribute 'flake' missing" (nix build)

**Symptom**: Darwin configuration build fails with missing `flake` attribute

**Cause**: `extraSpecialArgs` not configured in home-manager (darwin module context)

**Solution** (see Story 1.10C implementation):
```nix
# In darwin machine configuration (e.g., blackphos/default.nix)
let
  # Capture outer flake-parts config
  flakeForHomeManager = config.flake // { inherit inputs; };
in
{
  # ... darwin module ...
  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;

    # Bridge from flake-parts layer to home-manager layer
    extraSpecialArgs = {
      flake = flakeForHomeManager;
    };

    users.crs58.imports = [
      flakeModulesHome."users/crs58"
      flakeModulesHome.base-sops  # sops-nix module
      # ...
    ];
  };
}
```

### 8.5 Clan User Key Mismatch

**Symptom**: Clan vars secrets fail to decrypt, but sops-nix works

**Cause**: Clan user's `key.json` has different age key than `~/.config/sops/age/keys.txt`

**Solution**:
```bash
# Extract clan user's age public key
clan_age=$(jq -r '.[0].publickey' sops/users/crs58/key.json)

# Derive from workstation private key
work_age=$(age-keygen -y < <(grep "AGE-SECRET-KEY" ~/.config/sops/age/keys.txt | tail -1))

# Compare
if [ "$clan_age" != "$work_age" ]; then
  echo "❌ Mismatch detected!"
  echo "Clan:       $clan_age"
  echo "Workstation: $work_age"

  # Regenerate clan user with correct key
  clan secrets users add crs58 --age-key "$work_age"
fi
```

## 9. Platform-Specific Notes

### 9.1 Darwin Laptops (blackphos, stibnite, rosegold, argentum)

**SSH Agent**: Bitwarden Desktop app can serve as SSH agent

**Setup**:
1. Install Bitwarden Desktop app (Mac App Store or bitwarden.com)
2. Login to Bitwarden Desktop
3. Settings → Options → Enable "Use Bitwarden for SSH agent"
4. Add SSH key to Bitwarden Web UI (generates keypair, stores in vault)
5. Bitwarden Desktop serves SSH key to ssh-agent protocol

**Age key workflow**:
- SSH keys stored in Bitwarden (source of truth)
- Use `bw` CLI to extract and derive age keys
- Age private keys placed in `~/.config/sops/age/keys.txt`
- SSH operations use Bitwarden Desktop as agent
- sops-nix decryption uses age private keys from keys.txt

**Advantages**:
- Single source of truth (Bitwarden vault)
- No local SSH private key files needed
- SSH signing, git operations work via Bitwarden agent
- Age keys derived on-demand for sops decryption

### 9.2 NixOS Servers (cinnabar, electrum, ephemeral VMs)

**SSH Agent**: Cannot use Bitwarden Desktop (no GUI), requires linux-native SSH agent

**Setup**:
1. Use `bw` CLI to extract SSH private key from Bitwarden
2. Deploy SSH private key to `~/.ssh/id_ed25519` (or similar)
3. Set file permissions: `chmod 600 ~/.ssh/id_ed25519`
4. Use standard OpenSSH agent or systemd ssh-agent service
5. Separately derive and deploy age private key to `~/.config/sops/age/keys.txt`

**Age key workflow**:
```bash
# Extract and deploy SSH private key (for SSH operations)
export BW_SESSION=$(bw unlock --raw)
bw get item "sops-admin-user-ssh" | jq -r '.sshKey.privateKey' > ~/.ssh/id_ed25519
chmod 600 ~/.ssh/id_ed25519

# Derive and deploy age private key (for sops decryption)
age_priv=$(bw get item "sops-admin-user-ssh" | jq -r '.sshKey.privateKey' | ssh-to-age -private-key)
mkdir -p ~/.config/sops/age
echo "$age_priv" > ~/.config/sops/age/keys.txt
chmod 600 ~/.config/sops/age/keys.txt

# Configure SSH agent (systemd service)
systemctl --user enable ssh-agent.service
systemctl --user start ssh-agent.service
export SSH_AUTH_SOCK="$XDG_RUNTIME_DIR/ssh-agent.socket"
```

**Security considerations**:
- SSH private key exists as file on disk (encrypted filesystem recommended)
- Age private key exists as file on disk (encrypted filesystem recommended)
- Both derive from same Bitwarden source (single keypair, two formats)
- Alternative: Use TPM/Secure Enclave for key storage (future enhancement)

### 9.3 CI/CD Environments (GitHub Actions, GitLab CI)

**Setup**: Store age private key as repository secret

```bash
# Generate age private key from Bitwarden
export BW_SESSION=$(bw unlock --raw)
age_priv=$(bw get item "sops-ci-ssh" | jq -r '.sshKey.privateKey' | ssh-to-age -private-key)

# Set GitHub secret (manual via Web UI or gh CLI)
gh secret set SOPS_AGE_KEY --body "$age_priv"

# In GitHub Actions workflow:
# - name: Decrypt secrets
#   env:
#     SOPS_AGE_KEY: ${{ secrets.SOPS_AGE_KEY }}
#   run: |
#     mkdir -p ~/.config/sops/age
#     echo "$SOPS_AGE_KEY" > ~/.config/sops/age/keys.txt
#     sops -d secrets/shared.yaml
```

## 10. Quick Reference

### Common Commands

```bash
# Unlock Bitwarden vault
export BW_SESSION=$(bw unlock --raw)

# Derive age public key from Bitwarden
bw get item "sops-{user}-ssh" | jq -r '.sshKey.publicKey' | ssh-to-age

# Derive age private key from Bitwarden
bw get item "sops-{user}-ssh" | jq -r '.sshKey.privateKey' | ssh-to-age -private-key

# Derive public from private
age-keygen -y < <(echo "AGE-SECRET-KEY-...")

# Extract clan user's age public key
jq -r '.[0].publickey' sops/users/{user}/key.json

# Decrypt sops file
sops -d secrets/home-manager/users/{user}/secrets.yaml

# Encrypt sops file in-place
sops -e -i secrets/home-manager/users/{user}/secrets.yaml

# Edit encrypted file
sops secrets/home-manager/users/{user}/secrets.yaml

# Re-encrypt with updated keys
sops updatekeys secrets/home-manager/users/{user}/secrets.yaml
```

### File Locations

- **Bitwarden vault**: Source of truth for SSH keys (`sops-{user}-ssh` items)
- **Age private keys**: `~/.config/sops/age/keys.txt` (user's workstation/server)
- **Clan user age public**: `sops/users/{user}/key.json` (repository)
- **sops-nix config**: `.sops.yaml` (repository root)
- **Encrypted secrets**: `secrets/home-manager/users/{user}/secrets.yaml` (repository)
- **User sops module**: `modules/home/users/{user}/default.nix` (repository)

### Epic 2-6 User Matrix

| Username | SSH Key (Bitwarden) | Age Public Key (first 12 chars) | Secrets Count | Aggregates |
|----------|---------------------|--------------------------------|---------------|------------|
| crs58/cameron | sops-admin-user-ssh | age1vn8fpkmk... | 8 | dev, ai, shell |
| raquel | sops-raquel-user-ssh | age12w0rmmsk... | 5 | dev, shell |
| christophersmith | sops-christophersmith-ssh | TBD (Epic 4) | TBD | TBD |
| janettesmith | sops-janettesmith-ssh | TBD (Epic 4) | TBD | TBD |

## References

- **infra justfile**: `~/projects/nix-workspace/infra/justfile` (sops-* recipes)
- **sync-age-keys.sh**: `~/projects/nix-workspace/infra/scripts/sops/sync-age-keys.sh`
- **extract-key-details.sh**: `~/projects/nix-workspace/infra/scripts/sops/extract-key-details.sh`
- **test-clan .sops.yaml**: `~/projects/nix-workspace/test-clan/.sops.yaml`
- **Story 1.10C**: `~/projects/nix-workspace/infra/docs/notes/development/work-items/1-10c-establish-sops-nix-secrets-home-manager.md`
- **Architecture Section 11**: `~/projects/nix-workspace/infra/docs/notes/development/test-clan-validated-architecture.md` (Module System Architecture)
- **sops-nix documentation**: https://github.com/Mic92/sops-nix
- **age specification**: https://age-encryption.org/
