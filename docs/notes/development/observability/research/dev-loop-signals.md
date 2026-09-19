---
title: Dev-loop signals that close the CCV feedback loop
status: research v1
date: 2026-09-18
sources:
  - cameronraysmith/vanixiets@da74672e5
  - nix-community/buildbot-nix@daf88af
  - Mic92/nix-fast-build@8f0c351
  - nixos/nix-eval-jobs@9f1553a
  - omnigent-ai/omnigent@beb043a6
---

# Dev-loop signals that close the CCV feedback loop

The four-property mapping below cites the CCV skill by section from `cameronraysmith/vanixiets@da74672e5:modules/home/ai/plugins/preferences-operations-and-reliability/.apm/skills/preferences-compositional-continuous-verification/SKILL.md`, hereafter `SKILL.md`.
Sections referenced: §"The four-property hierarchy" (lines 40-69), §"The closure operator" (lines 71-83), §"What this means for an agent session" (lines 99-127).

## Findings

F1 The closure operator is realized locally in two distinct shapes: `just check` runs `nix flake check -L --show-trace` and `just check-fast` runs `nix-fast-build --skip-cached --eval-workers 4 --flake .#checks.$system` (`cameronraysmith/vanixiets@da74672e5:justfile:285`, `:332-337`).
Only the second shape can emit per-attribute data, because `nix flake check` has no per-attribute result surface.

F2 `nix-fast-build` writes a machine-readable per-attribute record when given `--result-file` with `--result-format json|junit` (`Mic92/nix-fast-build@8f0c351:nix_fast_build/options.py:396-405`).
Each record carries `type`, `attr`, `success`, `duration`, `error`, optional `skipped`, `outputs`, `drvPath` and `cacheStatus` (`Mic92/nix-fast-build@8f0c351:nix_fast_build/results.py:28-43`).
Neither `just check` nor `just check-fast` passes `--result-file`, so this record is currently produced by nothing (`cameronraysmith/vanixiets@da74672e5:justfile:332-337`).

F3 Per-attribute *build* wall time is real, but per-attribute *eval* wall time is hardcoded to zero: the EVAL result is constructed with `duration=0.0` behind the comment `TODO: maybe add this to nix-eval-jobs?` (`Mic92/nix-fast-build@8f0c351:nix_fast_build/workers.py:60-61`).
The eval-versus-build split is therefore half-available from existing tooling and half-absent.

F4 Cache hit and miss is already computed per attribute, not inferred: `nix-eval-jobs` emits `cacheStatus` with the three values `cached`, `local` and `notBuilt` (`nixos/nix-eval-jobs@9f1553a:src/drv.cc:243-251`), and `nix-fast-build` reads that field and falls back to the older boolean `isCached` (`Mic92/nix-fast-build@8f0c351:nix_fast_build/workers.py:50-52`).

F5 The same field survives into CI as a first-class buildbot property: `props.setProperty("cacheStatus", job.cacheStatus, source)` (`nix-community/buildbot-nix@daf88af:buildbot_nix/buildbot_nix/build_trigger.py:209`).
Per-attribute CI status, timing and cache status are therefore persisted in buildbot's PostgreSQL by construction, with no new emitter needed.

F6 buildbot-nix ships no metrics exporter at all: a recursive search for `prometheus`, `statsd` or `metrics` over the whole checkout returns zero files (`nix-community/buildbot-nix@daf88af`).
Aggregates over CI history are consequently reachable only through the web UI or by direct query, which is exactly the shape of the September audit, where the number of attributes per build was read out of the `build_attributes` table by hand (`cameronraysmith/vanixiets@da74672e5:docs/notes/development/incidents/2026-09-02-nixbot-eval-throughput-magnetite-storage-audit.md:52`).

F7 The buildbot data API is not web-UI-only in principle but is authenticated in practice: `fullyPrivate` mode places oauth2-proxy in front of the master and declares `api-route = ["^/api" "^/ws$"]` with only `^/change_hook` exempt (`nix-community/buildbot-nix@daf88af:nixosModules/master.nix:1160-1164`).
magnetite runs exactly that mode with the GitHub backend (`cameronraysmith/vanixiets@da74672e5:modules/nixos/buildbot.nix:118-125`), so an off-host collector needs an OAuth identity while an on-host collector can reach the master's loopback port that oauth2-proxy itself proxies to (`nix-community/buildbot-nix@daf88af:nixosModules/master.nix:1157`).

F8 CI covers one system only: the master declares `buildSystems = [ "x86_64-linux" ]` (`cameronraysmith/vanixiets@da74672e5:modules/nixos/buildbot.nix:111`), while the flake declares four darwin configurations (`cameronraysmith/vanixiets@da74672e5:modules/checks/structure/flake-shape.nix:57-66`).
Local-versus-CI divergence is therefore not a drift risk to be measured but a standing structural fact: every darwin-only regulator has zero CI observations, and `just check-fast` routes non-native systems to `--remote magnetite.zt` rather than building them locally (`cameronraysmith/vanixiets@da74672e5:justfile:331`).

F9 Existence is measurable today with the enumeration commands the skill itself supplies, which count attribute names for `currentSystem` only (`SKILL.md:110-115`).
The count has no denominator in this repository, because no artifact manifest exists; the check tree is 31 files under `modules/checks/` with no declared artifact set beside them.

F10 Traceability, the surjectivity of check-artifact pairs onto artifacts requiring regulation (`SKILL.md:48-50`), cannot be computed at all today, since the denominator of F9 is absent.
`SKILL.md:131-133` states that the traceability, adequacy, integrity and exemption-audit meta-derivations are out of scope for the skill and live flake-side, and no such derivation exists in `modules/checks/`.

F11 Adequacy is depth relative to a declared bin set and is meaningless without one (`SKILL.md:52-54`), and this repository declares no bin set anywhere under `modules/checks/` or `modules/lib/`.
`SKILL.md:54` further states that observability-interaction bins are an adequacy obligation rather than a stylistic choice, which makes the absence of the store a current adequacy gap, not a future one.

F12 Integrity evidence exists in this repository but is structurally unobservable, because it is asserted at eval time and emits nothing.
`modules/checks/omnigent-environment.nix` builds three named policy mutants and asserts that every one of them produces a non-empty failure list, with the message `Omnigent environment oracle accepted a policy mutant` (`cameronraysmith/vanixiets@da74672e5:modules/checks/omnigent-environment.nix:98-114`).
`modules/checks/omnigent-workers.nix` writes a mutated launcher that appends `|| true` to an activation line and asserts the discriminating outcome (`cameronraysmith/vanixiets@da74672e5:modules/checks/omnigent-workers.nix:884-889`).
`modules/checks/structure/aggregate-eval-failure.nix` documents its own negative control in prose: flipping `expected` to `true` makes the check fail (`cameronraysmith/vanixiets@da74672e5:modules/checks/structure/aggregate-eval-failure.nix:17-19`).
A mutation-kill *rate* over these is not derivable, because the mutant set is embedded in assertions rather than enumerated as data.

F13 The exemption audit that `SKILL.md:67-69` names as the fifth wheel against silent erosion has a live instance with no owner and no expiry: `deferred = [ "scheelite" ]` suppresses one machine's build check, and a sibling assertion explicitly excludes deferred machines from the obligation set (`cameronraysmith/vanixiets@da74672e5:modules/checks/machines.nix:6`, `:50-52`).

F14 Deploy events are not recorded anywhere machine-readable: activation runs through `nh` via the `just activate*` recipes (`cameronraysmith/vanixiets@da74672e5:justfile:75-104`), which leave no artifact naming the closure that was activated.
Deploy-to-incident latency therefore has no start timestamp today, whatever the incident side provides.

F15 Incident-to-regulator latency is measurable from repository history and currently reads as unbounded for the most recent incident: the September audit closes with a section titled `Recommendations, unapplied` (`cameronraysmith/vanixiets@da74672e5:docs/notes/development/incidents/2026-09-02-nixbot-eval-throughput-magnetite-storage-audit.md:228`).
The June 10 pair is the counter-example of the loop closing, where an ENOSPC crash loop produced quota and threshold commits in the same response (`:206`).
`SKILL.md:122` states the obligation in the form this signal measures: for every incident, the coverage-model update is part of the same resolution.

F16 Runtime envelope violations are already emitted to the journal and already reduced to numbers by hand: `nix-gc` and `nix-optimise` fired successfully on 63 of 63 retained journal days with per-run frees enumerated, and one evidentiary boundary is named because the journal only retains from 2026-07-01 (`cameronraysmith/vanixiets@da74672e5:docs/notes/development/incidents/2026-09-02-nixbot-eval-throughput-magnetite-storage-audit.md:210`, `:214`).
Retention, not instrumentation, is the binding constraint on this signal.

F17 Closure-operator throughput is already derivable from state magnetite keeps: the `eval-gcroots` index advanced from 171 to 186 in forty-five minutes, giving roughly 180 seconds per evaluation and about twenty evaluations per hour (`:80-81`).
The consequence that motivates collection is stated numerically: a human pull request arriving behind one full automated cycle waits 3 hours 8 minutes before its own evaluation begins (`:110-111`).

F18 The repository's own check set has a measured cost distribution with a named lever: FULL-ACT bindings are 9.4% of attributes and 47.4% of the deduplicated path union, and the recommendation is a canary-per-shape arrangement with the full set on scheduled runs (`:228-230`, `:161-163`).
This is an adequacy-bin resizing decision that was computed once by hand and has no time series behind it.

F19 Agent-session telemetry is already emitted and merely unrouted: omnigent installs an OTLP `TracerProvider` when `OTEL_EXPORTER_OTLP_ENDPOINT` is set and is otherwise inert (`omnigent-ai/omnigent@beb043a6:omnigent/runtime/telemetry.py:1241`, `:14-15`).
Spans carry `session.id` (`:235`) and token usage as `gen_ai.usage.input_tokens`, `gen_ai.usage.output_tokens` and the cache-read and cache-creation variants (`:689`, `:719-726`).
A repository-wide search for `OTEL_EXPORTER`, `opentelemetry`, `prometheus` or `otlp` under `modules/` matches only agent-skill prose under the vendored plugin tree and no configuration (`cameronraysmith/vanixiets@da74672e5:modules/`).

F20 Per-tool-call spans already exist with name `tool:<tool_name>`, the attributes `tool.name` and `gen_ai.tool.name`, `gen_ai.operation.name = execute_tool`, and a `duration_ms` attribute (`omnigent-ai/omnigent@beb043a6:omnigent/inner/tracing.py:266-276`, `:294-295`).

F21 Tool-call failure *classes* are not obtainable under a W9-safe configuration, only failure *rates*: `end_tool_span` records the error message and sets the descriptive status only when content capture is on, and otherwise sets a bare `StatusCode.ERROR` with no class attribute (`omnigent-ai/omnigent@beb043a6:omnigent/inner/tracing.py:296-303`).
A redaction-safe `error.type` helper exists (`omnigent-ai/omnigent@beb043a6:omnigent/runtime/telemetry.py:731-748`) but a search for its call sites outside its own module finds none.

F22 The content hazard is already gated and already redacted upstream: capture is opt-in behind `OMNIGENT_OTEL_CAPTURE_CONTENT` (`omnigent-ai/omnigent@beb043a6:omnigent/runtime/telemetry.py:80-90`, `:186-188`), and payloads pass through `_redact_payload`, which replaces secret-looking keys with `[redacted]` and caps serialized length (`:135-171`).
Leaving that variable unset is the whole of the W9 discipline for omnigent, and `modules/checks/omnigent-environment.nix` is an existing mutant-tested oracle over the worker environment that could assert its absence (F12).

## Bearing on decisions

**D4 (signal scope and schema).**
The evidence points at a small, mostly-existing signal set: per-attribute `{attr, system, success, duration, cacheStatus, drvPath}` from F2 and F4, per-attribute CI status from F5, and omnigent spans from F19.
Cardinality is bounded by attribute count times system count times build count, which F6's `build_attributes` figure puts at 117 attributes per build, so the dev-loop half of D4 is a low-cardinality problem.
What would reverse this: if the traceability and adequacy meta-checks of F10 and F11 require per-artifact bin identifiers, cardinality becomes artifacts times bins rather than attributes, and the budget must be recomputed.

**D5 (dev-loop instrumentation).**
Most of what R2 asks for is already emitted and merely uncollected, which is the strongest anti-ceremony argument available under C1: F2, F4, F5, F16, F17, F19 and F20 need routing, not authoring.
The genuinely new instrumentation is narrow and enumerated: per-attribute eval duration (F3), an artifact-and-bin manifest (F10, F11), a mutant enumeration (F12), an exemption ledger (F13), a deploy event (F14), and a redaction-safe tool error class (F21).
What would reverse this: if `--result-file` output proves too coarse to attribute a regression to a bin, the eval-side instrumentation moves from optional to load-bearing.

**D3 (collection topology).**
F7 pushes toward an on-host collector on magnetite for CI signals, because the loopback master port is reachable without an OAuth identity while `^/api` through oauth2-proxy is not.
F8 pushes the opposite way for closure-operator signals: darwin hosts never appear in CI, so local `check-fast` runs are the only observation channel for four of ten machines, and a laptop-side emitter is required rather than optional.
What would reverse this: adding darwin to `buildSystems`, which would move local-versus-CI divergence from structural to incidental.

**D8 (access control and tenancy).**
F22 shows the prompt-content hazard is upstream-gated and upstream-redacted, so D8's omnigent half reduces to asserting one environment variable stays unset, with F12's existing mutant-tested oracle as the natural regulator.
F21 is the countervailing evidence: the W9-safe configuration costs the failure-class dimension, so D8 cannot be settled without deciding whether to carry an upstream patch.
What would reverse this: an upstream change wiring `error.type` unconditionally, which would make the safe configuration lossless.

**D6 (storage substrate and lakehouse seam).**
F2's JSON and JUnit records and F5's relational history are both batch-shaped and analytic rather than alerting-shaped, which favors the Parquet-reachable seam over a metrics silo.
What would reverse this: if the regulator-quality series of F10 through F13 are wanted as live gates inside `nix flake check`, they need a query path the closure operator can call synchronously.

**D1, D2, D7.** Not touched by this unit beyond D4's cardinality input.

## Flags

W3 is confirmed rather than contradicted, and sharpened: the absence is not merely of a store but of any emitter wiring, since `OTEL_EXPORTER_OTLP_ENDPOINT` appears nowhere in `modules/` (F19).

CCV's own claim that a local pass is a CI pass by hash equality (`SKILL.md:102`) does not hold across platforms in this repository, because CI evaluates one system and the fleet has two (F8).
That is a contradiction between the skill's stated guarantee and the deployed configuration, and it is a traceability hole rather than a measurement problem.

`SKILL.md:81` asserts that a green closure operator implies traceability, adequacy and integrity.
No meta-check for any of the three exists in `modules/checks/` (F10, F11), so the implication is currently vacuous in this repository, and the claim should be read as a target rather than a description.

Acceptance regulator A4 false-positives on this document: its `/home/` pattern matches this repository's own `modules/home/` tree, which the CCV skill's citation path necessarily contains.
That is a defect in the regulator's approximation rather than an S5 violation, and no absolute path appears in this text.

Absent, reported explicitly: per-attribute eval duration (F3); any buildbot-nix metrics exporter (F6); any artifact manifest, bin declaration, mutant enumeration or exemption ledger (F9 through F13); any deploy record (F14); any tool-call error class under safe configuration (F21).

The nixbot master is a second CI backend alongside the buildbot master on the same host, and the September audit measures nixbot rather than buildbot throughput, so any CI signal schema needs a backend label or the two series will be silently merged.

`omnigent/runtime/telemetry.py:731-748` advertises operator-facing filtering by error class that no call site outside its own module supplies; that docstring overstates the shipped behavior (F21).

## Questions

Q1 Does the artifact denominator for traceability (F10) mean flake outputs, `modules/` files, or a hand-declared manifest?
The three give different untraced-count series and different failure modes, and the choice is a human decision under C1.

Q2 Is `deferred = [ "scheelite" ]` (F13) a legitimate exemption needing an owner and expiry, or a defect to be fixed?
This unit refused to infer which.

Q3 Should the design carry an upstream patch or fork to obtain redaction-safe tool-call error classes (F21), accept failure rates without classes, or enable content capture behind an access boundary that D8 would then have to defend?

Q4 Is darwin CI coverage (F8) in scope for this design, or is the local-run channel the accepted permanent answer for four of ten machines?

## Ranked signals by decision value over instrumentation cost

1. Per-attribute `cacheStatus` plus build duration from `--result-file` (F2, F4).
   Decision: adequacy-bin affordability, specifically which regulators stay in the per-pull-request lane versus the scheduled lane (F18).
   Cost: one flag on two justfile recipes, against a signal that is already emitted.
2. Per-attribute CI status and duration from the buildbot database or loopback data API (F5, F7).
   Decision: the same bin-lane partition, plus attribution of a regression to a commit.
   Cost: one on-host reader, against a signal that is already persisted.
3. Closure-operator throughput and queue depth (F17).
   Decision: whether the per-pull-request bin set is admissible at all, which is the batching lever the audit computed once by hand.
   Cost: sample an index that already advances.
4. Exemption ledger with owner and expiry (F13).
   Decision: exemption expiry, the drift channel `SKILL.md:67-69` names.
   Cost: one declaration plus one check, and the instrumentation is new.
5. Deploy event naming machine, flake revision and closure hash (F14).
   Decision: deploy-to-incident latency, which is what attributes an incident to a closure and therefore to a missing bin.
   Cost: one emitter in the activation path, and the instrumentation is new.
6. Incident-to-regulator latency from repository history (F15).
   Decision: whether the double loop should change the process, since the current value is unbounded for the most recent incident.
   Cost: derived from commit and document dates that already exist.
7. Untraced-artifact count (F10).
   Decision: add a regulator in the same commit, per `SKILL.md:120-122`.
   Cost: an artifact manifest, new instrumentation, blocked on Q1.
8. Declared-bin saturation (F11).
   Decision: bin addition and removal, including the observability-interaction bins of `SKILL.md:54`.
   Cost: a per-artifact bin declaration, new instrumentation, strictly downstream of item 7.
9. Mutation-kill rate per regulator (F12).
   Decision: retire or strengthen a regulator whose kill rate falls.
   Cost: lift the embedded mutants into enumerated data, new instrumentation, strictly downstream of item 8.
10. omnigent session spans with token usage (F19, F20).
    Decision: cost attribution per session, feeding the planning-unit sizing `SKILL.md:141-142` leaves open.
    Cost: one environment variable plus an endpoint, against a signal that is already emitted.
11. Per-attribute eval duration (F3).
    Decision: whether a proposed bin is eval-cheap or build-expensive, which sets the marginal cost of closing an adequacy gap.
    Cost: an upstream change or a timestamping wrapper, and the instrumentation is new.
12. Local-versus-CI attribute-set difference (F8).
    Decision: whether an envelope is platform-scoped.
    Cost: a set difference between a local result file and CI history, already emitted on both sides, blocked on Q4.
13. Tool-call failure rate per tool name (F20).
    Decision: which harness surfaces need a regulator of their own.
    Cost: falls out of item 10, already emitted.
14. Journal-derived envelope violations, meaning unit failures and garbage-collection frees (F16).
    Decision: retention and threshold envelope revision.
    Cost: a journal shipper, already emitted but retention-bounded.
15. Raw check-attribute count (F9).
    Chart-only, rejected: existence alone is the trivial property (`SKILL.md:44-46`), and without the denominator of item 7 the count feeds no decision.
16. Harness turn latency in isolation.
    Chart-only, rejected under C1: it names no failure it prevents unless joined to a check outcome or a session cost, at which point item 10 already carries it.
