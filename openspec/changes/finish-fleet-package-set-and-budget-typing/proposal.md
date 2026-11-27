---
linear_story_id: CAM-137
linear_story_identifier: CAM-137
linear_story_title: "Finish the fleet package set and the envelope budget typing"
linear_story_url: https://linear.app/cameronraysmith/issue/CAM-137/finish-the-fleet-package-set-and-the-envelope-budget-typing
linear_story_state: Todo
linear_team: CAM
linear_project: den-ready-fleet
last_synced_state: Todo
last_synced_at: "2026-11-27T08:16:12Z"
review_round: 0
max_review_rounds: 3
attempt_log:
  - { at: "2026-11-27T08:16:12Z", transition: "Backlog->Todo", outcome: "posted", note: "Issue CAM-137 created in Todo in project 06049a4f18a4 (Den-ready fleet architecture), no label, with description seeded from proposal.md's Why and What Changes; state and project confirmed by read-only view; bind comment posted" }
---

## Why

`register-fleet-obligations` could not finish three pieces because another session holds the files they edit: two runtime tests still build their own nixpkgs instead of the fleet's package set, and the collector's envelope budget is still an untyped attribute set, so a misspelled field is silently ignored. Its verification also found two fleet rules stated in the specs but never shown to fail: dropping a host from the host registry, and adding a database without a backup. Splitting these off lets that change archive with everything it keeps already true, and gives the remainder one owner and one acceptance run.

## What Changes

**The last two runtime tests use the fleet's package set**
- From: `perses-greptimedb` and `shared-reference-tree` each import nixpkgs for their nodes.
- To: both read the per-system fleet package set, like the other nine runtime tests.
- Impact: non-breaking; their derivations are expected unchanged, and any difference is named with its cause.

**The envelope budget has a declared shape**
- From: `vanixiets.otelCollector.envelopeBudget` accepts any attribute set.
- To: `null` or a record of exactly `storeUrl`, `notifiedUnits` and `databases`; a misspelled field fails evaluation.
- Impact: non-breaking; both writers already set exactly these fields, and the ingress host's derivation is unchanged.

**Two fleet rules shown to fail when broken**
- A host record removed from the registry fails the fleet's checks, naming the host.
- A PostgreSQL database added on a backed-up host without a backup fails that host's machine check, naming the backup rule and the database's dump unit.
- Both run in throwaway copies of the tree; nothing committed changes for them.

**Sequencing**: the first two wait until the other session's edits to the two runtime tests and to the otel-collector service have landed. The mutants can run at once.

**Non-goals**: changing what any judge enforces; editing the test bodies; any other option of the otel-collector service.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `fleet-package-set-interface` (stratum: interface): ADDED "Runtime tests evaluate against the fleet package set". Trust boundary: the same package set is guaranteed at evaluation only; an equal derivation does not show that a runtime test behaves the same at run time.
- `fleet-ingress-interface` (stratum: interface): ADDED "The envelope budget has a declared shape". Trust boundary: the type rejects a malformed definition at evaluation; it does not check that `storeUrl` reaches a store or that the units and databases exist.

No capability is behavioral or world. The two mutants discharge scenarios that `fleet-host-registry` and `database-backup-interface` already state.

## Impact

- Code: `modules/vm-tests/perses-greptimedb.nix`, `modules/vm-tests/shared-reference-tree.nix`; the file holding `vanixiets.otelCollector.envelopeBudget` once the otel-collector change lands (today `modules/clan/services/otel-collector/flake-module.nix`).
- Depends on: the other session's unlanded edits to those files; `register-fleet-obligations` archiving first, since that change creates `fleet-package-set-interface` and A330.
- Acceptance: one `just drv-diff` from the parent to the commit, with an exact-path allow-list.
- Hosts: none deploys; no host's derivation changes.
