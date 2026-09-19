---
title: Fleet observability documentation map
---

# Fleet observability documentation map

This tree holds the design work for a fleet observability platform and the continuous-feedback loop that consumes it.
It is a design corpus, not an implementation: nothing here is deployed, and no module, collector, store or dashboard exists in `modules/` today.

Read [charter.md](charter.md) first, because every artifact below is scoped by its world assumptions W1 through W9 and answers to its decision list D1 through D8.

## Current status

The charter is accepted at v2, revised on 2026-09-18 after the research phase landed.
The research phase is complete: eight artifacts under [research/](research/) cover the store, the dashboard layer, the collection topology, the rejected store alternatives, the fleet's existing emitters, the development-loop signal set, the Nix packaging position, and telemetry access control.
Decisions D1 through D8 are all open; no ADR has been written and none of the `architecture/`, `components/` or `decisions/` trees that charter deliverable S1 names exists yet.
No implementation work has begun, and charter constraint C4 forbids it until the decisions land.
Roughly thirty-six questions were carried to the human gate rather than answered by inference, per the charter's standing rule; they are aggregated below.

## Documentation map

| Document | Path | Question it answers |
|---|---|---|
| Charter | [charter.md](charter.md) | What is being designed, under what world assumptions, against which requirements, and which eight decisions remain open |
| GreptimeDB as observability store | [research/greptimedb.md](research/greptimedb.md) | What the leading store candidate can actually do: engines, OTLP ingest paths, query surfaces, SST layout, deployment floor, and where the open/enterprise line falls |
| Perses as dashboard layer | [research/perses.md](research/perses.md) | Whether the packaged Perses can query the candidate store, what dashboards-as-code costs, and what its CLI validates |
| Collection topology decision space | [research/otel-collector-topology.md](research/otel-collector-topology.md) | Per-host agent versus central gateway for this fleet's shape, what a nix-darwin host can run, which transport and ingress paths exist, and the volume budget |
| Rejected store alternatives | [research/store-alternatives.md](research/store-alternatives.md) | Why SigNoz, the Grafana assembly, the VictoriaMetrics family, OpenObserve and ClickHouse-direct are disfavored, and where each beats the leading candidate |
| Fleet emitter inventory | [research/fleet-emitter-inventory.md](research/fleet-emitter-inventory.md) | What each deployed service can emit today without code changes, and which documented failures are candidate service-level indicators |
| Dev-loop signals | [research/dev-loop-signals.md](research/dev-loop-signals.md) | Which development-loop signals exist, which are missing, and which coverage-model decision each one feeds |
| Nix packaging status | [research/nix-packaging-status.md](research/nix-packaging-status.md) | Which candidate is packaged where, which NixOS and nix-darwin modules exist, and the routes to a GreptimeDB derivation |
| Telemetry security and tenancy | [research/telemetry-security-and-tenancy.md](research/telemetry-security-and-tenancy.md) | What agent-session telemetry carries, where redaction can be enforced, and what the store, the dashboard layer and the mesh do and do not authorize |

## Findings that change the design

These are the cross-artifact conclusions a reader needs before opening any ADR.
Each is traceable to an artifact and its finding numbers.

### 1. Emission is not zero, and three unauthenticated metrics endpoints are already public

Charter v1 claimed nothing was emitted; that is false.
`gitea`, `nixbot` and `niks3` each serve a Prometheus `/metrics` endpoint with no authentication, and each is reachable over public TLS because the service vhosts proxy `/` wholesale (`research/fleet-emitter-inventory.md` F9).
Only nixbot's endpoint carries an upstream-declared containment property, aggregating by status and never labelling by project (`research/fleet-emitter-inventory.md` F10).
The accurate statement is zero collection with three unintended public endpoints, and the charter's W3 is corrected to say so.
This is a tightening argument that exists independently of which store is chosen.

### 2. The non-metric signals are constrained at both ends of the pipeline

At the ingest end, GreptimeDB registers no standard OTLP gRPC trace or logs service; the only OpenTelemetry gRPC service is an OTel-Arrow metrics service, so a collector must use the HTTP exporter for logs and traces, and the trace handler accepts protobuf only (`research/greptimedb.md` F12, F13, F14, corroborated by `research/otel-collector-topology.md` F25).
At the rendering end, Perses binds query plugins to datasource kinds, and the packaged 0.53.1 plugin set contains log and trace query plugins only for Loki, Tempo, VictoriaLogs and Pyroscope, so a GreptimeDB-only store has no log or trace query path at that version (`research/perses.md` F13, F39, F40, F41).
Metrics are the exception in both directions: a stock `PrometheusDatasource` pointed at `/v1/prometheus` matches GreptimeDB's Prometheus router on every path and method the plugin uses (`research/perses.md` F17, F18, F19, F20).
The native GreptimeDB plugin exists upstream, is SQL-based rather than PromQL-based, and is absent from both the 0.53.1 default set and the nixpkgs vendored set (`research/perses.md` F14, F21).

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

`greptimedb` is absent at the repository's root nixpkgs pin, but it was added to nixpkgs `master` at 1.1.4 on 2026-08-30, twenty-six days after the pin's commit date, and neither that commit nor its follow-up is an ancestor of the pin (`research/nix-packaging-status.md` F9, F10).
Upstream also ships checksummed Linux and Darwin release tarballs across its six most recent releases, so a from-source build is not forced into the critical path (`research/nix-packaging-status.md` F15).
What remains is module work rather than derivation work: no GreptimeDB NixOS module exists at the pin or on `master`, no third-party flake supplies one, and nix-darwin ships no OpenTelemetry Collector, Vector or Alloy module at the locked revision, so a first-party launchd module is unavoidable for whichever collector is chosen (`research/nix-packaging-status.md` F17, F25, F27, corroborated by `research/otel-collector-topology.md` F8).
Citations into nixpkgs must name the lock node, because `flake.lock` holds two distinct nixpkgs tarball nodes and neither is a git checkout (charter W4, `research/nix-packaging-status.md` F1, F2).

## Decision status

All eight decisions are open.
The bearing column names the artifacts that supply evidence for that decision, not a recommendation.

| Decision | Subject | Status | Bearing artifacts |
|---|---|---|---|
| D1 | Store, including the open/enterprise boundary and single-node versus clustered | open | `greptimedb.md`, `store-alternatives.md`, `nix-packaging-status.md`, `telemetry-security-and-tenancy.md`, `perses.md` |
| D2 | Dashboard layer, its as-code format, and datasource reachability | open | `perses.md`, `telemetry-security-and-tenancy.md`, `store-alternatives.md`, `nix-packaging-status.md` |
| D3 | Collection topology, transport authentication, and ingress | open | `otel-collector-topology.md`, `fleet-emitter-inventory.md`, `dev-loop-signals.md`, `telemetry-security-and-tenancy.md`, `nix-packaging-status.md`, `greptimedb.md` |
| D4 | Signal scope, schema, cardinality and retention budgets | open | `fleet-emitter-inventory.md`, `dev-loop-signals.md`, `otel-collector-topology.md`, `greptimedb.md`, `telemetry-security-and-tenancy.md`, `perses.md` |
| D5 | Dev-loop instrumentation and the coverage-model decision each signal feeds | open | `dev-loop-signals.md`, `fleet-emitter-inventory.md` |
| D6 | Storage substrate and the lakehouse seam | open | `greptimedb.md`, `store-alternatives.md`, `dev-loop-signals.md` |
| D7 | Packaging, host placement, and clan service shape | open | `nix-packaging-status.md`, `greptimedb.md`, `otel-collector-topology.md`, `fleet-emitter-inventory.md`, `store-alternatives.md`, `telemetry-security-and-tenancy.md`, `perses.md` |
| D8 | Access control and tenancy, including the prompt-content hazard | open | `telemetry-security-and-tenancy.md`, `fleet-emitter-inventory.md`, `greptimedb.md`, `perses.md`, `store-alternatives.md`, `otel-collector-topology.md`, `dev-loop-signals.md` |

## Open questions for the human gate

Grouped and deduplicated from the eight artifacts' own questions sections.
Each is attributed to the artifact that raised it; where two artifacts raised the same question it is listed once with both attributions.

### Scope and consent

- Is in-database alerting wanted at all, given that trigger DDL is enterprise-gated and external alerting is therefore the open-build answer (`greptimedb.md` Q1)?
- Are the three darwin machines belonging to other people in scope as telemetry subjects at all (`otel-collector-topology.md`)?
- Are `cognee` and `k3s-server` intended to be deployed, or retained as unimported definitions, since that decides whether they enter the D4 scope (`fleet-emitter-inventory.md` Q4)?
- Is re-enabling the disabled `sso-gateway` on `magnetite` in scope, or must the dashboard layer work with it disabled (`telemetry-security-and-tenancy.md` Q4)?
- Is bumping the root nixpkgs pin in scope, or must the design assume the current pin (`nix-packaging-status.md` question 1)?
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
- Should the design target the packaged 0.53.1 or a newer Perses, since every plugin-set, provisioning-watch, `dac watch` and software-development-kit import-path difference follows from that one choice (`perses.md`)?
- Which plugin, if any, declares the SQL proxy, and would the MySQL or PostgreSQL wire route be preferable for analytical dev-loop queries (`perses.md`)?

### Collection topology and darwin

- Does any pinned collector read the macOS unified log, which is the only source for the highest-value darwin signal class (`fleet-emitter-inventory.md` Q1)?
- Which collectors does node-exporter implement on `aarch64-darwin` at the packaged version (`fleet-emitter-inventory.md` Q2)?
- Does Vector's OTLP source cover all three signals at 0.57.0, the single criterion that could eliminate it outright (`otel-collector-topology.md`)?
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
- Should the three already-public metrics endpoints be closed behind the gateway, moved to a mesh-only listener, or left open because their label sets are aggregate-only (`fleet-emitter-inventory.md` Q3)?
- Should the design carry an upstream patch to obtain redaction-safe tool-call error classes, accept failure rates without classes, or enable content capture behind an access boundary (`dev-loop-signals.md` Q3)?
- Is Kanidm the intended identity provider for the dashboard layer, and do agent-session dashboards live in a separate project or a separate instance (`perses.md`)?

### Coverage model and regulators

- Does the traceability denominator mean flake outputs, `modules/` files, or a hand-declared manifest, since the three give different untraced-count series (`dev-loop-signals.md` Q1)?
- Is the standing single-machine exemption a legitimate exemption needing an owner and expiry, or a defect to be fixed (`dev-loop-signals.md` Q2)?
- Is journald log volume on the always-on hosts measurable before the signal budget is written, since the log leg of that budget currently rests on no measurement (`otel-collector-topology.md`)?

## Next steps

The charter's S1 names one file per decision under `decisions/`, so the eight open decisions imply eight decision records, plus `architecture/reference-architecture.md` and a `components/<component>.md` per chosen component.
The charter's S2 sequences the continuous-verification half after the store and topology decisions land, which orders the store decision and the collection-topology decision ahead of the rest.
Its standing rule and requirement R7 put the questions above at a human gate before any record is written, because several of them decide the shape of the record rather than a detail inside it.
Charter acceptance criteria A5, A6 and A8 bind every record: a rationale with each rejected alternative in one line, a declared operating envelope with a named regulator, and a named failure for each proposed layer.
Finding 5 above adds a precondition to A6 in practice, since a regulator that cannot be shown to fail on a mutant does not discharge it.
