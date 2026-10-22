# Brainstorm: collect dev-loop signals into `devloop` (S2, CAM-69)

## Background

Slice S2 of the fleet observability implementation (`docs/notes/development/observability/architecture/reference-architecture.md:252-254`): the nixbot reader, the gitea-mq journal parse, the deploy record, `devloop-reconcile`, the `devloop-queries` check and the dev-loop SLO burn rule.
It realizes ADR-005 (`decisions/ADR-005-dev-loop-instrumentation.md`) except the omp emitter, which moves to S7 (`reference-architecture.md:253`), and its component is `devloop-exporters` (`components/devloop-exporters.md`).
The burn rule was deferred to S2 by S3's D8 (`charter.md:332`), and S3's review finding F10, one database header for every query, was deferred with it (`charter.md:356`).
Classification under `skill://brainstorming`: architectural, because S2 adds a logs path and new tables to the store and changes interfaces other slices depend on (`openspec/specs/telemetry-store-interface/spec.md:77`, `:116`; `openspec/specs/fleet-alerting-interface/spec.md:12`).

Abbreviations used below: `OBS` is `docs/notes/development/observability/`, `RA` is `OBS/architecture/reference-architecture.md`, `A4`, `A5` and `A9` are ADR-004, ADR-005 and ADR-009 under `OBS/decisions/`, `CH` is `OBS/charter.md`, `S1` and `S3` are the archived changes `openspec/changes/archive/2026-10-18-stand-up-greptimedb-on-magnetite/` and `openspec/changes/archive/2026-10-21-stand-up-fleet-alerting/`, and `brief` is `logs/s1-evidence/s2brief.md`.

Inputs gathered for this brainstorm:

- `logs/s2/brainstorm-prep.md`: the design corpus read against S2, with contradictions C1 to C8, open decisions D1 to D11, the assets S2 reuses and the items carried over from S1 and S3.
- `brief`: ADR-005's envelopes, the gitea-mq messages at the pin and the nixbot schema facts, written 2026-10-17 and stale on the points C8 lists.
- The 18 questions of the prep's §5, each resolved by the operator on 2026-10-21; the decisions below record those resolutions.
- The S1 and S3 retrospectives' §6 rules (`S1/retrospective.md:130-181`; `S3/retrospective.md:140-188`).

## Grounding evidence

### What CAM-69 and the decision records ask for

- The three signals are per-attribute CI outcomes and per-build timing read from nixbot's PostgreSQL by the collector's `sqlquery` receiver, gitea-mq batch events parsed from its journal, and a deploy record appended at every activation (A5:48-50, A5:55-58).
- The regulators are the daily `devloop-reconcile`, the gating checks `devloop-queries` and `devloop-signals`, and the on-demand `devloop-ingest` (A5:144-152).
- CAM-69's acceptance: `devloop-reconcile` passes with per-build row counts matching nixbot and an overlap re-read adding no row; enqueue-to-land latency and per-build CI outcome excluding flaky attributes are queryable for the past week; a magnetite deploy yields exactly one deploy record, with other hosts following in S4 and S5.

### Contradictions found

- C1: CH:332 places the burn rule in S2 and says ADR-009 is unchanged, while ADR-009 item 15 says no CI or merge-queue rule is in the initial set (A9:91), and no document defines the rule's SLO, window, threshold or query.
- C2: CH:272 and RA:245 say S1 to S5 are metrics-only, but every S2 signal is a log row (A5:48-58; A4:129), and the main specs forbid a logs pipeline and a logs table (`telemetry-store-interface/spec.md:77`, `:116`; `host-metrics-collection/spec.md:12`); A4:107 also lists "any OTLP log record" as never stored.
- C3: CAM-69 gives the nixbot reader the `regulator` user, while ADR-005 authenticates the reader by peer with no credential and gives `regulator` to `devloop-reconcile`'s store reads (A5:78, A5:197-198).
- C4: CAM-69 asks for enqueue-to-land latency, but the five admitted batch messages carry no enqueue time; enqueue is the per-PR `enqueued PR` line, which neither A5:57 nor A4:58 admits, and no D5 rule reads it (brief:36-44; A5:63-71).
- C5: CAM-69 asks for CI outcome "excluding flaky attributes", but `flaky` is a per-batch boolean on `batch done`, and no attribute-level flakiness column exists (A4:102, A4:104).
- C6: CAM-69 lists "commit and outcome" in the deploy record, while ADR-005 records `{host, closure, previous_closure, ts}` and attributes the commit by joining the closure against CI `outputs.out` (A5:58, A5:69, A5:180, A5:206); an activation snippet runs before the switch completes, so it cannot record the switch's outcome.
- C7: A4:58 admits gitea-mq lines beginning `batch `, which also matches five further messages (CH:363), while A5:57 greps the five exact `msg` values (brief:37-42).
- C8: the brief's framing of the burn rule and its RA line numbers predate charter v17 to v21, and its premise, shared with A5:158, that no container-test pattern exists is stale, because S1 added the nspawn test `modules/vm-tests/greptimedb-pipeline.nix`, which runs on magnetite.

### What S1 and S3 provide

- The `devloop` database at 365 days, created by `greptimedb-schema`, with no table yet (`modules/clan/services/otel-collector/schema.nix:81-85`).
- The ingress role's `routing` connector, an `otlp_http/devloop` exporter, `basicauth/store`, the `file_storage` queue and infinite retry; the routing table and pipelines are `metrics/<db>` only (`modules/clan/services/otel-collector/flake-module.nix:350-433`).
- `devloop-reconcile.service` already on the collector's watched-unit list (`schema.nix:30`).
- The `regulator:ro` account with its credential-holder assertion, whose holders are `fleet-alert` and `greptimedb-envelope` (`modules/machines/nixos/magnetite/default.nix:642-669`).
- `observability-notify` with `services.observability-notify.units`, and R3.1's failure-wiring clause, which matches only S1's units (`modules/checks/otel-collector-config.nix:35-40`).
- The envelope's table scan over `devloop` base tables, which fails on `sst_format=primary_key` and on an undeclared table TTL (`modules/lib/greptimedb-envelope.nix:250-268`).
- The fleet evaluator with a fixed `database = "fleet"` and a fixture server that answers 400 to any other database (`modules/nixos/fleet-alert.nix:529`; `modules/checks/fleet-alert.nix:966`).
- The machine-check obligation hook, evaluated with each machine's toplevel (`modules/checks/machines.nix:33-45`).
- The nspawn container test on magnetite, run on demand (`modules/vm-tests/greptimedb-pipeline.nix:1-29`).
- The `flake.lock` pins: gitea-mq `02264515` and nixbot `b1f69980`, while the ADRs cite earlier revisions (A5:18, A5:31).

### Already resolved

- S1's retrospective asked S2 to drop "slice S4" from `Series cardinality stays bounded` (`S1/retrospective.md:178`); the main spec no longer contains the word "slice" (`openspec/specs/host-metrics-collection/spec.md:52-80`), so nothing remains to drop.

## Decision chain

Each decision below was resolved by the operator, 2026-10-21, accepting the recommendation of the prep's matching question.

### D1. The dev-loop SLO burn rule (C1)

Options: retire the rule and record D5-R4 as a weekly review query; a slow-burn rule on D5-R4's SLO; a multi-window burn rate, which at a few dozen PR builds a day is mostly noise `[INFERENCE]`.

Decision (operator, 2026-10-21): a 24 h slow-burn rule at severity `warning` on the SLO "at least 90% of PR builds start within 1 h" (A5:66, A5:222), firing when the trailing 24 h's share of PR builds that waited more than 1 h exceeds 10%, and silent below a minimum build count.
ADR-009 item 15 is amended to admit this one dev-loop rule.

- The minimum build count is left for design.
- The rule's state transitions land with a fixture timeline taken from a spec scenario before any reference-model change (`S3/retrospective.md:142-144`).

### D2. How the evaluator queries `devloop` (F10)

Options: per-rule `database` and `language` fields with SQL rules sent to `/v1/sql`; a GreptimeDB Flow materialising a metric-shaped table, which adds a store feature (`OBS/research/greptimedb.md:56`, `:210`); a `sqlquery` metrics-mode gauge at alpha stability (A5:124).

Decision (operator, 2026-10-21): each rule declares `database` and `language`; PromQL rules keep the PromQL endpoint, SQL rules go to `/v1/sql`, `promtool` renders only the PromQL rules, and the fixture server gains `/v1/sql` and a leg that queries both databases.
This absorbs S3's F10.

- PromQL cannot take `started_at - created_at` over log rows `[INFERENCE]`, so a header field alone would not serve the burn rule.

### D3. Admitting a non-content logs path in S2 (C2)

Decision (operator, 2026-10-21): CH:272, RA:245, A4:107 and the `telemetry-store-interface` spec are amended to admit a non-content `devloop` logs path in S2, through an explicit allow-list, with no message bodies stored.

- The journald `MESSAGE` body is dropped after parsing, because it is free text, and the nixbot queries select no `error` text (A5:73-74).
- The allow-list is enforced by an explicit SELECT column list and a keep-list for the parsed gitea-mq keys, both rendered from one `devloop` allow-list, and `devloop-queries` compares the queries' result columns with that list; the two values are defined independently, as `S1/retrospective.md:144-146` requires.
- The content stages and their regulator still arrive in S7 for content-bearing pipelines.

### D4. The logs ingress shape

Options: `logs/*` routes beside the metrics routes in the ingress role, with each S2 receiver stamping its database; a devloop-only path straight to `otlp_http/devloop`.

Decision (operator, 2026-10-21): `logs/*` pipelines route on the existing ingress connector, not a devloop-only side path.

- S4's deploy records from other hosts (CH:310) and S7's `fleet` journald logs reuse the same path.
- The local OTLP receiver stays out of every logs pipeline (`OBS/decisions/ADR-003-collection-topology.md:81`).

### D5. Table layout, keys and deduplication

Options: the default `opentelemetry_logs` table renamed per signal, probably append-mode so the five-minute overlap is not deduplicated `[INFERENCE]`; an ingest pipeline per table that declares A4:102-105's keys and time index; tables pre-created by `greptimedb-schema` with an explicit primary key, time index and `append_mode = 'false'`, fed by a pipeline.

Decision (operator, 2026-10-21): a container spike runs before the design fixes the table layout.
It writes the same `(build_id, attr, finished_at)` twice and reads one row back, and it establishes whether OTLP-with-pipeline writes into a pre-created table.

- The pre-created tables are chosen if deduplication holds under the non-`primary_key` SST format the envelope requires (`greptimedb-envelope.nix:250-251`); otherwise per-table ingest pipelines are.
- Tables inherit `devloop`'s 365 days, so `tableTtls` stays empty.
- For each new writer the design names the unit that creates its target table or pipeline and adds an ordering clause with a mutant (`S1/retrospective.md:136-138`).

### D6. The nixbot reader's credential (C3)

Decision (operator, 2026-10-21): the reader authenticates to PostgreSQL by peer with no credential, as ADR-005 states, and CAM-69's text is corrected accordingly; `regulator` is used only by `devloop-reconcile`'s store reads.

### D7. Enqueue-to-land latency (C4)

Decision (operator, 2026-10-21): CAM-69's enqueue-to-land latency is replaced by batch formation-to-land, the interval from a batch's `batch formed` to its `batch landed`, plus D5-R4's CI queue wait, `started_at - created_at` per PR build.
No `enqueued PR` line is admitted.

### D8. Flaky attributes (C5)

Decision (operator, 2026-10-21): an attribute is flaky in a window when one `drv_path` has differing outcomes within it; this is computed at query time with no stored column, and abandoned attributes are also excluded from the per-build CI outcome.

### D9. Deploy-record fields (C6)

Decision (operator, 2026-10-21): "commit and outcome" is dropped from CAM-69 in favour of ADR-005's fields `{host, closure, previous_closure, ts}` and its join of the closure against CI `outputs.out`.

### D10. Batch-line matching (C7)

Decision (operator, 2026-10-21): the journald receiver matches the five exact messages `batch formed`, `batch built`, `batch landed`, `batch bisecting` and `batch done`, and A4:58's prefix rule is amended to say so.

### D11. Identities and journal access

Decision (operator, 2026-10-21): `devloop-reconcile` runs as its own `DynamicUser` with a peer-authenticated nixbot PostgreSQL role and journal read, and the collector gains journal read for gitea-mq.

- `devloop-reconcile` becomes a `regulator-password` holder under magnetite's credential-holder assertion.
- `devloop-reconcile` is added to `services.observability-notify.units`, and R3.1's failure-wiring clause extends to it.

### D12. Deploy-record presence and rollout

Decision (operator, 2026-10-21): deploy-record presence is checked as an obligation in `modules/checks/machines.nix`, evaluated with each machine's toplevel, rather than by a check that evaluates all ten configurations, which would likely exceed the 0.5 GiB budget `[INFERENCE]`; ADR-005's deploy-record regulator wording is amended to say so.
The snippet is installed on all ten machines now, and only magnetite ships records until S4 and S5.

- The darwin and `scheelite` machine checks are best-effort or deferred (`machines.nix:6`; A5:28).
- The `filelog` receiver reads from the start of the file, so a host's buffered history ships when its collector arrives `[INFERENCE]`.

### D13. The `devloop-ingest` lane (C8)

Decision (operator, 2026-10-21): `devloop-ingest` is an on-demand nspawn container test on magnetite, following `greptimedb-pipeline`, rather than a QEMU VM test on pyrite, and ADR-005's Q13 premise is amended.

- Whether a specialisation switch works inside a container is unverified and is part of D5's spike `[INFERENCE]`.
- Every case touching ingest asserts the exporter's `send_failed` is zero after first start (`S1/retrospective.md:140-142`).

### D14. Reproducing nixbot's schema in `devloop-queries`

Decision (operator, 2026-10-21): the check applies the nixbot input's migrations in lexical order with `psql`, falling back to nixbot's own migrator if that does not reproduce the schema at `b1f69980`.

### D15. Cursor, overlap and volume

Decision (operator, 2026-10-21): no index is added to nixbot's database; the receiver polls every 60 s, and the scan is measured with `EXPLAIN ANALYZE` on magnetite at deploy.

- A five-minute overlap re-read at a 60 s poll re-emits each row about five times before deduplication, against A4:129's budget of 100,000 rows per day.

### D16. Pins and identifiers

Decision (operator, 2026-10-21): upstream line citations are re-cited at the `flake.lock` revisions, gitea-mq `02264515` and nixbot `b1f69980`, and ADR-005's envelopes are numbered E5.1 to E5.6, as ADR-009 numbers E9.x, through a charter version entry.

### D17. Plan review

Decision (operator, 2026-10-21): the holistic review's four questions run over `design.md` and `tasks.md`, and their findings are recorded, before Task 1 (`S1/retrospective.md:164-166`; `S3/retrospective.md:162-164`).

## Rules adopted from the S1 and S3 retrospectives

- Evaluation cost is measured with `NIX_SHOW_STATS=1 nix eval --raw .#.checks.x86_64-linux.<check>.drvPath` against 0.5 GiB, and the method is recorded with each figure (`S3/retrospective.md:154-156`; `S1/retrospective.md:148-150`).
- Each new clause names its two independently defined value sources before its mutant is written (`S3/retrospective.md:158-160`).
- Each `devloop-reconcile` clause names the container-test case that makes it fail (`S1/retrospective.md:152-154`).
- Format and lint run before every commit step (`S1/retrospective.md:156-158`).
- Tasks section 7 names the operator page and component README it updates, with how to query `devloop` (`S1/retrospective.md:160-162`).
- The designation rows proposed by S1's and S3's `verify.md` §8a are added to `world-assumptions` in S2's delta (`S1/retrospective.md:176-178`; `S3/retrospective.md:182-184`).
- The design lists the later slices that touch S2's objects and the rule each must keep: S4 ships deploy records through each host's agent (CH:310), S6 dashboards read `devloop` (RA:265), S7 adds `fleet` journald logs on the same logs path (RA:267), and S8 exports `devloop` (RA:275).

## Left for design

- The burn rule's minimum build count, its `for` duration and its query text.
- The table layout and keys, after D5's spike.
- The shape of the shared `devloop` allow-list and where it lives.
- The PostgreSQL roles' column grants for the collector and for `devloop-reconcile`.
- Which envelope rows of ADR-005 become E5.1 to E5.6, recorded in the charter entry.
- The memory and timeout envelope of `devloop-reconcile` and its timer schedule.
