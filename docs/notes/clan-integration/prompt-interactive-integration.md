# Interactive dendritic + clan migration prompt for Claude Code

Use this prompt to initiate an interactive dendritic + clan migration session.

---

# Dendritic + clan migration interactive guide

## Context and objectives

I want to migrate my nixos-unified based nix-config repository at `~/projects/nix-workspace/nix-config` to the dendritic flake-parts pattern with clan-core integration.
This migration will transition all hosts (VPS + darwin machines) from nixos-unified to dendritic's `flake.modules.*` namespace with clan's multi-machine coordination and vars management.

**Key infrastructure**:
- New VPS: cinnabar (Hetzner Cloud, zerotier controller, core services)
- Darwin hosts: blackphos → rosegold → argentum → stibnite (progressive migration)
- Test environment: test-clan/ (validation before production)

## Your role

Guide me through a progressive, validation-first migration to dendritic + clan.
Start with test-clan validation (Phase 0), optionally darwin validation (Phase 0.5), deploy VPS infrastructure (Phase 1), then migrate darwin hosts progressively (Phases 2-5).
Prioritize safety (test first, parallel environment, preserve rollback), education (explain dendritic and clan concepts), and interactivity (pause for my input and questions).

## Required reading for you

Before beginning, read and internalize these documents I've prepared:

**Integration documentation** (start here, in order):

1. `~/projects/nix-workspace/nix-config/docs/notes/clan-integration/README.md` - Overview and navigation
2. `~/projects/nix-workspace/nix-config/docs/notes/clan-integration/00-integration-plan.md` - Strategic analysis, architecture, all phases overview
3. `~/projects/nix-workspace/nix-config/docs/notes/clan-integration/01-phase-0-validation.md` - Phase 0 (test-clan) + Phase 0.5 (darwin validation)
4. `~/projects/nix-workspace/nix-config/docs/notes/clan-integration/02-phase-1-vps-deployment.md` - Phase 1 (cinnabar VPS with zerotier controller)
5. `~/projects/nix-workspace/nix-config/docs/notes/clan-integration/03-phase-2-blackphos-guide.md` - Phase 2 (first darwin host)
6. `~/projects/nix-workspace/nix-config/docs/notes/clan-integration/04-migration-assessment.md` - Post-migration evaluation

**My development preferences** (follow these strictly):

- `~/.claude/commands/preferences/preferences.md` - Strict preferences (lowercase, no emojis, kebab-case)
- `~/.claude/commands/preferences/general-practices.md` - Development practices
- `~/.claude/commands/preferences/git-version-control.md` - Git workflow (atomic commits)
- `~/.claude/commands/preferences/nix-development.md` - Nix-specific patterns

**Current repository structure**:

- `~/projects/nix-workspace/nix-config/flake.nix` - Current flake structure
- `~/projects/nix-workspace/nix-config/modules/flake-parts/` - Auto-wired flake-parts modules
- `~/projects/nix-workspace/nix-config/configurations/{darwin,nixos}/` - Host-specific configurations via nixos-unified autowire
- `~/projects/nix-workspace/nix-config/modules/{darwin,home,nixos}/` - Modular configurations
- `~/projects/nix-workspace/nix-config/secrets/` - SOPS-based secrets management (agenix + sops-nix)

**Clan reference repositories**:

- `~/projects/nix-workspace/clan-core/` - Monorepo with modules, CLI, documentation
- `~/projects/nix-workspace/clan-core/docs/site/` - Official Clan documentation
- `~/projects/nix-workspace/clan-core/clanServices/` - Example Clan service implementations
- `~/projects/nix-workspace/clan-infra/` - Production infrastructure examples (clan + flake-parts)
- `~/projects/nix-workspace/jfly-clan-snow/` - Darwin + clan example

**Dendritic pattern references**:

- `~/projects/nix-workspace/dendritic-flake-parts/` - Canonical pattern
- `~/projects/nix-workspace/drupol-dendritic-infra/` - Comprehensive production example
- `~/projects/nix-workspace/gaetanlepage-dendritic-nix-config/` - Another production example

## Migration phases (validation-first approach)

Guide me through these phases progressively, with validation gates between each:

### Phase 0: Test-clan validation (REQUIRED FIRST)

**Objective**: Validate dendritic + clan integration on NixOS in isolated test environment

**Why first**: De-risks entire migration by proving architectural combination works before infrastructure commitment

**Location**: `~/projects/nix-workspace/test-clan/` (separate repository)

**Tasks**:

1. Create test-clan/ repository with minimal dendritic + clan setup
2. Add clan-core, import-tree, flake-parts inputs
3. Create dendritic module structure: `modules/{base,nixos,hosts}/`
4. Configure single NixOS test VM using dendritic pattern
5. Add clan inventory with test-vm machine
6. Configure minimal clan service (emergency-access or sshd)
7. Generate clan vars: `nix run nixpkgs#clan-cli -- vars generate test-vm`
8. Build and test in VM: `nix run .#clan-cli -- vms run test-vm`
9. Document findings, patterns, and any compromises needed
10. Validate: dendritic pattern works with clan, understand integration points

**Success criteria**:

- [ ] Test-clan repository builds successfully
- [ ] import-tree discovers modules correctly
- [ ] Clan inventory configured properly
- [ ] VM boots and activates successfully
- [ ] Clan vars generation works
- [ ] Understand dendritic + clan integration points
- [ ] Pattern decisions documented for Phase 1

**Validation gate**: DO NOT proceed to Phase 1 until test-clan validates the approach

**Detailed guide**: Follow `01-phase-0-validation.md` steps 1-21

### Phase 0.5: Darwin validation (STRONGLY RECOMMENDED)

**Objective**: Validate darwin + clan + dendritic integration before production darwin deployment

**Why critical**: First darwin + clan test would otherwise be Phase 2 (blackphos production), which is risky

**Location**: test-clan/ with darwin VM or lima/UTM test environment

**Tasks**:

1. Add darwinConfiguration to test-clan
2. Create darwin-specific dendritic modules
3. Test darwin + clan service integration
4. Validate home-manager + clan combination
5. Test rollback procedures in safe environment
6. Document darwin-specific patterns and issues

**Success criteria**:

- [ ] Darwin test configuration builds
- [ ] Clan services work on darwin
- [ ] home-manager integrates correctly
- [ ] Rollback procedures tested and validated
- [ ] Darwin-specific patterns documented

**Validation gate**: Strongly recommended before Phase 2 (blackphos)

**Detailed guide**: See `01-phase-0-validation.md` section "Phase 0.5: Darwin validation"

### Phase 1: VPS infrastructure (cinnabar)

**Objective**: Deploy always-on infrastructure with zerotier controller on NixOS

**Why before darwin**: Validates dendritic + clan on NixOS (clan's native platform) and provides stable controller for darwin hosts

**Location**: Hetzner Cloud VPS (cinnabar, CX53, ~€24/month)

**Tasks**:

1. Return to `~/projects/nix-workspace/nix-config/`
2. Add all required flake inputs (clan-core, import-tree, terranix, disko, srvos)
3. Create dendritic modules/ directory structure (parallel to configurations/)
4. Initialize clan secrets (age keys, admin group)
5. Setup terraform/terranix for Hetzner Cloud provisioning
6. Create cinnabar host configuration with disko for LUKS encryption
7. Configure zerotier controller role on cinnabar
8. Deploy VPS via terraform + clan machines install
9. Validate zerotier controller operational
10. Keep existing configurations/ active (darwin hosts unaffected)

**Success criteria**:

- [ ] Flake evaluates with all new inputs
- [ ] Terranix generates valid terraform
- [ ] Hetzner Cloud VPS provisioned
- [ ] NixOS installed on cinnabar with LUKS encryption
- [ ] Zerotier controller operational
- [ ] SSH access functional (CA certificates)
- [ ] Emergency access configured
- [ ] Clan vars deployed correctly
- [ ] Existing darwin configs still build

**Validation gate**: Monitor cinnabar stability for 1-2 weeks before Phase 2

**Detailed guide**: Follow `02-phase-1-vps-deployment.md` steps 1-21

### Phase 2: First darwin host (blackphos)

**Objective**: Migrate first darwin machine, validate darwin + clan integration, establish darwin patterns

**Prerequisites**: Phase 1 complete (cinnabar operational), Phase 0.5 recommended

**Tasks**:

1. Create darwin-specific dendritic modules: `modules/{base,darwin,shell,dev}/`
2. Create blackphos host configuration: `modules/hosts/blackphos/default.nix`
3. Configure blackphos as zerotier peer (connects to cinnabar controller)
4. Add blackphos to clan inventory
5. Generate clan vars for blackphos
6. Build: `nix build .#darwinConfigurations.blackphos.system`
7. Deploy: `darwin-rebuild switch --flake .#blackphos`
8. Validate zerotier peer connects to controller
9. Test cinnabar ↔ blackphos network connectivity
10. Verify all functionality preserved (no regressions)

**Success criteria**:

- [ ] blackphos builds with dendritic + clan
- [ ] All functionality preserved
- [ ] Zerotier peer connects to cinnabar controller
- [ ] SSH via zerotier network works
- [ ] Secrets deployed via clan vars
- [ ] Stable for 1-2 weeks
- [ ] Darwin patterns documented for reuse

**Validation gate**: Monitor blackphos stability before Phase 3

**Detailed guide**: Follow `03-phase-2-blackphos-guide.md` steps 1-15

### Phase 3: Second darwin host (rosegold)

**Objective**: Validate darwin patterns are reusable, test multi-darwin coordination

**Prerequisites**: Phase 2 complete and stable

**Tasks**:

1. Create rosegold host configuration (reuse blackphos patterns)
2. Add to clan inventory with zerotier peer role
3. Generate vars and deploy
4. Test 3-machine network (cinnabar ↔ blackphos ↔ rosegold)
5. Validate pattern reusability

**Success criteria**:

- [ ] rosegold operational with minimal customization
- [ ] 3-machine network functional
- [ ] Patterns validated for reuse
- [ ] Stable for 1-2 weeks

### Phase 4: Third darwin host (argentum)

**Objective**: Final validation before primary workstation

**Prerequisites**: Phase 3 complete and stable

**Tasks**:

1. Create argentum host configuration (reuse patterns)
2. Add to clan inventory
3. Deploy and test
4. Validate 4-machine zerotier network

**Success criteria**:

- [ ] argentum operational
- [ ] 4-machine coordination working
- [ ] No new issues discovered
- [ ] Ready for primary workstation
- [ ] Stable for 1-2 weeks

### Phase 5: Primary workstation (stibnite)

**Objective**: Migrate primary daily workstation (HIGHEST RISK - LAST)

**Prerequisites**: Phases 1-4 complete and stable (4-6 weeks minimum)

**Tasks**:

1. Create stibnite host configuration
2. Extra validation and testing
3. Deploy only after extensive validation
4. Keep fallback path available
5. Monitor closely

**Success criteria**:

- [ ] stibnite operational
- [ ] All daily workflows functional
- [ ] 5-machine zerotier network complete
- [ ] Productivity maintained or improved
- [ ] Stable for 1-2 weeks

### Phase 6: Cleanup

**Objective**: Remove legacy infrastructure

**Tasks**:

1. Remove nixos-unified configurations/
2. Clean up old flake inputs
3. Update documentation
4. Archive migration notes

## Your implementation approach

**Before starting each phase**:

1. Verify previous phase prerequisites met
2. Summarize what we'll do and why
3. Explain key dendritic + clan concepts we'll encounter
4. Ask for my confirmation to proceed
5. Provide estimated time and complexity
6. Remind me of rollback options

**During each phase**:

1. Show exactly what you're doing (commands, file edits)
2. Explain why each step is necessary
3. Validate results before proceeding (nix flake check, build tests)
4. Pause if errors occur - don't push through
5. Create atomic git commits for each logical change (per git-version-control.md)
6. Stage and commit immediately after each file edit

**After each phase**:

1. Summarize what we accomplished
2. Verify my understanding of key concepts
3. List success criteria and verify completion
4. Recommend stability monitoring period
5. Ask if I have questions
6. Get explicit confirmation before proceeding to next phase

## Safety requirements

**Critical constraints**:

- VALIDATE in test-clan first (Phase 0 required)
- CREATE parallel dendritic environment (modules/ alongside configurations/)
- PRESERVE nixos-unified configurations until all hosts migrated
- ALWAYS test with `nix flake check` and dry-run builds before deploying
- CREATE atomic git commits for each logical change (immediately after edit)
- ENABLE easy rollback (preserve old configs, clean git history)
- VALIDATE each step succeeds before proceeding
- MIGRATE one host at a time with stability gates (1-2 weeks)
- MONITOR stability between phases

**If anything breaks**:

1. Stop immediately
2. Show me the error
3. Explain what happened and likely cause
4. Propose troubleshooting steps or rollback to previous commit
5. Wait for my decision before acting

## Interactive teaching points

At appropriate moments, explain these concepts using examples from the repositories:

**Dendritic pattern**:

- Minimal specialArgs (only inputs/self for framework), avoid extensive pass-through
- Values shared via `config.flake.*` instead of specialArgs
- File path = feature name (clear organization)
- `flake.modules.{nixos,darwin,homeManager}.*` namespace for all modules
- Cross-cutting concerns (one module, multiple system targets)
- Examples from `~/projects/nix-workspace/drupol-dendritic-infra/`

**import-tree auto-discovery**:

- Recursively imports all .nix files in modules/
- Each file is a flake-parts module
- No manual imports needed
- Directory structure becomes module hierarchy
- How to structure for auto-discovery

**Clan inventory system**:

- Machines: Define all hosts with tags and machineClass
- Instances: Service instances with roles
- Roles: Machine membership and service-specific config
- Tags: Bulk machine assignment to roles
- Configuration hierarchy: instance-wide → role-wide → machine-specific
- Examples from `~/projects/nix-workspace/clan-infra/machines/flake-module.nix`

**Clan vars system**:

- Generator structure (prompts, script, dependencies, files)
- Secret vs public files (.path vs .value)
- share = true for cross-machine secrets
- Storage backends (SOPS default)
- Deployment to /run/secrets/
- Examples from clan services (sshd, zerotier)

**Zerotier architecture**:

- Controller role (cinnabar VPS - always-on)
- Peer role (darwin hosts)
- Network topology and security
- Why VPS controller vs darwin

**Migration strategy**:

- Validation-first (test-clan before production)
- Parallel environment (dendritic + nixos-unified coexist)
- Progressive per-host migration (VPS → darwin test hosts → primary workstation)
- Stability gates between phases (1-2 weeks)
- Rollback safety (preserve old configs, clean commits)

## Success criteria

I'll know migration is successful when:

**Phase 0**:
- ✅ Understand dendritic pattern and `flake.modules.*` namespace
- ✅ Validated dendritic + clan integration in test-clan
- ✅ import-tree auto-discovery working
- ✅ Clan inventory and vars system understood
- ✅ Pattern decisions documented

**Phase 0.5** (if completed):
- ✅ Darwin + clan integration validated
- ✅ Rollback procedures tested
- ✅ Darwin-specific patterns documented

**Phase 1**:
- ✅ Cinnabar VPS operational
- ✅ Zerotier controller functional
- ✅ Dendritic + clan validated on NixOS production
- ✅ Infrastructure stable for 1-2 weeks

**Phase 2**:
- ✅ blackphos migrated successfully
- ✅ All functionality preserved
- ✅ Zerotier peer ↔ controller connectivity
- ✅ Darwin patterns established and documented
- ✅ Stable for 1-2 weeks

**Phases 3-5**:
- ✅ All darwin hosts migrated progressively
- ✅ Multi-machine coordination functional
- ✅ Patterns validated as reusable
- ✅ Primary workstation (stibnite) fully functional
- ✅ All hosts stable

**Overall**:
- ✅ Can articulate dendritic + clan architecture
- ✅ Understand specialArgs usage (minimal framework only)
- ✅ Clan inventory managing all machines
- ✅ Zerotier network connecting all hosts
- ✅ Secrets managed via clan vars (hybrid with sops acceptable)
- ✅ Confidence in maintaining dendritic + clan infrastructure

## Flexibility and adaptation

**Adapt to my pace**:

- If I'm struggling with concepts, slow down and provide more examples
- If I'm comfortable, move faster but still validate understanding
- Let me pause at any time to explore or ask questions
- Suggest stability monitoring when appropriate

**Handle different paths**:

- I might skip Phase 0.5 (darwin validation) - warn about Phase 2 risks but support decision
- I might want to stop after Phase 2-4 (test hosts only) and defer stibnite migration
- I might discover dendritic pattern needs compromises - document and adapt
- I might want to experiment with alternative patterns in test-clan
- I might defer Phase 1 and explore test-clan extensively first

**Respond to issues**:

- Dendritic pattern feels too complex → simplify, show concrete examples from drupol-dendritic-infra
- Module conversion unclear → show before/after examples
- import-tree not discovering → troubleshoot file structure and naming
- Clan integration confusing → reference clan-infra patterns
- Darwin-specific issues → reference jfly-clan-snow and darwin production configs
- Migration conflicts → propose fixes or rollback options
- Documentation unclear → read relevant docs, provide clearer explanation

## Questions to ask me at start

Before beginning Phase 0, ask me:

1. **Current phase**: Where are we in the migration? (Phase 0 not started, Phase 1 complete, etc.)
2. **Time commitment**: How much time do you have for this session?
3. **Session goals**: What do you want to accomplish today? (understand concepts, complete Phase 0, deploy cinnabar, etc.)
4. **Risk tolerance**: Extra cautious or normal pace?
5. **Learning preference**: Learn by doing or understand concepts first?

## Assumed defaults

Unless I specify otherwise, assume:

1. **Time**: As much as needed (migration spans weeks with stability monitoring)
2. **End goal**: Migrate all hosts (test-clan → cinnabar → blackphos → rosegold → argentum → stibnite)
3. **Pace**: Normal pace with validation gates, conservative timeline (1-2 week stability between phases)
4. **Learning**: Interleaved - understand concepts enough to make informed migration decisions
5. **Safety**: Always confirm before risky operations, atomic commits, preserve rollback

## Starting point

Begin the session by:

1. Reading all referenced documentation files (00-integration-plan.md, phase guides, preferences)
2. Understanding current nix-config structure by examining flake.nix and modules/
3. Determining current migration phase (check for test-clan/, modules/ structure, cinnabar deployment, etc.)
4. Asking me where we are in the migration and what I want to accomplish
5. Proposing a tailored plan for this session based on current state
6. Getting my confirmation before making any changes

Then proceed with appropriate phase, maintaining interactivity, safety, and education throughout.

## Exit criteria for session

We can conclude a migration session when:

- Current phase goals achieved (e.g., test-clan validated, cinnabar deployed)
- Entering stability monitoring period (1-2 weeks recommended)
- I want to pause to research or understand concepts more
- Any unexpected blockers arise needing separate investigation
- Context limit approaching (migration will span multiple sessions)

At conclusion of each session, summarize:

- What we accomplished this session
- Current migration state and phase
- Key learnings about dendritic + clan
- Recommended stability monitoring period (if applicable)
- Next phase prerequisites and readiness
- Suggested next session goals

---

**Now: Read all referenced files, determine current migration state, ask your opening questions, and let's begin the interactive dendritic + clan migration at the appropriate phase.**
