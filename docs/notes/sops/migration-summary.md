---
title: SOPS Unified Secrets Management Implementation Summary
---

Date: 2025-10-09
Branch: 06-sops-update
Status: Complete (stibnite validated, blackphos/orb-nixos deferred)
Planning docs: test-secrets/docs/notes/secrets/unified-plan/ (v2.2)

## Implementation overview

Successfully implemented unified secrets management with Bitwarden as single source of truth for all SSH keys used in SOPS encryption.

### Architecture: 3-tier key structure

1. **Repository keys** (2):
   - `sops-dev-ssh` → age1js028xag... → &dev
   - `sops-ci-ssh` → age1ldx73kk... → &ci

2. **User identity keys** (2):
   - `sops-admin-user-ssh` → age1vn8fpkm... → &admin-user (cameron/crs58/runner/jovyan)
   - `sops-raquel-user-ssh` → age12w0rmmsk... → &raquel-user (raquel)

3. **Host keys** (3):
   - `sops-stibnite-ssh` → age1a696klq... → &stibnite
   - `sops-blackphos-ssh` → age1ez8lkuk... → &blackphos
   - `sops-orb-nixos-ssh` → age140evke8... → &orb-nixos

4. **Admin recovery key** (1):
   - Offline key (not in Bitwarden): age1vy7wsn... → &admin

**Total**: 8 keys in .sops.yaml (7 from Bitwarden + 1 offline recovery)

## What was completed

### Infrastructure built

Created reusable scripts in `scripts/sops/`:
- `extract-key-details.sh` - Extract SSH/age keys from Bitwarden
- `update-sops-yaml.sh` - Generate .sops.yaml from Bitwarden keys
- `deploy-host-key.sh` - Deploy host keys to /etc/ssh/
- `validate-correspondences.sh` - Validate config.nix ↔ Bitwarden ↔ .sops.yaml
- `sync-age-keys.sh` - Regenerate ~/.config/sops/age/keys.txt

Added justfile recipes in `[group('sops')]`:
- `sops-extract-keys` - Extract key details
- `sops-update-yaml` - Update .sops.yaml
- `sops-deploy-host-key` - Deploy to hosts
- `sops-validate-correspondences` - Run validations
- `sops-sync-keys` - Sync age keys.txt
- `sops-rotate` - Full rotation workflow

### Keys and encryption

- Generated 7 SSH keys in Bitwarden (3 new host keys, 2 repo keys, preserved 2 user keys)
- Updated .sops.yaml with 3-tier architecture
- Re-encrypted all secrets for all 8 keys
- Updated GitHub CI secret (SOPS_AGE_KEY)
- Deployed stibnite host key to /etc/ssh/ssh_host_ed25519_key

### Validation

- All correspondence validations passing
- All secrets decrypt successfully
- CI pipeline verified (run 18365584613 succeeded)
- Devshell updated with all required tools (bitwarden-cli, jq, gh)

## Current state

### Deployed

**stibnite** (current machine):
- ✅ Host key deployed to /etc/ssh/ssh_host_ed25519_key
- ✅ Secrets encrypted for stibnite
- ✅ All validations passing
- ✅ CI pipeline working

### Deferred (to be deployed later)

**blackphos** (production Darwin):
- ✅ Key generated in Bitwarden (sops-blackphos-ssh)
- ✅ Secrets encrypted for blackphos
- ⏳ Host key deployment pending (do when physically at machine)

**orb-nixos** (development VM):
- ✅ Key generated in Bitwarden (sops-orb-nixos-ssh)
- ✅ Secrets encrypted for orb-nixos
- ⏳ Host key deployment pending

## Next steps for deferred hosts

When ready to onboard blackphos or orb-nixos:

### On the target host

```bash
# 1. Clone or pull nix-config
cd ~/projects
git clone https://github.com/cameronraysmith/nix-config
# OR: git pull (if already cloned)
cd nix-config
git checkout 06-sops-update  # or main after merge

# 2. Enter devshell (has all tools: bw, jq, sops, just, etc.)
nix develop

# 3. Unlock Bitwarden
export BW_SESSION=$(bw unlock --raw)

# 4. Deploy host key
just sops-deploy-host-key <hostname>
# For blackphos: just sops-deploy-host-key blackphos
# For orb-nixos: just sops-deploy-host-key orb-nixos

# 5. Verify deployment
sudo ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub
# Compare fingerprint with Bitwarden

# 6. (Later) Activate nix-config
just activate <hostname>
```

### Key principle

Host keys MUST be deployed BEFORE first nix-config activation because:
- sops-nix needs /etc/ssh/ssh_host_ed25519_key to derive age key
- Without it, secrets can't decrypt
- Activation will fail

## Commits made

Migration completed in 10 commits on branch 06-sops-update:

```
d044e59 fix(sops): handle SSH key comments and grep pattern with leading dash
5f5f39e fix(sops): regenerate keys with correct user identity keys
b4f806b fix(config): update raquel SSH key to match Bitwarden
50e9304 fix(sops): correct age key extraction from .sops.yaml
9eadb6b feat(secrets): re-encrypt with new 3-tier key architecture
05c8ef8 feat(devshell): add SOPS key management tools
b62bf7d fix(sops): handle hosts without SSH server running
e408bdb feat(sops): update .sops.yaml with 3-tier key architecture
492f6d6 fix(sops): use correct SSH key field paths for Bitwarden type 5
dd9c497 feat(sops): add key rotation infrastructure
```

View all commits: `git log --oneline 53ac5407..HEAD`

## Future key rotation

To rotate keys in the future:

### Full rotation (all keys)

```bash
# 1. Generate new SSH keys in Bitwarden Web UI
#    - Update all sops-*-ssh entries with new keys

# 2. Unlock Bitwarden
export BW_SESSION=$(bw unlock --raw)

# 3. Use the rotation workflow
just sops-rotate

# This will:
# - Extract keys from Bitwarden
# - Update .sops.yaml
# - Re-encrypt secrets
# - Validate correspondences

# 4. Deploy new host keys
just sops-deploy-host-key stibnite
just sops-deploy-host-key blackphos
just sops-deploy-host-key orb-nixos

# 5. Update GitHub CI secret
# (Follow prompts from sops-rotate)

# 6. Test, commit, and push
```

### Partial rotation (specific key)

```bash
# 1. Update specific key in Bitwarden Web UI
# 2. Regenerate .sops.yaml
just sops-update-yaml

# 3. Re-encrypt secrets
find secrets/ -name "*.yaml" -not -name ".sops.yaml" -type f -exec sops updatekeys {} \;

# 4. Validate
just sops-validate-correspondences

# 5. If host key: deploy
just sops-deploy-host-key <hostname>

# 6. If CI key: update GitHub secret
# (manual gh secret set as shown in sops-rotate output)
```

## Maintenance

### Validating correspondences

Run comprehensive validation:

```bash
export BW_SESSION=$(bw unlock --raw)
just sops-validate-correspondences
bw lock
```

This checks:
- config.nix SSH keys match Bitwarden
- Bitwarden age keys match .sops.yaml
- Host keys exist in Bitwarden
- CI test configs have no keys
- Repository keys exist

### Adding new hosts

```bash
# 1. Generate key in Bitwarden Web UI
#    Name: sops-<hostname>-ssh
#    Type: SSH Key (ed25519)

# 2. Update .sops.yaml
just sops-update-yaml

# 3. Add host-specific creation_rule in .sops.yaml
# (manual edit following existing patterns)

# 4. Re-encrypt secrets
find secrets/ -name "*.yaml" -not -name ".sops.yaml" -type f -exec sops updatekeys {} \;

# 5. Deploy host key on new machine
just sops-deploy-host-key <hostname>

# 6. Validate
just sops-validate-correspondences
```

### Backups

Current backups retained:
- `.sops.yaml.pre-migration` (committed) - original .sops.yaml before migration
- `/etc/ssh/ssh_host_ed25519_key.old` on stibnite - original host key

Safe to delete after verification period.

## Troubleshooting

### Secrets won't decrypt

```bash
# Check which keys you have access to
ls -la ~/.config/sops/age/keys.txt
# OR: ls -la ~/Library/Application\ Support/sops/age/keys.txt  # macOS

# Regenerate age keys from Bitwarden
export BW_SESSION=$(bw unlock --raw)
just sops-sync-keys
bw lock

# Verify secrets decrypt
just validate-secrets
```

### Host key mismatch

```bash
# Check deployed key fingerprint
sudo ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub

# Check Bitwarden key (extract and derive fingerprint)
bw get item sops-<hostname>-ssh | jq -r '.sshKey.publicKey' | ssh-keygen -lf -

# If mismatch, redeploy
just sops-deploy-host-key <hostname>
```

### CI can't decrypt secrets

```bash
# Verify GitHub secret is set
gh secret list | grep SOPS_AGE_KEY

# Re-upload CI key
export BW_SESSION=$(bw unlock --raw)
bw get item sops-ci-ssh | jq -r '.sshKey.privateKey' | \
  ssh-to-age -private-key | \
  gh secret set SOPS_AGE_KEY
bw lock
```

## Documentation references

- Planning documents: `test-secrets/docs/notes/secrets/unified-plan/` (v2.2)
- Script implementations: `scripts/sops/*.sh`
- Justfile recipes: Search for `[group('sops')]` in justfile
- SOPS documentation: https://github.com/getsops/sops
- Age documentation: https://github.com/FiloSottile/age

## Key decisions made

1. **Bitwarden as single source of truth**: ALL keys (including host keys) stored in Bitwarden
   - Enables centralized key management
   - Allows automated rotation
   - Provides backup/recovery

2. **Preserved user identity keys**: Used existing SSH keys from config.nix rather than generating new
   - Maintains existing SSH authentication
   - Avoids need to update authorized_keys everywhere
   - Only rotated repository and host keys

3. **Phased host key deployment**: Deploy locally on each machine when ready
   - Safer than remote deployment
   - Allows testing on stibnite first
   - Physical access available if issues occur

4. **Devshell includes all tools**: Added bitwarden-cli, jq, gh to devshell
   - Enables new host onboarding without pre-activation
   - All tools available via `nix develop`
   - Consistent environment across machines

5. **No SSH server restart required**: Scripts handle hosts without SSH server
   - Keys deployed even if sshd not running
   - Useful for development machines
   - Key available for sops-nix regardless

## Success criteria achieved

- ✅ All 7 keys generated in Bitwarden
- ✅ .sops.yaml updated with 3-tier architecture (8 keys total)
- ✅ All secrets re-encrypted for all hosts
- ✅ GitHub CI secret updated
- ✅ Stibnite host key deployed and verified
- ✅ All validation passing
- ✅ CI pipeline verified (secrets decrypt successfully)
- ✅ Reusable infrastructure built (scripts + justfile recipes)
- ✅ Devshell updated with required tools
- ✅ Documentation complete

## Migration complete on stibnite

This migration is complete and validated on stibnite. The infrastructure is ready for use, and blackphos/orb-nixos can be onboarded when convenient using the documented procedure above.
