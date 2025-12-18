---
argument-hint: [doc-path...] [--shallow]
description: Review beads database against planning docs and repository state, proposing remediation commands
---

# Beads database review

Symlink location: `~/.claude/commands/issues/beads-review.md`
Slash command: `/issues:beads-review [doc-path...] [--shallow]`

Action prompt for auditing beads database completeness, accuracy, and alignment.
Use at project setup, major milestones, or when planning documents have significantly changed.

Arguments:
- `doc-path...` — Explicit paths to planning documents (PRD, architecture, epics)
- `--shallow` — Skip deep git pickaxe analysis (faster, less thorough)

$ARGUMENTS

## Phase 1: Document discovery

If document paths were provided in arguments, use those.
Otherwise, search for planning documents in conventional locations:

```bash
# Common planning doc locations
fd -t f -e md '(PRD|prd|architecture|epics?|requirements|design)' docs/ . --max-depth 3 2>/dev/null
fd -t f 'README' . --max-depth 1 2>/dev/null
```

Present discovered documents to user and confirm before proceeding:

> I found the following planning documents:
> - `docs/PRD.md` (Product Requirements)
> - `docs/architecture.md` (Architecture)
> - `docs/epics/` (Epic definitions)
>
> Should I proceed with reviewing beads against these documents?
> Are there other documents I should include?

Wait for user confirmation before continuing.
Read and internalize the confirmed planning documents.

## Phase 2: Structural health

Run diagnostics on the beads database structure:

```bash
# Quick human-readable overview
bd status

# Structural issues
bd dep cycles

# Database integrity
bd validate
```

For deeper structural analysis (redirect to avoid context pollution):

```bash
REPO=$(basename "$(git rev-parse --show-toplevel)")

# Suggestions: duplicates, missing deps, label issues
SUGGEST=$(mktemp "/tmp/bv-${REPO}-suggest.XXXXXX.json")
bv --robot-suggest > "$SUGGEST"
jq '.duplicates[:10]' "$SUGGEST"
jq '.missing_dependencies[:10]' "$SUGGEST"
jq '.label_suggestions[:10]' "$SUGGEST"
jq '.cycles' "$SUGGEST"
rm "$SUGGEST"

# Priority misalignment
PRIORITY=$(mktemp "/tmp/bv-${REPO}-priority.XXXXXX.json")
bv --robot-priority > "$PRIORITY"
jq '.recommendations[:10]' "$PRIORITY"
rm "$PRIORITY"

# Stale issues
bd stale
```

Record all findings for the synthesis phase.

## Phase 3: Planning alignment

Cross-reference planning documents against beads database.

### Extract requirements from planning docs

For each planning document, identify:
- Explicit requirements (MUST, SHALL, SHOULD statements)
- Features and capabilities described
- Epic/milestone boundaries
- Acceptance criteria
- Non-functional requirements

### Query beads for coverage

```bash
# List all open beads with their descriptions
bd list --status open --json | jq -r '.[] | "\(.id): \(.title)"'

# List all epics
bd list --type epic --json | jq -r '.[] | "\(.id): \(.title) [\(.status)]"'

# Search for specific terms from requirements
bd search "<requirement-keyword>"
```

### Identify gaps

For each requirement from planning docs:
1. Search for corresponding bead(s)
2. If found: verify description aligns with requirement
3. If not found: flag as missing coverage

Record:
- **Uncaptured requirements** — Planning items with no corresponding bead
- **Stale descriptions** — Beads whose descriptions don't match current requirements
- **Orphaned beads** — Beads with no corresponding planning requirement (may be valid discoveries)

## Phase 4: Code correlation

Analyze alignment between beads and actual implementation.

### Git history overview

```bash
# Recent commit activity
git log --oneline -30

# Commits mentioning bead IDs
git log --oneline --grep="bd-" -20 2>/dev/null || git log --oneline --grep="-[a-z0-9]\{3,4\}" -20
```

### Bead-to-commit correlation

```bash
REPO=$(basename "$(git rev-parse --show-toplevel)")
HISTORY=$(mktemp "/tmp/bv-${REPO}-history.XXXXXX.json")
bv --robot-history > "$HISTORY"

# Sample correlations
jq '.correlations[:20]' "$HISTORY"

# Orphan commits (should be linked but aren't)
ORPHANS=$(mktemp "/tmp/bv-${REPO}-orphans.XXXXXX.json")
bv --robot-orphans > "$ORPHANS"
jq '.candidates[:15]' "$ORPHANS"

rm "$HISTORY" "$ORPHANS"
```

### Deep analysis with pickaxe (skip if --shallow)

For closed beads, verify implementation exists:

```bash
# For a closed bead about "authentication", verify related code exists
git log -S"authentication" --oneline -- "*.ts" "*.py" "*.rs" | head -5

# For specific function/class mentioned in bead
git log -G"loginUser\|authenticateRequest" --oneline | head -5
```

For open beads, check if already implemented but not closed:

```bash
# Search for implementation of open bead's described functionality
git log -S"<key-term-from-open-bead>" --oneline | head -5
```

Record:
- **Zombie beads** — Closed beads with no corresponding implementation
- **Ghost implementations** — Implemented features with open beads that should be closed
- **Orphan commits** — Significant commits not linked to any bead

## Phase 5: Findings synthesis

Organize findings by category and severity.

### Report structure

Present findings in this order:

**Critical (must fix)**
- Circular dependencies
- Database integrity errors
- Closed beads with no implementation (zombies)

**High priority**
- Uncaptured requirements from planning docs
- Implemented features with open beads (ghosts)
- Priority misalignments on critical path

**Medium priority**
- Stale beads (no updates in 30+ days)
- Duplicate/overlapping beads
- Missing dependencies
- Orphan commits

**Low priority / informational**
- Label inconsistencies
- Description drift from requirements
- Orphaned beads (may be valid discoveries)

### Remediation commands

For each finding, propose specific `bd` commands:

**Uncaptured requirement:**
```bash
bd create "<requirement-title>" -t <type> -p <priority>
# Then wire dependencies:
bd dep add <new-id> <blocking-id>
```

**Ghost implementation (should be closed):**
```bash
bd close <bead-id> --comment "Implemented in commit <sha>. Discovered during beads-review."
```

**Duplicate beads:**
```bash
bd close <duplicate-id> --comment "Duplicate of <primary-id>"
# Migrate unique deps if any:
bd dep add <unique-blocker> <primary-id>
```

**Missing dependency:**
```bash
bd dep add <blocker-id> <blocked-id>
```

**Priority misalignment:**
```bash
bd update <bead-id> --priority <new-priority>
```

**Stale bead needing review:**
```bash
bd show <bead-id>
# Then either close, update, or add comment explaining status
```

**Label fix:**
```bash
bd update <bead-id> --labels "<corrected-labels>"
```

## Summary template

Provide final summary to user:

```
## Beads Review Summary

**Documents reviewed:** [list]
**Beads analyzed:** X open, Y closed, Z total

### Findings by severity
- Critical: N issues
- High: N issues
- Medium: N issues
- Low: N issues

### Key actions needed
1. [Most important remediation]
2. [Second priority]
3. [Third priority]

### Proposed commands
[Consolidated list of bd commands to execute]

Run `/issues:beads-orient` after applying fixes to verify improved health.
```

---

*Related commands:*
- `/issues:beads-orient` — Session start orientation
- `/issues:beads-checkpoint` — Session wind-down
- `/issues:beads-evolve` — Adaptive refinement patterns
