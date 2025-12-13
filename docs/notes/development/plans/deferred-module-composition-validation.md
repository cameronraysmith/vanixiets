# Deferred module composition validation plan

This document provides validation procedures and maintenance guidelines for the deferred module composition architecture.
The migration to this architecture is substantially complete, with 90% structural pattern compliance and 98% mathematical property compliance.
This plan focuses on verifying ongoing compliance and documenting the established patterns.

## Current state assessment

### Architecture compliance summary

The repository demonstrates strong adoption of deferred module composition:

| Metric | Value | Status |
|--------|-------|--------|
| Structural pattern compliance | 90% (9/10 patterns) | Complete |
| Mathematical property compliance | 98% (15/15 properties) | Complete |
| Deferred module exports | 119 | Established |
| Files using `flake.modules.*` | 89/156 (57%) | Appropriate |

The 57% file coverage is correct because not all files should use the pattern.
Infrastructure modules, aggregators, and library utilities intentionally operate at different layers.

### File inventory by category

| Category | Count | Description |
|----------|-------|-------------|
| **Deferred modules** | 89 | Export to `flake.modules.<class>.<name>` |
| **Flake-level config** | 18 | perSystem, systems, infrastructure |
| **Aggregators** | 9 | Empty default.nix stubs for import-tree |
| **Library/utility** | 2 | Function exports |
| **Clan inventory** | 38 | Use `clan.inventory.*` pattern |

### Namespace distribution

| Namespace | Files | Description |
|-----------|-------|-------------|
| homeManager | 54 | Home-manager aspect modules |
| darwin | 20 | Darwin system + machine configs |
| nixos | 16 | NixOS system + machine configs |
| terranix | 3 | Terraform infrastructure |

### Established patterns

The following patterns are correctly implemented.

**Aspect modules with namespace merging**:

```nix
# modules/home/tools/bottom.nix
{ ... }:
{
  flake.modules.homeManager.tools = { ... }: {
    programs.bottom = {
      enable = true;
      settings = { ... };
    };
  };
}
```

**Machine modules as deferred exports**:

```nix
# modules/machines/darwin/stibnite/default.nix
{ config, ... }:
let
  flakeModules = config.flake.modules.darwin;
  flakeModulesHome = config.flake.modules.homeManager;
in
{
  flake.modules.darwin."machines/darwin/stibnite" = { config, pkgs, lib, ... }: {
    imports = [ ... ] ++ (with flakeModules; [
      base
      ssh-known-hosts
      colima
    ]);

    networking.hostName = "stibnite";

    home-manager.users.crs58.imports = [
      flakeModulesHome."users/crs58"
      flakeModulesHome.ai
      flakeModulesHome.core
      flakeModulesHome.development
      flakeModulesHome.packages
      flakeModulesHome.shell
      flakeModulesHome.terminal
      flakeModulesHome.tools
    ];
  };
}
```

**Unified machine registration through clan**:

```nix
# modules/clan/machines.nix
{ config, ... }:
{
  clan.machines = {
    stibnite = {
      imports = [ config.flake.modules.darwin."machines/darwin/stibnite" ];
    };
    cinnabar = {
      imports = [ config.flake.modules.nixos."machines/nixos/cinnabar" ];
    };
    # All 8 machines registered here
  };
}
```

**Cross-platform aspect modules**:

```nix
# modules/system/ssh-known-hosts.nix exports to BOTH namespaces
{ ... }:
{
  flake.modules.darwin.ssh-known-hosts = { ... }: { ... };
  flake.modules.nixos.ssh-known-hosts = { ... }: { ... };
}
```

### Design decisions

The following are intentional design choices, not gaps.

**Inline option declarations**: Options are declared in the same file as their configuration (e.g., `darwin/homebrew.nix` declares `custom.homebrew.*` options).
This keeps related concerns together rather than splitting them across `options/` directories.
Only 7 files declare options, and all follow valid patterns for custom namespace ownership.

**Platform-specific modules**: Some configuration is intentionally platform-specific (`darwin/nix-settings.nix` for launchd intervals, TouchID).
Cross-platform settings are consolidated in `system/*.nix` which exports to both namespaces.

## Validation procedures

### Structural pattern validation

Run these checks to verify structural compliance.

**Entry point and auto-discovery**:

```bash
# Verify import-tree usage in flake.nix
rg "import-tree" flake.nix
# Expected: (inputs.import-tree ./modules)
```

**Namespace consistency within directories**:

```bash
# Each directory should export to single namespace
for dir in modules/home/*/; do
  if [[ -d "$dir" ]]; then
    namespace=$(basename "$dir")
    echo "=== $dir (expected: homeManager.$namespace) ==="
    rg "flake\.modules\." "$dir" -h --no-filename | sort -u
  fi
done
```

**Machine registration completeness**:

```bash
# All machines should be in clan/machines.nix
cat modules/clan/machines.nix
# Expected: 8 machines (4 darwin + 4 nixos)
```

**Cross-platform exports**:

```bash
# System modules should export to both namespaces
for f in $(fd -t f -e nix . modules/system/); do
  darwin=$(rg -c "flake\.modules\.darwin\." "$f" 2>/dev/null || echo 0)
  nixos=$(rg -c "flake\.modules\.nixos\." "$f" 2>/dev/null || echo 0)
  if [[ "$darwin" -gt 0 && "$nixos" -gt 0 ]]; then
    echo "UNIFIED: $f (darwin: $darwin, nixos: $nixos)"
  fi
done
# Expected: caches.nix, nix-optimization.nix, nix-settings.nix, ssh-known-hosts.nix, etc.
```

### Mathematical property validation

These procedures verify compliance with documented mathematical properties.

**FR1: Fixpoint computation**

Modules reference `config.*` values resolved through fixpoint computation.

```bash
# Evaluation should succeed without infinite recursion
nix eval .#darwinConfigurations.stibnite.config.networking.hostName
nix eval .#nixosConfigurations.cinnabar.config.networking.hostName
```

Success criteria: Both return hostname strings without errors.

**FR2: Lazy evaluation**

Deferred modules evaluate only when accessed.

```bash
# Each configuration evaluates independently
nix eval .#darwinConfigurations --apply builtins.attrNames
nix eval .#nixosConfigurations --apply builtins.attrNames
```

Success criteria: Returns `[ "argentum" "blackphos" "rosegold" "stibnite" ]` and `[ "cinnabar" "electrum" "galena" "scheelite" ]`.

**FR3: Referential transparency**

No impure operations in module code.

```bash
# Should return no matches
rg "builtins\.(currentTime|getEnv)" modules/
rg "import\s+<" modules/
```

Success criteria: Zero matches for both commands.

**FR4: Parametric polymorphism**

Platform checks are justified and localized.

```bash
# Check for platform-specific code (should be minimal and justified)
rg "stdenv\.is" modules/ -l | wc -l
```

Success criteria: Limited occurrences in platform-specific modules (overlays, package selection).

**FR5: Monadic composition**

Modules use `{ config, lib, pkgs, ... }` pattern.

```bash
# Sample module signatures
rg "^{ (config|lib|pkgs|inputs)" modules/ | head -20
```

Success criteria: Consistent pattern across modules.

**NFR2: Configuration-only deferral**

Deferred modules primarily contain configuration, not option declarations.

```bash
# Count files with both flake.modules AND mkOption
for f in $(rg "flake\.modules\." modules/ -l | head -50); do
  if rg -q "mkOption|mkEnableOption" "$f" 2>/dev/null; then
    echo "MIXED: $f"
  fi
done
```

Success criteria: Only custom namespace modules (homebrew, profile, colima, helix) appear.

**NFR5: Aspect orthogonality**

Aspects can be independently enabled/disabled.

```bash
# Machine configs import aggregates, not individual modules
rg "flakeModulesHome\.(ai|core|development|packages|shell|terminal|tools)" modules/machines/ | head -10
```

Success criteria: Machine files import aggregates like `flakeModulesHome.ai`, not individual files.

### Full evaluation test

```bash
# Complete build test for each configuration class
nix build .#darwinConfigurations.stibnite.system
nix build .#nixosConfigurations.cinnabar.config.system.build.toplevel

# Or use flake check
nix flake check --no-build
```

Success criteria: All configurations build without errors.

## Maintenance guidelines

### Adding new aspect modules

When creating new modules in aspect directories (`home/tools/`, `home/terminal/`, etc.):

1. Export to the directory's namespace: `flake.modules.homeManager.<directory-name>`
2. Use the two-layer pattern: outer flake-parts module, inner deferred module
3. The file is auto-discovered via import-tree, no registration needed

Example:

```nix
# modules/home/tools/newtool.nix
{ ... }:
{
  flake.modules.homeManager.tools = { pkgs, ... }: {
    home.packages = [ pkgs.newtool ];
  };
}
```

### Adding new machines

1. Create machine module exporting to `flake.modules.<class>."machines/<class>/<hostname>"`:

```nix
# modules/machines/darwin/newhost/default.nix
{ config, ... }:
let
  flakeModules = config.flake.modules.darwin;
  flakeModulesHome = config.flake.modules.homeManager;
in
{
  flake.modules.darwin."machines/darwin/newhost" = { ... }: {
    imports = [ ... ] ++ (with flakeModules; [ base ssh-known-hosts ]);
    networking.hostName = "newhost";
    # ...
  };
}
```

2. Register in `modules/clan/machines.nix`:

```nix
clan.machines.newhost = {
  imports = [ config.flake.modules.darwin."machines/darwin/newhost" ];
};
```

### Adding cross-platform configuration

For configuration that applies to both darwin and nixos, create in `modules/system/` and export to both namespaces:

```nix
# modules/system/new-aspect.nix
{ ... }:
{
  flake.modules.darwin.new-aspect = { ... }: { ... };
  flake.modules.nixos.new-aspect = { ... }: { ... };
}
```

### Maintenance checklist

When adding new modules:

- [ ] File exports to `flake.modules.<class>.<name>` namespace
- [ ] Namespace matches directory location
- [ ] No option declarations inside deferred module body (unless custom namespace)
- [ ] Cross-platform configuration in `system/` domain
- [ ] Machine registration in `clan/machines.nix`

When modifying existing modules:

- [ ] Preserve namespace consistency
- [ ] Run validation procedures after changes
- [ ] Update tests if behavior changes

## Optional enhancements

The following are not required for compliance but could improve organization.

### Option declaration separation

Currently, options are declared inline with configuration.
An alternative pattern separates them into `options/` subdirectories:

```
modules/darwin/
├── options/
│   └── homebrew.nix    # Option declarations only
└── homebrew.nix        # Configuration only
```

This is useful if option definitions need to be reused across multiple modules.
The current inline approach is valid and keeps related concerns together.

### Dedicated nixos/base.nix

The codebase lacks a dedicated `modules/nixos/base.nix` equivalent to `modules/darwin/base.nix`.
NixOS base configuration is currently provided through `modules/system/*.nix` exports.
Creating a dedicated file would improve symmetry but is not functionally required.

## Compliance summary

| Category | Status | Evidence |
|----------|--------|----------|
| Entry point pattern | ✅ | `import-tree ./modules` in flake.nix |
| Module uniformity | ✅ | All files are flake-parts modules |
| Namespace convention | ✅ | 119 exports to `flake.modules.<class>.<name>` |
| Directory-based merging | ✅ | Files in same directory share namespace |
| Machine composition | ✅ | All machines use `config.flake.modules.*` |
| Unified registration | ✅ | All 8 machines in clan/machines.nix |
| Aspect organization | ✅ | 108 aspect files vs 12 machine files |
| Cross-platform aspects | ✅ | system/*.nix exports to both namespaces |
| Home-manager integration | ✅ | Machines import `flakeModulesHome.*` aggregates |
| Options/config separation | ⚪ | Not implemented (intentional) |

**Overall: 9/10 patterns implemented (90%), 1 intentionally different**

## References

- [Deferred module composition](/concepts/deferred-module-composition/) - Core pattern documentation
- [Module system primitives](/concepts/module-system-primitives/) - Mathematical foundations
- [Flake-parts module system](/concepts/flake-parts-module-system/) - Framework integration
- [Clan integration](/concepts/clan-integration/) - Multi-machine coordination
