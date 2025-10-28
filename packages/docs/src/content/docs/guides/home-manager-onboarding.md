---
title: Home-Manager-Only User Onboarding Guide
sidebar:
  order: 4
---

This guide covers onboarding non-admin users (like runner, raquel) on hosts where an admin user already has nix-darwin/NixOS configured.

## When to use this guide

Use this procedure when:
- An admin user (crs58/cameron) has already configured nix-darwin on the host
- You need to set up a non-admin user's environment with home-manager only
- The host already has nix, SOPS infrastructure, and secrets deployed by the admin

This guide assumes:
- The admin user has completed host onboarding (see [`onboarding.md`](./onboarding.md))
- The nix daemon is running and `/nix/store` is available
- Host SSH keys are deployed to `/etc/ssh/ssh_host_ed25519_key`

**For SOPS secrets architecture details**, see the "Architecture overview" section in [`onboarding.md`](./onboarding.md).
This guide focuses only on user-specific home-manager setup.

## Architecture overview

**Admin user** (crs58/cameron):
- Managed via nix-darwin (macOS) or NixOS (Linux)
- Controls system-level configuration
- Manages the nix daemon and shared `/nix/store`

**Non-admin users** (runner, raquel):
- Managed via home-manager only (standalone mode)
- Personal environment in their home directory
- Use shared `/nix/store` and nix daemon
- Independent home-manager generations in `/nix/var/nix/profiles/per-user/<username>/`

## Prerequisites

Before starting, ensure:
- [ ] You can SSH or have physical access to the host
- [ ] The admin user has completed host onboarding
- [ ] Your user account exists on the host: `id <username>`
- [ ] Nix is available: `which nix`
- [ ] Your user configuration exists in `config.nix`
- [ ] Your SOPS user key exists in Bitwarden (e.g., `sops-raquel-user-ssh`)
- [ ] Your secrets are encrypted in `.sops.yaml` for your user identity

## User configuration setup

### Step 1: Verify user in config.nix

Check that your user is defined in `config.nix`:

```nix
# Example for raquel
raquel = {
  username = "raquel";
  fullname = "Someone Local";
  email = "raquel@localhost";
  sshKey = "ssh-ed25519 AAAAC3...";  # Your SSH public key
  sopsIdentifier = "raquel-user";     # Maps to secrets/users/raquel-user/
  isAdmin = false;
};
```

### Step 2: Create home configuration

Create `configurations/home/<username>@<hostname>.nix`:

```nix
# configurations/home/raquel@blackphos.nix
{
  flake,
  pkgs,
  lib,
  ...
}:
let
  inherit (flake) config inputs;
  inherit (inputs) self;
  user = config.raquel;  # Reference from config.nix
in
{
  imports = [
    self.homeModules.default
    self.homeModules.darwin-only  # or linux-only for NixOS hosts
    self.homeModules.standalone
  ];

  home.username = user.username;
  home.homeDirectory = "/Users/${user.username}";  # or /home/ for Linux
  home.stateVersion = "23.11";

  # User-specific overrides
  programs.git = {
    userName = lib.mkForce user.fullname;
    userEmail = lib.mkForce user.email;
  };

  # Disable heavy tools if not needed
  programs.lazyvim.enable = lib.mkForce false;
}
```

### Step 3: Create user secrets

Your secrets directory structure should follow:

```
secrets/
└── users/
    └── <sopsIdentifier>/
        ├── signing-key.yaml      # SSH key for git/jujutsu/radicle signing
        ├── llm-api-keys.yaml     # LLM API keys (if using Claude Code)
        └── mcp-api-keys.yaml     # MCP server keys (if using Claude Code)
```

**For new users**: Copy from the template:
```bash
cp -r secrets/users/template-user secrets/users/<sopsIdentifier>
```

Then edit and encrypt the files for your keys.

### Step 4: Update .sops.yaml

Ensure `.sops.yaml` has rules for your user:

```yaml
keys:
  - &<your-user> age1abc...  # from sops-<user>-ssh in Bitwarden

creation_rules:
  - path_regex: secrets/users/<sopsIdentifier>/.*\.yaml$
    key_groups:
      - age:
        - *admin
        - *dev
        - *<your-user>
```

### Step 5: Sync age keys

On the host, as your user:

```bash
# Enter devshell (provides bitwarden-cli, sops, etc.)
cd ~/projects/nix-config
nix develop

# Unlock Bitwarden
export BW_SESSION=$(bw unlock --raw)

# Sync age keys to ~/.config/sops/age/keys.txt
just sops-sync-keys

# Lock Bitwarden
bw lock
```

This creates `~/.config/sops/age/keys.txt` containing:
- Repository dev key (all users)
- Your user identity key
- Host key (for this machine)

### Step 6: Test secrets decryption

```bash
SOPS_AGE_KEY_FILE=~/.config/sops/age/keys.txt sops -d secrets/users/<sopsIdentifier>/signing-key.yaml | head -5
```

If successful, you'll see your decrypted signing key.

### Step 7: Verify configuration builds

```bash
# Verify flake and build configuration (auto-detects home-manager)
just verify
```

This runs:
- `nix flake check` to validate the entire flake
- Auto-detects and builds your home-manager configuration

### Step 8: Activate

**The user must run activation interactively:**

```bash
# Using just (auto-detects <username>@<hostname>)
just activate
```

The `just activate` recipe automatically detects whether to use:
- Home-manager-only config (if `./configurations/home/$USER@$(hostname).nix` exists)
- System-level config (otherwise)

After activation:
- Home-manager generation is in `/nix/var/nix/profiles/per-user/<username>/home-manager`
- Dotfiles and configurations are in your home directory
- SOPS plist is deployed to `~/Library/LaunchAgents/` (darwin) or systemd unit (linux)

### Step 9: Load SOPS agent (standalone home-manager only)

**CRITICAL STEP for standalone home-manager on darwin:**

```bash
# Load the SOPS launchd agent (one-time setup)
just sops-load-agent
```

**Why this is necessary:**
- nix-darwin automatically loads SOPS agents during system activation
- Standalone home-manager creates the plist but **does not load it automatically**
- Without loading the agent, secrets won't be decrypted and deployed
- Symptoms: `~/.radicle/keys/radicle` symlink missing, git signing fails

**One-time vs per-login:**
- The `launchctl load` command is **one-time** (persists across reboots)
- The plist in `~/Library/LaunchAgents/` ensures the agent starts on login
- Only run `just sops-load-agent` once after initial activation
- Re-run only if you unload the agent or the plist changes significantly

**Linux (NixOS) users:** Skip this step - systemd automatically starts the sops-nix user service.

After loading the agent:
- Secrets directory created: `~/.config/sops-nix/secrets/`
- Private keys deployed (e.g., `~/.radicle/keys/radicle` symlink to secrets directory)
- Git signing, jujutsu, radicle keys available

## Validation

After activation and loading SOPS agent, verify:

- [ ] SOPS agent loaded: `launchctl list | grep sops` (darwin only)
- [ ] Secrets directory exists: `ls -la ~/.config/sops-nix/secrets/`
- [ ] Git signing key: `git config --get user.signingkey`
- [ ] Signing key symlink: `ls -la ~/.radicle/keys/radicle`
- [ ] Age keys synced: `ls -la ~/.config/sops/age/keys.txt`
- [ ] Shell configured: Check your shell prompt, aliases
- [ ] Tools available: `which git gh just ripgrep fd bat`

## Relationship to nix-darwin

**How they coexist:**

```
/nix/store/                    # Shared nix store (admin manages)
├── <hash>-git-2.x/           # Packages used by all users
└── <hash>-home-manager-gen/  # Per-user generations

/nix/var/nix/profiles/
├── system/                    # nix-darwin system profile (admin only)
└── per-user/
    ├── crs58/
    │   └── home-manager -> /nix/store/<hash>  # Admin's home-manager
    ├── runner/
    │   └── home-manager -> /nix/store/<hash>  # Runner's home-manager
    └── raquel/
        └── home-manager -> /nix/store/<hash>  # Raquel's home-manager
```

**Key points:**
- Admin's nix-darwin controls system-level configuration
- Each user's home-manager controls their personal environment
- All users share the same `/nix/store` (deduplication)
- Users have independent home-manager generations
- No conflicts - each user manages their own profile

## Troubleshooting

### SOPS secrets not deployed (symlinks missing)

If `~/.radicle/keys/radicle` or other secret symlinks are missing:

```bash
# Check if SOPS agent is loaded (darwin)
launchctl list | grep sops

# If not loaded, load it
just sops-load-agent

# Verify secrets directory created
ls -la ~/.config/sops-nix/secrets/
```

The SOPS launchd agent (darwin) or systemd service (linux) must be running to deploy secrets.

### Secrets won't decrypt

```bash
# Check keys.txt exists
cat ~/.config/sops/age/keys.txt

# Regenerate from Bitwarden
export BW_SESSION=$(bw unlock --raw)
just sops-sync-keys
bw lock
```

### Build fails with "no such file" for secrets

Ensure secrets files exist and are committed:

```bash
ls secrets/users/<sopsIdentifier>/
git status
```

If missing, copy from template and re-encrypt.

### Activation permission errors

Home-manager-only activation should not require `sudo`. If you see permission errors:
- Check you're not trying to modify system files
- Verify you own your home directory: `ls -ld ~`
- Ensure nix daemon is running: `pgrep nix-daemon`

## See also

- Host onboarding (admin): `docs/notes/hosts/onboarding.md`
- SOPS architecture: `docs/notes/secrets/sops-migration-summary.md`
- Creating new users: See "Template user directory" section below

