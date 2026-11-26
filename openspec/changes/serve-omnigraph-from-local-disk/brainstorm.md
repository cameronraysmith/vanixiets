<!--
Raw capture of the brainstorming for this change.
The exploration was nine research reports written on 2026-11-26 (a crash probe of a local cluster root, OmniGraph's local and S3 roots, its store needs, Lance's storage guidance, S3-compatible store candidates, Hetzner Object Storage, peer fleets and magnetite's disk, OmniGraph's telemetry surface, and the fleet's observability patterns) and the operator's decisions the same day; this file records that decision chain.
-->

# Brainstorm: serve OmniGraph from local disk on magnetite

## Background

magnetite serves ten example graphs, one per cookbook of the pinned `omnigraph-cookbooks`, from the cluster root `s3://sciexp/omnigraph/clusters/cookbooks-f17` (`modules/machines/nixos/magnetite/default.nix`, `services.omnigraph.storageUri`; `modules/lib/omnigraph-cluster-roots.nix`).
The `sciexp` bucket is placed in eastern North America (`location = "enam"` in `modules/terranix/cloudflare.nix`), and magnetite runs in Hetzner's fsn1.
A server start takes about 4 min 50 s to open the ten graphs, and creating the root took about 26 min, roughly 1.5 s per object over about 1,019 writes.
Every one of those costs is a round trip across the Atlantic; the graphs themselves are a few MB each.

OmniGraph 0.16.0 admits one writer process per cluster and supports no read replicas (`docs/user/deployment.md`, "Writer topology"), so a store shared between hosts buys nothing here.
The Lance and LanceDB teams rank local NVMe fastest (p95 under 10 ms) and object storage slowest (several hundred ms per request), and pair local disk with "be very diligent about backing up".
Hetzner Cloud's local disk is NVMe; magnetite has one disk of about 328 GB with ZFS pool `zroot` (188 GiB used, 111 GiB free on 2026-11-26).

## What the research found

- A local root is a supported OmniGraph deployment, documented first; the omnigraph module already accepts one beneath `/var/lib/omnigraph`, and `vmTests.x86_64-linux.omnigraph-seed` serves `/var/lib/omnigraph/clusters/test`.
- On a local root the cluster lock `__cluster/lock.json` has no lease. After a kill the lock stays, naming the dead pid, and every restart refuses with `state_lock_held` in about 0.17 s until `omnigraph cluster force-unlock <id>` runs. `force-unlock` checks only the id: in the probe it removed a live server's lock, and that server kept writing.
- The lock record holds `version`, `lock_id`, `operation`, `created_at` and `pid`; no host, boot id or start time.
- Commits are atomic across a kill: five trials of kill during writes left no partial batch, and the restart served the same counts.
- A plain copy of a live root is not a backup: `cp -a` opened consistently 2 times of 8; a copy taken with the server frozen (the stand-in for an atomic snapshot) opened 8 times of 8. Every copy carries the original's lock and needs `force-unlock`.
- OmniGraph exports no metrics. `/readyz` (public) gives ready, status and served, ready, loading and blocked counts; `GET /graphs` and `GET /graphs/{id}/snapshot` (bearer token) give per-graph state, entity counts, manifest version and storage format. OpenTelemetry is traces only and trusts only public certificate authorities.
- `omnigraph cleanup` runs only directly against storage, so only with the server stopped.
- Hetzner Object Storage documents conditional PUT as unsupported on versioned buckets and says nothing of unversioned ones, is HDD-backed, and its FAQ advises against many small objects and latency-sensitive use.
- R2 cannot be moved: a bucket's location hint is fixed at creation.

## Decision chain (operator, 2026-11-26)

**Where the root lives.**
A local ZFS dataset on magnetite's NVMe, quota 20 GiB, with local auto-snapshots.
Hetzner Object Storage is rejected (conditional writes undocumented on unversioned buckets, HDD, its own FAQ).
The new root is created and seeded fresh by the existing bootstrap: the ten graphs are example data, so nothing is copied from R2.

**R2 stays a supported choice.**
One host-level setting selects local disk or R2 for the same root name (`flake.lib.omnigraphClusterRoots`).
Everything R2-specific stays: the `omnigraph-r2` keys generator, endpoint and region, the lease seconds, the lifecycle rules and the retired-roots check. The lease setting applies only to S3.
Switching back serves the R2 root as it was left; writes made on the local root do not follow.

**Stale-lock recovery on a local root.**
Run only by the server's own start, before launch.
Unlock only when no omnigraph process has the root open (direct CLI writers included), the lock is a `serve` lock, and its pid is dead or the lock predates the current boot; unlock by the exact id; count each recovery for the dashboard and post an info notice each time.
Refuse otherwise, and let the start fail visibly.

**Nightly backup.**
An atomic ZFS snapshot of the dataset, then restic from the snapshot to a new R2 bucket `sciexp-omnigraph-backup` declared in terranix, following `postgresql-backup.nix`: generated restic password, prompted R2 keys, a success timestamp through the textfile collector, a failure notice, a timer naming its zone.
Never copy a live root with cp or rsync.
A runbook covers restore, the force-unlock a restored root needs, and switching back to R2.

**Monitoring.**
A minutely probe of `/readyz` (ready; served, ready, loading and blocked counts; start-to-ready seconds) and, with a new read-only `monitor` actor and a generated token, per-graph entity counts, manifest version and storage format; the dataset's used bytes, quota and snapshot count.
Rules `OmnigraphNotServing` (not ready, or any graph blocked, for 5 min; warning) and `OmnigraphBackupStale` (36 h; warning), each with fixtures, fire-and-resolve legs and threshold mutants.
A Perses view `dashboard-omnigraph.json`, and docs.
No tracing (the exporter trusts only public certificate authorities, and the fleet's collector serves an internal one), no JSON log receiver (the fatal log events end the server process, which the readiness rule and the failure notice already report), no scheduled cleanup (it needs the server stopped).

**Runtime test.**
`vmTests.x86_64-linux.omnigraph-local-root`, medium, ZFS inside the VM, declared in `testSizes.vmTests`: kill -9, recovery, same data; a direct writer holding the root makes recovery refuse; snapshot, restic, restore, unlock, identical counts and query results; the probe's series present. Runs on pyrite only.

**Rollout on magnetite, gated.**
The dataset is created by hand once before the switch: disko does not create datasets on an installed machine, as with `root/greptimedb` and `root/postgresql-dumps`.
`omnigraph-server` runs with `DynamicUser` and `StateDirectory=omnigraph`, so `/var/lib/omnigraph` is a symlink to `private/omnigraph` (observed on magnetite on 2026-11-26: `lrwxrwxrwx root root /var/lib/omnigraph -> private/omnigraph`, dated Aug 6).
The operator mints the R2 token for the backup bucket; the terraform apply for the bucket needs an explicit yes.
Rollback is the previous generation, serving `cookbooks-f17` on R2, untouched.

**Out of scope.**
The collector's unit name for `omnigraph-server` and its failure notice are fixed separately.
pyrite and the Macs reach OmniGraph at the same URL and are unaffected.

## Forks decided in design (agent, for operator review)

1. The dataset mounts at `/var/lib/private/omnigraph/clusters`, not `/var/lib/omnigraph`, because the latter is systemd's symlink; the root stays addressed as `/var/lib/omnigraph/clusters/cookbooks-f17`, and the bootstrap markers in `clusters/_omnigraph-markers` share the dataset, so one snapshot holds root and markers together.
2. The recovery step runs as a privileged `ExecStartPre` (`+`), because the server's sandbox (`ProtectProc=invisible`, `PrivateUsers`) hides other users' processes, and a direct writer run as root must be seen.
3. The host setting is a value `local` or `r2` passed to `flake.lib.omnigraphClusterRoots`, which returns the root's URI; the modules derive local-only behaviour (recovery, backup, dataset metrics) from the URI's scheme.
4. Three delivery commits: monitoring of today's server first; then local-root support (recovery, backup, test, bucket) with magnetite still on R2; then magnetite's switch.
