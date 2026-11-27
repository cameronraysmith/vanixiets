---
title: User Onboarding
sidebar:
  order: 5
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

User configurations follow the [deferred module composition pattern](/concepts/deferred-module-composition):

```
modules/
├── home/
│   └── users/
│       ├── crs58/           # exports users/crs58
│       ├── raquel/          # exports users/raquel
│       ├── cameron/         # exports users/cameron
│       ├── janettesmith/    # exports users/janettesmith
│       └── christophersmith/ # exports users/christophersmith
└── machines/
    └── darwin/
        ├── stibnite.nix     # imports users/crs58
        └── blackphos.nix    # imports users/crs58, users/raquel
```

Each user is exposed as a single registry entry, `flake.modules.homeManager."users/<user>"`, that holds the full home-manager module: programs, packages, and dotfiles together with identity (`home.username`, `home.homeDirectory`) and secrets.
Identity is sourced from typed `flake.users.<user>.meta` and profile composition is driven by `flake.users.<user>.aggregates`.
Machine configs import this `users/<user>` module to activate the user's full home environment.

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

### Step 2: Attach the user to the machine

Declare the account on the host once, as an attachment in `modules/lib/host-users.nix`:

```nix
# modules/lib/host-users.nix
config.flake.fleet.hosts.blackphos.users.raquel = {
  primary = true; # the person the machine belongs to
  uid = 506; # darwin only: the account's existing uid
  overrides.deploysWithoutScreenSession = true; # settings for this pair only
};
```

The `home-manager-integration` aspect (`modules/system/home-manager-integration.nix`), which every host imports, turns each attachment into the home `home-manager.users.raquel` from `flake.users.raquel.modules`, sets nix-darwin's admin account and the uid on darwin, and bridges the personal key on NixOS.
On a NixOS host, the user's clan instance (`modules/clan/inventory/services/users/<user>.nix`) takes its machine list from the same attachments, so no host body names the user.

### Step 3: Create user secrets (legacy sops tree)

User secrets live in the legacy sops tree, one file per user.

Add the user's age public key to `.sops.yaml` (the `ssh-to-age` image of the first `sshKeys` entry in the user's `meta.nix`, derived from their Bitwarden SSH key) with a rule for their file:

```yaml
keys:
  - &raquel-user age1xxx...

creation_rules:
  - path_regex: secrets/home-manager/users/raquel/.*\.yaml$
    key_groups:
      - age:
        - *admin        # offline recovery
        - *admin-user   # operator, to maintain the file
        - *raquel-user
```

Add the anchor to the user table in `modules/checks/sops-correspondence.nix`, then create the secrets file:

```bash
sops secrets/home-manager/users/raquel/secrets.yaml
```

Example key names (values are written in the editor and never committed in plaintext):

```yaml
github-token: <value>
ssh-signing-key: <value>
```

### Step 4: Reference secrets in user module

Use sops in the user module, leaving the age key file location to `base-sops`, which sets the XDG path with `mkDefault`:

```nix
# modules/home/users/raquel/default.nix
{ config, inputs, ... }:
{
  flake.modules.homeManager."users/raquel" = { pkgs, lib, ... }: {
    sops = {
      defaultSopsFile = ../../../../secrets/home-manager/users/raquel/secrets.yaml;
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

Do not set `sops.age.keyFile` in a user module.
On a NixOS host whose attachment bridges this user's key (`sopsBridge`, true by default on NixOS), the bridge assigns the same option at ordinary priority, and a second ordinary-priority definition is an evaluation conflict rather than an override.

### Step 5: Provision the user's age key

On a darwin host, the user derives the key from their SSH key in Bitwarden and appends it to `~/.config/sops/age/keys.txt`; follow [Workstation age key](/guides/secrets-management#workstation-age-key).
Never generate an unrelated age key: the key must be the image of the SSH key the repository records for the user, or the correspondence check fails.

On a clan-managed NixOS host, do not generate a key on the host.
Set `flake.users.<user>.meta.sopsAgeKeyId`, attach the user to the host (`flake.fleet.hosts.<host>.users.<user> = { };`, which bridges the key on NixOS), and commit the user's age private key as `secrets/bridge/<id>-age-key.enc` encrypted to that machine's age key.
System activation then delivers it to `/run/secrets/<id>-age-key` and home-manager reads it from there.
See [Host onboarding](/guides/host-onboarding/) for the host-side steps.

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
  flake.homeConfigurations."raquel@aarch64-darwin" = config.lib.mkHomeConfiguration {
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
nix build '.#homeConfigurations."raquel@aarch64-darwin".activationPackage'

# Activate
./result/activate
```

Or use the home-manager CLI:

```bash
nix run home-manager/master -- switch --flake '.#"raquel@aarch64-darwin"'
```

### Step 4: Ongoing updates

For subsequent updates:

```bash
# Rebuild and activate
home-manager switch --flake '.#"raquel@aarch64-darwin"'
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
- Integrating with clan's vars-based secrets infrastructure (clan vars)

This pattern is NixOS-specific.
For darwin machines, continue using the integrated user setup described above.

### The flake.clan.inventory.instances.user-* pattern

A clan user instance creates the system account and its password; its machine list is generated from the host attachments, and the home comes from the `home-manager-integration` aspect, not from the instance:

```nix
# modules/clan/inventory/services/users/myuser.nix
{ config, inputs, lib, ... }:
{
  flake.clan.inventory.instances.user-myuser = {
    module = {
      name = "users";
      input = "clan-core";
    };

    # Every host with a myuser attachment (modules/lib/host-users.nix)
    roles.default.machines = lib.genAttrs (config.flake.lib.hostsOfAccount "myuser") (_: { });

    roles.default.settings = {
      user = "myuser";
      groups = [ "wheel" "networkmanager" ];
      share = true;   # Same password across machines
      prompt = false; # Auto-generate via xkcdpass
    };

    # System-level user settings only
    roles.default.extraModules = [
      ({ pkgs, ... }: {
        users.users.myuser.shell = pkgs.zsh;
        users.users.myuser.openssh.authorizedKeys.keys = inputs.self.users.myuser.meta.sshKeys;
        programs.zsh.enable = true;
      })
    ];
  };
}
```

Then attach the user to each host in `modules/lib/host-users.nix` (`flake.fleet.hosts.<host>.users.myuser = { };`).

### Settings options

**`user`**: username; it must equal the attachment's account name.
**`groups`**: system groups, e.g. `["wheel" "networkmanager"]`.
**`share = true`**: one password across every machine of the instance, stored in clan vars.
**`prompt = false`**: generate the password with xkcdpass instead of prompting during `clan vars generate`.

### Integration with home-manager

Every host imports `home-manager-integration` beside home-manager's own module, which stays at machine level because importing it from the user services duplicated catppuccin's imports.
For each attachment the aspect sets `home-manager.users.<user>` to import the person's `flake.users.<user>.modules`, then the attachment's `extraImports`, then the pair's `overrides`, sets `useGlobalPkgs`, `useUserPackages` and `backupFileExtension`, and gives the home its own `flake` argument (`flake.lib.homeFlake`).
The order of list options is not import order: the module system collects modules breadth-first and merges the reversed list, so a module's own list definitions follow only those of the modules it imports directly, and a definition imported one level deeper lands earlier (world assumption A344).
A list the pair's `overrides` set follows the person's own entries only where it says so: stibnite's extra packages are last because they are written with `lib.mkAfter`.
No host or service sets `home-manager.extraSpecialArgs.flake`: the aspect asserts it is absent, because a specialArg would shadow each home's own value, including an Omnigent worker's restricted one.

### Vars generation

```bash
clan vars generate myhost
```

With `share = true`, the password is shared across all machines with this user instance; with `prompt = false`, it is generated by xkcdpass.

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

All users use [sops-nix](/concepts/clan-integration#secrets-management) for personal secrets, in `secrets/home-manager/users/<username>/secrets.yaml`.

### Derive your age key

Your key is derived from your SSH key in Bitwarden, never generated separately; follow [Workstation age key](/guides/secrets-management#workstation-age-key).

### Get public key

```bash
age-keygen -y ~/.config/sops/age/keys.txt
```

### Add to .sops.yaml

```yaml
keys:
  - &raquel-user age1xxx...

creation_rules:
  - path_regex: secrets/home-manager/users/raquel/.*\.yaml$
    key_groups:
      - age:
        - *admin
        - *admin-user
        - *raquel-user
```

### Create secrets file

```bash
sops secrets/home-manager/users/raquel/secrets.yaml
```

### Verify decryption

```bash
sops -d secrets/home-manager/users/raquel/secrets.yaml >/dev/null && echo ok
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
nix build '.#homeConfigurations."<user>@<system>".activationPackage'
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
# Your public keys (the key file must exist)
age-keygen -y ~/.config/sops/age/keys.txt
```

If the file is missing, derive the key again from Bitwarden ([Workstation age key](/guides/secrets-management#workstation-age-key)); it is the same key every time, so `.sops.yaml` needs no change.

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
- [Deferred Module Composition](/concepts/deferred-module-composition) - Module organization
- [Clan Integration](/concepts/clan-integration) - Secrets management
