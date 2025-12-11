---
title: Flake-parts and the module system
description: How flake-parts wraps nixpkgs evalModules to provide flake composition, perSystem evaluation, and namespace conventions
sidebar:
  order: 4
---

Flake-parts provides ergonomic access to the Nix module system for creating flakes.
It wraps `lib.evalModules` to evaluate modules with specialized abstractions for flake outputs, per-system evaluation, and module publication.
Understanding what flake-parts adds on top of the base module system is critical for working with dendritic architectures.

## What flake-parts provides

Flake-parts is not a replacement for the module system, but a specialized framework that adds flake-specific conveniences on top of nixpkgs `lib.evalModules`.
These conveniences handle the boilerplate of creating flake outputs while preserving the composability of the underlying module system.

### The perSystem abstraction

The `perSystem` option eliminates manual iteration over system types when defining per-architecture outputs.
Instead of writing repetitive code for each system string (`"x86_64-linux"`, `"aarch64-darwin"`, etc.), you define packages, apps, and checks once in a perSystem module.

```nix
{ ... }:
{
  perSystem = { config, pkgs, system, ... }: {
    packages.hello = pkgs.writeShellScriptBin "hello" ''
      echo "Hello from ${system}"
    '';
  };
}
```

Flake-parts automatically evaluates this module for each system listed in the `systems` option, producing system-specific configurations that get transposed into flake outputs like `packages.<system>.hello`.

### The flake.modules namespace

The `flake.modules` option creates a conventional namespace for publishing deferred modules that can be consumed by other configurations (NixOS, nix-darwin, home-manager).
This enables flakes to export modules as reusable components.

```nix
{ ... }:
{
  flake.modules.nixos.my-service = { config, lib, pkgs, ... }: {
    options.services.my-service.enable = lib.mkEnableOption "my service";
    config = lib.mkIf config.services.my-service.enable {
      systemd.services.my-service = { /* ... */ };
    };
  };
}
```

Consumers can then import these modules in their own configurations:

```nix
{
  inputs.our-flake.url = "github:org/repo";
  outputs = { nixpkgs, our-flake, ... }: {
    nixosConfigurations.host = nixpkgs.lib.nixosSystem {
      modules = [
        our-flake.modules.nixos.my-service
        { services.my-service.enable = true; }
      ];
    };
  };
}
```

The namespace structure is `flake.modules.<class>.<name>` where `class` identifies the module system context (nixos, darwin, homeManager, generic, flake) and `name` is the module identifier.

### Automatic transposition

The transposition module automatically merges per-system attributes from `perSystem` evaluations into conventional flake output locations.
When you define `packages.hello` in a perSystem module, flake-parts creates `flake.packages.<system>.hello` for each system without explicit configuration.

This handles the mapping from per-system configurations to the flat attribute structure expected by flake outputs.

### System-specific context access

The `withSystem` and `moduleWithSystem` helpers provide escape hatches for accessing system-specific context in top-level flake modules.
These bridge the gap between flake-level (class `"flake"`) and perSystem-level (class `"perSystem"`) evaluation contexts.

## Two-layer evaluation model

Flake-parts evaluates modules in two distinct layers, each using `lib.evalModules` with different module classes.

### Top-level flake evaluation

The first layer evaluates modules with class `"flake"` to produce the overall flake structure:

```nix
# From flake-parts lib.nix
lib.evalModules {
  specialArgs = {
    inherit self flake-parts-lib moduleLocation;
    inputs = args.inputs or self.inputs;
  } // specialArgs;
  modules = [ ./all-modules.nix module ];
  class = "flake";
}
```

This evaluation creates a module system context where:
- The `flake` option accumulates all output attributes
- The `perSystem` option holds deferred modules for per-system evaluation
- The `systems` option lists architectures to enumerate
- The `flake.modules` namespace publishes modules for external consumption

The final flake outputs come from extracting `config.flake` after this evaluation completes.

### Per-system evaluation

For each system in the `systems` list, flake-parts evaluates the deferred modules from `perSystem` with class `"perSystem"`:

```nix
# From flake-parts modules/perSystem.nix
(lib.evalModules {
  inherit modules;
  prefix = [ "perSystem" system ];
  specialArgs = { inherit system; };
  class = "perSystem";
}).config
```

Each per-system evaluation receives:
- The specific `system` string as a module argument
- System-specific input views via `inputs'` and `self'`
- Access to `config`, `pkgs`, and other perSystem options

The `allSystems` option memoizes these evaluations as a mapping from system strings to perSystem configurations.
The transposition module then merges these configurations into the top-level flake outputs.

## Module classes in flake-parts

Module classes prevent accidental mixing of modules from incompatible contexts.
The nixpkgs module system supports classes via the `class` parameter to `evalModules` and the `_class` module attribute.

Flake-parts uses two primary module classes:

- **`"flake"`** - Top-level flake-parts modules that define `flake`, `perSystem`, `systems` options
- **`"perSystem"`** - Per-system modules evaluated with specific system context

The `flake.modules` namespace supports publishing modules for external classes:

- **`nixos`** - NixOS system modules
- **`darwin`** - nix-darwin system modules
- **`homeManager`** - home-manager user modules
- **`generic`** - Class-agnostic modules that work in any context
- **`flake`** - Nested flake-parts modules

When you define `flake.modules.nixos.my-module`, flake-parts automatically wraps it with `_class = "nixos"` metadata to ensure type safety.

## The deferredModule type

The `flake.modules` option uses the `deferredModule` type to delay evaluation until the consumer calls `evalModules` with the appropriate class.
This type is a nixpkgs primitive, not a flake-parts invention.

The type is defined as `lazyAttrsOf (lazyAttrsOf deferredModule)`:
- First level: module class (nixos, darwin, homeManager, generic, flake)
- Second level: module name
- Value: deferred module content

A deferred module accepts attribute sets, functions, or paths as module definitions and merges them by concatenating into a module list.
The actual evaluation happens when a consumer imports the module into their own `evalModules` call.

```nix
# Publishing side (flake-parts)
flake.modules.nixos.example = { config, lib, ... }: {
  options.foo = lib.mkOption { type = lib.types.str; };
};

# Consuming side (NixOS configuration)
nixpkgs.lib.nixosSystem {
  modules = [
    inputs.our-flake.modules.nixos.example
    { foo = "bar"; }
  ];
}
```

This pattern enables module composition across flake boundaries without premature evaluation.

## How dendritic builds on flake-parts

The dendritic pattern uses flake-parts as its integration layer for producing flake outputs, but extends it with auto-discovery and structured module organization.

Key additions in dendritic architectures:

- **import-tree for auto-discovery** - Automatically discovers and imports modules from directory structures
- **Namespace sharding** - Organizes modules by concern (configurations, modules, packages, systems)
- **Hierarchical composition** - Modules at each level contribute to merged outputs

These are organizational patterns specific to aspect-based deferred module composition architectures, not features of flake-parts itself.
The deferred module composition pattern fundamentally relies on deferred modules (a module system primitive), uses flake-parts for ergonomic flake integration, and adds its own conventions for module discovery and composition.

For details on the underlying module system primitives, see [Module system primitives](/concepts/module-system-primitives/).
For details on the deferred module composition pattern, see [Deferred module composition](/concepts/deferred-module-composition/).

## External references

- [Flake-parts documentation](https://flake.parts) - Official flake-parts reference
- [Nixpkgs module system](https://nixos.org/manual/nixpkgs/stable/#module-system) - Base module system documentation
- [Module classes RFC](https://github.com/NixOS/rfcs/pull/146) - Design rationale for module classes
- [deferredModule in nixpkgs](https://github.com/NixOS/nixpkgs/pull/163617) - Implementation of deferred module type
