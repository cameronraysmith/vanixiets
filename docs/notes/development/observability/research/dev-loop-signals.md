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

## Refresh (2026-10-15)

Revisions read for this refresh: `cameronraysmith/vanixiets@109c67346`, `Mic92/nixbot@3c432d593` (the `nixbot` flake input), `Mic92/gitea-mq@9bad60d8f` (the `gitea-mq` flake input), `nixos/nix-eval-jobs@9f1553afa` (master, unchanged since the original findings), `Mic92/nix-fast-build@496c4c5e4` (master), `clan/clan-core@7ac938fe5` (the `clan-core` flake input), `omnigent-ai/omnigent@a8676d23` (tag `v0.18.0`, the version this repository packages), and `can1357/oh-my-pi@c2cb79e4c` (tag `v18.11.0`, the version the `llm-agents` input pins at `numtide/llm-agents.nix@09aee4513:packages/omp/hashes.json`).
The root nixpkgs input is now the node `nixpkgs_10` at rev `ac1faec44836a722f7b003834f367486ff9adfd1`.

### What changed

RF1 The CI backend this unit studied is no longer the one in service.
buildbot-nix is disabled behind `vanixiets.buildbot.enable`, an `mkEnableOption` that defaults to off (`cameronraysmith/vanixiets@109c67346:modules/nixos/buildbot.nix:36-38`), and nixbot serves both GitHub repositories (`cameronraysmith/vanixiets@109c67346:modules/nixos/nixbot.nix:160-163`).
Every CI-side finding must therefore be re-read against nixbot's schema rather than buildbot's properties.

RF2 nixbot persists per-build and per-attribute rows in its own PostgreSQL database.
`builds` carries `status` (`pending | evaluating | building | succeeded | failed | cancelled`), `commit_sha`, `branch`, `pr_number`, `tree_hash`, `created_at`, `started_at` and `finished_at` (`Mic92/nixbot@3c432d593:nixbot/nixbot/migrations/0001_initial.sql:25-50`), plus `eval_duration_ms` (`Mic92/nixbot@3c432d593:nixbot/nixbot/migrations/0027_eval_stats.sql:2`).
`build_attributes` carries `attr`, `system`, `drv_path`, `outputs`, `status`, a boolean `cached`, `error`, `started_at` and `finished_at` (`Mic92/nixbot@3c432d593:nixbot/nixbot/migrations/0001_initial.sql:56-77`), plus `eval_wall_ms` and `eval_alloc_bytes` (`Mic92/nixbot@3c432d593:nixbot/nixbot/migrations/0027_eval_stats.sql:4-6`).
The attribute status set is `pending | building | succeeded | failed | cancelled | skipped_local | dependency_failed | cached_failure | failed_eval` (`Mic92/nixbot@3c432d593:nixbot/nixbot/migrations/0001_initial.sql:64-65`) plus `ignored_failure` (`Mic92/nixbot@3c432d593:nixbot/nixbot/build_scheduler.py:121`).

RF3 nixbot rows are pruned after 90 days by default.
`retention_days` defaults to 90 (`Mic92/nixbot@3c432d593:nixbot/nixbot/config.py:427-428`), the cleanup query deletes finished builds older than that (`Mic92/nixbot@3c432d593:nixbot/nixbot/db_gen/maintenance.py:232-238`), and this repository does not override it (`cameronraysmith/vanixiets@109c67346:modules/nixos/nixbot.nix:83-210`).
A collector that wants CI history longer than 90 days must copy rows before the prune runs.

RF4 nixbot also exposes an unauthenticated Prometheus `/metrics` endpoint, but it carries only fleet-wide aggregates.
The module docstring states that metrics are aggregated by status or state only and never labelled by project (`Mic92/nixbot@3c432d593:nixbot/nixbot/web/metrics.py:1-4`).
The exposed series are build and attribute counts by status, queue depth, oldest active build age, build and eval duration sums and counts, work-queue, effect and upload-queue gauges (`Mic92/nixbot@3c432d593:nixbot/nixbot/web/metrics.py:46-155`).
Every series is typed `gauge`, and the duration "sums" are recomputed over retained rows (`Mic92/nixbot@3c432d593:nixbot/nixbot/db_gen/web.py:636-639`), so they fall when RF3's prune runs and are not Prometheus counters.
Per-attribute status, duration, cache and eval cost are therefore available only as database rows.

RF5 Our local patches add two CI outcomes that nixbot upstream does not record.
`nixbot-ignore-failure-dependents.patch` settles an `ignoreFailure` attribute whose dependency failed as `ignored_failure` instead of `dependency_failed` (`cameronraysmith/vanixiets@109c67346:modules/nixos/nixbot-ignore-failure-dependents.patch:15-21`).
`nixbot-abandon-optional-attributes.patch` stops optional attributes still unfinished `optional_build_grace` seconds after every required attribute settled, and records them as `ignored_failure` with the error text `not finished when the required attributes had settled` (`cameronraysmith/vanixiets@109c67346:modules/nixos/nixbot-abandon-optional-attributes.patch:138-152`).
That error string reaches `build_attributes.error` through `complete_attribute` (`Mic92/nixbot@3c432d593:nixbot/nixbot/build_run.py:760-790`).
An abandoned attribute is thus distinguishable from a genuinely failed ignored attribute only by matching that error text, not by status.
The grace is 300 seconds (`cameronraysmith/vanixiets@109c67346:nixbot.toml:21`).

RF6 aarch64-darwin is now in CI as a best-effort system.
`buildSystems` and `evalSystems` both list `x86_64-linux` and `aarch64-darwin` (`cameronraysmith/vanixiets@109c67346:modules/nixos/nixbot.nix:94-101`), and every `checks.aarch64-darwin` attribute carries `ignoreFailure = true` (`cameronraysmith/vanixiets@109c67346:modules/checks/nixbot-best-effort-darwin.nix:28-29`).

RF7 Per-attribute evaluation cost is emitted by nix-eval-jobs and persisted by nixbot.
Every nix-eval-jobs output line carries `"stats": {"wallMs", "allocBytes"}` measured around each worker evaluation (`nixos/nix-eval-jobs@9f1553afa:src/worker.cc:396-405`, `nixos/nix-eval-jobs@9f1553afa:README.md:139-145`), introduced by `nixos/nix-eval-jobs@d526b15` on 2026-09-01.
nixbot reads it into `eval_wall_ms` and `eval_alloc_bytes` (`Mic92/nixbot@3c432d593:nixbot/nixbot/db.py:184-185`).
The README warns that shared values are billed to whichever attribute forced them first, so the figure locates outliers rather than giving exact per-attribute cost (`nixos/nix-eval-jobs@9f1553afa:README.md:142-145`).
nix-fast-build still discards it and hardcodes the eval duration to zero (`Mic92/nix-fast-build@496c4c5e4:nix_fast_build/workers.py:61`).

RF8 The local closure operator still writes no per-attribute record.
`just check-fast` invokes `nix-fast-build` without `--result-file` (`cameronraysmith/vanixiets@109c67346:justfile:349-375`).

RF9 gitea-mq records batch lifecycle both as database rows and as log lines.
The `batches` table carries `state` (`forming | testing | done | cancelled`), `member_ids`, `landed_ids`, `ejected_ids`, `builds`, `ff_retries`, `flaky`, `created_at` and `testing_started_at`, with no completion timestamp (`Mic92/gitea-mq@9bad60d8f:internal/store/pg/migrations/004_batches.sql:2-24`).
Batch rows are never deleted by any query (`Mic92/gitea-mq@9bad60d8f:internal/store/pg/query.sql`), but `queue_entries` rows, which hold PR numbers and `enqueued_at`, are deleted when an entry leaves the queue (`Mic92/gitea-mq@9bad60d8f:internal/store/pg/query.sql:13-15`, `:93-95`).
A historical batch row therefore keeps entry ids whose PR numbers and enqueue times are gone.
The log events `batch formed` (members), `batch built` (build number, sha, current, pending), `batch bisecting` (failed check, left, right), `batch landed` (sha, prs) and `batch done` (landed, ejected, builds, flaky) are emitted through `slog` (`Mic92/gitea-mq@9bad60d8f:internal/batch/batch.go:143`, `:228`, `:328`, `:391`, `:568`) with a text handler on stderr (`Mic92/gitea-mq@9bad60d8f:cmd/gitea-mq/main.go:52`), so they reach the journal as logfmt-style text with timestamps.
gitea-mq exposes no metrics endpoint; a search for `prometheus`, `/metrics` and `opentelemetry` in its Go sources returns nothing (`Mic92/gitea-mq@9bad60d8f`).
Our settle patch adds only a `Debug`-level `batch settling` line (`cameronraysmith/vanixiets@109c67346:modules/nixos/gitea-mq-batch-settle.patch:93`).
The one known source of `flaky=true` is an unpatched nixbot supersede race, counted by hand as once in 27 multi-PR batches (`cameronraysmith/vanixiets@109c67346:modules/nixos/nixbot.nix:248-252`).

RF10 Machine deploys still produce no event naming a flake revision.
No effect deploys machines; the vanixiets effects are `docs`, `browser-evidence` and `release-packages` (`cameronraysmith/vanixiets@109c67346:modules/effects/vanixiets/effects.nix:44`, `:74`, `:114`).
`clan machines update` on NixOS builds, copies, runs `nix-env --set` on `/nix/var/nix/profiles/system`, then `switch-to-configuration` (`clan/clan-core@7ac938fe5:pkgs/clan-cli/clan_lib/machines/update.py:376-420`), and on darwin shells out to `darwin-rebuild switch` (`clan/clan-core@7ac938fe5:pkgs/clan-cli/clan_lib/machines/update.py:687-699`).
It writes no deployment record of its own in that path.
The profile generation symlink does name the activated closure and its creation time, but `system.configurationRevision` is set nowhere in `modules/` (`cameronraysmith/vanixiets@109c67346:modules/`), so no on-host artifact links a closure to a commit.

RF11 omp (oh-my-pi) emits OpenTelemetry natively, which the original unit did not examine.
omp registers OTLP trace, log and metric providers when any `OTEL_EXPORTER_OTLP_*ENDPOINT` is set, over `http/protobuf` only (`can1357/oh-my-pi@c2cb79e4c:docs/environment-variables.md:649-662`), and export remains on by default unless `telemetry.otlpExportEnabled` is false (`can1357/oh-my-pi@c2cb79e4c:packages/coding-agent/CHANGELOG.md:1188`).
GenAI spans date from `can1357/oh-my-pi@4679789cf1` (2026-05-15), so this capability existed when the original unit was written.
Metrics include `gen_ai.client.token.usage`, `omp.agent.chat.cost.estimated_usd`, `omp.agent.runs`, `omp.agent.chat.duration`, `omp.agent.tool.calls` labelled by `gen_ai.tool.name` and `omp.tool.status`, `omp.agent.tool.duration` and `omp.agent.errors` (`can1357/oh-my-pi@c2cb79e4c:packages/coding-agent/src/telemetry-export-otlp.ts:220-256`, `:300-305`).
Spans carry `gen_ai.conversation.id`, token usage and `error.type` (`can1357/oh-my-pi@c2cb79e4c:packages/agent/src/telemetry.ts:76`, `:100-104`, `:1217`).
Message, system-instruction and tool-argument content is captured only when `OTEL_INSTRUMENTATION_GENAI_CAPTURE_MESSAGE_CONTENT` is `summary` or truthy, and defaults to none (`can1357/oh-my-pi@c2cb79e4c:packages/agent/src/telemetry.ts:454-469`).
The log signal is not under that gate: every internal logger event is forwarded as an OTLP log record with its message and context attributes (`can1357/oh-my-pi@c2cb79e4c:packages/coding-agent/src/telemetry-export-otlp.ts:178-188`), and error-valued context is rendered as `name: message` (`:427-431`).
This repository sets no `OTEL_*` variable for omp (`cameronraysmith/vanixiets@109c67346:modules/home/ai/omp/default.nix`).

RF12 Omnigent's emitter is unchanged in substance at the packaged version, but cannot export as packaged.
The packaged version is 0.18.0 from PyPI with `opentelemetry-api` as the only OpenTelemetry dependency (`cameronraysmith/vanixiets@109c67346:pkgs/by-name/omnigent/package.nix:8`, `:70`).
Upstream moved the SDK and OTLP exporters into the opt-in `tracing` and `all` extras (`omnigent-ai/omnigent@a8676d23:pyproject.toml:148`, `:217`), and trace initialization imports `opentelemetry.sdk` inside a `try` that only logs on failure (`omnigent-ai/omnigent@a8676d23:omnigent/runtime/telemetry.py:1064-1085`).
Enabling telemetry on the packaged build would therefore log an exception and export nothing.
The root nixpkgs input provides `opentelemetry-sdk`, `opentelemetry-exporter-otlp-proto-http` and `opentelemetry-exporter-otlp-proto-grpc` at 1.43.0 and `opentelemetry-instrumentation-fastapi` at 0.64b0 (evaluated against `nixpkgs_10` at `ac1faec44`), so adding them is a dependency-list change.
New since the original findings, Omnigent emits OTLP metrics: `omnigent.skill.invocations` labelled by `skill.name` and turn `outcome`, `omnigent.skill.execution.duration`, `omnigent.skill.tool_calls` labelled by `tool.name` (`omnigent-ai/omnigent@a8676d23:omnigent/runtime/skill_metrics.py:19-21`, `:54-80`, added in `omnigent-ai/omnigent@14b70a24`), and server HTTP request counters and duration (`omnigent-ai/omnigent@a8676d23:omnigent/server/performance_metrics.py:807-830`).
Tool spans still set a bare `StatusCode.ERROR` without `error.type` unless content capture is on (`omnigent-ai/omnigent@a8676d23:omnigent/inner/tracing.py:284-307`), and `record_error` still has no call site outside its module.

### Corrections

RC1 Supersedes F19's statement that omnigent installs an OTLP `TracerProvider` whenever `OTEL_EXPORTER_OTLP_ENDPOINT` is set.
A master opt-in `OMNIGENT_TELEMETRY_ENABLED`, off by default, gates all of it, and it was already present at the revision F19 cited (`omnigent-ai/omnigent@beb043a6:omnigent/runtime/telemetry.py:104-114`, `:1187`).
Routing omnigent spans therefore needs two variables plus the SDK packages of RF12, not one variable.

RC2 Supersedes F3 and ranked signal 11, which recorded per-attribute eval duration as absent and requiring an upstream change.
nix-eval-jobs has emitted it since 2026-09-01 and nixbot persists it per attribute (RF7); it is absent only on the local `nix-fast-build` path.

RC3 Supersedes F5 and F7, which placed per-attribute CI status, timing and three-valued `cacheStatus` in buildbot's database behind oauth2-proxy.
The live CI store is nixbot's database (RF1, RF2), its cache field is a boolean `cached` rather than the three-valued `cacheStatus`, and the rows expire after 90 days (RF3).

RC4 Supersedes F6's conclusion that CI aggregates are reachable only by web UI or direct query.
nixbot's `/metrics` serves status-level aggregates; per-attribute data remains database-only (RF4).

RC5 Supersedes F8, Q4 and the D3 paragraph's statement that darwin hosts never appear in CI.
aarch64-darwin checks are evaluated and built in CI best-effort (RF6), so local-versus-CI divergence on darwin is now incidental per attribute, observable as `ignored_failure` rows, rather than structural.

RC6 Supersedes the Flags paragraph requiring a backend label to keep buildbot and nixbot series apart.
With buildbot disabled the label guards nothing current, though it remains cheap if buildbot is re-enabled.

RC7 Narrows F14.
A NixOS system profile generation does name the activated closure and time (RF10); what is missing is the closure-to-commit link and any event emitted at deploy time.

RC8 Extends F19 through F22 and the D8 paragraph, which treated omnigent as the only agent emitter.
omp is a second native emitter, and its log signal forwards free-form messages outside any content gate (RF11), which is a W9 exposure the omnigent-only analysis did not cover.

### Signal table

| Signal | Source | Current availability | Coverage-model decision fed |
| --- | --- | --- | --- |
| Per-attribute CI status, duration, `cached`, system | nixbot `build_attributes` | Database rows only, 90-day retention (RF2, RF3) | Bin-lane partition: which regulators stay per pull request versus scheduled; regression attribution to a commit |
| Per-attribute eval wall time and allocation | nix-eval-jobs `stats` via nixbot `eval_wall_ms`, `eval_alloc_bytes` | Database rows only (RF7); zero on the local path | Marginal cost of a proposed bin: eval-cheap or build-expensive |
| Fleet-wide build, attribute and queue aggregates | nixbot `/metrics` | Unauthenticated Prometheus gauges, status-labelled only (RF4) | Closure-operator throughput envelope: whether the per-pull-request bin set is admissible |
| Abandoned optional attributes | nixbot `ignored_failure` with the abandonment error text (local patch) | Database rows, distinguishable by error text only (RF5) | Whether a best-effort darwin regulator ever observes anything, i.e. is vacuous in practice and should be scheduled or retired |
| Ignored failures of darwin checks | nixbot `ignored_failure` on `checks.aarch64-darwin.*` | Database rows (RF5, RF6) | Platform-scoped envelopes: promote a darwin check to required or record it as an exemption with owner and expiry |
| Batch formed, built, bisecting, landed, done (landed, ejected, builds, flaky) | gitea-mq journal lines and `batches` table | Logs with timestamps; rows without completion time, with PR identity lost on dequeue (RF9) | Batch-size and settle-window envelopes; flaky rate decides whether the supersede race earns a patch |
| Ejection with failed check | gitea-mq `batch bisecting` log | Logs only (RF9) | Which required check rejects merges, i.e. which bin catches real defects |
| Local per-attribute result | `nix-fast-build --result-file` | Not produced; flag not passed (RF8) | Local-versus-CI attribute-set difference |
| Deploy event (machine, closure, commit, outcome) | `clan machines update`, `just activate*` | Profile generation only, no commit link, no event (RF10) | Deploy-to-incident latency: attributing an incident to a closure and therefore to a missing bin |
| omp token usage, cost, tool calls by status, errors | omp OTLP metrics and spans | Emitted natively when an endpoint is set; not configured (RF11) | Planning-unit sizing and which harness tools need their own regulator |
| omp log records | omp OTLP logs | Emitted natively when an endpoint is set; content ungated (RF11) | None until redacted; a W9 obligation rather than a signal |
| Omnigent sessions, tool spans, skill outcome metrics | Omnigent OTLP | Needs `OMNIGENT_TELEMETRY_ENABLED`, an endpoint and SDK packages (RC1, RF12) | Cost attribution per session; skill outcome rate decides skill retirement or strengthening |
| Omnigent tool error class | Omnigent tool spans | Absent under the content-safe configuration (RF12) | Unchanged from F21 |

### Bearing on decisions, refreshed

D3: the CI half of collection is an on-host reader of nixbot's and gitea-mq's PostgreSQL databases plus a journal reader on magnetite, because the per-attribute and per-batch data have no network surface.
D4: omp adds `gen_ai.tool.name` and `omp.tool.status` as label dimensions, both bounded by the tool roster.
D5: the genuinely new instrumentation list shrinks by per-attribute eval duration (RC2) and grows by nothing.
D8: two emitters now require collector-side allow-listing, and omp's log signal is the one with no emitter-side gate.

### Questions

RQ1 Should CI history beyond nixbot's 90-day retention be kept by copying rows into the store, by raising `retention_days`, or not at all?

RQ2 Should abandonment be made a distinct attribute status in our nixbot patch, so that RF5's signal does not depend on matching error text?

RQ3 Should deploys record their commit, by setting `system.configurationRevision` or by emitting an event from the activation path, and which path counts as the deploy of record: `clan machines update` or `just activate*`?

RQ4 Should omp's OTLP log signal be disabled with `OTEL_LOGS_EXPORTER=none` while traces and metrics are exported, or routed through a collector allow-list?

RQ5 Should the omnigent package gain the SDK and exporter dependencies of its `tracing` extra, given that its metrics are content-free and its spans are content-gated?
