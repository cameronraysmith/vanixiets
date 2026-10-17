---
title: "ADR-006: Storage substrate and lakehouse seam"
---

## Status

Accepted (human gate, 2026-10-15)

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

R2 is configured through the S3 backend as `type = "S3"`, endpoint `https://<ACCOUNT_ID>.r2.cloudflarestorage.com`, `region = "auto"`, path-style addressing and `disable_ec2_metadata = true`, with `bucket` and `root` naming where the store's objects live (`research/greptimedb.md` R14-R19).
The `[storage]` section takes a static `access_key_id` and `secret_access_key` (`research/greptimedb.md` R14), so the store cannot renew a temporary credential and must hold a long-lived one.
`COPY` to S3, by contrast, also accepts a `session_token` connection option (`GreptimeTeam/greptimedb@179ff8e50:src/common/datasource/src/object_store/s3.rs:27`, `:68-69`).
R2 implements every object operation the storage layer needs and lacks only tagging and ACLs (`research/greptimedb.md` R18).
No GreptimeDB source or example mentions R2, so that stanza is derived and has not been exercised against a live bucket (`research/greptimedb.md` R20).
Object storage forces the mito write cache on and keeps a read cache, defaulting to 5 GiB and 5 GB, so the local floor on the store host is roughly 10 GB of cache plus WAL and metadata (`research/greptimedb.md` R21-R23).

The repository already holds a long-lived R2 token on `magnetite`: `omnigraph-r2`, an Object Read & Write token on the bucket `sciexp`, minted in the Cloudflare dashboard and delivered as a hidden-prompt clan vars generator with `restartUnits`, which omnigraph uses under `s3://sciexp/omnigraph/` (`cameronraysmith/vanixiets@109c67346:modules/machines/nixos/magnetite/default.nix:334-367`, `cameronraysmith/vanixiets@109c67346:modules/machines/nixos/magnetite/default.nix:399`, `research/telemetry-security-and-tenancy.md` F38).

Web-verification decision D9 fixes how this repository stores objects in R2 (`cameronraysmith/vanixiets@109c67346:docs/notes/development/web-verification/decisions.md:77-104`).
Objects go to the existing bucket `sciexp` under `projects/<project>/<kind>/`, and Terraform adopts that bucket with an import block and `prevent_destroy` (`cameronraysmith/vanixiets@109c67346:modules/terranix/cloudflare.nix:51-64`).
R2 lifecycle rules are bucket-wide, so the single resource `cloudflare_r2_bucket_lifecycle.sciexp` holds every rule for `sciexp`, including a multipart-abort rule at 7 days over the empty prefix, and a second lifecycle resource would replace its rules (`cameronraysmith/vanixiets@109c67346:modules/terranix/cloudflare.nix:66-83`).
D9 confines a writer to a prefix only through temporary credentials signed locally from a parent token whose scope is the whole bucket, each for one scope, one prefix and 15 minutes (`cameronraysmith/vanixiets@109c67346:modules/apps/docs/publish-evidence.sh:460-502`).
DuckDB's S3 secret accepts a `session_token` parameter, so a temporary credential is usable from DuckDB (`duckdb/duckdb-httpfs@6c07db62f:src/create_secret_functions.cpp:213`).
R2 bills stored GB-months and Class A and Class B operations, with no charge per bucket (https://developers.cloudflare.com/r2/pricing/, fetched 2026-10-15).
No DuckDB or DuckLake service is deployed in the fleet; DuckDB is consumed from nixpkgs on demand (`cameronraysmith/vanixiets@109c67346:pkgs/disabled/README.md:10`).
The dev-loop signals are batch-shaped and analytic rather than alerting-shaped (`research/dev-loop-signals.md` "Bearing on decisions", D6).

The rejected-alternatives unit records that Tempo and OpenObserve beat GreptimeDB on in-place Parquet readability (`research/store-alternatives.md` F20, F31), and asks that this be carried into D6 explicitly.

## Decision

The store's own substrate is GreptimeDB SST Parquet in the existing R2 bucket `sciexp` under the prefix `projects/vanixiets/observability/store/`, and the lakehouse seam is a scheduled Parquet export into the same bucket under `projects/vanixiets/observability/export/`, not external reads of the store's SSTs.
No R2 bucket is created; both prefixes follow D9's `projects/<project>/<kind>/` layout.
The store's `[storage]` section sets `bucket = "sciexp"` and `root = "projects/vanixiets/observability/store/"`, and authenticates with one long-lived Object Read & Write token on `sciexp` held as the clan var `greptimedb-r2`.
A systemd timer on the store host runs once a day and issues `COPY DATABASE devloop TO 's3://sciexp/projects/vanixiets/observability/export/devloop/date=<D>/' WITH (format = 'parquet', start_time = '<D>T00:00:00Z', end_time = '<D+1>T00:00:00Z', parallelism = 1)` for each of the last three UTC days, so each day's partition is rewritten twice more to absorb late data from intermittent hosts.
Before each `COPY`, the export oneshot signs, from the `greptimedb-r2` token as parent, a temporary credential with scope `object-read-write`, prefix `projects/vanixiets/observability/export/` and a 15-minute lifetime, using the same claims and derivation as D9's `mint`, and passes it to the `COPY` as `access_key_id`, `secret_access_key` and `session_token`.
The oneshot unsets the parent secret after signing, so the parent never appears in a statement, an argument vector or a child's environment.
Only the `devloop` database is exported by default; `fleet` and `agent` stay in the store and expire under their TTLs.
Consumers read the export with DuckDB's `httpfs` as `read_parquet('s3://sciexp/projects/vanixiets/observability/export/devloop/date=*/<table>.parquet', hive_partitioning = true)`, over a DuckDB S3 secret carrying a temporary credential with scope `object-read-only` and prefix `projects/vanixiets/observability/export/`.
That credential is signed on the analytics host itself by a reader command, from a parent R2 token with Object Read only on `sciexp`, held in the clan var `telemetry-export-reader` on each analytics host of Q3; the command emits the DuckDB `CREATE SECRET` with `KEY_ID`, `SECRET` and `SESSION_TOKEN`, and the parent never reaches DuckDB.
The reader credential's lifetime is one hour, and a session that outlives it re-runs the command `[INFERENCE: R2's acceptance of a one-hour lifetime on a locally signed credential is not checked]`.
No lifecycle rule covers the store prefix, because GreptimeDB manages its own objects: retention is the store's per-table and per-database TTL of ADR-004 (`research/greptimedb.md` R31), the live file set is whatever the region manifests name (`research/greptimedb.md` F27), and a delete-by-age rule would remove SSTs and manifests that are still live.
Any expiry for the export prefix is a rule added to the existing `cloudflare_r2_bucket_lifecycle.sciexp` resource, and no second lifecycle resource is created for `sciexp` (Q4).
Registering the export in a DuckLake catalog is deferred until a second consumer needs catalog semantics.
Every store table is created with the flat SST format, which is the default, and no table may set `sst_format` to the legacy value.
The store's local cache and WAL live on a dedicated ZFS dataset with its own quota and reservation, sized in ADR-007.

## Rationale

An export decouples the analytics path from the store's internal layout.
In-place SST reads would require every DuckDB consumer to parse region manifests and to merge `__sequence` and `__op_type` (`research/greptimedb.md` F27), and would expose the store's prefix, including its manifests, to read credentials held outside the store host.
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

Prefixes in `sciexp` follow D9 instead of introducing a second storage convention: one adopted bucket, one key layout, one lifecycle resource and one confinement mechanism.
A bucket is not a cost unit in R2, which bills stored data and operations, so separate buckets would buy no cost isolation; the isolation they would buy, a token that cannot reach the other bucket, comes from prefix-confined temporary credentials wherever the consumer accepts a session token.
The store is the one consumer that cannot use one, because `[storage]` takes only a static key pair, so it holds a long-lived `sciexp` token, the same blast radius `omnigraph-r2` already has on `magnetite`.
The export oneshot uses that same token as its parent rather than a second long-lived token, because a second `sciexp` token on the same host would widen nothing an attacker on `magnetite` lacks, and signing per run confines the export's own writes to the export prefix, so a wrong location in a `COPY` is refused rather than written over another project's keys.
Readers sign from a read-only parent on their own host, because the alternative, a signer on `magnetite` reached over the network, makes every analysis depend on the store host and adds a remote surface that holds the store's write token.

## Rejected alternatives

- External DuckDB reads of the store's SSTs in place: requires manifest parsing and sequence/op-type merging per consumer and exposes the store prefix (`research/greptimedb.md` F27).
- Separate silo with no seam: contradicts W8 and leaves the batch-shaped dev-loop history unreachable by the analytics path (`research/dev-loop-signals.md` D6 bearing).
- Arrow Flight from DuckDB to the store: Flight is served (`research/greptimedb.md` R36), but no DuckDB Flight client is established in this corpus, and an online query path loads the co-tenanted store at analysis time.
- DuckDB over the store's PostgreSQL wire protocol: compatibility is unverified and it requires enabling a port ADR-002 and ADR-007 keep disabled.
- `greptime cli data export` instead of a SQL `COPY`: it issues the same `COPY DATABASE` statement (`research/greptimedb.md` R33) and adds a client process and a second credential path.
- Exporting all three databases: copies agent-session data outside the TTL and the Kanidm-admitted read zone of ADR-008.
- A DuckLake catalog now: no consumer needs catalog semantics yet, so it prevents no named failure (C1).
- Tempo or OpenObserve for their native Parquet: rejected as stores in ADR-001, and the export seam closes the readability gap they hold.
- Local `File` storage instead of R2: overrides the human input without evidence that R2 fails; retained as the fallback.
- Two new buckets, one for the store and one for the export: contradicts D9's single adopted bucket and lifecycle resource, and buys no cost isolation because R2 bills stored data and operations, not buckets.
- A second `cloudflare_r2_bucket_lifecycle` resource for the export prefix: R2 lifecycle rules are bucket-wide, so it would replace the rules of `cloudflare_r2_bucket_lifecycle.sciexp`, including the browser-evidence expiries.
- A delete-by-age lifecycle rule on the store prefix: would remove SSTs and manifests that the store still references, whereas the store's TTLs already bound its data.
- A separate long-lived export token (`greptimedb-r2-export`): a second `sciexp` read-write token on the same host as the store's, with no confinement gain over signing per run from the store's token.
- Long-lived read tokens on analytics hosts used directly by DuckDB: D9's parent tokens are scoped to the bucket, and prefix confinement exists only in temporary credentials, so DuckDB would hold read access to all of `sciexp`, including the store prefix.
- A credential signer on `magnetite` for readers: makes analysis depend on the store host's reachability and exposes a remote command surface on the host holding the store's write token.

## Consequences

The analytics view of dev-loop data lags the store by up to one day and converges over three days.
`devloop` history beyond the in-store 365-day TTL exists only under the export prefix, so that prefix has no expiry by default and its growth becomes part of the envelope; any expiry later decided is a rule in `cloudflare_r2_bucket_lifecycle.sciexp` (Q4).
The export is a second copy of dev-loop data in R2, so R2 storage roughly doubles for that database within its TTL.
The store's R2 storage is bounded by ADR-004's TTLs and by E6.2, and it shares the account's R2 free tier and bill with every other `sciexp` user.
The bucket-wide multipart-abort rule at 7 days applies to the store prefix too, which is harmless only while no store upload stays open that long `[INFERENCE: GreptimeDB's upload duration on R2 is unmeasured]`.
Known limitation: the `greptimedb-r2` token can read, write and delete every object in `sciexp`, including `omnigraph/` and `projects/vanixiets/browser-evidence/`, so compromise of the store process or of `magnetite`'s vars exposes the whole bucket, the same blast radius `omnigraph-r2` already has on that host.
The `telemetry-export-reader` parent can read every object in `sciexp`, so a host that holds it is trusted with read access to the whole bucket, which bounds Q3.
The `object-read-only` scope and the two observability prefixes have not been checked against R2, as D9 records for its own read-only scope and per-tier prefixes.
Schema evolution in the store appears in the export as per-day column-set differences, which DuckDB reads with `union_by_name = true`.
The export runs inside the store process and consumes its scan memory budget, so a large backfill must be run in daily steps.
If the R2 stanza fails at first deployment, the store moves to local `File` storage on the dedicated dataset, whose quota must then be raised to hold the SSTs (ADR-007), and the export continues unchanged.

## Operating envelope and regulator

Envelope E6.1, export freshness: the export partition for UTC day D-1 exists by 06:00 UTC on day D, and the export unit's last run succeeded.
Regulator R6.1: the store-host probe timer of ADR-007 reads the export unit's `Result` and `ExecMainExitTimestamp` from systemd and lists `projects/vanixiets/observability/export/devloop/date=<D-1>/` in `sciexp` with an `object-read-only` temporary credential for the export prefix signed from the `greptimedb-r2` token, and the probe unit fails if either the result is not `success`, the timestamp is older than 30 hours, or the listing is empty.
It is shown able to fail by running it once against a date for which no partition exists and observing a failed unit, recorded in the implementing change.

Envelope E6.2, store substrate size: the sum of `sst_size` over `information_schema.region_statistics` stays under 50 GiB, against an estimate an order of magnitude lower for ADR-004's estimate of about 5,700 active `fleet` series under its 8,000 cap and under 60,000 dev-loop events per day `[INFERENCE: scaled from research/otel-collector-topology.md F41, F42; log volume is unmeasured]`.
Regulator R6.2: the same probe queries `information_schema.region_statistics` (`GreptimeTeam/greptimedb@179ff8e50:src/catalog/src/system_schema/information_schema/region_statistics.rs:46-49`) over the loopback HTTP SQL endpoint and fails above the bound.

Envelope E6.3, readable format: no table in any database has `sst_format` set to the legacy format.
Regulator R6.3: the same probe queries the `create_options` column of `information_schema.tables` (`GreptimeTeam/greptimedb@179ff8e50:src/catalog/src/system_schema/information_schema/tables.rs:67`) and fails on any legacy-format table; its negative control is a scratch table created with the legacy option during the implementing change.

Envelope E6.4, R2 substrate reachability: the store can write and list its manifest objects on R2.
Regulator R6.4 (amended in charter v16): the store's `/ready` endpoint after start, checked by the probe, and from S8 a NixOS evaluation-time assertion that the export location lies under `projects/vanixiets/observability/export/`, outside the store's `root`.
The S3 stanza's values (`type = "S3"`, `disable_ec2_metadata = true`, `region = "auto"`, `enable_virtual_host_style = false`, `bucket = "sciexp"`, `root = "projects/vanixiets/observability/store/"`) are literals of `magnetite`'s configuration with no copy in a check, because a copy fails only when the literal itself is edited; deployment confirms them by the store's objects appearing under the store prefix, and the readiness probe fails when R2 is unreachable.

## Failure prevented

The export seam prevents every analytics consumer from depending on GreptimeDB's internal manifest and merge semantics, which change across releases.
The three-day re-export window prevents permanent loss from the analytics copy of dev-loop rows that intermittent hosts deliver late.
`parallelism = 1` prevents the export from launching sixteen concurrent table scans on a host that has OOM-killed twice.
Excluding `agent` from export prevents agent-session telemetry from escaping the TTL and the Kanidm-admitted read zone of ADR-008.
The legacy-format check prevents a table whose tags are unrecoverable outside the store from entering the export.
The export-prefix credentials prevent an analytics reader from reading or corrupting the store's SSTs and manifests, and prevent the export from writing outside its prefix.
Placing the export rule in `cloudflare_r2_bucket_lifecycle.sciexp` prevents a second lifecycle resource from deleting the browser-evidence expiries and the multipart-abort rule.

## Implementation surface

- `modules/nixos/greptimedb.nix` (ADR-007): `services.greptimedb.export` options for the database list, prefix, schedule and lookback days, with the bucket fixed to `sciexp`; a `greptimedb-export.service` oneshot that loads the `greptimedb-r2` `env` file through `LoadCredential` and signs one temporary credential per `COPY` with the claims and derivation of D9's `mint` (`cameronraysmith/vanixiets@109c67346:modules/apps/docs/publish-evidence.sh:471-502`), and `greptimedb-export.timer`; the R6.4 assertion.
- `modules/nixos/greptimedb.nix`: the probe of R6.1 to R6.3 as checks inside the `greptimedb-envelope` unit defined in ADR-007, signing its R6.1 read-only credential the same way.
- Clan vars generator `greptimedb-r2` on `magnetite`: hidden prompts `access-key` and `secret-key` for an R2 token with Object Read & Write on `sciexp`, with `persist = true` and per-file `deploy = false`, rendered to an `env` file with `GREPTIMEDB_STANDALONE__STORAGE__ACCESS_KEY_ID` and `GREPTIMEDB_STANDALONE__STORAGE__SECRET_ACCESS_KEY` (`GreptimeTeam/greptimedb@179ff8e50:src/cmd/src/standalone.rs:287`, `GreptimeTeam/greptimedb@179ff8e50:src/common/config/src/config.rs:23`), `restartUnits = [ "greptimedb.service" ]`, following `omnigraph-r2`; the export and envelope oneshots load it at each start and need no `restartUnits` entry.
- Clan vars generator `telemetry-export-reader`, `share = true`, for each analytics host of Q3: hidden prompts for an R2 token with Object Read only on `sciexp`, used only as the parent from which the reader command signs export-prefix credentials.
- The reader command on each analytics host: signs an `object-read-only` credential for `projects/vanixiets/observability/export/` and prints the DuckDB `CREATE SECRET` statement.
- `modules/terranix/cloudflare.nix`: no bucket resource; only if Q4 decides an expiry, one rule with prefix `projects/vanixiets/observability/export/` added to `cloudflare_r2_bucket_lifecycle.sciexp`, and no rule for the store prefix.
- No new flake input.

## Questions for the human gate

Q1 Does the seam mean in-place reads of the store's SSTs or a scheduled export? Recommended: scheduled export; the alternative couples every consumer to the store's manifest format (`research/greptimedb.md` Q2, `research/store-alternatives.md` Q4).
Resolution: recommended answer accepted at the 2026-10-15 gate.
Q2 Should `fleet` or `agent` also be exported? Recommended: neither; exporting `agent` moves identifying data outside ADR-008's boundary, and exporting `fleet` doubles its R2 footprint for operational data with a 30-day horizon.
Resolution: recommended answer accepted at the 2026-10-15 gate.
Q3 Which hosts hold the `telemetry-export-reader` parent and sign export read credentials? Recommended: the human operators' primary workstations only, since the parent reads all of `sciexp`; the alternative of every host widens read access to dev-loop history and to the rest of the bucket to worker accounts.
Resolution: recommended answer accepted at the 2026-10-15 gate.
Q4 Should the export prefix carry an R2 lifecycle expiry, as a rule in `cloudflare_r2_bucket_lifecycle.sciexp`? Recommended: no expiry until a year of data exists and its size is measured; the alternative caps history before its value is known.
Resolution: recommended answer accepted at the 2026-10-15 gate.
Q5 Should a DuckLake catalog be added now? Recommended: no, defer until a second consumer needs snapshots; the alternative adds a catalog file and its ownership with no failure prevented.
Resolution: recommended answer accepted at the 2026-10-15 gate.
Q6 Do the store and the export live in the existing `sciexp` bucket under `projects/vanixiets/observability/store/` and `projects/vanixiets/observability/export/`, approving R2 storage cost bounded by ADR-004's retention for the store and growing at the `devloop` export rate until Q4 sets an expiry? Recommended: yes; R2 bills stored data and operations rather than buckets, and D9 already fixes the bucket, key layout and lifecycle resource, so a new bucket would add a second convention with no cost saving.
Resolution: recommended answer accepted at the 2026-10-15 gate.
Q7 Is local `File` storage acceptable as the fallback if the R2 stanza fails its first deployment? Recommended: yes; the alternative blocks the store on debugging an untested S3-compatible path.
Resolution: recommended answer accepted at the 2026-10-15 gate.
Q8 How nixbot rows reach `devloop` is decided by ADR-005 Q1, which owns that signal; no question remains here.
Resolution: recommended answer accepted at the 2026-10-15 gate.
Q9 Is one long-lived `sciexp` read-write token for the store acceptable, given that GreptimeDB's `[storage]` takes only static credentials? Recommended: yes, as a recorded limitation with the blast radius `omnigraph-r2` already has on `magnetite`; the alternative is local `File` storage, which overrides the human's R2 choice.
Resolution: recommended answer accepted at the 2026-10-15 gate.
