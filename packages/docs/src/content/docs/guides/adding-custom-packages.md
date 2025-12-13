---
title: Adding custom packages
description: How to add your own package derivations to this configuration
sidebar:
  order: 6
---

This guide shows you how to add custom package derivations to your configuration.
Packages you add will be automatically available system-wide and in your development shell.

## Quick start

The simplest way to add a package is to create a directory in `pkgs/by-name/` with a `package.nix` file.
The directory name becomes the package name, and the file is automatically discovered and built.

For example, creating `pkgs/by-name/hello-world/package.nix` makes the package available as `pkgs.hello-world`.

## Understanding how this works

To use custom packages effectively, you need to understand how they integrate with nixpkgs.

**Overlays extend nixpkgs.**
Nixpkgs is the base package set containing tens of thousands of packages.
[Overlays](https://nixos.org/manual/nixpkgs/stable/#chap-overlays) are the standard mechanism for extending or modifying this package set without forking the entire repository.
An overlay is a function that takes two arguments (`final` and `prev`) and returns an attribute set of packages to add or override.

**This repository automates the overlay boilerplate.**
Instead of writing overlay functions directly, you write standard package derivations.
The deferred module composition pattern uses `lib.packagesFromDirectoryRecursive` in `modules/nixpkgs/per-system.nix` to automatically discover your package files, call them with the necessary dependencies, and merge them into an overlay layer.

**What packagesFromDirectoryRecursive does.**
This nixpkgs library function scans the `pkgs/by-name/` directory and transforms it into an attribute set of packages.
For each directory containing `package.nix`, it uses `callPackage` to inject dependencies automatically based on the function arguments you declare, and uses the directory name as the package name.

**You write package derivations, not overlays.**
When you create a directory in `pkgs/by-name/`, you're writing a standard nix derivation using functions like `rustPlatform.buildRustPackage` or `buildNpmPackage`.
The overlay mechanism happens automatically in `modules/nixpkgs/per-system.nix` where your derivations are merged into the package set.
This is why your packages become available as `pkgs.your-package-name` throughout your system configuration.

## Simple packages

Simple packages with a single derivation file work well for most use cases.
Create a directory in `pkgs/by-name/` with a `package.nix` file that exports a standard nix derivation.

Here's a complete example for a Rust package from crates.io:

```nix
{
  lib,
  rustPlatform,
  fetchCrate,
  pkg-config,
  openssl,
}:
let
  pname = "starship-jj";
  version = "0.5.1";
in
rustPlatform.buildRustPackage {
  inherit pname version;

  src = fetchCrate {
    inherit pname version;
    hash = "sha256-tQEEsjKXhWt52ZiickDA/CYL+1lDtosLYyUcpSQ+wMo=";
  };

  cargoHash = "sha256-+rLejMMWJyzoKcjO7hcZEDHz5IzKeAGk1NinyJon4PY=";

  nativeBuildInputs = [ pkg-config ];
  buildInputs = [ openssl ];

  meta = with lib; {
    description = "starship plugin for jj";
    homepage = "https://gitlab.com/lanastara_foss/starship-jj";
    license = licenses.mit;
    mainProgram = "starship-jj";
  };
}
```

The function arguments at the top (inside the `{ ... }:`) specify dependencies from nixpkgs.
Nix automatically provides these when building your package.

For npm packages, use `buildNpmPackage` instead:

```nix
{
  lib,
  buildNpmPackage,
  fetchFromGitHub,
}:

buildNpmPackage rec {
  pname = "markdown-tree-parser";
  version = "1.6.1";

  src = fetchFromGitHub {
    owner = "ksylvan";
    repo = "markdown-tree-parser";
    rev = "v${version}";
    hash = "sha256-r6c6tpk7R2pWNJmRyIS1ScfX2L6nTVorOXNrGByJpgE=";
  };

  npmDepsHash = "sha256-2oDTln7l03RHk/uOP8vEOeOc9kO5ezXnMBEQYMVoNEo=";

  dontNpmBuild = true;

  meta = {
    description = "Parse and manipulate markdown files as tree structures";
    homepage = "https://github.com/ksylvan/markdown-tree-parser";
    license = lib.licenses.mit;
    mainProgram = "md-tree";
  };
}
```

## Multi-file packages

When your package needs multiple files (scripts, configuration, assets), add them alongside `package.nix`.
The directory name becomes the package name.
You can reference sibling files using `./filename` or `builtins.readFile ./filename`.

Example structure for a nushell script wrapper:

```
pkgs/by-name/atuin-format/
├── package.nix
└── atuin-format.nu
```

The `package.nix` file:

```nix
{ nuenv, atuin, ... }:

nuenv.writeShellApplication {
  name = "atuin-format";
  runtimeInputs = [ atuin ];
  meta.description = "Format atuin history with Catppuccin Mocha colors";
  text = ''
    #!/usr/bin/env nu

    ${builtins.readFile ./atuin-format.nu}
  '';
}
```

This pattern works for any case where you need to bundle multiple files together.

## Testing your package

After creating your package file, test it builds correctly:

```bash
nix build .#your-package-name
```

If the build succeeds, you'll see a `result` symlink pointing to the built package.
Test running the program:

```bash
./result/bin/your-program-name
```

To make the package available system-wide, rebuild your system configuration:

```bash
just activate
```

Your package is now available in your PATH.

## Finding hashes

Package definitions require content hashes for security and reproducibility.
When you first write a package definition, you won't know the correct hash.

The standard approach is to use a fake hash, let nix fail, then copy the correct hash from the error message:

```nix
src = fetchFromGitHub {
  owner = "example";
  repo = "example";
  rev = "v1.0.0";
  hash = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
};
```

Run `nix build .#your-package-name` and nix will tell you the expected hash:

```
error: hash mismatch in fixed-output derivation
  specified: sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=
    got:    sha256-r6c6tpk7R2pWNJmRyIS1ScfX2L6nTVorOXNrGByJpgE=
```

Copy the `got` hash into your package definition.

For npm packages, you also need `npmDepsHash` which works the same way.

## How packages are discovered

The discovery process happens in `modules/nixpkgs/per-system.nix` using the deferred module composition pattern:

```nix
pkgsDirectory = ../../../pkgs/by-name;

packagesFromDirectory = lib.packagesFromDirectoryRecursive {
  callPackage = pkgs.callPackage;
  directory = pkgsDirectory;
};
```

This means:
- Directories like `foo/package.nix` become `pkgs.foo`
- Non-nix files and empty directories are ignored
- The `callPackage` mechanism handles dependency injection automatically

The resulting package set is merged into the overlay composition as Layer 3 (after channels and stable fallbacks, before overrides), making your packages available throughout your system configuration.

## Common build functions

Nixpkgs provides specialized build functions for different languages and frameworks:

- `rustPlatform.buildRustPackage` - Rust packages (crates)
- `buildNpmPackage` - Node.js packages
- `buildGoModule` - Go packages
- `python3Packages.buildPythonPackage` - Python packages
- `writeShellApplication` - Simple shell script wrappers
- `nuenv.writeShellApplication` - Nushell script wrappers

Each build function has its own required attributes.
Check the [nixpkgs manual](https://nixos.org/manual/nixpkgs/stable/) for details on specific builders.

## Next steps

Once you're comfortable adding packages, you might want to:

- Override existing nixpkgs packages with custom build options (see `modules/nixpkgs/overlays/overrides.nix`)
- Use stable channel fallbacks for broken packages (see `modules/nixpkgs/overlays/stable-fallbacks.nix`)
- Apply upstream patches to nixpkgs packages (see [handling broken packages](/guides/handling-broken-packages))

For deeper understanding of the overlay architecture, see [ADR-0017: Dendritic overlay patterns](/development/architecture/adrs/0017-dendritic-overlay-patterns).
