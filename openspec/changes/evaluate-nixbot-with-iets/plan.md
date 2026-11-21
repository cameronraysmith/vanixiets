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

**Spec:** `openspec/changes/evaluate-nixbot-with-iets/` — `design.md` (D1–D11), `specs/build-service-evaluator`, `specs/build-service-evaluator-interface`, `specs/devloop-collection`, `specs/devloop-collection-interface`, `specs/fleet-dashboard`, `specs/world-assumptions` (A143–A147, A153).

## Global Constraints

- nixbot only: no classic shim, no iets on any host PATH, no change to buildbot or developer machines (D1, Q3).
- No Mic92/nixbot#255, no `evalWritablePaths`, no shared or writable evaluation cache; nixbot's sandbox and argv unchanged (D2).
- The iets package is a symlink `bin/nix-eval-jobs -> ${iets}/bin/iets` with `passthru = { pname = "nix-eval-jobs"; evaluator = "iets"; version; nix = <stock>.nix; }`; never iets' `classic` package (D3, Q6).
- `inputs.iets` carries no `follows` (D4).
- The record's producer is the nixbot patch; `modules/lib/nix-eval-lock.sh` and `modules/lib/nix-eval-lock.nix` are not edited except the 5.2 comment (D5).
- `eval_run` fields exactly: `build_id`, `evaluator`, `evaluator_version`, `workers`, `max_memory_mib`, `memory_max_bytes`, `memory_peak_bytes`, `oom_kill`, `wall_ms`, `user_ms`, `system_ms`, `budget_kills`, `worker_kills`, `exit_status`, `ts`; key `build_id`; time `ts`; no evaluator text (D6, D7).
- 6 workers × 3072 MiB unchanged through the switch; tuning only by the operator's recorded decision (D8, D10, Q2).
- D9 capacity trigger, not a verdict: an evaluation above 90 % of its own `memory_max_bytes` (the per-evaluation ceiling nixbot sets, at least 21504 MiB and higher when the host can spare more, so at least 19353 MiB) or at 20 GiB, or any `oom_kill > 0`, opens an operator capacity decision taken in order of cost: (a) tune the evaluator, (b) reclaim memory on magnetite (ARC cap, zram, per-service limits), (c) move non-CI services off magnetite (fleet-topology initiative), (d) resize magnetite; (c) and (d) are the operator's, outside this change. The one-line revert is only the safety valve for a failing or broken evaluation.
- magnetite memory budget (D11): ARC, swap use, available memory, OOM kills and large processes are already stored and are not re-added; the probe adds only `vanixiets_unit_memory_current_bytes`, `vanixiets_unit_memory_peak_bytes` (systemd `MemoryCurrent`/`MemoryPeak` for `memoryBudgetUnits`, `system.slice`, `user.slice`) and `vanixiets_zram_orig_data_bytes`, `vanixiets_zram_compr_data_bytes`, `vanixiets_zram_mem_used_bytes`.
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
- Modify: `modules/clan/services/otel-collector/schema.nix` (`memoryBudgetUnits`, `nodeExporterKeep`)
- Create: `modules/nixos/magnetite-memory-budget.nix` (probe service, timer, node_exporter `textfile` collector, assertions; imported by magnetite only)

**Interfaces:**
- Produces: the journal line `{"ts": "...Z", "level": "info", "logger": "nixbot.nix_eval", "msg": "evaluation finished", "build_id": int, "evaluator": str, "evaluator_version": str, "workers": int, "max_memory_mib": int, "memory_max_bytes"?: int, "memory_peak_bytes"?: int, "oom_kill"?: int, "wall_ms": int, "user_ms"?: int, "system_ms"?: int, "budget_kills": int, "worker_kills": int, "exit_status": int}` consumed by Steps 6–9 and Task 2; the environment value `NIXBOT_EVALUATOR="<evaluator> <version>"`, split on the first space.
- Produces: `devloop.eval_run` with the Global Constraints columns.
- Produces: `memory-budget.prom` lines `vanixiets_unit_memory_current_bytes{unit="<unit>"} <int>`, `vanixiets_unit_memory_peak_bytes{unit="<unit>"} <int>`, `vanixiets_zram_orig_data_bytes <int>`, `vanixiets_zram_compr_data_bytes <int>`, `vanixiets_zram_mem_used_bytes <int>`, consumed by Step 12 and Task 2.

- [ ] **Step 1: Write the check first.** `checks.x86_64-linux.nixbot-eval-record` runs the patched `nixbot.nix_eval` runner with `sandbox = False` against a stub `nix-eval-jobs` script, a stand-in cgroup directory holding `memory.max`, `memory.peak`, `memory.events` and `cpu.stat` fixtures, and a captured `JsonFormatter` handler. Cases: `success` (exit 0, one line, `exit_status` 0, `memory_peak_bytes` equal to the fixture); `failure` (exit 1, one line, `exit_status` 1); `kills` (stub prints `memory budget of 18432 MiB exceeded (19000 MiB in use), killing worker 42 ('checks.x', 4000 MiB)` and `evaluation worker 43 was killed (system out of memory?)`; `budget_kills` 1, `worker_kills` 1, and no value contains `checks.x`); `timeout` (stub sleeps past a 1 s timeout; one line); `no-cgroup` (limiter absent; one line without the cgroup keys).
- [ ] **Step 2: Build it and see it fail** against the unpatched package. Run: `nix build .#checks.x86_64-linux.nixbot-eval-record`. Expected: FAIL, no `evaluation finished` line.
- [ ] **Step 3: Write the patch** against `171a8c77`: a kill counter in `_read_stderr_tail`'s `keep` (two `startswith`/`in` tests, no text retained), a `_record_evaluation(eval_cgroup, settings, build_id, returncode, duration_ms, kills)` called from `_spawn` on every exit path before `run`'s `finally` cleanup, reading the four cgroup files, and `build_id` threaded from `build_run.py` through `EvalSettings`. Add it to `services.nixbot.packages.nixbot`'s patch list.
- [ ] **Step 4: Run the check.** Expected: PASS; then the three mutants of tasks.md 1.3 each FAIL their case. Logs under `logs/`.
- [ ] **Step 5: `NIXBOT_EVALUATOR`.** In `modules/nixos/nixbot.nix`: `systemd.services.nixbot.environment.NIXBOT_EVALUATOR = let p = config.services.nixbot.packages.nix-eval-jobs; in "${p.unwrapped.evaluator or "nix-eval-jobs"} ${p.version}";`. Run: `nix eval --raw .#nixosConfigurations.magnetite.config.systemd.services.nixbot.environment.NIXBOT_EVALUATOR`. Expected: `nix-eval-jobs 2.35.4`.
- [ ] **Step 6: Allow-list.** Add `eval_run` to `devloop.tables` (`build_id` int64, `evaluator` string, `evaluator_version` string, `workers` int64, `max_memory_mib` int64, `memory_max_bytes` int64, `memory_peak_bytes` int64, `oom_kill` int64, `wall_ms` int64, `user_ms` int64, `system_ms` int64, `budget_kills` int64, `worker_kills` int64, `exit_status` int64, time index `ts`; key `build_id`). Run: `nix eval --json .#lib.otelCollectorSchema.devloop.tables.eval_run`. Expected: those columns in that order.
- [ ] **Step 7: Receiver and pipeline.** `journald/nixbot-eval` with `units = [ "nixbot.service" ]`, `grep = ''"msg": "evaluation finished"''`, the gitea-mq receiver's `journalctl_path`, `start_at = "beginning"`, `storage = "file_storage"`, operators `json_parser` on `body.MESSAGE`, `retain` from the allow-list, body removal; pipeline `logs/devloop-eval_run` as the other four. Run: `nix build .#checks.x86_64-linux.otel-collector-config`. Expected: PASS.
- [ ] **Step 8: Reconcile and container test.** Add the `eval_run` comparison to `devloop-reconcile` and its fixture to `reconcile-fixtures.sql`; add the stub `nixbot.service` (two `evaluation finished` lines for one `build_id`, one without cgroup keys, one `starting evaluation` line), the evaluation case and the two mutants to `devloop-ingest`. Run: `nix build .#checks.x86_64-linux.devloop-queries` and `nix build .#vmTests.x86_64-linux.devloop-ingest` on magnetite. Expected: PASS; each mutant FAILS as the interface scenarios state.
- [ ] **Step 9: Charts.** Two panels in `dashboard-devloop.json` over `devloop.eval_run`: `memory_peak_bytes` and `memory_max_bytes` by `ts`, series per `evaluator`, with a 21474836480 threshold line; `wall_ms` by `ts` per `evaluator`. Run: the `perses-lint` check and the Perses container runtime test. Expected: PASS.
- [ ] **Step 10: Budget allow-list.** Add `memoryBudgetUnits` (the D11 list) and the five names to `nodeExporterKeep` in `schema.nix`. Run: `nix eval --json .#lib.otelCollectorSchema.memoryBudgetUnits` and `.nodeExporterKeep`. Expected: the D11 units; the keep-list with the five names after the existing nine.
- [ ] **Step 11: Budget probe, test first.** Write a fixture of recorded `systemctl show -p Id -p ActiveState -p MemoryCurrent -p MemoryPeak` output (one active unit, one inactive, one `[not set]`, one `omnigent-host-cameron.service`) and an `mm_stat` line, and a check that the probe's `format_budget(show_output, mm_stat, aliases) -> str` emits exactly the expected `.prom` text (alias applied, no line for the inactive or `[not set]` unit); see it fail; implement the probe as a `writeShellApplication` (or `writers.writePython3Bin`) with that function, the service and 60 s timer writing by write-then-rename, magnetite's node_exporter `--collector.textfile.directory`, and the two assertions of tasks.md 1.11; run the check, `otel-collector-config` and magnetite's `system.build.toplevel` evaluation, then the keep-list mutant. Expected: PASS, PASS, evaluates, mutant FAILS on the assertion.
- [ ] **Step 12: Budget chart.** A panel in `dashboard-devloop.json` through the PromQL datasource beside Step 9's: `sum by (unit) (vanixiets_unit_memory_current_bytes{host_name="magnetite", unit!~".*\\.slice"})` stacked, `node_zfs_arc_size{host_name="magnetite"}` and `vanixiets_zram_mem_used_bytes{host_name="magnetite"}`, with `node_zfs_arc_c_max` as a line. Run: `perses-lint` and the Perses container runtime test. Expected: PASS.
- [ ] **Step 13: Commit** onto this change's implementation chain: `feat(nixbot): record every evaluation and magnetite's memory budget`.

### Task 2: Land and baseline

**Interfaces:**
- Consumes: Task 1's record and table.
- Produces: `logs/cam-111-baseline-<date>.md`, consumed by Task 5 Step 1.

- [ ] **Step 1:** land through nixbot and gitea-mq (tasks.md 2.1).
- [ ] **Step 2:** deploy magnetite and attribute every post since the deploy (tasks.md 2.2).
- [ ] **Step 3:** compare journal line counts with `eval_run` rows and read one row (tasks.md 2.3); expected `memory_max_bytes` at least 22548578304 (the 21504 MiB worker budget), higher when the host could spare more when the evaluation started.
- [ ] **Step 4:** read the first reconcile log (tasks.md 2.4).
- [ ] **Step 5:** confirm the budget series on magnetite and in `fleet` (tasks.md 2.5).
- [ ] **Step 6 [operator, wizard]:** before the switch, summarise the stock records collected since 2026-11-18T23:18Z, with no gate (tasks.md 2.6, design D13 as revised by Q69), from `SELECT date_trunc('day', ts), count(*), max(memory_peak_bytes), approx_percentile_cont(memory_peak_bytes, 0.5), max(wall_ms), approx_percentile_cont(wall_ms, 0.5), sum(budget_kills), sum(worker_kills), sum(oom_kill), sum(exit_status <> 0) FROM devloop.eval_run GROUP BY 1 ORDER BY 1`, and for the budget `max_over_time(vanixiets_unit_memory_current_bytes{host_name="magnetite"}[<window>])` by `unit`, `max_over_time(node_zfs_arc_size{host_name="magnetite"}[<window>])` with `node_zfs_arc_c_max`, `max_over_time(vanixiets_zram_mem_used_bytes{host_name="magnetite"}[<window>])` and `max_over_time(sum(system_paging_usage_bytes{host_name="magnetite",state="used"})[<window>:1m])`, leaving out the replay's windows (03:48–05:42Z and 05:46–05:58Z on 2026-11-19).

### Task 3: The iets package, unused

**Files:**
- Modify: `flake.nix`, `flake.lock`
- Create: `modules/lib/nix-eval-jobs-iets.nix` (a `flake.lib.mkNixEvalJobsIets pkgs iets stock` function)

**Interfaces:**
- Produces: `flake.lib.mkNixEvalJobsIets : pkgs -> iets -> stock -> derivation`, where `stock` is `options.services.nixbot.packages.nix-eval-jobs.default`; consumed by Task 4 Step 3 and Task 5 Step 2.

- [ ] **Step 1:** add `inputs.iets.url = "github:numtide/iets";` and run `nix flake lock --update-input iets`. Expected: `nix flake metadata --json | jq -r '.locks.nodes.iets.locked.rev'` is `9157ca1a…` or later, and `.locks.nodes.iets.inputs.nixpkgs` names iets' own node.
- [ ] **Step 2:** write `mkNixEvalJobsIets` as `pkgs.runCommand "nix-eval-jobs-iets-${iets.version}" { passthru = { pname = "nix-eval-jobs"; evaluator = "iets"; inherit (iets) version; inherit (stock) nix; }; meta.mainProgram = "nix-eval-jobs"; } "mkdir -p $out/bin && ln -s ${lib.getExe' iets "iets"} $out/bin/nix-eval-jobs"`. Verify per tasks.md 3.2: `ls` of `bin/`, `nix path-info -r` without a second Nix, and `nix eval` of `passthru.nix.drvPath` equal to the stock's.
- [ ] **Step 3:** a check that the package exposes what nixbot and the lock need (`bin/nix-eval-jobs`, `passthru.nix` equal to the stock's, `evaluator = "iets"`, `pname = "nix-eval-jobs"`) and that the lock wraps it, with a mutant per property (tasks.md 3.3). Nothing is filed upstream to iets (design D12).
- [ ] **Step 4: Commit:** `feat(nixbot): package iets as an evaluator, not selected`.

### Task 4: Canary: the paired replay inside nixbot's sandbox

**Files:**
- Create: `scripts/nixbot-eval-canary.py` (run on magnetite only; reads nixbot's own argv builders)

**Interfaces:**
- Consumes: `config.vanixiets.nixbot.ietsEvaluator` (built by `flake.lib.mkNixEvalJobsIets`); the lock wrapper `config.services.nixEvalLock.wrap`.
- Produces: `logs/cam-111-canary-<ts>/{<commit>-{stock,iets}.jsonl,.stderr,.scope}`, each run's start and end, and `comparison.log`, consumed by Task 2 Step 6 (excluded windows) and Task 5 Step 1.

- [ ] **Step 1:** choose the replay set of design D13 and record why each commit qualifies (tasks.md 4.1): the five largest `memory_peak_bytes` and the five largest `wall_ms` from `devloop.eval_run`, each build's commit from `devloop.ci_attribute`'s `commit_sha` on the same `build_id`, the latest flake-update commit, the four cache-state and failure commits, the rest at random from recent days. For the cached commit, confirm with `nix path-info --store https://cache.scientistexperience.net <out>` succeeding and `nix path-info <out>` failing on magnetite before the run.
- [ ] **Step 2:** write `nixbot-eval-canary.py <commit> <evaluator-bin-dir>`: as the `nixbot` user, create a detached worktree of the clone, build `EvalSettings` from `/run/nixbot` configuration values (6, 3072, `systemd_scope=False`, `sandbox=True`), call `build_full_command`, write the argv to the log header, and run it with `PATH=<evaluator-bin-dir>:<unit PATH>` under `systemd-run --scope --unit=nixbot-replay-<commit>-<evaluator> -p MemoryAccounting=yes --expand-environment=no`, capturing stdout, stderr, start and end, the lock's `memory.max`, `memory.peak`, `memory.events` and `cpu.stat`.
- [ ] **Step 3:** in a quiet window, run each commit under both wrappers back to back, the stock one first on odd commits and the iets one first on even ones, never concurrently, each behind `/etc/nix/eval.lock` (tasks.md 4.3).
- [ ] **Step 4:** P1 and P4: compare per attribute (tasks.md 4.4) with `jq -S` on `{attr, drvPath, outputs, system, cacheStatus, error: (has("error"))}` sorted by `attr`. Expected: the same attribute sets, zero differences, `local`, `cached`, `notBuilt` each present, and the failing commit failing on the same attributes.
- [ ] **Step 5:** P2, P3 and P5: record per commit and evaluator the peak against `memory.max`, kills, times and the iets-to-stock wall ratio, with the overall speed-up and the warnings, in verify.md (tasks.md 4.5). A tripped criterion is written up for the operator's discussion (design D13), not treated as a rejection.

### Task 5: Switch

**Files:**
- Create: `modules/nixos/magnetite-user-slice-guard.nix`, `modules/checks/user-slice-guard-obligations.nix` (Step 0)
- Modify: `modules/nixos/magnetite-memory-budget/probe.py`, `modules/nixos/magnetite-memory-budget.nix`, `modules/checks/magnetite-memory-budget.nix` and its fixtures, `modules/clan/services/otel-collector/schema.nix` (Step 0)
- Modify: `modules/nixos/nixbot.nix:252-261`
- Modify: `modules/lib/nix-eval-lock.sh` (OOM paragraph comment only), `modules/machines/nixos/magnetite/default.nix` (the guard's import, Step 0; kill-order assertion comment only)

- [ ] **Step 0:** the soft guard of design D14 (tasks.md 5.0): the guard module with its assertion, seen failing on `nixos-magnetite` before the slice is set; the probe's `high` count with its check's fixture; land and deploy before Step 1. Commit: `feat(nixbot): soft memory guard for user sessions on magnetite`.
- [ ] **Step 1 [operator, wizard]:** as soon as the replay passes P1–P5 (Q69, 2026-11-19), the switch decision on P1–P5, with the D9 capacity trigger, after any discussion a tripped criterion opened (tasks.md 5.1, design D13).
- [ ] **Step 2:** replace `options.services.nixbot.packages.nix-eval-jobs.default` inside `config.services.nixEvalLock.wrap (...)` with `config.vanixiets.nixbot.ietsEvaluator` on one line; amend the two comments. Verify per tasks.md 5.2.
- [ ] **Step 3:** the unwrapped mutant fails magnetite's evaluation (tasks.md 5.3).
- [ ] **Step 4:** land, deploy, attribute posts, read the unit PATH (tasks.md 5.4).
- [ ] **Step 5:** read the first `eval_run` row naming `iets` (tasks.md 5.5).
- [ ] **Step 6: Commit:** `feat(nixbot): evaluate with iets`.

### Task 6: First week and capacity

- [ ] **Step 1:** the escalation ladder stands from Task 5 Step 4 on (tasks.md 6.1, operator Q88, 2026-11-21): rebuild; a repeat is capacity (D9, tuning first) or fixed forward (an iets pin); Task 7 Step 3's revert only when merges are blocked and no fix is quick. `IetsEvaluationUnhealthy` detects the failures.
- [ ] **Step 2 [operator, wizard]:** read the D9 trigger over the canary and the week (tasks.md 6.2), with Task 2 Step 6's queries restricted to `evaluator = 'iets'` and the switched week.
- [ ] **Step 3 [operator, wizard]:** the capacity decision, (a) to (d) in order, recorded in the comment table (tasks.md 6.3); a change under (a) or (b) loops back to Step 2 for its next week.

### Task 7: Integration verification

- [ ] **Step 1:** per-evaluator counts against the journal across the switch (tasks.md 7.1).
- [ ] **Step 2:** restart one pre-switch build and compare `ci_attribute.drv_path` per `attr` (tasks.md 7.2).
- [ ] **Step 3:** the rollback rehearsal in a scratch copy (tasks.md 7.3).
- [ ] **Step 4 [operator]:** the dev-loop view across the switch, budget included (tasks.md 7.4).
- [ ] **Step 5:** the budget's accounting of MemTotal at three moments (tasks.md 7.5).
- [ ] **Step 6:** archive preparation (tasks.md 7.6).
