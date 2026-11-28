---
title: Host Onboarding
sidebar:
  order: 4
---

This guide covers onboarding a new host to this infrastructure.
The workflow differs significantly between darwin (macOS) and NixOS platforms.

## Platform overview

| Platform | Hosts | Deployment command | Secrets |
|----------|-------|-------------------|---------|
| Darwin (nix-darwin) | stibnite, blackphos, rosegold, argentum | `just activate` | Clan vars (machine key installed with `clan vars upload`) + legacy sops tree |
| NixOS (clan-managed) | cinnabar, electrum, galena, scheelite, magnetite, pyrite | `clan machines update` | Clan vars + legacy sops tree |

Darwin hosts use nix-darwin with standalone builds.
NixOS hosts are managed by [clan](/concepts/clan-integration) which handles deployment, secrets generation, and multi-machine coordination.

## Architecture references

Before proceeding, understand the configuration patterns:
- [Deferred Module Composition](/concepts/deferred-module-composition) - Module organization (aspect-based, not host-based)
- [Clan Integration](/concepts/clan-integration) - Multi-machine coordination and secrets management

Configuration files live in `modules/machines/darwin/` and `modules/machines/nixos/`, not `configurations/`.

For detailed learning-oriented walkthroughs, see the [Darwin Deployment Tutorial](/tutorials/darwin-deployment/) for macOS or [NixOS Deployment Tutorial](/tutorials/nixos-deployment/) for servers.

## Adding a host to the fleet description

A host is declared once, as its record `flake.fleet.hosts.<host>` in `modules/lib/hosts.nix`, and composed once, in `modules/machines/<class>/<host>/default.nix`.
Its people's accounts are attachments in `modules/lib/host-users.nix`.
Every other list that names hosts is one of three kinds, and the table says what each needs for a new host.

### Host lists by treatment

| List | Treatment | For a new host |
|------|-----------|----------------|
| clan inventory machines, with tags and description (`modules/clan/inventory/machines.nix`) | derived from the registry | nothing; tags and description are fields of the record |
| `machineAnchors` (`modules/checks/sops-correspondence.nix`) | derived from the registry's enrolled hosts | nothing |
| `modules/lib/cloud-machines.nix` | hand-written, checked | a row for a host tagged `cloud`; `checks.x86_64-linux.host-list-keys` fails on a host tagged `cloud` without a row, and on a row for a name no such host has |
| `modules/lib/observability-hosts.nix` | hand-written, checked | a row, with `collect = false` until the host's first watched deploy; `host-list-keys` fails until it exists |
| ssh `logins` (`modules/home/core/ssh.nix`, `flake.lib.sshLogins`) | hand-written, checked | the login used for the host; `host-list-keys` fails until it exists |
| the `structure-fleet` pin (`modules/checks/structure/flake-shape.nix`) | hand-written, checked | the host and its class; `checks.x86_64-linux.structure-fleet` fails until it is added |
| machine `testSizes` entries (`modules/checks/machines.nix`) | hand-written, checked | `nixos-<host> = { class = "medium"; measured = false; };` (or `darwin-<host>`): a check with fewer than three recorded runs is medium and unmeasured (`modules/checks/README.md`, "What every check here carries"), whatever class the existing hosts' measured entries give; `test-size-classes` fails naming a check with no entry |
| `.sops.yaml` | hand-written, checked | the machine's anchor and its place in the creation rules; `checks.x86_64-linux.sops-correspondence` fails until it matches `sops/machines/<host>/key.json` |
| `ztRecords` (`modules/machines/nixos/cinnabar/zt-dns.nix`) | left | the host's `.zt` name, joined by hand; no check fails when it is missing, and the list goes with ZeroTier |
| the evaluator table in `modules/README.md` | left | a row; no check reads it |

Counted as files outside `modules/lib/hosts.nix` and the host's own directory, a new host's name is written by hand in 9: the six checked rows above (cloud table, observability table, ssh logins, `structure-fleet`, `testSizes`, `.sops.yaml`), `modules/lib/host-users.nix` when the host carries accounts, and two kept by convention only, `ztRecords` and the evaluator table in `modules/README.md`.

`host-list-keys` reports a missing or extra host as `"<list>": { "<host>": false }` in its diff, where `<list>` is `cloudMachines`, `observabilityHosts` or `sshLogins`.

### The record's fields

- `zerotier.address` and `zerotier.memberId`: for a NixOS host, written after its first `clan vars generate`, from `vars/shared/zerotier-ip-<host>-zerotier/ip/value` and the node id of `vars/shared/zerotier-identity-<host>`; for a Mac, from `zerotier-cli info` after it joins the network by hand. They go with ZeroTier.
- `tags`: the clan services select machines by `nixos` (sshd and tor), `peer` (the ZeroTier peers) and `all` (emergency access), and `host-list-keys` reads `cloud`. A host without `peer` joins no mesh, and no check fails. The other tags (`darwin`, `hetzner`, `gcp`, `gpu`, `laptop`, `workstation`, `fleet`, `controller`, `deployer-workstation`) select hosts only on the command line.
- `description`: free text, the clan inventory machine's description.

### Generated steps, in order

No declaration produces these; each is done once, in this order, and a check fails until it is done.

1. **The machine key and vars.** `clan vars generate <host>` writes the machine's age key under `sops/machines/<host>/` and its vars under `vars/per-machine/<host>/`. Until the generated `openssh` public key is committed, the host-key obligation fails the host's machine check, naming the file to commit.
2. **The bridge files re-encrypted for the new recipient.** With the machine's anchor in `.sops.yaml`, re-encrypt each file under `secrets/` its rules now reach, among them the `secrets/bridge/<identity>-age-key.enc` file of every account bridged on the host (`sops updatekeys <file>`). `sops-correspondence` fails on a file whose recipients differ from its rule's anchors, and `hm-sops-bridge` fails the host's evaluation when its machine key is not a recipient of a bridged account's file.
3. **The `fleet-deployers` link, for an enabled deploy target.** Every enabled NixOS or darwin machine other than the operator's workstations is a target of the fleet deployer with no edit in `modules/lib/fleet-deployer.nix`, so its machine key must name the group: `sops/secrets/<host>-age.key/groups/fleet-deployers`, a symbolic link to `../../../groups/fleet-deployers`. `sops-correspondence` fails with `<host>-age.key does not name the fleet-deployers group` until it exists.
4. **The topology files.** `just topology-generate` rewrites `packages/docs/diagrams/topology/`; `checks.x86_64-linux.fleet-topology-fresh` fails naming each stale file until they are committed.

### A new server's facts

- `serverType` (the Hetzner `serverType` or GCP `machineType` of its row in `modules/lib/cloud-machines.nix`) and `stateVersion` (in the record) are required and have no default, so a new host fails evaluation until both are written; a cloud row with neither type fails naming the host. A server type costs money and is chosen per host.
- `stateVersion` is the NixOS release of the locked nixpkgs when the host is first installed (`nix eval --raw .#nixosConfigurations.<existing-host>.config.system.nixos.release`), and it never changes afterwards.
- The boot mode is not chosen per host: it follows the server type, in `flake.modules.nixos.hetzner-cloud`. Shared-vCPU `cx*` types boot BIOS with GRUB; dedicated `ccx*` and ARM `cax*` types boot UEFI with systemd-boot. A host file that overrides the boot loader its type gives fails the host's machine check.

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
cd ~/projects  # Or your preferred directory for repositories
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

Expected: a directory named after the host, holding `default.nix` (e.g., `modules/machines/darwin/stibnite/default.nix`), and the host's record in `modules/lib/hosts.nix`.

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

### Step 5: Install the machine key (hosts with clan vars)

If the repository holds a machine key for this host (`sops/secrets/<hostname>-age.key` exists), install it before the first activation, from a machine that holds the operator identity:

```bash
clan vars upload <hostname>
```

This writes `/var/lib/sops-nix/key.txt`, which sops-nix needs to install the host's clan vars.
A local activation never writes it, and `just activate` refuses to run while it is missing or differs from `sops/machines/<hostname>/key.json`, printing this command.
A new host gets its machine key the first time `clan vars generate <hostname>` runs.

### Step 6: Deploy configuration

Apply the nix-darwin configuration:

```bash
just activate-darwin <hostname>

# On the host itself, the hostname is detected:
just activate
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

### Step 7: Set up your workstation age key (legacy sops tree)

Your home-manager secrets (`secrets/home-manager/users/<user>/secrets.yaml`) decrypt with your personal age key in `~/.config/sops/age/keys.txt`.
That key is derived from your SSH key in Bitwarden, never generated separately; follow [Workstation age key](/guides/secrets-management#workstation-age-key).

A new user's public key is added to `.sops.yaml` as an anchor named after the identity, with a rule for that user's home secrets (see the [Secrets Setup Tutorial](/tutorials/secrets-setup)):

```yaml
keys:
  - &yourname-user age1...   # ssh-to-age of your first meta.nix sshKeys entry

creation_rules:
  - path_regex: secrets/home-manager/users/yourname/.*\.yaml$
    key_groups:
      - age:
        - *admin
        - *admin-user
        - *yourname-user
```

Then run `just update-all-keys` and `nix build .#checks.x86_64-linux.sops-correspondence`.

#### Verify secrets decrypt

```bash
sops -d secrets/home-manager/users/<user>/secrets.yaml >/dev/null && echo ok
```

If decryption fails, verify:
- `age-keygen -y ~/.config/sops/age/keys.txt` lists the public key `.sops.yaml` names for you
- the file's recipients include it (`yq '.sops.age[].recipient' <file>`); if not, run `just update-all-keys`

### Step 8: Install zerotier (darwin-specific)

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

### Step 9: Verify deployment

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
- Using clan vars for machine secrets and sops-nix for user secrets

For updates, run:

```bash
just activate
```

---

## NixOS host onboarding (clan-managed)

Use this for NixOS servers: cinnabar, electrum, galena, scheelite.

NixOS hosts are managed by [clan](/concepts/clan-integration), which provides:
- Unified deployment commands
- Automatic secrets generation (clan vars)
- Multi-machine service coordination
- Zerotier mesh networking

### Prerequisites

Before starting, ensure you have:
- SSH access to deploy machine (or physical access for initial install)
- Your personal age key at `~/.config/sops/age/keys.txt` (operator identity, for encrypting secrets to the new host)
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
ls modules/machines/nixos/<hostname>/default.nix
```

Each machine's configuration is `modules/machines/nixos/<hostname>/default.nix`, and its record (system, class, inventory tags) is in `modules/lib/hosts.nix`; `modules/clan/machines.nix` derives the clan machines from those records.

### Step 3: Generate secrets (clan vars)

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
- Deploys clan vars secrets to `/run/secrets/`
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

### Step 6: Confirm user secret key delivery

User-level secrets (API keys, tokens) live in the legacy sops tree, but a clan-managed NixOS host needs no hand-provisioned `~/.config/sops/age/keys.txt`.
The `hm-sops-bridge` module decrypts `secrets/bridge/<id>-age-key.enc` with the machine's clan age key during system activation, writes it to `/run/secrets/<id>-age-key` owned by the user with mode `0400`, and points that user's home-manager `sops.age.keyFile` at it, overriding the XDG default set by `base-sops`.

Enrolling a user on this host therefore means three declarations rather than a manual key copy:
- `flake.users.<user>.meta.sopsAgeKeyId` is set in `modules/home/users/<user>/meta.nix`
- the user is attached to the host in `modules/lib/host-users.nix` (`flake.fleet.hosts.<host>.users.<user> = { };`), whose `sopsBridge` defaults to true on NixOS; the `home-manager-integration` aspect then enrolls the user in `hm-sops-bridge` and builds the home
- `secrets/bridge/<id>-age-key.enc` exists and is encrypted to this machine's age key (add the machine's anchor to the `secrets/bridge/` rule and run `just update-all-keys`; the host's evaluation fails until it is)

Verify on the host after deployment:

```bash
ls -l /run/secrets/<id>-age-key
systemctl status home-manager-<user>.service
```

Encrypting new secrets for a user is still an operator task performed from a workstation holding its own age key.
See [Legacy sops tree](#legacy-sops-tree-user-secrets) below for details.

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
- Using clan vars for system secrets
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

Secrets live in two sops trees that share one operator identity.
See the [Secrets Management Guide](/guides/secrets-management) for procedures and [Clan Integration](/concepts/clan-integration#secrets-management) for how clan fits in.

### Clan vars (machine secrets)

**Purpose**: Machine-specific, generated secrets

**Contents**:
- SSH host keys
- Zerotier network identities
- LUKS/ZFS encryption passphrases
- Service credentials and certificates

**Generation**:
```bash
clan vars generate <machine>
```

**Deployment**: `clan machines install` or `clan machines update` on NixOS; on darwin, `clan vars upload <host>` installs the machine key once and `just activate` installs the vars

**Location on target**: `/run/secrets/`

**Platforms**: NixOS and darwin

### Legacy sops tree (user secrets)

**Purpose**: User-specific, hand-written secrets

**Contents**:
- GitHub tokens and API keys
- Git signing keys
- Personal credentials
- MCP server secrets

**Setup**: derive your personal age key from your Bitwarden SSH key ([Workstation age key](/guides/secrets-management#workstation-age-key)), then edit your file:
```bash
sops secrets/home-manager/users/<username>/secrets.yaml
```

**Configuration**: Home-manager sops module (`sops.defaultSopsFile` in `modules/home/users/<username>/default.nix`)

**Location on target**: `~/.config/sops-nix/secrets/`

**Platforms**: All (darwin and NixOS), with the personal key provisioned differently per platform: derived from Bitwarden into the XDG path on darwin, and delivered by `hm-sops-bridge` from `/run/secrets/<id>-age-key` on NixOS.

### Platform secret comparison

| Aspect | Darwin | NixOS |
|--------|--------|-------|
| Clan vars | `clan vars generate`; machine key via `clan vars upload`; `/run/secrets/` | `clan vars generate`, `/run/secrets/` |
| User secrets | Personal key at XDG path + home-manager | Personal key bridged by `hm-sops-bridge` + home-manager |
| SSH host keys | macOS-managed, pinned in `flake.lib.darwinHostKeys` | Clan vars generated |
| Zerotier identity | Homebrew installation generates | Clan vars generated |

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

Each host's record in `modules/lib/hosts.nix` is the source of its clan machine: `modules/clan/machines.nix` builds `flake.clan.machines.<host>` from the record's `system` and imports `modules/machines/<class>/<host>/default.nix`, and `modules/clan/inventory/machines.nix` builds the inventory machine from the record's tags and description; neither file names a host.

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

### Darwin: activation fails

**Symptom**: `just activate` fails with build errors, or stops with "Machine key check failed"

**Diagnosis**:
```bash
# Verify configuration builds
nix build .#darwinConfigurations.<hostname>.system --show-trace
```

**Common causes**:
- Machine key missing or stale: run `clan vars upload <hostname>`
- Missing Xcode CLT: `xcode-select --install`
- Flake not trusted: Answer `y` to trust prompts
- Nix store corruption: `sudo nix-store --verify --repair`

### Darwin: Secrets not decrypting

**Symptom**: `sops -d` fails with "no key could be found" or "could not decrypt data key"

**Diagnosis**:
```bash
# Your public keys
age-keygen -y ~/.config/sops/age/keys.txt

# The file's recipients
yq '.sops.age[].recipient' secrets/home-manager/users/<username>/secrets.yaml
```

**Solution**: derive your key from Bitwarden if it is missing ([Workstation age key](/guides/secrets-management#workstation-age-key)); if your anchor is in `.sops.yaml` but not among the file's recipients, run `just update-all-keys`.

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
- [ ] Machine key installed (`clan vars upload <hostname>`) if the host has one
- [ ] `just activate` completes without errors
- [ ] Personal age key at `~/.config/sops/age/keys.txt`, derived from Bitwarden
- [ ] Zerotier connected to network `db4344343b14b903`
- [ ] Secrets decrypting via sops-nix

A successful NixOS onboarding:
- [ ] `clan machines install` completes without errors
- [ ] Clan vars secrets at `/run/secrets/`
- [ ] Zerotier mesh connected
- [ ] SSH access via `.zt` hostname

---

## See also

- [Deferred Module Composition](/concepts/deferred-module-composition) - Module organization pattern
- [Clan Integration](/concepts/clan-integration) - Multi-machine coordination
- [Getting Started](/guides/getting-started/) - Initial repository setup
- [User Onboarding](/guides/home-manager-onboarding/) - Standalone home-manager for non-admin users
