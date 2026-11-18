<!--
Raw capture of the brainstorming for this change.
The exploration was the GcPolicy research report (2026-11-18) and the operator's approval of its recommendations the same day; this file records that decision chain as it happened.
-->

# Brainstorm: bound the fleet's garbage collection

## Background

On 2026-11-18 rosegold's `/nix` volume was 99% full: `/dev/disk3s7 229G 225G 3.8G` (`logs/rosegold-gc-deploy-20261118-152227.log`).
A deploy (`logs/clan-update-rosegold-20261118-150810.log`) copied its source, ran an auto-GC that took the lock and freed some space, then started `darwin-rebuild switch`, whose build asked for another auto-GC ("running auto-GC to free 6740205568 bytes"), printed "waiting for the big garbage collector lock..." and never got past it; the deploy failed with return code 255.
The host had 119 idle `nix-daemon` children.
The operator restarted `nix-daemon` to release them and, with explicit approval, deleted the system generations older than 7 days.
The day before, `logs/clan-update-rosegold-20261117-201425.log` shows four auto-GC runs during one deploy (5.4, 8.3 and 8.2 GB requested), so the host had been running at the `min-free` backstop for at least a day.

The research report (agent `GcPolicy`) established the fleet's garbage collection as it stands:

- harmonia-gc (`modules/system/harmonia-gc.nix`, `nix-community/harmonia@8d717e07`) is the only scheduled collector on every NixOS and darwin host: daily (darwin 03:15 launchd, NixOS 04:00 America/New_York with 5 min jitter), `deleteOlderThan = "10d"`, `keepRecent = "1d"`, no `ensureFree`, so every run deletes all garbage.
- It takes `/nix/var/nix/gc.lock` exclusively and, when the non-blocking attempt fails, logs "waiting for the big garbage collector lock..." and blocks with no timeout (`harmonia-store-gc/src/gc.rs:125-147`).
  A run that blocks keeps its launchd job or systemd unit busy, so the next day's run does not start either.
- Nix's own auto-GC (`min-free`/`max-free`) takes the same lock the same way, which is what the rosegold build waited on.
- darwin's harmonia-gc output is discarded: the upstream darwin module sets no `StandardOutPath`/`StandardErrorPath`.
- `modules/darwin/nix-settings.nix:59-60` says harmonia-gc "runs daily to 15% free"; nothing sets `ensureFree`, so that is wrong.
- harmonia-gc runs as root and prunes `/nix/var/nix/profiles` and root's own `~/.local/state/nix/profiles`; home-manager generations and `nix profile` generations under each user's `~/.local/state/nix/profiles` are never expired by anything.
- rosegold, argentum and blackphos send no metrics, so `FilesystemFillingWarn` (85%) and `FilesystemFull` (95%) cannot fire for the laptops that actually fill up.
  `LaunchdJobFailed` watches `org.nixos.harmonia-gc` only where metrics are collected (stibnite today), and a run that hangs never exits, so it would not fire anyway.
- magnetite: min-free 30 GiB / max-free 80 GiB; harmonia-gc wipes all unrooted outputs daily; upstream recommends `noVacuum` on busy builders because concurrent daemon readers stop the post-GC VACUUM's WAL from being cleaned up.

## Decision chain

**Q1. Should a scheduled collection be allowed to wait on the lock forever?**
No. A run that waits forever is indistinguishable from one that never ran, and it blocks the following days' runs.
Decision (operator, 2026-11-18): bound every harmonia-gc run to 2 hours.
NixOS: `systemd.services.harmonia-gc.serviceConfig.TimeoutStartSec = "2h"` (the unit is `Type=oneshot`, so the start timeout bounds the whole run).
darwin: launchd has no run timeout, so wrap the upstream argv: `ProgramArguments = mkForce ([ "${coreutils}/bin/timeout" "2h" ] ++ config.services.harmonia-dev.gc.argv)`; `argv` is read-only upstream but readable.
A timed-out run exits non-zero on both platforms, which the existing failure alerts already treat as a failure.

**Q2. Where does darwin's output go?**
Decision: `StandardOutPath` and `StandardErrorPath` both `/var/log/harmonia-gc.log`, so bytes freed and lock waits are readable after the fact; this also answers `fleet-emitter-inventory.md:438`.
Fix the "15% free" comment in the same change.

**Q3. How many days of rollback do the laptops keep?**
Decision (operator, explicit): darwin `deleteOlderThan = "7d"`; NixOS stays at 10d.
This shortens darwin rollback depth from 10 days to 7; the current generation always survives and `keepRecent = "1d"` stays.
7d matches what the operator did by hand on rosegold and what `ngc` already does.

**Q4. Who expires users' generations?**
Options: (a) a second collector per user; (b) home-manager's `services.home-manager.autoExpire` with `store.cleanup = true`; (c) the same with `store.cleanup = false`.
Decision: (c), 14 days, expiry only.
A per-user collector would contend for the same lock harmonia-gc and auto-GC take, which is the failure this change addresses; expiry only removes generation links, and the next harmonia-gc run reclaims what they held.

**Q5. How does a person learn that a laptop is filling or a collection is stuck?**
Decision: add rosegold, argentum and blackphos to `modules/lib/observability-hosts.nix` with `collect = false`, then enable each with a watched deploy, as the observability README prescribes for a joining host.
Add an alert for a harmonia-gc run that is still running past its expected duration, so a stuck run is reported before the 2-hour bound kills it, and the kill itself is reported as a failure.
blackphos is a reserved name with no machine (`modules/clan/inventory/services/tincr.nix:23`): its entry can be added, but it cannot be enabled or watched, so for blackphos P4 ends at the `collect = false` entry until a machine takes the name.

**Q6. Should magnetite keep a warm store?**
Decision: `noVacuum = true` and `ensureFree = "40%"` on magnetite: the run stops once 40% of the store's filesystem (roughly 100 GiB of the 250G quota) is free, rather than discarding every unrooted output daily.
min-free 30 GiB / max-free 80 GiB and `nix.optimise.automatic` stay.

**Q7. What stays as it is?** (recorded as decisions)
- darwin `min-free`/`max-free` 5/10 GiB stays.
  Dropping `min-free` to 0 would turn the hang into an ENOSPC failure, but at 99% full macOS loses swap headroom and freezes (argentum, 2026-10-07); the hang is a lock-holder problem, so the defence is the bound in Q1 plus headroom from Q3 and Q4.
- Store optimise stays off on darwin: the repo's syspolicyd reason still holds and NixOS/nix#14599 (scheduled optimise hard-linking non-identical files on aarch64-darwin) is still open.

**Q8. How is the bound kept from regressing?**
Per the checks-architecture placement ladder, the facts are configuration values, so the cheapest rung is an obligation asserted on the existing `nixos-<host>` and `darwin-<host>` machine checks (`modules/checks/machines.nix`), which already evaluate each configuration; the obligation adds no attribute and no evaluation.
Its judge is our own pure logic, so a fixture check on x86_64-linux runs it over literal service shapes with one mutant per failure mode.
Key set static: the new fixture check's name is a literal, gated on `system == "x86_64-linux"`.

## Trade-offs noted

- 2 hours is long for a laptop run and short for a first run on a store that has never been collected; the alert threshold below it (1 hour) is a guess until the darwin log gives real durations.
- A bounded run that is killed mid-collection leaves the store consistent (Nix deletes path by path under the lock), but frees less than a full run; the next day's run continues.
- `ensureFree = "40%"` depends on how ZFS reports the dataset's size under a quota; if statfs reports the pool rather than the quota, 40% means something else.

## Open questions carried from the research

1. What held rosegold's 229 GB, given that harmonia-gc deletes all garbage older than 10 days daily: rooted paths (system or user generations, `gcroots/auto`, home-manager) or non-Nix data on the shared APFS container?
2. Did rosegold's daily 03:15 run complete, fail or hang on the lock? Its output was discarded; only `launchctl print system/org.nixos.harmonia-gc` on the host can tell.
3. Who held `gc.lock`: the 119 nix-daemon children themselves or rosegold's `nix-grpc-daemon` builder pool? No `lsof /nix/var/nix/gc.lock` was captured.
4. The weekly `gcroots/auto` reaper deletes `auto` links older than 30 days whatever they point to; does that unroot a user's current `nix profile` generation, and should user profile roots be covered differently?
5. Disk sizes for blackphos, stibnite and pyrite are not recorded in the repo.
