---
title: "Bootstrap to Activation"
description: "Learn how to set up your first nix-managed machine from scratch, understanding each step along the way."
sidebar:
  order: 2
---

This tutorial guides you through setting up a new machine with this infrastructure, teaching you the concepts behind each step so you can confidently work with the system going forward.

## What you will learn

By the end of this tutorial, you will understand:

- How Nix flakes provide reproducible, declarative system configuration
- What the dendritic pattern is and why we organize modules by aspect rather than by host
- How direnv automatically activates your development environment
- What happens during system activation and how to verify success
- How to explore your machine's configuration and make sense of the module structure

## Prerequisites

Before starting, you need:

- **Physical or SSH access** to a macOS or NixOS machine
- **Administrator privileges** (sudo access)
- **Git installed** and configured with your credentials
- **Internet connectivity** for downloading packages

No prior Nix experience is required, but familiarity with command-line basics helps.

## Estimated time

45-60 minutes for your first run through.
Subsequent machines take 15-20 minutes once you understand the concepts.

## Understanding the architecture

Before touching the keyboard, let's understand what we're building toward.

### Why Nix?

Traditional system configuration involves installing packages manually, editing configuration files in `/etc/`, and hoping you remember what you changed when something breaks.
Nix takes a different approach: your entire system configuration lives in version-controlled files, and the system state is derived from those files deterministically.

This means:
- **Reproducibility**: The same configuration produces the same system, every time
- **Rollback**: Every change creates a new generation you can roll back to
- **Declarative**: You describe what you want, not how to get there

### The four-layer architecture

This infrastructure combines four complementary technologies:

1. **Flake-parts** provides the foundation, organizing everything as composable modules
2. **Dendritic pattern** organizes modules by aspect (what they do) rather than by host (where they run)
3. **Clan-core** coordinates multi-machine deployments with inventory-based service assignment
4. **Overlays** provide resilience through multi-channel nixpkgs access and hotfixes

You don't need to understand all of this deeply right now.
The key insight is that your machine configuration is just one piece of a larger, well-organized system.

For deeper understanding, see [Nix Configuration Architecture](/concepts/nix-config-architecture).

### Dendritic organization

Traditional nix configs often organize by host: all of `stibnite`'s configuration in one place, all of `blackphos`'s in another.
This leads to duplication when multiple machines need similar features.

The dendritic pattern instead organizes by aspect:

```
modules/
├── machines/         # Machine-specific configurations
│   ├── darwin/       # macOS hosts
│   └── nixos/        # NixOS hosts
├── home/             # User environment modules
│   ├── users/        # Per-user configurations
│   └── all/          # Shared user features
├── nixpkgs/          # Package customizations
└── clan/             # Multi-machine coordination
```

Each feature (git configuration, shell setup, development tools) lives in its own module.
Machines compose these modules to build their complete configuration.

For the full explanation, see [Dendritic Architecture](/concepts/dendritic-architecture).

## Step 1: Clone the repository

Let's start by getting the configuration onto your machine.

```bash
cd ~/projects  # Or wherever you keep your code
git clone git@github.com:cameronraysmith/infra.git
cd infra
```

Take a moment to explore the structure:

```bash
ls -la
```

You'll see:
- `flake.nix` - The entry point defining all outputs
- `modules/` - The dendritic module hierarchy
- `secrets/` - Encrypted secrets (we'll cover this in the secrets tutorial)
- `justfile` - Task runner with common operations
- `Makefile` - Bootstrap automation

The `flake.nix` file is intentionally minimal because most logic lives in the auto-discovered modules.
This is the dendritic pattern at work.

## Step 2: Bootstrap Nix and direnv

The bootstrap process installs Nix (if needed) and sets up direnv for automatic environment activation.

```bash
make bootstrap
```

This command:
1. Checks if Nix is installed, installs it via the Determinate Systems installer if not
2. Installs direnv for automatic development shell activation
3. Configures your shell to use direnv

**Why the Determinate Systems installer?**
It provides a cleaner installation with better macOS integration than the official installer, particularly for multi-user setups and Apple Silicon Macs.

**Why direnv?**
When you enter a directory with a `.envrc` file, direnv automatically activates the appropriate environment.
You get the right tools, environment variables, and shell configuration without remembering to run anything.

After bootstrap completes, restart your shell or run:

```bash
source ~/.zshrc  # or ~/.bashrc
```

## Step 3: Allow direnv

Now activate the development environment:

```bash
direnv allow
```

The first time takes a few minutes as Nix downloads and builds the development shell.
You'll see output as packages are fetched from the cache or built locally.

Once complete, your prompt may change (depending on your shell configuration), and you'll have access to all the tools defined in the flake's `devShells`.

**Verify the environment:**

```bash
which just
which darwin-rebuild  # On macOS
which nixos-rebuild   # On NixOS
```

These commands should point to paths inside `/nix/store/`, confirming the development shell is active.

## Step 4: Explore your machine configuration

Before activating, let's understand what configuration will be applied.

### Find your machine

Machines are defined in the clan inventory and have corresponding module directories:

```bash
# Darwin machines
ls modules/machines/darwin/

# NixOS machines
ls modules/machines/nixos/
```

The current fleet includes:
- **Darwin**: stibnite, blackphos, rosegold, argentum
- **NixOS**: cinnabar, electrum, galena, scheelite

Find your machine's directory.
If your machine isn't listed, you'll need to create a configuration first; see the [Host Onboarding Guide](/guides/host-onboarding).

### Understand the module structure

Open your machine's main configuration file.
For a darwin machine like `stibnite`:

```bash
cat modules/machines/darwin/stibnite/default.nix
```

You'll see imports of various modules.
These imports follow the dendritic pattern, pulling in features from across the module hierarchy rather than defining everything inline.

Notice how the file is relatively short.
Most configuration comes from:
- Aggregate modules that bundle related features
- User modules that define personal environments
- Shared modules that all machines inherit

### Trace an import

Pick one import and follow it.
For example, if you see an import of an aggregate module:

```bash
cat modules/home/users/crs58/default.nix
```

This shows how a user's environment is composed from smaller, focused modules.
Each module handles one concern (git, shell, development tools), making the system easier to understand and modify.

## Step 5: Validate before activating

Always validate your configuration builds before activating:

**For darwin machines:**

```bash
nix build .#darwinConfigurations.stibnite.system --dry-run
```

Replace `stibnite` with your hostname.
The `--dry-run` flag shows what would be built without actually building.

**For NixOS machines:**

```bash
nix build .#nixosConfigurations.cinnabar.config.system.build.toplevel --dry-run
```

If validation succeeds with no errors, you're ready to activate.

## Step 6: Activate your configuration

Now apply the configuration to your system.

**For darwin machines:**

```bash
darwin-rebuild switch --flake .#stibnite
```

Or use the just task:

```bash
just activate
```

The `just activate` command auto-detects your platform and hostname.

**For NixOS machines managed by clan:**

```bash
clan machines update cinnabar
```

### What happens during activation?

The activation process:
1. **Builds** the complete system configuration from your flake
2. **Creates** a new system generation in `/nix/store`
3. **Switches** symlinks to point to the new generation
4. **Runs** activation scripts (creating users, starting services, etc.)

This is a transactional operation.
If something fails, your previous generation remains intact.

### Verify activation

After activation completes:

```bash
# Check the current generation
darwin-rebuild --list-generations | head -5  # macOS
nixos-rebuild --list-generations | head -5   # NixOS

# Verify a package is available
which git
git --version

# Check home-manager status (if you have user configuration)
home-manager generations | head -3
```

If you configured zerotier, verify network connectivity:

```bash
sudo zerotier-cli listnetworks
```

## What you've learned

You've now completed your first bootstrap-to-activation cycle.
Along the way, you learned:

- **Nix flakes** provide reproducible, declarative system configuration
- **Dendritic organization** groups modules by aspect, reducing duplication
- **direnv** automatically activates your development environment
- **Validation before activation** catches errors before they affect your system
- **Generations** provide rollback safety for every change

## Next steps

Now that your machine is activated, you should:

1. **Set up secrets** if you haven't already.
   The [Secrets Setup Tutorial](/tutorials/secrets-setup) walks you through the two-tier secrets architecture.

2. **Understand your user configuration** by reading through your user module in `modules/home/users/`.

3. **Explore the guides** for operational tasks:
   - [Getting Started Guide](/guides/getting-started) for quick command reference
   - [Host Onboarding Guide](/guides/host-onboarding) for adding new machines

4. **Deepen your understanding** with the concepts documentation:
   - [Dendritic Architecture](/concepts/dendritic-architecture) for module organization
   - [Clan Integration](/concepts/clan-integration) for multi-machine coordination

## Troubleshooting

### direnv not activating

If your prompt doesn't change after `direnv allow`:

```bash
# Ensure direnv hook is in your shell config
grep direnv ~/.zshrc  # or ~/.bashrc

# If missing, add it
echo 'eval "$(direnv hook zsh)"' >> ~/.zshrc
source ~/.zshrc
```

### Build fails with hash mismatch

This usually means a flake input was updated but not locked:

```bash
nix flake update
nix flake check
```

### darwin-rebuild not found

Ensure your development shell is active:

```bash
cd /path/to/infra
direnv allow
which darwin-rebuild
```

### Permission denied during activation

You need administrator privileges:

```bash
sudo darwin-rebuild switch --flake .#hostname
```

For comprehensive troubleshooting, see the [Host Onboarding Guide](/guides/host-onboarding#troubleshooting).
