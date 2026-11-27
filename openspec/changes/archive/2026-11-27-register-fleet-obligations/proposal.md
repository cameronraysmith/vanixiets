---
linear_story_id: CAM-135
linear_story_identifier: CAM-135
linear_story_title: "Register each fleet host rule once and test every rule the same way"
linear_story_url: https://linear.app/cameronraysmith/issue/CAM-135/register-each-fleet-host-rule-once-and-test-every-rule-the-same-way
linear_story_state: Done
linear_team: CAM
linear_project: den-ready-fleet
last_synced_state: Done
last_synced_at: "2026-11-27T08:22:07Z"
review_round: 0
max_review_rounds: 3
attempt_log:
  - { at: "2026-11-26T23:04:01Z", transition: "Backlog->Todo", outcome: "posted", note: "Issue CAM-135 created in Todo in project 06049a4f18a4 (Den-ready fleet architecture), no label, with description seeded from proposal.md's Why and What Changes; state and project confirmed by read-only view; bind comment posted. A first create attempt with --json returned non-JSON output and created nothing (project query showed no new issue before the retry)" }
  - { at: "2026-11-27T07:09:21Z", transition: "Todo->In Progress", outcome: "posted", note: "Fired on the first checked task; state confirmed In Progress by read-only view; milestone comment posted" }
  - { at: "2026-11-27T07:42:34Z", transition: "In Progress->In Review", outcome: "posted", note: "Fired on verify.md creation (PASS WITH WARNINGS: commit verified for landing, archive blocked by open tasks); description re-synced from the corrected proposal.md (26 conditions, eleven fixture copies, held tests and envelope typing following, docs-site checks changing); state confirmed In Review by read-only view; milestone comment posted" }
  - { at: "2026-11-27T08:22:07Z", transition: "In Review->Done", outcome: "posted", note: "Fired after openspec archive; documents upserted to project 06049a4f18a4: world-assumptions updated in place, fleet-ingress-interface, fleet-obligation-registry-interface and fleet-package-set-interface created and their ids stored in openspec/linear.yaml; state confirmed Done by read-only view; archive comment posted. Code and docs review sub-gates waived by the operator" }
---

## Why

The machine checks enforce twelve fleet-wide rules about host configuration, and every rule is hand-wired into one check file, where its name appears in four places. Every new rule has meant another edit to that shared file. The check helpers repeat themselves: eleven copies of one test shape, twenty-six duplicated platform conditions, and thirteen test files that each build their own package set. An unused, risky package channel is still documented as the way to patch a package, and two configuration shapes are never checked. The fleet is moving toward den, where each rule is declared once beside the code it governs. With this change a new rule is declared beside its code plus one line in a pinned list, and every rule is tested the same way. Every host builds exactly as it does now.

## What Changes

**Host rules registered once**
- From: `modules/checks/machines.nix` binds, calls, tests and names each of eleven judges by hand, plus a separate `withNetworkTargets` path for the twelfth; darwin-only judges are picked by a class test written into the fold.
- To: a flake-parts option `fleetObligations.<name> = { classes; failures; }`; each judge registers in the file that defines it; the machine checks fold every entry whose `classes` include the host's class and fail with the messages of the judges that failed.
- Impact: non-breaking; every host and check keeps its derivation; a failure message lists only failing rules.

**One way to test a rule against its fixtures**
- From: eleven fixture checks each hand-copy a `misjudges` filter that names wrong cases only; ten move in this change's commit, and the host-key check, added after it was planned, follows before the change closes.
- To: `flake.lib.judgeCases` and `flake.lib.mkJudgeCheck`, which report each wrong case with expected and actual counts and the judge's messages; `perses-config` and the nix-unit checks keep their own form.
- Impact: non-breaking; derivations unchanged; each check keeps its literal size-class entry.

**Duplicate platform conditions removed**
- From: 26 check modules repeat, inside their size-class entry, the `system == "x86_64-linux"` condition that already encloses the whole module.
- To: the inner repetition is removed; modules where the size-class entry has no enclosing condition keep theirs.

**Tests use the fleet's package set**
- From: eleven runtime tests and two fixture checks build their own nixpkgs.
- To: each reads the fleet's per-system package set; the devin-worker check shares one per system. Two of the runtime tests, held by another change in flight, follow in `finish-fleet-package-set-and-budget-typing`.
- Impact: evaluated against the parent, no runtime-test or check derivation changes.

**Unused patched channel removed**
- From: `pkgs.patched` is exported and documented; nothing reads it, and reading it would build during evaluation.
- To: removed; ADR-0017 is amended; the broken-package guide and five architecture and reference documents describe patching a single package instead.

**Two configuration shapes declared**
- From: the collector's envelope budget is an untyped attribute set; the observability host table has no schema.
- To: a validator checks the host table's rows inside an existing check. Typing the budget as a record of its three fields moved to `finish-fleet-package-set-and-budget-typing`, which waits on the change holding the collector service.

**Non-goals**: renaming judges or the machine-check attributes; changing what any judge enforces; giving deferred scheelite a machine check; deriving any literal check oracle; touching the poisoned `flake` argument in the omnigent-workers check; the nixidy package set; the `nixpkgs` and `unstable` channels.

**Resolved before apply**
- Stibnite's `controller` inventory tag was renamed to `deployer-workstation` by the host-registry change. Nothing in this change reads the tag.

## Capabilities

### New Capabilities

- `fleet-obligation-registry-interface` (stratum: interface): the `fleetObligations` option and its entry shape; the fold the machine checks run and its message; `flake.lib.judgeCases` and `flake.lib.mkJudgeCheck` and what they report; one system condition per check module. Trust boundary: the registry guarantees that every registered judge runs on every machine check of its class. It does not guarantee that a judge is correct beyond its fixtures, and it says nothing about a host with no machine check (deferred scheelite, covered only by fleet-wide checks). A judge sees only the evaluated configuration, not the deployed host.
- `fleet-package-set-interface` (stratum: interface): runtime tests and fixture checks evaluate against the per-system fleet package set; the channels overlay exports no `patched`. Trust boundary: the same package set is guaranteed at evaluation only. Equal derivations do not mean a runtime test behaves the same, and nothing here covers top-level outputs such as nixidy.

### Modified Capabilities

- `fleet-ingress-interface` (stratum: interface): two ADDED requirements: the observability host table's rows conform to one validated nine-field schema. Trust boundary: the validator runs in a check, not on read, so a row that breaks it fails the gate but still evaluates for its readers.
- `world-assumptions` (stratum: world): A330–A332. In the locked nixpkgs, `allowUnfree` and `permittedInsecurePackages` decide only whether evaluation throws. An overlay attribute nothing reads is never evaluated, so its import-from-derivation is never built. An evaluation-time assertion leaves the asserted derivation unchanged.

No capability is behavioral. The change moves wiring and tightens shapes, and every requirement a fleet user can observe stays as it is.

## Impact

- Code: `modules/checks/machines.nix`; new `modules/lib/fleet-obligations.nix` and `modules/lib/judge-check.nix`; the twelve judge files named in design.md; 26 check modules (system conditions), nine of them also moved to the judge constructor with `r2-usage` as the tenth; nine `modules/vm-tests/*.nix` now and two after the change holding them lands; `checks/{omnigent-workers,devin-worker}.nix`; `nixpkgs/overlays/channels.nix`; `lib/mk-eval-check.nix` (header); `lib/observability-hosts.nix` and `checks/otel-collector-config.nix`; later, the otel-collector service's option type.
- Docs: ADR-0017 amendment; `architecture/architecture.md`, `concepts/architecture-overview.md`, `reference/repository-structure.md`, `requirements/functional-hierarchy.md`, `requirements/usage-model.md`, `guides/handling-broken-packages.md`; `modules/README.md` where it describes machine-check wiring. The checks built from the docs site change with its source (`drv-delta.txt`).
- Depends on: `establish-refactor-oracle` (`just drv-diff`, including `vmTests`), `type-the-fleet-host-registry` (its parent).
- Overlaps: the change in flight that holds `vm-tests/{shared-reference-tree,perses-greptimedb}.nix`, `checks/{fleet-alert,test-sizes}.nix` and the otel-collector service; `compose-hosts-from-cohesive-aspects` (`deploy-record-order.nix`, the otel-collector split); `declare-host-user-relations-once` (`omnigent-workers.nix`); see design.md.
- Hosts: none deploys for this change. No host's derivation changes.
