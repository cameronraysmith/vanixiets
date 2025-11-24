# Managing Machines in Clan

This guide explains how to add new machines to the clan inventory, generate vars, deploy configurations, and troubleshoot common machine-related issues.

**Target Audience**: Epic 2-6 engineers managing NixOS servers and nix-darwin laptops
**Prerequisites**: Understanding of clan inventory structure (see `docs/architecture/dendritic-pattern.md`)

## Quick Start

1. Generate machine age key on deployed machine (via sops-nix module)
2. Register machine in clan: `clan secrets machines add <machine> --age-key <age-pub>`
3. Generate machine vars: `clan vars generate <machine>`
4. Deploy configuration: `clan machines update <machine>`
5. Restart SSH daemon if host keys changed: `ssh root@<machine> 'systemctl restart sshd'`

## Understanding Machine Age Keys

**Critical distinction**: Machine age keys are NOT derived from SSH host keys.

- **SSH host keys**: Located in `/etc/ssh/ssh_host_ed25519_key.pub`, used for SSH connection authentication
- **sops-nix age keys**: Located in `/var/lib/sops-nix/key.txt`, used for decrypting clan vars secrets

**Common mistake:**
```bash
# ❌ WRONG: This gets the SSH host key, not the sops-nix age key
ssh-keyscan -t ed25519 <machine-ip> | ssh-to-age
```

**Why this fails**: When you register the SSH host key as the machine's age key, clan vars encrypted with that key cannot be decrypted because the machine has a different age private key in `/var/lib/sops-nix/key.txt`.

**Symptom**: Deployment fails with:
```
Error getting data key: 0 successful groups required, got 0
```

## Step-by-Step Guide

### 1. Deploy Initial NixOS Configuration

Before adding a machine to clan, deploy the base NixOS configuration that includes the sops-nix module.
This generates the machine's age keypair.

**For Hetzner Cloud VMs** (via terraform):
```bash
# Machine config includes sops-nix module
# modules/machines/nixos/<machine>/default.nix

# Deploy via terraform wrapper
nix run .#terraform
# This runs: tofu apply → clan machines install
```

**For manual deployments**:
```bash
# Build configuration
nix build .#nixosConfigurations.<machine>.config.system.build.toplevel

# Deploy to machine
nixos-rebuild switch --flake .#<machine> --target-host root@<machine>
```

**Verification**: SSH to machine and verify sops-nix key exists:
```bash
ssh root@<machine> 'test -f /var/lib/sops-nix/key.txt && echo "✅ sops-nix key exists"'
```

### 2. Extract Machine Age Public Key

**Method A: Direct extraction from deployed machine** (recommended):
```bash
# SSH to machine and derive public key from private key
ssh root@<machine> 'cat /var/lib/sops-nix/key.txt | age-keygen -y'

# Example output:
# age195r8vrsxqxmljgmxf3reeqyxzj2lh6mldxep8uf7npjs2f2e7q7shxlsfp
```

**Method B: Via clan CLI**:
```bash
# If machine is already registered
clan secrets machines get <machine>

# Returns JSON with age public key:
# [
#   {
#     "publickey": "age195r8vrsxqxmljgmxf3reeqyxzj2lh6mldxep8uf7npjs2f2e7q7shxlsfp",
#     "type": "age"
#   }
# ]
```

**Validation**: Verify age public key format:
```bash
age_pub="age195r8vrsxqxmljgmxf3reeqyxzj2lh6mldxep8uf7npjs2f2e7q7shxlsfp"

if [[ $age_pub =~ ^age1[a-z0-9]{58}$ ]]; then
  echo "✅ Valid age public key"
else
  echo "❌ Invalid format - verify extraction"
fi
```

### 3. Register Machine with Clan

Add the machine to clan with its age public key:

```bash
# Extract age public key (from step 2)
MACHINE="cinnabar"
AGE_PUB=$(ssh root@<machine-ip> 'cat /var/lib/sops-nix/key.txt | age-keygen -y')

# Register machine
clan secrets machines add "$MACHINE" --age-key "$AGE_PUB"

# Verify registration
cat "sops/machines/${MACHINE}/key.json"
# Should show:
# [
#   {
#     "publickey": "age195r8vrsxqxmljgmxf3reeqyxzj2lh6mldxep8uf7npjs2f2e7q7shxlsfp",
#     "type": "age"
#   }
# ]
```

**Commit machine registration**:
```bash
git add "sops/machines/${MACHINE}/"
git commit -m "chore(clan): add machine ${MACHINE} with age key"
```

### 4. Generate Machine Vars

Generate clan vars for the machine (creates encrypted secrets):

```bash
# Generate vars (creates SSH keys, zerotier identity, etc.)
clan vars generate <machine>

# Vars are stored in:
# - vars/per-machine/<machine>/<generator>/<file>/secret
# - vars/shared/<generator>/<file>/secret (if shared across machines)
```

**Verify vars generation**:
```bash
# List generated vars
clan vars list <machine>

# Expected output (example for cinnabar):
# openssh/ssh.id_ed25519: ********
# openssh/ssh.id_ed25519.pub: ssh-ed25519 AAAAC3Nza...
# user-password-cameron/user-password: ********
# user-password-cameron/user-password-hash: ********
# zerotier/zerotier-identity-secret: ********
```

**Commit generated vars**:
```bash
git add vars/per-machine/<machine>/
git add vars/shared/  # If new shared vars created
git commit -m "chore(vars): generate vars for machine <machine>"
```

### 5. Deploy Configuration with Vars

Deploy the full configuration including vars:

```bash
# Deploy to machine
clan machines update <machine>

# Or manually via nixos-rebuild
nixos-rebuild switch --flake .#<machine> --target-host root@<machine>
```

**What happens during deployment**:
1. NixOS configuration deployed to machine
2. sops-nix module decrypts vars using `/var/lib/sops-nix/key.txt`
3. Decrypted vars appear in `/run/secrets/vars/<generator>/<file>`
4. Services reference vars via `config.clan.core.vars.generators.<generator>.files.<file>.value`

### 6. Post-Deployment Verification

**Check vars deployed correctly**:
```bash
# SSH to machine and list vars
ssh root@<machine> 'ls -la /run/secrets/vars/'

# Expected output:
# drwxr-x--x openssh/
# drwxr-x--x user-password-cameron/
# drwxr-x--x zerotier/
```

**Verify SSH host key deployed**:
```bash
# Check sshd configuration
ssh root@<machine> 'sshd -T | grep "^hostkey"'

# Expected output:
# hostkey /run/secrets/vars/openssh/ssh.id_ed25519
```

**Critical: Restart SSH daemon**:

After vars deployment, SSH daemon may still be serving old host keys from memory.

```bash
# Restart sshd to load new host key
ssh root@<machine> 'systemctl restart sshd'
```

**Verify host key matches vars**:
```bash
# Get host key from ssh-keyscan
ssh-keyscan -t ed25519 <machine-ip> 2>/dev/null | cut -d' ' -f3

# Get expected host key from vars
nix eval .#nixosConfigurations.<machine>.config.clan.core.vars.generators.openssh.files.\"ssh.id_ed25519.pub\".value --raw

# Keys should match exactly
```

### 7. Add Machine to Inventory

Define machine in clan inventory (if not already done):

**Edit `modules/clan/inventory/machines.nix`**:
```nix
{
  config,
  ...
}:
{
  clan.inventory.machines = {
    <machine> = {
      name = "<machine>";
      description = "<Brief description>";
      tags = [ "nixos" "hetzner" ]; # Or relevant tags
      system = "x86_64-linux"; # Or aarch64-linux, aarch64-darwin
      # Machine-specific config...
    };
  };
}
```

**Commit inventory**:
```bash
git add modules/clan/inventory/machines.nix
git commit -m "feat(inventory): add machine <machine> to inventory"
```

## Re-encrypting Vars After Key Changes

When machine age keys change (key rotation, fixing mistakes), vars must be re-encrypted WITHOUT regenerating values.

### When to Re-encrypt

- Machine age key was corrected (wrong key registered initially)
- New machine added to shared vars
- Security incident requires key rotation

### Re-encryption Workflow

**Step 1: Update machine age key**:
```bash
# Get correct age public key from machine
CORRECT_AGE=$(ssh root@<machine> 'cat /var/lib/sops-nix/key.txt | age-keygen -y')

# Update clan registration (overwrites old key)
clan secrets machines add <machine> --age-key "$CORRECT_AGE"

# Verify update
cat "sops/machines/<machine>/key.json"
```

**Step 2: Re-encrypt vars** (preserves plaintext values):
```bash
# Re-encrypt with new key
clan vars fix <machine>

# This runs SOPS updatekeys operation internally
# Plaintext values are preserved, only encryption keys change
```

**Step 3: Verify re-encryption**:
```bash
# List vars (should still be accessible)
clan vars list <machine>

# Commit re-encrypted vars
git add vars/per-machine/<machine>/
git commit -m "fix(vars): re-encrypt <machine> vars with correct age key"
```

**Step 4: Redeploy configuration**:
```bash
# Deploy updated vars to machine
clan machines update <machine>
```

## Verifying Age Key Correspondence

**Problem**: Machine age key in repository doesn't match actual key on deployed machine.

**Symptom**: Deployment fails with "0 successful groups required, got 0"

**Verification workflow**:
```bash
MACHINE="cinnabar"

# 1. Get registered age public key from repository
registered_key=$(jq -r '.[0].publickey' "sops/machines/${MACHINE}/key.json")

# 2. Get actual age public key from deployed machine
actual_key=$(ssh root@<machine-ip> 'cat /var/lib/sops-nix/key.txt | age-keygen -y')

# 3. Compare
if [ "$registered_key" = "$actual_key" ]; then
  echo "✅ Age keys match"
else
  echo "❌ MISMATCH DETECTED"
  echo "Registered: $registered_key"
  echo "Actual:     $actual_key"
  echo ""
  echo "Fix: clan secrets machines add ${MACHINE} --age-key \"$actual_key\""
  echo "Then: clan vars fix ${MACHINE}"
fi
```

## Managing Shared Vars Across Multiple Machines

Some vars (like emergency access credentials) may be shared across multiple machines.

**Current limitation**: No automated tooling for adding machines to existing shared vars.

**Manual workflow**:

1. **Add symlinks to shared var**:
```bash
# Navigate to shared var directory
cd vars/shared/emergency-access/backup-key/

# Add symlink for new machine
ln -s ../../../machines/<new-machine> machines/<new-machine>

# Commit symlink
cd ../../../../
git add vars/shared/emergency-access/backup-key/machines/
git commit -m "feat(vars): add <new-machine> to emergency-access shared var"
```

2. **Re-encrypt shared var with new machine's key**:
```bash
# Re-encrypt with all machine keys (including new one)
clan vars fix <new-machine>
```

3. **Verify all machines can decrypt**:
```bash
# Each machine should show the shared var
clan vars list <machine1> | grep emergency-access
clan vars list <new-machine> | grep emergency-access
```

## Examples

### Example 1: Adding cinnabar (Hetzner CX43, NixOS)

```bash
# 1. Deployed via terraform (includes sops-nix module)
nix run .#terraform

# 2. Extract age public key
AGE_PUB=$(ssh root@49.13.68.78 'cat /var/lib/sops-nix/key.txt | age-keygen -y')
echo "Age public key: $AGE_PUB"

# 3. Register machine
clan secrets machines add cinnabar --age-key "$AGE_PUB"

# 4. Generate vars
clan vars generate cinnabar

# 5. Deploy configuration
clan machines update cinnabar

# 6. Restart SSH daemon
ssh root@49.13.68.78 'systemctl restart sshd'

# 7. Verify host key
ssh-keyscan -t ed25519 49.13.68.78
# Should match: nix eval .#nixosConfigurations.cinnabar.config.clan.core.vars.generators.openssh.files.\"ssh.id_ed25519.pub\".value --raw
```

### Example 2: Adding blackphos (nix-darwin laptop)

```bash
# 1. Darwin machines don't use clan vars (no sops-nix module on darwin)
# Age keys only needed for user-level sops-nix secrets

# 2. For user sops secrets, see docs/guides/age-key-management.md
# User age keys derived from Bitwarden SSH keys

# 3. Deploy darwin configuration
nh darwin switch . -H blackphos

# 4. No SSH daemon restart needed (darwin uses system SSH)
```

### Example 3: Fixing age key mismatch on electrum

```bash
# Symptom: Deployment fails with "0 successful groups required, got 0"

# 1. Verify mismatch
registered=$(jq -r '.[0].publickey' sops/machines/electrum/key.json)
actual=$(ssh root@162.55.175.87 'cat /var/lib/sops-nix/key.txt | age-keygen -y')

echo "Registered: $registered"
echo "Actual:     $actual"
# Output shows keys don't match

# 2. Update clan registration
clan secrets machines add electrum --age-key "$actual"

# 3. Re-encrypt vars with correct key
clan vars fix electrum

# 4. Commit fixes
git add sops/machines/electrum/key.json vars/per-machine/electrum/
git commit -m "fix(electrum): correct machine age key and re-encrypt vars"

# 5. Deploy configuration
clan machines update electrum

# 6. Verify deployment succeeds
ssh root@162.55.175.87 'ls /run/secrets/vars/'
# Should show: openssh/ user-password-cameron/ zerotier/
```

## Troubleshooting

### "Error getting data key: 0 successful groups required, got 0"

**Symptom**: Deployment or vars operation fails with SOPS error about data key.

**Cause**: Machine age key registered in `sops/machines/<machine>/key.json` doesn't match actual age private key in `/var/lib/sops-nix/key.txt` on deployed machine.

**Solution**:
1. Extract correct age public key from machine: `ssh root@<machine> 'cat /var/lib/sops-nix/key.txt | age-keygen -y'`
2. Update clan registration: `clan secrets machines add <machine> --age-key "<correct-key>"`
3. Re-encrypt vars: `clan vars fix <machine>`
4. Commit changes and redeploy

**Prevention**: Always extract age keys from `/var/lib/sops-nix/key.txt`, never from SSH host keys.

### "WARNING: REMOTE HOST IDENTIFICATION HAS CHANGED"

**Symptom**: SSH connection fails with host key verification warning after deploying new configuration.

**Cause**: SSH daemon hasn't restarted to load updated host key from vars.

**Timeline**:
- `clan vars fix <machine>` updates SSH host key file
- SSH daemon still serving old key from memory
- Client SSH sees different key than expected

**Solution**:
1. Restart SSH daemon: `ssh -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no root@<machine-ip> 'systemctl restart sshd'`
2. Verify new key: `ssh-keyscan -t ed25519 <machine-ip>`
3. Remove old key from `~/.ssh/known_hosts`: `ssh-keygen -R <machine-ip>`
4. Connect normally: `ssh root@<machine>`

**Root cause**: systemd restarts services when config changes, but not when secret file contents change.
Since `HostKey` path in sshd_config doesn't change, no restart is triggered.

### vars generation fails with "machine not found"

**Symptom**: `clan vars generate <machine>` fails saying machine doesn't exist.

**Cause**: Machine not defined in clan inventory or nixosConfigurations.

**Solution**:
1. Verify machine config exists: `nix eval .#nixosConfigurations.<machine> --apply 'x: "exists"'`
2. If missing, add machine module to `modules/machines/nixos/<machine>/default.nix`
3. Ensure machine is exported via dendritic pattern (auto-discovered by import-tree)
4. Build configuration: `nix build .#nixosConfigurations.<machine>.config.system.build.toplevel`

### sops decryption fails on machine

**Symptom**: Machine boots but services fail with sops decryption errors.

**Cause**: `/var/lib/sops-nix/key.txt` doesn't exist or has wrong permissions.

**Solution**:
1. SSH to machine and check: `ls -la /var/lib/sops-nix/key.txt`
2. If missing, sops-nix module didn't initialize: Add `sops.age.keyFile = "/var/lib/sops-nix/key.txt";` to machine config
3. If wrong permissions: `chmod 600 /var/lib/sops-nix/key.txt`
4. Redeploy: `nixos-rebuild switch --flake .#<machine>`

### vars re-encryption regenerates secret values

**Symptom**: After `clan vars fix`, secret values changed (e.g., new SSH keys generated).

**Cause**: Used `clan vars generate` instead of `clan vars fix`.

**Commands distinction**:
- `clan vars generate <machine>`: Runs generators, creates NEW secret values
- `clan vars fix <machine>`: Re-encrypts EXISTING values with updated keys

**Solution**:
- If values must be preserved: Restore vars from git history before regeneration
- If new values acceptable: Update dependent configurations (e.g., update known_hosts for new SSH keys)

### Shared var not accessible on new machine

**Symptom**: Shared var exists for machine1, but machine2 can't decrypt it.

**Cause**: machine2 not added to shared var's encryption recipients.

**Solution**:
1. Navigate to shared var: `cd vars/shared/<generator>/<var>/machines/`
2. Add symlink: `ln -s ../../../machines/<machine2> <machine2>`
3. Re-encrypt: `clan vars fix <machine2>`
4. Commit: `git add . && git commit -m "feat(vars): add <machine2> to shared var <var>"`
5. Deploy: `clan machines update <machine2>`

## Best Practices

1. **Always extract age keys from deployed machines**: Use `/var/lib/sops-nix/key.txt`, never `ssh-keyscan`
2. **Verify age key correspondence**: Check registered vs actual keys before troubleshooting
3. **Restart SSH daemon after vars updates**: Prevent host key verification failures
4. **Use `clan vars fix` for re-encryption**: Preserves secret values when only keys change
5. **Commit vars after generation**: Version-controlled encrypted secrets for disaster recovery
6. **Test deployment in isolated environment**: Use test VMs before production deployments
7. **Document machine-specific quirks**: Add comments in machine modules for special requirements
8. **Regular age key audits**: Verify all machines have correct keys registered

## Security Considerations

1. **Machine age keys**: Stored in `/var/lib/sops-nix/key.txt` (persistent, needs encrypted filesystem)
2. **Vars deployment**: Secrets appear in `/run/secrets/` (tmpfs, cleared on reboot)
3. **Root-only access**: Only root can read age private key and decrypted vars
4. **Key rotation**: Rotate machine age keys if compromise suspected; re-encrypt all vars
5. **Backup age keys**: Store machine age keys securely for disaster recovery
6. **Separate user/machine keys**: User age keys (Bitwarden) separate from machine keys (sops-nix)

## References

- **Secrets architecture**: `docs/architecture/secrets-and-vars-architecture.md`
- **Age key operations**: `docs/guides/age-key-management.md`
- **User management**: `docs/guides/adding-users.md`
- **Dendritic pattern**: `docs/architecture/dendritic-pattern.md`
- **Clan-core documentation**: https://docs.clan.lol
- **sops-nix**: https://github.com/Mic92/sops-nix
