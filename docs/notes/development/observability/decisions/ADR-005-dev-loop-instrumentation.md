---
title: "ADR-005: Dev-loop instrumentation"
---

## Status

Accepted (human gate, 2026-10-15)
Amended in place under charter v22 (2026-10-21), from slice S2's planning (`openspec/changes/stand-up-devloop-collection/`): upstream lines are cited at the `flake.lock` revisions, gitea-mq `02264515b` and nixbot `d020013fa`, every cited nixbot file being byte-identical to `b1f699803`'s; the envelopes are numbered E5.1 to E5.6; deploy-record presence is an obligation in `modules/checks/machines.nix`; `devloop-ingest` is an on-demand nspawn container test on magnetite, which amends Q13's premise; `devloop-reconcile` runs as its own `DynamicUser` with a peer-authenticated nixbot role and journal read; and, from slice S2's review (2026-10-22), E5.1's window is the previous UTC day, reconciled at 02:15 UTC, E5.4's regulator counts the journal's JSON entries per message with `jq`, and E5.3's marker clause carries no embedded negative control.

## Context

Charter R2 requires every development-loop signal to close onto a coverage-model decision rather than onto a chart, and C1 requires the smallest apparatus that closes that loop.
Under CCV, a coverage-model update is a change to a declared envelope or bin set caused by a runtime observation (charter Designations), so a signal is admitted here only if a named decision rule reads it.

The evidence base is `research/dev-loop-signals.md`, whose `## Refresh (2026-10-15)` supersedes its original findings where they conflict.
Most of the relevant data is already produced and merely uncollected.

The CI backend in service is nixbot, not buildbot-nix (`research/dev-loop-signals.md` RF1, RC3).
nixbot persists per-build rows (`commit_sha`, `branch`, `pr_number`, `status`, `created_at`, `started_at`, `finished_at`, `eval_duration_ms`) and per-attribute rows (`attr`, `system`, `drv_path`, `outputs`, `status`, boolean `cached`, `error`, `started_at`, `finished_at`, `eval_wall_ms`, `eval_alloc_bytes`) in its own PostgreSQL database (`Mic92/nixbot@d020013fa:nixbot/nixbot/migrations/0001_initial.sql:25-77`, `Mic92/nixbot@d020013fa:nixbot/nixbot/migrations/0027_eval_stats.sql:2-6`; `research/dev-loop-signals.md` RF2).
Those rows are deleted 90 days after the build finishes, and this repository does not override the default (`Mic92/nixbot@d020013fa:nixbot/nixbot/config.py:427-428`, `Mic92/nixbot@d020013fa:nixbot/nixbot/db_gen/maintenance.py:232-238`; `research/dev-loop-signals.md` RF3).
The same `retention_days` setting is documented upstream as the build and log retention horizon (`Mic92/nixbot@d020013fa:nixbot/nixbot/config.py:427`).
nixbot's `/metrics` endpoint carries only status-level gauges whose duration sums are recomputed over retained rows and fall when the prune runs, so per-attribute status, timing, cache and evaluation cost exist only as rows (`Mic92/nixbot@d020013fa:nixbot/nixbot/web/metrics.py:1-4`, `Mic92/nixbot@d020013fa:nixbot/nixbot/db_gen/web.py:636-639`; `research/dev-loop-signals.md` RF4).
nixbot also serves the same build and attribute columns through a JSON API under `/api`, which is unversioned and authenticates by bearer token (`Mic92/nixbot@d020013fa:nixbot/nixbot/web/api_routes.py:1-5`, `:67-115`).
Its build list pages by page number with status, branch, pull-request and commit filters but no completion cursor, and its `finished_after` cursor is scoped to a single build (`Mic92/nixbot@d020013fa:nixbot/nixbot/web/api_routes.py:233-263`, `:282-306`).
nixbot contains no OpenTelemetry or OTLP code at `Mic92/nixbot@d020013fa`.
Per-attribute evaluation cost reaches those rows from nix-eval-jobs `stats.wallMs` and `stats.allocBytes`, which locate outliers rather than giving exact cost because shared values are billed to the first attribute that forces them (`nixos/nix-eval-jobs@9f1553afa:README.md:139-145`; `research/dev-loop-signals.md` RF7, RC2).

Our local patch records an optional attribute abandoned after `optional_build_grace` as `ignored_failure` with the error text `not finished when the required attributes had settled`, so abandonment is distinguishable from a genuine ignored failure only by that text (`cameronraysmith/vanixiets@109c67346:modules/nixos/nixbot-abandon-optional-attributes.patch:138-152`; `research/dev-loop-signals.md` RF5).
Every `checks.aarch64-darwin` attribute is best-effort with `ignoreFailure = true` (`research/dev-loop-signals.md` RF6, RC5).

gitea-mq's `batches` table has no completion timestamp, and the `queue_entries` rows that hold PR numbers are deleted on dequeue (`research/dev-loop-signals.md` RF9).
Its batch lifecycle is logged through `slog`'s text handler as `batch formed`, `batch built`, `batch bisecting` (with `failed_check`), `batch landed` and `batch done` (with `landed`, `ejected`, `builds`, `flaky`) (`Mic92/gitea-mq@02264515b:internal/batch/batch.go:143`, `:228`, `:391`, `:328`, `:568`; `Mic92/gitea-mq@02264515b:cmd/gitea-mq/main.go:52`).
Five further messages begin `batch `, so a prefix match would admit them too (`Mic92/gitea-mq@02264515b:internal/batch/batch.go:302`, `:471`, `:473`, `:705`; `Mic92/gitea-mq@02264515b:internal/registry/registry.go:138`) (charter v22).
gitea-mq exposes no metrics surface (`research/dev-loop-signals.md` RF9; `research/fleet-emitter-inventory.md` R6).
Batch branches are named `gitea-mq/batch/<id>` (`Mic92/gitea-mq@02264515b:internal/merge/merge.go:18`, `Mic92/gitea-mq@02264515b:internal/batch/batch.go:30`), so nixbot's `builds.branch` already links every batch to its CI builds.

Deploys record no commit: `clan machines update` writes no deployment record, and `system.configurationRevision` is set nowhere in `modules/` (`research/dev-loop-signals.md` RF10, RC7).
Each machine's system toplevel is itself a flake check, `checks.<system>.nixos-<name>` or `darwin-<name>` (`cameronraysmith/vanixiets@02432c594:modules/checks/machines.nix:72-74`, `:79`), with `scheelite` deferred (`cameronraysmith/vanixiets@02432c594:modules/checks/machines.nix:6`), so nixbot's `build_attributes.outputs` already maps every CI-built toplevel store path to a `commit_sha`.
Both activation scripts run before `/run/current-system` is relinked, so an activation snippet can read the previous closure and knows the new one as `$systemConfig` (`NixOS/nixpkgs@ac1faec44836:nixos/modules/system/activation/activation-script.nix:55`, `:79`, root node `nixpkgs_10`; `nix-darwin/nix-darwin@4cff07de:modules/system/activation-scripts.nix:102`, `:140`, `:146`).

omp emits OTLP traces, logs and metrics natively over `http/protobuf` when an endpoint is set (`research/dev-loop-signals.md` RF11).
Its metrics include `omp.agent.tool.calls` labelled by `gen_ai.tool.name` and `omp.tool.status`, and `omp.agent.errors` labelled by `error.type` (`can1357/oh-my-pi@c2cb79e4c:packages/coding-agent/src/telemetry-export-otlp.ts:220-256`, `:300-305`).
Its log signal forwards free-form logger messages outside any content gate, and `OTEL_LOGS_EXPORTER=none` disables that signal (`research/dev-loop-signals.md` RF11, RC8; `can1357/oh-my-pi@c2cb79e4c:docs/environment-variables.md:659`).
Omnigent as packaged cannot export, because its SDK and exporters sit in the unpackaged `tracing` extra and a master switch `OMNIGENT_TELEMETRY_ENABLED` gates all export (`research/dev-loop-signals.md` RF12, RC1).

## Decision

The development loop emits four signal families, each bound to a declared coverage-model decision rule, and no upstream emitter is patched:

1. CI attribute outcomes, copied continuously from nixbot's PostgreSQL by magnetite's collector through the contrib `sqlquery` receiver, one log row per finished attribute joined to its build.
2. Merge-queue batch events, parsed from gitea-mq's journal by magnetite's collector through the `journald` receiver and the `key_value_parser` operator.
3. A deploy record, one JSON line per system activation written by an activation snippet on every machine and shipped by the collector of each host ADR-003 places in scope, with commit attribution obtained by joining the activated closure against signal 1.
4. omp tool-outcome metrics, `omp.agent.tool.calls` and `omp.agent.errors`, exported by omp itself to the host's collector, with omp's log signal disabled at the emitter.

| Signal | Source | Transport | Coverage decision fed | Retention |
|---|---|---|---|---|
| CI attribute outcome: `attr`, `system`, `status`, `cached`, derived `abandoned`, `drv_path`, `outputs.out`, `started_at`, `finished_at`, `eval_wall_ms`, `eval_alloc_bytes`, joined to build `commit_sha`, `branch`, `pr_number`, project name | nixbot `build_attributes` joined to `builds` and `projects` | magnetite collector `sqlquery` receiver, peer-authenticated SELECT over the local socket, cursor on `finished_at` held in `file_storage`, OTLP log rows into the `devloop` database (ADR-003) | D5-R1 lane partition, D5-R2 vacuity audit, D5-R3 evaluation-memory envelope, D5-R5 darwin best-effort disposition | nixbot rows 90 days, unchanged; store `devloop` 365 days (ADR-004); beyond that, ADR-006 |
| CI build timing: `created_at`, `started_at`, `finished_at`, `eval_duration_ms`, `status` per build | nixbot `builds` | same receiver, second query, cursor on `finished_at` | D5-R4 closure-operator throughput envelope | as above |
| Merge-queue batch event: `batch`, event name, `build`, `sha`, `failed_check`, `members`, `landed`, `ejected`, `builds`, `flaky`, journal timestamp | gitea-mq journal on magnetite | magnetite collector `journald` receiver, `units` = `gitea-mq.service`, `grep` on the five `msg` values, `key_value_parser`, cursor in `file_storage`, log rows into `devloop` | D5-R6 required-check and batching envelope | journal per host default; store `devloop` 365 days; beyond that, ADR-006 |
| Deploy record: `host`, `closure`, `previous_closure` (absent at boot), activation timestamp | activation snippet on every NixOS and darwin machine, appending to `/var/log/deploy-record.jsonl` | per-host collector `filelog` receiver with `json_parser` on ADR-003's in-scope hosts, log rows into `devloop` (ADR-003) | D5-R7 deploy attribution and out-of-band deploy | local file unbounded but one line per activation; store `devloop` 365 days; beyond that, ADR-006 |
| omp tool outcome: `omp.agent.tool.calls` by `gen_ai.tool.name` and `omp.tool.status`; `omp.agent.errors` by `error.type` | omp on human accounts | OTLP/HTTP metrics to `127.0.0.1:4318` on the same host, metric names allow-listed by ADR-004 and applied at the collector (ADR-003, ADR-008), into the `agent` database | D5-R8 harness-surface regulator | store `agent` 90 days (ADR-004) |

The decision rules each signal feeds are part of the decision, because R2 is satisfied by the rule and not by the series:

- D5-R1 lane partition: an attribute whose non-cached build duration, summed over pull-request builds in a 30-day window, exceeds its share of the per-pull-request budget, and which caught no failure that its scheduled run would not also have caught, moves to the scheduled lane or behind a canary-per-shape, which is the lever the 2026-09-02 audit computed once by hand (`research/dev-loop-signals.md` F18).
- D5-R2 vacuity audit: an attribute that recorded zero `failed` outcomes across at least 20 distinct `drv_path` values in 365 days is flagged for a mutation demonstration under the CCV integrity property, and is retired or strengthened if no mutant makes it fail.
- D5-R3 evaluation-memory envelope: an attribute whose `eval_alloc_bytes` rises above the 99th percentile of its own 30-day history for three consecutive builds is flagged for splitting or lane change, because evaluation overlap has OOM-killed magnetite twice (`research/fleet-emitter-inventory.md` R16).
- D5-R4 throughput envelope: if the 90th percentile of `started_at - created_at` for pull-request builds exceeds the declared queue-wait bound, the per-pull-request bin set is reduced through D5-R1 rather than by adding evaluators, since the evaluator is memory-bound (`research/dev-loop-signals.md` F17; `research/fleet-emitter-inventory.md` R16).
- D5-R5 darwin best-effort disposition: a `checks.aarch64-darwin` attribute abandoned in at least half of its builds over 30 days observes nothing and is either moved to the scheduled lane or recorded as an exemption with an owner and an expiry; one that completes and has never been abandoned or failed over the same window is proposed for promotion to required.
- D5-R6 required-check and batching envelope: the distribution of `failed_check` over `batch bisecting` events identifies which required context rejects merges, and a `flaky` rate above the hand-counted one in 27 multi-PR batches (`cameronraysmith/vanixiets@109c67346:modules/nixos/nixbot.nix:248-252`) is the trigger for carrying a patch for nixbot's supersede race; a rising mean of `builds` per `batch done` triggers review of the settle window and `batchMax`.
- D5-R7 deploy attribution: on ADR-003's in-scope hosts, a deploy is a record whose `closure` differs from the host's previous record; its commit is every `commit_sha` whose `nixos-<host>` or `darwin-<host>` attribute succeeded with that `outputs.out`, and a deploy with no such row is an activation outside the closure operator, which either adds the missing regulator or records an exemption with an owner and an expiry, as `scheelite`'s deferral would require.
  blackphos, rosegold and argentum run no collector until their primary users consent (ADR-003 Q3), so D5-R7 records each as an exemption owned by that machine's primary user and expiring when that user consents under ADR-003 Q3.
- D5-R8 harness-surface regulator: a tool whose `error` status share over 30 days exceeds its declared envelope, or whose `error.type` distribution gains a new class, is a candidate for a regulator of its own in `modules/checks/`.

The magnetite collector derives `abandoned` in its query as `status = 'ignored_failure' AND error = <marker>`, where `<marker>` is a single Nix value shared with a flake check over the patch text.
The query selects no free-form `error` text, so CI error messages do not reach the store.

## Rationale

Signals 1 and 2 already exist in structured form on magnetite, so collecting them costs receiver configuration on a collector that ADR-003 places there anyway, and costs no new process, no patch and no credential, because PostgreSQL's default `local all all peer` rule admits a role named after the collector's unit user (`NixOS/nixpkgs@ac1faec44836:nixos/modules/services/databases/postgresql.nix:693`, root node `nixpkgs_10`), the same coupling `modules/nixos/gitea-mq.nix` already relies on (`cameronraysmith/vanixiets@02432c594:modules/nixos/gitea-mq.nix:13-14`).
The `sqlquery` receiver supplies the two properties a periodic copy needs, an incremental cursor through `tracking_column` and persistence of that cursor across restarts through a `storage` extension (`open-telemetry/opentelemetry-collector-contrib@aaf5045a2:receiver/sqlqueryreceiver/README.md:79-82`, `:167-173`).
The `journald` receiver filters by unit and by `MESSAGE` regular expression and persists its cursor (`open-telemetry/opentelemetry-collector-contrib@aaf5045a2:receiver/journaldreceiver/README.md:41`, `:45`, `:47`), and `key_value_parser` handles the quoted values `slog` writes (`open-telemetry/opentelemetry-collector-contrib@aaf5045a2:pkg/stanza/operator/parser/keyvalue/parser_test.go:522`).
Copying rows within minutes of completion makes nixbot's 90-day prune irrelevant to history, which closes `research/dev-loop-signals.md` RQ1 without touching nixbot's log retention.

Web-verification D4 and D10 route the browser-evidence publisher through nixbot's `build_finished` event and its build API (`docs/notes/development/web-verification/decisions.md:23-27`, `:203`), so reading nixbot's database departs from that precedent, and the departure is recorded here with its reasons.
Those decisions serve one action per settled build, run by default-branch effect code holding a task token (`docs/notes/development/web-verification/decisions.md:206`), and need that build's recorded output, which the API supplies.
This signal instead needs every finished attribute of every build, in completion order, behind a cursor that survives restarts.
A `build_finished` effect would push one build at a time, so a failed or skipped effect run loses that build with no cursor to resume from, and the effect environment would have to hold a store write credential.
An API poller would have to walk the build list itself, because the only completion cursor is per build, and would hold its own cursor and bearer token, which is the rejected timer script with an HTTP client in place of `psql`; it would also receive the `error` text the store must not keep.
The API is unversioned, so it does not decouple collection from nixbot upgrades any more than the schema does, and `devloop-queries` makes schema drift fail at check time.
The PostgreSQL reader is therefore kept, for its single cross-build cursor, its peer authentication without a credential, and a query that selects no `error` text.

Joining CI rows by the batch branch name and by `commit_sha` reconstructs everything the gitea-mq `batches` table loses, so the journal is read only for the five facts that exist nowhere else: formation size, bisection with its failed check, landed and ejected counts, and `flaky`.

The deploy record is written at activation rather than by a deploy tool, so `clan machines update` on NixOS, `darwin-rebuild` on darwin and the `just activate*` recipes are all covered by one snippet, which answers the "deploy of record" half of `research/dev-loop-signals.md` RQ3 by making the question moot.
Commit attribution by joining the activated closure against CI `outputs` needs no change to any closure, and an activation that does not join is itself the coverage signal that a closure reached a machine without passing the closure operator.

omp's tool-outcome metrics need only environment variables on the emitting account, carry tool name, status and error class as bounded labels, and carry no content, so they meet D8's allow-list without redaction logic; `OTEL_LOGS_EXPORTER=none` removes the one ungated content path at the emitter, and ADR-003's local receiver, which has no logs pipeline, removes it a second time.

Each admitted signal names a rule that changes an envelope, a lane or a regulator, which is what distinguishes it from the chart-only signals rejected below.

## Rejected alternatives

- Patch nixbot to emit OTel natively: carries a Python patch against an input that moved 43 commits between the two research pins (`research/fleet-emitter-inventory.md` R7) to emit data already present as rows.
- Read nixbot's `/metrics` as the CI source: status-level gauges with no per-attribute dimension that fall when rows are pruned (`research/dev-loop-signals.md` RF4).
- Raise nixbot `retention_days`: also extends build-log retention on a storage-constrained host (W2) and leaves history in a database no dashboard reads.
- A systemd timer running `psql` into GreptimeDB: a second process, a second cursor and a second store credential duplicating what the collector receiver already provides.
- A nixbot `build_finished` effect pushing each build's attributes to the store, following web-verification D4: no cursor across builds, so a failed effect run is a permanent gap, and a store write credential in the effect environment.
- Polling nixbot's `/api` build and attribute endpoints, following web-verification D10: no cross-build completion cursor, a bearer token and a client-side cursor to hold, and `error` text in every attribute (`Mic92/nixbot@d020013fa:nixbot/nixbot/web/api_routes.py:95-115`, `:233-263`).
- Patch gitea-mq to emit metrics or OTel: carries a Go patch to restate five log lines that are already structured.
- `sqlquery` over gitea-mq's `batches` table: no completion time, out-of-order completion defeats an id cursor, and the failed check is absent (`research/dev-loop-signals.md` RF9).
- `system.configurationRevision = self.rev`: substitutes the revision into `nixos-version` (`NixOS/nixpkgs@ac1faec44836:nixos/modules/installer/tools/tools.nix:59`, root node `nixpkgs_10`), so every commit changes every machine's toplevel and no-op commits become deploys, and dirty trees carry no revision.
- Record deploys in the `just activate*` recipes or a `clan` wrapper: covers one deploy path and misses the other.
- `nix-fast-build --result-file` from `just check-fast`: deferred, because with darwin built in CI (`research/dev-loop-signals.md` RC5) local runs feed no rule that CI rows do not, and shipping them adds a laptop-side file path for other people's machines (Q6).
- Omnigent OTLP export: deferred, because it needs the `tracing` extra packaged plus worker environment that the fleet obligation keeps empty (`research/telemetry-security-and-tenancy.md` R21) (Q5).
- omp spans: deferred, because `error.type` on `omp.agent.errors` already gives the failure class D5-R8 reads.
- omp logs: rejected under W9, because the log body is ungated and string-body redaction fails open (`research/telemetry-security-and-tenancy.md` R25, R26).
- omp token and cost metrics: not admitted, because no coverage decision reads them (Q7).
- Untraced-artifact count, bin saturation, mutation-kill rate and the exemption ledger as telemetry: these are meta-check derivations of the CCV half (charter S2) that consume D5 signals, not signals to emit.
- Raw check-attribute count and harness turn latency: chart-only, rejected under C1 (`research/dev-loop-signals.md` ranked items 15 and 16).

## Consequences

The CI history in the store becomes the only copy older than 90 days, so a gap in the copy is unrecoverable once nixbot prunes, which is why the reconciliation regulator below runs daily.
The receiver's queries are coupled to nixbot's schema, so a nixbot input bump that renames a column breaks collection; the gating `devloop-queries` check below builds the schema from the nixbot input's own migrations so that this coupling fails at check time.
The `sqlquery` receiver's logs mode is at development stability and its metrics mode at alpha (`open-telemetry/opentelemetry-collector-contrib@aaf5045a2:receiver/sqlqueryreceiver/metadata.yaml:10-11`), and the collector distribution must be contrib (`research/otel-collector-topology.md` C7).
The gitea-mq parse is coupled to upstream log message text, which no schema protects, so only the runtime cross-check against batch-branch builds detects a silent rename.
A cursor on `finished_at` re-emits an attribute whenever a restart re-finishes it, which records retries as distinct outcomes.
A row whose transaction commits after the cursor has passed its `finished_at` would be skipped, so each query re-reads a five-minute overlap behind the cursor and relies on ADR-004 keying the table on `(build_id, attr)` with `finished_at` as time index, so that GreptimeDB's default deduplication of non-append tables collapses the re-read rows `[INFERENCE]`; the reconciliation counts distinct `(build_id, attr, finished_at)` either way.
Every activation, including each NixOS boot, appends a line, and consumers treat a record whose `previous_closure` is absent as a boot rather than a deploy.
Deploys of `scheelite` never join a CI row while it stays deferred, so D5-R7 reports it as out-of-band until its exemption is owned or its check restored.
omp telemetry on omnigent worker accounts is not collected in this slice, because ADR-008 gives no omnigent worker account an OTLP endpoint or credential, and the ACP row passes no environment through to omp (`cameronraysmith/vanixiets@02432c594:modules/clan/services/omnigent/README.md:35`).
Unbounded identifiers (`commit_sha`, `pr_number`, `drv_path`, store paths, build ids) appear only on log rows, never as metric labels, which conforms to ADR-004's label ban.

Assumptions this decision depends on:

- ADR-003 runs the contrib collector as the NixOS module's `opentelemetry-collector` unit on magnetite with a `file_storage` extension, a per-host collector on each of its in-scope hosts (the six NixOS machines and stibnite) with an OTLP/HTTP receiver on `127.0.0.1:4318` wired to metrics and traces only, a `filelog` receiver on the deploy-record file, and the `journald` receiver over an allow-listed unit set that includes `gitea-mq`.
- ADR-004 provides the `devloop` database with a 365-day TTL and the `agent` database with a 90-day TTL, and owns the `devloop` column allow-list, primary key and time index of each event table, keying the CI attribute table on `(build_id, attr)` with `finished_at` as time index.
- ADR-006 exports the `devloop` event tables to Parquet before their TTL expires, which is the only path to CI history older than one year.
- ADR-004 admits the two omp metric names on its metric-name allow-list, which ADR-008's redaction stage applies.
- ADR-007 defines the `regulator:ro` store user in its `greptimedb-users` generator, as which the reconciliation job reads the store.
- ADR-003 defines the `observability-notify@%n.service` ntfy notifier that the reconciliation job's `OnFailure=` triggers.

## Operating envelope and regulator

| Artifact | Declared envelope | Regulator | Shown able to fail by |
|---|---|---|---|
| E5.1 nixbot export queries in the magnetite collector | every `build_attributes` row with `finished_at` in the previous UTC day, which closes 2 h 15 min before the reconcile runs at 02:15 UTC, appears once in `devloop`, distinct on `(build_id, attr, finished_at)`; every finished build likewise (charter v22) | `devloop-reconcile` daily timer on magnetite, which compares both sides' keys over that day and exits non-zero on any unexplained difference, surfacing as a failed unit | `vmTests.x86_64-linux.devloop-ingest`, run on demand on magnetite, running the reconcile job against a collector whose query omits `cached = true` rows, and requiring a non-zero exit |
| E5.2 nixbot schema coupling | the export queries execute against the schema the pinned nixbot input creates | flake check `devloop-queries`, a derivation without a VM that starts PostgreSQL in the build sandbox through nixpkgs' `postgresqlTestHook` (`NixOS/nixpkgs@ac1faec44836:pkgs/by-name/po/postgresqlTestHook/postgresql-test-hook.sh:57`, `:71`, root node `nixpkgs_10`), applies the nixbot input's `nixbot/nixbot/migrations` in lexical order, inserts fixture builds and attributes, and runs the two export queries with the shared abandonment marker, asserting their rows including `abandoned` | an in-check fixture migration renaming `cached`, which must make the queries fail; applying the migrations in lexical order reproduces nixbot's schema `[INFERENCE]`, and if it does not the check runs nixbot's own migration code from the input instead |
| E5.3 `abandoned` derivation | the marker the query matches is byte-identical to the error text in `nixbot-abandon-optional-attributes.patch` | flake check `devloop-queries` asserting the shared Nix marker occurs in the patch's production code, the added line between `return AttributeStatus.ignored_failure, (` and `if outcome == BuildOutcome.abandoned` (charter v22) | no embedded negative control: one evaluating the assertion with a mutated marker, or over the patch's test lines alone, re-tests only the substring search, so the clause matches the production context directly (charter v22) |
| E5.4 gitea-mq journal parse | each `batch done` journal line yields one row with integer `landed`, `ejected`, `builds` and boolean `flaky`; any 24-hour window containing a nixbot build on a `gitea-mq/batch/` branch contains at least one `batch built` row | `devloop-reconcile`, counting the day's `gitea-mq.service` journal entries per message with `jq` over `journalctl --output=json`, comparing the counts with store rows and checking the cross-signal liveness condition (charter v22) | `vmTests.x86_64-linux.devloop-ingest`, run on demand on magnetite, running a stub `gitea-mq` unit that prints fixture lines, with a mutant collector config lacking `key_value_parser` that must fail; no gating check exercises the parser, so the liveness condition is the runtime guard against both a config regression and an upstream message rename that fixtures cannot see |
| E5.5 deploy-record activation snippet | every machine in the inventory appends one valid JSON line per activation with `host`, `closure` and, outside boot, `previous_closure` | an obligation in `modules/checks/machines.nix` asserting the snippet is in the machine's activation, evaluated with each machine's toplevel, whose darwin checks are best-effort and whose `scheelite` check is deferred, so CI gates it on the five x86_64-linux NixOS machines (`modules/checks/machines.nix:6`, `:33-45`) (charter v22), plus `devloop-reconcile` asserting magnetite's latest stored record equals its current system | the obligation's negative control over a configuration without the module (charter v22); on demand, `vmTests.x86_64-linux.devloop-ingest` switching a test node between two specialisations and requiring exactly one new line naming both closures |
| E5.6 `devloop-reconcile` itself | runs daily and fails on any envelope breach above | the mutants of `vmTests.x86_64-linux.devloop-ingest`, run on demand on magnetite, each of which must make it exit non-zero | itself: a reconcile job that passes every mutant is rejected under RK8 |
| omp emitter configuration | human-account sessions export metrics only, `OTEL_LOGS_EXPORTER=none` is set, and no content-capture variable is set | flake check `devloop-signals` over the evaluated home configuration's session variables, plus `devloop-reconcile` asserting at least one `omp.agent.tool.calls` sample in the last seven days | the check's negative control with `OTEL_LOGS_EXPORTER` removed |

The envelopes slice S2 realizes are numbered E5.1 to E5.6 (charter v22).
The omp emitter row is left unnumbered and listed last, because slice S7, not S2, realizes the omp emitter (reference architecture, Implementation sequencing).

`devloop-reconcile` samples one host of ten for the deploy record, and this envelope declares that limit rather than claiming fleet coverage; the other nine are covered at build time only.
A failed `devloop-reconcile` unit notifies a human through `OnFailure=observability-notify@%n.service`, the ntfy notifier ADR-003 defines (ADR-003 Q9).

`devloop-ingest` is a systemd-nspawn container test exported under `vmTests` from `modules/vm-tests/`, outside pull-request gating, following S1's `greptimedb-pipeline`, which runs the store and both collector roles in one container on a builder advertising `uid-range` (`modules/vm-tests/greptimedb-pipeline.nix:1-29`; `modules/README.md:32`, `:56-57`, `:62`) (charter v22).
magnetite, which builds `checks.x86_64-linux`, has no KVM but advertises `uid-range` (`modules/machines/nixos/magnetite/default.nix:106`, `:109-113`; `modules/clan/inventory/services/nix-builders.nix:32`, `:41`), so `devloop-ingest` runs on magnetite (charter v22).
Whether a specialisation switch works inside a container is unverified `[INFERENCE]`, and slice S2's container spike settles it before the deploy-record case relies on it (charter v22).
The gating regulators are therefore the build-time check `devloop-queries`, joined by `devloop-signals` for the omp emitter in S7, and the deploy-record obligation in `modules/checks/machines.nix`, and `devloop-ingest` is on-demand evidence, not coverage (`modules/README.md:68`) (charter v22).
The reconcile job's own fallibility and the gitea-mq parser are shown only by `devloop-ingest`, so a change to either is run against it on magnetite before merge (charter v22).

## Failure prevented

- CI attribute export: loss of per-attribute CI history at nixbot's 90-day prune, which would leave D5-R1 to D5-R5 recomputable only by hand as in the 2026-09-02 audit.
- `abandoned` derivation: darwin best-effort checks that never complete being counted as ordinary ignored failures, which hides vacuous regulators from D5-R5.
- CI build timing: a per-pull-request bin set that silently exceeds the evaluator's throughput, measured once at 3 h 08 m of queue wait and never since (`research/dev-loop-signals.md` F17).
- Merge-queue batch events: a flaky or rejecting required context going unnoticed because its evidence exists only in rotated journal text and in rows that lose PR identity.
- Deploy record: an incident on a machine that cannot be attributed to a closure or a commit, and a closure activated without ever passing the closure operator going unnoticed.
- omp tool outcomes: a harness tool failing repeatedly across sessions without any regulator being proposed for it.
- omp log disablement: prompt or repository content reaching the store through the one omp signal that has no emitter-side gate.
- `devloop-reconcile`: a collection gap that becomes permanent once the source prunes or the journal rotates.
- Flake check `devloop-queries`: a nixbot input bump that breaks the export queries without failing the closure operator.
- `vmTests.x86_64-linux.devloop-ingest`: a collector-config or gitea-mq change that breaks collection end to end, caught when the test is run rather than at merge.

## Implementation surface

Files to add:

- `modules/nixos/devloop-collection.nix`: magnetite-only contributions to ADR-003's collector settings, namely the two `sqlquery` queries, the gitea-mq `journald` receiver with its `key_value_parser` operator, routing to the `devloop` database, the shared abandonment marker, the `opentelemetry-collector` PostgreSQL role with column-level `SELECT` on nixbot's `builds`, `build_attributes` and `projects`, and the `devloop-reconcile` service and timer, the service reading `regulator-password` from ADR-007's generator and setting `OnFailure=observability-notify@%n.service` (ADR-003).
  The collector gains read access to gitea-mq's journal, and `devloop-reconcile` runs as its own `DynamicUser` with its own peer-authenticated nixbot PostgreSQL role and journal read; it is a `regulator-password` holder under magnetite's credential-holder assertion and a unit in `services.observability-notify.units` (charter v22).
- `modules/system/deploy-record.nix`: `flake.modules.nixos.deploy-record` as a `system.activationScripts` entry and `flake.modules.darwin.deploy-record` as a `system.activationScripts.postActivation` addition, each appending `{host, closure, previous_closure, ts}` to `/var/log/deploy-record.jsonl` at mode 0644, following the two-platform shape of `modules/system/zt-dns.nix`.
- `modules/checks/devloop-signals.nix`: eval-time check for the omp session variables with an embedded negative control, added with the omp emitter in S7; the abandonment-marker clause lives in `devloop-queries` (charter v22), and deploy-record presence is an obligation in `modules/checks/machines.nix` instead, evaluated with each machine's toplevel (charter v22).
- `modules/checks/devloop-queries.nix`: `checks.x86_64-linux.devloop-queries`, a derivation using `postgresqlTestHook` that applies the nixbot input's migrations, loads fixtures and runs the two export queries rendered from the same Nix values as `devloop-collection`, with the renamed-column mutant.
- `modules/vm-tests/devloop-ingest.nix`: `perSystem.vmTests.devloop-ingest`, a systemd-nspawn container test requiring `uid-range`, run on demand on magnetite, with PostgreSQL, GreptimeDB, the collector, a stub `gitea-mq` unit and the reconcile job, including the mutants listed above, following `modules/vm-tests/greptimedb-pipeline.nix` (charter v22).

Files to modify:

- `modules/machines/nixos/magnetite/default.nix`: import `devloop-collection`, and add `devloop-reconcile` to the `regulator-password` holders and to `services.observability-notify.units` (charter v22).
- The NixOS and darwin machine aggregates that import fleet-wide `modules/system/` modules: import `deploy-record` on all ten machines.
- `modules/checks/machines.nix`: the deploy-record obligation, evaluated with each machine's toplevel (charter v22).
- `modules/home/ai/omp/default.nix`: set `OTEL_EXPORTER_OTLP_METRICS_ENDPOINT` to the local collector, `OTEL_TRACES_EXPORTER=none`, `OTEL_LOGS_EXPORTER=none`, `OTEL_EXPORTER_OTLP_PROTOCOL=http/protobuf` and `OTEL_SERVICE_NAME=omp` in the human-account session variables only.

Files deliberately not modified: `justfile` (Q6), `pkgs/by-name/omnigent/package.nix` and the omnigent modules (Q5), `nixbot.toml`, and the nixbot and gitea-mq patches (Q2).

Flake inputs: none added; `nixbot` and `gitea-mq` are existing inputs, and `devloop-queries` and `devloop-ingest` read the `nixbot` input's migrations directory.

Clan vars generators and sops entries:

- No PostgreSQL credential, because the collector's reader and `devloop-reconcile` both authenticate by peer (charter v22).
- No store credential generator: of this decision's units only `devloop-reconcile` reads the store, as the `regulator:ro` user that ADR-007's `greptimedb-users` generator defines, through its `regulator-password` secret file; the collector's nixbot reader holds no `regulator` credential (charter v22).

## Questions for the human gate

Q1. Keep CI history beyond nixbot's 90 days by copying rows into `devloop` within minutes? Recommended: yes, with ADR-006 beyond 365 days; the alternative of raising `retention_days` also lengthens build-log retention on magnetite and keeps history out of the dashboard.
Resolution: recommended answer accepted at the 2026-10-15 gate.
Q2. Make abandonment a distinct nixbot status in our patch? Recommended: no, keep the error-text marker under the `devloop-queries` equality check; the alternative extends the local patch into nixbot's aggregation, forge-status and UI handling of statuses.
Resolution: recommended answer accepted at the 2026-10-15 gate.
Q3. Record deploys at activation and attribute commits by joining closures against CI outputs, leaving `system.configurationRevision` unset? Recommended: yes; the alternative makes every commit change all ten toplevels.
Resolution: recommended answer accepted at the 2026-10-15 gate.
Q4. Disable omp's log signal at the emitter while ADR-003's local receiver also has no logs pipeline? Recommended: yes; the alternative needs string-body redaction that fails open.
Resolution: recommended answer accepted at the 2026-10-15 gate.
Q5. Package Omnigent's `tracing` extra and enable its export now? Recommended: defer to ADR-008, which in this slice gives no omnigent worker account an OTLP endpoint or credential and reserves `OTEL_` in the worker environment; enabling export requires revising ADR-008.
Resolution: recommended answer accepted at the 2026-10-15 gate.
Q6. Add `--result-file` to `just check-fast` and ship local results? Recommended: no, until a rule needs data CI rows lack; the alternative adds a shipped file on laptops including other people's.
Resolution: recommended answer accepted at the 2026-10-15 gate.
Q7. Admit omp token and cost metrics? Recommended: no; admitting them requires naming the decision they feed, such as planning-unit sizing, which the human would commit to making from them.
Resolution: recommended answer accepted at the 2026-10-15 gate.
Q8. Accept the `sqlquery` receiver at development stability for logs? Recommended: yes, under `devloop-reconcile`, the gating `devloop-queries` check and the on-demand `devloop-ingest`; the alternative is the rejected timer script with its own credential and cursor.
Resolution: recommended answer accepted at the 2026-10-15 gate.
Q9. Which store user does `devloop-reconcile` use? Answered by ADR-007: the shared `regulator:ro` user of the read-only regulators, kept separate from the dashboard's `perses:ro` credential so their rotation and holders stay decoupled.
Resolution: recommended answer accepted at the 2026-10-15 gate.
Q10. Adopt the starting thresholds of D5-R1 to D5-R8 (30-day windows, 20 distinct `drv_path` values, the 99th percentile for three builds, half of builds abandoned)? Recommended: yes as initial envelopes revised by the same coverage-model loop; without numbers each rule degrades to a chart.
Resolution: recommended answer accepted at the 2026-10-15 gate.
Q11. Should D5-R4's queue-wait bound be one hour at the 90th percentile? Recommended: yes, as one third of the 3 h 08 m measured worst case; a looser bound lets the per-pull-request bin set grow unchecked.
Resolution: recommended answer accepted at the 2026-10-15 gate.
Q12. Read nixbot's PostgreSQL directly, departing from web-verification D4 and D10, which route the evidence publisher through nixbot's events and API? Recommended: yes, because the copy needs one cursor across all builds, which neither the `build_finished` effect nor the API provides; the alternative is a per-build effect or API poller holding its own cursor and credential.
Resolution: recommended answer accepted at the 2026-10-15 gate.
Q13. Accept that the collector end-to-end path, the gitea-mq parser and the reconcile job's mutants are shown only by the on-demand `vmTests.x86_64-linux.devloop-ingest`? Recommended: yes, while no gating container-test pattern exists and magnetite lacks KVM; the alternative is to establish a gating nspawn check on magnetite's `uid-range`, which this repository has not yet done.
Resolution: recommended answer accepted at the 2026-10-15 gate.
Premise amended under charter v22: S1's `greptimedb-pipeline` established an on-demand systemd-nspawn container test on magnetite (`modules/vm-tests/greptimedb-pipeline.nix:1-29`), so `devloop-ingest` follows it and runs on magnetite instead of a KVM-capable host; it stays on demand, and no gating container test is established.
