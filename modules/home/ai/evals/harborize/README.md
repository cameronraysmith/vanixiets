# Harborize evaluation workspace

Change-owned corpus for the `validate-harborize-instrument` OpenSpec change.
It validates the harborize instrument at version 0.2.1 by producing evaluation packages whose skill injection is proven at each level it can fail, and it stays in the repository after the change closes as the permanent home of the injection canary and the evaluation corpus.

This file has two halves and they have different lifetimes.
Everything down to "Change-scoped rung evidence" outlives the change.
Everything below that heading is execution evidence for one change and is migrated into `verify.md` and deleted when the change archives, which task 10.6 carries.

## Upstream pins and installed versions

Every source anchor in the change documents is read at these pinned revisions in the local ghq clones, whose HEADs were confirmed equal to the pins:

| repo | path | pin |
|---|---|---|
| Harbor | `~/ghq/github.com/harbor-framework/harbor` | `ac398bbda7c4c1073461797d3b95c2455cc671b5` |
| BenchFlow | `~/ghq/github.com/benchflow-ai/benchflow` | `d30527b82027a416e72014920cdf43a534967ad3` |
| SkillsBench | `~/ghq/github.com/benchflow-ai/skillsbench` | `9a1f4dd5f7659f75707435da3ce854b6e48321d1` |

The pins are reading pins, not install pins: CLI installs track PyPI latest stable (settled 2026-08-15), so the executed CLIs may drift from the anchors.

| CLI | installed | pin's version |
|---|---|---|
| `harbor` | 0.21.0 | 0.21.0 (equal at rung 0 time) |
| `bench` | benchflow 0.7.4 | 0.6.8.dev0 (drifted; anchors cite the pin) |

Where an anchor was re-read in the installed tree rather than the pin, the text citing it says so.

## Instrument freeze baseline

Instrument version: 0.2.1, frozen for the duration of the change.

Baseline start revision: git `5f33c36e23e2d4f36b23aefe7b9217c4d22ff3f6`, the tip of `harborize-instrument` this change baselines from, recorded as a git commit because this rung executed in a plain git worktree without jj metadata; the chain's jj change id lives in the primary checkout and the digest below is the authoritative freeze check either way.

Content digest over `modules/home/ai/plugins/testing-and-quality/.apm/skills/harborize` (13 files):

```
3fdd30d1fa2a69a5e53c8d34474c107a516c32e29dcc5087b9bd7738b22ccd4e
```

The recipe lives here rather than only in the change's tasks.md, because the digest outlives the change while tasks.md archives:

```
find modules/home/ai/plugins/testing-and-quality/.apm/skills/harborize -type f \
  -not -path '*/__pycache__/*' -exec shasum -a 256 {} + | LC_ALL=C sort | shasum -a 256
```

Two properties of that recipe are load-bearing.
The `__pycache__` exclusion is required because the change is obliged to run the instrument's own `scripts/*.py` and CPython writes bytecode beside them, which `.gitignore` then hides — without the exclusion, complying with one task makes another report a freeze violation that never happened.
And the digest is a function of the path string `find` was given, because each `shasum` line embeds it: the value above is what this exact invocation produces **from the repository root**. A trailing slash, a `./` prefix, an absolute path, or a `cd` into the directory each produce a different digest from an unchanged tree.

Task 10.3 recomputes this digest rather than trusting a `jj diff -r @`, which cannot see an edit squashed into the `harborize-instrument` chain.

## Kernel probe outcome

Probe command, run immediately after the daemon started and before any task was authored, with the anchored `grep -qE` whose exit status is the criterion:

```
docker run --rm alpine sh -c '
  [ -f /proc/config.gz ] || exit 2
  zcat /proc/config.gz | grep -qE "^CONFIG_NFT_FIB_INET=[ym]"'
```

Exit status: 0, on 2026-08-18.

Branch taken (task 1.3, exit-0 arm): egress control is available, so `no-network` may be declared anywhere the change declares it.
Every package keeps `network_mode = "public"` at the environment baseline and carries the `no-network` override on the `[agent]` phase only, per task 5.4.

Attribution recorded with the result (task 1.4): `no-network` is the harborize instrument's own authoring default (`SKILL.md:124`, `references/emitters.md:74`), not Harbor's.
Harbor's default is `public` (`models/task/config.py:249-252`, `NetworkPolicy` at `:66`), BenchFlow's is the same (`task/config.py:720-723`), and 86 of the 87 SkillsBench corpus tasks declare `network_mode: public`.
What the probe gates is whether a `no-network` declaration can be enforced at all: on failure `_enable_egress_control` goes false (`docker.py:188-195`), which zeroes `capabilities.disable_internet` (`:289-293`), and `environments/base.py:773-781` raises at environment start.

## Agent install caveat

`install()` curls its bootstrap (`claude_code.py:425-449`) during `_prepare`/`_setup_agent` (`trial.py:408-414`), which no network policy wraps, while only `_run_agent_phase` (`trial.py:465-469`) and the verifier phases enter `_phase_network_policy`.
A cell whose environment baseline is `no-network` therefore fails during agent install indistinguishably from an injection failure at the reward level, which is why task 5.4 puts `no-network` on the `[agent]` phase rather than on the baseline.
The anchors above are claude-code's, but the mechanism is the phase boundary rather than the adapter: every installed adapter's install runs inside `_prepare`/`_setup_agent`.

## Layout

Job output goes to `logs/harborize/` at the repository root, which `.gitignore:57` already excludes; nothing under this workspace writes logs inside the corpus.
No file in this workspace carries the `.nix` extension, because `flake.nix:6` calls `inputs.import-tree ./modules` bare and every `*.nix` file under `modules/` is evaluated as a flake-parts module — a corpus fixture with that extension would break the flake rather than fail as a fixture.

### Flake-evaluation guard

Run whenever a task writes new corpus files (tasks 1.11, 5.10):

```
if fd -H -e nix . modules/home/ai/evals/harborize | rg -q .; then
  echo "FAIL: a .nix file is inside the corpus"; exit 1
fi
nix eval .#nixosConfigurations --apply builtins.attrNames
```

What the eval proves and does not prove: `builtins.attrNames` forces the attrset spine and never the values, so it proves that import-tree's enumeration over `modules/` still succeeds and that every module file parses — which is exactly the hazard the extension audit guards — and it evaluates no module body.
It is therefore not evidence that the nix skill composition or its exclusion list evaluates.
The eval that would exercise those is `.#homeConfigurations."crs58@<system>".config.programs.claude-code.skills`, which triggers an import-from-derivation and is out of scope for a no-build guard.
The darwin arm has the identical scope.

## Generated Harbor heads

Each `<task-id>-harbor/` directory is emitted by `bench tasks export` and is never hand-edited; re-export after every edit to the authored tree.
Two properties of the exporter are worth knowing before reading one of them.

No generation marker can be written into the emitted files.
The exporter copies `environment/`, `oracle/` and `verifier/` verbatim and rebuilds `task.toml` with `tomli_w`, which emits no comments (`benchflow/task/export.py:268-273`, `:367-388`), so a header would vanish on the next export and the committed tree would stop equalling a fresh one.
The marker therefore lives outside the emitted content, as `.gitattributes` `linguist-generated=true`, alongside this repository's other machine-emitted files.

`compatibility/export-report.json` records `source_task_dir` as the exporting checkout's absolute path and cannot be made relative: `TaskPaths.__init__` calls `Path(task_dir).resolve()` (`benchflow/task/paths.py:55-56`) and no CLI flag controls it.
That field is provenance of one export run on one machine, not a portable reference, and re-exporting from a different checkout rewrites it.
The `losses: []` beside it means lossless over the contract files the exporter enumerates, which does not include the authored package README.

## Base image pinning

Every Dockerfile in the corpus pins its base by index digest, `ubuntu:24.04@sha256:561618e2c15bf2397621dd04f96926663a3b5616c189cf7e38db7e82f5c538ea`, which is the image the recorded evidence below was produced against.
The pin is not decorative: at rung-0 time the floating `ubuntu:24.04` tag had already moved to a later build than the one this host held, so an unpinned instrument would compare measurements taken in different environments.
The multi-arch index digest is pinned rather than a platform manifest, so the same line resolves correctly on `linux/arm64` and `linux/amd64`; a platform digest carries one architecture only and would either fail to resolve or silently emulate.

## Verifier forks

Both packages run a shared verifier.
Neither declares `verifier.sandbox_mode` and neither ships a `verifier/Dockerfile`, and the choice is forced rather than preferred — see design decision D11 and each package README for the evidence.
The short form: BenchFlow refuses at launch to run a package declaring separate rather than falling back to shared (`runtime_capabilities.py:186-192`, `sandbox/setup.py:676`, `:819-842`), and Harbor's separate verifier empties `/logs/verifier` before running (`trial.py:599`), which destroys the channel both packages use.
Separate mode is exercised nowhere in this corpus.

Record a fork by resolving it from the exported head rather than by reading the source layout.
Harbor derives the mode from `verifier.environment_mode` or `[verifier.environment]` and from nothing else (`models/task/verifier_mode.py:10-21`), so a `verifier/Dockerfile` on its own infers nothing.

## Harbor's static gate and its blind spot

`Task._validate_tests` returns early whenever a verifier environment is configured (`models/task/task.py:126-144`, early return at `:134-135`), so it structurally cannot catch a separate-mode package missing `/tests/test.sh`.
Both heads in this corpus resolve to shared and therefore do not reach that early return; the record is a source reading against harbor 0.21.0, kept because it bounds what `Task()` construction is evidence of.

## Standing precondition

The injection canary is re-run at the start of every later evaluation round, before any metered batch.
It is a positive control for skill delivery, and every silent-null class the instrument documents produces a clean run and a plausible negative result without it.

---

# Change-scoped rung evidence

Records for the `validate-harborize-instrument` change only.
Task 10.6 migrates this section into `verify.md` and deletes it at archive time.

## Rung 0 — prerequisites (complete)

- Docker daemon: answering (`docker info` exit 0) before the probe ran.
- Kernel probe: exit 0, recorded above with its branch and attribution.
- CLIs: `harbor` 0.21.0 and `bench` (benchflow 0.7.4) on `PATH` from PyPI, with
  all three ghq clones verified clean at their pins after install.
- Flake-evaluation guard: run at this rung's close, after this README became the
  first corpus file under `modules/`. Result: no `.nix` file found, `nix eval`
  exit 0 on both `nixosConfigurations` and `darwinConfigurations`.

## Canary skill and condition directory (tasks 2.1-2.4)

`conditions/canary/` is `dir(C)`: exactly one skill directory, `harborize-injection-canary`, carrying the token `HARBORIZE-CANARY-9F3A21`.
The name collides with none of the deployed skill directories, and the directory holds nothing else, because a stray non-hidden child without a `SKILL.md` turns the whole condition into a hard error at resolution (`_find_skill_dirs`, `skills.py:382-416`).

Leakage-audit expectation (task 2.3): the asserted literal appears in both the verifier and the `SKILL.md` by design, and `audit_leakage.py` check 1 flags exactly that pattern (`MIN_LITERAL_LENGTH` at `:44`, `check_literals` at `:96`).
The flag is correct on its own terms — the canary's mechanism is its answer key — and the instrument is not edited to exempt it because it is frozen at 0.2.1.

Exposure of the shared fork (task 2.4), corrected in the review round: the consequence originally recorded — that a real agent could read the token out of the verifier script — does not arise.
Both runners upload the verifier's own directory during the verification phase, after the agent phase has ended (Harbor `verifier/verifier.py:147-153` reached from `_run_shared_verifier`, phase order fixed at `trial/single_step.py:41` then `:52`; BenchFlow `task/verifier_core.py:385` inside `verify()`).
Rung 6's criterion is unchanged and rests on a different reason: a model-driven trial's reward conflates delivery with the model's own behaviour, so the adapter's registration directory is the deterministic witness.

## Rung 1 — adapter allowlist gate (tasks 3.1-3.3)

`scripts/design_matrix.py` with `--units harborize-injection-canary --design marginals`, three runs against throwaway `/tmp` outputs:

- `cells/cells-nonconsuming.json` (agent `aider`): exit 1 naming `aider` and
  the reason, `/tmp/design-neg` never created.
- `cells/cells-acp.json` (agent `acp:claude-agent`): exit 1 on the ACP
  shorthand, `/tmp/design-acp` never created.
- `cells/cells.json` (the codex cell this change will use): exit 0,
  `conditions.json`, `manifest.sh`, `jobs.json` written to `/tmp/design-ok`
  and then discarded — nothing the gate emitted was executed, committed or
  consumed by a later rung, keeping the whole rung inside the proposal's
  condition-lattice Non-goal.

## Rung 2 — host-side resolution (tasks 4.1-4.3)

`checks/resolve_check.py` calls `harbor.skills.resolve_skills` (`skills.py:111-123`) and `compute_skill_digest` (`skills.py:200-209`) against `conditions/canary`, run with the interpreter backing the `harbor` entrypoint:

```
HARBOR_PY=$(sed -n '1s|^#!||p' "$(command -v harbor)")
"$HARBOR_PY" modules/home/ai/evals/harborize/checks/resolve_check.py <dir>
```

- `dir(C)`: exactly one entry, `name` `harborize-injection-canary`, `digest`
  `sha256:47016a2e2b3f220c90fc183411a8ae8dbd2f37c4c6becc268460a5588ba85cd9`.
- Missing path: `FileNotFoundError` on the host, exit 1.
- A file rather than a directory: `ValueError: Skill path must be a directory`,
  exit 1.
- A child directory without a `SKILL.md`: `ValueError` naming `not-a-skill`,
  exit 1.
- No argument: a usage line on stderr, exit 2.

Each raise happened on the host before any container started (`_find_skill_dirs`, `skills.py:382-416`).

What this rung proves is host-side resolution and request, never delivery: a trial's `lock.json` cannot substitute for delivery evidence, because `_write_trial_lock` runs at `trial.py:104` inside `Trial.__init__`, before `_resolve_injected_skills` at `:107` and long before `_upload_injected_skills` at `:411`, and `_build_agent_skill_locks` (`models/job/lock.py:462-475`) calls only host-side functions.

## Task package authoring, dual head (tasks 5.1-5.10)

Two authored BenchFlow-native trees and two derived Harbor heads:

- `injection-canary/`: shared verifier fork, oracle output at
  `/logs/verifier/canary-output.txt`, `environment/skills/` empty with a
  `.gitkeep`, `sandbox.network_mode: public` baseline with the `no-network`
  override on `[agent]` only (probe exit 0 permits it).
- `pipeline-event-summary/`: the mechanical package sampling the
  `preferences-json-querying` skill's claimed contract, single binary reward
  key, shared verifier fork, verifier expectation held as a hand-derived literal
  rather than recomputed from a fixture copy; fork choice and reward channel
  recorded in its README.
- Both heads exported with `bench tasks export ... --target harbor --overwrite`,
  status lossless, 0 losses, reports under `compatibility/export-report.json`;
  the exported `task.toml` carries `[environment] network_mode = "public"` with
  the `[agent]` phase override, and the heads are never hand-edited.
- Fork verified from the heads rather than the layout:
  `resolve_task_verifier_mode(Task(<head>).config)` is
  `VerifierEnvironmentMode.SHARED` for both, matching what each README records.
- Leakage audit (task 5.8): mechanical exit 0 — after renaming the summary key
  `pipelines` to `per_pipeline`, because the skill's prose contains the word
  `pipelines` and the frozen check 1 flags any quoted verifier literal of eight
  characters or more recoverable from skill content; canary exit 1 with exactly
  the expected check-1 literal flag naming the token, justification in the
  package README.
- Extension audit and flake-evaluation guard re-run after export (task 5.10):
  no `.nix` file inside the corpus, `nixosConfigurations` and
  `darwinConfigurations` eval exit 0.

## Rung 3 — static task validation (tasks 6.1-6.3)

- `bench tasks check <native> --level structural`: exit 0, no issues, on both
  `injection-canary` and `pipeline-event-summary`.
- `bench tasks check <native> --level runtime-capability --sandbox docker`: exit
  0 on both, which is what establishes that neither package declares a feature
  BenchFlow would refuse to launch.
- `harbor.models.task.task.Task(<head>)` constructed both exported heads
  successfully (exit 0 each). The stub `harbor task(s) check` and its redirect
  to the metered `harbor check` LLM-rubric were not invoked.
- Harbor gate blind spot (task 6.3): recorded above as a permanent note, with
  the correction that neither head in this corpus reaches the early return.

## Host-side container dry runs, beyond the task list

Each oracle and verifier pair run under the pinned base image before any runner touches them.
These are not a rung's pass criterion; they are the re-verification of the artifacts the review round changed.

- Mechanical, shared-fork layout: oracle output scores 1; a summary with one
  digit of the median altered scores 0; a missing `summary.json` scores 0.
- Canary: with `dir(C)` mounted at `/harbor/skills` reward 1 and the token
  written; with no skill mounted reward 0 and an empty output file.
- Canary with `HOME` unset in the container: the oracle exits 0 and writes its
  output file, where it previously aborted under `set -u` before writing
  anything — a failure the verifier could not distinguish from a genuine
  injection failure.
