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

## Reflect

Consider what was learned this session that the issue graph doesn't yet reflect:

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
- Should any priorities be adjusted based on new understanding?

## Capture

For each learning identified above, execute the appropriate update:

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
bd comment <issue-id> "Checkpoint: <summary of state>"
```

**Completed work:**
```bash
bd close <issue-id> --comment "Implemented in commit $(git rev-parse --short HEAD). <any notable learnings>"
```

## Handoff

Prepare for the next session to pick up cleanly.

**If work is complete:**
```bash
# Check what was unblocked
bd dep tree <completed-id> --direction up

# Check if any epics can close
bd epic close-eligible --dry-run
```

Review unblocked issues — do their descriptions need updating given what was learned?

**If work is incomplete:**

Leave a checkpoint comment on the in-progress issue:
```bash
bd comment <issue-id> "$(cat <<'EOF'
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

**Final commit:**
```bash
# Validate beads database integrity before committing
bd hooks run pre-commit

# Commit with meaningful message describing what changed
git commit -m "chore(issues): <describe what changed - closed issues, new discoveries, etc.>"
```

The commit message should explain WHAT changed in the issue graph, not just generic sync messages.
Examples:
- "chore(issues): close bd-xyz auth implementation, discover bd-abc blocker"
- "chore(issues): refactor epic dependencies after arch review"
- "chore(issues): add checkpoint for bd-xyz incomplete auth work"

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

Provide the user a brief summary of what was captured:
- Issues updated: X
- New issues created: Y
- Dependencies modified: Z
- Work completed/checkpointed: <issue-id(s)>

The next session can run `/issues:beads-orient` to see the updated project state.

---

*Reference docs (read only if deeper patterns needed):*
- `/issues:beads-evolve` — comprehensive adaptation patterns
- `/issues:beads` — comprehensive reference for all beads workflows and commands
