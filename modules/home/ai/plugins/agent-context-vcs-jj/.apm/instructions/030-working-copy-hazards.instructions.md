---
description: The three working-copy hazard headlines and a pointer to the full hazard catalog in jj-version-control's hazards.md.
---

## Working-copy hazards

Three headlines: never relocate `@` off the wip join; path-scope every squash and check for `(divergent)` and `wip??` before squashing; treat surprising reads of shared state as transients until `jj op log` says otherwise.
Recovery for the destructive class is top-level `jj undo`; there is no `jj op undo`.
The full catalog — splice impossibility below the join, the clan-install second child, the `wip` bookmark slide, snapshot size gating, concurrent-session foreign modifications, auto-rebase commit-id churn, and the failures of sessions sharing one join — lives in the `jj-version-control` skill's `hazards.md`.
