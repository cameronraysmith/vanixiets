# agents-md Module Quick Reference

## All Instances (Sorted by Importance)

### 1. Source of Truth
**File**: `/Users/crs58/projects/nix-workspace/test-clan/modules/home/modules/_agents-md.nix` (43 lines)
- **Purpose**: Defines the option schema and file generation logic
- **Status**: Single source of truth (no duplication here)
- **References**: flake.lib.mdFormat (type system)
- **Imported by**: blackphos/default.nix (both users), cameron.nix (inlined), crs58.nix (inlined)

### 2. Configuration Provider
**File**: `/Users/crs58/projects/nix-workspace/test-clan/modules/home/tools/agents-md.nix` (65 lines)
- **Purpose**: Provides the configuration (enable=true, settings.body)
- **Status**: Dendritic export via flake.modules.homeManager.tools
- **Auto-discovered**: Yes (import-tree)
- **Used**: In blackphos, cameron, crs58 (all import tools aggregate)
- **Note**: Works correctly, just auto-exported and merged

### 3. Type Definition
**File**: `/Users/crs58/projects/nix-workspace/test-clan/modules/lib/default.nix` (lines 6-60)
- **Purpose**: Defines flake.lib.mdFormat type
- **Status**: Required by _agents-md.nix
- **Unique**: No duplication

### 4. Blackphos (Darwin Machine)
**File**: `/Users/crs58/projects/nix-workspace/test-clan/modules/machines/darwin/blackphos/default.nix`
- **crs58 user** (line 159): `../../../home/modules/_agents-md.nix`
- **raquel user** (line 182): `../../../home/modules/_agents-md.nix`
- **Status**: CORRECT - Direct import (no duplication)
- **Config source**: Imported via flakeModulesHome.tools aggregate
- **Option source**: Imported via relative path

### 5. Clan User: cameron
**File**: `/Users/crs58/projects/nix-workspace/test-clan/modules/clan/inventory/services/users/cameron.nix` (lines 93-126)
- **Machines**: cinnabar, electrum, (argentum, rosegold when configured)
- **Status**: DUPLICATED - Inlines full _agents-md.nix content (34 lines)
- **Issue**: Clan inventory can't reference flake modules, so module is inlined
- **Fix**: Replace lines 93-126 with `../../../home/modules/_agents-md.nix`

### 6. Clan User: crs58
**File**: `/Users/crs58/projects/nix-workspace/test-clan/modules/clan/inventory/services/users/crs58.nix` (lines 91-124)
- **Machines**: blackphos, stibnite
- **Status**: DUPLICATED - Inlines full _agents-md.nix content (34 lines)
- **Issue**: Clan inventory can't reference flake modules, so module is inlined
- **Fix**: Replace lines 91-124 with `../../../home/modules/_agents-md.nix`

## Duplication Metrics

| Location | Type | Content | Lines | Unique? |
|----------|------|---------|-------|---------|
| _agents-md.nix | Option module | Original | 43 | ✅ YES (source of truth) |
| cameron.nix | Inline copy | Duplicate | 34 | ❌ NO (REMOVE) |
| crs58.nix | Inline copy | Duplicate | 34 | ❌ NO (REMOVE) |
| **Total redundant lines** | | | **68** | |

## Module Dependency Graph

```
flake.lib.mdFormat
  │
  ├─ _agents-md.nix (option definition)
  │  │
  │  ├─ blackphos/default.nix → relative import (CORRECT)
  │  ├─ cameron.nix → INLINED DUPLICATE (FIX)
  │  └─ crs58.nix → INLINED DUPLICATE (FIX)
  │
  └─ agents-md.nix (configuration)
     └─ flake.modules.homeManager.tools (auto-discovered, merged)
        └─ Imported by: blackphos, cameron.nix, crs58.nix (via aggregates)
```

## Why Duplication Exists

**Root Cause**: Clan users service design
- ❌ Cannot reference flake.modules.homeManager.* namespaces
- ✅ CAN import files via relative paths
- ✅ CAN inline module functions

**Current Workaround**: Inline duplicate _agents-md.nix in cameron.nix and crs58.nix

**Better Solution**: Import _agents-md.nix directly (like blackphos does)

## Recommended Fix (Phase 0)

Replace in cameron.nix (delete lines 93-126):
```nix
# OLD (34 lines):
(
  { lib, config, flake, ... }: {...}  # INLINE DUPLICATE
)

# NEW:
../../../home/modules/_agents-md.nix
```

Replace in crs58.nix (delete lines 91-124):
```nix
# OLD (34 lines):
(
  { lib, config, flake, ... }: {...}  # INLINE DUPLICATE
)

# NEW:
../../../home/modules/_agents-md.nix
```

**Validation**: Blackphos already uses this pattern successfully
- Both users import the same _agents-md.nix
- Works on darwin with proper flake context
- Clan users service should work identically

## Architecture Notes

**Pattern**: Option definition (_*.nix) + Configuration (*.nix)
- Correct pattern for separating concerns
- _agents-md.nix: "What options are available and how do they work?"
- agents-md.nix: "What are the default values for this system?"
- Works across darwin, nixos, standalone home-manager

**Import-Tree**: Auto-discovers tools/*.nix for merging
- agents-md.nix IS discovered
- _agents-md.nix IS NOT discovered (underscore prefix, in different directory)
- Both are needed: option definition + configuration

**Dendritic Pattern**: Working correctly
- Modules organized by concern (tools, core, packages, etc.)
- Auto-merged into flake.modules.homeManager.* namespaces
- Well-structured, just needs consolidation of clan duplicates
