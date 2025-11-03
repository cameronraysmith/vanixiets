---
title: Understanding Autowiring
description: How nixos-unified directory-based autowiring eliminates configuration boilerplate
---

Instead of manually registering each configuration, module, and overlay in `flake.nix`, nixos-unified scans directories and automatically creates flake outputs based on file paths.

## Without autowiring (traditional approach)

```nix
# flake.nix (manual registration - verbose and error-prone)
{
  outputs = { nixpkgs, nix-darwin, home-manager, ... }: {
    darwinConfigurations.stibnite = nix-darwin.lib.darwinSystem {
      modules = [ ./configurations/darwin/stibnite.nix ];
    };
    darwinConfigurations.blackphos = nix-darwin.lib.darwinSystem {
      modules = [ ./configurations/darwin/blackphos.nix ];
    };
    nixosConfigurations.orb-nixos = nixpkgs.lib.nixosSystem {
      modules = [ ./configurations/nixos/orb-nixos.nix ];
    };
    # ... repeat for every configuration, module, and overlay
  };
}
```

**Problems:**
- Verbose boilerplate for each configuration
- Error-prone manual maintenance
- Every new host/module/overlay requires flake.nix updates

## With autowiring (nixos-unified approach)

```nix
# flake.nix (actual implementation - minimal)
{
  outputs = inputs@{ flake-parts, ... }:
    inputs.flake-parts.lib.mkFlake { inherit inputs; } {
      systems = [ "x86_64-linux" "aarch64-linux" "aarch64-darwin" ];
      imports = with builtins;
        map (fn: ./modules/flake-parts/${fn}) (attrNames (readDir ./modules/flake-parts));
      # ... minimal configuration
    };
}
```

**Benefits:**
- **Add a new host**: Create `configurations/darwin/newhostname.nix` → automatically available as `darwinConfigurations.newhostname`
- **Add a new module**: Create `modules/nixos/mymodule.nix` → automatically available as `nixosModules.mymodule`
- **Add an overlay**: Create `overlays/myoverlay.nix` → automatically available as `overlays.myoverlay`

## How autowiring works

The mechanism is straightforward but powerful:

### Step 1: Directory scan

nixos-unified scans specific directories looking for nix files:
- `configurations/darwin/` for Darwin system configurations
- `configurations/nixos/` for NixOS system configurations
- `configurations/home/` for standalone home-manager configurations
- `modules/flake-parts/` for system-agnostic flake modules
- `modules/darwin/` for Darwin-specific modules
- `modules/nixos/` for NixOS-specific modules
- `overlays/` for package overlays

### Step 2: Path parsing

File paths are transformed into flake output names:
- `configurations/darwin/stibnite.nix` → `darwinConfigurations.stibnite`
- `modules/nixos/common.nix` → `nixosModules.common`
- `overlays/default.nix` → `overlays.default`

The filename (minus `.nix`) becomes the configuration/module/overlay name.

### Step 3: Automatic import

Files are imported and wired into appropriate flake outputs without manual intervention.
nixos-unified handles the plumbing automatically.

### Step 4: Module composition

System configurations automatically import relevant modules based on the platform.

## Practical examples

### Example 1: Adding a new darwin host

**Task**: Add configuration for new macOS machine "newhostname"

**Traditional approach** (without autowiring):
1. Create `configurations/darwin/newhostname.nix`
2. Edit `flake.nix` to add:
   ```nix
   darwinConfigurations.newhostname = nix-darwin.lib.darwinSystem {
     modules = [ ./configurations/darwin/newhostname.nix ];
   };
   ```
3. Run `darwin-rebuild switch --flake .#newhostname`

**Autowiring approach**:
1. Create `configurations/darwin/newhostname.nix`
2. Run `darwin-rebuild switch --flake .#newhostname`

**Result**: nixos-unified detects the new file and automatically creates `darwinConfigurations.newhostname` output.
**No flake.nix modifications needed**.

### Example 2: Adding a custom package

**Task**: Package a new tool "mytool"

**Steps**:
1. Create `overlays/packages/mytool.nix` with package definition
2. Run `nix build .#mytool`

**What happens**:
- `overlays/packages/` directory is scanned by `packagesFromDirectoryRecursive`
- Package automatically merged into overlay composition (layer 3: packages)
- Available as `packages.${system}.mytool` output

**Package immediately available in all configurations** via the overlay.

### Example 3: Creating a reusable nixos module

**Task**: Create module for common server configuration

**Steps**:
1. Create `modules/nixos/server-common.nix`
2. Import in any nixos configuration:
   ```nix
   imports = [ inputs.self.nixosModules.server-common ];
   ```

**What happens**:
- nixos-unified scans `modules/nixos/`
- Automatically exports as `nixosModules.server-common`
- Available for import in any nixos configuration

**Module reusable across all NixOS systems** without manual registration.

## Why this matters

### For newcomers

- **Self-documenting structure**: Directory organization directly maps to functionality
- **Less nix knowledge required**: Add files to directories instead of editing complex flake.nix
- **Immediate feedback**: Changes reflect in flake outputs automatically

### For experts

- **Predictable patterns**: Consistent directory structure across projects
- **Scalable organization**: Handles growing configuration complexity gracefully
- **Focus on content**: Spend time on configuration logic, not structural boilerplate

### For maintenance

- **Minimal changes for new systems**: Adding machines/users requires only configuration files
- **Straightforward discovery**: `ls configurations/` shows all available systems
- **Reduced error surface**: No manual wiring means fewer opportunities for mistakes

## The transparency principle

The key insight: **the directory tree IS the API**.

Understanding the file structure means understanding the entire configuration architecture.
There's no hidden wiring logic to discover.
What you see in the directory tree is what you get in the flake outputs.

This transparency makes the system:
- Easy to learn (explore directories to understand structure)
- Easy to extend (add files where they logically belong)
- Easy to debug (output names directly correspond to file paths)

## See also

- [Nix-Config Architecture](nix-config-architecture) - Full three-layer architecture explanation
- [Repository Structure](/reference/repository-structure) - Complete directory-to-output mapping
- [Host Onboarding Guide](/guides/host-onboarding) - Practical example of adding a new host
