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
