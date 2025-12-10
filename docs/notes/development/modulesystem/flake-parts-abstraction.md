# Flake-parts as module system abstraction

## Overview

### Intuitive explanation

Flake-parts provides ergonomic access to the Nix module system for creating flakes.
It wraps `lib.evalModules` to evaluate modules with the class `"flake"`, and provides convenient abstractions like `perSystem` for defining per-architecture outputs without manually iterating over system types.
The `flake.modules` namespace allows flakes to publish deferred modules that can be consumed by other configurations (NixOS, nix-darwin, home-manager), creating a reusable module ecosystem.

Think of flake-parts as a specialized framework that:
- Handles the boilerplate of evaluating modules for flake outputs
- Provides the `perSystem` abstraction to avoid repetitive system-specific definitions
- Manages the `systems` option and automatic transposition of per-system attributes to flake outputs
- Enables module discovery and publication through `flake.modules`

### Computational explanation

Flake-parts evaluates modules in two main layers:

**Top-level flake evaluation** (class `"flake"`):
```nix
# lib.nix lines 117-124
lib.evalModules {
  specialArgs = {
    inherit self flake-parts-lib moduleLocation;
    inputs = args.inputs or self.inputs;
  } // specialArgs;
  modules = [ ./all-modules.nix (lib.setDefaultModuleLocation errorLocation module) ];
  class = "flake";
}
```

This creates a module system context where:
- `flake` option accumulates all output attributes
- `perSystem` option holds deferred modules for per-system evaluation
- `systems` lists architectures to enumerate
- `flake.modules` publishes deferred modules for external consumption

**Per-system evaluation** (class `"perSystem"`):
```nix
# modules/perSystem.nix lines 131-138
(lib.evalModules {
  inherit modules;
  prefix = [ "perSystem" system ];
  specialArgs = {
    inherit system;
  };
  class = "perSystem";
}).config
```

For each system in `systems`, flake-parts evaluates the deferred modules from `perSystem` with that specific `system` argument, producing system-specific configuration.
The `allSystems` option memoizes these evaluations.
The transposition module automatically merges these per-system results into flake outputs like `packages.<system>.*`.

The `flake.modules` option uses `deferredModule` type to delay evaluation until the consumer calls `evalModules` with the appropriate class (nixos, darwin, homeManager, etc).

### Formal characterization

Flake-parts can be characterized as a functor from the category of flake-parts modules to the category of flake outputs, with additional structure for per-system computations.

Let $\mathcal{C}_{\text{flake}}$ denote the category where:
- Objects are flake-parts modules (functions from module arguments to option definitions)
- Morphisms are module imports (one module importing another)

Let $\mathcal{C}_{\text{outputs}}$ denote the category where:
- Objects are flake output attribute sets
- Morphisms are attribute set extensions

Then `mkFlake : \mathcal{C}_{\text{flake}} \to \mathcal{C}_{\text{outputs}}` defined by:

```
mkFlake(args, module) = (evalFlakeModule args module).config.flake
```

This functor has additional structure for the per-system abstraction.
Let $\mathcal{S}$ be the set of system strings (e.g., `"x86_64-linux"`, `"aarch64-darwin"`).
The `perSystem` option defines a monoidal action:

```
perSystem : Module_{perSystem} → (S → Config_{perSystem})
```

where `Module_{perSystem}` are modules with class `"perSystem"` and `Config_{perSystem}` is the configuration space of per-system modules.

The transposition operation then acts as a natural transformation from per-system configurations to flake outputs:

```
transpose : (S → Config_{perSystem}) → AttrSet
```

satisfying the coherence condition that for attribute name `a`:

```
(transpose f).a.s = (f s).a
```

The `flake.modules` namespace provides a bifunctor:

```
flake.modules : Class × Name → DeferredModule
```

where:
- `Class` is the set of module classes (nixos, darwin, homeManager, generic, etc.)
- `Name` is the set of module names (strings)
- `DeferredModule` is the type of modules awaiting evaluation

The `deferredModule` type represents a suspended computation in the category of modules, with the merge operation forming a monoid under module concatenation.

## The flake.modules option

### Definition

**Source**: `/Users/crs58/projects/nix-workspace/flake-parts/extras/modules.nix:26-67`

```nix
flake.modules = mkOption {
  type = types.lazyAttrsOf (types.lazyAttrsOf types.deferredModule);
  description = ''
    Groups of modules published by the flake.

    The outer attributes declare the [`class`](https://nixos.org/manual/nixpkgs/stable/#module-system-lib-evalModules-param-class) of the modules within it.
    The special attribute `generic` does not declare a class, allowing its modules to be used in any module class.
  '';
  apply = mapAttrs (k: mapAttrs (addInfo k));
};
```

Where `addInfo` wraps the module with metadata:

```nix
addInfo = class: moduleName:
  if class == "generic"
  then module: module
  else
    module:
    {
      _class = class;
      _file = "${toString moduleLocation}#modules.${escapeNixIdentifier class}.${escapeNixIdentifier moduleName}";
      imports = [ module ];
    };
```

### Type structure

The type is `lazyAttrsOf (lazyAttrsOf deferredModule)` which means:
- First level: module class (nixos, darwin, homeManager, generic, flake)
- Second level: module name
- Value: deferred module

This creates a hierarchical namespace:

```
flake.modules : Class → Name → DeferredModule
```

The `deferredModule` type (from `lib.nix:36-58` or nixpkgs if available) is defined as:

```nix
deferredModuleWith = attrs@{ staticModules ? [] }: mkOptionType {
  name = "deferredModule";
  description = "module";
  check = x: isAttrs x || isFunction x || path.check x;
  merge = loc: defs: staticModules ++ map (def: lib.setDefaultModuleLocation ...) defs;
  inherit (submoduleWith { modules = staticModules; })
    getSubOptions
    getSubModules;
  substSubModules = m: deferredModuleWith (attrs // {
    staticModules = m;
  });
  functor = defaultFunctor "deferredModuleWith" // {
    type = deferredModuleWith;
    payload = { inherit staticModules; };
    binOp = lhs: rhs: {
      staticModules = lhs.staticModules ++ rhs.staticModules;
    };
  };
}
```

Key properties:
- Accepts attribute sets, functions, or paths as modules
- Merges by concatenating static modules with all definitions
- Forms a monoid under `binOp` (module concatenation)
- Defers actual evaluation until consumed by `evalModules`

### Usage in this repository

In `/Users/crs58/projects/nix-workspace/infra/modules/flake-parts.nix`:

```nix
{ inputs, ... }:
{
  imports = [
    inputs.flake-parts.flakeModules.modules # Enable flake.modules merging
    inputs.nix-unit.modules.flake.default
  ];
}
```

The `flakeModules.modules` import loads `/Users/crs58/projects/nix-workspace/flake-parts/extras/modules.nix`, which defines the `flake.modules` option and its merging behavior.

## Abstraction boundaries

### What flake-parts provides (not module system primitives)

These are flake-parts-specific conveniences built on top of the module system:

1. **perSystem abstraction** (`modules/perSystem.nix`)
   - Defines `perSystem` option with `mkPerSystemType`
   - Automatically evaluates modules for each system in `systems`
   - Provides `inputs'`, `self'`, `system` as module arguments
   - Memoizes per-system configurations in `allSystems`

2. **systems option** (`modules/perSystem.nix:73-80`)
   - Declares which architectures to enumerate
   - Used to generate `allSystems` mapping

3. **Flake output generation** (`lib.nix:138-142`)
   - `mkFlake` extracts `config.flake` from evaluation
   - Merges all `flake.*` option definitions into final output

4. **Module discovery coordination** (`extras/modules.nix`)
   - `flake.modules` namespace for publishing modules
   - Automatic `_class` and `_file` metadata injection
   - Merging across multiple flake-parts modules

5. **Transposition** (`modules/transposition.nix`)
   - Automatically merges per-system attributes into `flake.{packages,checks,...}.<system>.*`
   - Defined via `mkTransposedPerSystemModule` helper

6. **withSystem and moduleWithSystem** (`modules/withSystem.nix`, `modules/moduleWithSystem.nix`)
   - Escape hatches for accessing system-specific context in top-level modules
   - Bridge between flake-level and perSystem-level

### What is module system (not flake-parts specific)

These are primitives from nixpkgs `lib.modules` that work independently:

1. **deferredModule type** (`lib.nix:36-58`)
   - Core type for delaying module evaluation
   - Merge semantics: concatenate modules
   - Used by flake-parts but not specific to it

2. **evalModules fixpoint** (nixpkgs `lib.modules.evalModules`)
   - Takes `modules`, `specialArgs`, `class`, `prefix`
   - Returns `{ config, options, type, _module, extendModules, ... }`
   - Fixed-point evaluation of option definitions

3. **Option merging** (nixpkgs `lib.options.mergeDefinitions`)
   - Type-specific merge functions (merge, apply)
   - Priority handling (mkDefault, mkForce, mkOverride)
   - Conflict detection

4. **Module imports** (nixpkgs module system import resolution)
   - Recursive import expansion
   - `_module.args` for passing arguments
   - Conditional imports based on `config`

5. **Module classes** (nixpkgs `lib.evalModules` class parameter)
   - Introduced in nixpkgs to prevent accidental mixing (e.g., NixOS module in home-manager)
   - Flake-parts uses classes `"flake"` and `"perSystem"`
   - Modules can declare `_class` to constrain usage

## Terminology classification

| Term | Classification | Definition | Notes |
|------|---------------|------------|-------|
| flake-parts module | flake-parts specific | A module with class `"flake"` consumed by `flake-parts.lib.mkFlake` | May define `perSystem`, `flake`, `systems` options |
| perSystem module | flake-parts specific | A module with class `"perSystem"` evaluated for each system | Has `system` argument, accessed via `perSystem` option |
| deferred module | module system primitive | The `deferredModule` or `deferredModuleWith` type from nixpkgs | Used for delaying evaluation, not flake-parts specific |
| evalModules | module system primitive | Core function `lib.evalModules` for evaluating module fixpoint | Used by flake-parts but not part of flake-parts |
| perSystem (option) | flake-parts specific | Option of type `deferredModule` that gets evaluated per-system | Convenience for avoiding manual system iteration |
| flake.modules | flake-parts specific | Namespace for publishing deferred modules by class and name | Flake-parts convention, not module system feature |
| module class | module system primitive | String tag preventing cross-context module usage | `"nixos"`, `"darwin"`, `"homeManager"`, `"flake"`, `"perSystem"` |
| transposition | flake-parts specific | Automatic merging of per-system configs into flake outputs | Implemented in `modules/transposition.nix` |
| withSystem | flake-parts specific | Function to access system-specific context in top-level modules | Escape hatch for non-standard output structures |
| allSystems | flake-parts specific | Memoized mapping from system to perSystem config | Internal implementation detail of perSystem |
| inputs' / self' | flake-parts specific | System-specific views of inputs via `perInput` function | Module arguments in perSystem modules only |

## Implications for documentation

When documenting this repository:

1. **Use "deferred module" when explaining the fundamental concept**
   - Example: "The dendritic pattern uses deferred modules to delay evaluation until import time"
   - Links to module system primitives to explain why patterns work

2. **Use "flake-parts module" when explaining flake-parts integration specifically**
   - Example: "Each flake-module.nix is a flake-parts module that contributes to the final flake outputs"
   - Clarifies we're working within the flake-parts framework

3. **Use "perSystem module" when discussing per-system definitions**
   - Example: "Define packages in the perSystem module to automatically generate per-architecture outputs"
   - Distinguishes from top-level flake-parts modules

4. **Always link to module system primitives when explaining why patterns work**
   - Example: "This works because deferredModule merges by concatenating modules, allowing composition"
   - Grounds flake-parts patterns in underlying module system semantics

5. **Distinguish flake-parts conveniences from module system requirements**
   - Example: "While flake-parts provides perSystem for ergonomics, the underlying pattern is manually iterating over systems with deferred modules"
   - Helps users understand what's framework and what's fundamental

6. **Clarify when something is specific to our architecture vs general flake-parts**
   - Example: "The dendritic pattern's use of import-tree for auto-discovery is specific to our architecture, not a flake-parts feature"
   - Helps users understand what they'd find in other flake-parts projects

### Key insight

Following hsjobeki's clarification: **the dendritic pattern is fundamentally about deferred modules, not flake-parts**.

Flake-parts is one ergonomic way to work with deferred modules in a flake context, but:
- Deferred modules exist in nixpkgs and work independently
- You could use deferred modules with raw `evalModules` calls
- Flake-parts adds conveniences like `perSystem`, `flake.modules`, and transposition
- The dendritic pattern's core insight (auto-discovered deferred modules) is module system level
- Flake-parts just happens to be how we integrate it into our flake

This means our documentation should:
- Explain deferred modules first (module system level)
- Show how flake-parts uses them (framework level)
- Present dendritic as an organizational pattern (our architecture level)
- Avoid conflating the three layers

## References

- Nixpkgs module system documentation: https://nixos.org/manual/nixpkgs/stable/#module-system
- Module classes RFC: https://github.com/NixOS/rfcs/pull/146
- Flake-parts documentation: https://flake.parts
- `deferredModule` in nixpkgs: https://github.com/NixOS/nixpkgs/pull/163617
- `deferredModuleWith` in nixpkgs: https://github.com/NixOS/nixpkgs/pull/344216

## Examples

### Example 1: Publishing a NixOS module via flake.modules

```nix
# Some flake-parts module in our flake
{ ... }:
{
  flake.modules.nixos.my-service = { config, lib, pkgs, ... }: {
    options.services.my-service = {
      enable = lib.mkEnableOption "my service";
    };
    config = lib.mkIf config.services.my-service.enable {
      systemd.services.my-service = { ... };
    };
  };
}
```

After merging, consumers can import with:
```nix
# In another flake
{
  inputs.our-flake.url = "...";
  outputs = { nixpkgs, our-flake, ... }: {
    nixosConfigurations.my-host = nixpkgs.lib.nixosSystem {
      modules = [
        our-flake.modules.nixos.my-service
        { services.my-service.enable = true; }
      ];
    };
  };
}
```

### Example 2: Using perSystem for per-architecture packages

```nix
# Flake-parts module
{ ... }:
{
  perSystem = { config, pkgs, system, ... }: {
    packages.my-package = pkgs.writeShellScriptBin "hello" ''
      echo "Hello from ${system}"
    '';
  };
}
```

Flake-parts automatically:
1. Evaluates this perSystem module for each system in `systems`
2. Collects results into `allSystems`
3. Transposes into `flake.packages.<system>.my-package`

### Example 3: Raw deferred module without flake-parts

To illustrate that deferred modules are module system primitives:

```nix
# Without flake-parts
let
  nixpkgs = import <nixpkgs> {};
  deferredModule = { config, lib, ... }: {
    options.foo = lib.mkOption { type = lib.types.int; };
  };
in
nixpkgs.lib.evalModules {
  modules = [
    deferredModule
    { foo = 42; }
  ];
}
# => { config = { foo = 42; }; options = ...; }
```

This works without any flake-parts code, proving `deferredModule` is a nixpkgs primitive.
