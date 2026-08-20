# Dual emission: one authored tree, one exported head

Canonical content: the instruction body, `environment/Dockerfile`, one solver script, one verifier script and its checks.
The Harbor head is metadata plus naming shims over that content.
Author the BenchFlow-native tree, derive the Harbor head with `bench tasks export` into a sibling directory, and validate each head with the gate that can run against its layout.
Deriving rather than maintaining two trees is what keeps the heads from drifting; the two cannot share a directory, for the reasons under "Two heads, two directories" below.

## Verified against

Every claim below was read out of these clones at these revisions.

| repo | path | revision | date |
|---|---|---|---|
| Harbor | `~/ghq/github.com/harbor-framework/harbor` | `ac398bbda7c4c1073461797d3b95c2455cc671b5` | 2026-08-12 |
| BenchFlow | `~/ghq/github.com/benchflow-ai/benchflow` | `d30527b82027a416e72014920cdf43a534967ad3` | 2026-08-12 |
| SkillsBench | `~/ghq/github.com/benchflow-ai/skillsbench` | `9a1f4dd5f7659f75707435da3ce854b6e48321d1` | 2026-07-23 |

These are shallow clones sitting at HEAD rather than at released tags, so a line anchor is only valid at the revision above.
Re-read before trusting an anchor.

The task schema is moving under both heads and the two heads are on different numbers.
Harbor's `TaskConfig.schema_version` defaults to `"1.4"` (`src/harbor/models/task/config.py:796`); the field is a plain `str` with no enum, no range check and no compatibility gate, and the only migration it performs is renaming a legacy `version` key to `schema_version` (`config.py:824-828`).
Harbor's own example packages still declare `schema_version = "1.3"` (`examples/tasks/separate-verifier-environment/task.toml:1`), and all 87 shipped SkillsBench tasks declare `schema_version: '1.3'` in their `task.md` frontmatter.
Emitting 1.3 against a 1.4 Harbor is therefore valid and matches the SkillsBench corpus.

## Two heads, two directories

Author the package BenchFlow-native and derive the Harbor head into a separate sibling directory.
This is the sanctioned route rather than one option among several, because the two heads cannot share a directory.

Three independent validators forbid the co-present form.
BenchFlow's `--level publication-grade` rejects a `task.toml` or `instruction.md` beside `task.md` (`src/benchflow/_utils/task_authoring/structural_checks.py:208-212`) and rejects `solution/` in favour of `oracle/` (`:218-222`).
SkillsBench's corpus gate forbids exactly `instruction.md`, `task.toml`, `solution` and `tests` (`.github/scripts/validate_tasks.py:21-26`), which is precisely the set Harbor requires.
And the corpus itself is uniformly native: all 87 tasks under `tasks/` carry `task.md` and `oracle/solve.sh` with zero `task.toml` and zero `solution/`, as do the 14 under `tasks-extra/`.

`bench tasks export <task-dir> <out-dir> --target harbor` performs the derivation (benchflow `src/benchflow/cli/tasks.py:281`, `src/benchflow/task/export.py:266-286`).
It writes `task.toml` and `instruction.md` from `task.md`, copies `oracle/` to `solution/`, copies `verifier/` to `tests/`, copies `environment/` verbatim, and emits `compatibility/export-report.json` naming everything that did not survive the conversion.
`--report-only` prints that report without writing files, and `--overwrite` replaces an existing export directory.
The destination may not overlap the source in either direction (`export.py:242-251`); the export refuses rather than deleting source trees it has not yet copied, which is also why the Harbor head is a sibling and never a subdirectory.

So the native tree is the single source of truth, the export is a build product, and the loss report is machine-readable.
Re-export after every edit to the native tree and never hand-edit the Harbor head, whose contents are overwritten.
Hardlinks or a sync step remain the fallback only for a package inherited Harbor-first.

The export copies `environment/` verbatim, `environment/skills/` included.
Keep that directory empty in the canonical package: conditions are injected at run time, and a populated `environment/skills/` bakes one condition into the image.

## Shared to Harbor head

```
task.toml                 # metadata below
solution/solve.sh         # from oracle/solve.sh
tests/test.sh             # from verifier/test.sh (+ checks.py, judge.toml)
tests/Dockerfile          # required by separate mode; see below
```

task.toml essentials (full detail: harbor repo `skills/create-task/SKILL.md`):

```toml
schema_version = "1.3"
[task]
name = "<org>/<task-id>"; version = "1.0.0"
description = "..."; keywords = ["skills-eval", "<domain>", "rewardkit|pytest"]
[metadata]
difficulty = "easy|medium|hard"; category = "..."; tags = ["..."]
[agent]
timeout_sec = 900.0
[verifier]
timeout_sec = 900.0
environment_mode = "separate"          # one branch of a per-task fork
[verifier.environment]                 # declaring this table at all implies separate
network_mode = "public"                # only if judge/API needed, else no-network
[environment]
network_mode = "no-network"            # agent baseline; override per task need
cpus = 1; memory_mb = 4096; storage_mb = 10240
```

The verifier environment is a per-task fork recorded in the package README, not a default.
`_resolve_mode` returns the explicit `environment_mode` when one is set, otherwise infers `separate` from the presence of a `[verifier.environment]` table, otherwise defers; `resolve_task_verifier_mode` falls back to `shared` (harbor `src/harbor/models/task/verifier_mode.py`).
A shared-mode package therefore omits the `[verifier.environment]` table entirely rather than declaring it beside `environment_mode = "shared"`, because the table's presence is itself the separate-mode trigger whenever the explicit key is absent.
SKILL.md Phase 2 carries the fork and its leak consequences.

Network layering: `[environment].network_mode` is the agent baseline, `[agent]` and `[verifier]` are phase overrides, and `allowlist` mode takes `allowed_hosts` as hostnames or CIDRs rather than URLs.
Keep the agent offline unless the skill's contract requires network.

## Separate mode requires a verifier image that owns /tests/test.sh

`environment_mode = "separate"` constructs the verifier environment with `skip_tests_upload=True` (harbor `src/harbor/trial/trial.py:609-619`), and the verifier's `_resolve_tests` then returns an empty upload list on the stated grounds that "the verifier image already owns `/tests/test.{sh,bat}`" (`src/harbor/verifier/verifier.py:96-103`).
Harbor never uploads `tests/` in this mode, so the image must already contain the script.

The build context for that environment is the task's `tests/` directory (`trial.py:694-702`, `_verifier_env_build_context`), so `tests/Dockerfile` is what gets built.
Declaring `docker_image` in `[verifier.environment]` defeats this: `should_use_prebuilt_docker_image` returns True whenever `docker_image` is set and `force_build` is false (`src/harbor/environments/definition.py:26-36`), the Dockerfile is skipped, and the stock image runs with no `/tests/test.sh` and no way to acquire one.

The same reasoning extends past the test script to everything it invokes.
Harbor uploads nothing into a separate verifier environment, so the image must itself carry every interpreter and every tool the wrapper calls.
A wrapper that shells out to `uvx` in an image with no uv writes no reward file, the absent reward file raises `RewardFileNotFoundError`, and that exception sits in Harbor's default no-retry list (`src/harbor/models/job/config.py:289-300`), so every trial fails permanently.
Install the verifier's tooling at image build time and invoke it directly rather than resolving it at run time, which also keeps the verifier environment runnable with `network_mode = "no-network"`.

So a separate-mode package omits `docker_image` from `[verifier.environment]` and ships a Dockerfile that both installs the tooling and places the scripts.
For a Reward Kit verifier:

```dockerfile
FROM python:3.12-slim

RUN pip install --no-cache-dir 'harbor-rewardkit==0.1.*'

COPY --chmod=755 test.sh /tests/test.sh
COPY checks.py judge.toml /tests/
```

`harbor-rewardkit` installs a `rewardkit` console script (harbor `packages/rewardkit/pyproject.toml:37-38`), so `test.sh` calls `rewardkit /tests` with no `uvx` involved.
For a pytest verifier, swap the install line for `RUN pip install --no-cache-dir pytest==8.4.1`, drop the second `COPY`, and add `test_outputs.py` to the first.
Harbor's own separate-verifier examples take the same shape from the other direction: `examples/tasks/separate-verifier-environment/tests/Dockerfile` pairs `FROM ubuntu:24.04` with a pure-bash `test.sh` that invokes no interpreter at all.

Author this file at `verifier/Dockerfile` in the native tree; `bench tasks export` lands it at `tests/Dockerfile`.

## Skill injection under Harbor

`--skill <path>` (alias `--skills`) is the injection mechanism (harbor `src/harbor/cli/jobs.py:642-653`, on the `start` command that `harbor run` aliases at `src/harbor/cli/main.py:164`).
It is repeatable, and each value is a host path or a git source, meaning `org/name`, `org/name@ref`, or a full URL.
`resolve_skill_sources` takes the local-path branch when the path exists or the value starts with `.`, `/` or `~`, and only otherwise tries git resolution (`src/harbor/skills.py:126-176`), so an existing relative path passes through unchanged and a relative path that does not exist relative to the working directory is parsed as a git source.
Prefix relative paths with `./` to stay on the local branch either way.

A path value may be either a single skill directory containing `SKILL.md`, or a root whose immediate child directories each contain one; a non-hidden child directory without `SKILL.md` is a hard error, while files and dot-directories at the root are ignored (`skills.py:382-416`).
Skill names come from directory basenames and duplicates resolve last-wins.

The flag populates `AgentConfig.skills`, which the trial resolves (`trial.py:1142-1145`) and uploads per trial into `<skills-dir>/<skill-name>/` (`trial.py:1179-1204`).
The destination defaults to `/harbor/skills` (`src/harbor/models/trial/paths.py:41`) unless the task sets `[environment].skills_dir`, which must then be absolute or the trial raises (`trial.py:1162-1177`).
Injection also SHA-pins each skill into the trial's lock, recording name, source, content digest, and the git URL and commit id when the source sits in a repository (`src/harbor/models/job/lock.py:141-146`, `:462-475`), which is provenance worth having on its own.
The lock records the host, not the container.
`_write_trial_lock` runs in `Trial.__init__` at `trial.py:104`, ahead of `_resolve_injected_skills` at `:107` and far ahead of `_upload_injected_skills` at `:411`, and `_build_agent_skill_locks` calls only host-side functions.
So the lock is written before anything is uploaded and stays fully populated through an upload failure, a permissions failure, or an adapter that never reads the directory.
What it proves is that the paths resolved on the host and what their contents digested to.

`--ak skills_dir=<path>` is not an injection mechanism and must never be used as one.
`skills_dir` is an agent constructor kwarg documented as "Skills directory path in the environment" (`src/harbor/agents/base.py:75`), meaning container-side.
A skills-aware adapter uses it as the source of an in-container copy, for instance Claude Code's `cp -r <skills_dir>/* $CLAUDE_CONFIG_DIR/skills/ 2>/dev/null || true` (`src/harbor/agents/installed/claude_code.py:1530-1542`).
Passing a host path there names a directory that does not exist inside the container, the redirect and `|| true` swallow the failure, and the run exits 0.

The failure signature is that every condition becomes identical to the empty condition.
All first differences collapse toward zero, second differences follow, nothing in the pipeline raises, and the numbers look like a real negative result.
The trial lock catches this particular defect, because `--ak skills_dir=` never populates `AgentConfig.skills` and the lock's `skills` list therefore comes out empty while the condition asked for units.
`scripts/collect_rewards.py` reads that list per trial and refuses the batch when it disagrees with the condition.
The check is one-sided, for the reason given above: a populated lock is host-side resolution, so it rules out this defect and not the delivery failures that follow it.

The two settings can also collide.
The trial passes its own resolved `skills_dir` into the agent constructor (`trial.py:838-839`) and the factory merges with trial kwargs last (`src/harbor/agents/factory.py:183`), so whenever real injection or a task-level `environment.skills_dir` is in play, an `--ak skills_dir=` value is silently overridden.

## The silent-adapter class

Injection uploads regardless of adapter, but registration is adapter-specific.
Of the 39 agents the factory registers, 22 read the injected directory and 17 ignore it with no error, no warning and no log line.
The two commands that establish those figures:

```
rg -c 'AgentName\.[A-Z_0-9]+: ' src/harbor/agents/factory.py       # 39
rg -l 'self\.skills_dir' src/harbor/agents/ --type py              # 23
```

The second returns 23 files, being the 22 adapters plus `agents/base.py:85`, which is the definition site.
Map each module back to its registry name through `factory.py`, because the two differ: `qwen_code.py` is registered as `qwen-coder` and `installed/cline/cline.py` as `cline-cli`.

Consuming: antigravity-cli, antigravity-sdk, claude-code, cline-cli, codex, copilot-cli, cursor-cli, eve, fx, gemini-cli, goose, grok-build, hermes, kimi-cli, kimi-code, mimo, openclaw, opencode, pi, qwen-coder, terminus-2, vibe.

Non-consuming: acp, aider, computer-1, cortex-code, deerflow, devin, dspy-rlm, langgraph, mini-swe-agent, nemo-agent, nop, openhands, openhands-sdk, oracle, rovodev-cli, swe-agent, trae-agent.

The narrower glob `rg -l 'skills_dir' src/harbor/agents/installed/*.py` returns twenty and reads as if it were the answer.
It is not the adapter set: it misses `installed/cline/cline.py`, which sits in a subdirectory, and `terminus_2/terminus_2.py`, which sits outside `installed/`, and it counts modules where the question is registry entries.

`acp` is a non-consumer and also a router.
`factory.py:167-175` sends any name matching `is_acp_registry_shorthand`, meaning any name prefixed `acp:`, through `AgentName.ACP`, so an ACP-shorthand cell drops skills on the Harbor arm while the BenchFlow arm for the same agent works.

`scripts/design_matrix.py` refuses to emit a manifest for a cells.json naming a non-consuming Harbor adapter or an `acp:` shorthand, and carries the allowlist as `HARBOR_SKILL_CONSUMING_AGENTS` with the regenerating commands beside it.
That gate is where this class has to be caught: it costs nothing, it runs before any container starts, and no artifact written after the run distinguishes a non-consuming adapter from a working one.

## Where each adapter puts the skills

The destination differs per adapter, so no single canary assertion covers a grid.

| adapter | destination in the container | anchor |
|---|---|---|
| claude-code | `$CLAUDE_CONFIG_DIR/skills/<name>/`, and `CLAUDE_CONFIG_DIR` is `/logs/agent/sessions` | `claude_code.py:1530-1542`, `:1718`; `models/trial/paths.py:36` |
| codex | `$HOME/.agents/skills/<name>/` | `codex.py:1199-1207` |
| pi | `$HOME/.agents/skills/<name>/` | `pi.py:75-83` |
| opencode | `~/.config/opencode/skills/<name>/` | `opencode.py:425-433` |

claude-code's destination is the one with a free consequence: `/logs/agent` is bind-mounted from the trial directory (`trial.py:1284-1288`), so whatever the adapter registered is readable on the host after the run with no verifier code at all.

The two runners do not agree on these paths, so a cell's cross-runner comparability is a per-adapter question.
BenchFlow declares `skill_paths` per agent in `src/benchflow/agents/registry.py`: `codex-acp` at `:604` declares `["$HOME/.agents/skills"]`, which is exactly Harbor's codex destination, so codex is the one cell where both agree.
`pi-acp` at `:560` declares `["$HOME/.pi/agent/skills", "$HOME/.agents/skills"]`, a superset of Harbor's single path.
`opencode` at `:700` declares `["$HOME/.opencode/skills"]`, which does not overlap the `~/.config/opencode/skills` Harbor writes.
`claude-agent-acp` at `:518` declares `["$HOME/.claude/skills"]`, where Harbor redirects `CLAUDE_CONFIG_DIR` away from `~/.claude` entirely.
Whether a skill that loads under one runner loads under the other for pi, opencode and claude is an open question this instrument has not settled; do not report a cross-runner contrast on those cells as though it were.

## Shared to BenchFlow head (SkillsBench layout)

```
task.md                   # YAML frontmatter (schema_version '1.3') + instruction body
environment/skills/       # EMPTY in the canonical package; dir(C) is injected
                          #   at run time from outside it
oracle/solve.sh
verifier/test.sh
verifier/Dockerfile       # exports to tests/Dockerfile for separate mode
```

Frontmatter sections: `metadata` (author_name, author_email, difficulty, category, subcategory, plus controlled-vocabulary lists for task_type, modality, interface, skill_type, and free tags), `verifier` (type: test-script, timeout_sec, service, optional hardening like cleanup_conftests), `agent.timeout_sec`, and the sandbox spec.

The sandbox spec is spelled `sandbox` natively, taking network_mode, os, cpus, memory_mb, storage_mb, gpus and build_timeout_sec.
A top-level `environment` table is accepted as a legacy alias and converted (benchflow `src/benchflow/task/config.py:115-122`), but declaring both spellings in one file is a hard error rather than a silent merge.
The inverse conversion is what `bench tasks export` applies so the Harbor head spells it `[environment]` (`config.py:124-141`).

Vocabulary lives in the skillsbench repo's `taxonomy.yaml` and `taxonomy.md`.
Validate with `bench tasks check <task-dir> --level <level>` (benchflow `src/benchflow/cli/tasks.py:93-162`), whose levels are schema, structural (default), runtime-capability, publication-grade, acceptance, and acceptance-live.
It exits 1 with an enumerated issue list and spends no model calls below the acceptance-live level.

Prompt rules enforced by review there and adopted here: imperative prose, end state rather than steps, absolute paths, never mention skills, and anchored dates when answers are time-sensitive.

## Skill injection under BenchFlow, and the asymmetry

`--skills-dir <path>` takes a host path, validated on the host: a path that is not a directory raises `FileNotFoundError: skills_dir not found: <path>` (benchflow `src/benchflow/skill_policy.py:135`).
The directory is uploaded to `/skills` in the sandbox and symlinked into each agent's discovery paths (`src/benchflow/agents/install.py:303-360`); the expected skill set is computed as `<skills-dir>/*/SKILL.md`, so the host directory is a root of skill directories, the same shape Harbor's `--skill` accepts as a root.

`--skill-mode` takes `no-skill` (default), `with-skill`, or `self-gen` (`skill_policy.py:19-27`).
Two combinations are rejected outright: `no-skill` with `--skills-dir` raises "no-skill mode cannot be combined with skills_dir" (`skill_policy.py:128`), and `self-gen` with `--skills-dir` likewise.
So the empty condition is `--skill-mode no-skill` alone, and every non-empty condition is `--skill-mode with-skill --skills-dir <dir(C)>`.
Passing `--skills-dir` under `with-skill` takes precedence over the task's bundled `environment/skills/` and mounts at `/skills`.

The resolved host directory is recorded per rollout as `effective_skills_dir` (`skill_policy.py:60-68`), which is what `collect_rewards.py` requires to be non-null under `with-skill`; `skill_mode` on its own records the request rather than the outcome.

The asymmetry is the reason the Harbor defect survived.
Both runners want the same host directory, but they name the argument differently, and the one whose name reads like a host path is the one that is not.
`--skills-dir` is a host path and fails loudly on a bad one; `skills_dir` under `--ak` is a container path and fails silently on a host one.
A generator that carries the argument across from the bench arm to the Harbor arm produces a run that exits 0 and measures nothing.

## The free delivery canary

BenchFlow's oracle path proves skill delivery end to end and makes no model call.
`rollout/__init__.py:1160` takes the `primary_agent == "oracle"` branch and still calls `deploy_skills` at `:1174`, so the whole deployment path runs while the agent is a shell script.

The assertion is in the container.
`deploy_skills` computes the expected catalogue on the host as `Path(skills_dir).glob("*/SKILL.md")` (`agents/install.py:313-314`) and, with no `agent_cfg` on the oracle path, distributes to `_ORACLE_SKILL_PATHS` — the five discovery paths at `install.py:30-36` covering the claude, codex, opencode, agents and workspace conventions (`:350`).
`_link_skill_paths` then runs one command in the sandbox that links the tree into each path, enumerates `SKILL.md` at depth 2 under both the source and each destination, asserts the two catalogues are equal, and asserts the source catalogue equals the host-computed expected names (`install.py:146-161`).
A mismatch raises `experiment_fidelity/skill_deployment_missing`, naming the expected set (`:176-179`).

```
bench eval run --tasks-dir <task-dir> --agent oracle \
  --skill-mode with-skill --skills-dir /tmp/cond-<id> \
  --sandbox docker --jobs-dir runs/canary/<id>
```

Pass criterion: the run exits 0, no rollout carries `experiment_fidelity/skill_deployment_missing`, and each rollout's `effective_skills_dir` is the host `dir(C)` that was passed.
Run it once per distinct dir(C) shape before any metered batch.

Harbor has no free equivalent.
`--install-only` (`src/harbor/cli/jobs.py:901-910`) runs agent setup and exits, and setup does reach `_upload_injected_skills`, which sits in `_prepare` at `trial.py:411`.
But every adapter's registration copy is built inside `run()`, not `setup()` — `claude_code.py:1733`, `codex.py:1413`, `opencode.py:499`, `pi.py:116` — and `--install-only` skips the agent run.
So the cheapest Harbor evidence still costs a real agent invocation, which is why the adapter allowlist in `design_matrix.py` is a gate rather than a convenience.

## Run lines

Job output is laid out per runner under one root, which is what `scripts/design_matrix.py` emits and what `scripts/collect_rewards.py` reads back as `--harbor-jobs runs/harbor` and `--benchflow-jobs runs/bench`.

Harbor, one line per condition per cell:

```
harbor run -p <task-dir> -a claude-code -m anthropic/<model> \
  -k 3 --n-concurrent 2 \
  --skill /tmp/cond-<id> \
  -o runs/harbor --job-name <cell>__<id>
```

Omit `--skill` entirely for the empty condition.
`-k` is `--n-attempts` (`jobs.py:387-394`), `--n-concurrent` caps concurrent trials (`jobs.py:467-474`), and `--job-name` defaults to a timestamp (`jobs.py:366-371`).
`-o` is `--jobs-dir` (`jobs.py:372-383`) and the job lands at `jobs_dir / job_name` (`src/harbor/job.py:628`); emit it explicitly rather than letting harbor fall back to its configured default, so the manifest records where output went.

`-k 3` interacts with pass@k reporting.
Eligible k values are powers of two and multiples of five up to the minimum attempts per task (`src/harbor/utils/pass_at_k.py:71-84`), so three attempts report pass@2 only.
Choose `-k 4` or `-k 5` if a specific pass@k is the headline.

BenchFlow, one line per condition per cell per repetition:

```
bench eval run --tasks-dir <task-dir> --agent <agent> --model <model> \
  --skill-mode with-skill --skills-dir /tmp/cond-<id> \
  --sandbox docker --concurrency 2 \
  --jobs-dir runs/bench/<cell>__<id>/trial-01
# C = empty  ->  --skill-mode no-skill, and drop --skills-dir
```

There is no `--run-id`; passing one kills the arm at argument parsing, and `--jobs-dir` is the run-labelling option it was standing in for.
`bench eval run`'s options are declared inside its signature at benchflow `src/benchflow/cli/main.py:193-592`, except those that share an `Annotated` alias defined in `src/benchflow/cli/_options.py:16-32` and therefore do not appear literally inside the command body: `--model` at `main.py:270` and `--skill-mode` at `main.py:438` are the two the emitted run line depends on.
Search both files before concluding a flag does not exist.
`--concurrency` is "max concurrent tasks" (`main.py:339`), with `--build-concurrency` and `--worker-concurrency` as separate knobs.

There is no plain repetition flag.
`--trials` exists but is documented as "Number of trials for --matrix" and is consumed only inside the matrix branch (`main.py:585-590`, `:714`), which is itself reachable only under `--tasks-dir`, since `--dataset` and `--source-repo` ignore `--matrix` entirely.
Passing `--trials 3` without `--matrix` runs once.

Two mechanisms give k repetitions, both verified.

An outer shell loop with a distinct `--jobs-dir` per repetition is the one that keeps `--model` and `--agent` on the command line, and is what `scripts/design_matrix.py` emits:

```bash
for t in $(seq -w 1 3); do
  bench eval run --tasks-dir <task-dir> --agent <agent> --model <model> \
    --skill-mode with-skill --skills-dir /tmp/cond-<id> \
    --sandbox docker --concurrency 2 \
    --jobs-dir runs/bench/<cell>__<id>/trial-"$t"
done
```

A single-entry matrix file plus `--trials k` is the in-tool equivalent.
The matrix YAML is a `models:` mapping of alias to either a model string or a mapping with `model`, optional `agent`, and optional `agent_env` (`src/benchflow/cli/eval_artifacts.py:159-183`).
The runner iterates aliases then trials, writing each to `<jobs-dir>/<alias>/trial-NN` and a `matrix-summary.json` at the root (`eval_artifacts.py:244-305`).
Note that the matrix entry overwrites `eval_config.model`, and `eval_config.agent` when the entry names one, so a command-line `--model` is ignored on this path.

Condition ids reach these lines verbatim from `--units`, and the census's `<external>` sentinel contains shell redirection metacharacters, so `design_matrix.py` quotes every interpolated path and job name.
A hand-written manifest must do the same.

Auth per adapter.
Claude Code subscription auth is `CLAUDE_FORCE_OAUTH=1` plus `CLAUDE_CODE_OAUTH_TOKEN`, and Harbor raises if the first is set without the second (`claude_code.py:1587-1633`).
Codex takes `CODEX_FORCE_AUTH_JSON=1` or `CODEX_AUTH_JSON_PATH=<path>` (`codex.py:1305-1325`).
Pi's OAuth escape hatch reads `ANTHROPIC_OAUTH_TOKEN` and is gated only on the resolved provider being anthropic (`pi.py:102-105`), so any other provider falls through to the providers table and Pi on an OpenAI model bills `OPENAI_API_KEY`.

Pi has no force flag.
Claude Code requires `CLAUDE_FORCE_OAUTH` before it will drop the API key (`claude_code.py:1587-1597`) and Codex requires `CODEX_FORCE_AUTH_JSON` or `CODEX_AUTH_JSON_PATH` (`codex.py:1301-1329`), but Pi injects `ANTHROPIC_OAUTH_TOKEN` whenever the variable is present in the resolved environment.
SKILL.md Phase 5 bars subscription-authenticated cells from any reported run batch, and on a Pi cell that rule is enforced by scrubbing the variable, not by withholding a flag: declare `ANTHROPIC_OAUTH_TOKEN=""` in the cell's `env` block or unset it in the shell the manifest runs in.

## Verifier scripts

pytest wrapper, binary reward, for a separate-mode image that already carries pytest:

```bash
#!/bin/bash
mkdir -p /logs/verifier
pytest /tests/test_outputs.py \
  && echo 1 > /logs/verifier/reward.txt || echo 0 > /logs/verifier/reward.txt
```

Reward Kit, graded: `rewardkit /tests` writes reward.json, criteria live in checks.py, the judge in judge.toml, and judge API keys arrive through `[verifier.env]` in task.toml, kept out of the agent environment by separate mode.
Always absolute paths, pin every version, and remember that reward files are the only output channel either runner reads.

Under shared mode the verifier runs in the agent's own environment, so it is the agent image that must carry the tooling.
That is the branch harbor's `examples/tasks/reward-kit-example` takes: its `environment/Dockerfile` copies uv in with `COPY --from=ghcr.io/astral-sh/uv:latest /uv /uvx /bin/` and its `tests/test.sh` then calls `uvx --from harbor-rewardkit==0.1 rewardkit /tests`.
That package declares no `[verifier.environment]`, so it runs shared, which is the leaking branch and is why the separate-mode recipe above bakes the tool into the verifier image instead.

Reward shape decides which headline statistics exist, so choose it before the budget rather than after the run.
Harbor computes pass@k only when every trial carries exactly one reward key whose value is an int or float equal to 0 or 1; a second key, a non-numeric value, or a value strictly between 0 and 1 makes `_compute_pass_at_k_for_trials` return an empty mapping and pass@k disappears from the job stats with no warning (`src/harbor/utils/pass_at_k.py:32-53`).
A multi-dimensional Reward Kit rubric is exactly that case.
BenchFlow's `eval compare-lift` defines a pass strictly as `reward == 1.0` (`src/benchflow/eval_lift.py:31-33`, `:514`), so partial credit counts as a failure in its headline pass rate and shows only in mean_reward.
Graded rubrics remain the right call when the contract is graded; the cost is that pass@k and lift pass rates stop being available and the analysis runs on means.
