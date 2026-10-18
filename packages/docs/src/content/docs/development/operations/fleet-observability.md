---
title: Fleet observability
description: "Operating the GreptimeDB telemetry store and metrics collector on magnetite: dashboard access, failure notices, the hourly envelope, credential rotation and retention."
---

This runbook is for the operator of the fleet's telemetry store as deployed by slice S1.
It assumes SSH access to `magnetite.zt` over ZeroTier, `sudo` on magnetite, and a vanixiets checkout with the `clan` CLI on the workstation.
The maintainer contract for the collector lives in `modules/clan/services/otel-collector/README.md`.

## What runs where

Everything in S1 runs on magnetite.

- `greptimedb.service` runs GreptimeDB standalone, listening only on loopback: HTTP on `127.0.0.1:4000` and gRPC on `127.0.0.1:4001`.
- Its WAL and caches live on the ZFS dataset `zroot/root/greptimedb` at `/var/lib/greptimedb`, with a 16G quota and a 12G reservation.
- Its table data goes to Cloudflare R2, bucket `sciexp`, under the prefix `projects/vanixiets/observability/store/`.
- `greptimedb-schema.service` creates the databases and sets their retention each time the store starts.
- `opentelemetry-collector.service` collects magnetite's host, unit, process-memory, ZFS, OOM-kill and service metrics and writes them to the store.
- `greptimedb-envelope.timer` runs `greptimedb-envelope.service` hourly to check the store's runtime envelope.
- `observability-notify@.service` posts unit failures to ntfy.

The store holds three databases.

| Database | Retention | Written by |
|---|---|---|
| `fleet` | 30 days | the collector, from S1 |
| `devloop` | 365 days | nothing until S2 |
| `agent` | 90 days | nothing until S7 |

The store has four users: `admin` (read and write), `collector` (write only), `perses` (read only) and `regulator` (read only).

## Reaching the dashboard

The store serves its embedded dashboard on the loopback listener, so reach it through an SSH tunnel from the workstation:

```sh
ssh -L 4000:127.0.0.1:4000 magnetite.zt
```

Open `http://127.0.0.1:4000/dashboard/` in a browser.
Sign in as `perses`, the read-only user, with the password from:

```sh
clan vars get magnetite greptimedb-users/perses-password
```

Open the connection settings from the gear and set the connection database to `fleet`; the status bar then shows `fleet`.
The database selector in the Tables panel does not change where queries run.
A query run while the connection database is `public` returns no rows.

Two queries confirm data is arriving:

- PromQL, in Metrics Query: `up`
- SQL, in Table Query: `SELECT count(*) FROM fleet.up`

## Reading fleet-alerts

Unit failures on magnetite go to the ntfy topic `fleet-alerts` at `https://ntfy.zt/fleet-alerts`, reachable only over ZeroTier.
Subscribe in the ntfy app or a browser, or poll recent messages from a shell:

```sh
curl -sk 'https://ntfy.zt/fleet-alerts/json?poll=1&since=1h'
```

The notified units are `greptimedb`, `greptimedb-schema`, `greptimedb-envelope`, `opentelemetry-collector` and magnetite's `zfs-set-*` and `zfs-assert-*` oneshots.

- `FAILED <unit> on <host>` means the unit entered the failed state and a new failure episode began.
- `RESOLVED <unit> on <host>` means the same unit has since started again, or exited successfully, and the episode is over.

Within one episode the notifier posts once, however many times the unit fails.
It also posts at most one `FAILED` per unit per 15 minutes: a failure within 15 minutes of the last posted `FAILED` opens a suppressed episode that ends without a message.
A unit in a crash loop therefore shows one `FAILED`/`RESOLVED` pair, then at most one new pair every 15 minutes, so the messages understate how often it is failing.
Check the real restart count on magnetite:

```sh
systemctl show opentelemetry-collector -p NRestarts
```

Each failure runs one notifier instance, named after the failed unit with a second `.service` suffix:

```sh
sudo journalctl -u 'observability-notify@greptimedb-envelope.service.service' --no-pager
```

The notifier keeps one stamp per open episode in `/var/lib/observability-notify/<unit>`, containing `posted` or `suppressed`.
A stamp left behind by a failed `RESOLVED` post silences that unit until its next start or successful exit.

## Responding to an envelope failure

A `FAILED greptimedb-envelope.service on magnetite` notice means at least one envelope property failed.
Read the run's output on magnetite; journal reads need `sudo` there:

```sh
sudo journalctl -u greptimedb-envelope -n 50 --no-pager
```

Each failed property is one `FAIL <id>: ...` line.
After fixing the cause, rerun the envelope instead of waiting for the next hour; a passing run posts `RESOLVED`:

```sh
sudo systemctl start greptimedb-envelope
```

| Line | Meaning | Check first |
|---|---|---|
| `FAIL R6.4` | `http://127.0.0.1:4000/ready` did not answer 200 | `systemctl status greptimedb` and `sudo journalctl -u greptimedb -n 100 --no-pager`; the store may be down, restarting, or unable to reach R2 |
| `FAIL R6.2: no region ... reports sst_size` | no region has flushed table data | whether the collector is writing: `systemctl status opentelemetry-collector` |
| `FAIL R6.2: summed sst_size ...` | stored table data reached the 50 GiB bound | which database grew, and whether a retention setting changed |
| `FAIL R6.3: ... legacy sst_format=primary_key` | a table uses the legacy SST format | who created that table, and recreate it without `sst_format = 'primary_key'` |
| `FAIL R6.3: ... gave no base table` | no table exists in the store's databases | `systemctl status greptimedb-schema opentelemetry-collector` |
| `FAIL TTL` | a table's own TTL disagrees with `services.greptimedb.tableTtls` | whether the TTL was set on purpose; if so, declare it (see below), otherwise remove the table's own TTL |
| `FAIL R7.2: memory.stat anon ...` | the store's anonymous memory reached `MemoryHigh` (3 GiB) | `systemctl status greptimedb` for its current memory, and what load rose |
| `FAIL R7.2: memory.events high rose ...` | the kernel throttled the store at `MemoryHigh` since the last run | the same as above; throttling slows writes and queries |
| `FAIL R7.2: memory.events oom_kill` or `max rose ...` | the store hit `MemoryMax` (4 GiB) or lost a process to the OOM killer | `sudo journalctl -u greptimedb -n 100 --no-pager` |
| `FAIL R7.2: the kernel OOM killer killed processes ...` or `restarted automatically` | the store was killed or crashed and restarted since the last run | `systemctl show greptimedb -p NRestarts` and `sudo journalctl -u greptimedb --no-pager` around the restart |
| `FAIL R7.2: greptimedb.service has no current invocation` | the store is not running | `systemctl status greptimedb` |
| `FAIL R7.2: no journal entries ...` | the envelope could not read the journal | `systemctl show greptimedb-envelope -p SupplementaryGroups` lists `systemd-journal` |
| `FAIL R7.3: quota ...` or `reservation ...` | the dataset's quota or reservation differs from 16G or 12G | `systemctl status zfs-set-root-greptimedb-quota zfs-set-root-greptimedb-reservation` |
| `FAIL R7.3: used ... of quota` | the dataset is 80% full | `zfs list -o name,used,quota zroot/root/greptimedb` and the size of the WAL and caches under `/var/lib/greptimedb` |
| `FAIL R7.4` | the running store loaded a different users file from the one deployed | restart the store: `sudo systemctl restart greptimedb` |

The R7.2 lines about `high`, `oom_kill`, `max`, OOM kills and automatic restarts each fail one run only, because every run records a new baseline.
For those lines, a `FAILED` followed by `RESOLVED` an hour later records one past event, not a condition that cleared by itself.
The store's restart also restarts `greptimedb-schema`, which reapplies the databases and their retention.

## Forcing a failure deliberately

To confirm the envelope and the notifier still work end to end, lower the anonymous-memory threshold with a runtime drop-in and run the envelope:

```sh
printf "[Service]\nEnvironment=GREPTIMEDB_ENVELOPE_ANON_MAX_BYTES=1\n" | sudo systemctl edit --runtime --stdin --drop-in=force-fail greptimedb-envelope
sudo systemctl start greptimedb-envelope
```

The start fails with `FAIL R7.2: memory.stat anon ... >= GREPTIMEDB_ENVELOPE_ANON_MAX_BYTES 1`, and `fleet-alerts` receives `FAILED greptimedb-envelope.service on magnetite`.
Remove the drop-in and run the envelope again:

```sh
sudo systemctl revert greptimedb-envelope
sudo systemctl start greptimedb-envelope
```

The run passes and `fleet-alerts` receives `RESOLVED greptimedb-envelope.service on magnetite`.
If a `FAILED` for the envelope was posted in the previous 15 minutes, both messages are suppressed; wait and repeat.
A runtime drop-in disappears at reboot, but revert it explicitly so the next hourly run is not left failing.

## Rotating credentials

The store's accounts come from the `greptimedb-users` generator, which writes all four passwords, the users file and its public sha256 together.
Regenerate them and deploy:

```sh
clan vars generate magnetite --regenerate --generator greptimedb-users
clan machines update magnetite
```

The deployment restarts `greptimedb.service`, which loads the new users file and restarts `greptimedb-schema`, and `opentelemetry-collector.service`, which loads the new `collector-password`.
The envelope reads `regulator-password` afresh on each run.
R7.4 then compares the sha256 the running store recorded for the users file it loaded with the deployed file's sha256, so the next envelope run fails if the store is still running on the old file.
Fetch the new `perses` password with `clan vars get` before signing in to the dashboard again.

The R2 token comes from the `greptimedb-r2` generator, whose two hidden prompts take an Object Read & Write token on bucket `sciexp`, minted in the Cloudflare dashboard:

```sh
clan vars generate magnetite --regenerate --generator greptimedb-r2
clan machines update magnetite
```

The deployment restarts `greptimedb.service` with the new environment file.
R7.4 does not cover this credential; a store that cannot reach R2 shows up in R6.4, so run the envelope after the deployment.

## Declaring a per-table TTL

Every table normally keeps its database's retention, and the envelope fails on any table with a TTL of its own.
A table allowed its own TTL is declared in magnetite's configuration as `<database>.<table>`:

```nix
services.greptimedb.tableTtls = {
  "fleet.logs" = "14d";
};
```

The envelope then requires that table to carry exactly that TTL; a declared table that does not exist yet is not judged.
The declaration does not set the TTL: the change that creates the table sets it, and S7 does so for the `fleet` logs table.

## Not covered yet

- S2: dev-loop metrics into `devloop`: nixbot, gitea-mq and deploy records.
- S3: alert rules on the store, the dead-man on cinnabar, and ntfy access control.
- S4: the other NixOS hosts as collector agents, over an mTLS ingress on ZeroTier.
- S5: stibnite on darwin.
- S6: the dashboard on its own SSO-protected vhost with provisioned dashboards, replacing the SSH tunnel.
- S7: omp telemetry and journald logs into `agent` and `fleet`.
- S8: the Parquet export of the store and its reader.
