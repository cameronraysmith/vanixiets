---
description: Comprehensive reference for beads issue tracking with bd CLI and bv viewer
---

# Issue tracking with beads

Symlink location: `~/.claude/commands/issues/beads.md`
Slash command: `/issues:beads`

Beads is a git-friendly issue tracker that stores data in SQLite with a JSONL file for synchronization.
The `bd` CLI provides comprehensive issue, epic, and dependency management from the command line.
Data lives in `.beads/` at the repository root, making it portable and version-controllable.

Action commands:
- `/issues:beads-seed` (`~/.claude/commands/issues/beads-seed.md`) — convert architecture docs into beads issues
- `/issues:beads-orient` (`~/.claude/commands/issues/beads-orient.md`) — session start: run diagnostics, synthesize state, select work
- `/issues:beads-evolve` (`~/.claude/commands/issues/beads-evolve.md`) — adaptive refinement: refactor graph structure and feed back to architecture
- `/issues:beads-checkpoint` (`~/.claude/commands/issues/beads-checkpoint.md`) — session wind-down: update status, capture learnings, prepare handoff
- `/issues:beads-audit` (`~/.claude/commands/issues/beads-audit.md`) — periodic graph health checks and maintenance
- `/issues:beads-prime` (`~/.claude/commands/issues/beads-prime.md`) — minimal quick reference for token-constrained contexts

## Development lifecycle overview

Beads operates within a broader development lifecycle that separates architectural planning from execution tracking:

```
Architecture Phase (docs/architecture/*.md)
       │
       │ Knowledge artifacts: rationale, patterns, decisions
       │
       ▼ beads-seed
Implementation Phase (beads-first workflow)
       │
       │ orient → work → evolve → checkpoint
       │         ↓        ↑
       │         └────────┘ feedback loop
       │
       ▼ when structural problems emerge
Architecture updates (refine knowledge base)
```

**Key principle**: Beads is the source of truth for work items.
Architecture docs are knowledge and rationale artifacts.
They are complementary, not duplicative.

**beads-seed** transforms architecture documents into actionable beads issues, establishing the initial dependency graph for implementation.
This is the critical transition from planning to execution.

**beads-orient** starts each session by analyzing the graph state, synthesizing context, and selecting the optimal next task based on dependencies, priorities, and graph metrics.

**Work loop** involves progressing selected issues, discovering new tasks or blockers during implementation, and updating the graph to reflect actual constraints.

**beads-evolve** refactors the issue graph when structural problems emerge (circular dependencies, bottlenecks, misaligned priorities) and feeds insights back to architecture docs when assumptions change.

**beads-checkpoint** winds down sessions by updating issue statuses, capturing learnings in comments, and preparing handoff summaries for future sessions.

**Architecture feedback** happens when implementation reveals that original architectural assumptions need revision, triggering updates to architecture docs and potentially re-seeding portions of the graph.

## Command index

When to use each beads command:

| Command | Purpose | When to Use |
|---------|---------|-------------|
| beads-init | Setup beads without auto-commit hooks | New project initialization |
| beads-seed | Architecture docs → beads issues | Planning to execution transition |
| beads-orient | Pick optimal work from graph | Session start or status check |
| beads-evolve | Refactor graph structure + architecture feedback | Structural problems detected |
| beads-checkpoint | Update status, capture learnings, prepare handoff | Session end or before context switch |
| beads-audit | Graph health check and validation | Periodic maintenance |
| beads-prime | Quick command reference | Token-constrained contexts |

## Core concepts

### Issues

Issues are the fundamental unit of work, identified by short alphanumeric IDs like `bd-a3f8` or project-prefixed IDs like `ironstar-jzb`.
Each issue has a type (task, bug, feature, epic, milestone), priority (0-3, lower is higher), status (open, closed, in_progress), and optional labels.

Status lifecycle:
- **open**: Work not yet started or resumed after being blocked
- **in_progress**: Actively being worked on (optional convention, not enforced)
- **closed**: Completed, abandoned, or merged as duplicate

### Epics

Epics are issues with type `epic` that serve as containers for related work.
Child issues can be created under epics with hierarchical IDs that auto-increment: `bd-a3f8.1`, `bd-a3f8.2`, and so on.
This hierarchy supports up to three levels of nesting for complex work breakdown structures.

Epics should represent coherent work packages, not just organizational groupings.
An epic is eligible for closure when all its child issues are closed.

### Dependencies

Dependencies encode relationships between issues using four types:

- **blocks**: Hard blockers that affect the ready queue; the first issue must complete before the second can start
- **parent-child**: Epic/subtask relationships establishing hierarchical structure
- **related**: Soft associations indicating thematic connection without execution constraints
- **discovered-from**: Tracking issues found during other work, useful for tracing root causes

The dependency graph is a directed acyclic graph (DAG).
Circular dependencies are prohibited and detected by `bd dep cycles`.

Dependencies determine execution order through the ready queue: issues with no open blockers are ready for work.

### The DAG and graph metrics

The beads dependency graph forms a directed acyclic graph where nodes are issues and edges are dependencies.
Graph properties influence work selection:

- **Ready queue**: Issues with no open blockers (in-degree zero for blocking dependencies)
- **Blocked issues**: Issues waiting on unresolved dependencies
- **Critical path**: Longest dependency chain from open issues to final deliverables
- **Bottlenecks**: High-degree nodes whose completion unblocks many downstream tasks
- **Orphans**: Issues with no dependencies and no dependents (may indicate missing structure)

The `bv` viewer computes graph metrics like PageRank (global importance), betweenness centrality (bottleneck detection), and critical path analysis to inform work prioritization.

## Manual sync workflow

Beads uses a manual sync model for git integration.
Changes made with `bd` commands modify `.beads/issues.jsonl`, which must be committed explicitly.

### Commit beads changes

After any batch of `bd` modifications (creates, updates, closes, dependency changes):

```bash
# Validate and prepare for commit
bd hooks run pre-commit

# Commit the database
git add .beads/issues.jsonl
git commit -m "chore(issues): <description of changes>"
```

Commit frequency recommendations:
- **Eager**: After each logical batch (creating an epic with children, wiring dependencies)
- **Session boundary**: At minimum, commit before ending work via `/issues:beads-checkpoint`
- **Descriptive when relevant**: For significant changes, use specific messages like `chore(issues): close auth epic after implementation`

### After git pull/checkout/merge

When the git repository changes (pull, checkout, merge), import changes from JSONL:

```bash
bd sync --import-only
```

This updates the SQLite database from `.beads/issues.jsonl` without triggering export hooks.
Failing to sync after git operations leaves the database out of sync with the repository.

### Avoiding automatic hooks

The `beads-init` command initializes beads without installing git hooks for automatic sync.
This preserves manual control and integrates with existing atomic commit workflows.

If automatic hooks were installed (via `bd init` directly):
```bash
# Remove hooks if present
rm -f .git/hooks/post-checkout .git/hooks/post-merge .git/hooks/post-rewrite
```

## Common commands quick reference

### Creating and organizing work

Create a standalone issue with type and priority:

```bash
bd create "Implement authentication" -t feature -p 1
```

Create an epic to group related work:

```bash
bd create "User management system" -t epic -p 1
```

Create child tasks under an epic using the `--parent` flag, which auto-generates hierarchical IDs:

```bash
bd create "Design login flow" -p 2 --parent bd-a3f8      # becomes bd-a3f8.1
bd create "Implement JWT validation" -p 2 --parent bd-a3f8  # becomes bd-a3f8.2
bd create "Add session persistence" -p 2 --parent bd-a3f8   # becomes bd-a3f8.3
```

Link an existing issue to an epic retroactively:

```bash
bd dep add existing-issue-id epic-id --type parent-child
```

Update issue metadata as work evolves:

```bash
bd update bd-a3f8.1 --priority 0 --labels "critical,security"
bd update bd-a3f8.1 --status in_progress
bd update bd-a3f8.1 --description "Updated: also needs to handle edge cases"
```

### Managing dependencies

Add a blocking dependency where the first issue must complete before the second can start:

```bash
bd dep add bd-a3f8.1 bd-a3f8.2  # .1 blocks .2
```

Specify dependency type explicitly when needed:

```bash
bd dep add bug-123 feature-456 --type discovered-from
bd dep add task-789 epic-001 --type parent-child
```

Visualize the dependency tree for an issue:

```bash
bd dep tree bd-a3f8              # show what blocks this issue (downstream)
bd dep tree bd-a3f8 --reverse    # show what this issue blocks (upstream)
bd dep tree bd-a3f8 --direction both  # full context: blockers AND dependents
bd dep tree bd-a3f8 --format mermaid  # output as mermaid diagram
```

The `--direction both` flag is essential for understanding full impact: it shows upstream blockers and downstream dependents in a single view.

Detect circular dependencies that would create deadlocks:

```bash
bd dep cycles
```

Remove dependencies when requirements change:

```bash
bd dep remove bd-a3f8.1 bd-a3f8.2
```

### Workflow operations

View the ready queue (issues with no open blockers, representing work that can start immediately):

```bash
bd ready
bd ready --type task --priority 0  # filter to high-priority tasks
```

View blocked issues (waiting on unresolved dependencies):

```bash
bd blocked
bd blocked --json  # machine-readable output
```

View epic progress across all children:

```bash
bd epic status                    # all epics with completion counts
bd epic status --eligible-only    # epics where all children are closed
bd epic status --json             # structured output
```

Auto-close epics when all child issues are resolved:

```bash
bd epic close-eligible --dry-run  # preview what would close
bd epic close-eligible            # actually close eligible epics
```

Search and list operations:

```bash
bd search "authentication"
bd list --type bug --status open --priority 0
bd show <issue-id>                # detailed view of single issue
```

Repository statistics and status:

```bash
bd status  # quick human-readable summary (~20 lines, context-efficient)
bd stats   # detailed statistics
```

### Issue lifecycle

Close an issue with context:

```bash
bd close <issue-id> --comment "Implemented in commit $(git rev-parse --short HEAD)"
```

Reopen if needed:

```bash
bd reopen <issue-id>
```

Add comments to track progress or reasoning:

```bash
bd comment <issue-id> "Starting implementation"
bd comment <issue-id> "Progress: $(git log -1 --oneline)"
bd comment <issue-id> "Blocked by external dependency, deferring"
```

Delete an issue (use sparingly, prefer closing):

```bash
bd delete <issue-id>
```

### bv viewer for analysis

The `bv` viewer provides graph analysis and work prioritization.
Always redirect large outputs to temp files to avoid context pollution.

Quick human-readable summary:

```bash
bd status              # ~20 lines, context-efficient
bd epic status         # epic progress summary
```

Minimal structured output (safe for direct consumption):

```bash
bv --robot-next   # just the single top pick — small JSON
```

Full triage analysis (redirect to file):

```bash
REPO=$(basename "$(git rev-parse --show-toplevel)")
TRIAGE=$(mktemp "/tmp/bv-${REPO}-triage.XXXXXX.json")
bv --robot-triage > "$TRIAGE"

# Extract specific fields as needed
jq '.quick_ref' "$TRIAGE"              # summary + top 3 picks
jq '.recommendations[:3]' "$TRIAGE"    # top recommendations
jq '.quick_wins' "$TRIAGE"             # low-effort high-impact tasks
jq '.stale_alerts' "$TRIAGE"           # issues needing attention
jq '.project_health.graph_metrics' "$TRIAGE"  # cycles, bottlenecks

# Clean up
rm "$TRIAGE"
```

Priority validation (redirect to file):

```bash
REPO=$(basename "$(git rev-parse --show-toplevel)")
PRIORITY=$(mktemp "/tmp/bv-${REPO}-priority.XXXXXX.json")
bv --robot-priority > "$PRIORITY"
jq '.recommendations[:5]' "$PRIORITY"  # top priority misalignments
rm "$PRIORITY"
```

Deep graph insights (redirect to file, 3000+ lines):

```bash
REPO=$(basename "$(git rev-parse --show-toplevel)")
INSIGHTS=$(mktemp "/tmp/bv-${REPO}-insights.XXXXXX.json")
bv --robot-insights > "$INSIGHTS"   # PageRank, betweenness, critical path
# Extract fields with jq as needed
rm "$INSIGHTS"
```

## Session workflow patterns

### Phase 1: Orientation (session start)

Run diagnostics and synthesize current state:

```bash
bd status              # quick summary
bd epic status         # epic progress
bv --robot-next        # top pick for work selection
```

For structured analysis:

```bash
REPO=$(basename "$(git rev-parse --show-toplevel)")
TRIAGE=$(mktemp "/tmp/bv-${REPO}-triage.XXXXXX.json")
bv --robot-triage > "$TRIAGE"
jq '.quick_ref' "$TRIAGE"
rm "$TRIAGE"
```

### Phase 2: Work selection

Identify the optimal next task:

```bash
# Get top pick
TOP=$(bv --robot-next | jq -r '.recommendation.id')

# Full context: what blocks it AND what completing it unblocks
bd dep tree "$TOP" --direction both

# Detailed description and metadata
bd show "$TOP"
```

### Phase 3: During work

Mark issue as in-progress (optional):

```bash
bd update <issue-id> --status in_progress
bd comment <issue-id> "Starting implementation"
```

When discovering related issues or blockers:

```bash
# Create a new issue discovered during this work
bd create "Found: edge case in validation" -t bug -p 2

# Link it to the current work
bd dep add <new-issue-id> <current-issue-id> --type discovered-from
```

When encountering a blocker that should have been a dependency:

```bash
# Create the blocking issue
bd create "Need to refactor X first" -t task -p 1

# Wire the dependency
bd dep add <blocker-id> <current-issue-id>
```

Update descriptions or priorities as understanding evolves:

```bash
bd update <issue-id> --description "Updated: also needs to handle Y"
bd update <issue-id> --priority 0  # escalate if more critical than expected
```

### Phase 4: After completing work

Close the issue with context:

```bash
bd close <issue-id> --comment "Implemented in commit $(git rev-parse --short HEAD)"
```

Check what this unblocks:

```bash
bd dep tree <issue-id> --direction up
```

Check if any epics are now eligible for closure:

```bash
bd epic close-eligible --dry-run
bd epic close-eligible  # if appropriate
```

Commit beads changes:

```bash
bd hooks run pre-commit
git add .beads/issues.jsonl
git commit -m "chore(issues): close <issue-id> and update graph"
```

### Phase 5: Session wind-down

Use `/issues:beads-checkpoint` to update statuses, capture learnings, and prepare handoff.

## Maintenance operations

### Refactoring the issue graph

Split an issue that is too large:

```bash
# Create child tasks
bd create "Part 1: data layer" -p 2 --parent <original-id>
bd create "Part 2: API layer" -p 2 --parent <original-id>
bd create "Part 3: UI layer" -p 2 --parent <original-id>

# Wire dependencies if there is sequencing
bd dep add <part1-id> <part2-id>
bd dep add <part2-id> <part3-id>
```

Merge duplicate issues:

```bash
# Close the duplicate with reference
bd close <duplicate-id> --comment "Duplicate of <primary-id>"
```

Fix incorrectly wired dependencies:

```bash
bd dep remove <wrong-from> <wrong-to>
bd dep add <correct-from> <correct-to>
```

### Health checks

Detect circular dependencies (must be zero for healthy graph):

```bash
bd dep cycles
```

Check for orphaned dependency references:

```bash
bd repair-deps --dry-run
bd repair-deps  # if repairs are needed
```

Validate database integrity:

```bash
bd validate
```

## Integration patterns

### With atomic commits

After each commit that progresses an issue:

```bash
bd comment <issue-id> "Progress: $(git log -1 --oneline)"
```

Before committing, update the relevant issue:

```bash
bd comment <issue-id> "Implemented in commit $(git rev-parse --short HEAD)"
bd close <issue-id>
```

Commit beads changes alongside code changes to maintain synchronization.

### With branch workflow

When creating a feature branch, reference the issue ID:

```bash
git checkout -b <issue-id>-short-description
```

When merging:

```bash
bd close <issue-id> --comment "Merged in PR #N"
```

### With code review

Before requesting review:

```bash
bd comment <issue-id> "Ready for review: PR #N"
bd update <issue-id> --labels "needs-review"
```

After approval:

```bash
bd update <issue-id> --labels ""  # clear labels
bd close <issue-id>
```

### With sprint-like workflows

Filter to current priorities:

```bash
bd list --status open --priority 0 --priority 1
bd ready --priority 0  # high-priority ready queue
```

## Structuring project work

A well-structured issue graph follows the principle that dependencies should reflect actual execution constraints, not organizational hierarchy.
Over-specifying dependencies creates false bottlenecks; under-specifying loses the benefit of automated ready queue management.

For project bootstrapping, create epics for major phases with child tasks for concrete deliverables:

```bash
bd create "Infrastructure setup" -t epic -p 1
bd create "Initialize Nix flake" -p 2 --parent <epic-id>
bd create "Configure Cargo workspace" -p 2 --parent <epic-id>
bd create "Set up frontend build pipeline" -p 2 --parent <epic-id>
```

Then wire dependencies between tasks that have actual sequencing requirements:

```bash
bd dep add <nix-flake-id> <cargo-workspace-id>  # flake must exist before cargo setup
```

Milestone issues serve as synchronization points where multiple streams converge:

```bash
bd create "Ready for feature development" -t milestone -p 1
bd dep add <cargo-check-id> <milestone-id>
bd dep add <frontend-build-id> <milestone-id>
```

## Integration with development workflows

Beads complements higher-level planning tools by providing granular task-level tracking.
Product planning workflows handle epics, stories, and acceptance criteria; beads tracks the concrete implementation tasks and their dependencies.

Architecture docs capture the rationale, patterns, and decisions.
Beads tracks the actionable work items derived from those decisions.

When architectural assumptions change during implementation, use `/issues:beads-evolve` to refactor the graph and feed insights back to architecture docs.

## Command reference

| Operation | Command |
|-----------|---------|
| **Creation** | |
| Create issue | `bd create "title" -t type -p priority` |
| Create epic | `bd create "title" -t epic -p priority` |
| Create child | `bd create "title" --parent epic-id` |
| **Inspection** | |
| Show issue | `bd show issue-id` |
| List issues | `bd list [filters]` |
| Search | `bd search "query"` |
| Status summary | `bd status` |
| Statistics | `bd stats` |
| **Modification** | |
| Update issue | `bd update issue-id --field value` |
| Add comment | `bd comment issue-id "text"` |
| Close issue | `bd close issue-id [--comment "..."]` |
| Reopen issue | `bd reopen issue-id` |
| Delete issue | `bd delete issue-id` |
| **Dependencies** | |
| Add dependency | `bd dep add from-id to-id [--type type]` |
| Remove dependency | `bd dep remove from-id to-id` |
| View dep tree | `bd dep tree issue-id [--direction both]` |
| Find cycles | `bd dep cycles` |
| Repair orphans | `bd repair-deps [--dry-run]` |
| **Workflow** | |
| Ready queue | `bd ready [filters]` |
| Blocked issues | `bd blocked [--json]` |
| Epic status | `bd epic status [--eligible-only]` |
| Auto-close epics | `bd epic close-eligible [--dry-run]` |
| **Maintenance** | |
| Validate database | `bd validate` |
| Run hooks | `bd hooks run pre-commit` |
| Sync from JSONL | `bd sync --import-only` |
| **Labels** | |
| Manage labels | `bd label` |
| **Analysis (bv)** | |
| Top pick | `bv --robot-next` |
| Triage analysis | `bv --robot-triage > file` |
| Priority check | `bv --robot-priority > file` |
| Deep insights | `bv --robot-insights > file` |
