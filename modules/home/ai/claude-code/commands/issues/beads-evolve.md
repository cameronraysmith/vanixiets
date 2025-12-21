---
description: Adaptive refinement patterns for evolving the issue graph during implementation with architecture feedback loop
---

# Adaptive issue evolution

Symlink location: `~/.claude/commands/issues/beads-evolve.md`
Slash command: `/issues:beads-evolve`

Reference document for adaptive issue graph evolution.
Issues, epics, dependencies, and priorities are hypotheses refined through implementation feedback.

For session lifecycle, use the action commands: `/issues:beads-orient` (start) and `/issues:beads-checkpoint` (wind-down).

Related commands:
- `/issues:beads-orient` (`~/.claude/commands/issues/beads-orient.md`) — action: session start
- `/issues:beads-checkpoint` (`~/.claude/commands/issues/beads-checkpoint.md`) — action: session wind-down
- `/issues:beads` (`~/.claude/commands/issues/beads.md`) — comprehensive reference
- `/issues:beads-prime` (`~/.claude/commands/issues/beads-prime.md`) — minimal quick reference

## When to use this command

Use beads-evolve specifically for graph structure problems discovered during active implementation.

When to use beads-evolve:
- Implementing an issue and discovering it needs to be split
- Finding unexpected blockers that change dependency structure
- Realizing work can be done in parallel instead of sequentially
- Discovering scope is larger or smaller than initially thought
- Finding new issues during implementation that affect the graph

When NOT to use beads-evolve:
- **Periodic health checks without implementation context**: use `/issues:beads-audit` instead
- **Initial creation from architecture docs**: use beads-seed or manual creation
- **Session start diagnostics**: use `/issues:beads-orient`
- **Session end capture**: use `/issues:beads-checkpoint`

## Philosophy

The issue graph is a living model of work, not a contract.
Initial planning captures current understanding; implementation reveals what we couldn't anticipate.
Beads stores history in git-tracked JSONL, making evolution safe and auditable.

XP principles that apply:
- *Embrace change*: Requirements evolve as understanding deepens
- *Continuous feedback*: Implementation informs planning
- *Simple design*: Don't over-specify; evolve structure as needed
- *Courage*: Refactor the issue graph when it no longer reflects reality

The cost of an outdated issue graph is confusion, misaligned priorities, and phantom blockers.
The cost of evolution is low — `bd` commands are fast, history is preserved, and the graph recalculates automatically.

## Pre-work review

Before starting any issue, validate its current accuracy:

```bash
# Read the full issue
bd show <issue-id>

# Check dependencies — are they still relevant?
bd dep tree <issue-id> --direction both

# Check parent epic context if applicable
bd show <parent-epic-id>
```

Questions to ask:
- Is the description still accurate given what we've learned?
- Is the scope appropriate (not too large, not trivially small)?
- Are the listed blockers still actual blockers?
- Is the priority still correct relative to other ready work?
- Should this issue be split before starting?

If anything is stale, update before starting:

```bash
# Update description with current understanding
bd update <issue-id> --description "Revised: now includes X, excludes Y"

# Fix priority if misaligned
bd update <issue-id> --priority 1

# Remove dependency that's no longer a blocker
bd dep remove <not-actually-blocking> <issue-id>

# Add dependency we now recognize
bd dep add <actual-blocker> <issue-id>
```

## In-flight adaptation

During implementation, the issue graph should evolve in real-time.

### Scope expansion discovered

When an issue is larger than anticipated:

```bash
# Split into sub-tasks under the current issue
bd create "Part 1: data model changes" -p 2 --parent <issue-id>
bd create "Part 2: API implementation" -p 2 --parent <issue-id>
bd create "Part 3: UI integration" -p 2 --parent <issue-id>

# Wire sequencing if needed
bd dep add <part1-id> <part2-id>
bd dep add <part2-id> <part3-id>

# Update original issue to reflect it's now a container
bd update <issue-id> --type epic --description "Split into sub-tasks for tractability"
```

### Hidden blockers discovered

When work reveals an unexpected prerequisite:

```bash
# Create the blocker
bd create "Need to refactor auth module first" -t task -p 1

# Wire as blocking dependency
bd dep add <new-blocker-id> <current-issue-id>

# Comment on why this emerged
bd comment <current-issue-id> "Discovered blocker: auth module coupling prevents clean implementation"
```

### Parallel work opportunities discovered

When you realize parts can be done independently:

```bash
# Remove unnecessary sequencing
bd dep remove <issue-a> <issue-b>

# Add comment explaining the decoupling
bd comment <issue-b> "Can proceed independently of <issue-a> — only shared dependency is X"
```

### Scope reduction

When an issue is simpler than expected, or part is no longer needed:

```bash
# Update to reflect reduced scope
bd update <issue-id> --description "Simplified: Y approach eliminates need for Z"

# If sub-tasks become unnecessary, close them
bd close <unnecessary-subtask> --comment "No longer needed — parent issue simplified"
```

### New issues discovered

When implementation reveals related work:

```bash
# Bug found during implementation
bd create "Bug: edge case in validation when X" -t bug -p 2
bd dep add <bug-id> <current-issue-id> --type discovered-from

# Technical debt identified
bd create "Tech debt: refactor Y for maintainability" -t task -p 3
bd dep add <debt-id> <current-issue-id> --type discovered-from

# Future enhancement recognized
bd create "Enhancement: could also support Z" -t feature -p 3
bd dep add <enhancement-id> <current-issue-id> --type related
```

The `discovered-from` dependency type is crucial — it maintains traceability without creating false blockers.

## Post-completion reflection

After closing an issue, briefly reflect on what was learned:

### Update related issues

```bash
# Check what this unblocked
bd dep tree <completed-id> --direction up

# Review those issues — are their descriptions still accurate given what we learned?
bd show <unblocked-id>

# Update if implementation revealed something about downstream work
bd update <unblocked-id> --description "Note: X is now available from completed work"
```

### Epic health check

```bash
# Check if epic is complete
bd epic status

# If all children closed, close the epic
bd epic close-eligible --dry-run
bd epic close-eligible

# If epic scope changed significantly, update its description
bd update <epic-id> --description "Revised scope: originally N tasks, expanded to M due to discovered complexity"
```

### Priority recalibration

After completing work, priorities may need adjustment:

```bash
# Get current priority recommendations
bv --robot-priority

# Review if computed importance diverges from assigned priority
# Update priorities that are now misaligned
bd update <issue-id> --priority 0  # escalate if now critical path
bd update <other-id> --priority 2  # demote if less urgent than thought
```

## Periodic graph review

Beyond issue-by-issue evolution, periodically review the whole graph.

### Weekly or sprint-boundary review

```bash
# Quick human-readable health check
bd status

# Stale issues (not updated in 30+ days)
bd stale

# Blocked issues — are blockers being worked?
bd blocked

# Cycle check — should always be zero
bd dep cycles

# For structured analysis (redirect to avoid context pollution)
REPO=$(basename "$(git rev-parse --show-toplevel)")
TRIAGE=$(mktemp "/tmp/bv-${REPO}-triage.XXXXXX.json")
bv --robot-triage > "$TRIAGE"
jq '.stale_alerts' "$TRIAGE"
jq '.project_health' "$TRIAGE"
rm "$TRIAGE"

# Priority misalignment (redirect — can be large)
PRIORITY=$(mktemp "/tmp/bv-${REPO}-priority.XXXXXX.json")
bv --robot-priority > "$PRIORITY"
jq '.recommendations[:5]' "$PRIORITY"
rm "$PRIORITY"
```

### Graph structure review

For deep structural analysis (always redirect — 3000+ lines of JSON):

```bash
# Create repo-specific temp file to avoid conflicts between concurrent agents
REPO=$(basename "$(git rev-parse --show-toplevel)")
INSIGHTS=$(mktemp "/tmp/bv-${REPO}-insights.XXXXXX.json")
bv --robot-insights > "$INSIGHTS"

# Bottlenecks — are these being prioritized?
jq '.Bottlenecks[:10]' "$INSIGHTS"

# Keystones on critical path — any surprises?
jq '.Keystones[:10]' "$INSIGHTS"

# Overall density — is coupling increasing?
jq '.ClusterDensity' "$INSIGHTS"

# Clean up
rm "$INSIGHTS"
```

If density is increasing over time, consider:
- Are dependencies being over-specified?
- Should some epics be split into independent streams?
- Are there implicit dependencies that should be explicit (and then removed)?

### Cleanup operations

```bash
# Find and fix orphaned dependency references
bd repair-deps --dry-run
bd repair-deps

# Find potential duplicates
bd duplicates

# Validate database integrity
bd validate
```

## Common refactoring patterns

### Split a monolithic issue

When an issue grew beyond tractable scope:

```bash
# Promote to epic
bd update <issue-id> --type epic

# Create sub-tasks
bd create "Sub-task 1" -p 2 --parent <issue-id>
bd create "Sub-task 2" -p 2 --parent <issue-id>

# Migrate any existing dependencies to appropriate sub-tasks
bd dep remove <old-blocker> <issue-id>
bd dep add <old-blocker> <subtask-that-actually-needs-it>
```

### Merge duplicate/overlapping issues

```bash
# Pick the primary (better description, more context)
# Close the duplicate with reference
bd close <duplicate-id> --comment "Merged into <primary-id>"

# Migrate any unique dependencies from duplicate
bd dep add <unique-blocker-from-duplicate> <primary-id>

# Update primary description to incorporate duplicate's context
bd update <primary-id> --description "Merged: also includes X from <duplicate-id>"
```

### Re-parent issues

When organizational structure changes:

```bash
# Remove old parent-child relationship
bd dep remove <issue-id> <old-parent-id> --type parent-child

# Add new parent-child relationship
bd dep add <issue-id> <new-parent-id> --type parent-child
```

### Resequence a dependency chain

When execution order assumptions were wrong:

```bash
# Remove the incorrect sequence
bd dep remove <was-first> <was-second>

# Add the corrected sequence
bd dep add <actually-first> <actually-second>

# Comment explaining the resequencing
bd comment <actually-second> "Resequenced: discovered that <actually-first> must complete first because X"
```

### Promote a task to epic

When a task becomes a body of work:

```bash
bd update <task-id> --type epic --description "Promoted to epic: scope expanded to include X, Y, Z"
```

### Demote an epic to task

When an epic turns out to be simpler than anticipated:

```bash
# Close unnecessary children
bd close <child-1> --comment "Absorbed into parent — simpler than expected"
bd close <child-2> --comment "Absorbed into parent — simpler than expected"

# Demote the epic
bd update <epic-id> --type task --description "Demoted: originally expected complex, turned out straightforward"
```

## Integration with development phases

### During research/spike

```bash
# Create spike issue
bd create "Spike: investigate X approach" -t task -p 1

# After spike, create/refine actual implementation issues based on findings
bd create "Implement X using Y approach (from spike)" -t task -p 2 --parent <epic>
bd dep add <spike-id> <implementation-id> --type discovered-from

# Close spike with summary
bd close <spike-id> --comment "Findings: Y approach viable, estimate N days, see implementation issue"
```

### During implementation

See "In-flight adaptation" above — continuously evolve as understanding deepens.

### During testing

```bash
# Bugs found during testing
bd create "Bug: test failure in scenario X" -t bug -p 1
bd dep add <bug-id> <feature-id> --type discovered-from

# If bugs block release, wire as blockers
bd dep add <critical-bug-id> <release-milestone-id>
```

### During review

```bash
# Issues raised in code review
bd create "Review feedback: refactor X for clarity" -t task -p 2
bd dep add <feedback-id> <original-pr-issue> --type discovered-from

# If blocking merge, mark as blocker
bd dep add <must-fix-feedback-id> <original-pr-issue>
```

### During validation/acceptance

```bash
# Acceptance criteria gaps
bd create "Acceptance gap: missing Y behavior" -t bug -p 1
bd dep add <gap-id> <feature-id>

# Update original feature with learnings
bd comment <feature-id> "Acceptance revealed missing Y — added as blocker"
```

## Architecture feedback loop

When implementation reveals architectural problems, update both the graph and flag documentation needs.

### Identifying architectural discoveries

Implementation discoveries that warrant architecture doc updates:
- Component dependency assumptions were wrong
- Integration patterns don't work as designed
- Performance characteristics differ significantly from design
- Security model has gaps
- Data flow differs from architectural diagrams
- Technology choices prove incompatible

### Workflow for architectural changes

When you discover an architectural issue during implementation:

```bash
# 1. Update the issue graph to reflect new reality
bd create "Auth must precede API gateway setup" -t task -p 0
bd dep add <new-auth-task> <api-gateway-task>

# 2. Comment on the architectural implication
bd comment <current-issue> "Implementation revealed architectural change: auth dependency exists that wasn't in design docs"

# 3. Create documentation update issue
bd create "Update architecture docs: add auth dependency to API gateway component" -t task -p 1
bd dep add <arch-doc-update> <release-milestone> --type related

# 4. Flag specific documentation that needs updating
bd comment <arch-doc-update> "Files to update: docs/architecture/system-design.md (component diagram), docs/architecture/integration-patterns.md (auth flow)"
```

### Examples of architectural feedback

**Component dependency changes:**
```bash
bd comment <issue> "Discovered that auth must happen before API gateway setup — this changes our component dependency model. Flagged for architecture doc update: docs/architecture/system-design.md"
```

**Integration pattern problems:**
```bash
bd comment <issue> "Event-driven pattern doesn't work for this use case due to latency requirements. Need synchronous RPC. Update docs/architecture/integration-patterns.md"
```

**Performance constraints:**
```bash
bd comment <issue> "Database query performance requires caching layer not in original design. Add caching tier to docs/architecture/data-architecture.md"
```

**Security gaps:**
```bash
bd comment <issue> "API exposes PII without authentication check. Security model in docs/architecture/security.md needs revision"
```

### When to update architecture docs immediately vs defer

Update architecture docs immediately:
- Critical path blocker that affects multiple teams
- Security vulnerability or compliance gap
- Fundamental design assumption invalidated

Defer architecture doc updates:
- Minor optimization or implementation detail
- Change isolated to single component
- Experimental approach not yet validated

Always create a beads issue to track deferred doc updates so they don't get lost.

## Key principles

1. **Evolve early, evolve often**: Update issues as soon as understanding changes, not in batches
2. **Preserve traceability**: Use `discovered-from` for issues found during other work
3. **Maintain graph health**: Zero cycles, appropriate density, accurate dependencies
4. **Trust the history**: Git tracks all changes; don't fear refactoring the graph
5. **Reflect after completing**: Use completion as a trigger to review downstream issues
6. **Periodic whole-graph review**: Don't let the forest get lost in the trees
7. **Close the architecture feedback loop**: When implementation reveals design problems, update both graph and documentation
8. **Commit the database**: After evolving the graph, commit `.beads/issues.jsonl` to preserve changes

## Manual sync workflow

After evolving the graph, commit changes to preserve them:

```bash
# Run pre-commit hooks to ensure database integrity
bd hooks run pre-commit

# Commit with descriptive message about what changed
git commit -m "chore(issues): [describe graph changes]"
```

Examples of commit messages:
- `chore(issues): split auth task into subtasks due to scope expansion`
- `chore(issues): add database migration blocker discovered during API work`
- `chore(issues): resequence tasks after architectural feedback`
- `chore(issues): create arch doc update issues for component dependency changes`
