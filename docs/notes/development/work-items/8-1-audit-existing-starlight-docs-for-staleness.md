# Story 8.1: Audit Existing Starlight Docs for Staleness

Status: done

## Story

As a documentation maintainer,
I want to audit all existing Starlight documentation for outdated content,
so that I have a prioritized list of updates before making changes.

## Context

Story 8.1 initiates Epic 8 (Documentation Alignment) following the successful completion of Epic 7 (GCP Multi-Node Infrastructure).
This is an audit-only story producing an actionable checklist for Stories 8.2-8.4 implementation.
No modifications to Starlight docs occur in this story.

**Current State:**
- Starlight docs location: `packages/docs/src/content/docs/`
- Total files: 58 .md files across 9 categories
- Architecture: Dendritic flake-parts + clan-core (documented in internal docs)
- Starlight site: Likely contains stale nixos-unified references

**Epic 7 Retrospective Action Items (Documentation Gaps):**
| Priority | Topic | Notes |
|----------|-------|-------|
| HIGH | GCP Deployment Patterns | Startup-script workaround, zone availability |
| HIGH | Zerotier Authorization Flow | Controller update requirement after adding peers |
| HIGH | NVIDIA Datacenter Anti-Patterns | Bug #454772, global cudaSupport, nvidiaPersistenced |
| MEDIUM | GPU Onboarding Guide | CUDA cache, scoped overlays, driver selection |
| MEDIUM | Cost Control Toggle Pattern | Default disabled, cost documentation |

## Acceptance Criteria

1. Inventory of all .md/.mdx files in docs site (`packages/docs/src/content/docs/`)
2. Classification system with four categories:
   - **Current**: accurate, no updates needed
   - **Stale**: outdated but partially relevant
   - **Obsolete**: no longer applicable
   - **Missing**: needed but not present
3. Staleness indicators must identify:
   - References to `nixos-unified` or `configurations/` directory
   - Outdated architecture diagrams
   - Commands that no longer work
   - Missing coverage for new patterns (dendritic, clan)
   - Incorrect host references (obsolete machines)
4. Priority ranking for updates:
   - **Critical**: blocks other stories
   - **High**: significant gaps
   - **Medium**: nice-to-have improvements
   - **Low**: cosmetic updates
5. Estimated effort per document (for Stories 8.2-8.4 planning)
6. Audit output written to `docs/notes/development/work-items/story-8.1-audit-results.md`
7. Structured as actionable checklist for Stories 8.2-8.4 implementation

## Tasks / Subtasks

- [x] Task 1: Create file inventory (AC: #1)
  - [x] List all .md files in `packages/docs/src/content/docs/` with category breakdown
  - [x] Count files per category (About, Concepts, Development, Guides, Reference)
  - [x] Create inventory table in audit results document

- [x] Task 2: Search for staleness indicators (AC: #3)
  - [x] Search for `nixos-unified` references: `rg "nixos-unified" packages/docs/`
  - [x] Search for `configurations/` references: `rg "configurations/" packages/docs/`
  - [x] Search for `LazyVim-module` references: `rg "LazyVim-module" packages/docs/`
  - [x] Search for obsolete machine references (stibnite-nixos, blackphos-nixos, etc.)
  - [x] Identify commands that reference old directory structures
  - [x] Note missing coverage for dendritic, clan-core, zerotier patterns

- [x] Task 3: Classify each document (AC: #2)
  - [x] Review each file for staleness indicators
  - [x] Assign status: Current, Stale, Obsolete, or Missing
  - [x] Document specific issues per file

- [x] Task 4: Identify missing documentation (AC: #2, #3)
  - [x] Compare current architecture against documented patterns
  - [x] List undocumented patterns from Epic 7 retrospective
  - [x] Identify gaps in darwin vs nixos onboarding
  - [x] Note missing two-tier secrets documentation

- [x] Task 5: Assign priority rankings (AC: #4)
  - [x] Critical: Documents blocking Story 8.2-8.4
  - [x] High: Major gaps affecting user experience
  - [x] Medium: Improvements for completeness
  - [x] Low: Cosmetic or minor updates

- [x] Task 6: Estimate effort per document (AC: #5)
  - [x] Small: < 30 min (minor updates)
  - [x] Medium: 30 min - 2 hours (section rewrites)
  - [x] Large: > 2 hours (major overhaul or new document)

- [x] Task 7: Assign target stories (AC: #7)
  - [x] Story 8.2: Architecture and patterns documentation
  - [x] Story 8.3: Host onboarding guides (darwin vs nixos)
  - [x] Story 8.4: Secrets management documentation

- [x] Task 8: Create audit results document (AC: #6)
  - [x] Write `docs/notes/development/work-items/story-8.1-audit-results.md`
  - [x] Include inventory table
  - [x] Include classification table with columns: File, Status, Key Issues, Priority, Effort, Target Story
  - [x] Include missing documentation section
  - [x] Include summary statistics

## Dev Notes

### Starlight Docs Structure

The documentation site uses Astro Starlight and is located at `packages/docs/src/content/docs/`.

**Category Breakdown (58 files):**
| Category | Path | Count |
|----------|------|-------|
| About/Contributing | `about/` | 8 files |
| Concepts | `concepts/` | 4 files |
| Development/Architecture | `development/architecture/` | 19 files (incl 16 ADRs) |
| Development/Context | `development/context/` | 8 files |
| Development/Requirements | `development/requirements/` | 9 files |
| Development/Operations | `development/operations/` | 1 file |
| Development/Traceability | `development/traceability/` | 2 files |
| Development/Work Items | `development/work-items/` | 1 file |
| Guides | `guides/` | 8 files |
| Reference | `reference/` | 1 file |

### Known Stale Documents (Pre-Audit Indicators)

| File | Key Issues |
|------|------------|
| `guides/host-onboarding.md` | References `configurations/` directory, missing clan patterns |
| `guides/secrets-management.md` | Old 3-tier Bitwarden pattern, not two-tier clan vars + sops-nix |
| `concepts/nix-config-architecture.md` | References nixos-unified, missing dendritic + clan |

### Current Architecture (Reference for Comparison)

What the documentation should reflect:
- Dendritic flake-parts module organization (`modules/` directory structure)
- Clan-core for multi-machine coordination (`modules/clan/`)
- Two-tier secrets: clan vars (system) + sops-nix (user)
- GCP infrastructure patterns (terranix, startup-script workaround)
- Zerotier mesh networking (controller/peer pattern)
- Datacenter NVIDIA configuration patterns (nvidiaPersistenced, scoped CUDA)

### Machine Fleet (Current State)

| Hostname | Type | Notes |
|----------|------|-------|
| stibnite | nix-darwin | crs58's workstation |
| blackphos | nix-darwin | raquel's workstation |
| argentum | nix-darwin | christophersmith's workstation |
| rosegold | nix-darwin | janettesmith's workstation |
| cinnabar | NixOS VPS | Zerotier coordinator |
| electrum | NixOS VPS | Zerotier peer |
| galena | NixOS GCP | CPU-only (disabled) |
| scheelite | NixOS GCP | GPU T4 (disabled) |

### Staleness Search Patterns

```bash
# Primary staleness indicators
rg "nixos-unified" packages/docs/
rg "configurations/" packages/docs/
rg "LazyVim-module" packages/docs/

# Obsolete machine references
rg "stibnite-nixos|blackphos-nixos|rosegold-old" packages/docs/

# Old secrets patterns
rg "bitwarden|three-tier|3-tier" packages/docs/

# Missing pattern indicators (should exist but may not)
rg "dendritic|flake-parts" packages/docs/
rg "clan-core|clan\.nix" packages/docs/
rg "terranix" packages/docs/
```

### Project Structure Notes

Output files:
- Audit results: `docs/notes/development/work-items/story-8.1-audit-results.md`

No files modified in Starlight docs (audit-only story).

### Learnings from Previous Story

**From Story 7.4 (Status: done - APPROVED)**

- **Datacenter NVIDIA Anti-Patterns**: Bug #454772 (datacenter.enable), global cudaSupport causes mass rebuilds, nvidiaPersistenced critical for headless
- **Scoped CUDA Pattern**: Use pythonPackagesExtensions overlay instead of global nixpkgs.config.cudaSupport
- **GCP Deployment Patterns**: startup-script workaround for root SSH, zone availability constraints
- **Zerotier Authorization Flow**: New peers require `clan machines update [controller]`
- **Cost Control Toggle**: Default `enabled = false` pattern for expensive resources
- **10 Patterns Established**: terranix GCP, NixOS machine config, startup-script, zerotier peer, NVIDIA module, scoped CUDA, CUDA cache, cost control toggle, SSH config for .zt, dendritic module auto-discovery

**Epic 7 Retrospective Action Items:**
- HIGH: GCP deployment patterns, zerotier authorization flow, NVIDIA datacenter anti-patterns
- MEDIUM: GPU onboarding guide, cost control toggle pattern
- All require documentation updates in Epic 8

[Source: docs/notes/development/retrospectives/epic-7-gcp-multi-node-infrastructure.md]
[Source: docs/notes/development/work-items/7-4-gpu-capable-togglable-node-definition-deployment.md#Dev-Agent-Record]

### References

- [Epic 8: docs/notes/development/epics/epic-8-documentation-alignment.md]
- [Epic 7 Retrospective: docs/notes/development/retrospectives/epic-7-gcp-multi-node-infrastructure.md]
- [Architecture Index: docs/notes/development/architecture/index.md]
- [Starlight Docs: packages/docs/src/content/docs/]

### NFR Coverage

| NFR | Coverage |
|-----|----------|
| NFR-8.1 | Zero references to deprecated architecture (audit identifies all) |

### Estimated Effort

**2-4 hours** (research and documentation)

- File inventory: 30 min
- Staleness search: 30 min
- Document classification: 1-2 hours
- Results document creation: 30 min - 1 hour

## Dev Agent Record

### Context Reference

<!-- Path(s) to story context XML will be added here by context workflow -->

### Agent Model Used

{{agent_model_name_version}}

### Debug Log References

### Completion Notes List

**2025-12-01: Story 8.1 Completed**

Comprehensive audit of 59 Starlight documentation files completed. Key findings:

**Status Distribution:**
- Current: 22 files (37%) - No updates needed
- Stale: 21 files (36%) - Outdated but partially relevant
- Obsolete: 9 files (15%) - Need complete rewrites
- Missing: 7 topics identified - Need new documentation

**Priority Distribution:**
- Critical: 6 files (blocks Stories 8.2-8.4)
- High: 12 files (significant gaps)
- Medium: 12 files (nice-to-have)
- Low: 10 files (cosmetic)

**Most Common Staleness Patterns:**
1. `nixos-unified` references (80+ occurrences across 35+ files)
2. `configurations/` paths (60+ occurrences across 20+ files)
3. Bitwarden/3-tier secrets pattern (14 occurrences)

**Critical Path Items:**
1. `concepts/nix-config-architecture.md` - Foundation for all docs
2. `reference/repository-structure.md` - Core directory reference
3. `index.mdx` - Landing page with wrong tagline
4. `guides/host-onboarding.md` - Main operational guide

**Total Effort Estimate:**
- Story 8.2 (Architecture/Concepts): 34-38h
- Story 8.3 (Host Onboarding): 18-20h
- Story 8.4 (Secrets Management): 5-6h
- **Total: 57-64 hours**

**Missing Documentation (from Epic 7 retrospective):**
- Dendritic flake-parts architecture
- Clan-core integration
- Two-tier secrets (clan vars + sops-nix)
- GCP deployment patterns
- Zerotier authorization flow
- NVIDIA datacenter anti-patterns

Full results: `docs/notes/development/work-items/story-8.1-audit-results.md`

### File List

**Files Created:**
- `docs/notes/development/work-items/story-8.1-audit-results.md`

**Files Updated:**
- `docs/notes/development/sprint-status.yaml` (story-8-1: drafted → in-progress → done)
- `docs/notes/development/work-items/8-1-audit-existing-starlight-docs-for-staleness.md` (this file)

## Change Log

**2025-12-01 (Story Completed)**:
- Comprehensive audit of 59 Starlight documentation files
- Ran 8 parallel searches for staleness indicators
- Classified all documents: 22 current, 21 stale, 9 obsolete, 7 missing
- Identified 6 critical path items blocking Stories 8.2-8.4
- Total effort estimate: 57-64 hours across Stories 8.2-8.4
- Created audit results document with actionable checklist
- All 7 acceptance criteria met
- All 8 tasks completed

**2025-12-01 (Story Drafted)**:
- Story file created from Epic 8 Story 8.1 specification
- All 7 acceptance criteria mapped to 8 task groups
- Pre-audit staleness indicators documented (3 known stale files)
- File inventory: 58 files across 9 categories
- Epic 7 retrospective action items incorporated
- Machine fleet updated (8 hosts current state)
- Staleness search patterns documented
- Estimated effort: 2-4 hours
