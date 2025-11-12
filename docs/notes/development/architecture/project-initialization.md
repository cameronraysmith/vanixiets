# Project Initialization

This is a **brownfield migration project** transitioning from nixos-unified to dendritic + clan patterns.
There is no single initialization command; the architecture is applied progressively per host with validation gates.

**Proven Pattern Initialization** (from test-clan validation):
```bash
# 1. Repository structure (already exists in infra)
cd ~/projects/nix-workspace/infra
git checkout clan  # Migration branch

# 2. Flake inputs configuration (add clan-core, import-tree, terranix, disko, srvos)
# See Decision Summary table for specific versions

# 3. Module structure creation (dendritic pattern)
mkdir -p modules/{clan,system,machines/{nixos,darwin},terranix,checks}

# 4. Import-tree auto-discovery configuration
# flake.nix outputs: flake-parts.lib.mkFlake { inherit inputs; } (inputs.import-tree ./modules)

# 5. Clan inventory initialization
# modules/clan/meta.nix: clan.meta.name = "nix-config"
# modules/clan/inventory/machines.nix: Define all 5 machines

# 6. Per-host migration (progressive, with validation gates)
# Phase 0: test-clan validation (COMPLETE)
# Story 1.8: blackphos (darwin multi-user) in test-clan
# Production: Apply validated patterns to infra repo
```

**First Implementation Story** (Story 1.8 in test-clan, then apply to infra):
Migrate blackphos darwin host from infra's nixos-unified pattern to test-clan's dendritic + clan pattern, validating multi-user (crs58 admin + raquel non-admin), home-manager integration, and heterogeneous zerotier networking (nixos ↔ darwin) before production refactoring.
