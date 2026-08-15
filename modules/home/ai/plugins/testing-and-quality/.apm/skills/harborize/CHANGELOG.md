# Changelog

Notable changes to the harborize instrument.
The format follows Keep a Changelog, and the version numbers apply to this skill as a measurement instrument rather than to any package it emits.
Evaluation results are indexed by the instrument version that produced them, so a comparison spanning versions has to be made deliberately.
The instrument is not modified while an evaluation is being authored or run; revisions happen between rounds.

## 0.2.1 — 2026-08-14

Container-boundary round.
Every entry below corrects a 0.2.0 claim that was true on the host and asserted about the container, or records a consequence of that boundary the text did not carry.
0.2.0 repaired the instructions that could not run; this version repairs the evidence they produce.
No package layout, estimator or budget option changed, so a package built under 0.2.0 remains readable, and no results exist under either version.

Written against the same upstream revisions as 0.2.0: harbor `ac398bbda7c4c1073461797d3b95c2455cc671b5`, benchflow `d30527b82027a416e72014920cdf43a534967ad3`, skillsbench `9a1f4dd5f7659f75707435da3ce854b6e48321d1`.
Every anchor cited in this entry was read at those revisions.

### Fixed

- The instrument claimed delivery where only resolution is proven.
  `_write_trial_lock` runs inside `Trial.__init__` at harbor `trial.py:104`, before `_resolve_injected_skills` at `:107` and long before `_upload_injected_skills` at `:411`, and `_build_agent_skill_locks` (`models/job/lock.py:462-475`) calls only host-side functions.
  So `lock.json` records host-side resolution and pins digests, and proves nothing about what reached the container: it stays fully populated through an upload failure, a permissions failure, or an adapter that never reads the injected directory.
  `scripts/collect_rewards.py` said the lock's `skills` list records every skill "actually resolved and uploaded"; the upload half was false.
  SKILL.md said a run batch whose skills never arrived cannot be silently analyzed as if they had; that was false for the 17-adapter class below, which writes a fully populated lock and passes `harbor_injection`.
  Both are narrowed to resolution and request, with what the lock cannot see stated beside them, and the check is now documented as one-sided: a disagreement proves the lattice did not vary, agreement proves only that request and resolution matched.
- The adapter enumeration in `references/emitters.md` was wrong in a way that read as correct.
  It stated twenty adapters, which is exactly what `rg -l 'skills_dir' src/harbor/agents/installed/*.py` returns, but that glob is not the adapter set: it misses `installed/cline/cline.py` in a subdirectory and `terminus_2/terminus_2.py` outside `installed/`, and it counts modules where the question is registry entries.
  Every adapter it named was correct.
  The figure is 22 of 39 registered agents, from `rg -c 'AgentName\.[A-Z_0-9]+: ' src/harbor/agents/factory.py` and `rg -l 'self\.skills_dir' src/harbor/agents/ --type py`, the latter returning 23 files being 22 adapters plus the `agents/base.py:85` definition site.
  Both full lists are now enumerated rather than sampled.
- The canonical package layout and the publication-grade instruction disagreed.
  The layout placed `task.md`, `task.toml` and `instruction.md` in one directory, which `bench tasks check --level publication-grade` rejects: benchflow `_utils/task_authoring/structural_checks.py:208-212` refuses a co-present `task.toml`/`instruction.md`, and `:218-222` refuses `solution/` in favour of `oracle/`.
  skillsbench `.github/scripts/validate_tasks.py:21-26` forbids exactly `instruction.md`, `task.toml`, `solution` and `tests`, which is the set Harbor requires, and all 87 tasks under `tasks/` plus the 14 under `tasks-extra/` are native, with zero `task.toml` and zero `solution/`.
  The layout is now two directories: an authored BenchFlow-native tree and a generated `<task-id>-harbor` sibling, with `bench tasks export` as the sanctioned route rather than an aside, and each static gate named against the directory it can run in.
- Pi's subscription-auth exposure was understated.
  `pi.py:102-105` injects `ANTHROPIC_OAUTH_TOKEN` merely because the variable is present in the resolved environment, with no force flag, unlike claude-code (`claude_code.py:1587-1597`) and codex (`codex.py:1301-1329`).
  Since Phase 5 bars subscription-authenticated cells from a reported batch, enforcement on a Pi cell requires an explicit scrub rather than withholding a flag.

### Added

- A hard-fail adapter allowlist in `scripts/design_matrix.py`.
  Of the 39 factory-registered Harbor agents, 22 consume the injected skills and 17 ignore them with no error, no warning and no log line, so a cell naming one of the 17 uploads the skills, registers nothing, exits 0 and collapses every condition to the empty condition.
  `HARBOR_SKILL_CONSUMING_AGENTS` carries the consuming set with the commands that regenerate it and the revision it was derived from; `check_harbor_agents` runs from `load_cells`, so no caller reaches a manifest without passing it, and it refuses with a nonzero exit naming the adapter and why.
  Any `acp:` shorthand is refused for the same reason: `factory.py:167-175` routes every such name through `AgentName.ACP`, which is a non-consumer, so an ACP-shorthand cell drops skills on the Harbor arm while the BenchFlow arm works.
  The gate runs before any container starts, and no artifact written after a run distinguishes this failure, which is why it is a gate rather than a runtime canary.
- The per-adapter destination table, because no single canary assertion covers a grid.
  claude-code copies to `$CLAUDE_CONFIG_DIR/skills/<name>/` with `CLAUDE_CONFIG_DIR` set to `/logs/agent/sessions` (`claude_code.py:1530-1542`, `:1718`; `models/trial/paths.py:36`), codex and pi both write `$HOME/.agents/skills/<name>/` (`codex.py:1199-1207`, `pi.py:75-83`), and opencode writes `~/.config/opencode/skills/<name>/` (`opencode.py:425-433`).
  claude-code's destination sits inside the `/logs/agent` bind mount (`trial.py:1284-1288`), so it is readable on the host after a run with no verifier code at all.
  Harbor and BenchFlow declare the same path only for codex; `pi-acp` declares a superset (benchflow `agents/registry.py:560`), and `opencode` (`:700`) and `claude-agent-acp` (`:518`) declare paths Harbor does not write.
  Those three cells' cross-runner comparability is recorded as an open question rather than resolved.
- The free delivery canary, which already exists upstream.
  BenchFlow's oracle path proves delivery end to end with no model call: `rollout/__init__.py:1160` takes the `primary_agent == "oracle"` branch and still calls `deploy_skills` at `:1174`, `agents/install.py:313-314` computes the expected catalogue from `Path(skills_dir).glob("*/SKILL.md")`, `:350` falls back to the five `_ORACLE_SKILL_PATHS` at `install.py:30-36`, and `_link_skill_paths` asserts in the container that the catalogue at each discovery path equals the host's before raising `experiment_fidelity/skill_deployment_missing` at `:176-179`.
  The command and pass criterion are documented, along with the fact that Harbor has no free equivalent: every adapter's registration copy is built in `run()` rather than `setup()`, so `--install-only` (`cli/jobs.py:901-910`) reaches the upload and never the registration.
- Two blocking prerequisites in Phase 3, where an author hits them.
  Harbor's default `network_mode = "no-network"` is rejected at environment start when the daemon's kernel lacks `CONFIG_NFT_FIB_INET`: the probe is `environments/docker/docker.py:113-117`, failure zeroes `capabilities.disable_internet` (`:188-193`, `:289-293`), and `environments/base.py:772-781` raises.
  The one-line daemon probe is given, along with the note that Harbor's own probe passes when `/proc/config.gz` is absent and the hand probe does not.
  claude-code's `install()` curls its bootstrap from the network (`claude_code.py:425-449`) during `_prepare`/`_setup_agent` (`trial.py:408-414`), which is outside the agent-phase network policy that wraps only `_run_agent_phase` (`trial.py:465-469`) and the verifier phases, so a no-network cell fails during agent install indistinguishably from an injection failure at the reward level.
- `HARBOR_TELEMETRY=0` on every emitted Harbor line, overridable per cell.
  `telemetry.py:239` sets `uses_skills` from the requested list without consulting the effective directory or the adapter, so it classifies a voided run as skill-bearing.
  That is a third silent-null surface, recorded as one not to consume in analysis.

## 0.2.0 — 2026-08-14

Contract repair round.
Every entry below corrects a documented instruction that could not run as written, or states a consequence the text left unstated.
The canonical package layout is unchanged apart from the verifier Dockerfile that separate mode requires, so packages built under 0.1.0 remain readable; none of them were validated, and results produced under 0.1.0 are not comparable to results produced under this version.

The round was written in parallel across the files and then reconciled against an adversarial audit, so several entries below record the reconciled state rather than the first pass: the budget menu, the `audit_leakage.py` and `census.py` invocations, the verifier-environment fork, the manifest quoting, and the single-task interval all changed during reconciliation.

Upstream revisions this version was written against: harbor `ac398bbda7c4c1073461797d3b95c2455cc671b5`, benchflow `d30527b82027a416e72014920cdf43a534967ad3`, skillsbench `9a1f4dd5f7659f75707435da3ce854b6e48321d1`.
Every anchor cited anywhere in the skill was re-read at those revisions during reconciliation.

### Fixed

- Skill injection under Harbor (F1).
  The generated run line passed `--ak skills_dir=/tmp/cond-<id>`, a host path handed to a container-side field that the Claude Code adapter reads with `cp -r <path>/* $CLAUDE_CONFIG_DIR/skills/ 2>/dev/null || true`.
  The copy found nothing, the redirection swallowed the failure, the run exited 0, and every condition collapsed to the empty condition without a diagnostic.
  Harbor's injection flag is `--skill` (also spelled `--skills`), which resolves paths on the host, uploads each skill per trial under `/harbor/skills/<name>`, records name, source and content digest in the job lock, and raises `FileNotFoundError` on a bad path before any container starts.
  The root cause was a documentation hole: the emitter reference showed a Harbor run line carrying no injection flag at all, so the generator guessed.
- The validation gate named a removed command (F2).
  `harbor tasks check` prints an error and raises `SystemExit(1)` unconditionally, and `tasks` is a hidden alias of the same typer app as `task`, so both spellings fail rather than validate.
  The gate is now schema-level construction of `harbor.models.task.task.Task(<task-dir>)` for the Harbor head and `bench tasks check --level structural` for the BenchFlow head, with the limits of each stated: schema validation checks field names, types and enum membership and nothing about behaviour, and it skips the test-script check entirely whenever a verifier environment is configured.
  `harbor check`, the named replacement, is documented as a different instrument — an LLM rubric review that spawns a metered Harbor job and whose exit code ignores rubric failures — to be run once at authoring time and kept out of CI.
- The verifier environment was stated as a default rather than a fork (F3).
  `environment_mode = "separate"` sets `skip_tests_upload=True`, so Harbor never uploads `tests/` and the verifier image must already own `/tests/test.sh`.
  With the stock `python:3.12-slim` verifier image the skill declared, every trial fails permanently, because the absent reward file raises `RewardFileNotFoundError`, which is in Harbor's default no-retry list.
  Both branches are now explicit, with their leak consequences, the observation that two of the three packages emitted in iteration 1 needed `shared`, and the machinery `separate` requires: the separate verifier environment's build context is the task's `tests/` directory, so a `tests/Dockerfile` is what places the test scripts at `/tests/`.
  The task.toml template marks `environment_mode` as one branch of that fork rather than a default, and records that declaring a `[verifier.environment]` table at all implies `separate`, so a shared-mode package omits the table instead of setting `environment_mode = "shared"` beside it.
  The rule extends past the test script to everything it invokes: Harbor uploads nothing into a separate verifier image, so a wrapper shelling out to `uvx` in an image carrying no uv reaches the same `RewardFileNotFoundError` dead end.
  The shipped Dockerfile installs the verifier's tooling at build time and the wrappers call it directly, which also leaves the verifier environment runnable with no network.
- The BenchFlow run line died at argparse (F4).
  `bench eval run --run-id` does not exist in benchflow's option set.
  `--trials` exists but is implemented as the trial count for `--matrix` and is consumed only inside the `--matrix` branch, so it is inert on its own and there is no plain repetition flag.
- The host-versus-container asymmetry between the two runners was undocumented (F5).
  BenchFlow's `--skills-dir` is a host path, validated on the host and mounted into the sandbox at `/skills`, so the same argument shape that failed silently for Harbor is correct for benchflow, and benchflow fails loudly where Harbor does not.
- Reward shape had an unstated consequence (F6).
  Harbor computes pass@k only when every trial carries exactly one reward key valued 0 or 1, so a multi-dimensional Reward Kit rubric disables the metric with no message.
  BenchFlow's `eval compare-lift` defines `passed` as `reward == 1.0`, so partial credit is invisible to its headline pass rate and appears only in mean reward.
  The text now carries a decision rule rather than a warning: default to a single binary reward key, and take a graded rubric only when partial credit is the estimand.
- Dangling reference links.
  Phase 4 pointed at `references/harbor-emitter.md` and `references/benchflow-emitter.md`, neither of which exists, while `references/emitters.md`, which holds that content, was referenced from nowhere.
- The documented `census.py` invocation could not run.
  It was shown as a single positional call, but `--out` is required and the hardcoded sink is gone.
  The two-subject design needs two invocations anyway, source first, because a flat deployed root resolves every skill to the `<external>` sentinel without a `--membership-from` pointing at a source census, and the derived plugin units disappear with it.
- The bundled `census.json` was a 0.1.0-era snapshot: 128 skills, taken before harborize was itself in the tree, carrying no `provenance`, no `membership` map and no `overlap` tables, and therefore not the schema the 0.2.0 script emits.
  It was the traceable source of the stale 128.
  It is regenerated with the 0.2.0 script against a repo-relative root, so it is self-describing and usable as the `--membership-from` input, and SKILL.md now names it instead of leaving it orphaned.
- The documented `audit_leakage.py` invocation could not run.
  It was shown with the skill directories positional, but the script declares no positionals: `--task` and `--skills` are both required named options.
  The documented form is now `--task <task-pkg> --skills <skill-dir> [...]`, alongside the exit-code contract (0 clean, 1 flags raised, 2 the audit could not run) and the reason 2 is separated from 0, which is that every check searches for evidence of leakage and a mistyped path finds none.
- The package-layout comment claimed `environment/skills/` is "populated per condition".
  dir(C) lives outside the package and is passed to the runner's injection flag, so the directory stays empty in the canonical package.
  `materialize_conditions.py` does permit a `--dest` inside a package, which is how SkillsBench's own ablation driver uses `<task>/environment/skills`; what it refuses is a destination that a Dockerfile in an ancestor directory would COPY or ADD into an image, checked by reading that Dockerfile's own copy sources rather than by matching the path name.
- Three interpolations of dir(C) into the generated manifest were unquoted.
  The census's `<external>` sentinel is a candidate ablation unit and contains shell redirection metacharacters, so `--dest /tmp/cond-<external>` was reparsed by bash as a redirect pair and both the destination and the following option were lost, with `bash -n` and `shellcheck` clean on the file.
  Every interpolated path and job name now passes through `shlex.quote`.
- The analyzer printed zero-width 95% intervals on a single-task design.
  The bootstrap resamples tasks as clusters, so with one task every replicate is the same sample and the percentile interval collapses to the point estimate, with no marking.
  Phase 1 proposes 1 to 3 tasks per unit, so this was the ordinary case.
  Contrasts and condition estimates spanning fewer than two distinct tasks now report the point estimate and mark the interval unavailable.
  A second difference that is numerically zero is also now labelled additive rather than picking up a sign from floating-point residue.

### Changed

- The unit of ablation is settled rather than asked (D1).
  The unit is the skill, materialized from the deployed tree.
  A plugin unit is a derived aggregate, the union of its member skills' deployed directories resolved through an explicit skill-to-plugin membership map shipped beside the census, because the deployed tree is flat and carries no plugin directories or `.apm/` paths.
  The census reports both trees: the deployed tree is the evaluation subject because it is what a harness loads, and the first-party source tree is the refactor subject because it is where a fix can be written.
  Selection-competition simulation runs over the deployed field, which is about a third larger at 172 skills against 129, because the source field omits the 43 deployed skills belonging to no first-party plugin.
  How much interference that omission hides is what stage 2 measures; the ratio of field sizes does not establish it.
- Subjective contracts reduce to mechanical checks, and judges are gated (D2).
  Exactly one judge-validation package must clear the acceptance bar before any judge-based stratum enters a budget.
  The bar adopted here is a human-labeled validation set of roughly 6 to 12 submissions spanning pass, fail, partial, borderline, plausible-but-wrong and polished-but-unsupported, plus demonstrated agreement with the human labels and stability across runs; it is this instrument's bar rather than a quotation from SkillsBench, whose repository carries no such text.
  The attributed fact is that all 87 tasks shipped in SkillsBench declare `verifier.type: test-script` and none uses a judge verifier, which is what warrants the gate.
  If the gate fails, the subjective stratum falls back to structural proxies, which ask whether the produced artifact exhibits the convention and are checkable by grep or AST.
- Budgets are costed at metered API rates (D3).
  Subscription-authenticated cells are permitted for interactive exploration and are never used for a run batch whose numbers are reported, because metered costing is robust to the unresolved credential-use-policy question in either direction and because a subscription cell confounds the measurement independently, rate-limit throttling being nondeterministic and single-account auth capping concurrency.
  No per-run cost figure exists yet, so one must come from a calibration batch before any budget table is presented.
- The three iteration-1 packages are reference material to be regenerated under the repaired skill (D4).
  None passed the oracle inhabitation invariant, so none is cited as validated.
- The description's exclusion clause fenced off "the skill itself", which read ambiguously between the skill under evaluation and harborize.
  It now excludes only the skill under evaluation, and states that revising harborize between evaluation rounds is in scope.
- `references/emitters.md` is reflowed to one sentence per line, matching the other reference files and the repository's markdown convention.
  Most of its content was written this round, so the reflow and the corrections land together.
  SKILL.md's older bulleted sections keep their existing hard wrapping and are left for a separate pass.
- Counts corrected against a re-run census: the first-party source tree holds 129 skills rather than 128, and the deployed field is about a third larger rather than 34 percent.
  The command-style, environment-coupling and decidability figures in `references/marketplace-program.md` were reproduced exactly and stand.
- Anchor corrections: `_verifier_env_build_context` is at `trial.py:694-702`, `harbor task check` at `cli/tasks.py:476-487`, `_iter_rollouts` at `eval_lift.py:277-291`, and twenty adapter modules reference `skills_dir` rather than twenty-one.
  `bench eval run`'s option set is cited as `cli/main.py:193-592` together with `cli/_options.py:16-32`, because `--model` and `--skill-mode` are declared through shared `Annotated` aliases and do not appear literally inside the command body.
  The `./` prefix for a relative `--skill` path is stated as a precaution rather than a requirement: `resolve_skill_sources` takes the local branch whenever the path exists, and only a relative path that does not exist is parsed as a git source.

### Added

- Instrument versioning (D5).
  A `version` field in the frontmatter, this changelog, the rule that results are indexed by instrument version, and the rule that the instrument is revised between rounds and not during one.
  The upstream revisions each version was written against are recorded, because the 0.1.0 text cited a harbor command that has since been removed and a benchflow flag that does not exist.
- Explicit not-yet-implemented markers for the `lint` and `selection-sim` stages.
  Both are static, near-free and 100-percent coverage, both gate all container spend, and neither exists in `scripts/`, so the staged ordering reads as a plan rather than as inherited implementation.
- `scripts/collect_rewards.py`, closing the gap between running the manifest and feeding the analyzer.
  It walks both runners' job trees, emits the rows `analyze_lattice.py` reads, and refuses on an unresolvable condition, an ambiguous reward dict, unscored rollouts with no error policy, or a failed injection check, so a batch whose skills never arrived cannot be analyzed as though they had.
- A dependency convention for the bundled scripts.
  Each script under `scripts/` carries a `uv run --script` shebang and a PEP 723 inline metadata block declaring its Python requirement and any non-standard-library dependency, and is executable.
  All six are standard-library-only at this version, so every dependency list is empty.
- `design/jobs.json`, emitted beside `conditions.json` and `manifest.sh`.
  It records `{runner, cell, condition, path}` per job in the shape `collect_rewards.py --job-index` consumes, and the harbor run line now emits `-o/--jobs-dir` explicitly rather than writing to harbor's configured default, so where a job landed is recorded rather than reconstructed.
  Job output is laid out per runner under one root: harbor at `<jobs-root>/harbor/<cell>__<id>` and bench at `<jobs-root>/bench/<cell>__<id>/trial-NN`.
- Stronger injection evidence in `collect_rewards.py`.
  The Harbor arm reads each trial's `lock.json`, whose `skills` list carries a content digest per skill actually resolved and uploaded, and falls back to the requested `config.agent.skills` only when a trial wrote no lock.
  The BenchFlow arm requires a non-null `effective_skills_dir` under `with-skill` rather than trusting `skill_mode`, which records the request.
  Both fields record an outcome rather than a request, which is what detecting the F1 failure signature requires.
- Shape validation for `cells.json` in `design_matrix.py`.
  `runner` is restricted to the two spellings `collect_rewards.py` accepts, required keys are checked, and duplicate cell names are refused, since two cells sharing a name would write into one job directory and silently merge across cells.

### Removed

- The resolution-IV fractional-factorial budget option.
  The design the implementation actually offers is a foldover, which has no defining relation and therefore no resolution, and it was named in one file and rejected by `design_matrix.py --design`.
  Option 3 is now Foldover, described by what it yields: a solo marginal and a leave-one-out marginal per unit, whose gap aggregates every higher-order interaction involving that unit without separating them.
- The claim that invariant 4's coupling is a joint over `(task, trial-seed)`.
  Neither runner exposes a per-trial seed at these revisions, so the coupling is exact at the task level and positional within a task, with trial ordinals assigned by `collect_rewards.py`.

## 0.1.0

As-authored baseline, placed verbatim into the vanixiets apm marketplace.
It established the phase structure, the algebraic invariants used as the review gate, the dual Harbor and BenchFlow emission model, the condition lattice and its estimators, and the marketplace-scale staged program.
Its Harbor injection flag, its Harbor validation command, its BenchFlow run line, and its verifier-environment default were all wrong in ways that fail silently or at argparse, and no package emitted under it was validated.
