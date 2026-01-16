---
description: Session wind-down action - capture learnings into issue graph, prepare handoff
---

# Session checkpoint

Symlink location: `~/.claude/commands/issues/beads-checkpoint.md`
Slash command: `/issues:beads-checkpoint`

Action prompt for session wind-down.
Capture learnings into the issue graph before context is lost.

**Purpose**: End of session status updates and handoff preparation.
If you need to refactor the issue graph structure during checkpoint (e.g., split epics, merge issues, restructure dependencies), use `/issues:beads-evolve` first, then complete the checkpoint workflow.

## Run wind-down diagnostics

Execute these commands now:

```bash
# Current state (compare to session start)
bd status

# What changed this session
bd activity

# Epic progress change
bd epic status

# Health check before commit
bd dep cycles
```

The activity feed shows what happened this session.
Epic status shows progress advancement.
Cycle check prevents committing a corrupted graph.

For structured session summary:

```bash
# Create repo-specific temp file
REPO=$(basename "$(git rev-parse --show-toplevel)")
SUMMARY=$(mktemp "/tmp/bd-${REPO}-checkpoint.XXXXXX.json")
bv --robot-triage > "$SUMMARY"

# Session-relevant extractions
jq '.quick_ref' "$SUMMARY"                    # current counts
jq '.project_health.graph_metrics' "$SUMMARY" # health metrics
jq '.stale_alerts' "$SUMMARY"                 # attention needed

# Clean up when done
rm "$SUMMARY"
```

## Scale-aware session summary

Determine session scope by counting issues touched:

```bash
# Count issues modified this session (from activity feed)
bd activity | grep -E "^[→✓✗⊘+]" | wc -l
```

Tailor summary depth to session scope:

**Small sessions (1-3 issues touched)**:
- Full detail on each change with complete before/after state
- Include full descriptions for modified issues
- Show complete dependency changes with rationale

**Medium sessions (4-10 issues touched)**:
- Summary table of changes by category:
  - Closed: list with brief completion notes
  - Updated: list with what changed
  - Created: list with traceability
  - Dependencies: count of additions/removals
- Highlight key closures and discoveries

**Large sessions (10+ issues touched)**:
- Epic-level aggregation of changes
- Statistics only: "8 closed, 3 created, 12 dependencies modified"
- Only highlight critical changes:
  - Blockers discovered during work
  - Scope corrections that affect downstream
  - Priority changes based on new understanding
- Per-epic progress deltas: "Domain layer: 42% → 58% (+5 closed)"

Determine scope tier:

```bash
# Rough session scope from recent activity
bd activity --limit 50 | head -20
```

## Graph health verification

Before committing, verify graph integrity:

```bash
# Must be zero — cycles corrupt the graph
bd dep cycles

# Check for structural issues
bd lint

# Confirm ready queue makes sense
bd ready | head -5
```

If cycles are detected:

```bash
# Identify the cycle
bd dep cycles --verbose

# Break the cycle by removing the inappropriate dependency
bd dep remove <upstream> <downstream>
```

If lint issues are found, resolve before committing.
This prevents corrupting the graph during wind-down.

## Reflect

Consider what was learned this session that the issue graph does not yet reflect.

**Scope changes**
- Was the work larger or smaller than the issue described?
- Did implementation reveal complexity not anticipated?
- Should the issue description be updated to reflect actual scope?

**Discovered work**
- Were bugs found during implementation?
- Was technical debt identified that should be tracked?
- Are there follow-up enhancements worth capturing?

**Dependency corrections**
- Were any listed blockers not actually blocking?
- Were hidden prerequisites discovered?
- Can work that was assumed sequential actually proceed in parallel?

**Priority shifts**
- Did this work reveal that other issues are more/less critical than assigned?
- Were any P3 items actually critical blockers?
- Were any P1 items actually low-impact?

## Priority recalibration

If reflection revealed priority mismatches, update before committing:

```bash
# Issue proved more critical than marked
bd update <id> --priority 1

# Issue proved less critical than marked
bd update <id> --priority 3

# Add context for the change
bd comments add <id> "Priority adjusted: discovered this blocks X during implementation"
```

Common recalibration patterns:
- Infrastructure issues often prove higher priority once downstream work begins
- Optional enhancements sometimes prove necessary for core functionality
- Assumed blockers sometimes prove to have workarounds

## Capture

For each learning identified above, execute the appropriate update.

**Scope/understanding changes:**
```bash
bd update <issue-id> --description "Revised: <what changed and why>"
```

**Discovered issues:**
```bash
# Create with traceability to current work
bd create "<title>" -t <bug|task|feature> -p <priority>
bd dep add <new-id> <current-issue-id> --type discovered-from
```

**Dependency corrections:**
```bash
# Remove false dependencies
bd dep remove <not-actually-blocking> <issue-id>

# Add discovered dependencies
bd dep add <actual-blocker> <issue-id>
```

**Progress state** (if work incomplete):
```bash
bd comments add <issue-id> "Checkpoint: <summary of state>"
```

**Completed work:**
```bash
# Option A: Close with reason
bd close <issue-id> --reason "Implemented in commit $(git rev-parse --short HEAD). <any notable learnings>"

# Option B: Close and see what was unblocked
bd close <issue-id> --reason "Implemented in..." --suggest-next

# Option C: Separate close and comment
bd close <issue-id>
bd comments add <issue-id> "Implemented in commit $(git rev-parse --short HEAD). <learnings>"
```

## Unblock chain visibility

When closing issues, show the cascade effect:

```bash
# See what completing this unblocked
bd close <id> --reason "..." --suggest-next

# Show full unblock chain
bd dep tree <closed-id> --direction up
```

Extract structured unblock data:

```bash
# Count direct and transitive unblocks
bd dep tree <closed-id> --direction up --json | jq '{
  direct: [.children[] | .id],
  direct_count: [.children[]] | length,
  total_downstream: [.. | .id? // empty] | unique | length
}'
```

Present the cascade:
- "Closing nix-50f.2 unblocked 3 issues (nix-50f.1, nix-l2a.2, nix-l2a.5)"
- "These 3 issues unblock 7 more downstream"
- "Total downstream impact: 10 issues now closer to ready"

This demonstrates session impact and helps users understand graph flow.

## Epic impact aggregation

For medium and large sessions, show epic-level progress change:

```bash
# Epic progress overview
bd epic status
```

Present as progress deltas:
- "Domain layer: 42% → 58% (closed 5 issues)"
- "Infrastructure: 20% → 35% (closed 3 issues, created 2)"
- "Frontend: unchanged (0 issues touched)"

For large sessions, aggregate by epic rather than listing individual issues:

```bash
# Extract issues by epic from activity
bd activity | grep "✓" | while read line; do
  id=$(echo "$line" | awk '{print $2}')
  bd show "$id" --short
done
```

This provides high-level progress visibility without overwhelming detail.

## Handoff

Prepare for the next session to pick up cleanly.

**If work is complete:**
```bash
# Option A: Close and immediately see what was unblocked
bd close <issue-id> --reason "Implemented in..." --suggest-next

# Option B: Manual review of dependencies
bd dep tree <completed-id> --direction up

# Check if any epics can close
bd epic close-eligible --dry-run
```

Review unblocked issues — do their descriptions need updating given what was learned?

**If work is incomplete:**

Leave a checkpoint comment on the in-progress issue:
```bash
bd comments add <issue-id> "$(cat <<'EOF'
Checkpoint: <date/session identifier>

Done:
- <what was accomplished>

Remaining:
- <what still needs to be done>

Learnings:
- <key insights that affected approach>

Suggested next steps:
- <where to pick up>
EOF
)"
```

Note: Use `bd update <id> --claim` to atomically claim an issue when resuming work (sets assignee + status to in_progress, fails if already claimed).

## Narrative handoff synthesis

Produce a prose summary for the next session:

```
Session Summary:

Completed:
- <issue-id>: <brief description of what was implemented>
- <issue-id>: <brief description>

Discovered:
- <issue-id>: <why this was created, what triggered discovery>

Learned:
- <key insight that changed understanding>
- <assumption that proved incorrect>

Next:
- Recommended starting point: <issue-id> (<why this is the logical next step>)
- Alternative entry points: <issue-id>, <issue-id>

Warnings:
- <blockers discovered but not resolved>
- <scope risks identified>
- <concerns that may affect future work>
```

This mirrors beads-orient's synthesis section but for session end.
The next session can use this summary plus `/issues:beads-orient` to quickly resume.

## Final commit

Execute the commit sequence:

```bash
# Validate beads database integrity
bd hooks run pre-commit

# Ensure DB file is staged
git add .beads/issues.jsonl

# Commit with meaningful message
git commit -m "chore(issues): <describe what changed>"
```

The commit message should explain WHAT changed in the issue graph, not just generic sync messages.

**Small sessions**: Name specific issues
- "chore(issues): close bd-xyz auth implementation, discover bd-abc blocker"

**Medium sessions**: Summarize by category
- "chore(issues): close 5 domain issues, update infrastructure dependencies"

**Large sessions**: Epic-level summary
- "chore(issues): advance domain epic to 58%, infrastructure sprint complete"

## Verify next work is discoverable

Before ending the session, ensure the next agent can pick up cleanly via `/issues:beads-orient`.

```bash
# Quick check of top recommendation
bv --robot-triage | jq '.quick_ref'

# Or minimal: just the top pick
bv --robot-next

# Review its description
bd show <top-recommendation-id>
```

If the description is stale or incomplete based on what was learned this session:
```bash
bd update <top-recommendation-id> --description "Updated: <incorporate session learnings that affect this issue>"
```

This applies whether work was completed or interrupted:
- **Completed milestone**: Next issue's description should reflect any context discovered during the completed work
- **Interrupted work**: Current issue should have checkpoint comment, AND next logical issue should be accurate

The issue graph becomes the handoff — no complex session notes needed.
When descriptions are accurate, `/issues:beads-orient` in the next session will find actionable, up-to-date work.

## Summary for user

Provide the user a summary scaled to session scope.

**Small sessions**: Full detail
- Issues closed: <list with completion notes>
- Issues updated: <list with what changed>
- Issues created: <list with traceability>
- Dependencies modified: <list with rationale>
- Unblock cascade: <what is now ready>

**Medium sessions**: Category summary
- Closed: X issues (<key ones named>)
- Updated: Y issues
- Created: Z issues
- Dependencies: N additions, M removals
- Epic progress: <deltas for affected epics>
- Next session: <top recommendation>

**Large sessions**: Executive summary
- Statistics: "8 closed, 3 created, 12 dependencies modified"
- Epic progress: <deltas>
- Key changes: <only critical items>
- Next session: <top recommendation with rationale>

The next session can run `/issues:beads-orient` to see the updated project state.

---

*Reference docs (read only if deeper patterns needed):*
- `/issues:beads-evolve` — comprehensive adaptation patterns
- `/issues:beads` — comprehensive reference for all beads workflows and commands
