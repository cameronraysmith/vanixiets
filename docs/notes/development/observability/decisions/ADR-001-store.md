---
title: "ADR-001: Telemetry store"
---

## Status

Proposed

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
The latest stable release is `v1.2.1` of 2026-09-16, and the nixpkgs bump to it is open as https://github.com/NixOS/nixpkgs/pull/574558 (`research/greptimedb.md` R1, `research/nix-packaging-status.md` R6).
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

The store is the open build of GreptimeDB, run as one standalone process, consumed as `pkgs.greptimedb` from the root nixpkgs input and never from a prerelease.
The first deployment uses the highest stable version present at the root pin when implementation starts, which is 1.1.4 today and 1.2.1 once https://github.com/NixOS/nixpkgs/pull/574558 reaches the pin.
The `v1.3.x` line is adopted only when a stable `v1.3` tag reaches the root pin, and is not a precondition for deployment.
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

The version policy follows the packaging evidence.
Consuming the root-pin attribute costs no build, because the output is cache-resident (`research/nix-packaging-status.md` R4).
Every route to 1.2.1 ahead of nixpkgs adds either a roughly half-hour eight-core Rust build (`research/nix-packaging-status.md` F14) or a second packaging convention for one package (see ADR-007).
The 1.1.4-to-1.2.1 delta is PromQL correctness, which is why 1.2.1 is preferred for the first deployment when it is available, but no 1.2.1 change closes a gap the design depends on, because exponential histograms, `/metadata`, bearer tokens and hot credential reload are absent from both.
Waiting for `v1.3.x` would block deployment on a beta line with no stated release date while its two material gains have workarounds: exponential histograms by collector-side conversion, and credential rotation by `restartUnits` (`research/telemetry-security-and-tenancy.md` C3).
The missing `/metadata` route costs metric help text and type hints in the Perses Prometheus plugin, not query results; ADR-002 owns that consequence.

## Rejected alternatives

- GreptimeDB distributed mode: four units for a single-host, few-thousand-series workload, with no failure prevented that standalone admits (`research/greptimedb.md` F29).
- GreptimeDB `v1.3.0-beta.x` now: prerelease with no published assets at `beta.2`, and its gains have workarounds on stable (`research/greptimedb.md` R1, R7, R8).
- Waiting for a stable `v1.3` before any deployment: blocks the observability loop on an undated release for gains the collector and `restartUnits` already cover.
- GreptimeDB Enterprise: the only gain is store-enforced partitioning, which ADR-008 does not require because it adopts a content-free shared read zone, and it is a per-customer commercial agreement (`research/greptimedb.md` F52, `research/telemetry-security-and-tenancy.md` R3).
- VictoriaMetrics, VictoriaLogs and VictoriaTraces: strongest rejected operator floor, but OTLP is adapter-shaped and storage is opaque to the W8 substrate (`research/store-alternatives.md` F25, F29).
- Prometheus, Grafana, Loki, Tempo and Mimir: six units plus an agent on every host, Prometheus-first ingestion, and no governance advantage (`research/store-alternatives.md` F21, F22).
- SigNoz plus ClickHouse: four processes, an out-of-band migrator and three first-party derivations (`research/store-alternatives.md` F1-F7).
- OpenObserve: SSO and fine-grained authorization are private crates and no NixOS module exists (`research/store-alternatives.md` R10, R12).
- ClickHouse-direct: converts the store decision into owning three signal schemas and their migrations with no regulator (`research/store-alternatives.md` F39).

## Consequences

The store is a single point of failure for telemetry, and a store outage is survivable only to the depth of the collector's sending queue, which ADR-003 sizes.
Exponential-histogram precision is reduced to the declared explicit bucket bounds until a `v1.3` stable reaches the pin, and the bucket bounds become part of ADR-004's schema.
Each later version step, 1.1.4 to 1.2.1 to `v1.3`, arrives through a root-pin bump and therefore through the closure operator, with no first-party derivation to maintain.
When the deployed version reaches `v1.3.0-beta.1` or later, the collector conversion and the restart-on-rotation coupling can be removed; both removals are tracked by the regulators below rather than by memory.
Per-person read isolation is not a store property, and any design text that treats a GreptimeDB schema as a tenant boundary is wrong (`research/telemetry-security-and-tenancy.md` F30).
Alerting needs a component outside the store, which this record does not choose.

## Operating envelope and regulator

Envelope E1.1, version: the deployed store package is `pkgs.greptimedb` from the root nixpkgs input, its version is a stable `MAJOR.MINOR.PATCH` with no prerelease suffix, and no overlay or first-party derivation shadows the attribute.
Regulator R1.1: an evaluation-time assertion in the store module (ADR-007) that `cfg.package.version` matches `^[0-9]+\.[0-9]+\.[0-9]+$` and that `cfg.package` is `pkgs.greptimedb`; it fails on a mutant that sets `package` to an `overrideAttrs` with version `1.3.0-beta.2`, and that mutant is enumerated in the check per the existing mutant-asserting pattern (`research/dev-loop-signals.md` F12).

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
The histogram conversion prevents silent loss of every exponential-histogram series, which the store drops without error (`research/greptimedb.md` R7).
Disabling usage reporting prevents an undeclared outbound connection from the host that holds agent-session telemetry.
External alerting prevents a design that silently depends on an enterprise-only feature and reopens RK1.

## Implementation surface

- No new flake input: `pkgs.greptimedb` comes from the existing root `nixpkgs` input.
- `modules/nixos/greptimedb.nix`: the store module and the assertions R1.1, R1.2 and R1.4; its file list, options and secrets are specified in ADR-007.
- The magnetite collector configuration that carries the histogram conversion is listed in ADR-003.
- No clan vars generator is introduced by this record; the credential generators are in ADR-007 and the R2 generators are in ADR-006.

## Questions for the human gate

Q1 Should the first deployment wait for https://github.com/NixOS/nixpkgs/pull/574558 to reach the root pin? Recommended: no, deploy whichever stable version is at the pin when implementation starts; the alternative delays the loop for PromQL fixes that dashboards over a new store will not yet exercise.
Q2 Is the governance objection C3 a disqualifier for single-vendor stores, or an axis? Recommended: an axis, because every candidate in the evidence base is single-vendor (`research/store-alternatives.md` F22, F30); treating it as a disqualifier leaves no admissible store.
Q3 Is in-database alerting wanted? Recommended: no, alerting stays external; the alternative is an Enterprise dependency and reopens RK1.
Q4 Is store-side per-person read partitioning required, which only GreptimeDB Enterprise provides? Recommended: no; ADR-008 adopts a shared read zone, because neither the store nor Perses can partition reads; the alternative is a commercial agreement or a first-party `PermissionChecker` provider.
Q5 Is the unconditional flownode in standalone acceptable under C1? Recommended: yes; the alternative is the distributed shape with three more units.
Q6 Should a `v1.3` stable be adopted through an overlay ahead of nixpkgs once it is tagged? Recommended: no, wait for the root pin; the alternative is a local half-hour Rust build in the closure operator or a `-bin` derivation (see ADR-007).
