---
title: End-to-End Secrets Workflow
---

Comprehensive guide to how secrets management works in this nix-config, covering both the existing system and the new unified cryptographic infrastructure.

## Overview: Two Complementary Systems

This configuration uses **two complementary secrets management systems** that coexist and share the same Age encryption key:

- **System 1**: Existing multi-key SOPS setup for general secrets management
- **System 2**: New unified crypto pattern for Radicle + Git + Jujutsu signing

Both systems use SOPS with Age encryption and share the same decryption key, enabling gradual migration from System 1 to System 2 over time.

## System 1: General Secrets Management (Existing)

### Purpose
Multi-key secrets management for general infrastructure:
- User passwords
- Service tokens (GitHub, APIs)
- Network configurations (WiFi, VPN)
- Host-specific settings

### Location
- **Repository**: `~/projects/nix-workspace/nix-config/`
- **Secrets directory**: `secrets/`
- **Configuration**: `.sops.yaml` (root of nix-config)

### Architecture: 3-Tier Key Structure (8 keys total)

```
┌─────────────────────────────────────────────────────────┐
│ Bitwarden (Single Source of Truth)                     │
├─────────────────────────────────────────────────────────┤
│ All keys stored as SSH keys with naming pattern:       │
│ sops-<purpose>-ssh                                      │
└─────────────────────────────────────────────────────────┘
                         │
         ┌───────────────┴─────────────────┐
         │                                 │
         ▼                                 ▼
┌──────────────────┐            ┌──────────────────────┐
│ Repository Keys  │            │ User Identity Keys   │
│ (2 keys)         │            │ (2 keys)             │
├──────────────────┤            ├──────────────────────┤
│ sops-dev-ssh     │            │ sops-admin-user-ssh  │
│ → &dev           │            │ → &admin-user        │
│                  │            │ (cameron/crs58/      │
│ sops-ci-ssh      │            │  runner/jovyan)      │
│ → &ci            │            │                      │
│                  │            │ sops-raquel-user-ssh │
│                  │            │ → &raquel-user       │
└──────────────────┘            └──────────────────────┘

         ┌──────────────────────────────────┐
         │                                  │
         ▼                                  ▼
┌──────────────────┐            ┌──────────────────────┐
│ Host Keys (3)    │            │ Admin Recovery (1)   │
├──────────────────┤            ├──────────────────────┤
│ sops-stibnite-ssh│            │ Offline key          │
│ → &stibnite      │            │ (not in Bitwarden)   │
│                  │            │ → &admin             │
│ sops-blackphos..│            │                      │
│ → &blackphos     │            │                      │
│                  │            │                      │
│ sops-orb-nixos..│            │                      │
│ → &orb-nixos     │            │                      │
└──────────────────┘            └──────────────────────┘
```

### End-to-End Workflow

#### 1. Key Management (One-time setup)

```bash
# All keys generated in Bitwarden Web UI
# Naming pattern: sops-<purpose>-ssh
# Type: SSH Key (ed25519)

# Extract Age public keys from Bitwarden
export BW_SESSION=$(bw unlock --raw)
just sops-extract-keys

# Update .sops.yaml with all keys
just sops-update-yaml

# Sync Age private keys to ~/.config/sops/age/keys.txt
just sops-sync-keys

bw lock
```

**Result**:
- `.sops.yaml` updated with 8 Age keys
- `~/.config/sops/age/keys.txt` contains private keys you have access to
- Host keys deployed to `/etc/ssh/ssh_host_ed25519_key`

#### 2. Secret Encryption

```bash
# Create/edit a secret file
sops secrets/hosts/stibnite/secrets/default.yaml

# SOPS editor opens - add secrets in YAML format:
user:
  hashedPassword: $6$rounds=656000$...
github:
  token: ghp_xxxxxxxxxxxx

# On save: SOPS encrypts with all recipient keys from .sops.yaml
# File is safe to commit to git (encrypted)
```

**Encryption happens automatically** based on `creation_rules` in `.sops.yaml`:
```yaml
creation_rules:
  - path_regex: hosts/stibnite/.*\.yaml$
    key_groups:
      - age:
          - *admin
          - *dev
          - *admin-user
          - *stibnite
```

#### 3. Secret Reference in Nix Configuration

**In home-manager modules**:
```nix
# modules/home/all/core/sops.nix sets defaultSopsFile
sops.defaultSopsFile = flake.inputs.self + "/secrets/shared.yaml";

# In any module, declare a secret:
sops.secrets."github/token" = {
  # No sopsFile needed - uses defaultSopsFile
  # Will be deployed to /run/user/<uid>/secrets/github/token
};

# Use the secret:
programs.git.extraConfig = {
  credential.helper = "store --file ${config.sops.secrets.\"github/token\".path}";
};
```

#### 4. Secret Deployment (Automatic)

On `darwin-rebuild switch` or `nixos-rebuild switch`:

```
1. SOPS-nix activates during system rebuild
2. Reads Age key from:
   - System level: /etc/ssh/ssh_host_ed25519_key (host key)
   - User level: ~/.config/sops/age/keys.txt (user keys)
3. Decrypts secrets matching the available Age keys
4. Deploys to tmpfs:
   - System: /run/secrets/<name>
   - User: /run/user/<uid>/secrets/<name>
5. Sets ownership and permissions
6. Secrets cleared on reboot (tmpfs)
```

**Security**:
- Secrets never written to disk in plaintext
- Deployed to tmpfs (memory-backed filesystem)
- Cleared on logout/reboot
- Mode 0400 (read-only for owner)

#### 5. Validation and Maintenance

```bash
# Validate all correspondences
export BW_SESSION=$(bw unlock --raw)
just sops-validate-correspondences
bw lock

# Test secret decryption
just validate-secrets

# Re-encrypt after key changes
find secrets/ -name "*.yaml" -type f -exec sops updatekeys {} \;
```

### Key Rotation

```bash
# Full rotation workflow
export BW_SESSION=$(bw unlock --raw)
just sops-rotate
bw lock

# This runs:
# 1. Extract keys from Bitwarden
# 2. Update .sops.yaml
# 3. Re-encrypt all secrets
# 4. Validate correspondences
# 5. Update GitHub CI secret (if applicable)
```

## System 2: Unified Cryptographic Infrastructure (New)

### Purpose
Single SSH key serving three purposes:
- **Radicle node identity**: P2P repository synchronization
- **Git commit signing**: SSH-based commit verification
- **Jujutsu commit signing**: Shared SSH signature verification

### Location
- **Repository**: `~/projects/nix-workspace/nix-secrets/` (separate from nix-config)
- **Secrets directory**: `hosts/<hostname>/secrets/`
- **Configuration**: `.sops.yaml` (root of nix-secrets)

### Architecture: Single Key Pattern

```
┌─────────────────────────────────────────────────────────┐
│ Same Bitwarden Entry                                    │
├─────────────────────────────────────────────────────────┤
│ sops-admin-user-ssh (Ed25519)                          │
│ ├─ Private: ~/.ssh/id_ed25519                          │
│ ├─ Public: ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAA...    │
│ └─ Age: age1vn8fpkmkzkjttcuc3prq3jrp7t5fs... (&admin-user)│
└─────────────────────────────────────────────────────────┘
                         │
                         ▼
         ┌───────────────────────────────┐
         │ Encrypted in nix-secrets      │
         │ Repository                    │
         ├───────────────────────────────┤
         │ radicle/ssh-private-key       │
         │ (SOPS-encrypted copy of       │
         │  ~/.ssh/id_ed25519)           │
         └───────────────────────────────┘
                         │
                         ▼
         ┌───────────────────────────────┐
         │ Exposed via Flake             │
         ├───────────────────────────────┤
         │ inputs.secrets.secrets        │
         │   .stibnite.radicle           │
         └───────────────────────────────┘
                         │
         ┌───────────────┴───────────────┐
         │                               │
         ▼                               ▼
┌─────────────────┐         ┌─────────────────────┐
│ nix-config      │         │ SOPS Deployment     │
│ References      │         │ at Activation       │
├─────────────────┤         ├─────────────────────┤
│ Git signing     │────────>│ ~/.radicle/keys/    │
│ Jujutsu signing │         │ radicle             │
│ Radicle identity│         │                     │
│                 │         │ Mode: 0400          │
│ All use same    │         │ Cleared on reboot   │
│ SOPS path       │         └─────────────────────┘
└─────────────────┘
```

### End-to-End Workflow

#### 1. Secrets Repository Setup (One-time)

```bash
# Create nix-secrets repository
cd ~/projects/nix-workspace/nix-secrets
git init

# Create flake.nix exposing secret paths
cat > flake.nix << 'EOF'
{
  description = "SOPS-encrypted secrets for nix-config";

  outputs = { self, ... }: {
    secrets = {
      stibnite = {
        radicle = ./hosts/stibnite/secrets/radicle.yaml;
        test = ./shared/test.yaml;
      };
      # ... other hosts
    };
  };
}
EOF

# Create .sops.yaml with single key
cat > .sops.yaml << 'EOF'
keys:
  - &admin-user age1vn8fpkmkzkjttcuc3prq3jrp7t5fs...

creation_rules:
  - path_regex: hosts/stibnite/.*\.yaml$
    key_groups:
      - age: [*admin-user]
EOF
```

#### 2. Encrypt Unified SSH Key

```bash
# Create directory structure
mkdir -p hosts/stibnite/secrets

# Create unencrypted YAML with SSH private key
cat > /tmp/radicle-temp.yaml << 'EOF'
radicle:
  ssh-private-key: |
EOF
cat ~/.ssh/id_ed25519 | sed 's/^/    /' >> /tmp/radicle-temp.yaml

# Move to final location and encrypt in-place
mv /tmp/radicle-temp.yaml hosts/stibnite/secrets/radicle.yaml
sops -e -i hosts/stibnite/secrets/radicle.yaml

# Verify encryption worked
sops -d hosts/stibnite/secrets/radicle.yaml | head -5

# Commit encrypted file (safe)
git add .
git commit -m "feat: add encrypted radicle SSH key"
```

**Security**: Original `~/.ssh/id_ed25519` remains unchanged. We only create an encrypted copy in the secrets repo.

#### 3. Add Secrets as Flake Input (nix-config)

```nix
// In ~/projects/nix-workspace/nix-config/flake.nix

inputs = {
  // ... other inputs ...

  // Secrets repository (local for now, will move to Radicle)
  secrets.url = "git+file:///Users/crs58/projects/nix-workspace/nix-secrets";
  secrets.flake = true;
};
```

```bash
# Update flake lock
nix flake lock --update-input secrets
```

#### 4. Reference Secrets in Configuration

**Pattern used in git.nix and jujutsu.nix**:

```nix
{
  pkgs,
  flake,
  config,
  lib,
  ...
}:
let
  inherit (flake) inputs;
  hostname = "stibnite"; # TODO: Make dynamic
in
{
  programs.git = {
    signing = {
      # Use SOPS-deployed key
      key = config.sops.secrets."radicle/ssh-private-key".path;
      format = "ssh";
      signByDefault = true;
    };
  };

  # Declare SOPS secret with explicit sopsFile
  # This OVERRIDES the defaultSopsFile from System 1
  sops.secrets."radicle/ssh-private-key" = {
    sopsFile = inputs.secrets.secrets.${hostname}.radicle;
    mode = "0400";
  };
}
```

**Key points**:
- `sopsFile = inputs.secrets.secrets.stibnite.radicle` - References nix-secrets flake
- Overrides `defaultSopsFile` from System 1
- Same secret declared in git.nix, jujutsu.nix, and radicle.nix
- SOPS-nix handles deduplication (only deployed once)

#### 5. Deployment and Usage

On `darwin-rebuild switch`:

```
1. SOPS-nix activates
2. Reads ~/.config/sops/age/keys.txt (contains admin-user key)
3. Decrypts radicle/ssh-private-key using admin-user Age key
4. Deploys to /run/user/<uid>/secrets/radicle/ssh-private-key
5. Creates symlink: ~/.radicle/keys/radicle -> SOPS secret path
6. Git, Jujutsu, Radicle all reference the same deployed key
```

**Usage after deployment**:
```bash
# Git signing (automatic)
git commit -m "Test commit"
git log --show-signature -1
# Output: Good "git" signature for cameron.ray.smith@gmail.com...

# Jujutsu signing (automatic)
jj new -m "Test commit"
jj log -r @ -T 'signature'
# Output: shows signature status

# Radicle identity
rad self
# Uses ~/.radicle/keys/radicle for node identity
```

## How Both Systems Work Together

### Shared Infrastructure

```
┌────────────────────────────────────────────────────────┐
│ Bitwarden: Single Source of Truth                     │
│ sops-admin-user-ssh                                    │
│ ├─ Used in System 1 as &admin-user (one of 8 keys)   │
│ └─ Used in System 2 as sole encryption key           │
└────────────────────────────────────────────────────────┘
                         │
                         ▼
┌────────────────────────────────────────────────────────┐
│ Age Private Key: ~/.config/sops/age/keys.txt          │
│ age1vn8fpkmkzkjttcuc3prq3jrp7t5fsrdqey...             │
│ (Derived from sops-admin-user-ssh)                    │
│                                                        │
│ Used by BOTH systems to decrypt secrets               │
└────────────────────────────────────────────────────────┘
         │                               │
         ▼                               ▼
┌──────────────────┐         ┌──────────────────────┐
│ System 1         │         │ System 2             │
│ secrets/         │         │ nix-secrets/         │
├──────────────────┤         ├──────────────────────┤
│ 8 recipient keys │         │ 1 recipient key      │
│ Multi-key decrypt│         │ Single-key decrypt   │
│ General secrets  │         │ Unified crypto key   │
│                  │         │                      │
│ Uses:            │         │ Uses:                │
│ defaultSopsFile  │         │ explicit sopsFile    │
└──────────────────┘         └──────────────────────┘
```

### Configuration Hierarchy

**In modules/home/all/core/sops.nix**:
```nix
{
  # Age key location (SHARED by both systems)
  sops.age.keyFile = "${config.xdg.configHome}/sops/age/keys.txt";

  # Default for System 1 (can be overridden)
  sops.defaultSopsFile = flake.inputs.self + "/secrets/shared.yaml";
}
```

**In specific modules (git.nix, jujutsu.nix)**:
```nix
{
  # System 2 secret (overrides default)
  sops.secrets."radicle/ssh-private-key" = {
    sopsFile = inputs.secrets.secrets.stibnite.radicle;  # System 2
    mode = "0400";
  };

  # Other secrets can still use System 1
  sops.secrets."github/token" = {
    # Uses defaultSopsFile (System 1)
  };
}
```

### Decision Matrix: Which System to Use?

| Secret Type | System | Reason |
|------------|--------|--------|
| User passwords | System 1 | Multi-host access needed |
| API tokens | System 1 | Shared across team/hosts |
| Host SSH keys | System 1 | Host-specific decryption |
| Network configs | System 1 | Per-host configuration |
| Radicle SSH key | System 2 | Single unified identity |
| Git signing key | System 2 | Same as Radicle key |
| Jujutsu signing | System 2 | Same as Radicle key |

### Migration Path

**Current state**: Both systems coexist peacefully
- System 1: Production, stable, no changes needed
- System 2: New, proving effectiveness

**Future options**:

**Option A: Keep both** (recommended for now)
- System 1 for infrastructure secrets
- System 2 for cryptographic identity
- Clear separation of concerns

**Option B: Gradual migration**
```bash
# As System 2 proves effective, migrate secrets one by one:
# 1. Move secret from secrets/ to nix-secrets/
# 2. Update module to use explicit sopsFile
# 3. Test thoroughly
# 4. Remove from System 1
```

**Option C: Full migration**
```bash
# When System 2 is proven:
# 1. Move all secrets to nix-secrets repository
# 2. Update all modules to use explicit sopsFile
# 3. Remove System 1 secrets/ directory
# 4. Remove defaultSopsFile from sops.nix
```

## Troubleshooting

### Secrets won't decrypt

**Check which Age key you have**:
```bash
cat ~/.config/sops/age/keys.txt
# Should contain: AGE-SECRET-KEY-1...
```

**Regenerate from Bitwarden**:
```bash
export BW_SESSION=$(bw unlock --raw)
just sops-sync-keys  # System 1
bw lock
```

**Test decryption**:
```bash
# System 1
sops -d secrets/shared.yaml

# System 2
sops -d ~/projects/nix-workspace/nix-secrets/hosts/stibnite/secrets/radicle.yaml
```

### Which sopsFile is being used?

**Check SOPS configuration**:
```bash
# In a module
nix eval .#darwinConfigurations.stibnite.config.home-manager.users.crs58.sops.secrets.\"radicle/ssh-private-key\".sopsFile --json

# Should show:
# System 1 secret: "/nix/store/.../secrets/shared.yaml"
# System 2 secret: "/nix/store/.../nix-secrets/.../radicle.yaml"
```

### SOPS-nix can't find Age key

**Verify Age key location**:
```bash
ls -la ~/.config/sops/age/keys.txt

# On macOS, also check:
ls -la ~/Library/Application\ Support/sops/age/keys.txt
```

**Ensure SOPS config points to correct location**:
```nix
# In sops.nix
sops.age.keyFile = "${config.xdg.configHome}/sops/age/keys.txt";
```

### Secret deployed to wrong location

**Check deployment path**:
```bash
# System secrets: /run/secrets/<name>
ls -la /run/secrets/

# User secrets: /run/user/<uid>/secrets/<name>
ls -la /run/user/$(id -u)/secrets/
```

**Check in configuration**:
```nix
# Use the deployed path
config.sops.secrets."secret-name".path
# Returns: "/run/user/501/secrets/secret-name"
```

## Reference Documentation

- **System 1 Migration**: [sops-migration-summary.md](./sops-migration-summary.md)
- **System 2 Implementation**: [unified-crypto-infrastructure-implementation.md](./unified-crypto-infrastructure-implementation.md)
- **test-secrets**: `~/projects/nix-workspace/test-secrets/` (validation environment)
- **SOPS**: https://github.com/getsops/sops
- **Age**: https://github.com/FiloSottile/age
- **SOPS-nix**: https://github.com/Mic92/sops-nix

## Summary

**Two systems, one Age key**:
- System 1 (existing): Multi-key secrets for infrastructure
- System 2 (new): Single-key unified crypto for Radicle + Git + Jujutsu
- Both use same Age key for decryption
- Both can coexist indefinitely
- Gradual migration possible when System 2 proves effective

**Key workflows**:
- System 1: `bw unlock` → `just sops-update-yaml` → `sops secrets/...` → commit
- System 2: `sops nix-secrets/hosts/.../radicle.yaml` → commit → reference via `inputs.secrets`

**Deployment**:
- Both deploy via SOPS-nix at activation time
- System 1: Uses defaultSopsFile or per-secret sopsFile
- System 2: Always uses explicit sopsFile from nix-secrets flake
- All secrets deployed to tmpfs (cleared on reboot)
