---
title: Rejected store alternatives for the fleet observability platform
status: research v2
date: 2026-09-18
sources:
  - sciexp/ironstar@094e8d3c
  - signoz/signoz@57268e5
  - NixOS/nixpkgs@85f62611 (root node nixpkgs_9)
  - https://docs.victoriametrics.com/victoriametrics/integrations/opentelemetry/
  - https://docs.victoriametrics.com/victorialogs/data-ingestion/opentelemetry/
  - https://docs.victoriametrics.com/victoriatraces/
  - https://openobserve.ai/docs/architecture/
  - https://grafana.com/docs/tempo/latest/configuration/parquet/
  - https://api.github.com/repos/openobserve/openobserve/license
---

# Rejected store alternatives for the fleet observability platform

This artifact supplies the evidence base charter R1 requires for D1, weighing five non-leading candidates under C3's rule that a disfavored option is still weighed on evidence.

This revision re-evaluates every nixpkgs-derived finding against this repository's root `nixpkgs` input, which v1 misidentified; the correction and its consequences are recorded in FL1.

## Findings

### SigNoz plus ClickHouse

F1 ironstar built three first-party derivations rather than consuming an upstream package: `signoz-backend`, `signoz-frontend` and `signoz-otel-collector`, all pinned to one SigNoz source revision `8bfadbc1978c3acff9777c65f6152a0ec25087b9` (`sciexp/ironstar@094e8d3c:pkgs/by-name/signoz-backend/package.nix:17`).
F2 The backend derivation deliberately builds only the community entrypoint, `subPackages = [ "cmd/community" ]`, with `version.variant=community` stamped into the binary (`sciexp/ironstar@094e8d3c:pkgs/by-name/signoz-backend/package.nix:24`, `:32`).
F3 The frontend is a yarn-offline Vite build needing a 4 GB Node heap and two hand-run codegen scripts, because `yarnConfigHook` passes `--ignore-scripts` (`sciexp/ironstar@094e8d3c:pkgs/by-name/signoz-frontend/package.nix:39-47`).
F4 The runtime shape is four host processes: ClickHouse with embedded Keeper, a one-shot schema migrator, the SigNoz collector, and the backend serving the static frontend (`sciexp/ironstar@094e8d3c:modules/services/signoz.nix:225-330`).
F5 ClickHouse is configured with `max_memory_usage` of 10 GB per query profile and embedded ClickHouse Keeper on ports 9181 and 9234, replacing external Zookeeper (`sciexp/ironstar@094e8d3c:modules/services/signoz.nix:15`, `:74-98`).
F6 Schema ownership sits outside Nix: the composition runs `migrate bootstrap`, `migrate sync up` and `migrate async up` as a dependent process, and the collector re-checks `migrate sync check` at every start (`sciexp/ironstar@094e8d3c:modules/services/signoz.nix:252-254`, `:271`).
F7 The store is three separate ClickHouse databases reached over the native protocol, `signoz_traces`, `signoz_metrics` and `signoz_logs`, each with its own exporter, and a fourth SQLite file holds application metadata at `SIGNOZ_SQLSTORE_SQLITE_PATH` (`sciexp/ironstar@094e8d3c:modules/services/signoz.nix:187-196`, `:309`).
F8 Trace-derived metrics are produced by a vendor-specific processor, `signozspanmetrics/delta`, with a 100000-entry dimension cache and sixteen hard-coded dimensions, eleven of which are Kubernetes, browser or container attributes irrelevant to this fleet (`sciexp/ironstar@094e8d3c:modules/services/signoz.nix:138-179`).
F9 The exclusion list in ironstar's package-set invariant records the three SigNoz packages as checked only transitively via `dev-platform`, so no package-level regulator covers them (`sciexp/ironstar@094e8d3c:modules/checks/package-set-invariant.nix:25-28`, `:52-56`).
F10 ironstar's migration prompt scoped SigNoz beside Sentry and PostHog against a Rust application's `metrics-rs` call sites, and left open whether process-compose could host containers at all (`sciexp/ironstar@094e8d3c:docs/notes/development/observability-migration-agent-prompt.md:15-21`, `:207`).
F11 The retained process-compose boundary argument is that process-compose samples only the application-composition envelope: it can assert startup ordering, port binding, probe success and loopback reachability, and cannot assert systemd unit ordering, NixOS module behavior, secrets activation, boot sequence or multi-machine topology (skill `preferences-nix-checks-architecture`, `references/process-compose-checks.md:74-83`, vendored under this repository's agent-plugin tree).
F12 That reference names ironstar's SigNoz/ClickHouse subsystem as its illustration: Keeper raft topology, systemd slice limits and collector credential activation all sit outside the envelope, so a regression in any of them passes process-compose and fails in production (`…/process-compose-checks.md:85-89`).
F13 It also names end-to-end observability data flow through a collector and a backend as an escalation trigger to nspawn, and says the eval-gate pattern ironstar used leaves the runtime envelope entirely unsampled (`…/process-compose-checks.md:28-33`, `:123-124`).
F14 SigNoz's governance is single-sponsor with a source-available carve-out: the root license is MIT Expat except for `ee/` and `cmd/enterprise/`, which fall under a seat-counted enterprise license (`signoz/signoz@57268e5:LICENSE:1-7`, `signoz/signoz@57268e5:ee/LICENSE:1-20`).
F15 The enterprise carve-out includes `ee/authn`, `ee/authz`, `ee/auditor`, `ee/licensing` and `ee/gateway`, so authentication, authorization and audit are the specific capabilities behind the paid boundary; the repository ships no `GOVERNANCE.md` (`signoz/signoz@57268e5:ee/`).
F16 ironstar's composition sets `SIGNOZ_TOKENIZER_JWT_SECRET = "secret"` as a literal, which is acceptable in a dev loop and is not a deployable access model (`sciexp/ironstar@094e8d3c:modules/services/signoz.nix:310`).
F17 SigNoz is absent from the root-pinned nixpkgs: no `pkgs/by-name` entry exists and no NixOS module mentions it, so packaging and module authorship would both be ours (`NixOS/nixpkgs@85f62611:pkgs/by-name/`, `NixOS/nixpkgs@85f62611:nixos/modules/`, root node `nixpkgs_9`).

### Prometheus, Grafana, Loki, Tempo, Mimir

F18 This assembly has by far the best packaging position: `prometheus` 3.13.2, `grafana` 13.1.1, `grafana-loki` 3.7.4, `tempo` 3.0.2, `mimir` 3.1.4 and `grafana-alloy` 1.17.1 are all in the root-pinned nixpkgs, all six report `aarch64-darwin` in `meta.platforms`, none sets `meta.broken`, and all six evaluate to the same version and license from `aarch64-darwin` and from `x86_64-linux` (`NixOS/nixpkgs@85f62611:pkgs/by-name/`, root node `nixpkgs_9`).
Substance changed in v2: `grafana` is 13.1.1 at the root node, not the 13.1.3 that v1 read from the other node (`NixOS/nixpkgs@85f62611:pkgs/by-name/gr/grafana/package.nix:24`, root node `nixpkgs_9`).
F19 NixOS modules exist for every component, each path re-checked against the root node: `services/monitoring/prometheus/`, `services/monitoring/grafana.nix`, `services/monitoring/loki.nix`, `services/monitoring/mimir.nix`, `services/monitoring/alloy.nix` and `services/tracing/tempo.nix`, so host placement needs no first-party module work (`NixOS/nixpkgs@85f62611:nixos/modules/services/monitoring/`, `NixOS/nixpkgs@85f62611:nixos/modules/services/tracing/tempo.nix`, root node `nixpkgs_9`).
F20 Tempo's storage is genuinely FDAP-shaped and is the strongest single point any disfavored candidate holds: the default block format is `vParquet4`, Parquet has been the default since Tempo 2.0, and Tempo 3.0 supports only Parquet-based formats (https://grafana.com/docs/tempo/latest/configuration/parquet/ (fetched 2026-09-18)).
F21 The legacy shape is component count: the root-pinned tree carries six separately configured units for this assembly where the other four candidates carry one to four, and `alloy` is a seventh moving part on every emitter host (`NixOS/nixpkgs@85f62611:nixos/modules/services/monitoring/alloy.nix`, root node `nixpkgs_9`).
F22 Grafana and Mimir are `agpl3Only` and Loki is dual-licensed in the root-pinned tree, all under one corporate sponsor, so the governance objection C3 raises against SigNoz and OpenObserve applies here too and is not a discriminator (`NixOS/nixpkgs@85f62611:pkgs/by-name/gr/grafana/package.nix:159`, `NixOS/nixpkgs@85f62611:pkgs/by-name/mi/mimir/package.nix:66`, `NixOS/nixpkgs@85f62611:pkgs/by-name/gr/grafana-loki/package.nix:61`, root node `nixpkgs_9`).

### VictoriaMetrics and VictoriaLogs

F23 `victoriametrics` 1.148.0, `victorialogs` 1.52.0 and `victoriatraces` 0.10.0 are all in the root-pinned nixpkgs under Apache-2.0, none broken and all three reporting `aarch64-darwin` in `meta.platforms`, with NixOS modules at `services/databases/{victoriametrics,victorialogs,victoriatraces}.nix` (`NixOS/nixpkgs@85f62611:nixos/modules/services/databases/`, `NixOS/nixpkgs@85f62611:pkgs/by-name/vi/victoriametrics/package.nix:17`, root node `nixpkgs_9`).
Substance changed in v2: `victoriametrics` is 1.148.0 at the root node, not the 1.149.0 that v1 read from the other node, and v1 left `victoriatraces` unversioned.
F24 The resource floor is the lowest of any candidate here: each component is a single executable with no external dependency, all configuration is command-line flags, and all data lives under one `-storageDataPath` directory (https://docs.victoriametrics.com/victoriametrics/single-server-victoriametrics/ (fetched 2026-09-18)).
F25 OTel ingestion is adapter-based, not native: OTLP metrics arrive at `/opentelemetry/v1/metrics` and are then reconciled against the Prometheus data model through four separate naming-sanitization flags, and exponential histograms are converted into `vmrange`-labelled VictoriaMetrics histograms on ingest (https://docs.victoriametrics.com/victoriametrics/integrations/opentelemetry/ (fetched 2026-09-18)).
F26 Delta temporality, which is exactly what ironstar's span-metrics pipeline emitted (F8), is stored as-is but is documented as working badly: upstream recommends converting to cumulative via the collector's `deltatocumulative` processor, and warns that deduplication and downsampling on delta data may cause data loss (same page, fetched 2026-09-18).
F27 VictoriaLogs maps OTLP resource labels to stream fields and needs out-of-band HTTP headers such as `VL-Stream-Fields` and `VL-Msg-Field` to control that mapping, so semantic-convention fidelity is a per-pipeline configuration concern (https://docs.victoriametrics.com/victorialogs/data-ingestion/opentelemetry/ (fetched 2026-09-18)).
F28 VictoriaTraces accepts OTLP natively and exposes Jaeger query JSON, defaults to 7-day retention, and supports retention by absolute bytes or by filesystem percentage, which is directly useful under W2 (https://docs.victoriametrics.com/victoriatraces/ (fetched 2026-09-18)).
F29 Storage is not externally readable: data is per-day partition directories of immutable proprietary files, backed up by a two-pass `rsync`, with no Parquet or Arrow surface (same page, fetched 2026-09-18).
F30 Governance is single-vendor with a paid tier and a free-trial license for enterprise builds, so it is not structurally different from SigNoz on the C3 axis despite the Apache-2.0 core (https://docs.victoriametrics.com/victoriametrics/single-server-victoriametrics/ (fetched 2026-09-18)).

### OpenObserve

F31 OpenObserve's storage is the closest of any candidate to W8: ingesters convert records to Arrow `RecordBatch` in a memtable, then write Parquet files to local disk or object storage, and the compactor merges them into files up to 2 GB (https://openobserve.ai/docs/architecture/ (fetched 2026-09-18)).
F32 Single-node mode uses SQLite for metadata and local disk or object storage for Parquet, and the resource floor is one binary; HA mode requires Kubernetes, NATS, PostgreSQL and object storage, which is out of scope under C1 (same page, fetched 2026-09-18).
F33 The enterprise boundary is structural, not a footnote: the workspace has an `enterprise` cargo feature fanning out to `audit`, `openobserve-api-http`, `openobserve-api-grpc`, `openobserve-core`, `openobserve-jobs`, `super_cluster_queue`, `search_service`, `enrichment-data` and `usage_reporting` sub-features (https://raw.githubusercontent.com/openobserve/openobserve/main/Cargo.toml (fetched 2026-09-18)).
F34 The crates implementing that feature are not public: `src/enterprise/o2_dex`, `src/enterprise/o2_openfga` and `src/enterprise/o2_enterprise` each contain only a `Cargo.toml` and a `lib.rs` whose doc comment reads "Cargo dependency-resolution stub for the private `o2_dex` crate" (https://raw.githubusercontent.com/openobserve/openobserve/main/src/enterprise/o2_dex/lib.rs (fetched 2026-09-18)).
F35 Those two names identify what is withheld: Dex is OIDC single sign-on and OpenFGA is fine-grained authorization, so SSO and relationship-based RBAC are closed-source, and federated search across clusters is documented as enterprise-only (https://openobserve.ai/docs/architecture/ (fetched 2026-09-18)).
F36 The root-pinned nixpkgs carries `openobserve` 0.91.5 while upstream's latest release is v1.0.3 published 2026-09-18, and no NixOS module for it exists anywhere in that tree (`NixOS/nixpkgs@85f62611:pkgs/by-name/op/openobserve/package.nix:53`, root node `nixpkgs_9`, https://api.github.com/repos/openobserve/openobserve/releases/latest (fetched 2026-09-18)).

### ClickHouse-direct with a thin query layer

F37 `clickhouse` 26.7.1.1315-stable is in the root-pinned nixpkgs under Apache-2.0 with a NixOS module at `services/databases/clickhouse.nix`, and `meta.platforms` lists `aarch64-darwin` but not `x86_64-darwin` (`NixOS/nixpkgs@85f62611:nixos/modules/services/databases/clickhouse.nix`, `NixOS/nixpkgs@85f62611:pkgs/by-name/cl/clickhouse/package.nix:2`, root node `nixpkgs_9`).
F38 This candidate has no OTel ingestion of its own; ironstar's composition reached it through three distinct vendor exporters, one per signal, each carrying its own schema and its own migration tool (F6, F7).
F39 Choosing it means owning what the SigNoz collector supplied: three database schemas, their retention, and the span-to-metric derivation with its sixteen configured dimensions, none of which ClickHouse provides (`sciexp/ironstar@094e8d3c:modules/services/signoz.nix:138-179`, `:252-254`).
F40 Access is through the server protocol rather than through files: every SigNoz exporter addresses it as `tcp://localhost:9000/<database>`, so the D6 lakehouse seam would be an export path and not a shared substrate, and the sponsor is a single vendor (`sciexp/ironstar@094e8d3c:modules/services/signoz.nix:188`, `:192`, `:194`, `NixOS/nixpkgs@85f62611:pkgs/by-name/cl/clickhouse/package.nix`, root node `nixpkgs_9`).

## Bearing on decisions

### D1 Store

The evidence points away from all five candidates, but for different reasons and with different strength.
SigNoz plus ClickHouse is rejected on apparatus cost rather than on capability: four processes, an out-of-band migration tool, three databases plus a SQLite metastore, and three first-party derivations including a 4 GB-heap Vite build (F1-F7), against C1.
The Grafana assembly is rejected on component count and on the Prometheus-first ingestion model, not on maturity or governance, since its governance position is no better and no worse than SigNoz's (F22).
VictoriaMetrics plus VictoriaLogs plus VictoriaTraces is the strongest rejected candidate on operability and would be the correct fallback if the leading candidate's packaging burden under W5 proves unpayable; it loses on OTel-nativeness, which is adapter-shaped throughout (F25-F27), and on storage opacity (F29).
OpenObserve is rejected on the private-crate boundary (F34-F35) and on a nixpkgs version nine minor releases stale with no module (F36), not on architecture, which is the most FDAP-aligned of the five.
ClickHouse-direct is rejected because it converts a store decision into a schema-ownership commitment with no regulator to bound it (F39).
What would reverse D1 away from the leading candidate: GreptimeDB's own enterprise boundary (W7) withholding authentication or authorization the way SigNoz's `ee/authn` and OpenObserve's `o2_dex` do, or the from-source Rust build in RK6 landing in the critical path.
What would reverse D1 toward VictoriaMetrics specifically: a demonstration that the dev-loop signal set in D4 is predominantly metrics and logs rather than traces, at which point the adapter cost in F25 is paid once and the single-binary floor in F24 dominates.

### D2 Dashboard layer

Only the Grafana assembly bundles its own dashboard layer, and it is the one candidate whose dashboard reachability is not in question.
This is a real advantage over the leading stack and bears on RK2: Tempo, Loki, Mimir and Prometheus all have first-party Grafana datasources, whereas the leading stack's datasource path is the open risk.
Reversal condition: if Perses cannot query the chosen store without a plugin we write, Grafana's maturity becomes the deciding factor rather than a footnote.

### D6 Storage substrate and lakehouse seam

Two disfavored candidates are strictly stronger than the leading stack on this axis as currently evidenced.
Tempo writes `vParquet4` Parquet blocks readable by external tooling (F20), and OpenObserve writes Parquet to local disk or object storage as its only durable format (F31); both satisfy W8's Arrow/Parquet/DuckDB substrate directly.
SigNoz, ClickHouse-direct and the VictoriaMetrics family all require an export step (F29, F40).
This finding should be carried explicitly into D6 rather than absorbed into D1, because it is the one place where the rejected set beats the leading set on the repository's own stated preferences.

### D7 Packaging, host placement, and clan service shape

Packaging cost orders cleanly: the Grafana assembly and the VictoriaMetrics family need zero first-party derivations and zero first-party modules, ClickHouse-direct needs zero, OpenObserve needs a version bump and a module, and SigNoz needs three derivations and a module (F17-F19, F23, F36-F37).
Under W2 the process-count floor matters as much as the package count: one binary per signal for VictoriaMetrics, one for OpenObserve, four for SigNoz, six for the Grafana assembly.
Reversal condition: if `magnetite` cannot host the leading candidate at all, D7 collapses into D1 and the lowest-floor candidate wins by default.

### D8 Access control and tenancy

The rejected set supplies the sharpest evidence available for D8 and it is uniformly discouraging.
SigNoz places `authn`, `authz` and `auditor` under its enterprise license (F15), and OpenObserve ships only compilation stubs for its SSO and RBAC crates (F34-F35).
Any candidate whose access model is the paid tier is unusable under W9, because the prompt-content hazard is exactly what an access model must contain.
This should be applied symmetrically to the leading candidate when W7 is resolved: if GreptimeDB's authentication sits under `LICENSE-ENTERPRISE`, it fails the same test.

### D3 Collection topology

All five candidates accept an OpenTelemetry Collector in front of them, and the root-pinned nixpkgs carries `opentelemetry-collector-contrib` 0.155.0, `vector` 0.57.0 and `grafana-alloy` 1.17.1 with `aarch64-darwin` in `meta.platforms` for all three (W6 confirmed against `NixOS/nixpkgs@85f62611`, root node `nixpkgs_9`).
Collection topology is therefore weakly coupled to D1 and should not be used to justify a store choice.

## Comparison table

Axes are the ones C2 and C3 name, plus the two W-grounded practical constraints.
"In pinned nixpkgs" means the root node `nixpkgs_9` at `85f62611`, evaluated for `aarch64-darwin` and `x86_64-linux`.

| Candidate | Sponsor control | Withheld behind paid tier | OTel ingestion | Storage externally readable | In pinned nixpkgs | NixOS module | Single-node floor |
|---|---|---|---|---|---|---|---|
| SigNoz + ClickHouse | SigNoz Inc., no governance doc | authn, authz, audit, licensing, gateway | Native OTLP, vendor exporters and vendor span-metrics processor | No, MergeTree via server only | No | No | 4 processes, 10 GB query profile, SQLite metastore |
| Prometheus/Grafana/Loki/Tempo/Mimir | Grafana Labs, AGPL-3.0 core | Grafana Enterprise plugins and Adaptive tiers | Adapter for metrics, native OTLP for Tempo | Partly, Tempo vParquet4 is Parquet | Yes, all six: prometheus 3.13.2, grafana 13.1.1, grafana-loki 3.7.4, tempo 3.0.2, mimir 3.1.4, grafana-alloy 1.17.1 | Yes, all six | 5 servers + 1 agent |
| VictoriaMetrics + VictoriaLogs + VictoriaTraces | VictoriaMetrics Inc., Apache-2.0 core | Downsampling, multi-tenancy, vmbackupmanager | Adapter with four naming flags, delta temporality discouraged | No, proprietary per-day partitions | Yes, all three: victoriametrics 1.148.0, victorialogs 1.52.0, victoriatraces 0.10.0 | Yes, all three | 1 binary per signal, flags only |
| OpenObserve | OpenObserve Inc., AGPL-3.0 core | o2_dex SSO, o2_openfga RBAC, federated search, audit | Native OTLP | Yes, Parquet on disk or object store | Yes, 0.91.5 vs upstream 1.0.3 | No | 1 binary + SQLite |
| ClickHouse-direct + thin query layer | ClickHouse Inc., Apache-2.0 core | Cloud-only features | None, we write the ingestion path | No, MergeTree via server only | Yes, clickhouse 26.7.1.1315-stable | Yes | 1 server, plus everything we build |

The table is decision-relevant in one direction: no row wins, and the two rows that beat the leading stack on a charter-stated preference are the Tempo cell and the OpenObserve cell under "externally readable".

## Flags

FL1 Corrected in v2: v1's nixpkgs findings were evaluated against the wrong lock node, and this revision re-evaluates all of them.
`flake.lock` holds two distinct nixpkgs tarball nodes and both are real.
The node `nixpkgs_9`, at rev `85f62611fa3f3eacbcfe3bc7a6d6518b443ca442`, is this repository's root `nixpkgs` input, and it is what `.#inputs.nixpkgs` and every `pkgs` in this flake resolve to.
The node named `nixpkgs`, at rev `044bfe75bfe4c7bbe043dc17b5e42ea823b84a09`, is a separate node that other inputs resolve to, and it is not the root input.
The root identity is settled by `jq -r '.nodes.root.inputs.nixpkgs' flake.lock` returning `nixpkgs_9` and by `nix eval --raw .#inputs.nixpkgs.rev` returning `85f62611fa3f3eacbcfe3bc7a6d6518b443ca442`.
v1 asserted the inverse, that `85f62611` was a transitive node and `044bfe75` was the repository's own input, and it evaluated every nixpkgs-derived finding against `044bfe75`.
Re-evaluation against the root node changed two version numbers, `grafana` from 13.1.3 to 13.1.1 in F18 and `victoriametrics` from 1.149.0 to 1.148.0 in F23, and changed no license, `meta.broken`, `meta.platforms` or NixOS module-path claim.
W4's perses 0.53.1 claim also holds against the root node.

FL2 Retained from v1 and aligned with the charter's revised A2 regulator.
Neither nixpkgs node is a git checkout, since both are `type=tarball`, so `git cat-file -e` has nothing to run against for either one.
A2 now resolves citations into those two nodes by `nix eval` against the named node instead, which is what this revision used.
The residual obligation A2 places on every artifact is that a nixpkgs citation must name the node, because a bare revision does not tell a reader which of the two trees was evaluated.

FL3 nixpkgs and upstream disagree on OpenObserve's license.
`NixOS/nixpkgs@85f62611` declares `meta.license = Apache-2.0` for `openobserve` 0.91.5 in the root node `nixpkgs_9`, while upstream's `LICENSE` on `main` is AGPL-3.0 and its source headers assert AGPL-3.0-or-later (`NixOS/nixpkgs@85f62611:pkgs/by-name/op/openobserve/package.nix:163`).
This is reported, not resolved; whether the 0.91.5 tag itself was Apache-2.0 is a question below.

FL4 Upstream marketing prose overstates OpenObserve's single-node ceiling relative to W2.
The architecture page claims 31 MB/s ingest and 2.6 TB/day on an Apple M2 with default configuration, while the same page states queriers default to caching in 50% of available memory; the two claims together are not a headroom argument for a shared VPS.

FL5 VictoriaMetrics' own documentation contradicts the "OTel-native" framing its integration page title carries.
The page is titled native OTLP support, and its body then describes four naming-sanitization flags, a histogram format conversion, and a recommendation to convert delta to cumulative upstream in the collector.

FL6 ironstar's retained process-compose argument is evidence against process-compose as a regulator for an observability subsystem, not evidence for SigNoz.
The reference explicitly names end-to-end observability data flow as an escalation trigger to nspawn and describes ironstar's own SigNoz check as leaving the runtime envelope unsampled.

FL7 Absence reported: no candidate in this set is packaged in nixpkgs with both a NixOS module and a Parquet-readable store.
Re-checked against the root node `nixpkgs_9` at `85f62611`, where the intersection is still empty; OpenObserve has the storage and no module, the Grafana assembly has the module and only Tempo's blocks.

FL8 Absence reported: SigNoz ships no `GOVERNANCE.md` and its `CONTRIBUTING.md` contains no CLA or copyright-assignment text, so the governance objection in C3 rests on the license carve-out and the single corporate copyright holder, not on a documented governance model.

## Questions

Q1 Was the `openobserve` v0.91.5 tag that nixpkgs builds actually Apache-2.0 licensed, or is `meta.license` stale relative to an upstream relicense (FL3)?
Resolving this requires reading the LICENSE at that tag, which needs a checkout absent locally; the answer changes whether OpenObserve is even admissible.

Q2 Should the repository's other flake inputs be made to follow the root `nixpkgs` so that `flake.lock` holds one nixpkgs node rather than two?
The two-node shape is what produced this artifact's v1 error, and it will keep mis-evaluating findings in later units unless every citation carries a node name; the cost of unifying is not assessed here because it is a `flake.nix` change that C4 and C5 put out of scope.
v1's Q2, which asked which node the charter intends, is withdrawn because the charter now answers it in W4.

Q3 Is Tempo's `vParquet4` block layout considered a usable lakehouse seam under D6, or does D6 require a single store rather than a per-signal Parquet surface?
If the former, the Grafana assembly is not cleanly rejectable on D6 grounds and R1's one-line rejection is insufficient.

Q4 Does "externally readable" in the D6 sense require DuckDB to read the store's files in place, or is a scheduled export to Parquet acceptable?
The answer reorders the entire storage column of the comparison table.

Q5 Should the paid-tier access-control finding (F15, F34-F35) be applied as a hard admissibility filter rather than as one axis among several?
If it is a filter, SigNoz and OpenObserve are excluded before any other axis is weighed, and the same filter must then be applied to the leading candidate once W7 is resolved.
