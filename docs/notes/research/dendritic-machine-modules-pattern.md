# Dendritic Flake-Parts Pattern for Machine-Specific Modules

## Research Summary

After examining test-clan, dendrix, drupol-dendritic-infra, and gaetanlepage-dendritic-nix-config, the dendritic pattern for machine-specific modules is well-established and your current test-clan approach is **CORRECT**.

## Key Finding: Your Current Approach is Correct

Your structure in test-clan:

```
modules/machines/darwin/blackphos/
├── default.nix
└── zerotier.nix
```

With direct import in default.nix:
```nix
imports = [
  ./zerotier.nix
  # ... other imports
];
```

This **is the correct dendritic pattern**. It does not require flake-parts wrapper like `config.flake.modules.darwin."machines/darwin/blackphos/zerotier"`.

## Three Levels of Module Organization in Dendritic

### Level 1: Shared Modules (Auto-Discovered via import-tree)

These are discovered and auto-merged by import-tree into the appropriate flake.modules namespace:

```
modules/
├── darwin/
│   ├── base.nix                    # Exports: config.flake.modules.darwin.base
│   ├── system-defaults.nix         # Exports: config.flake.modules.darwin.system-defaults
│   └── homebrew.nix               # Exports: config.flake.modules.darwin.homebrew
├── nixos/
│   └── base.nix                    # Exports: config.flake.modules.nixos.base
└── home/
    └── core.nix                    # Exports: config.flake.modules.homeManager.core
```

Pattern: Single file = direct flake.modules export
```nix
# Example: modules/darwin/base.nix
{ ... }:
{
  flake.modules.darwin.base = { ... };
}
```

### Level 2: Machine Root Modules (Exported to flake.modules)

Machine root modules ARE exported to flake.modules so they can be built/deployed by the flake:

```
modules/machines/
├── darwin/
│   ├── blackphos/default.nix       # Exports: config.flake.modules.darwin."machines/darwin/blackphos"
│   └── test-darwin/default.nix     # Exports: config.flake.modules.darwin."machines/darwin/test-darwin"
└── nixos/
    ├── cinnabar/default.nix        # Exports: config.flake.modules.nixos."machines/nixos/cinnabar"
    └── electrum/default.nix        # Exports: config.flake.modules.nixos."machines/nixos/electrum"
```

Pattern: Machine root module exports itself to flake.modules path
```nix
# modules/machines/darwin/blackphos/default.nix
{ config, ... }:
let
  flakeModules = config.flake.modules.darwin;
in
{
  flake.modules.darwin."machines/darwin/blackphos" = {
    imports = [
      ./zerotier.nix              # Level 3: Direct import (NOT flake.modules)
      (with flakeModules; [ base ])
    ];
    # ... configuration
  };
}
```

### Level 3: Machine-Local Modules (Direct Imports ONLY)

Machine-specific sub-modules are **always** imported directly via relative paths, never wrapped in flake.modules:

```
modules/machines/darwin/blackphos/
├── default.nix                     # Exported to flake.modules (Level 2)
├── zerotier.nix                   # Direct import only (Level 3)
├── homebrew-specific.nix          # Direct import only (Level 3)
└── services/
    ├── default.nix               # Direct import only (Level 3)
    └── some-service.nix          # Direct import only (Level 3)
```

Pattern: Direct relative import
```nix
# modules/machines/darwin/blackphos/default.nix
{
  flake.modules.darwin."machines/darwin/blackphos" = {
    imports = [
      ./zerotier.nix                       # Correct: direct path
      # NOT: config.flake.modules.darwin."machines/darwin/blackphos/zerotier"
    ];
  };
}
```

## Evidence from Reference Implementations

### test-clan (Your Current Repository)

Structure matches the pattern perfectly:

**blackphos** (darwin):
```
modules/machines/darwin/blackphos/
├── default.nix      # Exports flake.modules.darwin."machines/darwin/blackphos"
└── zerotier.nix    # Imported via ./zerotier.nix (direct path)
```

From `modules/machines/darwin/blackphos/default.nix`:
```nix
flake.modules.darwin."machines/darwin/blackphos" = {
  config, pkgs, lib, ...
}:
{
  imports = [
    inputs.home-manager.darwinModules.home-manager
    ./zerotier.nix   # Direct import - CORRECT PATTERN
  ]
  ++ (with flakeModules; [
    base
  ]);
  # ...
};
```

**cinnabar** (nixos with disko.nix sub-module):
```
modules/machines/nixos/cinnabar/
├── default.nix     # Exports flake.modules.nixos."machines/nixos/cinnabar"
└── disko.nix      # Imported via ./disko.nix (direct path)
```

From `modules/machines/nixos/cinnabar/disko.nix`:
```nix
# Note: This file ALSO exports to flake.modules
# (Auto-merge pattern for platform-specific config)
{ ... }:
{
  flake.modules.nixos."machines/nixos/cinnabar" = {
    disko.devices = { ... };
  };
}
```

Why disko.nix exports: It's a complex configuration block that needs to be merged into the same flake.modules path. The flake-parts module merging system combines all exports to the same path.

### drupol-dendritic-infra

Machine modules in `modules/hosts/`:

```
modules/hosts/
├── x1c/default.nix              # Exports flake.modules.nixos."hosts/x1c"
├── apollo/default.nix           # Exports flake.modules.nixos."hosts/apollo"
└── xeonixos/default.nix         # Exports flake.modules.nixos."hosts/xeonixos"
```

From `modules/hosts/x1c/default.nix`:
```nix
{
  flake.modules.nixos."hosts/x1c" = {
    imports =
      with config.flake.modules.nixos;
      [
        inputs.disko.nixosModules.disko
        base
        bluetooth
        desktop
        dev
        education
        # ... more shared modules
      ]
      # Specific home-manager configuration inline
      ++ [
        {
          home-manager.users.pol = {
            imports = with config.flake.modules.homeManager; [
              base
              desktop
              dev
            ];
          };
        }
      ];
  };
}
```

Pattern: No sub-modules shown here, but the import style is clear - shared modules via `config.flake.modules.nixos`, inline configurations.

**Orchestration** in `modules/flake-parts/host-machines.nix`:
```nix
# Filters all modules with "hosts/" prefix and builds nixosConfigurations
flake.nixosConfigurations = lib.pipe (collectHostsModules config.flake.modules.nixos) [
  (lib.mapAttrs' (name: module: /* ... */))
];
```

### gaetanlepage-dendritic-nix-config

Complex machine with service sub-modules:

```
modules/hosts/tank/
├── default.nix              # References _nixos subdirectory
└── _nixos/
    ├── default.nix         # Contains all imports and config
    ├── hardware.nix        # Direct imports within _nixos
    ├── disko.nix          # Direct imports within _nixos
    ├── backup/            # Sub-directory (direct import)
    ├── nfs.nix            # Direct imports within _nixos
    └── ... (30+ service files)
```

From `modules/hosts/tank/default.nix`:
```nix
{
  nixosHosts.tank = {
    unstable = false;
    modules = [
      config.flake.modules.nixos.server
      ./_nixos              # Direct path to subdirectory
    ];
  };
}
```

From `modules/hosts/tank/_nixos/default.nix`:
```nix
{
  imports = [
    ./hardware.nix         # Direct import
    ./backup               # Direct directory import
    ./users.nix
    ./zfs                  # Direct directory import
    ./disko.nix
    ./nfs.nix
    ./samba.nix
    ./caddy.nix
    ./postgresql.nix
    ./deluge               # Direct directory import
    ./immich.nix
    # ... etc
  ];
}
```

Key insight: All machine-local sub-modules use direct relative imports. The `_nixos` prefix convention indicates "this is a namespace for machine-specific configuration, not auto-discovered."

## Three Design Patterns for Machine-Specific Sub-Modules

Based on reference implementations, there are three valid patterns:

### Pattern A: Inline in default.nix (Simplest)

Good for small machines with 1-2 features:

```
modules/machines/darwin/simple-machine/
└── default.nix
```

```nix
flake.modules.darwin."machines/darwin/simple-machine" = {
  imports = [ /* shared modules */ ];
  
  # Configuration inline
  networking.hostName = "simple-machine";
  system.stateVersion = 4;
};
```

### Pattern B: Sibling .nix files with Direct Import (Current test-clan)

Good for machines with 3-5 distinct concerns:

```
modules/machines/darwin/blackphos/
├── default.nix
├── zerotier.nix
├── homebrew-specific.nix
└── security.nix
```

```nix
# default.nix
flake.modules.darwin."machines/darwin/blackphos" = {
  imports = [
    ./zerotier.nix
    ./homebrew-specific.nix
    ./security.nix
  ];
  # Common config
};
```

This is your current approach and it's correct.

### Pattern C: Organized Subdirectories with Double Export

Good for complex machines with 10+ services (like gaetanlepage tank):

```
modules/machines/nixos/complex-server/
├── default.nix
└── _services/
    ├── default.nix
    ├── caddy.nix
    ├── postgres.nix
    └── backup/
        ├── default.nix
        └── retention.nix
```

The `_services/default.nix` has its own imports, all relative. The `_` prefix signals to import-tree: "don't auto-discover this, it's manually managed."

## Import-Tree Auto-Discovery Rules

Understanding how import-tree works clarifies the pattern:

1. Files matching `**/*.nix` (excluding `_*` paths) are auto-discovered
2. Each discovered file is imported as a module
3. If a file exports to `flake.modules.*`, that becomes the module
4. Multiple exports to the same path are merged by flake-parts

Key insight: **Paths with `_` components are ignored by import-tree.**

```nix
# From import-tree README:
// By default, paths having `/_` are ignored.
```

This means:
- `modules/machines/darwin/blackphos/zerotier.nix` - DISCOVERED (no `_`)
- `modules/machines/darwin/blackphos/_internal/config.nix` - NOT DISCOVERED

So your zerotier.nix file would be auto-discovered and imported separately. But since it doesn't export a `flake.modules.*`, it's just included as-is. This is fine for machine-local files that don't need auto-discovery.

## Why Machine Sub-Modules Should NOT Be Wrapped in flake.modules

1. **Composition Control**: Machine maintainers choose which sub-modules to include
2. **Visibility**: Sub-modules are only relevant to their parent machine
3. **Simplicity**: Avoids namespace explosion (wouldn't need `config.flake.modules.darwin."machines/darwin/blackphos/zerotier"`)
4. **Merge Semantics**: Direct import is explicit, flake.modules is for global discovery

## Special Case: disko.nix Pattern

Some machine sub-modules (like disko.nix in cinnabar) DO export to flake.modules:

```nix
# modules/machines/nixos/cinnabar/disko.nix
{ ... }:
{
  flake.modules.nixos."machines/nixos/cinnabar" = {
    disko.devices = { ... };
  };
}
```

This pattern is used when:
- The sub-module is complex enough to warrant its own file
- It should be auto-merged with the parent configuration
- The flake-parts merging system will combine it with the main default.nix export

This is NOT a requirement - you could also put disko config directly in default.nix. It's a style choice for readability.

## Recommendations for Your infra Repository

### Current (test-clan) Approach - KEEP

```
modules/machines/darwin/blackphos/
├── default.nix
└── zerotier.nix
```

With direct import:
```nix
imports = [ ./zerotier.nix ];
```

This is correct and follows dendritic patterns.

### If You Grow to 20+ Sub-Modules

Consider adopting the `_services/` pattern:

```
modules/machines/nixos/cinnabar/
├── default.nix
└── _services/
    ├── default.nix
    ├── zerotier.nix
    ├── caddy.nix
    ├── wireguard.nix
    └── postgres/
        └── default.nix
```

The `_services/default.nix` would contain all the imports.

### Never Do This

Do NOT wrap machine-local modules in flake.modules:

```nix
# WRONG - Don't do this
flake.modules.darwin."machines/darwin/blackphos/zerotier" = { ... };
```

Reasons:
1. Creates unnecessary namespace pollution
2. Breaks composition (you'd need to reference it in default.nix)
3. Not discoverable by import-tree anyway (already under machines/)
4. Violates the locality principle

## Summary Table

| Pattern | Use Case | Module Discovery | Sub-Module Imports |
|---------|----------|------------------|-------------------|
| Inline config in default.nix | Simple machines (< 3 concerns) | Auto-discovered root module only | N/A |
| Sibling files + direct import | Medium machines (3-10 concerns) | Auto-discovered root module only | Direct relative paths |
| Subdirectory with _prefix | Complex machines (10+ services) | Manual, opt-in via direct import | Direct relative paths in subdir |
| Double export (disko pattern) | Rare, for complex nested config | Auto-discovered for merge | Direct relative paths |

## Code Examples

### test-clan (Correct)

**File: modules/machines/darwin/blackphos/default.nix**
```nix
{
  config,
  pkgs,
  lib,
  inputs,
  ...
}:
let
  flakeModules = config.flake.modules.darwin;
  flakeModulesHome = config.flake.modules.homeManager;
in
{
  flake.modules.darwin."machines/darwin/blackphos" = {
    config,
    pkgs,
    lib,
    ...
  }:
  {
    imports = [
      inputs.home-manager.darwinModules.home-manager
      ./zerotier.nix              # CORRECT: Direct relative path
    ]
    ++ (with flakeModules; [
      base
    ]);

    networking.hostName = "blackphos";
    # ... rest of config
  };
}
```

**File: modules/machines/darwin/blackphos/zerotier.nix**
```nix
{
  config,
  lib,
  pkgs,
  ...
}:
let
  networkId = "db4344343b14b903";
  zerotierJoinScript = pkgs.writeShellScript "zerotier-join" ''
    # ...
  '';
in
{
  # Direct configuration, no flake.modules export
  system.activationScripts.postActivation.text = lib.mkAfter ''
    echo "Running zerotier network join check..."
    ${zerotierJoinScript}
  '';
}
```

### drupol-dendritic-infra (Reference)

**File: modules/hosts/x1c/default.nix**
```nix
{
  config,
  inputs,
  ...
}:
{
  flake.modules.nixos."hosts/x1c" = {
    imports =
      with config.flake.modules.nixos;
      [
        inputs.disko.nixosModules.disko
        base
        bluetooth
        desktop
        dev
        # ... shared modules
      ]
      ++ [
        {
          home-manager.users.pol = {
            imports = with config.flake.modules.homeManager; [
              base
              desktop
              dev
            ];
          };
        }
      ];

    boot = { /* ... */ };
    facter.reportPath = ./facter.json;
    disko.devices = { /* ... */ };
  };
}
```

No sub-modules here, but if there were 10+ services, they'd be in a `_services/` directory.

### gaetanlepage-dendritic-nix-config (Complex Example)

**File: modules/hosts/tank/default.nix**
```nix
{
  config,
  ...
}:
{
  nixosHosts.tank = {
    unstable = false;
    modules = [
      config.flake.modules.nixos.server
      ./_nixos                     # Direct path to sub-namespace
    ];
  };
}
```

**File: modules/hosts/tank/_nixos/default.nix**
```nix
{
  lib,
  pkgs,
  ...
}:
{
  imports = [
    ./hardware.nix               # Direct relative import
    ./backup                     # Can import directories
    ./users.nix
    ./zfs
    ./disko.nix
    ./nfs.nix
    ./samba.nix
    ./caddy.nix
    ./postgresql.nix
    ./deluge
    ./immich.nix
    ./invidious
    ./jellyfin.nix
    ./nextcloud
  ];

  networking = {
    hostName = "tank";
    hostId = "f504d887";
  };

  age.rekey.hostPubkey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDpwnnDFq6MrqjvwYikioz5kr3iOgD3iC+rPm6rC2O4b";
  # ... rest of config
}
```

Each service file (caddy.nix, postgresql.nix, etc.) is just a plain module with no flake.modules exports.

## Conclusion

Your current test-clan approach is perfectly aligned with dendritic patterns. The direct import pattern (`./zerotier.nix`) for machine-local sub-modules is correct and idiomatic. No changes needed unless you anticipate 20+ sub-modules per machine, at which point the `_services/` organizational pattern becomes useful.

The key principle: **Machine root modules are exported to flake.modules for orchestration; machine-local sub-modules are imported directly for composition.**
