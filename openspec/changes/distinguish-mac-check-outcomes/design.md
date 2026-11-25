## Context

nixbot on magnetite builds `checks.x86_64-linux` and `checks.aarch64-darwin` for every pull request, merge-queue batch and push to `main`.
Three contexts are required by the ruleset and by gitea-mq: `nixbot/nix-eval`, `nixbot/nix-build` and `nixbot/effects`.
Mac attributes can only be built on a Mac magnetite reaches over `grpc://`; magnetite dispatches to stibnite alone (rosegold and argentum are excluded in `modules/clan/inventory/services/nix-builders.nix`), and stibnite is the operator's workstation, usually awake but not always.

Today every Mac attribute carries hercules-ci's `ignoreFailure = true` (`modules/checks/nixbot-best-effort-darwin.nix`).
nixbot records any failure of such an attribute as `ignored_failure`, excludes it from the aggregate and from the failed-build cache, and counts it as built in the `nixbot/nix-build` summary (`status.py` `_count_key`, `_post_summary`).
Two local patches extend that: a Mac attribute settled by a failed dependency is ignored too (`nixbot-ignore-failure-dependents.patch`), and once every other attribute has settled, a Mac attribute unfinished 300 s later (`optional_build_grace`) is stopped and recorded as `ignored_failure` with the error `not finished when the required attributes had settled` (`nixbot-abandon-optional-attributes.patch`).

The records show both sides of the cost.
Build 2456 (2026-11-16) recorded at least twelve Mac attributes as ignored failures after stibnite built `vanixiets-docs-deps` and its builder exited 1; nothing blocked.
Builds 3001-3008 (2026-11-24, the twice-weekly update burst of 24 pull requests) stopped `darwin-*` and `home-manager-*` checks 234-406 s after they started, most of them mid-build on stibnite, and seven green pull requests carry those stops.
Build 3017, which ran 46 minutes, let three of the same medium checks finish, in 1,000-1,106 s against 30-day medians of 125-130 s.

### The principle

A check's result is evidence about a change only if a builder ran the check's work and answered; that answer is a *verdict*.
The absence of an answer is evidence about the infrastructure, so it never blocks a merge, is never cached, and is carried as an *unproven* outcome until a later build that contains the same derivation answers it.
The build waits for an answer only while one is being produced.

The three outcomes of the brief fall out of this: a Mac that built the check and saw it fail gave a verdict (blocks); a Mac still working is waited for (it is producing one); no Mac gave none (unproven, named, non-blocking).

### What the outcomes are, and what tells them apart

Verified in source: nixbot `b0472661` (the flake's pin), Nix master `e7386085` (magnetite's client is Nix 2.35.6; wording below must be pinned against it, see D4), nix-grpc-store at local HEAD `a40124f4`, of which the pin `f2f5acd8` is an ancestor (the pin's own blobs were not readable locally).

| Outcome | What happened | Evidence in the attribute's log (`nix build --log-format internal-json`) | Kind |
|---|---|---|---|
| passed | a builder built every derivation | exit 0 | verdict |
| failed on the Mac | the Mac's builder exited non-zero, timed out, or mismatched a hash | the hook's `build of '<drv>' on '<builder>' failed: … Reason: builder failed …` (`build-remote.cc:380-389`; seen in build 2456) | verdict |
| failed through a dependency | an attribute this one depends on failed with a verdict | nixbot's scheduler settles it (`build_scheduler.py` `fail_dependents`, `_ingest`) | verdict |
| no builder reachable | the connection to every Mac failed within `connect-timeout=5` | `cannot build on '<builder>'`, then Nix's refusal to build the platform locally (`build-remote.cc:213-268`; the repository's note in `modules/clan/services/nix-builders/flake-module.nix`) | unproven |
| builder lost | the Mac went away after accepting work | a transport error (gRPC keepalive of 20 s and 20 s, `src/keepalive.hh`; `unexpected end-of-file` and similar, `executor.py` `TRANSIENT_ERROR_MARKERS`) with no verdict line | unproven |
| waiting for a slot | every Mac slot is busy | no build activity at all; Nix's "waiting for a machine" activity, which nixbot does not render (`derivation-building-goal.cc:553-562`, `executor.py` `_render_event`) | unproven when stopped |
| still building | a Mac accepted the work and is producing output | build activities naming the builder (`derivation-building-goal.cc:701-711`) and log lines | waited for |
| dependency unproven | an attribute this one depends on ended unproven | the scheduler | unproven |
| unrecognised | a Mac attribute failed and its log holds neither a verdict line nor any infrastructure marker | the failure's last error line, which matches nothing the classifier knows | blocks until classified (D11) |
| cancelled | the build was superseded or closed | unchanged | cancelled |

Exit status does not separate the failed-on-the-Mac and builder-lost rows: Nix records every failed hook build as `MiscFailure`, so `nix build` exits 1 for both (`derivation-building-goal.cc:801-808`, upstream TODO #12641; `build-result.cc` `failingExitStatus`).
The log does.
Nothing in the log separates a failure the change caused from one the Mac's own environment caused while its builder ran (build 2456's `EACCES` in bun's cache directory may be the latter; not established); both are verdicts here.

### What each outcome does

| Outcome | Attribute status | Build aggregate | `nixbot/nix-eval` | `nixbot/nix-build` | `nixbot/effects` | Failed-build cache | Retry |
|---|---|---|---|---|---|---|---|
| failed verdict (own or through a dependency) | `failed` / `dependency_failed` | failed | unchanged | failure, plus the per-attribute failure context | unchanged | cached if the cache is enabled (it is off here: `cacheFailedBuilds` is unset, default false) | nixbot's existing one retry on transient markers only |
| unproven | `unproven`, with the reason as its error | unaffected | unchanged | success; the summary counts and names unproven attributes | unchanged | never | none within the build; the next build containing the derivation builds it again |
| unrecognised | `unrecognised`, with the failure's last error line as its error | failed | unchanged | failure; the summary names each unrecognised attribute with that line | unchanged | never, since it may be infrastructure | none within the build; an attribute rerun or the next build tries again |
| passed | `succeeded` | unaffected | unchanged | success | unchanged | — | — |

A Mac attribute's evaluation error is unchanged: it is recorded `failed_eval` and fails the build, because no builder could have caused it.

## Goals / Non-Goals

**Goals:**

- A Mac check that a Mac built and saw fail blocks the merge, as any Linux check does.
- A Mac check that ends without a verdict never blocks a merge, and is recorded and shown as unproven with its reason.
- A Mac that is working on a check is waited for, within a per-check stall limit and a build-wide deadline that keeps the merge queue inside its own timeout.
- An unproven check is visible on the pull request, on the `main` commit that carries it, and in the readiness report at enqueue time.
- A Mac failure the classifier does not recognise blocks, is recorded and shown as unrecognised with its log line, and can be classified within hours (D11).
- No added evaluation.

**Non-Goals:**

- Making Mac checks unconditionally required.
- Rerunning `main`'s unproven checks when a Mac wakes, or alerting on a sleeping Mac.
- Reclassifying infrastructure failures of Linux attributes; an attribute without `allowUnproven` is recorded exactly as today.
- Telling a change's failure from a Mac-environment failure inside a builder's answer.
- The loss of attributes that fail evaluation without an attribute row (pyrite, recorded only as an `eval_warnings` count); decided (Q8) to be its own change.
- Admitting rosegold or argentum as builders, or building Mac system closures anywhere but on a Mac.

## Decisions

### D1: a verdict, not a platform, decides whether a result blocks

- **Choice**: an attribute's result blocks a merge when it is a verdict; an attribute that may lack one (every Mac attribute) ends `unproven` when it has none, and `unproven` is terminal, not a failure, never cached, and built again by the next build that contains the derivation.
- **Rationale**: it is the one rule that gives A1 and A3 together and makes "builder absent" and "check broken" different facts instead of one status with two meanings.
- **Alternatives considered**: (a) make Mac checks fully required: simplest, honest, and the right design for an always-on Mac, but it blocks every merge whenever stibnite sleeps or travels, which the operator ruled out; (b) leave as is: build 2456 shows a real Mac regression passing; the burst shows working builds discarded; (c) a separate non-required Mac context per build: visible, but it carries no blocking for real failures, so it is A3 without A1; (d) keep `ignoreFailure` and add a second marker only for absence: two flags whose combination must be read together, where one modifier states the whole policy.
- **Boundary**: first-party policy expressed in a vendored service; the rule lives in a local patch to nixbot (vendored) and the marking in this repository (first-party).

### D2: fail closed: a failure is unproven only on positive evidence that no builder answered

- **Choice**: for an attribute that allows unproven, a failed run is `unproven` when its log carries one of: the scheduler's stop (D3); nixbot's built-in transport markers (`TRANSIENT_ERROR_MARKERS`) after its one retry; or one of the repository's `unproven_markers` (`nixbot.toml`, read from the built worktree), which hold the deployed Nix's and nix-grpc-store's wording for an unreachable or lost builder (`cannot build on '`, the local refusal of the platform, the `gRPC … failed` form; D4).
  A verdict line anywhere in the attribute's log (a `build of '…' on '…' failed:` answer whose reason is the builder's own failure, timeout or hash mismatch; its pattern is in the patch) makes it a failed verdict whatever else the log holds, since a verdict among its derivations decides it, as nixbot already lets a genuine failure win over a cancellation (`_ingest`). No marker can therefore turn a verdict into unproven.
  Any other failure is `unrecognised`: it blocks exactly as a failed verdict does, but is recorded, shown and handled apart (D11).
- **Rationale**: an unrecognised infrastructure failure then blocks until it is classified, which is loud and, by D11, short; the opposite rule, unproven unless a verdict line is recognised, goes quiet the day Nix rewords its line, which is the defect this change removes (`check-vacuity.md`, "The permissive scanner"). Decided with the operator (Q1), on the condition D11 meets.
- **Alternatives considered**: classifying by exit status (cannot work, above); asking stibnite directly whether it built the derivation (a second channel, a credential and a race, for what the log already says); keeping every marker in the patch (each new one would need a patch change and a magnetite deploy, which is days, not hours; D11).

### D3: wait while a Mac makes progress; a stall limit from the size class and a deadline from the merge queue

- **Choice**: nothing is stopped while any attribute without `allowUnproven` is unsettled or evaluation is running, because waiting then costs nothing.
  From the moment only `allowUnproven` attributes remain, two rules apply.
  The stall rule stops an attribute that has made no progress for its own `allowUnproven` seconds, counted from its last progress or, if it has made none, from its start; progress is a build activity starting or stopping on a builder, a builder's log line, or a phase change.
  The deadline rule stops every remaining one `unproven_deadline` seconds (`nixbot.toml`, proposed 1,200) after that moment.
  Each is recorded `unproven` with its reason (`no progress for N s`, `not finished by the deadline`), and an attribute never started is recorded `unproven` (`not started by the deadline`).
- **Stall limit's source**: `allowUnproven` is the check's size-class limit from `testSizes` (small 60 s, medium 300 s, large 900 s; 900 s if a check has no entry, which `checks.<system>.test-size-classes` already fails on).
  A check that has not moved for as long as one whole run of its class may take is not being worked on: it is queued behind a full builder, or its builder is gone.
- **Deadline's source**: the merge queue gives up on a batch whose required checks have not reported within one hour (gitea-mq `checkTimeout`, default `1h`, not set in `modules/nixos/gitea-mq.nix`); 1,200 s leaves two thirds of that hour for evaluation, the required attributes and effects.
  Build 3017 ran 46 minutes in all, so the hour is not slack during a burst; see Q2.
- **Why not a size-class total bound**: build 3017's medium checks took 1,000-1,106 s under contention, eight times their median; a total bound of 300 s or 900 s would have stopped them as the burst's grace did. A size class bounds one uncontended run, not the builder's queue.
- **What happens to a Mac that accepts work and then sleeps**: the gRPC connection's keepalive (20 s ping, 20 s timeout) breaks it within about 40 s plus the client's retry budget, the hook fails with a transport error, and the attribute ends `unproven` (`builder lost`) without waiting for the stall limit. If the connection somehow survives silently, the stall rule ends it.
- **Boundary**: vendored (scheduler and executor in the patch) reading first-party data (`testSizes` through the modifier; `unproven_deadline` from the worktree's `nixbot.toml`, as `optional_build_grace` is read today).

### D4: the classification markers are pinned by live probes, not by reading Nix

- **Choice**: the `unproven_markers` of D2 and the verdict pattern are each covered by a case of `checks.x86_64-linux.nixbot-unproven-attributes` over a captured log, and the captured logs come from magnetite's deployed Nix: one from a deliberately failing Mac check, one with stibnite's builder service stopped before dispatch, one with it stopped mid-build. The check classifies with the repository's own `nixbot.toml`, so a marker removed or mistyped there fails it.
  Nix master already words the local refusal differently (`platform mismatch`, `missing system features`) from older versions (`required system or feature not available`), so wording read from source is not trusted.
- **Rationale**: the markers are the trust boundary; a Nix bump moves them without anyone rereading them (A231 carries the trigger), and the unrecognised outcome (D11) is how a moved marker shows up.

### D5: one modifier, `allowUnproven = <seconds>`, replaces `ignoreFailure` on Mac attributes

- **Choice**: `modules/checks/nixbot-unproven-darwin.nix` (renamed from `nixbot-best-effort-darwin.nix`) maps every `checks.aarch64-darwin` attribute to `check // { allowUnproven = testSizeLimits.${class}; }`, reading `config.allSystems.aarch64-darwin.testSizes.checks.<name>.class`, which is literal data.
  The patch extends nixbot's `nix/apply.nix` to deliver `allowUnproven = drv.allowUnproven or null` in `extraValue`, and `NixEvalJobSuccess` gains `allow_unproven`.
- **Rationale**: one attribute states both the policy and the stall limit; adding it changes neither `drvPath` nor outputs, as `ignoreFailure` does not today, so nothing rebuilds; `ignoreFailure` keeps its hercules-ci meaning for any repository that wants it.
- **Evaluation**: nixbot's apply function already reads `drv.ignoreFailure or false` per job; reading one more literal attribute per Mac job is the same order of work, and `testSizes` entries force no derivation (`modules/checks/test-sizes.nix`). Measured before merge (task 2.4).
- **Alternatives considered**: a stall limit in `nixbot.toml` per attribute name (a second list to keep in step with `testSizes`); one stall limit for every check (simpler, but a 60 s small check and a 900 s large check would share it, so either small checks wait too long or large checks are cut).

### D6: one local patch replaces both scheduler patches

- **Choice**: `modules/nixos/nixbot-unproven-attributes.patch` replaces `nixbot-ignore-failure-dependents.patch` and `nixbot-abandon-optional-attributes.patch` in `flake.lib.nixbotPatches`, at the same position. It must:
  1. `nix/apply.nix`, `models.py`: deliver and expose `allowUnproven`.
  2. `build_scheduler.py`: add `BuildOutcome.unproven`, `BuildOutcome.unrecognised`, `AttributeStatus.unproven` and `AttributeStatus.unrecognised`; `outcome_status` returns `unproven` with its reason for an `allowUnproven` job and `failed` otherwise, and `unrecognised` with the failure's last error line; `_finish_job` adds neither to the failed-build cache; dependency propagation tracks `unproven_drvs` beside `cancelled_drvs`, so a dependent of an unproven attribute is `unproven` if it allows it and `dependency_failed` otherwise, a dependent of an unrecognised one is `dependency_failed`, and a verdict failure among the blocking dependencies wins; the stall and deadline rule of D3 replaces `AbandonOptional` and `_abandon_optional`, waking at the earliest pending expiry.
  3. `executor.py`, `build_run.py`: classify a failed run of an `allowUnproven` job per D2 with the built worktree's `unproven_markers`; keep a last-progress time per running attribute from the events the structured capture already parses, and expose it with the stop callback to the scheduler; write the reason line to the attribute's log.
  4. `db.py`: `unproven` is terminal and not a failure; `unrecognised` is terminal and a failure (`FAILED_ATTRIBUTE_STATUSES`; also `TERMINAL_FAILURES` and `status.py`'s `FAILED_STATUS_STATES`).
  5. `status.py`: `_count_key` gains `unproven` and `unrecognised` buckets; the `nixbot/nix-build` summary reads `N attributes built, M unproven: <short names>` (truncated with `and K more`) and, when any is unrecognised, leads with `unrecognised Mac ending: <short name>: <last error line>` for each (truncated likewise); both get their own icon and sort position in the build table; unproven posts no per-attribute failure context, unrecognised posts one whose headline starts `unrecognised Mac ending:`.
  6. `repo_config.py`: `unproven_deadline: int | None` replaces `optional_build_grace`; `unproven_markers: list[str]` is added, default empty.
  7. Tests: scheduler, executor-classification and orchestrator tests in nixbot's own suite, as the replaced patches carry today.
- **Rationale**: the dependency rule, the stopping rule and the new status are one behaviour; carried as one patch they cannot be applied half.
  `ignoreFailure` behaviour returns to upstream's: nothing in this repository sets it after D5, and sciexp/ironstar's local copy sets neither `ignoreFailure` nor a `nixbot.toml` (read 2026-11-24; [INFERENCE] that its remote agrees).
- **Cost of carrying it**: it touches `build_scheduler.py`, `executor.py`, `build_run.py` and `status.py`, which upstream changes often; the `nixbot` input is bumped in each update burst. The repository-side check (task 1.3) fails on a stale patch at evaluation of the bump's pull request, as the existing patches do.

### D7: visibility without a new context, a timer or an alert

- **Choice**: the `nixbot/nix-build` check run's summary names unproven and unrecognised attributes (D6 item 5); because a fast-forward landing reuses the batch's build for `main`, the same summary appears on the `main` commit.
  `gh-queue-open-prs` reads that summary for each pull request it reports (one `gh api` call to the commit's check runs, filtered to `nixbot/nix-build`) and appends `unproven: <names>` to the verdict line, and for a failing one `unrecognised Mac ending: <name>: <line>` (D11); it still authorizes when only unproven attributes are named, since unproven does not block.
  The repository-overview fragment's paragraph changes from "read ignored failures before enqueueing" to what unproven means and that a Mac failure now blocks.
- **Discharge after merge**: an unproven derivation is in neither magnetite's store nor the failed-build cache, so the next build containing it, of a pull request, batch or `main`, builds it again; a failing verdict then blocks that pull request or batch exactly as a broken Linux check on `main` does.
  A later build usually carries different Mac derivations (each update changes them), so what it proves is the newer state of `main`, not the unproven commit; that is the state that matters for the next merge.
- **Alternatives considered**: a timer on magnetite that reruns `main`'s unproven attributes when stibnite answers (proves the exact commit; a second moving part with an API token; rejected, Q5); an alert when `main` has been unproven for N days (fires for a laptop on holiday, which the brief rules out); a neutral `nixbot/unproven` check run (GitHub-only conclusion, a new status state in nixbot's reporter; rejected, Q6).

### D8: the dev-loop history counts unproven where it counted abandoned

- **Choice**: `ci_attribute.abandoned` becomes `status = 'unproven'` (all unproven reasons, not only the scheduler's stop); `own_fail` becomes `status IN ('failed', 'failed_eval', 'unrecognised')`, which now includes Mac verdicts and unrecognised endings; `flake.lib.devloopCollection.abandonMarker` and its binding clause in `devloop-queries` are removed, because the status names the outcome without shared text.
  The column keeps its name (decided, Q7); unrecognised endings are counted by `status = 'unrecognised'`.
- **Boundary**: first-party queries over the vendored schema; the status is TEXT (`migrations/0001_initial.sql`), so no migration is needed.

### D9: cost

- **Evaluation**: none added beyond reading one literal attribute per Mac job (D5), measured before merge.
- **stibnite absent**: Mac attributes fail at dispatch in about 5 s each (`connect-timeout=5`) and end unproven; builds finish as soon as the required attributes do, as today.
- **stibnite idle**: Mac checks run at their medians (125-130 s for the machine checks) and usually settle before the Linux attributes; [INFERENCE] no added wall time; measured in tasks 5.6 and 6.3.
- **stibnite busy (the operator working, or the burst)**: a build waits for Mac checks that are making progress up to 1,200 s after its required attributes settle, instead of 300 s: at most about 15 minutes more per build. Checks queued behind a full stibnite end after their stall limit (60/300/900 s) without progress. Batches pay the same, so landing a burst can take longer; it stays inside gitea-mq's hour unless the required attributes alone approach 40 minutes (Q2).
- **Mac work**: no new derivations are built. Work the burst used to throw away at 300 s is kept; [INFERENCE] total stibnite work falls, since stopped builds were rebuilt by later builds.

### D10: vacuity of each requirement

| Requirement (behavioral) | Plausible wrong implementation | What fails |
|---|---|---|
| A Mac verdict that fails blocks | every Mac failure classified unproven (fail open) | the broken-Mac-check probe stays green (task 5.3); the repository check's fail-open mutant is accepted (task 1.3) |
| No verdict never blocks | a stopped builder classified as a failure | the stopped-builder probe goes red (task 5.4); the check's stopped-builder fixture fails |
| Waited for while progressing | progress ignored (stop at the first deadline tick) | the scheduler test where a progressing attribute outlives its stall limit fails |
| Stopped when stalled | stall rule never fires | the scheduler test with a silent attribute and a long deadline times out |
| Deadline holds | deadline ignored | the scheduler test with a progressing attribute and a short deadline fails |
| Named where readiness is read | summary counts unproven as built | the status test reading the summary fails; `gh-queue-open-prs` fixture shows no `unproven:` |
| Built again next time | unproven added to the failed-build cache | the scheduler test with an enabled cache finds a cache entry |
| Dependents inherit the kind | dependent of an unproven attribute recorded `dependency_failed` | the dependency test fails, and the build fails |
| Unrecognised is recorded apart | an unrecognised ending recorded `failed` | the status case expecting `unrecognised` fails; the dev-loop fixture counting it fails |
| Unrecognised is shown with its line | summary or report drops the line or the word | the summary case and the `gh-queue-open-prs` fixture fail; its suffix-dropping mutant is rejected |
| Unrecognised is classifiable from the worktree | `unproven_markers` ignored, or read from the default branch instead of the built worktree | the case that classifies a fixture with and without the marker in the worktree's `nixbot.toml` fails |
| A marker cannot hide a verdict | markers checked before the verdict line | the case with a verdict line and a matching marker expects `failure` and fails |

### D11: an unrecognised Mac ending is found, shown and classified within hours

Decided by the operator as the condition of Q1 (2026-11-25): a block caused by a message the classifier does not know must last hours, not days.

- **Recorded apart**: the failure is `AttributeStatus.unrecognised`, a failure status in its own right, with the failure's last error line as its error. It blocks exactly as `failed` does, is never cached (it may be infrastructure), and is counted by status in nixbot's database and in the dev-loop history, so the question "how many unrecognised endings this week, and which lines" has an answer without parsing text.
- **Shown to whoever waits on the merge**: the per-attribute failure context's headline and the `nixbot/nix-build` summary start with `unrecognised Mac ending: <name>: <line>`, and `gh-queue-open-prs` prints the same on that pull request's line. A person or agent deciding whether to enqueue sees, at the moment they look, that the block is unrecognised and why. No alert is added: an unrecognised ending caused by a new wording for a sleeping Mac would otherwise page about a laptop.
- **Classified by a repository edit, not a deploy**: the infrastructure markers live in `nixbot.toml` (`unproven_markers`), which nixbot reads from the built worktree as it reads `unproven_deadline` (D2). Classifying a new ending:
  1. Read the attribute's log (`nixbot-logs log <attr> <build>`) and decide whether a builder answered.
  2. If no builder answered (infrastructure): add the distinguishing substring to `unproven_markers`, save the log as a fixture under `modules/checks/nixbot-unproven-attributes/fixtures/`, and add a case expecting `unproven`.
  3. Verify: `nix build .#checks.x86_64-linux.nixbot-unproven-attributes` fails with the fixture and without the marker, and passes with both; the verdict-precedence case still passes.
  4. Land it as an ordinary pull request. Its own build classifies with its own `nixbot.toml`, so the ending that blocked others does not block it; batches are built on `main`, so they classify with the marker as soon as it lands; an open pull request picks it up when its branch is updated.
  If a builder did answer, in wording the verdict pattern misses (a Nix rewording), the attribute blocks either way and only its label is wrong; the pattern is in the patch and is changed with a fixture case and a magnetite deploy, without urgency. If the failure is the change's own and carries no builder answer at all (for example, the hook failing to copy an input the change broke), it stays unrecognised and the change is fixed.
- **Why hours**: step 2 is a one-line edit and a fixture, step 3 one check build, step 4 one pass through the queue; no patch rebuild and no deploy. [INFERENCE] the elapsed time is set by when someone reads the report, then by the queue's build of the classifying pull request (tens of minutes in the records of 2026-11-24), not by the mechanism.
- **Landing unrelated work meanwhile**: there is no override, and none is added. Two ways exist that do not weaken the rule, because each yields a true record rather than a waived one:
  1. Rerun the blocked attribute through nixbot's per-attribute restart. If the ending was transient, the new attempt ends as a verdict or a recognised unproven outcome.
  2. Take the Mac out of service (stop stibnite's `nix-grpc-daemon`). Every Mac attribute then ends `unproven` with `no builder reachable`, which is what is true, so unrelated work lands with its Mac checks unproven and re-proved later; this also lets the classifying pull request land if the ending recurs on it. It costs every Mac verdict until the Mac is back.
  A pull request whose Mac derivations differ from the blocked one is not blocked at all unless the same ending recurs on it.
- **What the worktree marker cannot do**: a pull request can add a marker, but a verdict line takes precedence over every marker, so a marker can only reclassify endings in which no builder answered; review of `nixbot.toml` is the guard, as it is for any edit to the repository's checks.
- **A malformed `nixbot.toml`**: nixbot falls back to defaults for the whole file (`BranchConfig.loads`), so every marker disappears and infrastructure endings turn unrecognised: loud, not silent. The `BranchConfig` case of the repository check fails before such a file merges.

## Risks / Trade-offs

- [Risk] A Mac-environment failure (disk full, a cache directory's permissions) blocks a pull request as a verdict → Mitigation: the reason is in the log; a rebuild clears it once the Mac is repaired; recorded as the trust boundary, not hidden.
- [Risk] A Nix or nix-grpc-store update rewords a marker → Mitigation: D2 fails closed, so a reworded infrastructure message is recorded `unrecognised` and shown with its line; D11 classifies it by a repository edit; the probes of task 5 are rerun after a Nix bump on magnetite (A231's trigger).
- [Risk] While an unrecognised ending recurs, every pull request carrying the same Mac derivations is blocked → Mitigation: D11's rerun and taking the Mac out of service; no override.
- [Risk] A single long derivation that prints nothing for longer than its check's class limit is stopped as stalled → Mitigation: it ends unproven, not failed; the next build retries; a check whose run is that silent is reported by `CheckOutgrewItsClass`.
- [Risk] A batch's Mac derivations differ from every member's, so landing rebuilds them and waits again → accepted; that wait is the evidence for the exact tree that lands.
- [Risk] The patch touches hot upstream files → Mitigation: one patch, its own repository check, and the bump pull request fails at the patch step rather than at run time.
- [Trade-off] Up to 15 minutes more per build while stibnite is busy → accepted for verdicts instead of discarded work; the deadline is one setting (Q2).
- [Trade-off] A reused build (same tree, or `skipQueueIfUpToDate` landing) replays its unproven results without a new attempt → accepted (Q10); the next build containing the derivation attempts it.
- [Trade-off] Pull requests that pass today with a genuinely failing Mac check will block → this is the point of A1; at cutover, `main`'s Mac checks must be green with stibnite awake (Migration step 1).

## Migration Plan

1. Before the cutover pull request: with stibnite awake, read `main`'s latest build; every Mac attribute must be `succeeded` or `skipped_local`. An `ignored_failure` that is a builder's failure is fixed first, or the cutover would block every pull request carrying it (task 5.1).
2. One pull request carries the patch swap, the marking (`allowUnproven`), `nixbot.toml`'s `unproven_deadline` and `unproven_markers`, and every consumer change.
3. Cutover: that pull request is built by the old nixbot, which sees no `ignoreFailure` and ignores the unknown `allowUnproven`, so its Mac attributes are required for that one build. Land it while stibnite is awake, and deploy magnetite immediately after landing; between landing and deploy, any pull request the old nixbot builds treats Mac checks as required (task 5.2).
4. Run the live probes (tasks 5.3-5.5) against the deployed nixbot, the unrecognised path included.
5. First trial cases (task group 6): the seven input-update pull requests held as drafts for this change (#4261 home-manager, #4262 iets, #4263 llm-agents, #4264 niks3, #4266 nix-darwin, #4267 nix-grpc-store, #4268 nix-index-database), each carrying a comment pointing to CAM-126, are marked ready one by one after deployment; each Mac check's outcome is recorded; only those whose Mac checks returned passing verdicts are enqueued, and an unproven one stays held until a build with a Mac present proves it. The flake-input updater force-pushes these branches on Tuesday and Friday at 10:00 UTC, so their revisions will have moved by the trial, and whether it keeps them drafts is unverified: their draft status is re-checked after each updater run until the trial.
6. Rollback: revert the pull request and redeploy magnetite; the old patches and `ignoreFailure` return together. `unproven` and `unrecognised` rows already recorded stay as TEXT and are read by nothing but the dev-loop query, which the revert restores.

## Decisions taken (operator, 2026-11-25)

The operator accepted every recommendation of the proposal's review; Q1 carries a condition, met by D11.

- Q1: Fail closed (D2): a Mac failure the classifier does not recognise blocks. Decided yes, on condition that such a block is noticed and classified within hours (D11).
- Q2: The deadline after the required attributes settle is 1,200 s. Decided; lower it if a burst batch approaches gitea-mq's hour, with raising gitea-mq's `checkTimeout` as the other lever.
- Q3: The stall limit is each check's size-class limit rather than one fixed value. Decided.
- Q4: `nixbot-ignore-failure-dependents.patch` is dropped and `ignoreFailure` is no longer used here. Decided.
- Q5: After merge, the next build containing the derivation discharges an unproven outcome; no rerun timer. Decided.
- Q6: Unproven checks are named in the `nixbot/nix-build` summary and the readiness report, not in a new check run. Decided.
- Q7: The dev-loop column keeps the name `abandoned`, now meaning unproven. Decided.
- Q8: The pyrite evaluation loss is its own change, with the requirement "an attribute the build was asked for that fails evaluation is recorded as a failed evaluation, never only as a warning count". Decided.
- Q9: Infrastructure failures of Linux attributes stay recorded as `failed`. Decided.
- Q10: A reused build replays its unproven results without a new attempt. Decided.

## Open Questions

None remain from the review; Q1-Q10 are decided above. D11's elapsed time from an unrecognised ending to a classified build is a mechanism claim until it is measured: task 5.5 records it on a staged ending, and any real one met during the first trial (task group 6) is recorded the same way.

### What would change the decision

A Mac that is always on (a Mac mini on mains power and the mesh) makes plain required checks simpler and better: drop `allowUnproven` and keep `unproven` only as an infrastructure failure that blocks.
A second Mac builder that is usually awake narrows the unproven case but does not remove it.
Nix reporting a hook build's own failure status (upstream TODO #12641) would let the classification read the exit status instead of the log's wording.
