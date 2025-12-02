# Story 8.2: Architecture and Concepts Documentation Update

Status: drafted

## Story

As a new contributor,
I want accurate architecture documentation that reflects the current dendritic flake-parts + clan-core implementation,
so that I can understand how the infrastructure is organized.

## Acceptance Criteria

1. **New dendritic architecture doc** created at `packages/docs/src/content/docs/concepts/dendritic-architecture.md` with proper attribution to pattern creators

2. **Proper attribution** for dendritic pattern included:
   - Shahar "Dawn" Or (@mightyiam) - pattern creator
   - Robert Hensing / Hercules CI - flake-parts foundation
   - Victor Borja (@vic) - import-tree and dendrix ecosystem

3. **Clear clan boundaries** documented explaining:
   - What clan manages (machines, inventory, vars, deployment, service orchestration)
   - What clan does NOT manage (terranix, home-manager config, sops-nix secrets, NixOS modules)
   - Integration points between clan and other tools

4. **nix-config-architecture.md rewritten** to reference dendritic pattern instead of nixos-unified

5. **repository-structure.md updated** with correct `modules/` directory structure (not `configurations/`)

6. **index.mdx landing page updated** to remove "nixos-unified" tagline

7. **Obsolete concepts removed or redirected**:
   - `understanding-autowiring.md` - nixos-unified specific
   - `multi-user-patterns.md` - outdated paths

8. **Zero references** to `nixos-unified`, `configurations/`, or deprecated patterns remain in updated files

## Tasks / Subtasks

### Task 1: Create dendritic-architecture.md (AC: #1, #2)
- [ ] Create new file `packages/docs/src/content/docs/concepts/dendritic-architecture.md`
- [ ] Document dendritic flake-parts pattern concept
- [ ] Include attribution block for pattern creators:
  - flake-parts: Robert Hensing / Hercules CI
  - dendritic pattern: Shahar "Dawn" Or (@mightyiam)
  - import-tree: Victor Borja (@vic)
  - dendrix ecosystem: Victor Borja (@vic)
- [ ] Document key principle: every Nix file is a flake-parts module
- [ ] Document aspect-based organization (vs host-based)
- [ ] Include links to external references:
  - https://github.com/mightyiam/dendritic
  - https://vic.github.io/dendrix/Dendritic.html
  - https://flake.parts
- [ ] Commit: `docs(concepts): create dendritic-architecture.md with proper attribution`

### Task 2: Create clan-integration.md (AC: #3)
- [ ] Create new file `packages/docs/src/content/docs/concepts/clan-integration.md`
- [ ] Document what clan manages:
  - Machine registry (`clan.machines.*`)
  - Inventory system (`clan.inventory.*`)
  - Vars/generators (tier 1 secrets)
  - Deployment tooling (`clan machines install/update`)
  - Service orchestration (multi-machine coordination)
- [ ] Document what clan does NOT manage (with table):
  - Cloud infrastructure → Terranix/Terraform
  - User environments → Home-Manager
  - User secrets → sops-nix (tier 2)
  - System configuration → NixOS/nix-darwin
  - Nixpkgs overlays → Flake-level
- [ ] Document two-tier secrets architecture:
  - Tier 1 (clan vars): System-level, generated
  - Tier 2 (sops-nix): User-level, manually created
- [ ] Include mental model: "Kubernetes for NixOS"
- [ ] Link to https://clan.lol/
- [ ] Commit: `docs(concepts): create clan-integration.md with clear boundaries`

### Task 3: Rewrite nix-config-architecture.md (AC: #4)
- [ ] Read current `packages/docs/src/content/docs/concepts/nix-config-architecture.md`
- [ ] Replace "three-layer architecture" with dendritic pattern description
- [ ] Reference new dendritic-architecture.md for details
- [ ] Reference new clan-integration.md for deployment
- [ ] Update all directory paths from `configurations/` to `modules/`
- [ ] Remove all `nixos-unified` references
- [ ] Update architecture diagram if present
- [ ] Commit: `docs(concepts): rewrite nix-config-architecture.md for dendritic pattern`

### Task 4: Rewrite repository-structure.md (AC: #5)
- [ ] Read current `packages/docs/src/content/docs/reference/repository-structure.md`
- [ ] Document correct `modules/` directory structure:
  ```
  modules/
  ├── clan/           # Clan integration
  ├── darwin/         # nix-darwin modules (per-aspect)
  ├── home/           # home-manager modules (per-aspect)
  ├── machines/       # Machine-specific configs
  │   ├── darwin/     # Darwin hosts
  │   └── nixos/      # NixOS hosts
  ├── nixos/          # NixOS modules (per-aspect)
  ├── system/         # Cross-platform system modules
  └── terranix/       # Cloud infrastructure
  ```
- [ ] Remove all `configurations/` references
- [ ] Remove obsolete hosts (stibnite-nixos, blackphos-nixos, orb-nixos)
- [ ] Update machine list to current fleet
- [ ] Commit: `docs(reference): rewrite repository-structure.md with correct paths`

### Task 5: Update index.mdx landing page (AC: #6)
- [ ] Read current `packages/docs/src/content/docs/index.mdx`
- [ ] Remove "nixos-unified directory-based autowiring" tagline
- [ ] Update to dendritic flake-parts + clan-core description
- [ ] Update feature list to reflect current architecture
- [ ] Commit: `docs: update index.mdx landing page for dendritic+clan`

### Task 6: Handle obsolete concepts (AC: #7)
- [ ] Read `packages/docs/src/content/docs/concepts/understanding-autowiring.md`
- [ ] Delete or redirect to dendritic-architecture.md
- [ ] Read `packages/docs/src/content/docs/concepts/multi-user-patterns.md`
- [ ] Update paths from `configurations/` to `modules/machines/`
- [ ] Preserve valid multi-user concepts, fix incorrect paths
- [ ] Update concepts/index.md to reflect changes
- [ ] Commit: `docs(concepts): remove nixos-unified autowiring, update multi-user paths`

### Task 7: Update about/credits.md (AC: #1, #2)
- [ ] Read current `packages/docs/src/content/docs/about/credits.md`
- [ ] Update "Primary framework" from nixos-unified to dendritic flake-parts
- [ ] Add credits for dendritic pattern creators
- [ ] Add credits for clan-core
- [ ] Commit: `docs(about): update credits.md for dendritic+clan architecture`

### Task 8: Verify zero deprecated references (AC: #8)
- [ ] Run `rg "nixos-unified" packages/docs/src/content/docs/`
- [ ] Run `rg "configurations/" packages/docs/src/content/docs/`
- [ ] Run `rg "stibnite-nixos|blackphos-nixos|orb-nixos" packages/docs/`
- [ ] Fix any remaining deprecated references
- [ ] Run Starlight build validation
- [ ] Commit any final fixes

### Task 9: Update development context docs (AC: #4, #8)
- [ ] Read `packages/docs/src/content/docs/development/context/index.md`
- [ ] Update "target state" language to "current state" (migration complete)
- [ ] Update domain-model.md paths
- [ ] Update goals-and-objectives.md to reflect achieved objectives
- [ ] Update project-scope.md for current state
- [ ] Commit: `docs(development): update context docs for migration completion`

## Dev Notes

### Architecture Pattern: Dendritic Flake-Parts

Our infrastructure uses the **dendritic flake-parts pattern**, which organizes Nix configurations by feature (aspect) rather than host.

**Required Attribution Block (MUST INCLUDE in dendritic-architecture.md):**

```markdown
## Architectural Foundation: Dendritic Flake-Parts Pattern

### Credits

- **[flake-parts](https://flake.parts)**: Robert Hensing and Hercules CI -
  modular flake framework that enables the pattern
- **[dendritic pattern](https://github.com/mightyiam/dendritic)**: Shahar "Dawn" Or
  (@mightyiam) - pattern definition and documentation
- **[import-tree](https://github.com/vic/import-tree)**: Victor Borja (@vic) -
  automatic module discovery mechanism
- **[dendrix](https://vic.github.io/dendrix/Dendritic.html)**: Victor Borja (@vic) -
  community ecosystem and comprehensive documentation

### Key Principle

Every Nix file is a flake-parts module. Files are organized by **aspect** (feature)
rather than by host, enabling cross-cutting configuration that spans NixOS,
nix-darwin, and home-manager from a single location.
```

### Clan Boundaries Documentation

**Required Clan Scope Definition (MUST INCLUDE in clan-integration.md):**

```markdown
## Clan: Multi-Machine Coordination

[Clan](https://clan.lol/) is our multi-machine coordination and deployment framework.
It orchestrates deployments but does not replace underlying configuration tools.

### What Clan Manages

- **Machine Registry**: Machine definitions and deployment targets
- **Inventory System**: Service instance assignments and role-based deployment
- **Vars/Generators**: System-level secrets (SSH keys, zerotier identities)
- **Deployment**: `clan machines install/update` commands
- **Service Orchestration**: Multi-machine service coordination

### What Clan Does NOT Manage

| Capability | Managed By | Notes |
|------------|------------|-------|
| Cloud infrastructure | Terranix/Terraform | Clan deploys TO infrastructure |
| User environments | Home-Manager | Deployed WITH clan, not BY clan |
| User secrets | sops-nix | Tier 2 secrets, manually created |
| System configuration | NixOS/nix-darwin | Clan imports configs, doesn't define them |
| Nixpkgs overlays | Flake-level | Outside clan scope |

### Two-Tier Secrets Architecture

- **Tier 1 (clan vars)**: System-level, generated (SSH keys, machine identities)
- **Tier 2 (sops-nix)**: User-level, manually created (API keys, tokens)

### Mental Model

Think of clan as "Kubernetes for NixOS" - it coordinates deployment across machines
but doesn't replace the underlying NixOS module system or home-manager.
```

### Current Directory Structure (What Docs Should Reflect)

```
modules/
├── clan/           # Clan integration (machine registry, inventory, services)
├── darwin/         # nix-darwin modules (per-aspect)
├── home/           # home-manager modules (per-aspect)
├── machines/       # Machine-specific configs
│   ├── darwin/     # Darwin hosts (stibnite, blackphos, rosegold, argentum)
│   └── nixos/      # NixOS hosts (cinnabar, electrum, galena, scheelite)
├── nixos/          # NixOS modules (per-aspect)
├── system/         # Cross-platform system modules
└── terranix/       # Cloud infrastructure (GCP, Hetzner)
```

### Deprecated Structure (Remove All References)

```
configurations/     # OLD - does not exist
├── darwin/         # OLD - now modules/machines/darwin/
└── nixos/          # OLD - now modules/machines/nixos/
```

### Key Dendritic Module Pattern

```nix
# modules/home/tools/bottom.nix - Example dendritic module
{ ... }:
{
  flake.modules.homeManager.tools-bottom = { ... }: {
    programs.bottom.enable = true;
  };
}
```

### Project Structure Notes

**Starlight Docs Location:** `packages/docs/src/content/docs/`

**Files to Create:**
1. `concepts/dendritic-architecture.md` (NEW)
2. `concepts/clan-integration.md` (NEW)

**Files to Rewrite:**
1. `concepts/nix-config-architecture.md` (CRITICAL - foundation)
2. `reference/repository-structure.md` (CRITICAL - paths)
3. `index.mdx` (CRITICAL - entry point)
4. `concepts/understanding-autowiring.md` (DELETE/REDIRECT)
5. `concepts/multi-user-patterns.md` (UPDATE paths)
6. `about/credits.md` (UPDATE framework credits)
7. Development context docs (UPDATE target→current language)

### Learnings from Previous Story

**From Story 8.1 (Status: done)**

- **Staleness Distribution**: 22 current, 21 stale, 9 obsolete, 7 missing topics
- **Critical Path Items**: 6 files block Stories 8.2-8.4
- **Most Common Issues**:
  - `nixos-unified` references (80+ occurrences across 35+ files)
  - `configurations/` paths (60+ occurrences across 20+ files)
  - Bitwarden/3-tier secrets pattern (14 occurrences)
- **Effort Estimate**: 34-38 hours for Story 8.2
- **Execution Priority** (from audit):
  1. Create `concepts/dendritic-architecture.md` FIRST (establishes terminology)
  2. Rewrite `concepts/nix-config-architecture.md` to reference new doc
  3. Update `index.mdx` landing page
  4. Rewrite `reference/repository-structure.md`
  5. Handle obsolete docs (autowiring, multi-user-patterns)
  6. Verify zero deprecated references remain
- **Missing Documentation Gaps**:
  - Dendritic flake-parts architecture (NEW)
  - Clan-core integration (NEW)
  - Two-tier secrets pattern (for Story 8.4)

[Source: docs/notes/development/work-items/story-8.1-audit-results.md]
[Source: docs/notes/development/work-items/8-1-audit-existing-starlight-docs-for-staleness.md#Dev-Agent-Record]

### External References to Link

- https://github.com/mightyiam/dendritic - Pattern source
- https://vic.github.io/dendrix/Dendritic.html - Comprehensive docs
- https://flake.parts - Foundation framework
- https://clan.lol/ - Clan documentation

### Constraints

1. **Proper attribution required** - Do not claim invention of dendritic pattern
2. **Clear clan boundaries** - Document what clan does NOT manage
3. **Zero deprecated references** - No nixos-unified, configurations/, or old patterns
4. **Consistent terminology** - Use "dendritic pattern" not "our pattern"
5. **Atomic commits** - One commit per file updated

### References

- [Epic 8: docs/notes/development/epics/epic-8-documentation-alignment.md]
- [Story 8.1 Audit Results: docs/notes/development/work-items/story-8.1-audit-results.md]
- [Architecture Index: docs/notes/development/architecture/index.md]
- [Clan Boundaries Research: docs/notes/research/clan-boundaries-research.md]
- [Starlight Docs: packages/docs/src/content/docs/]

### NFR Coverage

| NFR | Coverage |
|-----|----------|
| NFR-8.1 | Zero references to deprecated architecture (verified in Task 8) |
| NFR-8.2 | Testability - commands should work (build validation) |

### Estimated Effort

**34-38 hours** (from Story 8.1 audit)

- Task 1 (dendritic-architecture.md): 4h
- Task 2 (clan-integration.md): 4h
- Task 3 (nix-config-architecture.md rewrite): 4h+
- Task 4 (repository-structure.md rewrite): 4h+
- Task 5 (index.mdx update): 3h
- Task 6 (obsolete concepts): 4h
- Task 7 (credits.md): 1h
- Task 8 (verification): 2h
- Task 9 (development context): 6h

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
- Story file created from Epic 8 Story 8.2 specification
- Incorporated detailed acceptance criteria from user context
- 8 acceptance criteria mapped to 9 task groups with 47 subtasks
- Required attribution blocks documented in Dev Notes
- Required clan boundaries documentation included
- Execution priority from Story 8.1 audit incorporated
- Learnings from Story 8.1 extracted and documented
- External references listed for linking
- Constraints documented (attribution, boundaries, zero deprecated refs)
- Estimated effort: 34-38 hours
