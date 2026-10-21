# Verification Report

> This file is produced by the `openspec-verify-change` skill after apply completes, to confirm that the
> implementation is consistent with the specs / design / tasks. Any failed check must be returned to its
> corresponding artifact for correction before re-running verify.

**Change**: `stand-up-fleet-alerting`
**Verified at**: `2026-10-18 11:31 UTC`, updated `2026-10-20 22:34 UTC` and `2026-10-20 23:30 UTC`
**Verifier**: `S3Verify (agent), running plan.md Task 8 Steps 1, 4 and 6 read-only; Steps 2 and 3 ran on 2026-10-20 (orchestrator, §10); S3CloseOut (agent) recorded 7.7 and 9.1 and set the Overall Decision`

---

## 1. Structural Validation (`openspec validate --all --json`)

- [x] All items report `"valid": true`

**Result**:

```text
$ openspec validate --all --json   (2026-10-18 11:31 UTC; not rerun at the update)
{"totals":{"items":36,"passed":36,"failed":0},"byType":{"change":{"items":18,"passed":18,"failed":0},"spec":{"items":18,"passed":18,"failed":0}}}
$ openspec validate stand-up-fleet-alerting --strict   (2026-10-20 22:34 UTC)
Change 'stand-up-fleet-alerting' is valid
exit=0
```

If any items fail, list their id and issues:

| Item | Type | Issues |
|---|---|---|
| — | — | — |

---

## 2. Task Completion (`tasks.md`)

- [ ] All `- [ ]` have been changed to `- [x]`

`tasks.md` on `origin/main` (`59af3f592`) has 48 ticked items and 13 unticked ones (7.1–7.7, 8.1–8.5, 9.1); this close-out ticks eleven of them, 7.1–7.7, 8.1–8.3 and 9.1.
6.3 is ticked on `origin/main`, and at 22:34Z on 2026-10-20 the delivered `~/.claude/skills/nix-flake-pr-cycle/SKILL.md` and `~/.claude/skills/preferences-style-and-conventions/SKILL.md` on stibnite both contain `NTFY_TOKEN_FILE`.

**Incomplete tasks** (if any):

| Task | Reason incomplete | Blocks archive? |
|---|---|---|
| 8.4, 8.5 | the Purpose edit and the archive, which are the second close-out pull request | no; they are the archive |

---

## 3. Delta Spec Sync State

For each delta spec file reported by the CLI
(`openspec status --change "stand-up-fleet-alerting" --json | jq -r '.artifactPaths.specs.existingOutputPaths[]'`),
compare against the corresponding main capability spec:

| Capability | Sync status | Notes |
|---|---|---|
| `fleet-alerting` | pending sync | New capability; `openspec/specs/fleet-alerting/` does not exist. |
| `fleet-alerting-interface` | pending sync | New capability; `openspec/specs/fleet-alerting-interface/` does not exist. |
| `host-metrics-collection` | pending sync | MODIFIES `A failed collection or store job notifies a person`; the main spec still ends it with "without the notifier holding any credential". |
| `telemetry-store` | pending sync | MODIFIES `The telemetry store's own failures reach a person`; the main spec's discharge still rests on A33's anonymous publishing. |
| `telemetry-store-interface` | pending sync | MODIFIES `Failure notices are posted to one topic`, `Credentials exist only as activation-resolved files owned by non-worker users` and `This capability states its own trust boundary`; the Purpose's "ntfy access is ZeroTier membership" is tasks.md 8.4's hand edit at archive. |
| `world-assumptions` | pending sync | ADDS A37–A42, MODIFIES A33 and `Grounded vocabulary for behavioral requirements`, RENAMES A33; the main spec has no A37–A42, still titles A33 "accepts anonymous publishing" and still reads "Fourteen terms carry two senses". |

All six sync at archive, after tasks.md 8.3's sync-order check (§10.3).

---

## 4. Design / Specs Coherence Spot Check

Spot-check whether the decisions in `design.md` are reflected in the Requirements and
Scenarios of `specs/*.md`:

| Sampled item | design description | specs correspondence | Gap |
|---|---|---|---|
| D1 | `behind-proxy: true`, `proxy-trusted-hosts` `::1`, `visitor-prefix-bits-ipv6: 128`, no exempt host | `fleet-alerting-interface` `ntfy counts each mesh client as its own visitor`; A40, A41 | none in the specs; stibnite reached ntfy over IPv4 at acceptance, where the IPv6 prefix setting does not apply (§9.9) |
| D5 | three deploys: provisioning with no access entries, then magnetite's token-bearing senders, then `auth-access` and the dead-man | `fleet-alerting-interface` `The alerter token travels only as a file` (cutover order under A39) and `ntfy grants the fleet topics to alerter through declarative provisioning` (scenario "The access entries arrive last") | none |
| D11 | `transition.jq` as a pure function checked against `model.py`; a rule is read from `results` when it has an `expr` or a results entry, except `StoreQueryFailing` and `RuleSignalMissing`; frozen time is not absence; an always-on host's absence raises `RuleSignalMissing` for that host (#3516) | `fleet-alerting-interface` `Alert instance state is kept in one state file and posted once per transition`, `Store errors and silent hosts freeze instance state`, `An always-on host's silence is reported`; `fleet-alerting` scenarios "A freeze ends with the condition gone" and "magnetite stops reporting while the store answers" | none |
| D13 | one query in flight, `--max-time 10`, first failure or 30 s ends the query phase, no post after 35 s (40 s before #3516) | `fleet-alerting-interface` `The evaluator queries the fleet database as the regulators' store account` (fixture server fails a leg on two open requests), the scenario "One failed query bounds the run", and `The evaluator's memory ceiling and start timeout are asserted` (the timing relation) | none |
| D15 | `state.json` per instance with `absenceFrom`; `mark_posted` written through a temporary file and renamed after each post; an unreadable `failed.log` fails the run | `fleet-alerting-interface` `Alert instance state is kept in one state file and posted once per transition` and `The alert budget is counted over the evaluator's state and the notifier's FAILED log` (scenario "The FAILED log cannot be read") | none |

**Drift warnings** (non-blocking):

- none.
  The first run of this file warned that the title requirement stated only `[FIRING] <alert> <host>`; tasks.md 10.7 (review F12, #3516) added the host-less form and the scenario "A host-less post is recorded".

---

## 5. Implementation Signal

- [x] No unstaged files in the worktree
- [x] All related commits have been pushed

Every S3 implementation commit is on `origin/main`, and the change directory's artifacts in the working copy are byte-identical to `origin/main` `59af3f592`'s (`cmp`); this file is new.
The working copy also carries other agents' unmerged chains, which this verification did not inspect.
Plan Task 8 Step 4's path-filtered `git log origin/main` lists the S3 commits, newest first:

```text
59af3f592 refactor(fleet-alert): single-host relations as assertions, drop restating checks    (#3519, tasks.md 10.8–10.10)
e48bf7b2d fix(fleet-alert): always-on host silence, retried notices, timing budget and schema restart (#3516, tasks.md 10.2–10.7)
5f935064c docs(observability): S3 alerting runbook, module index and ntfy-send token lines        (#3512, Task 6)
c926297ef docs(fleet-alert): correct the evaluation-cost evidence and method (charter v19)      (#3511)
18e3b8acf fix(fleet-alert): frozen time is not absence                                         (#3510, tasks.md 10.1)
6caa2425c fix(ntfy): end the S3 cutover debug logging on cinnabar                              (#3509, tasks.md 7.4)
dbec98c74 feat(fleet-alert): dead-man on cinnabar and fleet-* access control                   (#3508, Task 5)
6ccc644bb feat(fleet-alert): alert evaluator on magnetite with rule, fixture and property checks (#3507, Task 4)
e19971f37 feat(ntfy): provision the alerter user and token on cinnabar, one visitor per mesh client (#3506, Task 3)
23c82360b refactor(observability-notify): own module, FAILED log and token option              (#3505, Task 2)
b9b922036 feat(ntfy-send): send the token from NTFY_TOKEN_FILE on stdin, never on argv         (#3504, Task 1)
```

The plan landed before them as `b32825cde` (#3503).
At the first run, the verify precheck printed 31 commits for `git log --oneline $(git merge-base HEAD origin/main)..HEAD` (the working copy's join) and 28 ticked items in the CLI-resolved `tasks.md`; at the update the CLI-resolved `tasks.md` has 48.

**Commit range** (if known): `630722b14..59af3f592`, filtered to the S3 paths.

---

## 6. Front-Door Routing Leak Detector (warning, non-blocking)

Design output should not land in `docs/superpowers/specs/` (the brainstorm artifact's
output redirection routes it to the change's resolved brainstorm.md — the `brainstorm`
entry in `artifactPaths` from `openspec status --change "stand-up-fleet-alerting" --json`).

Detect:

```bash
ls docs/superpowers/specs/*.md 2>/dev/null
```

- [x] No files, or any existing files are legitimate residue from before schema installation

The command printed nothing and exited 2, because the glob matched no file.

**Leak list** (if any):

| File | Content captured into change? | Recommended action |
|---|---|---|
| — | — | — |

> Does not block archive. Leaks produced by a new schema-installed cycle should be moved into
> the change's brainstorm.md (resolved via `artifactPaths.brainstorm`) or `design.md`, then the
> original file deleted.

---

## 7. Deferred Manual Dogfood vs Automated Test Equivalence

`plan.md` has no row marked `[~]`; its one `[~]` match is the Step 6 instruction text at plan.md:6805.
This section is blank by the template's rule.
7.7 and 9.1 were human-dependent `tasks.md` items, not `[~]` plan rows; §9.8 and §10.1 record how each closed.

| Deferred dogfood (plan §) | Equivalent automated test | Coverage assessment | Real gap? |
|---|---|---|---|
| — | — | — | — |

---

## 8. Designation lint and discharge coherence

This section is agent-executed and non-blocking.
`openspec validate` checks markdown structure and delta well-formedness only; nothing here is validation.
The designation table used is the one this change's `world-assumptions` delta carries (the MODIFIED `Grounded vocabulary for behavioral requirements`, 129 rows), which includes the main table's rows and this change's alerting rows.

### 8a. Designation lint

The proposal tags `fleet-alerting`, `telemetry-store` and `host-metrics-collection` `behavioral`.
The two modified behavioral requirements only drop a trailing clause from S1's text, which S1's verify linted, so they add no noun.
A lexer pass over `fleet-alerting`'s requirement titles and statements, excluding scenarios and `Discharged by` lines, leaves these content nouns without a row:

| Noun | Requirement | Disposition proposed |
|---|---|---|
| failure class | `Each known failure class on a host reaches a person as an alert` (title) | designation table: shared; the `alert rule` row already defines a rule by "one known failure class" |
| condition | `An alert instance reaches a person once when it fires and at most once when it resolves` | designation table: shared, or read through the `alert rule` row's "named condition" |
| holding time | same | designation table: shared; the `alert rule` row uses the term without a row of its own |
| critical, warning, info (as instance and alert kinds) | same; `Alert volume stays within the alert budget` ("info alerts") | read as values of the existing `severity` row, which names all three |
| publisher | `Only the alerting credential publishes alerts and heartbeats` | designation table: shared; the `credential` and `topic` rows use it without a row |
| alerting credential | same | read as the existing `credential` (notification service) row; a second sense is not needed |
| fleet | `Alert volume stays within the alert budget` ("across the fleet") | designation table: world-only; it is used throughout the table's definitions without a row |
| pass (of the evaluator) | `The evaluator stays inside its envelope on magnetite` | designation table: shared; the `evaluator` (alerting) and `heartbeat` rows define and use it without a row |
| memory incident | same | designation table, or rephrase as `memory pressure`, which has a row |
| path (from the telemetry store to the person) | `A weekly test alert proves the path to a person` | designation table: a second sense of `path`, whose one row is a target's location string |
| time zone | same ("the `America/New_York` time zone") | designation table: world-only |
| always-on host | `A missing signal is itself reported` (added by #3516: "When an always-on host, magnetite alone in S3, has reported no memory signal …") | designation table: shared, a host the rule table expects to report at all times; or the interface stratum, since the rule table's `alwaysOn` list defines it |

Every other content noun resolves to a row: `person`, `alert`, `alert rule`, `alert instance`, `host` (fleet sense), `series`, `telemetry store` (and its short form "the store"), `memory`, `memory pressure`, `kernel`, `process`, `out-of-memory`, `storage pool`, `unit`, `notifier`, `source`, `collector`, `evaluator` (alerting sense), `signal` ("memory signal" is `memory` plus `signal`), `gap`, `heartbeat`, `notification service`, `topic`, `alert budget`, `failure notice` and `envelope`.
Each row above is a finding for the retrospective's Promote section, not a rewrite applied here.

### 8b. Discharge coherence

Each behavioral requirement's `Discharged by` line names its interface requirements and world assumptions, and each `tasks.md` `Discharges:` clause names the requirements its task discharges.
Evidence names are files under `logs/s3-evidence/`; §9 to §11 paste the decisive lines.
An observation the spec assigns to "the operator" was made by the agent S3OpsPreC1 where marked *(agent)*; tasks.md 7.1–7.6 name commands, not a person, and only 7.7 is a human step.

| Requirement | Discharged by (S) | Under (W) | Status |
|---|---|---|---|
| fleet-alerting: `Each known failure class on a host reaches a person as an alert` | FAI `The evaluator queries the fleet database as the regulators' store account`, `Alert rules are rendered from one Nix source to the evaluator and to promtool`, `Alerts are posted to fleet-alerts with a title and a severity priority`, `ntfy counts each mesh client as its own visitor` (tasks 4.1, 4.3, 4.5, 7.1, 7.6, 10.10); exclusion and attribution legs (`review-b-green-20261020-164707.log`); every rule fired and resolved on magnetite (`7.6-oom-…`, `7.6-oom-store-resolved-…`, `7.6-exporter-alerts-…`, `7.6-forced-firing-…`, `7.6-forced-resolved-…`), which since #3519 also discharges the scenario "A storage pool degrades"; the operator's phone received a test post on `fleet-alerts` (§9.8) | A33, A40, A41 | discharged; arrival on the phone by the composition of §10.1 |
| fleet-alerting: `An alert instance reaches a person once when it fires and at most once when it resolves` | FAI `Alert instance state is kept in one state file and posted once per transition`, `Alerts are posted to fleet-alerts with a title and a severity priority` (tasks 4.5, 4.6, 7.6); fixture sequence, `noStateWrite`, `forZero` and `noRepost` rejected (`4.5-check-…`, `4.6-property-…`, `review-b-green-…`); one `FIRING` and one `RESOLVED` per rule at runtime (§9.7) | — | discharged |
| fleet-alerting: `An unreachable telemetry store or a silent host freezes alerts` | FAI `Store errors and silent hosts freeze instance state` (tasks 4.5, 7.6, 10.1); store-error and silent-host legs, `noStoreFreeze` and `noAbsenceFreeze` rejected; `storeThawLeg`, `hostThawLeg` and `test_resolve_follows_unfrozen_absence` red then green (`10.1-red-…`, `10.1-green-…`); runtime `7.6-store-…`, `10.1-reobserve-resolved-…` | — | discharged after #3510; the first runtime observation failed the scenario "A freeze ends with the condition gone" (§11.1) |
| fleet-alerting: `A missing signal is itself reported` (amended by #3516) | FAI `Each rule's presence selector is watched`, `An always-on host's silence is reported` (tasks 4.5, 7.2, 10.2); both signal-gap legs and the always-on-host leg with `noHostsUpdate`, red then green (`review-a-F1-red-20261020-155359.log`, `review-a-green-20261020-155814.log`); no `RuleSignalMissing` in 35 min after C2 and the misspelt-selector control fired (`7.2-rulesignalmissing-silence-20261018T083133Z.log`, `7.2-rulesignalmissing-negative-…`) *(agent)* | — | discharged; the always-on-host clause is discharged by check only |
| fleet-alerting: `A silent evaluator is reported from another host` | FAI `Each completed evaluator run posts a heartbeat`, `The dead-man on cinnabar polls the heartbeat topic after an anonymous-publish probe` (tasks 5.1, 7.5); dead-man legs (`5.1-fleet-alert-green-20261018T080549Z.log`); R9.3 at runtime (`7.5-silent-…`, `7.5-resolved-…`) | A33, A42 | discharged |
| fleet-alerting: `Only the alerting credential publishes alerts and heartbeats` | FAI `ntfy grants the fleet topics to alerter through declarative provisioning`, `The alerter token travels only as a file` (tasks 5.2, 7.3); `ntfy-provisioning` with four mutants (`5.2-ntfy-provisioning-…`); R9.4 probe and its negative control (`7.3-deadman-…`, `7.3-matrix-…`, `7.3-r94-negative-…`, `7.3-r94-resolved-…`) | A37, A38 | discharged |
| fleet-alerting: `Alert volume stays within the alert budget` | FAI `The alert budget is counted over the evaluator's state and the notifier's FAILED log` (tasks 2.3, 4.2, 4.5, 9.1); the four budget legs (`review-b-green-…`); R9.1 equals the captured messages over two 24 h windows (`9.1-budget-20261020T223210Z.log`, §10.2) | — | discharged |
| fleet-alerting: `The evaluator stays inside its envelope on magnetite` | FAI `The evaluator's memory ceiling and start timeout are asserted` (tasks 4.4, 10.4); `4.4-r95-mutant-…`, `4.4-r95-control-…`, the timing relation red at `postDeadlineSec = 40` (`review-a-F5-red-20261020-154626.log`); deployed `MemoryMax=67108864`, `TimeoutStartUSec=50s`, peaks 6.0–7.6M (`7.2-evaluator-…`) | A31 | discharged |
| fleet-alerting: `A weekly test alert proves the path to a person` | FAI `The weekly test rule is evaluated in one window each Monday` (tasks 4.1, 7.7); window leg across the daylight-saving change (`review-b-green-…`); the scheduled `[FIRING] WeeklyPipelineTest` at 2026-10-19T13:00:01Z, priority 2, in the evaluator's journal and in the pyrite capture as id `KFK1gVKC6rZu` (`9.1-budget-…`, `9.1-fleet-alerts-capture.jsonl`); the 7.7 test post `tA8WItkDXEKi` received on the operator's phone (`7.7-test-post-20261020T231209Z.log`, §9.8) | A33 | discharged; the first Monday message reached no phone, because none was subscribed, and the phone's receipt was shown by a later test post (§9.8) |
| fleet-alerting-interface: `The evaluator queries the fleet database as the regulators' store account` | R8.2 holder assertion and its mutant (`4.8-red-…`, `4.8-r82-mutant-…`); fixture-server refusal leg; first run on magnetite (`7.2-evaluator-…`) *(agent)* (tasks 4.3, 4.8) | — | discharged |
| fleet-alerting-interface: `Alert rules are rendered from one Nix source to the evaluator and to promtool` | `4.1-promtool-…`; `malformedExpression` rejected (`4.5-check-…`); fixture legs running the evaluator on the rendered rules, exclusion and attribution legs (`review-b-green-…`); task 7.6's forced condition for each shipped rule (§9.7) (tasks 4.1, 10.10) | — | discharged |
| fleet-alerting-interface: `Alert instance state is kept in one state file and posted once per transition` | fixture sequence, `noStateWrite`, `forZero`, property against `model.py` (tasks 4.2, 4.6); deployed `state.json` keys `budgetPostedAt, firings, hosts, instances, lastRun` (`7.2-evaluator-…`) | — | discharged |
| fleet-alerting-interface: `Store errors and silent hosts freeze instance state` | store-error and silent-host legs, both freeze mutants, property; thaw legs and property after #3510 (task 4.2, 10.1) | — | discharged |
| fleet-alerting-interface: `Each rule's presence selector is watched` | both signal-gap legs; `7.2-rulesignalmissing-silence-20261018T083133Z.log` and `-negative-…` *(agent)* (task 4.1) | — | discharged |
| fleet-alerting-interface: `An always-on host's silence is reported` (added by #3516) | always-on-host leg with `noHostsUpdate`, failing before the fix and passing after (`review-a-F1-red-20261020-155359.log`, `review-a-green-20261020-155814.log`, `review-b-green-20261020-164707.log`) (task 10.2) | — | discharged by check |
| fleet-alerting-interface: `Alerts are posted to fleet-alerts with a title and a severity priority` | fixture server's recorded posts, including the host-less `[FIRING] StoreQueryFailing` of `storeErrorLeg` (task 10.7); 5 `alerter`-authenticated heartbeat requests in 5 min during the cutover (`7.2-evaluator-…`); R9.3 at runtime (`7.5-…`); runtime titles and priorities 4, 3 and 2 for `critical`, `warning` and `info` (§9.7) (tasks 4.3, 10.9) | — | discharged |
| fleet-alerting-interface: `Each completed evaluator run posts a heartbeat` | heartbeat on normal and store-error legs; 10 heartbeats in 10 min and 5 `alerter`-authenticated heartbeat requests in 5 min after C2 (`7.2-evaluator-…`) (tasks 4.3, 7.2) | — | discharged |
| fleet-alerting-interface: `The dead-man on cinnabar polls the heartbeat topic after an anonymous-publish probe` | R9.3 (`7.5-…`); R9.4 with `*:fleet-*:ro` removed (`7.3-r94-negative-…`); dead-man legs and probe mutant (`5.1-fleet-alert-green-…`); since #3519, `fleet-alert.nix`'s assertions on ntfy's listener and access entries and cinnabar's on the dead-man's ordering, each failing under its override (`review-b-F3-F6-assertion-overrides-20261020-164505.log`) (tasks 5.1, 7.3, 7.5, 10.8) | A42 | discharged |
| fleet-alerting-interface: `ntfy grants the fleet topics to alerter through declarative provisioning` | `ntfy-provisioning` with four mutants (`3.4-green-4mutants-…`, `5.2-ntfy-provisioning-…`); `alerter` provisioned from server config (`7.1-provisioning-…`); R9.4; anonymous `stibnite` publish 200 beside `fleet-alerts` 403 (`7.3-matrix-…`) (tasks 3.3, 3.4, 5.2) | A37, A38 | discharged |
| fleet-alerting-interface: `ntfy counts each mesh client as its own visitor` | negative control before C1 (`7.1-pre-c1-visitors-…`); two distinct client addresses and flat counter after C1 (`7.1-visitor-journal-…`, `7.1-post-c1-visitors-…`) *(agent)* (tasks 3.3, 7.1) | A40, A41 | discharged; stibnite is counted by its IPv4 address (§9.9) |
| fleet-alerting-interface: `The alerter token travels only as a file` | `package-ntfy-send-test-token-transport` red then green with its argv mutant (`1.2-token-transport-red-…`, `1.2-token-transport-20261018T061305Z.log`); the resolve-hook assertion `unitsWithoutToken`, failing when `fleet-alert.service`'s `ExecStopPost` is replaced (`review-b-F3-F6-assertion-overrides-…`); unknown token refused 401 at C1 (`7.1-token-probe-…`); `alerter`-authenticated heartbeats, the forced failure notice and R9.3 delivered after `*:fleet-*:ro` (§9.3–§9.6) (tasks 1.1, 1.2, 3.2, 4.7, 10.9) | A39 | discharged; #3519 deleted the token-path and credential-name assertions of `4.7-assertion-mutants-…` and `5.3-assertion-mutants-…` |
| fleet-alerting-interface: `The alert budget is counted over the evaluator's state and the notifier's FAILED log` | budget legs and the unreadable-log leg, red then green (`review-a-F8-red-20261020-154753.log`, `review-a-green-…`); `failed.log` rehearsal with `drop-append` and `drop-mode` mutants (`2.3-rehearsal-red-…`, `2.3-rehearsal-20261018T061737Z.log`); deployed `failed.log` line and mode `644` (`7.2-notifier-…`); R9.1 at runtime (§10.2) (tasks 2.3, 4.2, 9.1, 10.5) | — | discharged |
| fleet-alerting-interface: `The rule check runs promtool, fixture mutants and a property test` | each mutant rejected (`4.5-check-…`, `5.1-fleet-alert-green-…`, `review-b-green-…`); evaluation cost in §9.1 (tasks 4.5, 4.6) | — | discharged |
| fleet-alerting-interface: `The evaluator's memory ceiling and start timeout are asserted` (amended by #3516) | `4.4-r95-mutant-…`, `4.4-r95-control-…`; the timing relation fails at `postDeadlineSec = 40` (`review-a-F5-red-…`) and `nixos-magnetite` builds at 35 (`review-a-green-…`) (tasks 4.4, 10.4) | — | discharged |
| fleet-alerting-interface: `The weekly test rule is evaluated in one window each Monday` | window leg; forced window on magnetite (`7.6-forced-firing-…`); the scheduled post at 2026-10-19T13:00:01Z (§9.8) | — | discharged |
| fleet-alerting-interface: `This capability states its own trust boundary` | the requirement's own statement; no regulator applies | — | discharged by statement |
| host-metrics-collection: `A failed collection or store job notifies a person` (MODIFIED) | TSI `Failure notices are posted to one topic`; R3.1 failure-wiring clause red then green (`2.4-r31-token-red-…`, `2.4-r31-token-…`) | A33, A37 | discharged |
| telemetry-store: `The telemetry store's own failures reach a person` (MODIFIED) | TSI `Failure notices are posted to one topic`; delivery with the token (`7.2-notifier-…`, `7.3-r94-negative-…`) | A33, A37 | discharged |
| telemetry-store-interface: `Failure notices are posted to one topic` (MODIFIED) | R3.1 and the rehearsal with mutants (`2.3-rehearsal-…`, `2.4-otel-collector-config-…`); token transport; the resolve-hook assertion (`review-b-F3-F6-assertion-overrides-…`) and R3.1 failing with the pre-token hook regex (`review-b-F6-resolvedHook-narrowed-20261020-164635.log`); forced failure delivered with `alerter` after the access entries were in force (`7.3-r94-negative-…`, `7.3-r94-resolved-…`) (tasks 1.2, 2.2, 2.3, 4.7, 7.2, 10.9) | — | discharged |
| telemetry-store-interface: `Credentials exist only as activation-resolved files owned by non-worker users` (MODIFIED) | R8.2 admits `fleet-alert` and rejects a third holder (`4.8-red-…`, `4.8-r82-mutant-…`) (task 4.8) | — | discharged |
| telemetry-store-interface: `This capability states its own trust boundary` (MODIFIED) | the requirement's own statement; the Purpose sentence is tasks.md 8.4 at archive | — | discharged by statement |
| world-assumptions: A37 | world assumption; `alerter` and its token come from server config at C1 (`7.1-provisioning-…`), and `ntfy-provisioning` cites the source | — | assumption, holding |
| world-assumptions: A38 | world assumption; `alerter` posts to `fleet-acceptance` while anonymous `fleet-alerts` is refused 403 (`7.3-matrix-…`) | — | assumption, holding |
| world-assumptions: A39 | world assumption; an unknown token got 401 on an open topic at C1 (`7.1-token-probe-…`) | — | assumption, holding |
| world-assumptions: A40 | world assumption; separate visitor counters after C1 (`7.1-post-c1-visitors-…`) | — | assumption, holding; IPv4 clients are masked by `visitor-prefix-bits-ipv4`, which S3 leaves at its default (§9.9) |
| world-assumptions: A41 | world assumption; the journal shows each client's own mesh address, never `::1` (`7.1-visitor-journal-…`), and caddy's source is in `3-caddy-xff-…` | — | assumption, holding |
| world-assumptions: A42 | world assumption; the dead-man's polls counted 10–11 heartbeats per 10 min and 0 when the evaluator stopped (`7.3-deadman-…`, `7.5-silent-…`) | — | assumption, holding |
| world-assumptions: A33 (MODIFIED and RENAMED) | world assumption; every `fleet-*` publish with `alerter` and every host-topic anonymous publish was accepted after C3 (`7.3-matrix-…`) | — | assumption, holding |
| world-assumptions: `Grounded vocabulary for behavioral requirements` (MODIFIED) | the designation table in the delta | — | discharged, with the unresolved nouns of 8a |

No ADDED or MODIFIED requirement is undischarged; the two behavioral requirements whose scenarios end on the phone rest on §9.8's test post for that last link.

### 8c. Alphabet check

`A weekly test alert proves the path to a person`, a behavioral requirement, names the time zone by its tz-database identifier `America/New_York`, a machine-side name; this is recorded, not counted as a violation, because the world phenomenon is the same.
`The evaluator stays inside its envelope on magnetite` states "64 MiB" and "50 seconds", which are R9.5's `MemoryMax` and `TimeoutStartSec` phrased as world quantities; recorded, not counted.
No interface requirement references world state the machine cannot observe: `This capability states its own trust boundary` names ntfy's enforcement, the token's secrecy, an ntfy outage and delivery to a person only to disclaim them.

---

## 9. Deployment record

Sections 9 and 10 are the evidence ledger that `tasks.md` 7.1–7.7 and 9.1 require this file to hold.
`[operator]` marks an observation only the operator could make; every other entry gives the command and its output.

Before pasting, `rg -n 'tk_[-_A-Za-z0-9]{29}' logs/s3-evidence` and `rg -n '\$2[aby]\$[0-9]{2}\$' logs/s3-evidence` were run; neither matched (both exit 1).
`7.1-provisioning-…` prints the token as `tk_<redacted>`.

### 9.1 Evaluation cost of each new check

The budget is design D19's 0.5 GiB, 536,870,912 bytes of `gc.totalBytes`.
The method tasks.md line 4 prescribes is `NIX_SHOW_STATS=1 nix eval --raw .#.checks.x86_64-linux.<check>.drvPath`; without the leading dot nix first probes `packages` and `legacyPackages`, which with the eval cache off adds about 114 MB that is not the check's (charter v19, PR #3511).
Each figure below names its method.

| Check | Revision | Method | `gc.totalBytes` | GiB | drvPath | Log |
|---|---|---|---|---|---|---|
| `package-ntfy-send-test-token-transport` (new) | Task 1 working copy | `.#.` | 126,936,864 | 0.118 | `/nix/store/b0jc79aflpd534750gpfpkp9vjaq2w2f-ntfy-send-test-token-transport.drv` | `1.2-token-transport-cost-20261018T061402Z.log` |
| `otel-collector-config` (extended) | Task 2 working copy | `.#.` | 481,641,568 (481,414,736 at `b9b922036`) | 0.449 | not recorded | `2.3-otel-collector-config-cost-20261018T064253Z.log` |
| `ntfy-provisioning` (new) | Task 3 working copy | `.#checks…`, no leading dot, eval-cache state not recorded | 255,747,088 | 0.238, an upper bound | `/nix/store/klyif57rwvm4asvdmx5wdadxvdlkxg75-ntfy-provisioning.drv` | `3.4-eval-cost-20261018T064841Z.log` |
| `fleet-alert` (new) | `6ccc644bb`, Task 4 merge | `.#.` | 270,361,264 | 0.252 | — | tasks.md 4.7 (charter v19; S3CostBisect) |
| `fleet-alert` | `dbec98c74`, Task 5 merge | `.#.` | 485,950,608 | 0.453 | — | tasks.md 4.7 |
| `fleet-alert` | `6caa2425c` (`origin/main` before #3510) | `.#.` | 485,945,120 | 0.453 | — | tasks.md 4.7 |
| `fleet-alert` | Task 5 working copy | `.#checks…`, eval cache on, which gives the clean figure | 486,076,832 and 486,086,112 | 0.453 | — | `5.1-fleet-alert-eval-cost-20261018T075946Z.json`, `…080945Z.json` |
| `greptimedb-envelope` (S1's, clauses moved out in task 4.9) | Task 4, before the move | `.#checks…`, eval cache off | 553,093,152; about 439 MB clean (tasks.md 4.7) | 0.515 contaminated, about 0.41 clean | `/nix/store/fysddi6610q8ldz0m3dqc1qqm3lrz7sj-greptimedb-envelope.drv` | `4.9-eval-cost-20261018T072254Z.log` |
| `greptimedb-envelope` | Task 4, after the move | `.#checks…`, eval cache off | 519,562,112 | 0.484 contaminated | same | `4.9-eval-cost-after-move-20261018T073204Z.log` |
| `fleet-alert` | #3516 working copy, before review F3 | `.#.` (tasks.md 10.2, 10.8) | 488,337,696; 488,343,456 | 0.455 | `/nix/store/lv6rpp52ax52982ldfrj896aby88aapm-fleet-alert.drv` (second run) | `review-a-cost-20261020-162025.log`, `review-b-F3-eval-cost-before-20261020-164026.log` |
| `fleet-alert` | #3519 working copy, after review F3 | `.#.` (tasks.md 10.8) | 328,151,376 | 0.306 | `/nix/store/7fvajs4n5kzhbxs5nxm5qyr1d3v2zdqd-fleet-alert.drv` | `review-b-F3-eval-cost-after-20261020-164414.log`; `review-b-isolated-20261020T205945Z.log` records 328,036,064 |

Five further `fleet-alert` figures were taken without the leading dot and the eval cache off, and each carries the 114 MB: 597,745,792 (`4.5-eval-cost-20261018T072250Z.log`, before the move), 384,555,888 (`4.5-eval-cost-after-move-20261018T073200Z.log`), 600,407,104 (`10.1-eval-cost-baseline-20261018-063647.log`), 601,516,736 (`10.1-eval-cost-20261018-063618.log`) and 601,354,432 (`10.1-isolated-20261018T104502Z.log`).
They led Task 4 to move the token-wiring and kill-order clauses into module assertions (charter v18) and S3FixAbsence to report 0.56 GiB; the clean figures in the table were under budget throughout (§9.10).
No `.#.` figure was taken directly after #3510; the 0.455 GiB of #3516's working copy includes #3510 and the always-on-host leg, and #3519 brought the check to 0.306 GiB by moving the dead-man's relations within cinnabar into assertions (§11.3).

### 9.2 Pre-C1 baseline and C1 (tasks.md 7.1)

C1 deployed cinnabar from `origin/main` `e19971f37` with the queue empty (`queue-C1-20261018T070642Z.log`), `C1_START=2026-10-18T07:06:42Z`, `C1_END=2026-10-18T07:15:48Z`.

`7.1-pre-c1-visitors-20261018T070120Z.log`:

```text
$ ssh cinnabar.zt grep -E "behind-proxy|proxy-trusted|visitor-prefix|auth-access|log-level" <server.yml>
/nix/store/39csl1fg79amq8hnrb50y7bgqp9ilfq3-server.yml
none set
before: stibnite=0 magnetite=0
after 3 stibnite posts: stibnite=3 magnetite=3
NEGATIVE CONTROL HOLDS: magnetite's visitor counted stibnite's posts (one shared visitor)
```

`7.1-provisioning-20261018T071609Z.log`:

```text
$ systemctl is-active ntfy-sh
active
$ systemctl show ntfy-sh -p EnvironmentFiles
EnvironmentFiles=/run/secrets/vars/per-machine/cinnabar/ntfy-alerter-env/ntfy-env (ignore_errors=no)
$ sudo ntfy user list
user alerter (role: user, tier: none, server config)
- no topic-specific permissions
user * (role: anonymous, tier: none)
- no topic-specific permissions
- read-write access to all (other) topics (server config)
$ sudo ntfy token list alerter (values redacted)
user alerter
- tk_<redacted>, never expires, accessed from 0.0.0.0 at 01 Jan 70 00:00 UTC (server config)
$ count of listed tokens equal to the deployed token file
1
$ stat token
400 root
$ grep settings /nix/store/gcw2sa2v94dg6ikmvgmm36y35yvkj5g2-server.yml
behind-proxy: true
log-level: debug
proxy-trusted-hosts: ::1
visitor-prefix-bits-ipv6: 128
```

`7.1-token-probe-20261018T071632Z.log` (journal line abridged to its fields):

```text
$ ssh cinnabar.zt sudo NTFY_TOKEN_FILE=<token path> ntfy-send "c1 token probe" fleet-acceptance
{"id":"CbHAGH9aUNEG","time":1792307795,"expires":1792350995,"event":"message","topic":"fleet-acceptance","message":"c1 token probe"}
exit=0
# negative control: a well-formed token ntfy does not know, from stibnite
T_BADTOKEN=2026-10-18T07:16:35Z
unknown token: HTTP 401
... HTTP request finished user_name=alerter visitor_ip=fddb:4344:343b:14b9:399:93db:4344:343b Connection closed with HTTP 401 visitor_ip=10.147.17.83
```

`7.1-anon-20261018T071649Z.log`:

```text
$ ntfy-send "c1 anon" stibnite
exit=0
$ ntfy-send "c1 anon" fleet-acceptance
exit=0
```

`7.1-visitor-journal-20261018T071650Z.log`:

```text
http_path=/stibnite visitor_ip=10.147.17.83
http_path=/magnetite visitor_ip=fddb:4344:343b:14b9:399:930f:39db:40d2
$ ssh magnetite.zt ip -br addr show | grep zt
zt554fbdjy       UNKNOWN        10.147.17.118/24 fddb:4344:343b:14b9:399:930f:39db:40d2/88 fe80::b6:2dff:fee0:7496/64
$ ifconfig | grep fddb (stibnite)
	inet6 fddb:4344:343b:14b9:399:9324:19d9:3451 prefixlen 88
$ ifconfig | grep 10.147 (stibnite)
	inet 10.147.17.83 netmask 0xffffff00 broadcast 10.147.17.255
```

`7.1-post-c1-visitors-20261018T071704Z.log` and `7.1-gate-20261018T071713Z.log`:

```text
before: stibnite=3 magnetite=1
after 3 stibnite posts: stibnite=6 magnetite=1
PASS: separate visitors
7.1 passed: C2 may start
```

`cinnabar-20261018T070642Z.log`, last lines:

```text
[cinnabar] adding secrets: vars/per-machine/cinnabar/ntfy-alerter-env/ntfy-env, vars/shared/ntfy-alerter/token
[cinnabar] restarting the following units: home-manager-cameron.service, ntfy-sh.service
[cinnabar] starting the following units: hermes-agent-dashboard.service, hermes-agent.service, ntfy-sh.service
[cinnabar] the following new units were started: zerotier-autoaccept-zerotier.service
```

### 9.3 C2 (tasks.md 7.2)

C2 deployed magnetite from `origin/main` `6ccc644bb` with the queue empty (`queue-C2-20261018T075518Z.log`), `C2_START=2026-10-18T07:55:18Z`, `C2_END=2026-10-18T07:56:15Z`.

`magnetite-20261018T075518Z.log`, last lines:

```text
[magnetite] adding secret: vars/shared/ntfy-alerter/token
[magnetite] the following new units were started: fleet-alert.timer
```

`7.2-evaluator-20261018T080629Z.log` (the plan's `systemctl show -p LoadCredential` printed `[unprintable]` and its unprivileged `journalctl` read nothing, so read-only equivalents follow):

```text
Sun 2026-10-18 08:07:00 UTC  29s Sun 2026-10-18 08:06:00 UTC 30s ago fleet-alert.timer fleet-alert.service
TimeoutStartUSec=50s
Result=success
MemoryMax=67108864
OOMScoreAdjust=0
$ sudo jq -c keys /var/lib/fleet-alert/state.json
["budgetPostedAt","firings","hosts","instances","lastRun"]
$ ssh cinnabar.zt curl heartbeat poll | jq -s length
10
$ heartbeat requests authenticated as alerter in the last 5 min
5
$ systemctl cat fleet-alert | grep -E LoadCredential
LoadCredential=regulator-password:/run/secrets/vars/per-machine/magnetite/greptimedb-users/regulator-password
LoadCredential=alerter-token:/run/secrets/vars/shared/ntfy-alerter/token
$ sudo journalctl -u fleet-alert -g "memory peak" -n 5
... 6.5M memory peak ... 7.6M memory peak ... 6M memory peak ... 6.4M memory peak ... 6.6M memory peak ...
$ sudo journalctl -u fleet-alert --since -10min -p warning
-- No entries --
$ systemctl --version | head -1
systemd 261 (261.3)
```

`7.2-notifier-20261018T080653Z.log`:

```text
$ sudo systemctl start observability-notify@acceptance-probe.service
exit=0
$ tail -1 failed.log
1792310814 acceptance-probe magnetite
$ stat failed.log
644 root
$ sudo cat stamp
posted
$ polls.sh fleet-alerts 1792310813
{"time":"2026-10-18T08:06:54Z","title":null,"priority":null,"message":"FAILED acceptance-probe on magnetite"}
stamp removed
$ systemctl cat observability-notify@acceptance-probe | grep -E "LoadCredential|NTFY_TOKEN_FILE"
Environment="NTFY_TOKEN_FILE=%d/alerter-token"
LoadCredential=alerter-token:/run/secrets/vars/shared/ntfy-alerter/token
$ cinnabar ntfy journal: fleet-alerts request since 08:06:50
user_name=alerter visitor_ip=fddb:4344:343b:14b9:399:930f:39db:40d2 ... HTTP request finished
```

`7.2-arc-20261018T080716Z.log`:

```text
MemFree+Cached+SReclaimable=16932134912 MemAvailable=15924097024 gap=1008037888 arc_size=12732406184
PASS: MemAvailable excludes the ARC
```

`7.2-rulesignalmissing-silence-20261018T083133Z.log` (the earlier `…083123Z.log` used GNU `date` and is void, §9.9):

```text
C2_END=2026-10-18T07:56:15Z
$ polls.sh fleet-alerts 1792310175
{"time":"2026-10-18T08:06:54Z","title":null,"priority":null,"message":"FAILED acceptance-probe on magnetite"}
$ count of RuleSignalMissing posts
0
$ RuleSignalMissing instances in state.json
0
```

`7.2-rulesignalmissing-negative-20261018T083139Z.log`:

```text
{"time":"2026-10-18T08:31:44Z","title":"[FIRING] RuleSignalMissing","priority":3,"message":"A rule's presence selector returned no series while an expected host reported host memory, so the rule cannot fire\nrule=HostOOMKill, selector=node_vmstat_oom_kil\nvalue 0"}
# supplement: nothing new on fleet-alerts since T
(end; lines above = new fleet-alerts messages)
```

`7.2-no-refusal-20261018T083257Z.log`, `7.2-main-extra-20261018T083415Z.log` and `7.2-gate-20261018T083438Z.log`:

```text
$ sudo journalctl -u fleet-alert --since 2026-10-18T07:55:18Z | grep -E "status=|Failed"
no failed run
$ count of fleet-alert runs since C2_START (Consumed lines)
37
no 401/403 outside the acceptance topic
$ systemctl list-units --failed
0 loaded units listed.
$ grep curl exit 22 / 401
no curl exit 22 and no 401
7.2 passed: C3 may start
```

### 9.4 C3 and R9.4 (tasks.md 7.3)

C3 deployed cinnabar from `origin/main` `dbec98c74` with the queue empty (`queue-C3-20261018T083506Z.log`), `C3_START=2026-10-18T08:35:07Z`, `C3_END=2026-10-18T08:40:55Z`; `cinnabar-20261018T083507Z.log` ends `the following new units were started: fleet-deadman.timer, zerotier-autoaccept-zerotier.service`.

`7.3-deadman-20261018T085603Z.log` (abridged to the R9.4 and heartbeat lines):

```text
Result=success
LoadCredential=alerter-token:/run/secrets/vars/shared/ntfy-alerter/token
Oct 18 08:45:02 cinnabar fleet-deadman[336601]: fleet-deadman: R9.4 probe refused with HTTP 403
Oct 18 08:45:02 cinnabar fleet-deadman[336601]: fleet-deadman: 11 heartbeat(s) on fleet-heartbeat in the last 10m
Oct 18 08:50:03 cinnabar fleet-deadman[337033]: fleet-deadman: R9.4 probe refused with HTTP 403
Oct 18 08:50:03 cinnabar fleet-deadman[337033]: fleet-deadman: 10 heartbeat(s) on fleet-heartbeat in the last 10m
Oct 18 08:55:00 cinnabar fleet-deadman[337430]: fleet-deadman: R9.4 probe refused with HTTP 403
Oct 18 08:55:00 cinnabar fleet-deadman[337430]: fleet-deadman: 10 heartbeat(s) on fleet-heartbeat in the last 10m
probe refusals: 3
```

`7.3-matrix-20261018T085609Z.log`:

```text
T_ANON403=2026-10-18T08:56:09Z
anonymous fleet-alerts: HTTP 403
anonymous stibnite:     HTTP 200
$ alerter on cinnabar to fleet-acceptance
{"id":"P2rm6NQwKREo","time":1792313771,"expires":1792356971,"event":"message","topic":"fleet-acceptance","message":"c3 alerter probe"}
alerter exit=0
$ systemctl status fleet-alert on magnetite
Result=success
10
$ anonymous read of fleet-alerts still allowed
anonymous read: HTTP 200
```

`7.3-r94-baseline-20261018T085616Z.log`:

```text
ls: cannot access '/var/lib/observability-notify': No such file or directory
Result=success
```

The negative control deployed cinnabar from `origin/main` `dbec98c74` with one line deleted (`R94NEG_START=2026-10-18T08:56:25Z`, `R94NEG_END=2026-10-18T08:57:49Z`); `7.3-r94-negative-deploy-20261018T085624Z.log` begins:

```text
origin/main: dbec98c74 feat(fleet-alert): dead-man on cinnabar and fleet-* access control
0	1	modules/machines/nixos/cinnabar/ntfy.nix
R94NEG_START=2026-10-18T08:56:25Z
```

`7.3-r94-negative-20261018T090020Z.log`:

```text
Oct 18 09:00:02 cinnabar fleet-deadman[346053]: fleet-deadman: R9.4: anonymous publish to fleet-heartbeat answered HTTP 200, expected 403
Oct 18 09:00:02 cinnabar systemd[1]: fleet-deadman.service: Main process exited, code=exited, status=1/FAILURE
Result=exit-code
posted
{"time":"2026-10-18T09:00:02Z","title":null,"priority":null,"message":"FAILED fleet-deadman.service on cinnabar"}
```

The redeploy from unmodified `origin/main` `dbec98c74` (`C3RE_START=2026-10-18T09:00:26Z`, `C3RE_END=2026-10-18T09:00:44Z`, `7.3-r94-redeploy-20261018T090025Z.log`) returned cinnabar to `/nix/store/7ivjc63ij7scmkmm5m4v22yn0hw10pj4-nixos-system-cinnabar-26.11.20261007.ac1faec`.

`7.3-r94-resolved-20261018T090520Z.log`:

```text
Oct 18 09:05:00 cinnabar fleet-deadman[349033]: fleet-deadman: R9.4 probe refused with HTTP 403
Result=success
stamp cleared
{"time":"2026-10-18T09:05:00Z","title":null,"priority":null,"message":"RESOLVED fleet-deadman.service on cinnabar"}
W_END=2026-10-18T09:05:22Z
```

### 9.5 No refused post across the cutover (tasks.md 7.4)

The window is `C1_START=2026-10-18T07:06:42Z` to `W_END=2026-10-18T09:05:22Z`; the journal extract `7.4-ntfy-journal-20261018T090524Z.log` holds 1625 lines.

`7.4-curl22-control-20261018T085613Z.log`:

```text
T_CURL22=2026-10-18T08:56:13Z
Main processes terminated with: code=exited, status=22/n/a
exit=22
Oct 18 08:56:14 magnetite systemd[1]: s3-curl22-control.service: Main process exited, code=exited, status=22/n/a
```

`7.4-refusals-20261018T090526Z.log` (the three refusal lines abridged to their status, path and visitor):

```text
window: 2026-10-18T07:06:42Z .. 2026-10-18T09:05:22Z
all 401/403: 7
deliberate R9.4 probes (POST /fleet-heartbeat from ::1, HTTP 403): 4
deliberate 7.1 unknown token at 2026-10-18T07:16:35Z (HTTP 401, /fleet-acceptance):
2026-10-18T07:16:35+00:00 ... http_path=/fleet-acceptance, http_status=401, ... visitor_ip=10.147.17.83 ...
deliberate 7.3 anonymous probe at 2026-10-18T08:56:09Z (HTTP 403, /fleet-alerts):
2026-10-18T08:56:09+00:00 ... http_path=/fleet-alerts, http_status=403, ... visitor_ip=10.147.17.83 ...
deliberate 7.4 control at 2026-10-18T08:56:13Z (HTTP 403, /fleet-acceptance):
2026-10-18T08:56:14+00:00 ... http_path=/fleet-acceptance, http_status=403, ... visitor_ip=fddb:4344:343b:14b9:399:930f:39db:40d2 ...
unexplained:
none
/fleet-alerts refusals (must be 1): 1
no /fleet-heartbeat refusal from a mesh client
$ magnetite journal, status=22 since C1_START
2026-10-18T08:56:14+00:00 magnetite systemd[1]: s3-curl22-control.service: Main process exited, code=exited, status=22/n/a
```

The four R9.4 probes are the five dead-man runs from `C3_END` to `W_END` minus the negative-control run, which ntfy answered 200.

The `log-level` revert (PR #3509, `6caa2425c`) passed its isolated checks (`7.4-revert-isolated-20261018T103025Z.log`: `treefmt`, `ntfy-provisioning` and `nixos-cinnabar` exit 0) and was deployed to cinnabar with the queue empty (`queue-LOGREVERT-20261018T103909Z.log`), `LOGREVERT_START=2026-10-18T10:39:09Z`, `LOGREVERT_END=2026-10-18T10:40:31Z`.
`7.4-revert-deployed-20261018T104032Z.log` names the deployed `/nix/store/4ir7p5r9bj7vxs9995fsh8gj7c2cmmbj-server.yml`; at 11:31Z `ssh cinnabar.zt 'grep -c log-level /nix/store/4ir7p5r9bj7vxs9995fsh8gj7c2cmmbj-server.yml'` printed `0`, and `origin/main`'s `modules/machines/nixos/cinnabar/ntfy.nix` has no `log-level` line.
tasks.md 7.4's verify names `nix eval … settings.log-level or null`; that evaluation was not run, and the source and delivered-file reads above stand in for it.

### 9.6 R9.3 (tasks.md 7.5)

`T_STOP=2026-10-18T09:05:34Z` (`7.5-stop-20261018T090534Z.log`: `inactive`) and `T_START=2026-10-18T09:20:50Z` (`7.5-start-20261018T092050Z.log`: `active`).
`[FIRING] AlertEvaluatorSilent magnetite` arrived 14 min 28 s after the stop, inside the 15 min the task allows, and `[RESOLVED]` 4 min 12 s after the start, inside 10 min.

`7.5-silent-20261018T092040Z.log` and `7.5-resolved-20261018T093153Z.log`:

```text
{"time":"2026-10-18T09:20:02Z","title":"[FIRING] AlertEvaluatorSilent magnetite","priority":4,"message":"No fleet-heartbeat message reached ntfy in 10 min: the evaluator, its host or its path to ntfy is down, and no other alert can be sent.\nhost_name=magnetite\nvalue 1"}
Oct 18 09:10:03 cinnabar fleet-deadman[349453]: fleet-deadman: 5 heartbeat(s) on fleet-heartbeat in the last 10m
Oct 18 09:15:01 cinnabar fleet-deadman[349977]: fleet-deadman: 1 heartbeat(s) on fleet-heartbeat in the last 10m
Oct 18 09:20:02 cinnabar fleet-deadman[350434]: fleet-deadman: 0 heartbeat(s) on fleet-heartbeat in the last 10m
{"time":"2026-10-18T09:25:02Z","title":"[RESOLVED] AlertEvaluatorSilent magnetite","priority":4,"message":"No fleet-heartbeat message reached ntfy in 10 min: the evaluator, its host or its path to ntfy is down, and no other alert can be sent.\nhost_name=magnetite"}
Oct 18 09:25:02 cinnabar fleet-deadman[350893]: fleet-deadman: 5 heartbeat(s) on fleet-heartbeat in the last 10m
Oct 18 09:30:02 cinnabar fleet-deadman[351295]: fleet-deadman: 11 heartbeat(s) on fleet-heartbeat in the last 10m
```

### 9.7 Every shipped rule fired and resolved (tasks.md 7.6)

Real conditions on `fleet-alerts`:

| Rule | Forced by | FIRING | RESOLVED | Log |
|---|---|---|---|---|
| `HostOOMKill` | cgroup OOM kill at `T_OOM=09:32:15Z`, `oom_kill` 0 → 1 | 09:33:02, priority 4, with attribution | 09:43:02, before 5 min of unfrozen absence (defect, §11); after #3510: FIRING 11:04:01, RESOLVED 11:19:02 | `7.6-oom-20261018T093213Z.log`, `7.6-oom-store-resolved-20261018T095420Z.log`, `10.1-reobserve-*` |
| `StoreQueryFailing` | `greptimedb` stopped 09:35:10Z–09:42:12Z | 09:39:01, priority 4, 3 min 51 s into the stop; no `RESOLVED` of any instance during the stop | 09:47:02 | `7.6-store-20261018T093510Z.log`, `7.6-oom-store-resolved-…` |
| `LocalExporterDown` | node exporter stopped 09:54:42Z–10:06:45Z, `up{job="node"}` read `["0"]` | 10:05:02, priority 3 | 10:11:02 | `7.6-exporter-20261018T095442Z.log`, `7.6-exporter-alerts-20261018T101350Z.log` |

`7.6-oom-store-resolved-20261018T095420Z.log`:

```text
{"time":"2026-10-18T09:33:02Z","title":"[FIRING] HostOOMKill magnetite","priority":4,"message":"The kernel killed a process for memory in the last 10 min\nhost_name=magnetite, instance=127.0.0.1:9100, job=node, service_instance_id=127.0.0.1:9100, service_name=node\nvalue 1.018351851851852\nZFS ARC size: 4813 MB\nswap used: 906 MB\ntop 3 executables by resident memory, which omits swapped-out pages: greptime 190 MB, .postgres-wrapp 147 MB, .gitea-wrapped 83 MB"}
{"time":"2026-10-18T09:39:01Z","title":"[FIRING] StoreQueryFailing","priority":4,"message":"The telemetry store has not answered the evaluator's queries; every other alert instance is frozen\nvalue 1"}
{"time":"2026-10-18T09:43:02Z","title":"[RESOLVED] HostOOMKill magnetite","priority":4,"message":"The kernel killed a process for memory in the last 10 min\nhost_name=magnetite, instance=127.0.0.1:9100, job=node, service_instance_id=127.0.0.1:9100, service_name=node"}
{"time":"2026-10-18T09:47:02Z","title":"[RESOLVED] StoreQueryFailing","priority":4,"message":"The telemetry store has not answered the evaluator's queries; every other alert instance is frozen"}
HostOOMKill FIRING: 1  RESOLVED: 1
StoreQueryFailing FIRING: 1  RESOLVED: 1
```

`7.6-exporter-alerts-20261018T101350Z.log`:

```text
{"time":"2026-10-18T10:05:02Z","title":"[FIRING] LocalExporterDown magnetite","priority":3,"message":"A loopback exporter the collector scrapes is down\nhost_name=magnetite, instance=127.0.0.1:9100, job=node, service_instance_id=127.0.0.1:9100, service_name=node\nvalue 0"}
{"time":"2026-10-18T10:11:02Z","title":"[RESOLVED] LocalExporterDown magnetite","priority":3,"message":"A loopback exporter the collector scrapes is down\nhost_name=magnetite, instance=127.0.0.1:9100, job=node, service_instance_id=127.0.0.1:9100, service_name=node"}
```

Hand runs of the deployed evaluator (`/nix/store/lvg5rihbi8ibdzrg6b4l4xjggx82as56-fleet-alert/bin/fleet-alert`) with each threshold or matcher changed, topic `fleet-acceptance` and a scratch state, `T_FORCED=1792318436` (10:13:56Z); the window was set to weekday 7, 06:13–06:25 New York time.
All sixteen runs exited 0.
`7.6-forced-resolved-20261018T102119Z.log`, the poll of `fleet-acceptance` since `T_FORCED` and the counts:

```text
{"time":"2026-10-18T10:14:00Z","title":"[FIRING] SystemdUnitRestartLoop magnetite","priority":3,"message":"A unit restarted more than 5 times in 15 min\nhost_name=magnetite, systemd_unit_name=nixbot.service\nvalue 0"}
{"time":"2026-10-18T10:14:01Z","title":"[FIRING] WeeklyPipelineTest","priority":2,"message":"Weekly test of the alert path: the value is the number of hosts reporting host memory\nvalue 1"}
{"time":"2026-10-18T10:15:02Z","title":"[FIRING] ZfsPoolUnhealthy magnetite","priority":4,"message":"A ZFS pool is not online\nhost_name=magnetite, instance=127.0.0.1:9100, job=node, service_instance_id=127.0.0.1:9100, service_name=node, state=online, zpool=zroot\nvalue 1"}
{"time":"2026-10-18T10:19:09Z","title":"[FIRING] HostMemoryPressure magnetite","priority":3,"message":"Available memory, counting the ZFS ARC above its minimum, is below 10 % of total, or swap use is above 85 %\nhost_name=magnetite\nvalue 0.7889289925227672\nZFS ARC size: 4974 MB\nswap used: 904 MB\ntop 3 executables by resident memory, which omits swapped-out pages: greptime 196 MB, .postgres-wrapp 150 MB, .gitea-wrapped 84 MB"}
{"time":"2026-10-18T10:19:09Z","title":"[FIRING] SystemdUnitFailed magnetite","priority":3,"message":"A unit the failure notifier does not report has failed\nhost_name=magnetite, systemd_unit_active_state=active, systemd_unit_name=nix-daemon.service\nvalue 1"}
{"time":"2026-10-18T10:26:30Z","title":"[RESOLVED] HostMemoryPressure magnetite","priority":3,"message":"Available memory, counting the ZFS ARC above its minimum, is below 10 % of total, or swap use is above 85 %\nhost_name=magnetite"}
{"time":"2026-10-18T10:26:30Z","title":"[RESOLVED] SystemdUnitFailed magnetite","priority":3,"message":"A unit the failure notifier does not report has failed\nhost_name=magnetite, systemd_unit_active_state=active, systemd_unit_name=nix-daemon.service"}
{"time":"2026-10-18T10:26:30Z","title":"[RESOLVED] SystemdUnitRestartLoop magnetite","priority":3,"message":"A unit restarted more than 5 times in 15 min\nhost_name=magnetite, systemd_unit_name=nixbot.service"}
{"time":"2026-10-18T10:26:30Z","title":"[RESOLVED] ZfsPoolUnhealthy magnetite","priority":4,"message":"A ZFS pool is not online\nhost_name=magnetite, instance=127.0.0.1:9100, job=node, service_instance_id=127.0.0.1:9100, service_name=node, state=online, zpool=zroot"}
HostMemoryPressure FIRING 1 RESOLVED 1
ZfsPoolUnhealthy FIRING 1 RESOLVED 1
SystemdUnitRestartLoop FIRING 1 RESOLVED 1
SystemdUnitFailed FIRING 1 RESOLVED 1
WeeklyPipelineTest FIRING 1 RESOLVED 0
scratch state removed
```

`7.6-final-state-20261018T102850Z.log` shows nothing new on `fleet-alerts` since `T_FORCED`, magnetite's five units active with no failed unit, cinnabar on `7ivjc63…` with no failed unit, the pyrite capture active, and no `/tmp/wt-s3-*` worktree left.

### 9.8 Subscription and the first Monday message (tasks.md 7.7)

PASS, by a test post after the first Monday message reached no phone.
The first window after deployment was Monday 2026-10-19, 09:00–09:05 America/New_York, which is 13:00–13:05 UTC.
The evaluator posted the scheduled alert in that window, and ntfy accepted it; the evaluator's journal (quoted in `9.1-budget-20261020T223210Z.log`) and the pyrite capture (`9.1-fleet-alerts-capture.jsonl`) each hold it:

```text
2026-10-19T13:00:01Z p=2 [FIRING] WeeklyPipelineTest
{"id":"KFK1gVKC6rZu","time":"2026-10-19T13:00:01Z","title":"[FIRING] WeeklyPipelineTest","priority":2}
```

The operator had not yet installed ntfy on the phone, so no device received it.
On 2026-10-20 the operator installed the ntfy app and subscribed it to `fleet-alerts` at `https://ntfy.zt`, following the runbook.
A first test post with plain `curl` failed certificate verification against caddy's internal CA and sent nothing (`7.7-test-post-20261020T231141Z.log`: `curl: (60) SSL certificate OpenSSL verify result: unable to get local issuer certificate (20)`); this is not a defect, because every production sender posts through `ntfy-send`, which passes `-k`, and the runbook now says so.
The second was sent from magnetite through `ntfy-send` with the `alerter` token file, as the evaluator posts (`7.7-test-post-20261020T231209Z.log`):

```text
{"id":"tA8WItkDXEKi","time":1792537931,"topic":"fleet-alerts","title":"[TEST] 7.7 phone delivery check"}
exit= sent=2026-10-20T23:12:11Z
```

```text
[operator] 2026-10-20: ntfy app installed on the phone and subscribed to fleet-alerts at https://ntfy.zt
[operator] 2026-10-20, shortly after 23:12:11Z: "[TEST] 7.7 phone delivery check" (id tA8WItkDXEKi) received on the phone
```

The test post's `[TEST]` title is not a `FIRING`, and R9.1 counts only `state.json` and `failed.log`, so it does not touch the alert budget.
The deviation from tasks.md 7.7's wording is that the phone's receipt was shown by this test post on the same topic and server, not by the first Monday message; the next Monday message, 2026-10-26, is the first scheduled one a subscribed phone can receive.

### 9.9 Plan-expectation deviations (not defects)

Each item is a difference between the plan's expected text and what ran, recorded in the agents' step reports; none changed a verdict.

- RED wording, Tasks 1, 2 and 5: the installed nix prints `error: Cannot build '…drv'.` then `Reason: builder failed with exit code 1.`, and the remote builder `error: build of '…' on 'grpc://…' failed: Cannot build …`, where the plan expected `builder for '…' failed with exit code 1` (`1.2-token-transport-red-…`, `2.3-rehearsal-red-…`).
  Task 5's RED steps failed on `attribute 'fleet-deadman' missing` rather than the plan's `fleetAlertDeadman`, because the check forces cinnabar's unit first (`5.1-fleet-alert-red-*.log`).
- Task 1 Step 8: `--help` shows `NTFY_TOKEN_FILE` at lines 11 and 24, not the plan's 17 and 29 (`1.1-ntfy-send-package-…`).
- Task 2 Steps 11 and 15: the join was rebased between Steps 4 and 11, so the Step 1 baseline was stale and showed 26 extra `resolved` hook lines; re-baselined at `@-`, the diff is the one `observability-notify-failed` `ExecStart` path the plan expects (`2.4-notifier-diff-…`, `2.4-notifier-rebaseline-parent-…`).
- Task 2 Step 12: R3.1 printed one failure, not two, because the start-hook clause compared `[ null ]` with `[ null ]` and passed without testing anything; Step 13's `lib.optional (m != null)` was the planned fix and closed it (`2.4-r31-token-red-…`).
- Task 2 Step 14 and Task 4 builds: cached derivations print no `ok:` lines, so the `nix log` output was appended (`2.4-otel-collector-config-…`).
- Task 4's determinism `--rebuild` first ran on aarch64-darwin and failed on platform mismatch (`4.6-determinism-20261018T074331Z.log`); the rerun printed `check-exit=0` (`…074343Z.log`).
- Task 5 Step 5 needed the plan's own fallback `f.packages.x86_64-linux.ntfy-send`, because plain nixpkgs has no `ntfy-send` (`5.1-fleet-deadman-build-…`); its Step 10 override pipe fed nix's stderr into `jq`, fixed in plan.md Task 5.
- Titles without a host: `RuleSignalMissing`, `StoreQueryFailing` and `WeeklyPipelineTest` instances carry no `host_name`, so their titles are `[FIRING] RuleSignalMissing`, `[FIRING] StoreQueryFailing` and `[FIRING] WeeklyPipelineTest`, where Task 7's expected text named `magnetite`; plan.md:1758 and :4435 state the host-less form, the orchestrator accepted it, and tasks.md 10.7 (#3516) added it to the title requirement (§4).
- `greptimedb-schema` is `PartOf=greptimedb.service`: stopping the store in 7.6 stopped it, and starting the store did not start it again; S3OpsPreC1 restarted it at 09:42:43Z (`7.6-store-20261018T093510Z.log`), and the 10.1 re-observation started both units; review F9 made the store pull it in again (tasks.md 10.6, §11.2).
- 7.6 Step 30's check `grep -E 'status=|Failed'` matched curl's `Failed to connect` stderr; the supplement shows all eight runs `Deactivated successfully`.
- 7.6 Step 29's journal says "The kernel OOM killer killed some processes in this unit", not the plan's "A process of this unit has been killed by the OOM killer"; the `oom-kill` result line matches.
- 7.1: stibnite reached ntfy over IPv4 (`10.147.17.83`), not an `fddb:` address; the visitor is still its own address and not `::1`, so the check holds, but `visitor-prefix-bits-ipv6 = 128` does not apply to it (`7.1-visitor-journal-…`).
- 7.3 Step 20: the line to delete from `ntfy.nix` is indented 12 spaces on `origin/main` after `nix fmt`, not the plan's 10; the orchestrator approved the 12-space line, and `s3-deploy.sh`'s exactly-one-line guard printed `0	1	modules/machines/nixos/cinnabar/ntfy.nix`.
- systemd 261.3: `systemctl show -p LoadCredential` prints `[unprintable]`, and `systemctl show -p Environment` prints `NTFY_TOKEN_FILE` with `%d` already expanded to `/run/credentials/observability-notify@acceptance-probe.service/alerter-token`; `systemctl cat` was added to show the configured values (`7.2-notifier-…`, `7.3-deadman-…`).
- Unprivileged `journalctl` on magnetite prints "No journal files were opened due to insufficient permissions", which made 7.2 Step 14's `no failed run` vacuous; that read was repeated with `sudo`, and from 7.3 on every journal read used `sudo` (`7.2-no-refusal-…`, `run-7.3-7.6.sh`).
- GNU `date` is first on stibnite's `PATH` and has no `-j`; 7.2 Step 12's first run (`7.2-rulesignalmissing-silence-20261018T083123Z.log`) therefore polled with an empty `since` and is void, and the rerun and every later BSD `date -j` call used `/bin/date`.

### 9.10 Defects found and fixed

- Task 5, `select(has("expr"))`: Task 4's `transition.jq` evaluated only rules with an `expr`, so the dead-man's `AlertEvaluatorSilent`, which has none, could never fire.
  Before Task 5's merge, `transition.jq` and `model.py` were changed to read a rule from `results` when it has an `expr` or a results entry, except `StoreQueryFailing` and `RuleSignalMissing`, with a property that an `expr`-less twin behaves identically; that property failed against the old selection (`5.1-transition-selection-old-control-20261018T080442Z.log`: `AssertionError: transition.jq: a rule without expr differs from its expr twin`) and passed against the new one (`5.1-transition-selection-local-20261018T080220Z.log`).
  Landed in PR #3508; design D11 and tasks.md 4.2 and 5.1 state the selection.
- PR #3510, frozen time counted as absence: after a 7 min store stop, `[RESOLVED] HostOOMKill magnetite` came at 09:43:02, 50 s after the store returned, because absence ran from the last observation before the freeze (`7.6-oom-store-resolved-20261018T095420Z.log`); §11 records the fix.
- The vars regeneration: `clan vars generate magnetite --generator ntfy-alerter` regenerated the shared `alerter` token and re-ran cinnabar's `ntfy-alerter-env` (`4.8-vars-magnetite-20261018T073644Z.log`: `[shared] Updated secret var ntfy-alerter/token for machines: cinnabar, magnetite` and `[cinnabar] Updated secret var ntfy-alerter-env/ntfy-env`).
  Deployed, that token would have differed from the one C1 had provisioned on cinnabar.
  The orchestrator caught it before Task 4's commit, restored `vars/shared/ntfy-alerter` and `vars/per-machine/cinnabar/ntfy-alerter-env` from the working-copy parent, and ran `CLAN_NO_COMMIT=1 clan vars fix magnetite --generator ntfy-alerter`, which only added magnetite's age recipient to the token's secret (`4.8-vars-fix-magnetite-20261018T073724Z.log`).
  tasks.md 4.8 records the command and the hazard.
- The evaluation-cost method (PR #3511, charter v19): `nix eval .#checks…` without the leading dot first probes `packages` and `legacyPackages`, adding about 114 MB with the eval cache off.
  Task 4 measured `checks.fleet-alert` at 0.557 GiB and `checks.greptimedb-envelope` at 553 MB that way and moved the token-wiring and kill-order clauses into module assertions (charter v18); S3FixAbsence reported 0.56 GiB over budget.
  With `.#.`, the check was 0.252 GiB at Task 4's merge and 0.453 GiB at Task 5's merge and at `6caa2425c`, and the envelope check about 439 MB before the move (§9.1); #3511 corrected tasks.md 4.7, the plan's commands and the evidence text.

## 10. Integration verification (tasks.md 9.1) and the sync order (tasks.md 8.3)

### 10.1 The closed alert loop

| Link | Evidence | State |
|---|---|---|
| `LocalExporterDown` pair on `fleet-alerts` | FIRING 10:05:02Z, RESOLVED 10:11:02Z (`7.6-exporter-alerts-…`, §9.7), and both in the pyrite capture | recorded |
| the same pair on the operator's phone | composed: pyrite's capture, a `fleet-alerts` subscriber, received both messages of the pair, which proves the evaluator-to-ntfy-to-subscriber path for those exact messages; the 7.7 test post `tA8WItkDXEKi` proves that the phone is a subscriber of the same topic on the same server (§9.8); the pair itself was not seen on the phone, which was not subscribed until 2026-10-20 | PASS WITH WARNING |
| `AlertEvaluatorSilent` pair | FIRING 09:20:02Z, RESOLVED 09:25:02Z (§9.6) | recorded |
| anonymous `fleet-*` publish refused beside an accepted host-topic publish | `anonymous fleet-alerts: HTTP 403`, `anonymous stibnite: HTTP 200` (§9.4) | recorded |
| no refused post across the cutover | `unexplained: none`, 7 refusals all deliberate (§9.5) | recorded |
| R9.1's count equals the captured `FIRING` messages | §10.2 | PASS |

### 10.2 The alert budget count against the posted messages

ntfy keeps a topic's messages for 12 hours (A42), so pyrite captured `fleet-alerts` to a file from `T_CAP_START=2026-10-18T09:32:05Z` (`9.1-capture-start-20261018T093159Z.log`).
The orchestrator ran plan.md Task 8 Step 2 at 2026-10-20T22:32:10Z (`9.1-budget-20261020T223210Z.log`).
The capture ran continuously from 2026-10-18T09:32:00Z (`NRestarts=0`); its three `open` events, at 09:32:00Z, 2026-10-18T10:40:32Z and 2026-10-20T21:16:42Z, are the start and two reconnects, each resumed with `since=<last id>`.
The copy kept as `9.1-fleet-alerts-capture.jsonl` has 4864 lines; the orchestrator reports that the capture unit was then stopped and its files removed from pyrite.

Two windows were compared.
Window A is the latest 24 hours ending at the evaluator's `lastRun`, (2026-10-19T22:30:01Z, 2026-10-20T22:30:01Z]: R9.1 over the live `state.json` and `failed.log` is 0, and the capture holds no message in it.
Window B is the first 24 hours of the capture, (2026-10-18T09:32:05Z, 2026-10-19T09:32:05Z], which holds all of 7.6.
R9.1 prunes `state.json`'s `.firings` after 86400 s, so for window B `.firings` was rebuilt from the evaluator's journal of posts; that rebuilt state, not the live file, is what this window compares.

```text
$ ssh pyrite.zt systemctl show fleet-alerts-capture -p ActiveState -p ActiveEnterTimestamp -p NRestarts
ActiveState=active
ActiveEnterTimestamp=Sun 2026-10-18 05:32:00 EDT
NRestarts=0
== capture opens (reconnects):
2026-10-18T09:32:00Z
2026-10-18T10:40:32Z
2026-10-20T21:16:42Z
== magnetite failed.log:
1792310814 acceptance-probe magnetite
== state.json lastRun=1792535401 (2026-10-20T22:30:01Z) budgetPostedAt=null firings=[]
##### Window A (primary): latest complete 24 h ending at the evaluator's lastRun
W = (2026-10-19T22:30:01Z, 2026-10-20T22:30:01Z]
PASS A: R9.1=0 equals capture=0
##### Window B (supplementary): (T_CAP_START, T_CAP_START + 24 h], state.firings reconstructed from the evaluator journal
W = (2026-10-18T09:32:05Z, 2026-10-19T09:32:05Z]
reconstructed firings:
{"at":1792315982,"alert":"HostOOMKill","host":"magnetite"}
{"at":1792316341,"alert":"StoreQueryFailing","host":""}
{"at":1792317902,"alert":"LocalExporterDown","host":"magnetite"}
{"at":1792321441,"alert":"HostOOMKill","host":"magnetite"}
{"at":1792321800,"alert":"StoreQueryFailing","host":""}
capture side firing:
[FIRING] LocalExporterDown magnetite, [FIRING] StoreQueryFailing, [FIRING] HostOOMKill magnetite, [FIRING] HostOOMKill magnetite, [FIRING] StoreQueryFailing
failed_magnetite: [], total: 5
PASS B: R9.1=5 equals capture=5
== journal vs capture, every fleet-alerts post by the evaluator since capture start:
identical id sets
```

The only `failed.log` line, `acceptance-probe` at 2026-10-18T08:06:54Z (7.2), predates the capture, so the plan's "if it falls inside" did not apply; cinnabar's `fleet-deadman` notice is not counted by R9.1 (design Trade-offs).
The `[FIRING] WeeklyPipelineTest` at 2026-10-19T13:00:01Z is `info`, which R9.1 does not count, and falls after window B.
9.1's R9.1 comparison passes; its phone link is the composition of §10.1.

### 10.3 Sync order against share-ghq-reference-tree

The orchestrator ran plan.md Task 8 Step 3; no `8.3-sync-order-*.log` is in `logs/s3-evidence/`.
It reports that `share-ghq-reference-tree` is not archived and that the stop condition holds: its `Grounded vocabulary for behavioral requirements` block has 56 designation rows against 106 on main, so archiving it unrebased would delete 62 of main's rows.
Decision: S3 archives first, because its block is built on the current main table; `share-ghq-reference-tree` must rebase its block on S3's synced main before its own archive.

A read-only recount at 2026-10-20 22:34 UTC with Step 3's `rows` function under `LC_ALL=C`, excluding the header and separator rows, gave main 118, the S3 delta 128 and the ghq delta 67, with 65 main rows missing from the ghq delta, `person` and `writer` among them; the counts differ from the orchestrator's by method, and both show the stop condition.
The recount's only main row missing from the S3 delta is `credential | notification service`, which S3 rewrites under the same term and sense, the exception Step 3 allows.

## 11. Review follow-ups (tasks.md section 10)

The holistic review (plan.md Task 8, tasks.md 8.2) replaces the paid codex review at the operator's direction, as in S1.
Its report is `logs/s3-evidence/review-report.md`, committed verbatim in `openspec/changes/stand-up-fleet-alerting/review.md` with a disposition table: nothing critical, eleven findings F1–F11, four significant and seven minor.
F4 (the ntfy-outage residual risk) is documented in the runbook and charter v21, with CAM-76 now blocking CAM-72 (S5); F10 (one database header for every query) is deferred to S2; neither changes code here.
F12, the host-less titles, came from §4's first-run drift warning, is named by tasks.md 10.7, and is not in the report's own table.
tasks.md 10.1 predates the review and is §11.1; the applied findings landed in two pull requests, each with its checks red before and green after as tasks.md 10.2–10.10 record.

### 11.1 Frozen time is not absence (tasks.md 10.1, PR #3510)

`transition.jq` and `model.py` keep `absenceFrom` per instance, cleared on every run frozen by the store or the instance's host and set again at the first unfrozen run; an instance resolves once `now - absenceFrom` reaches 300 s.
Against the old code, the new legs and the new property failed (`10.1-red-20261018-063317.log`):

```text
MISS HostOOMKill last seen before 7 runs of store error resolves 5 min after the store answers again, not on its first answer
MISS HostOOMKill on stibnite last seen before 7 silent runs resolves 5 min after stibnite reports again, not on its first report
AssertionError: RESOLVED before 5 min of unfrozen absence: transition.jq: run 3: [RESOLVED] Crit magnetite; model: run 3: [RESOLVED] Crit magnetite
```

After the fix, `checks.x86_64-linux.fleet-alert` built with every leg passing and the mutants `forZero`, `noStateWrite`, `noStoreFreeze`, `noAbsenceFreeze` and `noRepost` rejected (`10.1-green-20261018-063515.log`), and `nixos-magnetite`, `nixos-cinnabar` and `treefmt` exited 0 (`10.1-hosts-20261018-063657.log`, `10.1-isolated-20261018T104502Z.log`).

It was deployed to magnetite (`FIX101_magnetite_START=2026-10-18T11:00:26Z`, `_END=11:01:19Z`) and cinnabar (`FIX101_cinnabar_START=2026-10-18T11:01:20Z`, `_END=11:02:41Z`), each with the queue empty.
At 11:31Z the `transition.jq` that magnetite's `fleet-alert` and cinnabar's `fleet-deadman` load each contained `absenceFrom` five times (`grep -c` over the store path each unit references), and neither host had a failed unit.

`10.1-reobserve-resolved-20261018T112530Z.log`, the 7.6 store-stop timeline repeated (messages abridged after their priority):

```text
T_OOM=2026-10-18T11:03:32Z
T_STORE_STOP=2026-10-18T11:06:10Z
T_STORE_START=2026-10-18T11:13:12Z
{"time":"2026-10-18T11:04:01Z","title":"[FIRING] HostOOMKill magnetite","priority":4,...}
{"time":"2026-10-18T11:10:00Z","title":"[FIRING] StoreQueryFailing","priority":4,...}
{"time":"2026-10-18T11:18:02Z","title":"[RESOLVED] StoreQueryFailing","priority":4,...}
{"time":"2026-10-18T11:19:02Z","title":"[RESOLVED] HostOOMKill magnetite","priority":4,...}
HostOOMKill FIRING: 1  RESOLVED: 1
StoreQueryFailing FIRING: 1  RESOLVED: 1
first run after store returned: 2026-10-18T11:14:01Z; HostOOMKill RESOLVED: 2026-10-18T11:19:02Z; delta 301s
PASS: RESOLVED >= 5 min after the first run after the store returned
```

### 11.2 PR #3516: F1, F2, F5, F8, F9, F11, F12 (tasks.md 10.2–10.7)

- F1 and F11 (10.2): an always-on host, magnetite alone, absent from `system_memory_usage_bytes` for 10 min while the store answers raises `RuleSignalMissing magnetite`, exempt from the host freeze; `state.hosts` is now read.
  The always-on-host leg and the `noHostsUpdate` mutant failed before the fix (`review-a-F1-red-20261020-155359.log`) and pass after (`review-a-green-20261020-155814.log`).
- F2 (10.3): `observability-notify@*.service` joins the collector's unit allow-list, so a failed notifier post becomes a `SystemdUnitFailed` instance; the exclusion regex matches `greptimedb.service` and none of magnetite's notifier instances (`review-a-F2-20261020-155700.log`).
- F5 (10.4): R9.5 asserts `MemoryMax` and the timing relation; magnetite's evaluation fails at `postDeadlineSec = 40` (`review-a-F5-red-20261020-154626.log`), and the deadline drops to 35.
- F8 (10.5): an unreadable `failed.log` fails the run before any post; `unreadableLogLeg` failed before the fix (`review-a-F8-red-20261020-154753.log`) and passes after.
- F9 (10.6): `greptimedb-schema` is wanted by `greptimedb.service` (`review-a-F9-20261020-155820.log`).
- F12 (10.7): the title requirement states the host-less titles (`review-a-validate-20261020-155922.log`).

`review-a-isolated-20261020T202237Z.log` records `treefmt`, `fleet-alert`, `otel-collector-config`, `greptimedb-envelope`, `package-vanixiets-docs-test-linkcheck`, `nixos-magnetite` and `nixos-cinnabar` exit 0.
#3516 was deployed to magnetite (`REVA_magnetite_START=2026-10-20T20:44:49Z`, `_END=20:45:45Z`) and cinnabar (`REVA_cinnabar_START=2026-10-20T20:45:46Z`, `_END=20:54:27Z`).

`10.6-schema-restart-20261020T205427Z.log`, the runtime check of F9 on magnetite:

```text
+zsh:1> systemctl show greptimedb-schema -p WantedBy
WantedBy=opentelemetry-collector.service greptimedb.service multi-user.target
+zsh:1> sudo systemctl stop greptimedb
inactive
+zsh:1> sudo systemctl start greptimedb
+zsh:1> systemctl is-active greptimedb greptimedb-schema
active
active
+zsh:1> systemctl show greptimedb-schema -p Result -p ActiveEnterTimestamp
ActiveEnterTimestamp=Tue 2026-10-20 20:54:37 UTC
Result=success
0
```

The final `0` is the count of failed units.

### 11.3 PR #3519: F3, F6, F7 (tasks.md 10.8–10.10)

- F3 (10.8): the dead-man's relations within cinnabar, `deadman.ntfyUrl` against ntfy's `listen-http` and the access entries read with A38's decision, move from the check into assertions on the host that enables the dead-man; each fails under its override (`review-b-F3-F6-assertion-overrides-20261020-164505.log`), and `checks.fleet-alert` falls from 488,343,456 B (0.455 GiB) to 328,151,376 B (0.306 GiB) (§9.1).
- F6 (10.9): the token-path and credential-name assertions that restated the lines setting them are deleted; `unitsWithoutToken` stays and fails when `fleet-alert.service`'s `ExecStopPost` is replaced, and R3.1 fails with the pre-token hook regex (`review-b-F6-resolvedHook-narrowed-20261020-164635.log`).
- F7 (10.10): four fire-and-resolve legs that read their expectations from the evaluator's own rules are deleted; the scenario "A storage pool degrades" is now discharged by 7.6's hand run against magnetite's store.
  The remaining legs pass, and `noStateWrite`, `forZero`, `noStoreFreeze`, `noAbsenceFreeze`, `noHostsUpdate` and `noRepost` are rejected (`review-b-green-20261020-164707.log`).

`review-b-isolated-20261020T205945Z.log` records `treefmt`, `fleet-alert`, `otel-collector-config`, `ntfy-provisioning`, `nixos-magnetite` and `nixos-cinnabar` exit 0.
`review-b-units-unchanged-20261020-165850.log` compares every systemd unit text on both hosts before and after #3519's change: only home-manager and Omnigent units differ, each because it references a home-manager generation whose closure holds the flake source, and the `fleet-deadman.json` and `fleet-alert-config.json` store paths are unchanged; the orchestrator reports no deployed change, and #3519 was not deployed.

---

## Overall Decision

- [ ] (pass) PASS — may proceed to finishing-a-development-branch and archive
- [x] (warn) PASS WITH WARNINGS — may proceed to subsequent steps but note: the `LocalExporterDown` pair that tasks.md 9.1 asks to see on the phone was not observed there, because the phone was not subscribed until 2026-10-20; its last link is composed from pyrite's capture, a `fleet-alerts` subscriber that received the pair, and the 7.7 test post received on the phone over the same topic and server (§10.1); and §8a's designation-lint nouns remain for the retrospective's promote list
- [ ] (fail) FAIL — return to the failed artifact, correct it, then re-run verify

Every 7.1–7.6 expectation held, with the one timing failure of 7.6 fixed and re-observed under 10.1, and 9.1's R9.1 comparison passed over both windows (§10.2).
7.7 passed by a test post after the first Monday message, which ntfy accepted, reached no phone (§9.8).
§4 records no drift; §8 records the non-blocking designation findings of 8a and 8c.
Nothing is open before the archive except tasks.md 8.4 and 8.5, which are the archive itself.

**Next step**:

The documenter sub-gate (plan.md Task 8 Step 12, human) over `verify.md`, `review.md`, `retrospective.md`, the runbook, `modules/README.md`, the collector README and the amended decision records; then the archive pull request (tasks.md 8.4, 8.5).
