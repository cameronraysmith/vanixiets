---
linear_story_id: CAM-127
linear_story_identifier: CAM-127
linear_story_title: "Serve OmniGraph from local disk on magnetite"
linear_story_url: https://linear.app/cameronraysmith/issue/CAM-127/serve-omnigraph-from-local-disk-on-magnetite
linear_story_state: Done
linear_team: CAM
last_synced_state: Done
last_synced_at: "2026-11-27T15:54:08Z"
review_round: 3
max_review_rounds: 3
attempt_log:
  - { at: "2026-11-26T04:04:41Z", transition: "Backlog->Todo", outcome: "posted", note: "Issue CAM-127 created in Todo on team CAM with no project, description seeded from proposal.md; state confirmed by read-only view" }
  - { at: "2026-11-26T04:59:43Z", transition: "Todo->In Progress", outcome: "posted", note: "First tasks.md checkbox ticked; state set to In Progress with a comment and confirmed by read-only view" }
  - { at: "2026-11-27T15:42:31Z", transition: "In Progress->In Review", outcome: "posted", note: "verify.md Overall Decision PASS WITH WARNINGS after the fourth check; state set to In Review with a comment and confirmed by read-only view" }
  - { at: "2026-11-27", transition: "In Review gates", outcome: "posted", note: "Code review accepted on the review of 7d02f0a5 and the four verification checks; documentation accepted as it is (verify.md, In Review gates); review_round stays 3" }
  - { at: "2026-11-27T15:54:08Z", transition: "archive->mirror", outcome: "dropped", note: "no linear_project bound; spec mirror skipped" }
  - { at: "2026-11-27T15:54:08Z", transition: "In Review->Done", outcome: "posted", note: "Archived after syncing graph-store, graph-store-interface and world-assumptions; state confirmed Done by read-only view, closing comment posted" }
---

## Why

magnetite serves its OmniGraph graphs from an R2 bucket in eastern North America while magnetite runs in Germany. Every storage request crosses the Atlantic: a server start takes about 4 min 50 s to open ten small graphs, and creating the root took about 26 min. OmniGraph allows one writer and no read replicas, so shared object storage buys nothing, and Lance ranks local NVMe fastest. Nothing watches the server beyond its start job today. This change moves the root to a ZFS dataset on magnetite's own disk, recovers by itself from the stale lock a crash leaves on a local root when that is safe, backs the root up off the host every night, and reports a server that is not serving or a backup that is overdue.

## What Changes

Decisions tagged `D<n>` are developed in `design.md`; the operator settled the storage, recovery, backup, monitoring, test and rollout choices on 2026-11-26 (`brainstorm.md`).

**Monitoring of the running server (lands first, on today's R2 root)**
- A minutely probe records readiness, graph counts by state, start-to-ready seconds and, through a new read-only `monitor` actor, per-graph entity counts, manifest version and storage format (D6, D7).
- Rule `OmnigraphNotServing` warns when the server is not ready, or a graph is blocked, for 5 minutes (D8).
- A Perses view `dashboard-omnigraph.json` and operations docs (D9).

**Graph data on the host's disk**
- From: `s3://sciexp/omnigraph/clusters/cookbooks-f17`, 4 min 50 s per start.
- To: `/var/lib/omnigraph/clusters/cookbooks-f17` on dataset `zroot/root/omnigraph` (quota 20 GiB, auto-snapshots on) mounted at `/var/lib/omnigraph`, the omnigraph units' state directory, created and seeded fresh by the existing bootstrap (D1, D2).
- Every omnigraph unit runs as the static user `omnigraph` instead of a `DynamicUser`, on either store, so it owns every file on the dataset; on a local root the `omnigraph-cluster` wrapper and the lock recovery run `omnigraph` as that user too (D13).
- One setting, `flake.lib.omnigraphClusterRoots.stores.magnetite`, selects local disk or R2 for the same root name, and magnetite's internal option `vanixiets.omnigraphRootStore`, its backup and the local-root units it notifies all follow it; everything R2-specific stays, and switching back serves the R2 root as it was left (D3). On every NixOS host, activation, at boot and on `switch-to-configuration switch` and `test`, removes each textfile in node_exporter's directory that no declared writer writes, so the backup's stamp goes with the switch, or with the reboot after a `boot` switch, rather than firing alerts on a file left in `/run` (D3).

**Stale-lock recovery on a local root**
- The server's own start clears a crashed server's lock only when no omnigraph process has the root open, the lock is a `serve` lock and its pid is dead or it predates the boot, by its exact id; each recovery is counted and posts an info notice; every other end of the recovery, an unreadable answer or an unforeseen failure included, refuses, posts its reason and manual step without any process's arguments, and the start fails visibly (D4).
- `omnigraph optimize`, which leaves its lock behind on a local root, cannot be enabled there (D14).

**Nightly off-host backup**
- An atomic ZFS snapshot, then restic to a new R2 bucket `sciexp-omnigraph-backup`, following the PostgreSQL backup, with stale repository locks removed before each backup; rule `OmnigraphBackupStale` at 36 h; a runbook for restore, the unlock a restored root needs, and switching back to R2 (D5, D8).

**Proven before the switch**
- `vmTests.x86_64-linux.omnigraph-local-root` (medium, ZFS in the VM, run on pyrite): ownership by the static user, crash and recovery, refusal while a direct writer holds the root, backup and restore to identical counts and answers, a reboot, probe series present (D10).
- The probe reports a refused or failed per-graph read with a journal line and the gauge `vanixiets_omnigraph_graph_reads_ok` (D6).

**Not now, recorded**
- No trace export, no JSON log receiver, no scheduled `omnigraph cleanup` (D11).
- The collector's unit name and failure notice for `omnigraph-server` land separately.

## Capabilities

### New Capabilities
- `graph-store` (stratum: `behavioral`): the fleet's graph store keeps its graph data on the disk of the host that serves it or in a bucket, chosen per host; it recovers by itself from a stale writer claim only when that is safe and otherwise fails visibly; its graph data is copied off the host every night from an instant image and can be restored to identical answers; and the operator is told when it is not serving or its backups are overdue.
- `graph-store-interface` (stratum: `interface`): the root-store setting and URI function, the dataset and its oneshots, the recovery program in the server's start, the restic job and its snapshot step, the probe and its series, the `monitor` actor and its token, the two rules, the Perses view, the bucket resource, the vars generators, the rehearsal check and the runtime test that pin them.
  Trust boundary: this machine declares the units, programs, rules and resources and judges them in evaluation, in a build-sandbox rehearsal and inside a test VM. It does not guarantee that OmniGraph's lock record means what A232 says, that ZFS snapshots are instant images, that R2 keeps what restic wrote, that the operator keeps the identity that decrypts the vars, or that a restored root opens under a later OmniGraph release. The readiness and staleness alerts are the runtime evidence on the real host.

### Modified Capabilities
- `world-assumptions` (stratum: `world`): A231 to A242 record OmniGraph's single writer, its local lock record and force-unlock, atomic commits across a kill, the unsafety of copying a live root, ZFS snapshots as instant images on the same disk, the sciexp bucket's fixed location, Hetzner Object Storage's undocumented conditional writes, OmniGraph's telemetry surface, its exporter's trust roots, `cleanup` needing the server stopped, systemd's handling of a state directory, and `optimize` leaving its lock on a local root. `Grounded vocabulary for behavioral requirements` gains `graph store`, `graph`, `example graph`, `seed`, `graph data`, `graph data name`, `storage format`, `entity count`, `stored query`, a third sense of `writer`, `direct writer`, `writer claim`, `stale writer claim`, `crash`, `boot`, `serving`, `blocked graph`, `storage location`, `bucket`, a second sense of `disk` (the existing row becomes its `cloud session` sense), `local snapshot`, `graph backup`, `runbook` and `recovery notice`.

## Impact

- Code:
  - `modules/nixos/omnigraph.nix`, `modules/lib/omnigraph-cluster-roots.nix`;
  - new `modules/lib/omnigraph-lock-recovery.nix`, `modules/nixos/omnigraph-probe.nix`, `modules/nixos/omnigraph-backup.nix`;
  - `modules/machines/nixos/magnetite/{default,disko}.nix` and `magnetite/omnigraph/*.policy.yaml`;
  - `modules/nixos/fleet-alert/rules.nix`, `modules/checks/fleet-alert.nix` and its fixtures;
  - `modules/clan/services/otel-collector/schema.nix` (`nodeExporterKeep`), `modules/lib/observability-hosts.nix`;
  - `modules/nixos/perses/resources/dashboard-omnigraph.json`, `modules/vm-tests/perses-greptimedb.nix`;
  - `modules/terranix/cloudflare.nix`;
  - new `modules/checks/omnigraph-lock-recovery-rehearsal.nix`, new `modules/vm-tests/omnigraph-local-root.nix`; `modules/checks/omnigraph-cluster-actor-policy.nix`;
  - `modules/nixos/node-exporter-textfile.nix`;
  - docs under `packages/docs/src/content/docs/development/operations/`.
- Hosts: the omnigraph change touches magnetite only; pyrite and the Macs reach OmniGraph at the same URL and are unaffected. The textfile cleanup reaches every NixOS host and, read on magnetite, cinnabar and pyrite on 2026-11-27, removes no file on any of them.
- Operator by hand: apply the bucket with terranix after an explicit yes, mint the bucket's R2 token, generate the vars; directly before the switch's deploy, remove the empty state directory and its symlink and create the dataset at `/var/lib/omnigraph`.
- Spending: a few hundred MB of R2 storage for backups; R2 requests for the graph data stop while the host serves locally.
- No new flake input.
