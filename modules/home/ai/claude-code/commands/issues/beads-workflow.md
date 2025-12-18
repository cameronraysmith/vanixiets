# Beads workflow for AI agents

Symlink location: `~/.claude/commands/issues/beads-workflow.md`
Slash command: `/issues:beads-workflow`

Reference document for operational workflows.
For active session work, prefer the action commands: `/issues:beads-orient` (session start) and `/issues:beads-checkpoint` (session wind-down).

Related commands:
- `/issues:beads-orient` (`~/.claude/commands/issues/beads-orient.md`) — action: session start
- `/issues:beads-checkpoint` (`~/.claude/commands/issues/beads-checkpoint.md`) — action: session wind-down
- `/issues:beads` (`~/.claude/commands/issues/beads.md`) — conceptual reference
- `/issues:beads-evolve` (`~/.claude/commands/issues/beads-evolve.md`) — adaptive refinement patterns
- `/issues:beads-prime` (`~/.claude/commands/issues/beads-prime.md`) — minimal quick reference

## Phase 1: Orientation

Run these commands at session start or when asked about project status:

```bash
# Quick human-readable summary (~20 lines, context-efficient)
bd status

# Epic progress summary
bd epic status
```

For structured data (redirect to file — bv outputs can be thousands of lines):

```bash
# Create repo-specific temp files to avoid conflicts between concurrent agents
REPO=$(basename "$(git rev-parse --show-toplevel)")
TRIAGE=$(mktemp "/tmp/bv-${REPO}-triage.XXXXXX.json")
bv --robot-triage > "$TRIAGE"

# Extract specific fields as needed
jq '.quick_ref' "$TRIAGE"              # summary + top 3 picks
jq '.recommendations[:3]' "$TRIAGE"    # top recommendations
jq '.quick_wins' "$TRIAGE"             # low-effort high-impact
jq '.stale_alerts' "$TRIAGE"           # issues needing attention
jq '.project_health.graph_metrics' "$TRIAGE"  # cycles, bottlenecks

# Clean up
rm "$TRIAGE"
```

For minimal structured output (safe for direct consumption):

```bash
bv --robot-next   # just the single top pick — small JSON
```

For specialized deep analysis (always redirect — these are very large):

```bash
REPO=$(basename "$(git rev-parse --show-toplevel)")
INSIGHTS=$(mktemp "/tmp/bv-${REPO}-insights.XXXXXX.json")
bv --robot-insights > "$INSIGHTS"   # 3000+ lines: PageRank, betweenness, critical path
# ... extract fields with jq ...
rm "$INSIGHTS"
```

## Phase 2: Work selection

To identify what to work on next:

```bash
# Get top pick (minimal output, safe for direct consumption)
TOP=$(bv --robot-next | jq -r '.recommendation.id')

# Full context: what blocks it AND what completing it unblocks
bd dep tree "$TOP" --direction both

# Detailed description and metadata
bd show "$TOP"
```

The `--direction both` flag is essential: it shows upstream blockers (down) and downstream dependents (up), giving full impact context.

For priority validation (redirect — output can be large):

```bash
REPO=$(basename "$(git rev-parse --show-toplevel)")
PRIORITY=$(mktemp "/tmp/bv-${REPO}-priority.XXXXXX.json")
bv --robot-priority > "$PRIORITY"
jq '.recommendations[:5]' "$PRIORITY"  # top misalignments
rm "$PRIORITY"
```

This compares computed graph importance against assigned priorities and flags misalignments.

## Phase 3: Lifecycle management

### Before starting work

Optionally mark the issue as in-progress (if the project uses this convention):

```bash
bd update <issue-id> --status in_progress
```

Add a comment noting work is starting:

```bash
bd comment <issue-id> "Starting implementation"
```

### During work

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

### After completing work

Close the issue with a comment referencing the implementation:

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

### Abandoning or deferring work

If work cannot be completed:

```bash
# Add context about why
bd comment <issue-id> "Blocked by external dependency, deferring"

# Reset status if it was in_progress
bd update <issue-id> --status open

# Optionally add a label
bd update <issue-id> --labels "deferred"
```

## Phase 4: Maintenance operations

### Refactoring the issue graph

Split an issue that's too large:

```bash
# Create child tasks
bd create "Part 1: data layer" -p 2 --parent <original-id>
bd create "Part 2: API layer" -p 2 --parent <original-id>
bd create "Part 3: UI layer" -p 2 --parent <original-id>

# Wire dependencies if there's sequencing
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

```bash
# Detect circular dependencies (must be zero for healthy graph)
bd dep cycles

# Check for orphaned dependency references
bd repair-deps --dry-run

# Validate database integrity
bd validate
```

## Integration patterns

### With atomic commits

After each commit that progresses an issue:

```bash
bd comment <issue-id> "Progress: $(git log -1 --oneline)"
```

### With branch workflow

When creating a feature branch:

```bash
# Branch name should reference issue
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

## Command quick reference

| Phase | Command | Purpose |
|-------|---------|---------|
| Orient | `bd status` | Quick human-readable summary (~20 lines) |
| Orient | `bd epic status` | Epic progress |
| Orient | `bv --robot-next` | Minimal JSON: just the top pick |
| Orient | `bv --robot-triage > $(mktemp)` | Full triage (redirect to avoid context pollution) |
| Select | `bd dep tree <id> --direction both` | Full dependency context |
| Select | `bd show <id>` | Issue details |
| Start | `bd update <id> --status in_progress` | Mark as active |
| Start | `bd comment <id> "Starting"` | Log start |
| During | `bd create ... --parent <id>` | Create sub-issues |
| During | `bd dep add <new> <current> --type discovered-from` | Link discoveries |
| Finish | `bd close <id> --comment "..."` | Complete with context |
| Finish | `bd epic close-eligible` | Auto-close completed epics |
| Health | `bd dep cycles` | Detect circular deps |
| Health | `bd validate` | Database integrity |
