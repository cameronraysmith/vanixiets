
---
title: "Story 1.1: Prepare existing test-clan repository for validation"
---

Status: review

## Story

As a system administrator,
I want to review and prepare the existing test-clan repository for nix dendritic flake-parts + clan + terraform/terranix infrastructure validation, so that I can validate both the architectural patterns and infrastructure provisioning before production deployment.

## Context

The test-clan repository already exists at `~/projects/nix-workspace/test-clan/` as a fledgling repository.
Story 1.1 reviews and prepares it for dendritic flake-parts + clan-core + terraform/terranix infrastructure integration validation.
This is the entry point to the entire migration - if this foundation isn't solid, everything built on it will be unstable.

**Phase 0 Strategic Purpose**: Validate an untested architectural combination (dendritic flake-parts + clan) AND deploy real infrastructure (Hetzner + GCP VMs) using clan-infra's proven terranix pattern in a disposable test environment before committing to production nix-config.
De-risks the entire migration by proving both patterns AND infrastructure provisioning work in isolation.

**Infrastructure-First Strategy**: Following clan-infra's proven terranix + flake-parts pattern (non-dendritic) is the primary objective.
Dendritic optimization is secondary and can be added later via refactoring AFTER infrastructure works.

**Non-Standard Sequencing**: This project deliberately defers architecture workflow until after Phase 0.
Phase 0 (Epic 1) IS the architectural validation - it produces the patterns and decisions that normally come from architecture workflow.

## Acceptance Criteria

1. Existing test-clan repository at ~/projects/nix-workspace/test-clan/ reviewed and working branch created/confirmed
2. flake.nix updated to use flake-parts.lib.mkFlake with required inputs: nixpkgs, flake-parts, clan-core, import-tree, terranix, disko, srvos
3. Clan-core flakeModules.default and terranix.flakeModule imported
4. modules/ directory structure verified/created: modules/base/, modules/hosts/, modules/flake-parts/, modules/terranix/
5. Flake evaluates without errors: `nix flake check`
6. README.md updated to document Phase 0 validation + infrastructure deployment purpose and scope
7. Git working state clean and ready for iterative development (Story 1.2 or Story 1.4 depending on dendritic decision)

## Tasks / Subtasks

- [x] Review existing test-clan repository state (AC: #1)
  - [x] Navigate to ~/projects/nix-workspace/test-clan/
  - [x] Check git status and current branch
  - [x] Review existing flake.nix structure
  - [x] Identify existing modules/ organization
  - [x] Document current state for baseline

- [x] Create/confirm working branch for validation work (AC: #1)
  - [x] Create branch: `git checkout -b phase-0-validation` or confirm on main
  - [x] Ensure clean working state before modifications

- [x] Update flake inputs for dendritic + clan + infrastructure integration (AC: #2)
  - [x] Add clan-core input: `git+https://git.clan.lol/clan/clan-core` following nixpkgs/flake-parts
  - [x] Add import-tree input: `github:vic/import-tree`
  - [x] Add terranix input: `github:terranix/terranix` following flake-parts/nixpkgs
  - [x] Add disko input: `github:nix-community/disko` following nixpkgs
  - [x] Add srvos input: `github:nix-community/srvos` following nixpkgs
  - [x] Configure input follows for clan-core: nixpkgs, flake-parts
  - [x] Configure input follows for terranix: flake-parts, nixpkgs
  - [x] Verify flake.lock updates after input changes

- [x] Configure flake-parts.lib.mkFlake structure (AC: #2)
  - [x] Update flake.nix outputs to use `flake-parts.lib.mkFlake { inherit inputs; }`
  - [x] Import-tree available for future use (dendritic pattern in Story 1.2)
  - [x] Verify flake structure evaluates correctly

- [x] Import clan-core and terranix flakeModules (AC: #3)
  - [x] Add `inputs.clan-core.flakeModules.default` to imports list
  - [x] Add `inputs.terranix.flakeModule` to imports list (following clan-infra pattern)
  - [x] Verify both flakeModules load without conflicts
  - [x] Reference clan-infra pattern: ~/projects/nix-workspace/infra/docs/notes/implementation/clan-infra-terranix-pattern.md

- [x] Create/verify modules/ directory structure for infrastructure (AC: #4)
  - [x] Create modules/base/ for foundation modules (nix settings)
  - [x] Create modules/hosts/ for machine-specific configurations
  - [x] Create modules/flake-parts/ for flake-level configuration
  - [x] Create modules/terranix/ for terraform/terranix modules (following clan-infra pattern)
  - [x] Verify directory structure supports infrastructure deployment
  - [x] Note: Dendritic pattern optional at this stage (Story 1.2 can be skipped)

- [x] Test flake evaluation (AC: #5)
  - [x] Run: `nix flake check --all-systems` (PASSED)
  - [x] Fix any evaluation errors discovered
  - [x] Run: `nix flake show` to verify outputs structure
  - [x] Verify clan CLI works in dev shell

- [x] Update README.md with Phase 0 validation + infrastructure documentation (AC: #6)
  - [x] Document purpose: Phase 0 architectural validation + infrastructure deployment environment
  - [x] Document scope: Testing clan + infrastructure using clan-infra's proven terranix pattern, dendritic optimization secondary
  - [x] Document strategy: Infrastructure-first (follow clan-infra patterns), dendritic optional/later
  - [x] Document structure: Module organization, flake inputs, terraform/terranix setup, intended outcomes
  - [x] Note disposable nature: Experimental repository for validation, can destroy infrastructure via terraform destroy
  - [x] Reference integration-plan.md and clan-infra-terranix-pattern.md for patterns

- [x] Verify clean git state (AC: #7)
  - [x] Created atomic commits for each logical change
  - [x] Verify working tree clean: `git status` (CLEAN)
  - [x] Ready for next story (Story 1.2 dendritic pattern OPTIONAL, or skip to Story 1.4 terraform setup)

## Dev Notes

### Project Structure Notes

**Test-clan location**: `~/projects/nix-workspace/test-clan/` (experimental repository, separate from production nix-config)

**Dendritic flake-parts pattern target structure**:
```
test-clan/
├── flake.nix                    # Simplified with import-tree auto-discovery
├── modules/
│   ├── base/                    # Foundation modules (nix settings, state version)
│   ├── hosts/                   # Machine-specific configurations (test-vm/)
│   └── flake-parts/             # Flake-level configuration (clan.nix, nixpkgs.nix)
└── README.md                    # Phase 0 validation purpose and scope
```

**Critical integration point**: This story sets up the skeleton for dendritic flake-parts pattern + clan integration.
Story 1.2 will implement the actual dendritic flake-parts pattern, and Stories 1.3-1.4 will add clan functionality.

### Solo Operator Workflow

This story prepares the workspace for validation work.
Expected execution time: 1-2 hours.
All validation commands should be run locally - no CI required for Phase 0.

### Architectural Context

**Validation-first strategy**: Phase 0 validates dendritic + clan integration in minimal test environment before production infrastructure commitment.
No production infrastructure is touched during Phase 0 - test-clan is experimental and disposable.

**Known foundation, unknown optimization**:
- Clan works with flake-parts (proven in clan-core, clan-infra)
- The Dendritic pattern is built on flake-parts (proven in dendritic-flake-parts, drupol-dendritic-infra) and increases type-safety analogous to the nixos module system but with nix flakes attempting to enforce the constraint that each nix file is a valid nix flake-parts module.
- **Unknown**: How much of the dendritic flake-parts pattern is compatible with clan? What compromises, if any, are necessary?

**Acceptable outcomes**:
- Full dendritic flake-parts pattern adoption in a clan-managed infrastructure repo (best case)
- Hybrid approach with documented compromises (pragmatic)
- Vanilla clan pattern (proven alternative, we're trying to ultimately adopt clan, but since it already supports flake-parts see if we can go slightly beyond and support respecting the dendritic flake-parts architecture pattern where every nix file is a flake-parts module)

All three outcomes are valid - Phase 0's goal is to determine which is optimal, not to force pure dendritic adoption.

### References

- [Source: docs/notes/development/epics.md#Story-1.1]
- [Source: docs/notes/development/PRD.md#FR-1-Architectural-Integration]
- [Source: docs/notes/clan/integration-plan.md#Phase-0-validation-rationale]
- [Source: docs/notes/clan/integration-plan.md#Directory-structure-target-state]
- [Source: docs/notes/clan/migration-assessment.md#test-clan-Phase-0-validation-environment]

### Expected Validation Points

After this story completes:
- Flake structure should evaluate cleanly
- Module organization should be in place for the dendritic flake-parts pattern
- Clan-core should be imported and available
- Repository should be ready for Story 1.2 (implement dendritic pattern)

**What Story 1.1 does NOT validate**:
- Actual dendritic flake-parts module implementation (Story 1.2)
- Clan inventory and service instances (Story 1.3)
- Clan vars generation (Story 1.4)
- Integration findings and patterns (Stories 1.5-1.6)

This story is pure setup - validation of the integration happens in subsequent stories.

### Important Constraints

**Zero-regression mandate does NOT apply to test-clan**: This is experimental.
Regression here is expected and informative.
The zero-regression mandate applies to production hosts (Phases 1-6), not Phase 0 validation.

**Solo project considerations**:
- No team coordination required
- All work sequential
- No stability gates for test-clan itself (stability gates apply between phases)
- Validation findings documented for future reference

## Dev Agent Record

### Context Reference

- docs/notes/development/work-items/1-1-prepare-existing-test-clan-repository-for-validation.context.xml

### Agent Model Used

Claude Sonnet 4.5 (claude-sonnet-4-5-20250929) via BMAD dev-story workflow

### Debug Log References

**Task 1: Review existing test-clan repository state**
- Repository location: ~/projects/nix-workspace/test-clan
- Current branch: main (2 commits ahead of origin)
- Working tree: clean
- Existing flake structure: vanilla clan pattern using clan-core.lib.clan wrapper
- Inputs: clan-core (main), nixpkgs (follows clan-core)
- Modules: modules/gnome.nix only
- Clan config: clan.nix with basic inventory (admin, zerotier, tor services)
- Need to migrate: flake-parts.lib.mkFlake + import-tree + terranix integration

### Completion Notes List

**Story 1.1 completed successfully** - test-clan repository prepared for Phase 0 validation

**Implementation approach**:
- Migrated from vanilla clan pattern to flake-parts.lib.mkFlake structure
- Followed clan-infra's proven terranix + flake-parts pattern exactly
- Infrastructure-first strategy: terranix integration is primary, dendritic pattern is optional
- Created modular directory structure supporting both clan and terraform/terranix

**Key decisions**:
- Imported terranix.flakeModule in modules/flake-parts/clan.nix (following clan-infra pattern)
- Configured all input follows to prevent version conflicts
- Created placeholder structures for terranix modules (to be implemented in Story 1.4)
- Removed deprecated root-level clan.nix to avoid services→instances migration issues

**Validation results**:
- `nix flake check --all-systems`: PASSED (all 4 systems)
- `nix flake show`: Outputs structure correct (devShells, clan, clanInternals)
- `nix develop -c clan --help`: Clan CLI working in dev shell
- Git working tree: CLEAN (5 atomic commits on phase-0-validation branch)

**Next steps recommendation**: SKIP Story 1.2 (dendritic pattern) and proceed to Story 1.3 (clan inventory), then Story 1.4 (Hetzner terraform config).
Reasoning: Infrastructure deployment is primary objective, dendritic pattern can be refactored later if desired after infrastructure works. Story 1.3 is a required prerequisite for Story 1.4 (terraform needs inventory).

### File List

**Modified**:
- `flake.nix` - Migrated to flake-parts.lib.mkFlake with clan-core + terranix integration
- `flake.lock` - Updated with infrastructure inputs (disko, srvos, terranix, flake-parts, import-tree)

**Created**:
- `modules/flake-parts/clan.nix` - Clan configuration with terranix.flakeModule import
- `modules/flake-parts/nixpkgs.nix` - Nixpkgs configuration for all systems
- `modules/base/nix-settings.nix` - Base nix settings for all machines
- `modules/hosts/.gitkeep` - Placeholder for machine-specific configurations
- `modules/terranix/.gitkeep` - Placeholder for terraform modules (Story 1.4)
- `README.md` - Comprehensive Phase 0 validation documentation

**Deleted**:
- `clan.nix` - Removed deprecated root-level file (content moved to modules/flake-parts/clan.nix)

**Git commits** (5 atomic commits on phase-0-validation branch):
1. 32613b7 - feat: migrate to flake-parts.lib.mkFlake with clan-core integration
2. fcf94a0 - chore: update flake.lock with infrastructure inputs
3. db4f019 - feat: create modules directory structure for infrastructure
4. 576c489 - refactor: remove deprecated clan.nix from root
5. 14c120b - docs: create comprehensive README for Phase 0 validation
