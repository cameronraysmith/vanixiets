# Test-Clan Evaluation Path - Quick Reference

## Complete File-by-File Chain (Evaluation Order)

| # | File Path | Lines | What Happens | Config Context | Dependencies |
|---|-----------|-------|--------------|-----------------|--------------|
| 1 | `flake.nix` | 1-6 | Entry point, calls import-tree | Global | inputs.flake-parts, inputs.import-tree |
| 2 | `modules/checks/*.nix` | - | Test/validation modules | Global flake-parts | - |
| 3 | `modules/clan/core.nix` | 1-7 | Imports clan-core flakeModule | Global flake-parts | inputs.clan-core |
| 4 | `modules/clan/inventory/machines.nix` | 1-52 | Declares machine inventory | Global flake-parts | - |
| 5 | `modules/clan/meta.nix` | 1-11 | Clan metadata + specialArgs | Global flake-parts | - |
| 6 | `modules/flake-parts.nix` | 1-8 | Enables flake.modules merging | Global flake-parts | inputs.flake-parts.flakeModules.modules |
| 7 | `modules/system/nix-settings.nix` | 1-23 | Base nix settings (exports to flake.modules.nixos.base) | Module export | - |
| 8 | `modules/system/caches.nix` | 1-17 | Cache config (exports to flake.modules.nixos.base and darwin.base) | Module export | lib/caches.nix |
| 9 | `modules/system/admins.nix` | - | Admin users (exports to flake.modules.nixos.base) | Module export | - |
| 10 | `modules/system/initrd-networking.nix` | - | Initrd config (exports to flake.modules.nixos.base) | Module export | - |
| 11 | `modules/system/nix-optimization.nix` | - | Store optimization (exports to flake.modules.nixos.base) | Module export | - |
| 12 | `modules/machines/nixos/cinnabar/default.nix` | 1-86 | Cinnabar NixOS config (exports to flake.modules.nixos."machines/nixos/cinnabar") | Module export | flakeModules (from cinnabar.nix) |
| 13 | `modules/machines/nixos/cinnabar/disko.nix` | - | Disko config (merges into machines/nixos/cinnabar) | Module export | - |
| 14 | `modules/machines/nixos/electrum/default.nix` | - | Electrum config | Module export | - |
| 15 | `modules/machines/nixos/electrum/disko.nix` | - | Electrum disko | Module export | - |
| 16 | `modules/machines/nixos/gcp-vm/default.nix` | - | GCP VM config | Module export | - |
| 17 | `modules/machines/darwin/blackphos/default.nix` | - | Blackphos config | Module export | - |
| 18 | `modules/machines/darwin/test-darwin/default.nix` | - | Test Darwin config | Module export | - |
| 19 | `modules/nixpkgs/overlays-option.nix` | 1-32 | Declare flake.nixpkgsOverlays (mergeable list) | Module export | flake-parts-lib |
| 20 | `modules/nixpkgs/overlays/channels.nix` | 1-61 | Multi-channel overlay (appends to flake.nixpkgsOverlays) | Module export | inputs (all channels) |
| 21 | `modules/nixpkgs/overlays/hotfixes.nix` | 1-61 | Platform-specific hotfixes (appends to flake.nixpkgsOverlays) | Module export | final.stable references |
| 22 | `modules/nixpkgs/overlays/overrides.nix` | 1-29 | Package overrides (appends to flake.nixpkgsOverlays) | Module export | - |
| 23 | `modules/nixpkgs/overlays/nvim-treesitter-main.nix` | - | Treesitter overlay (appends to flake.nixpkgsOverlays) | Module export | inputs.nvim-treesitter |
| 24 | `modules/nixpkgs/overlays/fish-stable-darwin.nix` | - | Fish overlay (appends to flake.nixpkgsOverlays) | Module export | - |
| 25 | `modules/nixpkgs/overlays/markdown-tree-parser.nix` | - | Markdown parser overlay (appends to flake.nixpkgsOverlays) | Module export | - |
| 26 | `modules/nixpkgs/compose.nix` | 1-45 | Compose overlays into flake.overlays.default | Module export | config.flake.nixpkgsOverlays |
| 27 | `modules/nixpkgs/per-system.nix` | 1-38 | Create perSystem pkgs instance | perSystem evaluation | config.flake.nixpkgsOverlays, inputs.nuenv |
| 28 | `modules/nixpkgs/default.nix` | 1-19 | Import nixpkgs submodules | Module import | ./overlays-option, ./per-system, ./compose, ./overlays/* |
| 29 | `modules/darwin/*.nix` | - | Darwin-specific modules | Various | - |
| 30 | `modules/home/*.nix` | - | Home-manager configs | Module export | - |
| 31 | `modules/lib/default.nix` | 1-61 | Custom lib utilities (mdFormat, etc.) | Module export | lib |
| 32 | `modules/formatting.nix` | - | Formatter config | Global flake-parts | - |
| 33 | `modules/dev-shell.nix` | - | Dev environment | Global flake-parts | - |
| 34 | `modules/systems.nix` | 1-7 | List of supported systems | Global flake-parts | - |
| 35 | `modules/terranix/*.nix` | - | Terraform/infra config | Global flake-parts | - |
| 36 | `modules/clan/machines.nix` | 1-24 | Import machine modules into clan (references config.flake.modules.*) | Global flake-parts | config.flake.modules.nixos.*, config.flake.modules.darwin.* |

---

## Nixpkgs Instantiation Points

### Point A: perSystem Pkgs (per-system.nix, lines 15-37)

```nix
perSystem = { system, ... }: {
  _module.args.pkgs = import inputs.nixpkgs {
    inherit system;
    config.allowUnfree = true;
    overlays = config.flake.nixpkgsOverlays ++ [ inputs.nuenv.overlays.nuenv ];
  };
};
```

| Aspect | Details |
|--------|---------|
| **Evaluation context** | perSystem hook (per system: x86_64-linux, aarch64-linux, aarch64-darwin) |
| **When created** | During flake-parts module evaluation |
| **Config allowed** | YES - `config.allowUnfree = true` works |
| **Used for** | Checks, packages, devshells, development shells |
| **Scope** | Only within perSystem evaluations |
| **Assertion risk** | None (correct context for config) |

### Point B: Clan Machine Pkgs (clan internally)

```
Clan instantiates independent nixpkgs for each machine:
import inputs.nixpkgs {
  system = machine.system;  # e.g., "x86_64-linux"
  overlays = [ inputs.self.overlays.default ];  # from machines/nixos/cinnabar
};
```

| Aspect | Details |
|--------|---------|
| **Evaluation context** | NixOS/nix-darwin module system (not flake-parts) |
| **When created** | During clan machine evaluation (after all flake-parts modules complete) |
| **Config allowed** | PARTIAL - predicates only (allowUnfreePredicate) |
| **Used for** | Machine system build (nixos-system, nix-darwin system) |
| **Scope** | Independent per-machine |
| **Assertion risk** | HIGH - setting `nixpkgs.config.allowUnfree = true` causes failure |

### Point C: Overlay-Based Pkgs (other flakes)

```
flake.overlays.default = final: prev: {
  # No config here, function-based only
};
```

| Aspect | Details |
|--------|---------|
| **Evaluation context** | Any nixpkgs instantiation |
| **When created** | At overlay application time (flexible) |
| **Config allowed** | NO - overlays are functions, not configs |
| **Used for** | Attribute modifications, custom packages |
| **Scope** | Both perSystem and clan machines |
| **Assertion risk** | None (no config involved) |

---

## Where assertions occur

### Assertion: "Cannot set nixpkgs.config from externally-created instance"

**Trigger code** (machines/nixos/cinnabar/default.nix):
```nix
flake.modules.nixos."machines/nixos/cinnabar" = { config, ... }: {
  nixpkgs.config.allowUnfree = true;  # ← ASSERTION FAILURE
};
```

**Why it fails**:
1. Machine module is evaluated AFTER clan creates nixpkgs instance
2. `nixpkgs.config` option doesn't exist in machine module context
3. Clan uses `import inputs.nixpkgs { ... }` (external creation)
4. Machine module cannot override external instance config

**Correct approach**:
```nix
flake.modules.nixos."machines/nixos/cinnabar" = { lib, ... }: {
  nixpkgs.config.allowUnfreePredicate = pkg:
    builtins.elem (lib.getName pkg) ["graphite-cli" "ngrok"];
};
```

Predicates work because they evaluate AFTER instance creation.

---

## Overlay Composition Chain

```
overlays/*.nix files
  ↓ (each appends to flake.nixpkgsOverlays list)
  ↓
compose.nix
  ↓ (lib.composeManyExtensions flake.nixpkgsOverlays)
  ↓
flake.overlays.default = final: prev: ...
  ↓ (can be used in any context)
  ↓
perSystem pkgs:     inputs.self.overlays.default (via per-system.nix reference)
clan machines:      inputs.self.overlays.default (via machines/*/default.nix)
```

---

## Critical Evaluation Dependencies

### Must happen before clan/machines.nix:
1. flake-parts.nix (enables flake.modules)
2. All machines/*/default.nix (exports to flake.modules.*)
3. All system/*.nix (exports to flake.modules.nixos.base)
4. All nixpkgs/overlays/*.nix (builds flake.nixpkgsOverlays list)
5. nixpkgs/compose.nix (creates flake.overlays.default)

### Must happen for machines to work:
1. clan/core.nix (sets up clan namespace)
2. clan/machines.nix (imports machine definitions)

### Circular? No!
- clan/machines.nix is evaluated AFTER all exports complete
- References to config.flake.modules.* are available by then
- No circular dependencies because modules are evaluated first

---

## Key Configuration Scopes

| Scope | Location | Works? | Example |
|-------|----------|--------|---------|
| **perSystem config** | `modules/nixpkgs/per-system.nix:21` | ✓ YES | `config.allowUnfree = true` |
| **perSystem overlays** | `modules/nixpkgs/per-system.nix:24-30` | ✓ YES | Overlay list |
| **Machine predicate** | `modules/machines/nixos/*/default.nix` | ✓ YES | `allowUnfreePredicate = pkg: ...` |
| **Machine global config** | `modules/machines/nixos/*/default.nix` | ✗ NO | `config.allowUnfree = true` |
| **Overlay functions** | `modules/nixpkgs/overlays/*.nix` | ✓ YES | `(final: prev: { ... })` |
| **Clan meta** | `modules/clan/meta.nix` | ✓ YES | `specialArgs = { inherit inputs; }` |

---

## File Locations Reference

```
/Users/crs58/projects/nix-workspace/test-clan/
├── flake.nix                           # Entry point
├── modules/
│   ├── nixpkgs/
│   │   ├── default.nix                # Imports submodules
│   │   ├── per-system.nix             # perSystem pkgs creation
│   │   ├── compose.nix                # Overlay composition
│   │   ├── overlays-option.nix        # List option declaration
│   │   └── overlays/
│   │       ├── channels.nix           # Multi-channel access
│   │       ├── hotfixes.nix           # Platform hotfixes
│   │       ├── overrides.nix          # Package build mods
│   │       └── ...
│   ├── clan/
│   │   ├── core.nix                   # clan-core import
│   │   ├── machines.nix               # Machine definitions
│   │   ├── meta.nix                   # Clan metadata
│   │   └── inventory/
│   │       └── machines.nix           # Machine inventory
│   ├── system/
│   │   ├── nix-settings.nix           # → flake.modules.nixos.base
│   │   ├── caches.nix                 # → flake.modules.{nixos,darwin}.base
│   │   └── ...
│   ├── machines/
│   │   ├── nixos/
│   │   │   ├── cinnabar/
│   │   │   │   ├── default.nix        # → flake.modules.nixos."machines/nixos/cinnabar"
│   │   │   │   └── disko.nix          # Disko config
│   │   │   ├── electrum/
│   │   │   └── gcp-vm/
│   │   └── darwin/
│   │       ├── blackphos/
│   │       └── test-darwin/
│   ├── flake-parts.nix                # Enable flake.modules
│   └── ...
└── docs/
    └── architecture/
        ├── dendritic-pattern.md       # Pattern explanation
        ├── evaluation-flow-trace.md   # This detailed trace
        └── evaluation-path-summary.md # This file (quick reference)
```

