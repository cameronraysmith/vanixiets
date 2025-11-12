# Story 1.8A: Extract Portable Home-Manager Modules for Cross-Platform User Config Sharing

**Epic:** Epic 1 - Architectural Validation + Migration Pattern Rehearsal (Phase 0)

**Status:** ready-for-dev

**Dependencies:**
- Story 1.8 (review): blackphos config implemented with inline home configs
- **Blocks:** Story 1.9 (cinnabar NixOS config needs crs58 module)
- **Blocks:** Story 1.10 (heterogeneous network validation needs shared crs58 config)

**Strategic Value:** Restores proven capability from infra (modular home-manager configs) that was lost in Story 1.8 prototype. Enables DRY principle for user configs across 6 machines (1 VPS + 4 darwin + future). Validates cross-platform user config sharing as part of Epic 1 architectural validation.

---

## Story Description

As a system administrator,
I want to extract crs58 and raquel home-manager configurations from blackphos into portable, reusable modules,
So that user configs can be shared across platforms (darwin + NixOS) without duplication and support three integration modes (darwin integrated, NixOS integrated, standalone).

**Context:**
Story 1.8 successfully migrated blackphos to test-clan's dendritic + clan pattern, but implemented home-manager configs inline in the machine module. This is a **feature regression** from infra's proven modular pattern. The inline approach blocks Epic 1 progression:
- Story 1.9 (cinnabar) needs crs58 home config → would require duplication
- Story 1.10 (network validation) needs crs58 on both platforms → would require maintaining two versions
- Epic 2+: 4 more machines need crs58 config → would create 6 duplicate configs

**Epic 1 Goal:** Architectural validation must prove cross-platform user config sharing works.

**This Story:** Restores modular home-manager pattern adapted to dendritic + clan architecture.

---

## Acceptance Criteria

### AC1: crs58 Home Module Created and Exported to Dendritic Namespace

- [ ] Module created: `test-clan/modules/home/users/crs58/default.nix`
- [ ] Content extracted from blackphos lines 128-148:
  - `home.stateVersion = "23.11"`
  - `programs.zsh.enable = true`
  - `programs.starship.enable = true`
  - `programs.git.enable = true` with Cameron Smith credentials
  - `home.packages = [ git gh ]`
- [ ] Dendritic export pattern:
  ```nix
  {
    flake.modules.homeManager."users/crs58" = { config, pkgs, lib, ... }: {
      # User configuration here
    };
  }
  ```
- [ ] Auto-discovered by import-tree (no manual flake.nix import)
- [ ] Export verifiable: `nix eval .#flake.modules.homeManager --apply 'x: builtins.attrNames x'` shows `"users/crs58"`

**Implementation Notes:**
- Follow dendritic pattern from test-clan `modules/system/nix-settings.nix` (lines 1-23)
- Use `flake.modules.homeManager.*` namespace (new platform, parallel to darwin/nixos)
- No capture of outer config needed (home modules are leaf nodes, not importing other modules yet)

### AC2: raquel Home Module Created and Exported to Dendritic Namespace

- [ ] Module created: `test-clan/modules/home/users/raquel/default.nix`
- [ ] Content extracted from blackphos lines 151-182:
  - `home.stateVersion = "23.11"`
  - `programs.zsh.enable = true`
  - `programs.starship.enable = true`
  - `programs.git.enable = true` with "Someone Local" credentials
  - `home.packages = [ git gh just ripgrep fd bat eza ]`
  - LazyVim disabled (implicit in test-clan - no module present)
- [ ] Dendritic export pattern (same as AC1)
- [ ] Auto-discovered by import-tree
- [ ] Export verifiable: namespace includes `"users/raquel"`

**Implementation Notes:**
- raquel has more dev tools than crs58 (admin vs primary user differentiation)
- Keep configs separate (no shared base module yet - premature abstraction)

### AC3: Standalone homeConfigurations Exposed in Flake

- [ ] Create flake-level module: `test-clan/modules/home/configurations.nix`
- [ ] Expose `flake.homeConfigurations.crs58`:
  ```nix
  { inputs, config, ... }:
  {
    flake.homeConfigurations.crs58 = inputs.home-manager.lib.homeManagerConfiguration {
      pkgs = import inputs.nixpkgs { system = "aarch64-darwin"; }; # Multi-platform support
      modules = [
        config.flake.modules.homeManager."users/crs58"
      ];
    };
  }
  ```
- [ ] Expose `flake.homeConfigurations.raquel` (same pattern)
- [ ] Username-only naming (no `@hostname`) for portability
- [ ] Standalone configs buildable: `nix build .#homeConfigurations.crs58.activationPackage`
- [ ] Multi-platform support: Both darwin and linux pkgs supported (pkgs arg parameterized)

**Implementation Notes:**
- Reference home-manager.lib.homeManagerConfiguration API
- Use `config.flake.modules.homeManager.*` to import user modules
- Consider adding system parameter if needed for cross-platform

### AC4: blackphos Refactored to Import Shared Modules (Zero Regression)

- [ ] blackphos `home-manager.users.crs58` refactored from inline to namespace import:
  ```nix
  home-manager.users.crs58.imports = [
    config.flake.modules.homeManager."users/crs58"
  ];
  ```
- [ ] blackphos `home-manager.users.raquel` refactored (same pattern)
- [ ] Remove inline config (lines 128-183 deleted, replaced with imports)
- [ ] Pre-refactor package list captured:
  ```bash
  nix-store -qR $(nix build .#darwinConfigurations.blackphos.system --no-link --print-out-paths) | sort > pre-1.8a-packages.txt
  ```
- [ ] Post-refactor package list captured and compared (same command)
- [ ] Package diff analysis: All packages preserved (zero regression)
- [ ] Configuration builds: `nix build .#darwinConfigurations.blackphos.system`
- [ ] User-specific settings preserved (git credentials, packages, shell config)

**Implementation Notes:**
- Capture outer config for namespace access: `flakeModules = config.flake.modules.homeManager;`
- Use imports within home-manager.users.{username} block
- Validate that home-manager.useGlobalPkgs = true still works

### AC5: Standalone Home Activation Validated

- [ ] crs58 standalone activation works:
  ```bash
  nh home switch . -c crs58
  # Or: nix run .#homeConfigurations.crs58.activationPackage
  ```
- [ ] raquel standalone activation works (same workflow)
- [ ] Standalone activation creates ~/.config/home-manager symlinks
- [ ] User profile updated with correct packages
- [ ] Programs configured correctly (git, zsh, starship)
- [ ] No system-level conflicts (standalone vs integrated coexist)

**Implementation Notes:**
- Test standalone activation on a darwin machine
- Verify home-manager generations work: `home-manager generations`
- Document that standalone is independent of darwin-rebuild

### AC6: Pattern Documented for Story 1.9 Reuse (cinnabar NixOS)

- [ ] Architecture pattern documented in `architecture.md`:
  - Pattern name: "Portable Home-Manager Modules with Dendritic Integration"
  - Three integration modes (darwin, NixOS, standalone)
  - Namespace export pattern (`flake.modules.homeManager."users/{username}"`)
  - Machine import pattern (via config.flake.modules)
  - Username-only naming strategy (no @hostname)
- [ ] Story 1.9 preparation notes in Story 1.8A completion:
  - cinnabar will import `config.flake.modules.homeManager."users/crs58"`
  - Use `inputs.home-manager.nixosModules.home-manager` (NixOS equivalent)
  - Same pattern as darwin, different integration module
- [ ] nh CLI usage documented:
  - Darwin integrated: `nh darwin switch . -H blackphos`
  - NixOS integrated: `nh os switch . -H cinnabar` (Story 1.9)
  - Standalone: `nh home switch . -c crs58`

**Implementation Notes:**
- Document clan compatibility: users still defined per machine, configs imported modularly
- Document Story 1.8 lesson: inline configs are anti-pattern
- Provide cinnabar example code snippet for Story 1.9

### AC7: Test Harness Updated (Validation Coverage)

- [ ] Add validation test: `test-clan/modules/checks/validation.nix`
  - Test name: "validate-home-module-exports"
  - Verifies `flake.modules.homeManager."users/crs58"` exists
  - Verifies `flake.modules.homeManager."users/raquel"` exists
  - Verifies both are functions (proper module structure)
- [ ] Add validation test: "validate-home-configurations-exposed"
  - Verifies `flake.homeConfigurations.crs58` exists
  - Verifies `flake.homeConfigurations.raquel` exists
  - Verifies both are derivations (buildable)
- [ ] Test suite passes: `nix flake check`
- [ ] New tests added to validation category count

**Implementation Notes:**
- Follow existing validation test patterns in test-clan
- Use `assert` or `lib.assertMsg` for verification
- Keep tests fast (structural checks, not builds)

### AC8: Architectural Decisions Documented (Clan Pattern Analysis)

- [ ] Document clan-core user management investigation findings:
  - Clan users clanService exists (`clanServices/users/`) for multi-machine user account coordination
  - Decision to use traditional `users.users.*` instead of clanService (darwin compatibility + UID control)
  - Trade-offs documented: clan service abstraction vs explicit per-machine control
- [ ] Document home-manager pattern divergence analysis:
  - Clan examples use profile-based exports (`homeConfigurations.desktop` - pinpox pattern)
  - Our approach uses user-based modules (`flake.modules.homeManager."users/crs58"`)
  - Justification: Multi-user machines (blackphos: crs58 + raquel) benefit from user-granular modules
  - Dendritic namespace integration (`flake.modules.*`) vs direct flake outputs
- [ ] Document architectural alignment assessment:
  - User account management: DIVERGENT but JUSTIFIED (real-world clan usage validates pattern)
  - Portable home modules: NOVEL (fills gap in clan ecosystem)
  - Vars naming convention: ALIGNED (`ssh-key-{username}` matches clan pattern)
  - Multi-machine coordination: Manual per-machine definitions, shared configs via dendritic namespace
- [ ] Document preservation of infra features:
  - Cross-platform user config sharing validated (darwin + NixOS)
  - DRY principle maintained (single definition, multiple machines)
  - Three integration modes supported (darwin, NixOS, standalone)
  - Zero regression validated
- [ ] Add reference to clan pattern investigation:
  - Location: `docs/notes/development/clan-pattern-investigation-2025-11-12.md` (or inline in architecture.md)
  - Clan-core source analysis findings (users clanService, vars/secrets patterns)
  - Clan-infra and developer repo patterns (qubasa, mic92, pinpox)
  - Alignment matrix with recommendations

**Implementation Notes:**
- This captures the comprehensive architectural investigation completed before Story 1.8A execution
- Documents why our pattern diverges from some clan examples but is justified
- Provides context for future architectural decisions
- References clan-core source code locations for validation

---

## Implementation Tasks

### Task 1: Create crs58 Home Module (30 minutes)

**Objective:** Extract crs58 home config from blackphos into portable module

**Actions:**
1. Create directory: `test-clan/modules/home/users/crs58/`
2. Create file: `default.nix` with dendritic export pattern:
   ```nix
   {
     flake.modules.homeManager."users/crs58" = { config, pkgs, lib, ... }: {
       home.stateVersion = "23.11";
       home.username = "crs58";
       home.homeDirectory = "/Users/crs58";

       programs.zsh.enable = true;
       programs.starship.enable = true;

       programs.git = {
         enable = true;
         settings = {
           user.name = "Cameron Smith";
           user.email = "cameron.ray.smith@gmail.com";
         };
       };

       home.packages = with pkgs; [
         git
         gh
       ];
     };
   }
   ```
3. Verify export: `nix eval .#flake.modules.homeManager --apply 'x: builtins.attrNames x'`
4. Check auto-discovery: `nix flake show --all-systems | grep homeManager`

**Success Criteria:**
- File created with correct dendritic export
- Module auto-discovered by import-tree
- Export shows in namespace

### Task 2: Create raquel Home Module (30 minutes)

**Objective:** Extract raquel home config from blackphos into portable module

**Actions:**
1. Create directory: `test-clan/modules/home/users/raquel/`
2. Create file: `default.nix` with raquel's config:
   - Same structure as crs58 module
   - Different git credentials: "Someone Local" / "raquel@localhost"
   - Additional packages: `just ripgrep fd bat eza`
3. Verify export in namespace
4. Validate auto-discovery

**Success Criteria:**
- raquel module exported to namespace
- Config preserves all packages from blackphos
- Module structure matches crs58 pattern

### Task 3: Create Standalone homeConfigurations (45 minutes)

**Objective:** Expose flake-level homeConfigurations for standalone usage

**Actions:**
1. Create file: `test-clan/modules/home/configurations.nix`
2. Implement homeConfigurations for crs58:
   ```nix
   { inputs, config, ... }:
   {
     flake.homeConfigurations.crs58 = inputs.home-manager.lib.homeManagerConfiguration {
       pkgs = import inputs.nixpkgs { system = "aarch64-darwin"; };
       modules = [
         config.flake.modules.homeManager."users/crs58"
       ];
     };
   }
   ```
3. Implement raquel homeConfiguration (same pattern)
4. Test standalone build: `nix build .#homeConfigurations.crs58.activationPackage`
5. Verify both configs buildable

**Success Criteria:**
- Both homeConfigurations exposed in flake
- Standalone configs build successfully
- Ready for `nh home switch` workflow

### Task 4: Refactor blackphos to Import Shared Modules (1 hour)

**Objective:** Replace inline configs with namespace imports, validate zero regression

**Actions:**
1. Capture pre-refactor package list:
   ```bash
   cd ~/projects/nix-workspace/test-clan
   nix-store -qR $(nix build .#darwinConfigurations.blackphos.system --no-link --print-out-paths) | sort > /tmp/pre-1.8a-packages.txt
   ```
2. Edit `modules/machines/darwin/blackphos/default.nix`:
   - Capture outer config: `flakeModulesHome = config.flake.modules.homeManager;`
   - Replace crs58 inline (lines 128-148) with import:
     ```nix
     home-manager.users.crs58.imports = [
       flakeModulesHome."users/crs58"
     ];
     ```
   - Replace raquel inline (lines 151-182) with import (same pattern)
3. Build configuration: `nix build .#darwinConfigurations.blackphos.system`
4. Capture post-refactor package list: `/tmp/post-1.8a-packages.txt`
5. Compare packages: `diff /tmp/pre-1.8a-packages.txt /tmp/post-1.8a-packages.txt`
6. Analyze differences (should be minimal - only derivation paths changed)

**Success Criteria:**
- Configuration builds successfully
- Package diff shows zero functional regressions
- All user settings preserved
- Imports work via namespace

### Task 5: Test Standalone Home Activation (30 minutes)

**Objective:** Validate standalone homeConfigurations work with nh CLI

**Actions:**
1. Test crs58 standalone activation:
   ```bash
   cd ~/projects/nix-workspace/test-clan
   nh home switch . -c crs58
   # Or fallback: nix run .#homeConfigurations.crs58.activationPackage
   ```
2. Verify activation:
   - Check ~/.config/home-manager symlinks exist
   - Run `git --version` (should work)
   - Run `gh --version` (should work)
   - Check zsh config active
   - Check starship prompt appears
3. Test raquel standalone activation (same validation)
4. Verify home-manager generations: `home-manager generations`

**Success Criteria:**
- Standalone activation succeeds for both users
- User environments correctly configured
- No conflicts with darwin-rebuild activation

### Task 6: Document Pattern for Story 1.9 (45 minutes)

**Objective:** Update architecture.md with portable home-manager pattern

**Actions:**
1. Add new section to `docs/notes/development/architecture.md`:
   - Title: "Pattern: Portable Home-Manager Modules with Dendritic Integration"
   - Location: After "Pattern 2: Darwin Multi-User" section
2. Document pattern structure:
   - Module location: `modules/home/users/{username}/default.nix`
   - Dendritic export: `flake.modules.homeManager."users/{username}"`
   - Auto-discovery via import-tree
3. Document three integration modes:
   - **Mode 1**: Darwin integrated (blackphos example)
   - **Mode 2**: NixOS integrated (cinnabar Story 1.9 example)
   - **Mode 3**: Standalone (nh home switch example)
4. Document nh CLI workflows for all three modes
5. Add Story 1.8 lesson: "Inline configs are anti-pattern - always modularize"
6. Provide cinnabar code snippet for Story 1.9 reuse:
   ```nix
   # In cinnabar NixOS config
   imports = [
     inputs.home-manager.nixosModules.home-manager
   ];

   home-manager.users.crs58.imports = [
     config.flake.modules.homeManager."users/crs58"
   ];
   ```

**Success Criteria:**
- Pattern fully documented in architecture.md
- All three modes explained with examples
- Story 1.9 has clear implementation guidance
- Clan compatibility noted (users per machine, configs modular)

### Task 7: Update Test Harness with Validation Tests (30 minutes)

**Objective:** Add test coverage for home module exports and configurations

**Actions:**
1. Edit `test-clan/modules/checks/validation.nix`
2. Add test: validate-home-module-exports
   ```nix
   test-home-module-exports = pkgs.runCommand "validate-home-module-exports" {} ''
     ${
       assert builtins.hasAttr "users/crs58" config.flake.modules.homeManager;
       assert builtins.hasAttr "users/raquel" config.flake.modules.homeManager;
       assert builtins.isFunction config.flake.modules.homeManager."users/crs58";
       assert builtins.isFunction config.flake.modules.homeManager."users/raquel";
       "echo 'Home module exports valid' > $out"
     }
   '';
   ```
3. Add test: validate-home-configurations-exposed
   ```nix
   test-home-configurations = pkgs.runCommand "validate-home-configurations" {} ''
     ${
       assert builtins.hasAttr "crs58" config.flake.homeConfigurations;
       assert builtins.hasAttr "raquel" config.flake.homeConfigurations;
       "echo 'Home configurations exposed' > $out"
     }
   '';
   ```
4. Run test suite: `nix flake check`
5. Verify new tests pass

**Success Criteria:**
- Two new validation tests added
- Tests verify structural correctness
- Test suite passes with new coverage

### Task 8: Create Story Completion Notes (30 minutes)

**Objective:** Document Story 1.8A completion and unblock Story 1.9

**Actions:**
1. Add completion notes to Story 1.8A file:
   - Implementation summary (what was extracted/created)
   - Zero regression validation results (package diff)
   - Pattern proven for cross-platform reuse
   - Story 1.9 explicitly unblocked
2. Update sprint status: Mark Story 1.8A as `done`
3. Update sprint status: Remove `blocked` from Story 1.9
4. Commit changes to test-clan:
   ```bash
   cd ~/projects/nix-workspace/test-clan
   git add modules/home/
   git add modules/machines/darwin/blackphos/default.nix
   git add modules/checks/validation.nix
   git commit -m "feat(story-1.8a): extract portable home-manager modules for cross-platform reuse

   - Extract crs58 home module (modules/home/users/crs58)
   - Extract raquel home module (modules/home/users/raquel)
   - Export to dendritic namespace (flake.modules.homeManager)
   - Expose standalone homeConfigurations
   - Refactor blackphos to import shared modules
   - Add validation test coverage
   - Zero regression validated (package diff clean)
   - Unblocks Story 1.9 (cinnabar needs crs58 config)"
   ```

**Success Criteria:**
- Story completion notes comprehensive
- Sprint status updated
- Changes committed with clear message
- Story 1.9 ready to proceed

---

## Technical Notes

### Dendritic Flake-Parts Pattern (Proven in test-clan)

**Module Export Structure:**
```nix
{
  flake.modules.{platform}.{path} = { config, pkgs, lib, ... }: {
    # Module content
  };
}
```

**Auto-Discovery:**
- All `.nix` files in `modules/` discovered by `import-tree ./modules`
- Zero manual imports in flake.nix
- Namespace automatically populated

**Self-Composition:**
- Modules reference each other via `config.flake.modules.*`
- Requires capturing outer config in machine modules
- Example from blackphos:
  ```nix
  let
    flakeModules = config.flake.modules.darwin;
  in
  {
    imports = with flakeModules; [ base ];
  }
  ```

### Home-Manager Three Integration Modes

**Mode 1: Darwin Integrated (Current blackphos)**
```nix
{
  imports = [
    inputs.home-manager.darwinModules.home-manager
  ];

  home-manager.useGlobalPkgs = true;
  home-manager.useUserPackages = true;

  home-manager.users.crs58.imports = [
    config.flake.modules.homeManager."users/crs58"
  ];
}
```

**Mode 2: NixOS Integrated (Story 1.9 cinnabar)**
```nix
{
  imports = [
    inputs.home-manager.nixosModules.home-manager
  ];

  home-manager.useGlobalPkgs = true;
  home-manager.useUserPackages = true;

  home-manager.users.crs58.imports = [
    config.flake.modules.homeManager."users/crs58"
  ];
}
```

**Mode 3: Standalone (nh home workflow)**
```nix
{
  flake.homeConfigurations.crs58 = inputs.home-manager.lib.homeManagerConfiguration {
    pkgs = import inputs.nixpkgs { system = "aarch64-darwin"; };
    modules = [
      config.flake.modules.homeManager."users/crs58"
    ];
  };
}
```

### Clan-Core Compatibility

**No Clan-Specific User Management:**
- Clan-core has NO built-in user management system
- Users defined via standard NixOS `users.users` in machine modules
- Home-manager integration is standard (no clan-specific patterns)

**Per-Machine User Definitions:**
- Each machine defines its users locally
- Example from blackphos (lines 84-111):
  ```nix
  users.users.crs58 = { uid = 550; home = "/Users/crs58"; ... };
  users.users.raquel = { uid = 551; home = "/Users/raquel"; ... };
  ```

**Home Configs Imported Modularly:**
- Machine module imports shared home config from namespace
- Same user config used on multiple machines (DRY principle)
- Clan compatibility: users per machine, configs shared

### infra Proven Pattern (Reference)

**Structure:**
```
modules/home/
├── all/                   # Shared configs (core, development, terminal, tools)
├── darwin-only/           # Darwin-specific configs
├── modules/               # Sub-modules
└── default.nix            # Main entry point

configurations/home/
├── raquel@blackphos.nix   # Per-user, per-machine configs
└── ...
```

**Usage Pattern:**
```nix
# configurations/home/raquel@blackphos.nix
{
  imports = [
    self.homeModules.default
    self.homeModules.darwin-only
  ];

  # User-specific overrides
  programs.git.userName = lib.mkForce "Someone Local";
}
```

**Adaptation to test-clan:**
- Simpler structure initially: `modules/home/users/{username}/`
- No `all/` or `darwin-only/` subdirs yet (premature abstraction)
- Export to dendritic namespace instead of `homeModules.*`
- Preserve pattern for future expansion

### Zero-Regression Validation Strategy

**Package Comparison Approach:**
```bash
# Before refactoring
nix-store -qR $(nix build .#darwinConfigurations.blackphos.system --no-link --print-out-paths) | sort > pre.txt

# After refactoring
nix-store -qR $(nix build .#darwinConfigurations.blackphos.system --no-link --print-out-paths) | sort > post.txt

# Compare
diff pre.txt post.txt
```

**Expected Diff:**
- Derivation paths will change (different /nix/store hashes)
- Package names/versions should be identical
- Zero functional regressions (same packages, same config)

**Validation Checklist:**
- [ ] Build succeeds
- [ ] All packages present in post-refactor
- [ ] User settings preserved (git config, shell, tools)
- [ ] No new packages added (unless intended)
- [ ] No packages missing (regression)

### nh CLI Workflows

**Darwin Integrated:**
```bash
cd ~/projects/nix-workspace/test-clan
nh darwin switch . -H blackphos
# Activates both system and home-manager configs
```

**NixOS Integrated:**
```bash
cd ~/projects/nix-workspace/test-clan
nh os switch . -H cinnabar
# Activates both system and home-manager configs
```

**Standalone Home:**
```bash
cd ~/projects/nix-workspace/test-clan
nh home switch . -c crs58
# Activates only home-manager config (no system changes)
```

**Benefits of Standalone:**
- No sudo required (user-level activation)
- Independent of darwin-rebuild/nixos-rebuild
- Useful for testing home configs
- Portable across machines

---

## References

**test-clan Validated Patterns:**
- Dendritic pattern: Stories 1.1-1.7 (zero regressions, 17 test cases)
- Story 1.8 blackphos: Multi-user darwin config (9 commits)
- Auto-discovery: `flake.nix` line 65 `inputs.import-tree ./modules`
- Namespace exports: `modules/system/nix-settings.nix` (base auto-merge)
- Machine imports: `modules/machines/nixos/hetzner-cx43/default.nix` lines 11-12

**infra Proven Pattern:**
- Modular home: `modules/home/default.nix`, `modules/home/all/`
- Per-user configs: `configurations/home/raquel@blackphos.nix`
- Import pattern: `self.homeModules.{default,darwin-only}`

**Clan-Core Documentation:**
- No clan-specific user management (use standard NixOS)
- Home-manager integration: standard darwin/nixos modules
- Machine-scoped user definitions

**Home-Manager Documentation:**
- `homeManagerConfiguration` API for standalone configs
- Darwin integration: `darwinModules.home-manager`
- NixOS integration: `nixosModules.home-manager`

---

## Risk Mitigation

### Refactoring Risks

**Risk:** Breaking blackphos configuration during refactoring
**Mitigation:**
- Capture package list before/after (zero-regression validation)
- Test build at each step
- Keep git history clean (atomic commits)
- Test on actual blackphos hardware before marking done

**Risk:** Namespace import failures
**Mitigation:**
- Follow proven dendritic pattern from test-clan
- Capture outer config properly
- Verify exports with `nix eval`
- Test imports before deleting inline configs

### Pattern Risks

**Risk:** Three integration modes not all working
**Mitigation:**
- Implement and test each mode separately
- Validate darwin integrated first (known working in blackphos)
- Document NixOS mode for Story 1.9 validation
- Test standalone mode last (least critical)

**Risk:** Cross-platform compatibility issues
**Mitigation:**
- Keep user modules platform-agnostic (no darwin-specific code)
- Use `pkgs` parameter for platform-specific packages
- Test on both darwin (blackphos) and NixOS (cinnabar in Story 1.9)

### Data Risks

**Risk:** User data loss during home-manager activation
**Mitigation:**
- Home-manager never deletes user data (only manages symlinks)
- Backup ~/.config before standalone activation testing
- Test standalone on non-critical machine first

---

## Definition of Done

- [ ] crs58 and raquel home modules created in `modules/home/users/`
- [ ] Dendritic namespace exports verified (`flake.modules.homeManager.*`)
- [ ] Standalone homeConfigurations exposed (`flake.homeConfigurations.*`)
- [ ] blackphos refactored to import shared modules (inline configs removed)
- [ ] Zero-regression validated (package diff analysis clean)
- [ ] Standalone home activation tested and working
- [ ] Pattern documented in architecture.md for Story 1.9 reuse
- [ ] Test harness updated with validation coverage
- [ ] Story completion notes created
- [ ] Story 1.9 explicitly unblocked

---

## Dev Notes

### Story 1.8 Learnings Applied

**From Story 1.8 completion notes (line 841-861):**
- Inline configs are anti-pattern for multi-machine reuse
- Dendritic namespace imports work perfectly (validated pattern)
- Multi-user support proven (crs58 admin + raquel non-admin)
- TouchID, homebrew, state version all preserved

**Story 1.8A Builds On:**
- Proven dendritic pattern (Stories 1.1-1.7)
- Validated darwin config (Story 1.8)
- Restores infra's modular home pattern
- Adapts to dendritic + clan architecture

### Implementation Strategy

**Phase 1: Extract (Tasks 1-2)**
- Create user modules from blackphos inline configs
- Verify dendritic namespace exports

**Phase 2: Expose (Task 3)**
- Create standalone homeConfigurations
- Enable nh home switch workflow

**Phase 3: Refactor (Task 4)**
- Replace inline configs with namespace imports
- Validate zero regression

**Phase 4: Validate (Task 5-7)**
- Test standalone activation
- Document pattern
- Update test harness

**Phase 5: Complete (Task 8)**
- Story completion notes
- Unblock Story 1.9

### File List (Planned)

**New files:**
- `modules/home/users/crs58/default.nix` - crs58 portable home module
- `modules/home/users/raquel/default.nix` - raquel portable home module
- `modules/home/configurations.nix` - Standalone homeConfigurations

**Modified files:**
- `modules/machines/darwin/blackphos/default.nix` - Refactored to import shared modules
- `modules/checks/validation.nix` - Added home module validation tests
- `docs/notes/development/architecture.md` - Portable home-manager pattern documented

**Commits (planned 3-4 atomic commits):**
1. `feat(home): create crs58 and raquel portable home modules`
2. `feat(home): expose standalone homeConfigurations for nh CLI`
3. `refactor(blackphos): import shared home modules (zero regression)`
4. `docs(arch): document portable home-manager pattern for Story 1.9`

---

## Dev Agent Record

### Context Reference

- **Story Context File:** `docs/notes/development/work-items/1-8a-extract-portable-home-manager-modules.context.xml` (Generated 2025-11-12)
- Story 1.8 completion notes: `1-8-migrate-blackphos-from-infra-to-test-clan.md` lines 771-884
- test-clan dendritic pattern: Validated in Stories 1.1-1.7
- infra home modules: `~/projects/nix-workspace/infra/modules/home/`
- Correct-course workflow: Executed 2025-11-12

### Agent Model Used

claude-sonnet-4-5-20250929

### Debug Log References

N/A - Story defined via correct-course workflow, not yet implemented

### Blocking Relationships

**This story blocks:**
- Story 1.9: cinnabar NixOS config needs `config.flake.modules.homeManager."users/crs58"`
- Story 1.10: Network validation requires shared crs58 config on both darwin and NixOS
- Epic 2-6: All future machine migrations require portable user configs

**This story unblocks Epic 1 progression.**
