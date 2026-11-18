# iets as nixbot's evaluator implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

<!--
Procedural note: the interactive `superpowers:writing-plans` handoff was not run; this plan was
written by the session that wrote tasks.md, following that skill's structure, and stops for
operator review before any apply. Task N here is tasks.md group N; Step N.M maps to task N.M
where the mapping is one to one.
-->

**Goal:** Record every nixbot evaluation in the dev-loop history, then, on measured evidence, switch nixbot's evaluator from its patched nix-eval-jobs to iets behind the same host evaluation lock.

**Architecture:** A fifth first-party nixbot patch logs one JSON `evaluation finished` line per evaluation from nixbot's runner, which alone can reach the evaluation cgroup and the journal; the collector's journald path copies it into `devloop.eval_run`, the reconcile checks it daily, and the dev-loop view charts it. A minimal package exposes iets' binary as `bin/nix-eval-jobs` with nixbot's own `nix` passthru grafted on, and one line selects it through the existing lock wrapper.

**Tech Stack:** nix flakes with flake-parts and import-tree; nixbot at `Mic92/nixbot@171a8c77` (Python, `nixbot/nixbot/nix_eval.py`, `build_run.py`, `log.py`); nix-eval-jobs 2.35.4; iets 0.2.0 (`numtide/iets@9157ca1a`); OpenTelemetry collector journald receiver; GreptimeDB 1.2.1 pipelines; Perses; clan deployment.

**Spec:** `openspec/changes/evaluate-nixbot-with-iets/` — `design.md` (D1–D10), `specs/build-service-evaluator`, `specs/build-service-evaluator-interface`, `specs/devloop-collection`, `specs/devloop-collection-interface`, `specs/fleet-dashboard`, `specs/world-assumptions` (A143–A147).

## Global Constraints

- nixbot only: no classic shim, no iets on any host PATH, no change to buildbot or developer machines (D1, Q3).
- No Mic92/nixbot#255, no `evalWritablePaths`, no shared or writable evaluation cache; nixbot's sandbox and argv unchanged (D2).
- The iets package is a symlink `bin/nix-eval-jobs -> ${iets}/bin/iets` with `passthru = { pname = "nix-eval-jobs"; evaluator = "iets"; version; nix = <stock>.nix; }`; never iets' `classic` package (D3, Q6).
- `inputs.iets` carries no `follows` (D4).
- The record's producer is the nixbot patch; `modules/lib/nix-eval-lock.sh` and `modules/lib/nix-eval-lock.nix` are not edited except the 5.2 comment (D5).
- `eval_run` fields exactly: `build_id`, `evaluator`, `evaluator_version`, `workers`, `max_memory_mib`, `memory_max_bytes`, `memory_peak_bytes`, `oom_kill`, `wall_ms`, `user_ms`, `system_ms`, `budget_kills`, `worker_kills`, `exit_status`, `ts`; key `build_id`; time `ts`; no evaluator text (D6, D7).
- 6 workers × 3072 MiB unchanged through the switch; tuning only by the operator's recorded decision (D8, D10, Q2).
- D9 gate: every evaluation ≤ 90 % of `memory.max` (≤ 19353 MiB of 21504) and below 20 GiB, with `oom_kill = 0`, through the canary and the first switched week, unless the operator restates it at 5.1.
- buildbot's and `nix-fast-build --remote`'s evaluations are not recorded.
- nix-managed outputs are verified by `nix eval`/`nix build` against `.#nixosConfigurations.magnetite`, `.#checks.x86_64-linux.*` and `.#vmTests.x86_64-linux.*`, or on magnetite after activation; never by reading source.
- Long or output-heavy commands: `<command> 2>&1 | tee logs/<identifier>-$(date +%Y%m%d-%H%M%S).log`.
- jj-colocated repository in a development join: route content to the owning chain with `jj squash --from @ --into <chain> --keep-emptied`; never `jj describe @`; the orchestrator commits and opens pull requests, each with `Part of CAM-111.`
- **[operator]** steps are presented through the `wizard` skill and stopped on.

## Grounding: the consumer's exact argument lists

The vendored consumer of the evaluator is nixbot at `171a8c77`. Any pre-switch run of iets must use the argv nixbot builds, not one chosen by hand:

- Evaluator argv, `build_eval_command` (`nixbot/nixbot/nix_eval.py:170-212`): `nix-eval-jobs --option extra-experimental-features "nix-command flakes" --option eval-cache false --workers 6 --max-memory-size 3072 --option accept-flake-config true --gc-roots-dir <gc_roots_dir> --force-recurse --check-cache-status --select <build_select_expr> --apply <APPLY_EXPR> --flake git+file://<worktree>?ref=HEAD&rev=<rev>`; `--eval-store daemon` only with `buildStore.url` and `--reference-lock-file` only when `lock_file != flake.lock`, neither set for vanixiets.
- Sandbox prefix, `build_sandbox_command` (`nix_eval.py:233-304`): `bwrap --unshare-all --share-net --die-with-parent --proc /proc --dev /dev --tmpfs /tmp --ro-bind /nix/store /nix/store --ro-bind /nix/var/nix/db /nix/var/nix/db --ro-bind <daemon socket> <daemon socket> --setenv NIX_REMOTE daemon --bind <gc_roots_dir> <gc_roots_dir> --bind <worktree> <worktree> --setenv HOME /tmp --chdir <worktree>`, then `--ro-bind` of each existing `SANDBOX_ETC_PATHS` entry (`/etc/nix`, `/etc/static`, `/etc/ssl`, `/etc/resolv.conf`, `/etc/hosts`, `/etc/passwd`, `/etc/group`, `/etc/nsswitch.conf`) and of the repository clone (`build_run.py:217`).
- Environment: `passthrough_env()` plus `CLICOLOR_FORCE=1`, the unit's `PATH` and `HOME` (`nix_eval.py:631-645`); the unit's `NIX_CONFIG = "allow-import-from-derivation = false"` (`modules/nixos/nixbot.nix:250`) passes through.
- The canary (Task 4) obtains both lists by calling the patched nixbot package's own `nixbot.nix_eval.build_full_command(worktree, BranchConfig.load(worktree), settings)` with magnetite's settings, and records the returned list; the benchmark of 2026-11-18 used `argv.json` from the same function but ran outside bwrap.

## Review Focus

- An evaluation that times out: the record must still be written, with `exit_status` reflecting the kill (Task 1 Step 2 timeout case).
- An evaluation nixbot ran without its own cgroup (limiter fallback): the cgroup fields absent, not zero, and the row still stored (Task 1 Step 2 no-cgroup case; Task 1 Step 8 fixture line without cgroup fields).
- Evaluator standard error carrying an attribute path or a secret-looking string in a kill message: nothing of it in the record (Task 1 Step 2 no-text case).
- A build evaluated twice (restart): two rows, distinct by `ts`, both reconciled (Task 1 Step 8 fixture with two lines for one `build_id`).
- The iets package's `nix` passthru drifting from the stock package's after a nixbot bump: the lock's `isWrapped` assertion fails at evaluation (Task 5 Step 3 covers the unwrapped mutant; Task 3 Step 2 asserts the drvPath equality).

---

### Task 1: Per-evaluation record

**Files:**
- Create: `modules/nixos/nixbot-evaluation-record.patch`
- Create: `modules/checks/nixbot-eval-record.nix`
- Modify: `modules/nixos/nixbot.nix:259-286` (patch list; `NIXBOT_EVALUATOR`)
- Modify: `modules/clan/services/otel-collector/schema.nix` (`devloop.tables.eval_run`)
- Modify: `modules/nixos/devloop-collection.nix` (`journald/nixbot-eval`, `logs/devloop-eval_run`, reconcile comparison)
- Modify: `modules/checks/devloop-queries.nix`, `modules/checks/devloop-queries/reconcile-fixtures.sql`, `modules/vm-tests/devloop-ingest.nix`
- Modify: `modules/nixos/perses/resources/dashboard-devloop.json`

**Interfaces:**
- Produces: the journal line `{"ts": "...Z", "level": "info", "logger": "nixbot.nix_eval", "msg": "evaluation finished", "build_id": int, "evaluator": str, "evaluator_version": str, "workers": int, "max_memory_mib": int, "memory_max_bytes"?: int, "memory_peak_bytes"?: int, "oom_kill"?: int, "wall_ms": int, "user_ms"?: int, "system_ms"?: int, "budget_kills": int, "worker_kills": int, "exit_status": int}` consumed by Steps 6–9 and Task 2; the environment value `NIXBOT_EVALUATOR="<evaluator> <version>"`, split on the first space.
- Produces: `devloop.eval_run` with the Global Constraints columns.

- [ ] **Step 1: Write the check first.** `checks.x86_64-linux.nixbot-eval-record` runs the patched `nixbot.nix_eval` runner with `sandbox = False` against a stub `nix-eval-jobs` script, a stand-in cgroup directory holding `memory.max`, `memory.peak`, `memory.events` and `cpu.stat` fixtures, and a captured `JsonFormatter` handler. Cases: `success` (exit 0, one line, `exit_status` 0, `memory_peak_bytes` equal to the fixture); `failure` (exit 1, one line, `exit_status` 1); `kills` (stub prints `memory budget of 18432 MiB exceeded (19000 MiB in use), killing worker 42 ('checks.x', 4000 MiB)` and `evaluation worker 43 was killed (system out of memory?)`; `budget_kills` 1, `worker_kills` 1, and no value contains `checks.x`); `timeout` (stub sleeps past a 1 s timeout; one line); `no-cgroup` (limiter absent; one line without the cgroup keys).
- [ ] **Step 2: Build it and see it fail** against the unpatched package. Run: `nix build .#checks.x86_64-linux.nixbot-eval-record`. Expected: FAIL, no `evaluation finished` line.
- [ ] **Step 3: Write the patch** against `171a8c77`: a kill counter in `_read_stderr_tail`'s `keep` (two `startswith`/`in` tests, no text retained), a `_record_evaluation(eval_cgroup, settings, build_id, returncode, duration_ms, kills)` called from `_spawn` on every exit path before `run`'s `finally` cleanup, reading the four cgroup files, and `build_id` threaded from `build_run.py` through `EvalSettings`. Add it to `services.nixbot.packages.nixbot`'s patch list.
- [ ] **Step 4: Run the check.** Expected: PASS; then the three mutants of tasks.md 1.3 each FAIL their case. Logs under `logs/`.
- [ ] **Step 5: `NIXBOT_EVALUATOR`.** In `modules/nixos/nixbot.nix`: `systemd.services.nixbot.environment.NIXBOT_EVALUATOR = let p = config.services.nixbot.packages.nix-eval-jobs; in "${p.unwrapped.evaluator or "nix-eval-jobs"} ${p.version}";`. Run: `nix eval --raw .#nixosConfigurations.magnetite.config.systemd.services.nixbot.environment.NIXBOT_EVALUATOR`. Expected: `nix-eval-jobs 2.35.4`.
- [ ] **Step 6: Allow-list.** Add `eval_run` to `devloop.tables` (`build_id` int64, `evaluator` string, `evaluator_version` string, `workers` int64, `max_memory_mib` int64, `memory_max_bytes` int64, `memory_peak_bytes` int64, `oom_kill` int64, `wall_ms` int64, `user_ms` int64, `system_ms` int64, `budget_kills` int64, `worker_kills` int64, `exit_status` int64, time index `ts`; key `build_id`). Run: `nix eval --json .#lib.otelCollectorSchema.devloop.tables.eval_run`. Expected: those columns in that order.
- [ ] **Step 7: Receiver and pipeline.** `journald/nixbot-eval` with `units = [ "nixbot.service" ]`, `grep = ''"msg": "evaluation finished"''`, the gitea-mq receiver's `journalctl_path`, `start_at = "beginning"`, `storage = "file_storage"`, operators `json_parser` on `body.MESSAGE`, `retain` from the allow-list, body removal; pipeline `logs/devloop-eval_run` as the other four. Run: `nix build .#checks.x86_64-linux.otel-collector-config`. Expected: PASS.
- [ ] **Step 8: Reconcile and container test.** Add the `eval_run` comparison to `devloop-reconcile` and its fixture to `reconcile-fixtures.sql`; add the stub `nixbot.service` (two `evaluation finished` lines for one `build_id`, one without cgroup keys, one `starting evaluation` line), the evaluation case and the two mutants to `devloop-ingest`. Run: `nix build .#checks.x86_64-linux.devloop-queries` and `nix build .#vmTests.x86_64-linux.devloop-ingest` on magnetite. Expected: PASS; each mutant FAILS as the interface scenarios state.
- [ ] **Step 9: Charts.** Two panels in `dashboard-devloop.json` over `devloop.eval_run`: `memory_peak_bytes` and `memory_max_bytes` by `ts`, series per `evaluator`, with a 21474836480 threshold line; `wall_ms` by `ts` per `evaluator`. Run: the `perses-lint` check and the Perses container runtime test. Expected: PASS.
- [ ] **Step 10: Commit** onto this change's implementation chain: `feat(nixbot): record every evaluation in the dev-loop history`.

### Task 2: Land and baseline

**Interfaces:**
- Consumes: Task 1's record and table.
- Produces: `logs/cam-111-baseline-<date>.md`, consumed by Task 5 Step 1.

- [ ] **Step 1:** land through nixbot and gitea-mq (tasks.md 2.1).
- [ ] **Step 2:** deploy magnetite and attribute every post since the deploy (tasks.md 2.2).
- [ ] **Step 3:** compare journal line counts with `eval_run` rows and read one row (tasks.md 2.3); expected `memory_max_bytes = 22548578304`.
- [ ] **Step 4:** read the first reconcile log (tasks.md 2.4).
- [ ] **Step 5 [operator, wizard]:** after seven days, write the baseline (tasks.md 2.5) from `SELECT date_trunc('day', ts), count(*), max(memory_peak_bytes), approx_percentile_cont(memory_peak_bytes, 0.5), max(wall_ms), approx_percentile_cont(wall_ms, 0.5), sum(budget_kills), sum(worker_kills), sum(oom_kill), sum(exit_status <> 0) FROM devloop.eval_run GROUP BY 1 ORDER BY 1`.

### Task 3: The iets package, unused

**Files:**
- Modify: `flake.nix`, `flake.lock`
- Create: `modules/lib/nix-eval-jobs-iets.nix` (a `flake.lib.mkNixEvalJobsIets pkgs iets stock` function)

**Interfaces:**
- Produces: `flake.lib.mkNixEvalJobsIets : pkgs -> iets -> stock -> derivation`, where `stock` is `options.services.nixbot.packages.nix-eval-jobs.default`; consumed by Task 4 Step 3 and Task 5 Step 2.

- [ ] **Step 1:** add `inputs.iets.url = "github:numtide/iets";` and run `nix flake lock --update-input iets`. Expected: `nix flake metadata --json | jq -r '.locks.nodes.iets.locked.rev'` is `9157ca1a…` or later, and `.locks.nodes.iets.inputs.nixpkgs` names iets' own node.
- [ ] **Step 2:** write `mkNixEvalJobsIets` as `pkgs.runCommand "nix-eval-jobs-iets-${iets.version}" { passthru = { pname = "nix-eval-jobs"; evaluator = "iets"; inherit (iets) version; inherit (stock) nix; }; meta.mainProgram = "nix-eval-jobs"; } "mkdir -p $out/bin && ln -s ${lib.getExe' iets "iets"} $out/bin/nix-eval-jobs"`. Verify per tasks.md 3.2: `ls` of `bin/`, `nix path-info -r` without a second Nix, and `nix eval` of `passthru.nix.drvPath` equal to the stock's.
- [ ] **Step 3 [operator, wizard]:** the upstream iets issue (tasks.md 3.3).
- [ ] **Step 4: Commit:** `feat(nixbot): package iets as nix-eval-jobs for nixbot`.

### Task 4: Canary inside nixbot's sandbox

**Files:**
- Create: `scripts/nixbot-eval-canary.py` (run on magnetite only; reads nixbot's own argv builders)

**Interfaces:**
- Consumes: `flake.lib.mkNixEvalJobsIets`; the lock wrapper `config.services.nixEvalLock.wrap`.
- Produces: `logs/cam-111-canary-<ts>/{<commit>-{stock,iets}.jsonl,.stderr,.scope}` and `comparison.log`, consumed by Task 5 Step 1.

- [ ] **Step 1:** choose the four commits and record why each qualifies (tasks.md 4.1). For the cached commit, confirm with `nix path-info --store https://cache.scientistexperience.net <out>` succeeding and `nix path-info <out>` failing on magnetite before the run.
- [ ] **Step 2:** write `nixbot-eval-canary.py <commit> <evaluator-bin-dir>`: as the `nixbot` user, create a detached worktree of the clone, build `EvalSettings` from `/run/nixbot` configuration values (6, 3072, `systemd_scope=False`, `sandbox=True`), call `build_full_command`, write the argv to the log header, and run it with `PATH=<evaluator-bin-dir>:<unit PATH>` under `systemd-run --scope -p MemoryAccounting=yes --expand-environment=no`, capturing stdout, stderr, `memory.peak` and `cpu.stat`.
- [ ] **Step 3:** run the four commits with the stock wrapper and then the iets wrapper, never concurrently, each behind `/etc/nix/eval.lock` (tasks.md 4.3).
- [ ] **Step 4:** compare per attribute (tasks.md 4.4) with `jq -S` on `{attr, drvPath, outputs, system, cacheStatus, error: (has("error"))}` sorted by `attr`. Expected: zero differences; `local`, `cached`, `notBuilt` each present.
- [ ] **Step 5:** record memory, time and warnings in verify.md (tasks.md 4.5).

### Task 5: Switch

**Files:**
- Modify: `modules/nixos/nixbot.nix:252-261`
- Modify: `modules/lib/nix-eval-lock.sh` (OOM paragraph comment only), `modules/machines/nixos/magnetite/default.nix` (kill-order assertion comment only)

- [ ] **Step 1 [operator, wizard]:** the switch decision and D9 threshold (tasks.md 5.1).
- [ ] **Step 2:** replace `options.services.nixbot.packages.nix-eval-jobs.default` inside `config.services.nixEvalLock.wrap (...)` with `(config.flake.lib.mkNixEvalJobsIets pkgs inputs.iets.packages.${pkgs.system}.default options.services.nixbot.packages.nix-eval-jobs.default)` on one line; amend the two comments. Verify per tasks.md 5.2.
- [ ] **Step 3:** the unwrapped mutant fails magnetite's evaluation (tasks.md 5.3).
- [ ] **Step 4:** land, deploy, attribute posts, read the unit PATH (tasks.md 5.4).
- [ ] **Step 5:** read the first `eval_run` row naming `iets` (tasks.md 5.5).
- [ ] **Step 6: Commit:** `feat(nixbot): evaluate with iets`.

### Task 6: First week and tuning

- [ ] **Step 1 [operator, wizard]:** the D9 gate over the canary and the week (tasks.md 6.1), with Task 2 Step 5's query restricted to `evaluator = 'iets'`.
- [ ] **Step 2 [operator, wizard]:** the D10 decision recorded in the comment table (tasks.md 6.2).

### Task 7: Integration verification

- [ ] **Step 1:** per-evaluator counts against the journal across the switch (tasks.md 7.1).
- [ ] **Step 2:** restart one pre-switch build and compare `ci_attribute.drv_path` per `attr` (tasks.md 7.2).
- [ ] **Step 3:** the rollback rehearsal in a scratch copy (tasks.md 7.3).
- [ ] **Step 4 [operator]:** the dev-loop view across the switch (tasks.md 7.4).
- [ ] **Step 5:** archive preparation (tasks.md 7.5).
