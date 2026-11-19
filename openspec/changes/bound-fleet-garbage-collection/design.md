## Context

harmonia-gc (`modules/system/harmonia-gc.nix`, harmonia `8d717e07`) replaces `nix.gc` on every NixOS and darwin host.
It runs daily with `deleteOlderThan = "10d"`, `keepRecent = "1d"` and no `ensureFree`, so each run deletes all garbage.
Upstream declares it as a `Type=oneshot` systemd unit `harmonia-gc` with `ExecStart = escapeShellArgs gcCfg.argv` on NixOS (`nix/module.nix:238-255`), and as a launchd daemon `harmonia-gc` (label `org.nixos.harmonia-gc`) with `ProgramArguments = gcCfg.argv` and no output paths on darwin (`nix/darwin-module.nix:40-52`).
`services.harmonia-dev.gc.argv` is an internal, read-only option holding the full argument list (`nix/gc-options.nix:98-121`).

Its collector takes `/nix/var/nix/gc.lock` exclusively and blocks without a limit when another process holds it (`harmonia-store-gc/src/gc.rs:125-147`); Nix's auto-GC does the same (`gc.cc` L393-394 at 2.34.8, the repo runs 2.35).
The 2026-11-18 rosegold incident (`logs/rosegold-gc-deploy-20261118-152227.log`, `logs/clan-update-rosegold-20261118-150810.log`) showed a build's auto-GC blocking on that lock with 119 idle daemon children on a 99% full `/nix`.

Monitoring: `FilesystemFillingWarn` and `FilesystemFull` (`modules/nixos/fleet-alert/rules.nix:162-177`) cover hosts with `collect = true` in `modules/lib/observability-hosts.nix`, which today excludes rosegold, argentum and blackphos.
`org.nixos.harmonia-gc` is in the darwin probe's `launchdLabels` and `harmonia-gc.service` in `systemdUnits` (`modules/clan/services/otel-collector/schema.nix:23,118`), so their state is already gathered wherever collection is on; `LaunchdJobFailed` and `SystemdUnitFailed` report a non-zero exit but nothing reports a run that never ends.

Stakeholders: the operator (deploys, approves rollback depth), the laptops' users (janettesmith on rosegold, christophersmith on argentum), and magnetite's build service, whose cache hit rate depends on what the store keeps.

## Goals / Non-Goals

**Goals:**
- No scheduled collection runs longer than 2 hours on any host, and a darwin run leaves a readable record.
- darwin laptops keep 7 days of system generations; each person's home-manager generations expire after 14 days without a second collector.
- rosegold and argentum report their disks, and a collection running past its expected duration reaches a person.
- magnetite keeps a warm store and skips the post-collection vacuum.
- A regression in the bound or the darwin log paths fails a check before deploy, at no added evaluation cost.

**Non-Goals:**
- Fixing who holds the lock (the idle daemon children, or `nix-grpc-daemon`'s pool); that waits on open question 3.
- Changing darwin `min-free`/`max-free` or turning store optimise on for darwin (D9, D10).
- Changing NixOS rollback depth, the `gcroots/auto` reaper, niks3's R2 retention, or `nix profile` expiry outside home-manager.
- Upstreaming a lock timeout to harmonia or Nix.

## Decisions

### D1: Bound every harmonia-gc run to 2 hours
- **Choice**: NixOS `systemd.services.harmonia-gc.serviceConfig.TimeoutStartSec = "2h"`; darwin `launchd.daemons.harmonia-gc.serviceConfig.ProgramArguments = lib.mkForce ([ "${pkgs.coreutils}/bin/timeout" "2h" ] ++ config.services.harmonia-dev.gc.argv)`, both in `modules/system/harmonia-gc.nix`.
- **Rationale**: a oneshot unit's start timeout covers the whole run, and systemd kills it and marks the unit failed; launchd has no run limit, so the bound has to be in the argument list. Deriving the wrapped list from `argv` keeps every upstream option (P2's `deleteOlderThan`, P5's `ensureFree`, `noVacuum`) flowing through unchanged.
- **Boundary**: vendored-versus-first-party. Upstream owns `argv` and the unit; we override one `serviceConfig` key on each platform and never copy upstream's argument list, so a harmonia bump that changes `argv` still lands inside the wrapper.
- **Alternatives considered**: a lock timeout inside harmonia-gc (not offered at `8d717e07`; would need an upstream change); `RuntimeMaxSec` (applies to the service's runtime, equivalent here but less conventional for oneshot); a watchdog job that kills stuck runs (a second moving part to keep alive).

### D2: darwin output to `/var/log/harmonia-gc.log`
- **Choice**: `StandardOutPath` and `StandardErrorPath` both `/var/log/harmonia-gc.log`.
- **Rationale**: one file keeps lock waits and bytes freed in order; root owns `/var/log`, and the job runs as root.
- **Alternatives considered**: separate `.out`/`.err` files (interleaving lost); the unified log (`log show` does not capture a daemon's stdout).

### D3: Correct the `min-free` comment
- **Choice**: `modules/darwin/nix-settings.nix:59-60` says harmonia-gc runs daily and deletes all unrooted garbage older than its generation window, with no free-space target.
- **Rationale**: the comment states a guarantee nothing provides.

### D4: darwin keeps 7 days of generations
- **Choice**: the darwin branch sets `deleteOlderThan = "7d"`; NixOS keeps `"10d"`; `keepRecent = "1d"` everywhere.
- **Rationale**: the laptops have the smallest disks and fill from generations; 7d matches `ngc` and the operator's manual cleanup. Approved explicitly as a shorter rollback depth.
- **Alternatives considered**: 7d fleet-wide (servers have headroom and benefit from depth); per-laptop values (no evidence that the laptops differ).

### D5: home-manager generations expire after 14 days, expiry only
- **Choice**: in `modules/home/tools/nix.nix`, `services.home-manager.autoExpire = { enable = true; timestamp = "-14 days"; frequency = "daily"; store.cleanup = false; }`.
- **Rationale**: harmonia-gc runs as root and never sees `~/.local/state/nix/profiles`; expiry removes the links, and the next harmonia-gc run reclaims what they rooted. Leaving `store.cleanup` off keeps one collector per host, so no second process contends for the lock.
- **Boundary**: vendored-versus-first-party; the module is home-manager's, and its darwin support (a launchd agent) is verified at apply against the pinned home-manager.
- **Alternatives considered**: `store.cleanup = true` (a per-user collector on the same lock); extending harmonia-gc to user profiles (not supported upstream).

### D6: The laptops join the observability host table
- **Choice**: entries for rosegold, argentum and blackphos in `modules/lib/observability-hosts.nix` with `platform = "darwin"`, `notifiedUnits = [ "otel-envelope" ]`, `collect = false`; then rosegold and argentum each get `collect = true` in its own commit, deployed and watched one at a time. Their `smartDevices` follow stibnite's `disk0` pattern if the probe reads the internal disk there; this is confirmed per host at apply.
- **Rationale**: the README's joining procedure; collecting is what lets `FilesystemFillingWarn` and `FilesystemFull` fire for them.
- **blackphos**: the name is reserved with no machine (`modules/clan/inventory/services/tincr.nix:23`). Its entry can only be added with `collect = false`: no deploy can run, nothing can be watched, and nothing reports for it. P4 for blackphos is complete at the entry; enabling it is a step of whatever change gives the name a machine.
- **Alternatives considered**: adding blackphos only when a machine exists (the host table would then disagree with the inventory, which lists blackphos as a darwin machine).

### D7: Alert on a collection that runs past its expected duration
- **Choice**: a rule `GarbageCollectionOverrun` in `modules/nixos/fleet-alert/rules.nix`: `launchd_job_state{launchd_label="org.nixos.harmonia-gc", launchd_state="running"} == 1 or systemd_unit_state{systemd_unit_name="harmonia-gc.service", systemd_unit_active_state="activating"} == 1`, `for: 60m`, severity warning, with presence on the darwin and NixOS hosts as the existing launchd and systemd rules declare it. Its case in `modules/checks/fleet-alert.nix` fires once for a run held 70 minutes and not for one that ends at 50.
- **Rationale**: a stuck run is reported an hour before D1 kills it; the kill itself is reported by `LaunchdJobFailed` (exit 124) or `SystemdUnitFailed`. The expected duration is a placeholder until the darwin log (D2) gives real run times (open question 6).
- **Alternatives considered**: relying on the failure alerts alone (a person learns only after 2 hours, and only if the kill is recorded); a probe-side duration gauge (new signal and budget for one job).

### D8: magnetite keeps a warm store
- **Choice**: `services.harmonia-dev.gc.noVacuum = true` and `ensureFree = "40%"` in `modules/machines/nixos/magnetite/default.nix`.
- **Rationale**: upstream recommends `noVacuum` on busy builders; `ensureFree` stops the run once 40% of the store's filesystem is free, so recently built outputs survive between runs instead of being re-substituted.
- **Boundary**: source-versus-delivered; what "40%" means depends on the size the ZFS dataset reports under its 250G quota (A152), confirmed on the host at apply.
- **Alternatives considered**: an absolute size like `"100G"` (needs retuning if the quota changes).

### D9: darwin `min-free`/`max-free` stays 5 GiB / 10 GiB (unchanged)
- **Rationale**: `min-free = 0` turns the hang into an ENOSPC build failure, but at 99% full macOS loses swap headroom and freezes (argentum, 2026-10-07). The hang is a lock-holder problem; D1 and the headroom from D4 and D5 address it.

### D10: Store optimise stays off on darwin (unchanged)
- **Rationale**: relinking busts the syspolicyd cache (incident 2026-09-27), and NixOS/nix#14599 (scheduled optimise hard-linking non-identical files on aarch64-darwin) is open. `ngc` remains the manual path.

### D11: Regulators: a fleet obligation plus a fixture check
- **Choice**: `flake.lib.harmoniaGcObligations` in `modules/system/harmonia-gc.nix` exposes `bound` (the literal `"2h"`, shared by the module and the judge), `logPath`, a pure judge `problems { platform, service }` over the unit's `serviceConfig` (NixOS) or the job's `serviceConfig` plus `argv` (darwin), and `failures name hostConfig`. `modules/checks/machines.nix` asserts `failures` inside `withFleetObligations` on every `nixos-<host>` and `darwin-<host>` check. `modules/checks/harmonia-gc-obligations.nix` defines `checks.x86_64-linux.harmonia-gc-obligations`, which runs `problems` over literal fixtures: an accepted NixOS unit and darwin job, and one mutant each for a missing `TimeoutStartSec`, a different duration, a missing wrapper, a wrapper around a different argument list, a missing `StandardOutPath`, a missing `StandardErrorPath`, and a log path elsewhere, each with exactly one problem.
- **Rationale**: the facts are configuration values, so the lowest rung of the placement ladder is the machine checks that already evaluate every configuration; the obligation adds no attribute and no evaluation. The fixture check's key is a literal gated on `x86_64-linux`, so the key set stays static; each mutant runs only the case it must fail.
- **Alternatives considered**: a standalone check evaluating every host's configuration (re-pays each fixpoint; the mesh-hosts precedent cost 454 MB); module `assertions` in the harmonia-gc module (would pass by construction, since the same module sets the values; the obligation judges the final merged value, so a later `mkForce` elsewhere fails it).

## Risks / Trade-offs

- [Risk] A first run on a store never collected may need longer than 2 hours and be killed every day → Mitigation: Nix deletes path by path under the lock (A150), so each killed run still frees what it reached; the log (D2) and the overrun alert show it; the bound is one literal to raise.
- [Risk] `timeout` sends SIGTERM only; a harmonia-gc that ignores it keeps running → Mitigation: apply verifies the wrapped process exits on SIGTERM while waiting on the lock; if not, add `--kill-after`.
- [Risk] `/var/log/harmonia-gc.log` grows without rotation → Mitigation: read its size after the first week; add a `newsyslog.d` entry if a run writes per-path lines.
- [Risk] `ensureFree = "40%"` is computed against the pool rather than the quota → Mitigation: read `df` and `zfs get quota,available` for the store dataset before deploy (A152); switch to an absolute size if they disagree.
- [Risk] Turning collection on for a laptop adds an always-on agent on an 8 GiB host (argentum) → Mitigation: the watched deploy reads memory before and after, as stibnite's did.
- [Trade-off] darwin rollback depth drops from 10 to 7 days → accepted by the operator.
- [Trade-off] magnetite holds up to 60% of its store quota between runs → accepted for cache hits; min-free/max-free remain the backstop.
- [Trade-off] the 60-minute alert threshold is a guess → accepted until D2's log gives run times.

## Migration Plan

1. Land the obligation, the fixture check and the module changes (D1-D5, D8, D11) together; every machine check proves the bound before any deploy.
2. Deploy magnetite and cinnabar (NixOS bound, warm store); confirm `systemctl show harmonia-gc -p TimeoutStartUSec` and the next run's journal.
3. Deploy stibnite first among darwin hosts; read `launchctl print system/org.nixos.harmonia-gc` and `/var/log/harmonia-gc.log` after the next run.
4. Land the alert rule (D7) and the host-table entries with `collect = false` (D6); deploy magnetite (evaluator) and each darwin host so its closure carries the entry.
5. Turn collection on for rosegold, deploy, watch; then argentum. blackphos stays off.
6. Each deploy reads every alert posted since it started from the evaluator's log and records its cause.

Rollback: each step is one revertible commit; a host returns to the previous generation with `darwin-rebuild --rollback` or `nixos-rebuild --rollback`, and D4 leaves at least 7 days of generations to roll back to.

## Open Questions

1. What held rosegold's 229 GB, given daily collection of everything older than 10 days: rooted paths (system or user generations, `gcroots/auto`, home-manager) or non-Nix data on the shared APFS container?
2. Did rosegold's daily 03:15 run complete, fail or hang on the lock? Its output was discarded; `launchctl print system/org.nixos.harmonia-gc` on rosegold is the remaining evidence.
3. **Answered (observed 2026-11-18 15:55; `logs/rosegold-gc-deploy-20261118-152227.log`).** Who held `gc.lock`? nix-daemon worker processes serving a `darwin-rebuild switch` that `clan machines update` started at 15:11. Killing the local clan and ssh client did not end that rebuild on rosegold, which kept waiting on auto-GC while 111 workers held the lock. `launchctl kickstart -k system/org.nixos.nix-daemon` restarts only the parent daemon, and the workers survive it. Any collection behind them, harmonia-gc or `nix-collect-garbage`, therefore waits indefinitely, which is the case D1's 2-hour bound covers.
4. Does the weekly `gcroots/auto` reaper (30 days, regardless of target) unroot a person's current `nix profile` generation, and should user profile roots be treated differently?
5. Disk sizes for blackphos, stibnite and pyrite are not recorded in the repo.
6. What is a collection's normal duration per host, so D7's 60-minute threshold can be set from evidence?

## Findings during apply

- **F47:** temporary roots blocked collection on rosegold (observed during the 2026-11-18 incident).
- **F49:** `--delete-older-than` keeps the generation at the cutoff, so a host's rollback window (D4) can hold one generation older than the window.
- **F53:** never delete the generation a profile points at without first checking `/etc/static`. This applies to any manual cleanup, such as the one done on rosegold during the incident.
- **F58:** a `collect = false` host was in the collector role and received the shared `ntfy-alerter` token without being one of its recipients, so rosegold half-activated. Fixed by keeping `collect = false` hosts out of the role and its secrets, and by a module assertion (`flake.lib.sharedVarsObligations`) that fails any host deploying a shared secret it is not a recipient of.
- **F66:** a held GC lock blocks every build and realisation on the host, not just collection. On pyrite during the hold test, a new trivial `nix build` hung until it was interrupted at 180 s and `nix-store --realise` of an existing path timed out at 60 s, while `nix path-info` answered at once (`logs/cam113-hold-test-v3-20261118-184927.log`). This is the mechanism behind rosegold's stuck deploys. It raises the stakes of D1: until a stuck run is ended, the host can neither build nor deploy, so the 2-hour bound is the most a stuck run can cost a host, and the 60-minute overrun alert (D7) is how a person learns of it.

## Gate 1 modality verdicts

This table is the pre-apply spec-and-feature alignment record.
The repository has no BDD runner and no `.feature` file, so no row routes to a Gherkin scenario; each requirement is witnessed by a build gate (`nix eval`, `nix build`, the fleet obligation on the machine checks, the fixture check, the fleet-alert rule check) or a smoke observation on a deployed host recorded in `verify.md`.
The operator approved this table, and with it the pre-apply alignment sub-gate, on 2026-11-18.

| Requirement | Capability | Stratum | Modality | Witness |
|---|---|---|---|---|
| Every scheduled store cleanup ends within two hours | `store-garbage-collection` | behavioral | build gate (obligation, fixture check) and smoke | tasks 1.1-1.3, 2.1-2.3, 5.4, 5.5, 6.1, 6.2, 6.4 |
| A darwin host keeps a readable record of each store cleanup | `store-garbage-collection` | behavioral | build gate (obligation, fixture check) and smoke | tasks 1.2, 1.3, 2.2, 5.5, 5.7, 6.1, 6.4 |
| Each host keeps its rollback window | `store-garbage-collection` | behavioral | build gate (`nix eval`) and smoke | tasks 3.1, 6.3; the scenario "a laptop rolls back" is accepted unobserved: 3.1's evaluated `7d` and `keepRecent` cover it, and a real rollback on a user's laptop is not worth the disruption |
| A person's own generations expire after fourteen days without a second store cleanup | `store-garbage-collection` | behavioral | build gate (`nix eval`, `nix build`) and smoke | tasks 3.2, 3.3, 5.7 |
| magnetite keeps a warm software store | `store-garbage-collection` | behavioral | build gate (`nix eval`) and smoke | tasks 4.1, 4.2, 5.4, 6.3 |
| A store cleanup that runs past its expected duration reaches a person | `store-garbage-collection` | behavioral | build gate (fleet-alert rule check) and smoke | tasks 5.2, 5.3, 6.1 |
| Each laptop that builds for the fleet reports its store disk | `host-metrics-collection` | behavioral | smoke (watched deploy) | tasks 5.8, 5.9 |
| blackphos is declared an agent host with its collection off until a machine takes its name | `host-metrics-collection` | behavioral | build gate (`nix eval`) | task 5.1 |
| Each `store-garbage-collection-interface` requirement | `store-garbage-collection-interface` | interface | build gate | tasks 1.1-1.3, 2.1, 2.2, 3.1, 3.3, 4.2, 5.3 |
| A148-A152 | `world-assumptions` | world | monitoring (violation scenarios) | A148 by 2.3 and 6.1; A149 by review of launchd.plist(5) at each macOS upgrade; A150 by 6.2; A151 by 3.2; A152 by 4.1 |
