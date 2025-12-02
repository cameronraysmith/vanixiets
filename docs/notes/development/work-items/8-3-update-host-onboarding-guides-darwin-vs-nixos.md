# Story 8.3: Update Host Onboarding Guides (Darwin vs NixOS)

Status: review

## Story

As a new user,
I want clear onboarding documentation for my platform type,
so that I can deploy my machine using the correct workflow.

## Acceptance Criteria

### Darwin Onboarding (AC1-AC6)

1. **Prerequisites documented**: Nix installation (Determinate Systems installer), flakes enablement, required system tools
2. **Clone and setup documented**: Repository clone, direnv activation, devshell entry
3. **Build validation documented**: `nix build .#darwinConfigurations.<hostname>.system` with copy-paste examples
4. **Deployment documented**: `darwin-rebuild switch --flake .#<hostname>` with common options
5. **Zerotier integration documented**: Homebrew cask installation, network join via `zerotier-cli`, authorization flow
6. **Secrets setup documented**: Age key generation, sops-nix user secrets configuration (Tier 2)

### NixOS VPS Onboarding (AC7-AC11)

7. **Prerequisites documented**: Terraform, cloud provider credentials (Hetzner/GCP), age key for decryption
8. **Infrastructure provisioning documented**: `nix run .#terraform` with toggle patterns for cost control
9. **Clan installation documented**: `clan machines install <hostname> --target-host root@<ip>` workflow
10. **Zerotier mesh documented**: Automatic peer configuration via clan inventory, controller/peer pattern
11. **Secrets deployment documented**: Clan vars generate and `/run/secrets/` deployment (Tier 1)

### Common Sections (AC12-AC15)

12. **Dendritic module structure explained**: Reference to `dendritic-architecture.md` with practical path examples
13. **Clan inventory integration documented**: How machine configs integrate with clan.machines and inventory
14. **Architecture documentation linked**: Cross-references to Story 8.2 docs (dendritic-architecture.md, clan-integration.md)
15. **Two-tier secrets architecture explained**: Clear differentiation between Tier 1 (clan vars) and Tier 2 (sops-nix)

### Documentation Quality (AC16-AC18)

16. **Zero deprecated references**: No `configurations/`, `nixos-unified`, `bitwarden`, `3-tier` mentions
17. **Commands are copy-paste ready**: All examples use actual hostnames from current fleet
18. **Internal links verified**: All cross-references to other docs work correctly

## Tasks / Subtasks

### Task 1: Rewrite guides/host-onboarding.md (AC: #1-6, #7-11, #12-15)

- [x] Read current file and identify all deprecated patterns
- [x] Create new document structure with darwin vs NixOS separation
- [x] **Darwin onboarding section:**
  - [x] Document prerequisites (Nix installer, flakes, Xcode CLT)
  - [x] Document repository setup and direnv activation
  - [x] Document build validation with `nix build` command
  - [x] Document `darwin-rebuild switch` deployment
  - [x] Document zerotier homebrew cask and network join
  - [x] Document sops-nix age key setup (Tier 2 secrets)
- [x] **NixOS VPS onboarding section:**
  - [x] Document prerequisites (terraform, cloud credentials)
  - [x] Document `nix run .#terraform` infrastructure provisioning
  - [x] Document `clan machines install` workflow
  - [x] Document zerotier inventory configuration
  - [x] Document clan vars (Tier 1 secrets)
- [x] **Common sections:**
  - [x] Add dendritic module structure overview with links
  - [x] Add clan inventory integration explanation
  - [x] Add two-tier secrets architecture summary
- [x] Remove all Bitwarden, 3-tier, `configurations/` references
- [x] Update examples to use current machine fleet (stibnite, cinnabar, etc.)
- [x] Verify all internal links work
- [x] Commit: `docs(guides): rewrite host-onboarding.md for darwin vs nixos`

### Task 2: Update guides/home-manager-onboarding.md (AC: #12, #14, #16)

- [x] Read current file and identify deprecated paths
- [x] Replace `configurations/home/` with `modules/machines/` and `modules/home/users/`
- [x] Replace Bitwarden workflow with sops-nix age key workflow
- [x] Replace `sopsIdentifier` pattern with current sops.secrets pattern
- [x] Reference dendritic aggregates for user configuration
- [x] Link to dendritic-architecture.md for module pattern explanation
- [x] Remove all deprecated references
- [x] Update examples with current usernames (crs58, raquel, cameron)
- [x] Commit: `docs(guides): update home-manager-onboarding.md paths and patterns`

### Task 3: Update guides/getting-started.md (AC: #12, #14, #16)

- [x] Read current file and identify deprecated sections
- [x] Replace "Understanding the structure" section:
  - [x] Remove `configurations/` directory structure
  - [x] Add `modules/` dendritic structure
  - [x] Remove "directory-based autowiring" mention
  - [x] Reference dendritic-architecture.md
- [x] Update "Next steps" links section:
  - [x] Replace "Understanding Autowiring" with dendritic-architecture.md link
  - [x] Add clan-integration.md link
- [x] Verify all linked pages exist
- [x] Commit: `docs(guides): update getting-started.md for dendritic pattern`

### Task 4: Update guides/index.md (AC: #14)

- [x] Add new guide listings:
  - [x] Zerotier setup guide (if created) - N/A, not created
  - [x] GCP deployment guide (if created in future) - N/A, not created
  - [x] Clan integration reference - Added via Architecture References section
- [x] Update existing guide descriptions
- [x] Commit: `docs(guides): update index.md navigation listings`

### Task 5: Verify zero deprecated references (AC: #16)

- [x] Run `rg "nixos-unified" packages/docs/src/content/docs/guides/` - Zero matches
- [x] Run `rg "configurations/" packages/docs/src/content/docs/guides/` - Only intentional reference explaining what NOT to use
- [x] Run `rg "bitwarden|3-tier" packages/docs/src/content/docs/guides/` - Zero matches in updated files (secrets-management.md is Story 8.4 scope)
- [x] Fix any remaining deprecated references - None needed
- [x] Run Starlight build validation: `bun run build` - Passed, all 62 pages indexed
- [x] Link validation: `bun run linkcheck` - All internal links valid

## Dev Notes

### Key Architectural References (From Story 8.2)

Story 8.2 created foundational docs that this story must reference:

1. **`concepts/dendritic-architecture.md`** - Core architecture pattern
   - Core principle: Every file is a flake-parts module
   - Directory structure: `modules/` organization
   - Aggregate modules pattern
   - Auto-discovery via import-tree

2. **`concepts/clan-integration.md`** - Multi-machine coordination
   - Mental model: "Kubernetes for NixOS"
   - What clan manages vs does NOT manage
   - Two-tier secrets architecture (Tier 1: clan vars, Tier 2: sops-nix)
   - Deployment commands

### Platform Workflows

**Darwin Deployment Path:**
```bash
# Build validation
nix build .#darwinConfigurations.<hostname>.system

# Deployment
darwin-rebuild switch --flake .#<hostname>

# Zerotier (via Homebrew)
brew install --cask zerotier-one
sudo zerotier-cli join <network-id>
```

**NixOS/Clan Deployment Path:**
```bash
# Infrastructure provisioning (new VMs)
nix run .#terraform

# Clan installation (new machine)
clan machines install <hostname> --target-host root@<ip>

# Clan update (existing machine)
clan machines update <hostname>

# Zerotier (automatic via clan inventory)
# Configured in modules/clan/inventory/services/zerotier.nix
```

### Two-Tier Secrets Architecture

**Tier 1: Clan Vars (System-Level)**
- Generated automatically via `clan vars generate`
- SSH host keys, zerotier identities, LUKS passphrases
- Deployed to `/run/secrets/` via clan deployment
- Machine-specific, not user-specific

**Tier 2: sops-nix (User-Level)**
- Manually created and encrypted via `sops` CLI
- API keys, tokens, personal credentials
- Configured in home-manager via `sops.secrets.*`
- User-specific secrets

### Terminology Consistency

| Use This | Not This |
|----------|----------|
| Dendritic flake-parts pattern | nixos-unified, directory-based autowiring |
| Module aggregates | autowiring |
| Aspect-based organization | host-centric |
| Clan inventory | manual service configuration |
| Tier 1/Tier 2 secrets | 3-tier key architecture |
| `modules/machines/darwin/` | `configurations/darwin/` |
| `modules/machines/nixos/` | `configurations/nixos/` |

### Current Machine Fleet (Use in Examples)

**Darwin Hosts:**
- stibnite (crs58's workstation)
- blackphos (raquel's workstation)
- rosegold (janettesmith's workstation)
- argentum (christophersmith's workstation)

**NixOS Hosts:**
- cinnabar (Hetzner VPS, zerotier controller)
- electrum (Hetzner VPS, zerotier peer)
- galena (GCP, CPU-only, togglable)
- scheelite (GCP, GPU T4, togglable)

### Project Structure Notes

**Starlight Docs Location:** `packages/docs/src/content/docs/guides/`

**Files to Update:**
1. `host-onboarding.md` (COMPLETE REWRITE - Critical priority)
2. `home-manager-onboarding.md` (PATH + WORKFLOW UPDATES - High priority)
3. `getting-started.md` (STRUCTURE SECTION UPDATE - High priority)
4. `index.md` (NAVIGATION UPDATE - Medium priority)

### Verification Checklist

Before marking complete:
- [x] No references to `configurations/darwin/`, `configurations/nixos/`, `configurations/home/`
- [x] Darwin examples use `darwin-rebuild` and reference `modules/machines/darwin/`
- [x] NixOS examples use `clan machines` commands
- [x] Two-tier secrets documented with Tier 1/Tier 2 labels
- [x] Zerotier integrated into both darwin and NixOS paths
- [x] All internal links work (to 8.2 docs, between guides)
- [x] Commands are copy-paste ready with real hostnames

### Learnings from Previous Story

**From Story 8.2 (Status: done)**

- **New Files Created**:
  - `concepts/dendritic-architecture.md` - Core architecture doc, link frequently
  - `concepts/clan-integration.md` - Clan boundaries doc, link for deployment context
- **Files Rewritten**:
  - `nix-config-architecture.md` - Updated architecture, don't duplicate content
  - `repository-structure.md` - Correct paths, reference for directory layout
  - `multi-user-patterns.md` - Updated paths, reference for user patterns
- **Files Deleted**:
  - `understanding-autowiring.md` - nixos-unified specific, don't link to it
- **Pattern Established**:
  - Zero tolerance for deprecated patterns (`nixos-unified`, `configurations/`, `bitwarden`)
  - Atomic commits per file
  - Proper attribution when referencing external patterns

[Source: docs/notes/development/work-items/8-2-update-architecture-and-patterns-documentation.md]

### References

- [Epic 8: docs/notes/development/epics/epic-8-documentation-alignment.md]
- [Story 8.1 Audit: docs/notes/development/work-items/story-8.1-audit-results.md]
- [Story 8.2 Architecture Docs: docs/notes/development/work-items/8-2-update-architecture-and-patterns-documentation.md]
- [Dendritic Architecture: packages/docs/src/content/docs/concepts/dendritic-architecture.md]
- [Clan Integration: packages/docs/src/content/docs/concepts/clan-integration.md]

### Constraints

1. **Reference Story 8.2 docs** - Link to dendritic-architecture.md and clan-integration.md
2. **Platform differentiation** - Clear darwin vs NixOS sections
3. **Two-tier secrets** - Replace all 3-tier/Bitwarden references
4. **Zero deprecated paths** - No `configurations/` references
5. **Atomic commits** - One commit per file
6. **Practical focus** - Commands should be copy-paste ready

### NFR Coverage

| NFR | Coverage |
|-----|----------|
| NFR-8.1 | Zero references to deprecated architecture |
| NFR-8.2 | Testability - commands should work |
| NFR-8.3 | Darwin vs NixOS differentiation |

### Estimated Effort

**18-20 hours** (from Story 8.1 audit)

- Task 1 (host-onboarding.md rewrite): 10-12h (complete rewrite)
- Task 2 (home-manager-onboarding.md): 3h
- Task 3 (getting-started.md): 2h
- Task 4 (index.md): 1h
- Task 5 (verification): 2h

## Dev Agent Record

### Context Reference

<!-- Path(s) to story context XML will be added here by context workflow -->

### Agent Model Used

claude-opus-4-5-20251101

### Debug Log References

### Completion Notes List

1. **host-onboarding.md complete rewrite**: 640 lines → platform-differentiated with darwin vs NixOS sections
2. **home-manager-onboarding.md rewrite**: 462 lines → portable user modules, aggregates, sops-nix patterns
3. **getting-started.md updated**: Structure section replaced with dendritic pattern, links updated
4. **index.md updated**: Navigation listings updated, Architecture References section added
5. **Validation passed**: Zero deprecated patterns, all internal links valid, docs build successful

### File List

| File | Action | Lines | Key Changes |
|------|--------|-------|-------------|
| `packages/docs/src/content/docs/guides/host-onboarding.md` | Rewritten | 640 | Platform differentiation (darwin vs NixOS), two-tier secrets, clan integration |
| `packages/docs/src/content/docs/guides/home-manager-onboarding.md` | Rewritten | 462 | Portable user modules, aggregates, sops-nix age key workflow |
| `packages/docs/src/content/docs/guides/getting-started.md` | Updated | 259 | Dendritic structure section, updated links |
| `packages/docs/src/content/docs/guides/index.md` | Updated | 30 | Navigation descriptions, Architecture References section |
| `docs/notes/development/sprint-status.yaml` | Updated | - | story-8-3: drafted → in-progress → review |

### Commits Created

1. `32ce2ce1` - docs(guides): rewrite host-onboarding.md for darwin vs nixos
2. `33d3a7cb` - docs(guides): update home-manager-onboarding.md paths and patterns
3. `ed5aac22` - docs(guides): update getting-started.md for dendritic pattern
4. `b8d59d2b` - docs(guides): update index.md navigation listings

## Change Log

**2025-12-01 (Story Drafted)**:
- Story file created from Epic 8 Story 8.3 specification
- Incorporated detailed acceptance criteria from user-provided context
- 18 acceptance criteria mapped to 5 task groups
- Platform workflows documented (darwin vs NixOS deployment paths)
- Two-tier secrets architecture included in Dev Notes
- Learnings from Story 8.2 incorporated
- Terminology consistency table added
- Current machine fleet documented for examples
- Verification checklist included
- Estimated effort: 18-20 hours

**2025-12-01 (Story Implementation)**:
- All 5 tasks completed (100%)
- 4 guide files updated with 4 atomic commits
- Platform differentiation achieved (darwin vs NixOS workflows)
- Two-tier secrets documented (Tier 1: clan vars, Tier 2: sops-nix)
- Zero deprecated references in target files
- All internal links validated
- Docs build successful (62 pages indexed)
- Status: review
