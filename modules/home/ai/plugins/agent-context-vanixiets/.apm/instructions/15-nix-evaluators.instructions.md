---
description: vanixiets many-attribute evaluators — which host evaluates with iets or stock nix-eval-jobs, what iets refuses, the drvPath-identity oracle, and how to report an evaluation-cost number.
---

## Evaluators

Two evaluators answer to `nix-eval-jobs` in this fleet, and which one a host has is decided by its memory.
A host with a known memory class (`flake.lib.hosts.<name>.memoryGiB` in `lib/hosts.nix`, turned into a bound by `flake.lib.nixEvalJobsBoundRules`) has [iets](https://github.com/numtide/iets) as `nix-eval-jobs`, capped at the bound's workers, and stock nix-eval-jobs beside it as `nix-eval-jobs-stock`.
A host without one (blackphos, whose memory is `"unknown"`) has stock as `nix-eval-jobs` and no second name.
The bound is the default when you pass no `--workers` and the ceiling when you pass more, so asking for 4 workers on an 8 GiB Mac gets 1.
The per-host table of memory, evaluator, bound and lock is in `modules/README.md` §Evaluators; read it there rather than from a copy.
nixbot on magnetite evaluates pull requests with its own lock-wrapped iets (`vanixiets.nixbot.ietsEvaluator`), whatever the host's PATH holds.

A host's PATH changes only when that host is deployed, so a server can still have stock as `nix-eval-jobs` after the change reached `main`.
`command -v nix-eval-jobs-stock` succeeds only where `nix-eval-jobs` is iets, which is also how the recipes decide: `just check-ifd` and the local lane of `just check-fast` print `evaluating ... with iets` or `with stock`, while the remote lane prints only `with its nix-eval-jobs`, so run the same `command -v` over ssh to learn what a remote has.

iets differs from stock in ways an agent meets directly:

- It refuses import-from-derivation, failing the attribute with `import from derivation is not supported: … is not built`. This repository forbids IFD anyway (`preferences-nix-development` §No import-from-derivation), so the fix is to remove the IFD, never to switch evaluator.
- It rejects `--override-input`, `--override-flake`, `--repair` and `--help` with exit 1, and evaluates only a local root flake, refusing `github:` and other fetched roots. `nix-eval-jobs-stock` is the escape hatch for these, and for nothing else.
- When one of its workers is killed, by the OOM killer for instance, the whole evaluation fails rather than that worker being replaced. That is why both names are lock-wrapped on every NixOS host that has iets: `nix-eval-jobs: waiting for the host evaluation lock held by …` every 30 seconds is queueing behind nixbot or another user, not a hang, and a second evaluation started beside it only queues too.
- `--max-memory-size` restarts its workers on Linux and does nothing on macOS, and iets has no garbage collector, so a worker on a Mac grows with everything it evaluates and only the worker count bounds memory.

The lock serialises only the evaluations that go through it, and only the names on PATH take it.
On a NixOS host, run a many-attribute evaluation (nix-eval-jobs or iets over a check set or a host set) only through the host's `nix-eval-jobs` or `nix-eval-jobs-stock` as PATH resolves them, as `just check-fast` does, never an evaluator called by its store path or one built from a flake, which takes no lock and runs beside nixbot's evaluation.
On magnetite a many-attribute evaluation needs 14 to 18 GiB of the host's 30 GiB, so two at once do not fit: on 2026-11-27 one called by its store path ran beside nixbot's and the host reset.

Plan memory from these peaks, measured on 2026-11-23 with nixbot's arguments: on argentum (8 GiB) at 1 worker, `checks.aarch64-darwin` reached a 4.8 GiB footprint and both systems 12.8 GiB with 5.3 GiB in swap; on stibnite (64 GiB) at 5 workers, 10.2-10.5 GiB and 17.1 GiB, with 2.2-3.8 GiB per worker; on magnetite, user evaluations stop at the 10.1 GiB `MemoryHigh` of `user.slice` and are throttled there.
The Macs have no evaluation lock, and several agents run at once on them, so their evaluations add up: before starting a many-attribute evaluation on a Mac, check `pgrep -fl 'nix-eval-jobs|iets'` and wait for a running one rather than start a second.

`just eval-identity [systems] [rev] [workers]` is the oracle that keeps iets honest: it runs a host's `nix-eval-jobs-stock` and `nix-eval-jobs` over `checks.<system>` of one commit and fails unless every attribute has the same drvPath, system and outputs.
It needs a host with iets and queues on the lock where there is one.
Run it on every bump of the `iets` flake input and on any change to how a host chooses, bounds, locks or wraps its evaluator, and name the result in the change description.
A difference is a finding: report the attribute and both drvPaths to the operator, and do not pin, exclude or rewrite anything to make the two agree.

An evaluation-cost number is evidence only with its conditions, so every one you record or compare names the evaluator (iets or stock, and its version or input revision), the host, the worker count and memory limit, the attribute scope, and whether another evaluation was running at the time.
Numbers from different evaluators are not comparable: the worker sizing table in `preferences-nix-ci-cd-integration` and the per-check figures in `preferences-nix-checks-architecture` were measured with stock, and iets evaluated the same check sets 3 to 5 times faster on 2026-11-23.
Evaluation-cost measurements are not made on magnetite, which runs CI, the binary cache, telemetry and OmniGraph, but on a host whose bound leaves headroom for them, inside a memory-limited scope.
`preferences-nix-checks-architecture` `references/evaluation-cost.md` holds the protocol.
