# nix-config

This is my personal [nix](https://nix.dev/reference/nix-manual.html)-config. If
you'd like to experiment with nix in a containerized environment, consider
trying [nixpod](https://github.com/cameronraysmith/nixpod) before attempting to
use something like this repository or one of the credited examples below.

<details>
<summary>organization</summary>

## Architecture overview

This configuration uses [flake-parts](https://github.com/hercules-ci/flake-parts) with [nixos-unified](https://github.com/srid/nixos-unified) to provide a modular, multi-platform nix configuration supporting:

- **darwin**: macOS systems via nix-darwin
- **nixos**: Linux systems via NixOS
- **home**: Standalone home-manager for non-admin users

The key benefit of nixos-unified is **autowiring**: directory structure automatically maps to flake outputs without manual wiring in flake.nix.

## Directory structure

```
nix-config/
├── configurations/      # System and user configurations (autowired)
│   ├── darwin/          # → darwinConfigurations.*
│   ├── nixos/           # → nixosConfigurations.*
│   └── home/            # → legacyPackages.${system}.homeConfigurations.*
├── modules/             # Reusable nix modules (autowired)
│   ├── flake-parts/     # → flakeModules.* (system-agnostic)
│   ├── darwin/          # → darwinModules.* (macOS-specific)
│   ├── nixos/           # → nixosModules.* (Linux-specific)
│   └── home/            # home-manager modules (imported, not autowired)
├── overlays/            # Package modifications (autowired)
│   ├── default.nix      # → overlays.default (6-layer composition)
│   ├── inputs.nix       # → overlays.inputs (multi-channel nixpkgs)
│   ├── infra/           # Infrastructure files (not autowired)
│   ├── overrides/       # Per-package build modifications
│   ├── packages/        # Custom derivations (6 packages)
│   └── debug-packages/  # Development packages (4 packages)
├── lib/                 # Shared library functions
│   └── default.nix      # → flake.lib (exported for external use)
├── packages/            # Standalone packages (not currently used)
├── scripts/             # Maintenance and utility scripts
│   ├── bisect-nixpkgs.sh    # Find breaking nixpkgs commits
│   ├── verify-system.sh     # Verify system configuration builds
│   └── sops/                # Secrets management helpers
├── secrets/             # Encrypted configuration data (sops-nix)
│   ├── hosts/           # Host-specific secrets
│   ├── users/           # User-specific secrets
│   └── services/        # Service credentials
├── docs/                # Documentation
│   ├── notes/           # Technical notes and guides
│   └── development/     # Development workflows
├── tests/               # Integration tests
└── disabled/            # Temporarily disabled configurations
```

## Directory-to-output mapping

### Configurations (autowired by nixos-unified)

| File | Flake output | Command |
|------|--------------|---------|
| `configurations/darwin/stibnite.nix` | `darwinConfigurations.stibnite` | `darwin-rebuild switch --flake .#stibnite` |
| `configurations/darwin/blackphos.nix` | `darwinConfigurations.blackphos` | `darwin-rebuild switch --flake .#blackphos` |
| `configurations/nixos/orb-nixos.nix` | `nixosConfigurations.orb-nixos` | `nixos-rebuild switch --flake .#orb-nixos` |
| `configurations/nixos/stibnite-nixos.nix` | `nixosConfigurations.stibnite-nixos` | `nixos-rebuild switch --flake .#stibnite-nixos` |
| `configurations/nixos/blackphos-nixos.nix` | `nixosConfigurations.blackphos-nixos` | `nixos-rebuild switch --flake .#blackphos-nixos` |
| `configurations/home/runner@stibnite.nix` | `legacyPackages.${system}.homeConfigurations.runner@stibnite` | `nix run .#activate-home -- runner@stibnite` |
| `configurations/home/runner@blackphos.nix` | `legacyPackages.${system}.homeConfigurations.runner@blackphos` | `nix run .#activate-home -- runner@blackphos` |
| `configurations/home/raquel@blackphos.nix` | `legacyPackages.${system}.homeConfigurations.raquel@blackphos` | `nix run .#activate-home -- raquel@blackphos` |

**Key insight**: File names become configuration names. No manual registration required.

### Modules (autowired by nixos-unified)

| Directory | Flake output | Usage |
|-----------|--------------|-------|
| `modules/flake-parts/*.nix` | `flakeModules.*` | Imported automatically in flake.nix |
| `modules/darwin/*.nix` | `darwinModules.*` | Available for darwin configurations |
| `modules/nixos/*.nix` | `nixosModules.*` | Available for nixos configurations |
| `modules/home/` | (imported directly) | Not autowired; imported via `modules/home/default.nix` |

**Example**: `modules/flake-parts/devshell.nix` defines the development shell, automatically available as `flakeModules.devshell`.

### Overlays (autowired by nixos-unified)

| File | Flake output | Purpose |
|------|--------------|---------|
| `overlays/default.nix` | `overlays.default` | 6-layer composition (inputs → hotfixes → packages → debugPackages → overrides → flakeInputs) |
| `overlays/inputs.nix` | `overlays.inputs` | Multi-channel nixpkgs access (stable, unstable, patched) |
| `overlays/overrides/default.nix` | `overlays.overrides` | Auto-imported per-package build modifications |

**Custom packages** (defined in overlays, exposed via packages output):
- From `overlays/packages/`: cc-statusline-rs, starship-jj, markdown-tree-parser, atuin-format, bitwarden-cli, claude-code-bin
- From `overlays/debug-packages/`: nvim-treesitter-main, activate, update, default

**Note**: The `overlays/infra/` subdirectory is intentionally excluded from autowiring to avoid conflicts. It contains:
- `hotfixes.nix`: Platform-specific stable fallbacks
- `patches.nix`: Upstream patch infrastructure

### Library functions

| File | Flake output | Exported functions |
|------|--------------|-------------------|
| `lib/default.nix` | `flake.lib` | `mdFormat`, `systemInput`, `systemOs`, `importOverlays` |

**Usage in other files**:
```nix
# flake.lib is available throughout the configuration
inherit (flake.lib) systemInput systemOs;
```

## Nixos-unified autowiring explained

### What is autowiring?

Instead of manually registering each configuration, module, and overlay in `flake.nix`, nixos-unified scans directories and automatically creates flake outputs based on file paths.

### Without autowiring (manual approach):

```nix
# flake.nix (traditional approach)
{
  outputs = { nixpkgs, nix-darwin, home-manager, ... }: {
    darwinConfigurations.stibnite = nix-darwin.lib.darwinSystem {
      modules = [ ./configurations/darwin/stibnite.nix ];
    };
    darwinConfigurations.blackphos = nix-darwin.lib.darwinSystem {
      modules = [ ./configurations/darwin/blackphos.nix ];
    };
    nixosConfigurations.orb-nixos = nixpkgs.lib.nixosSystem {
      modules = [ ./configurations/nixos/orb-nixos.nix ];
    };
    # ... repeat for every configuration, module, and overlay
  };
}
```

**Problems**: Verbose, error-prone, requires manual maintenance for each new configuration.

### With autowiring (nixos-unified approach):

```nix
# flake.nix (actual implementation)
{
  outputs = inputs@{ flake-parts, ... }:
    inputs.flake-parts.lib.mkFlake { inherit inputs; } {
      systems = [ "x86_64-linux" "aarch64-linux" "aarch64-darwin" ];
      imports = with builtins;
        map (fn: ./modules/flake-parts/${fn}) (attrNames (readDir ./modules/flake-parts));
      # ... minimal configuration
    };
}
```

**Benefits**:
- **Add a new host**: Create `configurations/darwin/newhostname.nix` → automatically available as `darwinConfigurations.newhostname`
- **Add a new module**: Create `modules/nixos/mymodule.nix` → automatically available as `nixosModules.mymodule`
- **Add an overlay**: Create `overlays/myoverlay.nix` → automatically available as `overlays.myoverlay`

### How autowiring works

1. **Directory scan**: nixos-unified scans specific directories (`configurations/`, `modules/`, `overlays/`)
2. **Path parsing**: File paths become flake output names
   - `configurations/darwin/stibnite.nix` → `darwinConfigurations.stibnite`
   - `modules/nixos/common.nix` → `nixosModules.common`
   - `overlays/default.nix` → `overlays.default`
3. **Automatic import**: Files are imported and wired into appropriate flake outputs
4. **Module composition**: System configurations automatically import relevant modules

### Value proposition

**Developer ergonomics**:
- Focus on configuration content, not plumbing
- Less boilerplate → more maintainable
- Reduced cognitive load: file organization IS the flake structure

**Scalability**:
- Adding new machines/users is straightforward
- No flake.nix modifications needed for new configurations
- Consistent patterns across configurations

**Error prevention**:
- Typos in manual wiring are eliminated
- Missing imports are caught by directory structure
- Consistent naming conventions enforced by file paths

## Current flake outputs

```zsh
❯ om show .

📦 Packages (nix build .#<name>)
╭──────────────────────┬──────────────────────────────────────────────────────────────────────────────────────╮
│ name                 │ description                                                                          │
├──────────────────────┼──────────────────────────────────────────────────────────────────────────────────────┤
│ nvim-treesitter-main │ N/A                                                                                  │
│ starship-jj          │ starship plugin for jj                                                               │
│ bitwarden-cli        │ Secure and free password manager for all of your devices                            │
│ atuin-format         │ Format atuin history with Catppuccin Mocha colored table output                     │
│ claude-code-bin      │ Agentic coding tool that lives in your terminal                                     │
│ activate             │ Activate NixOS/nix-darwin/home-manager configurations                               │
│ cc-statusline-rs     │ Claude Code statusline implementation in Rust                                       │
│ default              │ Activate NixOS/nix-darwin/home-manager configurations                               │
│ markdown-tree-parser │ JavaScript library and CLI for parsing markdown as tree structures                  │
│ update               │ Update the primary flake inputs                                                      │
╰──────────────────────┴──────────────────────────────────────────────────────────────────────────────────────╯

🐚 Devshells (nix develop .#<name>)
╭─────────┬────────────────────────────────╮
│ name    │ description                    │
├─────────┼────────────────────────────────┤
│ default │ Dev environment for nix-config │
╰─────────┴────────────────────────────────╯

🔍 Checks (nix flake check)
╭────────────┬─────────────╮
│ name       │ description │
├────────────┼─────────────┤
│ pre-commit │ N/A         │
╰────────────┴─────────────╯

🐧 NixOS Configurations (nixos-rebuild switch --flake .#<name>)
╭─────────────────┬─────────────╮
│ name            │ description │
├─────────────────┼─────────────┤
│ blackphos-nixos │ N/A         │
│ orb-nixos       │ N/A         │
│ stibnite-nixos  │ N/A         │
╰─────────────────┴─────────────╯

🍏 Darwin Configurations (darwin-rebuild switch --flake .#<name>)
╭───────────┬─────────────╮
│ name      │ description │
├───────────┼─────────────┤
│ stibnite  │ N/A         │
│ blackphos │ N/A         │
╰───────────┴─────────────╯

🔧 NixOS Modules
╭─────────┬─────────────╮
│ name    │ description │
├─────────┼─────────────┤
│ default │ N/A         │
│ common  │ N/A         │
╰─────────┴─────────────╯

🎨 Overlays
╭───────────┬─────────────╮
│ name      │ description │
├───────────┼─────────────┤
│ inputs    │ N/A         │
│ overrides │ N/A         │
│ default   │ N/A         │
╰───────────┴─────────────╯
```

**Mapping outputs to directories**:
- **10 packages**: From `overlays/packages/` (6) + `overlays/debug-packages/` (4)
- **3 NixOS configurations**: From `configurations/nixos/*.nix`
- **2 Darwin configurations**: From `configurations/darwin/*.nix`
- **3 Home configurations**: From `configurations/home/*.nix` (not shown in om output, but available)
- **2 NixOS modules**: From `modules/nixos/*.nix`
- **3 overlays**: From `overlays/*.nix` (default, inputs, overrides)
- **1 devshell**: From `modules/flake-parts/devshell.nix`

## Practical examples

### Example 1: Adding a new darwin host

**Task**: Add configuration for new macOS machine "newhostname"

**Steps**:
1. Create `configurations/darwin/newhostname.nix`
2. Run `darwin-rebuild switch --flake .#newhostname`

**What happens**:
- nixos-unified detects new file
- Automatically creates `darwinConfigurations.newhostname` output
- Configuration becomes immediately available

**No flake.nix modifications needed**.

### Example 2: Adding a custom package

**Task**: Package a new tool "mytool"

**Steps**:
1. Create `overlays/packages/mytool.nix` with package definition
2. Run `nix build .#mytool`

**What happens**:
- `overlays/packages/` directory is scanned by `packagesFromDirectoryRecursive`
- Package automatically merged into overlay composition (layer 3: packages)
- Available as `packages.${system}.mytool` output

**Package immediately available in all configurations** via overlay.

### Example 3: Creating a reusable nixos module

**Task**: Create module for common server configuration

**Steps**:
1. Create `modules/nixos/server-common.nix`
2. Import in any nixos configuration: `imports = [ inputs.self.nixosModules.server-common ];`

**What happens**:
- nixos-unified scans `modules/nixos/`
- Automatically exports as `nixosModules.server-common`
- Available for import in any nixos configuration

**Module reusable across all NixOS systems**.

## Why this matters

**For newcomers**:
- Directory structure is self-documenting
- File organization directly maps to functionality
- Less nix language knowledge required to add configurations

**For experts**:
- Predictable patterns enable quick modifications
- Directory-based organization scales to large configurations
- Focus energy on configuration content, not structure

**For maintenance**:
- Adding new machines/users requires minimal changes
- Configuration discovery is straightforward (just list directories)
- Reduced surface area for errors

The transparency of nixos-unified's autowiring means **the directory tree IS the API**. Understanding the file structure means understanding the entire configuration architecture.

</details>

## nixpkgs hotfixes infrastructure

<details>
<summary>multi-channel nixpkgs resilience</summary>

This repository uses a multi-channel nixpkgs resilience system to handle unstable breakage gracefully.

### Features

- **Multi-channel access**: Stable, unstable, and patched nixpkgs variants available
- **Platform-specific hotfixes**: Selective stable fallbacks without full rollbacks
- **Upstream patch application**: Apply fixes before they reach your channel
- **Organized overrides**: Per-package build modifications in dedicated files
- **Composable architecture**: Six-layer overlay composition for flexibility

### Quick example

When nixpkgs unstable breaks a package:

```bash
# Option 1: Use stable version (fastest)
# Edit overlays/infra/hotfixes.nix to inherit from final.stable

# Option 2: Apply upstream patch
# Add to overlays/infra/patches.nix

# Option 3: Modify build (e.g., disable tests)
# Create overlays/overrides/packageName.nix
```

### Documentation

- Architecture: [./docs/notes/nixpkgs-hotfixes.md](./docs/notes/nixpkgs-hotfixes.md)
- Incident response: [./docs/notes/nixpkgs-incident-response.md](./docs/notes/nixpkgs-incident-response.md)
- Override guidelines: [./overlays/overrides/README.md](./overlays/overrides/README.md)

See incident response documentation for detailed workflows.

</details>

## usage

<details>
<summary>bootstrapping a new machine</summary>

Start on a clean macOS or NixOS system:

```bash
# bootstrap nix and essential tools
make bootstrap && exec $SHELL

# verify installation
make verify

# setup secrets (generate age keys for sops-nix)
make setup-user

# activate configuration
nix run . hostname       # admin user (darwin/nixos with integrated home-manager)
nix run . user@hostname  # non-admin user (standalone home-manager, no sudo required)
```

**What this does:**
- `make bootstrap`: Installs nix and direnv using Determinate Systems installer
- `make verify`: Checks nix installation, flakes support, and flake validity
- `make setup-user`: Generates age key at `~/.config/sops/age/keys.txt` for secrets
- Activation: Applies system and/or home-manager configuration

</details>

<details>
<summary>multi-user architecture</summary>

This config supports two user patterns:

**1. admin users** (darwin/nixos): Integrated home-manager configuration
- Define user in `config.nix` and `configurations/{darwin,nixos}/${hostname}.nix`
- Activate with `nix run . hostname` (requires sudo for system changes)
- Full system and home-manager configuration
- One admin per host

**2. non-admin users**: Standalone home-manager configuration
- Define user in `config.nix` and `configurations/home/${user}@${host}.nix`
- Activate with `nix run . user@hostname` (no sudo required)
- Home environment only, independent of system config
- Multiple users per host supported

**Directory structure:**
```
configurations/
├── darwin/          # darwin system configs (admin users)
│   ├── stibnite.nix
│   └── blackphos.nix
├── nixos/           # nixos system configs (admin users)
│   └── orb-nixos.nix
└── home/            # standalone home-manager (non-admin users)
    ├── runner@stibnite.nix
    └── raquel@blackphos.nix
```

</details>

<details>
<summary>adding a new host</summary>

**Step 1: Get host SSH key and convert to age**

On the new host:
```bash
# if host doesn't have ssh key, generate one
sudo ssh-keygen -t ed25519 -f /etc/ssh/ssh_host_ed25519_key -N ""

# convert to age public key
sudo cat /etc/ssh/ssh_host_ed25519_key.pub | ssh-to-age
# Output: age18rgyca7ptr6djqn5h7rhgu4yuv9258v5wflg7tefgvxr06nz7cgsw7qgmy
```

**Step 2: Add host key to `.sops.yaml`**

```yaml
keys:
  # existing keys...
  - &newhostname age18rgyca7ptr6djqn5h7rhgu4yuv9258v5wflg7tefgvxr06nz7cgsw7qgmy

creation_rules:
  - path_regex: hosts/newhostname/.*\.yaml$
    key_groups:
      - age:
        - *admin
        - *crs58  # or appropriate admin user
        - *newhostname
```

**Step 3: Create host configuration**

Darwin: `configurations/darwin/${hostname}.nix`
NixOS: `configurations/nixos/${hostname}.nix`

See [docs/new-user-host.md](docs/new-user-host.md) for complete examples.

**Step 4: Reencrypt secrets and activate**

```bash
# reencrypt secrets for new host
sops updatekeys secrets/shared.yaml

# activate configuration
nix run . hostname
```

</details>

<details>
<summary>adding a new user</summary>

**Step 1: User generates age key**

On the user's machine:
```bash
make bootstrap && exec $SHELL  # if nix not installed
make setup-user                 # generates ~/.config/sops/age/keys.txt

# display public key to send to admin
grep "public key:" ~/.config/sops/age/keys.txt
```

**Important:** Use `age-keygen` for user keys (not `ssh-to-age` from SSH keys).
SSH keys (in Bitwarden) are for authentication; age keys are for secrets encryption.

**Step 2: Admin adds user to config**

1. Add user to `config.nix`:
```nix
newuser = {
  username = "newuser";
  fullname = "New User";
  email = "newuser@example.com";
  sshKey = "ssh-ed25519 AAAAC3Nza...";
  isAdmin = false;
};
```

2. Create `configurations/home/newuser@${host}.nix`

3. Update `.sops.yaml` with user's age public key

4. Reencrypt secrets:
```bash
sops updatekeys secrets/shared.yaml
# repeat for any secrets the user needs access to
```

**Step 3: User activates**

```bash
nix run . newuser@hostname  # no sudo required
```

</details>

<details>
<summary>secrets management</summary>

All secrets use sops-nix with age encryption.

**Key generation:**
- **Users**: `age-keygen -o ~/.config/sops/age/keys.txt` (via `make setup-user`)
- **Hosts**: `ssh-to-age < /etc/ssh/ssh_host_ed25519_key.pub`

**Daily operations:**
```bash
# verify secrets access
make check-secrets

# create content-addressed encrypted file
just hash-encrypt /path/to/file.txt

# edit existing secret
just edit-secret secrets/encrypted-file.yaml

# validate all secrets decrypt correctly
just validate-secrets

# reencrypt secrets after adding new keys to .sops.yaml
sops updatekeys secrets/shared.yaml
```

**See also:**
- [docs/sops-quick-reference.md](docs/sops-quick-reference.md) - Commands and troubleshooting
- [docs/sops-team-onboarding.md](docs/sops-team-onboarding.md) - Team collaboration workflow
- [docs/new-user-host.md](docs/new-user-host.md) - Comprehensive onboarding guide

</details>

<details>
<summary>example: multi-machine multi-user setup</summary>

**machine 1: stibnite (darwin, admin: crs58)**

```bash
cd /path/to/nix-config
make bootstrap && exec $SHELL
make setup-user  # generate age key
# send public age key to repo admin

# admin creates:
# - config.nix entry for crs58
# - configurations/darwin/stibnite.nix
# - updates .sops.yaml with crs58's age key and host key

nix run . stibnite  # activate darwin + home-manager
```

**add non-admin user (runner) on stibnite**

```bash
# runner generates their key
make bootstrap && exec $SHELL
make setup-user
# send public age key to admin

# admin creates:
# - config.nix entry for runner
# - configurations/home/runner@stibnite.nix
# - updates .sops.yaml with runner's age key
# - runs: sops updatekeys secrets/*

# runner activates (no sudo)
nix run . runner@stibnite
```

**machine 2: blackphos (darwin, admin: cameron)**

```bash
# similar bootstrap process
# admin creates configurations/darwin/blackphos.nix
nix run . blackphos

# add runner on blackphos (same user, different machine config)
# create configurations/home/runner@blackphos.nix
nix run . runner@blackphos

# add raquel (unique to blackphos)
# create configurations/home/raquel@blackphos.nix
nix run . raquel@blackphos
```

This demonstrates:
- Multiple admin users across machines (crs58, cameron)
- Same user on multiple machines (runner@stibnite, runner@blackphos)
- Machine-specific users (raquel@blackphos)
- Shared configuration via `modules/home/default.nix`
- Per-user, per-machine customization

</details>

<details>
<summary>workflow to address breaking updates</summary>

After initial setup, this is the workflow for managing system updates and addressing breakage:

### Basic workflow (when updates work)

```bash
# 1. Update flake inputs
nix flake update nixpkgs
# or: just update

# 2. Verify everything builds (catches issues before activation)
just verify

# 3. If verification passes, activate
just activate
```

### Workflow to address breaking updates

```bash
# 1. Update nixpkgs
nix flake update nixpkgs

# 2. Test if it breaks
just verify

# --- If verify PASSES ✓ ---
just activate

# --- If verify FAILS ✗ ---

# 3. Find which commit broke it
just bisect-nixpkgs

# 4. After bisect identifies breaking commit, apply fix
# Option A: Use incident response prompt with Claude Code
#   Copy error from step 2, use: @modules/home/all/tools/claude-code/commands/nixpkgs/incident-response.md
# Option B: Manual troubleshooting
#   See: docs/notes/nixpkgs-incident-response.md

# 5. After applying fix, verify again
just verify

# 6. When verify passes, activate
just activate

# 7. Document the fix
git commit -am "fix(overlays): add hotfix for [package] after nixpkgs [commit]"
```

### What each command does

**`just verify`**:
- Runs `nix flake check` to validate flake structure and configurations
- Builds your full system configuration without activating it
- Exits with clear error messages if anything fails
- Safe: never modifies your running system

**`just bisect-nixpkgs`**:
- Automatically finds the exact nixpkgs commit that broke your build
- Uses git bisect in ~/projects/nix-workspace/nixpkgs
- Tests each commit with `just verify`
- Shows GitHub link to breaking commit
- Takes ~15-50 minutes depending on commit range
- See: [docs/notes/workflow/nixpkgs-bisect-guide.md](./docs/notes/workflow/nixpkgs-bisect-guide.md)

**Incident response**:
- Systematic troubleshooting using hotfixes infrastructure
- Three strategies: stable fallback, upstream patch, or build override
- Documented in: [docs/notes/nixpkgs-incident-response.md](./docs/notes/nixpkgs-incident-response.md)
- AI-assisted via: `@modules/home/all/tools/claude-code/commands/nixpkgs/incident-response.md`

### Benefits of this workflow

- Catch build failures before breaking your current system
- Know exactly which commit caused the problem
- Systematic approach to applying fixes
- Test changes in isolation before activation
- Easy rollback if needed (just don't activate)

See the "nixpkgs hotfixes infrastructure" section above for details on the multi-channel resilience system.

</details>

## developing

Run `direnv allow` or `nix develop` and then `just` for a table of commands.

<details>
<summary>commands</summary>

```zsh
❯ just

Run 'just -n <command>' to print what would be executed...

Available recipes:
    default                                        # Run 'just <command>' to execute a command.
    help                                           # Display help

    [nix]
    activate target=""                             # Activate the appropriate configuration for current user and host
    io                                             # Print nix flake inputs and outputs
    lint                                           # Lint nix files
    dev                                            # Manually enter dev shell
    clean                                          # Remove build output link (no garbage collection)
    build profile                                  # Build nix flake
    check                                          # Check nix flake
    switch                                         # Run nix flake to execute `nix run .#activate` for the current host.
    switch-home                                    # Run nix flake to execute `nix run .#activate-home` for the current user.
    switch-wrapper                                 # Run nix flake with explicit use of the sudo in `/run/wrappers`
    bootstrap-shell                                # Shell with bootstrap dependencies
    update                                         # Update nix flake
    update-primary-inputs                          # Update primary nix flake inputs (see flake.nix)
    update-package package="claude-code-bin"       # Update a package using its updateScript

    [nix-home-manager]
    home-manager-bootstrap-build profile="aarch64-linux" # Bootstrap build home-manager with flake
    home-manager-bootstrap-switch profile="aarch64-linux" # Bootstrap switch home-manager with flake
    home-manager-build profile="aarch64-linux"     # Build home-manager with flake
    home-manager-switch profile="aarch64-linux"    # Switch home-manager with flake

    [nix-darwin]
    darwin-bootstrap profile="aarch64"             # Bootstrap nix-darwin with flake
    darwin-build profile="aarch64"                 # Build darwin from flake
    darwin-switch profile="aarch64"                # Switch darwin from flake
    darwin-test profile="aarch64"                  # Test darwin from flake

    [nixos]
    nixos-bootstrap destination username publickey # Bootstrap nixos
    nixos-vm-sync user destination                 # Copy flake to VM
    nixos-build profile="aarch64"                  # Build nixos from flake
    nixos-test profile="aarch64"                   # Test nixos from flake
    nixos-switch profile="aarch64"                 # Switch nixos from flake

    [secrets]
    show                                           # Show existing secrets using sops
    create-secret name                             # Create a secret with the given name
    populate-single-secret name path               # Populate a single secret with the contents of a dotenv-formatted file
    populate-separate-secrets path                 # Populate each line of a dotenv-formatted file as a separate secret
    create-and-populate-single-secret name path    # Complete process: Create a secret and populate it with the entire contents of a dotenv file
    create-and-populate-separate-secrets path      # Complete process: Create and populate separate secrets for each line in the dotenv file
    get-secret name                                # Retrieve the contents of a given secret
    seed-dotenv                                    # Create empty dotenv from template
    export                                         # Export unique secrets to dotenv format using sops
    check-secrets                                  # Check secrets are available in sops environment.
    get-kubeconfig                                 # Save KUBECONFIG to file (using sops - requires KUBECONFIG secret to be added)
    hash-encrypt source_file user="crs58"          # Hash-encrypt a file: copy to secrets directory with content-based name and encrypt with sops
    verify-hash original_file secret_file          # Verify hash integrity: decrypt secret file and compare hash with original file
    edit-secret file                               # Edit a sops encrypted file
    new-secret file                                # Create a new sops encrypted file
    get-shared-secret key                          # Show specific secret value from shared secrets
    run-with-secrets +command                      # Run command with all shared secrets as environment variables
    validate-secrets                               # Validate all sops encrypted files can be decrypted

    [CI/CD]
    test-ci-blocking workflow="ci.yaml"            # Trigger CI workflow and wait for result (blocking)
    ci-status workflow="ci.yaml"                   # View latest CI run status and details
    ci-logs workflow="ci.yaml"                     # View latest CI run logs
    ci-logs-failed workflow="ci.yaml"              # View only failed logs from latest CI run
    ci-show-outputs system=""                      # List categorized flake outputs using nix eval
    ci-build-local category="" system=""           # Build all flake outputs locally with nom (inefficient manual version of om ci for debugging builds)
    ci-validate workflow="ci.yaml" run_id=""       # Validate latest CI run comprehensively
    ci-debug-job workflow="ci.yaml" job_name="nix (aarch64-darwin)" # Debug specific failed job from latest CI run
    ghsecrets repo="cameronraysmith/nix-config"    # Update github secrets for repo from environment variables
    list-workflows                                 # List available workflows and associated jobs.
    test-flake-workflow                            # Execute ci.yaml workflow locally via act.
    ratchet-pin                                    # Pin all workflow versions to hash values (requires Docker)
    ratchet-unpin                                  # Unpin hashed workflow versions to semantic values (requires Docker)
    ratchet-update                                 # Update GitHub Actions workflows to the latest version (requires Docker)
    test-cachix                                    # Test cachix push/pull with a simple derivation

...by running 'just <command>'.
This message is printed by 'just help' and just 'just'.
```

</details>

## credits

### flake-parts

- [hercules-ci/flake-parts](https://github.com/hercules-ci/flake-parts)
- [srid/nixos-unified](https://github.com/srid/nixos-unified)
- [srid/nixos-config](https://github.com/srid/nixos-config)
- [mirkolenz/nixos](https://github.com/mirkolenz/nixos)
- [ehllie/dotfiles](https://github.com/ehllie/dotfiles)

### other

- [NickCao/flakes](https://github.com/NickCao/flakes)
- [EmergentMind/nix-config](https://github.com/EmergentMind/nix-config)
- [wegank/nixos-config](https://github.com/wegank/nixos-config)
- [MatthiasBenaets/nixos-config](https://github.com/MatthiasBenaets/nixos-config)
- [Misterio77/nix-config](https://github.com/Misterio77/nix-config)
