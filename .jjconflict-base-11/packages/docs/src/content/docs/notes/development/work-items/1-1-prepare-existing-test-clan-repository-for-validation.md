
---
title: "Story 1.1: Prepare existing test-clan repository for validation"
---

Status: ready-for-dev

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

- [ ] Review existing test-clan repository state (AC: #1)
  - [ ] Navigate to ~/projects/nix-workspace/test-clan/
  - [ ] Check git status and current branch
  - [ ] Review existing flake.nix structure
  - [ ] Identify existing modules/ organization
  - [ ] Document current state for baseline

- [ ] Create/confirm working branch for validation work (AC: #1)
  - [ ] Create branch: `git checkout -b phase-0-validation` or confirm on main
  - [ ] Ensure clean working state before modifications

- [ ] Update flake inputs for dendritic + clan + infrastructure integration (AC: #2)
  - [ ] Add clan-core input: `git+https://git.clan.lol/clan/clan-core` following nixpkgs/flake-parts
  - [ ] Add import-tree input: `github:vic/import-tree`
  - [ ] Add terranix input: `github:terranix/terranix` following flake-parts/nixpkgs
  - [ ] Add disko input: `github:nix-community/disko` following nixpkgs
  - [ ] Add srvos input: `github:nix-community/srvos` following nixpkgs
  - [ ] Configure input follows for clan-core: nixpkgs, flake-parts, sops-nix, home-manager, nix-darwin
  - [ ] Configure input follows for terranix: flake-parts, nixpkgs
  - [ ] Verify flake.lock updates after input changes

- [ ] Configure flake-parts.lib.mkFlake structure (AC: #2)
  - [ ] Update flake.nix outputs to use `flake-parts.lib.mkFlake { inherit inputs; }`
  - [ ] Add import-tree auto-discovery: `(inputs.import-tree ./modules)`
  - [ ] Verify flake structure follows dendritic pattern

- [ ] Import clan-core and terranix flakeModules (AC: #3)
  - [ ] Add `inputs.clan-core.flakeModules.default` to imports list
  - [ ] Add `inputs.terranix.flakeModule` to imports list (following clan-infra pattern)
  - [ ] Verify both flakeModules load without conflicts
  - [ ] Reference clan-infra pattern: ~/projects/nix-workspace/infra/packages/docs/src/content/docs/notes/implementation/clan-infra-terranix-pattern.md

- [ ] Create/verify modules/ directory structure for infrastructure (AC: #4)
  - [ ] Create modules/base/ for foundation modules (nix settings)
  - [ ] Create modules/hosts/ for machine-specific configurations
  - [ ] Create modules/flake-parts/ for flake-level configuration
  - [ ] Create modules/terranix/ for terraform/terranix modules (following clan-infra pattern)
  - [ ] Verify directory structure supports infrastructure deployment
  - [ ] Note: Dendritic pattern optional at this stage (Story 1.2 can be skipped)

- [ ] Test flake evaluation (AC: #5)
  - [ ] Run: `nix flake check`
  - [ ] Fix any evaluation errors discovered
  - [ ] Run: `nix flake show` to verify outputs structure
  - [ ] Verify no warnings or critical issues

- [ ] Update README.md with Phase 0 validation + infrastructure documentation (AC: #6)
  - [ ] Document purpose: Phase 0 architectural validation + infrastructure deployment environment
  - [ ] Document scope: Testing clan + infrastructure using clan-infra's proven terranix pattern, dendritic optimization secondary
  - [ ] Document strategy: Infrastructure-first (follow clan-infra patterns), dendritic optional/later
  - [ ] Document structure: Module organization, flake inputs, terraform/terranix setup, intended outcomes
  - [ ] Note disposable nature: Experimental repository for validation, can destroy infrastructure via terraform destroy
  - [ ] Reference integration-plan.md and clan-infra-terranix-pattern.md for patterns

- [ ] Verify clean git state (AC: #7)
  - [ ] Stage changes: `git add .`
  - [ ] Commit with atomic message: "chore(phase-0): prepare test-clan for clan + infrastructure validation"
  - [ ] Verify working tree clean: `git status`
  - [ ] Ready for next story (Story 1.2 dendritic pattern OPTIONAL, or skip to Story 1.4 terraform setup)

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

<!-- Agent model will be recorded during implementation -->

### Debug Log References

<!-- Debug logs will be added during implementation -->

### Completion Notes List

<!-- Implementation notes will be added here as work progresses -->

### File List

<!-- Files created/modified will be tracked here during implementation -->
