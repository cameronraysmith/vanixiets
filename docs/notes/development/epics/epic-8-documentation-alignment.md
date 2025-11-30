# Epic 8: Documentation Alignment (Post-MVP Phase 7)

**Status:** Backlog
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

**Business Objective:** Documentation accuracy enables new contributors and reduces support burden.

---

## FR Coverage Map

| Story | Functional Requirements |
|-------|-------------------------|
| Story 8.1 | FR-8.1 (Starlight docs audit) |
| Story 8.2 | FR-8.2 (Architecture documentation) |
| Story 8.3 | FR-8.3 (Host onboarding guides) |
| Story 8.4 | FR-8.4 (Secrets management docs) |

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
