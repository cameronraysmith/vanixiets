# Evaluation-cost baselines

This note keeps the evaluation-cost baselines that a claim about evaluation cost is compared against.
A claim that a change makes a host's configuration, a home configuration, a check, a runtime test or a set of check names cheaper to evaluate is accepted only on interleaved measurements at the base and candidate commits, taken on one host with one evaluator, whose runs agree at each commit and separate between the two; a change of evaluator or host starts a new baseline.
`logs/` is gitignored, so a figure kept only there is lost to everyone else; the baselines live here.
The principles document, `architectural-principles.md`, cites this note for every planned change that claims a cost reduction.

## Protocol

Measure with `just eval-cost <attr> <before> <after> [runs] [mode]` (`modules/apps/eval-cost.{nix,sh}`):

- every evaluation is the fleet's stock Nix (`flake.lib.fleetNix`), never the `nix` on PATH, which on stibnite can be iets' classic mode;
- each commit is read through `git+file://<repo>?rev=<commit>`, so only committed trees are measured;
- one untimed warm-up evaluation per commit, so the copy of the flake into the store is not timed;
- then `runs` rounds (default 2) of before, after, each a fresh process with `NIX_SHOW_STATS=1`, its own `NIX_SHOW_STATS_PATH` and `--option eval-cache false`;
- mode `drv` evaluates `<attr>.drvPath`; mode `keys` evaluates `<attr>` with `--apply builtins.attrNames`.

Each run records wall time, `cpuTime`, `gc.totalBytes`, `nrThunks` and `envs.number`; the header of `logs/eval-cost-<label>-<UTC>.log` records the evaluator's resolved path and version, the host and its memory, its sandbox setting, and the other evaluations running when the measurement started.
Thunk count and allocation are reproducible for one expression and one evaluator, so they separate on one round; CPU and wall time are not, so they need the interleaving.

A row below records the date, the commit, the host, the evaluator and its version, the attribute, the mode, and every run's figures, with the header conditions copied from the log.
A baseline is measured with the same commit on both sides, so its before and after rows also show the run-to-run spread.

## Baselines

All three were measured on 2026-11-27 at commit `b718b62ec596a92784e69c030723a3c3285836fa` on both sides, on stibnite (Darwin arm64, 65,536 MiB), with the fleet's stock Nix `/nix/store/g2n4lw86lg8xa3kml84hmynm22kla7j5-nix-2.35.6/bin/nix` (Nix 2.35.6), no other evaluation running at the start of each measurement.
Stibnite's `sandbox` setting is `false`: darwin builds there are not sandboxed, so an equal derivation path is evidence of an equal build recipe, not of an equal build.

### `darwinConfigurations.stibnite.config.system.build.toplevel` (drv)

`logs/eval-cost-darwinConfigurations-stibnite-config-system-build-toplevel-20261127T005522Z.{log,jsonl}`, started 2026-11-27T00:55:22Z.

| run | side | wall s | cpuTime s | gc.totalBytes | nrThunks | envs.number |
|---|---|---|---|---|---|---|
| 1 | before | 13.23 | 10.89 | 3,165,576,192 | 24,376,445 | 16,103,250 |
| 1 | after | 13.17 | 10.84 | 3,165,583,792 | 24,376,445 | 16,103,250 |
| 2 | before | 13.42 | 10.91 | 3,165,588,352 | 24,376,445 | 16,103,250 |
| 2 | after | 13.26 | 10.90 | 3,165,588,368 | 24,376,445 | 16,103,250 |

### `nixosConfigurations.cinnabar.config.system.build.toplevel` (drv)

`logs/eval-cost-nixosConfigurations-cinnabar-config-system-build-toplevel-20261127T005644Z.{log,jsonl}`, started 2026-11-27T00:56:44Z.

| run | side | wall s | cpuTime s | gc.totalBytes | nrThunks | envs.number |
|---|---|---|---|---|---|---|
| 1 | before | 30.73 | 12.28 | 2,679,411,792 | 24,154,292 | 16,859,178 |
| 1 | after | 29.17 | 12.36 | 2,679,407,936 | 24,154,292 | 16,859,178 |
| 2 | before | 28.85 | 12.59 | 2,679,408,592 | 24,154,292 | 16,859,178 |
| 2 | after | 26.63 | 12.28 | 2,679,410,128 | 24,154,292 | 16,859,178 |

Wall time exceeds CPU time by 14 to 18 s on every run; the log does not say where that time went, so compare cinnabar's wall time only with runs on the same host.

### `checks.x86_64-linux` (keys)

`logs/eval-cost-checks-x86_64-linux-20261127T005938Z.{log,jsonl}`, started 2026-11-27T00:59:38Z.

| run | side | wall s | cpuTime s | gc.totalBytes | nrThunks | envs.number |
|---|---|---|---|---|---|---|
| 1 | before | 0.37 | 0.31 | 199,098,208 | 792,380 | 294,009 |
| 1 | after | 0.36 | 0.31 | 199,098,208 | 792,380 | 294,009 |
| 2 | before | 0.37 | 0.31 | 199,098,208 | 792,380 | 294,009 |
| 2 | after | 0.36 | 0.31 | 199,098,208 | 792,380 | 294,009 |

### `just drv-diff` over the fleet

One full run of the cross-revision oracle (task 3.1), from `b718b62ec596` to `07877c74b4e5` on stibnite, started 2026-11-27T01:20:31Z with the fleet's stock Nix 2.35.6 and `nix-eval-jobs` 2.35.4 at 2 workers and 4,096 MiB per worker, took 857.5 s (`logs/drv-diff-b718b62ec596-07877c74b4e5-20261127T012031Z/header`, gitignored).
The mutant run of task 3.2, from `096de303b53b` to `8270a07764a7` under the same conditions, took 831.1 s.
Re-judging a recorded run with `just drv-diff-rejudge` evaluates nothing and takes seconds.

| set | attributes | before s | after s |
|---|---|---|---|
| nixos | 6 | 82.4 | 77.9 |
| darwin | 4 | 36.9 | 36.4 |
| home | 20 | 117.7 | 116.1 |
| checks.x86_64-linux | 238 | 113.8 | 133.3 |
| checks.aarch64-darwin | 115 | 35.9 | 32.8 |
| vmTests.x86_64-linux | 21 | 30.6 | 27.6 |
| vmTests.aarch64-linux | 3 | 8.8 | 6.5 |

## Measured changes

### stop-reading-other-hosts-configs (CAM-133), 2026-11-27

Before `390f72f0c80986760e941972c553008f00ee459c`, after `bbb7c5ccc978abd186a55b90cf0ab4b67ae3a29d`, on stibnite (Darwin arm64, 65,536 MiB), with the fleet's stock Nix `/nix/store/g2n4lw86lg8xa3kml84hmynm22kla7j5-nix-2.35.6/bin/nix` (Nix 2.35.6), sandbox `false`, no other evaluation running at the start of either measurement.
The change reads every fleet host key and stibnite's session key from committed files instead of from other hosts' evaluated configurations.

`darwinConfigurations.stibnite.config.system.build.toplevel` (drv), `logs/eval-cost-srohc-7-stats-stibnite-20261127T035106Z.{log,jsonl}`, started 2026-11-27T03:51:06Z:

| run | side | wall s | cpuTime s | gc.totalBytes | nrThunks | envs.number |
|---|---|---|---|---|---|---|
| 1 | before | 11.31 | 10.43 | 3,165,612,096 | 24,376,947 | 16,103,638 |
| 1 | after | 10.85 | 9.51 | 2,744,247,040 | 20,688,021 | 13,047,318 |
| 2 | before | 11.62 | 10.43 | 3,165,610,176 | 24,376,947 | 16,103,638 |
| 2 | after | 11.85 | 9.56 | 2,744,246,560 | 20,688,021 | 13,047,318 |

`nixosConfigurations.cinnabar.config.system.build.toplevel` (drv), `logs/eval-cost-srohc-7-stats-cinnabar-20261127T035215Z.{log,jsonl}`, started 2026-11-27T03:52:16Z:

| run | side | wall s | cpuTime s | gc.totalBytes | nrThunks | envs.number |
|---|---|---|---|---|---|---|
| 1 | before | 27.85 | 12.46 | 2,679,431,792 | 24,154,692 | 16,859,498 |
| 1 | after | 27.14 | 11.93 | 2,410,155,728 | 21,336,653 | 14,379,164 |
| 2 | before | 27.31 | 12.95 | 2,679,439,520 | 24,154,692 | 16,859,498 |
| 2 | after | 26.82 | 11.07 | 2,410,146,800 | 21,336,653 | 14,379,164 |

stibnite: 3,688,926 fewer thunks (15.1 %), 421,365,056 fewer bytes (13.3 %), CPU 10.43 s to 9.51 and 9.56 s (0.87 to 0.92 s, about 8.6 %).
cinnabar: 2,818,039 fewer thunks (11.7 %), 269,276,064 fewer bytes (10.1 %), CPU 12.46 and 12.95 s to 11.93 and 11.07 s.
Thunks and bytes are identical within each side and separate on one round; CPU separates on both rounds for both hosts (stibnite's slowest after run, 9.56 s, is below its fastest before run, 10.43 s; cinnabar's 11.93 s is below 12.46 s).
The 2026-11-26 reference below put the known-hosts read alone at 3.72 million thunks, 423 MB and 0.98 s over the host-only baseline; the observed stibnite saving is of that size.

## Reference, not comparable (2026-11-26)

These figures come from single runs on stibnite on 2026-11-26 (`logs/cross-host-eval-cost-<label>-20261126-*.stats.json`, gitignored) and are restated from the den-readiness audit.
They are not a baseline: the logs record neither the evaluator nor its version nor the exact command, the working tree was dirty, and each label was run once except `b`.
`base-flake`'s wall time (113 s, 23 s system) was dominated by copying the flake to the store, not by evaluation.

| label | what | cpuTime s | nrThunks | gc.totalBytes | envs.number |
|---|---|---|---|---|---|
| b | `darwinConfigurations.stibnite` toplevel drvPath | 10.97 | 24,376,302 | 3,148,532,208 | 16,103,072 |
| b2 | the same, second run | 10.70 | 24,376,302 | 3,148,547,760 | 16,103,072 |
| base-flake | flake load (`builtins.attrNames` of the 26 outputs) | 1.61 | 121,461 | 8,219,888 | 88,709 |
| base-host | stibnite's host name only | 0.39 | 681,965 | 138,745,408 | 320,931 |
| a | one NixOS host key read through cinnabar's config | 0.70 | 1,505,491 | 286,808,336 | 858,537 |
| c | the whole known-hosts attrset of `modules/system/ssh-known-hosts.nix` | 1.37 | 4,402,939 | 562,100,704 | 3,398,765 |
| d | magnetite's `stibnite-agent-session` public key through its config | 0.57 | 1,182,490 | 176,070,096 | 804,145 |

`c` less `base-host` is the audit's cross-host cost: 0.98 s CPU, 3.72 million thunks and 423 MB, 9 to 12 % of the stibnite toplevel.
The two stibnite runs agree on thunks exactly and on allocation within 16 kB, while CPU differs by 2.5 %.
