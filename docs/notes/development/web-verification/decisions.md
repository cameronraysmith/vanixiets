# Decisions

## D1: keep interaction and verification separate

Use Playwright CLI for portable exploration and committed Playwright Test scenarios for the verdict.
Do not add another browser framework merely to demonstrate tool diversity.
This preserves the existing browser/version work and an independent assertion oracle.

## D2: make APM the skill source of truth

Declare the upstream Git skill dependency in the existing planning-and-development plugin.
Reuse the packaged release source in offline composition with a full-revision drift guard.
Remove the direct Home Manager extraSkillDirs route for this skill.
The existing Linear CLI integration is the local precedent.

## D3: separate completed reports from passing verdicts

A conventional failing derivation cannot export normal successful output artifacts.
Produce a valid completed execution report independently of its result, then enforce that result with a mandatory dependent check.
Missing or invalid reports fail closed.
Do not replace the verdict check with an always-green artifact producer.

## D4: use nixbot events for failed-build evidence

Extend the existing registry for build_finished rather than importing GitHub Actions artifact jobs.
Reuse the recorded-build-output lookup and writeShellApplication sidecar pattern.
Publication uses trusted default-branch code and requires no execution of PR code under credentials.

## D5: demonstrate integrity with a controlled defect

A passing baseline alone cannot show that the harness detects regressions.
Use an isolated broken fixture and require the intended assertion to fail while its evidence survives.
Do not break or deploy the real documentation site for the demonstration.

## D6: retain human control over changed expectations

An agent may repair implementation or propose test changes.
It may not silently weaken assertions, accept visual baselines, skip tests, or redefine the journey.
Ambiguity between an intended behavior change and a regression requires review.

## Unresolved operational choices

- Report destination, serving-origin isolation, access policy, and retention.
- Whether publication failures should add a separate required gate.
- Scope of successful-run recordings beyond the focused demonstration.
- Association of a new revision with existing evidence when nixbot reuses an entire build and does not emit build_finished.

These choices do not block pure report/verdict work, skill composition, or hermetic publisher rehearsals.
They do block enabling live publication.

## D7: preserve observations and refresh through an explicit evidence epoch

Review R2 identified that a completed negative report remains a valid cached output.
Pinned nixbot restarts use ordinary realization; Nix 2.35.2 `--rebuild` compares output hashes and does not replace a valid report.
Changing only cache availability would not prevent local reuse.

Use a source-controlled decimal evidence epoch outside the application's source fileset.
Increment it deliberately to collect another required observation without rebuilding unchanged application or browser inputs.
Record the epoch in the report and preserve the old observation.
Do not reuse an epoch or interpret a fresh pass as proof that an earlier failure was harmless.
This provides a defined refresh mechanism; it does not make live or inherently time-dependent tests hermetic.

## Source grounding

The research inspected nixbot at `2626aa2ca80b76ef894f4558635a3fdda1edd8b4` and hercules-ci-effects at `6c58de7236d1cd634deea07bd15d52c7ce470bd3`, matching the inputs at the start of this implementation.
Kandev at `9f8e98e56a023de985ee03c78a30d9e33ea7dd1f` informed the separation between exploration, executable tests, selected PR media, and expiring CI diagnostics.
Its media-ref publication mechanism is a reference, not a selected storage design.
The Playwright CLI release source is to remain coupled to its package; upstream HEAD is not a substitute for inspecting that release.
