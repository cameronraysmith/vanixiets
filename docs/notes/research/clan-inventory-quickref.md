# Clan Inventory extraModules: Quick Reference

## Answer to Critical Question

**Can clan inventory service extraModules reference flake-exported modules?**

**PARTIAL YES with constraints:**
- Cannot directly reference `inputs.self.modules.homeManager.*` in inventory context (not JSON-serializable)
- CAN access dendritic modules via `extraSpecialArgs` pass-through in NixOS module layer
- This is proven working in test-clan implementation

## Four Valid Reference Patterns

### 1. File Path Imports (Simplest)
```nix
roles.default.extraModules = [ ./users/lhebendanz.nix ];
```
✅ Works everywhere
❌ Cannot access dendritic modules directly

### 2. Self-Referenced NixOS Modules (Limited)
```nix
roles.default.extraModules = [ self.nixosModules.borgbackup ];
```
⚠️ Works only if module is JSON-serializable
❌ No flake context

### 3. Inline Modules (More Flexible)
```nix
roles.default.extraModules = [
  {
    imports = [ ./file.nix ];  # File imports OK
    some.option = "value";      # JSON-serializable values OK
  }
];
```
✅ Works - inline attrset is JSON-serializable

### 4. Inline + extraSpecialArgs (Full Consolidation)
```nix
roles.default.extraModules = [
  inputs.home-manager.nixosModules.home-manager
  (
    { pkgs, ... }:
    {
      home-manager = {
        extraSpecialArgs = {
          flake = inputs.self // { inherit inputs; };  # Pass flake context
        };
        users.cameron = {
          imports = [
            # Now dendritic modules ARE accessible!
            inputs.self.modules.homeManager."users/crs58"
            inputs.self.modules.homeManager.ai
            inputs.self.modules.homeManager.development
            # ... etc
          ];
        };
      };
    }
  )
];
```
✅ Works - this is test-clan pattern
✅ Full consolidation possible
⚠️ More complex structure

## Key Insight: JSON Serialization Boundary

The inventory evaluation pipeline requires JSON serialization:
```
clan.nix → nix eval --json → JSON → clan CLI → machines
```

This means:
- File paths: ✅ JSON-serializable (strings)
- Lambdas: ❌ Not JSON-serializable at inventory level
- `inputs.self`: ❌ Not JSON-serializable at inventory level

**But**: Inside an inline NixOS module (which is JSON-serializable), non-serializable expressions are fine because they're evaluated AFTER the JSON step.

## Test-Clan Proves It Works

Both `cameron.nix` and `crs58.nix` in test-clan inventory successfully:
1. Reference all dendritic home-manager aggregates
2. Pass `inputs.self` through to home-manager context
3. Consolidate configuration without duplication

Locations:
- `/Users/crs58/projects/nix-workspace/test-clan/modules/clan/inventory/services/users/cameron.nix`
- `/Users/crs58/projects/nix-workspace/test-clan/modules/clan/inventory/services/users/crs58.nix`

## For Infra Repository

To consolidate infra's users with dendritic modules:

1. **Add home-manager to user services** (currently missing)
   ```nix
   roles.default.extraModules = [
     inputs.home-manager.nixosModules.home-manager
     # ... inline config
   ];
   ```

2. **Pass flake context** in `extraSpecialArgs`
   ```nix
   home-manager = {
     extraSpecialArgs = {
       flake = inputs.self // { inherit inputs; };
     };
     users.cameron.imports = [
       inputs.self.modules.homeManager."users/crs58"
       # ... all dendritic aggregates
     ];
   };
   ```

3. **Result**: Single source of truth for user configuration

## Architectural Constraints

1. Inventory must be JSON-serializable
2. extraSpecialArgs scope limited to that inline module and descendants
3. Users service currently NixOS-only (darwin via extraModules workaround)

## Reference Files

**Full Research**: `docs/notes/research/clan-inventory-extramodules-research.md`

**Example Implementations**:
- test-clan: `/Users/crs58/projects/nix-workspace/test-clan/modules/clan/inventory/services/users/`
- qubasa-clan: `/Users/crs58/projects/nix-workspace/qubasa-clan-infra/clan.nix` (file-based pattern)
- pinpox-clan: `/Users/crs58/projects/nix-workspace/pinpox-clan-nixos/inventory.nix` (programmatic paths)

**Documentation**:
- clan-core inventory: `~/projects/nix-workspace/clan-core/docs/site/guides/inventory/inventory.md`
- clan-core services: `~/projects/nix-workspace/clan-core/docs/site/guides/services/introduction-to-services.md`
- clan-core users: `~/projects/nix-workspace/clan-core/docs/site/getting-started/add-users.md`
