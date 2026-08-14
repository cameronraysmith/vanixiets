# Dual emission: one package, two heads

Canonical content: `instruction.md`, `environment/Dockerfile`, one solver
script, one verifier script (+ checks). The heads are metadata plus naming
shims. Emit both; validate both; keep content byte-identical via hardlinks or
a small sync step — never let the heads drift.

## Shared → Harbor head

```
task.toml                 # metadata below
solution/solve.sh         # hardlink of oracle/solve.sh
tests/test.sh             # hardlink of verifier/test.sh (+ checks.py, judge.toml)
```

task.toml essentials (full detail: harbor repo skills/create-task/SKILL.md,
canonical ghq path github.com/harbor-framework/harbor):

```toml
[task]
name = "<org>/<task-id>"; version = "1.0.0"
description = "..."; keywords = ["skills-eval", "<domain>", "rewardkit|pytest"]
[metadata]
difficulty = "easy|medium|hard"; category = "..."; tags = ["..."]
[agent]
timeout_sec = 900.0
[verifier]
timeout_sec = 900.0
environment_mode = "separate"          # default for harborize packages
[verifier.environment]
docker_image = "python:3.12-slim"
network_mode = "public"                # only if judge/API needed, else no-network
[environment]
network_mode = "no-network"            # agent baseline; override per task need
cpus = 1; memory_mb = 4096; storage_mb = 10240
```

Network layering: `[environment].network_mode` is the agent baseline;
`[agent]`/`[verifier]` are phase overrides; `allowlist` mode takes
`allowed_hosts` (hostnames/CIDRs, not URLs). Keep the agent offline unless the
skill's contract requires network.

Run (per cell; auth per adapter):
```
harbor run -p <task-dir> -a claude-code -m anthropic/<model> -k 3 --n-concurrent 2
```
Subscription auth: CLAUDE_FORCE_OAUTH=1 + CLAUDE_CODE_OAUTH_TOKEN (Claude
Code); CODEX_FORCE_AUTH_JSON=1 or CODEX_AUTH_JSON_PATH (Codex); Pi with
provider=openai requires OPENAI_API_KEY.

## Shared → BenchFlow head (SkillsBench layout)

```
task.md                   # YAML frontmatter (schema_version '1.3') + instruction body
environment/skills/       # EMPTY in the canonical package; populated per condition
oracle/solve.sh
verifier/test.sh
```

Frontmatter: `metadata` (author, difficulty, category + controlled-vocab LISTS
for task_type, modality, interface, skill_type, plus tags), `verifier`
(type: test-script, timeout_sec, optional hardening like cleanup_conftests),
`agent.timeout_sec`, `environment` (network_mode, os, cpus, memory_mb,
storage_mb, build_timeout_sec). Vocabulary lives in the skillsbench repo's
taxonomy.yaml / taxonomy.md (canonical ghq path github.com/benchflow-ai/
skillsbench); validate with `bench tasks check` before calling the head done.

Prompt rules enforced by review there and adopted here: imperative prose;
end-state not steps; absolute paths; never mention skills; anchor dates when
answers are time-sensitive.

Run:
```
bench eval run --tasks-dir <task-dir> --agent <agent> --model <model> \
  --skill-mode with-skill --skills-dir <dir(C)> --sandbox docker
# C = ∅ → --skill-mode no-skill
```

## Verifier scripts

pytest head-agnostic wrapper (binary):
```bash
#!/bin/bash
mkdir -p /logs/verifier
uvx --with pytest==8.4.1 pytest /tests/test_outputs.py \
  && echo 1 > /logs/verifier/reward.txt || echo 0 > /logs/verifier/reward.txt
```
Reward Kit (graded): `uvx --from 'harbor-rewardkit==0.1.*' rewardkit /tests`
writes reward.json; criteria in checks.py, judge in judge.toml; judge API keys
via `[verifier.env]` in task.toml, kept out of the agent environment by
separate-mode. Always absolute paths; pin every version; reward files are the
only output channel either runner reads.
