# Story 1.10BA: Refactor Home-Manager Modules from Pattern B to Pattern A (Drupol Multi-Aggregate)

**Epic:** Epic 1 - Architectural Validation + Migration Pattern Rehearsal (Phase 0)

**Status:** drafted

**Dependencies:**
- Story 1.10B (done-with-limitations): Provided empirical evidence of Pattern B architectural failures (11 disabled features, darwinConfigurations build failure)

**Blocks:**
- Story 1.10C (backlog): Secrets migration needs modules with flake context for clan vars integration

**Strategic Value:** Restores 11 disabled features (SSH signing, MCP API keys, GLM wrapper, themes, custom packages), fixes darwinConfigurations.blackphos.system build failure (unblocks Story 1.12 physical deployment), aligns with industry-standard pattern (gaetanlepage + drupol both use Pattern A), validates Party Mode architectural review (unanimous 9/9 recommendation proven correct by empirical evidence), provides correct migration pattern for Epic 2-6 (4 more machines will use Pattern A), demonstrates evidence-based decision-making (Pattern B tried, failed, corrected based on data).

**⚠️ CRITICAL ARCHITECTURAL CORRECTION**

This story was discovered during Story 1.10B implementation (Session 2, 2025-11-14) when Pattern B migration encountered **CRITICAL ARCHITECTURAL LIMITATIONS** that disabled 11 features and broke darwinConfigurations builds. Party Mode investigation (9 agents) unanimously recommended immediate refactoring to Pattern A based on reference implementation analysis.

---

## Story Description

As a system administrator,
I want to refactor the 17 migrated home-manager modules from Pattern B (underscore directories, plain modules) to Pattern A (drupol multi-aggregate dendritic),
So that full functionality is restored (flake inputs, sops-nix compatibility, custom packages) and Story 1.10C can proceed with working modules.

**Context:**

Story 1.10B migration (Session 2, 2025-11-14) discovered **CRITICAL ARCHITECTURAL LIMITATIONS** of Pattern B that block 11 features and break darwinConfigurations builds.

**Pattern B Failures (Documented in Story 1.10B Dev Notes lines 767-1031):**
- No flake context access (plain modules signature: `{ config, pkgs, lib }` only - missing `flake` parameter)
- sops-nix DISABLED (requires `flake.config` lookups, incompatible with plain modules)
- Flake inputs DISABLED (nix-ai-tools, lazyvim, catppuccin-nix unreachable)
- darwinConfigurations.blackphos.system **FAILS TO BUILD** (lazyvim integration broken)
- 11 features disabled with Story 1.10C TODOs (SSH signing, MCP API keys, GLM wrapper, ccstatusline, tmux theme)

**11 Features Disabled in Pattern B:**
1. SSH signing (git.nix, jujutsu.nix) - sops-nix DISABLED
2. MCP API keys (mcp-servers.nix) - 3 servers DISABLED (firecrawl, huggingface, context7)
3. GLM wrapper (wrappers.nix) - Entire wrapper DISABLED
4. nix-ai-tools claude-code package (default.nix) - Custom package DISABLED
5. ccstatusline (default.nix) - Package unavailable
6. catppuccin-nix tmux theme (tmux.nix) - Entire 36-line block REMOVED

**Build Failure:**
- darwinConfigurations.blackphos.system **FAILS TO BUILD**
- Error: "option 'programs.lazyvim' does not exist"
- Root cause: lazyvim flake input unreachable (no flake context in plain modules)

**Root Cause:**
Plain home-manager modules have signature `{ config, pkgs, lib, ... }` - NO `flake` parameter.
- Cannot access `flake.inputs.*` (nix-ai-tools, lazyvim, catppuccin-nix unreachable)
- Cannot access `flake.config.*` (sops-nix user lookup broken)
- Cannot use home-manager modules from flake inputs

**Party Mode Investigation (2025-11-14):**

Party Mode team (9 agents) investigated two reference implementations:
1. **gaetanlepage-dendritic-nix-config**: Single `core` aggregate, all modules dendritic exports
2. **drupol-dendritic-infra**: Multi-aggregate (`base`, `shell`, `desktop`), all modules dendritic exports

**Key Finding:** BOTH references use Pattern A (all-dendritic, aggregate namespaces). ZERO references use Pattern B (underscore workaround).

**Team Unanimous (9/9):** Refactor to Pattern A immediately.

**Pattern A (Drupol Multi-Aggregate) Structure:**

```nix
# Component module: modules/home/development/git.nix (NOT _development/)
{
  flake.modules.homeManager.development = { config, pkgs, lib, flake, ... }: {
    programs.git = {
      # ... config with access to flake.inputs, flake.config
    };
  };
}

# User module: modules/home/users/crs58/default.nix
{
  flake.modules.homeManager."users/crs58" = {
    imports = with config.flake.modules.homeManager; [
      development  # All 7 Priority 1 modules (merged aggregate)
      ai           # All 4 Priority 2 modules (merged aggregate)
      shell        # All 6 Priority 3 modules (merged aggregate)
    ];
  };
}
```

**Aggregate Organization (17 modules → 3 aggregates):**
- homeManager.development (7 modules: git, jujutsu, neovim, wezterm, zed, starship, zsh)
- homeManager.ai (4 modules: claude-code, mcp-servers, wrappers, ccstatusline-settings)
- homeManager.shell (6 modules: atuin, yazi, zellij, tmux, bash, nushell)

**Strategic Rationale:**
- Refactoring cost ~8 hours (same as finishing Pattern B migrations would have been)
- Restores full functionality (11 disabled features re-enabled)
- Aligns with industry-standard pattern (both gaetanlepage and drupol references)
- Unblocks Story 1.10C (secrets need modules with flake context for clan vars)
- Fixes darwinConfigurations build failure (lazyvim accessible via flake.inputs)

---

## Acceptance Criteria

### A. Validation Experiment (Murat's 1-Hour Test)

**AC1: Single Module Pattern A Conversion**
- [ ] Convert ONE module (git.nix) to Pattern A as proof-of-concept
- [ ] Create `development` aggregate namespace: `flake.modules.homeManager.development`
- [ ] Wrap git.nix in dendritic export: `flake.modules.homeManager.development = { config, pkgs, lib, flake, ... }: { programs.git = { ... }; }`
- [ ] Move `modules/home/_development/git.nix` → `modules/home/development/git.nix` (remove underscore)
- [ ] Verify import-tree auto-discovers new location (no underscore prevention)

**AC2: Validation Experiment Integration**
- [ ] Import in crs58 user module: `imports = [ config.flake.modules.homeManager.development ];`
- [ ] Build validation: `nix build .#homeConfigurations.aarch64-darwin.crs58.activationPackage` succeeds
- [ ] Verify flake context accessible in git.nix module
- [ ] If successful: Proceed with full refactoring (AC B-H)
- [ ] If fails: Analyze root cause (infinite recursion, evaluation errors), adjust approach

**Estimated Time:** 1 hour (de-risks full refactoring)

### B. Aggregate Namespace Organization

**AC3: Define Three-Aggregate Structure**
- [ ] Define aggregate structure for 17 modules (following drupol pattern):
  - `homeManager.development` (7 modules: git, jujutsu, neovim, wezterm, zed, starship, zsh)
  - `homeManager.ai` (4 modules: claude-code, mcp-servers, wrappers, ccstatusline-settings)
  - `homeManager.shell` (6 modules: atuin, yazi, zellij, tmux, bash, nushell)
- [ ] Document aggregate organization rationale in story dev notes

**AC4: Directory Restructuring**
- [ ] Remove underscore prefixes: `_development/` → `development/`, `_tools/` → `ai/` and `shell/`
- [ ] Move modules to new locations:
  - Priority 1: `_development/*.nix` → `development/*.nix`
  - Priority 2: `_tools/claude-code/*.nix` → `ai/claude-code/*.nix`
  - Priority 3: `_tools/atuin.nix` etc. → `shell/*.nix`
- [ ] Verify all modules auto-discovered by import-tree (no underscore prevention needed)
- [ ] Verify no stale files in `_development/` or `_tools/` directories

**AC5: Aggregate Namespace Merging**
- [ ] Multiple files merge into single aggregate namespace (e.g., development/git.nix + development/jujutsu.nix both export to homeManager.development)
- [ ] Verify namespace merging works correctly (no conflicts)
- [ ] Test individual module builds after namespace definition

### C. Refactor Existing Modules to Pattern A

**AC6: Priority 1 Modules (7 modules → development aggregate)**
- [ ] Wrap each module in dendritic export wrapper:
  - Before: `{ config, pkgs, lib, ... }: { programs.git = { ... }; }`
  - After: `{ flake.modules.homeManager.development = { config, pkgs, lib, flake, ... }: { programs.git = { ... }; }; }`
- [ ] Refactor all 7 modules:
  - [ ] git.nix
  - [ ] jujutsu.nix
  - [ ] neovim/default.nix (+ lazyvim.nix, plugins.nix)
  - [ ] wezterm/default.nix
  - [ ] zed/default.nix
  - [ ] starship.nix
  - [ ] zsh.nix
- [ ] Preserve module content (move inside wrapper, no functional changes yet)
- [ ] Verify individual builds after each module refactoring

**AC7: Priority 2 Modules (4 modules → ai aggregate)**
- [ ] Wrap in `flake.modules.homeManager.ai = { config, pkgs, lib, flake, ... }: { ... }`
- [ ] Refactor all 4 modules:
  - [ ] claude-code/default.nix
  - [ ] claude-code/mcp-servers.nix
  - [ ] claude-code/wrappers.nix
  - [ ] claude-code/ccstatusline-settings.nix
- [ ] Move: `_tools/claude-code/*.nix` → `ai/claude-code/*.nix`
- [ ] Note disabled features for restoration in AC E

**AC8: Priority 3 Modules (6 modules → shell aggregate)**
- [ ] Wrap in `flake.modules.homeManager.shell = { config, pkgs, lib, flake, ... }: { ... }`
- [ ] Refactor all 6 modules:
  - [ ] atuin.nix
  - [ ] yazi.nix
  - [ ] zellij.nix
  - [ ] tmux.nix
  - [ ] bash.nix
  - [ ] nushell/default.nix
- [ ] Move: `_tools/*.nix` → `shell/*.nix`
- [ ] Note catppuccin-nix tmux integration for restoration in AC E

### D. Update User Modules to Import Aggregates

**AC9: crs58 User Module Refactoring**
- [ ] Change from relative imports to aggregate imports
- [ ] Before (Pattern B): 17 relative paths like `../../_development/git.nix`
- [ ] After (Pattern A):
  ```nix
  imports = with config.flake.modules.homeManager; [
    development  # All 7 Priority 1 modules
    ai           # All 4 Priority 2 modules
    shell        # All 6 Priority 3 modules
  ];
  ```
- [ ] Remove all relative import statements
- [ ] Verify build succeeds with aggregate imports
- [ ] Verify all 17 modules integrated for crs58

**AC10: raquel User Module Refactoring**
- [ ] Selective aggregate imports (raquel doesn't need ai tools):
  ```nix
  imports = with config.flake.modules.homeManager; [
    development  # git, starship, zsh, neovim
    shell        # atuin, yazi, tmux, bash
  ];
  ```
- [ ] Verify raquel gets appropriate subset (no claude-code, no MCP servers, no wrappers)
- [ ] Verify build succeeds for raquel configuration
- [ ] Verify 13 modules total for raquel (7 development + 6 shell)

### E. Restore Disabled Features (from Story 1.10B TODOs)

**AC11: SSH Signing (git.nix, jujutsu.nix)**
- [ ] Re-enable sops-nix blocks (flake context now available via `flake` parameter)
- [ ] Use `flake.config` for user lookup pattern
- [ ] git.nix: Restore sops.secrets configuration for signing key
- [ ] jujutsu.nix: Restore sops.secrets configuration for signing key
- [ ] Prepare for Story 1.10C clan vars migration (working sops-nix → working clan vars)
- [ ] Verify signing key paths accessible in module

**AC12: MCP API Keys (mcp-servers.nix)**
- [ ] Re-enable 3 disabled `sops.secrets` blocks (firecrawl, huggingface, context7)
- [ ] Re-enable 3 disabled `sops.templates` blocks
- [ ] Access flake.config for user lookup
- [ ] Verify MCP server configurations with secrets functional
- [ ] Verify 8 MCP servers without secrets remain functional

**AC13: GLM Wrapper (wrappers.nix)**
- [ ] Re-enable entire GLM wrapper (sops.secrets + home.packages with writeShellApplication)
- [ ] Access flake.config for API key path
- [ ] Verify GLM wrapper package created correctly
- [ ] Verify xdg.configFile sharing remains enabled

**AC14: nix-ai-tools claude-code Package (default.nix)**
- [ ] Uncomment: `package = flake.inputs.nix-ai-tools.packages.${pkgs.stdenv.hostPlatform.system}.claude-code;`
- [ ] Access flake.inputs via `flake` parameter
- [ ] Verify flake input available (check flake.nix inputs section)
- [ ] Verify package builds correctly
- [ ] If flake input not configured: Document limitation, keep disabled with TODO

**AC15: ccstatusline (default.nix)**
- [ ] Investigate package availability (pkgs.ccstatusline or flake input)
- [ ] Re-enable if package source identified
- [ ] If unavailable: Document limitation, keep disabled with clear comment
- [ ] Update TODO comment with investigation findings

**AC16: catppuccin-nix tmux Theme (tmux.nix)**
- [ ] Re-integrate 36-line `catppuccin.tmux = { ... }` block removed in commit 6b7f33f
- [ ] Access catppuccin-nix flake input for home-manager module
- [ ] Restore: window styling, status bar separators, kubernetes module customizations
- [ ] Verify catppuccin-nix flake input available
- [ ] Verify theme applies correctly
- [ ] If flake input not configured: Document limitation, defer to future story

### F. Build Validation

**AC17: homeConfigurations Validation**
- [ ] `nix build .#homeConfigurations.aarch64-darwin.crs58.activationPackage` SUCCEEDS
- [ ] `nix build .#homeConfigurations.aarch64-darwin.raquel.activationPackage` SUCCEEDS
- [ ] Verify all 17 modules integrated for crs58
- [ ] Verify 13 module subset for raquel (development + shell, no ai)
- [ ] Record build artifacts for package diff comparison

**AC18: darwinConfigurations Validation (CRITICAL FIX)**
- [ ] `nix build .#darwinConfigurations.blackphos.system` SUCCEEDS
- [ ] Lazyvim integration functional (flake.inputs.lazyvim accessible)
- [ ] Previous Pattern B failure: "option 'programs.lazyvim' does not exist" RESOLVED
- [ ] Verify full darwin system builds successfully
- [ ] Verify no evaluation errors or warnings

**AC19: Feature Validation**
- [ ] SSH signing configs present and accessible (sops-nix or clan vars ready)
- [ ] MCP servers with API keys functional (3 servers re-enabled)
- [ ] GLM wrapper operational (API key accessible)
- [ ] catppuccin tmux theme integrated (if flake input available)
- [ ] nix-ai-tools package integrated (if flake input configured)

### G. Zero-Regression Validation

**AC20: Package Diff Analysis**
- [ ] Compare Pattern B vs Pattern A package lists:
  - homeConfigurations.crs58: all Pattern B packages present + restored features
  - homeConfigurations.raquel: all Pattern B packages present
- [ ] No functionality lost from Pattern B
- [ ] All 11 disabled features restored (or documented if blocked by external factors)
- [ ] Record package count differences (expected: +5 to +11 packages from restored features)

**AC21: Build Regression Testing**
- [ ] darwinConfigurations.blackphos: build succeeds (was failing in Pattern B)
- [ ] All existing test-clan tests continue passing
- [ ] No new evaluation errors introduced
- [ ] No new build warnings introduced

### H. Documentation

**AC22: Refactoring Documentation in Story**
- [ ] Pattern B → Pattern A transformation documented in work item dev notes
- [ ] Why Pattern B failed (11 limitations from Story 1.10B dev notes)
- [ ] How Pattern A solves issues (flake context access, aggregate namespaces)
- [ ] Aggregate organization rationale (development, ai, shell following drupol pattern)
- [ ] Reference implementations documented (gaetanlepage, drupol patterns)

**AC23: Architecture Updates**
- [ ] Update `docs/notes/architecture/home-manager-architecture.md` (or create if missing) with Pattern A as standard
- [ ] Document aggregate namespace pattern (multi-aggregate like drupol, not monolithic like gaetanlepage)
- [ ] Remove Pattern B references (underscore workaround was dead end)
- [ ] Document validation experiment approach (1-hour de-risking strategy)

**AC24: Story 1.10B Lessons Learned**
- [ ] Underscore workaround prevented import-tree discovery but blocked flake context
- [ ] Both reference implementations (gaetanlepage, drupol) use Pattern A for good reason
- [ ] Party Mode architectural review validated empirically (11 failures documented)
- [ ] Evidence-based decision-making prevented wasted effort on Pattern B migrations
- [ ] Document in story completion notes and learnings section

---

## Tasks / Subtasks

### Task 1: Validation Experiment - Prove Pattern A Works (AC: 1-2)

**Estimated Time:** 1 hour

- [ ] **1.1: Convert git.nix to Pattern A**
  - [ ] Create `modules/home/development/` directory in test-clan
  - [ ] Copy `modules/home/_development/git.nix` → `modules/home/development/git.nix`
  - [ ] Wrap content in dendritic export: `{ flake.modules.homeManager.development = { config, pkgs, lib, flake, ... }: { <original content> }; }`
  - [ ] Verify flake parameter accessible in module signature

- [ ] **1.2: Test import-tree auto-discovery**
  - [ ] Verify `development/git.nix` auto-discovered (no underscore prevention)
  - [ ] Check flake evaluation for namespace: `nix eval .#flake.modules.homeManager.development --apply builtins.attrNames`

- [ ] **1.3: Update crs58 user module for validation**
  - [ ] Add import: `imports = [ config.flake.modules.homeManager.development ];`
  - [ ] Keep existing relative imports temporarily (parallel testing)

- [ ] **1.4: Build validation**
  - [ ] Run: `nix build .#homeConfigurations.aarch64-darwin.crs58.activationPackage`
  - [ ] Verify build succeeds with Pattern A git.nix
  - [ ] Verify flake.inputs accessible in git.nix module

- [ ] **1.5: Decision gate**
  - [ ] If SUCCESS: Proceed with full refactoring (Task 2-7)
  - [ ] If FAILURE: Analyze error (infinite recursion, eval errors), adjust approach, retry

### Task 2: Organize Aggregate Namespace Structure (AC: 3-5)

**Estimated Time:** 30 minutes

- [ ] **2.1: Create aggregate directory structure**
  - [ ] Create `modules/home/development/` (if not exists from Task 1)
  - [ ] Create `modules/home/ai/claude-code/` (nested structure for ai aggregate)
  - [ ] Create `modules/home/shell/` (shell aggregate)

- [ ] **2.2: Document aggregate organization**
  - [ ] Add dev notes section explaining 3-aggregate pattern
  - [ ] Document module distribution: development (7), ai (4), shell (6)
  - [ ] Reference drupol pattern (multi-aggregate) vs gaetanlepage (monolithic)

- [ ] **2.3: Verify import-tree discovery**
  - [ ] Check all new directories discovered by import-tree
  - [ ] Verify no underscore prevention needed (standard directories)

### Task 3: Refactor Priority 1 Modules (development aggregate) (AC: 6)

**Estimated Time:** 2-3 hours

- [ ] **3.1: Refactor git.nix** (already done in Task 1)
  - [ ] Move `_development/git.nix` → `development/git.nix`
  - [ ] Wrap in `flake.modules.homeManager.development`
  - [ ] Add `flake` parameter to module signature
  - [ ] Build test: `nix build .#homeConfigurations.aarch64-darwin.crs58.activationPackage`

- [ ] **3.2: Refactor jujutsu.nix**
  - [ ] Move `_development/jujutsu.nix` → `development/jujutsu.nix`
  - [ ] Wrap in `flake.modules.homeManager.development` (merges with git.nix namespace)
  - [ ] Add `flake` parameter
  - [ ] Build test after merge

- [ ] **3.3: Refactor neovim modules**
  - [ ] Move `_development/neovim/` → `development/neovim/`
  - [ ] Wrap `neovim/default.nix` in `flake.modules.homeManager.development`
  - [ ] Ensure lazyvim.nix, plugins.nix accessible via relative imports within neovim/
  - [ ] Add `flake` parameter to default.nix
  - [ ] Build test

- [ ] **3.4: Refactor wezterm**
  - [ ] Move `_development/wezterm/` → `development/wezterm/`
  - [ ] Wrap in `flake.modules.homeManager.development`
  - [ ] Add `flake` parameter
  - [ ] Build test

- [ ] **3.5: Refactor zed**
  - [ ] Move `_development/zed/` → `development/zed/`
  - [ ] Wrap in `flake.modules.homeManager.development`
  - [ ] Add `flake` parameter
  - [ ] Build test

- [ ] **3.6: Refactor starship.nix**
  - [ ] Move `_development/starship.nix` → `development/starship.nix`
  - [ ] Wrap in `flake.modules.homeManager.development`
  - [ ] Add `flake` parameter
  - [ ] Build test

- [ ] **3.7: Refactor zsh.nix**
  - [ ] Move `_development/zsh.nix` → `development/zsh.nix`
  - [ ] Wrap in `flake.modules.homeManager.development`
  - [ ] Add `flake` parameter
  - [ ] Build test

- [ ] **3.8: Clean up _development/ directory**
  - [ ] Verify all files moved to development/
  - [ ] Remove `_development/` directory
  - [ ] Commit: "refactor(story-1.10BA): migrate Priority 1 modules to Pattern A (development aggregate)"

### Task 4: Refactor Priority 2 Modules (ai aggregate) (AC: 7)

**Estimated Time:** 1.5-2 hours

- [ ] **4.1: Refactor claude-code/default.nix**
  - [ ] Move `_tools/claude-code/default.nix` → `ai/claude-code/default.nix`
  - [ ] Wrap in `flake.modules.homeManager.ai`
  - [ ] Add `flake` parameter
  - [ ] Build test

- [ ] **4.2: Refactor claude-code/mcp-servers.nix**
  - [ ] Move `_tools/claude-code/mcp-servers.nix` → `ai/claude-code/mcp-servers.nix`
  - [ ] Wrap in `flake.modules.homeManager.ai` (merges with default.nix namespace)
  - [ ] Add `flake` parameter
  - [ ] Note disabled sops-nix features (3 MCP servers) for Task 5
  - [ ] Build test

- [ ] **4.3: Refactor claude-code/wrappers.nix**
  - [ ] Move `_tools/claude-code/wrappers.nix` → `ai/claude-code/wrappers.nix`
  - [ ] Wrap in `flake.modules.homeManager.ai`
  - [ ] Add `flake` parameter
  - [ ] Note disabled GLM wrapper for Task 5
  - [ ] Build test

- [ ] **4.4: Refactor claude-code/ccstatusline-settings.nix**
  - [ ] Move `_tools/claude-code/ccstatusline-settings.nix` → `ai/claude-code/ccstatusline-settings.nix`
  - [ ] Wrap in `flake.modules.homeManager.ai`
  - [ ] Add `flake` parameter
  - [ ] Build test

- [ ] **4.5: Clean up**
  - [ ] Verify all claude-code files moved
  - [ ] Commit: "refactor(story-1.10BA): migrate Priority 2 modules to Pattern A (ai aggregate)"

### Task 5: Refactor Priority 3 Modules (shell aggregate) (AC: 8)

**Estimated Time:** 1.5-2 hours

- [ ] **5.1: Refactor atuin.nix**
  - [ ] Move `_tools/atuin.nix` → `shell/atuin.nix`
  - [ ] Wrap in `flake.modules.homeManager.shell`
  - [ ] Add `flake` parameter
  - [ ] Build test

- [ ] **5.2: Refactor yazi.nix**
  - [ ] Move `_tools/yazi.nix` → `shell/yazi.nix`
  - [ ] Wrap in `flake.modules.homeManager.shell`
  - [ ] Add `flake` parameter
  - [ ] Build test

- [ ] **5.3: Refactor zellij.nix**
  - [ ] Move `_tools/zellij.nix` → `shell/zellij.nix`
  - [ ] Wrap in `flake.modules.homeManager.shell`
  - [ ] Add `flake` parameter
  - [ ] Build test

- [ ] **5.4: Refactor tmux.nix**
  - [ ] Move `_tools/tmux.nix` → `shell/tmux.nix`
  - [ ] Wrap in `flake.modules.homeManager.shell`
  - [ ] Add `flake` parameter
  - [ ] Note removed catppuccin-nix theme (36 lines) for Task 5
  - [ ] Build test

- [ ] **5.5: Refactor bash.nix**
  - [ ] Move `_tools/bash.nix` → `shell/bash.nix`
  - [ ] Wrap in `flake.modules.homeManager.shell`
  - [ ] Add `flake` parameter
  - [ ] Build test

- [ ] **5.6: Refactor nushell**
  - [ ] Move `_tools/nushell/` → `shell/nushell/`
  - [ ] Wrap `nushell/default.nix` in `flake.modules.homeManager.shell`
  - [ ] Add `flake` parameter
  - [ ] Build test

- [ ] **5.7: Clean up**
  - [ ] Verify all _tools/ files moved
  - [ ] Remove `_tools/` directory
  - [ ] Commit: "refactor(story-1.10BA): migrate Priority 3 modules to Pattern A (shell aggregate)"

### Task 6: Update User Modules for Aggregate Imports (AC: 9-10)

**Estimated Time:** 30 minutes

- [ ] **6.1: Update crs58 user module**
  - [ ] Remove all 17 relative imports from `modules/home/users/crs58/default.nix`
  - [ ] Add aggregate imports:
    ```nix
    imports = with config.flake.modules.homeManager; [
      development
      ai
      shell
    ];
    ```
  - [ ] Build test: `nix build .#homeConfigurations.aarch64-darwin.crs58.activationPackage`
  - [ ] Verify all 17 modules integrated

- [ ] **6.2: Update raquel user module**
  - [ ] Remove all relative imports from `modules/home/users/raquel/default.nix`
  - [ ] Add selective aggregate imports:
    ```nix
    imports = with config.flake.modules.homeManager; [
      development
      shell
    ];
    ```
  - [ ] Build test: `nix build .#homeConfigurations.aarch64-darwin.raquel.activationPackage`
  - [ ] Verify 13 modules integrated (no ai aggregate)

- [ ] **6.3: Commit user module updates**
  - [ ] Commit: "refactor(story-1.10BA): update user modules for aggregate imports"

### Task 7: Restore Disabled Features (AC: 11-16)

**Estimated Time:** 2-3 hours

- [ ] **7.1: Restore SSH signing (git.nix, jujutsu.nix)**
  - [ ] git.nix: Uncomment sops.secrets configuration for signing key
  - [ ] git.nix: Use `flake.config` for user lookup: `user = flake.config.clan.inventory.services.user-${config.home.username}.config.user`
  - [ ] jujutsu.nix: Uncomment sops.secrets configuration
  - [ ] jujutsu.nix: Use `flake.config` for user lookup
  - [ ] Build test
  - [ ] Verify signing key paths accessible (prepare for Story 1.10C clan vars)

- [ ] **7.2: Restore MCP API keys (mcp-servers.nix)**
  - [ ] Uncomment 3 sops.secrets blocks (firecrawl, huggingface, context7)
  - [ ] Uncomment 3 sops.templates blocks for MCP server configs
  - [ ] Use `flake.config` for user lookup in secrets paths
  - [ ] Build test
  - [ ] Verify 11 MCP servers total (8 without secrets + 3 with secrets)

- [ ] **7.3: Restore GLM wrapper (wrappers.nix)**
  - [ ] Uncomment sops.secrets block for glm-api-key
  - [ ] Uncomment home.packages GLM wrapper (writeShellApplication)
  - [ ] Use `flake.config` for API key path
  - [ ] Build test
  - [ ] Verify GLM wrapper package created

- [ ] **7.4: Restore nix-ai-tools claude-code package (default.nix)**
  - [ ] Check if nix-ai-tools flake input configured in flake.nix
  - [ ] If configured: Uncomment `package = flake.inputs.nix-ai-tools.packages.${pkgs.stdenv.hostPlatform.system}.claude-code;`
  - [ ] If not configured: Document limitation, keep disabled with TODO
  - [ ] Build test (if uncommented)

- [ ] **7.5: Investigate ccstatusline (default.nix)**
  - [ ] Check pkgs.ccstatusline availability
  - [ ] Search for ccstatusline flake input or custom package
  - [ ] If available: Uncomment statusLine.command configuration
  - [ ] If unavailable: Document limitation clearly in comment
  - [ ] Update TODO comment with investigation findings

- [ ] **7.6: Restore catppuccin-nix tmux theme (tmux.nix)**
  - [ ] Check if catppuccin-nix flake input configured in flake.nix
  - [ ] If configured: Re-integrate 36-line catppuccin.tmux block from commit 6b7f33f
  - [ ] Access catppuccin-nix via flake.inputs for home-manager module
  - [ ] Restore window styling, status bar separators, kubernetes customizations
  - [ ] Build test (if re-integrated)
  - [ ] If not configured: Document limitation, defer to future story

- [ ] **7.7: Commit feature restoration**
  - [ ] Commit: "feat(story-1.10BA): restore disabled features with flake context access"

### Task 8: Build Validation and Regression Testing (AC: 17-21)

**Estimated Time:** 1 hour

- [ ] **8.1: homeConfigurations validation**
  - [ ] Build crs58: `nix build .#homeConfigurations.aarch64-darwin.crs58.activationPackage`
  - [ ] Build raquel: `nix build .#homeConfigurations.aarch64-darwin.raquel.activationPackage`
  - [ ] Record build artifacts for package diff analysis
  - [ ] Verify all 17 modules for crs58, 13 modules for raquel

- [ ] **8.2: darwinConfigurations validation (CRITICAL FIX)**
  - [ ] Build blackphos: `nix build .#darwinConfigurations.blackphos.system`
  - [ ] Verify build SUCCEEDS (Pattern B failed with lazyvim error)
  - [ ] Verify no evaluation errors or warnings
  - [ ] Verify lazyvim integration functional

- [ ] **8.3: Package diff analysis**
  - [ ] Compare Pattern B vs Pattern A package lists
  - [ ] Expected: +5 to +11 packages from restored features
  - [ ] Verify no Pattern B packages lost
  - [ ] Document package count differences in dev notes

- [ ] **8.4: Test suite validation**
  - [ ] Run all existing test-clan tests
  - [ ] Verify no regressions introduced
  - [ ] All tests should continue passing

- [ ] **8.5: Feature validation**
  - [ ] Verify SSH signing configs present (sops-nix or prepared for clan vars)
  - [ ] Verify MCP servers with API keys functional
  - [ ] Verify GLM wrapper operational (if restored)
  - [ ] Verify catppuccin tmux theme integrated (if restored)
  - [ ] Verify nix-ai-tools package integrated (if restored)

### Task 9: Documentation (AC: 22-24)

**Estimated Time:** 1 hour

- [ ] **9.1: Update story dev notes**
  - [ ] Document Pattern B → Pattern A transformation process
  - [ ] Why Pattern B failed (11 limitations from Story 1.10B)
  - [ ] How Pattern A solves issues (flake context, aggregate namespaces)
  - [ ] Aggregate organization rationale (development, ai, shell)
  - [ ] Reference implementations (gaetanlepage, drupol)

- [ ] **9.2: Update architecture documentation**
  - [ ] Update or create `docs/notes/architecture/home-manager-architecture.md` in test-clan
  - [ ] Document Pattern A as standard (multi-aggregate dendritic pattern)
  - [ ] Remove Pattern B references (underscore workaround deprecated)
  - [ ] Document validation experiment approach (1-hour de-risking)
  - [ ] Add drupol multi-aggregate vs gaetanlepage monolithic comparison

- [ ] **9.3: Document Story 1.10B lessons learned**
  - [ ] Underscore workaround blocked flake context (fundamental limitation)
  - [ ] Both references use Pattern A (validated industry standard)
  - [ ] Party Mode review empirically validated (11 failures documented)
  - [ ] Evidence-based decision-making prevented waste
  - [ ] Add to story completion notes and learnings section

- [ ] **9.4: Final commit and summary**
  - [ ] Commit: "docs(story-1.10BA): comprehensive Pattern A migration documentation"
  - [ ] Update story status to "review" in dev notes
  - [ ] Prepare summary for review: modules refactored, features restored, builds passing

---

## Dev Notes

### Architectural Context

**Pattern A (Drupol Multi-Aggregate Dendritic):**

Pattern A uses dendritic exports at the component module level with aggregate namespaces:

```nix
# Component module: modules/home/development/git.nix
{
  flake.modules.homeManager.development = { config, pkgs, lib, flake, ... }: {
    programs.git = {
      enable = true;
      # Full access to flake.inputs, flake.config
      signing.key = config.sops.secrets."${flake.config.users.${config.home.username}.sopsIdentifier}/signing-key".path;
    };
  };
}

# User module: modules/home/users/crs58/default.nix
{
  flake.modules.homeManager."users/crs58" = {
    imports = with config.flake.modules.homeManager; [
      development  # Merged aggregate (7 modules)
      ai           # Merged aggregate (4 modules)
      shell        # Merged aggregate (6 modules)
    ];
  };
}
```

**Benefits:**
- Full flake context access (`flake.inputs.*`, `flake.config.*`)
- sops-nix user lookup works (requires `flake.config`)
- Flake input integration functional (nix-ai-tools, lazyvim, catppuccin-nix)
- Home-manager modules from flake inputs accessible
- Aggregate namespaces enable selective composition (raquel imports development + shell only)
- Auto-discovery by import-tree (no underscore prevention needed)

**Pattern B (Underscore + Plain Modules) - DEPRECATED:**

Pattern B attempted to use underscore directories to prevent auto-discovery with plain home-manager modules:

```nix
# Component module: modules/home/_development/git.nix (underscore prevents discovery)
{ config, pkgs, lib, ... }: {  # NO flake parameter
  programs.git = {
    enable = true;
    # Cannot access flake.inputs or flake.config - BROKEN
  };
}

# User module: modules/home/users/crs58/default.nix
{
  flake.modules.homeManager."users/crs58" = {
    imports = [
      ../../_development/git.nix  # Relative imports (fragile)
      # ... 17 relative paths
    ];
  };
}
```

**Critical Limitations (Story 1.10B Evidence):**
1. **No flake context** - Plain modules signature: `{ config, pkgs, lib, ... }` (missing `flake` parameter)
2. **sops-nix broken** - Requires `flake.config` for user lookup, incompatible with plain modules
3. **Flake inputs unreachable** - Cannot access `flake.inputs.nix-ai-tools`, `flake.inputs.lazyvim`, etc.
4. **Home-manager module integration fails** - catppuccin-nix module from flake input not accessible
5. **darwinConfigurations build failure** - "option 'programs.lazyvim' does not exist"

### Pattern B Failures - Empirical Evidence from Story 1.10B

Story 1.10B Session 2 (2025-11-14, commits 92bb19b..d4ef3a2) discovered **11 disabled features** and **1 critical build failure**:

**11 Disabled Features:**
1. SSH signing (git.nix) - sops-nix DISABLED, requires flake.config user lookup
2. SSH signing (jujutsu.nix) - sops-nix DISABLED
3. MCP firecrawl server (mcp-servers.nix) - API key sops-nix DISABLED
4. MCP huggingface server (mcp-servers.nix) - API key sops-nix DISABLED
5. MCP context7 server (mcp-servers.nix) - API key sops-nix DISABLED
6. GLM wrapper (wrappers.nix) - Entire wrapper DISABLED (sops-nix API key)
7. nix-ai-tools claude-code package (default.nix) - Custom package DISABLED (flake.inputs unreachable)
8. ccstatusline package (default.nix) - Package unavailable (needs flake input)
9. catppuccin-nix tmux theme (tmux.nix) - Entire 36-line block REMOVED (flake input unreachable)
10. catppuccin tmux window styling - Part of removed block
11. catppuccin tmux status bar separators - Part of removed block

**Build Failure:**
- `nix build .#darwinConfigurations.blackphos.system` **FAILS**
- Error: `The option 'home-manager.users.crs58.programs.lazyvim' does not exist`
- Root cause: lazyvim home-manager module requires flake input, unreachable in plain modules
- Impact: Cannot build complete darwin system configuration

**Functional Status with Pattern B:** ~85% (core functionality present, secrets/themes/packages disabled)

[Source: Story 1.10B Dev Notes lines 767-1031]

### Pattern A Solution - How It Fixes Pattern B Failures

**Flake Context Access:**
- Module signature: `{ config, pkgs, lib, flake, ... }` (includes `flake` parameter)
- Enables `flake.inputs.*` access for custom packages, themes, home-manager modules
- Enables `flake.config.*` access for sops-nix user lookup

**sops-nix User Lookup Restored:**
```nix
# Pattern A - WORKS
user = flake.config.clan.inventory.services.user-${config.home.username}.config.user;
signing.key = config.sops.secrets."${user.sopsIdentifier}/signing-key".path;

# Pattern B - BROKEN (no flake parameter)
# Cannot access flake.config, user lookup impossible
```

**Flake Input Integration Restored:**
```nix
# Pattern A - WORKS
package = flake.inputs.nix-ai-tools.packages.${pkgs.stdenv.hostPlatform.system}.claude-code;
catppuccin.tmux.enable = true;  # catppuccin-nix module from flake.inputs

# Pattern B - BROKEN (no flake parameter)
# Cannot access flake.inputs, custom packages and themes unavailable
```

**Expected Outcome:** 100% functionality (all 11 features restored, darwinConfigurations build succeeds)

### Reference Implementations

**Party Mode Investigation (2025-11-14):**

9 agents investigated two reference implementations to determine industry-standard pattern:

**1. gaetanlepage/dendritic-nix-config (Single Aggregate Pattern):**
- Repository: `~/projects/nix-workspace/gaetanlepage-dendritic-nix-config/`
- Pattern: All modules export to single `core` aggregate
- Structure: `flake.modules.homeManager.core` (monolithic namespace)
- Modules: All dendritic exports, NO underscore directories
- Result: 100% Pattern A (dendritic at component level)

**2. drupol/dendritic-infra (Multi-Aggregate Pattern):**
- Repository: `~/projects/nix-workspace/drupol-dendritic-infra/`
- Pattern: Modules organized into multiple aggregates (`base`, `shell`, `desktop`)
- Structure: `flake.modules.homeManager.{base,shell,desktop}`
- Modules: All dendritic exports, selective composition enabled
- Result: 100% Pattern A (dendritic at component level + aggregate organization)

**Key Finding:** BOTH references use Pattern A (all-dendritic, aggregate namespaces). ZERO references use Pattern B (underscore workaround).

**Team Unanimous (9/9):** Refactor to Pattern A immediately.

**Story 1.10BA Follows drupol Multi-Aggregate Pattern:**
- 3 aggregates: development (7), ai (4), shell (6)
- Selective composition: raquel imports development + shell only (no ai)
- Dendritic exports at component level (all modules have flake context)

[Source: Party Mode Investigation Session 2025-11-14]

### Learnings from Previous Story (Story 1.10B)

**From Story 1.10B (Status: done-with-limitations)**

Story 1.10B migrated 17 home-manager modules using Pattern B (Session 2, 2025-11-14). Implementation revealed critical architectural limitations that necessitate this refactoring story.

**New Patterns/Services Created (Pattern B - to be refactored):**
- 17 home-manager modules migrated: 7 Priority 1 (development), 4 Priority 2 (AI tools), 6 Priority 3 (shell/terminal)
- Underscore directory pattern: `_development/`, `_tools/` (prevents import-tree auto-discovery)
- Plain home-manager modules: `{ config, pkgs, lib, ... }` signature (NO flake parameter)
- Relative import pattern in user modules: 17 `../../_development/*.nix` imports

**Architectural Limitations Discovered:**
- No flake context access (fundamental limitation, not a bug)
- sops-nix completely incompatible (requires flake.config lookups)
- Flake input integration requires higher-level wiring (cannot be done in plain modules)
- Home-manager modules from flake inputs need darwin/nixos integration (cannot import in plain modules)

**Files Modified (Pattern B locations - will be moved to Pattern A):**
- Created: `modules/home/_development/*.nix` (7 modules) → **Move to `development/`**
- Created: `modules/home/_tools/claude-code/*.nix` (4 modules) → **Move to `ai/claude-code/`**
- Created: `modules/home/_tools/*.nix` (6 modules) → **Move to `shell/`**
- Modified: `modules/home/users/crs58/default.nix` (17 relative imports) → **Refactor to aggregate imports**
- Modified: `modules/home/users/raquel/default.nix` (7 relative imports) → **Refactor to aggregate imports**

**Technical Debt from Pattern B:**
- 11 features disabled (documented in Story 1.10B dev notes lines 806-904)
- darwinConfigurations build failure (lazyvim integration broken)
- Secrets management deferred to Story 1.10C (blocked by lack of flake context)
- Theme integration deferred (catppuccin-nix unreachable)
- Custom package integration deferred (nix-ai-tools unreachable)

**Warnings for This Story:**
- Pattern B modules exist in underscore directories - move to standard directories
- All modules need dendritic export wrapper added
- User modules need complete refactoring (relative imports → aggregate imports)
- 11 disabled features need restoration (sops-nix blocks, flake input packages, themes)
- darwinConfigurations build must succeed (critical validation)

**DO NOT Recreate:**
- Underscore directories (`_development/`, `_tools/`) - use standard directories
- Plain home-manager modules without flake parameter - use dendritic exports
- Relative imports in user modules - use aggregate namespace imports

**REUSE:**
- Module content (programs.git, programs.jujutsu, etc.) - preserve functionality
- Module organization (Priority 1-3 grouping) - maps to development/ai/shell aggregates
- User module selective composition (raquel subset) - aggregate pattern enables this

[Source: Story 1.10B Dev Notes lines 767-1031, File List, Completion Notes]

### Testing Standards

**Build Validation (CRITICAL):**

All builds must succeed before story completion:

```bash
# homeConfigurations (PRIMARY)
nix build .#homeConfigurations.aarch64-darwin.crs58.activationPackage
nix build .#homeConfigurations.aarch64-darwin.raquel.activationPackage

# darwinConfigurations (CRITICAL FIX)
nix build .#darwinConfigurations.blackphos.system  # Must SUCCEED (Pattern B FAILED)
```

**Package Diff Analysis:**

Compare Pattern B vs Pattern A package lists to validate zero-regression:

```bash
# Pattern B baseline (from Story 1.10B)
nix build .#homeConfigurations.aarch64-darwin.crs58.activationPackage
nix-store -qR result | wc -l  # Record count

# Pattern A (after refactoring)
nix build .#homeConfigurations.aarch64-darwin.crs58.activationPackage
nix-store -qR result | wc -l  # Should be >= Pattern B count

# Expected: +5 to +11 packages from restored features
```

**Test Suite Validation:**

All existing test-clan tests must continue passing:

```bash
# Run full test suite
nix flake check

# Verify no regressions
# All tests from Story 1.9/1.10/1.10A/1.10B should pass
```

**Feature Validation Checklist:**

After feature restoration (Task 7), verify:
- [ ] SSH signing configs present and accessible (git.nix, jujutsu.nix)
- [ ] MCP servers with API keys functional (3 servers: firecrawl, huggingface, context7)
- [ ] GLM wrapper operational (package created, API key accessible)
- [ ] catppuccin tmux theme integrated (if flake input available)
- [ ] nix-ai-tools package integrated (if flake input configured)
- [ ] ccstatusline documented (available or limitation documented)

### Quick Reference

**Target Repository:** ~/projects/nix-workspace/test-clan/

**Build Commands:**

```bash
# Validation experiment (Task 1)
cd ~/projects/nix-workspace/test-clan
nix build .#homeConfigurations.aarch64-darwin.crs58.activationPackage

# Full validation (Task 8)
nix build .#homeConfigurations.aarch64-darwin.crs58.activationPackage
nix build .#homeConfigurations.aarch64-darwin.raquel.activationPackage
nix build .#darwinConfigurations.blackphos.system  # MUST SUCCEED

# Test suite
nix flake check
```

**Module Locations:**

Pattern B (CURRENT - to be removed):
```
modules/home/_development/          # 7 modules → development/
modules/home/_tools/claude-code/    # 4 modules → ai/claude-code/
modules/home/_tools/                # 6 modules → shell/
modules/home/users/crs58/           # 17 relative imports → aggregate imports
modules/home/users/raquel/          # 7 relative imports → aggregate imports
```

Pattern A (TARGET - after refactoring):
```
modules/home/development/           # 7 modules, flake.modules.homeManager.development
modules/home/ai/claude-code/        # 4 modules, flake.modules.homeManager.ai
modules/home/shell/                 # 6 modules, flake.modules.homeManager.shell
modules/home/users/crs58/           # Imports: development, ai, shell
modules/home/users/raquel/          # Imports: development, shell (no ai)
```

**Aggregate Structure:**

```nix
# development aggregate (7 modules)
flake.modules.homeManager.development = {
  # Merged from: git.nix, jujutsu.nix, neovim/, wezterm/, zed/, starship.nix, zsh.nix
};

# ai aggregate (4 modules)
flake.modules.homeManager.ai = {
  # Merged from: claude-code/default.nix, mcp-servers.nix, wrappers.nix, ccstatusline-settings.nix
};

# shell aggregate (6 modules)
flake.modules.homeManager.shell = {
  # Merged from: atuin.nix, yazi.nix, zellij.nix, tmux.nix, bash.nix, nushell/
};

# User composition
flake.modules.homeManager."users/crs58" = {
  imports = with config.flake.modules.homeManager; [ development ai shell ];
};

flake.modules.homeManager."users/raquel" = {
  imports = with config.flake.modules.homeManager; [ development shell ];  # Selective
};
```

**Module Distribution:**

| Aggregate | Modules | Count | Users |
|-----------|---------|-------|-------|
| development | git, jujutsu, neovim, wezterm, zed, starship, zsh | 7 | crs58, raquel |
| ai | claude-code, mcp-servers, wrappers, ccstatusline-settings | 4 | crs58 only |
| shell | atuin, yazi, zellij, tmux, bash, nushell | 6 | crs58, raquel |

**Validation Experiment (Task 1):**

Murat's 1-hour test to de-risk full refactoring:
1. Convert ONE module (git.nix) to Pattern A
2. Verify build succeeds with flake context access
3. If success → proceed with full refactoring
4. If failure → analyze error, adjust approach

**Estimated Effort:** 8-10 hours
- Validation experiment: 1h (Task 1)
- Refactoring modules: 5-6h (Tasks 2-5)
- User updates + feature restoration: 2-3h (Tasks 6-7)
- Validation + documentation: 1h (Tasks 8-9)

**Risk Level:** Medium (refactoring 17 modules, but validation experiment de-risks, proven pattern from references)

### External References

**Story 1.10B Evidence:**
- File: `~/projects/nix-workspace/infra/docs/notes/development/work-items/1-10B-migrate-home-manager-modules.md`
- Lines 767-1031: Session 2 dev notes with Pattern B limitations
- Lines 806-904: Complete list of 11 disabled features with TODO blocks
- Lines 918-928: darwinConfigurations build failure details

**Epic 1 Definition:**
- File: `~/projects/nix-workspace/infra/docs/notes/development/epics/epic-1-architectural-validation-migration-pattern-rehearsal-phase-0.md`
- Lines 701-903: Story 1.10BA complete definition
- Lines 733-881: 8 acceptance criteria (AC A-H) with detailed requirements

**Reference Implementations:**
- gaetanlepage-dendritic-nix-config: `~/projects/nix-workspace/gaetanlepage-dendritic-nix-config/modules/home/`
  - Single `core` aggregate pattern, all modules dendritic exports
- drupol-dendritic-infra: `~/projects/nix-workspace/drupol-dendritic-infra/modules/`
  - Multi-aggregate (`base`, `shell`, `desktop`) pattern, selective composition

**Quality Baseline:**
- Story 1.10A: `~/projects/nix-workspace/infra/docs/notes/development/work-items/1-10A-migrate-user-management-inventory.md`
  - Approved 5/5, comprehensive acceptance criteria, detailed tasks, complete documentation

**Architecture Documentation:**
- test-clan architecture (to be updated): `~/projects/nix-workspace/test-clan/docs/notes/architecture/home-manager-architecture.md`
- infra architecture index: `~/projects/nix-workspace/infra/docs/notes/development/architecture/index.md`

**Party Mode Investigation:**
- Date: 2025-11-14
- Team: 9 agents (unanimous 9/9 recommendation)
- Finding: Both gaetanlepage and drupol use Pattern A (all-dendritic, aggregate namespaces)
- Recommendation: Refactor to Pattern A immediately based on industry-standard pattern

---

## Dev Agent Record

### Context Reference

<!-- Path(s) to story context XML will be added here by story-context workflow -->

### Agent Model Used

<!-- Agent model name and version will be recorded during implementation -->

### Debug Log References

<!-- Links to debug sessions, error analysis, investigation notes -->

### Completion Notes List

<!-- Implementation session summaries, discoveries, decisions -->

### File List

<!-- Files created/modified during implementation -->

---

## Learnings

<!-- Post-implementation insights, architectural discoveries, pattern validations -->
<!-- This section will be populated during Party Mode checkpoint or retrospective -->

---

## Change Log

### 2025-11-14 - Story Created

- Story 1.10BA drafted based on Story 1.10B architectural limitation discoveries (Session 2, 2025-11-14)
- Critical architectural correction: Pattern B → Pattern A refactoring required
- Empirical evidence: 11 features disabled, darwinConfigurations build failure documented
- Party Mode investigation findings: Both gaetanlepage and drupol use Pattern A (9/9 unanimous recommendation)
- Complete story definition extracted from Epic 1 file (lines 701-903)
- All 8 acceptance criteria sections (AC A-H) expanded with 24 detailed ACs
- 9 tasks with comprehensive subtasks mapped to acceptance criteria
- Validation experiment approach: 1-hour git.nix conversion to de-risk full refactoring
- Dev notes include: Pattern A vs Pattern B comparison, empirical failure evidence, reference implementations
- Learnings from Story 1.10B integrated: 17 modules to refactor, Pattern B locations documented
- Testing standards defined: Build validation (3 builds), package diff analysis, test suite validation
- Quick reference: Build commands, module locations, aggregate structure, module distribution table
- External references: Story 1.10B evidence (lines 767-1031), Epic 1 definition (lines 701-903), Party Mode investigation
- Quality baseline: Story 1.10A (approved 5/5) used as template
- Estimated effort: 8-10 hours (1h validation + 5-6h refactoring + 2-3h user updates/restoration + 1h validation/docs)
- Risk level: Medium (validation experiment de-risks, proven pattern from references)
- Strategic value: Restores 11 features, fixes darwinConfigurations build, aligns with industry standard, unblocks Story 1.10C
- Dependencies: Story 1.10B (done-with-limitations), Blocks: Story 1.10C (secrets need flake context)
