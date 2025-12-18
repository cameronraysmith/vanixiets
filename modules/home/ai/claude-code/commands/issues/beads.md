---
description: Conceptual reference for beads issue tracking with bd CLI and bv viewer
---

# Issue tracking with beads

Symlink location: `~/.claude/commands/issues/beads.md`
Slash command: `/issues:beads`

Beads is a git-friendly issue tracker that stores data in SQLite with a JSONL file for synchronization.
The `bd` CLI provides comprehensive issue, epic, and dependency management from the command line.
Data lives in `.beads/` at the repository root, making it portable and version-controllable.

Action commands (start here):
- `/issues:beads-orient` (`~/.claude/commands/issues/beads-orient.md`) — session start: run commands, synthesize state, select work
- `/issues:beads-checkpoint` (`~/.claude/commands/issues/beads-checkpoint.md`) — session wind-down: capture learnings, prepare handoff
- `/issues:beads-review` (`~/.claude/commands/issues/beads-review.md`) — audit: review database against planning docs and repo state

Reference commands:
- `/issues:beads-workflow` (`~/.claude/commands/issues/beads-workflow.md`) — operational workflows
- `/issues:beads-evolve` (`~/.claude/commands/issues/beads-evolve.md`) — adaptive refinement patterns
- `/issues:beads-prime` (`~/.claude/commands/issues/beads-prime.md`) — minimal quick reference

## Core concepts

Issues are the fundamental unit of work, identified by short alphanumeric IDs like `bd-a3f8` or project-prefixed IDs like `ironstar-jzb`.
Each issue has a type (task, bug, feature, epic), priority (0-3, lower is higher), status (open, closed), and optional labels.

Epics are issues with type `epic` that serve as containers for related work.
Child issues can be created under epics with hierarchical IDs that auto-increment: `bd-a3f8.1`, `bd-a3f8.2`, and so on.
This hierarchy supports up to three levels of nesting for complex work breakdown structures.

Dependencies encode relationships between issues using four types: `blocks` for hard blockers that affect the ready queue, `parent-child` for epic/subtask relationships, `related` for soft associations, and `discovered-from` for tracking issues found during other work.

## Creating and organizing work

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
bd close bd-a3f8.1 --comment "Completed in commit abc123"
```

## Dependency networks

Dependencies form a directed graph that determines execution order and blocking relationships.
The `blocks` dependency type is the primary mechanism for sequencing work.

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
bd dep tree bd-a3f8              # show what blocks this issue
bd dep tree bd-a3f8 --reverse    # show what this issue blocks
bd dep tree bd-a3f8 --format mermaid  # output as mermaid diagram
```

Detect circular dependencies that would create deadlocks:

```bash
bd dep cycles
```

Remove dependencies when requirements change:

```bash
bd dep remove bd-a3f8.1 bd-a3f8.2
```

## Workflow operations

The ready queue shows issues with no open blockers, representing work that can start immediately:

```bash
bd ready
bd ready --type task --priority 0  # filter to high-priority tasks
```

The blocked view shows issues waiting on unresolved dependencies:

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

Search across all issues:

```bash
bd search "authentication"
bd list --type bug --status open --priority 0
```

View repository statistics:

```bash
bd stats
bd status
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

When starting a new development session, check the ready queue:

```bash
bd ready
```

Before committing, update the relevant issue:

```bash
bd comment <issue-id> "Implemented in commit $(git rev-parse --short HEAD)"
bd close <issue-id>
```

After closing tasks, check if any epics are now complete:

```bash
bd epic close-eligible --dry-run
```

For sprint-like workflows, filter to current priorities:

```bash
bd list --status open --priority 0 --priority 1
```

## Command reference

| Operation | Command |
|-----------|---------|
| Create issue | `bd create "title" -t type -p priority` |
| Create epic | `bd create "title" -t epic -p priority` |
| Create child | `bd create "title" --parent epic-id` |
| Show issue | `bd show issue-id` |
| Update issue | `bd update issue-id --field value` |
| Close issue | `bd close issue-id` |
| Reopen issue | `bd reopen issue-id` |
| Delete issue | `bd delete issue-id` |
| Add dependency | `bd dep add from-id to-id [--type type]` |
| Remove dependency | `bd dep remove from-id to-id` |
| View dep tree | `bd dep tree issue-id [--reverse]` |
| Find cycles | `bd dep cycles` |
| Ready queue | `bd ready` |
| Blocked issues | `bd blocked` |
| Epic status | `bd epic status [--eligible-only]` |
| Auto-close epics | `bd epic close-eligible` |
| Search | `bd search "query"` |
| List issues | `bd list [filters]` |
| Add comment | `bd comment issue-id "text"` |
| Manage labels | `bd label` |
| Statistics | `bd stats` |
