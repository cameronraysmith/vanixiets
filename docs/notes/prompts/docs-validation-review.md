---
title: Pre-Migration Documentation Validation and Review
---

# Documentation validation and review task

## Context

You are working on the `infra` repository, a Nix-based infrastructure configuration using flake-parts and nixos-unified, with an integrated Astro Starlight documentation website in `packages/docs/`.

This repository is about to undergo a major architectural migration from nixos-unified to the dendritic flake-parts pattern with clan-core integration (see `docs/notes/clan/integration-plan.md` for full context).

Before beginning that migration, we need to ensure the current documentation accurately represents the pre-migration architecture, creating a reliable snapshot for future reference.

## Your task

Systematically review, validate, and polish all documentation pages that are built into the Astro Starlight website, ensuring they accurately reflect the current implementation.

## Scope

### In scope: Documentation that gets built

Review all markdown files in `packages/docs/src/content/docs/` that are:
- **Included** in the Astro build (check `packages/docs/astro.config.ts` for sidebar configuration)
- **Not** in the `notes/` subdirectory (those are working notes, not published docs)

Key sections to review:
- `/concepts/` - Conceptual explanations of architecture patterns
- `/guides/` - How-to guides for common operations
- `/reference/` - Technical reference documentation
- `/development/` - Development workflows and conventions
- `/tutorials/` - Step-by-step learning paths
- `/about/` - Project information and credits

### Out of scope: Working notes

Skip these directories (they don't get built into the site):
- `docs/notes/clan/` - Clan migration planning (future work)
- `docs/notes/prompts/` - Prompt templates
- `docs/notes/development/work-items/` - Task tracking
- Any other `notes/` subdirectories

## Validation approach

For each documentation page, perform these checks:

### 1. Accuracy validation

Compare documentation claims against actual implementation:

**File references**:
- Does the file/directory structure match what's documented?
- Use `fd`, `find`, or `ls` to verify paths exist
- Check that code examples reference real files

**Code examples**:
- Do the code snippets reflect actual implementation?
- Use `Read` tool to check referenced files match examples
- Verify nix expressions evaluate correctly (use `nix eval` or `nix-instantiate --parse`)

**Configuration claims**:
- Are configuration options documented correctly?
- Check against actual module definitions in `modules/`, `configurations/`
- Verify flake outputs match documentation (use `nix flake show`)

**Command examples**:
- Do documented commands actually work?
- Test critical commands (read-only operations like `nix build --dry-run`, `nix flake check`)
- Flag commands that would require system changes for user verification

### 2. Completeness check

Identify gaps or outdated content:
- Are there features/modules in the codebase not documented?
- Are there documented features that no longer exist?
- Are there TODOs or placeholder sections that need completion?

### 3. Quality polish

Improve readability and clarity:
- Fix typos, grammar issues, formatting inconsistencies
- Ensure consistent terminology throughout
- Improve unclear explanations
- Add missing cross-references between related docs
- Follow markdown conventions from `~/.claude/commands/preferences/style-and-conventions.md`

## Execution workflow

### Phase 1: Discovery and inventory (15-30 min)

1. **Map the documentation structure**:
   ```bash
   # Get list of all docs that get built
   cd packages/docs/src/content/docs
   find . -type f \( -name "*.md" -o -name "*.mdx" \) ! -path "*/notes/*" | sort > /tmp/docs-inventory.txt

   # Count pages by section
   find . -type f \( -name "*.md" -o -name "*.mdx" \) ! -path "*/notes/*" -exec dirname {} \; | sort | uniq -c
   ```

2. **Identify Astro build configuration**:
   ```bash
   # Check which docs are in the sidebar (actually built)
   cat packages/docs/astro.config.ts | grep -A 100 "sidebar:"
   ```

3. **Create prioritized review list**:
   - Critical: `/concepts/`, `/reference/` (architecture foundation)
   - Important: `/guides/`, `/development/` (daily use)
   - Nice-to-have: `/tutorials/`, `/about/` (onboarding, context)

4. **Report inventory to user**:
   - Total page count by section
   - Estimated review time
   - Proposed review order

### Phase 2: Systematic review (2-4 hours)

For each documentation page:

1. **Read the documentation page**:
   ```bash
   # Use Read tool
   Read packages/docs/src/content/docs/<section>/<page>.md
   ```

2. **Extract verifiable claims**:
   - File paths mentioned
   - Code examples shown
   - Configuration options documented
   - Command examples provided
   - Architecture diagrams or descriptions

3. **Verify each claim against implementation**:
   ```bash
   # Example verification commands

   # Check file exists
   fd <filename> --type f

   # Read referenced code
   Read <path/to/file.nix>

   # Validate nix expression
   nix-instantiate --parse <file.nix>

   # Check flake outputs
   nix flake show --legacy

   # Grep for specific patterns
   rg "<pattern>" <path>
   ```

4. **Document findings**:
   - Accurate: Note it's correct
   - Inaccurate: Note what's wrong and what it should be
   - Outdated: Note what changed since doc was written
   - Incomplete: Note what's missing

5. **Update the documentation**:
   - Use `Edit` tool to fix inaccuracies
   - Add missing information
   - Polish language and formatting
   - Follow style guide preferences

6. **Commit changes atomically per file**:
   ```bash
   # After editing each doc file, commit immediately
   git add packages/docs/src/content/docs/<section>/<file>.md
   git commit -m "docs(<section>): <what you fixed/updated>"
   ```

### Phase 3: Cross-cutting validation (30-60 min)

After individual page reviews:

1. **Check consistency across docs**:
   - Is terminology used consistently?
   - Do cross-references work correctly?
   - Are there conflicting claims between docs?

2. **Validate code examples build**:
   ```bash
   # Run flake check to ensure nix code is valid
   nix flake check --all-systems
   ```

3. **Check for broken links**:
   ```bash
   # If there's a link checker in the project, run it
   # Otherwise, manually verify critical internal links
   ```

### Phase 4: Summary and handoff (15 min)

Create a summary report documenting:

1. **Pages reviewed**: List all pages checked with status (✅ accurate, ⚠️ updated, ❌ needs user input)

2. **Changes made**: Summary of corrections, additions, improvements

3. **Issues requiring user decision**:
   - Ambiguous claims that need clarification
   - Missing information only user would know
   - Deprecated features to remove or keep

4. **Validation blockers**:
   - Commands that couldn't be run (require system changes)
   - Features that couldn't be verified (require specific hardware/access)

5. **Quality metrics**:
   - Number of files reviewed
   - Number of issues found and fixed
   - Number of issues flagged for user
   - Overall documentation quality assessment

## Output deliverables

By the end of this task, produce:

1. **Updated documentation files**: All reviewed pages with corrections applied (committed atomically)

2. **Review report**: `docs/notes/development/docs-review-report-YYYYMMDD.md` with:
   - Summary of work completed
   - List of all pages reviewed with status
   - Issues requiring user attention
   - Recommendations for future documentation improvements

3. **Git commit history**: Clean, atomic commits for each documentation update

## User preferences to follow

### Style and conventions

Read and follow: `~/.claude/commands/preferences/style-and-conventions.md`

Key points:
- One sentence per line in markdown
- Prefer prose over bullet lists for explanatory content
- Use lowercase except for proper nouns, acronyms, first word of sentences/headers
- No emojis unless explicitly requested
- Lowercase kebab-case for markdown filenames

### Git workflow

Read and follow: `~/.claude/commands/preferences/git-version-control.md`

Key points:
- **Commit atomically after each file edit** (don't batch multiple files)
- Use conventional commit format: `docs(<scope>): <description>`
- Stage one file at a time: `git add <file>`
- Verify with `git diff --cached <file>` before committing
- Never use `git add .` or `git add -A`

### Nix development

Read and follow: `~/.claude/commands/preferences/nix-development.md`

Key points for validation:
- Use `nix flake check` to validate nix expressions
- Use `nix eval` to test evaluations
- Understand flake outputs structure
- Know how to read nix derivations

## Success criteria

This task is complete when:

- [ ] All in-scope documentation pages have been reviewed
- [ ] Inaccuracies corrected and committed
- [ ] Code examples verified against actual implementation
- [ ] File paths and references validated
- [ ] Quality improvements applied (typos, clarity, formatting)
- [ ] Review report created and saved
- [ ] Issues requiring user attention documented
- [ ] Clean git history with atomic commits per file
- [ ] User can confidently merge beta branch to main knowing docs accurately reflect current state

## Working branch

- Current branch: `beta`
- All commits should go to `beta` branch
- After review complete, user will merge `beta` → `main`

## Repository context

### Key files to understand

- `flake.nix` - Main flake definition
- `packages/docs/astro.config.ts` - Astro site configuration (sidebar structure)
- `docs/reference/repository-structure.md` - Repository organization reference
- `modules/flake-parts/` - Flake-parts modules (auto-wired)
- `configurations/{darwin,nixos,home}/` - Host configurations (nixos-unified autowired)
- `modules/{darwin,nixos,home}/` - Modular system configurations

### Documentation structure

```
packages/docs/src/content/docs/
├── concepts/          # Architecture patterns and principles
├── guides/            # How-to guides for common tasks
├── reference/         # Technical reference (API-like docs)
├── development/       # Development workflows
├── tutorials/         # Step-by-step learning
├── about/            # Project info, credits
└── notes/            # Working notes (NOT BUILT - skip these)
    ├── clan/         # Clan migration plans (future work)
    ├── prompts/      # Prompt templates
    └── development/  # Task tracking
```

### Tools available

Use these CLI tools for efficient validation:
- `fd` - File search (faster than `find`)
- `rg` - Content search (faster than `grep`)
- `nix flake check` - Validate nix expressions
- `nix flake show` - Show flake outputs
- `nix eval` - Evaluate nix expressions
- `nix-instantiate --parse` - Parse nix files

### Time estimate

- Phase 1 (Discovery): 15-30 minutes
- Phase 2 (Review): 2-4 hours (depending on page count and issue density)
- Phase 3 (Cross-cutting): 30-60 minutes
- Phase 4 (Summary): 15 minutes

**Total estimated time**: 3-6 hours

## Questions to ask user before starting

1. **Priority sections**: Are there specific documentation sections most critical to validate? (e.g., architecture, flake outputs, module system)

2. **Known issues**: Are there any known outdated docs or problem areas to focus on?

3. **Time constraints**: Is there a deadline or time budget for this work?

4. **Validation depth**: Should code examples be tested by building, or is reading/verification sufficient?

5. **Scope adjustment**: Should any sections be skipped or deferred?

## Example review workflow for one page

Here's what reviewing one page looks like:

```bash
# 1. Read the doc
Read packages/docs/src/content/docs/concepts/understanding-autowiring.md

# 2. Extract claims (example):
# - Claims: "Files in configurations/darwin/ become darwinConfigurations.*"
# - Claims: "Files in modules/flake-parts/ are auto-imported"

# 3. Verify claims
fd -t d "configurations/darwin" --max-depth 1
# Output: configurations/darwin/ exists ✓

nix flake show --legacy | grep darwinConfigurations
# Output: Shows darwinConfigurations.stibnite, etc. ✓

ls modules/flake-parts/
# Output: Shows devshell.nix, nixos-flake.nix, etc. ✓

# 4. Check if examples match actual code
Read configurations/darwin/stibnite.nix
# Compare with example in doc ✓ or ✗

# 5. Fix any issues found
Edit packages/docs/src/content/docs/concepts/understanding-autowiring.md
# Update outdated example, fix typo, improve clarity

# 6. Commit atomically
git add packages/docs/src/content/docs/concepts/understanding-autowiring.md
git commit -m "docs(concepts): correct autowiring example to match actual configuration"
```

## Ready to begin

Start by:
1. Confirming you understand the task
2. Asking the user any clarifying questions from the "Questions to ask user" section
3. Running Phase 1 (Discovery) to create an inventory and review plan
4. Presenting the plan to the user for approval before beginning systematic review

Then proceed through Phases 2-4, maintaining communication about progress and any issues that need user input.
