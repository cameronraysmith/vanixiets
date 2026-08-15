# validate-harborize-instrument Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Prove that harborize 0.2.1 produces evaluation packages whose skill injection is delivered end to end, leave a permanent injection canary behind, and measure the per-run cost constant.

**Architecture:** Seven rungs run in order, six of them free of model spend.
The free rungs retire every silent-null class except adapter registration, which is unreachable without a real agent invocation and is therefore the single metered rung, reduced to one short trial per cell.
Each package is authored BenchFlow-native and exported to a sibling Harbor head, because three independent validators forbid the co-present layout.

**Tech Stack:** Docker via OrbStack; the Harbor CLI and the BenchFlow CLI installed with `uv tool install`; python 3.12 for host-side checks; the frozen harborize instrument's bundled scripts (`design_matrix.py`, `audit_leakage.py`, `materialize_conditions.py`).

## Global Constraints

- Instrument version is `0.2.1` and the harborize directory at `modules/home/ai/plugins/testing-and-quality/.apm/skills/harborize/` MUST NOT be modified for the duration of this change.
  A defect found mid-change is recorded and deferred.
- Upstream pins, and every anchor is valid only at these revisions: harbor `ac398bbda7c4c1073461797d3b95c2455cc671b5`, benchflow `d30527b82027a416e72014920cdf43a534967ad3`, skillsbench `9a1f4dd5f7659f75707435da3ce854b6e48321d1`.
- The three ghq clones at `~/ghq/github.com/harbor-framework/harbor`, `~/ghq/github.com/benchflow-ai/benchflow` and `~/ghq/github.com/benchflow-ai/skillsbench` are read-only reference trees.
  Never run `uv sync` inside them; install CLIs with `uv tool install` or a scratch `UV_PROJECT_ENVIRONMENT` outside the clone.
- Every package carries a single binary reward key.
  A multi-dimensional rubric silently disables Harbor's pass@k and makes BenchFlow's compare-lift count only `reward == 1.0` as passed.
- Every Harbor run line sets `HARBOR_TELEMETRY=0`.
  Every metered run scrubs `ANTHROPIC_OAUTH_TOKEN`.
- Every package declares `network_mode = "public"` at its environment baseline and confines `no-network` to the `[agent]` phase, because the baseline governs container creation while the phase policy wraps only the agent run.
  `no-network` is the harborize instrument's authoring default, not Harbor's; Harbor's default is `public`.
- Package corpus path is `modules/home/ai/evals/harborize/` in this repository, tracked in version control.
  Job output goes to `logs/harborize/`, which is already gitignored (`.gitignore:57`).
  The path is settled and needs no further confirmation: the corpus is co-located with the skills it evaluates, which live under `modules/home/ai/plugins/`, and the location was verified safe against every automated surface that walks `modules/` — import-tree, treefmt, the `naming-conventions` check, and the apm skill composition.
- No file inside the corpus may carry the `.nix` extension.
  `flake.nix:6` calls `inputs.import-tree ./modules` bare with no custom filter, so import-tree's default `nixFilter = andNot (hasInfix "/_") (hasSuffix ".nix")` (import-tree `default.nix:50`, rev `4ebb10ae17d5f1ad366e7aef5b92cb8eecf24f69`) imports every `*.nix` file anywhere under `modules/` and evaluates it as a flake-parts module.
  A fixture named `expected.nix` is the realistic trap, and it would break the flake rather than fail as a fixture.
  Two escapes exist and either one is sufficient: **never give a fixture the `.nix` extension**, or place it under a `_`-prefixed directory, which is this repository's documented exclusion convention (ADR-0018, `packages/docs/src/content/docs/development/architecture/adrs/0018-deferred-module-composition-architecture.md:311`).
  Everything else is safe by construction, because non-nix files are enumerated and then dropped before anything reads them with no warning and no error, which is why `modules/` already carries 444 non-nix files and the flake still evaluates.
  This constraint is checked rather than trusted: Task 1 Step 7 runs the flake-evaluation guard as soon as the corpus root exists, and Task 5 Step 8 re-runs it with an extension audit once the package directories and the generated Harbor heads exist.
- Integration is jj-native onto the existing `harborize-instrument` bookmark, which is already a parent of the development join.
  Routing a change onto that chain is orchestrator-owned; an implementing subagent leaves its work in the working copy and names what it touched.

## File Structure

```
modules/home/ai/evals/harborize/
├── README.md                                  # pins, instrument version, probe result, caveats
├── cells/cells.json                           # cell definitions consumed by design_matrix.py
├── conditions/canary/                         # dir(C): exactly one skill directory
│   └── harborize-injection-canary/SKILL.md
├── injection-canary/                          # authored BenchFlow-native, shared verifier
│   ├── task.md
│   ├── environment/Dockerfile
│   ├── environment/skills/.gitkeep            # directory stays EMPTY; .gitkeep keeps it tracked
│   ├── oracle/solve.sh
│   └── verifier/test.sh                       # no verifier/Dockerfile: shared mode ships none
├── injection-canary-harbor/                   # generated by bench tasks export; never hand-edited
└── <mechanical-task-id>/ , <mechanical-task-id>-harbor/
logs/harborize/                                # gitignored job trees
├── canary-bench/
└── gate1/
```

Each package directory is self-contained: the authored native tree is the source of truth and its Harbor sibling is a build product re-derived after every edit.
The condition directory lives outside every package, because a populated `environment/skills/` bakes one condition into the image.
`environment/skills/` carries a `.gitkeep` because neither git nor jj tracks an empty directory, and the emptiness is the load-bearing property: it is what proves no condition is baked into the image.
BenchFlow reads that directory as a bundled skills source through `task_bundled_skills_dir` (`skill_policy.py:71`), so an accidentally populated one silently becomes a condition.

---

## Task 1: Prerequisites and the blocking kernel probe

**Files:**
- Create: `modules/home/ai/evals/harborize/README.md`

**Interfaces:**
- Consumes: nothing.
- Produces: a running Docker daemon, `harbor` and `bench` on `PATH`, and a README recording the probe result that every later task's network mode depends on.

- [ ] **Step 1: Start the Docker daemon**

```bash
open -a OrbStack
docker info
```

Expected: `docker info` exits 0 and prints a server block.
It currently fails, because OrbStack is stopped and the socket is absent.

- [ ] **Step 2: Run the blocking kernel probe before authoring anything**

```bash
docker run --rm alpine sh -c '
  [ -f /proc/config.gz ] || exit 2
  zcat /proc/config.gz | grep -qE "^CONFIG_NFT_FIB_INET=[ym]"'
echo "probe exit: $?"
```

Read the exit status, not the output.
The anchor and `-q` are load-bearing: an unanchored `grep NFT_FIB_INET` matches the line `# CONFIG_NFT_FIB_INET is not set` and exits 0, so the negative reading would pass a scripted check.

Branch on three outcomes rather than halting on any non-zero.
Exit 0 means egress control is available and `no-network` may be declared wherever this plan declares it.
Exit 1 means the option is explicitly unset, so drop the `[agent]` phase override from Task 5 Step 4, leave every package fully `public`, and record the loss of egress control in the workspace README.
Exit 2 means `/proc/config.gz` is absent, which is indeterminate rather than negative: Harbor's own probe short-circuits to exit 0 in exactly that case (`environments/docker/docker.py:113-117`), so Harbor proceeds and this plan proceeds with it, treating a later `no-network` rejection as the deciding evidence.

What the probe gates is enforcement, not the default.
`no-network` is the harborize instrument's authoring default (`SKILL.md:124`, `references/emitters.md:74`), while Harbor's own default is `public` (`models/task/config.py:249-252`, `NetworkPolicy` at `:66`), BenchFlow's is the same (`task/config.py:720-723`), and 86 of the 87 SkillsBench corpus tasks declare `network_mode: public`.
When the option is missing, `_enable_egress_control` goes false (`docker.py:188-195`), which zeroes `capabilities.disable_internet` (`:289-293`), and `environments/base.py:773-781` raises at environment start for any `no-network` policy — baseline or phase.

- [ ] **Step 3: Install the two CLIs outside the reference clones**

```bash
uv tool install --from ~/ghq/github.com/harbor-framework/harbor harbor
uv tool install --from ~/ghq/github.com/benchflow-ai/benchflow benchflow
harbor --version
bench --version
```

Expected: both commands print a version.
If `uv tool install` refuses the local path form, use a scratch environment instead and keep it outside the clone:

```bash
UV_PROJECT_ENVIRONMENT=~/.cache/harborize-venvs/harbor uv sync --project ~/ghq/github.com/harbor-framework/harbor
```

- [ ] **Step 4: Verify the reference clones are unmodified**

```bash
git -C ~/ghq/github.com/harbor-framework/harbor status --porcelain
git -C ~/ghq/github.com/benchflow-ai/benchflow status --porcelain
```

Expected: both print nothing.

- [ ] **Step 5: Record the instrument-freeze baseline**

```bash
jj log --ignore-working-copy -r @ -T 'change_id.short()'
find modules/home/ai/plugins/testing-and-quality/.apm/skills/harborize -type f \
  -exec shasum -a 256 {} + | LC_ALL=C sort | shasum -a 256
```

Write both values into the workspace README before any other task runs.
Task 10 Step 4 recomputes the digest and compares it, because a `jj diff -r @` reports only what the working-copy commit changed against its parents and would show nothing for an edit squashed into the `harborize-instrument` chain this plan routes onto.

- [ ] **Step 6: Write the workspace README**

Record, one line each: the three upstream pins; instrument version 0.2.1; the probe exit status from Step 2 with its branch and its date; the freeze baseline from Step 5; the attribution that `no-network` is the instrument's authoring default rather than Harbor's; and the claude-code install caveat.
The caveat is that `install()` curls its bootstrap (`claude_code.py:425-449`) during `_prepare`/`_setup_agent` (`trial.py:408-414`), which no network policy wraps, while only `_run_agent_phase` (`trial.py:465-469`) and the verifier phases enter `_phase_network_policy`.
A cell whose environment baseline is `no-network` therefore fails during agent install indistinguishably from an injection failure at the reward level, which is why Task 5 Step 4 puts `no-network` on the agent phase and never on the baseline.

- [ ] **Step 7: Run the flake-evaluation guard now that the corpus root exists under `modules/`**

```bash
if fd -H -e nix . modules/home/ai/evals/harborize | rg -q .; then
  echo "FAIL: a .nix file is inside the corpus"; exit 1
fi
nix eval .#nixosConfigurations --apply builtins.attrNames
```

Expected: the audit finds nothing and the eval exits 0 printing the attribute list.
Step 6 writes the first corpus file under `modules/`, so this is the earliest point at which the Global Constraints' `.nix` prohibition can be violated, and the guard is what turns that constraint from a comment into a check.
The eval is the cheapest expression that forces import-tree to walk `modules/` and construct the module set.
`nix flake check` is the stronger form and is equivalent for this purpose, so prefer it when the wait is acceptable; do not add `--no-build`, which exits 1 on an unrelated import-from-derivation in this repository and would read as a guard failure.
The audit is written as an explicit `if` rather than a negated pipeline, because bash exempts a `!`-inverted command from `set -e` and an absence assertion written that way is a no-op.

- [ ] **Step 8: Check off tasks.md §1 and hand the working copy back for routing onto `harborize-instrument`**

---

## Task 2: Canary skill and condition directory

**Files:**
- Create: `modules/home/ai/evals/harborize/conditions/canary/harborize-injection-canary/SKILL.md`

**Interfaces:**
- Consumes: Task 1's workspace.
- Produces: `dir(C)` at `modules/home/ai/evals/harborize/conditions/canary/`, containing exactly one skill directory. The literal token `HARBORIZE-CANARY-9F3A21` is the value Task 5's oracle extracts and Task 5's verifier asserts.

- [ ] **Step 1: Write the canary skill**

```markdown
---
name: harborize-injection-canary
description: Injection canary for the harborize instrument. Carries a single token that a canary task's oracle extracts and its verifier asserts, so a failure to deliver injected skills fails a task rather than silently voiding a batch.
---

# Harborize injection canary

This skill exists to be delivered, not to be used.

The canary token is HARBORIZE-CANARY-9F3A21 and it appears nowhere else in the deployed tree.
```

The name must not collide with any of the 172 deployed skill directories; confirm with `ls ~/.claude/skills | grep -c harborize-injection-canary` returning 0.

- [ ] **Step 2: Verify dir(C) contains skill directories and nothing else**

```bash
ls -A modules/home/ai/evals/harborize/conditions/canary/
```

Expected: exactly `harborize-injection-canary`.
Harbor's `_find_skill_dirs` raises on a root holding a non-hidden child directory without a `SKILL.md` (`skills.py:382-416`), so a stray directory turns the whole condition into a hard error.

- [ ] **Step 3: Record the leakage-audit expectation in the canary README section**

Write into `modules/home/ai/evals/harborize/README.md` that the token appears in both the canary `SKILL.md` and the canary verifier by design, that `audit_leakage.py` check 1 flags exactly that pattern (`MIN_LITERAL_LENGTH = 8` at `:44`, `check_literals` at `:96`), that the flag is correct on its own terms, and that the instrument is not edited to exempt it because D5 freezes it at 0.2.1.
Record the second consequence in the same place: the canary runs a shared verifier (Task 5 Step 2), so a real agent in the metered rung can read the token out of the verifier script without the skill ever being delivered.
That costs nothing, because the metered rung's pass criterion is the adapter's registration directory rather than the reward, and the falsifiability control in Task 7 Step 3 runs under the oracle, which greps skill directories and never reads the verifier.

- [ ] **Step 4: Check off tasks.md §2 and hand the working copy back for routing**

---

## Task 3: Adapter allowlist gate

**Files:**
- Create: `modules/home/ai/evals/harborize/cells/cells.json`
- Create: `modules/home/ai/evals/harborize/cells/cells-nonconsuming.json`
- Create: `modules/home/ai/evals/harborize/cells/cells-acp.json`

**Interfaces:**
- Consumes: Task 1's CLIs are not needed here; this rung is pure python over the frozen instrument's script.
- Produces: a validated `cells.json` that later rungs pass to `design_matrix.py`.

- [ ] **Step 1: Write the negative-control cells file naming a non-consuming adapter**

```json
[{"name": "neg-aider", "runner": "harbor", "agent": "aider", "model": "anthropic/claude-opus-5"}]
```

`aider` is in the non-consuming set: of the 39 agents Harbor's factory registers, 22 read the injected skills directory and 17 do not.

- [ ] **Step 2: Run the gate against it and confirm it refuses**

```bash
SKILL=modules/home/ai/plugins/testing-and-quality/.apm/skills/harborize
python3 "$SKILL/scripts/design_matrix.py" \
  --units harborize-injection-canary --design marginals \
  --cells modules/home/ai/evals/harborize/cells/cells-nonconsuming.json --out /tmp/design-neg
```

`--units`, `--design` and `--cells` are all required, and without `--from-census` the unit names are free strings, so this is the smallest invocation that reaches the gate.
`load_cells` calls `check_harbor_agents`, so no caller reaches a manifest without passing it.
Expected: a nonzero exit naming `aider` and the reason, with `/tmp/design-neg` never written.

- [ ] **Step 3: Write the second negative control naming an ACP shorthand**

```json
[{"name": "neg-acp", "runner": "harbor", "agent": "acp:claude-agent", "model": "anthropic/claude-opus-5"}]
```

Run the same command with `--cells modules/home/ai/evals/harborize/cells/cells-acp.json`.
Expected: a nonzero exit, because `factory.py:167-175` routes every `acp:`-prefixed name through the non-consuming ACP adapter, so the Harbor arm drops skills while a BenchFlow arm for the same agent works.

- [ ] **Step 4: Write the real cells file and confirm it passes**

```json
[{"name": "cc-opus", "runner": "harbor", "agent": "claude-code", "model": "anthropic/claude-opus-5", "env": {"HARBOR_TELEMETRY": "0", "ANTHROPIC_OAUTH_TOKEN": ""}}]
```

Run the same command with `--cells modules/home/ai/evals/harborize/cells/cells.json --out /tmp/design-ok`.
Expected: exit 0 and a printed conditions-and-jobs summary.
The `--out` path is deliberately throwaway.
`design_matrix.py:442-466` writes `conditions.json`, `manifest.sh` and `jobs.json` there, and nothing this rung emits is executed, committed or consumed by a later rung, which is what keeps the whole rung inside the proposal's condition-lattice Non-goal.
`load_cells` runs at `:440`, before `out.mkdir` at `:442`, so a refused cells file leaves the directory uncreated and the negative controls above assert exactly that.

- [ ] **Step 5: Check off tasks.md §3 and hand the working copy back for routing**

---

## Task 4: Host-side resolution

**Files:**
- Create: `modules/home/ai/evals/harborize/checks/resolve_check.py`

**Interfaces:**
- Consumes: `dir(C)` from Task 2.
- Produces: recorded evidence that the condition directory resolves on the host, explicitly labelled resolution and request rather than delivery.

- [ ] **Step 1: Write the resolution check**

```python
import json, sys
from harbor.skills import compute_skill_digest, resolve_skills

root = sys.argv[1]
resolved = resolve_skills([root])
print(json.dumps([
    {"name": s.name, "source": str(s.source), "digest": compute_skill_digest(s.source)}
    for s in resolved
], indent=2))
```

- [ ] **Step 2: Run it against dir(C)**

```bash
python3 modules/home/ai/evals/harborize/checks/resolve_check.py modules/home/ai/evals/harborize/conditions/canary
```

Expected: exactly one entry, `name` equal to `harborize-injection-canary`, and a `digest` beginning `sha256:`.
`resolve_skills` is `skills.py:111-123` and `compute_skill_digest` is `skills.py:200-209`, which is pure over the directory.

- [ ] **Step 3: Run the three malformed-root controls**

```bash
python3 modules/home/ai/evals/harborize/checks/resolve_check.py /nonexistent/path
python3 modules/home/ai/evals/harborize/checks/resolve_check.py modules/home/ai/evals/harborize/README.md
mkdir -p /tmp/badcond/not-a-skill && python3 modules/home/ai/evals/harborize/checks/resolve_check.py /tmp/badcond
```

Expected: `FileNotFoundError`, then `ValueError: Skill path must be a directory`, then `ValueError` naming the child directory without a `SKILL.md`, each raised on the host before any container starts (`_find_skill_dirs`, `skills.py:382-416`).

- [ ] **Step 4: Record what this rung does and does not prove**

Write into the workspace README that this is host-side resolution only, and that a trial's `lock.json` cannot substitute for delivery evidence: `_write_trial_lock` runs at `trial.py:104` inside `Trial.__init__`, before `_resolve_injected_skills` at `:107` and long before `_upload_injected_skills` at `:411`, and `_build_agent_skill_locks` (`models/job/lock.py:462-475`) calls only host-side functions.

- [ ] **Step 5: Check off tasks.md §4 and hand the working copy back for routing**

---

## Task 5: Package authoring, dual head

**Files:**
- Create: `modules/home/ai/evals/harborize/injection-canary/task.md`
- Create: `modules/home/ai/evals/harborize/injection-canary/environment/Dockerfile`
- Create: `modules/home/ai/evals/harborize/injection-canary/environment/skills/.gitkeep`
- Create: `modules/home/ai/evals/harborize/injection-canary/oracle/solve.sh`
- Create: `modules/home/ai/evals/harborize/injection-canary/verifier/test.sh`
- Create: `modules/home/ai/evals/harborize/<mechanical-task-id>/` with the same shape
- Generate: `modules/home/ai/evals/harborize/injection-canary-harbor/`, `modules/home/ai/evals/harborize/<mechanical-task-id>-harbor/`

**Interfaces:**
- Consumes: the token `HARBORIZE-CANARY-9F3A21` from Task 2.
- Produces: two authored native trees and two exported Harbor heads for Tasks 6, 7 and 8.
- Acceptance condition: no file in either authored tree or either exported head carries the `.nix` extension, per the Global Constraints, and the flake still evaluates afterwards.
  This is the first task that creates package directories, and two of the four are written by `bench tasks export` rather than authored here, so the audit runs against the generated heads as well and is repeated after every re-export.

- [ ] **Step 1: Write the canary oracle**

```bash
#!/bin/bash
set -euo pipefail
out=/logs/verifier/canary-output.txt
mkdir -p /logs/verifier
: > "$out"
for root in /harbor/skills "$HOME/.claude/skills" "$HOME/.codex/skills" \
            "$HOME/.opencode/skills" "$HOME/.agents/skills" /skills; do
  [ -d "$root" ] || continue
  for f in "$root"/*/SKILL.md; do
    [ -f "$f" ] || continue
    grep -ho 'HARBORIZE-CANARY-[A-Z0-9]*' "$f" >> "$out" || true
  done
done
sort -u -o "$out" "$out"
```

The search covers Harbor's upload destination, which defaults to `/harbor/skills` (`models/trial/paths.py:41`) and is populated for every agent by `_upload_injected_skills` in `_prepare` (`trial.py:411`), BenchFlow's five oracle discovery paths (`agents/install.py:30-36`), and BenchFlow's sandbox mount at `/skills`.

The output path is `/logs/verifier/`, not the agent workspace, and the choice is load-bearing.
Under Harbor that directory is bind-mounted into the agent environment (`trial.py:1279-1283`) and into a separate verifier environment (`trial.py:686-692`) from the same host directory, so the oracle-to-verifier channel survives a later change of the verifier fork; a workspace path such as `/app` does not, because `_verifier_env_mounts` returns exactly one bind and no agent-workspace mount.
Harbor's verifier does not clear the directory before reading the reward (`verifier/verifier.py:199-236`), and BenchFlow treats `/logs/verifier/` as its standard verifier contract path.

- [ ] **Step 2: Fix the canary's verifier fork as shared, and write the verifier**

The canary ships no `verifier/Dockerfile` and declares no `[verifier.sandbox]` table, so it runs shared.
The fork is forced rather than preferred: under BenchFlow a separate verifier sandbox is "parsed but not executed" (`task/runtime_capabilities.py:186-192`), so the verifier runs in the agent sandbox whatever the package declares, and shared is the one fork both runners execute identically.
The mechanical package is where separate mode gets exercised, on the Harbor arm, per Step 5.

```bash
#!/bin/bash
mkdir -p /logs/verifier
if grep -qx 'HARBORIZE-CANARY-9F3A21' /logs/verifier/canary-output.txt; then
  echo 1 > /logs/verifier/reward.txt
else
  echo 0 > /logs/verifier/reward.txt
fi
```

A single binary reward key, written to the only output channel either runner reads.
Harbor parses `reward.txt` into a one-key `rewards` dict whose key is the literal `reward` (`verifier/verifier.py:73`), which is what keeps pass@k enabled (`utils/pass_at_k.py:36-52`).

- [ ] **Step 3: Write the canary `task.md` frontmatter and body**

Frontmatter carries `schema_version: '1.3'`, a `metadata` block, `verifier.type: test-script`, `agent.timeout_sec`, and the `sandbox` spec per Step 4.
The body states the end state — that `/logs/verifier/canary-output.txt` holds the canary token — in imperative prose with absolute paths, and never mentions skills.
The body does not name the token: only the injected `SKILL.md` carries it, which is what makes the oracle's pass evidence of delivery.

- [ ] **Step 4: Declare the network policy on every package**

In the native `task.md` frontmatter, using BenchFlow's own `sandbox` spelling:

```yaml
sandbox:
  network_mode: public        # baseline: what the container is created with
agent:
  network_mode: no-network    # phase override; drop this key on probe exit 1
```

`bench tasks export` renames `sandbox` to Harbor's `[environment]` on the way out (`task/export.py:383-387`) and leaves `[agent]` as it is, so the exported head reads `[environment] network_mode = "public"` with `[agent] network_mode = "no-network"`.

The baseline is what the container is created with (`trial.py:896`) and the phase policy is applied around `_run_agent_phase` alone (`trial.py:465-469`), so a `no-network` baseline breaks claude-code's install fetch during `_prepare` while a `no-network` agent phase does not.
Harbor reads the override through `task_cfg.agent.explicit_phase_policy()` (`trial/network_policy.py:45-59`) and validates that the environment can switch policy after start (`trial.py:203-217`); BenchFlow carries the same field at `task/config.py:524-530`.
Drop the `[agent]` table entirely when Task 1 Step 2 returned exit 1, because the switch would then be rejected at environment start.

- [ ] **Step 5: Write the mechanical package the same way**

Pick a task whose success is a decidable predicate on final state, sampling the claimed contract of the skill under test rather than that skill's own examples.
Keep the reward binary.
Record the verifier fork in the package README with its justification: a separate-mode package declares `[verifier.sandbox]` — exported as Harbor's `[verifier.environment]` — ships `verifier/Dockerfile` that installs its tooling and places `/tests/test.sh`, and never sets `docker_image`, because Harbor uploads nothing into a separate verifier image; a shared-mode package omits the table entirely.
A separate-mode declaration is exercised on the Harbor arm only, for the reason in Step 2.

- [ ] **Step 6: Export both Harbor heads**

```bash
bench tasks export modules/home/ai/evals/harborize/injection-canary modules/home/ai/evals/harborize/injection-canary-harbor \
  --target harbor --overwrite
```

`--overwrite` is required from the second export onwards: `export.py:255-256` raises `FileExistsError` on an existing destination, and the CLI exposes the flag at `cli/tasks.py:294-297`.

Expected: the sibling directory is written with `task.toml`, `instruction.md`, `solution/solve.sh`, `tests/`, `environment/` and `compatibility/export-report.json`.
Read the export report and record anything that did not survive the conversion.
Never hand-edit the derived head, and re-export after every edit to the native tree.

- [ ] **Step 7: Run the leakage audit on both packages**

```bash
SKILL=modules/home/ai/plugins/testing-and-quality/.apm/skills/harborize
python3 "$SKILL/scripts/audit_leakage.py" --task modules/home/ai/evals/harborize/<mechanical-task-id> --skills <skill-dir>
python3 "$SKILL/scripts/audit_leakage.py" --task modules/home/ai/evals/harborize/injection-canary --skills modules/home/ai/evals/harborize/conditions/canary/harborize-injection-canary
```

Expected: exit 0 on the mechanical package; exit 1 on the canary with a check-1 literal flag naming the token.
Exit 2 means the audit could not run, which is a mis-invocation rather than a clean package.
Record the canary's flag with the justification from Task 2 Step 3.

- [ ] **Step 8: Audit the four package directories for the `.nix` extension and re-run the flake-evaluation guard**

```bash
if fd -H -e nix . modules/home/ai/evals/harborize | rg -q .; then
  echo "FAIL: a .nix file is inside the corpus"; exit 1
fi
nix eval .#nixosConfigurations --apply builtins.attrNames
```

Expected: the audit finds nothing and the eval exits 0.
Run it after Step 6's export rather than only after Step 5's authoring, because the two Harbor heads are generated and an extension the export introduces would otherwise reach the flake unaudited.
Re-run it after any later re-export.

- [ ] **Step 9: Stamp both package READMEs with instrument version 0.2.1 and the three upstream pins, then check off tasks.md §5 and hand the working copy back for routing**

---

## Task 6: Static task validation

**Files:**
- Create: `modules/home/ai/evals/harborize/checks/harbor_schema_check.py`

**Interfaces:**
- Consumes: the four package directories from Task 5.
- Produces: a clean static gate per head, and a recorded statement of what the Harbor gate cannot catch.

- [ ] **Step 1: Run the BenchFlow gate against each authored native tree**

```bash
bench tasks check modules/home/ai/evals/harborize/injection-canary --level structural
bench tasks check modules/home/ai/evals/harborize/<mechanical-task-id> --level structural
```

Expected: exit 0 with no issues.
The levels are schema, structural (default), runtime-capability, publication-grade, acceptance and acceptance-live (benchflow `cli/tasks.py:93-115`), and nothing below acceptance-live spends a model call.

- [ ] **Step 2: Write the Harbor schema check**

```python
import sys
from harbor.models.task.task import Task

task = Task(sys.argv[1])
print("constructed:", task.paths.task_dir)
```

- [ ] **Step 3: Run it against each exported head**

```bash
python3 modules/home/ai/evals/harborize/checks/harbor_schema_check.py modules/home/ai/evals/harborize/injection-canary-harbor
python3 modules/home/ai/evals/harborize/checks/harbor_schema_check.py modules/home/ai/evals/harborize/<mechanical-task-id>-harbor
```

Expected: both print `constructed:` and exit 0.
Do not call `harbor task check` or `harbor tasks check`: both spellings reach one command that prints an error and raises `SystemExit(1)` unconditionally (`cli/tasks.py:476-487`).
Do not follow that stub's own redirect either.
It prints "Use 'harbor check <task-dir>' instead" (`cli/tasks.py:483-486`), and `harbor check` is a metered LLM-rubric run defaulting to `claude-code` and `claude-sonnet-4-6` (`cli/main.py:160`, `cli/analyze.py:100-103`), so obeying the CLI would spend money inside a rung this plan calls free.

- [ ] **Step 4: Record the gate's blind spot**

Write into the workspace README that `Task._validate_tests` returns early whenever a verifier environment is configured (`models/task/task.py:126-144`, early return at `:134-135`), so a separate-mode package whose verifier image does not own `/tests/test.sh` passes schema validation and fails at run time.

- [ ] **Step 5: Check off tasks.md §6 and hand the working copy back for routing**

---

## Task 7: Delivery proof under BenchFlow

**Files:**
- Modify: `modules/home/ai/evals/harborize/README.md` (record the rung's evidence)

**Interfaces:**
- Consumes: the canary package from Task 5 and `dir(C)` from Task 2.
- Produces: end-to-end delivery evidence with zero model calls, which is the precondition for any metered run using that `dir(C)` shape.

- [ ] **Step 1: Run the canary under the oracle agent**

```bash
bench eval run --tasks-dir modules/home/ai/evals/harborize/injection-canary --agent oracle \
  --skill-mode with-skill --skills-dir modules/home/ai/evals/harborize/conditions/canary \
  --sandbox docker --jobs-dir logs/harborize/canary-bench
```

Expected: the rollout reaches the agent phase and reward equals 1.
No model is materialized: `evaluation.py:461-462` returns None for the oracle agent.
The deployment path still runs in full: `rollout/__init__.py:1160` takes the `primary_agent == "oracle"` branch and calls `deploy_skills` at `:1174`.

- [ ] **Step 2: Confirm the fidelity assertion passed and the effective directory is the host path**

```bash
rg -c 'skill_deployment_missing' logs/harborize/canary-bench || echo "clean"
rg -o '"effective_skills_dir":[^,]*' logs/harborize/canary-bench -r '$0' | sort -u
```

Expected: `clean`, and every `effective_skills_dir` equal to the host `dir(C)` that was passed.
The assertion runs in the container: `deploy_skills` computes the expected catalogue on the host from `Path(skills_dir).glob("*/SKILL.md")` (`agents/install.py:303`, `:313-314`), falls back to the five `_ORACLE_SKILL_PATHS` (`:30-36`) at `:349-350`, and `_link_skill_paths` compares the in-container catalogue to the host's (`:146-161`) before raising at `:176-180`.

- [ ] **Step 3: Run the falsifiability control**

```bash
bench eval run --tasks-dir modules/home/ai/evals/harborize/injection-canary --agent oracle \
  --skill-mode no-skill \
  --sandbox docker --jobs-dir logs/harborize/canary-bench-negative
```

Expected: reward 0, because the token never reaches the container.
`no-skill` cannot be combined with `--skills-dir`, so the empty condition is the mode alone.
This is the canary's proof that it can fail, which is what makes its passing run evidence rather than a constant.
It is explicitly not the fidelity control: with no `skills_dir`, `expected_skill_names` is the empty tuple (`agents/install.py:313-317`) and the `experiment_fidelity/skill_deployment_missing` raise is guarded on `if expected:` (`:176-180`), so this run cannot raise it.

- [ ] **Step 4: Run the fidelity control against a throwaway sibling**

The fidelity assertion compares the in-container skill catalogue against the host-computed one, so no edit to `dir(C)` alone separates them: `_skill_link_cmd` replaces each discovery path with a symlink to the uploaded source (`agents/install.py:90`), which makes the `actual == source_catalog` test at `:157` tautological, leaving only the `source_catalog == expected` test at `:159-161`.
The one author-constructible divergence is an image that already carries a different condition.

```bash
cp -R modules/home/ai/evals/harborize/injection-canary /tmp/canary-fidelity-control
mkdir -p /tmp/canary-fidelity-control/environment/_deps/skills/decoy-skill
printf -- '---\nname: decoy-skill\ndescription: decoy\n---\n' \
  > /tmp/canary-fidelity-control/environment/_deps/skills/decoy-skill/SKILL.md
printf 'COPY _deps/skills /skills/\n' \
  >> /tmp/canary-fidelity-control/environment/Dockerfile
bench eval run --tasks-dir /tmp/canary-fidelity-control --agent oracle \
  --skill-mode with-skill --skills-dir modules/home/ai/evals/harborize/conditions/canary \
  --sandbox docker --jobs-dir logs/harborize/canary-bench-fidelity
```

Expected: a raised `experiment_fidelity/skill_deployment_missing` naming `harborize-injection-canary` as the expected set.
`deploy_skills` finds the `COPY _deps/skills /skills/` line and takes the `already_injected` branch (`agents/install.py:328-332`, `:342-344`), performs no runtime upload, so `/skills` carries `decoy-skill` while `expected` still carries the host `dir(C)`.
Delete `/tmp/canary-fidelity-control` afterwards; it is a control fixture and not part of the corpus.

- [ ] **Step 5: Repeat Step 1 for every distinct dir(C) shape this change uses, then check off tasks.md §7 and hand the working copy back for routing**

---

## Task 8: Harbor oracle inhabitation

**Files:**
- Modify: `modules/home/ai/evals/harborize/README.md` (record five-of-five evidence per package)

**Interfaces:**
- Consumes: the exported Harbor heads from Task 5.
- Produces: the inhabitation witness the review gate requires before any agent run counts.

- [ ] **Step 1: Run the oracle five times per package**

```bash
HARBOR_TELEMETRY=0 harbor run -p modules/home/ai/evals/harborize/injection-canary-harbor \
  -k 5 -o logs/harborize/gate1 --job-name canary-gate1 -y \
  --skill ./modules/home/ai/evals/harborize/conditions/canary
HARBOR_TELEMETRY=0 harbor run -p modules/home/ai/evals/harborize/<mechanical-task-id>-harbor \
  -k 5 -o logs/harborize/gate1 --job-name mechanical-gate1 -y
```

Oracle is Harbor's default agent (`models/trial/config.py:164-168`), so `-a` and `-m` are unnecessary.
`OracleAgent.run` (`agents/oracle.py:81-136`) uploads `solution/` and execs `solve.sh`; no LLM client appears in the file.
The `./` prefix on the `--skill` path is a precaution: `resolve_skill_sources` takes the local branch whenever the path exists or begins with `.`, `/` or `~`, and parses a non-existent relative path as a git source.

- [ ] **Step 2: Check both halves of the pass criterion**

```bash
n=$(rg --no-filename -o '"reward":\s*[0-9.]+' logs/harborize/gate1 | sort | uniq -c | tee /dev/stderr | wc -l)
[ "$n" -gt 0 ] || { echo "FAIL: no reward lines found — the check did not run"; exit 1; }
fd -H 'exit-code.txt' logs/harborize/gate1 -x cat {}
```

Expected: `"reward": 1.0` on all five trials of each job, zero errored trials, and no `exit-code.txt` at all, or one containing `0`.
The non-empty assertion is load-bearing, because an empty grep prints nothing and nothing reads as "no failures" rather than as "the check did not run".
The singular `reward` is the key Harbor actually emits inside the plural `rewards` dict: `VerifierResult.rewards` is a `dict[str, float | int]` (`models/verifier/result.py:5`) and `_parse_reward_text` fills it with `{"reward": float(...)}` (`verifier/verifier.py:73`), so a search for `"rewards"` alone would find the container and not the value.
Reading rewards alone is insufficient: a broken oracle exiting nonzero does not raise, because `oracle.py:149-151` writes `exit-code.txt` and proceeds to the verifier, scoring 0.

- [ ] **Step 3: Triage any errored trial by exception name before rerunning**

`RetryConfig.max_retries` defaults to 0 (`models/job/config.py:282-284`), so every exception is terminal unless `-r N` is passed.
Four of the nine names in the no-retry list at `:288-300` are defined in `agents/installed/base.py`, which `OracleAgent` does not subclass, so any of them in a Gate-1 log means the job was not running the oracle.
Four further exceptions kill a trial without appearing in that list: `AddTestsDirError` (`verifier/verifier.py:19`), `DownloadVerifierDirError` (`:27`), and a bare `FileNotFoundError` from `_resolve_tests` or from a missing solve.sh (`oracle.py:94-95`).

- [ ] **Step 4: Record five-of-five per package in the workspace README, then check off tasks.md §8 and hand the working copy back for routing**

---

## Task 9: Metered registration assertion

**Files:**
- Modify: `modules/home/ai/evals/harborize/README.md` (record the per-adapter assertion and the cost figures)

**Interfaces:**
- Consumes: the validated cells file from Task 3 and the canary Harbor head from Task 5.
- Produces: the only evidence that Harbor's adapter registration copy ran, plus the raw job accounting Task 10 turns into the cost constant.

- [ ] **Step 1: Scrub subscription auth and confirm the scrub**

```bash
env | rg 'ANTHROPIC_OAUTH_TOKEN|CLAUDE_CODE_OAUTH_TOKEN|CODEX_AUTH_JSON_PATH' || echo "clean"
export ANTHROPIC_OAUTH_TOKEN=""
```

Expected: `clean`, or an explicit empty assignment.
Pi injects `ANTHROPIC_OAUTH_TOKEN` whenever the variable is present and non-empty in the resolved environment and the provider is anthropic, with no force flag of the kind claude-code and codex require, so withholding a flag is not enforcement.
The check is a walrus on the value rather than a membership test (`pi.py:102-105`), which is exactly why assigning the empty string suppresses the injection as reliably as unsetting the variable.

- [ ] **Step 2: Confirm the canary head's network baseline before spending**

```bash
rg -n 'network_mode' modules/home/ai/evals/harborize/injection-canary-harbor/task.toml
```

Expected: `network_mode = "public"` under `[environment]`, and `no-network` only under `[agent]` if Task 1 Step 2 permitted it.
A `no-network` baseline makes the next step fail during claude-code's install fetch rather than at the registration copy, which is the failure design.md's risk register predicts and the one this ordering exists to avoid.

- [ ] **Step 3: Run one short metered trial on the claude-code cell**

```bash
HARBOR_TELEMETRY=0 ANTHROPIC_OAUTH_TOKEN="" harbor run \
  -p modules/home/ai/evals/harborize/injection-canary-harbor \
  -a claude-code -m anthropic/claude-opus-5 -k 1 \
  --skill ./modules/home/ai/evals/harborize/conditions/canary \
  -o logs/harborize/gate1 --job-name cc-registration -y
```

This is the only rung that reaches the registration copy.
`--install-only` cannot substitute: `_build_register_skills_command` (`claude_code.py:1530-1542`) is appended to `setup_command` at `:1733-1735`, both inside `async def run` beginning at `:1601`; `Trial.run` guards `_run()` on `not install_only` (`trial.py:375-378`); and `TrialConfig._install_only_disables_verification` (`models/trial/config.py:484-494`) disables the verifier too.

- [ ] **Step 4: Assert the registration destination from the host**

```bash
fd -H -t d 'harborize-injection-canary' logs/harborize/gate1/cc-registration
```

Expected: a path under the trial's `agent/sessions/skills/` directory.
`CLAUDE_CONFIG_DIR` is set to `EnvironmentPaths.agent_dir / "sessions"` (`claude_code.py:1718`), which is `/logs/agent/sessions` because `agent_dir` is `logs_dir / "agent"` (`models/trial/paths.py:36`), and `/logs/agent` is bind-mounted from the trial directory (`trial.py:1284-1288`), so what the adapter registered is readable on the host with no verifier code.
The criterion is the directory alone and deliberately not the reward.
The canary's verifier is shared (Task 5 Step 2), so a real agent can reach the token without the skill being delivered, and this trial's reward therefore carries no injection information in either direction.

- [ ] **Step 5: For any additional cell, assert that adapter's own destination**

codex and pi register at `$HOME/.agents/skills/<name>/` (`codex.py:1199-1207`, `pi.py:75-83`) and opencode at `~/.config/opencode/skills/<name>/` (`opencode.py:425-433`), none of which sits in a bind mount, so those assertions need an in-container check rather than a host read.

- [ ] **Step 6: Record the cross-runner limitation**

Write into the workspace README that pi, opencode and claude are not cross-runner comparable at these revisions, because BenchFlow's registry declares `["$HOME/.pi/agent/skills", "$HOME/.agents/skills"]` for `pi-acp` (`registry.py:560`) and `["$HOME/.opencode/skills"]` for `opencode` (`:700`), and codex is the one cell where both runners agree.

- [ ] **Step 7: Check off tasks.md §9 and hand the working copy back for routing**

---

## Task 10: Record, stamp and close

**Files:**
- Modify: `modules/home/ai/evals/harborize/README.md`
- Create: `modules/home/ai/evals/harborize/results/cost-constant.json`

**Interfaces:**
- Consumes: the job accounting from Task 9.
- Produces: the per-run cost constant the dependent change consumes, and the close-out evidence for verify.md.

- [ ] **Step 1: Extract the per-run cost from the metered job**

```bash
cost=$(rg --no-filename -o '"cost_usd":\s*[0-9.]+' \
  logs/harborize/gate1/cc-registration | rg -o '[0-9.]+$' | sort -rn | head -1)
[ -n "$cost" ] || { echo "FAIL: no cost_usd found — do not record a zero"; exit 1; }
echo "per-run cost: $cost"
```

Read the job's own accounting rather than estimating from token counts.
The field is `cost_usd`, not `cost` or `usage`: `JobResult.cost_usd` (`models/job/result.py:41`) accumulates at `:169` from the per-trial `AgentContext.cost_usd` that the adapter sets from `metrics.total_cost_usd` (`agents/installed/claude_code.py:1525`).
A search for `"cost"` or `"total_cost"` matches nothing, because neither spelling exists at this revision.
The non-empty assertion is required: an empty extraction must fail this task rather than leave the placeholder in Step 2 reading as a measured zero.

- [ ] **Step 2: Write the cost record**

```json
{
  "per_run_cost_usd": null,
  "cell": "claude-code + anthropic/claude-opus-5",
  "task": "injection-canary",
  "trials": 1,
  "auth_mode": "metered-api-key",
  "instrument_version": "0.2.1",
  "harbor_rev": "ac398bbda7c4c1073461797d3b95c2455cc671b5",
  "note": "a cost per run is a function of the cell and the task, not of the runner"
}
```

The placeholder is `null` rather than `0.0` so an unreplaced slot is unambiguous; a committed `0.0` would read as a measured zero, and this number is the change's headline deliverable.
Replace `per_run_cost_usd` with the figure Step 1 extracted, and assert it is non-null before the change closes.
Do not multiply it by any condition count, cell count or run total inside this change.

- [ ] **Step 3: Confirm the canary is retained and named as a per-round precondition**

```bash
ls modules/home/ai/evals/harborize/injection-canary modules/home/ai/evals/harborize/conditions/canary
```

Write into the workspace README that Task 7 Step 1 is re-run at the start of every later evaluation round, before any metered batch.

- [ ] **Step 4: Confirm the instrument is unmodified**

```bash
find modules/home/ai/plugins/testing-and-quality/.apm/skills/harborize -type f \
  -exec shasum -a 256 {} + | LC_ALL=C sort | shasum -a 256
```

Expected: the digest equals the baseline Task 1 Step 5 recorded in the workspace README.
The digest is the check rather than `jj diff --stat -r @ -- <harborize path>`, because that diff reports only what the working-copy commit changed against its parents and would print nothing for an edit squashed into the `harborize-instrument` chain — the chain this plan explicitly routes onto, and therefore the most likely way the freeze would be violated.

- [ ] **Step 5: List the deferred instrument defects**

Write into the workspace README every instrument defect found during the change, deferred to the next revision, with its evidence.
The list opens with three already known: the canary leakage flag from Task 2 Step 3; the `--membership-from` census workflow; and `CHANGELOG.md:55`, which attributes `network_mode = "no-network"` to Harbor when Harbor's default is `public` (`models/task/config.py:249-252`) and the `no-network` default is the instrument's own authoring prescription at `SKILL.md:124`.

- [ ] **Step 6: Write the review-gate audit into each package README**

One line per algebraic invariant — truncation, inhabitation, non-triviality, coupling, grade discipline, empirical naturality, nucleus hygiene — with pass or fail and its evidence.
A package failing truncation, inhabitation, non-triviality or coupling is not done.

- [ ] **Step 7: Check off tasks.md §10 and hand the working copy back for routing**
