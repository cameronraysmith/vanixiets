# Story 8.8: Create Tutorials for Common User Workflows

Status: review

## Story

As a new user learning this infrastructure,
I want step-by-step tutorials that teach me how the system works through guided practice,
so that I build skills progressively and understand both "how" and "why" before using the task-oriented guides.

## Acceptance Criteria

### Bootstrap-to-Activation Tutorial (AC1-AC5)

1. **tutorials/bootstrap-to-activation.md exists**: File created in `packages/docs/src/content/docs/tutorials/`
2. **Prerequisites documented**: Nix installation, git access, hardware requirements clearly stated
3. **Progressive skill building**: Content flows from simple concepts (clone, direnv) to complex (configuration customization)
4. **Working examples included**: All commands tested against current 8-machine fleet configuration
5. **Cross-references to guides**: Links to `/guides/getting-started` and `/guides/host-onboarding` for task completion after learning

### Secrets Setup Tutorial (AC6-AC10)

6. **tutorials/secrets-setup.md exists**: File created in `packages/docs/src/content/docs/tutorials/`
7. **Two-tier architecture explained**: Clan vars (Tier 1) vs sops-nix (Tier 2) with conceptual "why" not just "how"
8. **Bitwarden bootstrap workflow documented**: Complete SSH key retrieval → ssh-to-age → age key derivation journey
9. **Platform differences explained**: Darwin (Tier 2 only) vs NixOS (both tiers) with rationale
10. **Cross-references to guides**: Links to `/guides/secrets-management` and `/concepts/clan-integration` for deeper understanding

### Darwin Deployment Tutorial (AC11-AC15)

11. **tutorials/darwin-deployment.md exists**: File created in `packages/docs/src/content/docs/tutorials/`
12. **End-to-end journey covered**: From fresh macOS to fully activated darwin host
13. **Zerotier darwin integration explained**: Homebrew cask installation with conceptual explanation of mesh networking
14. **Machine examples use real fleet**: stibnite, blackphos, rosegold, argentum referenced appropriately
15. **Cross-references to guides**: Links to `/guides/host-onboarding#darwin-host-onboarding` for operational procedures

### NixOS Deployment Tutorial (AC16-AC20)

16. **tutorials/nixos-deployment.md exists**: File created in `packages/docs/src/content/docs/tutorials/`
17. **Infrastructure provisioning explained**: Terranix + terraform flow with conceptual understanding
18. **Clan installation workflow documented**: `clan machines install` and `clan machines update` with context
19. **Multi-cloud coverage**: Hetzner (cinnabar, electrum) and GCP (galena, scheelite) patterns explained
20. **Cross-references to guides**: Links to `/guides/host-onboarding#nixos-host-onboarding` and `/concepts/clan-integration`

### Diataxis Compliance (AC21-AC23)

21. **Learning-oriented structure**: Each tutorial teaches concepts, not just steps - includes "why" explanations throughout
22. **Progressive complexity**: Tutorials build from simpler to more complex concepts within each document
23. **Distinct from guides**: Content clearly complements (not duplicates) existing task-oriented guides

### Validation (AC24-AC26)

24. **tutorials/index.md created**: Navigation index with clear learning path recommendations
25. **Starlight build passes**: `bun run build` succeeds with all new tutorial files
26. **Internal links valid**: All cross-references to guides/, concepts/, reference/ verified working

## Tasks / Subtasks

### Task 1: Research Phase - Understand Existing Coverage (AC: all)

- [x] Read all 7 guides completely to understand current task-oriented coverage
  - [x] getting-started.md - bootstrap commands documented (259 lines)
  - [x] host-onboarding.md - darwin vs NixOS procedures (640 lines)
  - [x] home-manager-onboarding.md - user environment setup (462 lines)
  - [x] secrets-management.md - two-tier secrets operations (529 lines)
  - [x] adding-custom-packages.md - pkgs-by-name pattern (249 lines)
  - [x] handling-broken-packages.md - hotfixes workflow (643 lines)
  - [x] mcp-servers-usage.md - MCP integration (166 lines)
- [x] Read all 5 concepts completely to understand existing mental models
  - [x] nix-config-architecture.md - four-layer architecture (207 lines)
  - [x] dendritic-architecture.md - aspect-based organization (343 lines)
  - [x] clan-integration.md - multi-machine coordination (293 lines)
  - [x] multi-user-patterns.md - admin vs standalone users (302 lines)
  - [x] index.md - navigation structure (18 lines)
- [x] Review Story 8.6 CLI reference docs for command documentation
- [x] Document differentiation strategy: what tutorials teach vs what guides accomplish

### Task 2: Create Bootstrap-to-Activation Tutorial (AC: #1-5, #21-23)

- [x] Create `packages/docs/src/content/docs/tutorials/bootstrap-to-activation.md`
- [x] Write frontmatter with title, description, sidebar order
- [x] Section 1: Introduction - What you will learn
  - [x] Explain learning objectives (not just outcomes)
  - [x] Set expectations for time and prerequisites
- [x] Section 2: Understanding the Nix ecosystem
  - [x] Explain flakes, direnv, and development shells conceptually
  - [x] Why this architecture was chosen (link to concepts)
- [x] Section 3: Your first bootstrap
  - [x] Clone repository with explanation of structure
  - [x] `make bootstrap` with explanation of what each step does
  - [x] `direnv allow` with context on automatic environments
- [x] Section 4: Understanding the configuration
  - [x] Explore `modules/` structure with explanations
  - [x] Understand dendritic pattern through exploration
  - [x] Find your machine configuration
- [x] Section 5: First activation
  - [x] `darwin-rebuild switch` or `clan machines update` with full context
  - [x] Understand what changed and why
  - [x] Verify successful activation
- [x] Section 6: Next steps
  - [x] Link to secrets tutorial for credential setup
  - [x] Link to guides for operational tasks
  - [x] Link to concepts for deeper understanding
- [x] Add cross-references to related guides and concepts

### Task 3: Create Secrets Setup Tutorial (AC: #6-10, #21-23)

- [x] Create `packages/docs/src/content/docs/tutorials/secrets-setup.md`
- [x] Write frontmatter with title, description, sidebar order
- [x] Section 1: Introduction - Why secrets management matters
  - [x] Explain security model conceptually
  - [x] Two-tier architecture rationale (not just structure)
- [x] Section 2: Understanding the two tiers
  - [x] Tier 1 (clan vars): What it's for, how it works, when to use
  - [x] Tier 2 (sops-nix): What it's for, how it works, when to use
  - [x] Platform differences explained conceptually
- [x] Section 3: The Bitwarden bootstrap journey
  - [x] Why SSH keys live in Bitwarden (security rationale)
  - [x] Step-by-step key retrieval with explanations
  - [x] ssh-to-age derivation with conceptual context
  - [x] Age key storage and security considerations
- [x] Section 4: Setting up your secrets
  - [x] Adding your key to .sops.yaml with explanation
  - [x] Creating your first secret with context
  - [x] Understanding encryption at rest
- [x] Section 5: Verifying secrets work
  - [x] Test decryption with understanding
  - [x] Activate configuration with secrets
  - [x] Troubleshoot common issues
- [x] Section 6: Next steps
  - [x] Link to secrets-management guide for operations
  - [x] Link to clan-integration concept for architecture
- [x] Add cross-references to related guides and concepts

### Task 4: Create Darwin Deployment Tutorial (AC: #11-15, #21-23)

- [x] Create `packages/docs/src/content/docs/tutorials/darwin-deployment.md`
- [x] Write frontmatter with title, description, sidebar order
- [x] Section 1: Introduction - Darwin in this infrastructure
  - [x] Explain nix-darwin conceptually
  - [x] How darwin differs from NixOS (and why)
  - [x] Fleet overview: stibnite, blackphos, rosegold, argentum
- [x] Section 2: Preparing your Mac
  - [x] Nix installation with context
  - [x] Homebrew for zerotier (and why not nix)
  - [x] Repository setup
- [x] Section 3: Understanding your darwin configuration
  - [x] Explore `modules/machines/darwin/` with explanations
  - [x] Understand aggregate imports and why they exist
  - [x] Find machine-specific vs shared settings
- [x] Section 4: Your first darwin deployment
  - [x] Build validation with explanation
  - [x] `darwin-rebuild switch` with full context
  - [x] Understanding the activation process
- [x] Section 5: Zerotier mesh integration
  - [x] Why zerotier (mesh networking concept)
  - [x] Installing and joining the network
  - [x] Authorization flow and controller concept
  - [x] Verifying connectivity
- [x] Section 6: Setting up secrets (darwin-specific)
  - [x] Tier 2 only explanation
  - [x] Age key setup for darwin
  - [x] Verify secrets deployment
- [x] Section 7: Next steps
  - [x] Link to host-onboarding guide for operations
  - [x] Link to secrets tutorial for full secrets understanding
- [x] Add cross-references to related guides and concepts

### Task 5: Create NixOS Deployment Tutorial (AC: #16-20, #21-23)

- [x] Create `packages/docs/src/content/docs/tutorials/nixos-deployment.md`
- [x] Write frontmatter with title, description, sidebar order
- [x] Section 1: Introduction - NixOS in this infrastructure
  - [x] Explain clan-managed NixOS conceptually
  - [x] How NixOS differs from darwin (and why)
  - [x] Fleet overview: cinnabar, electrum (Hetzner), galena, scheelite (GCP)
- [x] Section 2: Understanding the infrastructure layer
  - [x] Terranix and terraform conceptually
  - [x] Multi-cloud strategy (Hetzner vs GCP)
  - [x] Toggle patterns for cost control
- [x] Section 3: Provisioning infrastructure
  - [x] Understanding `nix run .#terraform`
  - [x] Hetzner example with context
  - [x] GCP example with context
  - [x] What gets created and why
- [x] Section 4: Understanding clan machine configuration
  - [x] Explore `modules/machines/nixos/` with explanations
  - [x] Clan inventory and service instances conceptually
  - [x] Vars generation and why it matters
- [x] Section 5: Your first NixOS deployment
  - [x] `clan vars generate` with explanation
  - [x] `clan machines install` with full context
  - [x] Understanding what gets deployed where
- [x] Section 6: Updates and the zerotier mesh
  - [x] `clan machines update` conceptually
  - [x] Automatic zerotier integration
  - [x] Verifying mesh connectivity
- [x] Section 7: Two-tier secrets on NixOS
  - [x] Both tiers available explanation
  - [x] Tier 1 automatic secrets
  - [x] Tier 2 user secrets setup
- [x] Section 8: Next steps
  - [x] Link to host-onboarding guide for operations
  - [x] Link to clan-integration concept for architecture
- [x] Add cross-references to related guides and concepts

### Task 6: Create Tutorials Index (AC: #24)

- [x] Create `packages/docs/src/content/docs/tutorials/index.md`
- [x] Write frontmatter with title, description, sidebar order: 1
- [x] Section 1: About these tutorials
  - [x] Explain Diataxis tutorial purpose (learning, not doing)
  - [x] Differentiate from guides (task-oriented)
- [x] Section 2: Recommended learning path
  - [x] Suggested order for new users
  - [x] Prerequisites between tutorials
  - [x] Time expectations
- [x] Section 3: Tutorial catalog
  - [x] Bootstrap-to-Activation: What you'll learn, prerequisites, time
  - [x] Secrets Setup: What you'll learn, prerequisites, time
  - [x] Darwin Deployment: What you'll learn, prerequisites, time
  - [x] NixOS Deployment: What you'll learn, prerequisites, time
- [x] Section 4: After completing tutorials
  - [x] Link to guides for operational tasks
  - [x] Link to concepts for deeper understanding
  - [x] Link to reference for CLI details

### Task 7: Validation Phase (AC: #25-26)

- [x] Run Starlight build: `bun run build`
- [x] Verify all internal links work
  - [x] Check all `/guides/` references
  - [x] Check all `/concepts/` references
  - [x] Check all `/reference/` references
- [x] Verify sidebar appears correctly in development server
- [x] Run link validation if available: `just docs-linkcheck`
- [x] Update story status to review

## Dev Notes

### Diataxis Framework Context

This story addresses the CRITICAL gap identified in Story 8.5 audit: the `packages/docs/src/content/docs/tutorials/` directory is completely empty.

**Tutorials vs Guides (Diataxis distinction):**

| Aspect | Tutorials (this story) | Guides (existing) |
|--------|------------------------|-------------------|
| Orientation | Learning-oriented | Task-oriented |
| Purpose | Teach concepts and skills | Accomplish specific goals |
| Structure | Progressive skill building | Step-by-step procedures |
| Content | Includes "why" explanations | Focuses on "how" steps |
| User state | New user building skills | User with task to complete |
| Examples | Working through scenarios | Quick reference |

**Key principle:** Tutorials teach the user through guided learning, then point to guides for operational use.

### Current Machine Fleet for Examples

**Darwin machines (4):**
- stibnite - crs58's primary workstation (Apple Silicon)
- blackphos - raquel's workstation (Apple Silicon)
- rosegold - janettesmith's workstation (Apple Silicon)
- argentum - christophersmith's workstation (Apple Silicon)

**NixOS machines (4):**
- cinnabar - Hetzner VPS, zerotier controller
- electrum - Hetzner VPS, zerotier peer
- galena - GCP CPU node (e2-standard-8)
- scheelite - GCP GPU node (n1-standard-8 + Tesla T4)

**Zerotier network:** db4344343b14b903

### Two-Tier Secrets Architecture

**Tier 1 (clan vars) - System-level:**
- Automatic generation via `clan vars generate`
- SSH host keys, zerotier identities, service credentials
- NixOS only (not available on darwin)
- Deployed to `/run/secrets/`

**Tier 2 (sops-nix) - User-level:**
- Manual creation, derived from SSH keys via ssh-to-age
- GitHub tokens, API keys, personal credentials
- Available on all platforms (darwin + NixOS)
- Deployed to `~/.config/sops-nix/secrets/`

**Bootstrap flow:** Bitwarden → SSH key retrieval → ssh-to-age → age private key → .sops.yaml public key → sops secrets

### Key CLI Commands to Document

**Bootstrap/activation:**
- `make bootstrap` - Initial nix + direnv installation
- `direnv allow` - Activate development shell
- `darwin-rebuild switch --flake .#<hostname>` - Darwin deployment
- `clan machines update <hostname>` - NixOS deployment

**Infrastructure:**
- `nix run .#terraform` - Terranix infrastructure provisioning
- `clan machines install <hostname> --target-host root@<ip>` - Fresh NixOS install
- `clan vars generate <hostname>` - Generate Tier 1 secrets

**Secrets:**
- `age-keygen -o ~/.config/sops/age/keys.txt` - Generate age key
- `ssh-to-age -private-key -i <ssh_key>` - Derive age from SSH
- `sops <file>` - Edit encrypted secrets
- `sops -d <file>` - Decrypt and view secrets

**Verification:**
- `just check` - Run nix flake checks
- `just activate` - Shortcut for darwin activation
- `sudo zerotier-cli listnetworks` - Check zerotier status

### Reference to Story 8.6 (CLI Tooling Reference)

Story 8.6 created comprehensive CLI reference documentation:
- `reference/justfile-recipes.md` - All justfile recipes by group
- `reference/flake-apps.md` - Flake app documentation
- `reference/ci-jobs.md` - CI job reference

Tutorials should reference these docs for CLI details rather than duplicating command documentation. Link pattern: "See the [Justfile Recipe Reference](/reference/justfile-recipes) for the complete command catalog."

### Research Stream Coverage

From `docs/notes/development/research/documentation-coverage-analysis.md`:

| Stream | Tutorial Coverage |
|--------|-------------------|
| R1 (Bootstrap-to-Activation) | bootstrap-to-activation.md |
| R2 (Secrets Lifecycle) | secrets-setup.md |
| R3 (Darwin Pipeline) | darwin-deployment.md |
| R4 (NixOS/Cloud Pipeline) | nixos-deployment.md |

### Project Structure Notes

- Tutorials live in `packages/docs/src/content/docs/tutorials/`
- Pattern: lowercase-kebab-case filenames
- Frontmatter: title, description, sidebar object with order
- Cross-refs use absolute paths: `/guides/getting-started`, `/concepts/clan-integration`

### Learnings from Previous Story

**From Story 8.7 (Status: review):**

- Parallel subagent dispatch effective for research-intensive tasks
- Evidence-based assessments with line numbers valuable
- Starlight build validation: `bun run build`
- Verification commands useful for quality assurance
- Comprehensive completion notes aid future stories

[Source: docs/notes/development/work-items/8-7-audit-amdire-development-documentation-alignment.md#Completion-Notes-List]

### Constraints

1. **Learning-oriented, not task-oriented**: Include "why" explanations, not just "how" steps
2. **Document current architecture only**: Dendritic flake-parts + clan-core (NOT nixos-unified)
3. **Real machine examples**: Use actual 8-machine fleet, not hypothetical examples
4. **Cross-reference, don't duplicate**: Link to guides for task completion, concepts for mental models
5. **Progressive complexity**: Start simple, build to complex within each tutorial
6. **Working examples**: All commands must work against current configuration

### References

- [Epic 8: docs/notes/development/epics/epic-8-documentation-alignment.md] (lines 325-355)
- [Research Document: docs/notes/development/research/documentation-coverage-analysis.md] (R1-R4)
- [Story 8.5 Audit: docs/notes/development/work-items/story-8.5-structure-audit-results.md]
- [Story 8.6 CLI Reference: reference/justfile-recipes.md, reference/flake-apps.md]
- [Diataxis Framework: https://diataxis.fr/]

### NFR Coverage

| NFR | Coverage |
|-----|----------|
| NFR-8.8 | New user learning path |
| NFR-8.1 | Zero references to deprecated architecture |

### Estimated Effort

| Task | Estimate |
|------|----------|
| Task 1 (Research phase) | 2-3 hours |
| Task 2 (Bootstrap tutorial) | 4-5 hours |
| Task 3 (Secrets tutorial) | 3-4 hours |
| Task 4 (Darwin tutorial) | 4-5 hours |
| Task 5 (NixOS tutorial) | 5-6 hours |
| Task 6 (Index) | 1-2 hours |
| Task 7 (Validation) | 1-2 hours |
| **Total** | **20-27 hours** |

**Effort justification:** Tutorials require substantial content creation with conceptual explanations. Each tutorial is estimated at 1,500-2,500 words with code examples, diagrams, and comprehensive cross-references.

## Dev Agent Record

### Context Reference

No context file generated - proceeding with story file and discover_inputs protocol.

### Agent Model Used

claude-opus-4-5-20251101 (Opus 4.5)

### Debug Log References

**2025-12-02 Task 1 Research Summary:**

**Documentation Coverage Analysis:**
- 7 guides (2,948 lines total): All task-oriented, current with dendritic+clan architecture
- 5 concepts (1,163 lines total): Provide foundational mental models
- 4 reference docs (827 lines total): CLI commands from Story 8.6
- Research document (R1-R4 streams): Identified exact gaps tutorials must fill

**Differentiation Strategy:**
| Aspect | Tutorials (create) | Guides (exist) |
|--------|-------------------|----------------|
| Focus | WHY decisions made | HOW to execute |
| Structure | Progressive learning | Step-by-step procedures |
| Prerequisites | Explains from scratch | Assumes knowledge |
| Outcome | Skills and understanding | Task completion |

**Key Principles:**
1. Tutorials REFERENCE guides for procedures, don't duplicate
2. Tutorials EXPLAIN concepts before showing commands
3. Tutorials BUILD progressive understanding through exploration
4. Tutorials LINK to concepts for deeper mental models

**Reclassification Assessment:**
- No guides require reclassification (all appropriately task-oriented)
- adding-custom-packages.md has good conceptual content - tutorials can reference it
- handling-broken-packages.md is operational runbook - tutorials complement it

### Completion Notes List

**2025-12-02 Story Complete:**

- Created 5 tutorial files totaling ~2,500 lines of learning-oriented documentation
- All 26 acceptance criteria satisfied with evidence
- Starlight build passes, all internal links validated
- Diataxis compliance: tutorials are learning-oriented (WHY) vs guides (HOW)

**Key Deliverables:**
1. `tutorials/index.md` (143 lines) - Learning path overview and catalog
2. `tutorials/bootstrap-to-activation.md` (303 lines) - Zero to working system
3. `tutorials/secrets-setup.md` (361 lines) - Two-tier secrets architecture
4. `tutorials/darwin-deployment.md` (418 lines) - macOS deployment end-to-end
5. `tutorials/nixos-deployment.md` (410 lines) - Cloud deployment with terranix + clan

**Cross-reference counts:**
- Links to guides: 15
- Links to concepts: 12
- Links to reference: 4
- Total cross-references: 31

**Validation evidence:**
- `bun run build`: SUCCESS (72 pages indexed)
- `just docs-linkcheck`: SUCCESS (All internal links valid)
- Tutorials appear in sidebar correctly

**Diataxis Compliance Notes:**
- Each tutorial includes "What you will learn" and "Prerequisites"
- Tutorials explain WHY decisions were made, not just HOW to execute
- Progressive skill building within each tutorial
- Explicitly link to guides for operational procedures

### File List

**Created:**
- packages/docs/src/content/docs/tutorials/index.md (143 lines)
- packages/docs/src/content/docs/tutorials/bootstrap-to-activation.md (303 lines)
- packages/docs/src/content/docs/tutorials/secrets-setup.md (361 lines)
- packages/docs/src/content/docs/tutorials/darwin-deployment.md (418 lines)
- packages/docs/src/content/docs/tutorials/nixos-deployment.md (410 lines)

## Change Log

**2025-12-02 (Story Complete):**
- Created 5 tutorial files in packages/docs/src/content/docs/tutorials/
- All 26 acceptance criteria satisfied
- Starlight build and link validation passed
- Story status updated to review

**2025-12-02 (Story Drafted):**
- Story file created from Epic 8 Story 8.8 specification
- Incorporated research streams R1, R2, R3, R4 from documentation-coverage-analysis.md
- 26 acceptance criteria mapped to 7 task groups
- Diataxis framework context documented (tutorials vs guides distinction)
- 8-machine fleet documented for examples
- Two-tier secrets architecture summarized
- Key CLI commands cataloged for tutorial content
- Reference to Story 8.6 CLI docs for cross-linking
- Previous story learnings incorporated from Story 8.7
- Estimated effort: 20-27 hours
