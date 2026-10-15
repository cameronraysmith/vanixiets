---
title: "ADR-006: Storage substrate and lakehouse seam"
---

## Status

Proposed

## Context

Charter D6 asks whether telemetry lands as Parquet reachable by the repository's DuckDB/DuckLake analytics path or in a separate silo.
W8 records Arrow, Parquet, DuckDB and DuckLake as this repository's analytics substrate, and `preferences-data-modeling` prescribes append-only, time-partitioned Parquet with idempotent delete-insert at partition boundaries and lookback windows for late data.
The human gate of 2026-10-06 placed the store's data on Cloudflare R2.
ADR-001 fixes the store as GreptimeDB standalone, and ADR-004 fixes the databases and their retention: `fleet` at 30 days with fleet logs at 14 days, `devloop` at 365 days, and `agent` at 90 days.

GreptimeDB SSTs are Parquet files at `<table_dir>/<region_id>/{data,metadata}/<file_id>.parquet` with region metadata in Parquet key-value metadata (`research/greptimedb.md` F21, F22).
The flat SST format, which stores raw named tag columns, is the default at `v1.1.4` and `v1.2.1` (`research/greptimedb.md` R32).
A correct external read still has to take the live file set from the per-region manifest and resolve `__sequence` and `__op_type` (`research/greptimedb.md` F27).
A table created with the legacy format collapses tags into an opaque `__primary_key` column (`research/greptimedb.md` F23, F26).

Parquet export exists in the open build at `v1.2.1` as SQL `COPY ... TO` and as `COPY DATABASE ... TO ... WITH (format = 'parquet', start_time, end_time)` (`research/greptimedb.md` R33).
`COPY` to an S3 target accepts `endpoint`, `region`, `enable_virtual_host_style` and `disable_ec2_metadata`, so an export into R2 needs no extra component (`research/greptimedb.md` R34).
`COPY DATABASE` requires a directory location ending in a separator and writes one file per base table, named `<table>.parquet`, skipping metric-engine physical tables (`GreptimeTeam/greptimedb@179ff8e50:src/operator/src/statement/copy_database.rs:82`, `:120-139`).
Its `parallelism` option defaults to the host's CPU count, which is 16 on `magnetite` (`GreptimeTeam/greptimedb@179ff8e50:src/operator/src/statement/copy_database.rs:66-72`, `research/otel-collector-topology.md` F39).
Arrow Flight is registered at `v1.2.1` (`research/greptimedb.md` R36).

R2 is configured through the S3 backend as `type = "S3"`, endpoint `https://<ACCOUNT_ID>.r2.cloudflarestorage.com`, `region = "auto"`, path-style addressing and `disable_ec2_metadata = true` (`research/greptimedb.md` R14-R19).
R2 implements every object operation the storage layer needs and lacks only tagging and ACLs (`research/greptimedb.md` R18).
No GreptimeDB source or example mentions R2, so that stanza is derived and has not been exercised against a live bucket (`research/greptimedb.md` R20).
Object storage forces the mito write cache on and keeps a read cache, defaulting to 5 GiB and 5 GB, so the local floor on the store host is roughly 10 GB of cache plus WAL and metadata (`research/greptimedb.md` R21-R23).

The repository already holds R2 credentials for another service, minted per bucket in the Cloudflare dashboard and delivered as a hidden-prompt clan vars generator with `restartUnits` (`cameronraysmith/vanixiets@109c67346:modules/machines/nixos/magnetite/default.nix:334-367`, `research/telemetry-security-and-tenancy.md` F38).
No DuckDB or DuckLake service is deployed in the fleet; DuckDB is consumed from nixpkgs on demand (`cameronraysmith/vanixiets@109c67346:pkgs/disabled/README.md:10`).
The dev-loop signals are batch-shaped and analytic rather than alerting-shaped (`research/dev-loop-signals.md` "Bearing on decisions", D6).

The rejected-alternatives unit records that Tempo and OpenObserve beat GreptimeDB on in-place Parquet readability (`research/store-alternatives.md` F20, F31), and asks that this be carried into D6 explicitly.

## Decision

The store's own substrate is GreptimeDB SST Parquet on a dedicated R2 bucket, and the lakehouse seam is a scheduled Parquet export into a second R2 bucket, not external reads of the store's SSTs.
A systemd timer on the store host runs once a day and issues `COPY DATABASE devloop TO 's3://<export-bucket>/devloop/date=<D>/' WITH (format = 'parquet', start_time = '<D>T00:00:00Z', end_time = '<D+1>T00:00:00Z', parallelism = 1)` for each of the last three UTC days, so each day's partition is rewritten twice more to absorb late data from intermittent hosts.
Only the `devloop` database is exported by default; `fleet` and `agent` stay in the store and expire under their TTLs.
Consumers read the export with DuckDB's `httpfs` over a read-only R2 token, as `read_parquet('s3://<export-bucket>/devloop/date=*/<table>.parquet', hive_partitioning = true)`.
Registering the export in a DuckLake catalog is deferred until a second consumer needs catalog semantics.
Every store table is created with the flat SST format, which is the default, and no table may set `sst_format` to the legacy value.
The store's local cache and WAL live on a dedicated ZFS dataset with its own quota and reservation, sized in ADR-007.

## Rationale

An export decouples the analytics path from the store's internal layout.
In-place SST reads would require every DuckDB consumer to parse region manifests and to merge `__sequence` and `__op_type` (`research/greptimedb.md` F27), and would expose the store's own bucket, including its manifests, to read credentials held outside the store host.
The export writes plain Parquet with one row per stored row, so a consumer needs nothing beyond `read_parquet`.

`COPY DATABASE` to S3 is already in the open build and takes the R2 connection options directly (`research/greptimedb.md` R33, R34), so the seam adds a timer unit and a credential, not a service.
Date-partitioned directories with a re-exported three-day window are the append-only, time-partitioned, idempotent pattern `preferences-data-modeling` prescribes, and the window exists because five of ten machines are intermittent (`research/otel-collector-topology.md` F5).
`parallelism = 1` bounds the export's concurrent table scans on a host with recorded memory exhaustion (`research/otel-collector-topology.md` R21) instead of the default of one per core.

Exporting `devloop` alone follows from what each database is for.
Dev-loop data is the primary consumer under the charter and the one whose questions are batch analytics over months (`research/dev-loop-signals.md` D6 bearing).
`fleet` data answers operational questions inside its 30-day TTL.
`agent` data carries identifying attributes whose retention is an open D8 question (`research/telemetry-security-and-tenancy.md` Q6), and an export copy would escape both the store TTL and the Kanidm-admitted read zone of ADR-008.

A DuckLake catalog is deferred under C1 because no deployed consumer requires snapshots or ACID registration today, and a hive-partitioned prefix is readable by DuckDB without one.
The export layout is compatible with later registration because it is immutable per partition and named by date.

R2 is retained for the store's substrate as the human chose, with one recorded risk: the stanza is untested (`research/greptimedb.md` R20).
The regulator below makes the first failure of that stanza visible at deploy time rather than at first query.
The fallback, local `File` storage on the dedicated dataset, needs no change to the export seam, because the seam does not depend on where the store keeps its SSTs; it does require raising the dataset quota to hold the SSTs (ADR-007).

## Rejected alternatives

- External DuckDB reads of the store's SSTs in place: requires manifest parsing and sequence/op-type merging per consumer and exposes the store bucket (`research/greptimedb.md` F27).
- Separate silo with no seam: contradicts W8 and leaves the batch-shaped dev-loop history unreachable by the analytics path (`research/dev-loop-signals.md` D6 bearing).
- Arrow Flight from DuckDB to the store: Flight is served (`research/greptimedb.md` R36), but no DuckDB Flight client is established in this corpus, and an online query path loads the co-tenanted store at analysis time.
- DuckDB over the store's PostgreSQL wire protocol: compatibility is unverified and it requires enabling a port ADR-002 and ADR-007 keep disabled.
- `greptime cli data export` instead of a SQL `COPY`: it issues the same `COPY DATABASE` statement (`research/greptimedb.md` R33) and adds a client process and a second credential path.
- Exporting all three databases: copies agent-session data outside the TTL and the Kanidm-admitted read zone of ADR-008.
- A DuckLake catalog now: no consumer needs catalog semantics yet, so it prevents no named failure (C1).
- Tempo or OpenObserve for their native Parquet: rejected as stores in ADR-001, and the export seam closes the readability gap they hold.
- Local `File` storage instead of R2: overrides the human input without evidence that R2 fails; retained as the fallback.

## Consequences

The analytics view of dev-loop data lags the store by up to one day and converges over three days.
`devloop` history beyond the in-store 365-day TTL exists only in the export bucket, so the export bucket has no lifecycle rule by default and its growth becomes part of the envelope.
The export is a second copy of dev-loop data in R2, so R2 storage roughly doubles for that database within its TTL.
Schema evolution in the store appears in the export as per-day column-set differences, which DuckDB reads with `union_by_name = true`.
The export runs inside the store process and consumes its scan memory budget, so a large backfill must be run in daily steps.
If the R2 stanza fails at first deployment, the store moves to local `File` storage on the dedicated dataset, whose quota must then be raised to hold the SSTs (ADR-007), and the export continues unchanged.

## Operating envelope and regulator

Envelope E6.1, export freshness: the export partition for UTC day D-1 exists by 06:00 UTC on day D, and the export unit's last run succeeded.
Regulator R6.1: the store-host probe timer of ADR-007 reads the export unit's `Result` and `ExecMainExitTimestamp` from systemd and lists `devloop/date=<D-1>/` in the export bucket with the `greptimedb-r2-export` token, and the probe unit fails if either the result is not `success`, the timestamp is older than 30 hours, or the listing is empty.
It is shown able to fail by running it once against a date for which no partition exists and observing a failed unit, recorded in the implementing change.

Envelope E6.2, store substrate size: the sum of `sst_size` over `information_schema.region_statistics` stays under 50 GiB, against an estimate an order of magnitude lower for roughly 3,000 series and under 60,000 dev-loop events per day `[INFERENCE: from research/otel-collector-topology.md F41, F42; log volume is unmeasured]`.
Regulator R6.2: the same probe queries `information_schema.region_statistics` (`GreptimeTeam/greptimedb@179ff8e50:src/catalog/src/system_schema/information_schema/region_statistics.rs:46-49`) over the loopback HTTP SQL endpoint and fails above the bound.

Envelope E6.3, readable format: no table in any database has `sst_format` set to the legacy format.
Regulator R6.3: the same probe queries the `create_options` column of `information_schema.tables` (`GreptimeTeam/greptimedb@179ff8e50:src/catalog/src/system_schema/information_schema/tables.rs:67`) and fails on any legacy-format table; its negative control is a scratch table created with the legacy option during the implementing change.

Envelope E6.4, R2 substrate reachability: the store can write and list its manifest objects on R2.
Regulator R6.4: the store's `/ready` endpoint after start, checked by the probe, plus a NixOS evaluation-time assertion that `disable_ec2_metadata = true`, `region = "auto"` and `enable_virtual_host_style = false` are set when `type = "S3"`; the assertion's mutant drops `disable_ec2_metadata`.

## Failure prevented

The export seam prevents every analytics consumer from depending on GreptimeDB's internal manifest and merge semantics, which change across releases.
The three-day re-export window prevents permanent loss from the analytics copy of dev-loop rows that intermittent hosts deliver late.
`parallelism = 1` prevents the export from launching sixteen concurrent table scans on a host that has OOM-killed twice.
Excluding `agent` from export prevents agent-session telemetry from escaping the TTL and the Kanidm-admitted read zone of ADR-008.
The legacy-format check prevents a table whose tags are unrecoverable outside the store from entering the export.
The two-bucket split prevents an analytics read token from reading or corrupting the store's SSTs and manifests.

## Implementation surface

- `modules/nixos/greptimedb.nix` (ADR-007): `services.greptimedb.export` options for the database list, bucket, prefix, schedule and lookback days; a `greptimedb-export.service` oneshot and `greptimedb-export.timer`; the R6.4 assertion.
- `modules/nixos/greptimedb.nix`: the probe of R6.1 to R6.3 as checks inside the `greptimedb-envelope` unit defined in ADR-007.
- Clan vars generator `greptimedb-r2` on `magnetite`: hidden prompts `access-key` and `secret-key` with `persist = true` and per-file `deploy = false`, rendered to an `env` file with `GREPTIMEDB_STANDALONE__STORAGE__ACCESS_KEY_ID` and `GREPTIMEDB_STANDALONE__STORAGE__SECRET_ACCESS_KEY` (`GreptimeTeam/greptimedb@179ff8e50:src/cmd/src/standalone.rs:287`, `GreptimeTeam/greptimedb@179ff8e50:src/common/config/src/config.rs:23`), `restartUnits = [ "greptimedb.service" ]`, following `omnigraph-r2`.
- Clan vars generator `greptimedb-r2-export` on `magnetite`: hidden prompts for a token scoped read-write to the export bucket only, rendered to a file the export unit reads through `LoadCredential`.
- Clan vars generator `telemetry-export-reader`, `share = true`, for each analytics host: hidden prompts for a token scoped read-only to the export bucket; the set of analytics hosts is Q3.
- Two R2 buckets created in the Cloudflare dashboard, outside this repository.
- No new flake input.

## Questions for the human gate

Q1 Does the seam mean in-place reads of the store's SSTs or a scheduled export? Recommended: scheduled export; the alternative couples every consumer to the store's manifest format (`research/greptimedb.md` Q2, `research/store-alternatives.md` Q4).
Q2 Should `fleet` or `agent` also be exported? Recommended: neither; exporting `agent` moves identifying data outside ADR-008's boundary, and exporting `fleet` doubles its R2 footprint for operational data with a 30-day horizon.
Q3 Which hosts hold the read-only export token? Recommended: the human operators' primary workstations only; the alternative of every host widens read access to dev-loop history to worker accounts.
Q4 Should the export bucket carry an R2 lifecycle expiry? Recommended: no expiry until a year of data exists and its size is measured; the alternative caps history before its value is known.
Q5 Should a DuckLake catalog be added now? Recommended: no, defer until a second consumer needs snapshots; the alternative adds a catalog file and its ownership with no failure prevented.
Q6 What are the two bucket names? Recommended: `fleet-telemetry-store` and `fleet-telemetry-export`; any names work if each token is scoped to one bucket.
Q7 Is local `File` storage acceptable as the fallback if the R2 stanza fails its first deployment? Recommended: yes; the alternative blocks the store on debugging an untested S3-compatible path.
Q8 How nixbot rows reach `devloop` is decided by ADR-005 Q1, which owns that signal; no question remains here.
