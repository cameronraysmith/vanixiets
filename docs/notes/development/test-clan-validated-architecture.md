# test-clan Validated Architecture Map

**Generated**: 2025-11-11
**Branch**: phase-0-validation
**Status**: Stories 1.1-1.7 complete, validated through comprehensive test harness

This document maps the actual proven architecture in test-clan after Stories 1.1-1.7 completion.
All patterns documented here have been validated through the test harness (17 test cases) and proven working.

## Executive Summary

test-clan successfully validates the integration of:
- **Dendritic flake-parts** with pure import-tree auto-discovery (minimal flake.nix, zero manual imports)
- **clan-core** for multi-machine coordination and service orchestration
- **Terranix** for infrastructure-as-code provisioning (Hetzner Cloud)
- **Comprehensive test harness** with nix-unit, VM integration tests, and validation tests

## Repository Structure

```
test-clan/
├── flake.nix                       # Minimal flake with import-tree (65 lines)
├── justfile                        # Development task recipes
├── modules/                        # All .nix files auto-discovered
│   ├── clan/                       # Clan orchestration (4 files)
│   │   ├── core.nix                # Imports clan-core/terranix flakeModules
│   │   ├── meta.nix                # Clan metadata (name, tld, specialArgs)
│   │   ├── machines.nix            # Machine definitions (4 machines)
│   │   └── inventory/              # Service instances (2 files)
│   │       ├── machines.nix        # Machine inventory declarations
│   │       └── services/           # Service instance configs (4 services)
│   ├── terranix/                   # Terranix infrastructure (3 files)
│   │   ├── base.nix                # Base terranix config (providers, secrets)
│   │   ├── config.nix              # Terranix perSystem configuration
│   │   └── hetzner.nix             # Hetzner Cloud resources (toggle mechanism)
│   ├── system/                     # Base NixOS modules (auto-merged to base)
│   │   ├── admins.nix              # User accounts, SSH keys
│   │   ├── initrd-networking.nix   # Early boot networking
│   │   └── nix-settings.nix        # Nix daemon configuration
│   ├── darwin/                     # Darwin base modules (2 files)
│   │   ├── base.nix                # Darwin system baseline
│   │   └── users.nix               # Darwin user configuration
│   ├── machines/                   # Machine/home configurations
│   │   ├── nixos/                  # NixOS machines (3 machines)
│   │   │   ├── hetzner-ccx23/      # CCX23 (UEFI, systemd-boot, ZFS)
│   │   │   ├── hetzner-cx43/       # CX43 (BIOS, GRUB, ZFS)
│   │   │   └── gcp-vm/             # GCP VM (minimal config)
│   │   ├── darwin/                 # nix-darwin machines (1 test machine)
│   │   │   └── test-darwin/
│   │   └── home/                   # Future: home-manager configs
│   ├── checks/                     # Test suite modules (4 files)
│   │   ├── nix-unit.nix            # Expression evaluation tests (11 tests)
│   │   ├── integration.nix         # VM integration tests (2 tests, Linux-only)
│   │   ├── validation.nix          # Property validation tests (4 tests)
│   │   └── performance.nix         # Performance/CI tests (skeleton)
│   ├── dev-shell.nix               # Development environment
│   ├── flake-parts.nix             # Import flake modules (flake-parts.modules, nix-unit)
│   ├── formatting.nix              # Code formatting (treefmt)
│   ├── nixpkgs.nix                 # Nixpkgs configuration
│   └── systems.nix                 # Supported system architectures
├── machines/                       # Machine runtime data (facter.json)
├── sops/                           # Encrypted secrets (clan via sops-nix)
├── terraform/                      # Terraform state files
└── vars/                           # Variables (clan generated)
```

**File Count**:
- Total modules: 29 .nix files
- Flake.nix: 65 lines (minimal)
- Test suite: 17 test cases across 4 test modules

## 1. Flake Structure

### Inputs Configuration

```nix
inputs = {
  nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  
  flake-parts.url = "github:hercules-ci/flake-parts";
  flake-parts.inputs.nixpkgs-lib.follows = "nixpkgs";
  
  nix-darwin.url = "github:nix-darwin/nix-darwin";
  nix-darwin.inputs.nixpkgs.follows = "nixpkgs";
  
  home-manager.url = "github:nix-community/home-manager";
  home-manager.inputs.nixpkgs.follows = "nixpkgs";
  
  clan-core.url = "git+https://git.clan.lol/clan/clan-core";
  clan-core.inputs.nixpkgs.follows = "nixpkgs";
  clan-core.inputs.flake-parts.follows = "flake-parts";
  clan-core.inputs.treefmt-nix.follows = "treefmt-nix";
  clan-core.inputs.nix-darwin.follows = "nix-darwin";
  
  import-tree.url = "github:vic/import-tree";
  
  terranix.url = "github:terranix/terranix";
  terranix.inputs.flake-parts.follows = "flake-parts";
  terranix.inputs.nixpkgs.follows = "nixpkgs";
  
  disko.url = "github:nix-community/disko";
  disko.inputs.nixpkgs.follows = "nixpkgs";
  
  srvos.url = "github:nix-community/srvos";
  srvos.inputs.nixpkgs.follows = "nixpkgs";
  
  treefmt-nix.url = "github:numtide/treefmt-nix";
  treefmt-nix.inputs.nixpkgs.follows = "nixpkgs";
  
  git-hooks.url = "github:cachix/git-hooks.nix";
  git-hooks.inputs.nixpkgs.follows = "nixpkgs";
  
  nix-unit.url = "github:nix-community/nix-unit";
  nix-unit.inputs.nixpkgs.follows = "nixpkgs";
  nix-unit.inputs.flake-parts.follows = "flake-parts";
  nix-unit.inputs.treefmt-nix.follows = "treefmt-nix";
};
```

**Key Pattern**: All inputs use `follows` rules to prevent version conflicts.

### Flake Outputs (import-tree integration)

```nix
outputs = inputs@{ flake-parts, ... }:
  flake-parts.lib.mkFlake { inherit inputs; } (inputs.import-tree ./modules);
```

**Key Pattern**: Single line using import-tree for complete auto-discovery.
No manual imports, no explicit module lists - pure dendritic pattern.

## 2. Module Organization

### Dendritic Namespace Structure

Modules self-organize into namespaces via `flake.modules.<namespace>.<path>` pattern:

**Proven Namespaces**:
- `flake.modules.nixos.*` - NixOS modules (base, machines)
- `flake.modules.darwin.*` - Darwin modules (base, machines)
- `flake.modules.terranix.*` - Terranix modules (base, hetzner)

**Auto-Merging Pattern**: Multiple modules can export to the same namespace (e.g., `base`), and they're automatically merged.

### Base Module Auto-Merge Example

Three files all export to `flake.modules.nixos.base`:

```nix
# modules/system/admins.nix
{ flake.modules.nixos.base = { ... }: { users.users = {...}; }; }

# modules/system/nix-settings.nix
{ flake.modules.nixos.base = { ... }: { nix.settings = {...}; }; }

# modules/system/initrd-networking.nix
{ flake.modules.nixos.base = { ... }: { boot.initrd.network = {...}; }; }
```

**Result**: All three modules are automatically merged into a single `base` module without explicit imports.

### Machine Module Pattern

Machine configs export to namespaced paths and import base modules:

```nix
# modules/machines/nixos/hetzner-ccx23/default.nix
{ config, inputs, ... }:
{
  flake.modules.nixos."machines/nixos/hetzner-ccx23" = { lib, ... }: {
    imports = with config.flake.modules.nixos; [
      base
      inputs.srvos.nixosModules.server
      inputs.srvos.nixosModules.hardware-hetzner-cloud
    ];
    
    # Machine-specific configuration
    nixpkgs.hostPlatform = "x86_64-linux";
    networking.hostName = "hetzner-ccx23";
    
    # Disko disk configuration
    disko.devices = { ... };
    
    # Bootloader (UEFI + systemd-boot)
    boot.loader.systemd-boot.enable = true;
    # ...
  };
}
```

**Key Pattern**: 
- Export uses outer `config` to access `flake.modules.nixos`
- Inner module receives standard NixOS module args (`lib`, `pkgs`, etc.)
- Path-based naming: `"machines/nixos/hetzner-ccx23"` matches directory structure

## 3. Clan Integration

### Clan Core Import

```nix
# modules/clan/core.nix
{ inputs, ... }:
{
  imports = [
    inputs.clan-core.flakeModules.default
    inputs.terranix.flakeModule
  ];
}
```

**Key Pattern**: Central import point for both clan-core and terranix flakeModules.

### Clan Metadata

```nix
# modules/clan/meta.nix
{ inputs, ... }:
{
  clan = {
    meta.name = "test-clan";
    meta.description = "Phase 0: Architectural validation + infrastructure deployment";
    meta.tld = "clan";
    
    # Pass inputs to all machines via specialArgs
    specialArgs = { inherit inputs; };
  };
}
```

**Key Pattern**: `specialArgs` propagates inputs to all machine configurations.

### Machine Registration

```nix
# modules/clan/machines.nix
{ config, ... }:
{
  clan.machines = {
    hetzner-ccx23 = {
      imports = [ config.flake.modules.nixos."machines/nixos/hetzner-ccx23" ];
    };
    
    hetzner-cx43 = {
      imports = [ config.flake.modules.nixos."machines/nixos/hetzner-cx43" ];
    };
    
    gcp-vm = {
      imports = [ config.flake.modules.nixos."machines/nixos/gcp-vm" ];
    };
    
    test-darwin = {
      imports = [ config.flake.modules.darwin."machines/darwin/test-darwin" ];
    };
  };
}
```

**Key Pattern**: clan.machines references dendritic modules via `config.flake.modules.*`.

### Clan Inventory

```nix
# modules/clan/inventory/machines.nix
{
  clan.inventory.machines = {
    hetzner-ccx23 = {
      tags = [ "nixos" "cloud" "hetzner" ];
      machineClass = "nixos";
    };
    
    hetzner-cx43 = {
      tags = [ "nixos" "cloud" "hetzner" ];
      machineClass = "nixos";
    };
    
    gcp-vm = {
      tags = [ "nixos" "cloud" "gcp" ];
      machineClass = "nixos";
    };
    
    test-darwin = {
      tags = [ "darwin" "test" ];
      machineClass = "darwin";
    };
  };
}
```

**Key Pattern**: Inventory provides tags and machineClass for service targeting.

### Service Instances

```nix
# modules/clan/inventory/services/zerotier.nix
{
  clan.inventory.instances.zerotier = {
    module = {
      name = "zerotier";
      input = "clan-core";
    };
    roles.controller.machines."hetzner-ccx23" = { };
    roles.peer.tags."all" = { };
  };
}
```

**Service Instance Pattern**:
- `module`: Specifies clan-core service module
- `roles.<role>.machines.<name>`: Target specific machines
- `roles.<role>.tags.<tag>`: Target by inventory tags

**Available Services** (4 instances):
1. **zerotier**: VPN coordination (controller: hetzner-ccx23, peers: all)
2. **emergency-access**: SSH emergency access (all machines)
3. **tor**: Tor hidden service (all machines)
4. **users**: User management across fleet

## 4. Infrastructure Configuration (Terranix)

### Terranix perSystem Configuration

```nix
# modules/terranix/config.nix
{ self, ... }:
{
  perSystem = { inputs', pkgs, lib, config, ... }:
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
      terranix = {
        terranixConfigurations.terraform = {
          workdir = "terraform";
          modules = [
            self.modules.terranix.base
            self.modules.terranix.hetzner
          ];
          terraformWrapper.package = package;
          terraformWrapper.extraRuntimeInputs = [ inputs'.clan-core.packages.default ];
          terraformWrapper.prefixText = ''
            # Fetch passphrase from clan secrets
            TF_VAR_passphrase=$(clan secrets get tf-passphrase)
            export TF_VAR_passphrase
            
            # Configure OpenTofu state encryption
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
            export TF_ENCRYPTION
          '';
        };
      };
      
      # Override terranix-generated outputs to add metadata
      packages.terraform = lib.mkForce (
        config.terranix.terranixConfigurations.terraform.result.app.overrideAttrs (old: {
          meta = (old.meta or {}) // {
            description = "OpenTofu with Hetzner Cloud provider and encrypted state";
          };
        })
      );
    };
}
```

**Key Patterns**:
- OpenTofu with required Hetzner Cloud provider plugins
- State encryption using clan secrets (passphrase-based)
- Wrapper includes clan CLI for `clan machines install`
- Metadata override for package description

### Terranix Base Module

```nix
# modules/terranix/base.nix
{
  flake.modules.terranix.base = { config, pkgs, lib, ... }: {
    # Passphrase variable for OpenTofu state encryption
    variable.passphrase = { };
    
    # Required providers
    terraform.required_providers.external.source = "hashicorp/external";
    terraform.required_providers.hcloud.source = "hetznercloud/hcloud";
    
    # Fetch Hetzner API token from clan secrets
    data.external.hetzner-api-token = {
      program = [
        (lib.getExe (
          pkgs.writeShellApplication {
            name = "get-hetzner-secret";
            text = ''
              jq -n --arg secret "$(clan secrets get hetzner-api-token)" '{"secret":$secret}'
            '';
          }
        ))
      ];
    };
    
    # Configure Hetzner Cloud provider with secret
    provider.hcloud.token = config.data.external.hetzner-api-token "result.secret";
  };
}
```

**Key Patterns**:
- Secrets fetched at terraform runtime via `clan secrets get`
- External data source pattern for secret injection
- Provider credentials completely separated from code

### Terranix Hetzner Resources

```nix
# modules/terranix/hetzner.nix
{ ... }:
{
  flake.modules.terranix.hetzner = { config, lib, ... }:
    let
      machines = {
        hetzner-ccx23 = {
          enabled = false;  # Toggle for deployment
          serverType = "ccx23";
          location = "fsn1";
          image = "debian-12";
          comment = "4 vCPU, 16GB RAM, 160GB SSD, native UEFI";
        };
        hetzner-cx43 = {
          enabled = true;
          serverType = "cx43";
          location = "fsn1";
          image = "debian-12";
          comment = "8 vCPU, 16GB RAM, 160GB SSD, legacy BIOS";
        };
      };
      
      enabledMachines = lib.filterAttrs (_name: cfg: cfg.enabled) machines;
    in
    {
      terraform.required_providers.tls.source = "hashicorp/tls";
      terraform.required_providers.null.source = "hashicorp/null";
      
      # Generate ED25519 SSH key for terraform deployment
      resource.tls_private_key.ssh_deploy_key = {
        algorithm = "ED25519";
      };
      
      # Store private key locally for clan machines install
      resource.local_sensitive_file.ssh_deploy_key = {
        filename = "\${path.module}/.terraform-deploy-key";
        file_permission = "600";
        content = config.resource.tls_private_key.ssh_deploy_key "private_key_openssh";
      };
      
      # Register SSH key with Hetzner Cloud
      resource.hcloud_ssh_key.terraform = {
        name = "test-clan-terraform-deploy";
        public_key = config.resource.tls_private_key.ssh_deploy_key "public_key_openssh";
      };
      
      # Hetzner Cloud servers (generated from enabled machines)
      resource.hcloud_server = lib.mapAttrs (name: cfg: {
        inherit name;
        server_type = cfg.serverType;
        location = cfg.location;
        image = cfg.image;
        ssh_keys = [ (config.resource.hcloud_ssh_key.terraform "id") ];
      }) enabledMachines;
      
      # Provision NixOS via clan machines install
      resource.null_resource = lib.mapAttrs' (name: cfg:
        lib.nameValuePair "install-\${name}" {
          provisioner.local-exec = {
            command = "clan machines install \${name} --update-hardware-config nixos-facter --target-host root@\${
              config.resource.hcloud_server.\${name} "ipv4_address"
            } -i '\${config.resource.local_sensitive_file.ssh_deploy_key "filename"}' --yes";
          };
        }
      ) enabledMachines;
    };
}
```

**Toggle Mechanism**: Set `enabled = true/false` in machines definition to deploy/destroy.

**Key Patterns**:
- Dynamic resource generation via `lib.mapAttrs` over `enabledMachines`
- Ephemeral SSH key generation for deployment only
- `null_resource` provisioner calls `clan machines install` with generated IP

**Deployment Workflow**:
1. Edit `enabled` flags in Nix code
2. Run `clan vars generate` (first deployment only)
3. Run `nix run .#terraform` (regenerates config.tf.json and applies)

## 5. Test Harness

### Test Categories (17 test cases)

**Expression Evaluation (nix-unit.nix, 11 tests)**:
- TC-001: Terraform module exports exist
- TC-002: NixOS closure equivalence
- TC-003: Clan inventory structure
- TC-004: NixOS configurations exist
- TC-005: Darwin configurations exist
- TC-008: Dendritic module discovery
- TC-009: Darwin module discovery
- TC-010: Namespace exports
- TC-013: Module evaluation isolation
- TC-014: SpecialArgs propagation
- TC-015: Required NixOS options
- TC-016: Terranix required fields
- TC-021: Package metadata

**Integration Testing (integration.nix, 2 tests, Linux-only)**:
- VM test framework validation
- VM boot all machines

**Validation Testing (validation.nix, 4 tests)**:
- TC-006: Deployment safety analysis
- TC-007: Secrets generation capability
- TC-012: Terraform deep validation
- TC-017: Naming conventions (kebab-case)

### Test Execution Patterns

```bash
# Fast tests (~5s)
just test-quick
# Runs: nix-unit + validation tests

# Full test suite for current system (~11s)
just test
# Runs: fast tests + integration tests (if Linux)

# Integration tests only (~2-5min, Linux only)
just test-integration
# Runs: VM boot tests

# All systems (~49s)
nix flake check --all-systems
```

**Test Coverage**:
- Structural validation ✓
- Architectural constraints ✓
- Behavioral properties ✓
- Type-safety checks ✓
- Deployment safety ✓

## 6. Proven Patterns Summary

### 1. Dendritic Flake-Parts Pattern

**Minimal flake.nix** (65 lines):
```nix
outputs = inputs@{ flake-parts, ... }:
  flake-parts.lib.mkFlake { inherit inputs; } (inputs.import-tree ./modules);
```

**Module self-organization**:
- Modules export to `flake.modules.<namespace>.<path>`
- Multiple modules can merge into same namespace (e.g., `base`)
- No manual imports, no explicit module lists
- Pure auto-discovery via import-tree

### 2. Clan-Core Integration

**Three integration points**:
1. `modules/clan/core.nix`: Import clan-core flakeModule
2. `modules/clan/meta.nix`: Clan metadata + specialArgs
3. `modules/clan/machines.nix`: Machine registration (references dendritic modules)

**Inventory-driven services**:
- Service instances defined in `modules/clan/inventory/services/`
- Role-based targeting: by machine name OR by inventory tags
- Automatic secret/var generation for service instances

### 3. Terranix Infrastructure-as-Code

**Toggle-based deployment**:
- Edit `enabled = true/false` in Nix code
- Run `nix run .#terraform` to regenerate and apply
- No manual terraform commands needed

**Secrets integration**:
- Provider credentials via `clan secrets get` at runtime
- State encryption via passphrase from clan secrets
- Zero secrets in repository

**Provisioning workflow**:
- Terraform creates cloud VMs
- `null_resource` provisioner calls `clan machines install`
- NixOS deployed via clan CLI with disko disk partitioning

### 4. Machine Configuration Pattern

**Complete machine config** (hetzner-ccx23 example):
- Export to dendritic namespace: `flake.modules.nixos."machines/nixos/hetzner-ccx23"`
- Import base modules: `config.flake.modules.nixos.base`
- Import srvos modules: `inputs.srvos.nixosModules.{server,hardware-hetzner-cloud}`
- Disko disk configuration (UEFI or BIOS)
- Networking (systemd-networkd with DHCP)
- Hostname, stateVersion, platform

**Base module merging**:
- `system/admins.nix` + `system/nix-settings.nix` + `system/initrd-networking.nix`
- All export to `flake.modules.nixos.base`
- Automatically merged without explicit imports

### 5. Test-Driven Validation

**Three test frameworks**:
1. **nix-unit**: Expression evaluation (11 tests, ~1s)
2. **runNixOSTest**: VM integration (2 tests, ~2-5min, Linux-only)
3. **runCommand**: Validation/behavioral (4 tests, ~4s)

**Test properties**:
- Structural: Module exports, inventory structure, config existence
- Architectural: Dendritic discovery, namespace correctness, naming conventions
- Behavioral: Terraform validation, deployment safety, secrets generation
- Type-safety: Module isolation, specialArgs propagation, required fields

## 7. Machine Fleet

**Current machines** (4 total):

| Hostname | Type | Platform | Boot | Storage | Status |
|----------|------|----------|------|---------|--------|
| hetzner-ccx23 | NixOS VM | x86_64-linux | UEFI + systemd-boot | ZFS | enabled=false |
| hetzner-cx43 | NixOS VM | x86_64-linux | BIOS + GRUB | ZFS | enabled=true |
| gcp-vm | NixOS VM | x86_64-linux | TBD | TBD | Story 1.8 |
| test-darwin | nix-darwin | aarch64-darwin | N/A | N/A | Test only |

**Infrastructure providers**:
- Hetzner Cloud: hetzner-ccx23, hetzner-cx43 (terranix managed)
- GCP: gcp-vm (Story 1.8, terranix pattern TBD)

## 8. Key Files Reference

**Core integration** (6 files):
- `flake.nix`: Minimal flake with import-tree (65 lines)
- `modules/flake-parts.nix`: Import flake-parts.modules + nix-unit
- `modules/clan/core.nix`: Import clan-core + terranix flakeModules
- `modules/clan/meta.nix`: Clan metadata + specialArgs
- `modules/clan/machines.nix`: Machine registration
- `modules/terranix/config.nix`: Terranix perSystem configuration

**Machine configuration** (3 files):
- `modules/machines/nixos/hetzner-ccx23/default.nix`: UEFI + systemd-boot + ZFS
- `modules/machines/nixos/hetzner-cx43/default.nix`: BIOS + GRUB + ZFS
- `modules/machines/nixos/gcp-vm/default.nix`: Minimal GCP VM config

**Base modules** (3 files, auto-merged):
- `modules/system/admins.nix`: User accounts, SSH keys, sudo
- `modules/system/nix-settings.nix`: Nix daemon, experimental features
- `modules/system/initrd-networking.nix`: Early boot networking

**Infrastructure** (2 files):
- `modules/terranix/base.nix`: Providers, secrets integration
- `modules/terranix/hetzner.nix`: Hetzner Cloud resources, toggle mechanism

**Test suite** (4 files):
- `modules/checks/nix-unit.nix`: Expression evaluation (11 tests)
- `modules/checks/integration.nix`: VM integration (2 tests)
- `modules/checks/validation.nix`: Behavioral validation (4 tests)
- `modules/checks/performance.nix`: CI tests (skeleton)

## 9. Validation Status

**Stories 1.1-1.7 Complete**:
- ✓ Story 1.1: Repository preparation
- ✓ Story 1.2: Dendritic + clan validation
- ✓ Story 1.3: Clan inventory configuration
- ✓ Story 1.4: Hetzner terraform config
- ✓ Story 1.5: Hetzner VM deployment
- ✓ Story 1.6: Comprehensive test harness
- ✓ Story 1.7: Dendritic refactoring (pure import-tree)

**Stories 1.8-1.12 Pending**:
- Story 1.8: GCP VM deployment (multi-cloud validation)
- Story 1.9: Multi-machine coordination testing
- Story 1.10: One week stability monitoring
- Story 1.11: Integration findings documentation
- Story 1.12: GO/NO-GO decision framework

**Test Results**:
- All 17 test cases passing
- Fast tests: ~5s (nix-unit + validation)
- Full test suite: ~11s (includes integration on Linux)
- All systems check: ~49s (x86_64-linux, aarch64-linux, aarch64-darwin)

## 10. Next Steps for infra Migration

Once Epic 1 completes with GO decision (Story 1.12), migrate patterns to infra:

**Architecture patterns to migrate**:
1. Dendritic flake-parts with pure import-tree auto-discovery
2. Clan inventory for machine/service coordination
3. Terranix toggle-based deployment workflow
4. Base module auto-merge pattern
5. Test harness structure (nix-unit + integration + validation)

**Machine fleet to support**:
- nix-darwin: stibnite, blackphos, argentum, rosegold (4 laptops)
- nixos: cinnabar (permanent VPS), ephemeral-* (various)
- User identity: crs58 (forced on legacy), cameron (alias on new), multiple users

**Service coordination**:
- Zerotier VPN (cinnabar as controller)
- Emergency access across fleet
- User management (crs58, raquel, christophersmith, janettesmith)

## 11. Module System Architecture - Flake-Parts + Home-Manager Nesting

**Updated**: 2025-11-14 (Stories 1.10B, 1.10BA complete)
**Note**: Story 1.10BA validated structural Pattern A only; feature restoration deferred to Story 1.10D (depends on Story 1.10C clan vars infrastructure).

**Critical for all development:** This section explains the nested module system architecture that causes the most agent confusion. Read this FIRST before working with home-manager modules.

### The Fundamental Misunderstanding: Two Separate Module Systems

Most agent failures stem from confusing two SEPARATE, NESTED module systems. They are not the same, they are not merged, they are LAYERED.

```
┌─────────────────────────────────────────────────────────────┐
│ 1. FLAKE OUTPUTS (what `nix flake show` displays)           │
│    - Final build artifacts                                  │
│    - No `config`, no `flake.config`                         │
│                                                              │
│  ┌────────────────────────────────────────────────────┐     │
│  │ 2. FLAKE-PARTS MODULE SYSTEM (evaluation-time)     │     │
│  │    - Your dendritic modules ARE flake-parts modules│     │
│  │    - Access: config.flake.*, inputs.*              │     │
│  │    - Lives: modules/home/development/git.nix       │     │
│  │                                                     │     │
│  │  ┌──────────────────────────────────────────┐      │     │
│  │  │ 3. HOME-MANAGER MODULE SYSTEM (nested)   │      │     │
│  │  │    - The FUNCTION your dendritic defines │      │     │
│  │  │    - Access: config.*, pkgs.*, flake.*   │      │     │
│  │  │    - Lives: Return value of dendritic    │      │     │
│  │  └──────────────────────────────────────────┘      │     │
│  └────────────────────────────────────────────────────┘     │
└─────────────────────────────────────────────────────────────┘
```

### The Dendritic Pattern: A Nested Function

**What a dendritic module ACTUALLY is:**

```nix
# File: modules/home/development/git.nix
# ┌─ OUTER: This is a FLAKE-PARTS module
# │
{ config, inputs, ... }:  # ← Flake-parts module signature
{
  # Setting a flake-parts option
  flake.modules = {
    # ┌─ INNER: This VALUE is a HOME-MANAGER module
    # │
    homeManager.development =
      { config, pkgs, flake, ... }:  # ← DIFFERENT config!
      {
        programs.git = { ... };
      };
    # └─ END INNER
  };
}
# └─ END OUTER
```

**Two different `config` variables:**
- **Outer config:** Flake-parts module system state (`config.flake.*`, `inputs.*`)
- **Inner config:** Home-manager module system state (`config.programs.*`, `config.home.*`, `config.sops.*`)

**They are NOT the same object!**

### What `config.flake` Actually Contains (Flake-Parts Layer)

During flake-parts evaluation, `config.flake` contains the **options being set** by all flake-parts modules:

```nix
# In a flake-parts module
{ config, ... }:
{
  # What you CAN access:
  config.flake.packages.${system}.* = ...;        # ✓ Flake outputs being set
  config.flake.homeConfigurations.* = ...;        # ✓ Flake outputs being set
  config.flake.modules.homeManager.* = ...;       # ✓ Our dendritic modules

  # IF clan-core imported as flake-parts module:
  config.flake.config.clan.inventory.* = ...;     # ✓ Clan options
  config.flake.config.clan.core.vars.* = ...;     # ✓ Clan vars

  # What does NOT exist:
  config.flake.config.sops.* = ...;               # ✗ sops-nix is home-manager module
  config.flake.config.programs.* = ...;           # ✗ programs is home-manager option
  config.flake.pkgs.* = ...;                      # ✗ pkgs doesn't exist in flake
}
```

**Why this matters:** `config.flake` is the flake-parts options namespace, NOT the final flake outputs, and definitely NOT home-manager config.

### What `config` Contains (Home-Manager Layer)

In the **inner** home-manager module:

```nix
# The inner module (what dendritic modules DEFINE)
{ config, pkgs, flake, ... }:  # ← flake from extraSpecialArgs
{
  # What you CAN access:
  config.programs.* = ...;                        # ✓ Home-manager programs
  config.home.* = ...;                            # ✓ Home-manager home
  config.sops.* = ...;                            # ✓ IF sops-nix imported
  config.clan.core.vars.* = ...;                  # ✓ IF clan-core imported

  pkgs.git                                        # ✓ Nixpkgs packages
  flake.inputs.nix-ai-tools.* = ...;              # ✓ From extraSpecialArgs
  flake.config.clan.inventory.* = ...;            # ✓ From extraSpecialArgs

  # What does NOT exist:
  flake.config.sops.* = ...;                      # ✗ Wrong layer!
  flake.pkgs.* = ...;                             # ✗ Use pkgs, not flake.pkgs
  config.inputs.* = ...;                          # ✗ Use flake.inputs, not config.inputs
}
```

### The Bridge: extraSpecialArgs

**How the layers connect:**

```nix
# File: modules/home/configurations.nix (flake-parts module)
{ config, inputs, ... }:  # ← Flake-parts signature
{
  flake.homeConfigurations.crs58 =
    inputs.home-manager.lib.homeManagerConfiguration {
      # The bridge: Pass flake-parts config.flake to home-manager
      extraSpecialArgs = {
        flake = config.flake;  # ← Bridge from outer to inner!
      };

      modules = [
        config.flake.modules.homeManager.development
        # ...
      ];
    };
}
```

**What this does:** Makes `config.flake` from flake-parts available as `flake` parameter in home-manager modules.

**Result in home-manager modules:**
```nix
{ config, pkgs, flake, ... }:
{
  # flake.* = config.flake from flake-parts (the bridge)
  # config.* = home-manager config (separate system)
}
```

### Access Patterns Reference Table

**READ THIS BEFORE EVERY HOME-MANAGER MODULE IMPLEMENTATION:**

| What You Want | In Home-Manager Module | In Flake-Parts Module | Why |
|---------------|------------------------|----------------------|-----|
| Flake input package | `flake.inputs.X.packages.${pkgs.system}.Y` | `inputs.X.packages.${system}.Y` | Flake inputs passed via extraSpecialArgs |
| Nixpkgs package | `pkgs.git` | `inputs.nixpkgs.legacyPackages.${system}.git` | Home-manager provides `pkgs` automatically |
| Clan inventory user | `flake.config.clan.inventory.services.users.users.cameron` | `config.flake.config.clan.inventory.services.users.users.cameron` | Clan-core is flake-parts module |
| Clan vars secret | `config.clan.core.vars.generators.X.files.Y.path` | N/A (wrong layer) | Clan vars in home-manager if imported |
| Sops-nix secret | `config.sops.secrets."user/key".path` | N/A (wrong layer) | sops-nix is home-manager module |
| Another dendritic module | N/A (imported by configurations.nix) | `config.flake.modules.homeManager.shell` | Dendritic modules accessed in flake-parts layer |
| Home-manager option | `config.programs.git.userName` | N/A (wrong layer) | Home-manager config only in home-manager modules |

### Anti-Patterns - DO NOT USE THESE

**These patterns WILL fail. Do not try them:**

```nix
# In home-manager module:

# ✗ WRONG - sops-nix is home-manager module, not flake-parts
flake.config.sops.secrets.*

# ✗ WRONG - programs is home-manager option, not flake-parts
flake.config.programs.*

# ✗ WRONG - pkgs doesn't exist in flake
flake.pkgs.*

# ✗ WRONG - inputs doesn't exist in home-manager config
config.inputs.*

# ✗ WRONG - trying to import dendritic modules in home-manager
imports = [ flake.modules.homeManager.shell ];  # Causes recursion
```

### test-clan Specific Reality: Clan Vars, NOT sops-nix

**CRITICAL FACT:** test-clan uses clan vars for secrets management (NOT sops-nix for home-manager modules). After Story 1.10BA (structural Pattern A), Story 1.10C will migrate to clan vars, and Story 1.10D will enable features.

**Current State (Post-Story 1.10BA, 2025-11-14):**
- sops-nix: Machine/terraform secrets active (`sops/secrets/*-age.key`, `hetzner-api-token`), user/home-manager secrets DISABLED (commented pending migration)
- Clan vars: Infrastructure exists (`vars/shared/`, `vars/per-machine/`), home-manager integration PENDING Story 1.10C
- All secrets references in home-manager modules: COMMENTED OUT with Story 1.10C TODOs
- Story 1.10C will establish clan vars infrastructure for home-manager modules
- Story 1.10D will enable features (SSH signing, MCP API keys, GLM wrapper) using clan vars

**Proof:**
```bash
cd ~/projects/nix-workspace/test-clan
ls sops/         # Shows: secrets/ (machine keys), machines/, users/
ls vars/         # Shows: shared/ (user-password-cameron), per-machine/ (cinnabar, electrum, gcp-vm)
rg "sops.secrets" modules/home/     # All occurrences COMMENTED OUT
rg "clan.core.vars" modules/home/   # All occurrences COMMENTED OUT (Story 1.10C targets)
```

**Implications:**

```nix
# ✗ DOES NOT WORK in test-clan (no sops-nix)
config.sops.secrets."user/signing-key".path

# ✓ CORRECT for test-clan (clan vars, if configured)
config.clan.core.vars.generators.ssh-signing-key.files.ed25519_priv.path

# ✓ CORRECT for accessing clan inventory
flake.config.clan.inventory.services.users.users.cameron.name
```

**Why clan inventory works but sops doesn't:**
- Clan inventory (`flake.config.clan.inventory.*`): Clan-core IS a flake-parts module, so `config.flake.config.clan.*` exists
- Sops secrets (`config.sops.*`): sops-nix is a HOME-MANAGER module (if imported), exists in home-manager `config`, NOT in `flake.config`

### Pattern A Home-Manager Modules (Story 1.10BA Validated)

**Correct structure for dendritic home-manager modules:**

```nix
# File: modules/home/development/git.nix
{ ... }:  # Flake-parts module (outer)
{
  # CORRECT: Explicit braces pattern
  flake.modules = {
    homeManager.development =
      { pkgs, lib, flake, ... }:  # Home-manager module (inner)
      {
        programs.git = {
          package = pkgs.gitFull;  # ✓ Use pkgs for nixpkgs packages

          # ✓ Access flake inputs via extraSpecialArgs
          # signing.key = flake.inputs.sops-nix...;  # (if sops-nix used)

          # ✓ Access home-manager config
          userName = lib.mkDefault "Cameron Smith";
        };
      };
  };
}
```

**WRONG structure (causes errors):**

```nix
# ✗ WRONG - dot notation instead of explicit braces
flake.modules.homeManager.development =
  { pkgs, ... }:
  {
    programs.git = { ... };
  };
```

**Why explicit braces matter:** Dendritic import-tree requires the explicit `flake.modules = { ... }` structure for proper module merging during flake-parts evaluation.

### Diagnostic Questions for Access Patterns

**When you want to access something, ask these questions in order:**

**Q1: Is it a flake input?**
- ✅ YES → Use `flake.inputs.*` (via extraSpecialArgs in home-manager)

**Q2: Is it from a FLAKE-PARTS module (clan-core, custom flake-parts modules)?**
- ✅ YES → Use `flake.config.*` (via extraSpecialArgs in home-manager)
- Example: `flake.config.clan.inventory.*`

**Q3: Is it from a HOME-MANAGER module (sops-nix, catppuccin-nix.homeManagerModules)?**
- ✅ YES → Use `config.*` (home-manager config)
- Example: `config.sops.secrets.*`, `config.programs.*`

**Q4: Is it a nixpkgs package?**
- ✅ YES → Use `pkgs.*` (always available in home-manager)

**Q5: Is it another dendritic module?**
- ✅ In flake-parts layer: Use `config.flake.modules.homeManager.*`
- ❌ In home-manager layer: DO NOT import (already imported by configurations.nix)

### Verification Commands

**When in doubt, check what actually exists:**

```bash
# What's in flake outputs?
cd ~/projects/nix-workspace/test-clan
nix flake show
# Shows: packages, homeConfigurations, etc.
# Does NOT show: config, flake.config (evaluation-time only)

# What's available via extraSpecialArgs.flake?
# It's: config.flake from flake-parts
# Contains: inputs, modules, config.clan (if imported)
# Does NOT contain: sops, programs, home (those are home-manager)

# What modules are imported?
rg "imports.*clan-core" modules/
rg "imports.*sops-nix" modules/
# If sops-nix not found → config.sops.* doesn't exist
```

### Common Error Messages and Fixes

**Error: "attribute 'config' missing"**
```nix
# ✗ WRONG
programs.git.signing.key = flake.config.sops.secrets."user/key".path;

# ✓ CORRECT
programs.git.signing.key = config.sops.secrets."user/key".path;
# (But only if sops-nix is imported!)
```

**Error: "attribute 'sops' missing"**
```nix
# Check: Is sops-nix imported?
rg "sops-nix" modules/

# If NOT imported, don't try to use config.sops.*
# Use clan vars instead:
programs.git.signing.key = config.clan.core.vars.generators.ssh-key.files.*.path;
```

**Error: "infinite recursion"**
```nix
# ✗ WRONG - trying to import dendritic module in home-manager module
{ flake, ... }: {
  imports = [ flake.modules.homeManager.shell ];  # Recursion!
}

# ✓ CORRECT - import in configurations.nix (flake-parts layer)
{ config, ... }: {
  flake.homeConfigurations.user = homeManagerConfiguration {
    modules = [
      config.flake.modules.homeManager.development
      config.flake.modules.homeManager.shell  # Import here
    ];
  };
}
```

### Summary: The Two-Layer Mental Model

**Always remember:**

1. **Flake-parts layer (outer):** Where dendritic modules live
   - Access: `config.flake.*`, `inputs.*`
   - Purpose: Define what home-manager modules exist

2. **Home-manager layer (inner):** What dendritic modules return
   - Access: `config.*`, `pkgs.*`, `flake.*` (via extraSpecialArgs)
   - Purpose: Configure user environment

3. **The bridge:** `extraSpecialArgs.flake = config.flake`
   - Makes flake-parts data available in home-manager
   - Does NOT merge the two `config` objects

4. **Key insight:** `flake.config.*` only contains data from FLAKE-PARTS modules (like clan-core), NOT from home-manager modules (like sops-nix)

**When you write code, always know which layer you're in:**
- In a dendritic .nix file outer scope? → Flake-parts layer
- In the function returned by dendritic module? → Home-manager layer

## 12. Two-Tier Secrets Architecture - System vs User Secrets

**Added**: 2025-11-16 (Story 1.10C complete)
**Critical Discovery**: clan vars module incompatible with home-manager context

### The Problem: Clan Vars + Home-Manager Incompatibility

During Story 1.10C implementation (2025-11-15), we discovered a **critical architectural limitation**:

**clan vars module** (`clan-core.nixosModules.clanCore.vars`) is **NixOS-specific** and **cannot be imported** into home-manager modules.

**Evidence**:
- Zero reference repos use clan vars in home-manager modules (mic92, qubasa, pinpox, jfly, enzime, clan-infra, onix examined)
- Clan vars module expects `_class` parameter (NixOS/nix-darwin module system concept)
- Home-manager module system does NOT provide `_class` parameter
- Attempting to import clan vars in home-manager causes evaluation error: "attribute '_class' missing"

**Implication**: Clan vars designed for **SYSTEM-level** secrets (machine configuration), NOT **USER-level** secrets (home-manager).

### The Solution: Two-Tier Secrets Architecture

We validated a **two-tier architecture** that cleanly separates system secrets from user secrets:

```
┌─────────────────────────────────────────────────────────────────┐
│ TIER 1: System-Level Secrets (NixOS/nix-darwin)                │
│                                                                 │
│ Technology: clan vars                                           │
│ Scope:      Machine/system configuration                       │
│ Module:     clan-core.nixosModules.clanCore.vars               │
│ Storage:    vars/shared/, vars/per-machine/                    │
│ Access:     config.clan.core.vars.generators.*                 │
│                                                                 │
│ Use Cases:                                                      │
│   - Machine identity (user passwords, system SSH keys)         │
│   - System services (VPN credentials, API tokens for daemons)  │
│   - Infrastructure (Terraform tokens, DNS keys)                │
│   - Deployment automation (clan machines update)               │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│ TIER 2: User-Level Secrets (home-manager)                      │
│                                                                 │
│ Technology: sops-nix                                            │
│ Scope:      Per-user home-manager configuration                │
│ Module:     sops-nix.homeManagerModules.sops                   │
│ Storage:    secrets/home-manager/users/{user}/secrets.yaml     │
│ Access:     config.sops.secrets.*                              │
│                                                                 │
│ Use Cases:                                                      │
│   - Personal credentials (GitHub tokens, SSH signing keys)     │
│   - Development tools (API keys for AI services, MCP servers)  │
│   - Shell environment (atuin sync keys, bitwarden email)       │
│   - User-specific configs (git signing, ssh config)            │
└─────────────────────────────────────────────────────────────────┘
```

**Key Principle**: **Both tiers can use the SAME age keypair** (one per user), simplifying key management while maintaining architectural separation.

### Age Key Reuse Pattern

**ONE SSH keypair** (stored in Bitwarden) derives **ONE age keypair** used in **THREE contexts**:

1. **infra repository**: sops-nix home-manager (user's workstation `~/.config/sops/age/keys.txt`)
2. **clan user management**: Tier 1 system secrets (clan-core `sops/users/{user}/key.json`)
3. **test-clan repository**: sops-nix home-manager (Epic 1 validation, same pattern as infra)

**Workflow**:
```bash
# Source of truth: Bitwarden SSH key
bw get item "sops-admin-user-ssh"

# Derive age PUBLIC key (deterministic, one-way)
age_pub=$(bw get item "sops-admin-user-ssh" | jq -r '.sshKey.publicKey' | ssh-to-age)
# Output: age1vn8fpkmkzkjttcuc3prq3jrp7t5fsrdqey74ydu5p88keqmcupvs8jtmv8

# Use in THREE contexts:

# Context 1: clan user (for system-level clan vars)
clan secrets users add crs58 --age-key "$age_pub"
# Stores in: sops/users/crs58/key.json

# Context 2: sops-nix .sops.yaml (for user-level secrets)
# Add to .sops.yaml keys section:
#   - &crs58-user age1vn8fpkmkzkjttcuc3prq3jrp7t5fsrdqey74ydu5p88keqmcupvs8jtmv8

# Context 3: User's workstation age private key
age_priv=$(bw get item "sops-admin-user-ssh" | jq -r '.sshKey.privateKey' | ssh-to-age -private-key)
echo "$age_priv" >> ~/.config/sops/age/keys.txt
```

**Validation** (ensure correspondence across all three contexts):
```bash
# Extract from each context
clan_age=$(jq -r '.[0].publickey' sops/users/crs58/key.json)
yaml_age=$(grep "crs58-user" .sops.yaml | awk '{print $NF}')
work_age=$(age-keygen -y < <(grep "AGE-SECRET-KEY" ~/.config/sops/age/keys.txt | tail -1))

# Verify all match
if [ "$clan_age" = "$yaml_age" ] && [ "$yaml_age" = "$work_age" ]; then
  echo "✅ Age keys correspond across all contexts"
else
  echo "❌ CRITICAL: Age key mismatch!"
fi
```

**Benefit**: Single key management burden, multiple usage contexts. User generates ONE SSH key in Bitwarden → derives ONE age key → uses everywhere.

### sops-nix Home-Manager Integration Patterns

Story 1.10C validated **three production-ready patterns** for sops-nix in home-manager:

#### Pattern 1: Direct Secret Path Access

**Use case**: Simple path reference to decrypted secret

**Example** (git.nix):
```nix
{ config, ... }: {
  programs.git.signing.key = config.sops.secrets.ssh-signing-key.path;
  # Path resolves to: /run/user/501/secrets.d/ssh-signing-key (macOS)
  # Path resolves to: /run/user/1000/secrets.d/ssh-signing-key (Linux)
}
```

**Deployment**: sops-nix creates symlink at `config.sops.secrets.{name}.path` pointing to runtime secrets directory.

#### Pattern 2: sops.templates for Config File Generation

**Use case**: Generate entire config file with secret placeholders

**Example** (mcp-servers.nix):
```nix
{ config, pkgs, ... }: {
  sops.templates."mcp-firecrawl" = {
    mode = "0400";
    path = "${config.xdg.configHome}/claude-code/mcp-servers/firecrawl.json";
    content = ''
      {
        "mcpServers": {
          "firecrawl": {
            "command": "${pkgs.npx}/bin/npx",
            "args": ["-y", "@mendable/firecrawl-mcp-server"],
            "env": {
              "FIRECRAWL_API_KEY": "${config.sops.placeholder."firecrawl-api-key"}"
            }
          }
        }
      }
    '';
  };
}
```

**Advantages**:
- **Security**: Secret never exposed in process arguments (unlike environment variables)
- **Atomic**: Config file generated with secrets already populated
- **Clean**: No activation scripts needed, declarative

**How it works**:
1. sops-nix creates template file at specified path
2. `sops.placeholder."secret-name"` replaced with actual secret value from decrypted secrets file
3. File permissions set per `mode` specification
4. File atomically written during home-manager activation

#### Pattern 3: Activation Script with Symlinks

**Use case**: Deploy secret to location expected by external tool

**Example** (atuin.nix):
```nix
{ config, ... }: {
  home.activation.deployAtuinKey = ''
    $DRY_RUN_CMD mkdir -p ${config.xdg.configHome}/atuin
    $DRY_RUN_CMD ln -sf \
      ${config.sops.secrets.atuin-key.path} \
      ${config.xdg.configHome}/atuin/key
  '';
}
```

**Use when**: External tool expects secret at specific hardcoded path not configurable via config file.

**Caution**: Activation scripts run at every `home-manager switch`, idempotency required.

### Multi-User Encryption and Isolation

sops-nix supports **per-user secret files** with **multi-user encryption** via `.sops.yaml` creation rules:

**Example** (.sops.yaml):
```yaml
keys:
  - &admin age1vy7wsnf8eg5229evq3ywup285jzk9cntsx5hhddjtwsjh0kf4c6s9fmalv
  - &crs58-user age1vn8fpkmkzkjttcuc3prq3jrp7t5fsrdqey74ydu5p88keqmcupvs8jtmv8
  - &raquel-user age12w0rmmskrds6m334w7qrcmpms5lpe3llah6wf8ry5jtatvuxku2sarl8ut

creation_rules:
  # crs58/cameron: 8 secrets (development + ai + shell aggregates)
  - path_regex: secrets/home-manager/users/crs58/.*\.yaml$
    key_groups:
      - age: [*admin, *crs58-user]

  # raquel: 5 secrets (development + shell, no ai aggregate)
  - path_regex: secrets/home-manager/users/raquel/.*\.yaml$
    key_groups:
      - age: [*admin, *raquel-user]
```

**Security properties**:
- crs58 can decrypt ONLY crs58's secrets (requires crs58-user private key)
- raquel can decrypt ONLY raquel's secrets (requires raquel-user private key)
- admin can decrypt ALL secrets (recovery/ops key)
- Secrets file paths enforce isolation: `secrets/home-manager/users/{user}/secrets.yaml`

**Module pattern** (per-user sops configuration):
```nix
# modules/home/users/crs58/default.nix
{ flake, ... }: {
  flake.modules.homeManager."users/crs58" = { config, flake, ... }: {
    sops = {
      defaultSopsFile = flake.inputs.self + "/secrets/home-manager/users/crs58/secrets.yaml";
      secrets = {
        github-token = { };
        ssh-signing-key = { mode = "0400"; };
        ssh-public-key = { };  # For allowed_signers template
        glm-api-key = { };
        firecrawl-api-key = { };
        huggingface-token = { };
        bitwarden-email = { };
        atuin-key = { };
      };
    };
  };
}
```

**Aggregate pattern** (user imports aggregates, secrets flow through):
```nix
# User modules import aggregates
modules/home/users/crs58/  → imports development, ai, shell aggregates
modules/home/users/raquel/ → imports development, shell aggregates (NO ai)

# Aggregates access secrets conditionally
modules/home/ai/claude-code/mcp-servers.nix:
  # Only works for users who import ai aggregate + have secrets defined
  sops.templates."mcp-firecrawl" = {
    content = ''... ${config.sops.placeholder."firecrawl-api-key"} ...''
  };
```

**Result**: Secret declarations in user module + aggregate imports = scoped access.

### Implementation Evidence (Story 1.10C)

**Code locations** (test-clan repository):
- `.sops.yaml`: Multi-user encryption rules (lines 1-23)
- `modules/home/base/sops.nix`: Base sops-nix module (imports sops-nix, sets age.keyFile)
- `modules/home/users/crs58/default.nix`: crs58 sops secrets (8 secrets declared, sops.templates for allowed_signers)
- `modules/home/users/raquel/default.nix`: raquel sops secrets (5 secrets declared)
- `modules/home/development/git.nix`: Pattern 1 (direct path access for signing.key)
- `modules/home/ai/claude-code/mcp-servers.nix`: Pattern 2 (sops.templates for Firecrawl, HuggingFace)
- `modules/home/shell/atuin.nix`: Pattern 3 (activation script symlink)
- `modules/home/shell/rbw.nix`: Pattern 2 (sops.templates for rbw config.json)

**Build validation** (AC16, 2025-11-16):
```bash
# All builds PASSED
nix build .#darwinConfigurations.blackphos.system --no-link  # ✅ SUCCESS
nix build .#homeConfigurations.aarch64-darwin.crs58.activationPackage --no-link  # ✅ SUCCESS
nix build .#homeConfigurations.aarch64-darwin.raquel.activationPackage --no-link  # ✅ SUCCESS
```

**Security validation**:
- Zero private keys committed to repository (AGE-SECRET-KEY, BEGIN PRIVATE KEY) ✅
- All secrets files encrypted (ASCII text format, sops-encrypted) ✅
- `.gitignore` excludes `~/.config/sops/age/keys.txt` ✅

### Architectural Lessons for Epic 2-6

**What worked**:
1. **Two-tier separation**: Clean boundary between system (clan vars) and user (sops-nix) secrets
2. **Age key reuse**: Single keypair works for both tiers (simpler management)
3. **sops.templates pattern**: Exceeds expectations, production-ready for Epic 2-6
4. **Multi-user isolation**: Separate secrets files prevent cross-user access
5. **Pattern A compatibility**: sops-nix works seamlessly with dendritic flake-parts modules

**What didn't work**:
1. **Clan vars in home-manager**: Technical impossibility due to `_class` parameter requirement
2. **Shared secrets file**: Attempted initially, abandoned for per-user files (better isolation)

**Epic 2-6 migration readiness**:
- **Pattern validated**: test-clan proves sops-nix + Pattern A works at scale (2 users, 8+5 secrets)
- **Documentation complete**: Age key management guide (`test-clan/docs/guides/age-key-management.md`)
- **Onboarding workflow**: Step-by-step process for adding new users (Bitwarden → age keys → clan → sops-nix)
- **Multi-machine ready**: Same pattern replicates across 6 machines (4 darwin + 2 NixOS)

**Critical dependencies**:
- Bitwarden as source of truth (SSH keys stored in vault)
- `bw` CLI for age key derivation (`ssh-to-age` tool)
- `~/.config/sops/age/keys.txt` on every user's workstation
- `.sops.yaml` creation rules per repository
- Encrypted secrets files per user in repository

### Diagnostic Questions

When implementing secrets in home-manager modules, ask:

**Q1: Is this a system-level secret or user-level secret?**
- System (machine identity, system services) → Use clan vars (NixOS/darwin module)
- User (personal credentials, dev tools) → Use sops-nix (home-manager module)

**Q2: Am I in a home-manager module context?**
- YES → Use sops-nix (`config.sops.secrets.*`)
- NO (NixOS/darwin system module) → Use clan vars (`config.clan.core.vars.*`)

**Q3: Do I need to generate a config file with secrets?**
- YES → Use sops.templates pattern (Pattern 2)
- NO (just need secret path) → Use direct path access (Pattern 1)

**Q4: Does the tool expect secret at specific hardcoded path?**
- YES → Use activation script symlink (Pattern 3)
- NO → Use sops.templates or direct path

**Q5: Is the secret shared across multiple users?**
- YES → Create shared secrets file with multi-user encryption rule
- NO → Use per-user secrets file (recommended for isolation)

### Quick Reference

**Tier 1 (System Secrets - clan vars)**:
```nix
# In NixOS/darwin module
{ config, ... }: {
  # Declare generator
  clan.core.vars.generators.user-password-cameron = {
    files."password.txt".secret = true;
    script = ''mkpasswd -m bcrypt > "$facts/password.txt"'';
  };

  # Access secret
  users.users.cameron.hashedPasswordFile =
    config.clan.core.vars.generators.user-password-cameron.files."password.txt".path;
}
```

**Tier 2 (User Secrets - sops-nix)**:
```nix
# In home-manager module
{ config, flake, ... }: {
  sops = {
    defaultSopsFile = flake.inputs.self + "/secrets/home-manager/users/crs58/secrets.yaml";
    secrets.github-token = { };
  };

  # Pattern 1: Direct path access
  programs.git.extraConfig.credential.helper =
    "!f() { echo \"password=$(cat ${config.sops.secrets.github-token.path})\"; }; f";

  # Pattern 2: sops.templates
  sops.templates."config.json" = {
    content = ''{"token": "${config.sops.placeholder."github-token"}"}''
    path = "${config.xdg.configHome}/app/config.json";
  };
}
```

**Age key correspondence validation**:
```bash
# Ensure same age public key in all three contexts
jq -r '.[0].publickey' sops/users/crs58/key.json  # Clan
grep "crs58-user" .sops.yaml | awk '{print $NF}'  # sops-nix
age-keygen -y < <(grep "AGE-SECRET-KEY" ~/.config/sops/age/keys.txt | tail -1)  # Workstation
```

## References

- **test-clan README**: `~/projects/nix-workspace/test-clan/README.md`
- **PRD**: `~/projects/nix-workspace/infra/docs/notes/development/PRD.md`
- **Epic breakdown**: `~/projects/nix-workspace/infra/docs/notes/development/epics.md`
- **Sprint status**: `~/projects/nix-workspace/infra/docs/notes/development/sprint-status.yaml`
- **Terranix pattern**: `~/projects/nix-workspace/infra/docs/notes/implementation/clan-infra-terranix-pattern.md`
- **Story 1.10BA work item**: `~/projects/nix-workspace/infra/docs/notes/development/work-items/1-10BA-refactor-pattern-a.md` (Pattern A validation)
