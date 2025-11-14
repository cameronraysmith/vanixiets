# Story 1.10B: Migrate Home-Manager Module Ecosystem from infra to test-clan

**Epic:** Epic 1 - Architectural Validation + Migration Pattern Rehearsal (Phase 0)

**Status:** ready-for-dev

**Dependencies:**
- Story 1.10A (done): Clan inventory pattern migration complete, user management established

**Strategic Value:** Completes blackphos configuration migration (15% → 100% coverage), validates dendritic pattern at scale (51 modules vs 2-3), unblocks Story 1.12 physical deployment validation, provides empirical data for Party Mode checkpoint (Story 1.11 assessment), establishes home-manager migration pattern for Epic 2-6 (4 more machines).

**⚠️ DISCOVERED STORY - Configuration Completeness Gap**

This story was discovered during comprehensive blackphos audit (2025-11-14).
Story 1.10 claimed "no additional packages/services needed" but audit was superficial - only compared top-level darwin configs, missed 51 home-manager modules (2,500+ lines) auto-wired via nixos-unified `self.homeModules.default`.

---

## Story Description

As a system administrator,
I want to migrate the remaining 51 home-manager modules from infra to test-clan,
So that blackphos configuration is complete and ready for physical deployment validation.

**Context:**

**Investigation Findings (2025-11-14):**

Story 1.10 audit was incomplete:
- Only compared top-level darwin configuration files (`darwin/blackphos.nix`)
- Missed deep module composition via nixos-unified auto-wiring
- infra uses `self.homeModules.default` which auto-aggregates all 51 modules
- test-clan uses dendritic explicit imports (no auto-aggregation)
- Current coverage: ~15% (basic git/gh/zsh only from Story 1.8/1.10 baseline)
- Missing: Development environment (neovim, wezterm, editors), AI tooling (claude-code, 11 MCP servers), shell environment (atuin, yazi, zellij), utilities

**Deployment Risk:**

Physical deployment to blackphos with current config would cause severe productivity regression:
- No advanced editors (neovim/LazyVim, zed)
- No AI-assisted development (claude-code ecosystem, MCP servers)
- No enhanced shell environment (atuin history, yazi file manager, zellij multiplexer)
- No essential dev tools (jujutsu VCS, enhanced git config)

**Architectural Pattern Difference:**

| Aspect | infra (nixos-unified) | test-clan (dendritic) |
|--------|----------------------|----------------------|
| Module aggregation | Auto-wiring via `self.homeModules.default` | Explicit imports via namespace |
| Import mechanism | Implicit (all modules auto-included) | Explicit (`config.flake.modules.homeManager.*`) |
| Visibility | Hidden (6+ levels of indirection) | Transparent (what you import is what you get) |
| Discovery | Requires deep trace (easy to miss) | Clear from import statements |

**Module Categories (51 modules across 6 priority levels):**

See Acceptance Criteria section A for complete breakdown.

---

## Acceptance Criteria

### A. Priority 1-3 Module Migration (Critical Path)

**Priority 1: Critical Development Environment (MUST HAVE) - 7 modules**

- [ ] `git.nix` - Git with SSH signing, delta diff, lazygit, allowed_signers
- [ ] `jujutsu.nix` - Modern VCS with SSH signing, git colocate mode
- [ ] `neovim/` - LazyVim editor framework
- [ ] `wezterm/` - Terminal emulator with GPU acceleration
- [ ] `zed/` - Zed editor configuration
- [ ] `starship.nix` - Enhanced prompt (basic already migrated, add enhancements)
- [ ] `zsh.nix` - Enhanced shell (basic already migrated, add enhancements)

**Exclusion Note:** starship-jj intentionally excluded (custom Rust package, long compile time, non-essential).

**Priority 2: AI-Assisted Development (HIGH VALUE) - 4 modules**

- [ ] `claude-code/default.nix` - Claude Code CLI configuration
- [ ] `claude-code/mcp-servers.nix` - 11 MCP server configs (firecrawl, huggingface, chrome, cloudflare, duckdb, historian, mcp-prompt-server, nixos, playwright, terraform, gcloud, gcs)
- [ ] `claude-code-wrappers.nix` - GLM alternative LLM backend
- [ ] `claude-code/ccstatusline-settings.nix` - Status line configuration

**Priority 3: Shell & Terminal Environment (HIGH VALUE) - 6 modules**

- [ ] `atuin.nix` - Shell history with sync
- [ ] `yazi.nix` - Terminal file manager
- [ ] `zellij.nix` - Terminal multiplexer
- [ ] `tmux.nix` - Alternative multiplexer
- [ ] `bash.nix` - Bash shell setup
- [ ] `nushell/` - Modern structured shell

**AC1: All Priority 1 modules migrated to test-clan**
- [ ] 7 modules migrated following dendritic pattern
- [ ] Each module exported to `flake.modules.homeManager.*` namespace
- [ ] User modules (crs58, raquel) import migrated modules explicitly
- [ ] Build validation: `nix build .#homeConfigurations.crs58.activationPackage` succeeds
- [ ] starship-jj explicitly excluded with rationale documented

**AC2: All Priority 2 modules migrated**
- [ ] 4 AI tooling modules migrated (claude-code ecosystem)
- [ ] MCP servers configuration preserved (11 servers)
- [ ] GLM wrapper configuration migrated
- [ ] Status line settings migrated

**AC3: All Priority 3 modules migrated**
- [ ] 6 shell/terminal modules migrated
- [ ] Shell history (atuin) with sync capabilities
- [ ] File manager (yazi) and multiplexers (zellij, tmux)
- [ ] Alternative shells (bash, nushell) configured

### B. Module Access Pattern Updates

**AC4: Prepare for clan vars integration (coordinate with Story 1.10C)**
- [ ] Identify sops-nix references in migrated modules (git.nix, jujutsu.nix, mcp-servers.nix, claude-code-wrappers.nix)
- [ ] Document current sops-nix access patterns
- [ ] Add TODO comments for Story 1.10C clan vars migration
- [ ] Ensure modules build with current access patterns (no premature clan vars changes)

### C. Dendritic Pattern Compliance

**AC5: Module organization follows dendritic philosophy**
- [ ] All modules use explicit imports (`config.flake.modules.homeManager.*`)
- [ ] No auto-aggregation patterns (infra's `self.homeModules.default` not replicated)
- [ ] Module directory structure:
  - `modules/home/users/crs58/` - user-specific imports
  - `modules/home/users/raquel/` - user-specific imports
  - `modules/home/tools/` - reusable tool configs (created as needed)
  - `modules/home/development/` - dev environment configs (created as needed)

**AC6: Namespace exports configured**
- [ ] Each migrated module exported to dendritic namespace
- [ ] Export paths follow convention: `flake.modules.homeManager."category/module-name"`
- [ ] User modules import from namespace (no relative paths to tools/development modules)

### D. Build Validation

**AC7: All configurations build successfully**
- [ ] `nix build .#homeConfigurations.crs58.activationPackage` succeeds
- [ ] `nix build .#homeConfigurations.raquel.activationPackage` succeeds
- [ ] `nix build .#darwinConfigurations.blackphos.system` succeeds
- [ ] Zero evaluation errors

**AC8: Configuration coverage validated**
- [ ] Coverage: ~15% → ~100% (all critical Priority 1-3 functionality migrated)
- [ ] Verify Priority 1 modules present in build output
- [ ] Verify Priority 2 modules present in build output
- [ ] Verify Priority 3 modules present in build output

### E. Zero-Regression Validation

**AC9: Package diff comparison**
- [ ] Generate infra blackphos package list: `nix-store -q --references result | sort > infra-packages.txt`
- [ ] Generate test-clan blackphos package list: `nix-store -q --references result | sort > test-clan-packages.txt`
- [ ] Compare: `diff infra-packages.txt test-clan-packages.txt`
- [ ] Target: <10% package delta (acceptable additions: clan vars infrastructure)
- [ ] Document any regressions with justification

**AC10: Functional validation checklist**
- [ ] All Priority 1-3 functionality present in build
- [ ] No missing packages from infra baseline
- [ ] No broken module imports or evaluation errors
- [ ] Build time acceptable (starship-jj exclusion reduces compile time)

### F. Documentation

**AC11: Migration completion documented**
- [ ] Priority 1-3 migration checklist documented in work item
- [ ] Dendritic pattern notes captured (explicit imports, no auto-aggregation)
- [ ] Module organization documented (users/, tools/, development/ structure)
- [ ] starship-jj exclusion rationale documented

**AC12: Learnings captured for Party Mode checkpoint**
- [ ] Dendritic pattern scalability assessment (51 modules vs 2-3 in Story 1.8A)
- [ ] Auto-aggregation vs explicit imports trade-offs
- [ ] Migration effort vs maintenance cost analysis
- [ ] Input for Story 1.11 decision (type-safe architecture feasibility)

---

## Tasks / Subtasks

### Task 1: Audit infra home modules and document inventory (AC1-AC3)

- [ ] Read all Priority 1 module files from `~/projects/nix-workspace/infra/modules/home/all/development/`:
  - [ ] `git.nix` - Note sops-nix signing key references
  - [ ] `jujutsu.nix` - Note sops-nix signing key references
  - [ ] `neovim/` - Check for any secret references
  - [ ] `wezterm/` - Check for configuration dependencies
  - [ ] `zed/` - Check for configuration dependencies
  - [ ] `starship.nix` - Identify enhancements vs baseline
  - [ ] `zsh.nix` - Identify enhancements vs baseline
- [ ] Read all Priority 2 module files from `~/projects/nix-workspace/infra/modules/home/all/tools/claude-code/`:
  - [ ] `default.nix` - Claude Code CLI configuration
  - [ ] `mcp-servers.nix` - Note sops-nix API key references (11 servers)
  - [ ] `../claude-code-wrappers.nix` - Note sops-nix GLM API key reference
  - [ ] `ccstatusline-settings.nix` - Status line configuration
- [ ] Read all Priority 3 module files from `~/projects/nix-workspace/infra/modules/home/all/terminal/` and `shell/`:
  - [ ] `terminal/atuin.nix`
  - [ ] `terminal/yazi.nix`
  - [ ] `terminal/zellij.nix`
  - [ ] `terminal/tmux.nix`
  - [ ] `shell/bash.nix`
  - [ ] `shell/nushell/`
- [ ] Document sops-nix access patterns for Story 1.10C coordination
- [ ] Create migration inventory spreadsheet (module, priority, sops-nix refs, dependencies)

### Task 2: Migrate Priority 1 modules (Critical Development Environment)

- [ ] Create `modules/home/development/` directory in test-clan
- [ ] Migrate `git.nix`:
  - [ ] Copy module to `modules/home/development/git.nix`
  - [ ] Add TODO comment for sops-nix → clan vars migration (Story 1.10C)
  - [ ] Export to namespace: `flake.modules.homeManager."development/git"`
  - [ ] Verify builds independently
- [ ] Migrate `jujutsu.nix`:
  - [ ] Copy to `modules/home/development/jujutsu.nix`
  - [ ] Add TODO comment for signing key clan vars migration
  - [ ] Export to namespace: `flake.modules.homeManager."development/jujutsu"`
  - [ ] Verify builds independently
- [ ] Migrate `neovim/`:
  - [ ] Copy directory to `modules/home/development/neovim/`
  - [ ] Preserve LazyVim configuration
  - [ ] Export to namespace: `flake.modules.homeManager."development/neovim"`
  - [ ] Verify builds independently
- [ ] Migrate `wezterm/`:
  - [ ] Copy to `modules/home/development/wezterm/`
  - [ ] Export to namespace: `flake.modules.homeManager."development/wezterm"`
  - [ ] Verify builds independently
- [ ] Migrate `zed/`:
  - [ ] Copy to `modules/home/development/zed/`
  - [ ] Export to namespace: `flake.modules.homeManager."development/zed"`
  - [ ] Verify builds independently
- [ ] Enhance `starship.nix`:
  - [ ] Update existing `modules/home/tools/starship.nix` with infra enhancements
  - [ ] Explicitly exclude starship-jj (add comment: "starship-jj excluded - custom Rust package, long compile time, non-essential")
  - [ ] Verify builds independently
- [ ] Enhance `zsh.nix`:
  - [ ] Update existing `modules/home/users/crs58/zsh.nix` with infra enhancements
  - [ ] Preserve existing configuration from Story 1.8 baseline
  - [ ] Verify builds independently
- [ ] Update crs58 user module imports:
  - [ ] Add Priority 1 imports to `modules/home/users/crs58/default.nix`
  - [ ] Use explicit namespace imports: `config.flake.modules.homeManager."development/*"`
  - [ ] Build validation: `nix build .#homeConfigurations.crs58.activationPackage`

### Task 3: Migrate Priority 2 modules (AI-Assisted Development)

- [ ] Create `modules/home/tools/claude-code/` directory in test-clan
- [ ] Migrate `claude-code/default.nix`:
  - [ ] Copy to `modules/home/tools/claude-code/default.nix`
  - [ ] Export to namespace: `flake.modules.homeManager."tools/claude-code"`
  - [ ] Verify builds independently
- [ ] Migrate `claude-code/mcp-servers.nix`:
  - [ ] Copy to `modules/home/tools/claude-code/mcp-servers.nix`
  - [ ] Document 11 MCP server configurations (firecrawl, huggingface, chrome, cloudflare, duckdb, historian, mcp-prompt-server, nixos, playwright, terraform, gcloud, gcs)
  - [ ] Add TODO comments for API key clan vars migration (Story 1.10C)
  - [ ] Export to namespace: `flake.modules.homeManager."tools/claude-code/mcp-servers"`
  - [ ] Verify builds independently
- [ ] Migrate `claude-code-wrappers.nix`:
  - [ ] Copy to `modules/home/tools/claude-code/wrappers.nix`
  - [ ] Add TODO comment for GLM API key clan vars migration
  - [ ] Export to namespace: `flake.modules.homeManager."tools/claude-code/wrappers"`
  - [ ] Verify builds independently
- [ ] Migrate `claude-code/ccstatusline-settings.nix`:
  - [ ] Copy to `modules/home/tools/claude-code/ccstatusline-settings.nix`
  - [ ] Export to namespace: `flake.modules.homeManager."tools/claude-code/ccstatusline"`
  - [ ] Verify builds independently
- [ ] Update crs58 user module imports:
  - [ ] Add Priority 2 imports to `modules/home/users/crs58/default.nix`
  - [ ] Use explicit namespace imports: `config.flake.modules.homeManager."tools/claude-code/*"`
  - [ ] Build validation: `nix build .#homeConfigurations.crs58.activationPackage`

### Task 4: Migrate Priority 3 modules (Shell & Terminal Environment)

- [ ] Create `modules/home/tools/terminal/` directory in test-clan (if needed)
- [ ] Migrate `atuin.nix`:
  - [ ] Copy to `modules/home/tools/atuin.nix` (or `terminal/atuin.nix`)
  - [ ] Export to namespace: `flake.modules.homeManager."tools/atuin"`
  - [ ] Verify builds independently
- [ ] Migrate `yazi.nix`:
  - [ ] Copy to `modules/home/tools/yazi.nix`
  - [ ] Export to namespace: `flake.modules.homeManager."tools/yazi"`
  - [ ] Verify builds independently
- [ ] Migrate `zellij.nix`:
  - [ ] Copy to `modules/home/tools/zellij.nix`
  - [ ] Export to namespace: `flake.modules.homeManager."tools/zellij"`
  - [ ] Verify builds independently
- [ ] Migrate `tmux.nix`:
  - [ ] Copy to `modules/home/tools/tmux.nix`
  - [ ] Export to namespace: `flake.modules.homeManager."tools/tmux"`
  - [ ] Verify builds independently
- [ ] Migrate `bash.nix`:
  - [ ] Copy to `modules/home/users/crs58/bash.nix` (user-specific shell)
  - [ ] Export if reusable, or keep user-specific
  - [ ] Verify builds independently
- [ ] Migrate `nushell/`:
  - [ ] Copy to `modules/home/tools/nushell/` (or `users/crs58/nushell/`)
  - [ ] Export to namespace if reusable
  - [ ] Verify builds independently
- [ ] Update crs58 user module imports:
  - [ ] Add Priority 3 imports to `modules/home/users/crs58/default.nix`
  - [ ] Use explicit namespace imports: `config.flake.modules.homeManager."tools/*"`
  - [ ] Build validation: `nix build .#homeConfigurations.crs58.activationPackage`

### Task 5: Update raquel user module with Priority 1-3 imports

- [ ] Audit raquel's module needs (may differ from crs58):
  - [ ] Which Priority 1 modules does raquel need? (likely subset)
  - [ ] Which Priority 2 modules? (claude-code possibly not needed)
  - [ ] Which Priority 3 modules? (shell environment may differ)
- [ ] Update `modules/home/users/raquel/default.nix`:
  - [ ] Add appropriate Priority 1-3 imports
  - [ ] Use explicit namespace imports
  - [ ] Avoid importing modules raquel doesn't use
- [ ] Build validation: `nix build .#homeConfigurations.raquel.activationPackage`
- [ ] Document raquel's module subset in Dev Notes

### Task 6: Build validation and zero-regression testing (AC7-AC10)

- [ ] Build all configurations:
  - [ ] `nix build .#homeConfigurations.crs58.activationPackage`
  - [ ] `nix build .#homeConfigurations.raquel.activationPackage`
  - [ ] `nix build .#darwinConfigurations.blackphos.system`
  - [ ] Verify zero evaluation errors
- [ ] Generate package comparison:
  - [ ] Build infra blackphos: `cd ~/projects/nix-workspace/infra && nix build .#darwinConfigurations.blackphos.system`
  - [ ] Extract packages: `nix-store -q --references result | sort > /tmp/infra-packages.txt`
  - [ ] Build test-clan blackphos: `cd ~/projects/nix-workspace/test-clan && nix build .#darwinConfigurations.blackphos.system`
  - [ ] Extract packages: `nix-store -q --references result | sort > /tmp/test-clan-packages.txt`
  - [ ] Compare: `diff /tmp/infra-packages.txt /tmp/test-clan-packages.txt > /tmp/package-diff.txt`
  - [ ] Analyze differences (target: <10% delta)
  - [ ] Document any regressions with justification
- [ ] Verify configuration coverage:
  - [ ] Check Priority 1 modules present in build output (editors, git, terminals)
  - [ ] Check Priority 2 modules present (claude-code, MCP servers)
  - [ ] Check Priority 3 modules present (atuin, yazi, zellij, shells)
  - [ ] Verify starship-jj absent (intentionally excluded)
- [ ] Run test suite:
  - [ ] `nix flake check` (all existing tests must pass)
  - [ ] Verify zero regressions in test harness

### Task 7: Documentation and learnings capture (AC11-AC12)

- [ ] Update work item completion notes:
  - [ ] Priority 1-3 migration completion checklist
  - [ ] Package diff analysis results
  - [ ] Zero-regression validation evidence
  - [ ] Build time improvements (starship-jj exclusion impact)
- [ ] Capture dendritic pattern learnings:
  - [ ] Scalability assessment (51 modules vs 2-3 in Story 1.8A)
  - [ ] Explicit imports vs auto-aggregation trade-offs:
    - Pros: Transparency, no hidden dependencies, clear what's included
    - Cons: More verbose, requires namespace management
  - [ ] Migration effort analysis (time spent, difficulties encountered)
  - [ ] Maintenance cost projection (adding new modules, updating existing)
- [ ] Document for Party Mode checkpoint:
  - [ ] Evidence for Story 1.11 type-safe architecture decision
  - [ ] Architectural pattern validation results
  - [ ] Recommendations for Epic 2-6 (migrate all 4 machines? subset only?)
- [ ] Update Dev Notes with:
  - [ ] starship-jj exclusion rationale
  - [ ] Module organization decisions (tools/ vs development/ vs users/)
  - [ ] Story 1.10C coordination notes (sops-nix → clan vars prep)

---

## Dev Notes

### Implementation Context

**Target Repository:** `~/projects/nix-workspace/test-clan/`
**Source Repository:** `~/projects/nix-workspace/infra/`
**Management Repository:** `~/projects/nix-workspace/infra/` (this story file location)

**Current State (Story 1.10A Baseline):**
- User management migrated to clan inventory pattern
- Home-manager modules: ~15% coverage (basic git/gh/zsh only)
- crs58/raquel portable home modules extracted (Story 1.8A)
- Source modules location: `~/projects/nix-workspace/infra/modules/home/all/`
- 51 modules identified across 6 categories (investigation 2025-11-14)

**Target State (Story 1.10B):**
- Priority 1-3 modules migrated (17 modules total: 7 P1 + 4 P2 + 6 P3)
- Module organization: `modules/home/development/`, `modules/home/tools/`, `modules/home/users/`
- All modules exported to dendritic namespace
- User modules import explicitly (no auto-aggregation)
- Configuration coverage: ~15% → ~100% (Priority 1-3 complete)
- Zero regression + ready for Story 1.10C (clan vars migration)

### Architectural Context

**nixos-unified Auto-Wiring (infra pattern):**

```nix
# infra: modules/home/default.nix auto-aggregates all modules
homeModules.default = {
  imports = [
    ./all/development/git.nix
    ./all/development/jujutsu.nix
    ./all/tools/claude-code
    # ... 51 modules auto-included
  ];
};

# User config gets ALL modules implicitly
home-manager.users.crs58 = {
  imports = [ self.homeModules.default ];
  # ALL 51 modules active (no explicit selection)
};
```

**Dendritic Explicit Imports (test-clan pattern):**

```nix
# test-clan: Each module exports to namespace
flake.modules.homeManager."development/git" = ./modules/home/development/git.nix;
flake.modules.homeManager."tools/claude-code" = ./modules/home/tools/claude-code;
# ... each module explicitly exported

# User config imports explicitly
modules/home/users/crs58/default.nix:
imports = [
  config.flake.modules.homeManager."development/git"
  config.flake.modules.homeManager."development/jujutsu"
  config.flake.modules.homeManager."tools/claude-code"
  # ... only imported modules active
];
```

**Pattern Comparison:**

| Aspect | nixos-unified (infra) | Dendritic (test-clan) |
|--------|----------------------|----------------------|
| **Aggregation** | Automatic via `homeModules.default` | Manual via namespace imports |
| **Visibility** | Hidden (6+ indirection levels) | Transparent (import list) |
| **Discovery** | Requires deep trace (easy to miss in audit) | Clear from import statements |
| **Maintenance** | Add module → auto-included | Add module → export + import |
| **Granularity** | All-or-nothing (or complex opt-out) | Fine-grained (import what you need) |
| **Migration Risk** | Easy to miss modules (as in Story 1.10 audit) | Hard to miss (no import = not included) |

**Pattern B (Secrets) Preparation:**

Story 1.10C will migrate sops-nix → clan vars.
This story (1.10B) must prepare by:
1. Identifying sops-nix references in migrated modules
2. Adding TODO comments for Story 1.10C
3. Ensuring modules build with current access patterns (no premature changes)

Affected modules:
- `git.nix`: `config.sops.secrets."admin-user/signing-key".path`
- `jujutsu.nix`: Same signing key reference
- `mcp-servers.nix`: API keys for 11 MCP servers
- `claude-code-wrappers.nix`: GLM API key
- `rbw.nix`: Bitwarden email (if migrated in Priority 4+)

### Testing Standards

**Zero Regression Requirement:**

All functionality from infra must be preserved in test-clan:
- Same packages available (via `nix-store -q --references` diff)
- Same development environment (editors, shells, terminals)
- Same AI tooling (claude-code, MCP servers)
- Build time acceptable (starship-jj exclusion reduces Rust compile time)

**Build Validation Commands:**

```bash
# Home configurations
nix build .#homeConfigurations.crs58.activationPackage
nix build .#homeConfigurations.raquel.activationPackage

# Darwin configuration
nix build .#darwinConfigurations.blackphos.system

# Test suite
nix flake check
```

**Package Diff Comparison:**

```bash
# Generate infra baseline
cd ~/projects/nix-workspace/infra
nix build .#darwinConfigurations.blackphos.system
nix-store -q --references result | sort > /tmp/infra-packages.txt

# Generate test-clan result
cd ~/projects/nix-workspace/test-clan
nix build .#darwinConfigurations.blackphos.system
nix-store -q --references result | sort > /tmp/test-clan-packages.txt

# Compare (target: <10% delta)
diff /tmp/infra-packages.txt /tmp/test-clan-packages.txt | tee /tmp/package-diff.txt

# Analyze additions/removals
grep '^<' /tmp/package-diff.txt | wc -l  # Packages in infra only
grep '^>' /tmp/package-diff.txt | wc -l  # Packages in test-clan only
```

**Acceptable Deltas:**
- Additions: Clan vars infrastructure, test-clan specific packages
- Removals: starship-jj (intentionally excluded), infra-specific packages
- Target: <10% total package delta

### Quick Reference

**Build Commands:**

```bash
# Working directory
cd ~/projects/nix-workspace/test-clan

# Build home configurations
nix build .#homeConfigurations.crs58.activationPackage
nix build .#homeConfigurations.raquel.activationPackage

# Build darwin configuration
nix build .#darwinConfigurations.blackphos.system

# Test suite
nix flake check

# Package inspection
nix-store -q --references result | sort
```

**Source Module Locations (infra):**

```
~/projects/nix-workspace/infra/modules/home/all/
├── development/
│   ├── git.nix
│   ├── jujutsu.nix
│   ├── neovim/
│   ├── wezterm/
│   ├── zed/
│   ├── helix/
│   ├── radicle.nix
│   ├── gui-apps/
│   └── ghostty/
├── terminal/
│   ├── starship.nix
│   ├── atuin.nix
│   ├── yazi.nix
│   ├── zellij.nix
│   └── tmux.nix
├── shell/
│   ├── bash.nix
│   ├── zsh.nix
│   └── nushell/
├── tools/
│   ├── claude-code/
│   │   ├── default.nix
│   │   ├── mcp-servers.nix
│   │   └── ccstatusline-settings.nix
│   ├── claude-code-wrappers.nix
│   ├── commands/
│   ├── bat.nix
│   ├── bottom.nix
│   ├── nix.nix
│   ├── gpg.nix
│   ├── pandoc.nix
│   ├── awscli.nix
│   ├── k9s.nix
│   ├── rbw.nix
│   ├── texlive.nix
│   └── ... (more tools)
└── core/
    ├── profile.nix
    ├── xdg.nix
    ├── sops.nix
    └── bitwarden.nix
```

**Target Module Locations (test-clan):**

```
~/projects/nix-workspace/test-clan/modules/home/
├── users/
│   ├── crs58/
│   │   ├── default.nix       # User-specific imports (Priority 1-3 modules)
│   │   ├── bash.nix           # User-specific bash config (if not reusable)
│   │   └── zsh.nix            # Enhanced from infra baseline
│   └── raquel/
│       └── default.nix        # Raquel-specific imports (subset of crs58)
├── development/
│   ├── git.nix                # Priority 1 (NEW)
│   ├── jujutsu.nix            # Priority 1 (NEW)
│   ├── neovim/                # Priority 1 (NEW)
│   ├── wezterm/               # Priority 1 (NEW)
│   └── zed/                   # Priority 1 (NEW)
└── tools/
    ├── starship.nix           # Priority 1 (enhanced from baseline)
    ├── atuin.nix              # Priority 3 (NEW)
    ├── yazi.nix               # Priority 3 (NEW)
    ├── zellij.nix             # Priority 3 (NEW)
    ├── tmux.nix               # Priority 3 (NEW)
    ├── nushell/               # Priority 3 (NEW)
    └── claude-code/
        ├── default.nix        # Priority 2 (NEW)
        ├── mcp-servers.nix    # Priority 2 (NEW)
        ├── wrappers.nix       # Priority 2 (NEW)
        └── ccstatusline-settings.nix  # Priority 2 (NEW)
```

### Learnings from Previous Story (Story 1.10A)

**From Story 1.10A (Status: done) - User Management Migration**

**Key Achievements:**
- Clan inventory users service pattern validated end-to-end
- Two-instance pattern (user-cameron, user-crs58) handles cross-platform username differences
- Vars system proven for password management (automatic generation + SOPS encryption)
- VPS deployment successful (cinnabar IP: 49.13.68.78, SSH login verified)

**Critical Patterns to Reuse:**
- **Explicit imports pattern:** Use `config.flake.modules.homeManager.*` for clarity
- **Namespace organization:** Clear directory structure (users/, tools/, development/)
- **Build validation workflow:** Test builds locally before moving to next task
- **Zero regression mindset:** Package diff comparison catches unintended changes

**Architectural Decisions:**
- **Machine-specific targeting:** Avoid `tags.all`, use explicit machine lists to prevent incorrect deployments
- **Inline vs separate files:** Inline configuration works for inventory, but separate files better for home modules (easier to maintain, clearer structure)
- **Platform awareness:** Handle darwin vs nixos differences explicitly (pkgs.stdenv.isDarwin conditionals)

**Testing Context:**
- 10 checks passing in test harness (TC-001 through TC-024)
- Test harness location: `modules/checks/validation.nix`
- Pattern: Add new tests as TC-XXX numbered test cases

**Learnings Relevant to Story 1.10B:**
- **Auto-discovery works:** Dendritic import-tree finds modules automatically
- **Explicit > Implicit:** Clear imports prevent "where did this come from?" debugging
- **Incremental validation:** Build after each module migration catches errors early
- **Documentation pays off:** Clear patterns in work items prevent confusion during implementation

[Source: work-items/1-10A-migrate-user-management-inventory.md#Dev-Agent-Record]

### Exclusions and Constraints

**starship-jj Explicitly Excluded:**

**Rationale:**
- Custom Rust package (requires full Rust toolchain compilation)
- Long compile time (10-30 minutes depending on hardware)
- Non-essential functionality (enhanced jujutsu integration for starship prompt)
- Basic starship configuration already migrated (Story 1.8/1.10 baseline)
- Enhanced starship.nix from infra provides 95% of value without starship-jj

**Implementation Note:**
Add explicit comment in migrated starship.nix:
```nix
# starship-jj intentionally excluded
# Rationale: Custom Rust package with long compile time, non-essential
# Story 1.10B decision (2025-11-14)
# Basic starship config provides 95% of value without starship-jj overhead
```

**Priority 4-6 Modules Deferred:**

Priority 4-6 modules (24 modules) intentionally deferred to future work:
- Not critical for physical deployment validation (Story 1.12)
- Can be added incrementally post-deployment
- Reduces Story 1.10B scope (12-16 hours vs 24-30 hours with all 51 modules)

**Deferred modules:**
- Priority 4: radicle, commands/, bat, bottom, gpg, pandoc (6 modules)
- Priority 5: awscli, k9s, rbw, texlive (4 modules)
- Priority 6: profile, xdg, bitwarden, tealdeer, macchina, nixpkgs, agents-md (7 modules)
- Plus: helix, ghostty, gui-apps (7 modules)

**Rationale:** Priority 1-3 provides complete development environment (17 modules = 33% of 51 total), unblocks Story 1.12, sufficient for Party Mode checkpoint assessment.

### External References

**Source Repository (infra):**
- `~/projects/nix-workspace/infra/modules/home/all/` - 51 home-manager modules
- Investigation report: Comprehensive blackphos audit (2025-11-14)

**Reference Implementation (Story 1.10A):**
- `~/projects/nix-workspace/infra/docs/notes/development/work-items/1-10A-migrate-user-management-inventory.md`
- Reference for structure, quality standards, completion notes format

**Epic Definition:**
- `~/projects/nix-workspace/infra/docs/notes/development/epics/epic-1-architectural-validation-migration-pattern-rehearsal-phase-0.md`
- Lines 572-696: Complete Story 1.10B definition

**Dendritic Pattern References:**
- `~/projects/nix-workspace/dendritic-flake-parts/` - Pattern source
- `~/projects/nix-workspace/dendrix-dendritic-nix/` - Reference implementation
- `~/projects/nix-workspace/gaetanlepage-dendritic-nix-config/` - Reference implementation

**nixos-unified Pattern (for comparison):**
- `~/projects/nix-workspace/nixos-unified/` - Auto-wiring mechanism
- `~/projects/nix-workspace/srid-nixos-config/` - Usage example
- Understanding auto-aggregation helps explain why Story 1.10 audit missed modules

### Project Structure Notes

**Dendritic Auto-Discovery:**
- Modules in `modules/home/development/*.nix` → Auto-discovered by import-tree
- Modules in `modules/home/tools/*.nix` → Auto-discovered by import-tree
- Export to namespace via flake-parts: `flake.modules.homeManager."category/module"`
- User modules import from namespace: `config.flake.modules.homeManager."category/module"`

**No Manual Flake-Level Imports Required:**
Dendritic pattern eliminates manual flake.nix module lists:
- ❌ Old pattern: Edit flake.nix to add every module
- ✅ New pattern: Add module file, auto-discovered, export to namespace

**Directory Structure Decisions:**

Three organizational categories chosen for clarity:
1. **`modules/home/users/`** - User-specific imports and user-specific configs
2. **`modules/home/development/`** - Dev environment (editors, VCS, terminals)
3. **`modules/home/tools/`** - Reusable tools (claude-code, shells, utilities)

Alternative considered: Flat `modules/home/` structure.
Rejected because: 51 modules in one directory = hard to navigate, unclear organization.

### References

**Epic Definition:**
- [Source: docs/notes/development/epics/epic-1-architectural-validation-migration-pattern-rehearsal-phase-0.md, lines 572-696]

**Investigation Evidence:**
- Comprehensive blackphos audit (2025-11-14) - Available in conversation history
- 51 modules identified across 6 categories
- Configuration coverage gap: ~15% (test-clan) vs 100% (infra)

**Previous Story Context:**
- [Source: docs/notes/development/work-items/1-10A-migrate-user-management-inventory.md]
- Proven dendritic pattern implementation
- Zero-regression validation methodology
- Documentation standards

**Architecture Documentation:**
- [Source: docs/notes/development/architecture/index.md] - Architecture index
- [Planned: Story 1.10C will update migration-patterns.md with home-manager migration learnings]

---

## Dev Agent Record

### Context Reference

- [Story 1.10B Context XML](./1-10B-migrate-home-manager-modules.context.xml) - Generated 2025-11-14

### Agent Model Used

<!-- Model name and version will be added during implementation -->

### Debug Log References

<!-- Debug logs will be added during implementation -->

### Completion Notes List

<!-- Implementation notes will be added during development -->

### File List

<!-- Files created/modified will be listed during implementation -->

---

## Change Log

### 2025-11-14 - Story Created
- Story 1.10B drafted based on comprehensive blackphos audit findings
- Complete story definition extracted from epic file (lines 572-696)
- All 6 acceptance criteria sections (A-F) preserved from epic definition
- 7 tasks with detailed subtasks for Priority 1-3 migration
- starship-jj exclusion explicitly documented (user direction, 2025-11-14)
- Estimated effort: 12-16 hours (6-8h P1 + 3-4h P2 + 2-3h P3 + 1-2h validation/docs)
- Risk level: Medium (extensive refactoring, 51 modules, but proven dendritic patterns)
- Strategic value: Completes blackphos migration, validates dendritic at scale, unblocks Story 1.12
