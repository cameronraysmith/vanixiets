# Test-Clan Evaluation Flow - Visual Diagrams

## Complete Evaluation Flow (Single Diagram)

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                            FLAKE.NIX ENTRY POINT                             │
│                     (single line: import-tree ./modules)                      │
└──────────────────────────────────────────────────────────────────────────────┘
                                       ↓
        ┌──────────────────────────────────────────────────────────┐
        │    IMPORT-TREE AUTO-DISCOVERY & FILESYSTEM TRAVERSAL     │
        │                                                           │
        │ Discovers all .nix files in modules/ recursively         │
        │ Returns function for flake-parts eval-modules            │
        └──────────────────────────────────────────────────────────┘
                                       ↓
┌──────────────────────────────────────────────────────────────────────────────┐
│                 FLAKE-PARTS EVAL-MODULES SYSTEM (PHASE 1)                    │
│                                                                              │
│ Evaluates all modules in filesystem order, merging identical namespaces:    │
│                                                                              │
│  1. modules/checks/*.nix                    (test/validation modules)        │
│  2. modules/clan/core.nix                   (imports clan-core flakeModule)  │
│  3. modules/clan/inventory/machines.nix     (declares inventory)             │
│  4. modules/clan/meta.nix                   (metadata + specialArgs)         │
│  5. modules/flake-parts.nix                 (enables flake.modules merging)  │
│  6. modules/system/*.nix                    (→ flake.modules.nixos.base)    │
│  7. modules/machines/nixos/*.nix            (→ flake.modules.nixos.*)       │
│  8. modules/machines/darwin/*.nix           (→ flake.modules.darwin.*)      │
│  9. modules/nixpkgs/overlays-option.nix     (declare list option)            │
│ 10. modules/nixpkgs/overlays/*.nix          (→ flake.nixpkgsOverlays list)  │
│ 11. modules/nixpkgs/compose.nix             (→ flake.overlays.default)      │
│ 12. modules/nixpkgs/per-system.nix          (creates perSystem pkgs)         │
│ 13. modules/clan/machines.nix               (imports config.flake.modules.*) │
│ 14. [remaining modules]                     (darwin, home, lib, etc.)        │
│                                                                              │
│ OUTPUT: config.flake.* namespace populated with:                            │
│  • flake.modules.nixos.* (all machine defs + base)                          │
│  • flake.modules.darwin.* (all machine defs + base)                         │
│  • flake.nixpkgsOverlays (list of overlay functions)                        │
│  • flake.overlays.default (composed overlays)                               │
│  • clan.machines.* (with imports from flake.modules.*)                      │
└──────────────────────────────────────────────────────────────────────────────┘
                        ↓                                  ↓
        ┌───────────────────────────────┐    ┌───────────────────────────────┐
        │     FLAKE-PARTS perSystem      │    │      CLAN ORCHESTRATION       │
        │         PATH (PHASE 2)         │    │         PATH (PHASE 3)        │
        └───────────────────────────────┘    └───────────────────────────────┘
                        ↓                                  ↓
┌──────────────────────────────┐              ┌──────────────────────────────┐
│ For each system:             │              │ For each machine:            │
│  - x86_64-linux              │              │  - cinnabar (nixos)          │
│  - aarch64-linux             │              │  - electrum (nixos)          │
│  - aarch64-darwin            │              │  - gcp-vm (nixos)            │
│                              │              │  - blackphos (darwin)        │
│ Create pkgs via:             │              │  - test-darwin (darwin)      │
│  import inputs.nixpkgs {     │              │                              │
│    inherit system;           │              │ Clan evaluates in order:     │
│    config.allowUnfree=true;  │              │  1. Load machine def from    │
│    overlays = [              │              │     config.flake.modules.*   │
│      config.flake.           │              │  2. Clan instantiates        │
│        nixpkgsOverlays       │              │     independent nixpkgs      │
│      + inputs.nuenv.overlay  │              │  3. Evaluate machine module  │
│    ]                         │              │     in NixOS/nix-darwin ctx  │
│  }                           │              │  4. Apply overlays from      │
│                              │              │     inputs.self.overlays.*   │
│ Evaluate:                    │              │  5. Apply allowUnfreePred    │
│  • checks                    │              │  6. Generate system build    │
│  • packages                  │              │                              │
│  • devshells                 │              │ Machine modules receive:     │
│  • apps                      │              │  { config, pkgs, lib, ... }  │
│                              │              │                              │
│ SUCCESS:                     │              │ Output: System derivation    │
│ pkgs available in checks,    │              │  /nix/store/xxx-nixos-sys.* │
│ packages, devshells          │              │  /nix/store/xxx-darwin-sys.* │
└──────────────────────────────┘              └──────────────────────────────┘
        ↓                                                  ↓
    perSystem outputs                          nixosConfigurations.*
    - nix flake check ✓                        darwinConfigurations.*
    - packages                                 clanInternals.machines.*
    - devShells
```

---

## Nixpkgs Instantiation Contexts

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                 TWO INDEPENDENT NIXPKGS INSTANTIATIONS                      │
└─────────────────────────────────────────────────────────────────────────────┘

┌──────────────────────────────────┐   ┌──────────────────────────────────┐
│  INSTANCE A: perSystem Pkgs      │   │  INSTANCE B: Clan Machine Pkgs   │
│  (modules/nixpkgs/per-system.nix │   │  (clan-core internal)            │
│   lines 15-37)                   │   │                                  │
├──────────────────────────────────┤   ├──────────────────────────────────┤
│ Creation Code:                   │   │ Creation Code:                   │
│                                  │   │                                  │
│ perSystem = { system, ... }: {   │   │ Clan internally:                 │
│   _module.args.pkgs =            │   │                                  │
│     import inputs.nixpkgs {      │   │ import inputs.nixpkgs {          │
│       inherit system;            │   │   system = machine.system;       │
│       config.allowUnfree=true;   │   │   overlays = [...]               │
│       overlays = [               │   │ }                                │
│         config.flake.            │   │                                  │
│           nixpkgsOverlays +      │   │ NO config.allowUnfree here!      │
│         inputs.nuenv.overlay     │   │                                  │
│       ];                         │   │                                  │
│     };                           │   │                                  │
│   pkgsDirectory = ./pkgs/...;    │   │                                  │
│ };                               │   │                                  │
├──────────────────────────────────┤   ├──────────────────────────────────┤
│ Evaluation Context:              │   │ Evaluation Context:              │
│ • perSystem (per-system)         │   │ • NixOS/nix-darwin module system │
│ • x86_64-linux                   │   │ • After all flake-parts modules  │
│ • aarch64-linux                  │   │ • Independent per-machine        │
│ • aarch64-darwin                 │   │                                  │
├──────────────────────────────────┤   ├──────────────────────────────────┤
│ Config Allowed:                  │   │ Config Allowed:                  │
│ ✓ YES                            │   │ ✗ NO (assertion failure)         │
│   config.allowUnfree = true      │   │                                  │
│                                  │   │ ✓ YES (uses predicates)          │
│                                  │   │   allowUnfreePredicate = pkg:... │
├──────────────────────────────────┤   ├──────────────────────────────────┤
│ Used By:                         │   │ Used By:                         │
│ • Checks                         │   │ • Machine system build           │
│ • Packages                       │   │ • NixOS system derivation        │
│ • DevShells                      │   │ • nix-darwin system derivation   │
│ • Custom apps                    │   │                                  │
├──────────────────────────────────┤   ├──────────────────────────────────┤
│ Overlays Applied:                │   │ Overlays Applied:                │
│ • flake.nixpkgsOverlays (list)   │   │ • inputs.self.overlays.default   │
│ • inputs.nuenv.overlays.nuenv    │   │   (from machines/*/default.nix)  │
│                                  │   │                                  │
│ = Complete overlay composition   │   │ = Composed overlays from all 5   │
│                                  │   │   internal overlay layers        │
└──────────────────────────────────┘   └──────────────────────────────────┘
        ↓                                       ↓
   Checks work                         Machine builds work
   Packages available                  IF using allowUnfreePredicate
   DevShells available                 FAILS IF using config.allowUnfree
```

---

## Overlay Composition Pipeline

```
┌─────────────────────────────────────────────────────────────────────────┐
│               OVERLAY COMPOSITION PIPELINE (Detailed)                   │
└─────────────────────────────────────────────────────────────────────────┘

LAYER 1: INDIVIDUAL OVERLAY MODULES
├─ modules/nixpkgs/overlays/channels.nix
│  └─ Appends to: flake.nixpkgsOverlays = [ (final: prev: { ... }) ]
├─ modules/nixpkgs/overlays/hotfixes.nix
│  └─ Appends to: flake.nixpkgsOverlays = [ (final: prev: { ... }) ]
├─ modules/nixpkgs/overlays/overrides.nix
│  └─ Appends to: flake.nixpkgsOverlays = [ (final: prev: { ... }) ]
├─ modules/nixpkgs/overlays/nvim-treesitter-main.nix
│  └─ Appends to: flake.nixpkgsOverlays = [ (final: prev: { ... }) ]
└─ modules/nixpkgs/overlays/fish-stable-darwin.nix
   └─ Appends to: flake.nixpkgsOverlays = [ (final: prev: { ... }) ]

   RESULT: flake.nixpkgsOverlays = [
             overlay1, overlay2, overlay3, overlay4, overlay5
           ]

                             ↓ (merged list via dendritic pattern)

LAYER 2: OPTION DECLARATION
├─ modules/nixpkgs/overlays-option.nix
│  └─ Declares flake.nixpkgsOverlays as mergeable list option
│     Allows multiple modules to append without conflicts

                             ↓

LAYER 3: COMPOSITION
├─ modules/nixpkgs/compose.nix (lines 22-44)
│  
│  flake.overlays.default = final: prev:
│    let
│      internalOverlays = 
│        lib.composeManyExtensions config.flake.nixpkgsOverlays
│      # Composes 5 overlays into single composite function
│      
│      nuenvOverlay = inputs.nuenv.overlays.nuenv
│      customPackages = pkgs-by-name auto-discovered packages
│    in
│    (internalOverlays final prev) // customPackages // (nuenvOverlay final prev)
│    
│  RESULT: Single overlay function that applies all 5 layers in order

                             ↓ (can be used anywhere)

LAYER 4A: perSystem APPLICATION
├─ modules/nixpkgs/per-system.nix (lines 24-30)
│  └─ overlays = config.flake.nixpkgsOverlays ++ [inputs.nuenv.overlays.nuenv]
│     
│     Applied to: import inputs.nixpkgs { inherit system; overlays = [...]; }
│     
│     RESULT: perSystem pkgs with all overlays + nuenv

LAYER 4B: Clan Machine APPLICATION
├─ modules/machines/nixos/cinnabar/default.nix (line 41)
│  └─ nixpkgs.overlays = [ inputs.self.overlays.default ]
│     
│     Applied by: clan during machine evaluation
│     
│     RESULT: Machine nixpkgs with composed overlays

                             ↓

FINAL OVERLAY STACK
├─ channels.nix output      (pkgs.stable, pkgs.unstable, etc.)
├─ hotfixes.nix output      (micromamba from stable, etc.)
├─ overrides.nix output     (package build customizations)
├─ nvim-treesitter-main.nix output
├─ fish-stable-darwin.nix output
├─ custom packages (pkgs-by-name)
└─ external overlays (nuenv)
   
   = Complete pkgs attribute set available to all evaluations
```

---

## Module Export Flow (Dendritic Pattern)

```
┌──────────────────────────────────────────────────────────────────────────┐
│                    DENDRITIC MODULE EXPORT FLOW                          │
│              (How config.flake.modules.* gets populated)                 │
└──────────────────────────────────────────────────────────────────────────┘

STEP 1: INDIVIDUAL MODULE FILES EXPORT
┌────────────────────────────────────┐   ┌────────────────────────────────┐
│ modules/system/nix-settings.nix    │   │ modules/system/caches.nix      │
├────────────────────────────────────┤   ├────────────────────────────────┤
│ flake.modules.nixos.base = { ... } │   │ flake.modules.nixos.base = ... │
│  nix.settings.experimental-features│   │ nix.settings.substituters      │
│  nix.settings.trusted-users        │   │ nix.settings.trusted-public... │
└────────────────────────────────────┘   └────────────────────────────────┘
               ↓                                        ↓
              (export to flake.modules.nixos.base)    (export to flake.modules.nixos.base)

                          ↓
                   
              STEP 2: EVAL-MODULES DEEP MERGE
              
              All three modules declare: flake.modules.nixos.base = { ... }
              
              Flake-parts eval-modules sees identical namespace and:
              • Deep merges all attributes from all modules
              • Result: single flake.modules.nixos.base with all attributes
              
                          ↓
                   
              STEP 3: COMBINED MODULE AVAILABLE
              
┌─────────────────────────────────────────────────────────────────────────┐
│ config.flake.modules.nixos.base (auto-merged)                           │
├─────────────────────────────────────────────────────────────────────────┤
│ {                                                                       │
│   # From nix-settings.nix                                              │
│   nix.settings.experimental-features = ["nix-command" "flakes"];       │
│   nix.settings.trusted-users = ["root" "@wheel"];                      │
│   system.stateVersion = lib.mkDefault "24.11";                         │
│                                                                         │
│   # From caches.nix                                                     │
│   nix.settings.substituters = [...];                                    │
│   nix.settings.trusted-public-keys = [...];                             │
│                                                                         │
│   # From admins.nix                                                     │
│   [admin user config...]                                               │
│                                                                         │
│   # [other base modules...]                                            │
│ }                                                                       │
└─────────────────────────────────────────────────────────────────────────┘
                          ↓

              STEP 4: IMPORTED BY MACHINE MODULES
              
┌────────────────────────────────────────────────────────┐
│ modules/machines/nixos/cinnabar/default.nix (line 20)  │
├────────────────────────────────────────────────────────┤
│ imports = with flakeModules; [                         │
│   base    # ← This references the auto-merged base     │
│   inputs.srvos.nixosModules.server                     │
│   ...                                                  │
│ ];                                                      │
└────────────────────────────────────────────────────────┘
                          ↓

              STEP 5: USED IN CLAN MACHINE EVALUATION
              
              Clan evaluates cinnabar machine module:
              • Loads flake.modules.nixos."machines/nixos/cinnabar"
              • This module imports flake.modules.nixos.base
              • All base config (nix settings, caches, admins) applies
              • Machine-specific config layered on top

═══════════════════════════════════════════════════════════════════════════

KEY INSIGHT: Dendritic Pattern avoids repetition

TRADITIONAL APPROACH:
┌─ modules/machines/nixos/cinnabar/default.nix
│  └─ imports = [
│       (nix settings module)
│       (caches module)
│       (admins module)
│       (other base modules)
│     ];
│  Problem: Every machine must import all base modules manually

DENDRITIC APPROACH:
┌─ modules/machines/nixos/cinnabar/default.nix
│  └─ imports = [ flake.modules.nixos.base ];
│     # flake.modules.nixos.base already has everything merged
│  Benefit: Single import references all base config

Result: flake.modules.nixos.base acts as a bundle
```

---

## Assertion Failure Timeline

```
TIMELINE: When does the assertion fire?

T=0: flake-parts eval-modules starts
     All modules evaluated, namespaces built
     
     ✓ config.flake.modules.nixos.* = fully populated
     ✓ config.flake.overlays.default = fully composed
     ✓ clan.machines.cinnabar = defined with imports

T=1: perSystem evaluations (x86_64-linux, aarch64-linux, aarch64-darwin)
     
     ✓ Per-system pkgs created with config.allowUnfree = true
     ✓ Checks run
     ✓ Packages built
     ✓ DevShells available

T=2: Clan orchestration begins
     
     For cinnabar (first machine):
     
     T=2.1: Clan loads machine definition
            clan.machines.cinnabar.imports = [
              config.flake.modules.nixos."machines/nixos/cinnabar"
            ]
            ✓ This succeeds - module is available
     
     T=2.2: Clan instantiates nixpkgs for x86_64-linux
            import inputs.nixpkgs {
              system = "x86_64-linux";
              overlays = [...];
              # NO config here!
            }
            ✓ This succeeds - independent instance created
     
     T=2.3: Clan evaluates machine module in nixpkgs context
            Module receives: { config, pkgs, lib, ... }
            
            Module code executes:
            { config, pkgs, lib, ... }: {
              nixpkgs.hostPlatform = "x86_64-linux";     ✓ OK
              nixpkgs.overlays = [...];                  ✓ OK
              nixpkgs.config.allowUnfree = true;         ✗ ASSERTION!
              
              # At this point, nixpkgs.config option doesn't exist
              # because nixpkgs was instantiated before module eval
              # The assertion fires:
              # "Cannot set option from externally-created instance"
            }

SOLUTION: Use allowUnfreePredicate instead
          { lib, ... }: {
            nixpkgs.config.allowUnfreePredicate = pkg:
              builtins.elem (lib.getName pkg) ["graphite-cli"];
          }
          
          ✓ allowUnfreePredicate evaluates AFTER instance creation
          ✓ Predicate is applied at package evaluation time
          ✓ No assertion because option already exists
```

---

## Quick Context Selector

```
WHICH CONFIGURATION CONTEXT AM I IN?

┌─────────────────────────────────┐
│ Are you editing...              │
└─────────────────────────────────┘
           │
     ┌─────┴─────┐
     ↓           ↓
  modules/      modules/
  nixpkgs/      machines/
   per-system   nixos/
              default.nix
     │              │
     ↓              ↓
┌─────────┐    ┌──────────┐
│perSystem│    │Clan      │
│context  │    │context   │
├─────────┤    ├──────────┤
│Config   │    │Config    │
│allowed: │    │allowed:  │
│✓ YES    │    │✗ NO      │
│         │    │✓ Pred.   │
│Overlays │    │Overlays  │
│allowed: │    │allowed:  │
│✓ YES    │    │✓ YES     │
├─────────┤    ├──────────┤
│Use for: │    │Use for:  │
│• Checks │    │• System  │
│• Pkgs   │    │• Build   │
│• Dev    │    │• Derive  │
│         │    │• Config  │
└─────────┘    └──────────┘
     │              │
     └──────┬───────┘
            ↓
      ┌──────────────────┐
      │ Want to configure│
      │ unfree packages? │
      └──────────────────┘
             │
        ┌────┴────┐
        ↓         ↓
   perSystem   Machine
     │            │
     ✓ Use:       ✓ Use:
   config.     allowUnfree
   allowUnfree Predicate
   = true      = pkg: ...
```

