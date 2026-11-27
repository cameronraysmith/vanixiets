---
linear_story_id: CAM-131
linear_story_identifier: CAM-131
linear_story_title: "Prove each fleet refactor changes only what it declares"
linear_story_url: https://linear.app/cameronraysmith/issue/CAM-131/prove-each-fleet-refactor-changes-only-what-it-declares
linear_story_state: In Review
linear_team: CAM
linear_project: den-ready-fleet
last_synced_state: In Review
last_synced_at: "2026-11-27T04:01:16Z"
review_round: 0
max_review_rounds: 3
attempt_log:
  - { at: "2026-11-26T23:00:30Z", transition: "Backlog->Todo", outcome: "posted", note: "Issue CAM-131 created in Todo in project 06049a4f18a4 (Den-ready fleet architecture), no label, with description seeded from proposal.md's Why and What Changes; state and project confirmed by read-only view; bind comment posted" }
  - { at: "2026-11-27T00:48:47Z", transition: "Todo->In Progress", outcome: "posted", note: "Fired by the first checked task (1.1); workspace confirmed by linear auth whoami; Linear was Todo, strictly behind; state confirmed In Progress by read-only view; comment posted" }
  - { at: "2026-11-27T04:01:16Z", transition: "In Progress->In Review", outcome: "posted", note: "Fired by verify.md creation (PASS WITH WARNINGS); workspace confirmed by linear auth whoami; Linear was In Progress, strictly behind; state confirmed In Review by read-only view; comment posted" }
---

## Why

The den-ready refactors reshape how hosts, users and checks are composed and are meant to leave every built system unchanged, or change only outputs named in advance. Nothing in the repository can show that across two revisions: `just eval-identity` compares two evaluators at one commit. Evaluation-cost claims rest on one-off measurements whose evaluator and command were not recorded, and the planning document the refactors start from still plans through a tracker the repository no longer uses. A committed before/after oracle, a measurement protocol with recorded baselines, and current planning documents let every later refactor in the project prove it changed nothing it did not declare.

## What Changes

**Cross-revision identity oracle (new)**
- From: a procedure in the `preferences-nix-checks-architecture` skill, run by hand with `/tmp` paths; runtime tests outside its scope.
- To: `just drv-diff <before> <after> [allow]` dumps the derivation paths of every NixOS and darwin system, every home configuration, `checks.{x86_64-linux,aarch64-darwin}` and `vmTests.{x86_64-linux,aarch64-linux}` at two commits without building, diffs them, and fails on any difference the change did not declare in its allow-list, or on a declared difference that did not happen.
- Impact: non-breaking; adds one flake app and one recipe.

**Evaluation-cost protocol and baselines (new)**
- From: single runs in gitignored logs, evaluator unrecorded.
- To: `just eval-cost` runs interleaved base/candidate/base/candidate measurements with stock Nix and writes every run with its conditions; a committed baselines note records the stibnite and cinnabar system cost and the `checks.x86_64-linux` key-set cost, with the 2026-11-26 cross-host figures as reference.

**Planning and architecture documents (docs only)**
- `docs/notes/development/architectural-principles.md`: resolved opportunities (O07, O08, O13, O14, O16) removed or marked; the tracker-based decomposition re-planned as the OpenSpec changes of the Linear project "Den-ready fleet architecture"; superseded host-constructor plan and false O06 note corrected; a fifth principle, "composition is order-free and demand-driven; a module never reads another entity's evaluated config", added beside P1–P4.
- ADR-0018, ADR-0019, ADR-0020: dated amendment notes for the fleet's size, where the host platform is set, the user-module example, and the known-hosts module path.
- `modules/README.md`: `just eval-identity` described as single-revision, pointing to `just drv-diff`. `modules/home/README.md`: Den attributed to `denful/den`.

**Operator decisions recorded (resolved)**
- Stibnite's `controller` inventory tag is renamed to `deployer-workstation` by type-the-fleet-host-registry, not here.
- `may-change` entries are accepted as written; each one in a change's own `drv-delta.txt` is resolved to `changed`, or removed, before that change archives. The oracle's base allow-list stays `may-change` by design.

**Non-goals**: any refactor of the fleet itself; changing `just eval-identity`; editing the `preferences-nix-checks-architecture` skill; dumping `checks.aarch64-linux`, `packages`, `apps` or `devShells`; adopting den.

## Capabilities

### New Capabilities

- `refactor-identity-oracle` (stratum: behavioral): a refactor declared neutral leaves every deployed system, home configuration, check and runtime test of the fleet with the same derivation, and any other difference is named before it is accepted; a claim that a refactor reduces evaluation cost is accepted only on interleaved measurement against a recorded baseline.
- `refactor-identity-oracle-interface` (stratum: interface): `just drv-diff`, its allow-list format, its base allow-list, its dumps and exit status; `just eval-cost` and its run records. Trust boundary: equal derivation paths show the build recipe is unchanged, not that a deployed system behaves the same; the oracle sees only the seven enumerated maps on the systems it is given, so `flake.lib` values, clan inventory data, terranix output and other systems are outside it; on darwin, builds are not sandboxed, so the same derivation can still build differently; cost figures hold only for the evaluator, host and conditions recorded with them.

### Modified Capabilities

- `world-assumptions` (stratum: world): A310–A313 (a derivation path names its build recipe; a commit-pinned flake reference evaluates exactly the committed tree; stock Nix's thunk and allocation counts are reproducible for one expression and evaluator while time is not; the command name `nix` can resolve to an alternative evaluator); designations for refactor, declared difference, base and candidate commit, comparison, home configuration, evaluator in its Nix sense, evaluation cost, cost measurement and baseline. The `check` row is the one declare-test-size-classes adds, word for word, and `runtime test` already exists; neither is a second row.

## Impact

- Code: new `modules/apps/drv-diff.{nix,sh}` and `modules/apps/eval-cost.{nix,sh}`; two recipes in `justfile`.
- Docs: `docs/notes/development/architectural-principles.md`, new `docs/notes/development/eval-cost-baselines.md`, ADR-0018/0019/0020 under `packages/docs/src/content/docs/development/architecture/adrs/`, `modules/README.md`, `modules/home/README.md`.
- Hosts: none; no deployed output changes.
- Dependencies: none upstream. Every other change in the Linear project "Den-ready fleet architecture" depends on this one's oracle for its acceptance.
