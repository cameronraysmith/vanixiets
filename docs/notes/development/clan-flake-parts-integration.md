# Clan-Core Inventory + Flake-Parts Integration: Complete Research Report

## Executive Summary

Clan-core's inventory system integrates with flake-parts through a sophisticated two-phase package instantiation and module composition system. Crucially, **nixpkgs gets instantiated in two separate phases**: pre-configuration (module.nix:35-41) and post-configuration (module.nix:95-111), with machine configuration (nixpkgs.config) applied between them.

---

## Critical Finding: Two-Phase Nixpkgs Instantiation

### Phase A: Pre-Configuration (module.nix:35-41)
```nix
pkgsFor = lib.genAttrs supportedSystems (
  system:
  let
    pkgs = pkgsForSystem system;
  in
  if pkgs != null then pkgs else nixpkgs.legacyPackages.${system}
);
```

**When**: Evaluated early, during `clan/module.nix` execution, BEFORE machine modules
**What**: Creates pre-instantiated nixpkgs for each supported system WITHOUT any module configuration
**Why**: Performance optimization - avoids multiple nixpkgs instantiations per system
**Key Point**: `pkgsForSystem` is called **once per system**, not per machine

### Phase B: Post-Configuration (module.nix:95-111)
```nix
configsPerSystem = builtins.listToAttrs (
  builtins.map (system:
    lib.nameValuePair system (
      lib.mapAttrs (_: machine:
        machine.extendModules {
          modules = [
            (lib.modules.importApply overridePkgs.nix {
              pkgs = pkgsFor.${system};
            })
          ];
        }
      ) configurations
    )
  ) supportedSystems
);
```

**When**: Evaluated AFTER machine configurations exist (post nixosSystem/darwinSystem evaluation)
**What**: Injects overridePkgs module into each machine's configuration
**Why**: Needed for vars/secrets generation which require consistent pkgs
**Key Point**: `overridePkgs.nix` forces nixpkgs.pkgs and nixpkgs.hostPlatform with mkForce

---

## Where nixpkgs.config Gets Applied

### CORRECT: Machine Module Level
```nix
# In clan.machines.name or imported module
{
  nixpkgs.config.allowUnfree = true;
  nixpkgs.config.allowUnfreePredicate = pkg: ...;
  nixpkgs.overlays = [ ... ];
}
```

**Works Because**:
1. nixosSystem/darwinSystem is called with moduleForMachine (line 57-65)
2. Module evaluation happens INSIDE nixosSystem/darwinSystem
3. At this point, nixpkgs.config is available in the module system
4. Later injection of overridePkgs doesn't interfere (it only forces pkgs/hostPlatform)

### INCORRECT: Inventory Level
```nix
# This does NOT exist and won't work
clan.inventory.machines.X.nixpkgs.config = { allowUnfree = true; };
```

**Why Not**:
1. `clan.inventory.machines.*` only supports: machineClass, tags, deploy info
2. Inventory is metadata layer, not configuration
3. No options for nixpkgs configuration

### NOT SUPPORTED: Service/Instance Level
```nix
# This is NOT supported
clan.inventory.instances.serviceName.roles.roleName.nixpkgs = {...};
```

**Why Not**:
1. Services/instances inject settings into machine configs, not pkgs configuration
2. Would require per-role nixpkgs instantiation (defeats optimization)

---

## Complete Evaluation Flow Diagram

```
┌─────────────────────────────────────────────────────────────────────────────┐
│ 1. FLAKE-PARTS INITIALIZATION                                              │
│    - User's flake.nix imports clan-core.flakeModules.default               │
│    - flake-parts loads clan.nix which imports clan/default.nix             │
│    - clan/default.nix imports: top-level-interface.nix, module.nix, etc.   │
└─────────────────────────────────────────────────────────────────────────────┘
                                    ↓
┌─────────────────────────────────────────────────────────────────────────────┐
│ 2. USER CONFIGURATION                                                       │
│    User provides:                                                           │
│    - clan.inventory.machines.X { machineClass, tags, ... }                 │
│    - clan.machines.X { imports, nixpkgs.config, ... }                      │
│    - clan.pkgsForSystem (optional, defaults to null)                       │
└─────────────────────────────────────────────────────────────────────────────┘
                                    ↓
┌─────────────────────────────────────────────────────────────────────────────┐
│ 3. INVENTORY RESOLUTION (module.nix:118-145)                                │
│    - Load from:                                                             │
│      1. $directory/inventory.json (if exists)                              │
│      2. $directory/machines/* (auto-discovered)                            │
│      3. clan.machines (user-defined)                                       │
│    - Result: config.clanInternals.inventoryClass.machines                  │
│    - Contains: { machineA: {machineClass: "nixos", ...}, ... }            │
└─────────────────────────────────────────────────────────────────────────────┘
                                    ↓
┌─────────────────────────────────────────────────────────────────────────────┐
│ 4a. PHASE A: PRE-CONFIGURATION NIXPKGS INSTANTIATION (line 35-41)          │
│     ┌───────────────────────────────────────────────────────────────────┐  │
│     │ pkgsFor = lib.genAttrs supportedSystems (system:                  │  │
│     │   let pkgs = pkgsForSystem system                                 │  │
│     │   in if pkgs != null then pkgs                                    │  │
│     │      else nixpkgs.legacyPackages.${system}                        │  │
│     │ )                                                                 │  │
│     └───────────────────────────────────────────────────────────────────┘  │
│                                                                             │
│    Result: Pre-instantiated nixpkgs for each system WITHOUT config         │
│    Key: pkgsForSystem called ONCE per system, not per machine              │
└─────────────────────────────────────────────────────────────────────────────┘
                                    ↓
┌─────────────────────────────────────────────────────────────────────────────┐
│ 4b. MODULE COMPOSITION (line 159-206)                                       │
│     outputs.moduleForMachine = lib.mkMerge [                                │
│       # Generated from inventory (forName.nix + clanCore modules)           │
│       (lib.mapAttrs (name: v: { ... }) inventoryMachines)                   │
│       # User-provided machine configuration                                 │
│       config.machines  # <- clan.machines.*                                 │
│     ]                                                                       │
│                                                                             │
│    Result: Per-machine module with nixpkgs.config available                │
└─────────────────────────────────────────────────────────────────────────────┘
                                    ↓
┌─────────────────────────────────────────────────────────────────────────────┐
│ 5. CONFIGURATION GENERATION (line 55-66)                                    │
│                                                                             │
│    configurations = lib.mapAttrs (name: _:                                  │
│      moduleSystemConstructor.${machineClasses.${name}} {                    │
│        modules = [ (config.outputs.moduleForMachine.${name}) ];             │
│        specialArgs = { inherit clan-core; } // specialArgs;                 │
│      }                                                                      │
│    ) allMachines                                                            │
│                                                                             │
│    CRITICAL: This is where nixosSystem/darwinSystem evaluates modules      │
│    At this point: nixpkgs.config from machine module IS AVAILABLE         │
│    But: pkgs come from pre-instantiated pkgsFor (no config applied)        │
└─────────────────────────────────────────────────────────────────────────────┘
                                    ↓
┌─────────────────────────────────────────────────────────────────────────────┐
│ 4c. PHASE B: POST-CONFIGURATION OVERRIDE (line 95-111)                      │
│     ┌───────────────────────────────────────────────────────────────────┐  │
│     │ configsPerSystem = builtins.listToAttrs (                          │  │
│     │   builtins.map (system:                                           │  │
│     │     lib.mapAttrs (_: machine:                                      │  │
│     │       machine.extendModules {                                      │  │
│     │         modules = [                                                │  │
│     │           importApply overridePkgs.nix { pkgs = pkgsFor.${sys} }  │  │
│     │         ]                                                          │  │
│     │       }                                                            │  │
│     │     ) configurations                                               │  │
│     │   ) supportedSystems                                               │  │
│     │ )                                                                  │  │
│     └───────────────────────────────────────────────────────────────────┘  │
│                                                                             │
│    Effect: Inject overridePkgs module AFTER all modules evaluated         │
│    overridePkgs forces:                                                    │
│    - nixpkgs.pkgs = pkgsFor.${system}  (mkForce)                           │
│    - nixpkgs.hostPlatform = system     (mkForce)                           │
│                                                                             │
│    Used for: vars/secrets generation that need consistent pkgs             │
└─────────────────────────────────────────────────────────────────────────────┘
                                    ↓
┌─────────────────────────────────────────────────────────────────────────────┐
│ 6. OUTPUT MAPPING                                                           │
│    - nixosConfigurations.<name> → configurations                            │
│    - darwinConfigurations.<name> → configurations                           │
│    - nixosModules.<name> → moduleForMachine (for reuse)                     │
│    - darwinModules.<name> → moduleForMachine (for reuse)                    │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## Role Configuration (inventory.instances.*.roles)

inventory.instances (formerly services) define multi-host services via roles:

```nix
clan.inventory.instances.myservice = {
  module.name = "myservice";  # or module.input = "external-flake"
  roles = {
    server = {
      machines = { machine1 = {}; };
      tags = [ "servers" ];
    };
    client = {
      tags = [ "clients" ];
    };
  };
};
```

**Role Configuration Structure** (from role.nix):
- `machines`: Explicit machine membership
- `tags`: Tag-based membership resolution
- `settings`: Module settings for this role (serializable)
- `extraModules`: Additional .nix files to import (if machine in role)

**Critical**: roles do NOT have nixpkgs configuration options
- Services are composed INTO machine configs
- But nixpkgs config must be set at machine level

---

## Dendritic Flake-Parts Integration Pattern

When using dendritic flake-parts (import-tree):

```
flake.nix outputs = inputs.flake-parts.lib.mkFlake (inputs.import-tree ./flake-modules)

flake-modules/
├── clan/
│   ├── core.nix (imports clan-core.flakeModules.default)
│   ├── machines.nix
│   │   clan.machines = {
│   │     machine1 = { imports = [ config.flake.modules.nixos."machines/nixos/machine1" ]; };
│   │   };
│   ├── inventory/
│   │   └── machines.nix
│   │       clan.inventory.machines = { machine1 = { machineClass = "nixos"; ... }; };
│   └── machines/
│       └── nixos/
│           └── machine1.nix (exports config.flake.modules.nixos."machines/nixos/machine1")
│
└── modules/
    ├── nixos/
    │   └── base.nix, etc.
    └── nixpkgs.nix (overlay layers)
```

**Flow**:
1. clan/machines.nix imports config.flake.modules.nixos."machines/nixos/machine1"
2. That module defines nixpkgs.config, nixpkgs.overlays, etc.
3. Gets merged into clan.machines.machine1
4. Merged into moduleForMachine via lib.mkMerge
5. Passed to nixosSystem

---

## Test-Clan Reference: Complete Working Example

**Setup**:
```nix
# flake.nix
inputs = {
  clan-core.url = "...";
  clan-core.inputs.nixpkgs.follows = "nixpkgs";
};
outputs = inputs: inputs.flake-parts.lib.mkFlake { inherit inputs; } 
  (inputs.import-tree ./modules);

# modules/clan/core.nix
{ inputs, ... }: {
  imports = [ inputs.clan-core.flakeModules.default ];
}

# modules/clan/machines.nix
{ config, ... }: {
  clan.machines = {
    cinnabar = {
      imports = [ config.flake.modules.nixos."machines/nixos/cinnabar" ];
    };
  };
}

# modules/clan/inventory/machines.nix
{ ... }: {
  clan.inventory.machines = {
    cinnabar = {
      machineClass = "nixos";
      tags = [ "nixos" "cloud" "hetzner" ];
    };
  };
}

# modules/machines/nixos/cinnabar.nix (in flake-modules)
{ config, ... }: {
  flake.modules.nixos."machines/nixos/cinnabar" = { lib, ... }: {
    imports = [ config.flake.modules.nixos.base ];
    
    # CRITICAL: nixpkgs.config set at machine module level
    nixpkgs.config.allowUnfreePredicate = pkg:
      builtins.elem (lib.getName pkg) [ "graphite-cli" "ngrok" ];
    
    # Overlays applied here
    nixpkgs.overlays = [ inputs.self.overlays.default ];
    
    # Machine configuration
    networking.hostName = "cinnabar";
    system.stateVersion = "25.05";
  };
}
```

---

## Key Insights for Infra Repository

### 1. Inventory and Configuration Separation
- **Inventory** (machines.nix): Metadata only (machineClass, tags, deploy info)
- **Configuration** (clan.machines or module files): Actual system config + nixpkgs options

### 2. Where to Set nixpkgs.config
**Option A: Direct in clan.machines**
```nix
clan.machines.myhost = {
  nixpkgs.config.allowUnfree = true;
  # ... rest of config
};
```

**Option B: Via dendritic module imports (recommended)**
```nix
# In flake-modules/machines/nixos/myhost.nix
flake.modules.nixos."machines/nixos/myhost" = { ... }: {
  nixpkgs.config = { allowUnfree = true; };
  # ... rest of config
};

# In clan/machines.nix
clan.machines.myhost = {
  imports = [ config.flake.modules.nixos."machines/nixos/myhost" ];
};
```

### 3. pkgsForSystem Option
If you want custom nixpkgs instantiation:
```nix
# In top-level clan config
clan.pkgsForSystem = system:
  if system == "x86_64-linux" then
    customNixpkgs.legacyPackages.x86_64-linux
  else
    null;  # fallback to default
```

### 4. Machine-Specific Package Configuration
All pkgs.config options work at machine module level:
```nix
{ ... }: {
  nixpkgs.config = {
    allowUnfree = true;
    allowUnfreePredicate = pkg: ...;
    allowBroken = true;
    # Any other nixpkgs.config option
  };
}
```

### 5. Overlays and Module Composition
Overlays can be set in multiple places and will merge:
```nix
# Machine module
nixpkgs.overlays = [ 
  inputs.self.overlays.machines.custom
];

# Base module
nixpkgs.overlays = [ 
  inputs.self.overlays.default
];
# Result: both applied via mkMerge
```

---

## Answers to Critical Questions

### Q1: How does clan.inventory.machines work with flake-parts?
**A**: It doesn't directly. Inventory defines metadata (machineClass, tags). Configuration comes from clan.machines which is imported into flake.clan via the flake-parts clan module. They are separate concerns merged together.

### Q2: When does clan-core apply overridePkgs?
**A**: AFTER nixosSystem/darwinSystem evaluation (Phase B, line 95-111). It injects the overridePkgs module via extendModules to ensure consistent pkgs for vars/secrets generation.

### Q3: Where in the evaluation chain does nixpkgs instantiation happen?
**A**: 
- **Phase A (Pre-config)**: module.nix:35-41, called once per system, creates pkgsFor
- **Phase B (Post-config)**: module.nix:95-111, injects overridePkgs with pre-instantiated pkgs
- **Module evaluation**: Inside nixosSystem/darwinSystem, where nixpkgs.config is available

### Q4: What's the role of clan.inventory.instances vs machines?
**A**:
- **machines**: System identity (machineClass, tags, deploy info)
- **instances**: Multi-host services applied TO machines (via roles)
- Neither has nixpkgs configuration

### Q5: How does clan-core expect to receive machine configurations?
**A**: Via clan.machines.* which gets merged into moduleForMachine. Can come from:
- Direct definition in clan.machines
- Via imports from flake.modules (dendritic pattern)
- From filesystem (clan/machines/$name/)

### Q6: Are there clan-specific flake-parts options?
**A**: Yes, clan option at top level with many sub-options:
- clan.inventory (machines, instances, tags, etc.)
- clan.machines (per-machine config modules)
- clan.pkgsForSystem (custom package instantiation)
- clan.specialArgs (passed to all machines)
- clan.modules, clan.templates, clan.secrets, etc.

### Q7: Can services set nixpkgs.config?
**A**: No. Services (inventory.instances) define roles that apply settings to machines, but not nixpkgs configuration. That must be at the machine level.

---

## File Reference

| File | Purpose |
|------|---------|
| clan-core/flakeModules/clan.nix | flake-parts integration entry point |
| clan-core/modules/clan/default.nix | Clan module root with imports |
| clan-core/modules/clan/module.nix | **CRITICAL**: package instantiation + module composition |
| clan-core/modules/clan/top-level-interface.nix | Clan option definitions |
| clan-core/modules/inventoryClass/inventory.nix | Inventory schema (machines, instances, tags) |
| clan-core/modules/inventoryClass/role.nix | Role configuration within instances |
| clan-core/modules/clan/distributed-services.nix | Service/instance composition logic |
| clan-core/nixosModules/machineModules/overridePkgs.nix | **CRITICAL**: Post-config pkgs injection |
| clan-core/nixosModules/machineModules/forName.nix | Per-machine module generator |

---

## Validation: Test-Clan Examples

✅ **Works**: Setting nixpkgs.config in machine module (cinnabar, blackphos, electrum)
✅ **Works**: Using config.flake.modules.* imports via dendritic pattern
✅ **Works**: Combining inventory and machines configuration
✅ **Works**: Per-system customization via pkgsForSystem
✅ **Works**: Overlays at machine and base module levels

❌ **Doesn't Work**: Inventory-level nixpkgs configuration
❌ **Doesn't Work**: Service-level nixpkgs.config
❌ **Doesn't Work**: Expecting pkgsForSystem called per-machine (it's per-system)

