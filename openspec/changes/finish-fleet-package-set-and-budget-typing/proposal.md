---
linear_story_id: CAM-137
linear_story_identifier: CAM-137
linear_story_title: "Finish the fleet package set and the envelope budget typing"
linear_story_url: https://linear.app/cameronraysmith/issue/CAM-137/finish-the-fleet-package-set-and-the-envelope-budget-typing
linear_story_state: In Review
linear_team: CAM
linear_project: den-ready-fleet
last_synced_state: In Review
last_synced_at: "2026-11-27T09:29:20Z"
review_round: 0
max_review_rounds: 3
attempt_log:
  - { at: "2026-11-27T08:16:12Z", transition: "Backlog->Todo", outcome: "posted", note: "Issue CAM-137 created in Todo in project 06049a4f18a4 (Den-ready fleet architecture), no label, with description seeded from proposal.md's Why and What Changes; state and project confirmed by read-only view; bind comment posted" }
  - { at: "2026-11-27T09:00:28Z", transition: "Todo->In Progress", outcome: "posted", note: "first checked tasks.md box (1.1); workspace confirmed by whoami; state confirmed In Progress by read-only view" }
  - { at: "2026-11-27T09:29:20Z", transition: "In Progress->In Review", outcome: "posted", note: "verify.md written (pass with warnings); workspace confirmed by whoami; state confirmed In Review by read-only view; comment posted; description re-synced down-only for the reworded envelope-budget deliverable" }
---

## Why

`register-fleet-obligations` could not finish three pieces because another session holds the files they edit: two runtime tests still instantiate a package set of their own instead of reading the fleet's, and the collector's envelope budget is still an untyped attribute set, so a definition with a field the budget does not have is accepted. (A misspelled `storeUrl` already failed evaluation, because `otelEnvelope` reads `budget.storeUrl`; what the untyped set let through was an extra field.) Its verification also found two fleet rules stated in the specs but never shown to fail: dropping a host from the host registry, and adding a database without a backup. Splitting these off lets that change archive with everything it keeps already true, and gives the remainder one owner and one acceptance run.

## What Changes

**The last two runtime tests use the fleet's package set**
- From: `perses-greptimedb` and `shared-reference-tree` each instantiate a package set of their own for their nodes.
- To: both read the per-system fleet package set, like the other nine runtime tests.
- Impact: non-breaking; their derivations are expected unchanged, and any difference is named with its cause.

**The envelope budget has a declared shape**
- From: `vanixiets.otelCollector.envelopeBudget` accepts any attribute set.
- To: `null` or a record of exactly `storeUrl`, `notifiedUnits` and `databases`; a definition with any other field fails evaluation, naming it.
- Impact: non-breaking; both writers already set exactly these fields, and the ingress host's derivation is unchanged.

**Two fleet rules shown to fail when broken**
- A host record removed from the registry fails the fleet's checks, naming the host.
- A PostgreSQL database added on a backed-up host without a backup fails that host's machine check, naming the backup rule and the database's dump unit.
- Both run in throwaway copies of the tree; nothing committed changes for them, except that the registry assert in `modules/checks/machines.nix` now names the hosts that differ, because the mutant showed evaluation failing there without naming the host.

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

- Code: `modules/vm-tests/perses-greptimedb.nix`, `modules/vm-tests/shared-reference-tree.nix`; the file holding `vanixiets.otelCollector.envelopeBudget` once the otel-collector change lands (today `modules/clan/services/otel-collector/flake-module.nix`); the message of the registry assert in `modules/checks/machines.nix`.
- Depends on: the other session's unlanded edits to those files; `register-fleet-obligations` archiving first, since that change creates `fleet-package-set-interface` and A330.
- Acceptance: one `just drv-diff` from the parent to the commit, with an exact-path allow-list.
- Hosts: none deploys; no host's derivation changes.
