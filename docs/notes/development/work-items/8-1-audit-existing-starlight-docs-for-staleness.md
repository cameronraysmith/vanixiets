# Story 8.1: Audit Existing Starlight Docs for Staleness

Status: drafted

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

- [ ] Task 1: Create file inventory (AC: #1)
  - [ ] List all .md files in `packages/docs/src/content/docs/` with category breakdown
  - [ ] Count files per category (About, Concepts, Development, Guides, Reference)
  - [ ] Create inventory table in audit results document

- [ ] Task 2: Search for staleness indicators (AC: #3)
  - [ ] Search for `nixos-unified` references: `rg "nixos-unified" packages/docs/`
  - [ ] Search for `configurations/` references: `rg "configurations/" packages/docs/`
  - [ ] Search for `LazyVim-module` references: `rg "LazyVim-module" packages/docs/`
  - [ ] Search for obsolete machine references (stibnite-nixos, blackphos-nixos, etc.)
  - [ ] Identify commands that reference old directory structures
  - [ ] Note missing coverage for dendritic, clan-core, zerotier patterns

- [ ] Task 3: Classify each document (AC: #2)
  - [ ] Review each file for staleness indicators
  - [ ] Assign status: Current, Stale, Obsolete, or Missing
  - [ ] Document specific issues per file

- [ ] Task 4: Identify missing documentation (AC: #2, #3)
  - [ ] Compare current architecture against documented patterns
  - [ ] List undocumented patterns from Epic 7 retrospective
  - [ ] Identify gaps in darwin vs nixos onboarding
  - [ ] Note missing two-tier secrets documentation

- [ ] Task 5: Assign priority rankings (AC: #4)
  - [ ] Critical: Documents blocking Story 8.2-8.4
  - [ ] High: Major gaps affecting user experience
  - [ ] Medium: Improvements for completeness
  - [ ] Low: Cosmetic or minor updates

- [ ] Task 6: Estimate effort per document (AC: #5)
  - [ ] Small: < 30 min (minor updates)
  - [ ] Medium: 30 min - 2 hours (section rewrites)
  - [ ] Large: > 2 hours (major overhaul or new document)

- [ ] Task 7: Assign target stories (AC: #7)
  - [ ] Story 8.2: Architecture and patterns documentation
  - [ ] Story 8.3: Host onboarding guides (darwin vs nixos)
  - [ ] Story 8.4: Secrets management documentation

- [ ] Task 8: Create audit results document (AC: #6)
  - [ ] Write `docs/notes/development/work-items/story-8.1-audit-results.md`
  - [ ] Include inventory table
  - [ ] Include classification table with columns: File, Status, Key Issues, Priority, Effort, Target Story
  - [ ] Include missing documentation section
  - [ ] Include summary statistics

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

### File List

## Change Log

**2025-12-01 (Story Drafted)**:
- Story file created from Epic 8 Story 8.1 specification
- All 7 acceptance criteria mapped to 8 task groups
- Pre-audit staleness indicators documented (3 known stale files)
- File inventory: 58 files across 9 categories
- Epic 7 retrospective action items incorporated
- Machine fleet updated (8 hosts current state)
- Staleness search patterns documented
- Estimated effort: 2-4 hours
