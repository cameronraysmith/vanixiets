---
description: Periodic beads graph health checks and maintenance
---

# Beads audit

Periodic maintenance and health checks for the beads issue graph.
This command focuses on structural integrity of the beads graph.

## When to use

Run beads audit during:

- Weekly maintenance cycles
- After completing major milestones or epics
- Before major planning sessions
- When the issue graph feels disorganized or inconsistent
- After batch imports or major graph modifications

## Health check commands

Run these commands to assess graph health:

```bash
# Overall graph status
bd status

# Check and fix installation health (primary diagnostic tool)
bd doctor

# Check issues for missing template sections
bd lint

# Detect circular dependencies
bd dep cycles

# Find stale issues (not updated recently)
bd stale

# Identify orphaned issues (referenced in commits but still open)
bd orphans

# Show what's actually ready to work on
bd ready

# Show blocked issues
bd blocked

# List all issues (for manual inspection)
bd list

# Record and label agent interactions
bd audit record --prompt "..." --response "..."
```

## Common problems

### Orphaned issues

**Symptoms**: Issues with no epic parent, broken dependencies pointing to deleted issues, issues that should be part of an epic but aren't, or issues referenced in commits but still open.

**Detection**:
```bash
bd orphans                         # Identifies issues referenced in commits but still open
bd list --parent <epic-id>        # List children of specific epic
bd doctor                          # Comprehensive health check (includes broken references)
bd doctor --deep                   # Deep graph integrity validation
```

**Remediation**:
```bash
bd update <id> --parent <epic-id>  # Assign to epic (use --parent flag)
bd dep remove <id> <bad-dep-id>    # Remove broken dependency
bd delete <id>                      # Delete truly orphaned issue
bd orphans --fix                    # Close orphaned issues with confirmation
bd repair                           # Clean orphaned dependencies, labels, comments, events
```

### Dependency cycles

**Symptoms**: Issues that transitively depend on themselves, blocking all progress.

**Detection**:
```bash
bd dep cycles
```

**Remediation**:
```bash
bd dep remove <id> <id>              # Break the cycle
bd dep add <id> <correct-dep-id>     # Rewire correctly
```

### Stale issues

**Symptoms**: Issues not updated in weeks/months that may be obsolete, completed but not closed, or abandoned.

**Detection**:
```bash
bd stale
bd list | sort -k3              # Sort by update timestamp
```

**Remediation**:
```bash
bd delete <id>                  # Remove obsolete issue
bd update <id> --status done    # Close completed work
bd update <id> --status open    # Reset abandoned work
```

### Status drift

**Symptoms**: Issues marked `in_progress` but no longer actively worked, blocking dependent issues.

**Detection**:
```bash
bd list --status in_progress | grep -v "$(date +%Y-%m-%d)"
bd stale
```

**Remediation**:
```bash
bd update <id> --status open         # Reset to open
bd update <id> --status blocked      # Mark blocked if waiting
bd close <id>                         # Close if actually complete (prefer bd close over --status done)
bd blocked                            # Show all blocked issues for review
```

### Missing dependencies

**Symptoms**: Work that should block other work but doesn't, causing premature "ready" status.

**Detection**:
```bash
bd ready                        # Review what's marked ready
bd list --parent <epic-id>      # Review epic structure (use --parent flag)
```

**Remediation**:
```bash
bd dep add <dependent-id> <blocker-id>
```

### Test and garbage pollution

**Symptoms**: Test issues, experiments, or duplicate issues cluttering the graph.

**Detection**:
```bash
bd doctor --check=pollution                  # Detect test/garbage issues
bd list | grep -i "test\|experiment\|tmp"    # Manual search for test patterns
```

**Remediation**:
```bash
bd doctor --check=pollution --clean          # Delete test issues (with confirmation)
bd delete <id>                                # Manually remove test issues
```

## Graph visualization

If the `bv` viewer is available:

```bash
# Interactive visual exploration
bv

# Machine-readable health data
bv --robot-triage

# Check for drift from baseline
bv --check-drift
```

Use visualization to:
- Identify disconnected subgraphs
- Spot overly complex dependency chains
- Verify epic decomposition makes sense
- Find issues that should be merged

## Remediation patterns

### Restructuring an epic

When epic structure doesn't match implementation reality:

```bash
# List current structure
bd list --parent <epic-id>

# Move issues to different epic
bd update <id> --parent <new-epic-id>

# Split epic (create new epic, reassign issues)
bd create --type epic --title "Epic: New Focus Area"
bd update <story-id> --parent <new-epic-id>

# Merge epics (reassign all issues, delete empty epic)
bd list --parent <old-epic-id> | while read id; do
  bd update "$id" --parent <target-epic-id>
done
bd delete <old-epic-id>
```

### Cleaning up completed work

After epic completion:

```bash
# Close epic and all stories
bd close <epic-id>
bd list --parent <epic-id> | while read id; do
  bd close "$id"
done

# Check for epics ready to close automatically
bd epic close-eligible

# Or delete if no historical value
bd delete --cascade <epic-id>
```

### Fixing broken dependency chains

When dependencies are tangled:

```bash
# Remove all deps for issue
bd dep remove <id> $(bd show <id> | grep "depends:" | cut -d: -f2)

# Rebuild correct dependencies
bd dep add <id> <correct-dep-1>
bd dep add <id> <correct-dep-2>

# Verify ready status makes sense
bd ready
```

## Audit checklist

Run through this checklist during periodic maintenance:

1. **Structural integrity**:
   - `bd doctor` passes with no errors
   - `bd doctor --deep` validates full graph integrity
   - `bd dep cycles` reports no cycles

2. **Status accuracy**:
   - `bd ready` shows only truly unblocked work
   - `bd blocked` shows expected blocked work
   - `bd list --status in_progress` contains only active work
   - `bd stale` shows minimal results

3. **Graph cleanliness**:
   - `bd doctor --check=pollution` finds no test issues
   - `bd orphans` finds no issues referenced in commits but still open
   - All issues have epic parents (unless they are epics)
   - No orphaned or disconnected subgraphs
   - `bd lint` passes for all issues

4. **Logical coherence**:
   - Epic decomposition matches current understanding
   - Dependencies reflect true blocking relationships
   - Issue titles and descriptions are current

5. **Visualization check** (if using `bv`):
   - Graph structure is comprehensible
   - No obvious visual clutter or complexity
   - Epics form coherent clusters

## Automation potential

Consider scripting common audit tasks:

```bash
#!/usr/bin/env bash
# beads-health-check.sh

echo "=== Beads Health Check ==="
echo

echo "## Installation Health"
bd doctor || echo "FAILED: Doctor found issues"
echo

echo "## Dependency Cycles"
bd dep cycles && echo "OK: No cycles" || echo "FAILED: Cycles detected"
echo

echo "## Orphaned Issues"
orphan_count=$(bd orphans --json | jq length)
echo "Orphaned issues (in commits but still open): $orphan_count"
if [ "$orphan_count" -gt 0 ]; then
  echo "WARNING: Found orphaned issues"
fi
echo

echo "## Stale Issues"
stale_count=$(bd stale | wc -l)
echo "Stale issues: $stale_count"
if [ "$stale_count" -gt 10 ]; then
  echo "WARNING: High stale issue count"
fi
echo

echo "## Ready Work"
bd ready
echo

echo "## Blocked Work"
bd blocked
echo

echo "## In Progress (should be actively worked)"
bd list --status in_progress
echo

echo "## Template Compliance"
bd lint
```

Run this script weekly or before major planning sessions to catch drift early.

## Related commands

- `beads-seed.md` - Architecture docs to beads issues transition
- `beads-evolve.md` - Adaptive refinement during implementation
- `beads.md` - Comprehensive reference for all beads workflows and commands
- `beads-orient.md` - Session start diagnostics
