## Context

The harborize instrument at `modules/home/ai/plugins/testing-and-quality/.apm/skills/harborize/` compiles agent skills into evaluation packages runnable under both the Harbor CLI and the BenchFlow CLI.
It is at version 0.2.1, reached through two repair rounds recorded in its `CHANGELOG.md`: 0.2.0 fixed documented instructions that could not run, and 0.2.1 fixed claims that were true on the host and asserted about the container.

Nothing the instrument has emitted has been validated.
The three iteration-1 packages under `~/Downloads/harbor-skill/harborize-workspace/iteration-1/` failed the oracle inhabitation invariant, and the instrument's own `references/marketplace-program.md` records that none is cited as validated.
No per-run cost figure exists, so the staged marketplace program's screening estimate of roughly 500 to 700 runs multiplies an unmeasured constant.

The failure classes that make this expensive to get wrong are all silent.
Harbor uploads injected skills for every agent, and of the 39 agents its factory registers, 22 read the injected directory and 17 ignore it with no error, no warning and no log line; the counts come from `rg -c 'AgentName\.[A-Z_0-9]+: ' src/harbor/agents/factory.py` returning 39 and `rg -l 'self\.skills_dir' src/harbor/agents/ --type py` returning 23 files, the latter being 22 adapters plus the definition site at `agents/base.py`, both reproduced here at the pinned revision.
A cell naming one of the 17 exits 0 and collapses every condition to the empty condition.
The trial lock cannot catch it: `_write_trial_lock` runs inside `Trial.__init__` at harbor `src/harbor/trial/trial.py:104`, before `_resolve_injected_skills` at `:107` and long before `_upload_injected_skills` at `:411`, and `_build_agent_skill_locks` (`src/harbor/models/job/lock.py:462-475`) calls only the host-side `resolve_skills`, `get_git_skill_metadata` and `compute_skill_digest`.
Harbor's telemetry cannot catch it either, since `src/harbor/telemetry.py:239` sets `uses_skills` from the requested agent list without consulting the effective directory or the adapter.

Three upstream repositories are pinned, and every anchor in this document was read at these revisions in the local ghq clones, whose HEADs were confirmed to equal the pins.

| repo | path | revision |
|---|---|---|
| Harbor | `~/ghq/github.com/harbor-framework/harbor` | `ac398bbda7c4c1073461797d3b95c2455cc671b5` |
| BenchFlow | `~/ghq/github.com/benchflow-ai/benchflow` | `d30527b82027a416e72014920cdf43a534967ad3` |
| SkillsBench | `~/ghq/github.com/benchflow-ai/skillsbench` | `9a1f4dd5f7659f75707435da3ce854b6e48321d1` |

The pins are recorded explicitly because all three clones are shallow and sit at their own HEAD rather than at a released tag, so an anchor is valid only at the revision beside it and a later `ghq` sync moves every line number in this document.

## Goals / Non-Goals

**Goals:**
- Prove that the instrument at 0.2.1 produces a package whose skill injection is delivered, in the container, at every level where it can silently fail.
- Leave behind a permanent injection canary in the corpus, so a later regression in the injection path fails a task rather than voiding a batch.
- Produce one mechanical evaluation package that passes both static gates and the oracle inhabitation invariant under both runners.
- Measure the per-run cost constant and record the conditions it was measured under.
- Retire as much risk as possible before any model call, and reduce the metered exposure to one short trial per cell.

**Non-Goals:**
- Marketplace-wide evaluation; the staged program stays a plan.
- Condition-lattice runs or any budget menu. Rung 1 invokes `design_matrix.py` three times against throwaway `/tmp` output directories solely to exercise its adapter gate, and nothing it emits there is executed, committed or consumed by a later rung.
- The judge-validation package, which is a hard gate for any judge-based stratum and belongs to the dependent change.
- Cost projections beyond the measured figure.
- Promotion of the three iteration-1 packages.
- Any modification to the harborize instrument, which is frozen at 0.2.1 for the duration of this change.

## Decisions

The first five decisions were settled before this change was opened and are encoded here rather than re-derived; they are inherited from the session that produced the 0.2.0 and 0.2.1 rounds and from the dispatch brief.
D6 onward are this change's own.

### D1: the ablation unit is the skill, materialized from the deployed tree

- **Choice**: the unit is the skill directory as deployed; a plugin unit is a derived aggregate, the union of its member skills' deployed directories, resolved through an explicit skill-to-plugin membership map shipped beside the census. The census covers both subjects: the deployed tree is the evaluation subject and the first-party source tree is the refactor subject.
- **Rationale**: the deployed tree is what a harness loads and it is flat, one directory per skill, with no plugin directories and no `.apm/` paths, so plugin membership cannot be recovered from directory structure. The deployed count is 172 (reproduced here by listing `~/.claude/skills`) against 129 first-party source skills across 18 plugin groups (from the `provenance` block of the instrument's bundled `census.json`, script version 0.2.0, revision `b26f5a179edbffed47253d453e3a8eb7ed43372f`).
- **Alternatives considered**: resolving plugin units by walking the filesystem, which silently yields a different unit set on the deployed tree than on the source tree.

### D2: mechanical contracts by default, with the judge gate held out of scope

- **Choice**: verifiers reduce to decidable predicates on final state wherever one exists; exactly one judge-validation package is a hard gate before any judge-based stratum enters a budget, and that package is not built here.
- **Rationale**: all 87 tasks shipped in SkillsBench declare `verifier.type: test-script` and none uses a judge verifier, reproduced at the pinned revision by counting `tasks/*/task.md`. The gate costs a human-labeled validation set, and this change has to demonstrate that a mechanical package works at all first.
- **Alternatives considered**: building the judge package alongside, which doubles the change and puts the harder measurement ahead of the easier one.

### D3: every budget figure is costed at metered API rates

- **Choice**: metered rates for anything reported; subscription-authenticated cells are for interactive exploration only.
- **Rationale**: metered costing is robust to the unresolved credential-use-policy question in either direction, and a subscription cell confounds the measurement independently through nondeterministic rate-limit throttling and single-account concurrency caps.
- **Narrowed for this change's one metered measurement, by the settled decision of 2026-08-15**: that decision names codex on the ChatGPT-subscription path as the metered adapter, which is the class this decision's second clause excludes. The narrowing is deliberate, and the rate clause survives it intact because the two clauses are separable and only the second is set aside. Harbor's codex adapter has no billed-cost field to read and derives `cost_usd` from token counts against LiteLLM's pricing table (`codex.py:724-780`, resolved at `:1120-1124`, set at `:1194`), unlike claude-code which parses an authoritative `total_cost_usd` from its own stream (`claude_code.py:858-879`, `:1463`, `:1525`). The reported figure is therefore a list-rate computation over observed token counts, which is what "costed at metered API rates" asks for, and it is a rate that does not vary with how the trial authenticated.
- **Residual confound, contained by the rung's shape rather than by argument**: the throttling and concurrency-cap confounds named above act on throughput and on batch scheduling, not on token counts, and rung 6 is one short trial on one cell (task 9.4) with no concurrency and no batch. What is not claimed is a billed charge: the record carries `"auth_mode": "chatgpt-subscription"` and the pricing basis alongside the number, and a billed-rate figure for any budget in the dependent change is a separate measurement that change must make.
- **Implementation note**: enforcement takes an explicit environment scrub rather than the absence of a flag. Claude Code gates subscription auth behind `CLAUDE_FORCE_OAUTH` and Codex behind `CODEX_FORCE_AUTH_JSON`, but Pi injects `ANTHROPIC_OAUTH_TOKEN` whenever the variable is present and non-empty in the resolved environment and the resolved provider is anthropic (harbor `src/harbor/agents/installed/pi.py:102-105`), with no force flag. The check is a walrus on the value rather than a membership test, which is what makes the empty-string scrub a sound mitigation: a Pi cell in a reported batch declares `ANTHROPIC_OAUTH_TOKEN=""` or runs from a shell where it is unset, and either form is falsy.

### D4: the iteration-1 packages are reference material and are regenerated

- **Choice**: read them for shape, regenerate under the repaired instrument, never cite them for results.
- **Rationale**: none passed oracle inhabitation, so promoting one carries an unvalidated package into a measured program.

### D5: the instrument is frozen at 0.2.1 for the duration of this change

- **Choice**: results are indexed by instrument version; the instrument is not modified while an evaluation is being authored or run, and a defect found mid-change is recorded and deferred to the next revision.
- **Rationale**: a fix applied mid-round makes the round's results unattributable to any version, which is the property the versioning exists to protect.
- **Consequence**: the three instrument-side items this change surfaces are recorded as deferred rather than fixed, and nothing under the harborize skill directory is edited. They are the canary leakage flag; the `--membership-from` census workflow; and `CHANGELOG.md:55`, which attributes `network_mode = "no-network"` to Harbor when Harbor's own default is `public` (`models/task/config.py:249-252`) and `no-network` is the instrument's own authoring prescription (`SKILL.md:124`, `references/emitters.md:74`). The third is a documentation defect in the CHANGELOG alone; `SKILL.md` and `emitters.md` state the default correctly as the instrument's own, so no emitted package is wrong because of it.
- **Enforcement**: the freeze is checked by a content digest of the harborize directory recorded at the start of the change and recomputed at the end, not by `jj diff -r @`. That diff reports only what the working-copy commit changed against its parents, so an edit squashed into the `harborize-instrument` chain this change routes onto would leave it empty while the instrument had in fact changed.

### D6: a seven-rung cost ladder, free rungs before metered ones

- **Choice**: run the rungs in order, each with an exact command and an executable pass criterion, with model spend confined to the last rung and reduced there to one short trial per cell.
- **Rationale**: rungs 0 through 5 spend no model calls and rung 6 is the only metered one. Only the adapter registration copy needs a real agent invocation to witness. Every adapter's registration command is built inside `run()` rather than `setup()` — for Claude Code, `_build_register_skills_command` at `claude_code.py:1530-1542` is appended to `setup_command` at `:1733-1735`, both inside `async def run` which begins at `:1601` — and `--install-only` skips the agent run: `Trial.run` guards `self._run()` on `not self.config.install_only` (`trial.py:375-378`), and `TrialConfig._install_only_disables_verification` (`models/trial/config.py:484-494`) also disables the verifier. So `--install-only` (`cli/jobs.py:901-910`) provably cannot substitute for the metered rung, and everything else is reachable for free.
- **Alternatives considered**: proving delivery from the trial lock, which is refuted by the `trial.py:104` / `:107` / `:411` ordering above; and running the metered rung first as a smoke test, which is how a daemon capability or an authoring error becomes an expensive discovery.

### D7: two package directories, BenchFlow-native authored and the Harbor head derived

- **Choice**: author `task.md` + `oracle/` + `verifier/` natively, then derive `<task-id>-harbor` with `bench tasks export` into a sibling directory, and never hand-edit the derived head.
- **Rationale**: three independent validators forbid the co-present form. BenchFlow's `--level publication-grade` rejects a co-present `task.toml` or `instruction.md` beside `task.md` (benchflow `src/benchflow/_utils/task_authoring/structural_checks.py:208-212`) and rejects `solution/` in favour of `oracle/` (`:218-222`). SkillsBench's corpus gate forbids exactly `instruction.md`, `task.toml`, `solution` and `tests` (skillsbench `.github/scripts/validate_tasks.py:21-26`), which is the set Harbor requires. And the corpus is uniformly native: all 87 tasks under `tasks/` carry `task.md` with zero `task.toml` and zero `solution/`, reproduced here at the pinned revision.
- **Alternatives considered**: one directory carrying both heads, which fails publication-grade by construction; and maintaining two hand-written trees, which drifts.

### D8: the canary asserts delivery where delivery is observable, per adapter

- **Choice**: the canary package asserts, on the BenchFlow arm, that the in-container skill catalogue equals the host-computed one, and on the Harbor arm that the adapter's own destination directory carries the skill after a metered trial. No single assertion is written for the whole grid.
- **Rationale**: the destinations differ per adapter — claude-code copies into `$CLAUDE_CONFIG_DIR/skills/<name>/` with `CLAUDE_CONFIG_DIR` set to `EnvironmentPaths.agent_dir / "sessions"` at `claude_code.py:1718`, which resolves to `/logs/agent/sessions` since `agent_dir` is `logs_dir / "agent"` at `models/trial/paths.py:36`; codex writes `$HOME/.agents/skills/<name>/` (`codex.py:1199-1207`); pi writes the same path (`pi.py:75-83`); and opencode writes `~/.config/opencode/skills/<name>/` (`opencode.py:425-433`).
- **Free consequence exploited, superseded for the metered cell**: claude-code's destination sits inside the `/logs/agent` bind mount (`trial.py:1284-1288`), so what the adapter registered is readable on the host after the run with no verifier code at all. That was the cheapest per-adapter assertion available and the original reason claude-code was named the first metered cell; the settled decision names codex on the ChatGPT-subscription path as the metered adapter instead, and codex's `$HOME/.agents/skills/<name>/` destination sits in no bind mount, so its assertion is made in-container (D8's per-adapter scope is unchanged).
- **Scope of the Harbor-arm assertion**: it is the destination directory alone and deliberately not the reward. The original reason — that a real agent could reach the token through the shared verifier — does not hold and is corrected in D11; the surviving reason is stronger and adapter-independent. A model-driven trial's reward conflates delivery with the model's own behaviour, because a model that never greps the discovery roots scores 0 with the skill perfectly delivered, so only the registration directory is a deterministic witness.

### D9: the cost constant is measured, not estimated, and recorded with its conditions

- **Choice**: the per-run cost is taken from the metered rung's own job accounting and recorded together with the cell, the model, the task, the trial length, the auth mode, and the instrument version.
- **Rationale**: a bare number without its conditions cannot be multiplied into a budget honestly, since a cost per run is a function of the cell and the task, not of the runner.
- **Scope boundary**: recording the constant is in scope, multiplying it into a program budget is not.

### D10: verification runs through the runners, and no Gherkin layer is introduced

- **Choice**: each ladder rung is witnessed by the runner's own artifact — a docker exit status, a python-level refusal, `bench tasks check`'s issue list, a reward file, or a directory listing taken inside the trial container — recorded in tasks.md and verify.md. No `.feature` files and no step-definition runner are added.
- **Rationale**: this is a Gate 0 verdict rather than a per-proposition Gate 1 one, and the Gate 1 section below records it as such. Gate 0 asks whether the change has an external observable a non-implementer stakeholder would recognize, and every observable here is a CLI flag, a container path or a reward file, so a scenario's steps could name nothing except the machine. That is Gate 0's own tell for a forced outer loop, and its own prescribed response is to drop out of the outer loop rather than launder structure through Gherkin. Every ladder proposition then routes, at Gate 1, to the one row that leaves BDD by construction: an assertion that an upstream Harbor or BenchFlow API still fits is dependency compatibility, witnessed by the runner that already exercises it.
- **Alternatives considered**: binding the rungs through pytest-bdd with steps that shell out to `docker`, `bench` and `harbor`, which adds a runner and a traceability guard to a change whose deliverables are evaluation packages, and whose scenarios would restate their own commands.

### D11: both packages run a shared verifier, and the agent-to-verifier channel is `/logs/verifier`

- **Choice**: both packages declare no `verifier.sandbox_mode` and ship no `verifier/Dockerfile`, so both run shared, and each writes its deliverable under `/logs/verifier` where its verifier reads it. Separate mode is exercised nowhere in this change; the earlier plan to exercise it on the mechanical package is withdrawn, and the reason it was withdrawn is recorded here rather than dropped.
- **Rationale**: the fork is forced rather than preferred, and each runner forces it independently. The original reading of BenchFlow was wrong in a way worth recording, because the source sentence invites it: "separate verifier sandboxes are parsed but not executed" is the reason string of a refusal, not a description of a fallback. `runtime_capabilities.py:186-192` raises an unsupported-feature issue and `raise_for_task_runtime_support` is a fail-closed pre-launch gate (`sandbox/setup.py:676`, `:819-842`), so a package declaring separate does not run shared under BenchFlow — it does not launch at all. Reproduced with `bench tasks check <pkg> --level runtime-capability --sandbox docker`, which exits 0 on both packages as shipped and reports that issue the moment `verifier.sandbox_mode: separate` is added. Since D7 authors one `task.md` per package and the proposal requires the mechanical package to pass under both runners, separate mode and a runnable BenchFlow arm are mutually exclusive at benchflow 0.7.4.
- **Second and independent reason, which also refutes the channel-survives argument**: Harbor's separate verifier empties `/logs/verifier` before running, `await target_env.empty_dirs([env_paths.verifier_dir], chmod=True)` at `trial.py:599`, through the same host bind it mounts at `:686-692`. The bind is real and the channel still does not survive, because the content is deleted rather than the mount dropped, so every agent including the oracle would score 0. The only separate-mode-safe channel is `/logs/artifacts/`, which the artifact re-upload restores after the wipe (`trial.py:601-607`, `artifact_handler.py:210-254`); moving a deliverable there is a task-contract change rather than a fork choice.
- **Why `/logs/verifier` rather than the workspace**: it is bind-mounted into the agent environment (`trial.py:1279-1283`), `_run_shared_verifier` (`trial.py:536-567`) performs no wipe and Harbor does not clear it before reading the reward (`verifier/verifier.py:199-236`), and it is BenchFlow's standard verifier contract path. A package that wrote to a workspace path such as `/app` would pass under one runner and fail under the other, which is the most confusing failure available to a change whose purpose is removing that confound.
- **Cost that was accepted and does not arise**: the shared fork was taken to expose the verifier to the agent under test. It does not. Both runners upload the verifier's own directory during the verification phase, after the agent phase has ended — Harbor at `verifier/verifier.py:147-153`, reached from `_run_shared_verifier`, with the phase order fixed at `trial/single_step.py:41` then `:52`; BenchFlow at `task/verifier_core.py:385`, inside `verify()`. The mechanical package's verifier therefore holds its expectation as a literal without leaking it, and rung 6 still declines to read the canary's reward — because a model-driven trial's reward conflates delivery with the model's own behaviour, not for the reason originally given.

### D12: the environment baseline is public and `no-network` is an agent-phase override

- **Choice**: every package declares `network_mode = "public"` at `[environment]` and puts `no-network` on the `[agent]` phase, dropping the phase override entirely when the kernel probe reports the option unset.
- **Rationale**: the baseline is what the container is created with (`trial.py:896`), while the phase policy is applied around `_run_agent_phase` alone (`trial.py:465-469`) and around the verifier phases. claude-code's `install()` curls its bootstrap during `_prepare`/`_setup_agent` (`trial.py:408-414`), which no policy wraps, so a `no-network` baseline breaks the one metered rung during agent install while a `no-network` agent phase leaves it intact. Harbor reads the override through `task_cfg.agent.explicit_phase_policy()` (`trial/network_policy.py:45-59`) and validates the switch at `trial.py:203-217`; BenchFlow carries the same field at `task/config.py:524-530`.
- **Correction encoded**: `no-network` is the harborize instrument's authoring default (`SKILL.md:124`, `references/emitters.md:74`), not Harbor's. Harbor's default is `public` (`models/task/config.py:249-252`), BenchFlow's is the same (`task/config.py:720-723`), and 86 of the 87 SkillsBench corpus tasks declare `network_mode: public`. The kernel probe therefore gates whether a `no-network` declaration can be *enforced*, not whether a package can be authored at all.
- **Alternatives considered**: baking the agent into the environment image at a pinned version so `_installed_claude_satisfies_version` returns early and the fetch is never reached, which the instrument itself prescribes at `SKILL.md:169`. It works and costs an image build per agent version; the phase override achieves the same result with no build and is reversible per probe outcome.

### D13: the corpus lives at `modules/home/ai/evals/harborize/` and carries no `.nix` file

- **Choice**: the package corpus is co-located with the skills it evaluates, at `modules/home/ai/evals/harborize/`, tracked in version control, with job output at `logs/harborize/` which `.gitignore:57` already excludes. No file inside the corpus carries the `.nix` extension.
- **Rationale**: co-location puts the measurement beside its subject, since the source of truth for every first-party skill under evaluation is `modules/home/ai/plugins/`. The location was verified against each automated surface that walks `modules/` rather than assumed safe. import-tree is called bare at `flake.nix:6` with no custom filter, so its default `nixFilter = andNot (hasInfix "/_") (hasSuffix ".nix")` (import-tree `default.nix:50`, rev `4ebb10ae17d5f1ad366e7aef5b92cb8eecf24f69`) enumerates non-nix files and drops them before anything reads them, which is why `modules/` already carries 444 non-nix files and the flake evaluates. `naming-conventions` (`modules/checks/validation.nix:186-205`) validates machine names read from `self.nixosConfigurations` and never filenames. treefmt enables only `programs.nixfmt` (`modules/formatting.nix:13`), scoped to `*.nix`, so byte-sensitive fixtures are untouched. The apm composition scans `modules/home/ai/plugins` one level deep gated on a `.apm/skills` child (`pkgs/by-name/apm-skills-compose/package.nix:11-19`), so an `evals/` sibling is outside it.
- **Consequence**: the same filter that makes every other extension safe makes `.nix` unsafe, because a `*.nix` file anywhere under `modules/` is imported and evaluated as a flake-parts module. A fixture named `expected.nix` is the realistic trap, and it would break the flake rather than fail as a fixture. Two escapes exist and either one is sufficient: no `.nix` extension on a fixture, or a `_`-prefixed directory, which is this repository's documented exclusion convention (ADR-0018, `packages/docs/src/content/docs/development/architecture/adrs/0018-deferred-module-composition-architecture.md:311`).
- **Enforcement**: an extension audit plus `nix eval .#nixosConfigurations --apply builtins.attrNames` runs when the corpus root is first written and again once the package directories and the generated Harbor heads exist, because a constraint with no check is a comment. The guard covers the generated heads too, since two of the four package directories are written by `bench tasks export` rather than authored by hand.
- **Alternatives considered**: a repository-root `evals/` directory, which is outside every `modules/` walker and so carries no `.nix` hazard, and which separates the corpus from the skills it measures; and a `_`-prefixed directory under `modules/`, which removes the hazard outright at the cost of marking the corpus as excluded machinery rather than as tracked content.

## Gate 1 modality verdicts

Gate 0 excludes this change from the outer loop as a whole.
The gate asks whether the change has an external observable a non-implementer stakeholder would recognize and care about, and this change's every observable is a container path, a CLI exit status or a reward file.
Its own tell for a forced outer loop — a scenario whose steps name functions, tables or endpoints — is unavoidable here, so no acceptance stream and no `.feature` file is laid out.
Gate 1 is still recorded per requirement below, because the modality column is what the pre-apply and before-archive machine checks read.

Every ladder requirement routes to the same Gate 1 row, `Dependency compatibility / import smoke`, and therefore to `smoke`.
That is the accurate class rather than a convenient one.
Each of these propositions asserts that an upstream API in Harbor or BenchFlow still fits — which adapters consume an injected directory, that host-side resolution still returns digests, that the oracle path still deploys skills, that the adapter still copies into its destination.
The change exists precisely because those are facts about two pinned upstreams that the instrument read from source and never exercised.

| Requirement | Proposition class | modality | Runner and witness |
|---|---|---|---|
| Environment prerequisites are established before authoring | Dependency compatibility / import smoke | `smoke` | `docker run` exit status and the kernel-probe exit status; `harbor --version` / `bench --version` |
| The evaluation corpus does not break flake evaluation | Dependency compatibility / import smoke | `smoke` | no `.nix` file inside the corpus, and `nix eval .#nixosConfigurations --apply builtins.attrNames` exits 0 |
| Harbor cells name only skill-consuming adapters | Dependency compatibility / import smoke | `smoke` | `scripts/design_matrix.py` exits nonzero naming the adapter |
| Host-side skill resolution is proven before any container starts | Dependency compatibility / import smoke | `smoke` | `harbor.skills.resolve_skills` output: one entry per expected skill, each with a sha256 |
| Both task heads pass their static gate | Dependency compatibility / import smoke | `smoke` | `bench tasks check --level structural` exit 0; `harbor.models.task.task.Task(<dir>)` constructs |
| Skill delivery is proven in the container with no model call | Dependency compatibility / import smoke | `smoke` | `bench eval run --agent oracle` reaches the agent phase and reward == 1 |
| The oracle inhabits the task under Harbor | Dependency compatibility / import smoke | `smoke` | `harbor run` reward 1.0 across five trials, zero errored trials, `agent/exit-code.txt` absent or 0 |
| Adapter registration is asserted per adapter | Dependency compatibility / import smoke | `smoke` | the adapter's destination directory carries the skill, asserted in-container for codex at `$HOME/.agents/skills/<name>/`, which sits in no bind mount |
| The injection canary is retained in the corpus permanently | none — Gate 0 excluded | `none` | the canary package is present and its run is listed in the round's manifest |
| The per-run cost constant is recorded with its conditions | none — Gate 0 excluded | `none` | the results file carries the constant, the cell, the auth mode and the instrument version |
| Packages and results are stamped with the instrument version, and the instrument is unmodified | none — Gate 0 excluded | `none` | each package README stamps 0.2.1; the harborize directory digest matches its recorded baseline |

The last three rows carry no Gate 1 modality at all, and `none` says so rather than inventing a token.
They are a corpus property over time, a recorded derived number, and a provenance property; none is an operation with an observable, so Gate 1 has nothing to route and they are witnessed by reading the artifact at the review gate.

No row carries `bdd-scenario`, so the pre-apply feature-layout arm of the spec-and-feature alignment sub-gate no-ops for this change.
No row carries `est-property`, `est-contract` or `est-symbolic`, so the executable-specification arm no-ops as well.
`smoke` is the Gate 1 vocabulary's own name for the regression-or-smoke destination and carries no expectation of a `.feature` file or an EST artifact.

## Risks / Trade-offs

- [Risk] The Docker daemon's kernel lacks `CONFIG_NFT_FIB_INET`, so Harbor rejects any `no-network` policy at environment start. On failure `_enable_egress_control` goes false (`src/harbor/environments/docker/docker.py:188-195`), which zeroes `capabilities.disable_internet` (`:289-293`), and `src/harbor/environments/base.py:773-781` raises. A task carrying `no-network` at its baseline then fails at environment start and reads as an authoring error. → Mitigation: the probe is a blocking task with its own checkbox, run immediately after the daemon starts and before any task is authored, and it branches three ways rather than halting. It is anchored (`grep -qE '^CONFIG_NFT_FIB_INET=[ym]'`) so its exit status is its criterion, because an unanchored search matches `# CONFIG_NFT_FIB_INET is not set` and exits 0. Exit 1 drops the `[agent]` phase override and leaves every package fully public, which is Harbor's own default and the corpus norm. Exit 2, an absent `/proc/config.gz`, is indeterminate rather than negative: Harbor's own probe short-circuits to exit 0 in that case (`docker.py:113-117`), so the change proceeds with Harbor and treats a later rejection as the deciding evidence.
- [Risk] A claude-code cell whose environment *baseline* is `no-network` fails during agent install rather than during the agent phase, indistinguishably from an injection failure at the reward level. `_prepare` calls `_setup_agent` at `trial.py:408-414` with no policy wrapper, while only `_run_agent_phase` (`trial.py:465-469`) and the verifier phases enter `_phase_network_policy`. → Mitigation: D12, carried as its own authoring task rather than as advice. Every package declares `network_mode = "public"` at `[environment]` and confines `no-network` to the `[agent]` phase, and the metered rung's own checklist re-reads the exported head's `[environment]` table before spending. Baking the agent into the image at a pinned version (`SKILL.md:169`) remains available and is not taken, because it costs an image build per agent version and the phase override is reversible per probe outcome.
- [Risk] A broken oracle scores 0 without raising, because `OracleAgent.run` writes `exit-code.txt` on a nonzero return and proceeds to the verifier (`agents/oracle.py:149-151`). Reading rewards alone cannot separate it from a genuine zero. → Mitigation: the Harbor rung's pass criterion checks both the reward and the presence of `exit-code.txt`.
- [Risk] A trial dies on the first exception, because `RetryConfig.max_retries` defaults to 0 (`models/job/config.py:282-284`). Four further exceptions kill a trial without appearing in the nine-name no-retry list at `:288-300`: `AddTestsDirError` (`verifier/verifier.py:19`), `DownloadVerifierDirError` (`:27`), and a bare `FileNotFoundError` from `_resolve_tests` or from a missing solve.sh (`agents/oracle.py:94-95`). → Mitigation: triage reads the exception name first. Four of the nine listed names are defined in `agents/installed/base.py`, which `OracleAgent` does not subclass, so any of them appearing in an oracle rung's log means the job was not running the oracle.
- [Risk] The canary's answer key is flagged by the instrument's own leakage audit, since the same literal must appear in the verifier and in the SKILL.md and `scripts/audit_leakage.py` check 1 searches for quoted expectation strings of eight characters or more (`MIN_LITERAL_LENGTH` at `:44`, `check_literals` at `:96`). → Mitigation: record the flag with its reasoning in the package README rather than suppressing it; the audit is correct on its terms and the canary is an instrument-integrity test whose mechanism is the answer key. The instrument-side question is deferred under D5.
- [Risk] The fidelity assertion the delivery rung relies on cannot be exercised by editing `dir(C)`. `_skill_link_cmd` replaces each discovery path with a symlink to the uploaded source (`agents/install.py:90`), which makes the `actual == source_catalog` test at `:157` tautological, and a `--skill-mode no-skill` run cannot raise the error either, because `expected_skill_names` is empty when `skills_dir` is falsy (`:313-317`) and the raise is guarded on `if expected:` (`:176-180`). Without a working control, a green delivery rung proves only that nothing crashed. → Mitigation: two distinct controls rather than one. A falsifiability control (`--skill-mode no-skill`, reward 0) proves the canary is not a constant, and a fidelity control against a throwaway sibling whose `environment/Dockerfile` carries a hand-written `COPY _deps/skills /skills/` line over a different `_deps/skills` tree makes `deploy_skills` take the `already_injected` branch (`:328-332`, `:342-344`), so the container's catalogue and the host-computed `expected` diverge and `:159-161` fails.
- [Trade-off] A multi-dimensional rubric would carry more information per run and would disable both headline statistics: Harbor computes pass@k only when every trial carries exactly one reward key valued 0 or 1, and BenchFlow's compare-lift counts only `reward == 1.0` as passed (`src/benchflow/eval_lift.py:32-33`). → Accepted: a single binary reward key throughout this change.
- [Trade-off] Keeping the canary in the corpus permanently adds a task that measures no capability. → Accepted: it is the only artifact that fails when the injection path regresses.
- [Trade-off] The metered rung buys one number and one per-adapter assertion rather than a measurement. → Accepted: this change's output is an instrument and a constant, and the measurement is the dependent change.

## Migration Plan

There is no deployment surface: no machine configuration, endpoint, schema or nix output changes.
The work is additive and reversible in the ordinary sense, in that the packages are new directories and the instrument is untouched.

Sequencing follows the ladder, and the ordering is load-bearing rather than a preference.
The prerequisites rung comes first because the ladder cannot start without a daemon and the two CLIs, and because the kernel probe decides whether the `[agent]` phase override in D12 can be declared at all by every task authored after it.
The five free rungs then run before any container carrying a model, and the metered rung runs last on one short trial per cell.
Rollback for the metered rung is to stop after it and report the constant; rollback for the change as a whole is to leave the packages unrun, since nothing outside the change directory is modified.

Integration is jj-native onto the existing `harborize-instrument` bookmark, whose four commits are the 0.2.1 instrument this change validates and which is already a parent of the development join.
Isolation is the development join rather than a worktree.

## Open Questions

These three are open and are recorded rather than resolved.
Each carries its options and what each option costs, so a later session can decide rather than infer.

### Where pi and opencode actually discover skills

Harbor and BenchFlow declare different destinations for the same agent.
Harbor's pi adapter writes `$HOME/.agents/skills/<name>/` (`pi.py:75-83`) while BenchFlow's registry declares `["$HOME/.pi/agent/skills", "$HOME/.agents/skills"]` for `pi-acp` (benchflow `src/benchflow/agents/registry.py:560`), a superset.
Harbor's opencode adapter writes `~/.config/opencode/skills/<name>/` (`opencode.py:425-433`) while BenchFlow declares `["$HOME/.opencode/skills"]` (`registry.py:700`), which does not overlap.
Codex is the one cell where both agree, at `$HOME/.agents/skills`.

Three resolutions, in increasing cost.
Declare those two cells' cross-runner numbers non-comparable, which costs nothing and forfeits two cells of the grid.
Clone the three CLIs and read which path each discovers, which costs reading time and settles the question statically for the pinned CLI versions.
Run a behavioral canary per cell, which costs one metered trial per adapter and settles it for the versions actually installed in the image.
This change takes the first option for its own reporting and leaves the other two to the dependent change.

### Whether the oracle rung adopts BenchFlow's acceptance level

BenchFlow ships an `acceptance` validation level whose evidence block requires `oracle_runs.required_reward` to be numeric and at least 0.99 (benchflow `src/benchflow/_utils/task_authoring/acceptance_evidence.py:104-107`), `verifier.reruns` to be an integer of at least 3, and `verifier.flake_rate` to be numeric and at most 0.05 (`:172-178`).
It overlaps the bespoke five-times oracle loop the instrument's inhabitation invariant already requires, and it is a declared evidence block rather than an executed check.

The cost of adopting it is that it has zero adoption across the corpus: no task under `tasks/` declares a `benchflow.evidence` block, so the block would have to be written from the validator source rather than copied from a worked example, and its field names and shapes would be inferred from `acceptance_evidence.py` alone.
The cost of not adopting it is that the package cannot claim the level, and a later publication-grade or acceptance run has to add the block anyway.
Left open; the ladder's own five-times criterion is what this change enforces either way.

### Whether the leakage audit should exempt an integrity canary

Any delivery canary asserting a token places the same literal in the verifier and in the SKILL.md, which `audit_leakage.py` check 1 flags by construction.
The flag is correct: the check searches for a verifier expectation recoverable from skill content, and here it is recoverable by design.
Adding an exemption is an instrument modification and D5 forbids it during this round.

The options for the next revision are to add an explicit canary exemption keyed on a package-README declaration, to leave the flag and require the README to carry the justification, or to redesign the canary so the asserted literal is generated at fixture-build time and never appears in the skill.
The third is the only one that removes the flag without weakening the audit, and it costs a fixture-generation step in the canary's environment Dockerfile.
This change takes the second option for now and records the choice in the package README.
