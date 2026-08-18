The rungs run in the order below.
Rungs 0 through 5 spend no model calls; rung 6 is the only metered one and it is last.
Each rung carries its exact command and its pass criterion, and a rung is not complete until its criterion is observed rather than assumed.

## 1. Rung 0 — prerequisites (free, currently unmet)

Every prerequisite below is currently unmet: OrbStack is stopped, the Docker socket is absent, neither `harbor` nor `bench` is installed, and neither ghq clone carries a virtualenv.
Installing with `uv sync` inside a ghq clone writes into a read-only reference tree, so use `uv tool install` or a scratch `UV_PROJECT_ENVIRONMENT` outside the clone.

```
docker run --rm alpine sh -c '
  [ -f /proc/config.gz ] || exit 2
  zcat /proc/config.gz | grep -qE "^CONFIG_NFT_FIB_INET=[ym]"'
```

- [x] 1.1 Start OrbStack and confirm the Docker daemon answers: `docker info` exits 0
- [x] 1.2 BLOCKING — run the kernel probe above immediately after the daemon starts and BEFORE authoring any task, and read its exit status rather than its output. The anchored `grep -qE` is load-bearing: an unanchored `grep NFT_FIB_INET` matches the line `# CONFIG_NFT_FIB_INET is not set` and exits 0, so the negative reading would pass any scripted check
- [x] 1.3 Branch on the probe's three outcomes rather than halting on any non-zero. Exit 0 means egress control is available, so `no-network` may be declared anywhere this change declares it. Exit 1 means the option is explicitly unset, so every package this change authors declares `network_mode = "public"` at the environment baseline and drops the `[agent]` phase override from task 5.4, and the loss of egress control is recorded in the workspace README. Exit 2 means `/proc/config.gz` is absent, which is indeterminate: Harbor's own probe short-circuits to exit 0 in exactly that case (`environments/docker/docker.py:113-117`), so Harbor proceeds and this change proceeds with it, recording the indeterminacy and treating a later `no-network` rejection as the deciding evidence
- [x] 1.4 Record the correct attribution alongside the probe result: `no-network` is the harborize instrument's own authoring default (`SKILL.md:124`, `references/emitters.md:74`), not Harbor's. Harbor's default is `public` (`models/task/config.py:249-252`, `NetworkPolicy` at `:66`), BenchFlow's is the same (`task/config.py:720-723`), and 86 of the 87 SkillsBench corpus tasks declare `network_mode: public`. What the probe gates is whether a `no-network` declaration can be enforced at all: on failure `_enable_egress_control` goes false (`docker.py:188-195`), which zeroes `capabilities.disable_internet` (`:289-293`), and `environments/base.py:773-781` raises at environment start
- [x] 1.5 Install the Harbor CLI from PyPI latest stable with `uv tool install harbor` (settled 2026-08-15: CLI installs track PyPI releases, not sha-pinned source checkouts; the upstream pins remain reading pins for every source anchor in this change); pass is `harbor --version` resolving on `PATH` with no file created or modified under `~/ghq/github.com/harbor-framework/harbor`, and the installed version recorded in the workspace README because it may differ from the pin
- [x] 1.6 Install the BenchFlow CLI the same way from PyPI (`uv tool install benchflow`); pass is `bench --version` resolving on `PATH` with `~/ghq/github.com/benchflow-ai/benchflow` unmodified and the installed version recorded beside 1.5's
- [x] 1.7 Create the change-owned evaluation workspace at `modules/home/ai/evals/harborize/`, co-located with the skills under evaluation in `modules/home/ai/plugins/`, and record in its README the three upstream pins, the instrument version 0.2.1, the probe outcome from 1.2 with its branch from 1.3, and the attribution from 1.4. Job output goes to `logs/harborize/`, which is already gitignored (`.gitignore:57`)
- [x] 1.8 Record the instrument-freeze baseline in the workspace README before any other task runs: the `jj` revision the change starts from and `find modules/home/ai/plugins/testing-and-quality/.apm/skills/harborize -type f -exec shasum -a 256 {} + | LC_ALL=C sort | shasum -a 256`. Task 10.3 recomputes that digest, because a `jj diff -r @` cannot see an edit squashed into the `harborize-instrument` chain this change routes onto
- [x] 1.9 Record the claude-code install caveat in the workspace README: `install()` curls its bootstrap (`claude_code.py:425-449`) during `_prepare`/`_setup_agent` (`trial.py:408-414`), which no network policy wraps, while only `_run_agent_phase` (`trial.py:465-469`) and the verifier phases enter `_phase_network_policy`. A cell whose *environment baseline* is `no-network` therefore fails during agent install indistinguishably from an injection failure at the reward level, which is why task 5.4 puts `no-network` on the `[agent]` phase rather than on the baseline
- [x] 1.10 Hard constraint binding every later task: no file inside `modules/home/ai/evals/harborize/` may carry the `.nix` extension. `flake.nix:6` calls `inputs.import-tree ./modules` bare with no custom filter, so import-tree's default `nixFilter = andNot (hasInfix "/_") (hasSuffix ".nix")` (import-tree `default.nix:50`, rev `4ebb10ae17d5f1ad366e7aef5b92cb8eecf24f69`) imports every `*.nix` file anywhere under `modules/` and evaluates it as a flake-parts module, so a fixture named `expected.nix` breaks the flake rather than failing as a fixture. Two escapes, either one sufficient: never give a fixture the `.nix` extension, or place it under a `_`-prefixed directory, which is this repository's documented exclusion convention (ADR-0018, `packages/docs/src/content/docs/development/architecture/adrs/0018-deferred-module-composition-architecture.md:311`). Every other extension is safe, because non-nix files are enumerated and then dropped before anything reads them with no warning and no error, which is why `modules/` already carries 444 non-nix files and the flake still evaluates
- [x] 1.11 Run the flake-evaluation guard as soon as 1.7 writes the first corpus file under `modules/`, which is the earliest point at which 1.10 can be violated; pass is that `fd -H -e nix . modules/home/ai/evals/harborize` matches nothing and `nix eval .#nixosConfigurations --apply builtins.attrNames` exits 0 printing the attribute list. Write the absence assertion as an explicit `if`, because bash exempts a `!`-inverted command from `set -e` and an absence assertion written that way is a no-op. `nix flake check` is the stronger equivalent and is preferable when the wait is acceptable; do not add `--no-build`, which exits 1 on an unrelated import-from-derivation in this repository and would read as a guard failure

## 2. Canary skill and condition directory (free)

- [x] 2.1 Author the canary skill directory: one `SKILL.md` carrying the asserted token, named so it cannot collide with a deployed skill name
- [x] 2.2 Materialize the condition directory `dir(C)` containing that skill directory and nothing else; a stray non-hidden child without a `SKILL.md` turns the whole condition into a hard error at resolution
- [x] 2.3 Record in the canary README that the asserted literal appears in both the verifier and the `SKILL.md` by design, that `audit_leakage.py` check 1 flags it by construction (`MIN_LITERAL_LENGTH` at `:44`, `check_literals` at `:96`), and that the instrument is not edited to exempt it because it is frozen at 0.2.1
- [x] 2.4 Record the second consequence of the shared verifier fork chosen in task 5.2: a real agent in the metered rung can read the token out of the verifier script without the skill ever being delivered. That costs nothing here, because rung 6's pass criterion is the adapter's registration directory rather than the reward (task 9.4), and the falsifiability control in task 7.3 runs under the oracle, which greps skill directories and never reads the verifier

## 3. Rung 1 — adapter allowlist (free, already implemented at 0.2.1)

The gate is `check_harbor_agents` in the instrument's `scripts/design_matrix.py`, called from `load_cells`, carrying `HARBOR_SKILL_CONSUMING_AGENTS`.
22 of the 39 factory-registered Harbor adapters consume an injected skill and 17 ignore it with no error, warning or log line.

- [x] 3.1 Run the gate against a cells file naming a non-consuming adapter; pass is a nonzero exit naming the adapter and the reason, with no manifest emitted
- [x] 3.2 Run the gate against a cells file naming an `acp:` registry shorthand; pass is a nonzero exit, since `factory.py:167-175` routes every such name through the non-consuming ACP adapter
- [x] 3.3 Run the gate against the cells file this change will actually use, writing to a throwaway `--out` under `/tmp`; pass is exit 0 and a manifest emitted there. The emitted design is discarded rather than executed or committed, which is what keeps this rung inside the proposal's condition-lattice Non-goal; `design_matrix.py:442-466` writes `conditions.json`, `manifest.sh` and `jobs.json` into `--out`, and `:439-440` runs `load_cells` before `out.mkdir` at `:442`, so a refused cells file leaves the directory uncreated

## 4. Rung 2 — host-side resolution (free, no daemon required)

This rung replaces a refuted idea: `lock.json` cannot prove delivery, because `_write_trial_lock` runs at `trial.py:104` inside `__init__`, before `_resolve_injected_skills` at `:107` and long before `_upload_injected_skills` at `:411`, and `_build_agent_skill_locks` (`models/job/lock.py:462-475`) calls only host-side functions.

- [x] 4.1 Call `harbor.skills.resolve_skills` (`skills.py:111-123`) over `dir(C)`; pass is one entry per expected skill name, each carrying a sha256 from `compute_skill_digest` (`skills.py:200-209`)
- [x] 4.2 Call it over a deliberately malformed root — a missing path, a file rather than a directory, and a child directory without a `SKILL.md`; pass is that each raises on the host before any container starts (`_find_skill_dirs`, `skills.py:382-416`)
- [x] 4.3 Record this rung's evidence as host-side resolution and request, never as delivery

## 5. Task package authoring, dual head (free)

Author BenchFlow-native and derive the Harbor head into a separate sibling directory; the two heads cannot share a directory, and the export refuses a destination overlapping its source in either direction.

```
bench tasks export <task-id> <task-id>-harbor --target harbor --overwrite
```

- [x] 5.1 Author the injection canary package BenchFlow-native (`task.md` + `oracle/solve.sh` + `verifier/test.sh`), with `environment/skills/` left empty and a `.gitkeep` in it so the directory survives a fresh checkout
- [x] 5.2 Fix the canary's verifier fork as shared and ship no `verifier/Dockerfile` and no `[verifier.sandbox]` table. The fork is forced rather than chosen: the canary's oracle-to-verifier channel is a file the oracle writes, and under Harbor a separate verifier container binds only `/logs/verifier` (`trial.py:681-692`), while under BenchFlow a separate verifier sandbox is "parsed but not executed" (`task/runtime_capabilities.py:186-192`) so the verifier runs in the agent sandbox regardless. Shared mode is the one fork both runners execute identically
- [x] 5.3 Route the canary's oracle output to `/logs/verifier/canary-output.txt` rather than to a workspace path. That directory is bind-mounted into the agent environment (`trial.py:1279-1283`) and into a separate verifier environment (`trial.py:686-692`) from the same host directory, so the channel survives a later change of the fork, and Harbor's verifier does not clear it before reading the reward (`verifier/verifier.py:199-236`)
- [x] 5.4 Declare the network policy on every package: `network_mode = "public"` at the environment baseline, and `no-network` on the `[agent]` phase only when probe branch 1.3 permits it. The baseline is what the container is created with (`trial.py:896`) and the phase override is applied around `_run_agent_phase` alone (`trial.py:465-469`), so a `no-network` baseline breaks the claude-code install per task 1.9 while a `no-network` agent phase does not. Harbor reads the override through `task_cfg.agent.explicit_phase_policy()` (`trial/network_policy.py:45-59`) and validates it against the environment at `trial.py:203-217`; BenchFlow carries the same field at `task/config.py:524-530`
- [x] 5.5 Author the one real mechanical evaluation package the same way, with a single binary reward key; a multi-dimensional rubric silently disables Harbor's pass@k and makes BenchFlow's compare-lift count only `reward == 1.0` as passed (`eval_lift.py:32-33`)
- [x] 5.6 Choose and record the verifier fork for the mechanical package in its README; a separate-mode package ships `verifier/Dockerfile` that installs its own tooling and places `/tests/test.sh`, since Harbor uploads nothing into a separate verifier image, and its fork is exercised on the Harbor arm only for the reason in 5.2
- [x] 5.7 Export both Harbor heads with the command above; never hand-edit a derived head, and re-export after every edit to the native tree. `--overwrite` is required from the second export onwards, because `export.py:255-256` raises `FileExistsError` on an existing destination
- [x] 5.8 Run `scripts/audit_leakage.py --task <task-pkg> --skills <skill-dir>` on both packages; pass is exit 0 on the mechanical package, and on the canary the expected check-1 flag recorded with its justification per task 2.3
- [x] 5.9 Stamp instrument version 0.2.1 and the three upstream pins into each package README
- [x] 5.10 Acceptance condition on this task, the first that creates package directories: no file in either authored tree or either exported head carries the `.nix` extension, and the flake still evaluates. Re-run 1.11's guard after 5.7's export rather than only after authoring, because `bench tasks export` writes two trees this change does not author by hand, and re-run it after every later re-export

## 6. Rung 3 — static task validation (free)

Harbor has no free CLI equivalent: `harbor task check` and `harbor tasks check` both reach a stub that prints an error and raises `SystemExit(1)` (`cli/tasks.py:476-487`).
Do not follow that stub's own redirect.
It prints "Use 'harbor check <task-dir>' instead" (`cli/tasks.py:483-486`), and `harbor check` is a metered LLM-rubric run defaulting to `claude-code` and `claude-sonnet-4-6` (`cli/main.py:160`, `cli/analyze.py:100-103`), so obeying the CLI would spend money inside a rung this change calls free.

```
bench tasks check <task-dir> --level structural
```

- [ ] 6.1 Run the command above against each authored native tree; pass is exit 0 with no issues reported (`benchflow cli/tasks.py:93-115`, default level `structural`)
- [ ] 6.2 Construct `harbor.models.task.task.Task(<task-id>-harbor)` in Python for each exported head; pass is that construction succeeds
- [ ] 6.3 Record the Harbor gate's blind spot in the workspace README: `Task._validate_tests` returns early whenever a verifier environment is configured (`models/task/task.py:126-144`, early return at `:134-135`), so it structurally cannot catch a separate-mode package missing `/tests/test.sh`

## 7. Rung 4 — delivery proof (Docker time, zero model calls)

The strongest free rung.
BenchFlow's oracle path still calls `deploy_skills`: `rollout/__init__.py:1160` takes the `primary_agent == "oracle"` branch and calls it at `:1174`; `agents/install.py:303` computes the expected catalogue from `Path(skills_dir).glob("*/SKILL.md")` at `:313-314`, falls back to the five `_ORACLE_SKILL_PATHS` at `:30-36` via `:349-350`, and `_link_skill_paths` asserts the in-container catalogue equals the host's (`:146-161`) before raising `experiment_fidelity/skill_deployment_missing` at `:176-180`.
No model is materialized: `evaluation.py:461-462` returns None for the oracle agent.

```
bench eval run --tasks-dir <pkg> --agent oracle --skill-mode with-skill \
  --skills-dir <dir> --sandbox docker --jobs-dir logs/harborize/canary-bench
```

- [ ] 7.1 Run the command above for the canary package; pass is that the rollout reaches the agent phase AND reward equals 1
- [ ] 7.2 Confirm no rollout raises `experiment_fidelity/skill_deployment_missing` and each rollout's `effective_skills_dir` is the host `dir(C)` that was passed
- [ ] 7.3 Run the falsifiability control: the same command with `--skill-mode no-skill` and no `--skills-dir`; pass is reward 0. This proves the canary can fail, which is what makes 7.1 evidence rather than a constant. It does NOT exercise the fidelity assertion, because `expected_skill_names` is empty when `skills_dir` is falsy (`agents/install.py:313-317`) and the `experiment_fidelity/skill_deployment_missing` raise is guarded on `if expected:` (`:176-180`)
- [ ] 7.4 Run the fidelity control, which needs its own throwaway package because the assertion compares the in-container catalogue against the host-computed one and no ordinary `dir(C)` edit separates them. Copy the canary to a sibling, write `COPY _deps/skills /skills/` into its `environment/Dockerfile` by hand with a hand-authored `environment/_deps/skills/` holding a different skill set, and run 7.1's command against it with the real `--skills-dir`. `deploy_skills` then takes the `already_injected` branch (`agents/install.py:328-332`, `:342-344`), performs no runtime upload, and the container's `/skills` carries the baked set while `expected` still carries the host set, so `test "$source_catalog" = "$expected_text"` (`:159-161`) fails. Pass is that `experiment_fidelity/skill_deployment_missing` is raised naming the expected skill set. Delete the throwaway sibling afterwards; it is not part of the corpus
- [ ] 7.5 Run 7.1 once per distinct `dir(C)` shape this change uses, before any metered rung

## 8. Rung 5 — Harbor oracle inhabitation (Docker time, zero model calls)

Oracle is Harbor's default agent (`models/trial/config.py:164-168`), so `-a` and `-m` are unnecessary.
`OracleAgent.run` (`agents/oracle.py:81-136`) uploads `solution/` and execs `solve.sh`; no LLM client appears in the file.

```
harbor run -p <task-dir> -k 5 -o logs/harborize/gate1 --job-name gate1 -y
```

- [ ] 8.1 Run the command above for each package; pass is reward 1.0 across five trials, zero errored trials, AND `<trial>/agent/exit-code.txt` absent or containing 0
- [ ] 8.2 Check the exit-code file explicitly rather than reading rewards alone: a broken oracle exiting nonzero does not raise, since `oracle.py:149-151` writes the file and proceeds to the verifier, scoring 0
- [ ] 8.3 On any errored trial, triage by exception name before rerunning: `RetryConfig.max_retries` defaults to 0 (`models/job/config.py:282-284`) so every exception is terminal unless `-r N` is passed; four of the nine names in the no-retry list at `:288-300` are defined in `agents/installed/base.py`, which `OracleAgent` does not subclass, so any of them in a log means the job was not running the oracle; and `AddTestsDirError` (`verifier/verifier.py:19`), `DownloadVerifierDirError` (`:27`) and a bare `FileNotFoundError` from `_resolve_tests` or a missing solve.sh (`oracle.py:94-95`) kill a trial without appearing in that list

## 9. Rung 6 — registration assertion (METERED, last, one short trial per cell)

The only rung reaching Harbor's adapter registration copy.
`--install-only` provably cannot substitute: `_build_register_skills_command` (`claude_code.py:1530-1542`) is appended to `setup_command` at `:1733-1735`, both inside `async def run` beginning at `:1601`; `Trial.run` guards `_run()` on `not install_only` (`trial.py:375-378`); and `TrialConfig._install_only_disables_verification` (`models/trial/config.py:484-494`) disables the verifier too.
Per-adapter destinations differ, so no single assertion covers the grid.

- [ ] 9.1 Scrub subscription auth from the run environment before any metered trial: declare `ANTHROPIC_OAUTH_TOKEN=""` or unset it, because Pi injects it whenever the variable is present and non-empty (`pi.py:102-105` reads the value through a walrus, so an empty string is falsy and suppresses the injection), unlike claude-code and codex which require a force flag
- [ ] 9.2 Set `HARBOR_TELEMETRY=0` on every Harbor line, because `telemetry.py:239` sets `uses_skills` from the requested list and classifies a voided run as skill-bearing
- [ ] 9.3 Confirm before spending that the canary Harbor head declares `network_mode = "public"` at `[environment]`, per task 5.4; a `no-network` baseline makes this trial fail during claude-code's install fetch rather than at the registration copy, which is the failure design.md's risk register predicts
- [ ] 9.4 Run one short metered trial on the codex cell (settled decision: the metered adapter is codex via the ChatGPT-subscription path, `CODEX_FORCE_AUTH_JSON=1` or `CODEX_AUTH_JSON_PATH=<path>` at `codex.py:1305-1325`, recorded on-branch at `references/marketplace-program.md:46`); pass is the skill directory present under `$HOME/.agents/skills/<name>/` (`codex.py:1199-1207`), asserted from inside the container because that destination sits in no host bind mount. The criterion is the directory alone and deliberately not the reward: the canary's shared verifier fork (task 5.2) puts the token within a real agent's reach, so this trial's reward carries no injection information in either direction
- [ ] 9.5 For any additional cell, assert that adapter's own destination: codex and pi at `$HOME/.agents/skills/<name>/` (`codex.py:1199-1207`, `pi.py:75-83`), opencode at `~/.config/opencode/skills/<name>/` (`opencode.py:425-433`)
- [ ] 9.6 Do not report a cross-runner contrast for pi, opencode or claude: BenchFlow's registry declares different paths (`registry.py:560`, `:700`), and codex is the one cell where both runners agree. Record those cells' cross-runner numbers as non-comparable per the design's open question

## 10. Record, stamp and close

- [ ] 10.1 Record the measured per-run cost constant together with the cell, the model, the task, the trial length, the auth mode and the instrument version; do not multiply it into any budget inside this change. Read it from Harbor's own accounting field `cost_usd` (`models/job/result.py:41`, accumulated at `:169` from `agents/installed/claude_code.py:1525`), and treat an extraction that yields no numeric value as a failed task rather than as a measured zero
- [ ] 10.2 Confirm the canary package is retained in the corpus and name it as a precondition to be re-run at the start of every later round
- [ ] 10.3 Confirm the harborize skill directory is unchanged by recomputing the content digest recorded in task 1.8 and comparing it to the recorded value. A `jj diff -r @` is not sufficient, because it reports only what the working-copy commit changed against its parents and would show nothing for an edit squashed into the `harborize-instrument` chain this change routes onto
- [ ] 10.4 List every instrument defect found mid-change as deferred to the next revision, with its evidence. The list opens with three already known: the canary leakage flag from task 2.3; the `--membership-from` census workflow; and `CHANGELOG.md:55`, which attributes `network_mode = "no-network"` to Harbor when Harbor's default is `public` (`models/task/config.py:249-252`) and the `no-network` default is the instrument's own authoring prescription at `SKILL.md:124`
- [ ] 10.5 Write the review-gate audit into each package README: one line per algebraic invariant, pass or fail, with its evidence
