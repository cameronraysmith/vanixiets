---
title: Getting started
description: Quick start guide for bootstrapping and using this configuration
sidebar:
  order: 2
---

This guide walks through bootstrapping a new machine with this configuration.

:::note
This repository pertains to a particular set of users and machines and is not directly structured as a template, but could relatively easily be treated as such via renaming.
:::

## Prerequisites

Before you begin, ensure you have:
- Physical access or SSH access to the target machine
- macOS (for nix-darwin) or NixOS system
- Internet connection for downloading Nix and packages

## Quick setup

### Step 1: Clone the repository

```bash
git clone https://github.com/cameronraysmith/vanixiets.git
cd vanixiets
```

### Step 2: Bootstrap Nix and essential tools

```bash
make bootstrap && exec $SHELL
```

**What this does:**
- Installs Nix using the [NixOS fork](https://github.com/NixOS/experimental-nix-installer) of the [Determinate Systems nix installer](https://github.com/DeterminateSystems/nix-installer)
- Configures Nix with comprehensive settings for optimal performance:
  - Enables flakes and nix-command experimental features
  - Disables store optimization (auto-optimise-store=false) to prevent corruption on Darwin
  - Enables parallel builds (max-jobs=auto)
  - Allows binary cache substitution for all derivations (always-allow-substitutes)
  - Configures legacy NIX_PATH compatibility (extra-nix-path)
- Installs direnv for automatic environment activation

### Step 3: Allow direnv

```bash
direnv allow
# or if already in the shell:
direnv reload
```

**What this does:**
- Automatically loads the Nix development shell
- Makes `just` and other dev tools available
- Activates the project environment

### Step 4: Verify installation

```bash
make verify
```

**This checks:**
- Nix installation
- Flakes support
- Flake validity

### Step 5: Set up secrets (optional, for existing users)

```bash
make setup-user
```

**What this does:**
- Generates age key at `~/.config/sops/age/keys.txt` for secrets encryption
- Skip this if you're just exploring the configuration

### Step 6: Activate configuration

If you are locally connected to the machine where you'd like to activate your configuration, you should be able to use the justfile `activate` recipe:

:::caution
review the contents of the `justfile` to confirm you understand precisely what this will do or do not use it

:::

```bash
just activate --ask
```

It would be best to first understand the more verbose ways of accomplishing similar tasks described below and then revert to using various relevant variations of the above command as the output is much more informative and easier to understand thanks to use of nix flake apps that call relevant subcommands of the [nh cli](https://github.com/nix-community/nh) and thus utilize the [nix-output-monitor](https://github.com/maralorn/nix-output-monitor) and [dix diff](https://github.com/faukah/dix).

**For NixOS hosts** (local access):
```bash
nixos-rebuild switch --flake .#cinnabar
nixos-rebuild switch --flake .#electrum
```

**For NixOS hosts** (remote or local via clan):
:::note
If you are activating a configuration on a remote machine that has the same system platform and architecture
as your local machine, the default behavior is to build on the local machine and transfer the build outputs
to the remote machine over ssh.
:::
```bash
clan machines update <hostname>

# Examples:
clan machines update cinnabar
clan machines update electrum
```

**For darwin hosts** (macOS):
```bash
darwin-rebuild switch --flake .#<hostname>

# Examples:
darwin-rebuild switch --flake .#stibnite
darwin-rebuild switch --flake .#blackphos
```


## Essential commands

Once you've activated direnv, you have access to the `just` task runner:

```bash
# Show all available commands
just help

# Or just run 'just' to see the command list
just
```

### Common tasks

**System management:**
```bash
just activate          # Activate configuration for current user/host
just update            # Update nix flake inputs
just verify            # Verify system builds without activating
```

**Development:**
```bash
just dev               # Enter development shell manually
just lint              # Lint nix files
just clean             # Remove build output links
```

**Secrets:**
```bash
just check-secrets     # Verify secrets access
just edit-secret FILE  # Edit encrypted secret
just validate-secrets  # Validate all secrets decrypt correctly
```

**Troubleshooting:**
```bash
just bisect-nixpkgs    # Find breaking nixpkgs commits
just verify            # Test if configuration builds
```

See the full command reference by running `just help` after activating the dev shell.

## Understanding the structure

**Architecture note**: This infrastructure uses [deferred module composition](/concepts/deferred-module-composition/) (the aspect-based pattern) built on nixpkgs' module system.
For deeper understanding of why patterns work, see [Module System Primitives](/concepts/module-system-primitives/).

This configuration uses the [deferred module composition pattern](/concepts/deferred-module-composition) where every Nix file is a flake-parts module organized by *aspect* (feature) rather than by *host*:

```
infra/
├── modules/
│   ├── clan/         # Clan integration (machines, inventory, services)
│   ├── darwin/       # nix-darwin modules (all darwin hosts)
│   ├── home/         # Home-manager modules (all users)
│   │   ├── ai/       # AI tooling (claude-code, MCP servers)
│   │   ├── development/ # Dev environment (git, editors)
│   │   ├── shell/    # Shell configuration (zsh, fish)
│   │   └── users/    # User-specific modules
│   ├── machines/     # Machine-specific configurations
│   │   ├── darwin/   # Darwin hosts (stibnite, blackphos, rosegold, argentum)
│   │   └── nixos/    # NixOS hosts (cinnabar, electrum, galena, scheelite)
│   ├── nixos/        # NixOS modules (all nixos hosts)
│   └── nixpkgs/      # Overlay composition (channels, stable fallbacks, overrides)
├── pkgs/             # Custom packages (pkgs-by-name pattern)
├── secrets/          # Encrypted secrets (legacy sops-nix)
└── vars/             # Clan-generated secrets (clan vars)
```

Key concepts:
- **Aspect-based organization**: Features (git, shell, AI tools) defined once, shared across hosts
- **Machine-specific configs**: Only truly unique settings in `modules/machines/`
- **Auto-discovery**: [import-tree](https://github.com/vic/import-tree) automatically imports all modules

See [Repository Structure](/reference/repository-structure) for complete directory mapping.

## Next steps

### Learn the architecture

- [Deferred Module Composition](/concepts/deferred-module-composition) - Core pattern where every file is a flake-parts module
- [Clan Integration](/concepts/clan-integration) - Multi-machine coordination and secrets management
- [System-user Integration](/concepts/system-user-integration) - Admin vs non-admin users

### Set up a new machine

- [Host Onboarding](/guides/host-onboarding) - Add a new Darwin or NixOS host
- [User Onboarding](/guides/home-manager-onboarding) - Add a new user to an existing host

### Operational tasks

- [Secrets Management](/guides/secrets-management) - Managing encrypted secrets with sops-nix
- [Handling broken packages](/guides/handling-broken-packages) - Fixing broken packages from nixpkgs unstable

## Tutorials

For in-depth learning-oriented walkthroughs, see:

- [Bootstrap to Activation](/tutorials/bootstrap-to-activation/) - Step-by-step initial setup and activation
- [Secrets Setup](/tutorials/secrets-setup/) - Secrets management with clan vars and legacy sops-nix
- [Darwin Deployment](/tutorials/darwin-deployment/) - Complete macOS deployment workflow
- [NixOS Deployment](/tutorials/nixos-deployment/) - Cloud server provisioning and deployment

## Troubleshooting

### Nix not found after bootstrap

**Solution:** Restart your shell or source the nix profile:
```bash
exec $SHELL
# or
source /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
```

### Direnv not activating

**Solution:** Ensure direnv is installed and hooked into your shell.
Check `~/.bashrc` or `~/.zshrc` for:
```bash
eval "$(direnv hook bash)"  # or zsh
```

### Build failures

**Solution:** Check if nixpkgs unstable has breaking changes:
```bash
just verify  # Test build without activating
```

If build fails, see [Handling broken packages](/guides/handling-broken-packages) for troubleshooting workflow.

### Secrets not decrypting

**Solution:** Ensure your age key is properly set up:
```bash
make setup-user                    # Generate age key
just check-secrets                 # Verify access
```

See [Secrets Management](/guides/secrets-management) for detailed troubleshooting.

## Getting help

### Documentation

- [Guides](/guides/) - Task-oriented how-tos
- [Concepts](/concepts/) - Understanding-oriented explanations
- [Reference](/reference/repository-structure/) - Information-oriented lookup

### External resources

- [Nix manual](https://nixos.org/manual/nix/stable/) - Official Nix documentation
- [NixOS wiki](https://nixos.wiki/) - Community documentation
- [nix-darwin](https://github.com/LnL7/nix-darwin) - macOS system configuration
- [home-manager](https://github.com/nix-community/home-manager) - User environment management
- [clan documentation](https://clan.lol/) - Multi-machine coordination

### Community

- [GitHub Discussions](https://github.com/cameronraysmith/vanixiets/discussions) - Ask questions
- [GitHub Issues](https://github.com/cameronraysmith/vanixiets/issues) - Report bugs

## What's next?

Now that you're set up, you can:
- Explore the configuration files to understand the setup
- Customize the configuration for your needs
- Add new hosts or users following the onboarding guides
- Set up secrets management for sensitive data
