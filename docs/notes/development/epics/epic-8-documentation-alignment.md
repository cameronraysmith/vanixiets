# Epic 8: Documentation Alignment (Post-MVP Phase 7)

**Status:** In Progress (Phase 2)
**Dependencies:** Epic 7 complete
**Strategy:** Audit-first approach - identify staleness before updating

---

## Epic Goal

Comprehensively update all documentation to reflect the dendritic flake-parts + clan-core architecture after GCP infrastructure deployment, ensuring zero references to deprecated nixos-unified patterns.

**Key Outcomes:**
- Starlight docs site accurately reflects implemented architecture
- Architecture documentation updated with GCP infrastructure decisions
- Host onboarding guides differentiate darwin vs nixos deployment paths
- Secrets management documentation covers two-tier pattern (clan vars + sops-nix)
- Zero references to deprecated nixos-unified architecture
- Reference documentation covers CLI tooling (justfile, flake apps, CI jobs)
- AMDiRE development documentation aligned with implementation
- Tutorial content exists for common user journeys
- Cross-references validated and navigation discoverable

**Business Objective:** Documentation accuracy enables new contributors and reduces support burden.

---

## FR Coverage Map

| Story | Functional Requirements |
|-------|-------------------------|
| Story 8.1 | FR-8.1 (Starlight docs audit) |
| Story 8.2 | FR-8.2 (Architecture documentation) |
| Story 8.3 | FR-8.3 (Host onboarding guides) |
| Story 8.4 | FR-8.4 (Secrets management docs) |
| Story 8.5 | FR-8.5 (Documentation structure audit) |
| Story 8.6 | FR-8.6 (CLI tooling reference docs) |
| Story 8.7 | FR-8.7 (AMDiRE development docs audit) |
| Story 8.8 | FR-8.8 (Tutorial content creation) |
| Story 8.9 | FR-8.9 (Cross-reference validation) |
| Story 8.10 | FR-8.10 (Test harness documentation) |

---

## Story 8.1: Audit existing Starlight docs for staleness

As a documentation maintainer,
I want to audit all existing Starlight documentation for outdated content,
So that I have a prioritized list of updates before making changes.

**Acceptance Criteria:**

**Given** the Starlight docs site at `packages/docs/src/content/docs/`
**When** I audit each document for staleness
**Then** the audit should produce:
- Inventory of all .md/.mdx files in docs site
- Classification: current, stale, obsolete, missing
- Specific staleness indicators (nixos-unified references, outdated patterns)
- Priority ranking for updates (critical, high, medium, low)
- Estimated effort per document

**And** staleness criteria should include:
- References to `nixos-unified` or `configurations/` directory
- Outdated architecture diagrams
- Commands that no longer work
- Missing coverage for new patterns (dendritic, clan)
- Incorrect host references (obsolete machines)

**And** the audit output should be:
- Written to `docs/notes/development/work-items/story-8.1-audit-results.md`
- Structured as actionable checklist for Stories 8.2-8.4

**Prerequisites:** Epic 7 complete (GCP infrastructure deployed)

**Technical Notes:**
- Starlight docs location: `packages/docs/src/content/docs/`
- Search patterns: `rg "nixos-unified|configurations/|LazyVim-module" packages/docs/`
- Output format: Markdown table with columns: File, Status, Issues, Priority

**NFR Coverage:** NFR-8.1 (Zero references to deprecated architecture)

---

## Story 8.2: Update architecture and patterns documentation

As a documentation maintainer,
I want to update architecture documentation to reflect dendritic + clan patterns,
So that developers understand the current implementation approach.

**Acceptance Criteria:**

**Given** the audit results from Story 8.1
**When** I update architecture documentation
**Then** docs/notes/development/architecture/ should:
- Reflect dendritic flake-parts module organization
- Document clan-core integration patterns
- Include ADRs for GCP infrastructure decisions
- Show multi-cloud deployment architecture (Hetzner + GCP)

**And** Starlight site architecture pages should:
- Remove all nixos-unified references
- Update diagrams to show current module namespace
- Document Pattern A (dendritic aggregates) for home-manager
- Include GCP infrastructure in architecture diagrams

**And** pattern documentation should:
- Document terranix patterns (hetzner.nix, gcp.nix)
- Document clan inventory patterns
- Document service instance configuration
- Include working code examples from current implementation

**Prerequisites:** Story 8.1 (audit complete)

**Technical Notes:**
- Architecture docs: `docs/notes/development/architecture/`
- Pattern examples: Extract from `modules/` directory
- Diagrams: Update or create using mermaid/plantuml
- ADR template: Follow existing format in `architecture-decision-records-adrs.md`

**NFR Coverage:** NFR-8.2 (Testability - commands should work)

---

## Story 8.3: Update host onboarding guides (darwin vs nixos)

As a new user,
I want clear onboarding documentation for my platform type,
So that I can deploy my machine using the correct workflow.

**Acceptance Criteria:**

**Given** the two deployment paths (darwin, nixos VPS)
**When** I create/update onboarding documentation
**Then** darwin onboarding should document:
- Prerequisites: Nix installation, flake enablement
- Clone and setup: Repository clone, direnv activation
- Build validation: `nix build .#darwinConfigurations.<hostname>.system`
- Deployment: `darwin-rebuild switch --flake .#<hostname>`
- Zerotier integration: Homebrew cask installation, network join
- Secrets setup: Age key generation, sops-nix configuration

**And** nixos VPS onboarding should document:
- Prerequisites: Terraform, GCP/Hetzner credentials
- Infrastructure provisioning: `nix run .#terraform`
- Clan installation: `clan machines install <hostname> --target-host root@<ip>`
- Zerotier mesh: Automatic peer configuration via clan
- Secrets deployment: Clan vars to `/run/secrets/`

**And** common sections should:
- Explain dendritic module structure
- Document clan inventory integration
- Reference architecture documentation

**Prerequisites:** Story 8.2 (architecture docs updated)

**Technical Notes:**
- Darwin path: `darwin-rebuild switch --flake`
- NixOS path: `clan machines install`
- Onboarding docs location: `packages/docs/src/content/docs/guides/`
- Platform detection: Reference machine tags in clan inventory

**NFR Coverage:** NFR-8.3 (Darwin vs NixOS differentiation)

---

## Story 8.4: Update secrets management documentation

As a system administrator,
I want comprehensive documentation of the two-tier secrets pattern,
So that I understand how to manage generated and external secrets.

**Acceptance Criteria:**

**Given** the two-tier secrets architecture (clan vars + sops-nix)
**When** I update secrets documentation
**Then** documentation should explain:
- Tier 1 (Clan vars): Generated secrets (SSH keys, service passwords)
- Tier 2 (sops-nix): External credentials (API tokens, if hybrid approach)
- Why two tiers exist and when to use each
- Age key management for both systems

**And** operational procedures should document:
- Adding a new generated secret (clan vars)
- Adding an external credential (sops-nix)
- Rotating secrets
- Sharing secrets between machines (`share = true`)
- Debugging secrets deployment issues

**And** examples should include:
- SSH host key generation via clan vars
- User secrets in sops-nix
- Cross-platform considerations (darwin vs nixos paths)

**Prerequisites:** Story 8.3 (onboarding guides updated)

**Technical Notes:**
- Clan vars path: `sops/machines/<hostname>/secrets/`
- sops-nix user secrets: `sops/users/<user>/secrets.yaml`
- Age keys: Same keypair used for both tiers (Epic 1 pattern)
- Secrets deployment: `/run/secrets/` (nixos) or home-manager managed (darwin)

**NFR Coverage:** NFR-8.4 (Two-tier pattern documentation)

---

## Story 8.5: Audit documentation structure against Diataxis/AMDiRE frameworks

As a documentation maintainer,
I want to audit the documentation structure against Diataxis and AMDiRE frameworks,
So that I have a prioritized list of structural gaps to address.

**Acceptance Criteria:**

**Given** the Starlight docs at `packages/docs/src/content/docs/`
**When** I audit against framework requirements
**Then** the audit should identify:
- Diataxis gaps: tutorials/ (empty), reference/ (sparse), guides completeness
- AMDiRE gaps: development/operations/, development/traceability/ completeness
- Structural recommendations for each gap

**And** output should reference the research document:
- `docs/notes/development/research/documentation-coverage-analysis.md`
- Research streams R8, R9, R10, R14, R15 provide detailed scope

**Prerequisites:** Stories 8.1-8.4 (initial alignment complete)

**Technical Notes:**
- Diataxis framework: tutorials, guides, concepts, reference
- AMDiRE framework: context, requirements, architecture, traceability, work-items
- Focus on structural gaps, not content accuracy (8.1-8.4 addressed accuracy)

**NFR Coverage:** NFR-8.5 (Framework compliance)

---

## Story 8.6: Create reference documentation for CLI tooling

As a user or developer,
I want comprehensive reference documentation for CLI tools,
So that I can discover and use justfile recipes, flake apps, and CI workflows.

**Acceptance Criteria:**

**Given** the justfile with 100+ recipes across 10 groups
**When** I create reference documentation
**Then** documentation should include:
- Justfile recipe reference organized by group (nix, clan, docs, containers, secrets, sops, CI/CD, nix-home-manager, nix-darwin, nixos)
- Flake apps reference (darwin, os, home, update, activate, activate-home)
- CI job reference with local equivalents

**And** each recipe/app should document:
- Purpose and usage
- Prerequisites
- Example invocations
- Related recipes/apps

**Prerequisites:** Story 8.5 (structural audit complete)

**Technical Notes:**
- Location: `packages/docs/src/content/docs/reference/`
- Research streams R16, R17, R18 provide detailed scope
- Consider auto-generation from justfile comments where possible

**NFR Coverage:** NFR-8.6 (CLI discoverability)

---

## Story 8.7: Audit AMDiRE development documentation alignment

As a contributor,
I want development documentation that accurately reflects project context and requirements,
So that I understand the project's goals, constraints, and architectural decisions.

**Acceptance Criteria:**

**Given** the development/ documentation tree
**When** I audit context, requirements, and ADR documentation
**Then** the audit should verify:
- development/context/ (6 files) reflects current project state
- development/requirements/ (7 files) aligns with implemented functionality
- development/architecture/adrs/ (16 ADRs) are current and cross-referenced

**And** identify:
- Outdated context or requirements
- ADRs needing updates or supersession
- Missing traceability links

**Prerequisites:** Story 8.5 (structural audit complete)

**Technical Notes:**
- Research streams R11, R12, R13 provide detailed scope
- Focus on alignment with post-clan-migration reality
- ADRs should reference each other where decisions relate

**NFR Coverage:** NFR-8.7 (Development documentation accuracy)

---

## Story 8.8: Create tutorials for common user workflows

As a new user,
I want step-by-step tutorials for common workflows,
So that I can learn the system through guided practice.

**Acceptance Criteria:**

**Given** the empty tutorials/ directory
**When** I create tutorial content
**Then** tutorials should cover:
- Bootstrap-to-activation journey (new user onboarding)
- Secrets setup workflow (Bitwarden → ssh-to-age → sops-nix)
- Darwin host deployment (macOS-specific workflow)
- NixOS host deployment (VPS-specific workflow)

**And** each tutorial should:
- Be learning-oriented (not task-oriented like guides)
- Include complete working examples
- Build skills progressively
- Reference related guides and concepts

**Prerequisites:** Stories 8.5, 8.6 (structure and reference docs established)

**Technical Notes:**
- Location: `packages/docs/src/content/docs/tutorials/`
- Research streams R1, R2, R3, R4 define user journeys
- Diataxis: tutorials are for learning, guides are for accomplishing tasks

**NFR Coverage:** NFR-8.8 (New user learning path)

---

## Story 8.9: Validate cross-references and navigation discoverability

As a documentation user,
I want to easily navigate between related documentation,
So that I can find information without getting lost.

**Acceptance Criteria:**

**Given** all documentation files
**When** I audit cross-references and navigation
**Then** validation should confirm:
- All internal links are valid (no broken links)
- Related documents link to each other bidirectionally
- Index pages provide clear navigation paths
- Prerequisites are linked from dependent documents

**And** discoverability audit should verify:
- Homepage provides clear entry points for each persona
- Sidebar navigation is logical and complete
- Common tasks are findable within 2 clicks
- Error messages reference relevant troubleshooting docs

**Prerequisites:** Stories 8.6, 8.7, 8.8 (content created/updated)

**Technical Notes:**
- Research streams R20, R21 provide detailed scope
- Use `just docs-linkcheck` for automated link validation
- Manual review needed for navigation quality

**NFR Coverage:** NFR-8.9 (Documentation discoverability)

---

## Story 8.10: Audit test harness and CI documentation

As a developer,
I want documentation that explains how to run tests locally and debug CI,
So that I can validate changes before pushing and troubleshoot failures.

**Acceptance Criteria:**

**Given** the CI workflow (ci.yaml) and justfile test recipes
**When** I audit test documentation
**Then** documentation should cover:
- Every CI job has documented local equivalent
- Test philosophy explained (risk-based, depth scaling)
- Common failure modes and troubleshooting documented
- Module options that affect tests are documented

**And** parity matrix should exist:
- CI job → local justfile recipe mapping
- When to use `just check` vs `just check-fast`
- How to run category-specific builds locally

**Prerequisites:** Story 8.6 (CLI reference includes test recipes)

**Technical Notes:**
- Research streams R19, R22 provide detailed scope
- Location: Enhance about/contributing/testing.md and development/traceability/
- Reference ci.yaml job structure

**NFR Coverage:** NFR-8.10 (Test reproducibility)

---

## Dependencies

**Depends on:**
- Epic 7: GCP infrastructure deployed (must document what exists)

**Enables:**
- Epic 9: Branch consolidation (docs must be accurate before main merge)

---

## Success Criteria

- [ ] Starlight docs site builds without errors
- [ ] Zero references to deprecated nixos-unified architecture
- [ ] Host onboarding guides accurate for both darwin and nixos
- [ ] Secrets management docs cover implemented two-tier pattern
- [ ] Documentation testable against actual infrastructure state
- [ ] Audit checklist completed with all items addressed

---

## Risk Notes

**Documentation drift risks:**
- Infrastructure may change between Epic 7 and Epic 8
- Screenshots/diagrams may become stale

**Mitigation:**
- Use text descriptions over screenshots where possible
- Include validation commands that can be tested
- Link to source files rather than duplicating code

---

**References:**
- PRD: `docs/notes/development/PRD/functional-requirements.md` (FR-8)
- NFRs: `docs/notes/development/PRD/non-functional-requirements.md` (NFR-8)
- Starlight docs: `packages/docs/src/content/docs/`
- Architecture docs: `docs/notes/development/architecture/`
- Research document: `docs/notes/development/research/documentation-coverage-analysis.md`
