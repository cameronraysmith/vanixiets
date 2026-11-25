---
linear_story_id: CAM-126
linear_story_identifier: CAM-126
linear_story_title: "Tell a failed Mac check from an absent Mac builder in CI"
linear_story_url: https://linear.app/cameronraysmith/issue/CAM-126/tell-a-failed-mac-check-from-an-absent-mac-builder-in-ci
linear_story_state: Backlog
linear_team: CAM
last_synced_state: Backlog
last_synced_at: "2026-11-24T22:40:00Z"
review_round: 0
max_review_rounds: 3
attempt_log: []
---

## Why

CI records three different Mac outcomes as one `ignored_failure`: a Mac built a check and it failed, a Mac was still building when the Linux checks settled, and no Mac was reachable.
So a real Mac regression passes the queue unseen (build 2456), and on 2026-11-24 seven green pull requests had Mac checks stopped mid-build during the update burst (builds 3001-3008).
The log nixbot already reads tells the three apart; the status it records does not.
Telling them apart lets a Mac failure block a merge while an absent or busy Mac still never does.

## What Changes

The decision: a Mac check's result blocks a merge only when it is a *verdict*, a builder's answer after running the check.
A check that ends without a verdict is *unproven*: never blocking, never cached, built again by the next build that contains it, and named wherever readiness is reported.

**A Mac failure blocks**
- From: every failed Mac check is `ignored_failure`, excluded from the aggregate.
- To: a Mac check whose builder answered with a failure fails the build, like any Linux check; a check settled by such a failure fails too.
- Reason: build 2456's Mac regression was recorded and ignored.
- Impact: breaking for pull requests that today pass with a genuinely failing Mac check.

**An absent Mac is its own outcome**
- From: an unreachable, busy or lost Mac also yields `ignored_failure`.
- To: the attribute ends `unproven`, with the reason (no builder reachable, no progress, builder lost, deadline), and does not affect `nixbot/nix-eval`, `nixbot/nix-build` or `nixbot/effects`; the `nixbot/nix-build` summary and `gh-queue-open-prs` name each unproven check.
- Reason: the operator's decision that no Mac is assumed awake, and that the outcome be visible.
- Impact: non-breaking for merges; a new attribute status.

**An unrecognised Mac failure blocks, labelled, and is classified within hours**
- From: nothing distinguishes a failure whose cause nixbot cannot read.
- To: a Mac failure with neither a builder's answer nor a known infrastructure message ends `unrecognised`: it blocks like a failure, is recorded under its own status with its last error line, and is shown as such in the `nixbot/nix-build` summary and by `gh-queue-open-prs`. Infrastructure markers live in `nixbot.toml` (`unproven_markers`), read from the built worktree, so classifying a new message is one repository edit with a fixture, verified by a check build, with no deploy; a builder's answer always outranks a marker.
- Reason: the operator's condition on failing closed (Q1): a block of this kind must last hours, not days.
- Impact: non-breaking beyond A1; no override and no alert.

**Wait while a Mac is working**
- From: once the Linux checks settle, every Mac check still running is stopped after 300 s (`optional_build_grace`).
- To: once the Linux checks settle, a Mac check is stopped only after it has made no progress for its size-class limit, or when a build-wide deadline (proposed 1,200 s) passes.
- Reason: in the burst, working Mac builds were discarded; their size classes bound one uncontended run, not the builder's queue.
- Impact: up to about 15 minutes more per build while stibnite is busy; none when it is idle or absent; no added evaluation.

**Replaced mechanism**
- `ignoreFailure = true` on Mac checks becomes `allowUnproven = <stall limit seconds>`; `nixbot-ignore-failure-dependents.patch` and `nixbot-abandon-optional-attributes.patch` become one patch, `nixbot-unproven-attributes.patch`; `optional_build_grace` becomes `unproven_deadline`, and `nixbot.toml` gains `unproven_markers`.

**First trial**: after cutover and deploy, the seven input-update pull requests held as drafts for this change (#4261-#4264, #4266-#4268) are the first real cases; only those whose Mac checks return passing verdicts are enqueued.

**Non-goals**: making Mac checks unconditionally required; rerunning `main`'s unproven checks on a timer; an alert for a sleeping Mac or for an unrecognised ending; an override for any Mac outcome; changing how Linux infrastructure failures are recorded; the separate loss of attributes that fail evaluation without a row (decided to be its own change, Q8); posting anything upstream.

## Capabilities

### New Capabilities

- `mac-check-outcomes` (stratum: behavioral): a Mac check's failing verdict blocks a merge; a Mac check without a verdict is unproven and never blocks; a Mac failure of unrecognised cause blocks, is named as unrecognised with its log line, and can be classified within hours without an override; the build waits for a Mac that is making progress, within a stall limit and a deadline; unproven checks are named on the pull request and in the readiness report; an unproven check is built again by the next build containing it; a dependent inherits its dependency's kind of outcome; telling the outcomes apart adds no evaluation.
- `mac-check-outcomes-interface` (stratum: interface): the `allowUnproven` modifier on every `checks.aarch64-darwin` attribute and its value from `testSizes`; `nixbot-unproven-attributes.patch` (modifier delivery, the `unproven` and `unrecognised` outcomes and statuses, the verdict pattern, the stall and deadline rule, dependency propagation, the `nixbot/nix-build` summary); `unproven_deadline` and `unproven_markers` in `nixbot.toml`; `gh-queue-open-prs`' unproven and unrecognised lines; the checks and probes that pin them.
  Trust boundary: Nix's log wording and nix-grpc-store's connection handling decide what nixbot can classify, and this machine only reads them; a Nix update that rewords a message turns the affected endings `unrecognised` (blocking, labelled) until a marker or the verdict pattern is updated, never silently passing; markers come from the built worktree, so their review is part of the repository's review; a failure caused by the Mac's own environment is a verdict here, because nothing in the log separates it from the change's failure.

### Modified Capabilities

- `world-assumptions` (stratum: world): A231-A238 on what Nix and nix-grpc-store report for a remote build, what nixbot reads of it, how Mac checks run under contention, the merge queue's check timeout, and the Mac builders' availability; designations for Mac builder, Mac attribute, verdict, unproven, unrecognised ending, progress and readiness report; `outcome` and `abandoned attribute` restated.
- `devloop-collection` (stratum: behavioral): the past week leaves out unproven rather than abandoned attributes.
- `devloop-collection-interface` (stratum: interface): `abandoned` is computed from the `unproven` status and an unrecognised ending counts as a failure of its build; the marker binding to the abandon patch is removed, since the status itself names the outcome.

## Impact

- Code: `modules/checks/nixbot-best-effort-darwin.nix` (renamed `nixbot-unproven-darwin.nix`), `modules/nixos/nixbot.nix` and its patch list, a new `modules/nixos/nixbot-unproven-attributes.patch` replacing two patches, `nixbot.toml`, `modules/checks/nixbot-wiring.nix`, `modules/nixos/devloop-collection.nix`, `modules/checks/devloop-queries.nix` and its fixtures, `modules/home/tools/commands/git/gh-queue-open-prs.sh`, `modules/home/tools/commands/dev/nixbot-logs.sh`, and comments citing the best-effort module.
- Docs: the repository-overview context fragment's paragraph on ignored failures; `modules/clan/inventory/services/nix-builders.nix`' header.
- Hosts: magnetite (nixbot); stibnite only as a probe subject.
- Depends on `declare-test-size-classes` for the `testSizes` declarations and the `check` and `size class` designations.
- Upstream: nothing is posted; the patch is carried locally like the six existing ones.
