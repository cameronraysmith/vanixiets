# Session checkpoint

Symlink location: `~/.claude/commands/issues/beads-checkpoint.md`
Slash command: `/issues:beads-checkpoint`

Action prompt for session wind-down.
Capture learnings into the issue graph before context is lost.

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

**Final sync:**
```bash
# Ensure all changes are persisted
bd sync
```

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
- `/issues:beads-workflow` — full operational workflows
