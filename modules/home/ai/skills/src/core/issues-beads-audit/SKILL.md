---
name: issues-beads-audit
description: Periodic beads graph health checks and maintenance procedures.
disable-model-invocation: true
---
# Beads audit

Periodic maintenance and health checks for the beads issue graph.
This skill covers both structural integrity and content quality of the beads graph, including signal table coverage, acceptance criteria adequacy, and confidence state health.

## When to use

Run beads audit during:

- Weekly maintenance cycles
- After completing major milestones or epics
- Before major planning sessions
- When the issue graph feels disorganized or inconsistent
- After batch imports or major graph modifications
- When bringing a legacy graph up to current signal table and confidence tracking standards
- After adopting new conventions (signal tables, confidence signals) that pre-existing issues lack

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

### Missing signal tables

**Symptoms**: Issues created before signal table conventions were adopted, or issues created by workflows that skip signal table seeding.

**Detection**:
```bash
# Count issues with and without signal tables
bd list --json | jq '[.[] | select(.status != "closed")] | length' # total open
bd list --json | jq '[.[] | select(.status != "closed") | select(.notes // "" | contains("stigmergic-signals"))] | length' # with tables
```

Compare counts to compute coverage percentage.
Issues with notes fields that lack `<!-- stigmergic-signals -->` delimiters have no signal table.

**Remediation**:

Signal table backfill is mechanical and automatable.
For each issue lacking a signal table, seed one with defaults: cynefin=complicated, surprise=0.0, progress matching current status (not-started for open, implementing for in_progress), escalation=none, planning-depth=standard, confidence=undemonstrated, evidence-freshness=absent, regression-guard=none.

```bash
# For each issue lacking a signal table:
NOTES=$(bd show <id> --json | jq -r '.[0].notes // ""')
# Prepend the default signal table template from stigmergic-convention
# Write back via bd update <id> --notes "$NEW_NOTES"
```

After backfill, adjust signals that have better-than-default values based on issue history.
Closed issues with verification in their closure reason may warrant confidence above `undemonstrated`.
Issues with known Cynefin classification from their epic or description context should have cynefin set accordingly.
These adjustments require judgment — flag them in the remediation report rather than applying automatically.

### Acceptance criteria gaps

**Symptoms**: Issues with missing, empty, or non-executable acceptance criteria.
Vague criteria like "should work correctly" or "implement the feature" that provide no testable condition.

**Detection**:
```bash
# Issues with empty or missing acceptance_criteria
bd list --json | jq '[.[] | select(.status != "closed") | select((.acceptance_criteria // "") == "")] | [.[].id]'
```

Manual inspection is needed to assess whether non-empty criteria are actually testable and severe.
Look for acceptance criteria that lack executable verification commands, that describe intent rather than observable behavior, or that would pass regardless of implementation correctness (zero severity).

**Remediation**:

Acceptance criteria quality requires judgment — flag affected issues in the remediation report for `/session-plan` to schedule via `beads-evolve`.
Do not rewrite acceptance criteria during audit; the planner needs specification context to write adequate criteria.

### Confidence-implementation drift

**Symptoms**: Implementation is ahead of evidence — code exists and issues are closed, but confidence tracking shows the claims are unsupported or weakly supported.

**Detection**:
```bash
# Closed issues with low confidence
bd list --json | jq '[.[] | select(.status == "closed") | select(.notes // "" | contains("stigmergic-signals"))] | .[]' | # for each, parse signal table and check confidence
```

Parse the signal table from each closed issue's notes.
Flag issues where confidence is `undemonstrated` or `prototype` on closed implementation work.
Flag issues where confidence is `validated` or higher but `regression-guard` is `none`.
Flag issues where `evidence-freshness` is absent or older than 30 days on active work.

**Remediation**:

Confidence drift on closed issues requires re-verification — flag in the remediation report for `/session-review` scoped to the affected epic.
Missing regression guards on validated work should be flagged for `/session-plan` to create regression-protection issues.

### Stale evidence

**Symptoms**: Evidence was produced long ago and the codebase has evolved since, making the evidence unreliable.

**Detection**:

Parse `evidence-freshness` from signal tables.
Compare against staleness thresholds:
- Implementation work: 30 days
- Operational work: 90 days
- Probe work: no staleness concern (findings are point-in-time by nature)

**Remediation**:

Stale evidence does not automatically demote confidence — it flags a re-verification need.
Include affected issues in the remediation report with a recommendation to re-run verification and update `evidence-freshness` if the evidence still holds.

## Graph review

Use bd commands to review graph structure:

```bash
# Full dependency graph for a specific epic
bd dep tree <epic-id> --direction both

# Health and drift detection
bd doctor

# Epic structure overview
bd epic status
```

Use graph review to identify disconnected subgraphs, spot overly complex dependency chains, verify epic decomposition makes sense, and find issues that should be merged.

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

After all children of an epic are closed:

```bash
# Check if any epics are ready for human review (epic closure is human-only)
bd epic close-eligible --dry-run

# Report eligible epics to the user for manual closure
# Do not close epics directly; the Kanban UI moves them to In Review automatically

# Or delete if no historical value (requires human decision)
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

5. **Graph structure check**:
   - `bd dep tree <epic-id> --direction both` shows comprehensible structure for each active epic
   - No excessively deep or wide dependency chains
   - Epics form coherent clusters per `bd epic status`

6. **Content quality and signal coverage**:
   - Signal table coverage exceeds 80% of open issues (100% for issues in active epics)
   - No closed implementation issues with confidence at `undemonstrated` or `prototype`
   - No `validated` or higher confidence issues with `regression-guard` at `none`
   - No `evidence-freshness` dates older than the staleness threshold for their issue type
   - Acceptance criteria present and non-empty on all implementation and convergence issues
   - Acceptance criteria include at least one executable verification command on complicated-domain and clear-domain issues

## Remediation report

When the audit identifies content quality issues that cannot be resolved mechanically, produce a structured remediation report in the relevant epic's notes field.
This report serves as planning input for `/session-plan` step 2, which checks for audit findings alongside docs-to-issues alignment.

The report uses a dedicated section in the epic's notes:

```
<!-- audit-findings -->
## Audit findings (YYYY-MM-DD)

### Mechanical fixes applied
- [list of signal table backfills, structural repairs, etc. — already done]

### Content remediation needed (for /session-plan)
- <issue-id>: acceptance criteria missing or non-executable
- <issue-id>: confidence at undemonstrated despite closed status; needs re-verification
- <issue-id>: description references superseded architecture; needs re-scoping
- <issue-id>: validated without regression guard; needs regression-protection issue

### Evidence refresh needed (for /session-review)
- <issue-id>: evidence-freshness stale (last: YYYY-MM-DD, threshold: N days)
<!-- /audit-findings -->
```

The report distinguishes three categories:
- *Mechanical fixes applied*: already executed by the audit (signal table backfill, structural repairs). Recorded for traceability.
- *Content remediation needed*: requires judgment and specification context. `/session-plan` consumes these as planning scope and delegates to `beads-evolve`.
- *Evidence refresh needed*: requires re-running verification. `/session-review` consumes these when scoped to the affected epic.

Write the remediation report via the standard read-modify-write protocol on the epic's notes field, preserving any existing signal table and checkpoint-context sections.

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
echo

echo "## Signal Table Coverage"
total=$(bd list --json | jq '[.[] | select(.status != "closed")] | length')
with_signals=$(bd list --json | jq '[.[] | select(.status != "closed") | select(.notes // "" | contains("stigmergic-signals"))] | length')
echo "Signal tables: $with_signals / $total open issues"
if [ "$with_signals" -lt "$((total * 80 / 100))" ]; then
  echo "WARNING: Signal table coverage below 80%"
fi
echo

echo "## Confidence Health"
closed_undem=$(bd list --json | jq '[.[] | select(.status == "closed") | select(.notes // "" | contains("confidence | undemonstrated"))] | length')
echo "Closed issues with undemonstrated confidence: $closed_undem"
if [ "$closed_undem" -gt 0 ]; then
  echo "WARNING: Confidence-implementation drift detected"
fi
echo
```

Run this script weekly or before major planning sessions to catch drift early.

## Programmatic usage

Most beads commands support global flags for scripting and automation:

```bash
# JSON output for machine parsing
bd status --json
bd ready --json
bd orphans --json
bd blocked --json

# Quiet mode (errors only)
bd doctor --quiet
bd lint --quiet

# Verbose/debug output
bd doctor --verbose
bd repair --verbose
```

Common scripting patterns:

```bash
# Check if any issues are ready
if [ "$(bd ready --json | jq length)" -gt 0 ]; then
  echo "Work available"
fi

# Export all open issues
bd list --status open --json > open-issues.json

# Batch operations with JSON parsing
bd list --json | jq -r '.[] | select(.priority == 0) | .id' | while read id; do
  bd update "$id" --assignee alice
done
```

## Related commands

- `/session-orient` — session start (default, composes beads-orient with additional context)
- `/session-checkpoint` — session wind-down (default, composes beads-checkpoint with additional context)
- `beads-seed.md` - Architecture docs to beads issues transition
- `beads-evolve.md` - Adaptive refinement during implementation
- `beads.md` - Comprehensive reference for all beads workflows and commands
- `beads-orient.md` - Session start diagnostics (beads-layer substrate)
- `preferences-validation-assurance` — evidence quality dimensions, confidence promotion chain, and regression harness design referenced by the content quality checks
- `stigmergic-convention` — signal table schema and field definitions for signal table backfill
