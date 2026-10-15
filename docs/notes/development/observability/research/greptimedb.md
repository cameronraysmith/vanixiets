---
title: GreptimeDB as observability store
status: research v1
date: 2026-09-18
sources:
  - GreptimeTeam/greptimedb@20d87cff4
---

# GreptimeDB as observability store

## Findings

### Data model and table engines

F1 The workspace declares four region engines by name: `mito`, `mito2`, `metric` and `file` (`GreptimeTeam/greptimedb@20d87cff4:src/common/catalog/src/consts.rs:146`).
F2 `mito2` is the general-purpose region engine, described in-tree as serving "a more generic use case" than the metric engine, and the distributed datanode is described as the region engine holding WAL, memtable, SST, cache, compaction and indexes (`GreptimeTeam/greptimedb@20d87cff4:src/metric-engine/src/lib.rs:17`, `GreptimeTeam/greptimedb@20d87cff4:README.md:124`).
F3 The `metric` engine is not an independent storage engine but a multiplexer over `mito2` that maps many logical tables onto one synthetic wide physical region, specifically for the many-small-tables shape Prometheus metrics produce (`GreptimeTeam/greptimedb@20d87cff4:src/metric-engine/src/lib.rs:16`).
F4 All three signals share one table shape of tags, timestamp and fields; there is no distinct log store or trace store crate, and `src/log-store` is the WAL implementation rather than a log signal engine (`GreptimeTeam/greptimedb@20d87cff4:Cargo.toml:52`).
F5 Traces are therefore an application-level schema over `mito2`: OTLP spans land in a main table defaulting to `opentelemetry_traces` plus derived `<main_table>_services` and `<main_table>_operations` lookup tables (`GreptimeTeam/greptimedb@20d87cff4:src/frontend/src/instance/otlp/README.md:55`, `GreptimeTeam/greptimedb@20d87cff4:src/frontend/src/instance/otlp/README.md:167`).
F6 Three trace encodings coexist as named internal pipelines `greptime_trace_v0`, `greptime_trace_v1` and `greptime_trace_v2`, differing in whether span attributes are JSON blobs or flattened dynamic columns (`GreptimeTeam/greptimedb@20d87cff4:src/frontend/src/instance/otlp/README.md:59`).
F7 Logs default to the table `opentelemetry_logs` (`GreptimeTeam/greptimedb@20d87cff4:src/servers/src/http/otlp.rs:230`).
F8 So metrics are first-class through a dedicated engine, while logs and traces are first-class only in the weaker sense of having native ingestion paths and conventional schemas on the generic engine.

### Native OTLP ingestion

F9 All three OTLP signals have HTTP endpoints: `/v1/metrics`, `/v1/traces`, `/v1/logs`, nested under `/v1/otlp` (`GreptimeTeam/greptimedb@20d87cff4:src/servers/src/http.rs:1492`, `GreptimeTeam/greptimedb@20d87cff4:src/servers/src/http.rs:768`).
F10 Decoding, span parsing and row conversion live in the `servers` crate under `src/servers/src/otlp/`, while frontend orchestration and DDL live in `src/frontend/src/instance/otlp/` and `operator` (`GreptimeTeam/greptimedb@20d87cff4:src/frontend/src/instance/otlp/README.md:7`).
F11 OTLP is enabled by default, with exponential-histogram support and OTLP resource-attribute descriptor tables both off by default and both marked experimental (`GreptimeTeam/greptimedb@20d87cff4:src/frontend/src/service_config/otlp.rs:36`, `GreptimeTeam/greptimedb@20d87cff4:src/frontend/src/service_config/otlp.rs:37`, `GreptimeTeam/greptimedb@20d87cff4:src/frontend/src/service_config/otlp.rs:39`).
F12 There is no OTLP/gRPC `TraceService`/`LogsService`/`MetricsService` server registered; the only OTel gRPC service is the OTel-Arrow `ArrowMetricsServiceServer` from `otel_arrow_rust` (`GreptimeTeam/greptimedb@20d87cff4:src/servers/src/grpc/builder.rs:29`).
F13 Collectors must therefore use the OTLP/HTTP exporter, not OTLP/gRPC, for logs and traces; this is a topology constraint, not a documented limitation.
F14 The trace handler rejects JSON content types and accepts protobuf only (`GreptimeTeam/greptimedb@20d87cff4:src/frontend/src/instance/otlp/README.md:54`).

### Query surfaces

F15 The Prometheus HTTP query API is implemented as a first-class router: `query`, `query_range`, `labels`, `series`, `metadata`, `parse_query`, `format_query`, `label/{name}/values`, `status/buildinfo` (`GreptimeTeam/greptimedb@20d87cff4:src/servers/src/http.rs:1418`).
F16 Prometheus remote read and remote write are separate routes (`GreptimeTeam/greptimedb@20d87cff4:src/servers/src/http.rs:1453`).
F17 Jaeger's query API is served natively at `/v1/jaeger` with `api/services`, `api/operations`, `api/traces` and single-trace lookup (`GreptimeTeam/greptimedb@20d87cff4:src/servers/src/http.rs:1518`).
F18 A native log-query endpoint exists at `/v1/logs` backed by the `log-query` crate, distinct from LogQL (`GreptimeTeam/greptimedb@20d87cff4:src/servers/src/http.rs:1410`).
F19 Arrow Flight is served: `FlightServiceServer` is registered in the gRPC builder and `do_get` is implemented against the request handler (`GreptimeTeam/greptimedb@20d87cff4:src/servers/src/grpc/builder.rs:165`, `GreptimeTeam/greptimedb@20d87cff4:src/servers/src/grpc/flight.rs:195`).
F20 Upstream states explicitly that query-side compatibility is narrower than ingestion, that LogQL and the Loki query API are unsupported, and that Elasticsearch QueryDSL is Enterprise-only (`GreptimeTeam/greptimedb@20d87cff4:README.md:104`).

### Storage layout — the D6 question

F21 SSTs are Parquet files at `<table_dir>/<region_id>/{data,metadata}/<file_id>.parquet` (`GreptimeTeam/greptimedb@20d87cff4:src/mito2/src/sst/location.rs:42`).
F22 Files are written with a standard `AsyncArrowWriter`, ZSTD compression, and the full region metadata serialised as JSON into Parquet key-value metadata under the key `greptime:metadata` (`GreptimeTeam/greptimedb@20d87cff4:src/mito2/src/sst/parquet/writer.rs:535`, `GreptimeTeam/greptimedb@20d87cff4:src/mito2/src/sst/parquet.rs:52`).
F23 The legacy SST schema is hostile to external readers: tag columns are collapsed into one `__primary_key` dictionary-encoded binary column, so tags are not recoverable without GreptimeDB's row codec (`GreptimeTeam/greptimedb@20d87cff4:src/mito2/src/sst/parquet/format.rs:18`, `GreptimeTeam/greptimedb@20d87cff4:src/mito2/src/sst/parquet/format.rs:24`).
F24 The newer flat format stores raw primary-key columns *and* the encoded key: `primary key columns, field columns, time index, encoded primary key, __sequence, __op_type` (`GreptimeTeam/greptimedb@20d87cff4:src/mito2/src/sst/parquet/flat_format.rs:26`).
F25 The flat format is the default at this revision, both in code and in the shipped example config (`GreptimeTeam/greptimedb@20d87cff4:src/mito2/src/config.rs:259`, `GreptimeTeam/greptimedb@20d87cff4:config/standalone.example.toml:835`).
F26 Format is also a per-table option `sst_format`, so it is selectable per table rather than only globally (`GreptimeTeam/greptimedb@20d87cff4:src/store-api/src/mito_engine_options.rs:84`).
F27 External readability is nonetheless not free: an external engine must merge across SSTs using `__sequence` and `__op_type` to resolve updates and deletes, and must locate live files via the per-region manifest at `<region_dir>/manifest` rather than by globbing (`GreptimeTeam/greptimedb@20d87cff4:src/mito2/src/manifest/storage.rs:62`).
F28 Default storage type is local `File`, with `S3`, `Gcs`, `Azblob` and `Oss` selectable (`GreptimeTeam/greptimedb@20d87cff4:config/standalone.example.toml:557`, `GreptimeTeam/greptimedb@20d87cff4:config/standalone.example.toml:552`).

### Deployment shapes and resource floor

F29 Standalone is a single binary; distributed is four components — frontend, datanode, metasrv, optional flownode (`GreptimeTeam/greptimedb@20d87cff4:README.md:120`).
F30 Standalone is not a reduced build: it constructs a flownode instance unconditionally alongside the datanode, frontend and procedure manager in one process (`GreptimeTeam/greptimedb@20d87cff4:src/cmd/src/standalone.rs:587`, `GreptimeTeam/greptimedb@20d87cff4:src/cmd/src/standalone.rs:242`).
F31 Default WAL is local `raft_engine` with 128MB segments and a 1GB purge threshold, so the disk floor is roughly 1GB of WAL plus SSTs plus caches (`GreptimeTeam/greptimedb@20d87cff4:config/standalone.example.toml:291`).
F32 Memory is auto-sized from host RAM: write buffer is `min(RAM/8, 1GB)`, SST metadata cache `min(RAM/16, 512MB)`, vector and selector caches `min(RAM/16, 512MB)` each, page cache an unbounded fraction of RAM (`GreptimeTeam/greptimedb@20d87cff4:src/mito2/src/config.rs:353`).
F33 Auto-sizing means the process claims a fraction of whatever host it lands on rather than a low fixed floor, which is directly adverse on a co-tenanted host (W2); every one of those knobs is explicitly overridable in config.
F34 Four ports are used in the documented single-node run: 4000 HTTP, 4001 gRPC, 4002 MySQL, 4003 PostgreSQL (`GreptimeTeam/greptimedb@20d87cff4:README.md:158`).

### Retention and compaction

F35 `ttl` is a mito table option and an alterable region option, so retention is per-table rather than global (`GreptimeTeam/greptimedb@20d87cff4:src/store-api/src/mito_engine_options.rs:29`, `GreptimeTeam/greptimedb@20d87cff4:src/store-api/src/region_request.rs:1604`).
F36 Some internal tables pin `ttl` to `forever`: the metric engine's metadata region and the pipeline table both do (`GreptimeTeam/greptimedb@20d87cff4:src/metric-engine/src/engine/create.rs:647`, `GreptimeTeam/greptimedb@20d87cff4:src/pipeline/src/manager/pipeline_operator.rs:68`).
F37 Compaction exposes `max_background_compactions` (default one quarter of cores), an experimental memory budget with a `wait`/exhausted policy, `min_compaction_interval`, and `schedule_compaction_after_edit` (`GreptimeTeam/greptimedb@20d87cff4:config/standalone.example.toml:708`).
F38 A built-in event recorder writes DDL and admin events to its own table with a default 90-day TTL and a selectable event-type list (`GreptimeTeam/greptimedb@20d87cff4:config/standalone.example.toml:1036`).

### Open/enterprise boundary — the D1 question

F39 `LICENSE-ENTERPRISE` states the arrangement in its own words: the core is Apache-2.0, enterprise files carry an explicit header, and those files are gated behind the `enterprise` Cargo feature and not compiled into the default build (`GreptimeTeam/greptimedb@20d87cff4:LICENSE-ENTERPRISE:11`).
F40 The gated file set is enumerated exactly, and the list is enforced by `make check-enterprise-license`: trigger DDL across `sql`, `operator` and `common/meta`; `mito2/src/extension.rs`; `common/function/src/admin/purge_table.rs`; `information_schema/recycle_bin.rs`; `ddl/purge_dropped_table.rs`; `ddl/undrop_table.rs` (`GreptimeTeam/greptimedb@20d87cff4:licenserc-enterprise.toml:18`).
F41 The concrete open-build losses are therefore: `CREATE`/`ALTER`/`DROP`/`SHOW TRIGGER` — that is, in-database alerting rules; `UNDROP TABLE`, the recycle bin and soft-drop retention; the `purge_table` admin function; and the `mito2` scan-extension hook (`GreptimeTeam/greptimedb@20d87cff4:src/sql/src/statements/create/trigger.rs:1`, `GreptimeTeam/greptimedb@20d87cff4:src/catalog/src/system_schema/information_schema/recycle_bin.rs:1`, `GreptimeTeam/greptimedb@20d87cff4:src/mito2/src/extension.rs:1`).
F42 429 `cfg(feature = "enterprise")` sites span 55 files, so the split is woven through the parser, DDL, frontend, metasrv GC and mito2 read path rather than isolated in one crate.
F43 `enterprise` is absent from `cmd`'s `default` feature list, and the release workflow builds with `FEATURES=servers/dashboard` only, so published binaries are the open build (`GreptimeTeam/greptimedb@20d87cff4:src/cmd/Cargo.toml:22`, `GreptimeTeam/greptimedb@20d87cff4:.github/workflows/release.yml:266`, `GreptimeTeam/greptimedb@20d87cff4:.github/workflows/release.yml:285`).
F44 Upstream's own edition statement adds capabilities with no in-repo gating at all — read replicas, workload isolation, automated repartitioning, enterprise security and governance — and states that in the open build repartitioning, region migration and index creation are manual (`GreptimeTeam/greptimedb@20d87cff4:README.md:114`).
F45 Nothing this charter's D1 through D8 require — OTLP ingestion for all three signals, object storage, SQL, PromQL, Jaeger query, Flow, retention, cluster mode — is behind the `enterprise` feature at this revision.

### Release artifacts and packaging

F46 Release artifacts are built for `linux-amd64`, `linux-arm64`, `linux-riscv64`, `aarch64-apple-darwin`, `x86_64-apple-darwin` and `x86_64-pc-windows-msvc` (`GreptimeTeam/greptimedb@20d87cff4:.github/workflows/release.yml:186`, `GreptimeTeam/greptimedb@20d87cff4:.github/workflows/release.yml:284`, `GreptimeTeam/greptimedb@20d87cff4:.github/workflows/release.yml:326`).
F47 Both platforms this repository needs — x86_64-linux and aarch64-darwin — are covered by first-party CI-built tarballs, so a `-bin` proxy derivation is viable under C6.
F48 A from-source derivation would be heavy: the workspace declares 69 member crates and requires a pinned nightly toolchain, protobuf >= 3.15 and a C/C++ toolchain (`GreptimeTeam/greptimedb@20d87cff4:Cargo.toml:2`, `GreptimeTeam/greptimedb@20d87cff4:README.md:171`, `GreptimeTeam/greptimedb@20d87cff4:README.md:172`).
F49 Upstream ships a `flake.nix`, but it exposes only `devShells.default` — no `packages`, no `checks` — so there is no upstream derivation to vendor (`GreptimeTeam/greptimedb@20d87cff4:flake.nix:29`).
F50 The workspace version at this revision is `1.3.0-alpha.1`, a prerelease (`GreptimeTeam/greptimedb@20d87cff4:Cargo.toml:79`).
F51 There is a Homebrew bump workflow and a helm-chart bump workflow, evidence that upstream maintains downstream packaging channels but not a nixpkgs one (`GreptimeTeam/greptimedb@20d87cff4:.github/workflows/bump-homebrew-greptime-version.yml`).

### Governance and access model

F52 Copyright on the enterprise files is held by GrepTime Inc., and the enterprise agreement is negotiated individually per customer (`GreptimeTeam/greptimedb@20d87cff4:LICENSE-ENTERPRISE:19`, `GreptimeTeam/greptimedb@20d87cff4:LICENSE-ENTERPRISE:28`).
F53 Committership is granted by the company to individuals after sustained contribution; `AUTHOR.md` lists 17 individual committers with no organisational or foundation structure above them (`GreptimeTeam/greptimedb@20d87cff4:CONTRIBUTING.md:5`, `GreptimeTeam/greptimedb@20d87cff4:AUTHOR.md:3`).
F54 Contributions require signing a CLA (`GreptimeTeam/greptimedb@20d87cff4:CONTRIBUTING.md:55`).
F55 There is no foundation, no technical steering committee document, and no vendor-neutral trademark holder in the repository; security reports go to a company address (`GreptimeTeam/greptimedb@20d87cff4:SECURITY.md:17`).
F56 Authentication in the open build is a static user provider with plaintext or PBKDF2/SCRAM verifier formats read from a file; no OIDC, LDAP or Kanidm integration exists in-tree (`GreptimeTeam/greptimedb@20d87cff4:src/auth/src/lib.rs:41`, `GreptimeTeam/greptimedb@20d87cff4:config/standalone.example.toml:16`).

## Bearing on decisions

**D1 (store).**
The evidence supports GreptimeDB as the store on capability grounds: all three signals ingest natively, the enterprise boundary is narrow and precisely enumerated (F39–F41), and nothing the charter needs sits behind it (F45).
Two facts push the other way.
The version is a prerelease (F50), and standalone is not a lean build — it runs a flownode whether or not continuous aggregation is used (F30), which is ceremony under C1 unless flow is actually wanted.
This would reverse if the design comes to depend on in-database alerting: `CREATE TRIGGER` is enterprise-only (F41), so alerting must be external, and RK1 fires the moment a design draft assumes otherwise.
On governance (C3) GreptimeDB is in the same category as SigNoz and OpenObserve, not better: single-company control, CLA, company-appointed committers, no foundation (F52–F55).
The distinguishing argument must therefore be the open-core boundary's narrowness and the Parquet substrate, not governance.

**D2 (dashboard layer).**
RK2 is largely retired on the store side: a full Prometheus HTTP query API exists (F15), so a Perses Prometheus datasource has a real endpoint to talk to.
Logs and traces do not have that property — Jaeger's API (F17) and the native `/v1/logs` (F18) are not shapes Perses reads — so a Perses-only dashboard layer covers metrics well and logs/traces poorly.
This would reverse if Perses gains a SQL or Flight datasource, since both surfaces exist (F19).

**D3 (collection topology).**
F12/F13 constrain the topology concretely: collectors must export OTLP/HTTP, not OTLP/gRPC, for logs and traces, and trace payloads must be protobuf (F14).
Any collector configuration drafted against `otlp/grpc` will silently fail to connect.
Four listening ports (F34) is the ingress surface to place behind ZeroTier.

**D4 (signal scope and retention).**
Retention is per-table (F35), which fits a charter that wants different budgets for fleet and dev-loop telemetry in one store — this weakens RK4.
Two caveats: the metric engine's metadata region and the pipeline table are pinned to `forever` (F36), so "everything expires" is not achievable, and the event recorder adds a 90-day table nobody asked for unless disabled (F38).

**D6 (lakehouse seam).**
Answered yes, with conditions.
On-disk and object-store data is real Parquet (F21), self-describing via `greptime:metadata` (F22), and at this revision the default flat format exposes raw named tag columns rather than only the opaque `__primary_key` blob (F24, F25).
DuckDB can therefore read an SST directly and get meaningful column names.
But a correct read is not a plain `read_parquet` glob: external consumers must consult the region manifest for the live file set and must resolve `__sequence`/`__op_type` to honour updates and deletes (F27).
The honest seam is therefore export or a scheduled Parquet copy into DuckLake, not treating the store's own SST directory as a lakehouse table.
This would reverse toward "separate silo" if a table is created with the legacy format (F23, F26), since tags become unrecoverable externally.

**D7 (packaging and placement).**
A `-bin` proxy derivation is viable for both required platforms (F46, F47), which is the cheap path out of RK6; from-source is a 69-crate nightly-Rust build (F48) and upstream's flake gives no derivation to borrow (F49).
Placement on `magnetite` is the live risk: auto-sizing takes a fraction of host RAM by default (F32, F33), so any placement decision must pin the memory knobs explicitly rather than accept defaults.

**D8 (access control).**
The open build's access model is a static user file (F56).
There is no identity-provider integration, so GreptimeDB cannot be put behind Kanidm at the database protocol level; separation for the W9 prompt-content hazard must come from a reverse proxy, network placement, or separate databases, and the design must say which.

## Flags

FL1 W7 is confirmed and sharpened: the enterprise boundary is not merely present but exactly enumerated in `licenserc-enterprise.toml` and enforced by a make target (F40).
FL2 Upstream's own edition-boundary prose is incomplete against its source: `README.md:116` names read replicas, workload isolation and automated repartitioning as Enterprise, but does not mention that triggers/alerting, `UNDROP TABLE` and the recycle bin are also enterprise-gated in this tree (F41 versus F44).
FL3 The reverse gap also exists: read replicas, workload isolation and automated repartitioning have no `enterprise`-gated code in this repository at all, so they are either unimplemented here or live in a closed tree; the repository cannot confirm they exist.
FL4 The README's headline claim of "one engine" for metrics, logs and traces is accurate at the storage layer but overstated at the modelling layer: traces and logs are conventional schemas plus ingestion pipelines on the generic engine, and traces have three competing encodings (F5, F6).
FL5 The README markets OTLP ingestion without stating that OTLP/gRPC is not served for logs and traces (F12); this is a marketing-versus-source disagreement that will cost a collector configuration round trip if unnoticed.
FL6 W8 tension noted rather than resolved: the repository's analytics substrate is DuckDB/DuckLake, and GreptimeDB's DataFusion lineage means query-engine overlap, but the two do not share a catalog.
FL7 W5 is confirmed and refined: absent from nixpkgs, and upstream's `flake.nix` is a dev shell only (F49), so `-bin` or first-party derivation are the only options.
FL8 C3 is adverse to GreptimeDB and this must not be quietly dropped: on the governance axis it is indistinguishable from the SigNoz and OpenObserve cases the charter disfavours (F52–F55).
FL9 Absent: no NixOS module, no systemd unit, and no packaging metadata of any kind in the upstream repository.
FL10 Absent: no OpenTelemetry Collector exporter for GreptimeDB in-tree; ingestion is via the collector's generic OTLP-HTTP, Prometheus-remote-write or Loki exporters.
FL11 Absent: no mTLS or certificate-based client authentication surfaced in `src/auth`; the only providers are static-file password verifiers (F56).

## Questions

Q1 Is in-database alerting (`CREATE TRIGGER`) wanted at all?
If it is, D1 has an enterprise dependency and RK1 fires; if alerting is external, the enterprise boundary is irrelevant to this design.
This is a scope decision, not something to infer.

Q2 Does the lakehouse seam (D6) mean external DuckDB reads of the store's own SST files, or a scheduled Parquet export into DuckLake?
F24 makes the first technically possible and F27 makes it operationally fragile; the two answers imply different designs and I will not pick one by inference.

Q3 Is the flownode that standalone starts unconditionally (F30) acceptable under C1, or does its presence argue for the distributed shape with flownode omitted?
Accepting it means paying for a component with no named failure it prevents.

Q4 Is a `1.3.0-alpha.1` prerelease (F50) acceptable as a fleet dependency, or must the design pin the most recent stable tag and re-verify these findings against it?

Q5 Given FL8, does the governance constraint C3 actually disqualify single-vendor stores, or does it only disqualify ones whose open build is materially crippled?
The charter states both SigNoz and OpenObserve are disfavoured for corporate control, and GreptimeDB has the same control structure; the distinguishing rule needs to be stated by a human.

## Refresh (2026-10-15)

Revisions read for this refresh: the latest stable release `v1.2.1` at `GreptimeTeam/greptimedb@179ff8e50`, the newest prerelease `v1.3.0-beta.2` at `GreptimeTeam/greptimedb@a788cd977`, `main` at `GreptimeTeam/greptimedb@4859e57e0` (2026-10-15), and `v1.1.4` at `GreptimeTeam/greptimedb@16e9abe4a` because that is the version nixpkgs ships (see `nix-packaging-status.md` Refresh).

### What changed since the original findings

R1 The latest stable release is still `v1.2.1`, published 2026-09-16; no `v1.2.2` exists, and the newer tags are prereleases `v1.3.0-beta.1` (2026-09-29), `v1.3.0-beta.2` (2026-10-15, no assets attached at fetch time) and `v1.4.0` nightlies (https://api.github.com/repos/GreptimeTeam/greptimedb/releases, fetched 2026-10-15).
R2 The original findings were read from `main` at `20d87cff4`, which is `1.3.0-alpha.1` and is not an ancestor of `v1.2.1`, because `v1.2.1` is cut from a release branch carrying backports such as `GreptimeTeam/greptimedb@3e3943226` and `GreptimeTeam/greptimedb@346001567`.
R3 Every original finding that describes `main`-only behaviour therefore does not hold for any binary we could deploy today, and R6, R7 and R12 below are the cases where that difference is material.
R4 OTLP ingestion at `v1.2.1` is unchanged in transport: HTTP routes `/v1/metrics`, `/v1/traces` and `/v1/logs` nested under `/v1/otlp` (`GreptimeTeam/greptimedb@179ff8e50:src/servers/src/http.rs:739`, `GreptimeTeam/greptimedb@179ff8e50:src/servers/src/http.rs:1399`).
R5 OTLP/gRPC is still not served at `v1.2.1`, at `v1.3.0-beta.2` or at `main`: the only OTel gRPC service registered is `ArrowMetricsServiceServer`, and no `TraceServiceServer`, `LogsServiceServer` or OTLP `MetricsServiceServer` exists anywhere under `src` (`GreptimeTeam/greptimedb@179ff8e50:src/servers/src/grpc/builder.rs:29`, `GreptimeTeam/greptimedb@4859e57e0:src/servers/src/grpc/builder.rs:29`).
R6 The published documentation agrees: it gives `http{s}://<host>/v1/otlp` as the base endpoint for all signals and states that clients must use HTTP/protobuf (https://docs.greptime.com/user-guide/ingest-data/for-observability/opentelemetry/, fetched 2026-10-15).
R7 OTLP exponential histograms are silently discarded at `v1.2.1` and at `v1.1.4`: the match arm for `ExponentialHistogram` is an empty block under a `TODO ... leave ExponentialHistogram for next release` comment (`GreptimeTeam/greptimedb@179ff8e50:src/servers/src/otlp/metrics.rs:377`, `GreptimeTeam/greptimedb@16e9abe4a:src/servers/src/otlp/metrics.rs:378`).
R8 Exponential-histogram encoding exists on `main` and in `v1.3.0-beta.2`, and since `GreptimeTeam/greptimedb@20dde2601` (2026-09-23, "enable native histogram ingestion by default") it has no opt-in flag (`GreptimeTeam/greptimedb@4859e57e0:src/servers/src/otlp/metrics.rs:527`, `GreptimeTeam/greptimedb@4859e57e0:src/frontend/src/service_config/otlp.rs`).
R9 Trace pipeline `greptime_trace_v2` exists on `main` and in `v1.3.0-beta.2` but not at `v1.2.1`, where only `greptime_trace_v0` and `greptime_trace_v1` are defined (`GreptimeTeam/greptimedb@179ff8e50:src/pipeline/src/manager.rs:81`, `GreptimeTeam/greptimedb@4859e57e0:src/pipeline/src/manager.rs:84`).
R10 `main` gained Jaeger UI v2 query endpoints `/api/v3/services`, `/api/v3/operations`, `/api/v3/traces`, `/api/v3/trace-summaries` and `/api/v3/traces/{trace_id}` on 2026-10-12, which are in no tagged release yet, including `v1.3.0-beta.2` (`GreptimeTeam/greptimedb@2d99a5cf6`, `GreptimeTeam/greptimedb@4859e57e0:src/servers/src/http.rs:1580`).
R11 The Prometheus query router at `v1.2.1` is mounted at `/v1/prometheus/api/v1` and serves `format_query`, `status/buildinfo`, `query`, `query_range`, `labels`, `series`, `parse_query` and `label/{label_name}/values` (`GreptimeTeam/greptimedb@179ff8e50:src/servers/src/http.rs:725`, `GreptimeTeam/greptimedb@179ff8e50:src/servers/src/http.rs:1343`).
R12 The Prometheus `/metadata` route is absent at `v1.2.1` and at `v1.1.4`, and present at `main` and `v1.3.0-beta.1`/`v1.3.0-beta.2` (`GreptimeTeam/greptimedb@4859e57e0:src/servers/src/http.rs:1464`).
R13 Remote read and remote write remain at `/v1/prometheus/read` and `/v1/prometheus/write` (`GreptimeTeam/greptimedb@179ff8e50:src/servers/src/http.rs:715`, `GreptimeTeam/greptimedb@179ff8e50:src/servers/src/http.rs:1370`).
R14 S3-compatible storage at `v1.2.1` is configured with `type = "S3"` plus `bucket`, `root`, `access_key_id`, `secret_access_key`, `endpoint` and `region` under `[storage]` (`GreptimeTeam/greptimedb@179ff8e50:config/standalone.example.toml:463`, `GreptimeTeam/greptimedb@179ff8e50:config/standalone.example.toml:530`, `GreptimeTeam/greptimedb@179ff8e50:config/standalone.example.toml:535`).
R15 Path-style addressing is the default; `enable_virtual_host_style` defaults to `false` and switches to virtual-host style when set (`GreptimeTeam/greptimedb@179ff8e50:src/object-store/src/config.rs:128`).
R16 `disable_ec2_metadata` stops OpenDAL from probing the EC2 instance-metadata service for credentials, which is irrelevant on Hetzner and should be set to `true` for R2 (`GreptimeTeam/greptimedb@179ff8e50:src/object-store/src/config.rs:132`).
R17 Cloudflare documents the R2 S3 endpoint as `https://<ACCOUNT_ID>.r2.cloudflarestorage.com` and the bucket region as `auto`, with empty and `us-east-1` aliased to `auto` (https://developers.cloudflare.com/r2/api/s3/api/, fetched 2026-10-15).
R18 R2 implements every object operation GreptimeDB's storage layer needs for SSTs and manifests (`GetObject` with `Range`, `PutObject` with conditional headers, `DeleteObjects`, `ListObjectsV2`, multipart upload) and does not implement object tagging or ACLs (https://developers.cloudflare.com/r2/api/s3/api/, fetched 2026-10-15).
R19 A working R2 stanza is therefore `type = "S3"`, `endpoint = "https://<ACCOUNT_ID>.r2.cloudflarestorage.com"`, `region = "auto"`, `enable_virtual_host_style = false`, `disable_ec2_metadata = true`, with the two keys supplied from a secret rather than the TOML file.
R20 Neither the source tree nor the configuration examples mention Cloudflare or R2, so R19 is derived from the S3 code path and Cloudflare's documentation and has not been exercised against a live bucket.
R21 Object storage adds two local caches: a read cache (`enable_read_cache`, default on, `cache_path` defaulting to `data_home`, `cache_capacity` defaulting to 5GB) and the mito write cache, which is forced on whenever the storage type is object storage (`GreptimeTeam/greptimedb@179ff8e50:src/object-store/src/config.rs:26`, `GreptimeTeam/greptimedb@179ff8e50:src/object-store/src/config.rs:363`, `GreptimeTeam/greptimedb@179ff8e50:src/datanode/src/datanode.rs:560`).
R22 The write cache defaults to 5GiB with an 8h TTL, 20% reserved for index files, and refill-on-read enabled (`GreptimeTeam/greptimedb@179ff8e50:config/standalone.example.toml:667`, `GreptimeTeam/greptimedb@179ff8e50:config/standalone.example.toml:673`, `GreptimeTeam/greptimedb@179ff8e50:config/standalone.example.toml:677`).
R23 With R2 as the storage backend, the local disk on `magnetite` still holds the raft-engine WAL, the standalone metadata store, the 5GB read cache and the 5GiB write cache, so object storage moves SSTs and manifests off-host but leaves a default local floor of roughly 10GB of cache plus WAL and metadata (`GreptimeTeam/greptimedb@179ff8e50:config/standalone.example.toml:239`, `GreptimeTeam/greptimedb@179ff8e50:config/standalone.example.toml:364`).
R24 `main` added an HDFS backend and bumped OpenDAL to 0.59.4, neither of which changes the S3 path (`GreptimeTeam/greptimedb@75bd8e9ce`, `GreptimeTeam/greptimedb@e6f3ca10a`).
R25 Standalone at `v1.2.1` still constructs a flownode unconditionally (`GreptimeTeam/greptimedb@179ff8e50:src/cmd/src/standalone.rs:545`), so F30 holds for the stable release.
R26 The open build's authorization model is richer than F56 records: each user line in the static or watched file may carry a permission mode suffix, `username:ro=…`, `username:wo=…` or `username:rw=…`, with `rw` the default (`GreptimeTeam/greptimedb@179ff8e50:src/auth/src/user_info.rs:32`, `GreptimeTeam/greptimedb@179ff8e50:src/auth/src/user_provider.rs:364`).
R27 The default permission checker rejects reads for write-only users and writes for read-only users, and performs no per-table or per-database check (`GreptimeTeam/greptimedb@179ff8e50:src/auth/src/permission.rs:310`).
R28 The permission trait carries a table-target hook whose documentation refers to "ACL-aware implementations", but the open tree contains no implementation of it (`GreptimeTeam/greptimedb@179ff8e50:src/auth/src/permission.rs:242`).
R29 A second provider, `watch_file_user_provider`, reloads the user file on change, and `main` made it follow symlink chains on 2026-09-28 (`GreptimeTeam/greptimedb@179ff8e50:src/auth/src/user_provider/watch_file_user_provider.rs:29`, `GreptimeTeam/greptimedb@d5a6a9ac0`).
R30 No OIDC, LDAP, mTLS or identity-provider integration exists at `v1.2.1` or at `main`; the `src/auth` file list is identical across `20d87cff4`, `v1.2.1` and `4859e57e0`.
R31 Retention remains the per-table `ttl` option, and a database-level `ttl` default also exists as a schema option accepting durations, `forever` and `instant` (`GreptimeTeam/greptimedb@179ff8e50:src/common/meta/src/key/schema_name.rs:37`).
R32 The flat SST format is the default at `v1.2.1` and at `v1.1.4` (`default_flat_format = true`), so F25's D6 conclusion holds for the stable release (`GreptimeTeam/greptimedb@179ff8e50:config/standalone.example.toml:730`, `GreptimeTeam/greptimedb@16e9abe4a:config/standalone.example.toml:690`).
R33 Parquet export is available two ways at `v1.2.1`: SQL `COPY ... TO` with `FORMAT` among CSV, JSON and Parquet, and `greptime cli data export`, which issues `COPY DATABASE ... TO ... WITH (format = 'parquet')` with optional start and end times (`GreptimeTeam/greptimedb@179ff8e50:src/common/datasource/src/file_format.rs:74`, `GreptimeTeam/greptimedb@179ff8e50:src/cli/src/data/export.rs:506`, `GreptimeTeam/greptimedb@179ff8e50:src/cli/src/data/export.rs:632`).
R34 `COPY` to an S3 target accepts `endpoint`, `region`, `enable_virtual_host_style` and `disable_ec2_metadata` in its connection options, so a scheduled Parquet export into an R2 bucket for DuckLake needs no extra component (`GreptimeTeam/greptimedb@179ff8e50:src/common/datasource/src/object_store/s3.rs:24`).
R35 Local-file `COPY` in standalone is confined to `copy_root`, defaulting to `<data_home>/copy`, and distributed deployments reject local-file `COPY` entirely (`GreptimeTeam/greptimedb@179ff8e50:config/standalone.example.toml:448`).
R36 Arrow Flight is still registered at `v1.2.1` and `main` (`GreptimeTeam/greptimedb@179ff8e50:src/servers/src/grpc/builder.rs:165`).
R37 The enterprise file set at `v1.2.1` is identical to the set F40 enumerated (`GreptimeTeam/greptimedb@179ff8e50:licenserc-enterprise.toml`).
R38 `main` added five `flow_write.rs` files to the enterprise set on 2026-10-15, gating "tracked flow writes", a retry-safe write protocol between flownode, frontend and datanode, behind `cfg(feature = "enterprise")`; ordinary Flow remains open, and the change is in no tagged release (`GreptimeTeam/greptimedb@c3469fad5`, `GreptimeTeam/greptimedb@4859e57e0:licenserc-enterprise.toml`, `GreptimeTeam/greptimedb@4859e57e0:src/frontend/src/instance.rs:19`).
R39 The release workflow at `v1.2.1` still builds with `features: servers/dashboard` and without `enterprise` (`GreptimeTeam/greptimedb@179ff8e50:.github/workflows/release.yml:236`).
R40 `main` switched from `nightly-2026-03-21` to stable Rust `1.98.1` on 2026-10-08, and `v1.3.0-beta.2` carries that change; `v1.2.1` is still nightly-pinned (`GreptimeTeam/greptimedb@7f0f592b6`, `GreptimeTeam/greptimedb@a788cd977:rust-toolchain.toml`, `GreptimeTeam/greptimedb@179ff8e50:rust-toolchain.toml`).

### Corrections

C1 F11 is superseded for the stable release: its exponential-histogram and resource-attribute flags describe `main`, whereas at `v1.2.1` neither option exists and exponential histograms are dropped without error (R7, R8).
C2 F14 is superseded: JSON content types are rejected by all three OTLP handlers, not only traces (`GreptimeTeam/greptimedb@179ff8e50:src/servers/src/http/otlp.rs:88`, `GreptimeTeam/greptimedb@179ff8e50:src/servers/src/http/otlp.rs:142`, `GreptimeTeam/greptimedb@179ff8e50:src/servers/src/http/otlp.rs:209`).
C3 F15 is superseded for the stable release: `metadata` is not in the `v1.2.1` Prometheus router (R12).
C4 F6 is superseded for the stable release: `greptime_trace_v2` does not exist at `v1.2.1` (R9).
C5 F50 and Q4 are superseded in framing: the `1.3.0-alpha.1` version they describe is the `main` workspace version, not a published release, and the deployable stable version is `v1.2.1` (R1, R2).
C6 F56 and FL11 are superseded in part: the open build has per-user read-only, write-only and read-write modes and a hot-reloading file provider, while the absence of identity-provider, mTLS and per-table authorization stands (R26–R30).
C7 F35 is refined: retention can also be defaulted per database, not only per table (R31).
C8 F45 is refined, not reversed: at `main` the enterprise set also covers tracked flow writes, so RK1's reopening list must add that capability if the design relies on Flow write guarantees (R38).

### Charter reconciliation

W7 stands for `v1.2.1` without change (R37, R39).
W7 needs one addition for the next release line: tracked flow writes are enterprise-gated on `main` (R38).
RK1 stays retired for the stable release, and its reopening trigger list should add tracked flow writes.
RK6 is addressed in `nix-packaging-status.md` Refresh.
D3 is unchanged and sharpened: collectors must use `otlphttp` with protobuf encoding for all three signals, and a fleet that emits exponential histograms needs either `v1.3.x` or a collector-side conversion to explicit-bucket histograms while on `v1.2.1` (R5–R8).
That conversion exists as the `transform` processor's OTTL function `convert_exponential_histogram_to_histogram(distribution, [ExplicitBounds])` in the contrib distribution (`open-telemetry/opentelemetry-collector-contrib@cd37ea9:processor/transformprocessor/internal/metrics/func_convert_exponential_hist_to_explicit_hist.go:24`, `open-telemetry/opentelemetry-collector-contrib@cd37ea9:processor/transformprocessor/README.md:500`).
D8 gains an option: a read-only user for the dashboard layer and a write-only user for collectors are expressible in the open build (R26, R27).

### Questions

Q6 Does the design deploy `v1.2.1`, which silently drops exponential histograms and lacks Prometheus `/metadata`, or wait for `v1.3.0`, which has both but is at beta today?
Q7 Is roughly 10GB of default local cache on `magnetite` (R23) acceptable, or must `cache_capacity` and `write_cache_size` be pinned lower with the read-latency cost that implies?
Q8 Is the per-user `ro`/`wo` split (R26) sufficient separation for D8, or does the W9 prompt-content hazard require per-table authorization, which the open build does not provide?
