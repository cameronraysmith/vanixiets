# Host onboarding guide

This guide covers the procedure for onboarding a new host (nix-darwin or NixOS) to this nix-config repository.

## When to use this guide

Use this procedure when:
- Setting up a new machine with this nix-config for the first time
- Re-onboarding a machine after a clean OS installation
- Adding a machine that has a host configuration defined in `hosts/<hostname>/`

This guide assumes the host configuration already exists in the repository.
If you need to create a new host configuration first, do that before following these steps.

## Architecture overview

This nix-config uses SOPS (Secrets OPerationS) for encrypted secrets management with a 3-tier key architecture:

1. **Repository keys** - for development and CI/CD
2. **User identity keys** - tied to user SSH keys in `config.nix`
3. **Host keys** - unique per machine, stored at `/etc/ssh/ssh_host_ed25519_key`

The critical requirement: host keys must be deployed before nix-config activation.
This is because sops-nix derives the age decryption key from the host's SSH key at `/etc/ssh/ssh_host_ed25519_key`.
Without it, secrets cannot be decrypted and activation will fail.

All keys are stored in Bitwarden as the single source of truth, with the exception of an offline admin recovery key.

## Prerequisites

Before starting, ensure you have:

- [ ] Physical access or SSH access to the target host
- [ ] Nix installed on the host (with flakes enabled)
- [ ] Bitwarden CLI access with master password
- [ ] Git access to this repository
- [ ] Host configuration exists in `hosts/<hostname>/`
- [ ] Host key generated in Bitwarden as `sops-<hostname>-ssh`
- [ ] Secrets already encrypted for the host (check `.sops.yaml`)

## Procedure

### Step 1: Clone or update repository

On the target host:

```bash
cd ~/projects
git clone https://github.com/cameronraysmith/nix-config
# OR if already cloned:
cd ~/projects/nix-config && git pull

cd nix-config
git checkout <branch>  # Use main or current development branch
```

### Step 2: Enter development shell

The devshell provides all required tools (bitwarden-cli, jq, sops, just, gh) without requiring nix-config activation:

```bash
nix develop
```

This may take several minutes on first run as Nix downloads and builds dependencies.

### Step 3: Unlock Bitwarden

```bash
export BW_SESSION=$(bw unlock --raw)
```

Enter your Bitwarden master password when prompted.
The session token allows scripts to access keys without repeated password entry.

### Step 4: Verify host key exists in Bitwarden

```bash
bw get item sops-<hostname>-ssh | jq -r '.sshKey.publicKey'
```

Expected output: an SSH public key starting with `ssh-ed25519 AAAAC3Nza...`

If this fails, the host key hasn't been generated yet.
See the "Adding new hosts" section in `docs/notes/secrets/sops-migration-summary.md` for key generation instructions.

### Step 5: Deploy host key

```bash
just sops-deploy-host-key <hostname>
```

This script will:
1. Extract the private key from Bitwarden
2. Backup any existing key to `/etc/ssh/ssh_host_ed25519_key.old`
3. Deploy the new key with correct permissions (private: 600, public: 644)
4. Attempt to restart SSH service (may warn if sshd not running - this is fine)
5. Display the key fingerprint for verification

Expected output:
```
Host key deployed successfully to /etc/ssh/ssh_host_ed25519_key
Fingerprint: 256 SHA256:... (ED25519)
```

### Step 6: Verify host key deployment

Verify the deployed key matches what's expected in `.sops.yaml`:

```bash
# Get the age key from the deployed SSH public key
ssh-to-age < /etc/ssh/ssh_host_ed25519_key.pub

# Find the age key for this host in .sops.yaml
grep <hostname> .sops.yaml
```

The age key from the first command should match the age key in `.sops.yaml`.
If they don't match, the deployment failed or the wrong key was deployed.

Optionally, also check the SSH fingerprint:
```bash
sudo ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub
```

### Step 7: Synchronize age keys

```bash
just sops-sync-keys
```

This extracts keys from Bitwarden and writes them to `~/.config/sops/age/keys.txt`:
- Repository development key
- User identity key (based on your username)
- Host key (for this machine)

The file includes public key comments above each private key for easy identification.

### Step 8: Verify age keys format

```bash
cat ~/.config/sops/age/keys.txt
```

Expected format:
```
# SOPS Age Keys - Generated <timestamp>
# DO NOT COMMIT THIS FILE

# Repository development key
# public key: age1js028xag...
AGE-SECRET-KEY-1...

# User identity key (<username>)
# public key: age1vn8fpkm...
AGE-SECRET-KEY-1...

# Host key (<hostname>)
# public key: age1ez8lkuk...
AGE-SECRET-KEY-1...
```

You should see exactly 3 keys with public key comments.

### Step 9: Test secrets decryption

```bash
sops -d secrets/shared.yaml | head -5
```

If this succeeds and displays decrypted secret values, the SOPS infrastructure is working correctly.

If it fails with "no key could be found to decrypt the data key", check:
- Host key deployed: `ls -la /etc/ssh/ssh_host_ed25519_key`
- Age keys present: `cat ~/.config/sops/age/keys.txt`
- Host in `.sops.yaml`: `grep <hostname> .sops.yaml`

### Step 10: Lock Bitwarden

```bash
bw lock
```

This clears the session token from memory.

### Step 11: Run validation (optional)

For comprehensive validation:

```bash
export BW_SESSION=$(bw unlock --raw)
just sops-validate-correspondences
bw lock
```

This checks:
- `config.nix` SSH keys match Bitwarden
- Bitwarden age keys match `.sops.yaml`
- Host keys exist and correspond
- All required keys present

### Step 12: Activate nix-config

When ready to activate:

```bash
just activate <hostname>
```

This applies the nix-darwin or NixOS configuration to the system.

On first activation, this will:
- Install system packages
- Configure system settings
- Set up home-manager for your user
- Deploy secrets via sops-nix

Monitor the output for any errors.
If activation fails due to secrets, revisit steps 5-9.

## Platform-specific considerations

### nix-darwin hosts (macOS)

- Host key deployment requires `sudo` password
- SSH server (sshd) may not be running - this is normal for development machines
- The deploy script will warn but continue if SSH restart fails
- First activation may require accepting Xcode license or other macOS prompts

### NixOS hosts (Linux)

- Host key deployment requires root access
- SSH server typically runs on servers but may not on desktops
- First activation will rebuild the entire system configuration
- May require reboot after first activation for some system-level changes

### Remote hosts

If onboarding via SSH rather than physical access:

```bash
# From your local machine
ssh <username>@<hostname>

# Then follow the procedure above
# Note: nix develop will work over SSH
```

Ensure the host SSH key deployment doesn't disrupt your current SSH connection.
The host key at `/etc/ssh/ssh_host_ed25519_key` is used for server identity, not client authentication.

## Validation

After activation, verify:

- [ ] Secrets decrypt: `sops -d secrets/shared.yaml`
- [ ] Host key present: `ls -la /etc/ssh/ssh_host_ed25519_key`
- [ ] Age keys present: `cat ~/.config/sops/age/keys.txt`
- [ ] System packages available: `which <expected-package>`
- [ ] Home-manager active: check home directory for expected configs
- [ ] No activation errors in system logs

## Troubleshooting

### Secrets won't decrypt

**Symptom:** `sops -d` fails with "no key could be found to decrypt the data key"

**Diagnosis:**
```bash
# Check keys.txt exists and has content
ls -la ~/.config/sops/age/keys.txt
cat ~/.config/sops/age/keys.txt

# Check host key deployed
ls -la /etc/ssh/ssh_host_ed25519_key

# Check host in .sops.yaml
grep <hostname> .sops.yaml
```

**Solution:**
```bash
# Regenerate age keys
export BW_SESSION=$(bw unlock --raw)
just sops-sync-keys
bw lock

# Retry decryption
sops -d secrets/shared.yaml
```

### Host key deployment fails

**Symptom:** `just sops-deploy-host-key` fails or reports errors

**Diagnosis:**
```bash
# Check Bitwarden access
bw get item sops-<hostname>-ssh | jq -r '.sshKey.publicKey'

# Check sudo access
sudo ls -la /etc/ssh/

# Check script exists
ls -la scripts/sops/deploy-host-key.sh
```

**Solution:**
- Ensure `BW_SESSION` is set: `export BW_SESSION=$(bw unlock --raw)`
- Verify host key exists in Bitwarden with correct name
- Check sudo permissions for writing to `/etc/ssh/`
- Review script output for specific error messages

### Activation fails

**Symptom:** `just activate <hostname>` fails with errors

**Common causes and solutions:**

1. **Secrets not decrypting**
   - Follow "Secrets won't decrypt" troubleshooting above
   - Ensure host key deployed before activation

2. **Missing packages or dependencies**
   - Run `nix flake check` to validate flake
   - Check for errors in host configuration
   - Ensure all inputs in `flake.lock` are accessible

3. **Permission errors**
   - nix-darwin may require running with appropriate privileges
   - Check file permissions on config files
   - Verify user has necessary system access

4. **First-time activation issues**
   - Some system changes require logout/login or reboot
   - MacOS may require granting permissions to terminal
   - Try activation again after addressing prompts

### Bitwarden session expires

**Symptom:** Commands fail with "Unauthorized" or "Session expired"

**Solution:**
```bash
bw lock  # Clear stale session
export BW_SESSION=$(bw unlock --raw)  # Create new session
# Retry command
```

### Wrong age keys in keys.txt

**Symptom:** Keys.txt has wrong keys or wrong number of keys

**Solution:**
```bash
# Remove old keys.txt
rm ~/.config/sops/age/keys.txt

# Regenerate from Bitwarden
export BW_SESSION=$(bw unlock --raw)
just sops-sync-keys
bw lock

# Verify format
cat ~/.config/sops/age/keys.txt
```

## Success criteria

A successful onboarding is complete when:

- Host key deployed to `/etc/ssh/ssh_host_ed25519_key` with correct permissions
- Backup created at `/etc/ssh/ssh_host_ed25519_key.old`
- Age keys present at `~/.config/sops/age/keys.txt` with 3 keys and public key comments
- Secrets decrypt successfully: `sops -d secrets/shared.yaml`
- Validation passes: `just sops-validate-correspondences`
- Nix-config activation succeeds: `just activate <hostname>`
- System operates normally with expected packages and configurations

## See also

- SOPS migration summary: `docs/notes/secrets/sops-migration-summary.md`
- SOPS key rotation: `just sops-rotate` workflow
- Adding new hosts: see "Adding new hosts" in migration summary
- Justfile recipes: run `just --list` to see all available commands
- SOPS documentation: https://github.com/getsops/sops
- Age encryption: https://age-encryption.org/
