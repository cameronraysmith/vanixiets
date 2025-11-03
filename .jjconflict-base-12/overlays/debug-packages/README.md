# Debug/Experimental Packages

Experimental derivations for local development and testing.

## Purpose

This directory contains package derivations that are:

- Available for manual builds: `nix build .#debug.<package>`
- Not built automatically by omnix ci (devour-flake ignores `legacyPackages.debug`)
- Not in the overlay, so they don't override nixpkgs or flake input packages
- Can be promoted to active use by moving to `overlays/packages/`

## Usage

### Building debug packages locally

```bash
# Build experimental holos version
nix build .#debug.holos

# List all debug packages
nix eval .#debug --apply 'builtins.attrNames' --json | jq .

# Check a debug package version
nix eval .#debug.holos.version --raw
```

### Using in configurations (not recommended)

If you really need to use a debug package in your home-manager or nixos configuration:

```nix
# Instead of:
home.packages = [ pkgs.holos ];

# Use explicit path:
home.packages = [ pkgs.legacyPackages.${system}.debug.holos ];
```

The ugly path is intentional to discourage this usage. Debug packages are for local experimentation only.
Validate and promote them to overlays/packages if they should become flake outputs (see below).

## Promoting to active use

When a debug package is ready for regular use:

1. Move the derivation file:

   ```bash
   mv overlays/debug-packages/holos.nix overlays/packages/holos.nix
   ```

2. Commit the change:

   ```bash
   git add overlays/packages/holos.nix overlays/debug-packages/
   git commit -m "feat(overlays): promote holos from debug to active packages"
   ```

3. The package is now:
   - Available as `pkgs.holos` (overrides nixpkgs version)
   - Built automatically by omnix ci
   - Included in flake outputs as `.#packages.<system>.holos`

## How it works

Debug packages are exposed via `modules/flake-parts/debug-packages.nix`:

```nix
perSystem = { pkgs, ... }: {
  legacyPackages.debug = pkgs.lib.packagesFromDirectoryRecursive {
    callPackage = pkgs.lib.callPackageWith pkgs;
    directory = ../../overlays/debug-packages;
  };
};
```

This places them in `legacyPackages.debug`, which tools like devour-flake (via omnix) specifically ignores when building flake outputs.

## Current debug packages

- `conda-lock`: conda environment lock file generator
- `holos`: kubernetes configuration tool
- `quarto`: scientific and technical publishing system

## See also

- [nixpkgs hotfixes infrastructure](../../docs/notes/nixpkgs-hotfixes.md)
- [flake-parts documentation](https://flake.parts)
