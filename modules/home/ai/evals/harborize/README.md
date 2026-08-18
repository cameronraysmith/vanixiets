# Harborize evaluation workspace

Change-owned corpus for the `validate-harborize-instrument` OpenSpec change.
It validates the harborize instrument at version 0.2.1 by producing evaluation
packages whose skill injection is proven at each level it can fail, and it stays
in the repository after the change closes as the permanent home of the injection
canary and the evaluation corpus.

## Upstream pins and installed versions

Every source anchor in the change documents is read at these pinned revisions in
the local ghq clones, whose HEADs were confirmed equal to the pins:

| repo | path | pin |
|---|---|---|
| Harbor | `~/ghq/github.com/harbor-framework/harbor` | `ac398bbda7c4c1073461797d3b95c2455cc671b5` |
| BenchFlow | `~/ghq/github.com/benchflow-ai/benchflow` | `d30527b82027a416e72014920cdf43a534967ad3` |
| SkillsBench | `~/ghq/github.com/benchflow-ai/skillsbench` | `9a1f4dd5f7659f75707435da3ce854b6e48321d1` |

The pins are reading pins, not install pins: CLI installs track PyPI latest
stable (settled 2026-08-15), so the executed CLIs may drift from the anchors.

| CLI | installed | pin's version |
|---|---|---|
| `harbor` | 0.21.0 | 0.21.0 (equal at rung 0 time) |
| `bench` | benchflow 0.7.4 | 0.6.8.dev0 (drifted; anchors cite the pin) |

## Instrument freeze baseline

Instrument version: 0.2.1, frozen for the duration of the change.

Baseline start revision: git `5f33c36e23e2d4f36b23aefe7b9217c4d22ff3f6`, the
tip of `harborize-instrument` this change baselines from, recorded as a git
commit because this rung executed in a plain git worktree without jj metadata;
the chain's jj change id lives in the primary checkout and the digest below is
the authoritative freeze check either way.

Content digest over
`modules/home/ai/plugins/testing-and-quality/.apm/skills/harborize` (13 files):

```
3fdd30d1fa2a69a5e53c8d34474c107a516c32e29dcc5087b9bd7738b22ccd4e
```

Task 10.3 recomputes this digest rather than trusting a `jj diff -r @`, which
cannot see an edit squashed into the `harborize-instrument` chain.

## Kernel probe outcome (rung 0)

Probe command, run immediately after the daemon started and before any task was
authored, with the anchored `grep -qE` whose exit status is the criterion:

```
docker run --rm alpine sh -c '
  [ -f /proc/config.gz ] || exit 2
  zcat /proc/config.gz | grep -qE "^CONFIG_NFT_FIB_INET=[ym]"'
```

Exit status: 0, on 2026-08-18.

Branch taken (task 1.3, exit-0 arm): egress control is available, so
`no-network` may be declared anywhere the change declares it. Every package
keeps `network_mode = "public"` at the environment baseline and carries the
`no-network` override on the `[agent]` phase only, per task 5.4.

Attribution recorded with the result (task 1.4): `no-network` is the harborize
instrument's own authoring default (`SKILL.md:124`, `references/emitters.md:74`),
not Harbor's. Harbor's default is `public` (`models/task/config.py:249-252`,
`NetworkPolicy` at `:66`), BenchFlow's is the same (`task/config.py:720-723`),
and 86 of the 87 SkillsBench corpus tasks declare `network_mode: public`. What
the probe gates is whether a `no-network` declaration can be enforced at all: on
failure `_enable_egress_control` goes false (`docker.py:188-195`), which zeroes
`capabilities.disable_internet` (`:289-293`), and `environments/base.py:773-781`
raises at environment start.

## Claude Code install caveat

`install()` curls its bootstrap (`claude_code.py:425-449`) during
`_prepare`/`_setup_agent` (`trial.py:408-414`), which no network policy wraps,
while only `_run_agent_phase` (`trial.py:465-469`) and the verifier phases enter
`_phase_network_policy`. A cell whose environment baseline is `no-network`
therefore fails during agent install indistinguishably from an injection failure
at the reward level, which is why task 5.4 puts `no-network` on the `[agent]`
phase rather than on the baseline.

## Layout

Job output goes to `logs/harborize/` at the repository root, which
`.gitignore:57` already excludes; nothing under this workspace writes logs
inside the corpus. No file in this workspace carries the `.nix` extension,
because `flake.nix:6` calls `inputs.import-tree ./modules` bare and every
`*.nix` file under `modules/` is evaluated as a flake-parts module — a corpus
fixture with that extension would break the flake rather than fail as a fixture.

## Rung evidence

Records land here as each rung completes.

### Rung 0 — prerequisites (complete)

- Docker daemon: answering (`docker info` exit 0) before the probe ran.
- Kernel probe: exit 0, recorded above with its branch and attribution.
- CLIs: `harbor` 0.21.0 and `bench` (benchflow 0.7.4) on `PATH` from PyPI, with
  all three ghq clones verified clean at their pins after install.
- Flake-evaluation guard: run at this rung's close, after this README became the
  first corpus file under `modules/` — see the guard record below.

### Flake-evaluation guard

Run whenever a task writes new corpus files (tasks 1.11, 5.10):

```
if fd -H -e nix . modules/home/ai/evals/harborize | rg -q .; then
  echo "FAIL: a .nix file is inside the corpus"; exit 1
fi
nix eval .#nixosConfigurations --apply builtins.attrNames
```

Result at rung 0 close: no `.nix` file found, eval exit 0, attribute list
printed.

### Canary condition directory (tasks 2.1-2.4)

`conditions/canary/` is `dir(C)`: exactly one skill directory,
`harborize-injection-canary`, carrying the token `HARBORIZE-CANARY-9F3A21`.
The name collides with none of the deployed skill directories, and the
directory holds nothing else, because a stray non-hidden child without a
`SKILL.md` turns the whole condition into a hard error at resolution
(`_find_skill_dirs`, `skills.py:382-416`).

Leakage-audit expectation (task 2.3): the asserted literal appears in both the
verifier and the `SKILL.md` by design, and `audit_leakage.py` check 1 flags
exactly that pattern (`MIN_LITERAL_LENGTH` at `:44`, `check_literals` at
`:96`). The flag is correct on its own terms — the canary's mechanism is its
answer key — and the instrument is not edited to exempt it because it is frozen
at 0.2.1.

Second consequence of the shared verifier fork chosen for the canary package
(task 2.4): a real agent in the metered rung can read the token out of the
verifier script without the skill ever being delivered. That costs nothing
here, because rung 6's pass criterion is the adapter's registration directory
rather than the reward (task 9.4), and the falsifiability control in task 7.3
runs under the oracle, which greps skill directories and never reads the
verifier.

### Rung 1 — adapter allowlist gate (tasks 3.1-3.3)

`scripts/design_matrix.py` with `--units harborize-injection-canary --design
marginals`, three runs against throwaway `/tmp` outputs:

- `cells/cells-nonconsuming.json` (agent `aider`): exit 1 naming `aider` and
  the reason, `/tmp/design-neg` never created.
- `cells/cells-acp.json` (agent `acp:claude-agent`): exit 1 on the ACP
  shorthand, `/tmp/design-acp` never created.
- `cells/cells.json` (the codex cell this change will use): exit 0,
  `conditions.json`, `manifest.sh`, `jobs.json` written to `/tmp/design-ok`
  and then discarded — nothing the gate emitted was executed, committed or
  consumed by a later rung, keeping the whole rung inside the proposal's
  condition-lattice Non-goal.

### Rung 2 — host-side resolution (tasks 4.1-4.3)

`checks/resolve_check.py` calls `harbor.skills.resolve_skills`
(`skills.py:111-123`) and `compute_skill_digest` (`skills.py:200-209`) against
`conditions/canary`, using the installed CLI's tool-environment python.

- `dir(C)`: exactly one entry, `name` `harborize-injection-canary`, `digest`
  `sha256:47016a2e2b3f220c90fc183411a8ae8dbd2f37c4c6becc268460a5588ba85cd9`.
- Missing path: `FileNotFoundError` on the host, exit 1.
- A file rather than a directory: `ValueError: Skill path must be a directory`,
  exit 1.
- A child directory without a `SKILL.md`: `ValueError` naming `not-a-skill`,
  exit 1.

Each raise happened on the host before any container started
(`_find_skill_dirs`, `skills.py:382-416`).

What this rung proves is host-side resolution and request, never delivery: a
trial's `lock.json` cannot substitute for delivery evidence, because
`_write_trial_lock` runs at `trial.py:104` inside `Trial.__init__`, before
`_resolve_injected_skills` at `:107` and long before `_upload_injected_skills`
at `:411`, and `_build_agent_skill_locks` (`models/job/lock.py:462-475`) calls
only host-side functions.

### Task package authoring, dual head (tasks 5.1-5.10)

Two authored BenchFlow-native trees and two derived Harbor heads:

- `injection-canary/`: shared verifier fork (no `verifier/Dockerfile`, no
  `[verifier.sandbox]` table), oracle output at `/logs/verifier/canary-output.txt`,
  `environment/skills/` empty with a `.gitkeep`, `sandbox.network_mode: public`
  baseline with the `no-network` override on `[agent]` only (probe exit 0
  permits it).
- `pipeline-event-summary/`: the mechanical package sampling the
  `preferences-json-querying` skill's claimed contract, single binary reward
  key, separate verifier fork whose Dockerfile installs its own python and
  places `/tests/test.sh` beside its own `_deps` fixture copy; fork choice and
  channel recorded in its README.
- Both heads exported with `bench tasks export ... --target harbor --overwrite`,
  status lossless, 0 losses, reports under `compatibility/export-report.json`;
  the exported `task.toml` carries `[environment] network_mode = "public"` with
  the `[agent]` phase override, and the heads are never hand-edited.
- Leakage audit (task 5.8): mechanical exit 0 — after renaming the summary key
  `pipelines` to `per_pipeline`, because the skill's prose contains the word
  `pipelines` and the frozen check 1 flags any quoted verifier literal of eight
  characters or more recoverable from skill content; canary exit 1 with exactly
  the expected check-1 literal flag naming the token, justification in the
  package README.
- Extension audit and flake-evaluation guard re-run after export (task 5.10):
  no `.nix` file inside the corpus, `nixosConfigurations` eval exit 0.
- Host-side container dry runs beyond the task list, proving each oracle and
  verifier pair under `ubuntu:24.04` before any runner touches them: canary
  with-skill reward 1 and no-skill reward 0; mechanical correct summary reward 1
  on both fork layouts (`/tests` and `/verifier`) and wrong summary reward 0.

### Rung 3 — static task validation (tasks 6.1-6.3)

- `bench tasks check <native> --level structural`: exit 0, no issues, on both
  `injection-canary` and `pipeline-event-summary`.
- `harbor.models.task.task.Task(<head>)` constructed both exported heads
  successfully (exit 0 each), using the installed CLI's tool-environment
  python. The stub `harbor task(s) check` and its redirect to the metered
  `harbor check` LLM-rubric were not invoked.
- Harbor gate blind spot (task 6.3): `Task._validate_tests` returns early
  whenever a verifier environment is configured, so it structurally cannot
  catch a separate-mode package missing `/tests/test.sh`. The anchor
  (`models/task/task.py:126-144`, early return at `:134-135`) is at the
  reading pin; the behavior was re-confirmed in the installed 0.21.0 tree,
  where `_validate_tests` resolves the effective verifier env config and
  returns before `discovered_test_path_for` is consulted.
