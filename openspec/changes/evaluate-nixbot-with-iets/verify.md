# Verification: evaluate-nixbot-with-iets

## Task group 4: paired replay (design D13), 2026-11-19

Logs: `logs/cam-111-replay/`:
- the driver `replay.py` with `runner.sh`, the argv grounding `argv-grounding.md` and the commit set `commits.tsv`;
- all runs merged in `out-merged/`, with `analysis.txt`, `comparison.log` and `summary.tsv`;
- the excluded windows in `excluded-windows.txt`;
- the memory variants in `variants-20261119T052959Z/` and the cold run in `cold-20261119T054609Z/`.

**4.1 Replay set.** 20 commits of `cameronraysmith/vanixiets` that nixbot had already evaluated (`commits.tsv`, chosen from `devloop.eval_run`, `devloop.ci_build` and `devloop.ci_attribute`):
- the 5 heaviest by stock `memory_peak_bytes` (builds 2789, 2788, 2776, 2775, 2784);
- the 5 slowest by `wall_ms` (2786, 2779, 2787, 2778, 2774);
- 3 nixpkgs bumps: 7ef711cd ("Update nixpkgs", 2026-11-17, build 2658), e527ef7b (nixpkgs 3a32588c with kernel 6.18.58, 2026-10-25, build 1913) and 97bfad2e (nixpkgs bump 2026-11-13, build 2440, which also had attribute evaluation errors). 2784 (bb7d5d3a) is also the latest `flake.lock` change.
- The failing commit is ab3cc6ff (build 2571, 68 `failed_eval` attributes).
- The rest: main at selection (c3672d28) and 5 commits drawn with a seeded `shuf` over the remaining `eval_run` builds.
- Every commit is in nixbot's clone.

**4.2 Argv.** `build_full_command` at the deployed nixbot (`Mic92/nixbot@171a8c77` plus vanixiets' patches, `/nix/store/wc3bz7lnf58wp7wjw5fmby5s3ylbsv07-python3.14-nixbot`). The driver imports it and calls it with `_eval_settings`' values; it does not reconstruct the argv:
- 6 workers × 3072 MiB;
- `cgroup_limit_mib` from `calculate_eval_workers()` at run time;
- eval systems x86_64-linux and aarch64-darwin;
- the clone read-only;
- `systemd_scope=False`, nixbot's delegated-cgroup branch.

File and line citations are in `argv-grounding.md`. The evaluator runs as `nixbot` with nixbot's environment and PATH, inside bwrap, in a transient scope whose `MemoryMax` is nixbot's computed `memory_limit_mib` and whose `MemoryHigh` is nixbot.service's 20 GiB. Both evaluators run behind `/etc/nix/eval.lock`:
- stock: `/nix/store/33vjcra6…-nix-eval-jobs`, the wrapper on nixbot.service's PATH (nix-eval-jobs 2.35.4);
- iets: `/nix/store/dzqhv8if…-nix-eval-jobs` (`nixEvalLock.wrap` of `vanixiets.nixbot.ietsEvaluator`, iets 0.2.0).

Flake inputs are prefetched before each pair with nixbot's `prefetch_flake_inputs`.

**4.3 Runs.** Each commit ran under both evaluators back to back, alternating which went first (odd commits stock first, even commits iets first), between 03:48Z and 05:57Z.
- **Quiet**, checked before every run: no process in a `nixbot.service/eval-*` cgroup, `/etc/nix/eval.lock` free, and no `switch-to-configuration`, `nixos-rebuild` or activation process. Each pair also waited until nixbot had started no evaluation for 150 s.
- **Discards and redos:**
  - A pair was discarded when nixbot logged "starting evaluation" during it, or when the lock wrapper reported waiting. That happened to two pairs, #15 and #02; both were redone.
  - Pairs #03, #06 and #07 overlapped two magnetite activations by CAM-115: 04:22:25Z–04:26:14Z (unplanned) and 04:36:01Z–04:37:53Z. They were excluded and redone at 05:23Z–05:32Z.
  - The redone #07 then overlapped builds offloaded to magnetite's nix-grpc-daemon from pyrite, 05:30:30Z–05:31:05Z, so it was redone again at 05:53Z–05:57Z.
  - In the final set no run waited for the lock or overlapped a production evaluation, a deploy or the offload (`excluded-windows.txt`).
- **Tagging:** scopes are named `cam111-replay-<n>-<evaluator>-a<attempt>`, and each run's start and end are in `out-merged/runs.tsv`. The runs bypass nixbot, so they leave no `eval_run` rows. The stock summary (2.6) excludes 03:48Z–05:42Z and 05:46Z–05:58Z on 2026-11-19 (the replay, the variants, the cold run and the last redo).

**4.4 P1, P4.**
- 20/20 commits have the same attribute set, and per attribute the same `drvPath`, `outputs`, `system` and presence of `error`; both evaluators exited 0 everywhere. That is 5,915 attributes in total, 37 of them erroring.
- The failing commit ab3cc6ff has the same 34 erroring attributes under both evaluators, and 97bfad2e the same 3.
- `cacheStatus` is identical per attribute on every commit. All three states occur among the attributes that did not error: 5,391 `local`, 352 `cached`, 135 `notBuilt`.

**4.5 P2, P3, P5.**

| # | commit | stock wall s | iets wall s | speed-up | stock peak / max MiB | iets peak / max MiB (%) |
|---|---|---|---|---|---|---|
| 1 | e8fda637 | 160.0 | 60.8 | 2.63× | 16001 / 21991 | 17455 / 21535 (81.1) |
| 2 | fc5298e7 | 158.6 | 59.1 | 2.68× | 16231 / 23004 | 18226 / 22361 (81.5) |
| 3 | 21ae9659 | 141.1 | 46.5 | 3.03× | 15466 / 22776 | 18050 / 22251 (81.1) |
| 4 | 7a7478ee | 125.1 | 78.3 | 1.60× | 16134 / 23012 | 17927 / 22746 (78.8) |
| 5 | bb7d5d3a | 145.2 | 59.0 | 2.46× | 15359 / 22678 | 18098 / 21830 (82.9) |
| 6 | 450f5ae4 | 133.1 | 32.4 | 4.11× | 15733 / 22196 | 17972 / 22662 (79.3) |
| 7 | 3b7bc70d | 137.2 | 49.3 | 2.78× | 15807 / 22320 | 17231 / 22904 (75.2) |
| 8 | df2eaab0 | 183.9 | 55.7 | 3.30× | 18272 / 22740 | 17592 / 22468 (78.3) |
| 9 | a1a3710d | 128.2 | 51.9 | 2.47× | 16755 / 22833 | 16953 / 22168 (76.5) |
| 10 | 3f0d702b | 139.2 | 32.2 | 4.32× | 15930 / 22399 | 18401 / 22836 (80.6) |
| 11 | 7ef711cd | 160.3 | 36.5 | 4.39× | 15850 / 22849 | 18585 / 23071 (80.6) |
| 12 | e527ef7b | 151.8 | 99.1 | 1.53× | 17302 / 23211 | **20480 / 22707 (90.2)** |
| 13 | 97bfad2e | 169.0 | 30.6 | 5.52× | 16085 / 23035 | 18434 / 22449 (82.1) |
| 14 | ab3cc6ff | 137.1 | 58.3 | 2.35× | 16341 / 23410 | 18749 / 23137 (81.0) |
| 15 | c3672d28 | 167.8 | 52.7 | 3.18× | 16061 / 21869 | 18964 / 22295 (85.1) |
| 16 | c15ba3ad | 149.0 | 37.6 | 3.96× | 15562 / 22626 | 17536 / 23501 (74.6) |
| 17 | c6376ab4 | 132.6 | 34.0 | 3.90× | 16610 / 22935 | 18382 / 22624 (81.2) |
| 18 | a67385bc | 147.6 | 33.5 | 4.41× | 16098 / 23040 | 18802 / 23138 (81.3) |
| 19 | 54da57d4 | 127.5 | 31.1 | 4.10× | 17591 / 23165 | 18674 / 22648 (82.5) |
| 20 | d05f4a39 | 139.9 | 34.9 | 4.01× | 17256 / 23045 | 20003 / 22881 (87.4) |

- **P2: 19/20.** #12's iets run peaked at nixbot.service's `MemoryHigh` (20480 MiB, `memory.events` high 94), which is 90.2 % of its ceiling. The throttling is why it ran only 1.53× faster. It was the first evaluation of that 3-week-old commit after prefetch.
  - Four repeat iets runs of #12 at the same settings, 05:33Z–05:41Z, peaked at 17145–18428 MiB (75.7–80.6 %) with no high events, in 31–39 s.
  - One discarded iets run of #02 (a1, the first evaluation of that commit) also reached 20480 MiB with 190 high events; its valid repeat peaked at 18226 MiB.
  - Stock peaks ranged 67.7–80.4 % of their ceilings, all iets peaks other than #12 74.6–87.4 %.
- **P3: 20/20.** No `oom_kill`, no `oom` events, and no kill messages in iets' stderr. Exit status is 0 in every run.
- **P5: 20/20.** No commit was slower under iets. The speed-up (stock wall / iets wall) has a median of 3.24× (worst 1.53× on #12, best 5.52× on #13); summed over the set it is 2934 s against 974 s, 3.01×. User CPU was about 3× lower under iets; system CPU was similar.
- **iets warnings** are only its two notices that it ignores `plugin-files` and `accept-flake-config` (A143). P4 shows that ignoring `accept-flake-config` does not change cache status.
- **#12's 20 GiB peak:** the cold run under B below measured the memory split. At its peak the evaluation held anonymous memory (16148 of 17081 MiB) and only 74 MiB of file pages, so a cold first evaluation is heavier in the workers' heaps, not in page cache.
- **Reading under D13:** P1, P3, P4 and P5 pass. P2 tripped once, on a cold first evaluation, which opened D9's ladder rather than a rejection; its first rung was taken (design D10, below).

**Memory variants**, iets on #12 and #18, twice each, same sandbox and cgroup shape, 05:33Z–05:41Z:

| variant | #12 wall s (mean) | #12 max peak MiB (%) | #18 wall s | #18 max peak MiB (%) | high events | oom | worker processes seen |
|---|---|---|---|---|---|---|---|
| base: MemoryHigh 20G, 6 × 3072 | 35.1 | 18428 (80.6) | 31.1 | 18624 (82.3) | 0 | 0 | 12 (6 replaced) |
| A: MemoryHigh 22G, 6 × 3072 | 31.7 | 18581 (83.6) | 31.1 | 17956 (80.4) | 0 | 0 | 12 (6 replaced) |
| B: MemoryHigh 20G, 5 × 3072 | 34.6 | 15584 (67.8) | 31.6 | 16163 (72.0) | 0 | 0 | 10–11 (5–6 replaced) |
| C: MemoryHigh 20G, 6 × 2560 | 33.4 | 15121 (65.9) | 33.1 | 15532 (69.8) | 0 | 0 | 14–17 (8–11 replaced) |

- **None of the 16 runs reached MemoryHigh.** #12's earlier 20480 MiB peak did not recur once that commit had been evaluated before.
- **Worker processes seen** counts distinct `iets eval-jobs --worker` processes sampled every 0.2 s; "replaced" is the count above the configured number of workers. This is routine recycling at `--max-memory-size`, not kills (A145).

**Cold run under B** (`cold-20261119T054609Z/`): 395ec68b (2026-10-07, nixpkgs ac1faec4, last evaluated by nixbot as build 1259, weeks before), iets at 5 × 3072 with MemoryHigh 20G, `memory.current` and `memory.stat` sampled every 0.25 s.

| run | wall s | peak MiB | memory.max MiB | % | high events | oom_kill | at the peak: anon / file MiB | workers seen |
|---|---|---|---|---|---|---|---|---|
| a1, cold, 05:47:26Z | 137.4 | 17081 | 22008 | 77.6 | 0 | 0 | 16148 / 74 | 10 (5 replaced) |
| a2, warm repeat, 05:52:45Z | 53.9 | 13008 | 22506 | 57.8 | 0 | 0 | 12856 / 70 | 12 (7 replaced) |

- **Cold timing:** a1's peak came 22 s in. It spent about 110 s copying the commit's sources and derivations into the store (stderr: "copying 12159 paths") and its last 25 s at about 600 MiB.
- **Why a1 is used:** the driver marked a1 discarded because a production evaluation started at 05:49:04Z, 40 s before a1 ended. That evaluation queued on the evaluation lock behind a1 (a1's stderr has no lock wait), so it did not run beside a1. A cold run cannot be repeated cold, so a1's figures are used, with that disclosed.
- **Result:** 235 attributes, no errors, exit 0.

**D9's first rung, taken 2026-11-19 (design D10):** 5 workers × 3072 MiB, `MemoryHigh` 20G kept.
- **Peaks:** B's iets peaks were 2.4–2.8 GiB below base's on the replay commits (15584 against 18428 MiB on #12, 16163 against 18624 MiB on #18), at 67.8–72.0 % of their own ceilings. Its cold first evaluation peaked at 77.6 %, with no throttling.
- **Speed:** wall times are within the run-to-run spread of base (34.6 against 35.1 s, 31.6 against 31.1 s; two runs each), so no speed loss is measurable.
- **Why not C:** it saves about as much memory but recycles workers more (8–11 replaced against 5–6).
- **Why not A:** it lowers no peak. It only removes the throttle, so a cold first evaluation like #12's, which was already at 90.2 % of a 22707 MiB ceiling when throttled, would cross the 90 % line.
- **Headroom on magnetite** (30.6 GiB total; ceiling = max(21504 MiB, MemAvailable + 0.75 · ARC − 2048 MiB), the ceilings seen here 21.0–22.9 GiB):
  - B's worst observed peak, the cold 16.7 GiB, leaves 4.8 GiB within its own ceiling and 13.9 GiB of the host for everything else, ARC (which can shrink to its 1 GiB `c_min`) included.
  - Base's worst warm peak, 18.2 GiB, leaves 12.4 GiB; its cold peak at the throttle, 20.0 GiB, leaves 10.6 GiB.

**Operator decision Q69, 2026-11-19 (design D13):** the switch happens as soon as the replay passes P1–P5, with the replay set holding broad `flake.lock` updates.
- Both parts of the baseline condition are gone: the 48 hours of stock records and the wait for Friday's flake update.
- 5.1's Saturday gate is gone.
- 2.6's stock summary stays, without a gate, as the reference for the switched week.
- The 6.1 safety valve stays.

**Operator decision Q72, 2026-11-19 (task 5.1):** switch nixbot to iets at 5 workers × 3072 MiB.
- **Criteria:** P1, P3, P4 and P5 passed on all 20 commits. P2 tripped once, on #12's cold first run under base settings, and is answered by D9's first rung (above), whose cold run peaked at 77.6 % with no throttling.
- **Capacity trigger:** D9's trigger stands as written (90 % of an evaluation's own `memory.max`, 20 GiB), read over the switched week in 6.2.
- **Worker count:** returning to 6 workers is reopened only on evidence that evaluation is worker-bound (wall time growing with attribute count while CPU time stays well below wall × workers), and then through a paired 5-against-6 run with enough repeats, not a production trial.
