---
name: issues-beads
description: Comprehensive reference for beads issue tracking with bd CLI.
---
# Issue tracking with beads

Symlink location: `~/.claude/skills/issues-beads/SKILL.md`
Slash command: `/issues:beads`

Beads is a git-friendly issue tracker that stores data in a Dolt database with native versioning and remote sync.
The `bd` CLI provides comprehensive issue, epic, and dependency management from the command line.
Data lives in `.beads/` at the repository root, making it portable and version-controllable.

Session workflow (default entry points):
- `/session-orient` — session start: orientation with AMDiRE documentation reading, cross-project context, and beads diagnostics
- `/session-plan` — structured planning after orientation
- `/session-review` — session review and retrospective
- `/session-checkpoint` — session wind-down: checkpoint with learnings capture and handoff preparation

Beads-layer commands (for repos without the full workflow):
- `/issues:beads-seed` (`~/.claude/skills/issues-beads-seed/SKILL.md`) — convert architecture docs into beads issues
- `/issues:beads-orient` (`~/.claude/skills/issues-beads-orient/SKILL.md`) — session start: run diagnostics, synthesize state, select work
- `/issues:beads-evolve` (`~/.claude/skills/issues-beads-evolve/SKILL.md`) — adaptive refinement: refactor graph structure and feed back to architecture
- `/issues:beads-checkpoint` (`~/.claude/skills/issues-beads-checkpoint/SKILL.md`) — session wind-down: update status, capture learnings, prepare handoff
- `/issues:beads-audit` (`~/.claude/skills/issues-beads-audit/SKILL.md`) — periodic graph health checks and maintenance
- `/issues:beads-prime` (`~/.claude/skills/issues-beads-prime/SKILL.md`) — minimal quick reference for token-constrained contexts

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
In the full workflow, `/session-orient` and `/session-checkpoint` compose these beads-layer commands with additional context assembly and documentation reading.

**Architecture feedback** happens when implementation reveals that original architectural assumptions need revision, triggering updates to architecture docs and potentially re-seeding portions of the graph.

## Command index

When to use each beads command:

| Command | Purpose | When to Use |
|---------|---------|-------------|
| session-orient | Full workflow orientation (composes beads-orient) | Session start (default) |
| session-plan | Structured planning after orientation | After orientation |
| session-review | Session review and retrospective | Mid-session or pre-checkpoint |
| session-checkpoint | Full workflow checkpoint (composes beads-checkpoint) | Session end (default) |
| beads-init | Setup beads without auto-commit hooks | New project initialization |
| beads-seed | Architecture docs → beads issues | Planning to execution transition |
| beads-orient | Pick optimal work from graph | Session start in beads-only repos |
| beads-evolve | Refactor graph structure + architecture feedback | Structural problems detected |
| beads-checkpoint | Update status, capture learnings, prepare handoff | Session end in beads-only repos |
| beads-audit | Graph health check and validation | Periodic maintenance |
| beads-prime | Quick command reference | Token-constrained contexts |

## Core concepts

### Issues

Issues are the fundamental unit of work, identified by short alphanumeric IDs like `bd-a3f8` or project-prefixed IDs like `ironstar-jzb`.
Each issue has a type (task, bug, feature, epic, milestone), priority (0-4, 0=highest, default=2), status (open, closed, in_progress), and optional labels.

Status lifecycle:
- **open**: Work not yet started or resumed after being blocked
- **in_progress**: Actively being worked on (the bd tool does not enforce this, but the team convention requires marking issues in_progress before beginning implementation)
- **closed**: Completed, abandoned, or merged as duplicate

### Epics

Epics are issues with type `epic` that serve as containers for related work.
Child issues can be created under epics with hierarchical IDs that auto-increment: `bd-a3f8.1`, `bd-a3f8.2`, and so on.
The beads tool supports up to three levels of hierarchical IDs for complex work breakdown structures, but the team convention is single-layer parent-child only: epics contain issues, not sub-epics.
Do not create nested epics without explicit human request.

Epics should represent coherent work packages, not just organizational groupings.
An epic becomes *eligible* for closure when all its child issues are closed, but eligible epics are intentionally kept open for human validation and follow-up issue creation.
See the closure policy in `/issues:beads-prime` for the authoritative convention.

### Dependencies

Dependencies encode relationships between issues using typed edges in the dependency graph.
The primary dependency types are:

- **blocks**: Hard blockers that affect the ready queue; the first issue must complete before the second can start
- **parent-child**: Epic/subtask relationships establishing hierarchical structure
- **tracks**: Soft associations for related work items that don't block execution
- **related** / **relates-to**: Bidirectional soft relationships indicating thematic connection without execution constraints
- **discovered-from**: Tracking issues found during other work, useful for tracing root causes
- **until**: Temporal dependencies for scheduled or time-bound work
- **caused-by**: Root cause tracking for bugs and issues
- **validates**: Testing or validation relationships
- **supersedes**: Replacement tracking for deprecated or obsoleted issues

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

Use `bd dep tree <id> --direction both` to understand dependency context and downstream impact for work prioritization.

## Dolt persistence

Beads uses a dolt database backend with native versioning.
Mutations auto-commit to dolt when `dolt.auto-commit` is enabled (the default after migration).
The dolt database is transported via `refs/dolt/data` on the same git remote as the repository itself.

### Push to remote

After a batch of mutations, push to the dolt remote for backup:

```bash
bd dolt push
```

### Checkpoint with label

For labeled checkpoints (e.g., before session end):

```bash
bd dolt commit -m "checkpoint: <description>"
bd dolt push
```

### Persistence frequency

- **Eager**: `bd dolt push` after each logical batch (creating an epic with children, wiring dependencies)
- **Session boundary**: At minimum, push before ending work via `/session-checkpoint`

### Hooks behavior

The `beads-init` command initializes beads without installing git hooks.
With the dolt backend, hooks are not needed for data persistence since mutations auto-commit to the dolt database.
The `prepare-commit-msg` hook is the only hook that performs useful work (adding agent identity trailers to git commits).

### Bootstrap: existing repo on a new host

When cloning a repo that already has dolt-backed beads (`refs/dolt/data` exists on the git remote), use `DOLT_CLONE` to pull the complete database in one step.
This avoids schema mismatches that occur with `CREATE DATABASE` + manual remote setup.

```bash
# 1. Get the database name and remote URL
db_name=$(jq -r '.dolt_database' .beads/metadata.json)
remote_url="git+$(git remote get-url origin)"

# 2. Clone the dolt database from the git remote
dolt --profile beads -p '' sql -q "CALL DOLT_CLONE('${remote_url}', '${db_name}')"

# 3. Create the marker directory that tells bd the dolt backend is active
mkdir -p .beads/dolt/
```

Verify with `bd status` and optionally `bd dolt pull` (which should report no changes).

Prerequisites: a running dolt sql-server on `127.0.0.1:3307` and the `beads` dolt CLI profile.
On nix-managed hosts, both are provided declaratively by vanixiets (dolt-sql-server module and home-manager dolt-config activation).

### Bootstrap: new repo with dolt backend

When setting up beads in a repo for the first time with dolt-native sync, the goal is to seed `refs/dolt/data` on the git remote so other clones can use `DOLT_CLONE`.

```bash
# 1. Initialize beads (creates the dolt database locally)
bd init --prefix <prefix>

# 2. Create the marker directory
mkdir -p .beads/dolt/

# 3. Derive the dolt remote URL from git origin and add it
remote_url="git+$(git remote get-url origin)"
dolt --profile beads -p '' sql -q \
  "USE \`<prefix>\`; CALL DOLT_REMOTE('add', 'origin', '${remote_url}')"

# 4. Push to seed refs/dolt/data on the git remote
bd dolt push

# 5. Verify the ref exists on the remote
git ls-remote origin refs/dolt/data
```

The database name matches the beads prefix (stored in `.beads/metadata.json` as `dolt_database`).
After this, any clone of the repo can bootstrap with the `DOLT_CLONE` approach above.

For repos migrating from the SQLite backend, use `scripts/migrate-beads-to-dolt.sh` which automates the migration, remote setup, and initial push.

## Common commands quick reference

### Creating and organizing work

Create a standalone issue with type and priority:

```bash
bd create "Implement authentication" -t feature -p 1
bd create "Fix login bug" -t bug -p 0 --deps "blocks:auth-epic,discovered-from:ui-task"
bd create "Add tests" -t task -p 2 --silent  # outputs only issue ID for scripting
```

The `--deps` flag allows inline dependency creation with syntax: `--deps "type:id,type:id,..."`.
The `--silent` flag suppresses all output except the issue ID, useful for shell scripts.

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
bd dep tree bd-a3f8                      # show what blocks this issue (downstream)
bd dep tree bd-a3f8 --direction up       # show what this issue blocks (upstream)
bd dep tree bd-a3f8 --direction both     # full context: blockers AND dependents
bd dep tree bd-a3f8 --format mermaid     # output as mermaid diagram
bd dep tree bd-a3f8 --max-depth 3        # limit tree depth
bd dep tree bd-a3f8 --status open        # filter by status
bd dep tree bd-a3f8 --type blocks        # filter by dependency type
bd dep tree bd-a3f8 --show-all-paths     # show all paths in diamond dependencies
```

The `--direction both` flag is essential for understanding full impact: it shows upstream blockers and downstream dependents in a single view.
Use `--show-all-paths` when diamond dependencies exist to see all possible traversal routes.

Detect circular dependencies that would create deadlocks:

```bash
bd dep cycles
```

Create soft bidirectional relationships (for cross-cutting concerns):

```bash
bd dep relate bd-a3f8 bd-xyz     # create bidirectional relationship
bd dep unrelate bd-a3f8 bd-xyz   # remove bidirectional relationship
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

Identify orphaned issues (referenced in commits but still open):

```bash
bd orphans
```

Check for stale issues (not updated recently):

```bash
bd stale
```

Monitor real-time issue state changes:

```bash
bd activity  # shows live feed of molecule state updates
```

View epic progress across all children:

```bash
bd epic status                    # all epics with completion counts
bd epic status --eligible-only    # epics where all children are closed
bd epic status --json             # structured output
```

Check epic closure eligibility (on-demand, when human requests):

```bash
bd epic close-eligible --dry-run  # on-demand only, when user requests epic closure review
```

Epics whose children are all closed are intentionally kept open for human validation and follow-up issue creation.
Do not proactively check, report, or suggest closing eligible epics.
The Kanban UI shows eligible epics in "In Review" status; the human initiates closure when ready.

Search and list operations:

```bash
bd search "authentication"
bd list --type bug --status open --priority 0
bd show <issue-id>                # detailed view of single issue
```

Repository statistics and status:

```bash
bd status  # quick human-readable summary (~20 lines, context-efficient)
bd stats   # alias for bd status, same output
```

### Issue lifecycle

Close an issue with context:

```bash
bd close <issue-id> --reason "Implemented in commit $(git rev-parse --short HEAD)"
bd close <issue-id> --suggest-next  # show newly unblocked issues after closing
```

Add comments separately when closing:

```bash
bd comments add <issue-id> "Implementation notes or context"
bd close <issue-id>
```

Reopen if needed:

```bash
bd reopen <issue-id>
```

Add comments to track progress or reasoning:

```bash
bd comments add <issue-id> "Starting implementation"
bd comments add <issue-id> "Progress: $(git log -1 --oneline)"
bd comments add <issue-id> "Blocked by external dependency, deferring"
```

Defer issues for later work:

```bash
bd defer <issue-id>    # mark as deferred
bd undefer <issue-id>  # remove deferred status
```

Delete an issue (use sparingly, prefer closing):

```bash
bd delete <issue-id>
```

### Graph analysis and work prioritization

Use bd commands for work prioritization and graph analysis:

```bash
# Top ready-to-work issues (priority-sorted)
bd ready

# Blocked issues and their blockers
bd blocked

# Full dependency context for a specific issue
bd dep tree <id> --direction both

# Epic progress overview
bd epic status

# Dependency health
bd dep cycles

# Installation and configuration health
bd doctor
```

For structured data when scripting:

```bash
# JSON output for machine parsing
bd list --json
bd ready --json
bd blocked --json
```

## Session workflow patterns

### Phase 1: Orientation (session start)

Run diagnostics and synthesize current state:

```bash
bd status              # quick summary
bd epic status         # epic progress
bd ready | head -1     # top pick for work selection
```

### Phase 2: Work selection

Identify the optimal next task:

```bash
# Get top ready issue
TOP=$(bd ready --json | jq -r '.[0].id')

# Full context: what blocks it AND what completing it unblocks
bd dep tree "$TOP" --direction both

# Detailed description and metadata
bd show "$TOP"
```

### Phase 3: During work

Mark issue as in-progress before beginning implementation:

```bash
bd update <issue-id> --status in_progress
bd comments add <issue-id> "Starting implementation"
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
bd comments add <issue-id> "Implemented in commit $(git rev-parse --short HEAD)"
bd close <issue-id> --suggest-next  # shows newly unblocked issues
```

Or use the `--reason` flag for closure context:

```bash
bd close <issue-id> --reason "Implemented in commit $(git rev-parse --short HEAD)"
```

Check what this unblocks:

```bash
bd dep tree <issue-id> --direction up
```

Epic closure eligibility (on-demand only, when user requests):

```bash
bd epic close-eligible --dry-run  # on-demand only, when user requests epic closure review
```

Push beads state to the dolt remote for backup:

```bash
bd dolt push
```

### Phase 5: Session wind-down

Use `/session-checkpoint` (or `/issues:beads-checkpoint` in beads-only repos) to update statuses, capture learnings, and prepare handoff.

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
bd close <duplicate-id> --reason "Duplicate of <primary-id>"
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
bd repair --dry-run
bd repair  # if repairs are needed
```

Check installation health and fix issues:

```bash
bd doctor  # comprehensive health check with auto-repair suggestions
```

Validate issue templates and content:

```bash
bd lint  # check issues for missing template sections
```

## Integration patterns

### With atomic commits

After each commit that progresses an issue:

```bash
bd comments add <issue-id> "Progress: $(git log -1 --oneline)"
```

Before committing, update the relevant issue:

```bash
bd comments add <issue-id> "Implemented in commit $(git rev-parse --short HEAD)"
bd close <issue-id>
```

Push beads state to the dolt remote after completing mutations.

### With branch workflow

When creating a feature branch, reference the issue ID:

```bash
git checkout -b <issue-id>-short-description
```

When merging:

```bash
bd comments add <issue-id> "Merged in PR #N"
bd close <issue-id>
```

### With code review

Before requesting review:

```bash
bd comments add <issue-id> "Ready for review: PR #N"
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
| Create with deps | `bd create "title" --deps "blocks:id1,discovered-from:id2"` |
| Create silent | `bd create "title" --silent` (outputs only ID) |
| Create epic | `bd create "title" -t epic -p priority` |
| Create child | `bd create "title" --parent epic-id` |
| **Inspection** | |
| Show issue | `bd show issue-id` |
| List issues | `bd list [filters]` |
| Search | `bd search "query"` |
| Status summary | `bd status` |
| Statistics | `bd stats` (alias for status) |
| **Modification** | |
| Update issue | `bd update issue-id --field value` |
| Add comment | `bd comments add issue-id "text"` |
| Close issue | `bd close issue-id [--reason "..."]` |
| Close with suggestions | `bd close issue-id --suggest-next` |
| Reopen issue | `bd reopen issue-id` |
| Delete issue | `bd delete issue-id` |
| Defer issue | `bd defer issue-id` |
| Undefer issue | `bd undefer issue-id` |
| **Dependencies** | |
| Add dependency | `bd dep add from-id to-id [--type type]` |
| Remove dependency | `bd dep remove from-id to-id` |
| Relate (bidirectional) | `bd dep relate id1 id2` |
| Unrelate | `bd dep unrelate id1 id2` |
| View dep tree | `bd dep tree issue-id [--direction up\|down\|both]` |
| Tree with depth | `bd dep tree issue-id --max-depth N` |
| Tree with filters | `bd dep tree issue-id --status open --type blocks` |
| Show all paths | `bd dep tree issue-id --show-all-paths` |
| Find cycles | `bd dep cycles` |
| **Workflow** | |
| Ready queue | `bd ready [filters]` |
| Blocked issues | `bd blocked [--json]` |
| Orphaned issues | `bd orphans` |
| Stale issues | `bd stale` |
| Activity feed | `bd activity` |
| Epic status | `bd epic status [--eligible-only]` |
| Check epic readiness (human-only closure) | `bd epic close-eligible --dry-run` |
| **Maintenance** | |
| Health check | `bd doctor` |
| Lint issues | `bd lint` |
| Repair database | `bd repair [--dry-run]` |
| Push to remote | `bd dolt push` |
| Pull from remote | `bd dolt pull` |
| Checkpoint | `bd dolt commit -m "..."` |
| Issue history | `bd history <id>` |
| **Labels** | |
| Manage labels | `bd label` |
| **Analysis** | |
| Ready issues | `bd ready` |
| Blocked issues | `bd blocked` |
| Dependency context | `bd dep tree <id> --direction both` |
| Epic progress | `bd epic status` |
| Graph health | `bd dep cycles` |
