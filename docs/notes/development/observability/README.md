---
title: Fleet observability documentation map
---

# Fleet observability documentation map

This tree holds the design work for a fleet observability platform and the continuous-feedback loop that consumes it.
It is a design corpus, not an implementation: nothing here is deployed, and no module, collector, store or dashboard exists in `modules/` today.

Read [charter.md](charter.md) first, because every artifact below is scoped by its world assumptions W1 through W9 and answers to its decision list D1 through D9.

## Current status

The charter is at v22, which records slice S2's planning decisions for dev-loop collection: ADR-009 admits one dev-loop rule, a 24 h slow-burn `warning` when more than 10% of pull-request builds wait over 1 h to start, and lets each rule name its database and query language with SQL over `/v1/sql`; S2 adds a non-content logs path into `devloop` through an explicit allow-list; ADR-004 admits the five exact gitea-mq batch messages; and ADR-005 cites upstream at the `flake.lock` revisions, numbers its envelopes E5.1 to E5.6, makes deploy-record presence a machine-check obligation, runs `devloop-ingest` as a container test on magnetite and gives `devloop-reconcile` its own identity.
v21 records the dispositions of S3's remaining review findings and schedules ADR-009 Q5 as CAM-76, which blocks S5.
v20 amends ADR-009 item 16 so that an always-on host, magnetite alone in S3, that reports no host memory for 10 min while the store answers raises `RuleSignalMissing` with its `host_name`.
v19 corrects v18's cost evidence: measured with `.#.checks…`, `checks.fleet-alert` costs 0.252 GiB at S3's Task 4 and 0.453 GiB at its Task 5, and both it and `checks.greptimedb-envelope` were under budget before v18's move, which stands on S1's review F5 principle that relations within one host belong in its module assertions.
v18, which moves slice S3's host-local relations, the `alerter` token's wiring and R7.1's memory ceilings and kill order, from flake checks into module and host assertions shown able to fail by `extendModules` overrides, keeping `checks.fleet-alert` at 0.36 GiB and `checks.greptimedb-envelope` at 0.484 GiB of evaluation, and adds a machine to a shared var with `clan vars fix` rather than `clan vars generate`.
v17 records slice S3's planning decisions for alerting: ntfy rate-limits each mesh client as its own visitor, the `alerter` token reaches curl through `ntfy-send`'s `NTFY_TOKEN_FILE` and never its argument list, the failure notifier becomes its own module that cinnabar imports for the dead-man, the cutover takes three deploys with no refused publish, a flake check validates ntfy's provisioning strings, S3 ships only the rules S1's signals feed, `SystemdUnitFailed` excludes exactly the notified units, and a property-based test checks the evaluator's transition function.
v16 records the rest of the S1 holistic review: S1's evaluation-time regulators keep only clauses that relate independently defined values, properties of one module's own settings become assertions in that module, R8.2's credential holders become an assertion on magnetite that saves about 1.6 GiB of evaluation per run, the failure-wiring clause requires every store, disk-share and collector unit to notify, and the pipeline container test shows the envelope's table clause failing against the real store.
v15 records three further findings of the same review: tables allowed a TTL of their own are declared in `services.greptimedb.tableTtls` and the hourly envelope fails on any other table TTL, the collector schema's database map is the one source of magnetite's databases and their TTLs, and S4 chooses the agent's exporter by role because only a co-located ingress receives from the in-process `forward` connector.
v14 records three defects the same review found: the failure notifier now ends an episode on a unit's next successful start, so automatic restarts no longer silence later failures, R7.2 regulates throttling and anonymous memory instead of the page-cache-inclusive `memory.peak`, and `ntfy-send` carries curl on Linux.
v13 keeps Prometheus remote read and write enabled on the store, because GreptimeDB `v1.2.1` registers the PromQL query API only together with them (`GreptimeTeam/greptimedb@179ff8e50:src/frontend/src/server.rs:130-158`).
v12 records the corrections found while S1's implementation plan was written: credential freshness compares the sha256 of the users file the store loaded with a public hash, R7.2 holds its baseline across store restarts, zerotierone's metrics key is `enableMetrics`, the owner-to-alias attrset is named with its values, and `ntfy-send` becomes the package S1 adds.
v11 records the amendments slice S1 carries: the dashboard layer is the Perses dashboard GreptimeDB embeds, served behind `sso-gateway` from slice S6, the store package is `greptimedb-bin` because its release tarball embeds that dashboard, gRPC is bound to loopback, and the failure notifier lands in S1.
v10 re-cut implementation into the vertical slices S1 to S8, and v9 recorded the human gate of 2026-10-15: every decision record is Accepted, and acceptance criteria A5, A6 and A8 are discharged as recorded human judgment.
v8 reconciled the decision records the same day with conventions already decided elsewhere in the repository: implementation proceeds through OpenSpec changes following the `openspec/changes/stand-up-*` precedent, and R2 storage follows web-verification D9.
v7 extended the charter the same day with decision D9 on alerting after the human approved host-level signals and an alerting decision; v6 recorded the GreptimeDB 1.2.1 nixpkgs bump, v5 revised the charter for consistency with the decision records, v4 followed the research refresh the same day, and v2 followed the research phase on 2026-09-18.
The research phase is complete: eight artifacts under [research/](research/) cover the store, the dashboard layer, the collection topology, the rejected store alternatives, the fleet's existing emitters, the development-loop signal set, the Nix packaging position, and telemetry access control.
Each artifact ends with a `## Refresh (2026-10-15)` section that re-reads its sources at current revisions and supersedes its stale claims; where the findings below conflict with a refresh section, the refresh wins.
Decisions D1 through D9 each have a decision record under [decisions/](decisions/) at status Accepted (human gate, 2026-10-15); ADR-009 is Accepted except its Q5, which is deferred to CAM-76, scheduled before S5 (charter v21).
The gate accepted the recommended answer of every question in every record, with ADR-002 Q6 answered as `perses.scientistexperience.net` behind Kanidm and ADR-003 Q15 as SMART on pyrite and stibnite, and each question line records its resolution; charter v11 amended ADR-002 Q2 and superseded ADR-002 Q1, Q7 and Q8.
The `architecture/` and `components/` trees that charter deliverable S1 names are listed in the map below; acceptance criterion A1 is satisfied once those files exist.
ADR-006 now places the store and the lakehouse export in the existing R2 bucket `sciexp` under `projects/vanixiets/observability/store/` and `projects/vanixiets/observability/export/`, following web-verification D9, in place of the two dedicated buckets it first proposed.
ADR-003 and ADR-004 now also cover host-level signals, each tied to a failure this fleet has had: bounded per-process metrics for the `magnetite` OOM kills of 2026-09-27 and 2026-10-01, systemd unit state and restart counts for the two omnigent-host units that restart-looped about 3,200 times overnight on 2026-10-15 (recorded in `docs/notes/development/incidents/2026-10-15-omnigent-host-restart-loop.md` and cited by ADR-009), and ZFS pool and ARC state, with NVMe SMART on `pyrite` and `stibnite`, for `magnetite`'s storage-starvation history.
Continuous profiling, laptop battery, thermal and sleep-wake state, and per-host ZeroTier peer latency and path state are documented in the "Future extensions (not adopted)" subsection of ADR-003's Decision, each with the trigger that would justify adopting it and what it would require.
No implementation work has begun; it proceeds through OpenSpec changes, and charter constraint C4 keeps this tree planning-only.
Roughly thirty-six questions were carried to the human gate rather than answered by inference, per the charter's standing rule; they are aggregated below.

## Documentation map

| Document | Path | Question it answers |
|---|---|---|
| Charter | [charter.md](charter.md) | What is being designed, under what world assumptions, against which requirements, and which nine decisions it requires |
| GreptimeDB as observability store | [research/greptimedb.md](research/greptimedb.md) | What the leading store candidate can actually do: engines, OTLP ingest paths, query surfaces, SST layout, deployment floor, and where the open/enterprise line falls |
| Perses as dashboard layer | [research/perses.md](research/perses.md) | Whether the packaged Perses can query the candidate store, what dashboards-as-code costs, and what its CLI validates |
| Collection topology decision space | [research/otel-collector-topology.md](research/otel-collector-topology.md) | Per-host agent versus central gateway for this fleet's shape, what a nix-darwin host can run, which transport and ingress paths exist, and the volume budget |
| Rejected store alternatives | [research/store-alternatives.md](research/store-alternatives.md) | Why SigNoz, the Grafana assembly, the VictoriaMetrics family, OpenObserve and ClickHouse-direct are disfavored, and where each beats the leading candidate |
| Fleet emitter inventory | [research/fleet-emitter-inventory.md](research/fleet-emitter-inventory.md) | What each deployed service can emit today without code changes, and which documented failures are candidate service-level indicators |
| Dev-loop signals | [research/dev-loop-signals.md](research/dev-loop-signals.md) | Which development-loop signals exist, which are missing, and which coverage-model decision each one feeds |
| Nix packaging status | [research/nix-packaging-status.md](research/nix-packaging-status.md) | Which candidate is packaged where, which NixOS and nix-darwin modules exist, and the routes to a GreptimeDB derivation |
| Telemetry security and tenancy | [research/telemetry-security-and-tenancy.md](research/telemetry-security-and-tenancy.md) | What agent-session telemetry carries, where redaction can be enforced, and what the store, the dashboard layer and the mesh do and do not authorize |
| Decision records | [decisions/](decisions/) | Where each of D1 through D9 is recorded, one decision per file, per charter S1 |
| ADR-001: store (D1) | [decisions/ADR-001-store.md](decisions/ADR-001-store.md) | Which system durably holds telemetry and answers queries over it |
| ADR-002: dashboard layer (D2) | [decisions/ADR-002-dashboard-layer.md](decisions/ADR-002-dashboard-layer.md) | Which dashboard layer renders the store's signals, and in which as-code format |
| ADR-003: collection topology (D3) | [decisions/ADR-003-collection-topology.md](decisions/ADR-003-collection-topology.md) | How telemetry travels from emitters to the store, and how transport is authenticated |
| ADR-004: signal scope and schema (D4) | [decisions/ADR-004-signal-scope-and-schema.md](decisions/ADR-004-signal-scope-and-schema.md) | Which signals exist, under which conventions, and within which cardinality and retention budget |
| ADR-005: dev-loop instrumentation (D5) | [decisions/ADR-005-dev-loop-instrumentation.md](decisions/ADR-005-dev-loop-instrumentation.md) | What the development loop emits, and which coverage-model decision each signal feeds |
| ADR-006: storage substrate and lakehouse seam (D6) | [decisions/ADR-006-storage-substrate-and-lakehouse-seam.md](decisions/ADR-006-storage-substrate-and-lakehouse-seam.md) | Where telemetry lands durably, and whether the DuckDB and DuckLake analytics path can read it |
| ADR-007: packaging, placement and clan service (D7) | [decisions/ADR-007-packaging-placement-and-clan-service.md](decisions/ADR-007-packaging-placement-and-clan-service.md) | How each component is packaged, which host runs it, and what shape its clan service takes |
| ADR-008: access control and tenancy (D8) | [decisions/ADR-008-access-control-and-tenancy.md](decisions/ADR-008-access-control-and-tenancy.md) | Who may write and read which telemetry, and how the prompt-content hazard is contained |
| ADR-009: alerting (D9) | [decisions/ADR-009-alerting.md](decisions/ADR-009-alerting.md) | How fleet conditions become human notifications, including watching the store itself |
| Reference architecture | [architecture/reference-architecture.md](architecture/reference-architecture.md) | How the accepted decisions compose into one fleet design, per charter S1 |
| Component: GreptimeDB | [components/greptimedb.md](components/greptimedb.md) | How the store is placed, configured and regulated (ADR-001, ADR-006 store side, ADR-007) |
| Component: Parquet export | [components/parquet-export.md](components/parquet-export.md) | How the daily `devloop` Parquet export reaches R2 and its DuckDB readers (ADR-006) |
| Component: Perses | [components/perses.md](components/perses.md) | How the dashboard layer is placed, configured and regulated (ADR-002, ADR-008 read side) |
| Component: fleet-alert | [components/fleet-alert.md](components/fleet-alert.md) | How the alert evaluator, dead-man and ntfy delivery work (ADR-009, ADR-003 notifier) |
| Component: OpenTelemetry Collector | [components/otel-collector.md](components/otel-collector.md) | How per-host agents, `magnetite` ingress, the darwin root process collector and redaction are configured (ADR-003, ADR-004, ADR-008) |
| Component: host probes | [components/host-probes.md](components/host-probes.md) | How loopback node_exporter, the smartctl exporter and the darwin `otel-host-probe` launchd job supply host signals (ADR-003, ADR-004) |
| Component: dev-loop exporters | [components/devloop-exporters.md](components/devloop-exporters.md) | How nixbot PostgreSQL rows, gitea-mq journal events, deploy records and omp metrics enter `devloop` (ADR-005) |
| Omnigent host restart-loop incident | [../incidents/2026-10-15-omnigent-host-restart-loop.md](../incidents/2026-10-15-omnigent-host-restart-loop.md) | What failed when the omnigent-host units restart-looped on 2026-10-15 without any alert, which is the detection gap ADR-009 closes |

## Findings that change the design

These are the cross-artifact conclusions a reader needs before opening any ADR.
Each is traceable to an artifact and its finding numbers.

### 1. Emission is not zero, and three unauthenticated metrics endpoints already exist

Charter v1 claimed nothing was emitted; that is false.
`gitea`, `nixbot` and `niks3` each serve a Prometheus `/metrics` endpoint with no authentication (`research/fleet-emitter-inventory.md` F9).
Their vhosts served those endpoints over public TLS until #3447 restricted them to loopback and the ZeroTier mesh range on 2026-10-15 (charter W3).
zerotierone and nginx `stub_status` also emit on loopback, and omp is a native OpenTelemetry emitter that this repository does not yet configure (charter W3).
Only nixbot's endpoint carries an upstream-declared containment property, aggregating by status and never labelling by project (`research/fleet-emitter-inventory.md` F10).
The accurate statement is zero collection over emitters that are already live, and the charter's W3 is corrected to say so.

### 2. The non-metric signals are constrained at ingest, and their rendering is unexercised

At the ingest end, GreptimeDB registers no standard OTLP gRPC trace or logs service; the only OpenTelemetry gRPC service is an OTel-Arrow metrics service, so a collector must use the HTTP exporter for logs and traces, and the trace handler accepts protobuf only (`research/greptimedb.md` F12, F13, F14, corroborated by `research/otel-collector-topology.md` F25).
At the rendering end, Perses 0.54.0's default plugin set and the nixpkgs vendored set at `nixpkgs_10` contain the GreptimeDB plugin 0.1.0 with `GreptimeDBLogQuery` and `GreptimeDBTraceQuery`, which the stock log and trace panels render (charter RK7; `research/perses.md` refresh R3, R5, R12).
That log and trace path has not been exercised against a live GreptimeDB, and the trace query maps result columns by name (charter RK7; `research/perses.md` refresh R8).
Metrics are the exception in both directions: a stock `PrometheusDatasource` pointed at `/v1/prometheus` matches GreptimeDB's Prometheus router on every path and method the plugin uses (`research/perses.md` F17, F18, F19, F20).
The native GreptimeDB plugin is SQL-based rather than PromQL-based (`research/perses.md` F14, F21).

### 3. The store authenticates but does not authorize, and unauthenticated is its default state

With no user provider configured, GreptimeDB's HTTP layer assigns a default user and returns before any credential check, so an open ingress is the default rather than a misconfiguration (`research/telemetry-security-and-tenancy.md` F31).
With a provider configured, both open-build user providers implement `authorize` as an explicit allow-all, the only enforced lever is a per-user `rw`, `ro` or `wo` mode, and the table-target `PermissionChecker` trait has no in-tree implementation beyond that default and test doubles (`research/telemetry-security-and-tenancy.md` F27, F28, F29).
Schema is caller-supplied through a request header, so a schema-per-person layout is expressible but is a label rather than a boundary (`research/telemetry-security-and-tenancy.md` F30).
Transport authentication is HTTP Basic against a static credential file; bearer-token authentication fails as unsupported in the open build, which closes off reusing Kanidm tokens for machine ingress (`research/telemetry-security-and-tenancy.md` F33).
The same axis is the sharpest evidence in the rejected set, where SigNoz places authentication, authorization and audit under its enterprise licence and OpenObserve ships only compilation stubs for its single-sign-on and fine-grained-authorization crates (`research/store-alternatives.md` F15, F34, F35).

### 4. The store's Parquet is externally readable only conditionally

SSTs are real Parquet written with a standard Arrow writer, carrying the full region metadata as Parquet key-value metadata (`research/greptimedb.md` F21, F22).
Readability depends on the format: the legacy format collapses tag columns into one opaque `__primary_key` blob, while the newer flat format stores raw primary-key columns and is the default at the read revision, selectable per table through an `sst_format` option (`research/greptimedb.md` F23, F24, F25, F26).
Even under the flat format a correct external read is not a `read_parquet` glob: the live file set must come from the per-region manifest, and updates and deletes must be resolved through `__sequence` and `__op_type` (`research/greptimedb.md` F27).
Two rejected candidates beat the leading stack on exactly this axis, Tempo writing `vParquet4` blocks and OpenObserve writing Parquet as its only durable format, which the rejected-alternatives artifact asks to be carried into D6 explicitly rather than absorbed into D1 (`research/store-alternatives.md` F20, F31).

### 5. Two of the regulators this design would reach for are tautologically green

`percli lint` without `--plugin.path` and without `--online` returns early, validates nothing beyond what unmarshalling enforces, skips custom lint rules, and still prints a success message, identically at the packaged version (`research/perses.md` F48, F49, F50).
On the continuous-verification side, the traceability and adequacy properties cannot be computed at all, because the repository declares no artifact manifest and no bin set, and no meta-check for either exists (`research/dev-loop-signals.md` F9, F10, F11).
Integrity evidence does exist, as mutant-asserting checks over the omnigent environment oracle and the worker launcher, but the mutants are embedded in assertions rather than enumerated as data, so no kill rate is derivable (`research/dev-loop-signals.md` F12).
Any dashboard or coverage regulator proposed in an ADR therefore has to be demonstrated to fail on a mutant before it is accepted.

### 6. The packaging position is not where the charter's risk framing put it

`greptimedb` 1.1.4 is present at the repository's root nixpkgs pin `nixpkgs_10` and substituted from cache.nixos.org, although the nixpkgs build omits the embedded web dashboard (charter W5; `research/nix-packaging-status.md` refresh R2, R4, R6).
Upstream also ships checksummed Linux and Darwin release tarballs across its six most recent releases, so a from-source build is not forced into the critical path (`research/nix-packaging-status.md` F15).
What remains is module work rather than derivation work: no GreptimeDB NixOS module exists at the pin or on `master`, no third-party flake supplies one, and nix-darwin ships no OpenTelemetry Collector, Vector or Alloy module at the locked revision, so a first-party launchd module is unavoidable for whichever collector is chosen (`research/nix-packaging-status.md` F17, F25, F27, corroborated by `research/otel-collector-topology.md` F8).
Citations into nixpkgs must name the lock node, because `flake.lock` holds six distinct nixpkgs tarball nodes and none is a git checkout; the root input resolves to `nixpkgs_10` (charter W4).

## Decision status

All nine decisions are Accepted at the human gate of 2026-10-15, ADR-009 with its Q5 deferred to CAM-76, before S5.
The bearing column names the artifacts that supply evidence for that decision, not a recommendation.

| Decision | Subject | Status | Bearing artifacts |
|---|---|---|---|
| D1 | Store, including the open/enterprise boundary and single-node versus clustered | Accepted ([ADR-001](decisions/ADR-001-store.md)) | `greptimedb.md`, `store-alternatives.md`, `nix-packaging-status.md`, `telemetry-security-and-tenancy.md`, `perses.md` |
| D2 | Dashboard layer, its as-code format, and datasource reachability | Accepted ([ADR-002](decisions/ADR-002-dashboard-layer.md)) | `perses.md`, `telemetry-security-and-tenancy.md`, `store-alternatives.md`, `nix-packaging-status.md` |
| D3 | Collection topology, transport authentication, and ingress | Accepted ([ADR-003](decisions/ADR-003-collection-topology.md)) | `otel-collector-topology.md`, `fleet-emitter-inventory.md`, `dev-loop-signals.md`, `telemetry-security-and-tenancy.md`, `nix-packaging-status.md`, `greptimedb.md` |
| D4 | Signal scope, schema, cardinality and retention budgets | Accepted ([ADR-004](decisions/ADR-004-signal-scope-and-schema.md)) | `fleet-emitter-inventory.md`, `dev-loop-signals.md`, `otel-collector-topology.md`, `greptimedb.md`, `telemetry-security-and-tenancy.md`, `perses.md` |
| D5 | Dev-loop instrumentation and the coverage-model decision each signal feeds | Accepted ([ADR-005](decisions/ADR-005-dev-loop-instrumentation.md)) | `dev-loop-signals.md`, `fleet-emitter-inventory.md` |
| D6 | Storage substrate and the lakehouse seam | Accepted ([ADR-006](decisions/ADR-006-storage-substrate-and-lakehouse-seam.md)) | `greptimedb.md`, `store-alternatives.md`, `dev-loop-signals.md` |
| D7 | Packaging, host placement, and clan service shape | Accepted ([ADR-007](decisions/ADR-007-packaging-placement-and-clan-service.md)) | `nix-packaging-status.md`, `greptimedb.md`, `otel-collector-topology.md`, `fleet-emitter-inventory.md`, `store-alternatives.md`, `telemetry-security-and-tenancy.md`, `perses.md` |
| D8 | Access control and tenancy, including the prompt-content hazard | Accepted ([ADR-008](decisions/ADR-008-access-control-and-tenancy.md)) | `telemetry-security-and-tenancy.md`, `fleet-emitter-inventory.md`, `greptimedb.md`, `perses.md`, `store-alternatives.md`, `otel-collector-topology.md`, `dev-loop-signals.md` |
| D9 | Alerting, including watching the store itself | Accepted, except Q5, deferred to CAM-76 before S5 ([ADR-009](decisions/ADR-009-alerting.md)) | `greptimedb.md`, `fleet-emitter-inventory.md`, `perses.md` |

## Open questions for the human gate

Grouped and deduplicated from the eight artifacts' own questions sections.
Each is attributed to the artifact that raised it; where two artifacts raised the same question it is listed once with both attributions.

### Scope and consent

- Is in-database alerting wanted at all, given that trigger DDL is enterprise-gated and external alerting is therefore the open-build answer (`greptimedb.md` Q1), answered by ADR-009, which evaluates rules outside the store through a timer that queries `/v1/prometheus` and posts to ntfy.
- Are the three darwin machines belonging to other people in scope as telemetry subjects at all (`otel-collector-topology.md`)?
- Are `cognee` and `k3s-server` intended to be deployed, or retained as unimported definitions, since that decides whether they enter the D4 scope (`fleet-emitter-inventory.md` Q4)?
- Is re-enabling the disabled `sso-gateway` on `magnetite` in scope, or must the dashboard layer work with it disabled (`telemetry-security-and-tenancy.md` Q4), settled by charter v11: ADR-002 admits dashboard readers through the gateway, so S6 enables it.
- Is bumping the root nixpkgs pin in scope, or must the design assume the current pin (`nix-packaging-status.md` question 1), settled because the pin has since been bumped to `nixpkgs_10`, and since charter v11 the store comes from `greptimedb-bin` rather than the pin (ADR-001 Decision).
- Is darwin continuous-integration coverage in scope, or is the local-run channel the accepted permanent answer for four of ten machines (`dev-loop-signals.md` Q4)?

### Store selection and versions

- Is a prerelease store version acceptable as a fleet dependency, or must the design pin the most recent stable tag and re-verify the findings against it (`greptimedb.md` Q4)?
- Is the flownode that standalone starts unconditionally acceptable under the anti-ceremony constraint, or does it argue for the distributed shape with flownode omitted (`greptimedb.md` Q3)?
- Does the governance constraint disqualify single-vendor stores as such, or only those whose open build is materially crippled, since the leading candidate has the same control structure as the two the charter disfavors (`greptimedb.md` Q5)?
- Should the paid-tier access-control finding be applied as a hard admissibility filter rather than as one axis among several, and if so must the same filter be applied to the leading candidate (`store-alternatives.md` Q5)?
- Was the `openobserve` version nixpkgs builds actually Apache-2.0 licensed, or is its declared licence stale relative to an upstream relicence, since the answer decides admissibility (`store-alternatives.md` Q1)?
- Does the charter's W4 nixpkgs claim resolve against the root input or the transitive node, raised by `store-alternatives.md` and answered by charter v2 W4, which fixes the root input and requires every citation to name its lock node.

### Storage substrate and the lakehouse seam

- Does the seam mean external DuckDB reads of the store's own SST files in place, or a scheduled Parquet export into DuckLake (`greptimedb.md` Q2, `store-alternatives.md` Q4)?
- Is Tempo's `vParquet4` block layout a usable lakehouse seam, or does the seam require a single store rather than a per-signal Parquet surface (`store-alternatives.md` Q3)?

### Dashboard layer

- Does the dashboard layer have to render logs and traces from the chosen store, or are metrics-only dashboards acceptable for the first deployment (`perses.md`)?
- Should the design target the packaged 0.54.0 or the 0.55 line (`perses.md`), carried forward as ADR-002 Q1 and superseded in charter v11, because the Perses version now follows the dashboard the store embeds.
- Which plugin, if any, declares the SQL proxy, and would the MySQL or PostgreSQL wire route be preferable for analytical dev-loop queries (`perses.md`)?

### Collection topology and darwin

- Does any pinned collector read the macOS unified log, which is the only source for the highest-value darwin signal class (`fleet-emitter-inventory.md` Q1)?
- Which collectors does node-exporter implement on `aarch64-darwin` at the packaged version (`fleet-emitter-inventory.md` Q2)?
- Does Vector's OTLP source cover all three signals (`otel-collector-topology.md`), settled because at 0.59.0 it does (`otel-collector-topology.md` refresh R13, C8), while ADR-003 rejects vector on other grounds.
- May the gateway collector be co-resident on `magnetite` given its recorded storage-exhaustion history, or must it sit elsewhere, which needs the store placement decision first (`otel-collector-topology.md`)?
- Must the store itself run on `aarch64-darwin`, since that decides whether a `-bin` proxy's darwin asset matters (`nix-packaging-status.md` question 3)?

### Packaging routes

- Does the repository's `-bin` convention test pass on artifacts produced by a conditionally-skipped continuous-integration job, or does that conditionality force the from-source route (`nix-packaging-status.md` question 2)?
- Should a new package check be blacklisted under the existing thin-upstream-re-package category, or is a half-hour source build acceptable inside the closure operator (`nix-packaging-status.md` question 4)?

### Access control and tenancy

- Should agent-session telemetry be partitioned per person at all, given that both humans work on the same repositories and the dev-loop consumer arguably wants the fleet-wide view (`telemetry-security-and-tenancy.md` Q1)?
- If partitioned, may one person's telemetry be readable by the other as fleet operator, and is the reverse also intended (`telemetry-security-and-tenancy.md` Q2)?
- Is prompt or tool content ever wanted, even opt-in for one named session, or is content exclusion absolute so the collector allow-list can be fixed once (`telemetry-security-and-tenancy.md` Q3)?
- Should the store credential be held only by a per-host collector, which requires deciding whether nix-darwin hosts run one as root, or may worker-adjacent processes hold a write-only credential directly (`telemetry-security-and-tenancy.md` Q5)?
- What retention applies to the identifying attributes that survive redaction, which are also the fields that make the store a personal-activity record (`telemetry-security-and-tenancy.md` Q6)?
- Should the three formerly public metrics endpoints be closed behind the gateway, moved to a mesh-only listener, or left open (`fleet-emitter-inventory.md` Q3), settled because #3447 restricted them to loopback and ZeroTier (charter W3) and ADR-003 scrapes them over loopback.
- Should the design carry an upstream patch to obtain redaction-safe tool-call error classes, accept failure rates without classes, or enable content capture behind an access boundary (`dev-loop-signals.md` Q3)?
- Is Kanidm the intended identity provider for the dashboard layer (`perses.md`), carried forward as ADR-002 Q4 and, since charter v11, served through `sso-gateway`'s Kanidm client; the original choice between a separate project and a separate instance for agent-session dashboards is superseded by ADR-008's shared read zone (ADR-008 Q1).

### Coverage model and regulators

- Does the traceability denominator mean flake outputs, `modules/` files, or a hand-declared manifest, since the three give different untraced-count series (`dev-loop-signals.md` Q1)?
- Is the standing single-machine exemption a legitimate exemption needing an owner and expiry, or a defect to be fixed (`dev-loop-signals.md` Q2)?
- Is journald log volume on the always-on hosts measurable before the signal budget is written, since the log leg of that budget currently rests on no measurement (`otel-collector-topology.md`)?

## Next steps

The nine decision records are Accepted at the human gate of 2026-10-15, and charter v9 records A5, A6 and A8 as discharged by that recorded human judgment.
A1 is satisfied once `architecture/reference-architecture.md` and the seven `components/*.md` files listed in the map exist.
Next, implementation proceeds through one or more OpenSpec changes under `openspec/changes/`, following the precedent of `openspec/changes/stand-up-nixbot-on-magnetite/` and `openspec/changes/stand-up-gitea-mq-on-magnetite/`, with the decision records, the reference architecture and the component documents as their design input (charter v8).
The charter's S2 sequences the continuous-verification half after the store and topology decisions land, so it follows the store and collection work of ADR-001 and ADR-003.
ADR-009 Q5, whether an external dead-man service watches cinnabar itself, is decided in CAM-76 before S5 (charter v21); the candidate is an external heartbeat from a free uptime service, weighed against the third-party dependency.
Finding 5 above adds a precondition to A6 in practice, since a regulator that cannot be shown to fail on a mutant does not discharge it.
