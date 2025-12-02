---
title: "Darwin Deployment"
description: "Learn how to deploy and manage macOS machines with nix-darwin, from initial setup to zerotier mesh integration."
sidebar:
  order: 4
---

This tutorial guides you through deploying a macOS machine using nix-darwin.
You'll understand how darwin differs from NixOS, set up zerotier mesh networking, and learn the patterns that make darwin management effective.

## What you will learn

By the end of this tutorial, you will understand:

- How nix-darwin provides declarative macOS configuration
- Why darwin uses different patterns than NixOS (and the practical implications)
- How zerotier mesh networking integrates with darwin via Homebrew
- The structure of darwin machine configurations in this infrastructure
- How to deploy, update, and troubleshoot darwin hosts

## Prerequisites

Before starting, you should have:

- Completed the [Bootstrap to Activation Tutorial](/tutorials/bootstrap-to-activation)
- Completed the [Secrets Setup Tutorial](/tutorials/secrets-setup)
- A macOS machine (Apple Silicon or Intel)
- Administrator access to the machine
- The repository cloned and direnv activated

## Estimated time

60-90 minutes for a complete darwin deployment.
Updates take 10-15 minutes once the initial setup is complete.

## Understanding darwin in this infrastructure

Before deploying, let's understand what makes darwin different and why those differences matter.

### What is nix-darwin?

[nix-darwin](https://github.com/LnL7/nix-darwin) brings NixOS-style declarative configuration to macOS.
It manages system preferences, launchd services, homebrew packages, and more through Nix expressions.

Unlike NixOS, which controls the entire operating system, nix-darwin works alongside macOS.
Apple controls the kernel, core system services, and many aspects of the user interface.
nix-darwin handles the parts that macOS allows external tools to configure.

### Darwin vs NixOS in this fleet

The infrastructure includes four darwin machines and four NixOS machines:

**Darwin machines:**
- **stibnite** - crs58's primary workstation (single user)
- **blackphos** - raquel's workstation (dual user: raquel primary, crs58 admin)
- **rosegold** - janettesmith's workstation (dual user: janettesmith primary, cameron admin)
- **argentum** - christophersmith's workstation (dual user: christophersmith primary, cameron admin)

**Key differences from NixOS:**

| Aspect | Darwin | NixOS |
|--------|--------|-------|
| Deployment | `darwin-rebuild switch` | `clan machines update` |
| Secrets Tier 1 | Not available | clan vars |
| Secrets Tier 2 | sops-nix | sops-nix |
| Zerotier | Homebrew cask | Nix package |
| Service management | launchd | systemd |
| Disk management | macOS manages | disko via clan |

These differences shape how you approach darwin configuration and deployment.

### Why Homebrew for zerotier?

You might wonder why zerotier uses Homebrew instead of Nix on darwin.
The answer involves macOS security architecture.

Zerotier requires:
- System extension installation (managed by macOS security policies)
- Network extension entitlements (requires Apple notarization)
- Persistent launchd service registration

Nix can build zerotier, but it can't install system extensions or handle the macOS security prompts required for network extensions.
The Homebrew cask includes Apple-notarized binaries and proper installer scripts.

This is a pragmatic choice: Homebrew handles the parts Nix can't, while Nix manages everything else.
The activation script installs zerotier via Homebrew and joins the network automatically.

## Step 1: Explore the darwin configuration structure

Let's understand how darwin machines are configured before making changes.

### Module hierarchy

```bash
ls modules/machines/darwin/
```

Each darwin machine has its own directory containing:
- `default.nix` - Main configuration importing modules and defining machine-specific settings
- Machine-specific overrides as needed

### Examine a machine configuration

Look at a typical darwin configuration:

```bash
cat modules/machines/darwin/stibnite/default.nix
```

You'll see a structure like:

```nix
{ config, pkgs, ... }:
{
  imports = [
    # Aggregate imports
  ];

  # Machine identification
  networking.hostName = "stibnite";

  # Homebrew configuration (including zerotier)
  homebrew = {
    enable = true;
    casks = [ "zerotier-one" ];
  };

  # Activation script for zerotier network join
  system.activationScripts.postUserActivation.text = ''
    # Zerotier network join logic
  '';

  # User imports
  home-manager.users.crs58 = import ../../../home/users/crs58;
}
```

### Understanding aggregates

Darwin configurations use aggregate imports to pull in related features.
These aggregates compose modules by functional area:

```bash
ls modules/home/all/
```

Common aggregates include:
- **aggregate-core** - Essential tools everyone needs
- **aggregate-shell** - Shell configuration (zsh, starship, etc.)
- **aggregate-development** - Development tools (git, editors, etc.)
- **aggregate-ai** - AI tooling (claude-code, etc.)

This pattern means changes to an aggregate affect all users who import it, reducing duplication.

## Step 2: Verify your machine configuration exists

Before deploying, ensure your machine has a configuration.

### Check for existing configuration

```bash
ls modules/machines/darwin/
```

If your hostname appears in the list, you have a configuration.
If not, you'll need to create one; see the [Host Onboarding Guide](/guides/host-onboarding#darwin-host-onboarding-macos).

### Verify the configuration builds

```bash
# Replace 'stibnite' with your hostname
nix build .#darwinConfigurations.stibnite.system --dry-run
```

A successful dry-run means the configuration is valid Nix.
Any errors indicate configuration problems to fix before proceeding.

## Step 3: Understand the deployment process

Darwin deployment differs from NixOS because darwin-rebuild runs on the machine itself rather than being pushed from a controller.

### The activation flow

1. **Build**: Nix evaluates your configuration and builds derivations
2. **Switch**: darwin-rebuild creates a new generation and updates symlinks
3. **Activate**: Activation scripts run (user creation, service registration, etc.)
4. **Homebrew**: If configured, homebrew packages install or update
5. **Post-activation**: Custom scripts run (like zerotier network join)

### Generations and rollback

Each successful activation creates a new "generation."
You can list and roll back to previous generations:

```bash
# List recent generations
darwin-rebuild --list-generations | head -10

# Roll back to previous generation
darwin-rebuild switch --rollback
```

This provides safety: if a change breaks something, you can roll back immediately.

## Step 4: Deploy your darwin configuration

Now deploy the configuration to your machine.

### Standard deployment

```bash
darwin-rebuild switch --flake .#stibnite
```

Replace `stibnite` with your hostname.

Or use the convenient just task:

```bash
just activate
```

The `just activate` command auto-detects your platform and hostname.

### First-time deployment

If this is a fresh machine without prior darwin-rebuild history, you might need:

```bash
# First time on a new machine
darwin-rebuild switch --flake .#hostname --impure
```

The `--impure` flag allows access to files outside the flake during initial setup.
Subsequent rebuilds shouldn't need it.

### Watch the output

During deployment, observe:
- **Building**: Derivations being built or fetched from cache
- **Activating**: System changes being applied
- **Homebrew**: Cask installations (like zerotier-one)
- **Post-activation**: Custom scripts running

If you see errors, note the specific message for troubleshooting.

## Step 5: Set up zerotier mesh networking

Zerotier connects your darwin machine to the infrastructure's private mesh network.

### Understanding the mesh

The zerotier network (ID: `db4344343b14b903`) creates a virtual Layer 2 network across all machines:

```
                    ┌─────────────┐
                    │  cinnabar   │
                    │ (controller)│
                    └──────┬──────┘
                           │
        ┌──────────────────┼──────────────────┐
        │                  │                  │
   ┌────┴────┐       ┌────┴────┐       ┌────┴────┐
   │stibnite │       │blackphos│       │ galena  │
   │ (peer)  │       │ (peer)  │       │ (peer)  │
   └─────────┘       └─────────┘       └─────────┘
```

**cinnabar** is the zerotier controller, managing network membership.
All other machines are peers that connect through the controller.

### Verify zerotier installation

After activation, zerotier should be installed via Homebrew:

```bash
# Check zerotier is installed
which zerotier-cli

# Check the service is running
sudo zerotier-cli status
```

If zerotier-cli isn't found, the Homebrew cask may not have installed.
Check the activation output for errors, or install manually:

```bash
brew install --cask zerotier-one
```

### Join the network

The activation script should automatically join the network.
Verify:

```bash
sudo zerotier-cli listnetworks
```

If the network isn't listed, join manually:

```bash
sudo zerotier-cli join db4344343b14b903
```

### Authorize the machine

New machines need authorization from the network controller.
Contact the network administrator (or if you have controller access):

1. Log into the zerotier controller web interface
2. Find the pending member by its zerotier address
3. Authorize the machine
4. Optionally assign a managed IP address

### Verify connectivity

Once authorized:

```bash
# Check network status (should show "OK")
sudo zerotier-cli listnetworks

# Get your zerotier IP address
sudo zerotier-cli listnetworks | awk '{print $NF}'

# Ping another machine on the mesh
ping cinnabar.zt  # If DNS is configured
ping 10.144.x.y   # Or use the IP directly
```

## Step 6: Configure secrets for darwin

Darwin machines use Tier 2 secrets (sops-nix) since Tier 1 (clan vars) requires NixOS.

### Ensure your age key exists

```bash
ls -la ~/.config/sops/age/keys.txt
```

If the key doesn't exist, complete the [Secrets Setup Tutorial](/tutorials/secrets-setup) first.

### Verify secrets deployment

After activation, check that secrets deployed:

```bash
ls -la ~/.config/sops-nix/secrets/
```

You should see your configured secrets as files with restricted permissions.

### Test a secret

```bash
# View a secret (be careful with sensitive values)
cat ~/.config/sops-nix/secrets/github-token
```

If secrets aren't appearing, check:
1. Your age key is in the correct location
2. Your public key is in `.sops.yaml`
3. The sops configuration in your home-manager module is correct

## Step 7: Verify the complete deployment

Let's confirm everything is working.

### System verification

```bash
# Check the current generation
darwin-rebuild --list-generations | head -3

# Verify system profile
echo $PATH | tr ':' '\n' | grep nix

# Check a nix-installed binary works
which git
git --version
```

### Home-manager verification

```bash
# Check home-manager generations
home-manager generations | head -3

# Verify home-manager profile
ls -la ~/.nix-profile/
```

### Network verification

```bash
# Zerotier connectivity
sudo zerotier-cli listnetworks
ping -c 3 cinnabar.zt

# SSH to another machine (if configured)
ssh cinnabar.zt
```

### Complete checklist

- [ ] `darwin-rebuild --list-generations` shows recent generation
- [ ] Nix-installed tools available in PATH
- [ ] Home-manager configuration active
- [ ] Secrets deployed to `~/.config/sops-nix/secrets/`
- [ ] Zerotier connected and authorized
- [ ] Can reach other machines on the mesh

## What you've learned

You've now deployed a darwin machine from start to finish.
Along the way, you learned:

- **nix-darwin** provides declarative macOS configuration alongside (not replacing) macOS
- **Homebrew integration** handles what Nix can't (system extensions, notarized installers)
- **Zerotier mesh** connects darwin machines to the broader infrastructure
- **Tier 2 secrets** work identically on darwin and NixOS via sops-nix
- **Generations** provide rollback safety for darwin configurations

## Next steps

Now that your darwin machine is deployed:

1. **Customize your configuration** by modifying your user module in `modules/home/users/`

2. **Learn about NixOS deployment** if you manage servers.
   The [NixOS Deployment Tutorial](/tutorials/nixos-deployment) covers terranix provisioning and clan deployment.

3. **Review operational procedures** in the guides:
   - [Host Onboarding Guide](/guides/host-onboarding#darwin-host-onboarding-macos) for adding more darwin machines
   - [Secrets Management Guide](/guides/secrets-management) for secret rotation and sharing

4. **Understand the architecture** more deeply:
   - [Dendritic Architecture](/concepts/dendritic-architecture) for module organization
   - [Multi-User Patterns](/concepts/multi-user-patterns) for user configuration approaches

## Troubleshooting

### darwin-rebuild not found

Ensure your development shell is active:

```bash
cd /path/to/infra
direnv allow
which darwin-rebuild
```

### "No configuration for hostname"

Your machine needs a configuration entry.
Check `modules/machines/darwin/` for your hostname, or create one following the [Host Onboarding Guide](/guides/host-onboarding#darwin-host-onboarding-macos).

### Homebrew cask installation fails

Check if Homebrew itself is working:

```bash
brew doctor
brew update
```

If Homebrew needs installation:

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

### Zerotier won't start

macOS security may be blocking the system extension:

1. Open **System Preferences > Security & Privacy > General**
2. Look for blocked software from "ZeroTier, Inc."
3. Click "Allow" and restart zerotier

```bash
sudo launchctl stop com.zerotier.one
sudo launchctl start com.zerotier.one
```

### Activation script errors

Check the specific error message.
Common issues:
- Missing Homebrew (`brew` not found)
- Network issues during package download
- Permission problems (need `sudo` for some operations)

For comprehensive troubleshooting, see the [Host Onboarding Guide](/guides/host-onboarding#troubleshooting).
