---
title: Secrets management
description: Managing encrypted secrets with SOPS and age encryption
---

This guide documents the complete workflow for managing SOPS keys and secrets for the typescript-nix-template, supporting both initial bootstrap and key rotation.

## Security architecture

### Key roles

1. **Dev key** (`age1dn8...ghptu3`): Developer workstation key
   - Stored in `~/.config/sops/age/keys.txt`
   - Can be shared among small team (or individual per developer)
   - Can decrypt all secrets in vars/

2. **CI key** (`age1m9m...22j3p8`): GitHub Actions key
   - Stored in GitHub Secrets as `SOPS_AGE_KEY`
   - Backup stored in Bitwarden
   - Can decrypt all secrets in vars/

### Secret categories

1. **Bootstrap secrets** (must exist before SOPS works):
   - `SOPS_AGE_KEY` - GitHub secret containing CI private age key
   - Uploaded directly via `gh secret set`

2. **SOPS-managed secrets** (in `vars/shared.yaml`):
   - `CACHIX_AUTH_TOKEN` - Nix binary cache auth
   - `GITGUARDIAN_API_KEY` - Secret scanning
   - `CLOUDFLARE_API_TOKEN` - Cloudflare Workers deployment
   - `CLOUDFLARE_ACCOUNT_ID` - Cloudflare account
   - `CI_AGE_KEY` - Backup of CI private key (for re-uploading)

3. **GitHub variables** (non-secret):
   - `CACHIX_CACHE_NAME` - Name of cachix cache

### Design decisions

**Why store `CI_AGE_KEY` in vars/shared.yaml?**
- Allows rotating SOPS_AGE_KEY GitHub secret from dev workstation
- Still requires dev key to decrypt
- Bitwarden serves as offline backup

**Why separate `sops-upload-github-key` from `ghsecrets`?**
- Avoids chicken-and-egg: can't use SOPS to get key needed to use SOPS
- During rotation, new key may not be in vars/shared.yaml yet
- Supports pasting from Bitwarden during initial bootstrap

**Why support both SSH and age key generation?**
- If CI needs SSH access (deploy, git push as bot), can derive age key from SSH key
- Single source of truth in Bitwarden
- Age-only is simpler if SSH not needed

## Workflows

### Initial bootstrap (new project)

```bash
# 1. Generate dev key
just sops-bootstrap dev

# Output shows private key - copy to password manager
# Then install locally:
just sops-add-key
# Paste the private key when prompted

# 2. Generate CI key
just sops-bootstrap ci

# Output shows private key - save to Bitwarden
# The recipe automatically adds it to vars/shared.yaml

# 3. Edit secrets with actual values
just edit-secrets
# Replace all REPLACE_ME values with actual secrets

# 4. Check requirements
just sops-check-requirements
# Verify all required secrets are present

# 5. Upload SOPS_AGE_KEY to GitHub
just sops-upload-github-key
# Choose option 2 to extract from vars/shared.yaml

# 6. Upload other secrets to GitHub
just sops-setup-github
# Uploads CACHIX_AUTH_TOKEN, GITGUARDIAN_API_KEY, etc.

# 7. Verify
gh secret list
gh variable list
just show-secrets

# 8. Test CI
just gh-ci-run --debug=true
```

### Key rotation (dev key)

```bash
# Option A: Quick rotation (guided)
just sops-rotate dev

# Option B: Manual steps
# 1. Bootstrap new dev key
just sops-bootstrap dev
# Adds as dev-next, saves private key

# 2. Install new key locally
just sops-add-key
# Paste the new private key

# 3. Verify decryption works with new key
just show-secrets

# 4. Finalize rotation (remove old key)
just sops-finalize-rotation dev

# 5. Update Bitwarden - mark old key as revoked
```

### Key rotation (CI key)

```bash
# 1. Bootstrap new CI key
just sops-bootstrap ci
# Adds as ci-next, saves private key to Bitwarden

# 2. Add new key to vars/shared.yaml
just edit-secrets
# Update CI_AGE_KEY field with new private key

# 3. Upload new key to GitHub
just sops-upload-github-key
# Choose option 1, paste from Bitwarden

# 4. Test CI with new key
just gh-ci-run --debug=true

# 5. Verify workflow succeeds with new key
just gh-workflow-status

# 6. Finalize rotation (remove old key)
just sops-finalize-rotation ci

# 7. Update vars/shared.yaml to remove old CI_AGE_KEY
just edit-secrets
# (The old value is fine to keep or remove)
```

### Adding new secrets

```bash
# 1. Edit encrypted file
just edit-secrets

# 2. Add new secret
# NEW_SECRET_NAME: new_secret_value

# 3. If needed in CI, upload to GitHub
sops exec-env vars/shared.yaml \
  'gh secret set NEW_SECRET_NAME --body="$NEW_SECRET_NAME"'

# Or add to ghsecrets recipe
```

### Onboarding new developer

```bash
# Option 1: Share existing dev key (small team)
# Send developer the dev private key via secure channel
just sops-add-key
# Paste the shared dev key

# Option 2: Generate individual dev key (recommended)
# 1. Add developer's public key to .sops.yaml
cat >> .sops.yaml << EOF
  - &dev-alice age1abc...xyz
EOF

# Update creation_rules
sed -i '/- \*dev/a\          - \*dev-alice' .sops.yaml

# 2. Re-encrypt all files with new key
just updatekeys

# 3. Commit and push .sops.yaml

# 4. Developer adds their private key
just sops-add-key
```

### Emergency key recovery

```bash
# If dev key lost but CI key backed up:
# 1. Get CI private key from Bitwarden

# 2. Install as temporary dev key
mkdir -p ~/.config/sops/age
cat >> ~/.config/sops/age/keys.txt << EOF
# Temporary CI key
# public key: age1m9m...22j3p8
AGE-SECRET-KEY-...
EOF

# 3. Now can decrypt secrets
just show-secrets

# 4. Rotate dev key
just sops-bootstrap dev

# 5. Remove temporary CI key from ~/.config/sops/age/keys.txt
```

## Recipe reference

### Bootstrap and rotation
- `just sops-bootstrap <role> [method]` - Generate new key (role: dev|ci, method: age|ssh)
- `just sops-rotate <role>` - Quick rotation workflow with guided steps
- `just sops-finalize-rotation <role>` - Remove old key after verifying new one

### Secret management
- `just edit-secrets` - Edit vars/shared.yaml (decrypts, opens editor, re-encrypts)
- `just show-secrets` - Display decrypted secrets
- `just set-secret <name> <value>` - Set specific secret value
- `just rotate-secret <name>` - Rotate specific secret value
- `just validate-secrets` - Verify all encrypted files can be decrypted

### GitHub integration
- `just sops-check-requirements` - Analyze workflows and show required secrets
- `just sops-upload-github-key [repo]` - Upload SOPS_AGE_KEY to GitHub
- `just sops-setup-github [repo]` - Upload all secrets and variables (except SOPS_AGE_KEY)
- `just ghsecrets [repo]` - Upload specific secrets from vars/shared.yaml
- `just ghvars [repo]` - Upload variables from environment

### Key management
- `just sops-init` - Generate new age key for current user
- `just sops-add-key` - Add existing age key to local config
- `just updatekeys` - Update all encrypted files with current keys from .sops.yaml

### Testing
- `just test-build` - Test CI build job locally with act
- `just test-deploy` - Test CI deploy job locally with act
- `just gh-ci-run` - Trigger CI workflow on GitHub

## File structure

```
.
├── .sops.yaml                    # SOPS config with public keys (committed)
├── vars/
│   ├── shared.yaml              # Encrypted secrets (committed)
│   └── README.md                # Documentation
├── .github/workflows/
│   └── ci.yaml                  # CI workflow that uses SOPS_AGE_KEY
└── justfile                     # Recipes for secret management
```

## Security checklist

- [ ] Dev private keys stored in `~/.config/sops/age/keys.txt` with `600` permissions
- [ ] CI private key backed up in Bitwarden
- [ ] `SOPS_AGE_KEY` GitHub secret set
- [ ] No unencrypted secrets committed to git
- [ ] `.sops.yaml` only contains public keys
- [ ] All secrets in `vars/shared.yaml` have non-REPLACE_ME values
- [ ] GitHub Actions logs don't expose `SOPS_AGE_KEY` or decrypted secrets
- [ ] Key rotation procedure documented and tested
- [ ] Recovery procedure documented (CI key in Bitwarden)

## Troubleshooting

### Cannot decrypt vars/shared.yaml

```bash
# Check if you have a valid key
grep "public key:" ~/.config/sops/age/keys.txt

# Check if your public key is in .sops.yaml
cat .sops.yaml

# Verify file is encrypted
head vars/shared.yaml  # Should show SOPS metadata

# Try decrypting with explicit key
SOPS_AGE_KEY_FILE=~/.config/sops/age/keys.txt sops -d vars/shared.yaml
```

### CI fails with "could not decrypt data key"

```bash
# Verify SOPS_AGE_KEY is set in GitHub
gh secret list | grep SOPS_AGE_KEY

# Verify CI public key in .sops.yaml matches private key
# Get public key from private key:
age-keygen -y <<< "AGE-SECRET-KEY-..."

# Re-upload key
just sops-upload-github-key
```

### Rotation left system in inconsistent state

```bash
# Restore from backup
cp .sops.yaml.backup .sops.yaml

# Or manually fix .sops.yaml
# - Remove -next suffix from new key
# - Remove old key line
# - Update all files
just updatekeys
```

## Advanced usage

### SSH-derived keys for CI bot

If CI needs SSH access (e.g., to push commits as bot user):

```bash
# Generate SSH key
ssh-keygen -t ed25519 -f /tmp/ci-bot -N "" -C "ci-bot@typescript-nix-template"

# Derive age key
ssh-to-age < /tmp/ci-bot.pub
# Output: age1abc...xyz

# Add to .sops.yaml as ci key

# Save SSH private key to Bitwarden as "typescript-nix-template CI SSH key"

# For SOPS, derive age private key
ssh-to-age -private-key -i /tmp/ci-bot
# Output: AGE-SECRET-KEY-...

# Upload to GitHub
echo "AGE-SECRET-KEY-..." | gh secret set SOPS_AGE_KEY

# For SSH access, also upload SSH key
gh secret set CI_SSH_KEY < /tmp/ci-bot

# Clean up
rm /tmp/ci-bot /tmp/ci-bot.pub
```

### Environment-specific secrets (dev/staging/prod)

```yaml
# .sops.yaml
keys:
  - &dev age1dn8...
  - &ci age1m9m...
  - &prod-admin age1xyz...

creation_rules:
  - path_regex: vars/dev\.yaml$
    key_groups:
      - age: [*dev, *ci]

  - path_regex: vars/prod\.yaml$
    key_groups:
      - age: [*prod-admin, *ci]
```

```bash
# Edit environment-specific secrets
just edit-secrets vars/dev.yaml
just edit-secrets vars/prod.yaml
```

### Multi-repository shared secrets

For secrets shared across multiple repos (e.g., CACHIX_AUTH_TOKEN):

```bash
# Create shared secrets repo
mkdir ~/.sops-shared
cd ~/.sops-shared

# Copy .sops.yaml and create shared.yaml
cp ~/projects/typescript-nix-template/.sops.yaml .
sops shared.yaml

# Upload to multiple repos
for repo in org/repo1 org/repo2; do
  sops exec-env shared.yaml "gh secret set CACHIX_AUTH_TOKEN --repo=$repo --body=\$CACHIX_AUTH_TOKEN"
done
```

## Quick reference

### Common operations

#### First-time setup

```bash
# 1. Generate and install dev key
just sops-bootstrap dev
just sops-add-key  # Paste private key

# 2. Generate CI key
just sops-bootstrap ci
# Save private key to Bitwarden

# 3. Edit secrets
just edit-secrets
# Replace all REPLACE_ME values

# 4. Upload to GitHub
just sops-upload-github-key  # Option 2: from vars/shared.yaml
just sops-setup-github       # Other secrets and variables

# 5. Verify
just sops-check-requirements
gh secret list
just gh-ci-run
```

#### Daily usage

```bash
# View secrets
just show-secrets

# Edit secrets
just edit-secrets

# Set specific secret
just set-secret CLOUDFLARE_API_TOKEN "new-value"

# Run command with secrets
just run-with-secrets 'echo $CLOUDFLARE_API_TOKEN'

# Validate all secrets decrypt
just validate-secrets
```

#### Key rotation

```bash
# Quick rotation (guided)
just sops-rotate dev    # or 'ci'

# Manual rotation
just sops-bootstrap dev
just sops-add-key
just show-secrets  # Verify works
just sops-finalize-rotation dev
```

#### GitHub sync

```bash
# Check what secrets are needed
just sops-check-requirements

# Upload SOPS_AGE_KEY
just sops-upload-github-key

# Upload all other secrets
just sops-setup-github

# Or upload individually
just ghsecrets  # Secrets from vars/shared.yaml
just ghvars     # Variables from environment
```

#### Troubleshooting

```bash
# Can't decrypt?
grep "public key:" ~/.config/sops/age/keys.txt
cat .sops.yaml  # Is your key listed?

# Update keys after changing .sops.yaml
just updatekeys

# CI failing?
gh secret list | grep SOPS_AGE_KEY
just gh-logs  # Check error message
```

### Recipe quick reference

| Recipe | Purpose |
|--------|---------|
| `sops-bootstrap <role>` | Generate new dev/ci key |
| `sops-rotate <role>` | Quick rotation workflow |
| `sops-finalize-rotation <role>` | Remove old key after rotation |
| `sops-add-key` | Install key locally |
| `sops-init` | Generate new age key |
| `edit-secrets` | Edit vars/shared.yaml |
| `show-secrets` | View decrypted secrets |
| `set-secret <name> <value>` | Set specific secret |
| `rotate-secret <name>` | Rotate specific secret value |
| `validate-secrets` | Verify all files decrypt |
| `updatekeys` | Update encrypted files after key changes |
| `sops-check-requirements` | Show required secrets from workflows |
| `sops-upload-github-key` | Upload SOPS_AGE_KEY to GitHub |
| `sops-setup-github` | Upload all secrets/vars to GitHub |
| `ghsecrets [repo]` | Upload secrets from SOPS |
| `ghvars [repo]` | Upload variables |

### File locations

| File | Purpose |
|------|---------|
| `.sops.yaml` | SOPS config (public keys only) |
| `vars/shared.yaml` | Encrypted secrets (committed) |
| `~/.config/sops/age/keys.txt` | Your private keys (NOT committed) |
| GitHub Secrets: `SOPS_AGE_KEY` | CI private key |

### Key public keys (from .sops.yaml)

- **Dev**: `age1dn8w7y4t4h23fmeenr3dghfz5qh53jcjq9qfv26km3mnv8l44g0sghptu3`
- **CI**: `age1m9m8h5vqr7dqlmvnzcwshmm4uk8umcllazum6eaulkdp3qc88ugs22j3p8`

### Required secrets (from ci.yaml)

| Secret | Location | Purpose |
|--------|----------|---------|
| `SOPS_AGE_KEY` | GitHub Secret | CI age private key |
| `CACHIX_AUTH_TOKEN` | vars/shared.yaml → GitHub Secret | Nix cache auth |
| `CACHIX_CACHE_NAME` | vars/shared.yaml → GitHub Variable | Nix cache name |
| `GITGUARDIAN_API_KEY` | vars/shared.yaml → GitHub Secret | Secret scanning |
| `CLOUDFLARE_API_TOKEN` | vars/shared.yaml | Cloudflare deploy |
| `CLOUDFLARE_ACCOUNT_ID` | vars/shared.yaml | Cloudflare account |
| `CI_AGE_KEY` | vars/shared.yaml | Backup of SOPS_AGE_KEY |

### Emergency contacts

- Bitwarden: CI key backup
- `.sops.yaml.backup`: Rollback point
- `vars/shared.yaml.backup`: Rollback point
- SOPS-WORKFLOW-GUIDE.md: Full documentation

## References

- [SOPS documentation](https://github.com/getsops/sops)
- [age encryption tool](https://age-encryption.org/)
- [GitHub CLI](https://cli.github.com/)
- [ssh-to-age](https://github.com/Mic92/ssh-to-age)
