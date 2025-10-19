# Phase 1 implementation guide: adding Clan for remote hosts

This guide provides step-by-step instructions for implementing Phase 1 of the Clan integration plan.
Phase 1 adds Clan capabilities to nix-config for managing remote Hetzner hosts without disrupting existing local configurations.

## Prerequisites

- [ ] Read `00-integration-plan.md` for context
- [ ] Hetzner account with API access (or alternative cloud provider)
- [ ] Age key generated for yourself: `nix run nixpkgs#age -- keygen`
- [ ] Current nix-config working and tests passing

## Step 1: Add clan-core flake input

**File**: `flake.nix`

Add clan-core input with follows for consistency:

```nix
{
  inputs = {
    # ... existing inputs ...

    clan-core.url = "git+https://git.clan.lol/clan/clan-core";
    clan-core.inputs.nixpkgs.follows = "nixpkgs";
    clan-core.inputs.flake-parts.follows = "flake-parts";
    clan-core.inputs.sops-nix.follows = "sops-nix";
    clan-core.inputs.home-manager.follows = "home-manager";
    clan-core.inputs.nix-darwin.follows = "nix-darwin";
  };
}
```

**Validation**:
```bash
cd ~/projects/nix-workspace/nix-config
nix flake lock --update-input clan-core
nix flake show
```

Expected: clan-core appears in inputs, flake evaluates successfully.

## Step 2: Create Clan flake-parts module

**File**: `modules/flake-parts/clan.nix`

```nix
{ inputs, ... }:
{
  imports = [
    inputs.clan-core.flakeModules.default
  ];

  clan = {
    # Distinct name from main nix-config
    meta.name = "nix-config-clan";

    # Make flake inputs available to Clan modules
    specialArgs = { inherit inputs; };

    # Reference to self for accessing outputs
    inherit (inputs) self;

    # Machine inventory
    inventory.machines = {
      # Will be populated with remote hosts
    };

    # Service instances
    inventory.instances = {
      # Essential services for remote hosts
      emergency-access = {
        module = {
          name = "emergency-access";
          input = "clan-core";
        };
        roles.default.tags."remote" = {};
      };

      users-root = {
        module = {
          name = "users";
          input = "clan-core";
        };
        roles.default.tags."remote" = {};
        roles.default.settings = {
          user = "root";
          prompt = false;
          groups = [];
        };
      };

      sshd-remote = {
        module = {
          name = "sshd";
          input = "clan-core";
        };
        roles.server.tags."remote" = {};
        roles.server.settings = {
          certificate.searchDomains = [];
        };
      };
    };

    # SOPS configuration
    secrets.sops.defaultGroups = [ "admins" ];
  };
}
```

**Validation**:
```bash
nix flake check
```

Expected: Flake checks pass, clan configuration available.

## Step 3: Initialize Clan secrets structure

**Commands**:
```bash
cd ~/projects/nix-workspace/nix-config

# Create Clan secrets directory structure
mkdir -p secrets/clan/{groups,machines,secrets,users}

# Generate your age key if not already done
# The key is stored in ~/.config/sops/age/keys.txt (Linux)
# or ~/Library/Application Support/sops/age/keys.txt (macOS)
nix run nixpkgs#clan-cli -- secrets key generate

# Extract your public key
YOUR_AGE_KEY=$(grep 'public key:' ~/.config/sops/age/keys.txt 2>/dev/null || \
               grep 'public key:' ~/Library/Application\ Support/sops/age/keys.txt)
echo "Your age public key: $YOUR_AGE_KEY"

# Create admin group
nix run nixpkgs#clan-cli -- secrets groups add admins

# Add yourself as admin
nix run nixpkgs#clan-cli -- secrets users add crs58 "$YOUR_AGE_KEY"
nix run nixpkgs#clan-cli -- secrets groups add-user admins crs58
```

**Validation**:
```bash
ls -la secrets/clan/groups/admins/
ls -la secrets/clan/users/crs58/
```

Expected: Age key files created in both directories.

## Step 4: Create base module for remote hosts

**File**: `modules/clan/hetzner-base.nix`

```nix
{ config, lib, pkgs, ... }:
{
  # Hetzner-specific base configuration

  # Ensure SSH access
  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = false;
      PermitRootLogin = "prohibit-password";
    };
  };

  # Basic firewall
  networking.firewall.enable = true;
  networking.firewall.allowedTCPPorts = [ 22 ];

  # Use systemd-boot
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # Automatic garbage collection
  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 30d";
  };

  # Same nix settings as local hosts
  nix.settings = {
    experimental-features = [ "nix-command" "flakes" ];
    trusted-users = [ "root" "@wheel" ];
  };

  # Same cache configuration as local hosts
  nix.settings.substituters = [
    "https://cache.nixos.org"
    "https://nix-community.cachix.org"
    "https://cameronraysmith.cachix.org"
  ];

  nix.settings.trusted-public-keys = [
    "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
    "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
    "cameronraysmith.cachix.org-1:aC8ZcRCVcQql77Qn//Q1jrKkiDGir+pIUjhUunN6aio="
  ];

  # Essential packages
  environment.systemPackages = with pkgs; [
    vim
    git
    htop
    curl
  ];

  # Timezone (adjust as needed)
  time.timeZone = "UTC";

  # Minimal locale setup
  i18n.defaultLocale = "en_US.UTF-8";
}
```

**Directory creation**:
```bash
mkdir -p modules/clan
```

## Step 5: Create first remote host configuration

**File**: `configurations/nixos/remote/hetzner-01.nix`

```nix
{ inputs, pkgs, ... }:
{
  imports = [
    inputs.self.nixosModules.clan.hetzner-base
  ];

  # Host-specific settings
  networking.hostName = "hetzner-01";

  # Minimal filesystem (will be replaced by actual disko config)
  fileSystems."/" = {
    device = "/dev/sda1";
    fsType = "ext4";
  };

  fileSystems."/boot" = {
    device = "/dev/sda2";
    fsType = "vfat";
  };

  # User configuration
  users.users.root.openssh.authorizedKeys.keys = [
    # Your SSH public key
    "ssh-ed25519 AAAAC3... your-key-here"
  ];

  # NixOS state version
  system.stateVersion = "25.05";
}
```

**Directory creation**:
```bash
mkdir -p configurations/nixos/remote
```

## Step 6: Update Clan inventory with remote host

**File**: `modules/flake-parts/clan.nix` (update)

Add to `inventory.machines`:

```nix
{
  clan = {
    # ... existing configuration ...

    inventory.machines = {
      hetzner-01 = {
        tags = [ "remote" "hetzner" ];
        # machineClass defaults to "nixos"
      };
    };

    # ... existing inventory.instances ...
  };
}
```

## Step 7: Export Clan nixosModules

**File**: `modules/clan/default.nix`

```nix
{
  hetzner-base = ./hetzner-base.nix;
}
```

**File**: `flake.nix` (update perSystem or flake outputs)

Ensure clan modules are exported:

```nix
{
  flake = {
    # ... existing outputs ...

    nixosModules = nixosModules // {
      clan = import ./modules/clan;
    };
  };
}
```

**Note**: Check your current `flake.nix` structure for where `nixosModules` is defined.
With nixos-unified and flake-parts, this might be auto-wired differently.

## Step 8: Generate vars for remote host

This will create SSH keys and other secrets for hetzner-01:

```bash
cd ~/projects/nix-workspace/nix-config

# Generate all vars for hetzner-01
nix run .#clan-cli -- vars generate hetzner-01
```

Expected prompts:
- Emergency access password
- Any other configured prompts

Expected results:
- `secrets/clan/machines/hetzner-01/` populated with encrypted secrets
- `secrets/clan/secrets/` contains shared secrets

**Validation**:
```bash
ls -la secrets/clan/machines/hetzner-01/
```

Expected: SSH keys, password hashes, other generated files.

## Step 9: Test configuration locally

Before deploying, validate the configuration builds:

```bash
# Build the system configuration
nix build .#nixosConfigurations.hetzner-01.config.system.build.toplevel

# Check for evaluation errors
nix flake check
```

Expected: Clean build, no errors.

## Step 10: Deploy to Hetzner (manual bootstrap)

**Option A: Using Hetzner rescue mode**

1. Create Hetzner cloud server (CX11 or higher)
2. Boot into rescue mode
3. Partition disk manually or use disko
4. Install NixOS:

```bash
# On local machine, from nix-config directory
nix run .#clan-cli -- machines install hetzner-01 \
  --target-host root@<hetzner-ip> \
  --update-hardware-config nixos-facter
```

This will:
- Detect hardware configuration
- Install NixOS
- Deploy configuration
- Reboot into new system

**Option B: Using Terraform (clan-infra pattern)**

Create `terraform/hetzner-01.nix` (advanced, defer if unfamiliar with Terraform).

## Step 11: Validate deployment

After deployment:

```bash
# SSH into host
ssh root@hetzner-01

# Check system configuration
nixos-version
systemctl status

# Verify Clan vars deployed
ls -la /run/secrets/
```

Expected:
- System running NixOS
- Secrets deployed to `/run/secrets/`
- SSH access working

## Step 12: Add basic services via inventory

**File**: `modules/flake-parts/clan.nix` (update)

Add a backup service instance:

```nix
{
  clan = {
    # ... existing configuration ...

    inventory.instances = {
      # ... existing instances ...

      borgbackup-remote = {
        module = {
          name = "borgbackup";
          input = "clan-core";
        };

        # hetzner-01 is backup client
        roles.client.machines.hetzner-01 = {};

        # Configure backup server separately or use cloud storage
        # roles.server.machines.backup-server = {};
      };
    };
  };
}
```

**Deploy update**:
```bash
nix run .#clan-cli -- machines update hetzner-01
```

## Step 13: Document deployment workflow

**File**: `docs/notes/clan-integration/deployment-workflow.md`

```markdown
# Clan deployment workflow

## Adding a new remote host

1. Create configuration in `configurations/nixos/remote/<hostname>.nix`
2. Add to inventory in `modules/flake-parts/clan.nix`
3. Generate vars: `nix run .#clan-cli -- vars generate <hostname>`
4. Install: `nix run .#clan-cli -- machines install <hostname> --target-host root@<ip>`

## Updating existing host

```bash
nix run .#clan-cli -- machines update <hostname>
```

## Managing secrets

```bash
# Add user
nix run .#clan-cli -- secrets users add <username> <age-key>

# Grant admin access
nix run .#clan-cli -- secrets groups add-user admins <username>
```
```

## Step 14: Update CI (if applicable)

If you have CI checking your flake:

**File**: `.github/workflows/ci.yml` (or similar)

Ensure CI doesn't try to build remote hosts:

```yaml
# Only check that configurations evaluate, don't build
- name: Check flake
  run: nix flake check --no-build
```

Or exclude remote hosts from full builds:

```yaml
- name: Build local configs only
  run: |
    nix build .#darwinConfigurations.stibnite.system
    nix build .#nixosConfigurations.stibnite-nixos.config.system.build.toplevel
    # Skip remote hosts that require specific hardware
```

## Step 15: Update main documentation

**File**: `README.md` (or equivalent in your nix-config)

Add section on Clan usage:

```markdown
## Remote host management with Clan

This repository now supports managing remote NixOS hosts using Clan.

### Quick start

```bash
# Generate secrets for a host
nix run .#clan-cli -- vars generate <hostname>

# Deploy to remote host
nix run .#clan-cli -- machines update <hostname>
```

See `docs/notes/clan-integration/` for detailed documentation.
```

## Troubleshooting

### Issue: clan-cli command not found

**Solution**: Use full flake reference:
```bash
nix run .#clan-cli -- <command>
# or
nix run nixpkgs#clan-cli -- <command>
```

### Issue: Age key not found

**Solution**: Ensure age key generated and properly referenced:
```bash
# Check key exists
cat ~/.config/sops/age/keys.txt

# Verify public key matches what you added
nix run nixpkgs#clan-cli -- secrets users list
```

### Issue: Machine not found in inventory

**Solution**: Verify machine added to `inventory.machines` in `modules/flake-parts/clan.nix`:
```bash
nix eval .#clan.inventory.machines --json | jq
```

### Issue: Vars generation fails

**Solution**: Check generator definitions and dependencies:
```bash
# See what vars are defined for a machine
nix eval .#nixosConfigurations.hetzner-01.config.clan.core.vars.generators --json | jq 'keys'
```

### Issue: Deployment fails with SSH errors

**Solution**: Verify SSH key in authorized_keys:
```nix
# In host configuration
users.users.root.openssh.authorizedKeys.keys = [
  "ssh-ed25519 AAAAC3... your-actual-key"
];
```

## Validation checklist

After completing all steps:

- [ ] Flake evaluates: `nix flake check`
- [ ] Clan configuration accessible: `nix eval .#clan.inventory --json`
- [ ] Remote host builds: `nix build .#nixosConfigurations.hetzner-01.config.system.build.toplevel`
- [ ] Vars generated: `secrets/clan/machines/hetzner-01/` populated
- [ ] Deployment successful: `nix run .#clan-cli -- machines update hetzner-01`
- [ ] SSH access works: `ssh root@hetzner-01`
- [ ] Secrets deployed: `ssh root@hetzner-01 ls /run/secrets`
- [ ] Services running: `ssh root@hetzner-01 systemctl status sshd`
- [ ] Local hosts unchanged: `nix build .#darwinConfigurations.stibnite.system`
- [ ] CI passing (if applicable)

## Next steps

After successful Phase 1 deployment:

1. **Monitor**: Operate remote host for 2-3 months, observe Clan patterns
2. **Expand**: Add second remote host using same patterns
3. **Services**: Explore additional Clan services (zerotier, borgbackup, monitoring)
4. **Document**: Record learnings, update troubleshooting section
5. **Evaluate**: Assess readiness for Phase 2 (migrating existing hosts)

## Additional resources

- Clan getting started: `~/projects/nix-workspace/clan-core/docs/site/getting-started/`
- Example production config: `~/projects/nix-workspace/clan-infra`
- Vars documentation: `~/projects/nix-workspace/clan-core/docs/site/guides/vars/`
- Inventory documentation: `~/projects/nix-workspace/clan-core/docs/site/guides/inventory/`
