# Engineering Backlog

This backlog collects cross-cutting or future action items that emerge from reviews and planning.

Routing guidance:

- Use this file for non-urgent optimizations, refactors, or follow-ups that span multiple stories/epics.
- Must-fix items to ship a story belong in that story's `Tasks / Subtasks`.
- Same-epic improvements may also be captured under the epic Tech Spec `Post-Review Follow-ups` section.

| Date | Story | Epic | Type | Severity | Owner | Status | Notes |
| ---- | ----- | ---- | ---- | -------- | ----- | ------ | ----- |
| 2025-11-13 | 1.9 | 1 | Documentation | Medium | TBD | Open | Add zerotier network ID section to test-clan README.md (network db4344343b14b903, controller assignment, peer list). Estimated effort: 15 minutes. Required for Story 1.10 blackphos integration. |
| 2025-11-13 | 1.9 | 1 | Investigation | Medium | TBD | Open | Investigate clan-core service restart behavior: validate whether `clan machines update` should automatically restart services after vars update, or if manual restart is expected workflow. Document findings in architecture or deployment guide. |
| 2025-11-13 | 1.9 | 1 | Documentation | Low | TBD | Open | Document age key lifecycle in architecture docs: explain age key re-encryption workflow after VM redeployment (`clan secrets machines add <machine> <age-key> --force`). |
