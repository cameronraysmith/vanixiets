# Verification Report

**Change**: `resolve-a-restarted-kept-alive-jobs-failure`
**Verified at**: `2026-11-08 17:10 UTC`, after #3782 merged at 16:49:06Z and magnetite was deployed from `61d921094` at 16:53:33Z
**Verifier**: written for tasks.md 5.1 from `tasks.md`, `design.md`, `proposal.md`, `specs/` and `logs/cam92-evidence/`, with the commands of §1, §3 and §8a run read-only against the working copy; the deploy of tasks.md 4.2 was made by the orchestrator

Evidence names are files under `logs/cam92-evidence/`, which is git-ignored.
Times are UTC.

---

## 1. Structural Validation (`openspec validate resolve-a-restarted-kept-alive-jobs-failure --strict`)

- [x] The change reports valid
- [x] Every requirement of the deltas is discharged by name in `tasks.md`

`openspec validate resolve-a-restarted-kept-alive-jobs-failure --strict` prints `Change 'resolve-a-restarted-kept-alive-jobs-failure' is valid`.
The deltas hold two MODIFIED requirements, and each is quoted after `Discharges:` in `tasks.md`:

| Requirement | Tasks whose `Discharges:` quote it |
|---|---|
| FA `Each known failure class on a host reaches a person as an alert` | 2.2, 2.3, 3.2, 4.2 |
| FAI `Alert rules are rendered from one Nix source to the evaluator and to promtool` | 2.1, 2.2 |

A scratch archive in a copy of `openspec/` applied one modified requirement to each of `fleet-alerting` and `fleet-alerting-interface`, and `openspec validate --specs --strict` then fails on the same 18 specs as before it (`6-scratch-archive-20261108T161357Z.log`; tasks.md 3.4, 5.4).

---

## 2. Task Completion (`tasks.md`)

Groups 1 to 4 and 6 and the items 5.1 to 5.3 are ticked.
5.1 is this file; 5.2's issue text is `follow-up-issue.md`, filed by the orchestrator as CAM-93; 5.3's projection is regenerated (§9.2); 5.4, the archive itself, the Linear mirror and CAM-92's move to Done, waits for the operator, with its scratch archive made.

| Task | Reason incomplete | Blocks archive? |
|---|---|---|
| 5.4 | the archive waits for the operator's decision | it is the archive |

---

## 3. Delta Spec Sync State

The two deltas copy the corpus's requirements as they stood at `main@origin` `68baae384b16` and change only:

- FA: the darwin scenario's clause on a non-zero last exit code gains "counted for a kept-alive job only within 30 minutes after launchd last started it", and the scenarios `A kept-alive job runs again after an abnormal exit` and `A kept-alive job crashes` are added.
- FAI: the `Discharged by` line gains the replay of `LaunchdJobFailed`'s two arms and the store measurement, the darwin rules' scenario states the two-arm expression, and the scenario `A kept-alive job's abnormal exit is counted only after its relaunch` is added.

No other change open in the working copy modifies either requirement (`verify-ntfy-before-sending-tokens` adds requirements to both capabilities and modifies only FAI `This capability states its own trust boundary`).

---

## 4. Design / Specs Coherence

- D1's expression is the one FAI's darwin scenario states, the one `rules.nix` renders and the one delivered on magnetite (6.1, byte for byte against `new-expr.promql`).
- D2's 30-minute window is the one the legs read from the rendered expression and the one O2 decided; `keptAliveRestarted`'s expected `34 [RESOLVED]` is the decision's 30 min plus `transition.jq`'s 300 s.
- D3's legs and mutant are those FAI's new scenario names.
- D4 is not implemented; its issue text is `follow-up-issue.md`.

---

## 5. Implementation Signal

| File | Change |
|---|---|
| `modules/nixos/fleet-alert/rules.nix` | `LaunchdJobFailed`'s two arms and the header's description |
| `modules/checks/fleet-alert.nix` | `failedArms`, `failedAnswer`, `failedOn` through them, legs `keptAliveRestarted`, `keptAliveCrashed`, `notKeptAliveHeld`, mutant `failedIgnoresLaunch`, header |
| `docs/notes/development/observability/charter.md` | v31 entry; status, date and version lines |
| `docs/notes/development/observability/decisions/ADR-009-alerting.md` | status line, `LaunchdJobFailed` row, Consequences, Q10's resolution |
| `docs/notes/development/observability/components/fleet-alert.md` | Q10's line and the `LaunchdJobFailed` row |
| `packages/docs/src/content/docs/development/operations/fleet-observability.md` | the `LaunchdJobFailed` row and "Clearing a crashed kept-alive job" |
| `packages/docs/src/content/docs/development/traceability/satisfaction.md` | regenerated (§9) |

---

## 6. Front-Door Routing Leak Detector (warning, non-blocking)

No requirement names this change, a task number or a change directory; the corpus-facing text references only other corpus requirements.

---

## 7. Deferred Manual Dogfood vs Automated Test Equivalence

The behaviour the legs replay was observed on the deployed evaluator: the instance for `org.nixos.nix-daemon` that fired at 03:21Z resolved at 16:59:03Z, six minutes after magnetite's deploy, with no restart of the daemon (4.2), and the daemon's last exit still reads -1 (6.1).
A new crash of a kept-alive job firing once was not induced after the deploy; `keptAliveCrashed` and the replay of acceptance 8.4's `otelcol-process` steps, which fire at the same minute as under the old rule (2.3), stand for it.

---

## 8. Designation lint and discharge coherence

This section is agent-executed and non-blocking, and is not validation.

### 8a. Designation lint

The pass read FA's changed statement and its two new scenarios and looked each content noun up in the `Term` column of `openspec/specs/world-assumptions/spec.md`.
`kept-alive job`, `launchd job`, `darwin host`, `alert`, `alert rule`, `person`, `host`, `telemetry store`, `evaluator`, `regulator`, `probe`, `operator` and `pass` resolve to rows.
"last exit code", "starts" and "started" resolve through the `launchd job` row, which names "a job or service a darwin host's launchd starts …, whose state, runs and last exit code launchd reports"; "ends without an exit code" and "is killed" describe that last exit and add no term.
"build-time alert regulator" and "stored history" resolve to no row; both are in the corpus's requirement before this change, so this change adds no ungrounded noun, and the gap is recorded rather than closed here.
This change adds no `world-assumptions` delta, so the archive-time row check has nothing to compare.

### 8b. Discharge coherence

Statuses use `configured` (shown by delivered configuration or evaluation), `not violated` (a watch over a window saw no counter-example) and `observed` (a step made it happen and saw it).

| Requirement | Discharge | Evidence | Status |
|---|---|---|---|
| FA `Each known failure class on a host reaches a person as an alert`, its kept-alive clause | `fleet-alert`'s three legs and the mutant; the replay over stibnite's history; the deployed evaluator resolving the `nix-daemon` instance | `3-red-20261108T155630Z.log`, `3-green-20261108T161335Z.log`, `4-replay-20261108T161337Z.log`, `4.2-magnetite-20261108T165333Z.log`, `6.1-integration-20261108T170317Z.log` | observed, 2026-11-08 16:53Z to 17:03Z, for the resolution; the firing of a new crash is shown by the legs and the replay only |
| FAI `Alert rules are rendered from one Nix source to the evaluator and to promtool`, its darwin and kept-alive scenarios | the rendered rule list, the legs and `failedIgnoresLaunch`, promtool's pass, the store measurement | `2-*-2026110815*.log`, `3-green-20261108T161335Z.log`, `6.1-integration-20261108T170317Z.log` | configured and observed: the delivered expression equals the tested one, and the store answered it as measured |

### 8c. World assumptions

No world assumption is added or changed.
D2 relies on GreptimeDB 1.2.1's `increase` counting a reset as Prometheus does, cited at the tag and measured on the deployed store, and on launchd raising a kept-alive job's run count at each relaunch, which the stored `launchd_job_runs_total` steps show for `org.nixos.nix-daemon` and `org.nixos.otelcol-process`.

### 8d. Trust boundaries

FAI's trust boundary is unchanged; the proposal states the part this change rests on: the evaluator judges the store's answer, and that a crash raises the run count and that `increase` counts a reset to a positive value rest on launchd and GreptimeDB 1.2.1.

---

## 9. Evaluation cost and observations

### 9.1 Evaluation cost of `checks.x86_64-linux.fleet-alert`

Method: `NIX_SHOW_STATS=1 NIX_SHOW_STATS_PATH=<file> nix eval --option eval-cache false --raw .#.checks.x86_64-linux.fleet-alert.drvPath`, `.gc.totalBytes` and `.cpuTime`, against 536,870,912 B.

| When | Tree | Bytes | CPU s | File |
|---|---|---|---|---|
| before | `main@origin` `68baae384b16` | 378,106,688 | 1.29 | `5-cost-before-20261108T155740Z.json` |
| after | working copy, also holding CAM-87's uncommitted changes | 389,395,904 | 1.23 | `5-cost-after-20261108T161318Z.json` |

Both are under the budget.

### 9.2 The traceability projection

`satisfaction.md` was regenerated from a scratch archive's post-sync corpus (tasks.md 5.3): the corpus has the same 299 requirements across 29 capabilities, the two modified rows keep their titles and gain this change's evidence, and the CAM-92 evidence line is added.
Its `generated:` date is 2026-11-08; an archive on a later date regenerates it with that date.

---

## 10. Migration flags (tasks.md 5.1)

This change adds no migration flag, one-shot branch or conditional keyed to a deploy.
The rule's second arm and the check's `failedArms` model are permanent; `failedArms` accepts the single-arm shape only so that the mutant `failedIgnoresLaunch` can be modelled, which is the mutant's purpose, not a transition path.
Nothing is removed at the close-out.

---

## Overall Decision

Ready for archive when the operator decides (tasks.md 5.4); the follow-up of design D4 is CAM-93.
