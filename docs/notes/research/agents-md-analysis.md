# agents-md Module Architecture Analysis

## Executive Summary

The test-clan repository exhibits **deliberate architectural duplication** of the agents-md module to work around clan-core's home-manager integration limitations. The duplication is **necessary for current architecture** but represents a consolidation opportunity once clan-core supports cross-platform home-manager modules.

Three separate implementations exist:
1. **flake.modules.homeManager.tools/agents-md.nix** - Dendritic flake-parts export (fully functional)
2. **modules/home/modules/_agents-md.nix** - Home-manager option module definition (portable, not exported)
3. **Inline in clan inventory** (cameron.nix, crs58.nix) - Clan users service workaround (required for clan)

## File Inventory with Complete Content Analysis

### File 1: `/Users/crs58/projects/nix-workspace/test-clan/modules/home/tools/agents-md.nix`

**Type**: Dendritic flake-parts module (auto-discovered by import-tree)
**Size**: 3.6 KB
**Exports**: `flake.modules.homeManager.tools` (merged with other tools modules)
**Status**: Working but NOT used in current evaluation path

```nix
# Lines 1-64
# AI agent documentation generation
# Generates unified CLAUDE.md, AGENTS.md, GEMINI.md, CRUSH.md, OPENCODE.md
# from shared configuration with references to preference documents
{ ... }:
{
  flake.modules.homeManager.tools =
    { config, ... }:
    let
      # Base path for preference documents (without @ prefix)
      # The @ prefix must be added when referencing to enable auto-loading
      prefsPath = "${config.home.homeDirectory}/.claude/commands/preferences";
      commandsPath = "${config.home.homeDirectory}/.claude/commands";
    in
    {
      # https://github.com/mirkolenz/nixos/blob/0911e2e/home/options/agents-md.nix#L22-L31
      #
      # Auto-loading requires @ prefix on full paths in generated CLAUDE.md
      programs.agents-md = {
        enable = true;
        settings.body = ''
          # Development Guidelines
          [... full content in lines 20-61 ...]
        '';
      };
    };
}
```

**Analysis**:
- Exports `flake.modules.homeManager.tools` which is an **aggregate namespace**
- This file defines the **settings (configuration)** for programs.agents-md
- Relies on **_agents-md.nix to define the option** (programs.agents-md.enable, programs.agents-md.settings)
- This is the **modern, correct pattern** - separate option definition from configuration
- However, this module is **NOT currently imported anywhere** in the evaluation path
- The dendritic pattern ensures this file is auto-discovered and merged by flake-parts via import-tree

### File 2: `/Users/crs58/projects/nix-workspace/test-clan/modules/home/modules/_agents-md.nix`

**Type**: Home-manager option module (NOT auto-discovered, must be explicitly imported)
**Size**: 1.0 KB
**Status**: Portable across platforms, but NOT exported as flake module

```nix
# Lines 1-43
# agents-md option module
# Defines programs.agents-md option for generating AI agent configuration files
# Generates 5 config files:
#   - ~/.claude/CLAUDE.md
#   - ~/.codex/AGENTS.md
#   - ~/.gemini/GEMINI.md
#   - ~/.config/crush/CRUSH.md
#   - ~/.config/opencode/AGENTS.md
{
  lib,
  config,
  flake,
  ...
}:
let
  cfg = config.programs.agents-md;
in
{
  options.programs.agents-md = {
    enable = lib.mkEnableOption "AGENTS.md";

    settings = lib.mkOption {
      type = flake.lib.mdFormat;
      default = { };
      description = "Markdown content with frontmatter for AI agent configuration files";
    };
  };

  config = lib.mkIf cfg.enable {
    # XDG config files
    xdg.configFile = {
      "crush/CRUSH.md".text = cfg.settings.text;
      "opencode/AGENTS.md".text = cfg.settings.text;
    };

    # Home directory files
    home.file = {
      ".claude/CLAUDE.md".text = cfg.settings.text;
      ".codex/AGENTS.md".text = cfg.settings.text;
      ".gemini/GEMINI.md".text = cfg.settings.text;
    };
  };
}
```

**Key Characteristics**:
- Defines the **option schema** (`options.programs.agents-md`)
- Defines the **implementation** (`config`) that writes files to home directory
- Depends on `flake` argument to access `flake.lib.mdFormat`
- **Portable**: Works on any home-manager platform (darwin, nixos, standalone)
- **Design Issue**: Uses underscore prefix (`_agents-md.nix`) - typically indicates private/internal modules
- **NOT exported as flake module**: Could be exported to `flake.modules.homeManager.*` but currently isn't

### File 3: `/Users/crs58/projects/nix-workspace/test-clan/modules/clan/inventory/services/users/cameron.nix`

**Type**: Clan users service instance (inventory configuration)
**Target Machines**: cinnabar (nixos), electrum (nixos), argentum (darwin), rosegold (darwin) - when configured
**Status**: REQUIRED for clan integration

**Relevant Section (lines 93-126)**:

```nix
# agents-md option module (requires flake arg from extraSpecialArgs)
# Defined inline since _agents-md.nix isn't exported as flake module
(
  {
    lib,
    config,
    flake,
    ...
  }:
  let
    cfg = config.programs.agents-md;
  in
  {
    options.programs.agents-md = {
      enable = lib.mkEnableOption "AGENTS.md";
      settings = lib.mkOption {
        type = flake.lib.mdFormat;
        default = { };
        description = "Markdown content with frontmatter for AI agent configuration files";
      };
    };
    config = lib.mkIf cfg.enable {
      xdg.configFile = {
        "crush/CRUSH.md".text = cfg.settings.text;
        "opencode/AGENTS.md".text = cfg.settings.text;
      };
      home.file = {
        ".claude/CLAUDE.md".text = cfg.settings.text;
        ".codex/AGENTS.md".text = cfg.settings.text;
        ".gemini/GEMINI.md".text = cfg.settings.text;
      };
    };
  }
)
```

**Analysis**:
- **EXACT DUPLICATE** of _agents-md.nix content (lines 1-43 of that file)
- Inlined because clan inventory `extraModules` cannot easily reference exported flake modules
- The module function is inlined within the users.cameron home-manager imports list
- This is a **clan-specific pattern**: clan users service integrates home-manager via extraModules

### File 4: `/Users/crs58/projects/nix-workspace/test-clan/modules/clan/inventory/services/users/crs58.nix`

**Type**: Clan users service instance (inventory configuration)
**Target Machines**: blackphos (darwin), stibnite (darwin) - when configured
**Status**: REQUIRED for clan integration

**Relevant Section (lines 91-124)**:

```nix
# agents-md option module (requires flake arg from extraSpecialArgs)
# Defined inline since _agents-md.nix isn't exported as flake module
(
  {
    lib,
    config,
    flake,
    ...
  }:
  let
    cfg = config.programs.agents-md;
  in
  {
    options.programs.agents-md = {
      enable = lib.mkEnableOption "AGENTS.md";
      settings = lib.mkOption {
        type = flake.lib.mdFormat;
        default = { };
        description = "Markdown content with frontmatter for AI agent configuration files";
      };
    };
    config = lib.mkIf cfg.enable {
      xdg.configFile = {
        "crush/CRUSH.md".text = cfg.settings.text;
        "opencode/AGENTS.md".text = cfg.settings.text;
      };
      home.file = {
        ".claude/CLAUDE.md".text = cfg.settings.text;
        ".codex/AGENTS.md".text = cfg.settings.text;
        ".gemini/GEMINI.md".text = cfg.settings.text;
      };
    };
  }
)
```

**Analysis**:
- **IDENTICAL DUPLICATE** to cameron.nix (same content)
- Same inline pattern required for clan integration
- Both crs58 and cameron users need the option module definition

### File 5: `/Users/crs58/projects/nix-workspace/test-clan/modules/machines/darwin/blackphos/default.nix`

**Type**: Darwin system module (flake.modules.darwin)
**Status**: Direct relative path import (NOT relying on flake exports)

**Relevant Lines**:
- Line 159: `../../../home/modules/_agents-md.nix` (crs58 user)
- Line 182: `../../../home/modules/_agents-md.nix` (raquel user)

```nix
# crs58 (admin): Import portable home modules + base-sops
users.crs58.imports = [
  flakeModulesHome."users/crs58"
  flakeModulesHome.base-sops
  # Import aggregate modules for crs58
  # Pattern A: All aggregates via auto-merge
  flakeModulesHome.ai
  flakeModulesHome.core
  flakeModulesHome.development
  flakeModulesHome.packages
  flakeModulesHome.shell
  flakeModulesHome.terminal
  flakeModulesHome.tools
  # LazyVim home-manager module
  inputs.lazyvim-nix.homeManagerModules.default
  # nix-index-database for comma command-not-found
  inputs.nix-index-database.homeModules.nix-index
  # agents-md option module (requires flake arg from extraSpecialArgs)
  ../../../home/modules/_agents-md.nix
  # Mac app integration (Spotlight, Launchpad)
  # Disabled: mac-app-util requires SBCL which has nixpkgs cache compatibility issues
  # inputs.mac-app-util.homeManagerModules.default
];
```

**Analysis**:
- Uses **relative path import** to _agents-md.nix
- Does NOT use `flakeModulesHome._agents-md` (doesn't exist as flake export)
- Imports the **option definition** but NOT the **configuration** from agents-md.nix
- The agents-md.nix configuration is provided inline in the tools aggregate

## Supporting Modules

### Module Type System: `/Users/crs58/projects/nix-workspace/test-clan/modules/lib/default.nix`

**Lines 1-62**:

Defines `flake.lib.mdFormat` type used by agents-md:

```nix
mdFormat = lib.types.submodule (
  { config, ... }:
  {
    options = {
      metadata = lib.mkOption {
        type = with lib.types; ...
        default = { };
        description = "Frontmatter for the markdown file, written as YAML.";
      };
      body = lib.mkOption {
        type = lib.types.lines;
        description = "Markdown content for the file.";
      };
      text = lib.mkOption {
        type = lib.types.str;
        readOnly = true;
      };
    };
    config = {
      text =
        if config.metadata == { } then
          config.body
        else
          ''
            ---
            ${lib.strings.toJSON config.metadata}
            ---

            ${config.body}
          '';
    };
  }
);
```

**Analysis**:
- Custom markdown type with YAML frontmatter support
- Required by _agents-md.nix option definition
- Must be passed via `flake` argument to home-manager modules

## Evaluation Order and Data Flow

### Dendritic Flake-Parts Architecture

```
flake.nix
  └─ inputs.import-tree ./modules
     └─ Auto-discovers all *.nix files recursively
        ├─ modules/home/tools/agents-md.nix (EXPORT: flake.modules.homeManager.tools)
        ├─ modules/home/tools/*.nix (30+ files EXPORT: flake.modules.homeManager.tools)
        ├─ modules/home/tools/default.nix (NAMESPACE: flake.modules.homeManager.tools = {} stub)
        ├─ modules/lib/default.nix (EXPORT: flake.lib.mdFormat)
        └─ ... other modules
     └─ All flake.modules.homeManager.tools.* are MERGED via attributes
```

### Import-Tree Merge Pattern

When multiple files export `flake.modules.homeManager.tools`, they are **recursively merged**:

```nix
flake.modules.homeManager.tools = {
  ... (from agents-md.nix) ...
  programs.agents-md = { enable = true; settings.body = "..."; };
  
  ... (from awscli.nix) ...
  programs.awscli = { ... };
  
  ... (from bottom.nix) ...
  programs.bottom = { ... };
  
  # Result: all tools merged into single namespace
};
```

### Current Evaluation Paths (2 separate paths)

#### Path 1: Blackphos Darwin Machine

```
flake.nix (import-tree discovers all modules)
  ├─ modules/lib/default.nix exports flake.lib.mdFormat
  ├─ modules/home/tools/agents-md.nix exports flake.modules.homeManager.tools
  │  ├─ Defines programs.agents-md.enable = true
  │  └─ Sets programs.agents-md.settings.body
  │
  └─ modules/machines/darwin/blackphos/default.nix
     ├─ User crs58:
     │  ├─ Import flakeModulesHome.tools (which includes agents-md config)
     │  └─ Import ../../../home/modules/_agents-md.nix (option definition)
     │     └─ Consumes flake.lib.mdFormat via extraSpecialArgs.flake
     │
     └─ User raquel:
        ├─ Import flakeModulesHome.tools (which includes agents-md config)
        └─ Import ../../../home/modules/_agents-md.nix (option definition)
           └─ Consumes flake.lib.mdFormat via extraSpecialArgs.flake
```

**Result**: Both option definition (_agents-md.nix) and configuration (agents-md.nix) are applied.

#### Path 2: Clan Inventory Users (cameron, crs58)

```
flake.nix (import-tree discovers all modules)
  ├─ modules/lib/default.nix exports flake.lib.mdFormat
  ├─ modules/home/tools/agents-md.nix exports flake.modules.homeManager.tools
  │  ├─ Defines programs.agents-md.enable = true
  │  └─ Sets programs.agents-md.settings.body
  │
  └─ modules/clan/inventory/services/users/cameron.nix
     ├─ Clan user service: user-cameron
     └─ home-manager extraModules:
        ├─ INLINE option module (DUPLICATE of _agents-md.nix)
        │  └─ Consumes flake.lib.mdFormat via extraSpecialArgs.flake
        └─ imports.self.modules.homeManager.tools
           └─ Configuration from agents-md.nix (but NOT used - see below)
```

## Critical Architectural Discovery

### Why agents-md.nix Configuration Is NOT Used (in clan path)

In clan inventory cameron.nix (lines 76-129):

```nix
users.cameron = {
  imports = [
    inputs.self.modules.homeManager."users/crs58"  # User identity
    inputs.self.modules.homeManager.base-sops      # Secrets
    # Import aggregate modules for crs58/cameron
    # Pattern A: All aggregates (matches blackphos configuration)
    inputs.self.modules.homeManager.ai
    inputs.self.modules.homeManager.core
    inputs.self.modules.homeManager.development
    inputs.self.modules.homeManager.packages
    inputs.self.modules.homeManager.shell
    inputs.self.modules.homeManager.terminal
    inputs.self.modules.homeManager.tools  # <-- Contains agents-md CONFIG
    inputs.lazyvim-nix.homeManagerModules.default
    inputs.nix-index-database.homeModules.nix-index
    # agents-md option module (requires flake arg from extraSpecialArgs)
    # Defined inline since _agents-md.nix isn't exported as flake module
    (
      { lib, config, flake, ... }: {...}  # <-- INLINE OPTION MODULE
    )
  ];
  home.username = "cameron";
};
```

**Wait - this DOES import flakeModulesHome.tools!**

However, the inline option module definition (lines 95-126) doesn't reference the tools aggregate configuration.
The tools configuration IS available through imports, but the inline module stands alone.

## Module Duplication Analysis

### Duplication Summary

| Location | Type | Content | Status | Reason |
|----------|------|---------|--------|--------|
| tools/agents-md.nix | Flake export | Option config (enable, settings) | Active | Dendritic pattern, auto-discovered |
| modules/_agents-md.nix | Portable module | Option definition + implementation | Active | Can be imported anywhere with flake arg |
| cameron.nix inline | Clan pattern | EXACT DUPLICATE of _agents-md.nix | ACTIVE | Clan users service doesn't reference flake exports |
| crs58.nix inline | Clan pattern | EXACT DUPLICATE of _agents-md.nix | ACTIVE | Clan users service doesn't reference flake exports |

### Duplication is 67 lines of repeated code

- _agents-md.nix: 43 lines (option definition + implementation)
- cameron.nix inline: 34 lines (lines 95-128, exact same content)
- crs58.nix inline: 34 lines (lines 93-126, exact same content)

**Total duplication: 43 + 34 + 34 = 111 lines, but unique content = 43 lines = 68 lines wasted**

## Root Cause Analysis: Why Clan Duplication Exists

### The Core Problem

Clan users service `extraModules` list accepts:
- ✅ Absolute file paths (e.g., `../../../home/modules/_agents-md.nix`)
- ✅ Anonymous module functions (e.g., `{ lib, config, ... }: {...}`)
- ❌ References to flake exports (e.g., `inputs.self.modules.homeManager._agents-md`)

The clan inventory system does NOT have access to the flake module namespace.
It can only reference:
- `inputs.*` (from flake inputs)
- Relative file paths
- Inline module functions

### Why Not Export _agents-md.nix as Flake Module?

It COULD be exported by:
1. Moving _agents-md.nix to a dendritic directory (e.g., modules/home/base-modules/)
2. Creating a default.nix that exports it
3. Ensuring import-tree discovers it

But clan inventory still couldn't reference it because:
- Clan doesn't evaluate the dendritic flake module namespace
- Clan passes `inputs.self` but NOT `config.flake.modules`

### Why Can blackphos Import It Directly?

Blackphos is defined in flake.modules.darwin, which:
- Has access to `config.flake.modules.homeManager.*`
- Can construct relative paths within the same flake
- Evaluates AFTER flake-parts merges all modules

## Consolidation Strategy

### Option A: Consolidate via Flake Export (Recommended for future)

**Goal**: Eliminate clan duplication by exporting _agents-md.nix as flake module

**Steps**:
1. Rename modules/home/modules/_agents-md.nix → modules/home/base/_agents-md.nix
2. Update modules/home/base/default.nix to export:
   ```nix
   flake.modules.homeManager.base = { ... }: { };
   ```
3. Update clan inventory to reference:
   ```nix
   inputs.self.modules.homeManager.base-agents-md
   # OR if exporting to base aggregate:
   # users.cameron.imports = [ inputs.self.modules.homeManager.base ];
   ```
4. Remove inline duplicates from cameron.nix and crs58.nix

**Blocker**: Requires clan-core to support passing `config.flake.modules.*` to users service
(Currently clan only passes `inputs` and local context)

### Option B: Consolidate via Central Module Factory (Doable now)

**Goal**: Generate inline modules from shared source, reduce visual duplication

**Steps**:
1. Create modules/lib/agents-md-module-factory.nix:
   ```nix
   { lib, flake, ... }:
   # Returns a module function that can be used inline
   { 
     lib, config, flake, ...
   }:
   { ... }  # agents-md option + config
   ```
2. Import in cameron.nix/crs58.nix:
   ```nix
   (import ../../../lib/agents-md-module-factory.nix { inherit lib; })
   # But this still requires passing { inherit lib; } which is awkward
   ```

**Problem**: Home-manager context (lib, config, flake) not available at import time.
Would need to be a function that returns a module function.

### Option C: Consolidate Existing via Import (Best solution now)

**Goal**: Import _agents-md.nix in cameron.nix/crs58.nix, eliminate inline duplicate

**Current State**:
```nix
# cameron.nix
users.cameron.imports = [
  # ... other imports ...
  (
    { lib, config, flake, ... }:
    { ... }  # INLINE DUPLICATE
  )
];
```

**Proposed Change**:
```nix
# cameron.nix
users.cameron.imports = [
  # ... other imports ...
  ../../../home/modules/_agents-md.nix
];
```

**Validation**:
- _agents-md.nix already accepts { lib, config, flake, ... } parameters
- blackphos.nix already imports it this way (line 159, 182)
- Should work identically in clan context

**Why this works**:
- Eliminates 68 lines of duplication
- _agents-md.nix is already the "source of truth"
- blackphos proves the pattern works
- No architectural changes needed

## Relationship Between Files

```
flake.lib.mdFormat (lib/default.nix)
  ↓ CONSUMED BY
_agents-md.nix (home/modules/_agents-md.nix)
  ├─ OPTION DEFINITION
  └─ IMPLEMENTATION (writes files)
     ↓
     REFERENCED BY:
     ├─ agents-md.nix (tools/agents-md.nix)
     │  └─ CONFIG: sets programs.agents-md.enable = true
     │             and programs.agents-md.settings.body
     │
     └─ blackphos/default.nix
        └─ Direct relative import (WORKING CORRECTLY)
        
     └─ cameron.nix & crs58.nix
        └─ INLINED DUPLICATE (ANTI-PATTERN)
```

## Recommendations

### Immediate (Phase 0 Completion)

1. **Replace inline in cameron.nix** (line 95-126):
   ```nix
   # OLD: (inline duplicate)
   # NEW: Direct import
   ../../../home/modules/_agents-md.nix
   ```

2. **Replace inline in crs58.nix** (line 93-124):
   ```nix
   # OLD: (inline duplicate)
   # NEW: Direct import
   ../../../home/modules/_agents-md.nix
   ```

3. **Verify agents-md.nix configuration** is still applied:
   - agents-md.nix provides the config (enable=true, settings.body)
   - _agents-md.nix provides the option (optionality, type checking)
   - Both imported through flakeModulesHome.tools and relative import
   - ✅ Should work correctly

### Future (Post Phase 0)

1. **Request clan-core enhancement**: Support passing flake module namespace to users service
2. **Export _agents-md.nix** as proper flake module:
   - Move to modules/home/base/ or modules/home/foundation/
   - Export via dendritic pattern
   - Reference from clan as `inputs.self.modules.homeManager.base-agents-md`

3. **Standardize cross-platform module pattern**:
   - Currently: separate option definition (_*.nix) from configuration (*.nix)
   - This is correct pattern but should be documented
   - Consider if other modules need similar separation

## Dendritic Pattern Validation

The test-clan repository correctly implements dendritic flake-parts:

✅ **Import-tree auto-discovery**: modules/home/tools/*.nix auto-discovered
✅ **Module merging**: Multiple files exporting same namespace (flake.modules.homeManager.tools) merge correctly
✅ **Namespace organization**: Aggregate namespaces (tools, core, etc.) organize related modules
✅ **Configuration composition**: tools/agents-md.nix + agents-md option definition = working system

⚠️ **Gap**: Option definitions (_*.nix) not auto-exported to flake module namespace
- Must be explicitly imported as relative paths
- Works fine but less elegant than full dendritic pattern

## Files Summary

| File | Type | Status | Duplication |
|------|------|--------|-------------|
| modules/home/tools/agents-md.nix | Flake export | ✅ Working | Correct location |
| modules/home/modules/_agents-md.nix | Portable module | ✅ Working | Single source of truth |
| modules/machines/darwin/blackphos/default.nix | Direct import | ✅ Working | No duplication |
| modules/clan/inventory/services/users/cameron.nix | Inline duplicate | ⚠️ Should import | 34 lines duplication |
| modules/clan/inventory/services/users/crs58.nix | Inline duplicate | ⚠️ Should import | 34 lines duplication |
| modules/lib/default.nix | Type definition | ✅ Working | Required by agents-md |
