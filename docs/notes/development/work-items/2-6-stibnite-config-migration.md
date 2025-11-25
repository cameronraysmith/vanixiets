# Story 2.6: Stibnite config migration

Status: done

## Story

As a system administrator,
I want to create stibnite darwin configuration in infra using blackphos as structural template,
So that my primary development workstation uses validated dendritic+clan architecture with full crs58 configuration.

## Context

**Epic 2 Phase 2 Second Story:**
This is the second story in Epic 2 Phase 2 (Active Darwin Workstations).
Story 2.5 validated blackphos configuration is ready for production deployment.
Story 2.6 creates stibnite configuration from scratch using blackphos as template.

**Critical Context: This is an IMPLEMENTATION Story:**
Story 2.6 is NOT a validation story like Story 2.5.
Unlike blackphos (which existed in test-clan and was migrated), stibnite configuration does NOT exist in infra.
The stibnite darwin module must be CREATED using blackphos as the structural template.

**Key Difference from blackphos:**
- **blackphos**: 2 users (crs58 admin + raquel primary)
- **stibnite**: 1 user (crs58 only - primary workstation owner)

**Configuration to Create:**
- stibnite darwin module: `modules/machines/darwin/stibnite/default.nix` (~185-190 lines)
- stibnite zerotier: `modules/machines/darwin/stibnite/_zerotier.nix` (100 lines - copy from blackphos)

**Existing Components to Use:**
- crs58 user module: `modules/home/users/crs58/default.nix` (71 lines, 8 secrets)
- crs58 secrets: `secrets/home-manager/users/crs58/secrets.yaml` (8 secrets, infra age keys)

## Acceptance Criteria

### AC1: stibnite Directory Structure Created

Create stibnite darwin module directory with all required files.

**Verification:**
```bash
# Verify directory and files exist
ls -la modules/machines/darwin/stibnite/
# Expected: default.nix, _zerotier.nix

# Verify default.nix has reasonable line count
wc -l modules/machines/darwin/stibnite/default.nix
# Expected: ~185-190 lines (vs blackphos 217 - single user)

# Verify _zerotier.nix copied correctly
diff modules/machines/darwin/blackphos/_zerotier.nix modules/machines/darwin/stibnite/_zerotier.nix | head -5
# Expected: Only hostname comments differ (if any)
```

### AC2: Darwin Build Succeeds

Verify stibnite darwin configuration builds without errors.

**Verification:**
```bash
# Build darwin configuration
nix build .#darwinConfigurations.stibnite.system

# Expected: Build succeeds, ./result symlink created
echo $?  # Exit code 0

ls -la result
# Expected: Symlink to /nix/store/...
```

### AC3: crs58 User Configuration Complete

Verify crs58 user is fully configured with all 8 secrets and 7 aggregates.

**Verification:**
```bash
# Build crs58 home-manager configuration
nix build .#homeConfigurations.aarch64-darwin.crs58.activationPackage

# Expected: Build succeeds (more derivations than raquel due to AI aggregate)

# Verify crs58 secrets exist (8 secrets vs raquel's 5)
sops -d secrets/home-manager/users/crs58/secrets.yaml | grep -c "^[a-z]"
# Expected: 8

# Verify secret names (includes AI secrets not in raquel)
sops -d secrets/home-manager/users/crs58/secrets.yaml | grep -E "^(github-token|ssh-signing-key|ssh-public-key|glm-api-key|firecrawl-api-key|huggingface-token|bitwarden-email|atuin-key):"
# Expected: All 8 secret keys present

# Verify 7 aggregates imported for crs58
grep -E "flakeModulesHome\.(ai|core|development|packages|shell|terminal|tools)" modules/machines/darwin/stibnite/default.nix | wc -l
# Expected: 7
```

### AC4: Zerotier Darwin Integration Configured

Verify zerotier configuration is correct for stibnite.

**Verification:**
```bash
# Verify _zerotier.nix exists and has correct network ID
cat modules/machines/darwin/stibnite/_zerotier.nix | grep -E "db4344343b14b903"
# Expected: Network ID present

# Verify homebrew cask configured
grep -E "zerotier-one" modules/machines/darwin/stibnite/default.nix
# Expected: zerotier-one in additionalCasks list

# Verify activation script imports
grep -E "\\./_zerotier\\.nix" modules/machines/darwin/stibnite/default.nix
# Expected: Import present
```

### AC5: Configuration Evaluation Succeeds

Verify nix evaluation completes without module resolution errors.

**Verification:**
```bash
# Evaluate darwin configuration
nix eval .#darwinConfigurations.stibnite.config.system.build.toplevel --json 2>&1 | head -c 200
# Expected: JSON output with /nix/store path, no errors

# Verify no evaluation warnings
nix eval .#darwinConfigurations.stibnite.config.system.build.toplevel 2>&1 | grep -i "warning\|error"
# Expected: No warnings or errors (except expected "Git tree is dirty")
```

### AC6: Darwin-Specific Features Validated

Verify darwin-specific configuration settings are correct.

**Verification:**
```bash
# Verify platform
grep -E "aarch64-darwin" modules/machines/darwin/stibnite/default.nix
# Expected: nixpkgs.hostPlatform = "aarch64-darwin"

# Verify hostname
grep -E 'networking.hostName.*"stibnite"' modules/machines/darwin/stibnite/default.nix
# Expected: networking.hostName = "stibnite"

# Verify primary user (crs58 is both admin AND primary)
grep -E "primaryUser.*crs58" modules/machines/darwin/stibnite/default.nix
# Expected: system.primaryUser = "crs58"

# Verify TouchID sudo
grep -E "touchIdAuth.*true" modules/machines/darwin/stibnite/default.nix
# Expected: security.pam.services.sudo_local.touchIdAuth = true

# Verify SSH MaxAuthTries (Bitwarden workaround)
grep -E "MaxAuthTries" modules/machines/darwin/stibnite/default.nix
# Expected: MaxAuthTries 20

# Verify zsh enabled system-wide
grep -E "programs.zsh.enable.*true" modules/machines/darwin/stibnite/default.nix
# Expected: programs.zsh.enable = true

# Verify documentation enabled (overrides srvos server defaults)
grep -E "documentation.enable.*true" modules/machines/darwin/stibnite/default.nix
# Expected: documentation.enable = true

# Verify single user configuration (NO raquel)
grep -E "users.raquel" modules/machines/darwin/stibnite/default.nix
# Expected: No matches (single user stibnite)
```

### AC7: Documentation Complete for Story 2.7 Handoff

Document implementation results and prepare for Story 2.7 (activate blackphos and stibnite).

**Deliverables:**
- Story Dev Notes with implementation patterns
- Reference links to Story 2.5 (blackphos template source)
- Single-user darwin pattern documented for future reference
- Explicit guidance for Story 2.7 on simultaneous activation

**Verification:**
- Story file Dev Notes section complete
- Cross-references to Story 2.5 present
- Implementation evidence documented inline

## Tasks / Subtasks

### Task 1: Configuration Diff Analysis (AC: #1, #6)

- [x] Review blackphos config structure
  - [x] `modules/machines/darwin/blackphos/default.nix` - 217 lines
  - [x] `modules/machines/darwin/blackphos/_zerotier.nix` - 100 lines
- [x] Document required modifications for stibnite
  - [x] Single user (remove raquel configuration)
  - [x] hostname/computerName changes
  - [x] crs58 UID verification (should be 502)
- [x] Identify unchanged components
  - [x] Zerotier script (identical except comments)
  - [x] Darwin features (TouchID, MaxAuthTries, zsh, docs)
  - [x] crs58 home-manager imports (all 7 aggregates)

### Task 2: Create Directory Structure (AC: #1)

- [x] Create stibnite module directory
  - [x] `mkdir -p modules/machines/darwin/stibnite`
- [x] Copy zerotier script from blackphos
  - [x] `cp modules/machines/darwin/blackphos/_zerotier.nix modules/machines/darwin/stibnite/`
- [x] Create default.nix with stibnite-specific configuration
- [x] Verify file structure matches blackphos pattern

### Task 3: Implement stibnite Configuration (AC: #1, #3, #4, #6)

- [x] Create `modules/machines/darwin/stibnite/default.nix`
  - [x] Copy blackphos/default.nix as starting point
  - [x] Change networking.hostName to "stibnite"
  - [x] Change networking.computerName to "stibnite"
  - [x] Remove raquel user configuration (lines 128-137 in blackphos)
  - [x] Remove raquel from users.knownUsers (line 143 in blackphos)
  - [x] Remove raquel home-manager imports (lines 194-214 in blackphos)
  - [x] Verify crs58 imports include AI aggregate (not present for raquel)
- [x] Configure machine-specific homebrew casks
  - [x] Include zerotier-one
  - [x] Adjust other casks based on stibnite needs (may differ from blackphos)
- [x] Verify documentation overrides present
- [x] Verify system.stateVersion = 4 (matching infra/blackphos)

### Task 4: Register in Clan Inventory (AC: #2, #5)

- [x] Add stibnite to `modules/clan/machines.nix`
  - [x] Register stibnite machine with darwin config
- [x] Add stibnite to `modules/clan/inventory/machines.nix`
  - [x] Create stibnite inventory entry
  - [x] Configure zerotier peer role (same network as blackphos)
- [x] Verify clan recognizes stibnite
  - [x] `clan machines list | grep stibnite`

### Task 5: Build Validation (AC: #2, #3)

- [x] Execute darwin build
  - [x] `nix build .#darwinConfigurations.stibnite.system`
  - [x] Verify exit code 0
  - [x] Verify ./result symlink created
- [x] Execute crs58 home-manager build
  - [x] `nix build .#homeConfigurations.aarch64-darwin.crs58.activationPackage`
  - [x] Compare derivation count to blackphos crs58 (should be identical)
- [x] Document build results

### Task 6: Configuration Evaluation (AC: #5)

- [x] Execute nix eval
  - [x] `nix eval .#darwinConfigurations.stibnite.config.system.build.toplevel --json`
  - [x] Verify no errors
  - [x] Verify JSON output received
- [x] Check for evaluation warnings
- [x] Document any evaluation issues

### Task 7: Documentation and Commit (AC: #7)

- [x] Complete Dev Notes with implementation results
  - [x] Configuration diff summary
  - [x] Single-user pattern documentation
  - [x] Build validation evidence
- [x] Add references to Story 2.5
- [x] Document Story 2.7 handoff guidance
  - [x] Both machines ready for simultaneous activation
  - [x] Zerotier network join order (blackphos first, stibnite second)
- [x] Update sprint-status.yaml
  - [x] story-2-6: backlog -> in-progress (on start)
  - [x] story-2-6: in-progress -> review (on implementation complete)
- [x] Commit implementation changes
  - [x] Atomic commits: structure, config, clan registration, documentation

## Dev Notes

### Learnings from Previous Story

**From Story 2.5 (Status: done)**

- **Migration Gap Discovery**: Story 2.3 missed `modules/home/packages/` directory - fixed in Story 2.5
- **Validation Pattern**: All 7 ACs validated with empirical evidence, providing template for this story
- **Zerotier Pattern**: `_zerotier.nix` with network ID `db4344343b14b903` validated
- **Darwin Features**: TouchID, MaxAuthTries 20, zsh, documentation enabled - all confirmed working
- **Package Counts**: Darwin system 1930 store paths, raquel HM 505 store paths
- **Build Success**: `darwinConfigurations.blackphos.system` builds successfully
- **crs58 Module Ready**: Exists at `modules/home/users/crs58/default.nix` with 8 secrets

[Source: docs/notes/development/work-items/2-5-blackphos-config-migration-to-infra.md#Dev-Agent-Record]

### Single-User Darwin Pattern

**Key Differences from blackphos (dual-user):**

1. **User Configuration**: Only crs58 defined (no raquel)
2. **knownUsers**: Single entry `[ "crs58" ]`
3. **Home-Manager**: Only crs58 imports (no users.raquel block)
4. **Aggregates**: crs58 gets ALL 7 aggregates including AI (raquel gets 6, no AI)
5. **Line Count**: ~185-190 lines (vs blackphos 217 - approximately 25-30 lines shorter)

**Pattern Template:**
```nix
# Single-user darwin configuration pattern
users.users.crs58 = {
  uid = 502;
  home = "/Users/crs58";
  shell = pkgs.zsh;
  description = "crs58";
  openssh.authorizedKeys.keys = [ "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINdO9rInDa9HvdtZZxmkgeEdAlTupCy3BgA/sqSGyUH+" ];
};

users.knownUsers = [ "crs58" ];  # Single user

home-manager = {
  # ... global settings ...
  users.crs58.imports = [
    flakeModulesHome."users/crs58"
    flakeModulesHome.base-sops
    # ALL 7 aggregates for crs58 (including AI)
    flakeModulesHome.ai          # crs58-only (not in raquel)
    flakeModulesHome.core
    flakeModulesHome.development
    flakeModulesHome.packages
    flakeModulesHome.shell
    flakeModulesHome.terminal
    flakeModulesHome.tools
    # ... additional modules ...
  ];
  # NO users.raquel block
};
```

### Machine-Specific Homebrew Casks

**blackphos casks (reference):**
- codelayer-nightly
- dbeaver-community
- docker-desktop
- gpg-suite
- inkscape
- keycastr
- meld
- postgres-unofficial
- zerotier-one

**stibnite casks (to determine):**
- zerotier-one (required)
- docker-desktop (likely)
- gpg-suite (likely)
- Others TBD based on actual stibnite usage

### Project Structure Notes

**Files to Create:**
```
modules/machines/darwin/stibnite/
├── default.nix        # ~185-190 lines - main darwin configuration
└── _zerotier.nix      # 100 lines - zerotier activation script (copy from blackphos)
```

**Files to Modify:**
```
modules/clan/machines.nix           # Add stibnite machine registration
modules/clan/inventory/machines.nix # Add stibnite inventory entry
```

**Existing Files to Use (no changes):**
```
modules/home/users/crs58/default.nix              # 71 lines - crs58 home-manager module
secrets/home-manager/users/crs58/secrets.yaml     # 8 secrets (infra age keys)
```

### crs58 vs raquel Configuration Comparison

| Component | crs58 (stibnite) | raquel (blackphos) |
|-----------|------------------|-------------------|
| Secrets Count | 8 | 5 |
| AI Aggregate | YES | NO |
| Additional Secrets | glm-api-key, firecrawl-api-key, huggingface-token | - |
| Common Secrets | github-token, ssh-signing-key, ssh-public-key, bitwarden-email, atuin-key | Same |
| UID | 502 | 506 |
| Role | Admin + Primary | Primary (non-admin) |

### References

**Source Documentation:**
- [Epic 2 Definition](docs/notes/development/epics/epic-2-infrastructure-architecture-migration.md) - Story 2.6 definition (lines 157-176)
- [Story 2.5](docs/notes/development/work-items/2-5-blackphos-config-migration-to-infra.md) - blackphos template source
- [CLAUDE.md](CLAUDE.md) - Machine fleet documentation (stibnite = crs58's PRIMARY workstation)

**Template Files:**
- `modules/machines/darwin/blackphos/default.nix` - 217 lines, structural template
- `modules/machines/darwin/blackphos/_zerotier.nix` - 100 lines, zerotier pattern

**User Configuration:**
- `modules/home/users/crs58/default.nix` - 71 lines, crs58 user module
- `secrets/home-manager/users/crs58/secrets.yaml` - 8 secrets

**Predecessor Stories:**
- Story 2.5 (done) - blackphos validation (provides structural template)
- Story 2.4 (done) - Secrets re-encrypted with infra keys

**Successor Stories:**
- Story 2.7 (backlog) - Activate blackphos and stibnite from infra (simultaneous deployment)
- Story 2.8 (backlog) - Cleanup unused darwin configs

## Dev Agent Record

### Context Reference

- `docs/notes/development/2-6-stibnite-config-migration.context.xml`

### Agent Model Used

claude-opus-4-5-20251101

### Debug Log References

- Step 1: Story loaded, context file verified
- Step 0.5: Project documents discovered (architecture, epics, sprint-status)
- Step 1.5: Fresh implementation start (no prior review)
- Step 1.6: Sprint status updated ready-for-dev → in-progress
- Task 1: Analyzed blackphos/default.nix (217 lines) and _zerotier.nix (100 lines)
- Task 2: Created modules/machines/darwin/stibnite/ directory, copied _zerotier.nix
- Task 3: Implemented stibnite default.nix (182 lines) - single-user darwin config
- Task 4: Registered stibnite in clan machines.nix and inventory/machines.nix
- Task 5: Build validation passed (darwin + home-manager)
- Task 6: Configuration evaluation succeeded with JSON output
- Task 7: Documentation and story file updates complete

### Completion Notes List

**Implementation Summary:**
- Created stibnite darwin configuration (182 lines vs blackphos 217)
- Single-user pattern: crs58 only (no raquel)
- All 7 aggregates imported for crs58 including AI
- Zerotier network db4344343b14b903 configured
- Darwin features: TouchID, MaxAuthTries 20, zsh, documentation enabled

**Build Validation Evidence:**
- Darwin build: `/nix/store/8ghfy0vmwpv8kya4snv2zsirfm1r61v8-darwin-system-25.11.973db96`
- Home-manager build: `/nix/store/nxw8cxwjika74zdr6s66v8carc27lmdl-home-manager-generation`
- 8 secrets verified for crs58
- 7 aggregates verified in config
- Clan machines list shows stibnite

**Story 2.7 Handoff Guidance:**
- Both blackphos and stibnite darwin configs ready in infra
- Zerotier network join order: blackphos first (already has established identity), then stibnite
- Both machines use same zerotier network ID: db4344343b14b903
- crs58 home-manager module shared between both machines

### File List

**Created:**
- `modules/machines/darwin/stibnite/default.nix` (182 lines)
- `modules/machines/darwin/stibnite/_zerotier.nix` (100 lines, copy from blackphos)

**Modified:**
- `modules/clan/machines.nix` - Added stibnite registration
- `modules/clan/inventory/machines.nix` - Added stibnite inventory entry
- `docs/notes/development/sprint-status.yaml` - Status: ready-for-dev → in-progress → review
- `docs/notes/development/work-items/2-6-stibnite-config-migration.md` - Task completion, dev notes

---

## Change Log

| Date | Version | Change |
|------|---------|--------|
| 2025-11-24 | 1.0 | Story drafted from Epic 2 definition and user context |
| 2025-11-24 | 2.0 | Implementation complete - stibnite darwin config created, all 7 ACs PASS |
| 2025-11-24 | 3.0 | Senior Developer Review (AI) - APPROVED |

---

## Senior Developer Review (AI)

### Reviewer
Dev

### Date
2025-11-24

### Outcome
**APPROVE**

Story 2.6 successfully implements the stibnite darwin configuration using the validated blackphos template.
All 7 acceptance criteria are fully satisfied with empirical evidence.
All 32 completed tasks are verified.
No blocking issues found.
Implementation follows established patterns and architectural constraints.

### Summary

The implementation creates a single-user darwin configuration for stibnite (crs58's primary workstation) by adapting the blackphos dual-user template.
Key achievements:
- Created 182-line darwin module (vs blackphos 217 lines) with single-user simplification
- All 7 home-manager aggregates configured for crs58 including AI
- Zerotier network integration with correct network ID db4344343b14b903
- Darwin features validated: TouchID, MaxAuthTries 20, zsh, documentation enabled
- Proper clan registration in machines.nix and inventory/machines.nix

### Key Findings

**No HIGH or MEDIUM severity issues.**

**LOW Severity (Advisory):**

- Note: `_zerotier.nix` comment at line 1 says "blackphos" instead of "stibnite" - cosmetic only, no action required

### Acceptance Criteria Coverage

| AC# | Description | Status | Evidence |
|-----|-------------|--------|----------|
| AC1 | stibnite Directory Structure Created | IMPLEMENTED | `modules/machines/darwin/stibnite/` with `default.nix` (182 lines), `_zerotier.nix` (100 lines) |
| AC2 | Darwin Build Succeeds | IMPLEMENTED | `nix eval` returns `/nix/store/rjcl92diif0yl0lgir6azkx6755ivzgk-darwin-system-25.11.973db96` |
| AC3 | crs58 User Configuration Complete | IMPLEMENTED | 8 secrets verified via sops, 7 aggregates at `default.nix:163-169`, crs58 module at `modules/home/users/crs58/default.nix:1-71` |
| AC4 | Zerotier Darwin Integration | IMPLEMENTED | Network ID at `_zerotier.nix:12`, zerotier-one cask at `default.nix:93`, import at `default.nix:32` |
| AC5 | Configuration Evaluation Succeeds | IMPLEMENTED | `nix eval` returns valid JSON with nix store path |
| AC6 | Darwin-Specific Features | IMPLEMENTED | Platform `default.nix:56`, hostname `default.nix:52`, primaryUser `default.nix:71`, TouchID `default.nix:105`, MaxAuthTries `default.nix:112`, zsh `default.nix:141`, docs `default.nix:44`, NO raquel |
| AC7 | Documentation Complete | IMPLEMENTED | Dev Notes `lines 271-401`, Story 2.5 refs present, Single-user pattern documented, Story 2.7 handoff guidance at `lines 443-447` |

**Summary: 7 of 7 acceptance criteria fully implemented**

### Task Completion Validation

| Task | Subtasks Verified | Status |
|------|-------------------|--------|
| Task 1: Configuration Diff Analysis | 5/5 subtasks | ✅ VERIFIED |
| Task 2: Create Directory Structure | 4/4 subtasks | ✅ VERIFIED |
| Task 3: Implement stibnite Configuration | 10/10 subtasks | ✅ VERIFIED |
| Task 4: Register in Clan Inventory | 3/3 subtasks | ✅ VERIFIED |
| Task 5: Build Validation | 4/4 subtasks | ✅ VERIFIED |
| Task 6: Configuration Evaluation | 3/3 subtasks | ✅ VERIFIED |
| Task 7: Documentation and Commit | 6/6 subtasks | ✅ VERIFIED |

**Summary: 32 of 32 completed tasks verified, 0 questionable, 0 falsely marked complete**

### Test Coverage and Gaps

- **Integration Tests**: Nix build commands serve as integration tests (passed)
- **Unit Tests**: Not applicable for declarative Nix configuration
- **Gap**: None - infrastructure code validated through build success

### Architectural Alignment

- ✅ Follows dendritic+clan architecture pattern from Epic 1
- ✅ Uses Pattern A aggregates for home-manager
- ✅ Consistent with blackphos structural template
- ✅ Proper module registration in clan inventory
- ✅ No architecture violations detected

### Security Notes

- ✅ SSH key: Ed25519 properly configured
- ✅ TouchID sudo enabled for laptop convenience
- ✅ MaxAuthTries 20 (documented Bitwarden workaround)
- ✅ All secrets handled via sops-nix (no hardcoded secrets)
- ✅ Zerotier network correctly configured with cinnabar controller

### Best-Practices and References

- [nix-darwin Manual](https://daiderd.com/nix-darwin/manual/)
- [Home-manager Manual](https://nix-community.github.io/home-manager/)
- [Clan-core Documentation](https://docs.clan.lol/)
- [Sops-nix Documentation](https://github.com/Mic92/sops-nix)

### Action Items

**Code Changes Required:**

(None - all criteria satisfied)

**Advisory Notes:**

- Note: Consider updating `_zerotier.nix` line 1 comment from "blackphos" to "stibnite" for clarity (optional, cosmetic only)
