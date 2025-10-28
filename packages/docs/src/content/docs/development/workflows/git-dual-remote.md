---
title: "Dual-Remote Workflow: GitHub + Radicle"
---

# Dual-Remote Workflow: GitHub + Radicle

This document describes the current secrets management setup using GitHub as the primary remote with Radicle as a secondary remote for future migration.

## Current Setup

### Primary Remote: GitHub (Private)
```bash
origin  https://github.com/cameronraysmith/nix-secrets
```

**Purpose**:
- Production secrets source for Nix flake
- CI/CD compatible (GITHUB_TOKEN)
- Multi-device access via `gh auth`
- Private repository with SOPS encryption

**Flake Input**:
```nix
secrets.url = "github:cameronraysmith/nix-secrets";
```

### Secondary Remote: Radicle (Private, Local)
```bash
rad  rad://z2qTVkuBMHn82UyKbfT2NyyC5EaEH
```

**Purpose**:
- Experimental decentralized infrastructure
- Learning Radicle ecosystem
- Future migration path to radicle-httpd

**Repository ID**: `rad:z2qTVkuBMHn82UyKbfT2NyyC5EaEH`

## Daily Workflow

### Making Changes

```bash
# Navigate to secrets repo
cd ~/projects/nix-workspace/nix-secrets

# Make changes to secrets
# ... edit files ...

# Commit changes
git add .
git commit -m "feat(secrets): update XYZ"

# Push to both remotes
git push origin main    # Primary: GitHub
git push rad main       # Secondary: Radicle
```

### Using Secrets in nix-config

```bash
cd ~/projects/nix-workspace/nix-config

# Nix automatically fetches from GitHub
nix flake update secrets  # Update to latest from GitHub
darwin-rebuild switch --flake .#stibnite  # Uses secrets from GitHub
```

## Authentication Setup

### GitHub Authentication

**One-time setup per machine**:
```bash
# Authenticate with GitHub CLI
gh auth login

# Configure Nix to use GitHub token
echo "access-tokens = github.com=$(gh auth token)" >> ~/.config/nix/nix.conf
```

**Verification**:
```bash
gh auth status
nix flake metadata github:cameronraysmith/nix-secrets  # Should work
```

### Radicle Authentication

**One-time setup per machine**:
```bash
# Start Radicle node
rad node start  # Enter passphrase when prompted

# Clone secrets repo locally
cd /tmp
rad clone rad:z2qTVkuBMHn82UyKbfT2NyyC5EaEH
```

## Adding a New Device

### For nix-config Access

```bash
# New device setup
gh auth login  # Authenticate with GitHub
echo "access-tokens = github.com=$(gh auth token)" >> ~/.config/nix/nix.conf

# Clone nix-config
git clone https://github.com/cameronraysmith/nix-config.git

# Build configuration (secrets fetched automatically)
cd nix-config
darwin-rebuild switch --flake .#<hostname>
```

### For nix-secrets Editing

```bash
# Clone with both remotes
gh repo clone cameronraysmith/nix-secrets
cd nix-secrets

# Add Radicle remote (optional)
rad clone rad:z2qTVkuBMHn82UyKbfT2NyyC5EaEH
cd nix-secrets
git remote add rad rad://z2qTVkuBMHn82UyKbfT2NyyC5EaEH
```

## CI/CD Integration

**GitHub Actions** automatically has access to private repos:
```yaml
# In .github/workflows/ci.yaml
- name: checkout
  uses: actions/checkout@v4
  # GITHUB_TOKEN automatically provides access to cameronraysmith/nix-secrets

- name: build config
  run: nix build .#darwinConfigurations.stibnite.config.system.build.toplevel
  # Nix uses GITHUB_TOKEN to fetch private secrets repo
```

No additional configuration needed!

## Future Migration to radicle-httpd

When ready to migrate to self-hosted Radicle:

### Step 1: Setup radicle-httpd Server
```bash
# On VPS or home server
# Setup radicle-httpd with HTTPS
# Configure authentication
```

### Step 2: Rotate Secrets
```bash
cd ~/projects/nix-workspace/nix-secrets

# Generate new Age key
age-keygen -o ~/.config/sops/age/keys-new.txt

# Re-encrypt all secrets with new key
# Update .sops.yaml with new recipient
# Re-encrypt: sops updatekeys hosts/*/secrets/*.yaml shared/*.yaml

# Update nix-config Age key reference
```

### Step 3: Make Radicle Repo Private
```bash
cd ~/projects/nix-workspace/nix-secrets

# Make Radicle repo private (if it was public)
rad id update --visibility private --title "Migrate to private"

# Add additional devices as delegates if needed
rad id update --add <device-DID> --title "Add device XYZ"
```

### Step 4: Update nix-config Flake Input
```nix
# Change from GitHub to radicle-httpd
secrets.url = "git+https://radicle.your-domain.com/z2qTVkuBMHn82UyKbfT2NyyC5EaEH.git";
```

### Step 5: Update CI Configuration
```yaml
# Configure CI to access radicle-httpd
# Add authentication credentials as secrets
# Update workflow to authenticate
```

## Reference Patterns

### Similar Configurations
- **fred-drake/nix-secrets**: Uses `git+ssh://git@github.com/fred-drake/nix-secrets.git`
- **Our approach**: Uses `github:cameronraysmith/nix-secrets` for better CI integration
- **defelo-nixos**: Uses `git+https://radicle.defelo.de/z2Wg1t47Ahi5sJqWKqPBVcf1DqB2A.git` (radicle-httpd)

### Documentation
- Main implementation: `docs/notes/secrets/unified-crypto-infrastructure-implementation.md`
- End-to-end workflow: `docs/notes/secrets/end-to-end-workflow.md`
- System comparison: Documents System 1 (multi-key) vs System 2 (unified crypto)

## Troubleshooting

### Nix Cannot Access Private GitHub Repo

**Symptom**: `error: unable to download ... HTTP error 404`

**Solution**:
```bash
# Verify gh auth
gh auth status

# Add GitHub token to Nix
echo "access-tokens = github.com=$(gh auth token)" >> ~/.config/nix/nix.conf

# Retry
nix flake update secrets
```

### Radicle Push Fails

**Symptom**: `error: A passphrase is required`

**Solution**:
```bash
# Start Radicle node
export RAD_PASSPHRASE=""  # Or set your passphrase
rad node start

# Retry push
git push rad main
```

### Secret Deployment Fails

**Symptom**: SOPS cannot decrypt secrets

**Solution**:
```bash
# Verify Age key exists
cat ~/.config/sops/age/keys.txt

# Check Age public key matches .sops.yaml
age-keygen -y ~/.config/sops/age/keys.txt
# Compare with recipient in nix-secrets/.sops.yaml

# Verify SOPS can decrypt
cd ~/projects/nix-workspace/nix-secrets
sops -d hosts/stibnite/secrets/radicle.yaml
```

## Security Notes

### Defense in Depth
1. **Repository access control**: Private GitHub repo (authentication required)
2. **SOPS encryption**: All secret values encrypted with Age
3. **Age key protection**: Private key never committed, stored in `~/.config/sops/age/keys.txt`

### Key Rotation Schedule
- **Immediate**: When key potentially compromised
- **Planned**: Before migrating to radicle-httpd
- **Regular**: Every 1-2 years for good practice

### GitHub Token Management
- Token stored in `~/.config/nix/nix.conf`
- **Do not commit** this file
- Regenerate token if exposed: `gh auth refresh`

## Repository Status

**nix-secrets**:
- Location: `~/projects/nix-workspace/nix-secrets`
- Primary remote: `https://github.com/cameronraysmith/nix-secrets` (private)
- Radicle remote: `rad:z2qTVkuBMHn82UyKbfT2NyyC5EaEH` (private, local)
- Encryption: SOPS + Age (age1vn8fpkmkzkjttcuc3prq3jrp7t5fsrdqey74ydu5p88keqmcupvs8jtmv8)
- Latest commit: 57eb381

**nix-config**:
- Flake input: `github:cameronraysmith/nix-secrets`
- Pure flake (no environment variables)
- CI compatible (GITHUB_TOKEN)
