---
title: User Onboarding
sidebar:
  order: 4
---

This guide covers onboarding users to machines where nix-darwin or NixOS is already configured by an admin.

## When to use this guide

Use this procedure when:
- An admin (crs58/cameron) has already deployed nix-darwin or clan on the host
- You need to set up a non-admin user's environment
- The host already has the nix daemon and secrets infrastructure configured

This guide assumes:
- Host onboarding is complete (see [Host Onboarding](/guides/host-onboarding/))
- The nix daemon is running and `/nix/store` is available
- User configuration exists in the repository

For initial setup, see [Bootstrap to Activation Tutorial](/tutorials/bootstrap-to-activation/) or ensure host onboarding is complete via [Host Onboarding](/guides/host-onboarding/).

## Architecture overview

Users in this infrastructure are configured in one of two ways:

**Integrated users** (most common):
- Configured within darwin/NixOS machine configs
- Home-manager activates automatically with system deployment
- Examples: crs58 on stibnite, raquel on blackphos

**Standalone users** (rare):
- Use home-manager independently from system config
- Useful for non-admin users on shared machines
- Manage their own home-manager generations

### User module locations

User configurations follow the [dendritic pattern](/concepts/dendritic-architecture):

```
modules/
├── home/
│   └── users/
│       ├── crs58/           # crs58's portable home-manager module
│       ├── raquel/          # raquel's portable home-manager module
│       ├── cameron/         # cameron alias module
│       ├── janettesmith/    # janettesmith's module
│       └── christophersmith/ # christophersmith's module
└── machines/
    └── darwin/
        ├── stibnite.nix     # imports users/crs58
        └── blackphos.nix    # imports users/crs58, users/raquel
```

User modules are **portable** - they can be imported by any machine configuration.
Machine configs select which user modules to include.

## Integrated user setup

For users configured within machine configs (the normal case).

### Step 1: Create user module

Create a user module in `modules/home/users/<username>/`:

```nix
# modules/home/users/raquel/default.nix
{ config, ... }:
{
  flake.modules.homeManager."users/raquel" = { pkgs, lib, ... }: {
    # User identity
    home.username = lib.mkDefault "raquel";
    home.homeDirectory = lib.mkDefault "/Users/raquel";

    # Import aggregate modules for features
    imports = with config.flake.modules.homeManager; [
      aggregate-core
      aggregate-shell
      # aggregate-development  # Optional - enable if needed
    ];

    # User-specific overrides
    programs.git = {
      userName = lib.mkForce "Raquel";
      userEmail = lib.mkForce "raquel@example.com";
    };
  };
}
```

Key points:
- Module exports to `flake.modules.homeManager."users/raquel"`
- Uses `lib.mkDefault` for values that machines can override
- Imports aggregates rather than individual modules
- User-specific settings use `lib.mkForce` to override defaults

### Step 2: Import user in machine config

Add the user to the machine configuration:

```nix
# modules/machines/darwin/blackphos.nix
{ config, ... }:
{
  flake.darwinConfigurations.blackphos = {
    # ... system config ...

    home-manager.users.raquel = {
      imports = [
        config.flake.modules.homeManager."users/raquel"
      ];
    };
  };
}
```

### Step 3: Create user secrets (Tier 2)

User secrets are managed via sops-nix.

Create the secrets file:

```bash
# Create encrypted secrets file
sops secrets/users/raquel.sops.yaml
```

Example structure:

```yaml
# secrets/users/raquel.sops.yaml
github-token: ghp_xxxx
ssh-signing-key: |
  -----BEGIN OPENSSH PRIVATE KEY-----
  ...
  -----END OPENSSH PRIVATE KEY-----
```

Add the user's age public key to `.sops.yaml`:

```yaml
keys:
  - &raquel-blackphos age1xxx...

creation_rules:
  - path_regex: secrets/users/raquel\.sops\.yaml$
    key_groups:
      - age:
        - *raquel-blackphos
        - *admin  # Allow admin to manage
```

### Step 4: Reference secrets in user module

Use sops in the user module:

```nix
# modules/home/users/raquel/default.nix
{ config, inputs, ... }:
{
  flake.modules.homeManager."users/raquel" = { pkgs, lib, ... }: {
    sops = {
      age.keyFile = "${config.home.homeDirectory}/.config/sops/age/keys.txt";
      defaultSopsFile = "${inputs.self}/secrets/users/raquel.sops.yaml";
      secrets = {
        "github-token" = { };
        "ssh-signing-key" = {
          path = "${config.home.homeDirectory}/.ssh/id_ed25519_signing";
          mode = "0600";
        };
      };
    };
  };
}
```

### Step 5: Generate age key on target machine

On the machine where this user will be active:

```bash
# As the user (raquel)
mkdir -p ~/.config/sops/age
age-keygen -o ~/.config/sops/age/keys.txt

# Display public key - add this to .sops.yaml
age-keygen -y ~/.config/sops/age/keys.txt
```

### Step 6: Deploy

Deploy the machine configuration:

**Darwin:**
```bash
darwin-rebuild switch --flake .#blackphos
```

**NixOS:**
```bash
clan machines update <hostname>
```

Home-manager activates automatically as part of system activation.

---

## Standalone user setup

For users who manage home-manager independently from system config.
This is rare - most users should use integrated setup above.

### When to use standalone

- User doesn't have admin access to modify machine config
- Testing home-manager configurations in isolation
- Shared machines where users manage their own environments

### Step 1: Verify user exists in system

The user account must exist on the system:

```bash
id raquel
```

### Step 2: Create standalone home configuration

Create a home configuration:

```nix
# modules/machines/home/raquel-standalone.nix
{ config, ... }:
{
  flake.homeConfigurations."raquel" = config.lib.mkHomeConfiguration {
    pkgs = config.flake.pkgs.aarch64-darwin;
    modules = [
      config.flake.modules.homeManager."users/raquel"
      {
        home.username = "raquel";
        home.homeDirectory = "/Users/raquel";
        home.stateVersion = "24.05";
      }
    ];
  };
}
```

### Step 3: Activate standalone home-manager

Build and activate:

```bash
# Build the configuration
nix build .#homeConfigurations.raquel.activationPackage

# Activate
./result/activate
```

Or use the home-manager CLI:

```bash
nix run home-manager/master -- switch --flake .#raquel
```

### Step 4: Ongoing updates

For subsequent updates:

```bash
# Rebuild and activate
home-manager switch --flake .#raquel
```

---

## Clan inventory user instances (NixOS)

For NixOS machines managed via clan, user configuration uses the inventory pattern.
This complements the home-manager user modules by handling system-level user creation (username, groups, password) while home-manager handles environment configuration.

### When to use this pattern

Use clan inventory user instances when:
- Deploying users to NixOS machines via clan
- You need declarative system user creation with encrypted password management
- Managing users across multiple machines with shared credentials
- Integrating with clan's vars-based secrets infrastructure (Tier 1)

This pattern is NixOS-specific.
For darwin machines, continue using the integrated user setup described above.

### The clan.inventory.instances.user-* pattern

Clan inventory instances combine system user creation with home-manager integration:

```nix
# modules/clan/inventory/services/users/myuser.nix
{ inputs, ... }:
{
  clan.inventory.instances.user-myuser = {
    module = {
      name = "users";
      input = "clan-core";
    };

    # Target specific machines
    roles.default.machines."myhost" = { };

    roles.default.settings = {
      user = "myuser";
      groups = [ "wheel" "networkmanager" ];
      share = true;   # Same password across machines
      prompt = false; # Auto-generate via xkcdpass
    };

    roles.default.extraModules = [
      inputs.home-manager.nixosModules.home-manager
      ({ pkgs, ... }: {
        # System user configuration
        users.users.myuser.shell = pkgs.zsh;
        programs.zsh.enable = true;

        # Home-manager integration
        home-manager.users.myuser = {
          imports = [
            inputs.self.modules.homeManager."users/myuser"
          ];
          home.username = "myuser";
        };
      })
    ];
  };
}
```

### Settings options

The `roles.default.settings` block controls system user creation:

**`user`**: Username string (required)
- Creates system user with this name
- Must match username in home-manager configuration

**`groups`**: List of system groups (required)
- Common groups: `["wheel" "networkmanager"]`
- `wheel`: sudo access (admin users)
- `networkmanager`: network configuration

**`share = true`**: Share password across machines (optional)
- When `true`, all machines with this user instance use the same encrypted password
- Password stored in clan vars (Tier 1 secrets)
- When `false`, each machine has unique password

**`prompt = false`**: Password generation method (optional)
- When `false`, auto-generate password using xkcdpass (recommended)
- When `true`, prompt interactively during `clan vars generate`
- Auto-generation is preferred for reproducible deployments

### Machine targeting options

Target machines using either direct machine names or tags:

**Machine-specific targeting**:
```nix
roles.default.machines."hostname" = { };
```

**Tag-based targeting**:
```nix
roles.default.tags."tagname" = { };
```

Tags are defined in machine configurations and allow bulk targeting (e.g., all NixOS servers, all laptops).

### Integration with home-manager

The `extraModules` block bridges system user creation with home-manager:

```nix
roles.default.extraModules = [
  inputs.home-manager.nixosModules.home-manager
  ({ pkgs, ... }: {
    # System-level user settings
    users.users.myuser.shell = pkgs.zsh;
    programs.zsh.enable = true;

    # Home-manager configuration
    home-manager = {
      useGlobalPkgs = true;
      useUserPackages = true;
      backupFileExtension = "before-home-manager";

      extraSpecialArgs = {
        flake = inputs.self // { inherit inputs; };
      };

      users.myuser = {
        imports = [
          inputs.self.modules.homeManager."users/myuser"
          # Import aggregates or other home modules
        ];
        home.username = "myuser";
      };
    };
  })
];
```

This pattern:
- Imports the portable user module from `modules/home/users/myuser/`
- Passes flake inputs via `extraSpecialArgs` for sops-nix and other modules
- Uses `backupFileExtension` to handle file conflicts gracefully
- Enables `useGlobalPkgs` and `useUserPackages` for efficiency

### Vars generation

After defining user instances, generate encrypted passwords:

```bash
# Generate vars for a machine
clan vars generate myhost

# Generates encrypted password in .clan/vars/myhost/user-myuser/password.yaml
```

With `share = true`, the password is shared across all machines with this user instance.
With `prompt = false`, the password is auto-generated using xkcdpass.

### Complete example

Here's a complete user instance configuration:

```nix
{ inputs, ... }:
{
  clan.inventory.instances.user-admin = {
    module = {
      name = "users";
      input = "clan-core";
    };

    # Deploy to multiple machines
    roles.default.machines."server1" = { };
    roles.default.machines."server2" = { };

    roles.default.settings = {
      user = "admin";
      groups = [ "wheel" "networkmanager" ];
      share = true;
      prompt = false;
    };

    roles.default.extraModules = [
      inputs.home-manager.nixosModules.home-manager
      ({ pkgs, ... }: {
        users.users.admin.shell = pkgs.zsh;

        users.users.admin.openssh.authorizedKeys.keys = [
          "ssh-ed25519 AAAA..."
        ];

        programs.zsh.enable = true;

        home-manager = {
          useGlobalPkgs = true;
          useUserPackages = true;
          backupFileExtension = "before-home-manager";

          extraSpecialArgs = {
            flake = inputs.self // { inherit inputs; };
          };

          users.admin = {
            imports = [
              inputs.self.modules.homeManager."users/admin"
              inputs.self.modules.homeManager.base-sops
            ];
            home.username = "admin";
          };
        };
      })
    ];
  };
}
```

This creates an admin user on server1 and server2 with:
- System user with wheel group access
- Auto-generated shared password
- SSH key for authentication
- zsh as default shell
- Full home-manager environment from portable user module

---

## Aggregate modules

Users import aggregates rather than individual modules.
Aggregates group related features:

| Aggregate | Contents | Use case |
|-----------|----------|----------|
| `aggregate-core` | XDG, SSH, fonts, basic tools | All users |
| `aggregate-shell` | zsh, fish, nushell, starship | All users |
| `aggregate-development` | git, editors, languages | Developers |
| `aggregate-ai` | claude-code, MCP servers | AI tool users |

Example usage in user module:

```nix
imports = with config.flake.modules.homeManager; [
  aggregate-core        # Everyone needs this
  aggregate-shell       # Shell configuration
  aggregate-development # Only for developers
  # aggregate-ai        # Only for AI tool users
];
```

Aggregates are defined in `modules/home/_aggregates.nix`.

---

## Secrets setup

All users use [Tier 2 (sops-nix)](/concepts/clan-integration#two-tier-secrets-architecture) for personal secrets.

### Generate age key

```bash
mkdir -p ~/.config/sops/age
age-keygen -o ~/.config/sops/age/keys.txt
```

### Get public key

```bash
age-keygen -y ~/.config/sops/age/keys.txt
```

### Add to .sops.yaml

Edit `.sops.yaml` to include the public key:

```yaml
keys:
  - &raquel-blackphos age1xxx...  # Add your key

creation_rules:
  - path_regex: secrets/users/raquel\.sops\.yaml$
    key_groups:
      - age:
        - *raquel-blackphos
```

### Create secrets file

```bash
sops secrets/users/raquel.sops.yaml
```

### Verify decryption

```bash
sops -d secrets/users/raquel.sops.yaml
```

---

## Platform differences

### Darwin (macOS)

- Home directory: `/Users/<username>`
- sops-nix uses launchd agent for secret deployment
- After first activation, may need: `launchctl load ~/Library/LaunchAgents/com.sops-nix.service.plist`

### NixOS (Linux)

- Home directory: `/home/<username>`
- sops-nix uses systemd user service
- Secrets automatically deployed on activation

---

## Troubleshooting

### Home-manager activation fails

**Symptom**: `home-manager switch` or system activation fails

**Diagnosis**:
```bash
# Check home-manager generations
ls -la ~/.local/state/nix/profiles/home-manager*

# Verify user module builds
nix build .#homeConfigurations.<user>.activationPackage
```

### Secrets not available

**Symptom**: Files in `~/.config/sops-nix/secrets/` missing

**Diagnosis**:
```bash
# Darwin: Check launchd agent
launchctl list | grep sops

# NixOS: Check systemd service
systemctl --user status sops-nix
```

**Solution**:
```bash
# Darwin: Load agent manually
launchctl load ~/Library/LaunchAgents/com.sops-nix.service.plist

# NixOS: Start service
systemctl --user start sops-nix
```

### Age key not found

**Symptom**: sops decryption fails with "no key found"

**Solution**:
```bash
# Verify key exists
cat ~/.config/sops/age/keys.txt

# Regenerate if needed
age-keygen -o ~/.config/sops/age/keys.txt

# Add public key to .sops.yaml
age-keygen -y ~/.config/sops/age/keys.txt
```

### User module not found

**Symptom**: Build fails with missing module error

**Diagnosis**:
```bash
# Check module exists
ls modules/home/users/<username>/

# Check export in module
grep "flake.modules.homeManager" modules/home/users/<username>/default.nix
```

---

## Relationship to system configuration

```
System Config (darwin/NixOS)
├── System packages
├── System settings
└── Home-manager integration
    ├── crs58's home config
    │   ├── Aggregates (core, shell, dev, ai)
    │   └── User secrets (sops-nix)
    └── raquel's home config
        ├── Aggregates (core, shell)
        └── User secrets (sops-nix)
```

Key points:
- System config controls which users are configured
- Each user imports portable user modules
- User modules import aggregates for features
- Secrets are per-user via sops-nix

---

## See also

- [Host Onboarding](/guides/host-onboarding/) - Initial machine setup
- [Dendritic Architecture](/concepts/dendritic-architecture) - Module organization
- [Clan Integration](/concepts/clan-integration) - Two-tier secrets architecture
