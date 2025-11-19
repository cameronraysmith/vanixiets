# Clan-Core macOS Support: Quick Reference

## TL;DR

Clan-core **officially supports nix-darwin machines** with the following reality:

| Feature | Status | Notes |
|---------|--------|-------|
| Inventory inclusion | ✓ Complete | `machineClass = "darwin"` fully supported |
| Remote updates | ✓ Complete | `clan machines update <mac>` works end-to-end |
| Secrets/Vars | ✓ Complete | Full sops-nix support |
| Multi-machine services | ✗ Not implemented | Services only provide `nixosModule`, not `darwinModule` |
| Zerotier VPN | ⚠ Partial | NixOS orchestrated, macOS manual install required |

## For Infra Project Decision

**Verdict**: Darwin machines can be included in clan, but **will not have service orchestration** via inventory roles.

**Recommended Setup**:

1. **Add to inventory**:
   ```nix
   inventory.machines = {
     stibnite.machineClass = "darwin";
     blackphos.machineClass = "darwin";
   };
   ```

2. **Manage via nix-darwin**:
   - Each mac gets full `machines/<name>/configuration.nix`
   - Update via `clan machines update stibnite`
   - Secrets via sops-nix

3. **Network access**:
   - Install zerotier manually on each mac
   - Join network manually (controller is cinnabar)
   - SSH updates work over zerotier IPs

## Why No Service Support

All 24 clan services hardcode `nixosModule` implementations:
- Zerotier: uses systemd (Linux-only)
- Borgbackup: uses systemd timers (Linux-only)  
- Wireguard: uses NixOS network options (Linux-only)
- etc.

No `darwinModule` equivalents exist yet. This is a feature gap in clan-core, not a limitation of nix-darwin itself.

## Build Architecture Constraint

**Hard requirement**: Cannot build darwin configs from Linux builders.

This means:
- `buildHost` must be macOS for darwin machines
- Cannot use cinnabar (Linux VPS) as buildHost for macOS targets
- Each mac typically builds its own config or uses another Mac as buildHost

Workaround: Let each mac build locally (`--build-host local`)

## Real-World Validation

mic92 (clan-core developer) runs:
- **evo** (darwin): In inventory, NOT in service roles
- **eve, eva** (nixos): Full service orchestration
- Uses same flake for both

This is the production pattern.

## Files to Reference

- Inventory: `/modules/inventoryClass/inventory.nix` (lines 249-259)
- Update mechanism: `/docs/site/getting-started/update-machines.md`
- Official macOS guide: `/docs/site/guides/macos.md`
- Example: `~/projects/nix-workspace/mic92-clan-dotfiles/machines/flake-module.nix`

## Action Items for Infra

1. ✓ **Research complete** - see full report in `clan-core-macos-support.md`
2. **Decision point**: Accept limitations or contribute darwin service modules
3. **Implementation**: Use recommended mixed architecture (darwin individual machines + nixos orchestration core)
4. **Testing**: Validate with stibnite + cinnabar zerotier setup

