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
