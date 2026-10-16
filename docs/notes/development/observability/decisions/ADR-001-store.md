---
title: "ADR-001: Telemetry store"
---

## Status

Accepted (human gate, 2026-10-15).
Amended in place under charter v11 (2026-10-16): the store package is `greptimedb-bin` because its upstream release tarball embeds the dashboard ADR-002 adopts, and R1.1 requires a stable release that serves that dashboard.

## Context

Charter D1 asks for one store, including the open/enterprise boundary and the single-node versus clustered choice.
The human gate of 2026-10-06 chose GreptimeDB, placed on `magnetite`, backed by Cloudflare R2 object storage; this record confirms or challenges that input on evidence.
Placement is decided in ADR-007 and the storage substrate in ADR-006; this record decides the product, its edition, its deployment shape, and its version policy.

GreptimeDB ingests all three OTLP signals over HTTP at `/v1/otlp/v1/{metrics,traces,logs}` at the deployable releases (`research/greptimedb.md` R4), and serves no OTLP/gRPC trace, logs or metrics service at `v1.1.4`, `v1.2.1` or `main` (`research/greptimedb.md` R5).
All three OTLP handlers reject JSON content types, so clients must send protobuf (`research/greptimedb.md` C2).
The Prometheus query router is mounted at `/v1/prometheus/api/v1` (`research/greptimedb.md` R11), which is the surface ADR-002 reads.

The enterprise file set at `v1.2.1` is identical to the set recorded at `20d87cff4`: trigger DDL, undrop and recycle bin, `purge_table`, and the mito2 scan-extension hook (`research/greptimedb.md` R37, F40).
The release workflow builds without the `enterprise` feature (`research/greptimedb.md` R39), and the nixpkgs derivation enables no extra features (`research/nix-packaging-status.md` R9).
Per-database and per-table authorization exists only in a separate Enterprise binary (`research/telemetry-security-and-tenancy.md` R3, R4), so the open build authenticates and enforces only a per-user `rw`/`ro`/`wo` mode (`research/greptimedb.md` R26, R27).
On governance (C3) GreptimeDB has single-company control, a CLA and company-appointed committers, which is the same structure as the disfavored SigNoz and OpenObserve (`research/greptimedb.md` FL8).

Three versions are in play.
`pkgs.greptimedb` at the root pin, lock node `nixpkgs_10` at `ac1faec4`, is 1.1.4 and is substituted from cache.nixos.org on both required platforms (`research/nix-packaging-status.md` R2, R4).
The latest stable release is `v1.2.1` of 2026-09-16, and the nixpkgs bump to it, https://github.com/NixOS/nixpkgs/pull/574558, merged on 2026-10-15 (`research/greptimedb.md` R1, `research/nix-packaging-status.md` R6).
The nixpkgs derivation builds without the `servers/dashboard` feature, so `pkgs.greptimedb` ships neither the embedded dashboard nor the dashboards API at any version, whereas upstream release tarballs are built with that feature (`research/nix-packaging-status.md` R9, R10).
Upstream publishes a checksummed `greptime-linux-amd64-v1.2.1.tar.gz` (`research/nix-packaging-status.md` R15).
The `v1.3.0` line is at `v1.3.0-beta.2`, published 2026-10-15 with no assets attached at fetch time (`research/greptimedb.md` R1).

The functional differences between those versions that bear on this design are enumerated below.
Both 1.1.4 and 1.2.1 silently discard OTLP exponential histograms (`research/greptimedb.md` R7), which `v1.3.0-beta.2` ingests by default (`research/greptimedb.md` R8).
Both lack the Prometheus `/metadata` route (`research/greptimedb.md` R12), which the Perses Prometheus plugin requests (`research/perses.md` F17).
Both lack the `greptime_trace_v2` pipeline (`research/greptimedb.md` R9).
Neither accepts bearer tokens, and the bearer path that exists from `v1.3.0-alpha.1` still has no open-build provider behind it (`research/otel-collector-topology.md` C1, `research/telemetry-security-and-tenancy.md` R5, R6).
Neither reloads a credential file across a sops-nix symlink swap, which is fixed from `v1.3.0-beta.1` (`research/telemetry-security-and-tenancy.md` R7).
`v1.2.1` carries PromQL correctness fixes that 1.1.4 lacks, including counter-reset accumulation in rate windows (`GreptimeTeam/greptimedb@8174697c9`) and NULL-sample and counter-extrapolation backports (`GreptimeTeam/greptimedb@7cf45a21a`), plus a jemalloc thread-cache initialization fix (`GreptimeTeam/greptimedb@d99a88261`).

Standalone runs frontend, datanode, metadata store, procedure manager and a flownode in one process, and constructs the flownode unconditionally at `v1.2.1` (`research/greptimedb.md` F29, F30, R25).
Distributed mode is four components, frontend, datanode, metasrv and optional flownode (`research/greptimedb.md` F29).
The fleet's volume estimate is roughly 3,000 metric series and under 60,000 dev-loop events per day, and the binding constraint is cardinality policy rather than bytes (`research/otel-collector-topology.md` F41, F42, F43).

`research/store-alternatives.md` weighs SigNoz plus ClickHouse, the Prometheus/Grafana/Loki/Tempo/Mimir assembly, the VictoriaMetrics family, OpenObserve and ClickHouse-direct, and its refresh reopens none of those rejections (`research/store-alternatives.md` Refresh, "Bearing on D1, D2, D6 and D8").

## Decision

The store is the open build of GreptimeDB, run as one standalone process, consumed as `greptimedb-bin`, a first-party package of the upstream release tarball under `pkgs/by-name/greptimedb-bin`, and never from a prerelease.
`greptimedb-bin` is the intended package, not a stopgap: the release tarball embeds the dashboard that ADR-002 adopts as the dashboard layer, and the package tracks stable upstream releases through its `update.sh`.
`pkgs.greptimedb` is acceptable only if it carries the embedded dashboard.
The first deployment uses `v1.2.1`, the latest stable release; 1.1.4 is not deployed.
The `v1.3.x` line is adopted only when a stable `v1.3` release is published, and is not a precondition for deployment.
Until the deployed version ingests exponential histograms, the collector that writes to the store converts them to explicit-bucket histograms with the contrib `transform` processor's `convert_exponential_histogram_to_histogram` function (`research/greptimedb.md` "Charter reconciliation", `open-telemetry/opentelemetry-collector-contrib@aaf5045a2:processor/transformprocessor/README.md:475-479`); the collector configuration belongs to ADR-003.
Alerting is external to the store, so no enterprise-gated trigger DDL is relied on and RK1 stays retired.
The store's anonymous usage reporting to `telemetry.greptimestats.com`, on by default, is disabled (`GreptimeTeam/greptimedb@179ff8e50:config/standalone.example.toml:51`, `GreptimeTeam/greptimedb@179ff8e50:src/common/greptimedb-telemetry/src/lib.rs:30`).

## Rationale

The human input survives the evidence on capability and on the open/enterprise boundary.
Every capability D1 through D8 needs, namely OTLP ingest of three signals, PromQL, SQL, per-table and per-database TTL, object storage and Parquet export, is in the open build at the deployable versions (`research/greptimedb.md` F45, R31, R33, R37).
The one capability the design would want and cannot have, store-enforced per-person read partitioning, is withheld from every open-build candidate in the rejected set as well (`research/store-alternatives.md` Refresh, D8 paragraph), so it does not discriminate against GreptimeDB and is handled by ADR-008.
The governance objection under C3 is real and is recorded rather than dismissed; the distinguishing argument for GreptimeDB is therefore the narrow enumerated enterprise boundary and the Parquet substrate (`research/greptimedb.md` "Bearing on decisions", D1), not its governance.

Standalone is chosen because distributed mode quadruples the process count for a workload of a few thousand series, and under C1 that apparatus prevents no failure this fleet has.
The unconditional flownode in standalone is accepted rather than avoided, because removing it requires the distributed shape, which costs three more units to remove one idle in-process component.

The version policy follows the packaging evidence and ADR-002.
Consuming the root-pin attribute costs no build, because the output is cache-resident (`research/nix-packaging-status.md` R4), but it omits the dashboard ADR-002 depends on (`research/nix-packaging-status.md` R9).
Building the dashboard into a source build needs a fixed-output fetch of the dashboard assets and a roughly half-hour eight-core Rust build (`research/nix-packaging-status.md` R11, F14).
The release tarball already carries the dashboard and is checksummed upstream, so packaging it costs a download and no build (`research/nix-packaging-status.md` R10, R15; ADR-007).
The 1.1.4-to-1.2.1 delta is PromQL correctness, so a first deployment on 1.1.4 would start a new store on a superseded release with known rate-window defects; no 1.2.1 change closes the gaps listed above, which remain until `v1.3`.
Waiting for `v1.3.x` would block deployment on a beta line with no stated release date while its two material gains have workarounds: exponential histograms by collector-side conversion, and credential rotation by `restartUnits` (`research/telemetry-security-and-tenancy.md` C3).
The missing `/metadata` route costs metric help text and type hints in the Prometheus plugin of the embedded dashboard, not query results; ADR-002 owns that consequence.

## Rejected alternatives

- GreptimeDB distributed mode: four units for a single-host, few-thousand-series workload, with no failure prevented that standalone admits (`research/greptimedb.md` F29).
- GreptimeDB `v1.3.0-beta.x` now: prerelease with no published assets at `beta.2`, and its gains have workarounds on stable (`research/greptimedb.md` R1, R7, R8).
- `pkgs.greptimedb` from the root pin: omits the embedded dashboard and the dashboards API, so the dashboard layer of ADR-002 would not exist (`research/nix-packaging-status.md` R9).
- Waiting for a stable `v1.3` before any deployment: blocks the observability loop on an undated release for gains the collector and `restartUnits` already cover.
- GreptimeDB Enterprise: the only gain is store-enforced partitioning, which ADR-008 does not require because it adopts a content-free shared read zone, and it is a per-customer commercial agreement (`research/greptimedb.md` F52, `research/telemetry-security-and-tenancy.md` R3).
- VictoriaMetrics, VictoriaLogs and VictoriaTraces: strongest rejected operator floor, but OTLP is adapter-shaped and storage is opaque to the W8 substrate (`research/store-alternatives.md` F25, F29).
- Prometheus, Grafana, Loki, Tempo and Mimir: six units plus an agent on every host, Prometheus-first ingestion, and no governance advantage (`research/store-alternatives.md` F21, F22).
- SigNoz plus ClickHouse: four processes, an out-of-band migrator and three first-party derivations (`research/store-alternatives.md` F1-F7).
- OpenObserve: SSO and fine-grained authorization are private crates and no NixOS module exists (`research/store-alternatives.md` R10, R12).
- ClickHouse-direct: converts the store decision into owning three signal schemas and their migrations with no regulator (`research/store-alternatives.md` F39).

## Consequences

The store is a single point of failure for telemetry, and a store outage is survivable only to the depth of the collector's sending queue, which ADR-003 sizes.
Exponential-histogram precision is reduced to the declared explicit bucket bounds until a `v1.3` stable release is deployed, and the bucket bounds become part of ADR-004's schema.
Each later version step, 1.2.1 to `v1.3`, arrives through `greptimedb-bin`'s `update.sh` and therefore through the closure operator; the derivation and its updater are first-party and ours to maintain.
When the deployed version reaches `v1.3.0-beta.1` or later, the collector conversion can be removed, a removal tracked by the regulators below rather than by memory; the restart-on-rotation coupling stays, because `LoadCredential` snapshots credentials at start (ADR-007 Q6).
Per-person read isolation is not a store property, and any design text that treats a GreptimeDB schema as a tenant boundary is wrong (`research/telemetry-security-and-tenancy.md` F30).
Alerting needs a component outside the store, which this record does not choose.

## Operating envelope and regulator

Envelope E1.1, version and dashboard: the deployed store package's version is a stable `MAJOR.MINOR.PATCH` with no prerelease suffix, and the package serves the embedded dashboard; `greptimedb-bin` is the package, and `pkgs.greptimedb` qualifies only if it carries the dashboard.
Regulator R1.1, amended under charter v11: an evaluation-time assertion in the store module (ADR-007) that `cfg.package.version` matches `^[0-9]+\.[0-9]+\.[0-9]+$` and that `cfg.package.passthru.embedsDashboard` is `true`, which `greptimedb-bin` sets; it fails on two mutants enumerated in the check per the existing mutant-asserting pattern (`research/dev-loop-signals.md` F12): `package` set to an `overrideAttrs` with version `1.3.0-beta.2`, and `package` set to the pinned `pkgs.greptimedb`, which lacks `passthru.embedsDashboard`.
The runtime half of R1.1 is a case of S1's on-demand container test `vmTests.x86_64-linux.greptimedb-pipeline`: `GET http://127.0.0.1:4000/dashboard/` returns 200, so a package whose attribute claims the dashboard without serving it is caught when the test runs.

Envelope E1.2, histogram compatibility: while the deployed version is below `1.3.0`, every collector pipeline that exports metrics to the store contains the exponential-to-explicit histogram conversion.
Regulator R1.2: an evaluation-time assertion that reads both the store package version and the magnetite collector's generated configuration and fails if the version is below `1.3.0` and the conversion statement is absent; its mutant removes the statement.
This regulator is coupled to ADR-003's collector configuration and is the mechanism by which the conversion is removed when it stops being needed.

Envelope E1.3, edition: no configuration path depends on trigger DDL, `UNDROP TABLE`, the recycle bin, `purge_table` or tracked flow writes (`research/greptimedb.md` R38).
Regulator R1.3: none automated beyond the open build's own refusal, because the open binary rejects those statements at parse or execution time; this is the open build failing closed rather than a regulator, and the human gate records it as such.

Envelope E1.4, egress: the store makes no outbound connection other than to the R2 endpoint.
Regulator R1.4: an evaluation-time assertion that the generated TOML sets `enable_telemetry = false`; its mutant omits the key, which the upstream default turns into `true`.

## Failure prevented

Standalone instead of distributed prevents three additional units, each with its own memory floor, on a host that has OOM-killed twice (`research/otel-collector-topology.md` R21).
The no-prerelease version rule prevents a beta store, with release artifacts not yet published, from becoming a fleet dependency through an overlay.
The dashboard clause of R1.1 prevents a package switch that silently removes the dashboard layer and the dashboards API from the store.
The histogram conversion prevents silent loss of every exponential-histogram series, which the store drops without error (`research/greptimedb.md` R7).
Disabling usage reporting prevents an undeclared outbound connection from the host that holds agent-session telemetry.
External alerting prevents a design that silently depends on an enterprise-only feature and reopens RK1.

## Implementation surface

- No new flake input.
- `pkgs/by-name/greptimedb-bin/{package.nix,update.sh}`: the upstream release tarball for `x86_64-linux`, with `passthru.embedsDashboard = true`, and `apps.update-greptimedb-bin`; its build details are specified in ADR-007.
- `modules/nixos/greptimedb.nix`: the store module and the assertions R1.1, R1.2 and R1.4; its file list, options and secrets are specified in ADR-007.
- `modules/vm-tests/greptimedb-pipeline.nix`: S1's on-demand container test, carrying the runtime case of R1.1.
- The magnetite collector configuration that carries the histogram conversion is listed in ADR-003.
- No clan vars generator is introduced by this record; the credential generators are in ADR-007 and the R2 generators are in ADR-006.

## Questions for the human gate

Q1 Deploy `v1.2.1` first? Recommended at the gate: yes, through a root-pin bump that includes https://github.com/NixOS/nixpkgs/pull/574558 (merged 2026-10-15), with `greptimedb-bin` held for a channel delay; deploying 1.1.4 first starts the store on a superseded release.
Resolution: recommended answer accepted at the 2026-10-15 gate.
Amended under charter v11: `v1.2.1` is deployed as `greptimedb-bin`, the intended package rather than a fallback, because the nixpkgs build omits the dashboard ADR-002 adopts.
Q2 Is the governance objection C3 a disqualifier for single-vendor stores, or an axis? Recommended: an axis, because every candidate in the evidence base is single-vendor (`research/store-alternatives.md` F22, F30); treating it as a disqualifier leaves no admissible store.
Resolution: recommended answer accepted at the 2026-10-15 gate.
Q3 Is in-database alerting wanted? Recommended: no, alerting stays external; the alternative is an Enterprise dependency and reopens RK1.
Resolution: recommended answer accepted at the 2026-10-15 gate.
Q4 Is store-side per-person read partitioning required, which only GreptimeDB Enterprise provides? Recommended: no; ADR-008 adopts a shared read zone, because neither the store nor Perses can partition reads; the alternative is a commercial agreement or a first-party `PermissionChecker` provider.
Resolution: recommended answer accepted at the 2026-10-15 gate.
Q5 Is the unconditional flownode in standalone acceptable under C1? Recommended: yes; the alternative is the distributed shape with three more units.
Resolution: recommended answer accepted at the 2026-10-15 gate.
Q6 Should a `v1.3` stable be adopted through an overlay ahead of nixpkgs once it is tagged? Recommended: no, wait for the root pin; the alternative is a local half-hour Rust build in the closure operator or a `-bin` derivation (see ADR-007).
Resolution: recommended answer accepted at the 2026-10-15 gate.
