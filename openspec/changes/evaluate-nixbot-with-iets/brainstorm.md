<!--
Raw capture of the 2026-11-18 decision session on iets. The questions were explored by a
read-only survey of eleven repositories that use iets, a shadow benchmark on magnetite
(logs/iets-bench-20261118-175044/), an independent verification of every claim the session
made (verdicts C1-C6 below), and a read of nixbot at the pinned revision 171a8c77 while this
change was written. The operator settled each decision; this file records the log as it ran,
and design.md reorganizes it.
-->

# Brainstorm: iets as nixbot's evaluator

## Background

nixbot on magnetite evaluates every push and pull request of `cameronraysmith/vanixiets` and `sciexp/ironstar` with `nix-eval-jobs`, wrapped by the host evaluation lock (`modules/nixos/nixbot.nix:259-261`, `modules/lib/nix-eval-lock.nix`), at `evalWorkerCount = 6` and `evalMaxMemorySize = 3072` (`:139-140`), under `MemoryHigh = 20G` (`:246`) and with `allow-import-from-derivation = false` in the unit's `NIX_CONFIG` (`:250`).
Evaluation is the largest consumer of magnetite's memory, and the lock exists because two overlapping evaluations OOM-killed magnetite on 2026-09-27 and 2026-10-01.
A vanixiets evaluation of the two-system `checks` scope takes about 150 s of wall time and 410-430 s of user CPU under `nix-eval-jobs` (F12).

`numtide/iets` (v0.2.0, `9157ca1a`, 2026-11-11) is a Nix evaluator written in Rust with an `eval-jobs` command that accepts `nix-eval-jobs`' flags, and a "classic" mode in which its binary answers to Nix's command names.
The operator asked whether iets solves the evaluation cost, whether it should be shimmed in fleet-wide, and whether Mic92/nixbot#255 is needed to use it as nixbot's evaluator.

## Findings

**F1. What iets is.** Its own benchmark (one NixOS configuration, `nix-instantiate`, Nix 2.34.8, 32 cores) shows 1.5-1.8x on one core and 3.3-5x with four workers. Limits: no IFD support (`README.md:104`); it never reads a flake's `nixConfig` (`docs/reference/divergences.md:768-791`); flakes must be local and locked; a worker never frees memory (`README.md:109`); parity is checked against Nix 2.34.8 while the fleet runs 2.35.6 (`divergences.md:3-8`); the README calls it "LLM-ware" (`README.md:117-119`).

**F2. Making it available.** As a flake input on PATH: low effort, opt-in. Through `nixosModules.default` with `iets.classic.enable`: it replaces `nix.package` with a wrapper intercepting `nix`, `nix-build`, `nix-shell` and `nix-eval-jobs` (`nix/classic.nix:20`), which reaches clan deploys, `nix-fast-build --remote` and the lock wrapper; NixOS-only.

**F3. Mic92/nixbot#255** (zimbatm): open, conflicting, unapproved, last updated 2026-10-25. Adds `evalCommand` and `evalWritablePaths` for a shared writable evaluation cache. Mic92 raised cache poisoning (a `file://` `builtins.fetchurl` reading the cache, crc32 integrity) that becomes remote code execution once a poisoned output is deployed; nixbot evaluates outside contributors' pull requests, so that concern applies here. No speedup figure.

**F4. The PR is not needed.** `services.nixbot.packages.nix-eval-jobs` is already overridden through the lock wrapper, and every flag nixbot passes is one iets documents (`docs/reference/commands.md:576-605`). Without the PR the iets cache lives in the sandbox's tmpfs and is discarded per run.

**F5. Mic92 tried the global shim and reverted it.** `turingmachine` routed classic commands through iets on 2026-10-28 (`f65d8ad3`) and disabled it four days later, "until we got ifd" (`9af16bdc`). His nixbot on `eve` uses stock `nix-eval-jobs`.

**F6. lassulus** runs `iets eval-jobs --workers 4 --max-memory-size 3072` in one hosted CI job over IFD-free NixOS configurations (`ci.yml:179-182`), "about 5 times faster"; everything else uses Nix.

**F7.** Trusted users run iets only where the evaluated code is proven IFD-free. nixbot already disables IFD; local paths that need IFD (`modules/checks/apps.nix:23`, `packages.nix:16`, `catppuccin.nix:42`) would break a global shim the way they broke Mic92's.

**F8. ScottyLabs** runs iets as its nixbot evaluator, through a fork carrying #255, a shared writable cache at `/var/lib/nixbot/eval-cache` with no extra sandbox, and the classic shim on every host.

**F9. eka-ci** runs `iets eval-jobs` in pure mode inside bubblewrap plus landlock plus network filtering, with no `/etc/nix` visible; its changelog notes each iets process reserves about 36 GiB of address space, so `RLIMIT_AS` caps kill it (`CHANGELOG.md:131-138`). None of the fleet's lock files set `ulimit`, `RLIMIT_AS` or `LimitAS`.

**F10. Others' numbers.** maintainermode: 13.9 s vs 19.6 s per nixpkgs sweep. ConnorBaker: 103k nixpkgs jobs in 14.4 s at 33 GB, or 39.9 s at 16.4 GB with 4 workers at 4096 MB. Without its tracing cache the evaluation speedup is roughly 1.4-2x; memory grows within a worker until a restart.

**F11. Shim users keep hitting gaps:** `--verbose` fell back to real Nix before numtide/iets#304; no lock command or `--apply`; no zip unpacking; no `nixConfig`; pins drift.

**F12. Shadow benchmark on magnetite** (`logs/iets-bench-20261118-175044/summary.md`). nixbot's exact argv against vanixiets `main` (`10aacbc`), 295 checks over x86_64-linux and aarch64-darwin, both evaluators under the host lock and never concurrently, as user cameron and outside bwrap:

| run | wall s | user s | sys s | cgroup memory.peak GiB |
|---|---|---|---|---|
| nix-eval-jobs 2.35.4, cold | 150.0 | 411.5 | 113.6 | 15.20 |
| nix-eval-jobs, warm (median of 3) | 148.7 | 430.1 | 118.8 | 15.96 |
| iets 0.2.0, cold | 59.0 | 147.2 | 110.7 | 16.93 |
| iets, warm (median of 3) | 45.5 | 142.2 | 75.7 | 17.91 |
| iets, cache emptied | 30.3 | 135.2 | 52.9 | 17.53 |

All 295 drvPaths, outputs, `cacheStatus` (all `local`), `extraValue` and `system` matched. User CPU fell about 3x and held from run to run; iets' wall time fell across runs (59, 61, 46, 31, 30 s) for a reason not established. `iets eval-jobs` turns its tracing cache off (`src/cli/jobs.rs:227`), and the emptied-cache run matched the warm runs, so the gain is the evaluator, not the cache, and the shared writable cache of #255 buys nothing here. iets' cgroup peak ran 1-2.5 GiB higher (highest single run 18.55 GiB, iets warm2).

**F13. The fleet's caches do not depend on the flake's `nixConfig`.** `modules/system/caches.nix` writes `lib/caches.nix` into `nix.settings` for every NixOS and darwin host; `flake.nix:224-225` is a copy of that list.

**F14. iets asks the daemon for cache status.** `--check-cache-status` sends `QueryValidPaths` and `QuerySubstitutablePathInfos` (`src/jobs/cache.rs:1-6,100-124`); the daemon answers from its own configuration (`nix/src/libstore/daemon.cc:889-907`, `store-registration.cc:116-121`), and iets' own commands send no setting overrides (`docs/reference/settings.md:349-351`). Inputs missing from the store are substituted through the daemon first (`docs/reference/flakes.md:124-145`).

**R1.** Every iets path must run against a daemon configured from `lib/caches.nix`. Safe: nixbot on magnetite and any fleet host. Not safe: a runner relying on the flake's `nixConfig`, where plain Nix with `accept-flake-config` keeps the caches and iets loses them.

## Verification of the session's claims (verdicts)

- **C1 (benchmark and parity): confirmed.** Raw values in `logs/harness.log` match; all nine output files give an identical sorted fingerprint. argv matches `build_eval_command` (`nixbot/nix_eval.py:170-212`). **Correction:** nixbot passes `--eval-store` only when `buildStore.url` is set and `--reference-lock-file` only when `lock_file != flake.lock`; the fleet sets neither, so neither flag is passed today.
- **C2 (the swap): corrected — not one line.** `wrapNixEvalJobsWithLock` copies `package.nix` only if present and requires `version` (`modules/lib/nix-eval-lock.nix:43-49`); nixbot puts `packages.nix-eval-jobs.nix` on its unit PATH (upstream `nixosModules/nixbot.nix:1155-1158`) and builds its package with `buildInputs = [ nix-eval-jobs.nix ]` (`packages/nixbot.nix:56`). iets' `classic` package passes through only its own Nix's `{ pname, version }` (`nix/classic.nix:8`) and exists on Linux only; the default `iets` package has no `bin/nix-eval-jobs`. The default package's `nix` passthru must be grafted on. Under the classic name iets prints no summary (`src/cli/jobs.rs:305-306`), and the benchmark ran native `iets eval-jobs`, not the classic name.
- **C3 (cache status through the daemon): confirmed**, with the note that `query_substitutable_path_infos(...).unwrap_or_default()` makes a failed query count as a miss.
- **C4 (caches threaded into every host): confirmed.** **Correction:** cache.numtide.com is already in `lib/caches.nix:8` with its key at `:21`; there is nothing to trust.
- **C5 (the sandbox's `/etc/nix` does not matter for substitution): confirmed.**
- **C6 (no `RLIMIT_AS`; the sandbox's writable paths): confirmed.** nixbot caps each evaluation with a cgroup `memory.max` of 3072 × (6+1) = 21504 MiB (`nix_eval.py:107-112,385`); iets' cache resolves to `/tmp/.cache/iets` on the sandbox tmpfs. iets in a linked worktree with a read-only gitdir inside bwrap was not tested.

**Blocker B1:** the swap needs the passthru graft (C2).
**Blocker B2:** the lock's OOM design does not hold under iets. `nix-eval-lock.sh` raises the evaluator to `oom_score_adj 900` on the premise that "nix-eval-jobs >= 2.35.3 requeues an OOM-killed worker and retries it alone". iets turns a SIGKILLed worker into `Err(Protocol("…killed by SIGKILL, maybe memory limit reached?"))` (`src/jobs/collector.rs:215-239`), which aborts the whole run (`run_collector`, `:404-435`); nixbot reports that as `EvalOOMError`, a permanent failure (`nix_eval.py:676-689`). The magnetite assertion (`modules/machines/nixos/magnetite/default.nix:770-782`) still passes because it reads the script, not the evaluator.

**Open risks from verification:** headroom (nixbot measured 18.7 GB peak at 6 × 3072 inside nixbot; +1-2.5 GiB would land at about 19-20 GiB under `MemoryHigh = 20G` and the 21 GiB per-evaluation `memory.max`); uncovered paths (bwrap with a linked worktree, the `cached` and `notBuilt` states, the classic name, a failing evaluation); the unexplained wall-time drop; `allocBytes` meaning arena bytes under iets; per-run warnings about `plugin-files` and `accept-flake-config`; a repository `iets.toml` may only hold `[lint]`.

## Decision chain

**D1. A global classic shim?** No. Mic92 reverted his after four days because of IFD (F5), shim users keep hitting gaps (F11), and the fleet has IFD paths of its own (F7). (Operator, 2026-11-18.)

**D2. Where iets goes.** iets replaces only nixbot's evaluator, through `services.nixbot.packages.nix-eval-jobs`, still wrapped by the evaluation lock. No #255, no writable or shared cache, no change to nixbot's sandbox. (Operator.)

**Q1. Add the flake's `nixConfig` substituters to magnetite?** Settled by F13/F14: they are already there; no change. R1 stays as a world assumption and a risk.

**Q2 (revised). Memory settings.** No blind change to `--max-memory-size`. Tune it from measured data after the switch, recorded as a decision citing the measurements. (Operator.)

**Q3. Scope.** nixbot only; developer machines, direnv and buildbot keep stock Nix. (Operator.)

**Q4. Linear.** A new issue. (Operator.)

**Q5 (revised). B2, whole-evaluation abort on a killed worker.** Accept it only if instrumentation shows comfortable headroom during the canary and the first week; file an upstream issue asking iets to retry killed workers. (Operator.)

**Q6. Packaging.** A minimal package with `bin/nix-eval-jobs -> iets` and nixbot's default `passthru.nix` grafted on. The `classic` package is rejected: it bundles a Nix closure and shims for four other command names. (Operator.)

**Q7. Instrumentation first, and evaluator-agnostic.** The change's first task group: one structured journald record per evaluation (evaluator name and version, workers, max-memory-size, wall/user/sys time, the evaluation cgroup's `memory.peak` against `memory.max`, `memory.events` `oom_kill`, worker restarts, exit status), shipped by the existing collector journald pipeline into GreptimeDB with a dashboard panel. Existing per-attribute `eval_wall_ms`/`eval_alloc_bytes` (`schema.nix:249-250`) are noted, with the caveat that iets' `allocBytes` are arena bytes. Order: instrument under stock `nix-eval-jobs` and collect one week of baseline at 3072 MB; canary iets inside nixbot's real sandbox (bwrap, worktree, classic name; covering `cached`/`notBuilt` and a failing evaluation); switch at 3072; tune from data. Rollback is a one-line revert to the stock package. (Operator; the operator's wording put the producer in the lock wrapper, revised by D3 below.)

## Points found while writing the change

**D3. Who produces the record.** The operator's Q7 wording had the nixEvalLock wrapper emit the record. Read at nixbot 171a8c77, that cannot work for nixbot's evaluations:
- The wrapper runs inside nixbot's bubblewrap sandbox, which is built with `--unshare-all` (so a private cgroup and PID namespace) and binds only `SANDBOX_ETC_PATHS`, the store, the store database, the daemon socket, the worktree and the gc-roots directory (`nixbot/nixbot/nix_eval.py:221-304`). Neither `/run` (so no journald socket) nor `/sys` (so no `memory.peak` or `memory.events`) is visible, and `extra_ro_paths` is hard-coded to the repository clone (`build_run.py:217`), with no option to add more.
- The wrapper `exec`s the evaluator (`modules/lib/nix-eval-lock.sh`, last line), so nothing of it remains to write after the evaluator exits.
- Evaluator stderr reaches only nixbot: a tail kept on failure and `warning:`/`error:` lines stored as build warnings (`nix_eval.py:441-470`, `build_run.py:350-359`); none of it reaches the journal.
- nixbot itself creates the evaluation cgroup, sets `memory.max` (`nix_eval.py:379-386`), reads `memory.events` (`:535-548`), and deletes the cgroup right after the run (`:614-615`). It logs JSON lines to the journal (`log.py:25-43`).
Main and the operator settled option A: one host-side producer, a fifth nixbot patch beside the four at `modules/nixos/nixbot.nix:277-286`, which logs one structured record per evaluation before the cgroup is removed; the wrapper is untouched. The patch also counts the two kill messages `nix-eval-jobs` prints on stderr (budget kill, `src/nix-eval-jobs.cc:322-327`; kernel kill, `:493-497`), so kills are measured for the stock evaluator; under iets a kill shows as a failed run with `oom_kill > 0`. It is written so it can be offered to Mic92/nixbot. Rejected: B, keeping the producer in the wrapper (fork-and-wait instead of `exec`, plus a nixbot patch to bind the journald socket and the evaluation cgroup into the sandbox, whose path the cgroup namespace hides), which still needs a nixbot patch and changes the lock's documented lifetime; C, two producers per evaluation. buildbot's and `nix-fast-build --remote`'s evaluations, which also go through the wrapper, are not recorded and are out of scope.

**Worker restarts have no default-verbosity signal in either evaluator.** `nix-eval-jobs` logs a worker's creation at debug level only (`src/nix-eval-jobs.cc:65-66`) and a recycling worker says `restart` on its private pipe (`src/worker.cc:483`); iets' collector likewise reads `restart` silently (`src/jobs/collector.rs:144-147,243`), its `spawned` counter appears only in the summary that classic mode suppresses (`src/cli/jobs.rs:305-322`), and its `IETS_EVENTS` groups have no worker event (`src/events.rs:47-62`). Candidates, left open: a debug-verbosity probe in the canary only, or an upstream request for a summary line.

**cgroup counters cover time as well as memory.** Every cgroup v2 directory has `cpu.stat` with `usage_usec`, `user_usec` and `system_usec`, whatever controllers are enabled, so the record's wall/user/sys can come from the same evaluation cgroup as `memory.peak`, without relying on `getrusage` of a daemon that runs other children concurrently.

**magnetite facts read on 2026-11-18** (as cameron, through `sudo -n`): kernel 6.18.60; `nixbot.service`'s cgroup has `memory.peak` (19,236,646,912 bytes since the unit started) and `cpu.stat`; the journal holds `nixbot.service` lines back to 2026-10-22 in 2.1 GB of journals; 88 `starting evaluation` lines in the past day.

**The record goes into the dev-loop history.** The `devloop` database already has the journald-to-table path (`journald/gitea-mq` -> `batch_event`), the single allow-list (`flake.lib.otelCollectorSchema.devloop.tables`), the per-table pipeline and the daily reconcile; an `eval_run` table follows it. The `devloop-collection` gap requirement already covers every kind of dev-loop record, so the daily reconcile gains a comparison of `eval_run` rows with nixbot's journal.

## Revision of 2026-11-18 (after #4012 merged)

**Operator decision R-a: capacity, not keep-or-revert.** magnetite's primary job is to be the best nixbot server. If iets is faster, the fleet adapts to give it room, within what the operator will pay for and maintain.
- The revert stays only as the immediate safety valve for a failing or broken evaluation; the one-line rollback is unchanged.
- Insufficient headroom triggers a resource decision, in order of cost and effort: (a) tune the evaluator (workers, `--max-memory-size`); (b) reclaim memory on magnetite (ZFS ARC cap, zram, per-service memory limits); (c) move non-CI services off magnetite, the subject of a separate fleet-topology initiative; (d) resize the host. (c) and (d) are operator decisions.
- The 90 % / 20 GiB figure becomes the trigger for that decision, not a verdict.

**Operator decision R-b: a magnetite memory budget in the record's scope.** Per-unit memory (current, peak) for the services competing with evaluations, the ZFS ARC size and limit, and swap/zram use, sampled over the baseline week; first check read-only what the collector and node_exporter already report, add only what is missing, and chart it beside the evaluation record.

**What the read-only check found (2026-11-18).**
- Stored in `fleet` on magnetite (label-values read through the store's read-only account): `node_zfs_arc_size`, `_c`, `_c_min`, `_c_max`, `_hits`, `_misses`, `_memory_throttle_count` (keep-list `modules/clan/services/otel-collector/schema.nix:61-71`); `system_paging_usage_bytes` (paging scraper, `flake-module.nix:343-348`); `system_linux_memory_available_bytes`; `system_memory_usage_bytes`; `node_vmstat_oom_kill`; `process_memory_usage_bytes` (processes of at least 64 MiB); `systemd_service_restarts_total` and `systemd_unit_state`.
- Not stored: any per-unit memory. The `systemd` receiver is configured for restarts only (`flake-module.nix:395-402`), and the deployed `opentelemetry-collector-contrib-0.155.0` has no memory metric in that receiver: its `metadata.yaml` at tag `v0.155.0` lists `systemd.service.cpu.time` and `systemd.service.restarts` only, while the local checkout at `cd37ea9151` (2026-10-15) adds `systemd.service.memory.usage` and `.usage.max`.
- Not stored: zram's own RAM use. `system_paging_usage_bytes` counts swapped data at its uncompressed size; zram0's `mm_stat` showed 4.98 GB of data in 0.55 GB of RAM.
- magnetite read through `sudo -n`: ARC `size` 5.41 GB, `c` 6.11 GB, `c_max` 31.78 GB (`zfs_arc_max` is 0, so ARC may grow to the whole of RAM); swap is zram0 at 45.9 GiB (`zramSwap.memoryPercent = 150`), 4.8 GiB used; `system.slice` `MemoryCurrent` 2.39 GB, `user.slice` 0.78 GB. Unit `memory.current` / `memory.peak`: `nixbot` 0.36 / 19.24 GB, `nix-daemon` 0.42 / 12.97 GB, `greptimedb` 0.59 / 1.07 GB, `postgresql` 0.29 / 0.59 GB, `omnigent` 0.03 / 0.23 GB, `gitea` 0.09 / 0.17 GB, `matrix-synapse` 0.02 / 0.13 GB (nested under `system-synapse.slice`), `docker` 0.03 / 0.10 GB, `kanidm` 0.02 / 0.08 GB, `perses` 0.04 / 0.08 GB, `omnigraph-server` 0.02 / 0.08 GB, `niks3` 0.03 / 0.07 GB, `gitea-mq` 0.04 / 0.06 GB, `livekit` 0.02 / 0.04 GB.
- No buildbot unit exists on magnetite (`systemctl list-units --all '*buildbot*'` is empty), so the operator's mention of buildbot has nothing to measure today.

**Resulting design (D9 rewritten, D10 revised, D11 added).** A magnetite-only probe writes systemd's `MemoryCurrent`/`MemoryPeak` for a fixed unit list plus `system.slice` and `user.slice`, and zram's `mm_stat`, to node_exporter's textfile collector; five names join the keep-list; a budget chart sits beside the evaluation charts. Reading through `systemctl show` rather than a fixed cgroup path covers nested units such as `matrix-synapse.service`. When a contrib bump brings the receiver's memory metrics, the probe's unit series give way to them.

## Decisions of 2026-11-18 (after the first deploy)

**Operator decision R-c: nothing is filed upstream to iets.** No issue, pull request or comment to `numtide/iets`. The request for iets to retry killed workers (Q5 as revised, task 3.3) and the upstream-summary-line candidate for counting worker restarts are withdrawn. The whole-evaluation abort on a killed worker (C2/B2) stays mitigated only by the capacity gate, the measured headroom and the canary; no replacement action is added (design D12).

**Operator decision R-d (Q40): task group 3 starts now, beside the baseline week.** The iets input and the minimal package are added and built on magnetite but not selected; nixbot keeps stock nix-eval-jobs and magnetite's system derivation must not change. A check pins what nixbot and the lock need from the package. Q41, when the canary runs, is undecided; task group 4 is not scheduled.

**Operator decision R-e (Q43): the paired replay replaces the week as the switch condition, read with judgement.** About twenty commits nixbot has already evaluated (the five heaviest, the five slowest, the latest flake update, one each of local, cached, not-built and failing, the rest random) run under both evaluators back to back, alternating order, in nixbot's real sandbox and argv, in a quiet window, tagged and kept out of the baseline. P1 identical attributes and derivations, P2 iets peaks at most 90 % of `memory.max` and 20 GiB, P3 no OOM or worker kill, P4 cache states alike, P5 no commit more than 10 % slower (sanity only). The baseline needs at least 48 hours including Friday 22:00 UTC's flake-update evaluation, whose stock peak must be under 90 %. A tripped criterion opens a discussion of mitigations, not a rejection; P1 is firm until explained. The only automatic action is the one-line revert after a failed production evaluation. Earliest switch: Saturday 2026-11-21 (design D13).

**Operator decision R-f (Q47, 2026-11-19): a soft memory guard on magnetite's user sessions before the switch.** `user.slice` gets `MemoryHigh = 10G` and no `MemoryMax`; nix-daemon, nixbot and `system.slice` stay unlimited. User evaluation does not warm nixbot's cache, builds through nix-daemon do, so throttling it keeps the warming. A hard `MemoryMax` and moving development evaluation off magnetite wait for CAM-112's dev host. The probe adds the slice's `memory.events` `high` count (design D14, task 5.0).
