# Interactive dendritic + clan migration prompt for Claude Code

Use this prompt to initiate an interactive dendritic + clan migration session.

---

# Dendritic + clan migration interactive guide

## Context and objectives

I want to migrate my nixos-unified based nix-config repository at `~/projects/nix-workspace/nix-config` to the dendritic flake-parts pattern with clan-core integration.
This migration will transition darwin hosts (blackphos, rosegold, argentum, stibnite) from nixos-unified to dendritic's `flake.modules.*` namespace with clan's multi-machine coordination and vars management.

## Your role

Guide me through a progressive, interactive migration to dendritic + clan.
Start with understanding dendritic patterns, validate my understanding at each step, and only proceed to host migration when patterns are clear.
Prioritize safety (parallel environment, preserve rollback), education (explain dendritic and clan concepts), and interactivity (pause for my input and questions).

## Required reading for you

Before beginning, read and internalize these documents I've prepared:

**Integration documentation** (start here):

- `~/projects/nix-workspace/nix-config/docs/notes/clan-integration/README.md` - Overview and navigation
- `~/projects/nix-workspace/nix-config/docs/notes/clan-integration/00-integration-plan.md` - Strategic analysis and architecture
- `~/projects/nix-workspace/nix-config/docs/notes/clan-integration/01-phase-1-guide.md` - Step-by-step implementation guide
- `~/projects/nix-workspace/nix-config/docs/notes/clan-integration/02-migration-assessment.md` - Migration evaluation (Phase 2)

**My development preferences** (follow these strictly):

- `~/.claude/commands/preferences/preferences.md` - Strict preferences (lowercase, no emojis, kebab-case)
- `~/.claude/commands/preferences/general-practices.md` - Development practices
- `~/.claude/commands/preferences/git-version-control.md` - Git workflow (atomic commits)
- `~/.claude/commands/preferences/nix-development.md` - Nix-specific patterns

**Current repository structure**:

- `~/projects/nix-workspace/nix-config/flake.nix` - Current flake structure
- `~/projects/nix-workspace/nix-config/modules/flake-parts/` - Auto-wired flake-parts modules
- `~/projects/nix-workspace/nix-config/configurations/nixos/` - NixOS host configurations
- `~/projects/nix-workspace/nix-config/secrets/` - Current SOPS-based secrets

**Clan reference repositories**:

- `~/projects/nix-workspace/clan-core/` - Monorepo with modules, CLI, documentation
- `~/projects/nix-workspace/clan-core/docs/site/` - Official Clan documentation
- `~/projects/nix-workspace/clan-core/clanServices/` - Example Clan service implementations
- `~/projects/nix-workspace/clan-infra/` - Production infrastructure examples

## Migration progression

Guide me through these stages progressively, with checkpoints between each:

### Stage 1: Dendritic pattern exploration (minimal risk)

**Objective**: Understand dendritic flake-parts pattern without migration

**Tasks**:

1. Read dendritic pattern documentation: `~/projects/nix-workspace/dendritic-flake-parts/README.md`
2. Examine production examples: `~/projects/nix-workspace/drupol-dendritic-infra/`
3. Add clan-core and import-tree flake inputs to `flake.nix`
4. Update flake outputs to use import-tree: `inputs.import-tree ./modules`
5. Create dendritic directory structure: `modules/{base,darwin,shell,dev,hosts,users}/`
6. Verify flake evaluates with import-tree: `nix flake check`
7. Understand `flake.modules.{darwin,homeManager,nixos}.*` namespace concept
8. Explore how import-tree discovers modules: `fd -e nix . modules/`

**Checkpoint**: Stop and ask if I understand dendritic pattern, import-tree auto-discovery, and flake.modules.* namespace before proceeding.

### Stage 2: Module conversion to dendritic (low-medium risk)

**Objective**: Convert existing modules to dendritic pattern

**Tasks**:

1. Create base modules in dendritic pattern:
   - `modules/base/nix.nix`: Define `flake.modules.darwin.base-nix`
   - `modules/base/system.nix`: Define `flake.modules.darwin.base-system`
2. Convert shell modules:
   - `modules/shell/fish.nix`: Define both `darwin.shell-fish` and `homeManager.shell-fish`
3. Convert development tools:
   - `modules/dev/git/git.nix`: Define `homeManager.dev-git` with metadata references
4. Create user metadata module:
   - `modules/users/crs58/default.nix`: Define `flake.meta.users.crs58` and user modules
5. Create flake-parts host-machines module:
   - `modules/flake-parts/host-machines.nix`: Auto-generate darwinConfigurations
6. Verify module namespace populated: `nix eval .#flake.modules.darwin --apply builtins.attrNames`

**Checkpoint**: Verify I understand module conversion patterns, metadata sharing, and host generation before proceeding.

### Stage 3: blackphos migration (medium risk)

**Objective**: Migrate first darwin host to dendritic + clan

**Tasks**: Follow `01-phase-1-guide.md` steps 1-15

1. Create clan inventory in `modules/flake-parts/clan.nix`
2. Define all four hosts with tags and machineClass
3. Add clan service instances (emergency-access, users, zerotier)
4. Create blackphos host configuration: `modules/hosts/blackphos/default.nix`
5. Initialize clan secrets structure
6. Generate vars for blackphos: `nix run .#clan-cli -- vars generate blackphos`
7. Build blackphos: `nix build .#darwinConfigurations.blackphos.system`
8. Deploy to blackphos: `darwin-rebuild switch --flake .#blackphos`
9. Validate all functionality preserved
10. Verify zerotier controller operational
11. Monitor stability for 1-2 weeks

**Checkpoint**: After deployment, evaluate blackphos stability and decide whether to proceed to rosegold.

### Stage 4: Multi-machine coordination (medium-high risk)

**Objective**: Migrate rosegold and argentum, validate multi-machine features

**Tasks**:

1. **rosegold migration**:
   - Create `modules/hosts/rosegold/default.nix` (reuse blackphos patterns)
   - Generate vars: `nix run .#clan-cli -- vars generate rosegold`
   - Deploy: `darwin-rebuild switch --flake .#rosegold`
   - Test zerotier peer connection to blackphos controller
   - Validate 2-machine network connectivity
   - Monitor stability for 1-2 weeks
2. **argentum migration**:
   - Create `modules/hosts/argentum/default.nix` (reuse patterns)
   - Generate vars and deploy
   - Test 3-machine zerotier mesh network
   - Validate pattern stability across three hosts
   - Monitor stability for 1-2 weeks
3. **Evaluation**:
   - Assess whether to migrate stibnite (primary workstation)
   - See `02-migration-assessment.md` for stibnite considerations

**Checkpoint**: After all test hosts stable, discuss stibnite migration readiness and timeline.

## Your implementation approach

**Before starting each stage**:

1. Summarize what we'll do and why
2. Explain key Clan concepts we'll encounter
3. Ask for my confirmation to proceed
4. Provide estimated time and complexity

**During each stage**:

1. Show exactly what you're doing (commands, file edits)
2. Explain why each step is necessary
3. Validate results before proceeding
4. Pause if errors occur - don't push through
5. Create atomic git commits for each logical change

**After each stage**:

1. Summarize what we accomplished
2. Verify my understanding of key concepts
3. Ask if I have questions
4. Get explicit confirmation before proceeding to next stage

## Safety requirements

**Critical constraints**:

- CREATE parallel dendritic environment (modules/ directory alongside configurations/)
- PRESERVE nixos-unified configurations until migration complete
- ALWAYS test with `nix flake check` before committing
- CREATE atomic git commits for each logical change
- ENABLE easy rollback (preserve old configs, git history)
- VALIDATE each step succeeds before proceeding
- MIGRATE one host at a time (blackphos → rosegold → argentum → stibnite)

**If anything breaks**:

1. Stop immediately
2. Show me the error
3. Explain what happened
4. Propose troubleshooting steps or rollback to previous commit
5. Wait for my decision before acting

## Interactive teaching points

At appropriate moments, explain these concepts using examples from the repositories:

**Dendritic pattern**:

- Eliminate specialArgs in favor of `config.flake.*` access
- File path = feature name (clear organization)
- `flake.modules.*` namespace for all modules
- Cross-cutting concerns (one module, multiple targets)
- Examples from `~/projects/nix-workspace/drupol-dendritic-infra/`

**import-tree auto-discovery**:

- Recursively imports all .nix files in modules/
- Each file is a flake-parts module
- No manual imports needed
- Directory structure becomes module hierarchy

**Module composition**:

- Host modules import from `config.flake.modules.*`
- Combine darwin, homeManager, and nixos modules
- Metadata sharing via `config.flake.meta.*`
- Examples from `00-integration-plan.md`

**Inventory system**:

- How machines, tags, instances, and roles relate
- Configuration hierarchy (instance → role → machine)
- Service distribution across machines
- Examples from `~/projects/nix-workspace/clan-infra/machines/flake-module.nix`

**Vars system**:

- Generator structure (prompts, script, dependencies, files)
- Secret vs public files (.path vs .value)
- Storage backends and deployment
- Examples from `~/projects/nix-workspace/clan-core/clanServices/sshd/default.nix`

**Migration strategy**:

- Parallel environment (dendritic + nixos-unified coexist)
- Progressive per-host migration
- Validation gates between phases
- Rollback safety (preserve old configs)

## Success criteria

I'll know migration is successful when:

- ✅ Understand dendritic pattern and `flake.modules.*` namespace
- ✅ Can convert existing modules to dendritic pattern
- ✅ import-tree auto-discovery works correctly
- ✅ blackphos builds and deploys with dendritic + clan
- ✅ All functionality preserved after migration
- ✅ Clan inventory and vars system operational
- ✅ Zerotier multi-machine network functional (blackphos controller, others as peers)
- ✅ Can articulate how to migrate remaining hosts (rosegold, argentum, stibnite)
- ✅ Confidence in dendritic + clan approach for all hosts

## Flexibility and adaptation

**Adapt to my pace**:

- If I'm struggling with concepts, slow down and explain more
- If I'm comfortable, move faster but still validate understanding
- Let me skip stages if I'm confident (but warn about risks)
- Let me pause at any time to explore or ask questions

**Handle different paths**:

- I might want to skip pattern exploration and go straight to migration
- I might want to focus on specific module types (shell, development, etc.)
- I might discover dendritic pattern doesn't fit after Stage 1-2
- I might want to migrate multiple hosts quickly vs. conservative timeline
- I might want to defer stibnite migration indefinitely

**Respond to issues**:

- Dendritic pattern feels too complex → simplify explanations, more examples
- Module conversion unclear → show concrete before/after examples
- import-tree not discovering modules → troubleshoot file structure
- Migration conflicts with existing setup → propose fixes or rollback
- I want to try alternative patterns → support exploration while noting tradeoffs
- Documentation unclear → read relevant docs, provide clearer explanation

## Questions to ask me at start

Before beginning Stage 1, ask me:

1. **Time commitment**: How much time do you have for this migration? (This helps me pace appropriately)
2. **Goals**: What do you most want to accomplish? (understand dendritic, migrate all hosts, just blackphos, pattern exploration?)
3. **Risk tolerance**: Should we be extra cautious or can we move at a normal pace?
4. **End goal**: Are you planning to migrate all four darwin hosts, or just test hosts (blackphos, rosegold, argentum)?
5. **Preferred learning style**: Learn by doing, or prefer understanding patterns thoroughly before migrating?

Assume the following answers

1. As much as it takes (migration can span several weeks with stability monitoring).
2. Migrate all four darwin hosts to dendritic + clan (blackphos → rosegold → argentum → stibnite).
3. Normal pace, notify commands and confirm before execution if there is risk involved. Conservative timeline with 1-2 week stability gates.
4. Migrate all hosts progressively: test hosts first (blackphos, rosegold, argentum), then primary workstation (stibnite) only after others proven stable.
5. Need to do both interleaved with enough of the concepts up front that the migration is well-informed. Understand dendritic pattern before migrating, validate each phase before proceeding.

## Starting point

Begin the session by:

1. Reading all referenced documentation files
2. Understanding current nix-config structure by examining key files
3. Asking me the 5 questions above
4. Proposing a tailored experimentation plan based on my answers
5. Getting my confirmation before making any changes

Then proceed with Stage 1, maintaining interactivity and safety throughout.

## Exit criteria

We can conclude migration session when:

- I've achieved current phase goals (e.g., blackphos migrated and stable)
- I've decided dendritic + clan isn't right for this use case
- I want to pause and monitor stability before next phase
- I want to research more before proceeding to next host
- Any unexpected blockers arise that need separate investigation

At conclusion of each session, summarize:

- What we accomplished
- Key learnings about dendritic + clan
- Current migration state (which hosts migrated)
- Recommended next steps (stability monitoring, next host, or pause)
- Whether patterns are validated and ready for reuse

---

**Now: Read all referenced files, understand the context, ask your opening questions, and let's begin the interactive dendritic + clan migration.**
