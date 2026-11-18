---
linear_story_id: CAM-113
linear_story_identifier: CAM-113
linear_story_title: "Bound the fleet's Nix garbage collection"
linear_story_url: https://linear.app/cameronraysmith/issue/CAM-113/bound-the-fleets-nix-garbage-collection
linear_story_state: In Progress
linear_team: CAM
linear_project: fleet-observability
last_synced_state: In Progress
last_synced_at: "2026-11-18T21:19:14Z"
review_round: 0
max_review_rounds: 3
attempt_log:
  - { at: "2026-11-18T20:39:57Z", transition: "Backlog->Todo", outcome: "posted", note: "Issue CAM-113 created in Todo in project aeed302bea3b (Fleet observability) with description seeded from proposal.md; state and project confirmed by read-only view" }
  - { at: "2026-11-18T21:19:14Z", transition: "Todo->In Progress", outcome: "posted", note: "Operator approved the Gate 1 table (pre-apply alignment sub-gate) and implementation on 2026-11-18; state set to In Progress at the first checked task and confirmed by read-only view" }
---

## Why

On 2026-11-18 rosegold's store volume was 99% full and a deploy's build waited forever for the store lock, which 119 idle daemon connections held, until the operator restarted the daemon and deleted week-old generations by hand.
harmonia-gc, the fleet's only scheduled collector, waits on the same lock with no limit, so a stuck run also stops every later day's run; on darwin its output is discarded, users' generations are never expired, and the laptops that fill up report nothing.
This change bounds every collection, keeps what it did readable, gives the laptops back their headroom, and makes a full disk or a stuck collection reach a person.

## What Changes

Decisions tagged `D<n>` are developed in `design.md`; the operator approved the scope of D1 to D8 and D11 on 2026-11-18, and D9 and D10 are recorded as kept unchanged.

**A bounded, readable collection (P1)**
- From: harmonia-gc waits for the store lock with no limit and, on darwin, its output is thrown away.
- To: every run ends within 2 hours (NixOS `TimeoutStartSec`; darwin `timeout 2h` around the upstream argument list), and darwin writes its output and errors to `/var/log/harmonia-gc.log` (D1, D2).
- The wrong "runs daily to 15% free" comment in `modules/darwin/nix-settings.nix` is corrected (D3).
- Impact: non-breaking; a run that hits the bound exits non-zero, which the existing failure alerts already report.

**Rollback depth on darwin (P2)**
- From: 10 days of system generations on every host.
- To: 7 days on darwin hosts; NixOS stays at 10 (D4).
- Impact: shortens how far back a laptop can roll back, approved explicitly by the operator.

**Users' generations expire (P3)**
- From: home-manager and `nix profile` generations are kept forever.
- To: home-manager expires each person's generations older than 14 days, removing links only, so harmonia-gc stays the only collector (D5).

**Laptops report, and a stuck collection is reported (P4)**
- rosegold, argentum and blackphos join the observability host table with collection off, and each is turned on with a watched deploy; blackphos has no machine, so its entry stays off until a machine takes the name (D6).
- A new alert fires when a collection is still running past its expected duration (D7).

**A warm store on magnetite (P5)**
- From: magnetite deletes every unrooted output daily and vacuums the store database afterwards.
- To: magnetite stops collecting once 40% of its store's filesystem is free and skips the vacuum (D8).

**Kept unchanged, recorded (P6)**
- darwin's 5 GiB / 10 GiB `min-free`/`max-free` backstop stays (D9).
- Store optimise stays off on darwin while NixOS/nix#14599 is open (D10).

**Regulators**
- A fleet obligation asserted on every existing `nixos-<host>` and `darwin-<host>` check fails when a host's harmonia-gc unit lacks the 2-hour bound, or its launchd job lacks the bound or either log path; `checks.x86_64-linux.harmonia-gc-obligations` runs the obligation's judge over literal fixtures with one mutant per failure (D11).

## Capabilities

### New Capabilities
- `store-garbage-collection` (stratum: `behavioral`): every host's scheduled store cleanup ends within a bound, leaves a readable record on darwin, keeps the rollback window per platform, is the only thing that removes software from the store, keeps magnetite's store warm, and is reported to a person when it runs too long; each person's generations expire after 14 days.
- `store-garbage-collection-interface` (stratum: `interface`): the harmonia-gc systemd unit's `TimeoutStartSec`, the launchd job's `ProgramArguments` wrapper and log paths, `deleteOlderThan` per platform, magnetite's `ensureFree` and `noVacuum`, home-manager's `autoExpire` settings, the overrun alert rule, and the obligation and fixture check that pin them.
  Trust boundary: this machine declares the unit, job and settings and judges the evaluated configuration; it does not guarantee that harmonia-gc, launchd, systemd or `timeout` honour them at run time, that the lock holder releases the lock, or that a bounded run frees enough space.

### Modified Capabilities
- `host-metrics-collection` (stratum: `behavioral`): adds `Each laptop that builds for the fleet reports its store disk` (rosegold and argentum, once each is turned on) and `blackphos is declared an agent host with its collection off until a machine takes its name`.
- `world-assumptions` (stratum: `world`): A148 to A152 record that Nix's store lock is waited on without a limit, that launchd has no run time limit, that stopping a collection leaves the store consistent, that a collector running as root does not see a person's own generations, and how a quota-bounded ZFS dataset reports its size; `Grounded vocabulary for behavioral requirements` gains `software store`, `store cleanup`, `store lock`, `generation`, `rollback window`, `personal environment` and `free space`.

## Impact

- Code: `modules/system/harmonia-gc.nix`, `modules/darwin/nix-settings.nix`, `modules/home/tools/nix.nix`, `modules/lib/observability-hosts.nix`, `modules/nixos/fleet-alert/rules.nix` and its check `modules/checks/fleet-alert.nix`, `modules/machines/nixos/magnetite/default.nix`, `modules/checks/machines.nix`, and a new `modules/checks/harmonia-gc-obligations.nix`.
- Hosts: every NixOS and darwin host on its next deploy; rosegold and argentum each get a watched deploy turning collection on.
- Rollback depth on darwin shrinks to 7 days; magnetite's store keeps more cached outputs and uses more disk between runs.
- No new flake input; harmonia stays at `8d717e07`.
