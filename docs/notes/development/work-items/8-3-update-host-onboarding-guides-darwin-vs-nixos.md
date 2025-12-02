# Story 8.3: Update Host Onboarding Guides (Darwin vs NixOS)

Status: drafted

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

- [ ] Read current file and identify all deprecated patterns
- [ ] Create new document structure with darwin vs NixOS separation
- [ ] **Darwin onboarding section:**
  - [ ] Document prerequisites (Nix installer, flakes, Xcode CLT)
  - [ ] Document repository setup and direnv activation
  - [ ] Document build validation with `nix build` command
  - [ ] Document `darwin-rebuild switch` deployment
  - [ ] Document zerotier homebrew cask and network join
  - [ ] Document sops-nix age key setup (Tier 2 secrets)
- [ ] **NixOS VPS onboarding section:**
  - [ ] Document prerequisites (terraform, cloud credentials)
  - [ ] Document `nix run .#terraform` infrastructure provisioning
  - [ ] Document `clan machines install` workflow
  - [ ] Document zerotier inventory configuration
  - [ ] Document clan vars (Tier 1 secrets)
- [ ] **Common sections:**
  - [ ] Add dendritic module structure overview with links
  - [ ] Add clan inventory integration explanation
  - [ ] Add two-tier secrets architecture summary
- [ ] Remove all Bitwarden, 3-tier, `configurations/` references
- [ ] Update examples to use current machine fleet (stibnite, cinnabar, etc.)
- [ ] Verify all internal links work
- [ ] Commit: `docs(guides): rewrite host-onboarding.md for darwin vs nixos`

### Task 2: Update guides/home-manager-onboarding.md (AC: #12, #14, #16)

- [ ] Read current file and identify deprecated paths
- [ ] Replace `configurations/home/` with `modules/machines/` and `modules/home/users/`
- [ ] Replace Bitwarden workflow with sops-nix age key workflow
- [ ] Replace `sopsIdentifier` pattern with current sops.secrets pattern
- [ ] Reference dendritic aggregates for user configuration
- [ ] Link to dendritic-architecture.md for module pattern explanation
- [ ] Remove all deprecated references
- [ ] Update examples with current usernames (crs58, raquel, cameron)
- [ ] Commit: `docs(guides): update home-manager-onboarding.md paths and patterns`

### Task 3: Update guides/getting-started.md (AC: #12, #14, #16)

- [ ] Read current file and identify deprecated sections
- [ ] Replace "Understanding the structure" section:
  - [ ] Remove `configurations/` directory structure
  - [ ] Add `modules/` dendritic structure
  - [ ] Remove "directory-based autowiring" mention
  - [ ] Reference dendritic-architecture.md
- [ ] Update "Next steps" links section:
  - [ ] Replace "Understanding Autowiring" with dendritic-architecture.md link
  - [ ] Add clan-integration.md link
- [ ] Verify all linked pages exist
- [ ] Commit: `docs(guides): update getting-started.md for dendritic pattern`

### Task 4: Update guides/index.md (AC: #14)

- [ ] Add new guide listings:
  - [ ] Zerotier setup guide (if created)
  - [ ] GCP deployment guide (if created in future)
  - [ ] Clan integration reference
- [ ] Update existing guide descriptions
- [ ] Commit: `docs(guides): update index.md navigation listings`

### Task 5: Verify zero deprecated references (AC: #16)

- [ ] Run `rg "nixos-unified" packages/docs/src/content/docs/guides/`
- [ ] Run `rg "configurations/" packages/docs/src/content/docs/guides/`
- [ ] Run `rg "bitwarden|3-tier" packages/docs/src/content/docs/guides/`
- [ ] Fix any remaining deprecated references
- [ ] Run Starlight build validation: `nix build .#docs`
- [ ] Commit any final fixes

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
- [ ] No references to `configurations/darwin/`, `configurations/nixos/`, `configurations/home/`
- [ ] Darwin examples use `darwin-rebuild` and reference `modules/machines/darwin/`
- [ ] NixOS examples use `clan machines` commands
- [ ] Two-tier secrets documented with Tier 1/Tier 2 labels
- [ ] Zerotier integrated into both darwin and NixOS paths
- [ ] All internal links work (to 8.2 docs, between guides)
- [ ] Commands are copy-paste ready with real hostnames

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

{{agent_model_name_version}}

### Debug Log References

### Completion Notes List

### File List

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
