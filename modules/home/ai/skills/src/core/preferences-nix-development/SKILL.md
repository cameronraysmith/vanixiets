---
name: preferences-nix-development
description: >
  Nix development conventions for flakes, derivations, modules, and code style.
  Use when authoring flake.nix files, writing derivations or builders, designing
  NixOS/nix-darwin/home-manager modules, or following nix formatting and naming
  conventions. For check architecture and CI integration, see
  preferences-nix-checks-architecture and preferences-nix-ci-cd-integration.
---

# Nix development

- Most projects should contain a nix flake in `flake.nix` to provide devshell development environments, package builds, and OCI container image builds
- Verify builds with `nix flake check` and `nix build`

## Flakes and modules
- Use flakes for all nix projects, not channels
- Use hercules-ci/flake-parts to structure flake.nix files modularly where relevant
  - package: nix/modules/{devshell,containers,packages,overrides}.nix
- Use nixos-unified for system configurations and autoWire for module discovery
  - system: modules/{home,darwin,nixos,flake-parts}/

## Best practices
- Follow nixpkgs naming conventions and style
- Use `inputs.*.follows = "nixpkgs"` to minimize flake input duplication
- Place system-level config in modules/darwin/ or modules/nixos/
- Place user-level config in modules/home/all/ (cross-platform) or darwin-only.nix/linux-only.nix
- Use home-manager.sharedModules for platform-specific home configuration

## Shell scripts and writeShellApplication

`pkgs.writeShellApplication` runs shellcheck during its `checkPhase`.
`nix build --dry-run` evaluates the derivation graph but does not execute build phases, so it will not catch shellcheck errors.

Run `shellcheck <file>` directly on shell scripts before committing.
This is faster than a full `nix build` and catches the same class of errors that `checkPhase` would surface.
A full `nix build` (without `--dry-run`) of the relevant derivation remains the definitive verification, as it executes `checkPhase` with the exact shellcheck configuration the derivation specifies.

## Nix code style
- Format with `nix fmt`
- Use explicit function arguments, not `with` statements
- Prefer `inherit (x) y z;` over `inherit y z;`
- Use `lib.mkIf`, `lib.mkMerge`, `lib.mkDefault` appropriately

## Derivation authoring patterns

### mkDerivation anatomy

`stdenv.mkDerivation` builds packages through a sequence of phases: `unpackPhase`, `patchPhase`, `configurePhase`, `buildPhase`, `installPhase`, and `checkPhase`.
Each phase can be overridden independently, and `checkPhase` runs only when `doCheck = true`.

`nativeBuildInputs` provides tools needed at build time that run on the build platform: compilers, code generators, `pkg-config`, `cmake`, `meson`.
`buildInputs` provides libraries and packages needed at runtime or that propagate to downstream consumers.
When cross-compiling, this distinction determines which packages target the build platform versus the host platform.
Conflating the two causes silent failures in cross-compilation and missing runtime dependencies.

### Language-specific builders

Rust packages use crane, which separates dependency compilation from source compilation for incremental caching.
The typical pattern chains `buildDepsOnly` (compiles only Cargo dependencies), `buildPackage` (compiles project source against cached deps), `cargoClippy` (lint check), and `cargoNextest` (test runner).
For PyO3/maturin hybrid packages that produce Python wheels from Rust source, crane-maturin provides `buildMaturinPackage`.
Reference repo: `~/projects/nix-workspace/crane-maturin`.

Python packaging uses uv2nix and pyproject-nix rather than nixpkgs' `buildPythonPackage`.
The uv2nix approach reads `uv.lock` files via `workspace.loadWorkspace`, produces nix overlays through `mkPyprojectOverlay`, and composes them with `pyproject-build-systems` into a Python package set.
`mkVirtualEnv` produces the final installable environment.
Reference repos: `~/projects/nix-workspace/pyproject.nix`, `~/projects/nix-workspace/uv2nix`.
The nixpkgs `buildPythonPackage` remains a fallback for packages not managed by uv that need nix-specific fixups.

JavaScript packages use bun2nix with `fetchBunDeps` for reproducible dependency fetching from `bun.lock` files.

### Overlay authoring

Prefer `pkgs-by-name-for-flake-parts` auto-discovery from `pkgs/by-name/` over manual overlay definitions.
Each subdirectory under `pkgs/by-name/` contains a `package.nix` that receives `{ lib, pkgs, ... }` and returns a derivation, mirroring the nixpkgs `pkgs/by-name` convention.
Use explicit overlays when modifying existing nixpkgs packages or when cross-package composition requires it.

### writeShellApplication enhancements

Beyond the basic `text` attribute, `writeShellApplication` supports structured configuration.
`runtimeInputs` adds packages to `PATH` at runtime without polluting the build environment.
`runtimeEnv` injects environment variables as shell assignments at the top of the script.
The `env` attribute provides build-time environment variables visible during `checkPhase` as well.
These mechanisms replace ad-hoc `export` statements and `makeWrapper` calls for simple shell scripts.

## Module authoring patterns

### Option declarations

`mkOption` declares a module option with `type`, `default`, and `description` attributes.
`mkEnableOption` is shorthand for a boolean option defaulting to `false` with a standardized description, conventionally used as `enable = mkEnableOption "the service name"`.

The `types` vocabulary covers the common shapes: `types.str`, `types.int`, `types.bool`, `types.path`, `types.package` for scalars; `types.listOf`, `types.attrsOf` for collections; `types.submodule` for nested option sets; `types.enum` for closed alternatives; `types.nullOr` for optional values.
`types.submodule` accepts a module function and composes recursively, enabling arbitrarily nested configuration schemas.

### Module structure

A NixOS, nix-darwin, or home-manager module is a function with the signature `{ config, lib, pkgs, ... }:` that returns an attribute set.
The returned set splits into `options` (declaring the module's configurable interface) and `config` (setting values that take effect when the module is enabled).
`imports` lists other modules to compose, and the module system merges all imported option declarations and configuration values according to their priority and merge rules.

Separating `options` from `config` keeps the module's public interface distinct from its implementation.
Reading values from `config` within the same module's `config` block is the standard way to react to user-provided settings, and `lib.mkIf config.services.foo.enable { ... }` is the canonical pattern for conditional activation.

### Platform differences

NixOS modules manage system services through `systemd.services` and declare system-level state under `environment`, `networking`, `security`, and similar top-level option namespaces.
nix-darwin modules use `launchd.daemons` and `launchd.agents` for service management, with system configuration under `system`, `security`, and `homebrew` namespaces.
home-manager modules target user-level configuration through `home.file`, `home.packages`, `xdg`, and `programs.*` option namespaces.

All three share the module system primitives (`mkOption`, `mkIf`, `mkMerge`, `mkDefault`, `mkForce`) and compose identically.
The difference is the set of available option namespaces, not the module authoring mechanics.

### Testing modules

`lib.evalModules` evaluates a module set without building a full system, producing the merged `config` attribute set for inspection.
This enables unit-testing module option evaluation: assert that given inputs produce expected config values without incurring a full system build.

nix-unit provides structural property assertions over nix expressions, suitable for testing pure functions, option merging behavior, and derivation metadata.
NixOS VM tests provide integration testing of module behavior at runtime, spinning up a QEMU VM with the evaluated configuration and running a Python test script against it.
See `preferences-nix-checks-architecture` for the full check derivation taxonomy including VM test patterns.

## Cross-references

The check derivation taxonomy, NixOS VM test patterns, and nix-unit invariant testing are covered in `preferences-nix-checks-architecture`.
CI pipeline integration with `nix-fast-build`, buildbot-nix, and GitHub Actions is documented in `preferences-nix-ci-cd-integration`.
Property-based testing of nix expressions and algebraic law verification are covered in `preferences-algebraic-laws`.
