# Verification Report

> This file is produced by the `openspec-verify-change` skill after apply completes, to confirm that the
> implementation is consistent with the specs / design / tasks. Any failed check must be returned to its
> corresponding artifact for correction before re-running verify.

**Change**: `serve-omnigraph-from-local-disk` (CAM-127)
**Verified at**: `2026-11-27 09:20` UTC (first run, against `main` at `d625c64e`); `2026-11-27 10:15` UTC (second run, against the remedies `okoptrow`, `zmmzwqtk`, `utrkprxr` and `tuwmzvxy` at `ddec126c`, over `main` at `30223609`)
**Verifier**: `openspec-verify-change` (omp)

Prechecks: the delivery commits are on `main`: `2dbb1e25` (`feat(omnigraph): watch the server's readiness and graphs on magnetite`), `7d02f0a5` (`feat(omnigraph): serve a local root with stale-lock recovery and nightly backup`), `72596929` (`fix(omnigraph): refuse lock recovery on unreadable process state or an omnigraph at the lock pid`), `afd978d8` (`feat(magnetite): serve omnigraph from local disk`) and `27ac2fe8` (`docs(omnigraph): record the restore drills and the restore without the host`).
magnetite runs generation 296 (`system-296-link`), booted 2026-11-27 05:21:38Z after a reset without a shutdown at about 05:20:30Z.
The code was read at `d625c64e`: `modules/lib/omnigraph-lock-recovery.nix`, `modules/nixos/omnigraph.nix`, `modules/nixos/omnigraph-backup.nix`, `modules/nixos/omnigraph-probe.nix`, `modules/lib/omnigraph-cluster-roots.nix`, `modules/machines/nixos/magnetite/{default,disko}.nix`, `modules/lib/observability-hosts.nix`, `modules/lib/observability-notify-run.nix`, `modules/clan/services/otel-collector/flake-module.nix`, `modules/nixos/fleet-alert/rules.nix`, `modules/nixos/perses/resources/dashboard-omnigraph.json`, `modules/checks/omnigraph-retired-roots.nix`, `modules/vm-tests/{omnigraph-local-root,perses-greptimedb}.nix` and the runbook `packages/docs/src/content/docs/development/operations/omnigraph.md`.
No test or runtime test was re-run; `checks.x86_64-linux.omnigraph-retired-roots` at `d625c64e` was substituted from the fleet cache, which nixbot fills (`logs/cam127-verify-retired-roots-20261127T0900Z.log`).
The evidence is the deploy and drill records (`logs/agent-reports-20261126/DeployMagnetite-{probe,latest,switch}.md`, `OmnigraphRestoreDrill.md`), read-only inspection of magnetite on 2026-11-27 between 09:00 and 09:10Z (`logs/cam127-verify-{host-state,restic-units,front-r2,notices}-20261127T0900Z.log`), the stored series through `nix run .#obs-query`, read-only requests to R2 with magnetite's own credentials, and one evaluation of magnetite with the store forced to `"r2"` (`logs/cam127-verify-wayback-eval-20261127T0900Z.{nix,json}`).

## 0. Second run, 2026-11-27 10:15 UTC

The first run (§1 to §8 below, kept as written at 09:20) failed four checks.
Four changes not yet on `main` remedy them: `okoptrow` (`fix(omnigraph-backup): remove stale restic locks before each backup`), `zmmzwqtk` (`fix(omnigraph): post a notice when the lock recovery refuses, naming the reason`), `utrkprxr` (`fix(magnetite): switch the omnigraph root store with one setting`) and `tuwmzvxy` (`docs(openspec): amend serving omnigraph from local disk after verification`).
The code and artifacts were read at `tuwmzvxy` (`ddec126c`). None of it is deployed: magnetite still runs generation 296 (read at 10:09Z: no new boot, no notice but heartbeats since 09:05Z, no backup run since 03:40Z, counter 1, no `@restic`, no restic lock, `systemctl --failed` empty).
Run here: `checks.x86_64-linux.omnigraph-retired-roots` and `checks.x86_64-linux.omnigraph-lock-recovery-rehearsal` at `ddec126c` (both pass, built on magnetite as a remote builder, `logs/cam127-reverify-{omnigraph-retired-roots,omnigraph-lock-recovery-rehearsal}-20261127.log`); one evaluation of the whole flake with `stores.magnetite = "r2"` and nothing else changed, from a scratch copy of `ddec126c` (`logs/cam127-reverify-r2-only-setting-20261127T1010Z.{nix,json}`); the recovery program built from `flake.lib.omnigraphLockRecovery` at `ddec126c` over stubs of `omnigraph` and `ntfy-send` and a scratch process table (`logs/cam127-reverify-recovery-stubs-20261127T1010Z.{nix,log}`); restic's lock code read at tag `v0.20.0`. The runtime tests were not re-run; their runs on the remedies are `logs/cam127-fix-final-*-20261127-04*.log`.

### Findings of the second run

- [x] **FAIL 5, switching to R2 leaves the backup's textfile behind, and two alerts fire on it** (`specs/graph-store/spec.md:37`, requirement `One setting switches the storage location`: what exists only for one location, "the failure notices and alerts about it included, SHALL follow that setting"; scenario `the setting is the only change` `:43`; the runbook, `omnigraph.md:260-261`, "nothing else needs editing … `OmnigraphBackupStale` no longer expects magnetite").
  With `"r2"` the backup's units are gone, but nothing removes `/run/node-exporter-textfile/omnigraph-backup.prom` (`modules/nixos/omnigraph-backup.nix:80`): `modules/nixos/node-exporter-textfile.nix` only creates the directory, and `/run` is emptied only by a reboot.
  Failing scenario: magnetite is deployed with `stores.magnetite = "r2"` and nothing else, without a reboot. node_exporter keeps exporting the last stamp and its file's mtime; `omnigraph-backup-metric` no longer rewrites the file, so `HostProbeStale` (`time() - node_textfile_mtime_seconds > 300`, for 10 m, `rules.nix:379-385`) fires for `file="/run/node-exporter-textfile/omnigraph-backup.prom"` about 15 minutes after the switch, and `OmnigraphBackupStale`, whose expression reads the series whatever its presence selector expects, fires about 36 h after the last local backup. Both persist until someone deletes the file or the host reboots.
  The evaluation does follow the setting (below), and `checks.x86_64-linux.omnigraph-retired-roots` cannot see a file left on a host.

- [x] **FAIL 6, a `cluster status` answer that is not a JSON object ends the recovery unannounced, with exit 5** (`specs/graph-store-interface/spec.md:145`, "otherwise it SHALL leave `lock.json` unchanged, print the reason and the manual command, announce them …, and exit 1"; `:221`, `A refusal is announced`, "Every refusal … SHALL post one message").
  `reported=$(jq -r '.lock_id // "none"' <<<"$status")` (`modules/lib/omnigraph-lock-recovery.nix:253`) runs under `errexit` outside any guard, so when `omnigraph cluster status --json` exits 0 with output `jq` cannot index (not JSON, or an array), the program exits with `jq`'s status before it refuses.
  Failing scenario, run over the stub: a held serve lock and a `cluster status` printing `not json` (or `[1]`) give exit 5, stderr `jq: parse error: Invalid numeric literal at line 1, column 4` (or `Cannot index array with string "lock_id"`), no `left … in place` line, no manual step and no post; `lock.json` is kept (`logs/cam127-reverify-recovery-stubs-20261127T1010Z.log`). The start fails and `FAILED omnigraph-server.service` still posts, so the server does not come up silently, but the reason and the manual step are not delivered. The rehearsal has no such row. The path predates the remedies; the first run missed it.

### The first run's failures, against `ddec126c`

| First-run finding | Remedy | Closed? |
|---|---|---|
| 1, the way back did not evaluate | `stores.magnetite` (`modules/lib/omnigraph-cluster-roots.nix:102-104`) sets magnetite's option (`modules/machines/nixos/magnetite/default.nix`) and the backup (`enable = omnigraphRootStore == "local"`); `observabilityHostsFor` drops `omnigraphBackup.localRootUnits` from the row on `"r2"` (`modules/lib/observability-hosts.nix:56`); the check evaluates both stores | closed for evaluation; FAIL 5 is what the switch still leaves on the host |
| 2, an interrupted prune or check stopped every later backup | `restic unlock` as the first `ExecStart` (`omnigraph-backup.nix:198`, `postgresql-backup.nix:300`; evaluated: `unlock`, `backup`, `unlock`, `forget --prune …`, `check …` on both jobs) | closed |
| 3, the notice did not name the writer | `post` and `refuse` (`omnigraph-lock-recovery.nix:112-127`) post the reason and manual step, titled `omnigraph lock not recovered on <host>` | closed for every path through `refuse` and the unconfirmed unlock; FAIL 6 is a path around it |
| 4, the vocabulary requirement was an old copy | the delta now carries `main`'s requirement | closed (re-diffed at 10:10Z, below) |

### Trying to break each remedy

**(a) Unlock first.** At restic `v0.20.0`, `stale()` (`internal/repository/lock_file.go:249-277`) is true when the lock's time is more than `staleLockTimeout` (30 min, `:244`) old, or when the lock's hostname is this host's and `processExists` fails; `processExists` (`lock_file_unix.go`) sends SIGHUP to the pid, which every restic ignores; a running restic rewrites its lock every 5 min (`lock.go:34`). `RemoveStaleLocks` skips a lock it cannot load (`lock.go`), and `checkForOtherLocks` refuses an append lock beside any exclusive one (`lock_file.go:186`).
- The two jobs never share a repository: `…/sciexp-omnigraph-backup/magnetite` and `…/sciexp-postgresql-backup/magnetite` (evaluated). Within one job systemd never runs two instances of the oneshot.
- A failing `unlock` stops the unit before `backup`: the `ExecStart` lines run in order and the first failure ends the job (failure notice, cleanup destroys `@restic`). An unreachable repository already fails the pre-start's `cat config`. What is new is that a transient error at `unlock` now costs the night's backup, where it used to come after it.
- `unlock` can remove the lock of a restic that is still running, against the runbook's "never" (`omnigraph.md:146`) and design D5's "cannot" (`design.md:95`); the spec's wording (`graph-store-interface/spec.md:273`) is accurate. Ways: a running restic whose lock has not been rewritten for 30 min (suspended, or cut off from R2 that long); a restic on another host whose clock is more than 30 min behind magnetite's; magnetite's clock stepped more than 30 min forward. The repository's other users are the operator's `restic-omnigraph` on magnetite and, off the host, the runbook's commands, which all take `--no-lock`. So it needs an operator running a locking restic (a `prune`, say) at 03:30 under one of those conditions. Recorded as a warning.
- A lock of this host younger than 30 minutes whose pid now belongs to another program is kept, and that program receives SIGHUP. This only matters for a manual run within 30 minutes of an interrupted one; the nightly run comes a day later. A lock R2 stored unreadable would be skipped by `unlock` and still refuse the backup; R2 writes objects whole, and restic ignores empty lock files.
- `restic-backups-postgresql` gets the same order and is covered by the same reading; it has no runtime case of its own (design.md, "Verification findings and remedies").

**(b) The refusal notice.** Over the stub (`logs/cam127-reverify-recovery-stubs-20261127T1010Z.log`): no lock, exit 0, nothing posted; an id mismatch with `ntfy-send` failing, exit 1, one post attempted, `the refusal notice was not posted`, lock kept; a direct `apply` writer's lock, exit 1, one post; `force-unlock` answering `{"unlocked": false}`, exit 1, one post carrying the manual `force-unlock` and not the command's output; writers naming the root as `…//root`, `…/./root/` and `file:///…/root`, exit 1, one post. The rehearsal at `ddec126c` passes with its mutants rejected. The added post for an unconfirmed unlock is now specified (`A refusal is announced`, `graph-store-interface/spec.md:221`) and behaves as specified.
- Every exit through `refuse` posts. Exits that bypass it: FAIL 6; `mktemp` or the `chown` of its directory failing; and, after a confirmed unlock, a failed counter write, which exits 1 with neither notice, though the lock is already gone and the next start serves (warning).
- The message carries no line of `lock.json` (it never reads the file into the message), so the interface's wording holds. It does carry the record's `lock_id`, `operation`, `pid` and `created_at` (validated shapes), which the behavioral wording "without the claim's own content" (`graph-store/spec.md:68`) contradicts if read literally (warning: name the fields the notice may carry).
- It also carries a process's whole command line in rows 2, 3 and 10 (`holder="pid $entry: ${args[*]}"`, `:201`), now on an ntfy topic as well as in the journal. omnigraph 0.16.0's `omnigraph`, `omnigraph cluster` and `omnigraph-server` take no secret as an argument (their `--help`), but row 2's "executable … cannot be read" names any process. So "never a token" holds only as far as no such process carries one in its arguments (warning).
- A post that fails or times out (30 s) changes neither the verdict nor exit 1. Each refused start in the restart loop posts once (up to `StartLimitBurst` 5), as the runbook says.
- The normalisation does not resolve `..`: a writer naming the root as `/var/lib/omnigraph/clusters/x/../cookbooks-f17` is not counted (exit 0 over the stub). The amended scenario names only slashes, `.` segments and a trailing slash, so this is outside it (warning).

**(c) The way back.** Evaluated from a scratch copy of `ddec126c` with only `stores.magnetite = "r2"` changed (`logs/cam127-reverify-r2-only-setting-20261127T1010Z.json`):
- `vanixiets.omnigraphRootStore` is `"r2"` and `storageUri` is `s3://sciexp/omnigraph/clusters/cookbooks-f17`. The backup is off. None of the three local-root units is defined, none is in magnetite's `services.observability-notify.units`, in `flake.lib.observabilityHosts.magnetite`, or in the envelope's `envelopeBudget.notifiedUnits.magnetite`. `SystemdUnitFailed`'s exclusion names none of them. `OmnigraphBackupStale`'s presence expects no host, while `OmnigraphNotServing`'s still expects magnetite. The only omnigraph timer left is `omnigraph-probe`. `system.build.toplevel` evaluates (`/nix/store/d7k2jnxd…-nixos-system-magnetite-…drv`).
- Every reader of the host table reads `flake.lib.observabilityHosts`, which follows `stores`: the agent role's notified units (`otel-collector/flake-module.nix:1556`), the envelope (`:1724`), the fleet-alert rules (`fleet-alert.nix:618`, `rules.nix:75`), `node-exporter-textfile.nix:21`, and the checks.
- The check's other-store evaluation overrides only `vanixiets.omnigraphRootStore` and `services.observability-notify.units` (`omnigraph-retired-roots.nix:50`). On that evaluation magnetite's envelope and fleet-alert rules still read the committed table, and none of magnetite's assertions but the notified-unit `ExecStart` rule is read. The requirement `A check reads magnetite on both stores` says exactly this, and design.md's new limit points to the one toplevel evaluation for the rest. The check cannot see a value read from the table elsewhere, an assertion, or anything on the host (FAIL 5).
- The Perses view has no per-store panel. Its backup-age panel keeps showing the left-over stamp's age until the file goes. The runbook's section says "that one value" and is wrong only in FAIL 5's respect.
- The reverse direction, `"r2"` to `"local"`: for magnetite now, the dataset is still mounted and the `omnigraph-backup-r2` and `omnigraph-backup-restic` vars are committed, so the one value suffices. For a host that never served locally, two things come first, and nothing at evaluation says either is missing: the hand-made dataset (disko declares it only for a reinstall; without it, the `/var/lib/omnigraph` mount fails and with it every unit carrying `RequiresMountsFor`) and the two generators' vars (`clan machines update` would prompt for the R2 keys). `stores` names only magnetite today (warning).

**(d) The vocabulary delta.** Re-diffed at 10:10Z against `main` at `30223609` (`git ls-remote origin main` gives the same commit). The delta's `Grounded vocabulary for behavioral requirements` differs from `main`'s only by the context `cloud session` on `disk`'s existing row, the 24 added rows, and the count scenario. That scenario now reads twenty-seven terms, with `probe`, `release`, `credential`, `evaluator` and `writer` carrying three; counting the delta's rows gives the same 27 terms and the same five. It removes nothing of `main`'s. A231 to A242 remain free: `main` holds 113 numbered assumptions, the highest A332, none in A231–A242, and no other open change adds one.

### The amendment's requirements, against code and witness

| Requirement (new or split) | Result |
|---|---|
| `graph-store`: One setting switches the storage location | FAIL (FAIL 5); the evaluation part holds |
| `graph-store`: An interrupted night does not stop later graph backups | PASS by code and `omnigraph-local-root`'s new subtest (a `prune` killed holding its exclusive lock; the next run backs up and leaves no lock, `logs/cam127-fix-final-omnigraph-local-root-20261127-044714.log`); not yet on the host |
| `graph-store`: The graph store refuses … (added sentence: the notice carries the reason and manual step) | PASS for every refusal through `refuse`; FAIL 6 for the unguarded path; warning on "without the claim's own content" |
| `graph-store-interface`: One value switches the store, and the local-root units follow it | PASS: both scenarios, evaluated |
| `graph-store-interface`: A check reads magnetite on both stores | PASS: the check passes at `ddec126c`; its red run over the old row is `logs/cam127-fix-wayback-red-20261127-043236.log` |
| `graph-store-interface`: A refusal is announced | FAIL (FAIL 6); every other refusal, the unconfirmed unlock, the nothing-to-do path and the failed post behave as written |
| `graph-store-interface`: The backup job removes stale repository locks before it backs up | PASS: evaluated order on both jobs; the scenario held by the runtime test |
| `graph-store-interface`: A rehearsal holds the recovery's verdicts (split: `the packaged record`) | PASS: the check passes, rows for the spelled roots and the failing post included |
| `graph-store-interface`: The server's start clears a stale serve lock (amended `exit 1`, the normalised scan) | PASS except FAIL 6 |
| `world-assumptions`: Grounded vocabulary (rebased) | PASS |

Every other requirement keeps its first-run result (§4).

### Task 1.6

Recorded from the orchestrator as an observation made through a signed-in Perses session, not seen by this verifier: the view at https://obs.scientistexperience.net/projects/fleet/dashboards/omnigraph rendered on 2026-11-26 about 22:15Z (first layout; all 44 queries answered 200; every panel had data) and on 2026-11-27 about 03:55Z after `083caaa5` and `3d1f2ff2`: stat tiles "serving" and "reading"; "Graphs by state" 10 served and 10 ready; "Start to ready" stepping from about 3 minutes on R2 to about 2 s; entities per graph 457, 48, 169, 341, 449, 817, 295, 313, 349, 667; the table showing manifest 2 and format 17 for all ten; dataset quota used about 0.12%; used 26 MiB against 20 GiB; local snapshots; backup age; lock recoveries 0; server memory.
That meets 1.6's remaining clause, "the dashboard shows magnetite"; 1.6 is ticked. The lock-recovery tile has not been looked at since the counter became 1 at the reset (stored series 1 since 05:23Z).

### What a deploy of the remedies changes

Not deployed. On magnetite with `"local"`, the row, the backup and the alert rules evaluate as today; the unit files that change are `omnigraph-server.service` (the recovery program's new store path), `restic-backups-omnigraph.service` and `restic-backups-postgresql.service` (`unlock` first) (`logs/cam127-fix-magnetite-unit-diff-20261127-045108.log`).
[INFERENCE] the switch restarts `omnigraph-server` (a clean stop, a start of a few seconds with no lock to judge); the restic units carry `X-RestartIfChanged=false` and are only replaced.
To look at after it:
- the first nightly runs: `restic-backups-postgresql` at about 02:30Z and `restic-backups-omnigraph` at about 03:30Z, whose journals should show `unlock` before `backup`, then success and an advanced stamp;
- a refusal has never happened on the host, so the first refusal notice, its title and body on `fleet-alerts`, is unobserved outside the VM and the rehearsal;
- the lock-recovery tile showing 1.

---

## 1. Structural Validation (`openspec validate --all --json`)

- [ ] All items report `"valid": true`

```text
totals: 85 items, 82 passed, 3 failed
openspec validate serve-omnigraph-from-local-disk --strict: valid
```

None of the three failures is this change: `compose-hosts-from-cohesive-aspects`, `stand-up-gitea-mq-on-magnetite` and `stand-up-nixbot-on-magnetite`.
Second run, at 10:12Z: 84 items, 81 passed, the same three failing; `openspec validate serve-omnigraph-from-local-disk --strict` is valid.

---

## 2. Task Completion (`tasks.md`)

- [x] All `- [ ]` have been changed to `- [x]` (second run)

First run: 24 of 26; 1.6 and 5.4 stayed open. Second run: 1.6 is ticked on the observation in §0, and 5.4 was closed by the amendment's 6.3, which also added 6.1 to 6.4, all ticked; 30 of 30.

| Task | Evidence checked | Missing |
|---|---|---|
| 1.6 probe deploy | `DeployMagnetite-probe.md` (generation 291): `omnigraph.prom` had ready 1 and 10/10/0/0; `obs-query` returned `vanixiets_omnigraph_ready{host_name="magnetite"}` 1; ntfy from 05:23:53 to 05:42:59Z held 19 heartbeats and nothing else; fleet-alert's state held argentum's two pending `HostProbeStale` (a sleeping Mac) and the standing `R2CostProjected` | first run: the dashboard as rendered; second run: supplied by the observation in §0 |
| 2.8 static user deploy | `DeployMagnetite-latest.md` (generation 292): no recovery `ExecStartPre`, `User=omnigraph`, ready 1 with 10 graphs, the journal line `Found pre-existing private StateDirectory= directory /var/lib/private/omnigraph, migrating to /var/lib/omnigraph.` at 07:44:21Z, a plain `/var/lib/omnigraph` owned `65534:65534` and no `/var/lib/private/omnigraph`; the server's one restart is the switch's; from 07:43:06 to 07:58:22Z nothing but 15 heartbeats was posted; stored ready was 0 from 07:45:00 to 07:47:45, under the rule's 5 minutes | the last 4 minutes of the 15-minute window the deploy brief set |
| 3.3 backup token and vars | `vars/per-machine/magnetite/omnigraph-backup-r2/env/secret` and `omnigraph-backup-restic/password/secret` exist; with that token magnetite lists `sciexp-omnigraph-backup` (200) and is refused `sciexp` and `sciexp-postgresql-backup` (403) | the token's scope as the dashboard shows it |
| 5.1 switch | see "The switch" below | the stored query ran from magnetite, not pyrite |
| 5.2 storage | see "Storage and snapshots" below | none |
| 5.4 way back | see finding 1 and "The way back" below | first run: the configuration did not evaluate; second run: evaluates (§0), FAIL 5 aside |
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

### Findings (first run, 2026-11-27 09:20 UTC; see §0 for what closed each)

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

First run (09:20): four findings in §4. Second run (10:15): the remedies close all four for what they address (§0), and two new findings fail.
FAIL 5: a switch to R2 by the one setting leaves the backup's textfile on the host, so `HostProbeStale` and later `OmnigraphBackupStale` fire.
FAIL 6: a `cluster status` answer the program cannot index ends it with exit 5, no reason and no notice.
Warnings: `unlock`'s "never removes a running restic's lock" holds only while clocks agree within 30 minutes and every running restic keeps refreshing; the notice carries command lines and the record's fields; `..` is not normalised; a failed counter write after an unlock posts nothing; a host's first switch to `"local"` needs the dataset and the vars first, and nothing says which is missing.

**Next step**:

Correct the code, runbook or spec for FAIL 5 and FAIL 6, then re-run verify; CAM-127 stays In Progress (`review_round: 1`).
