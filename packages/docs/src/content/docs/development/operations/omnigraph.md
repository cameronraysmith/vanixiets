---
title: OmniGraph
description: "How magnetite's omnigraph-server stores, watches, recovers and backs up its graphs: the root store option, the static user, stale-lock recovery and its refusals, the nightly backup and its restore, the probe's series, and how to answer OmnigraphNotServing and OmnigraphBackupStale."
---

This runbook covers the graph store magnetite serves, `omnigraph-server.service` from `flake.modules.nixos.omnigraph` in `modules/nixos/omnigraph.nix`, where its graph data lives, and how it is watched, recovered and backed up.
magnetite serves ten example graphs, one per cookbook of the pinned `omnigraph-cookbooks`, `cookbook-agent-ops` to `cookbook-vc-os`, on port 8090, which cinnabar's TLS fronts reach over the mesh.

## Where the graphs are served from

The graph data of one cluster lives under one root, named `cookbooks-f17` on magnetite.
The internal option `vanixiets.omnigraphRootStore`, declared and set in magnetite's module `modules/machines/nixos/magnetite/default.nix`, says where that root lives; `flake.lib.omnigraphClusterRoots.uriIn` turns the option and the root name into `services.omnigraph.storageUri`:

| Value | Root | What it selects |
|---|---|---|
| `"r2"` | `s3://sciexp/omnigraph/clusters/cookbooks-f17` | the R2 endpoint, `region = "auto"`, the credentials of the clan vars generator `omnigraph-r2`, and `OMNIGRAPH_CLUSTER_LEASE_SECONDS = "120"` |
| `"local"` | `/var/lib/omnigraph/clusters/cookbooks-f17` | the ZFS dataset `zroot/root/omnigraph`, mounted at `/var/lib/omnigraph`; every unit requires that mount; the `omnigraph-cluster` wrapper runs `omnigraph` as `omnigraph`; the server's start recovers a stale lock; the nightly backup can be turned on; the probe publishes the dataset's series |

On either value every omnigraph unit runs as the static user `omnigraph`.

magnetite is set to `"r2"`, so today it serves from R2 and nothing below that is marked local applies to it.
The option is internal: changing it is a pull request against magnetite's module, not a host setting.

The bootstrap markers sit beside the root, in `clusters/_omnigraph-markers/`, in whichever store the root is.
A new local root starts empty: `omnigraph-cluster-bootstrap` finds no marker, creates the root, applies the cluster configuration, and the `omnigraph-seed-<graph>` units load each cookbook's seed once the server serves.
Nothing is copied from R2.

Print what a host evaluates to:

```bash
nix eval --raw .#nixosConfigurations.magnetite.config.services.omnigraph.storageUri
nix eval .#nixosConfigurations.magnetite.config.systemd.services.omnigraph-server.serviceConfig.User
```

## The static user and who may write the root

Every omnigraph unit, `omnigraph-cluster-bootstrap`, `omnigraph-cluster-apply`, each `omnigraph-seed-<graph>`, `omnigraph-server` and `omnigraph-optimize`, runs as the system user and group `omnigraph`, not as a systemd `DynamicUser`, with `StateDirectory = "omnigraph"`, on R2 and on a local root alike.
The state directory is therefore the plain directory `/var/lib/omnigraph`, and on a local root the dataset is that directory, owned by `omnigraph`.
systemd hands a state directory owned by root to the unit's user when the unit starts, so a freshly created dataset needs no `chown`.
On a local root every unit also requires the mount of `/var/lib/omnigraph/clusters` (`RequiresMountsFor`), so none starts before the dataset is mounted.

The rule is that every file on the dataset belongs to `omnigraph`, whoever writes it.
- On a local root, run direct writers only through the `omnigraph-cluster` wrapper, as `sudo omnigraph-cluster <verb> …`: it runs as root, reads the cluster configuration from `/etc`, and runs `omnigraph` itself as `omnigraph` through `runuser`. On an R2 root the wrapper runs `omnigraph` as root, which writes nothing on the host's disk.
- The lock recovery below runs its `omnigraph` commands as `omnigraph` too.
- An `omnigraph` run by hand as root writes files owned by root, which the server cannot write afterwards. If that happened, stop the server and run `sudo chown -R omnigraph:omnigraph /var/lib/omnigraph`.

The uid of `omnigraph` comes from NixOS's system-user allocation, which is stable on one host and may differ on another, which is why a restore ends with the same `chown`.
Earlier configurations ran the units as a `DynamicUser`, whose state directory systemd keeps at `/var/lib/private/omnigraph` behind the symlink `/var/lib/omnigraph`; at the first start under `omnigraph` systemd moves that directory to `/var/lib/omnigraph` and removes the symlink.
A directory moved this way keeps its `nobody` owner on disk, and systemd gives the units an id-mapped mount of it instead of a `chown`; a dataset created owned by root is chowned to `omnigraph`.

OmniGraph admits one writer at a time.
A direct writer, an apply included, needs `omnigraph-server` stopped first.

## Stale-lock recovery on a local root

A server writes `__cluster/lock.json` into the root when it starts and removes it when it stops cleanly.
On a local root a killed server leaves the file behind, every later start refuses with `state_lock_held`, and OmniGraph itself never decides that the lock is stale; `omnigraph cluster force-unlock <id>` removes a lock on a matching id without checking whether its holder still runs.

So on a local root `omnigraph-server`'s start runs `omnigraph-lock-recovery` (`flake.lib.omnigraphLockRecovery`, `modules/lib/omnigraph-lock-recovery.nix`) first, as root outside the unit's sandbox, so that it sees every process on the host.
It decides by the first matching row:

| Row | It finds | It does |
|---|---|---|
| 1 | no `lock.json` | nothing; the start goes on |
| 2 | a process whose executable is named `omnigraph` or `omnigraph-server` with an argument naming the root | refuses |
| 3 | a record not of the shape OmniGraph writes for a held lock (version 1, string `lock_id` and `operation`, RFC 3339 `created_at`, positive integer `pid`) | refuses |
| 4 | a `created_at` that is not a date | refuses |
| 5 | `omnigraph cluster status` failing | refuses |
| 6 | `omnigraph cluster status` reporting a lock other than the record's | refuses |
| 7 | an `operation` other than `serve`: a direct writer's lock | refuses |
| 8 | a record `pid` that is running, in a lock taken during the current boot | refuses |
| 9 | anything else: a server's lock whose process is gone, or taken before this boot | removes it by its exact id with `force-unlock`, counts it, posts a notice, and the start goes on |

A recovery adds one to `/var/lib/omnigraph-metrics/lock-recoveries`, which the probe publishes as `vanixiets_omnigraph_lock_recoveries_total`, logs `omnigraph-lock-recovery: omnigraph-server on magnetite cleared the stale serve lock <id> of <root> (pid <pid>, taken <created_at>) and starts; lock recoveries on magnetite: <n>`, and posts that message at low priority to `fleet-alerts` with the title `omnigraph lock recovered on magnetite`.
A recovery is an expected event after a crash, not an alert; a failed post does not fail the start.

A refusal leaves `lock.json` exactly as it was and fails the start: `Restart=on-failure` tries again within the start limit, the failure notice `FAILED omnigraph-server.service on magnetite` arrives, and `OmnigraphNotServing` fires after 5 minutes.
Read the reason from the start's journal:

```bash
sudo journalctl -u omnigraph-server -n 50 --no-pager | grep omnigraph-lock-recovery
```

Each refusal prints two lines, `omnigraph-lock-recovery: left <root>/__cluster/lock.json in place: <reason>` and `omnigraph-lock-recovery: omnigraph-server stays stopped until the lock is cleared. <manual step>`:

| Row | Reason | Manual step |
|---|---|---|
| 2 | `an omnigraph process has the root open (pid <pid>: <argv>)` | `Wait for that process to finish or stop it, then run: systemctl restart omnigraph-server` |
| 3 | `the record is not the shape omnigraph writes for a held lock (…)` | `Read <lock> and omnigraph-cluster status --json, and once no omnigraph process runs against the root, run: omnigraph-cluster force-unlock <lock_id>` |
| 4 | `the record's created_at (<value>) is not a date` | the same, with the record's id |
| 5 | `omnigraph cluster status failed, so the record's lock <id> cannot be confirmed as the cluster's` | `Read omnigraph-cluster status --json, and once no omnigraph process runs against the root, run: omnigraph-cluster force-unlock <id>` |
| 6 | `the record names lock <id> but omnigraph cluster status reports <other>, so the lock changed while it was read` | `Run systemctl restart omnigraph-server to read it again; if it persists, compare <lock> with omnigraph-cluster status --json` |
| 7 | `lock <id> was taken by a direct <operation> writer (pid <pid>, <created_at>), whose interrupted work needs its own recovery` | `With no omnigraph process running against the root, find its deployment with omnigraph-cluster status --json, then run omnigraph-cluster force-unlock <id> and omnigraph-cluster apply --deployment-id <deployment_id> --writers-stopped --json; for a writer other than an apply, confirm it stopped and run omnigraph-cluster force-unlock <id>` |
| 8 | `lock <id> was taken in this boot (<created_at>) by pid <pid>, which is running` | `Confirm pid <pid> is not an omnigraph-server holding the root (ps -o pid,args -p <pid>), then run omnigraph-cluster force-unlock <id> and systemctl restart omnigraph-server` |

Run the manual commands as root (`sudo omnigraph-cluster …`, `sudo systemctl …`).
A `force-unlock` that does not report the lock removed fails the start with `omnigraph cluster force-unlock <id> did not report the lock removed`; read the command's output in the same journal.
Once the start limit is spent, systemd refuses further starts until `sudo systemctl reset-failed omnigraph-server.service`.

On an R2 root none of this runs: a lock in the bucket carries a lease, and a successor takes over a crashed server's lock once the lease expires.

## Why optimize is not enabled on a local root

`omnigraph optimize` runs directly against storage, not through the server.
On a local root it exits with its admission lock still in `lock.json`, logging `cluster admission retained … use exact-ID cluster force-unlock`.
The server's next start then meets a direct writer's lock, which the recovery refuses (row 7), and the server stays down until someone runs `sudo omnigraph-cluster force-unlock <LOCK_ID>`.
An assertion in `modules/nixos/omnigraph.nix` therefore fails evaluation when `services.omnigraph.optimize.enable` is set for a local root.
Optimize on a local root is not provided; on an R2 root the option is unchanged and off on magnetite.

## The nightly backup

`vanixiets.omnigraphBackup.enable` (`modules/nixos/omnigraph-backup.nix`) backs a local root up off the host every night.
It is off on magnetite and becomes possible only once magnetite serves locally: the module's assertions refuse an `s3://` root, a job that backs up anything but the snapshot directory, a host whose `notifiedUnits` lack `restic-backups-omnigraph`, `omnigraph-backup-metric` or `zfs-set-root-omnigraph-quota`, and a host whose textfile collector does not keep the backup's series.

A file-by-file copy of a live root may not open, so the backup is taken from an instant image.
`restic-backups-omnigraph`, run by its timer every night at 03:30 UTC plus up to 15 minutes, and after a missed night at the next boot:
1. takes the ZFS snapshot `zroot/root/omnigraph@restic`, destroying one a failed run left;
2. backs up only `/var/lib/omnigraph/.zfs/snapshot/restic`, a fixed path, so restic finds each run's parent;
3. destroys the snapshot;
4. prunes to 7 daily, 4 weekly and 6 monthly copies per host, and reads back a tenth of the repository.

The repository is `s3:https://1ece4a9a8f092f8cbdd679d22b9ecb1f.r2.cloudflarestorage.com/sciexp-omnigraph-backup/<host>`, in the R2 bucket `sciexp-omnigraph-backup` (`modules/terranix/cloudflare.nix`, location `enam`, no lifecycle rule: restic's prune owns every deletion).
Its R2 keys come from the prompted clan vars generator `omnigraph-backup-r2`, for a token scoped to that bucket alone, and its password from the generated `omnigraph-backup-restic`.
Never regenerate `omnigraph-backup-restic`: the repository opens only with the password it was created under.

`restic-omnigraph` is the job's restic, with its repository and secrets, for listing and restoring:

```bash
sudo restic-omnigraph snapshots
```

Freshness is watched through one series.
A run whose backup, prune and check all succeeded writes `vanixiets_omnigraph_backup_last_success_timestamp_seconds` into `/var/lib/omnigraph-backup-metrics/backup.prom` and publishes it as `omnigraph-backup.prom` in the textfile directory.
`omnigraph-backup-metric` republishes it every minute, and on its first run seeds it with that run's time when no record exists, so a host that never completes a backup ages too.
`OmnigraphBackupStale` fires once the stamp is more than 36 hours old.

## Restoring the graph data

Restore from the backup when the dataset's contents are lost or damaged.
The steps are the ones `vmTests.x86_64-linux.omnigraph-local-root` runs and checks to identical entity counts and stored-query answers.
On a host that no longer has the dataset, create it first as the switch to local disk does: `sudo zfs create -o mountpoint=/var/lib/omnigraph -o quota=20G zroot/root/omnigraph`.

1. Stop the server:
   ```bash
   sudo systemctl stop omnigraph-server.service
   ```
2. Pick the backup, `latest` or a snapshot id from `sudo restic-omnigraph snapshots`.
3. Empty the dataset; its ZFS snapshots are untouched:
   ```bash
   sudo find /var/lib/omnigraph -mindepth 1 -xdev -delete
   ```
4. Restore the snapshot directory's contents into the dataset:
   ```bash
   sudo restic-omnigraph restore latest:/var/lib/omnigraph/.zfs/snapshot/restic --target /var/lib/omnigraph
   ```
5. Give every file to `omnigraph`. The backup records every file as owned by `0:0` (`sudo restic-omnigraph ls latest --json` shows it), so the restored files belong to root and the server, running as `omnigraph`, cannot write them; the `chown` also covers a host where `omnigraph` has another uid.
   ```bash
   sudo chown -R omnigraph:omnigraph /var/lib/omnigraph
   ```
6. Remove the lock the backup carries: the server was running when the snapshot was taken, so every backup holds its serve lock.
   ```bash
   sudo jq -r .lock_id /var/lib/omnigraph/clusters/cookbooks-f17/__cluster/lock.json
   sudo omnigraph-cluster force-unlock <LOCK_ID>
   ```
   Without this step the server's start treats the restored lock like a crashed server's and clears it when the recovery's checks pass, counting it as a recovery and posting a notice.
7. Start the server and compare:
   ```bash
   sudo systemctl start omnigraph-server.service
   sudo systemctl start omnigraph-probe.service
   grep vanixiets_omnigraph_graph_entities /run/node-exporter-textfile/omnigraph.prom
   ```
   The entity counts should equal those stored on the night of the backup, for example from `nix run .#obs-query -- --table promql 'vanixiets_omnigraph_graph_entities{host_name="magnetite"}'`.

To return to a recent state without R2, the dataset's hourly, daily and weekly ZFS snapshots are listed by `zfs list -t snapshot zroot/root/omnigraph`.
Any copy of a root carries the lock of the server it was taken from, so a copy from one of them needs the same `chown` and unlock; this path is not exercised by a test.

## Switching back to R2

Setting `vanixiets.omnigraphRootStore = "r2"` serves `s3://sciexp/omnigraph/clusters/cookbooks-f17` as the bucket held it when magnetite left it.
Its markers are still in the bucket, so the bootstrap adopts the root rather than recreating it.

What carries over: nothing written while serving locally.
Every load, apply and seed of the local root stays on the dataset, and the bucket's root has none of them.
The R2 settings, the `omnigraph-r2` generator and the retired and rollback roots were kept unchanged under `"local"`, so the R2 configuration is whole.
On R2, the dataset series and `vanixiets_omnigraph_lock_recoveries_total` are no longer written, and the per-graph series depend on whether the bucket's root was applied with the `monitor` grants.

The units run as `omnigraph` on both stores, so switching changes no unit's user and no state directory, and the dataset may stay mounted at `/var/lib/omnigraph`, holding the local root for a later return; `vmTests.x86_64-linux.omnigraph-state-directory-transitions`, with RustFS standing in for R2, shows every unit starting and serving from the bucket with the dataset mounted.
Deploy the configuration with `vanixiets.omnigraphRootStore = "r2"` and `vanixiets.omnigraphBackup.enable = false`, which the backup module requires of an R2 root.

Rolling magnetite back to a generation from before the static user is different.
Such a generation runs the units as a `DynamicUser`, and systemd then moves a plain `/var/lib/omnigraph` into `/var/lib/private`; a mountpoint cannot be moved, so with the dataset mounted there every omnigraph unit fails to start with `Failed to set up special execution directory in /var/lib: Device or resource busy` (status 238/STATE_DIRECTORY).
`vmTests.x86_64-linux.omnigraph-state-directory-transitions` shows that failure and the start succeeding once the dataset is unmounted.
Before such a rollback, take the dataset off that path; its data stays:

```bash
sudo systemctl stop omnigraph-server.service
sudo zfs set canmount=noauto zroot/root/omnigraph
sudo zfs unmount zroot/root/omnigraph
sudo rmdir /var/lib/omnigraph
```

## What watches the server

Four things report on `omnigraph-server`:
- its own failure notice: `omnigraph-server` is among magnetite's notified units, so a failed start posts `FAILED omnigraph-server.service on magnetite` to `fleet-alerts`;
- `omnigraph-probe.service`, every minute, which writes the server's state to node_exporter's textfile collector as `/run/node-exporter-textfile/omnigraph.prom`;
- the alert `OmnigraphNotServing`, which fires when the probe has found the server not ready, or serving a blocked graph, for 5 minutes;
- the Perses view `OmniGraph` (`modules/nixos/perses/resources/dashboard-omnigraph.json`), which shows every series below per host.

A probe that stops writing is reported by `HostProbeStale`, as for every textfile writer.
With the backup on, `OmnigraphBackupStale` and the failure notices of `restic-backups-omnigraph`, `omnigraph-backup-metric` and `zfs-set-root-omnigraph-quota` report on the backup.

## What the probe reads

omnigraph-server serves no metrics endpoint, so `omnigraph-probe` (`modules/nixos/omnigraph-probe.nix`) asks the server and the host:
- `GET /readyz`, which needs no token and answers whether the server is ready and how many graphs it serves, and how many of them are ready, loading or blocked, but not which;
- `systemctl show omnigraph-server`, for the time from the server's main process start to the end of its start job, whose readiness wait ends only once every graph is open;
- with the `monitor` actor's token, `GET /graphs` for the graphs and their states, then `GET /graphs/<graph>/snapshot` for each ready graph: the entity count of each of its datasets, its manifest version and its storage format;
- on a local root only, `zfs list` for the dataset holding the root, the one mounted deepest among the root's parent directory and its ancestors, and its snapshots, and `/var/lib/omnigraph-metrics/lock-recoveries` for the number of stale locks the server's start has cleared.

The probe runs as node_exporter's user, so it can write the directory node_exporter reads, and receives the token through systemd credentials.
A read that fails leaves its series out of the file and keeps the others; nothing the probe finds fails the unit.
Each per-graph request that fails logs one line to the probe's journal, `omnigraph-probe: GET <path> answered HTTP <status>`, where `<path>` is `/graphs` or `/graphs/<graph>/snapshot` and `000` means no HTTP answer, or `omnigraph-probe: GET <path> answered HTTP 200 with an unreadable body`:

```bash
sudo journalctl -u omnigraph-probe -n 20 --no-pager
```

## The series

| Series | Meaning | Written |
|---|---|---|
| `vanixiets_omnigraph_ready` | 1 while `/readyz` answers `ready: true`; 0 while it answers otherwise or nothing answers | always |
| `vanixiets_omnigraph_graphs{state}` | the graphs the server serves (`served`, blocked ones included) and how many are `ready`, `loading` and `blocked` | while `/readyz` answers |
| `vanixiets_omnigraph_start_to_ready_seconds` | seconds from the main process start of the current run to the end of its start job | while the unit is active |
| `vanixiets_omnigraph_graph_reads_ok` | 1 when `GET /graphs` and the snapshot read of every ready graph succeeded; 0 when one was refused or failed, or the server did not answer `/readyz` | on every run with the `monitor` actor's token |
| `vanixiets_omnigraph_graph_entities{graph}` | entities in the graph's `main` branch, summed over its datasets | per ready graph read |
| `vanixiets_omnigraph_graph_manifest_version{graph}` | the graph manifest version of `main`, which rises with each commit | per ready graph read |
| `vanixiets_omnigraph_graph_storage_format{graph}` | the storage format (`internal_schema_version`) `main` is stamped at | per ready graph read |
| `vanixiets_omnigraph_dataset_used_bytes` | bytes the dataset holding the root uses, snapshots included | on a local root on its own ZFS dataset |
| `vanixiets_omnigraph_dataset_quota_bytes` | that dataset's quota, 0 for none | on a local root on its own ZFS dataset |
| `vanixiets_omnigraph_dataset_snapshots` | that dataset's snapshots | on a local root on its own ZFS dataset |
| `vanixiets_omnigraph_lock_recoveries_total` | stale serve locks the server's start has cleared on this host, 0 before the first | on a local root |
| `vanixiets_omnigraph_backup_last_success_timestamp_seconds` | Unix time of the last backup run whose backup, prune and check all succeeded, in `omnigraph-backup.prom` | with the backup on |

`vanixiets_omnigraph_graph_reads_ok` tells an absent per-graph series apart from a refused one.
Absent means the host gives the probe no `monitor` token (`services.omnigraph.extraBearerTokenFiles.monitor` unset), or the probe did not write its file, which `HostProbeStale` reports.
0 means the probe asked and did not get every reading: the journal line names the request and its HTTP status, a 403 on `GET /graphs` means the served root was never applied with the `monitor` grants, and a series at 0 with `vanixiets_omnigraph_ready` also 0 means the server was down.
A graph whose snapshot read failed is missing from the per-graph series while the others stay.

Every name is in `nodeExporterKeep` in `modules/clan/services/otel-collector/schema.nix`, and an assertion in the probe's module, and one in the backup's for its stamp, fails evaluation when one is missing there or the textfile collector is off.
magnetite serves its graphs from R2 today, whose root was never applied with the `monitor` grants, so its file holds the first three series and `vanixiets_omnigraph_graph_reads_ok 0`, the probe's journal shows `omnigraph-probe: GET /graphs answered HTTP 403`, and the per-graph and dataset panels of the view stay empty.

## The monitor actor

The per-graph reads need a bearer token, and the probe reads as `monitor`, an actor allowed to list the graphs and read them and nothing else, so that `admin`'s token is not read every minute.
Its token is the clan vars generator `omnigraph-monitor-token` on magnetite; `services.omnigraph.extraBearerTokenFiles.monitor` names its file, and the server's start adds it to the assembled tokens file, refusing to start if the tokens file already names `monitor`.
`modules/machines/nixos/magnetite/omnigraph/server.policy.yaml` grants it `graph_list`, and `examples.policy.yaml` grants it `read` on every example graph; `checks.x86_64-linux.omnigraph-cluster-actor-policy` holds it to those and denies it `change`, `export`, `schema_apply`, `maintain` and `config_manage`.

A policy reaches a root only through `cluster apply`, which on magnetite runs at a root's creation or by hand with the server stopped.
Until an apply has reached the served root with these grants, `GET /graphs` refuses `monitor`, `vanixiets_omnigraph_graph_reads_ok` is 0 and the per-graph series are absent; readiness and graph counts do not depend on them.
A new local root is created with them.

Regenerating the token restarts `omnigraph-server`, which reads it only at start:

```bash
clan vars generate magnetite --generator omnigraph-monitor-token --regenerate
```

## Answering OmnigraphNotServing

The alert fires when `vanixiets_omnigraph_ready == 0 or vanixiets_omnigraph_graphs{state="blocked"} > 0` has held for 5 minutes.
The first arm's instance carries the host; the second's also carries `state="blocked"`.

On the host, first look at the unit and what the probe last wrote:

```bash
systemctl status omnigraph-server omnigraph-probe.timer
sudo journalctl -u omnigraph-server -n 100 --no-pager
cat /run/node-exporter-textfile/omnigraph.prom
curl -sS http://127.0.0.1:8090/readyz | jq
```

Then, by what you find:
- The unit is `activating`: the start job is still waiting for every graph to open. A start over magnetite's R2 root takes about 4 min 50 s, so a slow one fires the alert; it resolves 5 minutes after `/readyz` answers ready. A start that outlasts its `TimeoutStartSec` fails and posts its failure notice.
- The unit failed on a local root with `omnigraph-lock-recovery` lines in the journal: the recovery refused a lock; follow "Stale-lock recovery on a local root" for the reason's manual step.
- The unit failed with `state_lock_held` and no recovery lines: on an R2 root, a direct writer's lock, which needs `sudo omnigraph-cluster force-unlock <LOCK_ID>` with the id `sudo omnigraph-cluster status --json` reports once that writer is gone. A root that was never applied needs `sudo systemctl restart omnigraph-cluster-apply` with the server stopped. Start the server again with `sudo systemctl start omnigraph-server` once the cause is gone.
- The unit failed and the journal shows a permission error on a local root: a file on the dataset belongs to someone other than `omnigraph`; `sudo find /var/lib/omnigraph -xdev ! -user omnigraph` lists them, and `sudo chown -R omnigraph:omnigraph /var/lib/omnigraph` with the server stopped fixes it.
- The unit is active and `/readyz` reports a blocked graph: graphs are opened only at a start, so a blocked graph stays blocked until the server restarts. Read which graph and why from `GET /graphs`, whose entries carry `failure` and `action`, as `admin`:

  ```bash
  sudo jq -r '"header = \"Authorization: Bearer \(.admin)\""' \
      /run/secrets/vars/per-machine/magnetite/omnigraph-bearer-tokens/tokens.json \
    | curl -sS --config - -H 'Omnigraph-Http-Api: 0.14' http://127.0.0.1:8090/graphs \
    | jq '.graphs[] | select(.state != "ready")'
  ```

  `Omnigraph-Http-Api` names the HTTP contract of the packaged omnigraph, which `omnigraph version --json` reports as `http_contract`. Correct the graph's configuration or storage, apply it with the server stopped, and start the server.
- The unit is active, `/readyz` answers ready, and the probe's file still says 0: the probe cannot reach the server. Read `sudo journalctl -u omnigraph-probe -n 20 --no-pager` and run `sudo systemctl start omnigraph-probe` to write the file again.

The alert resolves 5 minutes after the probe last found the server not ready or a graph blocked.

## Answering OmnigraphBackupStale

The alert fires when `time() - vanixiets_omnigraph_backup_last_success_timestamp_seconds > 129600`, no successful backup for 36 hours, has held for 10 minutes, so a single missed night fires it about 12 hours after the run that did not happen.
A run that fails posts `FAILED restic-backups-omnigraph.service on <host>` at once; this alert reports runs that do not happen or never succeed.

On the host:

```bash
systemctl status restic-backups-omnigraph.timer restic-backups-omnigraph.service omnigraph-backup-metric.timer
systemctl list-timers restic-backups-omnigraph.timer
sudo journalctl -u restic-backups-omnigraph -n 100 --no-pager
cat /run/node-exporter-textfile/omnigraph-backup.prom
```

Then, by what you find:
- The job failed in its prepare or cleanup step: read the `zfs` error; `zfs list -t snapshot zroot/root/omnigraph` shows a leftover `@restic`, which the next run destroys and takes anew.
- The job failed talking to R2: a 403 means the `omnigraph-backup-r2` token lost its scope or was revoked, so mint a new one for `sciexp-omnigraph-backup` alone and run `clan vars generate <host> --generator omnigraph-backup-r2 --regenerate`; a wrong-password error means `omnigraph-backup-restic` was regenerated, and the repository can only be read with the old password from the vars history.
- The timer has not run: check the host was up at 03:30 UTC; `Persistent` makes it run at the next boot after a missed night.
- The stamp in `omnigraph-backup.prom` is old while the job succeeded: read `sudo journalctl -u omnigraph-backup-metric -n 20 --no-pager`.

Run a backup by hand with `sudo systemctl start restic-backups-omnigraph.service`; on success the stamp advances, and the alert resolves at the next evaluation.
