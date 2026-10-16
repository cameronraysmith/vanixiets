---
title: "parquet-export"
---

## Purpose

The Parquet export is the lakehouse seam: a daily copy of the `devloop` database into the existing R2 bucket `sciexp` as date-partitioned Parquet, read by DuckDB without any knowledge of the store's internal layout (ADR-006 Decision).
It is the only path to dev-loop history older than the store's 365-day TTL (ADR-004 Decision, ADR-005 Consequences).
It consists of a timer-driven oneshot on the store host, which runs the export inside the GreptimeDB process, and a reader command on each analytics host, which issues DuckDB a prefix-confined read credential.

## Decisions realized

- ADR-006 Decision and Q1: the seam is a scheduled export, not external reads of the store's SSTs.
- ADR-006 Decision and Q6: the export lives in the existing bucket `sciexp` under `projects/vanixiets/observability/export/`, following web-verification D9's `projects/<project>/<kind>/` layout, and no bucket is created.
- ADR-006 Decision: a systemd timer on the store host runs once a day and issues `COPY DATABASE devloop TO 's3://sciexp/projects/vanixiets/observability/export/devloop/date=<D>/' WITH (format = 'parquet', start_time = '<D>T00:00:00Z', end_time = '<D+1>T00:00:00Z', parallelism = 1)` for each of the last three UTC days.
- ADR-006 Decision: each day's partition is therefore rewritten twice more, which absorbs late data from intermittent hosts.
- ADR-006 Decision: before each `COPY` the oneshot signs, from the `greptimedb-r2` token as parent, a temporary credential with scope `object-read-write`, prefix `projects/vanixiets/observability/export/` and a 15-minute lifetime, using the claims and derivation of D9's `mint`, and passes it as `access_key_id`, `secret_access_key` and `session_token`.
- ADR-006 Decision: the oneshot unsets the parent secret after signing, so the parent never appears in a statement, an argument vector or a child's environment.
- ADR-006 Decision and Q2: only `devloop` is exported; `fleet` and `agent` stay in the store and expire under their TTLs.
- ADR-006 Decision and Q3: readers sign an `object-read-only` credential for the export prefix on their own host, from the read-only parent token `telemetry-export-reader`, held only on the human operators' primary workstations.
- ADR-006 Decision: the reader credential's lifetime is one hour, and a session that outlives it re-runs the reader command.
- ADR-006 Decision and Q4: the export prefix carries no lifecycle expiry until a year of data exists and its size is measured; any later expiry is a rule in the existing `cloudflare_r2_bucket_lifecycle.sciexp` resource, and no second lifecycle resource is created.
- ADR-006 Decision and Q5: no DuckLake catalog until a second consumer needs catalog semantics.
- ADR-006 Decision: every store table uses the flat SST format, so exported rows carry named tag columns.
- ADR-007 Decision: the oneshot authenticates to the store as the `admin:rw` user, whose only holders are `greptimedb-schema` and `greptimedb-export`.

## Placement

- Export host: `magnetite`, the store host (ADR-006 Decision, ADR-007 Decision).
- Export units: `greptimedb-export.service`, a oneshot, and `greptimedb-export.timer`, daily (ADR-006 Implementation surface).
- The `COPY` runs inside the store process and consumes its scan memory budget, bounded by ADR-007's `scan_memory_limit = "512MB"` and `memory_pool_size = "512MB"` (ADR-006 Consequences, ADR-007 Decision).
- Reader hosts: the human operators' primary workstations only (ADR-006 Q3).
- Reader runtime: DuckDB from nixpkgs on demand, with no DuckDB or DuckLake service deployed (ADR-006 Context).

## Interfaces

Upstream:

- The store's `devloop` database, reached as the `admin` user over the store's only listener, HTTP on `127.0.0.1:4000` (ADR-007 Decision).
- `COPY DATABASE` writes one file per base table, named `<table>.parquet`, into a directory location ending in a separator, and skips metric-engine physical tables (ADR-006 Context).
- The `devloop` tables and their columns, primary keys and time indexes are ADR-004's: CI attribute outcome, CI build timing, merge-queue batch event and deploy record (ADR-004 Decision).

Object layout:

- Bucket `sciexp`, prefix `projects/vanixiets/observability/export/devloop/date=<D>/<table>.parquet`, one directory per UTC day (ADR-006 Decision).
- The store's own prefix, `projects/vanixiets/observability/store/`, is never written by the export and never readable by an export reader credential (ADR-006 Failure prevented).
- R2 endpoint `https://<ACCOUNT_ID>.r2.cloudflarestorage.com` with `region = "auto"`, path-style addressing and `disable_ec2_metadata = true`, which `COPY` to S3 accepts as `endpoint`, `region`, `enable_virtual_host_style` and `disable_ec2_metadata` (ADR-006 Context).

Downstream:

- DuckDB reads `read_parquet('s3://sciexp/projects/vanixiets/observability/export/devloop/date=*/<table>.parquet', hive_partitioning = true)` over `httpfs`, with a DuckDB S3 secret carrying `KEY_ID`, `SECRET` and `SESSION_TOKEN` (ADR-006 Decision).
- Schema evolution in the store appears as per-day column-set differences, which DuckDB reads with `union_by_name = true` (ADR-006 Consequences).

Credentials consumed:

| Credential | Generator | Consumer | Delivery |
|---|---|---|---|
| Store `admin` password | `greptimedb-users` file `admin-password` (ADR-007) | `greptimedb-export.service` | loaded at each start (ADR-007 Decision) |
| R2 parent, Object Read & Write on `sciexp` | `greptimedb-r2` (ADR-006) | `greptimedb-export.service`, signing `object-read-write` export-prefix credentials | `env` file through `LoadCredential` at each start, no `restartUnits` entry (ADR-006 Implementation surface) |
| R2 parent, Object Read only on `sciexp` | `telemetry-export-reader`, `share = true` (ADR-006) | the reader command, signing `object-read-only` export-prefix credentials | held on each reader host; the parent never reaches DuckDB (ADR-006 Decision) |

The `greptimedb-r2` parent can read, write and delete every object in `sciexp`, the same blast radius `omnigraph-r2` already has on `magnetite` (ADR-006 Consequences, Q9).
The `telemetry-export-reader` parent can read every object in `sciexp`, so a host that holds it is trusted with read access to the whole bucket (ADR-006 Consequences).

Failure notification:

- `greptimedb-export.service` sets `OnFailure=observability-notify@%n.service`, the notifier of ADR-003 with delivery per ADR-009 (ADR-003 Q9, ADR-007 Decision).

## Configuration surface

- `modules/nixos/greptimedb.nix` (ADR-007): `services.greptimedb.export` options for the database list, prefix, schedule and lookback days, with the bucket fixed to `sciexp` (ADR-006 Implementation surface).
- `modules/nixos/greptimedb.nix`: `greptimedb-export.service`, which loads the `greptimedb-r2` `env` file through `LoadCredential` and signs one temporary credential per `COPY` with the claims and derivation of D9's `mint` (`cameronraysmith/vanixiets@109c67346:modules/apps/docs/publish-evidence.sh:471-502`), and `greptimedb-export.timer` (ADR-006 Implementation surface).
- `modules/nixos/greptimedb.nix`: the R6.4 assertion clause that the export location lies under `projects/vanixiets/observability/export/` (ADR-006 R6.4).
- `modules/nixos/greptimedb.nix`: the R6.1 probe inside the `greptimedb-envelope` unit, signing its `object-read-only` credential from `greptimedb-r2` the same way (ADR-006 Implementation surface).
- Clan vars generator `greptimedb-r2` on `magnetite`: specified in `components/greptimedb.md` and ADR-006 Implementation surface; the export needs no `restartUnits` entry.
- Clan vars generator `telemetry-export-reader`, `share = true`, on each reader host of ADR-006 Q3: hidden prompts for an R2 token with Object Read only on `sciexp`, used only as the parent from which the reader command signs export-prefix credentials (ADR-006 Implementation surface).
- The reader command on each reader host: signs an `object-read-only` credential for `projects/vanixiets/observability/export/` and prints the DuckDB `CREATE SECRET` statement (ADR-006 Implementation surface).
- `modules/terranix/cloudflare.nix`: no bucket resource and no rule now; under ADR-006 Q4 an expiry, when decided, is one rule with prefix `projects/vanixiets/observability/export/` in `cloudflare_r2_bucket_lifecycle.sciexp` (ADR-006 Implementation surface).
- No new flake input (ADR-006 Implementation surface).

## Operating envelope and regulator

| Envelope | Regulator | Source |
|---|---|---|
| E6.1 export freshness: the partition for UTC day D-1 exists by 06:00 UTC on day D, and the export unit's last run succeeded | R6.1: the `greptimedb-envelope` probe reads the export unit's `Result` and `ExecMainExitTimestamp` and lists `projects/vanixiets/observability/export/devloop/date=<D-1>/` with an `object-read-only` export-prefix credential signed from `greptimedb-r2`, failing if the result is not `success`, the timestamp is older than 30 hours, or the listing is empty | ADR-006 |
| E6.3 readable format: no table has `sst_format` set to the legacy format | R6.3: the probe queries `create_options` in `information_schema.tables` and fails on any legacy-format table | ADR-006 |
| E6.4 export location: the export location lies under `projects/vanixiets/observability/export/` | R6.4: evaluation-time assertion in `modules/nixos/greptimedb.nix` | ADR-006 |
| Scan load: `parallelism = 1` on every `COPY` | none separate; the store's `scan_memory_limit` with `scan_memory_on_exhausted = "fail"` makes an oversized export fail rather than wait, and R7.2 samples the store cgroup's memory | ADR-006 Rationale, ADR-007 Decision and R7.2 |

A failed probe is a failed `greptimedb-envelope` unit, and a failed export is a failed `greptimedb-export` unit, each reaching a human through `OnFailure=observability-notify@%n.service` (ADR-003 Q9, ADR-007 R7.2).
The analytics view of dev-loop data lags the store by up to one day and converges over three days (ADR-006 Consequences).
Because the export prefix has no expiry by default, its growth is part of the envelope, and R2 storage for `devloop` roughly doubles within its TTL (ADR-006 Consequences).

## Failure prevented

- The export seam: every analytics consumer depending on GreptimeDB's internal manifest and merge semantics, which change across releases (ADR-006).
- The three-day re-export window: permanent loss from the analytics copy of dev-loop rows that intermittent hosts deliver late (ADR-006).
- `parallelism = 1`: the export launching sixteen concurrent table scans on a host that has OOM-killed twice (ADR-006).
- Excluding `agent`: agent-session telemetry escaping the TTL and the Kanidm-admitted read zone of ADR-008 (ADR-006).
- The legacy-format check: a table whose tags are unrecoverable outside the store entering the export (ADR-006).
- Export-prefix credentials: an analytics reader reading or corrupting the store's SSTs and manifests, and the export writing outside its prefix (ADR-006).
- Signing per run from the store's token instead of a second long-lived token: a wrong location in a `COPY` overwriting another project's keys, with no confinement lost (ADR-006 Rationale).
- Placing any export rule in `cloudflare_r2_bucket_lifecycle.sciexp`: a second lifecycle resource deleting the browser-evidence expiries and the multipart-abort rule (ADR-006).
- Exporting `devloop` before its TTL: loss of CI history beyond one year, the only such path (ADR-005 Consequences).

## Deployment acceptance items

- R6.1 is shown able to fail by running it once against a date for which no partition exists and observing a failed unit, recorded in the implementing change (ADR-006 R6.1).
- R2's acceptance of a one-hour lifetime on a locally signed reader credential is not checked (ADR-006 Decision).
- The `object-read-only` scope and the two observability prefixes have not been checked against R2 (ADR-006 Consequences).
- R6.3's negative control is a scratch table created with the legacy option during the implementing change (ADR-006 R6.3).
- A large backfill must be run in daily steps, because the export consumes the store's scan memory budget (ADR-006 Consequences).

## Deferred

- DuckLake catalog registration: deferred until a second consumer needs snapshots or catalog semantics; the immutable, date-named partitions stay compatible with later registration (ADR-006 Decision, Rationale, Q5).
- Export-prefix expiry: none until a year of data exists and its size is measured, then at most one rule in `cloudflare_r2_bucket_lifecycle.sciexp` (ADR-006 Q4).
