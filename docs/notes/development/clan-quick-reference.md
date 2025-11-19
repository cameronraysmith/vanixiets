# Clan-Core Architecture: Quick Reference Guide

## Most Important: Two-Phase Nixpkgs Instantiation

```
1. PRE-CONFIG INSTANTIATION (module.nix:35-41)
   clan/module.nix evaluated → pkgsForSystem called ONCE per system
   Result: pkgsFor.${system} = pre-instantiated nixpkgs (no config)

2. MODULE EVALUATION
   Inside nixosSystem/darwinSystem → nixpkgs.config NOW AVAILABLE
   clan.machines.* modules evaluated here
   
3. POST-CONFIG INSTANTIATION (module.nix:95-111)
   machine.extendModules injects overridePkgs
   Forces: nixpkgs.pkgs = pkgsFor.${system}
```

## Where to Set nixpkgs.config

### Correct Approach
```nix
# In clan.machines.myhost or imported module
{
  nixpkgs.config = {
    allowUnfree = true;
    allowUnfreePredicate = pkg: builtins.elem (lib.getName pkg) ["package1" "package2"];
  };
  nixpkgs.overlays = [ inputs.self.overlays.default ];
}
```

### Recommended Pattern (Dendritic)
```nix
# flake-modules/machines/nixos/myhost.nix
flake.modules.nixos."machines/nixos/myhost" = { ... }: {
  nixpkgs.config.allowUnfree = true;
  # configuration here
};

# clan/machines.nix
clan.machines.myhost = {
  imports = [ config.flake.modules.nixos."machines/nixos/myhost" ];
};

# clan/inventory/machines.nix
clan.inventory.machines.myhost = {
  machineClass = "nixos";
  tags = ["linux"];
};
```

## Inventory vs Configuration

| Purpose | Location | Supports |
|---------|----------|----------|
| Metadata | clan.inventory.machines.* | machineClass, tags, deploy info |
| System Config | clan.machines.* | All nixos/darwin options + nixpkgs config |
| Services | clan.inventory.instances.*.roles | Machine membership, service settings |

## Critical: What Doesn't Work

```nix
# ❌ WRONG: Inventory doesn't support nixpkgs config
clan.inventory.machines.X.nixpkgs.config = { allowUnfree = true; };

# ❌ WRONG: Services don't have nixpkgs options
clan.inventory.instances.service.roles.roleName.nixpkgs = { ... };

# ❌ WRONG: pkgsForSystem is per-system, not per-machine
# Calling it multiple times per system defeats the optimization
```

## Clan Options Summary

| Option | Type | Purpose |
|--------|------|---------|
| clan.inventory.machines | attrs | Machine metadata |
| clan.inventory.instances | attrs | Multi-host services |
| clan.machines | attrs | Machine configurations |
| clan.pkgsForSystem | function | Custom nixpkgs instantiation (optional) |
| clan.specialArgs | attrs | Passed to all machines |
| clan.modules | attrs | Reusable modules |
| clan.templates | attrs | Clan templates |

## How Inventory Instances Work

```nix
clan.inventory.instances.zerotier = {
  module.name = "zerotier";  # or module.input = "external-input"
  roles.server = {
    machines.controller = {};  # explicit membership
    tags = [ "servers" ];       # tag-based membership
    settings = { ... };         # role configuration
    extraModules = [ "modules/special.nix" ];  # if machine in role
  };
};

# Applied to machines that have matching tags or explicit membership
# Settings are injected into machine nixos config
# Does NOT create separate package configuration
```

## Outputs Generated

```nix
flake.outputs = {
  nixosConfigurations.myhost = nixosSystem { ... };
  darwinConfigurations.myhost = darwinSystem { ... };
  nixosModules.clan-machine-myhost = deferredModule;  # reusable
  darwinModules.clan-machine-myhost = deferredModule;  # reusable
}
```

## Testing Your Configuration

1. Check inventory is loaded:
   ```bash
   nix eval '.#clanInternals.inventoryClass.machines'
   ```

2. Check machine config:
   ```bash
   nix eval '.#nixosConfigurations.myhost.config.nixpkgs.config'
   ```

3. Build a machine:
   ```bash
   nix build '.#nixosConfigurations.myhost.system'
   ```

## Common Patterns

### Pattern 1: Multiple Machines with Shared Base
```nix
# In base module
nixpkgs.overlays = [ inputs.self.overlays.default ];

# In machine-specific module
nixpkgs.config.allowUnfreePredicate = pkg: builtins.elem (lib.getName pkg) ["specific"];
```

### Pattern 2: Per-Architecture Configuration
```nix
clan.pkgsForSystem = system:
  if system == "x86_64-linux" then
    inputs.nixpkgs.legacyPackages.x86_64-linux
  else if system == "aarch64-darwin" then
    inputs.nixpkgs-darwin-stable.legacyPackages.aarch64-darwin
  else
    null;  # fallback to default
```

### Pattern 3: Service Configuration
```nix
clan.inventory.instances.borgbackup = {
  module.name = "borgbackup";
  roles.server = {
    machines.backup-host = {
      settings.publicKey = "...";
    };
    tags = [ "backup-clients" ];
  };
};
```

## Key Files Reference

| File | Lines | Purpose |
|------|-------|---------|
| clan-core/modules/clan/module.nix | 35-41 | Phase A: pre-config instantiation |
| clan-core/modules/clan/module.nix | 55-66 | nixosSystem/darwinSystem calls |
| clan-core/modules/clan/module.nix | 95-111 | Phase B: post-config injection |
| clan-core/modules/clan/module.nix | 159-206 | moduleForMachine composition |
| clan-core/flakeModules/clan.nix | all | flake-parts integration |
| clan-core/modules/clan/top-level-interface.nix | 304-316 | pkgsForSystem option definition |

## Debugging

If nixpkgs.config not working:
1. Verify it's in machine module, not inventory
2. Check clan.machines imports the right module
3. Verify moduleForMachine includes your config (nix eval)
4. Remember: pkgsFor is pre-instantiated (Phase A), config applied during module evaluation

If overlays not merging:
1. Check module order in imports
2. Overlays merge via mkMerge in moduleForMachine
3. Later overlays override earlier ones

If pkgsForSystem not called:
1. It's called once per supported system, not per machine
2. If you return null, falls back to nixpkgs.legacyPackages
3. Use machine-level nixpkgs.config for per-machine customization
