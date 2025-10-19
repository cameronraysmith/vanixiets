# Interactive Clan integration prompt for Claude Code

Use this prompt to initiate an interactive Clan integration session.

---

# Clan integration interactive experimentation guide

## Context and objectives

I want to experimentally integrate Clan (clan.lol) capabilities into my nixos-unified based nix-config repository at `~/projects/nix-workspace/nix-config`.
This is exploratory work to understand Clan's inventory, vars, and multi-machine coordination systems before committing to full deployment.

## Your role

Guide me through a progressive, interactive experimentation process with Clan integration.
Start with minimal local exploration, validate my understanding at each step, and only proceed to more complex stages when I'm comfortable.
Prioritize safety (preserve existing configurations), education (explain concepts), and interactivity (pause for my input and questions).

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

## Experimentation progression

Guide me through these stages progressively, with checkpoints between each:

### Stage 1: Local exploration (minimal risk)

**Objective**: Understand Clan abstractions without deployment

**Tasks**:

1. Add clan-core flake input to `flake.nix` with appropriate follows
2. Create minimal `modules/flake-parts/clan.nix` importing clan-core.flakeModules.default
3. Define empty inventory structure
4. Verify flake evaluates: `nix flake check`
5. Explore Clan outputs: `nix flake show`, `nix eval .#clan.inventory --json`
6. Examine clan-cli capabilities: `nix run nixpkgs#clan-cli -- --help`

**Checkpoint**: Stop and ask if I understand inventory, machines, and instances concepts before proceeding.

### Stage 2: Vars system experimentation (low risk)

**Objective**: Test declarative secret generation locally

**Tasks**:

1. Initialize Clan secrets structure: `secrets/clan/{groups,machines,secrets,users}/`
2. Generate age key: `nix run nixpkgs#clan-cli -- secrets key generate`
3. Set up admin group and add self as admin
4. Create a simple vars generator (e.g., test password hash)
5. Generate vars for a test machine
6. Inspect generated files in `secrets/clan/`
7. Understand `.path` vs `.value` for secret vs public files

**Checkpoint**: Verify I understand vars generators, prompts, dependencies, and storage before proceeding.

### Stage 3: Local VM testing (medium risk, optional)

**Objective**: Test full Clan workflow without cloud infrastructure

**Tasks**:

1. Create `configurations/nixos/remote/test-vm.nix` using Clan patterns
2. Add to clan inventory in `modules/flake-parts/clan.nix`
3. Add basic Clan services (emergency-access, sshd)
4. Generate vars: `nix run .#clan-cli -- vars generate test-vm`
5. Build VM: `nix build .#nixosConfigurations.test-vm.config.system.build.vm`
6. Run VM locally: `./result/bin/run-*-vm`
7. Test deployment workflow to VM

**Checkpoint**: Ask if I want to proceed to real remote deployment or continue experimenting locally.

### Stage 4: Remote deployment (Phase 1, production)

**Objective**: Deploy first Clan-managed remote host

**Tasks**: Follow `01-phase-1-guide.md` steps 1-15 exactly

- Only proceed if I explicitly confirm readiness
- Recommend starting with cheapest Hetzner instance (CX11)
- Validate each step before proceeding to next
- Create atomic git commits as work progresses

**Checkpoint**: After deployment, evaluate experience and discuss next steps.

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

- NEVER modify existing host configurations (stibnite, blackphos, etc.)
- ALWAYS test with `nix flake check` before committing
- CREATE separate directories for Clan-specific files
- PRESERVE existing secrets structure (dual systems during experimentation)
- ENABLE easy rollback (git commits per change, clear separation)
- VALIDATE each step succeeds before proceeding

**If anything breaks**:

1. Stop immediately
2. Show me the error
3. Explain what happened
4. Propose troubleshooting steps or rollback
5. Wait for my decision before acting

## Interactive teaching points

At appropriate moments, explain these concepts using examples from the repositories:

**Inventory system**:

- How machines, tags, instances, and roles relate
- Configuration hierarchy (instance → role → machine)
- Examples from `~/projects/nix-workspace/clan-infra/machines/flake-module.nix`

**Vars system**:

- Generator structure (prompts, script, dependencies, files)
- Secret vs public files (.path vs .value)
- Storage backends and deployment
- Examples from `~/projects/nix-workspace/clan-core/clanServices/sshd/default.nix`

**Clan services**:

- `_class = "clan.service"` module type
- perInstance vs perMachine
- Role interfaces and settings
- Examples from `~/projects/nix-workspace/clan-core/clanServices/`

**Integration with nixos-unified**:

- How flake-parts composition works
- Module auto-wiring
- Coexistence of Clan and non-Clan hosts
- Directory organization patterns

## Success criteria

I'll know experimentation is successful when:

- ✅ Flake builds cleanly with Clan integrated
- ✅ I can articulate how inventory maps to NixOS configurations
- ✅ I can create and generate vars for a machine
- ✅ I understand when to use Clan services vs plain modules
- ✅ Existing local hosts build and function identically
- ✅ I can deploy a configuration to a test machine (VM or remote)

## Flexibility and adaptation

**Adapt to my pace**:

- If I'm struggling with concepts, slow down and explain more
- If I'm comfortable, move faster but still validate understanding
- Let me skip stages if I'm confident (but warn about risks)
- Let me pause at any time to explore or ask questions

**Handle different paths**:

- I might want to skip VM testing and go straight to remote
- I might want to explore specific Clan services in depth
- I might discover I don't need Clan after Stage 1-2
- I might want to focus on specific use cases (backups, networking, etc.)

**Respond to issues**:

- Clan abstractions feel too complex → simplify explanations, more examples
- Integration conflicts with existing setup → troubleshoot, propose alternatives
- I want to try something not in the plan → support exploration while noting risks
- Documentation unclear → read relevant Clan docs, provide clearer explanation

## Questions to ask me at start

Before beginning Stage 1, ask me:

1. **Time commitment**: How much time do you have for this session? (This helps me pace appropriately)
2. **Goals**: What do you most want to understand about Clan? (inventory, vars, services, deployment, all of it?)
3. **Risk tolerance**: Should we be extra cautious or can we move at a normal pace?
4. **End goal**: Are you planning to eventually deploy remote hosts, or just exploring Clan as a concept?
5. **Preferred learning style**: Learn by doing, or prefer understanding concepts thoroughly before trying?

Assume the following answers

1. As much as it takes.
2. All of it.
3. Normal pace, notify commands and confirm before execution if there is risk involved.
4. Deploy at least 2 remote hosts to hetzner that can interact with one another and possibly my local machines as well.
5. Need to do both interleaved with enough of the concepts up front that the doing is well-informed.

## Starting point

Begin the session by:

1. Reading all referenced documentation files
2. Understanding current nix-config structure by examining key files
3. Asking me the 5 questions above
4. Proposing a tailored experimentation plan based on my answers
5. Getting my confirmation before making any changes

Then proceed with Stage 1, maintaining interactivity and safety throughout.

## Exit criteria

We can conclude experimentation when:

- I've achieved my stated goals
- I've decided Clan isn't right for this use case
- I've successfully deployed a test host and am ready to operate it
- I want to pause and research more before proceeding
- Any unexpected blockers arise that need separate investigation

At conclusion, summarize:

- What we accomplished
- Key learnings about Clan
- Recommended next steps
- Whether to proceed with Phase 1, continue experimenting, or defer

---

**Now: Read all referenced files, understand the context, ask your opening questions, and let's begin the interactive Clan integration experimentation.**
