# Verification Report

> This file is produced by the `openspec-verify-change` skill after apply completes, to confirm that the
> implementation is consistent with the specs / design / tasks. Any failed check must be returned to its
> corresponding artifact for correction before re-running verify.

**Change**: `serve-omnigraph-from-local-disk` (CAM-127)
**Verified at**: `2026-11-27 09:20` UTC
**Verifier**: `openspec-verify-change` (omp), against `main` at `d625c64e`

Prechecks: the delivery commits are on `main`: `2dbb1e25` (`feat(omnigraph): watch the server's readiness and graphs on magnetite`), `7d02f0a5` (`feat(omnigraph): serve a local root with stale-lock recovery and nightly backup`), `72596929` (`fix(omnigraph): refuse lock recovery on unreadable process state or an omnigraph at the lock pid`), `afd978d8` (`feat(magnetite): serve omnigraph from local disk`) and `27ac2fe8` (`docs(omnigraph): record the restore drills and the restore without the host`).
magnetite runs generation 296 (`system-296-link`), booted 2026-11-27 05:21:38Z after a reset without a shutdown at about 05:20:30Z.
The code was read at `d625c64e`: `modules/lib/omnigraph-lock-recovery.nix`, `modules/nixos/omnigraph.nix`, `modules/nixos/omnigraph-backup.nix`, `modules/nixos/omnigraph-probe.nix`, `modules/lib/omnigraph-cluster-roots.nix`, `modules/machines/nixos/magnetite/{default,disko}.nix`, `modules/lib/observability-hosts.nix`, `modules/lib/observability-notify-run.nix`, `modules/clan/services/otel-collector/flake-module.nix`, `modules/nixos/fleet-alert/rules.nix`, `modules/nixos/perses/resources/dashboard-omnigraph.json`, `modules/checks/omnigraph-retired-roots.nix`, `modules/vm-tests/{omnigraph-local-root,perses-greptimedb}.nix` and the runbook `packages/docs/src/content/docs/development/operations/omnigraph.md`.
No test or runtime test was re-run; `checks.x86_64-linux.omnigraph-retired-roots` at `d625c64e` was substituted from the fleet cache, which nixbot fills (`logs/cam127-verify-retired-roots-20261127T0900Z.log`).
The evidence is the deploy and drill records (`logs/agent-reports-20261126/DeployMagnetite-{probe,latest,switch}.md`, `OmnigraphRestoreDrill.md`), read-only inspection of magnetite on 2026-11-27 between 09:00 and 09:10Z (`logs/cam127-verify-{host-state,restic-units,front-r2,notices}-20261127T0900Z.log`), the stored series through `nix run .#obs-query`, read-only requests to R2 with magnetite's own credentials, and one evaluation of magnetite with the store forced to `"r2"` (`logs/cam127-verify-wayback-eval-20261127T0900Z.{nix,json}`).

---

## 1. Structural Validation (`openspec validate --all --json`)

- [ ] All items report `"valid": true`

```text
totals: 85 items, 82 passed, 3 failed
openspec validate serve-omnigraph-from-local-disk --strict: valid
```

None of the three failures is this change: `compose-hosts-from-cohesive-aspects`, `stand-up-gitea-mq-on-magnetite` and `stand-up-nixbot-on-magnetite`.

---

## 2. Task Completion (`tasks.md`)

- [ ] All `- [ ]` have been changed to `- [x]`

24 of 26; 1.6 and 5.4 stay open.

| Task | Evidence checked | Missing |
|---|---|---|
| 1.6 probe deploy | `DeployMagnetite-probe.md` (generation 291): `omnigraph.prom` had ready 1 and 10/10/0/0; `obs-query` returned `vanixiets_omnigraph_ready{host_name="magnetite"}` 1; ntfy from 05:23:53 to 05:42:59Z held 19 heartbeats and nothing else; fleet-alert's state held argentum's two pending `HostProbeStale` (a sleeping Mac) and the standing `R2CostProjected` | the dashboard as rendered: the API needs a signed-in session and no record shows the view |
| 2.8 static user deploy | `DeployMagnetite-latest.md` (generation 292): no recovery `ExecStartPre`, `User=omnigraph`, ready 1 with 10 graphs, the journal line `Found pre-existing private StateDirectory= directory /var/lib/private/omnigraph, migrating to /var/lib/omnigraph.` at 07:44:21Z, a plain `/var/lib/omnigraph` owned `65534:65534` and no `/var/lib/private/omnigraph`; the server's one restart is the switch's; from 07:43:06 to 07:58:22Z nothing but 15 heartbeats was posted; stored ready was 0 from 07:45:00 to 07:47:45, under the rule's 5 minutes | the last 4 minutes of the 15-minute window the deploy brief set |
| 3.3 backup token and vars | `vars/per-machine/magnetite/omnigraph-backup-r2/env/secret` and `omnigraph-backup-restic/password/secret` exist; with that token magnetite lists `sciexp-omnigraph-backup` (200) and is refused `sciexp` and `sciexp-postgresql-backup` (403) | the token's scope as the dashboard shows it |
| 5.1 switch | see "The switch" below | the stored query ran from magnetite, not pyrite |
| 5.2 storage | see "Storage and snapshots" below | none |
| 5.4 way back | see finding 1 and "The way back" below | the configuration does not evaluate |
| 5.5 conditionals | see "Conditionals on the store" below | none |

### The switch (5.1)

From `DeployMagnetite-switch.md` (generation 293, 2026-11-26): the bootstrap logged `no cluster state and no marker: initializing /var/lib/omnigraph/clusters/cookbooks-f17`, marked ten `seed-pending` files, applied 10 graphs `created` and wrote `cookbooks-f17.initialized` at 17:12:49Z; the ten seed units exited 0 with the R2 load's counts (457, 48, 169, 341, 449, 817, 295, 313, 349, 667) and no `seed-pending` file remained; `/readyz` 200 at 17:12:51.5Z; the probe measured start-to-ready 2.183 s against the 290 s R2 baseline (159.5 s and 183.7 s at the two R2 deploys before).
On magnetite on 2026-11-27 at 09:00Z: `find /var/lib/omnigraph ! -user omnigraph -o ! -group omnigraph | wc -l` and `find /var/lib/omnigraph -xdev ! -user omnigraph | wc -l` print 0; `/var/lib/omnigraph` is `omnigraph:omnigraph 755`, `clusters` `700`; the marker directory holds only `cookbooks-f17.initialized` (Nov 26 17:12); `omnigraph.prom` holds ready 1, graphs 10/10/0/0, `vanixiets_omnigraph_graph_reads_ok 1` and ten `vanixiets_omnigraph_graph_entities` lines with the counts above, all ten at manifest version 2 and storage format 17; the store returns the same (`count(vanixiets_omnigraph_graph_entities{host_name="magnetite"})` 10).
Stored queries: pyrite's `cameron` has no stored omnigraph credential (`omnigraph alias ready` answers `selected owner/profile has no stored credential`), so from pyrite only `/readyz` was asked through `https://omnigraph.zt/` (200, 10 served, 10 ready); from magnetite, as `admin`, `POST /graphs/cookbook-dev-graph/queries/ready` and `…/blocked` through the same front (cinnabar, `fddb:4344:343b:14b9:399:93db:4344:343b`) answered 200 with 5 and 2 rows, the counts of the switch and the drill. `monitor` is refused that route (`action=invoke_query allowed=false`), as its policy intends.

Alerts and notices since each deploy (fleet-alert's journal and every `observability-notify@` start on magnetite):

| Window (UTC) | Posted to `fleet-alerts` | Cause |
|---|---|---|
| 2026-11-26 05:23:53–05:42:59 (commit 1) | nothing | the server was not ready for 2 min 40 s with no stored 0 (the probe first ran at ready) |
| 2026-11-26 07:43:06–07:58:22 (commit 2) | nothing | ready 0 stored for under 3 minutes |
| 2026-11-26 17:11:03–2026-11-27 09:05 (commit 3 to now) | one message: `omnigraph lock recovered on magnetite`, 2026-11-27 05:22:01Z, priority 2 | the reset at about 05:20:30Z (below) |

No `observability-notify@` unit ran in that time, no fleet-alert line names any topic but `fleet-heartbeat`, `ALERTS{alertname=~"Omnigraph.*"}` is empty over the reset, and fleet-alert's `firings` is `[]`.
Notices fleet-deadman on cinnabar may have posted for the reset were not read (cinnabar was not inspected).

### Storage and snapshots (5.2)

`zfs list -t all -r zroot/root/omnigraph` at 09:00Z: the dataset uses 51.5M (refer 25.6M) of quota 20G, with snapshots `zfs-auto-snap_daily-2026-11-27-00h00` (25.9M, holding the files the restore drill replaced) and `zfs-auto-snap_hourly-2026-11-27-{06,07,08,09}h00`; `com.sun:auto-snapshot` is `true`, inherited from `zroot`.
The probe's `vanixiets_omnigraph_dataset_used_bytes 53975040` (51.47 MiB), `_quota_bytes 21474836480` (20 GiB) and `_snapshots 5` match, and the store holds them; `system_filesystem_usage_bytes{host_name="magnetite",mountpoint="/var/lib/omnigraph"}` exists (`device="zroot/root/omnigraph"`, used 26869760, free 21420703744).
`zpool history` shows `@pre-restore` taken at 04:51:32Z and destroyed at 05:14:19Z, step 9 of the runbook's restore.

### The stale-lock recovery at the reset

The previous boot ended at 05:20:30Z with `omnigraph-server` (pid 2243500) serving and its last request at 05:20:30.99Z; the boot after started at 05:21:38Z. `journalctl -b -u omnigraph-server --no-pager | grep -i -E 'lock|recover'`:

```text
Nov 27 05:22:01 magnetite omnigraph-lock-recovery[2689]: target /var/lib/omnigraph/clusters/cookbooks-f17 (inline): direct root /var/lib/omnigraph/clusters/cookbooks-f17; requested=/var/lib/omnigraph/clusters/cookbooks-f17; provider=Local
Nov 27 05:22:01 magnetite omnigraph-lock-recovery[2742]: target /var/lib/omnigraph/clusters/cookbooks-f17 (inline): direct root /var/lib/omnigraph/clusters/cookbooks-f17; requested=/var/lib/omnigraph/clusters/cookbooks-f17; provider=Local
Nov 27 05:22:01 magnetite omnigraph-lock-recovery[2404]: omnigraph-lock-recovery: omnigraph-server on magnetite cleared the stale serve lock 01M8DNH1BVCDGSB87QDAHK164C of /var/lib/omnigraph/clusters/cookbooks-f17 (pid 2243500, taken 2026-11-27T04:51:55.900111242Z) and starts; lock recoveries on magnetite: 1
Nov 27 05:22:01 magnetite omnigraph-lock-recovery[2795]: {"id":"dSvrWYvS0efV","time":1795756921,"expires":1796361721,"event":"message","topic":"fleet-alerts","title":"omnigraph lock recovered on magnetite","message":"omnigraph-server on magnetite cleared the stale serve lock 01M8DNH1BVCDGSB87QDAHK164C of /var/lib/omnigraph/clusters/cookbooks-f17 (pid 2243500, taken 2026-11-27T04:51:55.900111242Z) and starts; lock recoveries on magnetite: 1","priority":2}
```

The two `target … provider=Local` lines are `cluster status` and `force-unlock`, each in a `runuser` session `for user omnigraph(uid=979)`, so both ran as `omnigraph`.
The lock was the drill's server's (`01M8DNH1BVCDGSB87QDAHK164C`, taken 04:51:55Z, before the boot); its pid was absent in the new boot, so the program reached row 12 of design D4 and cleared it by its exact id.
The start then served: `serving omnigraph … graph_count=10` at 05:22:04.57Z, `/readyz` 200 and `Started` at 05:22:05Z, start-to-ready 4.232 s; the new lock is `01M8DQ850GTGP5AX6YHHAX7HVB`, `serve`, pid 3057.
`/var/lib/omnigraph-metrics/lock-recoveries` holds 1 (root, 0644, written 05:22); the stored `vanixiets_omnigraph_lock_recoveries_total` went from 0 to 1 at the 05:23:00 sample; entity counts and the `ready`/`blocked` answers afterwards equal those before.
Stored `vanixiets_omnigraph_ready` stayed 1 at every sample from 05:17 to 05:27 (the outage of about 95 s fell between probe runs), so `OmnigraphNotServing` had nothing to fire on.
This is the first real exercise on the host of the clearing rows; it exercised "the pid is gone", not "the pid now runs another program", which only the rehearsal check and the runtime test hold.
`zfs-set-root-omnigraph-quota` ran at 05:21:58Z (`zpool history`: `zfs set quota=20G zroot/root/omnigraph`), `active`, `Result=success`; `systemctl --failed` is empty.

### The backup

`journalctl -u restic-backups-omnigraph --since 2026-11-26`: two runs, both successful: the manual first run (2026-11-26 17:15:01–17:15:21Z, snapshot `74f6c85d`) and one nightly run (2026-11-27 03:40:17–03:40:34Z, snapshot `831ae1d2`). One nightly run exists so far; the second is due 2026-11-28 03:35:03Z (`systemctl list-timers`).
`restic-omnigraph --no-lock snapshots` lists exactly those two, both of path `/var/lib/omnigraph/.zfs/snapshot/restic` and 47.275 MiB; with one per day, `--keep-daily 7` keeps both.
`zpool history` shows the nightly run's `zfs snapshot zroot/root/omnigraph@restic` at 03:40:17 and `zfs destroy` at 03:40:34; no `@restic` exists now.
`restic-omnigraph --no-lock list locks` prints nothing: the reset at 05:20Z, an hour and 40 minutes after the run, left neither a snapshot nor a lock.
The stored stamp is 1795750833 (03:40:33Z); stored `vanixiets_omnigraph_ready` was 1 at every sample around the run, and the server answered no request with 4xx or 5xx from 03:39:30 to 03:41:30Z.

### The way back (5.4)

Evaluated at `d625c64e` with `vanixiets.omnigraphRootStore` forced to `"r2"` and `vanixiets.omnigraphBackup.enable` to `false`: `storageUri` is `s3://sciexp/omnigraph/clusters/cookbooks-f17`; `s3` is the R2 endpoint with region `auto`; `omnigraph-server`'s environment has `AWS_ENDPOINT_URL`, `AWS_ENDPOINT_URL_S3`, `AWS_REGION` and `OMNIGRAPH_CLUSTER_LEASE_SECONDS = "120"`, and its `EnvironmentFile` is the `omnigraph-r2` env; its `ExecStartPre` is only the bearer-token step; server, bootstrap, apply and the ten seeds have `User = "omnigraph"`, no `DynamicUser` and no `RequiresMountsFor`; the dataset is not declared; `users.users.omnigraph.isSystemUser` is true; the `omnigraph-r2` generator exists.
`checks.x86_64-linux.omnigraph-retired-roots` (cache hit) holds the URI on both stores.
A HEAD of `omnigraph/clusters/_omnigraph-markers/cookbooks-f17.initialized` in `sciexp` with magnetite's `omnigraph-r2` credential answers 200 (marker written 2026-11-26 02:01:26Z), so the bootstrap would adopt the root.
The configuration as a whole does not evaluate: finding 1.

### Conditionals on the store (5.5)

`rg -n "omnigraphRootStore" modules/` matches `modules/machines/nixos/magnetite/default.nix:56,58,111,128,422,624,625`, `modules/machines/nixos/magnetite/disko.nix:129` and `modules/checks/omnigraph-retired-roots.nix:19,35`. Each branch, and what selects it:

| Branch | Where | Store or local URI | Lasting? |
|---|---|---|---|
| the option and its value `"local"` | `default.nix:111`, `:128` | — | yes, the one setting |
| `storageUri` from `uriIn` | `default.nix:625` | store | yes |
| R2 settings: `s3`, `OMNIGRAPH_CLUSTER_LEASE_SECONDS`, `environmentFile` | `default.nix:638`, `:667`, `:670` (`omnigraphOnR2`, `:59`) | store | yes |
| dataset `root/omnigraph` | `disko.nix:129` | store | yes |
| `zfs-set-root-omnigraph-quota` | `default.nix:422` | store | yes |
| the way back read by the check | `omnigraph-retired-roots.nix:35` | store | yes |
| recovery `ExecStartPre` | `omnigraph.nix:1357` | local URI | yes |
| the wrapper's `runuser` and its `chown` of `OMNIGRAPH_HOME` | `omnigraph.nix:195`, `:214` | local URI | yes |
| `RequiresMountsFor` on every unit | `omnigraph.nix:261` | local URI | yes |
| optimize assertion | `omnigraph.nix:1168` | local URI | yes |
| backup's local-root assertion | `omnigraph-backup.nix:124` | local URI | yes |
| dataset and recovery series | `omnigraph-probe.nix:221`, `:243` | local URI | yes |

None is a migration step and none was removed.
Two local-only settings do not branch on the store: `vanixiets.omnigraphBackup.enable = true` (`default.nix:417`) and magnetite's `omnigraph-backup-metric`, `restic-backups-omnigraph` and `zfs-set-root-omnigraph-quota` in `notifiedUnits` (`modules/lib/observability-hosts.nix:77`, `:88`, `:101`); finding 1 follows from them.

---

## 3. Delta Spec Sync State

| Capability | Sync status | Notes |
|---|---|---|
| `graph-store` | needs sync | 10 ADDED; `openspec/specs/graph-store/spec.md` does not exist on `main` |
| `graph-store-interface` | needs sync | 22 ADDED; `openspec/specs/graph-store-interface/spec.md` does not exist on `main` |
| `world-assumptions` | needs sync, stale | 1 MODIFIED, 12 ADDED (A231–A242); the MODIFIED block no longer matches `main` (finding 4) |

A231 to A242 are free: `openspec/specs/world-assumptions/spec.md` on `main` (113 requirements, highest A332) holds none of them, and no other open change under `openspec/changes/` adds a requirement with those numbers.

---

## 4. Design / Specs Coherence Spot Check

### Findings

- [x] **FAIL 1, the way back to R2 does not evaluate** (`specs/graph-store/spec.md:20`, scenarios `switching back to the bucket` `:27` and `only one location is served` `:32`; the runbook, `omnigraph.md:252`; design D3, `design.md:65`, "Switching back is one value").
  magnetite's `notifiedUnits` name `omnigraph-backup-metric`, `restic-backups-omnigraph` and `zfs-set-root-omnigraph-quota` whatever the store (`modules/lib/observability-hosts.nix:77`, `:88`, `:101`, added by `afd978d8`), and the agent role asserts that every notified unit is a service with an `ExecStart` (`modules/clan/services/otel-collector/flake-module.nix:358-366`, from `cdd4e49e`, 2026-10-29).
  With `"r2"` the backup's units and the quota oneshot are not defined, so `observability-notify` declares them with only its hooks and the assertion fails.
  Failing scenario: evaluating magnetite with `vanixiets.omnigraphRootStore = "r2"` and `vanixiets.omnigraphBackup.enable = false`, as the runbook's "Switching back to R2" says to deploy, fails with `otel-collector agent: magnetite's notified units [… "omnigraph-backup-metric" … "restic-backups-omnigraph" … "zfs-set-root-omnigraph-quota" …] must be services with an ExecStart …`; with the backup left on, the backup module's `storageUri … must be a root under /var/lib/omnigraph/clusters` fails as well (`logs/cam127-verify-wayback-eval-20261127T0900Z.json`).
  So the way back is three edits in two files, not one setting, and the runbook names two of them.
  The witnesses miss it by design: `checks.x86_64-linux.omnigraph-retired-roots` reads none of magnetite's assertions (`design.md` Risks, the optimize limit), and `omnigraph-state-directory-transitions` switches stores on a test node, not magnetite's configuration.

- [x] **FAIL 2, a backup interrupted while pruning or checking stops every later backup** (`specs/graph-store/spec.md:85`, scenario `a night on magnetite` `:92`; `specs/graph-store-interface/spec.md:207`).
  The job's `ExecStart` runs, in nixpkgs' order, `restic backup`, `restic unlock`, `restic forget --prune …`, `restic check --read-data-subset=10%` (`systemctl cat restic-backups-omnigraph.service` on magnetite; `modules/nixos/omnigraph-backup.nix:144-180` adds no restic step before `backup`).
  `forget --prune` and `check` take an exclusive repository lock, `backup` an append lock; restic refuses an append lock while any exclusive lock exists, stale or not (`checkForOtherLocks`, `internal/repository/lock_file.go:159-206` in restic's source; `stale()` is consulted only by `unlock`, `RemoveStaleLocks`). [INFERENCE: read at restic `master`; magnetite runs restic 0.20.0.]
  Failing scenario: magnetite resets during the night's `forget --prune` or `check`, about the last 9 of the run's 16–20 s. The exclusive lock stays in `sciexp-omnigraph-backup/magnetite/locks/`. The next night's `backup` fails with `repository is already locked exclusively`, the unit fails before its `unlock` runs, and so does every night after, until someone runs `restic-omnigraph unlock`. The failure notice posts each night and `OmnigraphBackupStale` fires after 36 h, but no backup is made.
  A run interrupted during `backup` recovers: its leftover `@restic` is destroyed by the next prepare step (`omnigraph-backup.nix:156-159`), and its append lock neither blocks the next `backup` nor survives the next `unlock`.
  The runbook's "Answering OmnigraphBackupStale" (`omnigraph.md:381-388`) names the leftover snapshot but not the lock.
  The reset of 2026-11-27 05:20Z left neither: no `@restic`, no lock.

- [x] **FAIL 3, the failure notice does not name the running writer** (`specs/graph-store/spec.md:60`, scenario `a direct writer is running`: "the operator receives a failure notice naming the running writer").
  The recovery prints the writer only to the start's journal (`modules/lib/omnigraph-lock-recovery.nix:190-191`); the notice a refused start causes is `observability-notify`'s `FAILED omnigraph-server.service on magnetite` (`modules/lib/observability-notify-run.nix:61`), which carries no reason, as the runbook says (`omnigraph.md:87`).
  Failing scenario: a direct writer, such as `sudo omnigraph-cluster apply …`, runs against `/var/lib/omnigraph/clusters/cookbooks-f17` while the server starts; the notice the operator receives reads `FAILED omnigraph-server.service on magnetite`, and the writer's pid and arguments are only in `journalctl -u omnigraph-server`.
  The interface scenario `a running direct writer` (`specs/graph-store-interface/spec.md:133`) says only that the program exits naming the process, which holds.

- [x] **FAIL 4, the vocabulary requirement this change modifies has moved on `main`** (`specs/world-assumptions/spec.md:3-363`).
  The delta's MODIFIED `Grounded vocabulary for behavioral requirements` is the requirement as it stood before this change plus its 24 rows; `main` has since added 28 rows to it (`evaluator | Nix` through `state version`, `openspec/specs/world-assumptions/spec.md` at `d625c64e`, rows after the `disk | —` row), and its count scenario now reads "twenty-six terms … of which `probe`, `release`, `credential` and `evaluator` carry three".
  Failing scenario: archiving this change replaces `main`'s requirement with the delta's and drops those 28 rows, after which a behavioral requirement on `main` that uses `host registry`, `refactor` or `state version` uses an unlisted term (the requirement's scenario `A behavioral requirement uses an unlisted term`), and the count scenario says `evaluator` carries two senses while three rows remain only in history.
  Merged, the count would be twenty-seven terms, with `probe`, `release`, `credential`, `evaluator` and `writer` carrying three.
  A231–A242 themselves do not collide (§3).

### Requirements, against code and host

`graph-store` (behavioral):

| Requirement | Result |
|---|---|
| Graph data lives on the disk of the host that serves it | PASS: 25.6M referenced on `zroot/root/omnigraph` under quota 20G; the root was created empty and seeded (5.1); no unit reads R2 (`DeployMagnetite-switch.md`, check 7) |
| The storage location is chosen per host, and switching back serves what the bucket held | FAIL (finding 1); the bucket's root and marker are intact (HEAD 200; `cookbooks-f17/` and its `__cluster/lock.json` listed) |
| The graph store recovers from its own crash without a person | PASS: the reset of 2026-11-27 (above); counter 0 to 1; one low-priority notice |
| The graph store refuses to clear a writer claim it cannot prove stale | FAIL (finding 3) for the notice; every refusal row leaves `lock.json` and exits 1 in the code |
| Graph data is copied off its host every night from an instant image | FAIL (finding 2); otherwise holds: one nightly snapshot, served throughout |
| Graph data can be restored to identical answers | PASS: the in-place and off-host drills of 2026-11-27 (`design.md`, "Operator evidence, 2026-11-27") |
| Local snapshots stay available | PASS: five automatic snapshots |
| The operator learns when the graph store is not serving | PASS in code and the fleet-alert check; not fired on the host (no outage reached 5 minutes) |
| The operator learns when graph backups are overdue | PASS in code and the fleet-alert check; the stamp is seeded at first run; not fired on the host |
| The graph store's state is visible on a dashboard | PASS for the queries (every panel's query names a probe series, the backup stamp or the unit's memory, and the view is in `queryChecked`); the rendered view on the host is not verified |

`graph-store-interface`:

| Requirement | Result |
|---|---|
| The interface's trust boundary | PASS (statement of scope) |
| The root store setting yields the root's location | PASS: both URIs evaluated; `uriIn` rejects `hetzner` (check) |
| R2 settings apply only to an R2 root | PASS: none on the local server (check, `localServerSettings = [ ]`); present with `"r2"`; the generator kept |
| The graph data has a dataset of its own | PASS: mountpoint, quota, auto-snapshot `true`, the oneshot ran at boot, the three units notified, `RequiresMountsFor` on every unit (host: `/var/lib/omnigraph/clusters`) |
| The bootstrap creates and seeds the local root | PASS (5.1) |
| Every omnigraph unit runs as the static user omnigraph | PASS: host and evaluation, both stores; the wrapper runs `runuser -u omnigraph`; no file on the dataset belongs to anyone else |
| The state directory survives the moves between stores and generations | PASS for the runtime test and the 2.8 deploy; the store move on magnetite itself is finding 1 |
| Optimize is not enabled on a local root | PASS in code (`omnigraph.nix:1168-1179`); no gating test, as design Risks says |
| The server's start clears a stale serve lock | PASS against every scenario read in the code, and row 12 on the host; see the drift warning on argument spellings |
| Recoveries are counted and announced | PASS: counter file and one `Priority: low` post titled `omnigraph lock recovered on magnetite`, with the alerter token |
| A rehearsal holds the recovery's verdicts | PASS (check on `main`; not re-run) |
| The backup job copies a ZFS snapshot to its R2 repository | PASS for repository, options, prepare, cleanup, retention and secrets; FAIL for the interrupted run (finding 2) |
| The backup job runs nightly and catches up a missed night | PASS: `OnCalendar *-*-* 03:30:00 UTC`, 15m, `Persistent`; `omnigraph-backup-metric` every 60 s |
| The backup bucket deletes nothing by age | PASS: `prevent_destroy`; the only lifecycle resource names `sciexp` |
| The probe publishes readiness each minute | PASS |
| The probe publishes per-graph and storage series | PASS: ten graphs, four storage series |
| The probe reports a failed per-graph read | PASS: 403 logged and 0 at the commit 2 deploy; 1 now |
| The monitor actor reads and nothing else | PASS: `graph_list` and `read` allowed, `invoke_query` refused on the host |
| OmnigraphNotServing reports a graph store that is not serving | PASS: rule as merged (`rules.nix:481-488`), presence on hosts notifying `omnigraph-server` |
| OmnigraphBackupStale reports an overdue backup | PASS: rule as merged (`rules.nix:501-510`), presence on hosts notifying `restic-backups-omnigraph` |
| The omnigraph view is provisioned and query-checked | PASS: project `fleet`, `greptimedb-promql`, in `queryChecked` (`perses-greptimedb.nix:84-88`) |
| A runtime test proves recovery, refusal and restore | PASS (recorded runs; not re-run) |

`world-assumptions`: A231–A242 PASS as recorded assumptions; A241's "hands a static user's root-owned one to that user" held on magnetite (`/var/lib/omnigraph` `omnigraph:omnigraph` after 3.1); the MODIFIED vocabulary requirement FAILS (finding 4).

### The runbook against the modules

The unit, wrapper and path names in `omnigraph.md` exist on magnetite: `omnigraph-server`, `omnigraph-cluster-bootstrap`, `omnigraph-cluster-apply`, `omnigraph-seed-<graph>`, `omnigraph-probe`, `omnigraph-backup-metric`, `restic-backups-omnigraph` (`.timer`), `zfs-set-root-omnigraph-quota`, `omnigraph-lock-recovery`, `omnigraph-cluster` and `restic-omnigraph` on `PATH`, `/var/lib/omnigraph-metrics/lock-recoveries`, `/var/lib/omnigraph-backup-metrics/backup.prom`, `/run/node-exporter-textfile/omnigraph{,-backup}.prom`, `/run/secrets/vars/per-machine/magnetite/omnigraph-bearer-tokens/tokens.json`.
The refusal table's reasons and manual steps match `omnigraph-lock-recovery.nix` word for word, with `omnigraph-cluster` as `manualCli`.
The two sections corrected after the drills hold: step 9 says dropping `@pre-restore` frees little while the automatic snapshots hold the replaced files (the daily snapshot holds 25.9M of them now), and only a copy taken while the server ran carries a lock.
"Switching back to R2" does not hold (finding 1); "Answering OmnigraphBackupStale" lacks the stale lock (finding 2).

**Drift warnings** (non-blocking):

- The process scan matches an argument that ends in the root or contains `<root>/` (`omnigraph-lock-recovery.nix:167`), so a writer naming the root as `/var/lib/omnigraph//clusters/cookbooks-f17` or `/var/lib/omnigraph/./clusters/cookbooks-f17` is not counted, although the scenario `the process scan` (`specs/graph-store-interface/spec.md:173`) covers any argument "naming the root as `/var/lib/omnigraph/…`". A writer holding the root normally holds its lock as well, which rows 7 and 8 refuse; the gap is a reader, or a writer between taking the root and writing the record.
- The pool and quota probe (`f13f9a34`) publishes `vanixiets_zfs_dataset_used_bytes{dataset="zroot/root/omnigraph"}` (54073344 at 09:05Z, equal to the omnigraph probe's) and `_quota_bytes`; the view and the specs still name `vanixiets_omnigraph_dataset_*`, which remain true. Two series now carry one quantity.
- `modules/lib/observability-hosts.nix` and `modules/checks/machines.nix` were refactored by `9055ae0f` and `dfcee2e1`: the magnetite row and its `notifiedUnits` kept this change's three units, `checks.x86_64-linux.nixos-<host>` keeps its name, and `observabilityHostProblems` adds no rule a row breaks. Neither made a sentence of this change false; finding 1 predates them.
- The Perses commits `083caaa5`, `3d1f2ff2` and `802b2671` changed titles, layout and sessions; the view's queries are those §4 lists, and `c8ee415b` only declares the textfile options the probe and backup set.

---

## 5. Implementation Signal

- [x] No unstaged files in the worktree for this change: the code is on `main`, this file and the ticks on their own commit
- [x] All related commits have been pushed: the five delivery commits are on `main`

**Commit range**: `2dbb1e25`, `7d02f0a5`, `72596929`, `afd978d8`, `27ac2fe8`

Open items that outlive the change:

- The R2 root `s3://sciexp/omnigraph/clusters/cookbooks-f17` and its marker stay as the way back; `dev-graph-v10` is the rollback root; `dev-graph` and `dev-graph-v9` are retired, yet their objects remain (oldest 2026-08-06 and 2026-10-01, listed 09:05Z), with `dev-graph-v9.initialized`, though their lifecycle rules delete objects older than a day. The rules on `sciexp` could not be read (the `omnigraph-r2` token is refused `GET ?lifecycle`, 403); either they were never applied or they do not match.
- The second nightly backup (due 2026-11-28 03:35Z) and the first prune that removes a snapshot (after the eighth daily one) have not happened.
- The per-graph panels have data only since the switch (2026-11-26 17:12Z); their first week, and how the view reads it, is ahead.
- `omnigraph optimize` is not available on a local root (design D14); compaction of the local root waits on served optimize or on a cleanup with the server stopped.
- The restore without the host depends on a workstation holding the admin age key that decrypts `omnigraph-backup-r2` and `omnigraph-backup-restic`.
- `omnigraph-r2`'s credential stays deployed on magnetite while nothing uses it.
- pyrite's `cameron` has no omnigraph credential, so the documented aliases do not answer there.
- The rendered view (1.6) and `OmnigraphNotServing` and `OmnigraphBackupStale` firing on the host have not been observed.

---

## 6. Front-Door Routing Leak Detector (warning, non-blocking)

- [x] No files, or any existing files are legitimate residue from before schema installation

`ls docs/superpowers/specs/*.md` finds nothing.

---

## 7. Deferred Manual Dogfood vs Automated Test Equivalence

There is no `plan.md`, so no row is marked `[~]`.
The manual checks the change defers are 1.6's rendered view and 5.4's way back; `vmTests.x86_64-linux.omnigraph-state-directory-transitions` covers the systemd side of a store switch, not the evaluation of magnetite's configuration that finding 1 fails.

---

## 8. Designation Lint and Discharge Coherence

8a: the behavioral delta (`graph-store`) uses graph store, graph, example graph, seed, graph data, graph data name, storage format, entity count, stored query, writer, direct writer, writer claim, stale writer claim, crash, boot, serving, blocked graph, storage location, bucket, disk, local snapshot, graph backup, runbook and recovery notice, each a row the delta adds; "operator", "host" and "dashboard" resolve to rows on `main`.

8b:

| Requirement | Discharged by (S) | Under (W) | Status |
|---|---|---|---|
| Graph data lives on the disk of the host that serves it | root store, dataset, static user, bootstrap | A231, A241 | discharged |
| The storage location is chosen per host, and switching back serves what the bucket held | root store, R2 settings, static user, state directory | A236, A241 | not discharged: no interface requirement covers magnetite's whole configuration evaluating on the other store (finding 1) |
| The graph store recovers from its own crash without a person | clears a stale serve lock, counted and announced, rehearsal | A232, A233 | discharged; exercised on the host |
| The graph store refuses to clear a writer claim it cannot prove stale | clears a stale serve lock, rehearsal | A232 | partly: no interface requirement makes the notice name the writer (finding 3) |
| Graph data is copied off its host every night from an instant image | backup job, nightly timer | A234, A235 | partly: no requirement covers a stale exclusive lock (finding 2) |
| Graph data can be restored to identical answers | runtime test, static user, runbook | A232, A235 | discharged |
| Local snapshots stay available | dataset | A235 | discharged |
| The operator learns when the graph store is not serving | probe readiness, OmnigraphNotServing | — | discharged |
| The operator learns when graph backups are overdue | OmnigraphBackupStale | — | discharged |
| The graph store's state is visible on a dashboard | probe series, view | — | discharged for the queries |

8c: the interface delta names only what the configuration, the programs and the hosts expose; the behavioral delta names no unit, file or command.

---

## Overall Decision

- [ ] (pass) PASS — may proceed to finishing-a-development-branch and archive
- [ ] (warn) PASS WITH WARNINGS — may proceed to subsequent steps but note: …
- [x] (fail) FAIL — return to the failed artifact, correct it, then re-run verify

Four findings in §4: the way back to R2 does not evaluate (1); a backup interrupted during prune or check blocks every later one until a hand `unlock` (2); the failure notice of a refused start does not name the writer (3); the modified vocabulary requirement would drop 28 rows `main` has added (4).
Tasks 1.6 and 5.4 remain open.

**Next step**:

Correct the code, runbook or spec for each finding, then re-run verify; CAM-127 stays In Progress.
