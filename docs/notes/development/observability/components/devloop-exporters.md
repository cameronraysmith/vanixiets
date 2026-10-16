---
title: "devloop-exporters"
---

## Purpose

The devloop-exporters component collects the four development-loop signal families of ADR-005 into the store without patching any upstream emitter.
They are CI attribute outcomes and build timing read from nixbot's PostgreSQL, merge-queue batch events parsed from gitea-mq's journal, a deploy record written at every system activation, and omp tool-outcome metrics (ADR-005 Decision).
Each signal feeds a named coverage-model decision rule, D5-R1 to D5-R8, rather than a chart (ADR-005; charter R2).
The component also runs the daily `devloop-reconcile` regulator and the build-time checks that bind the collection queries to nixbot's schema.

## Decisions realized

- ADR-005 signal 1: CI attribute outcomes, copied continuously from nixbot's PostgreSQL by magnetite's collector through the contrib `sqlquery` receiver, one log row per finished attribute joined to its build and project, into `devloop`.
- ADR-005 signal 1, second query: CI build timing per build, cursor on `finished_at`, into `devloop`.
- ADR-005 signal 2: gitea-mq batch events from the `journald` receiver with `units` set to `gitea-mq.service`, a `grep` on the five `msg` values and the `key_value_parser` operator, into `devloop`.
- ADR-005 signal 3: a deploy record appended to `/var/log/deploy-record.jsonl` at every activation on all ten machines and shipped by the `filelog` receiver with `json_parser` on ADR-003's in-scope hosts, into `devloop`.
- ADR-005 signal 4: omp exports `omp.agent.tool.calls` and `omp.agent.errors` to the host's collector, with its log and trace signals disabled at the emitter, into `agent`.
- ADR-005 `abandoned` derivation: the query computes `abandoned` as `status = 'ignored_failure' AND error = <marker>`, where `<marker>` is one Nix value shared with a flake check over `nixbot-abandon-optional-attributes.patch`, and selects no `error` text (ADR-005 Q2).
- ADR-005 Q3: deploys are recorded at activation and attributed to commits by joining the activated closure against CI `outputs.out`, with `system.configurationRevision` left unset.
- ADR-005 Q12: nixbot's database is read directly, departing from web-verification D4 and D10, for one cursor across all builds.
- ADR-004: the `devloop` column allow-list, primary key and time index per table, the omp metric-name and key allow-lists, and the label bans that keep `commit_sha`, `pr_number`, `drv_path`, store paths and build ids on log rows only.
- ADR-008 emitter posture: omp runs with `OTEL_LOGS_EXPORTER=none` and without `OTEL_INSTRUMENTATION_GENAI_CAPTURE_MESSAGE_CONTENT`; ADR-008 content stage 6 keeps only allow-listed `devloop` columns.
- ADR-007: `devloop-reconcile` reads the store as the `regulator` (`ro`) user.

## Placement

- magnetite, inside the `opentelemetry-collector.service` agent that ADR-003 places there: the two `sqlquery` queries and the gitea-mq `journald` receiver, from `modules/nixos/devloop-collection.nix` (ADR-005 Implementation surface).
- magnetite, PostgreSQL: a role `opentelemetry-collector` with column-level `SELECT` on nixbot's `builds`, `build_attributes` and `projects`, admitted by the default `local all all peer` rule because it is named after the collector's unit user (ADR-005 Rationale; `NixOS/nixpkgs@ac1faec44836:nixos/modules/services/databases/postgresql.nix:693`, root node `nixpkgs_10`).
- magnetite: `devloop-reconcile.service` and its daily timer (ADR-005).
- Every machine in the inventory: the deploy-record activation snippet, `flake.modules.nixos.deploy-record` as a `system.activationScripts` entry and `flake.modules.darwin.deploy-record` as a `system.activationScripts.postActivation` addition (ADR-005 Implementation surface).
- ADR-003's in-scope hosts, the six NixOS machines and stibnite: the local agent's `filelog` receiver on `/var/log/deploy-record.jsonl` (ADR-003 item 4; ADR-005).
- Human accounts only: omp's session variables in `modules/home/ai/omp/default.nix` (ADR-005).
- No omnigent worker account receives an OTLP endpoint or credential (ADR-008 emitter posture item 3).

## Interfaces

- nixbot PostgreSQL, local socket, peer authentication, `SELECT` over `builds`, `build_attributes` and `projects`; cursor on `finished_at` through `tracking_column`, persisted in `file_storage`, re-reading a five-minute overlap behind the cursor (ADR-005; `open-telemetry/opentelemetry-collector-contrib@aaf5045a2:receiver/sqlqueryreceiver/README.md:79-82`, `:167-173`).
- gitea-mq journal on magnetite, cursor in `file_storage`, messages `batch formed`, `batch built`, `batch bisecting`, `batch landed` and `batch done` (`Mic92/gitea-mq@9bad60d8f:internal/batch/batch.go:143`, `:228`, `:328`, `:391`, `:568`).
- `/var/log/deploy-record.jsonl`, mode 0644, one JSON line `{host, closure, previous_closure, ts}` per activation, `previous_closure` absent at boot (ADR-005).
- omp, OTLP/HTTP `http/protobuf` metrics to the agent's `127.0.0.1:4318`, with `OTEL_SERVICE_NAME=omp` (ADR-005).
- Downstream: the local agent's pipelines, then the ingress on magnetite, into the `devloop` and `agent` databases; see `components/otel-collector.md` and `components/greptimedb.md`.
- Downstream beyond 365 d: the daily Parquet export of `devloop` event tables (ADR-006); see `components/parquet-export.md`.
- `devloop-reconcile` reads `journalctl -u gitea-mq --grep`, nixbot's PostgreSQL and the store at `127.0.0.1:4000` (ADR-005; ADR-007).

Stored tables (ADR-004 `devloop` column allow-list):

| Signal | Columns | Primary key | Time index |
|---|---|---|---|
| CI attribute outcome | `build_id`, `attr`, `system`, `status`, `cached`, `abandoned`, `drv_path`, `outputs.out`, `started_at`, `finished_at`, `eval_wall_ms`, `eval_alloc_bytes`, `commit_sha`, `branch`, `pr_number`, `project` | `(build_id, attr)` | `finished_at` |
| CI build timing | `build_id`, `created_at`, `started_at`, `finished_at`, `eval_duration_ms`, `status` | `(build_id)` | `finished_at` |
| Merge-queue batch event | `batch`, `msg`, `build`, `sha`, `failed_check`, `members`, `landed`, `ejected`, `builds`, `flaky` | `(batch, msg)` | journal timestamp |
| Deploy record | `host`, `closure`, `previous_closure`, `ts` | `(host)` | `ts` |

omp metrics in `agent`: `omp.agent.tool.calls` by `gen_ai.tool.name` and `omp.tool.status`, and `omp.agent.errors` by `error.type`, with the point keys of ADR-004's omp allow-list (ADR-004; ADR-005).

Coverage decisions fed (ADR-005):

- D5-R1 lane partition, D5-R2 vacuity audit, D5-R3 evaluation-memory envelope and D5-R5 darwin best-effort disposition read CI attribute outcomes.
- D5-R4 throughput envelope reads CI build timing, with the queue-wait bound at one hour at the 90th percentile (ADR-005 Q11).
- D5-R6 required-check and batching envelope reads batch events.
- D5-R7 deploy attribution reads deploy records joined to CI `outputs.out`.
- D5-R8 harness-surface regulator reads omp tool outcomes.

Credentials consumed:

- No PostgreSQL credential, because the reader authenticates by peer (ADR-005).
- `regulator-password` of ADR-007's `greptimedb-users` generator, read by `devloop-reconcile` (ADR-005; ADR-007).
- The `regulator` (`ro`) user is held by `otel-envelope`, `devloop-reconcile`, `greptimedb-envelope` and `fleet-alert.service` (ADR-007; ADR-009 item 1).
- omp holds no credential; the local receiver is unauthenticated loopback (ADR-003 Consequences).

## Configuration surface

Files to add (ADR-005 Implementation surface):

- `modules/nixos/devloop-collection.nix`: the two `sqlquery` queries, the gitea-mq `journald` receiver with `key_value_parser`, routing to `devloop`, the shared abandonment marker, the `opentelemetry-collector` PostgreSQL role with column-level `SELECT`, and `devloop-reconcile` service and timer reading `regulator-password` and setting `OnFailure=observability-notify@%n.service`.
- `modules/system/deploy-record.nix`: the NixOS and darwin activation snippets, following the two-platform shape of `modules/system/zt-dns.nix`.
- `modules/checks/devloop-signals.nix`: eval-time checks for the abandonment marker, deploy-record presence on every machine and the omp session variables, each with an embedded negative control.
- `modules/checks/devloop-queries.nix`: `checks.x86_64-linux.devloop-queries`, using `postgresqlTestHook`, applying the nixbot input's migrations, loading fixtures and running the two export queries rendered from the same Nix values as `devloop-collection`, with the renamed-column mutant.
- `modules/vm-tests/devloop-ingest.nix`: `perSystem.vmTests.devloop-ingest`, a NixOS VM test requiring `kvm`, with PostgreSQL, GreptimeDB from `pkgs.greptimedb`, the collector, a stub `gitea-mq` unit and the reconcile job with its mutants, following `modules/vm-tests/omnigent-worker-isolation.nix`.

Files to modify:

- `modules/machines/nixos/magnetite/default.nix`: import `devloop-collection` (ADR-005).
- The NixOS and darwin machine aggregates that import fleet-wide `modules/system/` modules: import `deploy-record` on all ten machines (ADR-005).
- `modules/home/ai/omp/default.nix`: in human-account session variables only, `OTEL_EXPORTER_OTLP_METRICS_ENDPOINT` to the local collector, `OTEL_TRACES_EXPORTER=none`, `OTEL_LOGS_EXPORTER=none`, `OTEL_EXPORTER_OTLP_PROTOCOL=http/protobuf` and `OTEL_SERVICE_NAME=omp` (ADR-005; ADR-008).
- `modules/clan/services/otel-collector/schema.nix`: the `devloop` column allow-list and the omp metric-name and key allow-lists (ADR-004).

Files deliberately not modified: `justfile`, `pkgs/by-name/omnigent/package.nix` and the omnigent modules, `nixbot.toml`, and the nixbot and gitea-mq patches (ADR-005).

Flake inputs: none added; `nixbot` and `gitea-mq` are existing inputs, and `devloop-queries` and `devloop-ingest` read the `nixbot` input's migrations directory (ADR-005).

Clan vars generators: none created; `devloop-reconcile` consumes `regulator-password` from `greptimedb-users` (ADR-005; ADR-007).

## Operating envelope and regulator

Envelopes and regulators (ADR-005):

| Artifact | Envelope | Regulator |
|---|---|---|
| nixbot export queries | every `build_attributes` row with `finished_at` in a closed 24-hour window ending one hour ago appears once in `devloop`, distinct on `(build_id, attr, finished_at)`; every finished build likewise | `devloop-reconcile`, daily on magnetite, counting both sides and exiting non-zero on any difference |
| nixbot schema coupling | the export queries execute against the schema the pinned nixbot input creates | flake check `devloop-queries` |
| `abandoned` derivation | the marker is byte-identical to the error text in `nixbot-abandon-optional-attributes.patch` | flake check `devloop-signals` |
| gitea-mq journal parse | each `batch done` line yields one row with integer `landed`, `ejected`, `builds` and boolean `flaky`; any 24-hour window containing a nixbot build on a `gitea-mq/batch/` branch contains at least one `batch built` row | `devloop-reconcile`, comparing `journalctl -u gitea-mq --grep` counts with store rows and checking the cross-signal liveness condition |
| deploy-record snippet | every machine appends one valid JSON line per activation with `host`, `closure` and, outside boot, `previous_closure` | `devloop-signals` over every `nixosConfigurations` and `darwinConfigurations` activation text, plus `devloop-reconcile` asserting magnetite's latest stored record equals its current system |
| omp emitter configuration | human-account sessions export metrics only, `OTEL_LOGS_EXPORTER=none` is set, and no content-capture variable is set | `devloop-signals` over the evaluated home configuration, plus `devloop-reconcile` asserting at least one `omp.agent.tool.calls` sample in the last seven days |
| `devloop-reconcile` itself | runs daily and fails on any envelope breach above | the mutants of `vmTests.x86_64-linux.devloop-ingest`, run on demand on a KVM-capable host |

- `devloop-reconcile` samples one host of ten for the deploy record; the other nine are covered at build time only (ADR-005).
- The gating regulators are `devloop-queries` and `devloop-signals`; `devloop-ingest` is on-demand evidence on a KVM-capable builder such as pyrite, not coverage (ADR-005 Q13).
- Volume: `devloop` at most 100,000 rows per day with 365 d retention, and `agent` at most 2,000 active series with `gen_ai.tool.name` at most 200 values and 90 d retention (ADR-004).
- A failed `devloop-reconcile` notifies through `OnFailure=observability-notify@%n.service`, which posts once per failure episode and once on recovery (ADR-003 Q9; ADR-009 item 11).
- The `devloop` column allow-list is also enforced at runtime by R8.3 in `otel-envelope` (ADR-008).

## Failure prevented

- CI attribute export: per-attribute CI history is lost at nixbot's 90-day prune, leaving D5-R1 to D5-R5 recomputable only by hand (ADR-005).
- `abandoned` derivation: darwin best-effort checks that never complete are counted as ordinary ignored failures, which hides vacuous regulators from D5-R5 (ADR-005).
- CI build timing: a per-pull-request bin set silently exceeds the evaluator's throughput (ADR-005).
- Merge-queue batch events: a flaky or rejecting required context goes unnoticed because its evidence exists only in rotated journal text (ADR-005).
- Deploy record: an incident cannot be attributed to a closure or a commit, and a closure activated without passing the closure operator goes unnoticed (ADR-005).
- omp tool outcomes: a harness tool fails repeatedly across sessions without a regulator being proposed for it (ADR-005).
- omp log disablement: prompt or repository content reaches the store through omp's ungated log signal (ADR-005; ADR-008).
- No `error` text selected: CI error messages reach the store (ADR-005).
- `devloop-reconcile`: a collection gap becomes permanent once the source prunes or the journal rotates (ADR-005).
- `devloop-queries`: a nixbot input bump breaks the export queries without failing the closure operator (ADR-005).
- `devloop-ingest`: a collector-config or gitea-mq change breaks collection end to end, caught when the test is run (ADR-005).

## Deployment acceptance items

- `devloop-ingest`, run on a KVM-capable host, makes `devloop-reconcile` exit non-zero against a collector whose query omits `cached = true` rows, and against a mutant collector config lacking `key_value_parser` (ADR-005).
- `devloop-ingest` switches a test node between two specialisations and finds exactly one new deploy-record line naming both closures (ADR-005).
- A reconcile job that passes every `devloop-ingest` mutant is rejected under charter RK8 (ADR-005).
- GreptimeDB's default deduplication of non-append tables collapses the rows re-read in the five-minute overlap, which ADR-005 records as `[INFERENCE]`; `devloop-reconcile` counts distinct `(build_id, attr, finished_at)` either way (ADR-005 Consequences).
- Applying the nixbot input's migrations in lexical order reproduces nixbot's schema, which ADR-005 records as `[INFERENCE]`; if it does not, `devloop-queries` runs nixbot's own migration code from the input instead (ADR-005).
- magnetite's latest stored deploy record equals its current system, and at least one `omp.agent.tool.calls` sample exists within seven days of deploy (ADR-005).
- At least one `batch built` row appears in any 24-hour window containing a nixbot build on a `gitea-mq/batch/` branch, which is the only guard against an upstream rename of gitea-mq's log messages (ADR-005 Consequences).

## Deferred

- Omnigent OTLP export: deferred until its package carries the `tracing` extra and ADR-008 is revised to give worker accounts an OTLP endpoint (ADR-005 Q5; ADR-004 Q5; ADR-008 Q3).
- omp spans: not wired; trigger is ADR-005 asking for them, at which point `gen_ai.conversation.id` rows enter `agent` under the same allow-list (ADR-004 Q3; ADR-005).
- omp token and cost metrics: not admitted; trigger is naming the decision they feed, such as planning-unit sizing (ADR-005 Q7).
- `nix-fast-build --result-file` from `just check-fast`: not added; trigger is a rule needing data that CI rows lack (ADR-005 Q6).
- A gating container test on magnetite's `uid-range` for the end-to-end path: not established; `devloop-ingest` stays on demand while no gating container-test pattern exists and magnetite lacks KVM (ADR-005 Q13).
- blackphos, rosegold and argentum: D5-R7 records each as an exemption owned by its primary user, expiring when that user consents under ADR-003 Q3 (ADR-005).
- `scheelite`: its deploys never join a CI row while its machine check stays deferred, so D5-R7 reports it as out-of-band until its exemption is owned or its check restored (ADR-005 Consequences).
- CI history beyond 365 d: only through the Parquet export of ADR-006 (ADR-004; ADR-005).
