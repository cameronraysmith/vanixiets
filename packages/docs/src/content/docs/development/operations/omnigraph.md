---
title: OmniGraph
description: "How magnetite's omnigraph-server stores, watches, recovers and backs up its graphs: the root store option, the static user, stale-lock recovery and its refusals, the nightly backup and its restore, the probe's series, and how to answer OmnigraphNotServing and OmnigraphBackupStale."
---

This runbook covers the graph store magnetite serves, `omnigraph-server.service` from `flake.modules.nixos.omnigraph` in `modules/nixos/omnigraph.nix`, where its graph data lives, and how it is watched, recovered and backed up.
magnetite serves ten example graphs, one per cookbook of the pinned `omnigraph-cookbooks`, `cookbook-agent-ops` to `cookbook-vc-os`, on port 8090, which cinnabar's TLS fronts reach over the mesh.

## Where the graphs are served from

The graph data of one cluster lives under one root, named `cookbooks-f17` on magnetite.
The internal option `vanixiets.omnigraphRootStore`, declared in magnetite's module `modules/machines/nixos/magnetite/default.nix`, says where that root lives, and takes its value from `flake.lib.omnigraphClusterRoots.stores.magnetite` in `modules/lib/omnigraph-cluster-roots.nix`; `flake.lib.omnigraphClusterRoots.uriIn` turns the option and the root name into `services.omnigraph.storageUri`:

| Value | Root | What it selects |
|---|---|---|
| `"r2"` | `s3://sciexp/omnigraph/clusters/cookbooks-f17` | the R2 endpoint, `region = "auto"`, the credentials of the clan vars generator `omnigraph-r2`, and `OMNIGRAPH_CLUSTER_LEASE_SECONDS = "120"` |
| `"local"` | `/var/lib/omnigraph/clusters/cookbooks-f17` | the ZFS dataset `zroot/root/omnigraph`, mounted at `/var/lib/omnigraph`; every unit requires that mount; the `omnigraph-cluster` wrapper runs `omnigraph` as `omnigraph`; the server's start recovers a stale lock; the nightly backup, which `vanixiets.omnigraphBackup.enable` turns on with the store; the dataset's quota oneshot; the failure notices of `restic-backups-omnigraph`, `omnigraph-backup-metric` and `zfs-set-root-omnigraph-quota`, which magnetite's row in `flake.lib.observabilityHosts` lists only on this value; the probe publishes the dataset's series |

On either value every omnigraph unit runs as the static user `omnigraph`.

magnetite is set to `"local"`, so it serves from the dataset `zroot/root/omnigraph` on its own disk, with the nightly backup on.
`stores.magnetite` is the one setting: the option, the backup, the quota oneshot and the notified units all follow it.
It is not a host setting: changing it is a pull request against `modules/lib/omnigraph-cluster-roots.nix`.

Two things must exist before a host serves `"local"` for the first time, and evaluation checks neither.
The dataset `zroot/root/omnigraph`, mounted at `/var/lib/omnigraph`, is created by hand on an installed host; `disko.nix` declares it only for a reinstall.
Without it the mount `var-lib-omnigraph.mount` fails at the switch, every omnigraph unit, each of which requires that mount through `RequiresMountsFor`, fails to start on that dependency, and `zfs-set-root-omnigraph-quota` fails on the missing dataset; the switch reports those units failed and their failure notices arrive.
The mount `/var/lib/omnigraph` has the options `defaults,zfsutil` and no `nofail`, so `local-fs.target` requires it, and the next boot without the dataset stops in emergency mode; create the dataset before the first switch to `"local"`.
The backup's vars must be generated and committed: `omnigraph-backup-r2`, whose R2 keys `clan machines update` prompts for, and `omnigraph-backup-restic`, which it generates.
`stores` names magnetite alone today, and magnetite has both; a host added to it needs both before its first deploy on `"local"`.

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
Such a directory is writable as `omnigraph` only inside a unit, through that id-mapped mount (`setup_exec_directory` in systemd's `src/core/exec-invoke.c`).
The `omnigraph-cluster` wrapper and the lock recovery run `omnigraph` through `runuser`, outside any unit, where the directory belongs to `nobody`, so neither can write the root.
A local root therefore needs `/var/lib/omnigraph` to be a dataset or a directory owned by `omnigraph`.
Replace a moved directory with the dataset before switching to local disk: stop `omnigraph-server`, check that `ls -A /var/lib/omnigraph` prints nothing, `sudo rmdir /var/lib/omnigraph`, `sudo zfs create -o mountpoint=/var/lib/omnigraph -o quota=20G zroot/root/omnigraph`, and start the server, whose start hands the dataset to `omnigraph`.

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
| 2 | a program it needs (`awk`, `chmod`, `date`, `dirname`, `id`, `install`, `jq`, `ls`, `mktemp`, `mv`, `readlink`, `timeout` or `omnigraph`) missing from its PATH; a process table it cannot read: `/proc` does not list, a process with a command line has an executable it cannot read, or a process it must judge by owner has an owner it cannot read; or the user `omnigraph` does not exist | refuses |
| 3 | a process that may write the root with an argument naming it, however the path is spelled (`/var/lib/omnigraph//clusters/cookbooks-f17/`, `/var/lib/omnigraph/clusters/x/../cookbooks-f17`, `file:///var/lib/omnigraph/clusters/cookbooks-f17`): its executable is named `omnigraph` or `omnigraph-server`, and lies in an omnigraph package in the Nix store or runs as root or `omnigraph` | refuses |
| 4 | a record not of the shape OmniGraph writes for a held lock (version 1, string `lock_id` and `operation`, RFC 3339 `created_at`, positive integer `pid`) | refuses |
| 5 | a `created_at` that is not a date | refuses |
| 6 | `omnigraph cluster status` failing, or answering with anything but one JSON object whose `lock_id` is a string or null | refuses |
| 7 | `omnigraph cluster status` reporting a lock other than the record's | refuses |
| 8 | an `operation` other than `serve`: a direct writer's lock | refuses |
| 9 | a boot time (`btime` in `/proc/stat`) it cannot read as an integer | refuses |
| 10 | a record `pid` running an executable named `omnigraph` or `omnigraph-server`, whatever the boot time says | refuses |
| 11 | a record `pid` that is running, in a lock taken during the current boot | refuses |
| 12 | anything else: a server's lock whose process is gone, or taken before this boot by a pid that now runs another program | removes it by its exact id with `force-unlock`, counts it, posts a notice, and the start goes on |

A process with an empty command line, a kernel thread or a zombie, has no executable and holds no file, so row 2 skips it.
An executable named `omnigraph` outside the Nix store and run by another user is not omnigraph's, and row 3 ignores it, so no user can hold the server down by running one.
Row 3 compares each argument with the root after normalising both as text, without reading the file system: runs of slashes collapse, `.` segments drop, a `..` segment takes away the one before it, and a trailing slash goes.
It does not follow a symbolic link, so a writer that names the root through a link to it, or through a link followed by `..`, is not counted there; rows 10 and 11 still judge the lock's own pid.

A recovery adds one to `/var/lib/omnigraph-metrics/lock-recoveries`, which the probe publishes as `vanixiets_omnigraph_lock_recoveries_total`, logs `omnigraph-lock-recovery: omnigraph-server on magnetite cleared the stale serve lock <id> of <root> (pid <pid>, taken <created_at>) and starts; lock recoveries on magnetite: <n>`, and posts that message at low priority to `fleet-alerts` with the title `omnigraph lock recovered on magnetite`.
A recovery is an expected event after a crash, not an alert; a failed post does not fail the start.
When the counter cannot be written, the journal says `omnigraph-lock-recovery: the lock-recovery counter /var/lib/omnigraph-metrics/lock-recoveries could not be written`, the message ends in `the lock-recovery counter /var/lib/omnigraph-metrics/lock-recoveries could not be written` instead of the count, the notice is posted all the same, and the start goes on: the lock is already gone.

A refusal leaves `lock.json` exactly as it was and fails the start with exit status 1: it posts the reason and the manual step below to `fleet-alerts` at default priority, titled `omnigraph lock not recovered on magnetite`, as `omnigraph-server on magnetite stays stopped: omnigraph-lock-recovery left <root>/__cluster/lock.json in place: <reason>. <manual step>`; `Restart=on-failure` tries again within the start limit, posting once per refused start, the failure notice `FAILED omnigraph-server.service on magnetite` arrives, and `OmnigraphNotServing` fires after 5 minutes.
The notice carries what the reason and the manual step name: the root's path, the lock's id, and for some rows its operation, pid and creation time, and a process's pid and executable name (`omnigraph` or `omnigraph-server`).
It never carries a line of `lock.json`, a token, or a process's arguments: a command line can hold anything, so only the journal, which root reads, gets it.
A post that fails is logged as `omnigraph-lock-recovery: the refusal notice was not posted` and changes neither the refusal nor its exit status.
The start's journal holds the same reason:

```bash
sudo journalctl -u omnigraph-server -n 50 --no-pager | grep omnigraph-lock-recovery
```

Each refusal prints two lines, `omnigraph-lock-recovery: left <root>/__cluster/lock.json in place: <reason>` and `omnigraph-lock-recovery: omnigraph-server stays stopped until the lock is cleared. <manual step>`, and between them, when it names a process, a third with that process's command line, `omnigraph-lock-recovery: pid <pid> runs <executable>: <argv>` or, for an executable it cannot read, `omnigraph-lock-recovery: pid <pid>'s command line: <argv>`:

| Row | Reason | Manual step |
|---|---|---|
| 2 | `<program> is not on the PATH of omnigraph-lock-recovery` | `Check the program's runtime inputs (systemctl cat omnigraph-server), and once no omnigraph process runs against the root, run: omnigraph-cluster force-unlock <lock_id>` |
| 2 | `the process table /proc cannot be listed` | `Check that /proc is mounted and readable by root (ls /proc), then run: systemctl restart omnigraph-server` |
| 2 | `the command line of pid <pid> cannot be read`, `the executable of pid <pid> cannot be read` or `the owner of pid <pid> (<executable name>) cannot be read` | `Confirm with ps -o pid,user,args -p <pid> that it is not an omnigraph process using the root, then run: systemctl restart omnigraph-server` |
| 2 | `the user omnigraph does not exist, so the processes that may write the root cannot be told apart` | `Once no omnigraph process runs against the root (ps -eo pid,user,args), run: omnigraph-cluster force-unlock <lock_id>` |
| 3 | `an omnigraph process has the root open (pid <pid>, <executable name>)` | `Wait for that process to finish or stop it, then run: systemctl restart omnigraph-server` |
| 4 | `the record is not the shape omnigraph writes for a held lock (…)` | `Read <lock> and omnigraph-cluster status --json, and once no omnigraph process runs against the root, run: omnigraph-cluster force-unlock <lock_id>` |
| 5 | `the record's created_at (<value>) is not a date` | the same, with the record's id |
| 6 | `omnigraph cluster status failed, so the record's lock <id> cannot be confirmed as the cluster's`, or `omnigraph cluster status --json did not answer with one JSON object whose lock_id is a string or null, so the record's lock <id> cannot be confirmed as the cluster's` | `Read omnigraph-cluster status --json, and once no omnigraph process runs against the root, run: omnigraph-cluster force-unlock <id>` |
| 7 | `the record names lock <id> but omnigraph cluster status reports <other>, so the lock changed while it was read` | `Run systemctl restart omnigraph-server to read it again; if it persists, compare <lock> with omnigraph-cluster status --json` |
| 8 | `lock <id> was taken by a direct <operation> writer (pid <pid>, <created_at>), whose interrupted work needs its own recovery` | `With no omnigraph process running against the root, find its deployment with omnigraph-cluster status --json, then run omnigraph-cluster force-unlock <id> and omnigraph-cluster apply --deployment-id <deployment_id> --writers-stopped --json; for a writer other than an apply, confirm it stopped and run omnigraph-cluster force-unlock <id>` |
| 9 | `the boot time in /proc/stat cannot be read, so whether lock <id> was taken in this boot cannot be told` | `Confirm pid <pid> is not an omnigraph-server holding the root (ps -o pid,args -p <pid>), then run omnigraph-cluster force-unlock <id> and systemctl restart omnigraph-server` |
| 10 | `pid <pid>, which lock <id> names, is running <executable name>, so the lock may be that server's whatever the boot time says` | `Confirm pid <pid> does not serve the root (ps -o pid,args -p <pid>); if it does not, run omnigraph-cluster force-unlock <id> and systemctl restart omnigraph-server; if it does, stop it, then run systemctl restart omnigraph-server` |
| 11 | `lock <id> was taken in this boot (<created_at>) by pid <pid>, which is running` | `Confirm pid <pid> is not an omnigraph-server holding the root (ps -o pid,args -p <pid>), then run omnigraph-cluster force-unlock <id> and systemctl restart omnigraph-server` |

Any other step that fails, outside the checks above (the program's working directory that cannot be made, for instance), is caught by the program's trap on errors and refused the same way, with the reason ``the step `<command>` (line <n>) failed with exit status <status>`` and the manual step `Read journalctl -u omnigraph-server, and once no omnigraph process runs against the root, run: omnigraph-cluster force-unlock <lock_id>`; the program ends in no other way than nothing to do, a recovery, or exit status 1 with a posted reason.

Run the manual commands as root (`sudo omnigraph-cluster …`, `sudo systemctl …`).
A `force-unlock` that does not report the lock removed fails the start with `omnigraph cluster force-unlock <id> did not report the lock removed` and posts that with its manual step, titled as a refusal; read the command's output in the same journal.
Once the start limit is spent, systemd refuses further starts until `sudo systemctl reset-failed omnigraph-server.service`.

The recovery cannot tell a server in another pid namespace, such as a container, from a dead one: that server's record holds its pid inside the namespace, which on the host is absent or another program, so row 10 never sees it, row 11 stops the unlock only while some host process happens to hold that pid, and otherwise only row 3 does, when the scan finds the server by its arguments.
Serve or write this root only from the host.

On an R2 root none of this runs: a lock in the bucket carries a lease, and a successor takes over a crashed server's lock once the lease expires.

## Why optimize is not enabled on a local root

`omnigraph optimize` runs directly against storage, not through the server.
On a local root it exits with its admission lock still in `lock.json`, logging `cluster admission retained … use exact-ID cluster force-unlock`.
The server's next start then meets a direct writer's lock, which the recovery refuses (row 8), and the server stays down until someone runs `sudo omnigraph-cluster force-unlock <LOCK_ID>`.
An assertion in `modules/nixos/omnigraph.nix` therefore fails evaluation when `services.omnigraph.optimize.enable` is set for a local root.
Optimize on a local root is not provided; on an R2 root the option is unchanged and off on magnetite.

## The nightly backup

`vanixiets.omnigraphBackup.enable` (`modules/nixos/omnigraph-backup.nix`) backs a local root up off the host every night.
It is on for magnetite's local root; the module's assertions refuse an `s3://` root, a job that backs up anything but the snapshot directory, a host whose `notifiedUnits` lack `restic-backups-omnigraph`, `omnigraph-backup-metric` or `zfs-set-root-omnigraph-quota`, and a host whose textfile collector does not keep the backup's series.

A file-by-file copy of a live root may not open, so the backup is taken from an instant image.
`restic-backups-omnigraph`, run by its timer every night at 03:30 UTC plus up to 15 minutes, and after a missed night at the next boot:
1. takes the ZFS snapshot `zroot/root/omnigraph@restic`, destroying one a failed run left;
2. removes the repository's stale locks with `restic unlock`;
3. backs up only `/var/lib/omnigraph/.zfs/snapshot/restic`, a fixed path, so restic finds each run's parent;
4. prunes to 7 daily, 4 weekly and 6 monthly copies per host, and reads back a tenth of the repository;
5. destroys the snapshot.

A backup takes a shared lock on the repository, and prune and check take an exclusive one; restic refuses a backup while any exclusive lock is in the repository, stale or not.
A run interrupted during its prune or check, by a reset for instance, leaves its exclusive lock behind, so step 2 runs before the backup.
restic counts a lock as stale when its time is more than 30 minutes old, which a running restic refreshes every 5 minutes, or when it was taken on this host by a process that is gone (restic 0.20.0, `internal/repository/lock_file.go`).
So `unlock` removes the lock of a restic that is still running when that lock has not been refreshed for 30 minutes: a restic suspended, or cut off from the repository, for that long; one on another host whose clock is more than 30 minutes behind this one; or this host's clock stepped more than 30 minutes forward.
Each host has a repository path of its own, so the nightly job is that path's only locking writer; the restore commands in this runbook take `--no-lock`, and a locking command run by hand (a `restic-omnigraph prune`, say) is the one that could lose its lock to the night's `unlock` under those conditions.

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
The steps are the ones `vmTests.x86_64-linux.omnigraph-local-root` runs and checks to identical entity counts and stored-query answers, all but the rollback in step 3.
On 2026-11-27 two restores of the nightly backup `831ae1d2` were rehearsed: these steps in place on magnetite, which brought the graphs back identical with the server down for 37 s, and the restore without the host below, on a Mac, which served the same graphs from a scratch directory.
On a host that no longer has the dataset, create it first as the switch to local disk does: `sudo zfs create -o mountpoint=/var/lib/omnigraph -o quota=20G zroot/root/omnigraph`.

1. Stop the nightly backup's timer and the server, so that no backup runs over a half-restored dataset; the prune after such a backup keeps one backup a day and would drop that day's good one:
   ```bash
   sudo systemctl stop restic-backups-omnigraph.timer omnigraph-server.service
   ```
   If `systemctl is-active restic-backups-omnigraph.service` answers `activating`, a backup is running; wait until it answers `inactive`.
2. Pick the backup from `sudo restic-omnigraph snapshots`: its id, or `latest`, is `<SNAPSHOT>` below.
3. Keep the dataset's current contents, so that a failed restore can go back to them:
   ```bash
   sudo zfs snapshot zroot/root/omnigraph@pre-restore
   ```
   To go back, with the server stopped, run `sudo zfs rollback -r zroot/root/omnigraph@pre-restore`; `-r` also destroys the snapshots taken after it, automatic ones included.
4. Empty the dataset; its ZFS snapshots are untouched:
   ```bash
   sudo find /var/lib/omnigraph -mindepth 1 -xdev -delete
   ```
5. Restore the chosen backup's snapshot directory into the dataset:
   ```bash
   sudo restic-omnigraph restore <SNAPSHOT>:/var/lib/omnigraph/.zfs/snapshot/restic --target /var/lib/omnigraph
   ```
6. Give every file to `omnigraph`. The backup records each file's numeric owner on the host it was taken on, the uid and gid of `omnigraph` there (`sudo restic-omnigraph ls <SNAPSHOT> --json` shows them), and restores those numbers; on a host where `omnigraph` has another uid, as after a reinstall, the restored files belong to a uid the server, running as `omnigraph`, cannot write as. The `chown` gives every file to `omnigraph` whatever the backup recorded.
   ```bash
   sudo chown -R omnigraph:omnigraph /var/lib/omnigraph
   ```
7. Remove the lock the backup carries: the server was running when the snapshot was taken, so every backup holds its serve lock.
   ```bash
   sudo jq -r .lock_id /var/lib/omnigraph/clusters/cookbooks-f17/__cluster/lock.json
   sudo omnigraph-cluster force-unlock <LOCK_ID>
   ```
   Without this step the server's start treats the restored lock like a crashed server's and clears it when the recovery's checks pass, counting it as a recovery and posting a notice.
8. Start the server and compare:
   ```bash
   sudo systemctl start omnigraph-server.service
   sudo systemctl start omnigraph-probe.service
   grep vanixiets_omnigraph_graph_entities /run/node-exporter-textfile/omnigraph.prom
   ```
   The entity counts should equal those stored on the night of the backup, for example from `nix run .#obs-query -- --table promql 'vanixiets_omnigraph_graph_entities{host_name="magnetite"}'`.
9. Once they do, drop the snapshot of step 3 and start the timer again:
   ```bash
   sudo zfs destroy zroot/root/omnigraph@pre-restore
   sudo systemctl start restic-backups-omnigraph.timer
   ```
   If they do not, roll back as step 3 says before starting the timer.
   The replaced files' space stays within the dataset's quota while any snapshot taken before the restore remains, the automatic ones as well as the one of step 3, so dropping that one frees little; it returns as the automatic ones expire, within a week on magnetite, which keeps 4 hourly, 3 daily and 1 weekly snapshot.

To return to a recent state without R2, the dataset's hourly, daily and weekly ZFS snapshots are listed by `zfs list -t snapshot zroot/root/omnigraph`.
A copy taken while the server ran carries its lock, so a copy from one of them needs the same `chown` and unlock; this path is not exercised by a test.
The snapshot of step 3, taken after the server's clean stop, holds no lock.

### Restoring without the host

A copy of the backup can be read and served on any machine holding the repository's clan vars keys, without magnetite and without writing to the bucket.
Use restic and `omnigraph` at the repository's pins, for example in `nix shell --inputs-from . nixpkgs#restic .#omnigraph`.
Every restic command takes `--no-lock`, so it writes no lock object to the repository; run nothing but `snapshots`, `ls` and `restore`.
The credentials go to files only the current user can read, and the restic password reaches restic as a file:
```bash
umask 077
S=$(mktemp -d)
clan vars get magnetite omnigraph-backup-r2/env > "$S/r2.env"
clan vars get magnetite omnigraph-backup-restic/password > "$S/restic.pw"
r() { ( set -a; . "$S/r2.env"; set +a
  restic -r s3:https://1ece4a9a8f092f8cbdd679d22b9ecb1f.r2.cloudflarestorage.com/sciexp-omnigraph-backup/magnetite \
    -o s3.bucket-lookup=path -o s3.region=auto \
    --password-file "$S/restic.pw" --cache-dir "$S/cache" --no-lock "$@" ); }
r snapshots
r restore <SNAPSHOT> --target "$S/restore"
```
Without a `:<path>` after the id the restore keeps the backed-up path, so the root is under the snapshot directory.
Clear the serve lock the backup carries, and serve the copy on a loopback port with a tokens file made for it:
```bash
export OMNIGRAPH_HOME="$S/home"; mkdir -p "$OMNIGRAPH_HOME"
ROOT="$S/restore/var/lib/omnigraph/.zfs/snapshot/restic/clusters/cookbooks-f17"
omnigraph --target "$ROOT" cluster force-unlock "$(jq -r .lock_id "$ROOT/__cluster/lock.json")"
printf '{"admin":"%s"}' "$(openssl rand -hex 32)" > "$S/tokens.json"
OMNIGRAPH_SERVER_BEARER_TOKENS_FILE="$S/tokens.json" \
  omnigraph-server --cluster "$ROOT" --bind 127.0.0.1:18090 --require-all-graphs
```
The root's bootstrap marker and its deployment record name `/var/lib/omnigraph/clusters/cookbooks-f17`, but the server serves the copy from wherever it lies.
Stop the server and remove `$S` when done.

## Switching back to R2

Setting `flake.lib.omnigraphClusterRoots.stores.magnetite = "r2"` serves `s3://sciexp/omnigraph/clusters/cookbooks-f17` as the bucket held it when magnetite left it.
Its markers are still in the bucket, so the bootstrap adopts the root rather than recreating it.

What carries over: nothing written while serving locally.
Every load, apply and seed of the local root stays on the dataset, and the bucket's root has none of them.
The R2 settings, the `omnigraph-r2` generator and the retired and rollback roots were kept unchanged under `"local"`, so the R2 configuration is whole.
On R2, the dataset series and `vanixiets_omnigraph_lock_recoveries_total` are no longer written, and the per-graph series depend on whether the bucket's root was applied with the `monitor` grants.

The units run as `omnigraph` on both stores, so switching changes no unit's user and no state directory, and the dataset may stay mounted at `/var/lib/omnigraph`, holding the local root for a later return; `vmTests.x86_64-linux.omnigraph-state-directory-transitions`, with RustFS standing in for R2, shows every unit starting and serving from the bucket with the dataset mounted.
Change that one value and deploy magnetite; nothing else needs editing.
The backup turns off with the store, so the nightly job, its timer and `omnigraph-backup-metric` are no longer defined, and neither is the quota oneshot; magnetite's row stops listing those three units, so no failure notice names them, and `OmnigraphBackupStale` no longer expects magnetite.
The backup's textfile goes at the switch: `omnigraph-backup` is no longer among `vanixiets.nodeExporter.textfileWriters`, so the activation removes `/run/node-exporter-textfile/omnigraph-backup.prom` and prints `node-exporter-textfile: removed /run/node-exporter-textfile/omnigraph-backup.prom, which no writer in vanixiets.nodeExporter.textfileWriters writes`; node_exporter's next scrape no longer has the stamp or the file's mtime, so neither `OmnigraphBackupStale` nor `HostProbeStale` fires on a file left behind (`modules/nixos/node-exporter-textfile.nix`, which removes every textfile no declared writer writes).
NixOS runs that activation at boot and on `switch-to-configuration switch` and `test`, not on `boot` or `dry-activate`; after a `switch-to-configuration boot` to `"r2"` the running generation still writes the file until the reboot, which empties `/run`, and the new generation's activation at boot finds nothing to remove.
The backup repository in `sciexp-omnigraph-backup` and the `omnigraph-backup-r2` and `omnigraph-backup-restic` vars stay as they are, for a later return to the disk.
`checks.x86_64-linux.omnigraph-retired-roots` evaluates magnetite on both stores and holds what the switch changes: the root's location, the R2 environment and credential of the server, the backup's option, whether the backup's textfile is among the files the activation keeps, which of those three units are notified, and that every notified unit is a service with an `ExecStart`.

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
magnetite's local root is applied with the `monitor` grants when the bootstrap creates it, so its file holds every series above.
Its R2 root was never applied with those grants: served from R2, the file holds the first three series and `vanixiets_omnigraph_graph_reads_ok 0`, the probe's journal shows `omnigraph-probe: GET /graphs answered HTTP 403`, and the per-graph and dataset panels of the view stay empty.

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
- The job failed with `repository is already locked exclusively by PID <pid> on <host>`: the job removes stale locks before it backs up, so this lock belongs to a restic that is running, or to one on another host whose lock is less than 30 minutes old. Read its host, pid and time with `sudo restic-omnigraph --no-lock list locks` and `sudo restic-omnigraph --no-lock cat lock <id>`; once that restic has stopped (`ps -o pid,args -p <pid>` on its host), `sudo restic-omnigraph unlock` removes the lock. `sudo restic-omnigraph unlock --remove-all` also removes locks that are not stale; run it only when you are sure that no restic uses the repository.
- The job failed talking to R2: a 403 means the `omnigraph-backup-r2` token lost its scope or was revoked, so mint a new one for `sciexp-omnigraph-backup` alone and run `clan vars generate <host> --generator omnigraph-backup-r2 --regenerate`; a wrong-password error means `omnigraph-backup-restic` was regenerated, and the repository can only be read with the old password from the vars history.
- The timer has not run: check the host was up at 03:30 UTC; `Persistent` makes it run at the next boot after a missed night.
- The stamp in `omnigraph-backup.prom` is old while the job succeeded: read `sudo journalctl -u omnigraph-backup-metric -n 20 --no-pager`.

Run a backup by hand with `sudo systemctl start restic-backups-omnigraph.service`; on success the stamp advances, and the alert resolves at the next evaluation.
