# S2 holistic review

A read-only review of slice S2 as merged (#3556 to #3563) and deployed on magnetite (D1 to D5 and D3B), read against this change's design, specs, tasks and plan and against read-only queries on magnetite, made on 2026-10-22 by a subagent with three read-only scouts, in place of the paid codex review, at the operator's direction, as in S1 and S3 (tasks.md 8.2).
It found nothing critical and ten findings, one significant and nine minor.
F1, the significant one, went to the operator, who decided on 2026-10-24 (decision O3) to keep the per-input flake-updater pull requests and the burn rule as they are, recorded as tasks.md 10.10 in #3591.
F2 to F10 were applied in #3564, as tasks.md 10.1 to 10.9 record with their verification; 10.2 and 10.6, the two that change what runs on magnetite, were verified on magnetite after the REVC deploy on 2026-10-22, and charter v22 records the amendments to ADR-005.
Unlike S3, S2 also ran the holistic review over its plan before the first implementation commit (tasks.md 1.1); all 22 of that review's findings, one high, nine medium and twelve low, were accepted and applied to the planning artifacts in #3556 and #3557.

| Finding | Category | Severity | Disposition |
|---|---|---|---|
| F1 the burn rule fired on every flake-updater batch, about twice a week, each firing open about 22 h | operational, alert noise | significant | operator decision O3 (2026-10-24): kept as is, because `mic92/update-flake-inputs` cannot group inputs and one combined pull request would let any failing input hold back every other update; the runbook names an updater run as the expected cause of a firing; #3591, tasks.md 10.10 |
| F2 "`devloop-pg-grants` grants once per boot or activation" was false for activation, including a spec SHALL | doc/spec accuracy | minor | #3564, tasks.md 10.1: the requirement, design D10, the plan, the runbook and the module comment say "once per boot, and at an activation only when the unit changes"; the unit is unchanged |
| F3 C1 and C2 failed falsely when a restarted build dropped attributes that nixbot had finished | correctness, false alarm | minor | #3564, tasks.md 10.2: `currentFinish` explains the dropped key from the build's current `finished_at`, with a `devloop-ingest` leg; verified on magnetite after the REVC deploy |
| F4 `devloop-queries`' result-header clauses compared the allow-list with itself | overzealous | minor | #3564, tasks.md 10.3: clauses deleted; the error-cell clause still rejects `selectError` and `errorUnderAlias` |
| F5 the marker clause's two negative controls only re-tested `hasInfix`, and a line-number assert broke on a harmless patch rebase | overzealous | minor | #3564, tasks.md 10.4, charter v22 |
| F6 the property-level `allDatabasesFreeze` rehearsal never reached the property it named | check gap, overzealous | minor | #3564, tasks.md 10.5: the property-level rehearsal deleted; the fixture-level mutant stays |
| F7 the kill-order slot for `devloop-reconcile` (11.5 MB peak) protected nothing | overzealous | minor | #3564, tasks.md 10.6: `OOMScoreAdjust`, the kill-order entry and the `reconcileOomZero` override dropped; verified on magnetite after the REVC deploy |
| F8 two `devloop-ingest` mutant legs judged only the clause name, plus some dead weight | check gap, overzealous | minor | #3564, tasks.md 10.7 |
| F9 runbook and ADR text drifted from the deployed behaviour in seven places | doc accuracy | minor | #3564, tasks.md 10.8, charter v22: all seven corrected |
| F10 tasks.md left done items unchecked | bookkeeping | minor | #3564, tasks.md 10.9: 1.6, 1.7, 2.8 and 4.8 ticked; 6.4 and 6.5 stayed open until the skill line was seen delivered, and #3591 ticked them |

The dispositions create no handoff to a later slice.
Three suggestions in the report were not taken: F6's optional removal of the fixture server's wrong-database and SQL-shape controls, the runbook note that a `sqlquery` replay should run only while the store is up, and the REINDEX of nixbot's pre-existing collation mismatch, which the report places outside S2.

## Report

The review's report, verbatim:

A read-only review of slice S2 as merged (`beea76ff4`; #3556–#3563) and deployed on magnetite (D1–D5, D3B), made on 2026-10-22 against the change's design, specs, tasks and plan, the evidence under `logs/s2-evidence/`, and read-only queries on magnetite (unit state, collector metrics, `DESC TABLE`, row counts, PostgreSQL privileges, the PR-build history in `devloop.ci_build`).
Nothing was edited, built or deployed.
Three read-only scouts covered `devloop-ingest`, the evaluation-time checks, and the docs.
I checked their findings that this report relies on against the code.

I found nothing critical.
There is one significant finding and nine minor ones.
The significant one is alert noise: every firing of `PullRequestQueueWaitBurn` in the last 15 days came from the flake-updater bot's own batch of pull requests.

| Finding | Category | Severity | Belongs in |
|---|---|---|---|
| F1 the burn rule fires on every flake-updater batch, about twice a week, and each firing stays open about 22 h | operational, alert noise | significant | operator decision, then S2 §10 |
| F2 "`devloop-pg-grants` grants once per boot or activation" is false for activation, including a spec SHALL | doc/spec accuracy | minor | S2 §10 |
| F3 C1/C2 fail falsely when a restarted build drops attributes that nixbot had finished | correctness, false alarm | minor | S2 §10 (or keep the runbook note) |
| F4 `devloop-queries`' result-header clause compares the allow-list with itself | overzealous (S3 F6 style) | minor | S2 §10 |
| F5 the marker clause's two negative controls only re-test `hasInfix`, and a line-number assert breaks on a harmless patch rebase | overzealous | minor | S2 §10 |
| F6 the property-level `allDatabasesFreeze` rehearsal never reaches the property it names | check gap / overzealous | minor | S2 §10 |
| F7 the kill-order slot for `devloop-reconcile` (11.5 MB peak) protects nothing | overzealous | minor | operator decision on S3 D12's scope |
| F8 `devloop-ingest`: two mutant legs judge only the clause name; some dead weight | check gap / overzealous | minor | S2 §10 |
| F9 runbook and ADR text drift from the deployed behaviour (seven small items) | doc accuracy | minor | S2 §10 |
| F10 tasks.md leaves done items unchecked (1.6, 1.7, 2.8, 4.8) | bookkeeping | minor | before verify.md (8.1) |

### Findings

**F1 (significant): `PullRequestQueueWaitBurn` fires on each flake-updater batch of pull requests, which is a scheduled event the bot causes itself.**
- **Evidence:**
  - I replayed the deployed expression minute by minute over the 15 days to 2026-10-22 04:00 UTC, using first-attempt PR rows read from `devloop.ci_build` and the evaluator's semantics (`for` 1 h, resolved after 5 min absent).
  - Five firings: 10-07 05:00, 10-10 04:54, 10-14 03:12, 10-17 02:34 and 10-21 03:06 UTC.
    Each resolved 22–24 h later, at 10-08 02:46, 10-11 03:56, 10-15 04:53, 10-18 01:23 and 10-22 02:36.
    That is 10 posts in 15 days, with the warning open about a third of the time.
    The figure matches the 5 of 15 days in `7.6-burn-history-20261022T034631Z.log`.
  - All 42 slow PR builds in the last 16 days (waits of 60–110 min) fall in five bursts of 4–13 PRs, each opened within about 3 minutes: #3327–#3340, #3368–#3370, #3413–#3423, #3481–#3486 and #3538–#3546.
  - `gh pr view` shows that these are `app/vanixiets-flake-updater` "Update flake input: …" PRs.
    The one exception, #3546, is the operator's own PR, caught in the 10-21 burst.
  - The bursts run on Wednesday and Saturday, around 00:15–01:40 UTC.
  - The rule cannot tell these builds apart: `ci_build.branch` holds the base branch, `main`, for PR builds, and S2 stores no author or head ref.
- **Consequence:** the only thing the warning has reported is the bot's own batch draining through a serial queue, which is expected.
  A real regression in queue wait would arrive as a sixth instance of a warning that is already routine.
  Design D1's rationale ("each of which breached D5-R4's bound") is true, but it does not lead to any action.
- **Change (operator to choose one):**
  1. Remove the cause: make the flake-updater open its input PRs one at a time, or as one combined PR.
     No S2 code changes.
  2. Raise the wait threshold to 2 h.
     The largest wait in the 16 days was 110 min, so the rule would have stayed silent.
     The fixtures move with it: `devloop-ingest` burnRule and the `thresholdHalfHour` mutant.
  3. Accept the noise and say so: document the twice-weekly firing in the runbook and in D1.
  - Excluding bot PRs inside the rule would need a new `ci_build` column (head ref or author), so I do not recommend it for S2.

**F2 (minor): the claim that `devloop-pg-grants` grants once per boot *or activation* is false for activation.**
- **Evidence:**
  - The unit is `Type = oneshot` with `RemainAfterExit = true` (`modules/nixos/devloop-collection.nix:841-842`).
    Its text depends on nothing from nixbot, so `switch-to-configuration` leaves it alone on every deploy that does not change the unit, including the nixbot-bump deploys that bring migrations.
  - Live, it last started at 2026-10-22 01:08:37 (D3).
    D3B, D4 and D5 did not restart it (`magnetite-D3B/D4/D5-*.log`).
  - The wording appears at `fleet-observability.md:19` and `:516`, `devloop-collection.nix:827`, `design.md:289`, `:300` and `:419` (the pipeline-version line, which has the same error), `plan.md:44` and `tasks.md:35`.
    It is also a SHALL in `specs/devloop-collection-interface/spec.md:75`.
- **Consequence:** small.
  The runbook's recovery (`:517`, `systemctl restart devloop-pg-grants`) is correct, and C1/C2 detect the lost grant the next morning.
  But the spec states behaviour the system does not have.
- **Change:** use the wording "once per boot, and at an activation only when the unit changes".
  At `fleet-observability.md:516` say "until the unit next runs (boot, or `systemctl restart devloop-pg-grants`)".
  A `restartTriggers` on nixbot's package would not help, because the grant would race the migrator (plan review F6).

**F3 (minor): C1 and C2 raise a false `FAILED` when nixbot deletes finished rows of a restarted build.**
- **Evidence:**
  - `currentFinish` fails a stored key whenever nixbot no longer has it (`WHERE NOT c.present OR …`, `devloop-collection.nix:476`).
  - The runbook acknowledges that a restarted build drops attributes for systems it no longer builds (`fleet-observability.md:518`, citing `rerun_exec.py:83-92`), and tells the operator to diagnose this by hand.
- **Consequence:** each such restart posts a `FAILED devloop-reconcile` that someone has to investigate.
  Restarts are rare (1 rerun in 615 PR builds, design D1), so the noise is low, but the rule is meant to report only real gaps.
- **Change:** in `currentFinish`, for an attribute key that nixbot no longer has, also join `builds` (the reconcile role already holds `builds.id` and `finished_at`), and count the key as explained when the build's current `finished_at` is null or later than the stored one.
  Add one `devloop-ingest` reconcile leg that deletes a finished attribute of a restarted fixture build.
  Alternatively, keep the runbook note and accept the rare false notice.

**F4 (minor, S3 F6 style): `devloop-queries`' "returns body and the allow-listed columns in order" clauses compare the allow-list with itself.**
- **Evidence:**
  - The query aliases are rendered from `tables.<t>.columns` (`devloop-collection.nix:204-210`), and the expected header is rendered from the same list (`modules/checks/devloop-queries.nix:229-230`).
    PostgreSQL only echoes the aliases back, so the clause at `:234-241` fails only when the template is hand-edited.
  - Error text in a cell is already caught by the error-cell clause (`:252-259`) and its mutants.
- **Change:** delete `:234-241` and the "columns" bullet in the header comment (`:21-22`), and amend D14's "result column names and order".
  `selectError` stays covered by the error-cell clause.

**F5 (minor): the marker clause's negative controls test the language, and its line-number assert can fail when nothing is wrong.**
- **Evidence:**
  - `markerLastCharacter` (`devloop-queries.nix:414-418`, `:432-433`) and `testLiteralsOnly` (`:419-422`, `:436-437`) hold by construction, since they only show that `lib.hasInfix` notices a changed string.
  - The `assert` at `:424-425` throws whenever the patch's test literals move off lines 379 and 451, which a rebase of the local nixbot patch can do with no fault present.
  - The real clause (`:427-430`, production context against `abandonMarker`) does not need them.
- **Change:** delete `:414-425` and `:431-438` and their mention in the header, and amend D15's "two embedded negative controls".

**F6 (minor): the property-level `allDatabasesFreeze` rehearsal does not exercise `test_failure_freezes_only_its_database`.**
- **Evidence:**
  - `modules/checks/fleet-alert.nix:1296-1303` runs the whole `test_transition.py`.
    The model-equivalence test runs first and falsifies the mutant, and `grep -q 'Falsifying'` accepts that from any test.
  - So the per-database property has been seen failing only once, at plan time (`5.4-f7-red-*.log`).
  - The fixture-level `allDatabasesFreeze` (`:1114-1118`), rejected by `devloopFailureLeg`, already guards the same fault.
  - Related and optional: the fixture server's wrong-database SQL control (`:1180`) repeats `everyQueryToFleet`, and the SQL-shape control (`:1184-1186`) tests the test double against a literal taken from the same reading of GreptimeDB.
- **Change:** delete `:1296-1303`, or run only the per-database property against the mutant.
  Optionally, drop `:1180` and `:1184-1186`.

**F7 (minor, overzealous): `devloop-reconcile`'s place in magnetite's kill order protects nothing.**
- **Evidence:**
  - The unit peaked at 11.5 MB for about 1 s of CPU (`systemctl show`; journal "11.5M memory peak"), under `MemoryMax=128M`.
  - The kill-order assertion and its `reconcileOomZero` mutant (`magnetite/default.nix:723`, `:750-751`) constrain its `OOMScoreAdjust` between the evaluator and the store.
    Killing it first or last under host OOM frees about 11 MB either way.
- **Change:** drop `OOMScoreAdjust`, the `order` entry and the mutant, and scope S3 D12's rule to units whose memory matters.
  If the operator wants D12 applied uniformly, keep them and close this finding.

**F8 (minor): `devloop-ingest` has two mutant legs that judge only the clause name, plus some dead weight.**
- **Evidence:**
  - `omitCached` (`modules/vm-tests/devloop-ingest.nix:700-702`) and `omitNullPr` (`:723-725`) settle with a fixed 130 s sleep, and `rejected()` (`:563-566`) checks only the failing clause names.
    A mutated query that errored would still read as "C1/C2 FAIL".
  - The recorded runs fail for the right reason: the 3 cached keys at `5.6-devloop-ingest-20261022T031031Z.log:4552`, and the 2 null-`pr_number` builds at `:6215`.
  - `assert WAITS["n"] == 12` (`:762`) restates the reconcile's 120 s / 10 s loop (`devloop-collection.nix:741-744`).
  - The `switch-to-configuration` branches (`:369-381`, `:394-395`) can never run, because the container has no such binary.
  - `"body" not in desc` (`:228`) is implied by `:227`, and `:315-316` repeats the first-start DESC check.
  - The unused `abandonMarker` and `batchEventKeys` are in config.json (`:1133`), and `:804` repeats a stop that `reset_devloop()` already did.
- **Change:** in those two legs, assert that the FAIL detail names the expected missing-key count.
  Use `WAITS["n"] >= 1`.
  Delete the dead branches and the duplicates.

**F9 (minor): the docs drift from deployed behaviour in seven small places.**
- `fleet-observability.md:564` says refused journal lines are lost "at once", but `journald/gitea-mq` retries with no time limit (`devloop-collection.nix:956-959`).
- `fleet-observability.md:562`, `otel-collector/README.md:85` and `design.md:414` list C1, C3 and C6 as detecting a 400 loss, and leave out C2.
- `fleet-observability.md:526` (and `:499`) use `journalctl -n 20`.
  A run prints four PostgreSQL collation-mismatch WARNING/DETAIL/HINT triplets (seen live, from a pre-existing glibc 2.42→2.44 mismatch on `nixbot`), plus up to 12 C7 wait lines, so 20 lines can cut off C1/C2.
  Use `-o cat -n 200 | grep '^devloop-reconcile: C'`.
- `fleet-observability.md:494` says exit 2 means a source cannot be read, but a malformed `DEVLOOP_RECONCILE_DAY` or `_DATABASE` also exits 2 (`devloop-collection.nix:600-606`).
- `fleet-observability.md:570` cites `verify.md`, which does not exist yet.
  Put the numbers inline (sent 204,203, stored 204,163 on 2026-10-22, `7.4-budget-*.log`) or fix the citation in 8.1.
- `ADR-005…md:148` and `:151` and `devloop-exporters.md:44`, `:102` and `:105` still describe E5.1 as a "24-hour window ending one hour ago" and E5.4 as `journalctl --grep` counts.
  The code reconciles the previous UTC day at 02:15 and counts JSON entries with jq.
- The "run `devloop-ingest` before merge" triggers (`nix-flake-pr-cycle/SKILL.md:83`, `modules/README.md:85`) leave out the burn rule's SQL in `rules.nix`, which only `devloop-ingest`'s burnRule case runs on a real store (`rules.nix:34-37`).

**F10 (minor): tasks.md bookkeeping.**
- 1.6, 1.7, 2.8 and 4.8 are unchecked, but their pull requests merged and D1 and D4 are deployed (`window.env`, `magnetite-D1/D4-*.log`).
- 6.4 and 6.5 are unchecked too.
  The skill line is merged, but 6.4's verification is the delivered file after activation, so it may legitimately still be open.
- **Change:** tick them with their evidence before 8.1 writes `verify.md`.

### Measured and checked, not counted as findings

- **Live correctness on magnetite (04:08 UTC):**
  - Collector exporters: queue size 0 for all four tables.
    Receivers report 0 refused and 0 failed records, and no `send_failed` series exists.
  - `ci_attribute` holds 203,061 rows, equal to its distinct `(build_id, attr, finished_at)` keys and to nixbot's joined finished attributes (203,061).
  - `batch_event` holds 788 rows, all distinct.
    `deploy_record` has 6 rows for 6 file lines.
  - `DESC TABLE` of the four tables equals the allow-list, with no `body` or extra column.
  - The reconcile passed all of C1–C7 on hand starts.
    The forced `devloop_absent` failure exited 2 and posted FAILED, then RESOLVED (7.5).
- **Grants and credentials:**
  - The live column privileges equal D10's table exactly.
    The reconcile role cannot read `error`.
  - Both roles are LOGIN without a password, not superuser and without CREATEDB.
  - Both roles can CONNECT to every database on the cluster (the PUBLIC default), but no table in nixbot, gitea, gitea-mq, matrix-synapse, buildbot, niks3, omnigent or cognee is granted to PUBLIC (0 each), so they can read nothing there.
  - The regulator password reaches the reconcile only through `LoadCredential`.
- **Allow-list enforcement:** each pipeline's VRL resets the event and assigns only allow-listed fields.
  The journal receiver drops the body and keeps only the keep-list.
  `error` is referenced in a predicate, never selected, and the error-cell clause plus `errorUnderAlias` show this can fail.
- **Load:**
  - The collector used 110 s of CPU in 2 h 11 min (about 1.4 % of one core, fleet metrics included), with a 144 MB memory peak.
  - Export queries take 9 ms (`ci_attribute`, index scan) and 3 ms (`ci_build`) per minute (`7.4-explain-*.log`).
    The evaluator's SQL query adds about 30 ms per run.
  - The reconcile takes about 1 s of CPU and 11.5 MB a day.
- **Evaluation cost against 0.5 GiB:**
  - `devloop-queries` is 143,284,368 B (26.7 %) and `fleet-alert` is 333,046,656 B (62.0 %).
  - `otel-collector-config` is 491,445,792 B (91.5 %), of which S2 added 8.3 MB.
    About 45 MB of headroom remains, so S4's per-host relations belong in host assertions, as S3 F3 concluded.
- **Cursor and replay:**
  - The widest `finished_at` tie is 106 rows, against the 10,000-row page.
  - The journald cursor reset touched only `receiver_journald_gitea-mq`, and the exporter queue files are separate (`7.4-cursor-reset-*.log`).
  - The query-text-keyed cursor and the 400-drops-a-page hazard are documented, and C1–C6 detect the loss.
  - A `sqlquery` replay should run only while the store is up, because 200k rows pass through a 32 MiB queue.
    Worth adding to the runbook line at `:549`.
- **Reboot:** not yet observed (7.2 is opportunistic, and uptime is 6 days).
  By reading the code, the boot path is sound:
  - The boot activation writes a line without `previous_closure`.
  - `sqlquery` errors until PostgreSQL and the grants are up, without advancing its cursor.
  - The journald wrapper's `--boot=all --after-cursor` resumes across the boot.
  - The timer's catch-up waits up to 120 s for the boot line (C7).
  - The first scheduled reconcile is due on 2026-10-23 at 02:15 UTC (7.5 is still open).
- **Not counted:**
  - On darwin, `postActivation` runs under `set -e`, so a failed deploy-record write (disk full) aborts the switch.
    That is acceptable, and it is not a new risk class.
  - The host name is not JSON-escaped, but no host name contains a quote.
  - The collation mismatch on `nixbot` predates S2.
    Fix it with REINDEX, then `ALTER DATABASE nixbot REFRESH COLLATION VERSION`, outside S2.

### What is sound

- **The data path:** one allow-list renders the DDL, pipelines, keep-lists and query aliases.
  The tables are pre-created and non-append, with `auto_create_table=false`, so duplicates and racing writes are structurally impossible, and the live counts confirm it.
- **The reconcile:**
  - It compares multisets, explains restarts by nixbot's current `finished_at`, and uses count-then-read for `greptimedbSql`'s empty-answer rule.
  - It guards journal visibility with PID 1, and separates exit 2 from exit 1.
  - Each of C1–C7 was seen failing on its named mutant in `devloop-ingest`, with the exact set of failing clauses required.
- **The evaluator's per-database freeze:**
  - `storeErrors` and `ask_store` stop querying only the failed database.
  - `StoreQueryFailing` is labelled by database, and `state.hosts` is updated only when the reporting database answered.
  - The two-database leg (`everyQueryToFleet`) and `devloopFailureLeg` (`allDatabasesFreeze`) each fail on their named fault.
    The burn timeline leg uses spec literals (61st run, run 70), not `rules.nix`, which avoids S3 F7's pattern.
- **`devloop-ingest`:** every D16 case and every row of D11's clause table is present, with hand-computed expectations for the burn rule and the three D8 questions.
  The `--boot=all` argument check failed when the wrapper was removed (`3.12-devloop-ingest-red-20261022T014502Z.log`).
- **The deploy-record obligation:** it compares the rendered script with the activation text the platform assembles, and fails on removal, an empty override and a replaced script (`1.5-obligation-control-*.log`).

### Verdict

S2 is correct and does what its specs require on magnetite.
Its regulators fail on the faults they name; the exceptions are the self-comparing clauses in F4–F6.
It stays within budget and puts negligible load on the host.
Before close-out, decide F1, since the burn rule will warn on the next flake-updater batch.
Apply the wording fixes F2 and F9 (one is a false spec SHALL), and the deletions F4–F6 and F8.
F3 and F7 are small operator choices.
F10 is bookkeeping before `verify.md`.

#### Questions for the operator
1. F1: should we serialize the flake-updater, raise the threshold to 2 h, or accept and document the twice-weekly warning?
2. F3: should we fix C1 for restart deletions in code, or keep the runbook's manual diagnosis?
3. F7: does S3 D12's kill-order rule apply to every memory-bounded unit, or only to units whose memory matters?
