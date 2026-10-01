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

## Dendritic module composition (import-tree)

Structure flakes with the dendritic pattern: a thin `flake.nix` whose `outputs` delegate to `flake-parts.lib.mkFlake { inherit inputs; } (inputs.import-tree ./modules)`, so every `.nix` file under the import-tree root is auto-discovered as a flake-parts module and merged into one module-system fixpoint.
This is the composition model used across vanixiets, ironstar, and python-nix-template.

Treat the import-tree root as a modules-only zone.
import-tree imports every `*.nix` under the root (excluding any path containing `/_`) and feeds each, content-blind and unconditional, to the module system, so a file that is not a valid flake-parts module crashes evaluation.
Keep non-modules outside the root: plain functions and data in `lib/`, package derivations in `pkgs/by-name/<name>/package.nix`, parked code as `*.nix.txt` or under a `/_`-prefixed path; pull them back in from a module inside the root (`import ../lib/foo.nix`, `pkgs.callPackage`, `pkgsDirectory`).

Distinguish discovery from merge.
Merge is location-independent: any module the fixpoint imports merges identically regardless of where it lives on disk.
Discovery is location-bound: `import-tree ./modules` only finds files under that root, so a `flake-module.nix` elsewhere is wired only if you add its directory as another root (`import-tree [ ./modules ./other ]`), filter by filename (`import-tree.filter (lib.hasSuffix "/flake-module.nix") [ ... ]`), or import it explicitly from a discovered module.

Litmus test for a file under the root: it must import to an attrset module or a function module; every config value it defines must target a declared option (or a freeform type such as `flake.*`); and a function form must end in `...` with formals drawn only from flake-level args (`pkgs`/`stdenv` are perSystem-only).
See `references/dendritic-module-composition.md` for the exact module-validity rules for both forms, the import-tree discovery API, and the common crash causes with fixes.

## No import-from-derivation

Never read a derivation output at evaluation time.
`import`, `builtins.readFile`, `lib.importJSON`, `lib.importTOML`, `builtins.pathExists`, `builtins.readDir`, and `builtins.path` applied to a path inside a derivation's output (a `runCommand` result, a package's `${pkg}/share/...`, a converter such as `yaml2json` or `chart2json`) force that derivation to build in the middle of evaluation: import-from-derivation (IFD).

Why it is forbidden:
- Evaluation serializes on the build: the evaluator blocks until the derivation is realized, so no other attribute evaluates and no build is scheduled meanwhile.
- Evaluation becomes platform-bound: the IFD derivation must be buildable by the evaluating machine, so evaluating `aarch64-darwin` outputs on a Linux CI worker (or the reverse) fails or needs a remote builder just to evaluate.
- The work is invisible to caches and schedulers: `nix-eval-jobs`, CI, and `nix flake check` see the dependency only after building it, so it is neither parallelized nor reported as a job, and a cold cache turns evaluation into a build.

IFD-free patterns, in order of preference:
- Take data from a flake input, including `flake = false` inputs for plain source trees; reading files of an input is a source read, not a build.
- Interpolate store paths into strings (`"${pkg}/share/foo"`) instead of reading them; string context carries the dependency to build time without evaluating the contents.
- Commit generated data (JSON indexes, rendered manifests, goldens) to the repository, regenerate it with a recipe, and add an in-build guard that fails, printing the corrected data, when the committed copy drifts from what the build produces.
- Move the step into a build: do the conversion or comparison inside a derivation's builder rather than feeding its output back into Nix.
- Write platform-independent checks for one system instead of every system when their evaluation cannot be made IFD-free elsewhere.

Enforcement: CI evaluates with `allow-import-from-derivation = false` (nixbot's `NIX_CONFIG`), and `just check-ifd` runs `nix-eval-jobs` over `checks.<system>` for every system with IFD disabled and lists each attribute that errors.
Verify a single attribute with `nix eval --raw --option allow-import-from-derivation false '.#<attr>.drvPath'`.

An exception requires an argument in review showing that none of the patterns above applies, and a recorded decision naming the attribute; an IFD-dependent output stays out of `checks` until then.

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

## Command-line diagnostics

- Inspect a failed build's log with `nix log /nix/store/<drv-or-out>`, filtered for the relevant text, rather than re-running the build to see its output
- Find which package provides a given path with `nix-locate`, for example `nix-locate bin/ip`
- Look up flake attributes with `nix eval` rather than `nix flake show`
- For cross-architecture builds, use `nix-build --eval-system <system>`; in flakes, address the system attribute directly, for example `.#packages.x86_64-linux.hello`
- Generate or update a package patch by cloning the source, optionally applying the existing patch, making the edits, then producing the new patch with `git format-patch`

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
Reference repo: `vlaci/crane-maturin`.

Python packaging uses uv2nix and pyproject-nix rather than nixpkgs' `buildPythonPackage`.
The uv2nix approach reads `uv.lock` files via `workspace.loadWorkspace`, produces nix overlays through `mkPyprojectOverlay`, and composes them with `pyproject-build-systems` into a Python package set.
`mkVirtualEnv` produces the final installable environment.
Reference repos: `pyproject-nix/pyproject.nix`, `pyproject-nix/uv2nix`.
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
