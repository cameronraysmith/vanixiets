# injection-canary

Instrument-integrity canary for the harborize instrument.

Instrument version: 0.2.1 (frozen for the duration of the `validate-harborize-instrument` change).

Upstream pins every source anchor cites: harbor `ac398bbda7c4c1073461797d3b95c2455cc671b5`, benchflow `d30527b82027a416e72014920cdf43a534967ad3`, skillsbench `9a1f4dd5f7659f75707435da3ce854b6e48321d1`.

## What it asserts

The oracle greps every skill discovery root (`/harbor/skills`, the per-agent `.claude`/`.codex`/`.opencode`/`.agents` paths, and `/skills`) for the canary token and writes what it finds to `/logs/verifier/canary-output.txt`; the verifier rewards 1 exactly when that file holds `HARBORIZE-CANARY-9F3A21`.

The token appears nowhere in the deployed skill tree, which is what makes a reward of 1 evidence that delivered skill content reached a container discovery path.
It is not true that the token lives *only* in the injected `SKILL.md`: it is also the asserted literal in this package's own `verifier/test.sh`, which is why the leakage audit flags it below.
That second copy does not weaken the inference, because no agent phase can observe it — both runners upload the verifier's directory during the verification phase, after the agent phase has ended (see the fork section).

The evidence is one-directional and only the positive direction is read.
Under the oracle, which greps every discovery root unconditionally, reward 1 and reward 0 are both informative, and the falsifiability control at task 7.3 establishes that the 0 is reachable.
Under a model-driven agent only reward 1 carries delivery information, because a model that never greps scores 0 with the skill perfectly delivered.
That is why rung 6 asserts the adapter's registration directory instead.

## Verifier fork: shared

No `verifier/Dockerfile` and no `verifier.sandbox_mode`, so the verifier runs in the agent sandbox.
The fork is forced rather than preferred, and each runner forces it for its own reason.

BenchFlow refuses to launch a task that declares separate rather than falling back to shared.
`runtime_capabilities.py:186-192` raises an unsupported-feature issue — its reason string reads "separate verifier sandboxes are parsed but not executed", which is the wording of a refusal and not of a fallback — and `raise_for_task_runtime_support` is a fail-closed pre-launch gate (`sandbox/setup.py:676`, `:819-842`).

Harbor's separate verifier would destroy this canary's oracle-to-verifier channel.
`_run_separate_verifier` empties `/logs/verifier` before the verifier runs (`trial.py:599`), through the same host bind it mounts at `:686-692`, so `canary-output.txt` would be gone before `grep` looked for it and every trial would score 0.
`_run_shared_verifier` (`trial.py:536-567`) performs no wipe, which is what makes `/logs/verifier/canary-output.txt` a sound channel under the fork actually used.

## Known leakage flag

`audit_leakage.py` check 1 flags the token (`MIN_LITERAL_LENGTH` at `:44`, `check_literals` at `:96`) because the asserted literal appears in both the verifier and the injected `SKILL.md`.
That is by design: the canary's mechanism is its answer key.
The instrument is frozen at 0.2.1 and is not edited to exempt it; the instrument-side question is deferred to the next revision.

A consequence that was accepted and turns out not to arise: the fork being shared does not put the token within a running agent's reach.
Both runners upload the verifier's own directory during the verification phase, after the agent phase has ended — Harbor at `verifier/verifier.py:147-153`, reached from `_run_shared_verifier`, with the phase order fixed at `trial/single_step.py:41` then `:52`; BenchFlow at `task/verifier_core.py:385`, inside `verify()`.
No agent phase observes `test.sh`.

Rung 6 still scores on the adapter's registration directory rather than on the reward, for a reason that does not depend on that: a model-driven trial's reward conflates delivery with the model's own behaviour, since a model that never greps scores 0 with the skill perfectly delivered.
The registration directory is the deterministic witness; the reward is not.
The falsifiability control runs under the oracle, which greps skill directories and never reads the verifier.
