---
linear_story_id: CAM-135
linear_story_identifier: CAM-135
linear_story_title: "Register each fleet host rule once and test every rule the same way"
linear_story_url: https://linear.app/cameronraysmith/issue/CAM-135/register-each-fleet-host-rule-once-and-test-every-rule-the-same-way
linear_story_state: Todo
linear_team: CAM
linear_project: den-ready-fleet
last_synced_state: Todo
last_synced_at: "2026-11-26T23:04:01Z"
review_round: 0
max_review_rounds: 3
attempt_log:
  - { at: "2026-11-26T23:04:01Z", transition: "Backlog->Todo", outcome: "posted", note: "Issue CAM-135 created in Todo in project 06049a4f18a4 (Den-ready fleet architecture), no label, with description seeded from proposal.md's Why and What Changes; state and project confirmed by read-only view; bind comment posted. A first create attempt with --json returned non-JSON output and created nothing (project query showed no new issue before the retry)" }
---

## Why

The machine checks enforce twelve fleet-wide rules about host configuration, and every rule is hand-wired into one check file, where its name appears in four places. Every new rule has meant another edit to that shared file. The check helpers repeat themselves: ten copies of one test shape, twenty-five duplicated platform conditions, and thirteen test files that each build their own package set. An unused, risky package channel is still documented as the way to patch a package, and two configuration shapes are never checked. The fleet is moving toward den, where each rule is declared once beside the code it governs. With this change a new rule is declared beside its code plus one line in a pinned list, and every rule is tested the same way. Every host builds exactly as it does now.

## What Changes

**Host rules registered once**
- From: `modules/checks/machines.nix` binds, calls, tests and names each of eleven judges by hand, plus a separate `withNetworkTargets` path for the twelfth; darwin-only judges are picked by a system-string suffix.
- To: a flake-parts option `fleetObligations.<name> = { classes; failures; }`; each judge registers in the file that defines it; the machine checks fold every entry whose `classes` include the host's class and fail with the messages of the judges that failed.
- Impact: non-breaking; every host and check keeps its derivation; a failure message lists only failing rules.

**One way to test a rule against its fixtures**
- From: ten fixture checks each hand-copy a `misjudges` filter that names wrong cases only.
- To: `flake.lib.judgeCases` and `flake.lib.mkJudgeCheck`, which report each wrong case with expected and actual counts and the judge's messages; `perses-config` and the nix-unit checks keep their own form.
- Impact: non-breaking; derivations unchanged; each check keeps its literal size-class entry.

**Duplicate platform conditions removed**
- From: 25 check modules repeat their `system == "x86_64-linux"` condition inside their size-class entry.
- To: the inner repetition is removed.

**Tests use the fleet's package set**
- From: eleven runtime tests and two fixture checks build their own nixpkgs.
- To: each reads the fleet's per-system package set; the devin-worker check shares one per system.
- Impact: runtime-test derivations may change (declared); nothing else should.

**Unused patched channel removed**
- From: `pkgs.patched` is exported and documented; nothing reads it, and reading it would build during evaluation.
- To: removed; ADR-0017 is amended; the broken-package guide and three architecture documents describe patching a single package instead.

**Two configuration shapes declared**
- From: the collector's envelope budget is an untyped attribute set; the observability host table has no schema.
- To: the budget is a typed record of its three fields; a validator checks the host table's rows inside an existing check.

**Non-goals**: renaming judges or the machine-check attributes; changing what any judge enforces; giving deferred scheelite a machine check; deriving any literal check oracle; touching the poisoned `flake` argument in the omnigent-workers check; the nixidy package set; the `nixpkgs` and `unstable` channels.

**Open question recorded for the operator (not decided here)**
- Whether stibnite's `controller` inventory tag is renamed. The answer depends on whether `clan machines update --tags controller` is part of the operator's habits. Nothing in this change reads the tag.

## Capabilities

### New Capabilities

- `fleet-obligation-registry-interface` (stratum: interface): the `fleetObligations` option and its entry shape; the fold the machine checks run and its message; `flake.lib.judgeCases` and `flake.lib.mkJudgeCheck` and what they report; one system condition per check module. Trust boundary: the registry guarantees that every registered judge runs on every machine check of its class. It does not guarantee that a judge is correct beyond its fixtures, and it says nothing about a host with no machine check (deferred scheelite, covered only by fleet-wide checks). A judge sees only the evaluated configuration, not the deployed host.
- `fleet-package-set-interface` (stratum: interface): runtime tests and fixture checks evaluate against the per-system fleet package set; the channels overlay exports no `patched`. Trust boundary: the same package set is guaranteed at evaluation only. Equal derivations do not mean a runtime test behaves the same, and nothing here covers top-level outputs such as nixidy.

### Modified Capabilities

- `database-backup-interface` (stratum: interface): "A host's backup set is pinned by a fleet obligation" names the registry entry instead of `withFleetObligations`. This applies once `back-up-postgresql-off-host` has archived that spec into the corpus.
- `fleet-ingress-interface` (stratum: interface): two ADDED requirements. The envelope budget has a declared three-field shape, and the observability host table's rows conform to one validated schema. Trust boundary: the validator runs in a check, not on read, so a row that breaks it fails the gate but still evaluates for its readers.
- `world-assumptions` (stratum: world): A330–A332. In the locked nixpkgs, `allowUnfree` and `permittedInsecurePackages` decide only whether evaluation throws. An overlay attribute nothing reads is never evaluated, so its import-from-derivation is never built. An evaluation-time assertion leaves the asserted derivation unchanged.

No capability is behavioral. The change moves wiring and tightens shapes, and every requirement a fleet user can observe stays as it is.

## Impact

- Code: `modules/checks/machines.nix`; new `modules/lib/fleet-obligations.nix` and `modules/lib/judge-check.nix`; the twelve judge files named in design.md; 25 check modules (system gates), ten of them also moved to the judge constructor; eleven `modules/vm-tests/*.nix`; `checks/{omnigent-workers,devin-worker}.nix`; `nixpkgs/overlays/channels.nix`; `clan/services/otel-collector/flake-module.nix` (one option type); `lib/observability-hosts.nix` and `checks/otel-collector-config.nix`.
- Docs: ADR-0017 amendment; `architecture/architecture.md`, `requirements/functional-hierarchy.md`, `requirements/usage-model.md`, `guides/handling-broken-packages.md`; `modules/README.md` where it describes machine-check wiring.
- Depends on: `establish-refactor-oracle` (`just drv-diff`, including `vmTests`). Its MODIFIED delta also requires `back-up-postgresql-off-host` to archive first.
- Overlaps: `type-the-fleet-host-registry` (`machines.nix`, the suffix tests), `compose-hosts-from-cohesive-aspects` (`deploy-record-order.nix`, the otel-collector split), `declare-host-user-relations-once` (`omnigent-workers.nix`); see design.md for the merge order.
- Hosts: none deploys for this change. No host's derivation changes.
