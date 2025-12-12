---
title: Secrets Management
description: Managing secrets using clan vars and legacy sops-nix during migration
sidebar:
  order: 7
---

This guide documents secrets management in the infrastructure.
Clan vars is the target for all secrets, with legacy sops-nix secrets pending migration.

## Secrets architecture overview

The infrastructure is migrating to clan vars for all secrets management.
Currently some secrets remain in legacy sops-nix format pending migration.
See [Clan Integration](/concepts/clan-integration#secrets-management) for the complete architectural explanation.

For a learning-oriented walkthrough of setting up secrets from scratch, see the [Secrets Setup Tutorial](/tutorials/secrets-setup/).

| Status | Tool | Purpose | Platforms | Generation |
|--------|------|---------|-----------|------------|
| Target | Clan vars | All secrets (system and user) | NixOS (darwin support planned) | Automatic (`clan vars generate`) |
| Legacy | sops-nix | User secrets pending migration | All (darwin + NixOS) | Manual (age key derivation) |

### Current usage patterns

During migration, secrets are split between two systems:

**Clan vars** currently handles auto-generated, machine-specific secrets on NixOS hosts.
The vars generator creates SSH keys, zerotier IDs, and other secrets that machines need automatically.
This is the target state for all secrets once migration is complete.

**sops-nix** currently handles manually-entered user secrets on all platforms.
API tokens, personal credentials, and signing keys are created by humans using age encryption.
These will migrate to clan vars when user-level vars support is implemented.

## Clan vars (target state)

Clan vars is the target for all secrets management.
Currently deployed on NixOS hosts (cinnabar, electrum, galena, scheelite) for system secrets.

### Current clan vars usage

- **SSH host keys** - Machine identity for SSH
- **Zerotier identities** - Network identity for mesh VPN
- **LUKS passphrases** - Disk encryption secrets
- **Service credentials** - Machine-specific service secrets

### Key commands

```bash
# Generate secrets for a machine
clan vars generate cinnabar

# View a specific secret
clan vars get cinnabar ssh.id_ed25519.pub

# Deploy secrets to machine (secrets deploy automatically)
clan machines update cinnabar
```

### Directory structure

Generated secrets are stored encrypted in the vars directory:

```
machines/
└── nixos/
    └── cinnabar/
        └── vars/
            ├── ssh.id_ed25519/
            │   ├── secret   # Private key (encrypted)
            │   └── public   # Public key
            └── zerotier/
                └── identity.secret
```

### Secrets location on target

Clan vars deploys secrets to `/run/secrets/` on NixOS machines during system activation.

```bash
# On cinnabar (NixOS)
ls /run/secrets/
# ssh.id_ed25519  zerotier/identity.secret
```

### Rotation procedure

To rotate clan vars secrets:

```bash
# Regenerate secrets for a machine
clan vars generate cinnabar

# Deploy the new secrets
clan machines update cinnabar
```

Service restart may be required after rotation depending on which secrets changed.

## Legacy sops-nix (migration pending)

sops-nix currently handles user-level secrets that require manual creation.
Available on all platforms (darwin and NixOS) pending migration to clan vars.

### Current sops-nix usage

- **GitHub tokens** - Personal access tokens, signing keys
- **API keys** - Anthropic, OpenAI, and other service credentials
- **Personal credentials** - User-specific service passwords
- **MCP server secrets** - Model Context Protocol authentication

### Age key bootstrap workflow

The age private key used by sops-nix is derived from your Bitwarden-managed SSH key using `ssh-to-age`.
This manual bootstrap step is intentional for security.

#### Bitwarden as source of truth

This infrastructure uses Bitwarden as the authoritative source for SSH keys from which age keys are deterministically derived.
SSH keys are stored in Bitwarden as items named `sops-{identifier}-ssh` (e.g., `sops-crs58-ssh`, `sops-raquel-ssh`).
Age keys are derived using `ssh-to-age`, which means the same SSH key always produces the same age key.

Three contexts must have corresponding keys for proper secrets management:

1. **Clan user key** in `sops/users/{user}/key.json` (age public key)
2. **YAML anchor** in `.sops.yaml` (age public key, e.g., `&admin-user`)
3. **Workstation keyfile** at `~/.config/sops/age/keys.txt` (age private key)

All three must correspond to the same SSH keypair stored in Bitwarden.
The justfile provides automation for maintaining this correspondence.

#### Justfile automation

The infrastructure provides justfile recipes for managing Bitwarden-derived age keys:

**Extract and display all age public keys:**
```bash
just sops-extract-keys
```
This retrieves all `sops-*-ssh` items from Bitwarden and displays their corresponding age public keys.

**Regenerate workstation keyfile from Bitwarden:**
```bash
just sops-sync-keys
```
This extracts your SSH private key from Bitwarden and regenerates `~/.config/sops/age/keys.txt`.

**Validate three-context correspondence:**
```bash
just sops-validate-correspondences
```
This checks that clan user keys, `.sops.yaml` anchors, and workstation keyfiles all correspond to the same Bitwarden SSH keys.

**Full key rotation workflow:**
```bash
just sops-rotate
```
This orchestrates the complete key rotation process including validation, re-encryption, and deployment.

#### Three-context validation

Proper secrets management requires consistency across three distinct contexts:

**Context 1: Clan user key** (`sops/users/{user}/key.json`)
This file contains the age public key for the user's clan identity.
It is used by clan commands and must match the user's Bitwarden SSH key.

**Context 2: YAML anchor** (`.sops.yaml`)
The age public key is referenced as a YAML anchor (e.g., `&admin-user`) in creation rules.
This controls which keys can decrypt specific secrets files.

**Context 3: Workstation keyfile** (`~/.config/sops/age/keys.txt`)
The age private key must exist on the workstation to decrypt secrets during configuration builds.
This is generated from the SSH private key in Bitwarden.

**Validation example:**
```bash
# Extract public key from clan user
cat sops/users/crs58/key.json | jq -r '.publickey'

# Extract public key from .sops.yaml
grep "admin-user" .sops.yaml | awk '{print $3}'

# Derive public key from workstation keyfile
age-keygen -y ~/.config/sops/age/keys.txt

# All three outputs must match for proper operation
```

The `just sops-validate-correspondences` recipe automates this verification.

#### Required tools

| Tool | Purpose | Installation |
|------|---------|--------------|
| `bw` | Bitwarden CLI for SSH key retrieval | `nix-shell -p bitwarden-cli` |
| `ssh-to-age` | Derive age keys from SSH keys | `nix-shell -p ssh-to-age` |
| `sops` | Encrypt/decrypt secrets files | `nix-shell -p sops` |
| `age` | Age encryption (for verification) | `nix-shell -p age` |

#### Bootstrap procedure

**Step 1: Unlock Bitwarden vault**

```bash
# Login to Bitwarden CLI (if not already logged in)
bw login

# Unlock vault and set session
export BW_SESSION=$(bw unlock --raw)
```

**Step 2: Derive age keys from Bitwarden SSH key**

```bash
# Derive age public key (for .sops.yaml and clan user)
age_pub=$(bw get item "sops-myuser-ssh" | jq -r '.login.password' | ssh-to-age)

# Derive age private key (for workstation keyfile)
age_priv=$(bw get item "sops-myuser-ssh" | jq -r '.notes' | ssh-to-age -private-key)

# Validate format (age public keys are 63 characters starting with 'age1')
[[ $age_pub =~ ^age1[a-z0-9]{58}$ ]] && echo "Valid public key format"

# Validate private key format
[[ $age_priv =~ ^AGE-SECRET-KEY- ]] && echo "Valid private key format"
```

**Step 3: Deploy age private key to workstation**

```bash
# Create sops directory if it doesn't exist
mkdir -p ~/.config/sops/age

# Write age private key to workstation keyfile
echo "$age_priv" > ~/.config/sops/age/keys.txt

# Set restrictive permissions
chmod 600 ~/.config/sops/age/keys.txt

# Verify age key exists
cat ~/.config/sops/age/keys.txt | head -1
# Should show: AGE-SECRET-KEY-...
```

**Step 4: Update clan user and .sops.yaml with public key**

```bash
# Add public key to .sops.yaml as YAML anchor
# Edit .sops.yaml and add line like:
#   - &myuser age1abc...xyz

# Create or update clan user key file
mkdir -p sops/users/myuser
echo "{\"publickey\": \"$age_pub\"}" > sops/users/myuser/key.json

# Lock Bitwarden vault
bw lock
```

**Step 5: Validate three-context correspondence**

```bash
# Use justfile validation recipe
just sops-validate-correspondences

# Or validate manually (see "Three-context validation" above)
```

#### Platform-specific notes

**Darwin laptops (stibnite, blackphos, rosegold, argentum):**
Bitwarden Desktop can serve as an SSH agent, allowing age keys to be derived on-demand without storing SSH private keys on disk.
The workstation keyfile (`~/.config/sops/age/keys.txt`) must still be manually created using the bootstrap procedure.

**NixOS servers (cinnabar, electrum, galena, scheelite):**
No GUI available, so use `bw` CLI to extract SSH keys and derive age keys.
Deploy the age private key to `~/.config/sops/age/keys.txt` before running configuration builds that require secrets decryption.

**CI/CD environments:**
Store the age private key as a repository secret (e.g., `SOPS_AGE_KEY` in GitHub Actions).
The CI runner exports this as `SOPS_AGE_KEY_FILE` environment variable for sops to use during builds.

#### Security rationale

The manual bootstrap is intentional for security:

1. **SSH keys remain in Bitwarden** - Not stored in nix store or git
2. **Age keys derived locally** - Private key material never transmitted
3. **User controls bootstrap** - Each user manages their own key derivation
4. **Defense in depth** - Compromising the nix config doesn't expose private keys
5. **Deterministic derivation** - Same SSH key always produces same age key, enabling validation

### Adding your key to .sops.yaml

After generating your age public key, add it to `.sops.yaml`:

```yaml
keys:
  # User keys (legacy sops-nix)
  - &crs58-stibnite age1abc...xyz
  - &raquel-blackphos age1def...uvw

creation_rules:
  - path_regex: secrets/users/crs58\.sops\.yaml$
    key_groups:
      - age:
        - *crs58-stibnite

  - path_regex: secrets/users/raquel\.sops\.yaml$
    key_groups:
      - age:
        - *raquel-blackphos
```

### Creating and editing secrets

```bash
# Create new secrets file
sops secrets/users/crs58.sops.yaml

# Edit existing secrets
sops secrets/users/crs58.sops.yaml

# View decrypted secrets (read-only)
sops -d secrets/users/crs58.sops.yaml
```

Example secrets file structure:

```yaml
# secrets/users/crs58.sops.yaml
github-signing-key: |
  -----BEGIN OPENSSH PRIVATE KEY-----
  ...
  -----END OPENSSH PRIVATE KEY-----
github-token: ghp_xxxxxxxxxxxxxxxxxxxx
anthropic-api-key: sk-ant-xxxxxxxxxxxxxxxx
ssh-public-key: ssh-ed25519 AAAA... crs58@stibnite
```

### Home-manager integration

Reference secrets in home-manager modules using `sops.secrets`:

```nix
# modules/home/users/crs58/default.nix
{ config, inputs, ... }:
{
  sops.secrets = {
    "users/crs58/github-signing-key" = {
      sopsFile = "${inputs.self}/secrets/users/crs58.sops.yaml";
    };
    "users/crs58/github-token" = {
      sopsFile = "${inputs.self}/secrets/users/crs58.sops.yaml";
    };
  };
}
```

Use secrets in configuration:

```nix
# Git signing key
programs.git.signing.key = config.sops.secrets."users/crs58/github-signing-key".path;

# Environment variable from secret
home.sessionVariables = {
  ANTHROPIC_API_KEY = "$(cat ${config.sops.secrets."users/crs58/anthropic-api-key".path})";
};
```

### Secrets location on target

sops-nix decrypts secrets during home-manager activation to:

```bash
# Check decrypted secrets location
ls ~/.config/sops-nix/secrets/

# Secrets are symlinked from this location
readlink -f ~/.config/sops-nix/secrets/users-crs58-github-token
```

### Rotation procedure

To rotate sops-nix secrets:

```bash
# 1. Edit the encrypted secrets file
sops secrets/users/crs58.sops.yaml

# 2. Update the secret value

# 3. Save and exit (sops re-encrypts automatically)

# 4. Rebuild configuration to deploy
darwin-rebuild switch --flake .#stibnite  # darwin
# OR
clan machines update cinnabar  # NixOS (includes home-manager)
```

### Adding a new key recipient

When adding a new machine or user that needs access to existing secrets:

```bash
# 1. Add public key to .sops.yaml
# Edit .sops.yaml and add the new key anchor

# 2. Update all affected secrets files with the new key
sops updatekeys secrets/users/crs58.sops.yaml

# 3. Commit the updated .sops.yaml and re-encrypted files
```

## Platform-specific workflows

### Darwin (stibnite, blackphos, rosegold, argentum)

Darwin hosts currently use **legacy sops-nix only**.
Clan vars support for darwin is planned but not yet implemented.

**Secrets workflow:**

1. Bootstrap age key from Bitwarden SSH key (see [Age key bootstrap](#age-key-bootstrap-workflow))
2. Create user secrets file: `sops secrets/users/<username>.sops.yaml`
3. Configure home-manager sops module
4. Deploy: `darwin-rebuild switch --flake .#<hostname>`

**Secrets deployment:**

- Automatic during home-manager activation
- Location: `~/.config/sops-nix/secrets/`
- No system-level secrets (no `/run/secrets/`)

### NixOS (cinnabar, electrum, galena, scheelite)

NixOS hosts use clan vars for system secrets and legacy sops-nix for user secrets.

**Clan vars workflow (system secrets):**

```bash
# Generate machine secrets
clan vars generate cinnabar

# Deploy (includes secrets)
clan machines update cinnabar
```

**Legacy sops-nix workflow (user secrets):**

Same as darwin - bootstrap age key, create sops secrets, configure home-manager.

**Secrets deployment:**

- Clan vars: `/run/secrets/` (system activation)
- sops-nix: `~/.config/sops-nix/secrets/` (home-manager activation)

### Platform comparison

| Aspect | Darwin | NixOS |
|--------|--------|-------|
| Clan vars | Not yet implemented | `clan vars generate`, `/run/secrets/` |
| Legacy sops-nix | Age key + home-manager | Age key + home-manager |
| SSH host keys | Manual or existing | Clan vars generated |
| Zerotier identity | Homebrew generates | Clan vars generated |
| User API keys | sops-nix (legacy) | sops-nix (legacy) |
| Deployment | `darwin-rebuild switch` | `clan machines update` |

## Working with secrets

### Creating new secrets

**For user-level secrets (legacy sops-nix):**

```bash
# 1. Edit or create secrets file
sops secrets/users/<username>.sops.yaml

# 2. Add the new secret
# my-new-secret: secret-value-here

# 3. Reference in home-manager module
# sops.secrets."users/<username>/my-new-secret" = { ... };

# 4. Deploy configuration
darwin-rebuild switch --flake .#<hostname>
```

**For system-level secrets (clan vars - NixOS only):**

System secrets are typically auto-generated by clan vars.
For custom system secrets, use clan vars generators or add to the machine's vars configuration.

### Editing existing secrets

```bash
# Open in editor (decrypts → edit → re-encrypts)
sops secrets/users/crs58.sops.yaml

# Make changes and save
# sops handles encryption automatically
```

### Viewing secrets

```bash
# View decrypted content
sops -d secrets/users/crs58.sops.yaml

# View specific secret (requires jq)
sops -d secrets/users/crs58.sops.yaml | yq '.github-token'
```

### Verifying encryption

```bash
# Check file is encrypted (should show sops metadata)
head secrets/users/crs58.sops.yaml

# Expected: sops: section with mac, lastmodified, etc.
```

## Troubleshooting

### Clan vars issues (NixOS)

**Vars not generating:**

```bash
# Verify machine is registered in clan
clan machines list

# Check vars generator configuration
cat modules/clan/machines.nix

# Regenerate vars
clan vars generate <hostname>
```

**Secrets not appearing at /run/secrets/:**

```bash
# Verify deployment
clan machines update <hostname>

# Check systemd service
systemctl status sops-nix

# Check secrets directory permissions
ls -la /run/secrets/
```

**Permission denied on secrets:**

```bash
# Check owner/group on secret
ls -la /run/secrets/<secret-name>

# Verify user is in correct group
groups $(whoami)
```

### Legacy sops-nix issues (all platforms)

**Cannot decrypt sops file:**

```bash
# Verify age key exists
cat ~/.config/sops/age/keys.txt | head -1
# Should show: AGE-SECRET-KEY-...

# Check your public key is in .sops.yaml
age-keygen -y ~/.config/sops/age/keys.txt
# Compare output with keys in .sops.yaml

# Test decryption explicitly
SOPS_AGE_KEY_FILE=~/.config/sops/age/keys.txt sops -d secrets/users/<user>.sops.yaml
```

**Age key not found:**

```bash
# Check key file location
ls -la ~/.config/sops/age/keys.txt

# If missing, re-bootstrap from Bitwarden (see Age key bootstrap workflow)
```

**sops.secrets not appearing in home-manager:**

```bash
# Verify sops module is imported
# Check home-manager configuration includes sops-nix

# Verify sopsFile path is correct
# Path should be: "${inputs.self}/secrets/users/<username>.sops.yaml"

# Rebuild and check for errors
darwin-rebuild switch --flake .#<hostname> 2>&1 | grep -i sops
```

**Secret path mismatch:**

```bash
# Check actual decrypted secret location
ls ~/.config/sops-nix/secrets/

# Secret names use dashes instead of slashes
# users/crs58/github-token → users-crs58-github-token
```

### Common errors

**"could not decrypt data key":**
- Your age public key is not in the creation rules for this file
- Solution: Add key to `.sops.yaml` and run `sops updatekeys <file>`

**"no key could be found":**
- Age key file missing or empty
- Solution: Re-bootstrap age key from Bitwarden

**"MAC mismatch":**
- File was modified without proper re-encryption
- Solution: Re-encrypt the file: `sops -e -i <file>`

## See also

- [Clan Integration](/concepts/clan-integration) - Secrets implementation architecture
- [Host Onboarding](/guides/host-onboarding) - Platform-specific setup steps
- [Home-Manager Onboarding](/guides/home-manager-onboarding) - User module patterns

## External references

- [sops documentation](https://github.com/getsops/sops) - SOPS encryption tool
- [age encryption](https://age-encryption.org/) - Age key management
- [ssh-to-age](https://github.com/Mic92/ssh-to-age) - SSH to age key derivation
- [sops-nix](https://github.com/Mic92/sops-nix) - Nix integration for sops
- [clan vars documentation](https://clan.lol/) - Clan vars system
