## Context

nixbot on magnetite evaluates every push and pull request of `cameronraysmith/vanixiets` and `sciexp/ironstar` with its own patched `nix-eval-jobs` (2.35.4, linking Nix 2.35.6), run as the bare name from the unit PATH inside a bubblewrap sandbox, behind the host evaluation lock (`modules/nixos/nixbot.nix:259-261`, `modules/lib/nix-eval-lock.nix`, `modules/nixos/nix-eval-lock.nix`).
The evaluator runs at 6 workers × 3072 MiB (`nixbot.nix:139-140`); nixbot gives each evaluation its own cgroup with `memory.max` = 3072 × (6+1) MiB = 21 GiB (`nixbot/nixbot/nix_eval.py:107-112,379-386`), and the unit carries `MemoryHigh = 20G` (`nixbot.nix:246`), a backstop measured to sit above the 18.7 GB evaluation peak of 2026-09.
IFD is off for nixbot through the unit's `NIX_CONFIG` (`nixbot.nix:250`).
The lock wrapper raises the evaluator to `oom_score_adj 900` because `nix-eval-jobs` ≥ 2.35.3 requeues an OOM-killed worker and retries it alone (`nix-eval-lock.sh`), and magnetite's kill-order assertion reads that script (`modules/machines/nixos/magnetite/default.nix:770-782`).

The shadow benchmark on magnetite (`logs/iets-bench-20261118-175044/summary.md`, brainstorm F12) ran nixbot's exact argv through iets 0.2.0 (`numtide/iets@9157ca1a`) and through the lock-wrapped `nix-eval-jobs`: 295 identical drvPaths, outputs, `cacheStatus`, `extraValue` and `system`; user CPU 135-147 s against 409-435 s; whole-tree cgroup peaks of 16.9-18.6 GiB against 15.2-16.2 GiB.
It ran as user cameron outside bwrap with native `iets eval-jobs`, every result was `local`, and no evaluation failed, so the sandbox, the classic command name, the `cached` and `notBuilt` states and a failing evaluation are uncovered.

What exists for measuring an evaluation today: nixbot's `builds.eval_duration_ms` and per-attribute `eval_wall_ms` and `eval_alloc_bytes`, copied into `devloop.ci_build` and `devloop.ci_attribute` (`modules/clan/services/otel-collector/schema.nix:249-250`).
Nothing records an evaluation's memory peak, its ceiling, kernel kills, the evaluator's own kill messages or which evaluator ran.
Under iets, `allocBytes` counts arena bytes, while `nix-eval-jobs` counts the garbage collector's bytes, so `eval_alloc_bytes` changes meaning at the switch.

Stakeholders: the operator, who maintains magnetite and reads the dev-loop view; contributors whose pull requests nixbot evaluates.

## Goals / Non-Goals

**Goals:**
- One structured record per nixbot evaluation, independent of which evaluator runs, in the dev-loop history, reconciled daily and charted.
- A week of baseline under `nix-eval-jobs` at 6 × 3072 before any switch.
- A canary of iets inside nixbot's real sandbox under the classic command name, covering `cached` and `notBuilt` outputs and a failing evaluation.
- nixbot evaluating with iets behind the same lock, revertible with one change.
- Memory settings tuned from recorded peaks after the switch, with the decision recorded.

**Non-Goals:**
- A fleet-wide classic shim, iets on developer machines, in direnv or under buildbot (D1).
- Mic92/nixbot#255, `evalWritablePaths`, or any shared or writable evaluation cache (D2).
- Recording buildbot's or `nix-fast-build --remote`'s evaluations, which also pass through the lock wrapper.
- Changing `--max-memory-size`, `evalWorkerCount` or `MemoryHigh` before the measurements exist (D8).
- Counting routine worker recycling (open question 1).

## Decisions

### D1: No global classic shim
- **Choice**: iets is not installed as `nix`, `nix-build`, `nix-shell` or `nix-eval-jobs` on any host's PATH or as `nix.package`.
- **Rationale**: Mic92 enabled the classic shim on 2026-10-28 and disabled it four days later because his configuration needs IFD (`9af16bdc`); the fleet has IFD paths of its own (`modules/checks/apps.nix:23`, `packages.nix:16`, `catppuccin.nix:42`); shim users keep hitting gaps (brainstorm F11); and the shim would sit under clan deploys, `nix-fast-build --remote` and the lock wrapper.
- **Alternatives considered**: `nixosModules.default` with `iets.classic.enable` (high blast radius, NixOS-only); iets on PATH as `iets` only (harmless, but out of this change's scope, Q3).

### D2: iets replaces only nixbot's evaluator, behind the lock, with no cache sharing
- **Choice**: set `services.nixbot.packages.nix-eval-jobs` to `config.services.nixEvalLock.wrap` of the D3 package; nixbot's sandbox, argv and settings are unchanged.
- **Rationale**: the benchmark's gain is the evaluator itself: `iets eval-jobs` turns its tracing cache off (`src/cli/jobs.rs:227`) and an emptied cache matched warm runs, so the shared writable cache of #255, and the poisoning risk Mic92 raised about it for a service that evaluates outside contributors' pull requests, buy nothing here.
- **Boundary**: vendored versus first-party. nixbot is vendored; only the first-party override at `nixbot.nix:259-261` changes, through the option nixbot already exposes.
- **Alternatives considered**: #255's `evalCommand` (unmerged, conflicting); ScottyLabs' fork with a shared cache at `/var/lib/nixbot/eval-cache` (brainstorm F8).

### D3: A minimal package exposing iets as `nix-eval-jobs`, with nixbot's Nix grafted on
- **Choice**: a first-party derivation named `nix-eval-jobs-iets-<version>` whose `bin/nix-eval-jobs` is a symlink to `${iets}/bin/iets` (the default package of the `iets` flake input), with `passthru = { pname = "nix-eval-jobs"; evaluator = "iets"; version = iets.version; nix = options.services.nixbot.packages.nix-eval-jobs.default.nix; }`. `pname` stays `nix-eval-jobs` so the lock module's guard against unwrapped evaluators, which selects packages by that name (`modules/nixos/nix-eval-lock.nix:53-55`), still sees this package if it ever reaches a PATH unwrapped.
- **Rationale**: the lock wrapper requires `version` and forwards `nix` only if present (`modules/lib/nix-eval-lock.nix:43-49`); nixbot puts `packages.nix-eval-jobs.nix` on its unit PATH (upstream `nixosModules/nixbot.nix:1155-1158`) and links its own package against it (`packages/nixbot.nix:56`); the grafted `nix` is the same derivation the stock package carries, so the patched nix CLI on the unit PATH, the nixbot package, and the lock module's `isWrapped` drvPath comparison (`modules/nixos/nix-eval-lock.nix:56-57`) are unchanged. iets dispatches on `argv[0]`, so the classic name reaches `cmd_eval_jobs` (`src/cli/classic/mod.rs:45`).
- **Boundary**: source versus delivered. The flake input is upstream source; the derivation and its symlink are first-party and are what lands on the unit PATH. The verification is by `nix eval`/`nix build` of magnetite's configuration and a read of the unit PATH on magnetite, never by reading the source.
- **Alternatives considered**: iets' `classic` package grafted with `.nix` (rejected by the operator: it bundles a second Nix closure and shims four other command names, and it is Linux-only); the plain `iets` package (fails at run time: no `bin/nix-eval-jobs`).

### D4: The `iets` flake input carries no `follows`
- **Choice**: `inputs.iets.url = "github:numtide/iets"`, locked at `9157ca1a` or later, with no `inputs.nixpkgs.follows`.
- **Rationale**: the repository's rule against redirecting an upstream input's nixpkgs; the unredirected build is substituted from cache.numtide.com (the benchmark's `/nix/store/jk7bh7cc…-iets-0.2.0`), which is already a fleet substituter (`lib/caches.nix:8`, key at `:21`).
- **Alternatives considered**: `follows = "nixpkgs"` (a local Rust build and an untested toolchain combination).

### D5: One host-side producer of the evaluation record: a fifth nixbot patch
- **Choice**: a patch beside the four at `nixbot.nix:277-286` makes nixbot's evaluation runner, after the evaluator exits and before it removes the evaluation cgroup, log one JSON line through nixbot's own logger (`log.py:25-43`, which writes JSON to the journal) with message `evaluation finished` and the fields of D6. The lock wrapper is untouched.
- **Rationale**: this supersedes the operator's 2026-11-18 wording that the nixEvalLock wrapper emits the record; read at nixbot 171a8c77 the wrapper cannot:
  - it runs inside bubblewrap built with `--unshare-all` and binds only `SANDBOX_ETC_PATHS`, the store, the store database, the daemon socket, the worktree and the gc-roots directory (`nix_eval.py:221-304`), so neither `/run` (the journald socket) nor `/sys` (`memory.peak`, `memory.events`, `cpu.stat`) is visible, and `extra_ro_paths` is hard-coded to the repository clone (`build_run.py:217`);
  - it `exec`s the evaluator (`nix-eval-lock.sh`, last line), so nothing of it is left to write after the evaluator exits;
  - the evaluation cgroup is nixbot's: it creates it and sets `memory.max` (`nix_eval.py:379-386`), reads `memory.events` (`:535-548`) and deletes it right after the run (`:614-615`).
  The producer sits where the cgroup, the exit status, the evaluator's stderr and the journal are all reachable. Main relayed the operator's choice of this option on 2026-11-18.
- **Boundary**: vendored versus first-party. The patch is first-party code carried against vendored nixbot, pinned like the four existing patches; it is written against upstream's structure and naming so it can be offered to Mic92/nixbot (a follow-up, not a task here).
- **Alternatives considered**: (B) keep the producer in the wrapper by turning `exec` into fork-and-wait and patching nixbot to bind the journald socket and the evaluation cgroup into the sandbox (the cgroup namespace hides the path, so nixbot would have to pass it): still a nixbot patch, and it changes the lock's documented lifetime; (C) the wrapper records what it can see and the patch adds the cgroup fields: two producers per evaluation to join.

### D6: The record's fields come from the evaluation cgroup and nixbot's own state
- **Choice**: the record carries `build_id`, `ts` (the `ts` nixbot's JSON formatter stamps on every line, `log.py:27-28`, written as soon as the evaluator has exited, so the patch passes no `ts` of its own), `evaluator` and `evaluator_version` (from the unit environment value `NIXBOT_EVALUATOR=<evaluator> <version>`, which the module sets from the wrapped package's `unwrapped.evaluator or "nix-eval-jobs"` and `version`), `workers` and `max_memory_mib` (nixbot's settings), `memory_max_bytes`, `memory_peak_bytes`, `oom_kill` (the cgroup's `memory.max`, `memory.peak` and `memory.events` `oom_kill`), `wall_ms` (nixbot's existing monotonic measurement), `user_ms` and `system_ms` (the cgroup's `cpu.stat` `user_usec` and `system_usec`), `budget_kills` and `worker_kills` (counts of the two `nix-eval-jobs` stderr messages `memory budget of … exceeded … killing worker` and `evaluation worker … was killed (system out of memory?)`, `src/nix-eval-jobs.cc:322-327,493-497`, counted as nixbot reads stderr), and `exit_status`. It carries no stderr text. When nixbot ran the evaluation without its own cgroup (the limiter's fallback, `nix_eval.py:582-596`), the cgroup fields are absent rather than zero.
- **Rationale**: every field comes from a source that is the same whichever evaluator runs, so the baseline and the iets weeks are comparable; `cpu.stat`'s core counters exist in every cgroup v2 directory, so CPU time is the evaluation's alone, not nixbot's children in general (magnetite's `nixbot.service` cgroup has `cpu.stat` and `memory.peak`, read 2026-11-18, kernel 6.18.60). Under iets the kill counters stay zero, and a killed worker shows as a failed run with `oom_kill > 0` (A144). Recording no text keeps the `devloop-collection` free-text requirement.
- **Alternatives considered**: probing `nix-eval-jobs --version` at startup for the evaluator identity (iets' classic `--version` output is unverified); `getrusage(RUSAGE_CHILDREN)` deltas (nixbot runs other children concurrently).

### D7: The record enters the dev-loop history as `devloop.eval_run`
- **Choice**: `eval_run` joins `flake.lib.otelCollectorSchema.devloop.tables` with key `build_id` and time index `ts`, gets its pipeline and table statement rendered from that allow-list like the other four, and is fed by a `journald/nixbot-eval` receiver on `nixbot.service` that greps `"msg": "evaluation finished"`, parses `body.MESSAGE` as JSON and retains the allow-listed keys, like `journald/gitea-mq`. `devloop-reconcile` gains a daily comparison of the previous UTC day's `eval_run` rows with nixbot's journal lines. The `devloop` view gains charts of `memory_peak_bytes` against `memory_max_bytes` and of `wall_ms` per evaluation, split by evaluator.
- **Rationale**: reuses the one journald-to-table path, the single allow-list, the reconcile the gap requirement already demands for every kind of dev-loop record, and the committed view.
- **Alternatives considered**: a metrics series through Prometheus scrape (no per-evaluation identity, and nixbot's `/metrics` has no such gauge); a separate database (another TTL and exporter for one table).

### D8: Order of operations, and what each gate needs
- **Choice**: (1) the record under stock `nix-eval-jobs`, then one week of baseline at 6 × 3072; (2) a canary of the D3 package inside nixbot's real sandbox, on magnetite, run through nixbot itself against pinned commits, comparing every attribute's derivation with the stock evaluator's for the same commit; (3) the switch at 6 × 3072; (4) a tuning decision from the switched week's records. Each gate is the operator's, recorded with the numbers it rests on.
- **Rationale**: the operator's order; the switch must be judged against a baseline measured by the same producer.
- **Alternatives considered**: switching straight after the benchmark (the benchmark skipped the sandbox, the classic name and the uncovered cache states).

### D9: Accepting whole-evaluation failure on a killed worker is conditional
- **Choice**: iets stays as nixbot's evaluator only if, through the canary and the first switched week, every evaluation's `memory_peak_bytes` stays at or below 90 % of `memory_max_bytes` and below the service's 20 GiB `MemoryHigh`, and no evaluation records `oom_kill > 0`; otherwise nixbot reverts to the stock package and the gate's record says why. An upstream issue asks iets to retry killed workers alone, as `nix-eval-jobs` ≥ 2.35.3 does.
- **Rationale**: the operator accepts B2 only with comfortable headroom. 90 % of the 21 GiB ceiling is 18.9 GiB, about the 2026-09 nix-eval-jobs peak and inside the benchmark's iets range, so the threshold is tight enough to bind; the operator may restate it at the gate, with the measurements.
- **Alternatives considered**: lowering `--max-memory-size` pre-emptively (rejected by Q2); making the switch wait for an upstream retry (no date).

### D10: Memory tuning is a recorded decision, not a default
- **Choice**: after the first switched week the operator decides whether to change `evalMaxMemorySize` or `evalWorkerCount`, recording the decision in `modules/nixos/nixbot.nix`'s comment table beside the 2026-09 measurements, with the week's peaks, wall times and kill counts cited from `devloop.eval_run`.
- **Rationale**: Q2 as revised; the existing table at `nixbot.nix:117-138` is where readers look for why the numbers are what they are.

## Risks / Trade-offs

- [Risk] A worker killed for memory fails the whole iets evaluation, and nixbot reports `EvalOOMError` as permanent (`nix_eval.py:676-689`), while the lock's `oom_score_adj 900` makes the evaluator the kernel's first victim → Mitigation: D9's headroom gate on recorded peaks, the revert path, and the upstream issue. magnetite's kill-order assertion keeps passing under iets because it reads the script; the change states this in the assertion's comment rather than leaving its premise silently false.
- [Risk] iets' peak runs 1-2.5 GiB above `nix-eval-jobs`', near `MemoryHigh = 20G`, where throttling made two-system evaluations crawl in 2026-09 → Mitigation: the record's `memory_peak_bytes` against `memory_max_bytes` and the 20 GiB line in the chart; the gate in D9.
- [Risk] iets diverges from Nix 2.35.6 on some expression the benchmark did not exercise (its parity target is 2.34.8; the README calls it "LLM-ware") → Mitigation: the canary's per-attribute derivation comparison over pinned commits including a failing evaluation; nixbot's own `nixbot/nix-build` would fail on a wrong derivation that does not build, but a different derivation that builds is silent, which the canary is there to catch.
- [Risk] R1: iets never reads the flake's `nixConfig`, so on a host whose daemon lacks the fleet's caches its `cacheStatus` loses them → Mitigation: iets runs only in nixbot on magnetite, whose daemon is configured from `lib/caches.nix` (A143).
- [Risk] The canary's `cached` and `notBuilt` states are the first exercise of iets' cache-status path through the daemon from inside bwrap → Mitigation: the canary covers both explicitly.
- [Risk] `eval_alloc_bytes` and per-attribute `eval_wall_ms` change meaning at the switch → Mitigation: the chart splits by evaluator, and the switch's record names the date; dashboards comparing across the switch are labelled.
- [Risk] iets warns on every run that it ignores `plugin-files` and `accept-flake-config`, which nixbot stores as build warnings (`build_run.py:350-359`) → accepted as noise, recorded at the canary.
- [Risk] The patch adds a fifth carried patch on a fast-moving upstream file → Mitigation: it touches only the runner's tail and the stderr reader; a nixbot input bump that breaks it fails the nixbot package build; it is offered upstream.
- [Trade-off] Routine worker recycling is not counted (open question 1) → accepted; the memory peak and kill counts bound what matters for D9.
- [Trade-off] buildbot's and `nix-fast-build --remote`'s evaluations go unrecorded → accepted; they are out of scope and keep stock `nix-eval-jobs`.

## Migration Plan

1. Land the instrumentation (record patch, `NIXBOT_EVALUATOR`, `eval_run` table, receiver, reconcile comparison, chart) and deploy magnetite. This changes only magnetite's configuration; no other host's closure reads it.
2. Collect one week of baseline under `nix-eval-jobs` 2.35.4 at 6 × 3072; the operator records the week's summary (peak, median and maximum wall, kill counts).
3. Land the `iets` input and the D3 package as a separate, unused output; run the canary on magnetite inside nixbot's sandbox (task group 4) and record the comparison.
4. Operator gate: switch. Land the one-line override and deploy magnetite.
5. Collect the switched week; operator gate D9 (keep or revert) and D10 (tune or keep).
6. File the upstream iets issue at step 3 or earlier.

Rollback: revert the override line in `modules/nixos/nixbot.nix` (the stock package is `options.services.nixbot.packages.nix-eval-jobs.default`, still wrapped by the lock) and deploy magnetite. The record, its table and its chart stay.

## Open Questions

1. **Worker restart count.** Neither evaluator reports routine recycling at default verbosity: `nix-eval-jobs` logs worker creation at debug level only (`src/nix-eval-jobs.cc:65-66`), and iets reads the `restart` line silently (`src/jobs/collector.rs:144-147,243`), its `spawned` counter appearing only in the summary classic mode suppresses (`src/cli/jobs.rs:305-322`), with no worker event among its `IETS_EVENTS` groups (`src/events.rs:47-62`). Candidates, not chosen here: a debug-verbosity probe in the canary only; an upstream request for a summary line under the classic name.
2. **The D9 threshold.** 90 % of `memory.max` and below 20 GiB is this design's proposal; the operator confirms or restates it at the switch gate.
3. **The unexplained wall-time drop** across the benchmark's iets runs (59, 61, 46, 31, 30 s at flat user CPU). The record's `wall_ms` and `user_ms` under nixbot's real load answer it for practical purposes; no separate investigation is planned.
