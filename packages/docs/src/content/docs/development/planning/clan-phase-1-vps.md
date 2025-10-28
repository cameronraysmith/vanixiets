---
title: "Phase 1 Implementation Guide: VPS Deployment (Cinnabar)"
---

**Working repository**: `~/projects/nix-workspace/test-clan/` (same experimental repo, `main` branch)

**Scope**: Complete end-to-end infrastructure deployment proof of concept

This guide provides step-by-step instructions for implementing Phase 1 of the dendritic flake-parts + clan-core migration.
Phase 1 deploys a Hetzner Cloud VPS named "cinnabar" as the foundation infrastructure FROM test-clan, establishing zerotier controller and core services.
This completes the test-clan proof of concept with real infrastructure before migrating patterns to production nix-config (Phase 2).

**CRITICAL**: Phase 1 happens in test-clan, NOT nix-config. This proves the entire stack (dendritic + clan + terraform + infrastructure) works before touching production configuration.

**Prerequisite**: Phase 0 (test-clan validation) should be completed first to validate dendritic + clan integration patterns.

## Strategic rationale: why VPS first?

Deploying cinnabar before migrating darwin hosts provides critical advantages:

1. **Always-on infrastructure**: VPS provides stable zerotier controller that doesn't depend on darwin hosts being powered on
2. **De-risks darwin migration**: Core services proven operational before touching daily-use machines
3. **Native platform validation**: Tests dendritic + clan on NixOS (clan's primary target) before attempting darwin integration
4. **Stable foundation**: Darwin hosts connect to proven-working infrastructure
5. **Low-risk experimentation**: VPS is disposable and doesn't affect existing darwin workflows
6. **Infrastructure-as-code validation**: Proves terraform/terranix patterns work in your repo before broader adoption

## Prerequisites

- [ ] **Phase 0 completed**: test-clan validation finished with patterns documented
- [ ] Read `00-integration-plan.md` for complete context
- [ ] Read `01-phase-0-validation.md` and review integration findings
- [ ] Hetzner Cloud account created (https://console.hetzner.cloud/)
- [ ] Hetzner Cloud API token generated (Read & Write permissions)
- [ ] Age key generated: `nix run nixpkgs#age -- keygen`
- [ ] test-clan repository from Phase 0 ready (patterns validated)
- [ ] Familiarity with flake-parts module system
- [ ] Understanding of dendritic flake-parts pattern and clan architecture from Phase 0
- [ ] Production nix-config remains unchanged (darwin hosts stay on nixos-unified, untouched during Phase 1)

## Migration overview

Phase 1 completes the test-clan proof of concept by:
1. Adding terraform/terranix inputs to test-clan flake (building on Phase 0 setup)
2. Extending dendritic module structure with VPS-specific modules
3. Setting up terraform/terranix for Hetzner Cloud provisioning (learning from clan-infra patterns)
4. Configuring cinnabar VPS with disko (ext4 + LUKS encryption)
5. Adding cinnabar to clan inventory (alongside Phase 0 test VM)
6. Deploying core services: zerotier controller, sshd-clan, emergency-access, users-root
7. Validating complete infrastructure stack works end-to-end

## Step 1: Add required flake inputs

**File**: `~/projects/nix-workspace/test-clan/flake.nix`

Add clan-core, import-tree, and terranix inputs with appropriate follows:

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

    import-tree.url = "github:vic/import-tree";

    terranix.url = "github:terranix/terranix";
    terranix.inputs.flake-parts.follows = "flake-parts";
    terranix.inputs.nixpkgs.follows = "nixpkgs";

    disko.url = "github:nix-community/disko";
    disko.inputs.nixpkgs.follows = "nixpkgs";

    srvos.url = "github:nix-community/srvos";
    srvos.inputs.nixpkgs.follows = "nixpkgs";
  };
}
```

**Validation**:
```bash
cd ~/projects/nix-workspace/nix-config
nix flake lock --update-input clan-core --update-input import-tree --update-input terranix --update-input disko --update-input srvos
nix flake show
```

Expected: All inputs appear, flake evaluates successfully.

## Step 2: Update flake outputs to use import-tree

**File**: `flake.nix`

Modify outputs to use import-tree for auto-discovery and import terranix flakeModule:

```nix
{
  outputs = inputs:
    inputs.flake-parts.lib.mkFlake { inherit inputs; } (
      { ... }: {
        imports = [
          inputs.terranix.flakeModule
          # Import all .nix files from modules/ recursively
          (inputs.import-tree ./modules)
        ];
      }
    );
}
```

**Note**: This replaces manual imports. import-tree discovers all .nix files in modules/ automatically.

**Validation**:
```bash
nix flake check
```

Expected: Flake evaluates, existing configurations still build.

## Step 3: Create dendritic module directory structure

**Commands**:
```bash
cd ~/projects/nix-workspace/nix-config

# Create dendritic module structure
mkdir -p modules/base
mkdir -p modules/nixos
mkdir -p modules/darwin
mkdir -p modules/shell
mkdir -p modules/dev/git
mkdir -p modules/hosts/cinnabar
mkdir -p modules/users
mkdir -p modules/flake-parts
mkdir -p modules/terranix

# Create terraform working directory
mkdir -p terraform
```

**Directory layout**:
```
modules/
├── base/           # Foundation modules (cross-platform)
├── nixos/          # NixOS-specific modules
├── darwin/         # Darwin-specific modules
├── shell/          # Shell tools (fish, starship, etc.)
├── dev/            # Development tools
│   └── git/
├── hosts/          # Machine-specific configurations
│   └── cinnabar/   # VPS configuration
├── users/          # User configurations
├── flake-parts/    # Flake-level modules (clan inventory, host generation)
└── terranix/       # Terraform/terranix modules
terraform/          # Terraform working directory (git-ignored state)
```

## Step 4: Initialize clan secrets structure

**Commands**:
```bash
cd ~/projects/nix-workspace/nix-config

# Create clan secrets directory structure
mkdir -p secrets/{groups,machines,secrets,users}

# Generate your age key if not already done
nix run nixpkgs#clan-cli -- secrets key generate

# Extract your public key (macOS)
YOUR_AGE_KEY=$(grep 'public key:' ~/Library/Application\ Support/sops/age/keys.txt | awk '{print $4}')
# Or Linux:
# YOUR_AGE_KEY=$(grep 'public key:' ~/.config/sops/age/keys.txt | awk '{print $4}')

echo "Your age public key: $YOUR_AGE_KEY"

# Create admin group
nix run .#clan-cli -- secrets groups add admins

# Add yourself as admin
nix run .#clan-cli -- secrets users add crs58 "$YOUR_AGE_KEY"
nix run .#clan-cli -- secrets groups add-user admins crs58

# Store Hetzner Cloud API token in clan secrets
echo -n "your-hetzner-api-token-here" | nix run .#clan-cli -- secrets set hcloud-api-key

# Store terraform state encryption passphrase
echo -n "$(openssl rand -base64 32)" | nix run .#clan-cli -- secrets set tf-passphrase
```

**Important**: Replace `your-hetzner-api-token-here` with your actual Hetzner Cloud API token from https://console.hetzner.cloud/projects → Security → API Tokens.

**Validation**:
```bash
ls -la secrets/groups/admins/
ls -la secrets/users/crs58/
nix run .#clan-cli -- secrets list
```

Expected: Age keys created, secrets stored (hcloud-api-key, tf-passphrase visible in list).

## Step 5: Create base terranix configuration

**File**: `modules/terranix/base.nix`

Base terraform configuration with Hetzner Cloud provider:

```nix
{
  config,
  pkgs,
  lib,
  ...
}:
{
  variable.passphrase = { };

  terraform.required_providers.external.source = "hashicorp/external";
  terraform.required_providers.hcloud.source = "hetznercloud/hcloud";
  terraform.required_providers.local.source = "hashicorp/local";

  data.external.hcloud-api-key = {
    program = [
      (lib.getExe (
        pkgs.writeShellApplication {
          name = "get-clan-secret";
          text = ''
            jq -n --arg secret "$(clan secrets get hcloud-api-key)" '{"secret":$secret}'
          '';
        }
      ))
    ];
  };

  provider.hcloud.token = config.data.external.hcloud-api-key "result.secret";
}
```

**Pattern**: Uses clan secrets to fetch Hetzner API token securely, following clan-infra pattern exactly.

## Step 6: Create SSH key generation module

**File**: `modules/terranix/ssh-keys.nix`

Generate SSH deployment keys for terraform-managed machines:

```nix
{ config, lib, ... }:
{
  terraform.required_providers.tls.source = "hashicorp/tls";

  resource.tls_private_key.ssh_deploy_key = {
    algorithm = "ED25519";
  };

  resource.local_sensitive_file.ssh_deploy_key = {
    filename = "\${path.module}/.terraform-deploy-key";
    file_permission = "600";
    content = config.resource.tls_private_key.ssh_deploy_key "private_key_openssh";
  };

  resource.hcloud_ssh_key.terraform = {
    name = "nix-config Terraform Deploy Key";
    public_key = config.resource.tls_private_key.ssh_deploy_key "public_key_openssh";
  };

  # Add your personal SSH key for emergency access
  resource.hcloud_ssh_key.crs58 = {
    name = "crs58";
    public_key = "ssh-ed25519 AAAAC3... your-ssh-public-key-here";
  };
}
```

**Important**: Replace `ssh-ed25519 AAAAC3... your-ssh-public-key-here` with your actual SSH public key.

## Step 7: Create cinnabar terraform configuration

**File**: `modules/hosts/cinnabar/terraform-configuration.nix`

Terraform resources for cinnabar VPS:

```nix
{ config, lib, ... }:
{
  resource.hcloud_server.cinnabar = {
    name = "cinnabar";
    server_type = "cx53"; # 16GB RAM, 6 vCPU, 360GB NVMe
    location = "ash"; # Ashburn, VA (or fsn1, nbg1, hel1 for EU)
    image = "debian-12"; # Base image for NixOS installation

    ssh_keys = [
      (config.resource.hcloud_ssh_key.terraform "id")
      (config.resource.hcloud_ssh_key.crs58 "id")
    ];

    public_net = {
      ipv4_enabled = true;
      ipv6_enabled = true;
    };
  };

  # Trigger NixOS installation after server provisioned
  resource.null_resource.install-cinnabar = {
    triggers = {
      server_id = config.resource.hcloud_server.cinnabar "id";
    };

    provisioner.local-exec = {
      command = "clan machines install cinnabar --update-hardware-config nixos-facter --target-host root@\${resource.hcloud_server.cinnabar.ipv4_address} -i '\${resource.local_sensitive_file.ssh_deploy_key.filename}' --yes --debug";
    };

    depends_on = [
      "hcloud_server.cinnabar"
    ];
  };

  output.cinnabar_ipv4 = {
    value = config.resource.hcloud_server.cinnabar "ipv4_address";
  };

  output.cinnabar_ipv6 = {
    value = config.resource.hcloud_server.cinnabar "ipv6_address";
  };
}
```

**Note**: Choose location based on your geography. Options: `ash` (US), `fsn1`/`nbg1`/`hel1` (EU), `hil` (India), `sin` (Singapore).

## Step 8: Create terranix configuration flake-parts module

**File**: `modules/flake-parts/terranix.nix`

Wire up terranix configurations in perSystem:

```nix
{
  inputs,
  self,
  ...
}:
{
  perSystem =
    {
      inputs',
      pkgs,
      ...
    }:
    {
      terranix =
        let
          package = pkgs.opentofu.withPlugins (p: [
            p.hashicorp_external
            p.hashicorp_local
            p.hashicorp_null
            p.hashicorp_tls
            p.hetznercloud_hcloud
          ]);
        in
        {
          terranixConfigurations.terraform = {
            workdir = "terraform";
            modules = [
              self.modules.terranix.base
              self.modules.terranix.ssh-keys
              ../hosts/cinnabar/terraform-configuration.nix
            ];
            terraformWrapper.package = package;
            terraformWrapper.extraRuntimeInputs = [ inputs'.clan-core.packages.default ];
            terraformWrapper.prefixText = ''
              TF_VAR_passphrase=$(clan secrets get tf-passphrase)
              export TF_VAR_passphrase
              TF_ENCRYPTION=$(cat <<'EOF'
              key_provider "pbkdf2" "state_encryption_password" {
                passphrase = var.passphrase
              }
              method "aes_gcm" "encryption_method" {
                keys = key_provider.pbkdf2.state_encryption_password
              }
              state {
                enforced = true
                method = method.aes_gcm.encryption_method
              }
              EOF
              )

              # shellcheck disable=SC2090
              export TF_ENCRYPTION
            '';
          };
        };
    };

  flake.modules.terranix.base = ./terranix/base.nix;
  flake.modules.terranix.ssh-keys = ./terranix/ssh-keys.nix;
}
```

**Pattern**: Uses OpenTofu (terraform fork) with encrypted state following clan-infra pattern.

## Step 9: Create cinnabar disko configuration

**File**: `modules/hosts/cinnabar/disko.nix`

Declarative disk partitioning with LUKS encryption:

```nix
{ config, pkgs, ... }:
{
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # Generate LUKS encryption key via clan vars
  clan.core.vars.generators.luks = {
    files.key.neededFor = "partitioning";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.xxd
    ];
    script = ''
      dd if=/dev/urandom bs=32 count=1 | xxd -c32 -p > $out/key
    '';
  };

  boot.initrd.systemd.services.systemd-cryptsetup@cryptroot = {
    preStart = ''
      while [ ! -f ${config.clan.core.vars.generators.luks.files.key.path} ]; do
        sleep 1
      done
    '';
    unitConfig.StartLimitIntervalSec = 0;
    serviceConfig = {
      RestartSec = "1s";
      Restart = "on-failure";
    };
  };

  disko.devices = {
    disk.primary = {
      type = "disk";
      device = "/dev/sda"; # Hetzner Cloud uses /dev/sda
      content = {
        type = "gpt";
        partitions = {
          ESP = {
            size = "1G";
            type = "EF00";
            content = {
              type = "filesystem";
              format = "vfat";
              mountpoint = "/boot";
              mountOptions = [ "umask=0077" ];
            };
          };
          luks = {
            size = "100%";
            content = {
              type = "luks";
              name = "cryptroot";
              passwordFile = config.clan.core.vars.generators.luks.files.key.path;
              settings = {
                allowDiscards = true;
                bypassWorkqueues = true;
              };
              content = {
                type = "lvm_pv";
                vg = "pool";
              };
            };
          };
        };
      };
    };

    lvm_vg.pool = {
      type = "lvm_vg";
      lvs = {
        root = {
          size = "100%FREE";
          content = {
            type = "filesystem";
            format = "ext4";
            mountpoint = "/";
            mountOptions = [ "defaults" ];
          };
        };
      };
    };
  };
}
```

**Pattern**: LUKS encryption with key managed by clan vars, ext4 on LVM for flexibility.

## Step 10: Create base NixOS modules

**File**: `modules/base/nix.nix`

Core nix settings for all systems:

```nix
{
  flake.modules = {
    nixos.base-nix = {
      pkgs,
      ...
    }: {
      nix.settings = {
        experimental-features = [
          "nix-command"
          "flakes"
        ];
        trusted-users = [
          "root"
          "@wheel"
        ];

        substituters = [
          "https://cache.nixos.org"
          "https://nix-community.cachix.org"
          "https://cache2.clan.lol"
        ];

        trusted-public-keys = [
          "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
          "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
          "niks3.clan.lol-1:R1VTRLhKHvKKrx/X36wAMuay2bdagsGylwfF7wPs6ns="
        ];
      };

      nix.gc = {
        automatic = true;
        dates = "weekly";
      };
    };

    darwin.base-nix = {
      pkgs,
      ...
    }: {
      nix.settings = {
        experimental-features = [
          "nix-command"
          "flakes"
        ];
        trusted-users = [
          "root"
          "@admin"
        ];

        substituters = [
          "https://cache.nixos.org"
          "https://nix-community.cachix.org"
        ];

        trusted-public-keys = [
          "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
          "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
        ];
      };

      nix.gc = {
        automatic = true;
        options = "--delete-older-than 30d";
      };
    };
  };
}
```

**File**: `modules/nixos/server.nix`

Server-specific NixOS configuration:

```nix
{ inputs, ... }:
{
  flake.modules.nixos.server = {
    imports = [
      inputs.srvos.nixosModules.server
      inputs.srvos.nixosModules.mixins-telegraf
    ];

    # Clan state version management
    clan.core.settings.state-version.enable = true;

    # Server kernel tuning
    boot.kernel.sysctl = {
      "fs.inotify.max_user_instances" = 524288;
      "fs.inotify.max_user_watches" = 524288;
    };

    # Automatic garbage collection
    nix.gc.automatic = true;
    nix.gc.dates = "weekly";

    # Basic firewall (zerotier will be added by clan service)
    networking.firewall.enable = true;
  };
}
```

## Step 11: Create cinnabar host configuration

**File**: `modules/hosts/cinnabar/default.nix`

Main configuration for cinnabar VPS using dendritic flake-parts pattern:

```nix
{
  config,
  inputs,
  self,
  ...
}:
{
  flake.modules.nixos."hosts/cinnabar" = {
    imports = [
      # Base modules
      config.flake.modules.nixos.base-nix
      config.flake.modules.nixos.server

      # Disko for declarative partitioning
      ./disko.nix

      # srvos hardware profile for Hetzner Cloud
      inputs.srvos.nixosModules.hardware-hetzner-cloud
    ];

    # Host identification
    networking.hostName = "cinnabar";
    networking.domain = ""; # No domain initially, use IP addresses

    # Clan SOPS default groups
    clan.core.sops.defaultGroups = [ "admins" ];

    # System state version
    system.stateVersion = "24.11";

    # Enable SSH for administration
    services.openssh = {
      enable = true;
      settings = {
        PermitRootLogin = "prohibit-password";
        PasswordAuthentication = false;
      };
    };

    # Basic admin user
    users.users.root.openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3... your-ssh-public-key-here"
    ];

    # Timezone
    time.timeZone = "UTC";

    # Basic system packages
    environment.systemPackages = with pkgs; [
      vim
      git
      htop
      curl
      wget
    ];
  };
}
```

**Important**: Replace SSH public key with your actual key.

## Step 12: Create clan inventory module

**File**: `modules/flake-parts/clan.nix`

Clan inventory with cinnabar as first machine:

```nix
{ inputs, ... }:
{
  imports = [ inputs.clan-core.flakeModules.default ];

  clan = {
    meta.name = "nix-config";
    specialArgs = {
      inherit inputs;
    };

    # Machine inventory
    inventory.machines = {
      cinnabar = {
        tags = [
          "nixos"
          "vps"
          "cloud"
        ];
        machineClass = "nixos";
      };

      # Darwin hosts (to be migrated in future phases)
      blackphos = {
        tags = [
          "darwin"
          "workstation"
        ];
        machineClass = "darwin";
      };
      rosegold = {
        tags = [
          "darwin"
          "workstation"
        ];
        machineClass = "darwin";
      };
      argentum = {
        tags = [
          "darwin"
          "workstation"
        ];
        machineClass = "darwin";
      };
      stibnite = {
        tags = [
          "darwin"
          "workstation"
          "primary"
        ];
        machineClass = "darwin";
      };
    };

    # Service instances
    inventory.instances = {
      # Emergency access for all machines
      emergency-access = {
        module = {
          name = "emergency-access";
          input = "clan-core";
        };
        roles.default.tags."all" = { };
      };

      # Root user management for VPS
      users-root = {
        module = {
          name = "users";
          input = "clan-core";
        };
        roles.default.machines.cinnabar = { };
        roles.default.settings = {
          user = "root";
          prompt = false;
          groups = [ ];
        };
      };

      # Zerotier network with cinnabar as controller
      zerotier-local = {
        module = {
          name = "zerotier";
          input = "clan-core";
        };
        # cinnabar is controller (always-on VPS)
        roles.controller.machines.cinnabar = { };
        # All machines are peers (darwin hosts will connect in later phases)
        roles.peer.tags."all" = { };
      };

      # SSH with certificate authority
      sshd-clan = {
        module = {
          name = "sshd";
          input = "clan-core";
        };
        # All machines run SSH server
        roles.server.tags."all" = { };
        # All machines are SSH clients (trust CA)
        roles.client.tags."all" = { };
      };
    };

    # Secrets configuration
    secrets.sops.defaultGroups = [ "admins" ];
  };
}
```

**Pattern**: cinnabar is zerotier controller, all other machines are peers.

## Step 13: Create nixosConfigurations generator

**File**: `modules/flake-parts/nixos-machines.nix`

Auto-generate nixosConfigurations from dendritic host modules:

```nix
{
  inputs,
  self,
  lib,
  config,
  ...
}:
let
  prefix = "hosts/";
  collectHostsModules = modules: lib.filterAttrs (name: _: lib.hasPrefix prefix name) modules;
in
{
  flake.nixosConfigurations = lib.pipe (collectHostsModules config.flake.modules.nixos) [
    (lib.mapAttrs' (
      name: module:
      let
        hostName = lib.removePrefix prefix name;
      in
      {
        name = hostName;
        value = inputs.nixpkgs.lib.nixosSystem {
          specialArgs = {
            inherit inputs self;
          };
          modules = [
            inputs.disko.nixosModules.disko
            module
          ];
        };
      }
    ))
  ];
}
```

**Function**: Discovers all `flake.modules.nixos."hosts/*"` and generates corresponding nixosConfigurations.

## Step 14: Add terraform .gitignore entries

**File**: `.gitignore` (add these lines)

```
# Terraform
terraform/
!terraform/.gitkeep
.terraform/
.terraform.lock.hcl
terraform.tfstate
terraform.tfstate.backup
*.tfvars
*.tfvars.sops.json
.terraform-deploy-key
*nixos-vars.json
```

**Create placeholder**:
```bash
touch terraform/.gitkeep
```

## Step 15: Build and validate configuration

Test that cinnabar configuration builds:

```bash
# Check flake structure
nix flake show

# Verify nixosConfigurations generated
nix eval .#nixosConfigurations --apply builtins.attrNames
# Expected: [ "cinnabar" ]

# Build cinnabar configuration (dry-run, won't deploy)
nix build .#nixosConfigurations.cinnabar.config.system.build.toplevel

# Check clan inventory
nix eval .#clan.inventory --json | jq .

# Verify terranix configuration
nix eval .#terranix.terraform --apply 'cfg: cfg.modules'
```

Expected: All commands succeed, cinnabar appears in configurations and inventory.

## Step 16: Initialize terraform workspace

Initialize OpenTofu/terraform:

```bash
cd ~/projects/nix-workspace/nix-config

# Initialize terraform (downloads providers, sets up state)
nix run .#terraform.terraform -- init

# Review planned changes (DOES NOT APPLY)
nix run .#terraform.terraform -- plan

# Expected output:
# + hcloud_server.cinnabar (create)
# + hcloud_ssh_key.terraform (create)
# + hcloud_ssh_key.crs58 (create)
# + tls_private_key.ssh_deploy_key (create)
# + local_sensitive_file.ssh_deploy_key (create)
# + null_resource.install-cinnabar (create)
```

**Review carefully**: Verify server specs (CX53, location, SSH keys) before applying.

## Step 17: Generate vars for cinnabar

Generate clan vars (LUKS key, zerotier network, etc.):

```bash
# Generate all vars for cinnabar
nix run .#clan-cli -- vars generate cinnabar

# Prompts you may see:
# - Emergency access password: Set a strong password
# - Any other service-specific prompts

# Verify vars generated
nix run .#clan-cli -- vars list cinnabar
```

Expected: `secrets/machines/cinnabar/` populated with encrypted secrets.

**Important**: The LUKS encryption key is generated automatically. Store this securely - you cannot access the disk without it.

## Step 18: Deploy VPS infrastructure

Apply terraform configuration to provision VPS:

```bash
# Apply terraform plan (creates real infrastructure, costs money)
nix run .#terraform.terraform -- apply

# Review plan again, type 'yes' to confirm
# This will:
# 1. Create SSH keys
# 2. Provision Hetzner Cloud CX53 server
# 3. Trigger 'clan machines install cinnabar' automatically
```

**Expected duration**: 3-5 minutes for server provisioning + 10-15 minutes for NixOS installation.

**Monitor installation**:
```bash
# Watch terraform output for 'null_resource.install-cinnabar'
# You'll see clan CLI installing NixOS, generating hardware config, deploying secrets
```

**Retrieve IP addresses**:
```bash
nix run .#terraform.terraform -- output cinnabar_ipv4
nix run .#terraform.terraform -- output cinnabar_ipv6
```

**Save these IPs** - you'll need them for SSH access and darwin host configuration.

## Step 19: Verify VPS deployment

After installation completes, verify cinnabar is operational:

```bash
# Get cinnabar IP
CINNABAR_IP=$(nix run .#terraform.terraform -- output -raw cinnabar_ipv4)

# SSH into cinnabar
ssh root@$CINNABAR_IP

# On cinnabar, verify system
nixos-version
# Expected: 24.11.x or similar

# Check clan vars deployed
ls -la /run/secrets/
# Expected: LUKS key, zerotier secrets, SSH CA keys, emergency password

# Verify zerotier controller
zerotier-cli info
# Expected: 200 info <node-id> <version> ONLINE

zerotier-cli listnetworks
# Expected: Shows zerotier-local network ID

# Get zerotier network ID for darwin hosts
NETWORK_ID=$(zerotier-cli listnetworks | awk 'NR==2 {print $3}')
echo "Zerotier network ID: $NETWORK_ID"

# Check SSH daemon
systemctl status sshd
# Expected: active (running)

# Verify emergency access user
sudo -l
# Expected: Can sudo without password if emergency access configured

# Exit cinnabar
exit
```

## Step 20: Authorize yourself on zerotier network

From your local machine (or any zerotier client):

```bash
# Get cinnabar IP
CINNABAR_IP=$(nix run .#terraform.terraform -- output -raw cinnabar_ipv4)

# SSH into cinnabar
ssh root@$CINNABAR_IP

# List zerotier network members
sudo zerotier-cli listnetworks
# Note the network ID (10 hex digits)

# If you want to connect another device now (optional):
# On other device: sudo zerotier-cli join <network-id>
# Then on cinnabar: sudo zerotier-cli set <network-id> <member-id> allow=true

exit
```

## Phase 1 validation checklist

After completing all steps:

- [ ] Flake evaluates: `nix flake check`
- [ ] cinnabar configuration builds: `nix build .#nixosConfigurations.cinnabar.config.system.build.toplevel`
- [ ] Clan inventory includes cinnabar: `nix eval .#clan.inventory.machines.cinnabar`
- [ ] Terraform initialized: `terraform/.terraform/` exists
- [ ] Hetzner Cloud VPS provisioned: Server visible in console.hetzner.cloud
- [ ] Vars generated: `secrets/machines/cinnabar/` populated
- [ ] NixOS installed on cinnabar: Can SSH to root@cinnabar-ip
- [ ] Secrets deployed: `/run/secrets/` on cinnabar contains LUKS key, zerotier files
- [ ] Zerotier controller operational: `zerotier-cli info` on cinnabar shows ONLINE
- [ ] SSH daemon running: Can SSH with password or key
- [ ] Emergency access functional: Can sudo as configured user

## Troubleshooting

### Issue: terraform init fails with provider errors

**Solution**: Verify terranix configuration syntax:
```bash
# Check generated terraform JSON
nix eval .#terranix.terraform.result.terraformConfiguration --json | jq .

# Verify provider versions available
nix eval .#terranix.terraform.terraformWrapper.package
```

### Issue: Hetzner API authentication fails

**Solution**: Verify API token in clan secrets:
```bash
# Check secret exists
nix run .#clan-cli -- secrets list | grep hcloud

# Re-set if needed
echo -n "your-hetzner-api-token" | nix run .#clan-cli -- secrets set hcloud-api-key

# Verify token works directly
curl -H "Authorization: Bearer $(clan secrets get hcloud-api-key)" \
  https://api.hetzner.cloud/v1/servers
```

### Issue: clan machines install fails during terraform apply

**Error**: `null_resource.install-cinnabar` provisioner fails

**Solution**: Run installation manually:
```bash
# Get server IP from terraform
CINNABAR_IP=$(nix run .#terraform.terraform -- output -raw cinnabar_ipv4)

# Run clan install manually
nix run .#clan-cli -- machines install cinnabar \
  --update-hardware-config nixos-facter \
  --target-host root@$CINNABAR_IP \
  -i terraform/.terraform-deploy-key \
  --yes --debug
```

### Issue: Cannot SSH to cinnabar after deployment

**Solution**: Check SSH key configured correctly:
```bash
# Verify your SSH key in terraform config
grep "public_key" modules/terranix/ssh-keys.nix

# Try with terraform deploy key
ssh -i terraform/.terraform-deploy-key root@$CINNABAR_IP

# Check Hetzner console for rescue mode if needed
```

### Issue: Zerotier controller not starting

**Solution**: Check zerotier vars generated:
```bash
# Verify zerotier vars exist
nix run .#clan-cli -- vars list cinnabar | grep zerotier

# On cinnabar, check zerotier service
ssh root@$CINNABAR_IP
systemctl status zerotier-one
journalctl -u zerotier-one -n 50
```

### Issue: Disko partitioning fails during installation

**Solution**: Check disk device name:
```bash
# Hetzner Cloud uses /dev/sda, verify in disko.nix
grep "device =" modules/hosts/cinnabar/disko.nix

# If different, update disko.nix and re-run installation
```

## Cost management and cleanup

**Monthly cost**: Hetzner Cloud CX53 costs approximately €23.50/month (~$25 USD).

**To destroy VPS and cleanup** (recoverable, fully declarative):
```bash
# WARNING: This deletes the server and all data on it
nix run .#terraform.terraform -- destroy

# Review plan, type 'yes' to confirm
# This removes:
# - Hetzner Cloud server
# - SSH keys from Hetzner
# - Local terraform state updated

# Secrets remain in secrets/machines/cinnabar/ for easy re-creation
```

**To recreate after destroy**:
```bash
# Re-apply terraform (uses existing secrets)
nix run .#terraform.terraform -- apply

# Clan will reinstall NixOS with same configuration
```

## CI/CD validation for Phase 1

### Update nix-config justfile for cinnabar

Add cinnabar-specific recipes to the nix-config justfile:

**File**: `~/projects/nix-workspace/nix-config/justfile`

Add to the `nixos` group:

```just
# Build cinnabar VPS configuration
[group('nixos')]
nixos-build-cinnabar:
  nix build .#nixosConfigurations.cinnabar.config.system.build.toplevel

# Test cinnabar configuration (dry-run)
[group('nixos')]
nixos-test-cinnabar:
  nixos-rebuild test --flake .#cinnabar --dry-run

# Deploy to cinnabar VPS
[group('nixos')]
deploy-cinnabar:
  nix run nixpkgs#clan-cli -- machines install cinnabar
```

Add to the `clan` group:

```just
# Generate vars for cinnabar
[group('clan')]
vars-generate-cinnabar:
  nix run nixpkgs#clan-cli -- vars generate cinnabar

# Show cinnabar in clan inventory
[group('clan')]
show-cinnabar-inventory:
  nix eval .#clan.inventory.machines.cinnabar --json | nix run nixpkgs#jq
```

Add to the `CI/CD` group:

```just
# Build cinnabar for CI validation
[group('CI/CD')]
ci-build-cinnabar:
  just nixos-build-cinnabar
```

### Update CI workflow for cinnabar

Update `.github/workflows/ci.yaml` to include cinnabar build:

**File**: `~/projects/nix-workspace/nix-config/.github/workflows/ci.yaml`

Add to the `nix` job matrix:

```yaml
# In the matrix section, add:
- system: x86_64-linux
  runner: ubuntu-latest
  category: nixos
  config: cinnabar  # NEW
```

The existing `ci-build-category` script will handle building cinnabar automatically.

### Local validation before CI

Before pushing to CI, validate locally:

```bash
cd ~/projects/nix-workspace/nix-config

# Enter devshell
nix develop

# Validate cinnabar builds
just ci-build-cinnabar

# Validate flake evaluation
just check

# Validate clan inventory includes cinnabar
just show-cinnabar-inventory

# Run full CI validation locally
just ci-local
```

### CI validation checklist

After Phase 1 deployment:

- [ ] Cinnabar configuration builds in CI (GitHub Actions)
- [ ] Justfile recipes for cinnabar work locally
- [ ] `just check` passes (flake evaluation)
- [ ] `just ci-build-cinnabar` succeeds
- [ ] Clan inventory includes cinnabar machine
- [ ] Terraform configuration validates (if using terraform CI job)
- [ ] No CI failures after cinnabar integration

### Benefits of CI validation

1. **Early detection**: CI catches configuration errors before deployment
2. **Reproducibility**: Same commands work locally and in CI (`just` recipes)
3. **Confidence**: Successful CI run means configuration is valid
4. **Documentation**: CI workflow serves as executable documentation
5. **Team collaboration**: Others can validate changes before deployment

### Troubleshooting CI failures

**Issue**: Cinnabar build fails in CI but works locally
**Solution**: Check system differences (x86_64-linux vs aarch64-darwin), ensure inputs.follows are correct

**Issue**: Terraform validation fails
**Solution**: Verify secrets are available in CI (SOPS_AGE_KEY secret), check terraform state encryption

**Issue**: Clan vars generation fails in CI
**Solution**: CI shouldn't run vars generation (requires secrets), only build validation

## Next steps: Phase 2 (blackphos migration)

After cinnabar is stable (monitor for 1-2 weeks), proceed to Phase 2 (blackphos migration).

**Phase 2 overview**:
1. Create blackphos darwin configuration using dendritic flake-parts pattern (reference: cinnabar structure)
2. Configure blackphos as zerotier peer (connects to cinnabar controller)
3. Generate vars for blackphos
4. Deploy blackphos with `darwin-rebuild switch`
5. Verify blackphos ↔ cinnabar zerotier connectivity
6. Test SSH via zerotier network (using sshd-clan CA certificates)

**Key difference**: blackphos uses darwin modules, but follows same dendritic flake-parts pattern as cinnabar.

See `02-phase-2-blackphos-guide.md` for detailed blackphos migration steps.

## Summary

Phase 1 establishes the infrastructure foundation:
- **cinnabar VPS**: Always-on zerotier controller and core services
- **Dendritic + clan integration**: Proven working on NixOS
- **Infrastructure-as-code**: Fully declarative with terraform/terranix
- **Secure deployment**: LUKS encryption, clan vars management, encrypted terraform state
- **Ready for darwin**: Stable foundation for connecting darwin hosts in Phase 2+

**Key achievements**:
- VPS deployed declaratively with terraform
- Dendritic module organization with `flake.modules.*` namespace
- import-tree auto-discovery working
- Clan inventory managing multi-machine coordination
- Zerotier controller operational on always-on infrastructure
- SSH CA ready for certificate-based authentication
- Emergency access configured for all machines
- Proven patterns ready for darwin host migration
