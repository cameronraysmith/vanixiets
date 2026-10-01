---
title: magnetite host OOM from concurrent evaluations, 2026-09-27 and 2026-10-01
---

magnetite hit the global kernel OOM killer twice, at 2026-09-27 01:08 UTC and at 2026-10-01 15:14 UTC.
Both times nixbot's evaluation overlapped a second `nix-eval-jobs` evaluation started by a remote `just check-fast`, and together they exhausted RAM and zram at once.
The kernel then killed nix-daemon connection workers rather than an evaluator, which severed in-flight evaluations from the daemon and turned the overload into failed CI.
This note records the evidence, the root cause, the mitigations shipped with it, and what is deferred to a second phase that needs measurement first.

## Configuration at the time

magnetite has 30.6 GiB of RAM and a single zstd `zram0` sized at 150 % of RAM, 45.9 GiB, with `vm.swappiness = 100` (`modules/machines/nixos/magnetite/default.nix`).
nixbot evaluates with `evalWorkerCount = 8` and `evalMaxMemorySize = 4096`, under `MemoryHigh = "12G"` on `nixbot.service` and no `MemoryMax` (`modules/nixos/nixbot.nix`).
That sizing comes from `logs/magnetite-zram-headroom-experiment.md`, which measured one `8 x 4096` evaluation peaking at 33.68 GB of swap (§4, §6.2) and assumed it was the only large evaluation on the host.
The absence of `MemoryMax` comes from `logs/nixbot-memorymax-oom-victim.md`, which measured a parent `MemoryMax` killing the nixbot daemon in a replica (§4, §6.2).
magnetite imports the srvos server profile, which sets `OOMScoreAdjust = 250` on `nix-daemon.service`; nothing in this repository sets it.
systemd-oomd was running but monitored no cgroup, as `logs/zfs-zram-swap-doctrine.md` had already found (§Q6), and MGLRU `min_ttl_ms` was 0.

## Evidence

The second evaluation ran as `cameron` (uid 1001) with four workers plus a collector, the shape of `nix-fast-build --remote magnetite.zt --eval-workers 4`.
`nix-fast-build --remote` runs `nix-eval-jobs` on the remote host over ssh, taking `nix-eval-jobs` from the remote user's PATH or else from `nix shell nixpkgs#nix-eval-jobs`.

Memory held by each evaluation at the moment of the OOM, from the kernel's task dump:

| Time (UTC) | nixbot evaluation (uid 987) | second evaluation as `cameron` (uid 1001) | zram free |
|---|---|---|---|
| 2026-09-27 01:08 | 9 processes, 9.7 G resident + 22.9 G in zram | 5 processes, 5.5 G + 21.0 G | 0 |
| 2026-10-01 15:14 | 9 processes, 11.1 G + 29.5 G | 5 processes, 4.0 G + 15.0 G | 0 |

The nixbot evaluation alone is within the experiment's envelope.
Adding the second evaluation, which held 19-26 GB, reached both ceilings together: zram's logical capacity was full and physical RAM was full, with the compressed zram pool itself occupying roughly 10 GB of RAM.

The kernel's victims were the wrong processes.
On 2026-10-01 it killed five nix-daemon workers, each with a few MiB of anonymous memory and `oom_score_adj` 250.
On 2026-09-27 it killed a run of nix-daemon workers (adj 250) and processes from `cameron`'s session (adj 100-200, including `(sd-pam)`, `dbus-broker`, `ssh-agent` and an agent CLI) before it reached the `nix-eval-jobs` process 2718905, at adj 0 with 1.06 GB anonymous memory, roughly 47 kills in all.
Each daemon-worker kill freed almost nothing and broke the daemon connection of an evaluation, which surfaced as broken-pipe and connection-reset evaluation failures.

## Root cause

magnetite's memory design holds one large evaluation at a time, and nothing prevented a second one from starting.
Three further gaps turned that overlap into broken CI rather than a slowdown.

The evaluator's own memory governor is blind to swap.
nix-eval-jobs decides dispatch and worker restarts from resident memory only, and with `swappiness = 100` resident memory stays low while the true footprint moves into zram.
The experiment measured resident memory at about 35 % of the true footprint and recorded zero budget kills in every run (`logs/magnetite-zram-headroom-experiment.md` §5).
So neither evaluator throttled itself as the host ran out.

The zram pool is not charged to any cgroup.
The compressed pages belong to the zram driver, not to the cgroup of the process that was swapped out.
`MemoryHigh = "12G"` bounds nixbot's resident memory, but the RAM its overflow occupies inside zram, about 7.6 GiB at the experiment's peak and more under overlap, sits outside every cgroup limit on the host.

Victim selection favoured the daemon.
The kernel scores each process by its resident, swapped and page-table pages plus `oom_score_adj / 1000` of total RAM plus swap.
With 76.5 GiB of RAM plus swap, adj 250 adds about 19 GiB to every nix-daemon worker, which outranks an evaluator worker holding about 7 GB in total at adj 0.
With systemd-oomd watching nothing, that global killer was the only backstop.

## Mitigations in this change

A host-wide evaluation lock on magnetite and pyrite (`services.nixEvalLock`, `modules/nixos/nix-eval-lock.nix`).
The wrapper is the `nix-eval-jobs` on PATH for nixbot, buildbot and interactive and ssh users, so a remote `nix-fast-build --remote` resolves it too.
It takes an exclusive `flock` on `/run/nix-eval-lock/lock`; while the lock is busy it prints `nix-eval-jobs: waiting for the host evaluation lock held by <user> pid <pid> since <ISO time> (<command>); evaluations on this host run one at a time to avoid exhausting memory` to stderr every 30 seconds, naming the holder from `/run/nix-eval-lock/holder`.
Once it holds the lock it records itself as holder, raises its own `oom_score_adj` to 900 and execs the real `nix-eval-jobs`, keeping the lock open until the evaluation exits.
Evaluations on one host now queue instead of overlapping, and if memory still runs out the evaluator is the preferred victim.
nix-eval-jobs 2.35.3 and later requeues a worker killed by the kernel OOM killer and retries it alone, so killing an evaluator worker costs a retry, while killing a daemon worker fails the evaluation.

MGLRU thrash protection on both hosts: `/sys/kernel/mm/lru_gen/min_ttl_ms` is set to 1000.

OOM ordering.
sshd runs at `OOMScoreAdjust = -1000` on both hosts.
On pyrite, nix-daemon runs at 250 to match magnetite, the user manager and the desktop beneath it are lowered so builds and evaluators die before niri and DMS, both omnigent workers share one `omnigent.slice` with a combined `MemoryMax = 8G`, and the zram pool is capped by `zram-resident-limit` at about 55 % of RAM.

`just check-fast` takes a fourth positional parameter, `remote`, which selects the remote host for non-native systems: `magnetite` (default, `--eval-workers 4`) or `pyrite` (`--eval-workers 2 --eval-max-memory-size 2048`).
Any other value fails before evaluation.

Deliberately unchanged: nixbot's `8 x 4096`, `MemoryHigh = "12G"` and the absence of `MemoryMax`; magnetite's zram at 150 % and `swappiness = 100`; `nixbot.toml`.
Those values are the measured configuration, and the incident came from a second evaluation rather than from them.

## Phase 2, after measurement

These change kill and reclaim policy and each needs numbers from the hosts before it ships.

- systemd-oomd on a batch slice holding the evaluators and builds, with `ManagedOOMSwap=kill` or `ManagedOOMMemoryPressure=kill`. The single `8 x 4096` evaluation sustains PSI `full avg10` near 50 (`logs/magnetite-zram-headroom-experiment.md` §6.1), close to oomd's default 60 % pressure limit, so a pressure rule could kill a healthy nixbot evaluation.
- `MemoryLow` for the services that must keep running under pressure (sshd, postgresql, kanidm, nginx, nix-daemon), since the runtime `MemoryMin` floors used in the experiment were never made declarative (`logs/magnetite-zram-headroom-experiment.md` §0).
- Nix `use-cgroups`, so each build runs in its own cgroup and can be placed and limited separately from the daemon.
- `MemorySwapMax` on the evaluator and build cgroups, so zram consumption is bounded per workload rather than only by device size.

Measurements needed first:

- the real zram pool size (`mm_stat` `mem_used_total`) and PSI during a single nixbot evaluation under production conditions with a warm ARC, which the experiment did not characterise (§8);
- how long evaluations wait on the lock, for nixbot and for remote `check-fast` runs, and whether a wait can approach nixbot's evaluation timeout;
- per-build memory under `use-cgroups` on both hosts;
- oomd's swap and pressure readings across an `8 x 4096` evaluation, to choose limits that do not trigger on the measured normal load;
- on pyrite, desktop responsiveness under a build with the zram resident limit in place.
