---
title: Host Onboarding
sidebar:
  order: 3
---

This guide covers onboarding a new host to this infrastructure.
The workflow differs significantly between darwin (macOS) and NixOS platforms.

## Platform overview

| Platform | Hosts | Deployment command | Secrets |
|----------|-------|-------------------|---------|
| Darwin (nix-darwin) | stibnite, blackphos, rosegold, argentum | `darwin-rebuild switch` | Legacy sops-nix |
| NixOS (clan-managed) | cinnabar, electrum, galena, scheelite | `clan machines update` | Clan vars + legacy sops-nix |

Darwin hosts use nix-darwin with standalone builds.
NixOS hosts are managed by [clan](/concepts/clan-integration) which handles deployment, secrets generation, and multi-machine coordination.

## Architecture references

Before proceeding, understand the configuration patterns:
- [Deferred Module Composition](/concepts/deferred-module-composition) - Module organization (aspect-based, not host-based)
- [Clan Integration](/concepts/clan-integration) - Multi-machine coordination and secrets management

Configuration files live in `modules/machines/darwin/` and `modules/machines/nixos/`, not `configurations/`.

For detailed learning-oriented walkthroughs, see the [Darwin Deployment Tutorial](/tutorials/darwin-deployment/) for macOS or [NixOS Deployment Tutorial](/tutorials/nixos-deployment/) for servers.

## Darwin host onboarding (macOS)

Use this for Apple Silicon Macs: stibnite, blackphos, rosegold, argentum.

### Prerequisites

Before starting, ensure you have:
- macOS with admin access
- Nix installed with flakes enabled (see Step 1)
- Git access to this repository
- Homebrew installed (for zerotier)

### Step 1: Install Nix

Use the Determinate Systems installer for reliable macOS support:

```bash
curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- install
```

After installation, restart your shell or source the profile:

```bash
exec $SHELL
```

Verify Nix installation:

```bash
nix --version
```

### Step 2: Clone and enter repository

```bash
cd ~/projects
git clone https://github.com/cameronraysmith/vanixiets
cd vanixiets

# Allow direnv to activate the development shell
direnv allow
```

The devshell provides all required tools (just, sops, age, gh).
First entry may take several minutes as Nix builds dependencies.

### Step 3: Verify host configuration exists

Check that a darwin configuration exists for this hostname:

```bash
ls modules/machines/darwin/
```

Expected: A file named `<hostname>.nix` (e.g., `stibnite.nix`, `blackphos.nix`).

If your host configuration doesn't exist, create one following the pattern in existing files.

### Step 4: Build validation

Test that the configuration builds before deploying:

```bash
# Replace <hostname> with your machine name
nix build .#darwinConfigurations.<hostname>.system

# Examples:
nix build .#darwinConfigurations.stibnite.system
nix build .#darwinConfigurations.blackphos.system
```

This builds the configuration without applying it.
If this succeeds, deployment should work.

### Step 5: Deploy configuration

Apply the nix-darwin configuration:

```bash
darwin-rebuild switch --flake .#<hostname>

# Examples:
darwin-rebuild switch --flake .#stibnite
darwin-rebuild switch --flake .#blackphos
```

On first run, you may be prompted to:
- Accept flake configuration trust prompts (answer `y` to all)
- Enter your password for sudo operations
- Accept Xcode license (run `sudo xcodebuild -license accept` if needed)

After deployment:
- System packages installed
- nix-darwin system profile active
- Home-manager configurations applied
- Shell and environment configured

### Step 6: Set up secrets (Tier 2 - sops-nix)

Darwin hosts use Tier 2 (sops-nix) secrets for user-level credentials.
Tier 1 (clan vars) is not available on darwin.

#### Generate age key

```bash
# Create sops directory
mkdir -p ~/.config/sops/age

# Generate age keypair
age-keygen -o ~/.config/sops/age/keys.txt

# Display public key (you'll need this)
age-keygen -y ~/.config/sops/age/keys.txt
```

Save the public key output (starts with `age1...`).

#### Add public key to .sops.yaml

Edit `.sops.yaml` and add your age public key:

```yaml
keys:
  - &stibnite-crs58 age1your-public-key-here...

creation_rules:
  - path_regex: secrets/users/crs58\.sops\.yaml$
    key_groups:
      - age:
        - *stibnite-crs58
        # ... other keys
```

#### Verify secrets decrypt

```bash
# Test decryption
sops -d secrets/users/crs58.sops.yaml | head -5
```

If decryption fails, verify:
- Age key exists at `~/.config/sops/age/keys.txt`
- Your public key is listed in `.sops.yaml`
- The secrets file is encrypted for your key

### Step 7: Install zerotier (darwin-specific)

Darwin hosts use Homebrew for zerotier (not managed by clan):

```bash
# Install zerotier cask
brew install --cask zerotier-one

# Join the network
sudo zerotier-cli join db4344343b14b903
```

After joining, the network controller (cinnabar) must authorize this peer.
Contact the network admin or run:

```bash
# On cinnabar (controller)
clan machines update cinnabar
```

Verify network connectivity:

```bash
# Check zerotier status
sudo zerotier-cli listnetworks

# Test connectivity to another host
ping stibnite.zt
ping cinnabar.zt
```

### Step 8: Verify deployment

Check that everything is working:

```bash
# System packages available
which git gh just rg fd bat

# Home-manager active
echo $HOME_MANAGER_GENERATION

# Shell configured correctly
echo $SHELL

# Secrets accessible (if configured)
ls ~/.config/sops-nix/secrets/
```

### Darwin onboarding complete

Your darwin host is now:
- Running nix-darwin with your configuration
- Connected to the zerotier network
- Using sops-nix for user secrets

For updates, run:

```bash
darwin-rebuild switch --flake .#<hostname>
```

---

## NixOS host onboarding (clan-managed)

Use this for NixOS servers: cinnabar, electrum, galena, scheelite.

NixOS hosts are managed by [clan](/concepts/clan-integration), which provides:
- Unified deployment commands
- Automatic secrets generation (Tier 1)
- Multi-machine service coordination
- Zerotier mesh networking

### Prerequisites

Before starting, ensure you have:
- SSH access to deploy machine (or physical access for initial install)
- Age key at `~/.config/sops/age/keys.txt` for Tier 2 secrets
- Cloud provider credentials (for new VMs):
  - Hetzner: API token
  - GCP: Service account JSON

### Step 1: Provision infrastructure (new VMs only)

For cloud VMs, provision the infrastructure first using terranix:

```bash
# Provision Hetzner or GCP infrastructure
nix run .#terraform

# This creates the VM and outputs the IP address
```

For Hetzner VMs (cinnabar, electrum):
- Creates VPS with specified server type
- Configures networking and SSH keys
- Outputs IP address for deployment

For GCP VMs (galena, scheelite):
- Creates compute instance
- Configures firewall and SSH
- Outputs external IP

Skip this step if deploying to existing infrastructure.

### Step 2: Verify clan machine configuration

Check that the machine is registered in clan:

```bash
# List all registered machines
clan machines list

# Verify specific machine configuration exists
ls modules/machines/nixos/<hostname>.nix
```

Machine configurations live in `modules/machines/nixos/`.
Clan machine registry is in `modules/clan/machines.nix`.

### Step 3: Generate secrets (Tier 1 - clan vars)

Clan vars handles system-level secrets automatically:

```bash
# Generate secrets for the machine
clan vars generate <hostname>

# Examples:
clan vars generate cinnabar
clan vars generate galena
```

This generates:
- SSH host keys
- Zerotier network identity
- Other machine-specific secrets

Generated secrets are stored in `vars/<hostname>/` encrypted with age.

#### Machine age keys (critical distinction)

**Important**: Machine age keys are NOT derived from SSH host keys.
Understanding this distinction prevents a common configuration mistake.

**Two separate key types**:
- **SSH host keys**: `/etc/ssh/ssh_host_ed25519_key.pub` - Used for SSH connection authentication
- **sops-nix age keys**: `/var/lib/sops-nix/key.txt` - Used for decrypting clan vars secrets

**Common mistake to avoid**:
```bash
# WRONG: This gets SSH host key, not the sops-nix age key
ssh-keyscan -t ed25519 <machine-ip> | ssh-to-age
```

This extracts the SSH host key and converts it to age format, but the machine's actual age private key at `/var/lib/sops-nix/key.txt` is different.

**Correct method**:
```bash
# CORRECT: Extract from deployed machine's sops-nix age key
ssh root@<machine> 'cat /var/lib/sops-nix/key.txt | age-keygen -y'
```

**Why this matters**: If you register the SSH host key as the machine's age key in the repository, clan vars encrypted with that key cannot be decrypted on the machine.
The machine has a different age private key at `/var/lib/sops-nix/key.txt`, so decryption will fail with "Error getting data key: 0 successful groups required, got 0".

### Step 4: Initial installation (new machines)

For fresh machines (bare metal or new VMs):

```bash
# Install NixOS via clan
clan machines install <hostname> --target-host root@<ip>

# Examples:
clan machines install cinnabar --target-host root@49.13.68.78
clan machines install galena --target-host root@34.82.xxx.xxx
```

This:
- Partitions disks (if using disko)
- Installs NixOS with your configuration
- Deploys Tier 1 secrets to `/run/secrets/`
- Configures zerotier automatically

### Step 5: Update existing machines

For machines already running NixOS:

```bash
# Update configuration
clan machines update <hostname>

# Examples:
clan machines update cinnabar
clan machines update electrum
```

This:
- Rebuilds and deploys NixOS configuration
- Updates secrets if changed
- Restarts affected services

### Step 6: Set up Tier 2 secrets (sops-nix)

For user-level secrets (API keys, tokens), configure sops-nix:

```bash
# Generate age key (if not already done)
age-keygen -o ~/.config/sops/age/keys.txt

# Display public key
age-keygen -y ~/.config/sops/age/keys.txt
```

Add the public key to `.sops.yaml` and create encrypted secrets files.
See [Tier 2 secrets](#tier-2-sops-nix-user-level) below for details.

### Step 7: Verify zerotier mesh

NixOS hosts get zerotier configuration automatically via clan inventory:

```bash
# SSH to the host
ssh cameron@cinnabar.zt

# Check zerotier status
sudo zerotier-cli listnetworks
sudo zerotier-cli listpeers
```

Zerotier roles are defined in `modules/clan/inventory/services/zerotier.nix`:
- **Controller**: cinnabar (authorizes peers)
- **Peers**: electrum, galena, scheelite, stibnite, blackphos, rosegold, argentum

### Step 8: Verify deployment

On the deployed machine:

```bash
# System packages
which git gh just

# Secrets available
ls /run/secrets/

# Zerotier connected
sudo zerotier-cli info

# Home-manager (if configured)
echo $HOME_MANAGER_GENERATION
```

### NixOS onboarding complete

Your NixOS host is now:
- Running clan-managed NixOS configuration
- Using Tier 1 secrets (clan vars) for system secrets
- Connected to the zerotier mesh network

For updates, run:

```bash
clan machines update <hostname>
```

---

## Machine maintenance operations

After initial onboarding, you may need to manage machine age keys and re-encrypt secrets.
This section covers critical maintenance operations that preserve existing secret values while updating encryption.

### Re-encrypting vars after key changes

Understand when to use `clan vars fix` versus `clan vars generate`:

| Command | Purpose | Effect |
|---------|---------|--------|
| `clan vars generate <machine>` | Initial generation or regeneration | Creates NEW secret values |
| `clan vars fix <machine>` | Re-encryption only | Preserves existing values, updates encryption keys |

**When to use each**:
- Use `generate` for: New machines, intentional secret rotation
- Use `fix` for: Correcting registered age key, adding machines to shared vars

**Example workflow**: After correcting a machine's registered age key:
```bash
# Update the registered key in the repository
clan secrets machines add <machine> --age-key "age1..."

# Re-encrypt existing vars with the new key (preserves values)
clan vars fix <machine>

# Deploy the updated configuration
clan machines update <machine>
```

### Verifying age key correspondence

Before troubleshooting decryption issues, verify the registered key matches the deployed key:

```bash
# Get registered key from repository
registered=$(jq -r '.[0].publickey' sops/machines/<machine>/key.json)

# Get actual key from deployed machine
actual=$(ssh root@<machine> 'cat /var/lib/sops-nix/key.txt | age-keygen -y')

# Compare
if [ "$registered" = "$actual" ]; then
  echo "Keys match - decryption should work"
else
  echo "MISMATCH - run: clan secrets machines add <machine> --age-key \"$actual\""
  echo "Then: clan vars fix <machine>"
fi
```

This verification script shows exactly which key is wrong and how to fix it.

### Troubleshooting machine secrets

Common issues when working with machine age keys and clan vars:

**"Error getting data key: 0 successful groups required, got 0"**

This error means the machine cannot decrypt vars because the registered age key doesn't match the actual key on the machine.

Diagnosis:
```bash
# Check which key is registered
jq -r '.[0].publickey' sops/machines/<machine>/key.json

# Check which key the machine actually has
ssh root@<machine> 'cat /var/lib/sops-nix/key.txt | age-keygen -y'
```

Solution:
```bash
# Extract the correct key from the machine
actual_key=$(ssh root@<machine> 'cat /var/lib/sops-nix/key.txt | age-keygen -y')

# Update the registered key
clan secrets machines add <machine> --age-key "$actual_key"

# Re-encrypt vars (preserves values)
clan vars fix <machine>

# Deploy
clan machines update <machine>
```

**"WARNING: REMOTE HOST IDENTIFICATION HAS CHANGED"**

This warning appears when clan vars deploys a new SSH host key but the SSH daemon hasn't restarted yet.

Cause: The vars deployment updated `/etc/ssh/ssh_host_ed25519_key`, but sshd is still using the old key in memory.

Solution:
```bash
# Restart SSH daemon on the machine
ssh root@<machine> 'systemctl restart sshd'

# Or reboot the machine
ssh root@<machine> 'reboot'

# Update your known_hosts
ssh-keygen -R <machine-hostname>
ssh-keygen -R <machine-ip>
```

After the SSH daemon restarts with the new key, SSH connections will work normally.

---

## Secrets management

This infrastructure uses clan vars for all secrets with legacy sops-nix during migration.
See [Clan Integration](/concepts/clan-integration#secrets-management) for the complete explanation.

### Clan vars (system secrets)

**Purpose**: Machine-specific, auto-generated secrets

**Contents**:
- SSH host keys
- Zerotier network identities
- LUKS/ZFS encryption passphrases
- Service credentials

**Generation**:
```bash
clan vars generate <machine>
```

**Deployment**: Automatic via `clan machines install` or `clan machines update`

**Location on target**: `/run/secrets/`

**Platforms**: NixOS only (not available on darwin)

### sops-nix (legacy user secrets)

**Purpose**: User-specific, manually-created secrets

**Contents**:
- GitHub tokens and API keys
- Git signing keys
- Personal credentials
- MCP server secrets

**Setup**:
```bash
# Generate age key
age-keygen -o ~/.config/sops/age/keys.txt

# Add public key to .sops.yaml
age-keygen -y ~/.config/sops/age/keys.txt

# Create encrypted secrets
sops secrets/users/<username>.sops.yaml
```

**Configuration**: Home-manager sops module

**Location on target**: `~/.config/sops-nix/secrets/`

**Platforms**: All (darwin and NixOS)

### Platform secret comparison

| Aspect | Darwin | NixOS |
|--------|--------|-------|
| Clan vars | Not available | `clan vars generate`, `/run/secrets/` |
| sops-nix (legacy) | Age key + home-manager | Age key + home-manager |
| SSH host keys | Manual or existing | Clan vars generated |
| Zerotier identity | Homebrew installation generates | Clan vars generated |
| User API keys | sops-nix (legacy) | sops-nix (legacy) |

---

## Deferred module structure

Host configurations follow the [deferred module composition pattern](/concepts/deferred-module-composition):

```
modules/
├── machines/
│   ├── darwin/
│   │   ├── stibnite.nix      # stibnite-specific config
│   │   ├── blackphos.nix     # blackphos-specific config
│   │   ├── rosegold.nix      # rosegold-specific config
│   │   └── argentum.nix      # argentum-specific config
│   └── nixos/
│       ├── cinnabar.nix      # cinnabar-specific config
│       ├── electrum.nix      # electrum-specific config
│       ├── galena.nix        # galena-specific config
│       └── scheelite.nix     # scheelite-specific config
├── darwin/                    # Shared darwin modules (all hosts)
├── nixos/                     # Shared nixos modules (all hosts)
└── home/                      # Shared home-manager modules (all users)
```

Machine-specific files contain only truly unique settings.
Shared features are defined in aspect-based modules (`darwin/`, `nixos/`, `home/`).

---

## Clan inventory integration

NixOS hosts are registered in the clan inventory for multi-machine coordination:

```nix
# modules/clan/machines.nix
clan.machines = {
  cinnabar = {
    nixpkgs.hostPlatform = "x86_64-linux";
    imports = [ config.flake.modules.nixos."machines/nixos/cinnabar" ];
  };
  # ... other machines
};
```

Service instances assign machines to roles:

```nix
# modules/clan/inventory/services/zerotier.nix
inventory.instances.zerotier = {
  roles.controller.machines."cinnabar" = { };
  roles.peer.machines = {
    "electrum" = { };
    "stibnite" = { };
  };
};
```

This enables coordinated multi-machine deployments and service discovery.

---

## Troubleshooting

### Darwin: darwin-rebuild fails

**Symptom**: `darwin-rebuild switch` fails with build errors

**Diagnosis**:
```bash
# Verify configuration builds
nix build .#darwinConfigurations.<hostname>.system --show-trace
```

**Common causes**:
- Missing Xcode CLT: `xcode-select --install`
- Flake not trusted: Answer `y` to trust prompts
- Nix store corruption: `sudo nix-store --verify --repair`

### Darwin: Secrets not decrypting

**Symptom**: `sops -d` fails with "no key could be found"

**Diagnosis**:
```bash
# Check age key exists
cat ~/.config/sops/age/keys.txt

# Check public key in .sops.yaml
grep "$(age-keygen -y ~/.config/sops/age/keys.txt)" .sops.yaml
```

**Solution**: Add your age public key to `.sops.yaml` creation rules.

### NixOS: clan machines install fails

**Symptom**: Installation fails or hangs

**Diagnosis**:
```bash
# Verify SSH access
ssh root@<ip> 'echo ok'

# Check clan vars generated
ls vars/<hostname>/
```

**Common causes**:
- SSH key not authorized on target
- Vars not generated: Run `clan vars generate <hostname>` first
- Network issues: Check firewall allows SSH

### NixOS: Zerotier not connecting

**Symptom**: Host not appearing in zerotier network

**Diagnosis**:
```bash
# On the target host
sudo zerotier-cli info
sudo zerotier-cli listnetworks
```

**Solution**: Ensure controller has authorized the peer:
```bash
# Update cinnabar to authorize new peers
clan machines update cinnabar
```

### Both: Flake trust prompts

**Symptom**: Repeated prompts about substituters and trusted-public-keys

**Solution**: Answer `y` to all four prompts (allow + permanently trust for both settings).
This is a one-time setup per machine.

---

## Success criteria

A successful darwin onboarding:
- [ ] Nix installed with flakes enabled
- [ ] `darwin-rebuild switch` completes without errors
- [ ] Age key at `~/.config/sops/age/keys.txt`
- [ ] Zerotier connected to network `db4344343b14b903`
- [ ] Secrets decrypting via sops-nix

A successful NixOS onboarding:
- [ ] `clan machines install` completes without errors
- [ ] Tier 1 secrets at `/run/secrets/`
- [ ] Zerotier mesh connected
- [ ] SSH access via `.zt` hostname

---

## See also

- [Deferred Module Composition](/concepts/deferred-module-composition) - Module organization pattern
- [Clan Integration](/concepts/clan-integration) - Multi-machine coordination
- [Getting Started](/guides/getting-started/) - Initial repository setup
- [User Onboarding](/guides/home-manager-onboarding/) - Standalone home-manager for non-admin users
