# Brainstorm: telling a failed Mac check from an absent Mac builder

Written by hand as a decision log from a read of the code and the build records on 2026-11-24, not by an interactive brainstorming session.
The operator's direction (A1-A3 below) was given before this log; the decisions here answer it.

## Background

Every `checks.aarch64-darwin` attribute carries hercules-ci's `ignoreFailure = true` (`modules/checks/nixbot-best-effort-darwin.nix`).
Two local nixbot patches extend it: a Mac attribute settled by a failed dependency is ignored (`nixbot-ignore-failure-dependents.patch`), and a Mac attribute still unfinished `optional_build_grace` (300 s, `nixbot.toml`) after every other attribute settled is stopped and ignored (`nixbot-abandon-optional-attributes.patch`).
So three different things share the status `ignored_failure`: a Mac that built the check and saw it fail, a Mac that was still building when the Linux attributes settled, and no Mac at all.

The cost showed twice in the records.
On 2026-11-16 build 2456 (renovate pull request #3851) recorded at least twelve Mac attributes, `package-vanixiets-docs-deps` among them, as ignored failures: stibnite built them and they failed (`error: build of '…vanixiets-docs-deps-0.0.0.drv' on 'grpc://[…]:50051…' failed: … Reason: builder failed with exit code 1.`).
On 2026-11-24, during a burst of 24 update pull requests, seven green input-update pull requests (#4261-#4264, #4266-#4268; builds 3001-3008) had `darwin-*` and `home-manager-*` checks stopped on stibnite 234-406 s after they started; every log tail read ends `abandoned: not finished when the required attributes had settled`, most just after lines such as `stibnite: building …`.
In build 3017, which ran 46 minutes, three of the same medium checks were allowed to finish and took 1,000-1,106 s, against 30-day medians of 125-130 s.

## The operator's direction

- A1: a Mac build that ran and failed blocks the merge.
- A2: a Mac build in progress is not abandoned while a builder is actively working on it, within a bound.
- A3: no reachable Mac stays non-blocking but is its own named outcome, visible wherever readiness is reported.
- Binding: Mac checks are not made unconditionally required; no Mac can be assumed awake.

## Q1: what can nixbot actually observe?

Read in source (nixbot `b0472661`, the pinned revision; Nix master `e7386085`; the deployed client is Nix 2.35.6):

- nixbot runs `nix build --log-format internal-json` per attribute on magnetite, and magnetite's daemon hands aarch64-darwin derivations to the build hook, which sends them over `grpc://` to stibnite, the only Mac magnetite dispatches to.
- Exit status cannot separate the cases: a hook-built derivation that fails for any reason is a `MiscFailure`, so `nix build` exits 1 whether the Mac's builder failed or the connection broke (`derivation-building-goal.cc:801-808`, upstream TODO #12641).
- The log can.
  The hook prints `build of '<drv>' on '<builder>' failed: <message>` only when the builder answered with a failed result (`build-remote.cc:380-389`); a broken transport throws before that line.
  An unreachable builder prints `cannot build on '<builder>'`, is disabled for the hook's lifetime, and the derivation then fails locally for want of the platform (`build-remote.cc:258-268`; the repository's own note in `modules/clan/services/nix-builders/flake-module.nix`).
  A derivation accepted by a builder opens a build activity whose fields name the builder (`derivation-building-goal.cc:701-711`); nixbot reads only the derivation from it (`executor.py:723`).
  A derivation waiting for a free builder slot opens a "waiting for a machine" activity that nixbot does not render.
- nix-grpc-store keeps the connection alive with 20 s pings and a 20 s timeout, so a Mac that sleeps mid-build is noticed in about 40 s plus its retry budget, not after nixbot's 3 h timeout.

Decision: the distinction is a fact in the log nixbot already reads, not in the exit status.
Name it: a *verdict* is a builder's answer for an attribute; an attribute that ends without one is *unproven*.

## Q2: which outcomes are evidence about the change?

A verdict is evidence about the change: the Mac ran the work and answered.
Everything else is evidence about the infrastructure: no Mac reachable, no free slot, the Mac lost mid-build, or the build stopped waiting.
A dependency's failure passes on its kind: a dependent of a failed verdict has a failed verdict; a dependent of an unproven attribute is unproven.

Decision: classify a failure as unproven only on positive evidence that no builder answered, and as a failed verdict otherwise.
Considered and rejected: classifying as a verdict only on positive evidence of an answer.
That fails open: if Nix rewords its line, every Mac regression goes quiet again, which is today's defect.
Failing closed risks a novel infrastructure failure blocking one pull request until it is rebuilt, which is visible and cheap to clear.

## Q3: how long to wait, and against what?

The size classes (`declare-test-size-classes`) looked like the natural source of a total bound: wait for a medium check up to 300 s, or one class up, 900 s.
The records rule that out: build 3017's medium Mac checks needed 1,000-1,106 s under contention, so any class-based total bound would cut honest runs during the burst, the exact failure observed.
A size class bounds one uncontended run; contention is the builder's queue, not the check.

What the class does bound well is silence: a check that makes no progress for as long as a whole run of its class may take is not being worked on.
That separates "busy and working" from "queued for a slot" and "gone".

The total wait needs a source outside the check: the merge queue gives up on a batch whose required checks have not reported within 1 h (gitea-mq `checkTimeout`, default, not set here).
Decision: two clocks, both starting only once every required attribute has settled, since waiting before then costs nothing.
A stall limit per check equal to its size-class limit, and one deadline for the build (1,200 s after the required attributes settled, proposed), leaving the rest of the hour for evaluation, the required attributes and effects.

## Q4: where does the mechanism live?

The check marking says which attributes may end unproven and their stall limit; nixbot decides verdict versus unproven and when to stop waiting; the queue tooling only reports.
`ignoreFailure` keeps its hercules-ci meaning (ignore any failure), so overloading it would mislead; a new modifier `allowUnproven = <seconds>` replaces it on the Mac checks.
Both scheduler patches are replaced by one patch; the dependency rule and the stopping rule both move into it.

## Q5: after merge

An unproven derivation is neither in magnetite's store nor in the failed-build cache (which is off here), so the next build that contains it builds it again.
If that answer is a failure, it blocks the pull request or batch carrying it, as a broken Linux check on `main` would.
No timer reruns `main`, and no alert fires for a sleeping laptop; the readiness report names unproven checks at enqueue time.

## Trade-offs carried to the design

- Failing closed puts a builder-environment failure (build 2456's `EACCES` in the Mac's bun cache may be one) on the change's side of the line.
- Waiting for working Macs adds up to 15 minutes per build when stibnite is busy, in exchange for not discarding work and not landing unproven changes.
- The log wording is Nix's, not ours; a live probe, not a source read, pins it.

## Q6: the operator's answers (2026-11-25)

The operator accepted all ten recommendations, with a condition on failing closed: a block from a message nobody recognises must last hours, not days.
That forced three things the first draft lacked.
An unrecognised ending needs its own status, so it can be counted rather than hidden among verdicts.
Its line must reach the readiness report, so whoever waits sees why.
And classifying it must not need a nixbot patch and a magnetite deploy: the infrastructure markers move from the patch into `nixbot.toml`, read from the built worktree, so the pull request that adds a marker is itself built with it.
A builder's answer still outranks every marker, so a marker can reclassify only endings in which no builder answered.
No override exists; a rerun, or taking stibnite's builder out of service so that its absence is recorded as such, are the only ways to land unrelated work during such a block.
He also named the first trial: seven input-update pull requests (#4261-#4264, #4266-#4268) held as drafts until the change is deployed.
