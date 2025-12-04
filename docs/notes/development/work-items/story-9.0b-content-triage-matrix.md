# Story 9.0b Content Triage Matrix

Created: 2025-12-03
Decision Bias: DELETE by default (ephemeral migration artifacts)

## Decision Summary

- **RETAIN:** 1 file (`cluster/nix-kubernetes-product-brief-references.md`)
- **DEFER-DELETE:** 162 files (all others)
- **MIGRATE:** 0 files (nothing meets migration bar)

## RETAIN (1 file)

| File | Rationale |
|------|-----------|
| `cluster/nix-kubernetes-product-brief-references.md` | Next phase planning (only exception) |

## DEFER-DELETE by Directory

### Root Level (25 files)

| File | Rationale |
|------|-----------|
| `backlog.md` | Ephemeral sprint planning |
| `bmm-product-brief-infra-2025-11-02.md` | Historical product brief, superseded |
| `bmm-workflow-status.yaml` | Sprint tracking artifact |
| `ci-caching-implementation.md` | Ephemeral implementation notes |
| `ci-optimization-handoff.md` | Ephemeral handoff notes |
| `clan-flake-parts-integration.md` | Ephemeral integration notes |
| `clan-quick-reference.md` | Ephemeral reference, superseded by Starlight |
| `dendritic-flake-parts-assessment.md` | Ephemeral assessment, decisions executed |
| `dendritic-refactor-test-strategy.md` | Ephemeral test strategy |
| `docs-review-report-20251029.md` | Historical review report |
| `epic-1-infrastructure-restructure-proposal.md` | Ephemeral proposal, superseded |
| `go-no-go-decision.md` | Ephemeral decision record |
| `home-manager-type-safe-architecture.md` | Ephemeral architecture notes |
| `implementation-readiness-report-2025-11-03.md` | Historical readiness report |
| `nvidia-module-analysis.md` | Ephemeral Epic 7 research (scheelite) |
| `path-filtering-research.md` | Ephemeral research |
| `sprint-change-proposal-2025-11-05.md` | Ephemeral sprint proposal |
| `sprint-change-proposal-2025-11-11.md` | Ephemeral sprint proposal |
| `sprint-change-proposal-2025-11-20.md` | Ephemeral sprint proposal |
| `sprint-change-proposal-2025-11-30.md` | Ephemeral sprint proposal |
| `sprint-status.yaml` | Sprint tracking artifact |
| `test-clan-test-case-enumeration.md` | Ephemeral test enumeration |
| `test-clan-validated-architecture.md` | Ephemeral validation notes |
| `testing.md` | Ephemeral testing notes |
| `validation-report-2025-11-12-correct-course-1-8a.md` | Historical validation report |

### PRD/ (12 files)

| File | Rationale |
|------|-----------|
| `PRD/executive-summary.md` | Requirements captured in Starlight |
| `PRD/functional-requirements.md` | Requirements captured in Starlight |
| `PRD/implementation-planning.md` | Requirements captured in Starlight |
| `PRD/index.md` | Requirements captured in Starlight |
| `PRD/infrastructure-configuration-management-specific-requirements.md` | Requirements captured in Starlight |
| `PRD/innovation-novel-patterns.md` | Requirements captured in Starlight |
| `PRD/next-steps.md` | Requirements captured in Starlight |
| `PRD/non-functional-requirements.md` | Requirements captured in Starlight |
| `PRD/product-scope.md` | Requirements captured in Starlight |
| `PRD/project-classification.md` | Requirements captured in Starlight |
| `PRD/references.md` | Requirements captured in Starlight |
| `PRD/success-criteria.md` | Requirements captured in Starlight |

### architecture/ (18 files)

| File | Rationale |
|------|-----------|
| `architecture/api-contracts.md` | Architecture in Starlight ADRs |
| `architecture/architectural-decisions.md` | Architecture in Starlight ADRs |
| `architecture/architecture-decision-records-adrs.md` | Architecture in Starlight ADRs |
| `architecture/darwin-networking-options.md` | Architecture in Starlight ADRs |
| `architecture/data-architecture.md` | Architecture in Starlight ADRs |
| `architecture/decision-summary.md` | Architecture in Starlight ADRs |
| `architecture/deployment-architecture.md` | Architecture in Starlight ADRs |
| `architecture/development-environment.md` | Architecture in Starlight ADRs |
| `architecture/epic-to-architecture-mapping.md` | Architecture in Starlight ADRs |
| `architecture/executive-summary.md` | Architecture in Starlight ADRs |
| `architecture/implementation-patterns.md` | Architecture in Starlight ADRs |
| `architecture/index.md` | Architecture in Starlight ADRs |
| `architecture/novel-pattern-designs.md` | Architecture in Starlight ADRs |
| `architecture/performance-considerations.md` | Architecture in Starlight ADRs |
| `architecture/project-initialization.md` | Architecture in Starlight ADRs |
| `architecture/project-structure.md` | Architecture in Starlight ADRs |
| `architecture/security-architecture.md` | Architecture in Starlight ADRs |
| `architecture/technology-stack-details.md` | Architecture in Starlight ADRs |

### archived-overlays/ (4 files)

| File | Rationale |
|------|-----------|
| `archived-overlays/README.md` | Historical overlay archive |
| `archived-overlays/packages/atuin-format/atuin-format.nu` | Historical overlay archive |
| `archived-overlays/packages/atuin-format/package.nix` | Historical overlay archive |
| `archived-overlays/packages/starship-jj.nix` | Historical overlay archive |

### decisions/ (1 file)

| File | Rationale |
|------|-----------|
| `decisions/2025-11-03-defer-dendritic-pattern.md` | Historical decision, superseded by ADRs |

### epics/ (14 files)

| File | Rationale |
|------|-----------|
| `epics/epic-1-architectural-validation-migration-pattern-rehearsal-phase-0.md` | Sprint tracking artifact |
| `epics/epic-2-infrastructure-architecture-migration.md` | Sprint tracking artifact |
| `epics/epic-3-first-darwin-migration-phase-2-blackphos.md` | Sprint tracking artifact |
| `epics/epic-3-multi-darwin-validation-phase-2-rosegold.md` | Sprint tracking artifact |
| `epics/epic-4-third-darwin-host-phase-3-argentum.md` | Sprint tracking artifact |
| `epics/epic-5-primary-workstation-validation-phase-4-stibnite.md` | Sprint tracking artifact |
| `epics/epic-6-legacy-cleanup-phase-5.md` | Sprint tracking artifact |
| `epics/epic-7-gcp-multi-node-infrastructure.md` | Sprint tracking artifact |
| `epics/epic-8-documentation-alignment.md` | Sprint tracking artifact |
| `epics/epic-9-branch-consolidation-and-release.md` | Sprint tracking artifact |
| `epics/index.md` | Sprint tracking artifact |
| `epics/overview.md` | Sprint tracking artifact |
| `epics/story-guidelines-reference.md` | Sprint tracking artifact |
| `epics/summary-statistics.md` | Sprint tracking artifact |

### research/ (1 file)

| File | Rationale |
|------|-----------|
| `research/documentation-coverage-analysis.md` | Served Epic 8 purpose, now obsolete |

### retrospectives/ (4 files)

| File | Rationale |
|------|-----------|
| `retrospectives/epic-1-retro-2025-11-20.md` | Lessons captured in session |
| `retrospectives/epic-2-retro-2025-11-28.md` | Lessons captured in session |
| `retrospectives/epic-7-gcp-multi-node-infrastructure.md` | Lessons captured in session |
| `retrospectives/epic-8-documentation-alignment.md` | Lessons captured in session |

### work-items/ (83 files)

| File | Rationale |
|------|-----------|
| `work-items/1-1-prepare-existing-test-clan-repository-for-validation.context.xml` | Sprint tracking artifact |
| `work-items/1-1-prepare-existing-test-clan-repository-for-validation.md` | Sprint tracking artifact |
| `work-items/1-10-complete-migrations-establish-clean-foundation.context.xml` | Sprint tracking artifact |
| `work-items/1-10-complete-migrations-establish-clean-foundation.md` | Sprint tracking artifact |
| `work-items/1-10A-migrate-user-management-inventory.context.xml` | Sprint tracking artifact |
| `work-items/1-10A-migrate-user-management-inventory.md` | Sprint tracking artifact |
| `work-items/1-10B-migrate-home-manager-modules.context.xml` | Sprint tracking artifact |
| `work-items/1-10B-migrate-home-manager-modules.md` | Sprint tracking artifact |
| `work-items/1-10BA-refactor-pattern-a.context.xml` | Sprint tracking artifact |
| `work-items/1-10BA-refactor-pattern-a.md` | Sprint tracking artifact |
| `work-items/1-10c-establish-sops-nix-secrets-home-manager.context.xml` | Sprint tracking artifact |
| `work-items/1-10c-establish-sops-nix-secrets-home-manager.md` | Sprint tracking artifact |
| `work-items/1-10d-validate-custom-package-overlays.context.xml` | Sprint tracking artifact |
| `work-items/1-10d-validate-custom-package-overlays.md` | Sprint tracking artifact |
| `work-items/1-10da-validate-overlay-preservation.context.xml` | Sprint tracking artifact |
| `work-items/1-10da-validate-overlay-preservation.md` | Sprint tracking artifact |
| `work-items/1-10db-execute-overlay-architecture-migration.context.xml` | Sprint tracking artifact |
| `work-items/1-10db-execute-overlay-architecture-migration.md` | Sprint tracking artifact |
| `work-items/1-10e-enable-remaining-features.context.xml` | Sprint tracking artifact |
| `work-items/1-10e-enable-remaining-features.md` | Sprint tracking artifact |
| `work-items/1-12-deploy-blackphos-zerotier-integration.context.xml` | Sprint tracking artifact |
| `work-items/1-12-deploy-blackphos-zerotier-integration.md` | Sprint tracking artifact |
| `work-items/1-14-execute-go-no-go-decision.context.xml` | Sprint tracking artifact |
| `work-items/1-14-execute-go-no-go-decision.md` | Sprint tracking artifact |
| `work-items/1-2-implement-dendritic-flake-parts-pattern-in-test-clan.context.xml` | Sprint tracking artifact |
| `work-items/1-2-implement-dendritic-flake-parts-pattern-in-test-clan.md` | Sprint tracking artifact |
| `work-items/1-3-configure-clan-inventory-and-service-instances-for-test-vm.context.xml` | Sprint tracking artifact |
| `work-items/1-3-configure-clan-inventory-and-service-instances-for-test-vm.md` | Sprint tracking artifact |
| `work-items/1-4-create-hetzner-terraform-config-and-host-modules.context.xml` | Sprint tracking artifact |
| `work-items/1-4-create-hetzner-terraform-config-and-host-modules.md` | Sprint tracking artifact |
| `work-items/1-5-deploy-hetzner-vm-and-validate-stack.context.xml` | Sprint tracking artifact |
| `work-items/1-5-deploy-hetzner-vm-and-validate-stack.md` | Sprint tracking artifact |
| `work-items/1-6-implement-comprehensive-test-harness-for-test-clan.context.xml` | Sprint tracking artifact |
| `work-items/1-6-implement-comprehensive-test-harness-for-test-clan.md` | Sprint tracking artifact |
| `work-items/1-7-execute-dendritic-refactoring-in-test-clan-using-test-harness.context.xml` | Sprint tracking artifact |
| `work-items/1-7-execute-dendritic-refactoring-in-test-clan-using-test-harness.md` | Sprint tracking artifact |
| `work-items/1-8-migrate-blackphos-from-infra-to-test-clan.context.xml` | Sprint tracking artifact |
| `work-items/1-8-migrate-blackphos-from-infra-to-test-clan.md` | Sprint tracking artifact |
| `work-items/1-8a-extract-portable-home-manager-modules.context.xml` | Sprint tracking artifact |
| `work-items/1-8a-extract-portable-home-manager-modules.md` | Sprint tracking artifact |
| `work-items/1-9-rename-vms-cinnabar-electrum-establish-zerotier.context.xml` | Sprint tracking artifact |
| `work-items/1-9-rename-vms-cinnabar-electrum-establish-zerotier.md` | Sprint tracking artifact |
| `work-items/2-1-identify-infra-specific-components-to-preserve.context.xml` | Sprint tracking artifact |
| `work-items/2-1-identify-infra-specific-components-to-preserve.md` | Sprint tracking artifact |
| `work-items/2-10-electrum-config-migration.md` | Sprint tracking artifact |
| `work-items/2-11-test-harness-and-ci-validation.md` | Sprint tracking artifact |
| `work-items/2-13-rosegold-configuration-creation.md` | Sprint tracking artifact |
| `work-items/2-14-argentum-configuration-creation.md` | Sprint tracking artifact |
| `work-items/2-2-prepare-clan-01-branch.context.xml` | Sprint tracking artifact |
| `work-items/2-2-prepare-clan-01-branch.md` | Sprint tracking artifact |
| `work-items/2-3-wholesale-migration-test-clan-to-infra.context.xml` | Sprint tracking artifact |
| `work-items/2-3-wholesale-migration-test-clan-to-infra.md` | Sprint tracking artifact |
| `work-items/2-4-home-manager-secrets-migration.context.xml` | Sprint tracking artifact |
| `work-items/2-4-home-manager-secrets-migration.md` | Sprint tracking artifact |
| `work-items/2-5-blackphos-config-migration-to-infra.context.xml` | Sprint tracking artifact |
| `work-items/2-5-blackphos-config-migration-to-infra.md` | Sprint tracking artifact |
| `work-items/2-6-stibnite-config-migration.context.xml` | Sprint tracking artifact |
| `work-items/2-6-stibnite-config-migration.md` | Sprint tracking artifact |
| `work-items/2-7-activate-blackphos-and-stibnite-from-infra.md` | Sprint tracking artifact |
| `work-items/2-9-cinnabar-config-migration.md` | Sprint tracking artifact |
| `work-items/7-1-terranix-gcp-provider-base-config.md` | Sprint tracking artifact |
| `work-items/7-2-cpu-only-togglable-node-definition-deployment.md` | Sprint tracking artifact |
| `work-items/7-3-clan-integration-zerotier-mesh-gcp-nodes.md` | Sprint tracking artifact |
| `work-items/7-4-gpu-capable-togglable-node-definition-deployment.md` | Sprint tracking artifact |
| `work-items/8-1-audit-existing-starlight-docs-for-staleness.md` | Sprint tracking artifact |
| `work-items/8-10-audit-test-harness-ci-documentation.md` | Sprint tracking artifact |
| `work-items/8-11-remediate-amdire-development-documentation-staleness.md` | Sprint tracking artifact |
| `work-items/8-12-create-foundational-architecture-decision-records.md` | Sprint tracking artifact |
| `work-items/8-2-update-architecture-and-patterns-documentation.md` | Sprint tracking artifact |
| `work-items/8-3-update-host-onboarding-guides-darwin-vs-nixos.md` | Sprint tracking artifact |
| `work-items/8-4-update-secrets-management-documentation.md` | Sprint tracking artifact |
| `work-items/8-5-audit-documentation-structure-against-diataxis-amdire-frameworks.md` | Sprint tracking artifact |
| `work-items/8-6-rationalize-and-document-cli-tooling.md` | Sprint tracking artifact |
| `work-items/8-7-audit-amdire-development-documentation-alignment.md` | Sprint tracking artifact |
| `work-items/8-8-create-tutorials-for-common-user-workflows.md` | Sprint tracking artifact |
| `work-items/8-9-validate-cross-references-and-navigation-discoverability.md` | Sprint tracking artifact |
| `work-items/9-0a-update-stale-migration-guides.md` | Sprint tracking artifact |
| `work-items/9-0b-clean-up-migration-artifacts.md` | Sprint tracking artifact (self-reference) |
| `work-items/story-2-1-preservation-checklist.md` | Sprint tracking artifact |
| `work-items/story-8.1-audit-results.md` | Sprint tracking artifact |
| `work-items/story-8.5-structure-audit-results.md` | Sprint tracking artifact |
| `work-items/story-8.7-amdire-audit-results.md` | Sprint tracking artifact |
| `work-items/validation-report-2025-11-20-130959.md` | Sprint tracking artifact |

## Deletion Manifest for Story 9.3

**Total files to delete:** 162

**Total directories that will be empty after deletion:**
- `docs/notes/development/PRD/`
- `docs/notes/development/architecture/`
- `docs/notes/development/archived-overlays/` (including subdirectories)
- `docs/notes/development/decisions/`
- `docs/notes/development/epics/`
- `docs/notes/development/research/`
- `docs/notes/development/retrospectives/`
- `docs/notes/development/work-items/`
- `docs/notes/development/` (root - only `cluster/` subdirectory retained)

**Directory retained:** `docs/notes/development/cluster/` (contains 1 RETAIN file)

### Story 9.3 Deletion Commands

```bash
# Delete all files except the single RETAIN exception
fd -t f . docs/notes/development/ \
  --exclude 'cluster/nix-kubernetes-product-brief-references.md' \
  -x rm {}

# Clean up empty directories (preserve cluster/)
fd -t d -e . docs/notes/development/ \
  --exclude cluster \
  -x rmdir {} 2>/dev/null

# Alternative: explicit directory removal
rm -rf docs/notes/development/PRD
rm -rf docs/notes/development/architecture
rm -rf docs/notes/development/archived-overlays
rm -rf docs/notes/development/decisions
rm -rf docs/notes/development/epics
rm -rf docs/notes/development/research
rm -rf docs/notes/development/retrospectives
rm -rf docs/notes/development/work-items
# Remove root-level files individually (25 files)
```

## Inventory Summary

| Directory | File Count | Decision |
|-----------|------------|----------|
| Root level | 25 | DEFER-DELETE |
| PRD/ | 12 | DEFER-DELETE |
| architecture/ | 18 | DEFER-DELETE |
| archived-overlays/ | 4 | DEFER-DELETE |
| cluster/ | 1 | **RETAIN** |
| decisions/ | 1 | DEFER-DELETE |
| epics/ | 14 | DEFER-DELETE |
| research/ | 1 | DEFER-DELETE |
| retrospectives/ | 4 | DEFER-DELETE |
| work-items/ | 83 | DEFER-DELETE |
| **Total** | **163** | 1 RETAIN, 162 DEFER-DELETE |

## Acceptance Criteria Verification

- [x] AC-1: Content triage matrix documents ALL 163 files with decisions
- [x] AC-2: NVIDIA docs (`nvidia-module-analysis.md`) marked DEFER-DELETE with rationale (Ephemeral Epic 7 research)
- [x] AC-3: Retrospectives (all 4) marked DEFER-DELETE
- [x] AC-4: Single RETAIN exception documented (`cluster/nix-kubernetes-product-brief-references.md`)
- [x] AC-5: Sprint management files listed as DEFER-DELETE for Story 9.3
- [x] AC-6: Validation confirms no files deleted (this story is triage only)
- [x] AC-7: Story 9.3 has clear deletion manifest to consume
