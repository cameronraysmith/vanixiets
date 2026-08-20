# injection-canary

Instrument-integrity canary for the harborize instrument.

Instrument version: 0.2.1 (frozen for the duration of the `validate-harborize-instrument` change).

Upstream pins every source anchor cites: harbor `ac398bbda7c4c1073461797d3b95c2455cc671b5`, benchflow `d30527b82027a416e72014920cdf43a534967ad3`, skillsbench `9a1f4dd5f7659f75707435da3ce854b6e48321d1`.

## What it asserts

The oracle greps every skill discovery root (`/harbor/skills`, the per-agent `.claude`/`.codex`/`.opencode`/`.agents` paths, and `/skills`) for the canary token and writes what it finds to `/logs/artifacts/canary-output.txt`; the verifier rewards 1 exactly when that file holds `HARBORIZE-CANARY-9F3A21`.

The token exists in exactly two places: the canary `SKILL.md` this package injects, and the asserted literal in its own `verifier/test.sh`.
It appears nowhere in the skill corpus under evaluation, which is what makes a reward of 1 evidence that delivered skill content reached a container discovery path.
The verifier's copy does not weaken that inference, because no agent phase can observe it — both runners upload the verifier's directory during the verification phase, after the agent phase has ended (see the fork section).
The claim this replaces, that the token lives only in the injected `SKILL.md`, was false in the other direction: the verifier's copy is real, and is why the leakage audit flags this package below.

The evidence is one-directional and only the positive direction is read.
Under the oracle, which greps every discovery root unconditionally, reward 1 and reward 0 are both informative, and the falsifiability control at task 7.3 establishes that the 0 is reachable.
Under a model-driven agent only reward 1 carries delivery information, because a model that never greps scores 0 with the skill perfectly delivered.
That is why rung 6 asserts the adapter's registration directory instead.

## Verifier fork: shared

No `verifier/Dockerfile` and no `verifier.sandbox_mode`, so the verifier runs in the agent sandbox.
The fork is forced rather than preferred, and each runner forces it for its own reason.

BenchFlow refuses to launch a task that declares separate rather than falling back to shared.
`runtime_capabilities.py:186-192` raises an unsupported-feature issue — its reason string reads "separate verifier sandboxes are parsed but not executed", which is the wording of a refusal and not of a fallback — and `raise_for_task_runtime_support` is a fail-closed pre-launch gate (`sandbox/setup.py:676`, `:819-842`).

Harbor's separate verifier empties `/logs/verifier` before the verifier runs (`trial.py:599`), through the same host bind it mounts at `:686-692`.
`_run_shared_verifier` (`trial.py:536-567`) performs no wipe, and both packages are single-step, which is the precondition that claim needs: the multi-step path calls `_reset_shared_step_verifier_dirs` (`multi_step.py:202`, defined at `:338-342`) before every shared step verifier, so a package that ever grows `[[steps]]` loses that directory too. `SingleStepTrial.__init__` raises on a stepped task (`single_step.py:28-29`), so the two cannot be confused silently.

None of that decides the deliverable channel, because `/logs/verifier` is not the channel this package uses and cannot be.
BenchFlow clears the directory's contents on the agent container immediately before the verifier runs, unconditionally (`sandbox/lockdown.py:775-784` called from `harden_before_verify` at `:1205-1212`), so a `canary-output.txt` written there is gone before `grep` looks for it under BenchFlow and present under Harbor's shared fork — the runner-dependent silent 0 the corpus exists to prevent.
The oracle therefore writes `/logs/artifacts/canary-output.txt`, which both runners bind for the whole trial and neither hardening step touches; the workspace README's channel section carries the anchors and the rung-4 evidence.

## Known leakage flag

`audit_leakage.py` check 1 flags the token (`MIN_LITERAL_LENGTH` at `:44`, `check_literals` at `:96`) because the asserted literal appears in both the verifier and the injected `SKILL.md`.
That is by design: the canary's mechanism is its answer key.
The instrument is frozen at 0.2.1 and is not edited to exempt it; the instrument-side question is deferred to the next revision.

A consequence that was accepted and turns out not to arise: the fork being shared does not put the token within a running agent's reach.
Both runners upload the verifier's own directory during the verification phase, after the agent phase has ended — Harbor at `verifier/verifier.py:147-153`, reached from `_run_shared_verifier`, with the phase order fixed at `trial/single_step.py:41` then `:52`; BenchFlow at `task/verifier_core.py:385` in `_verify_test_script` (`:346`), reached from `verify()` (`:260`).
No agent phase observes `test.sh`.

Rung 6 still scores on the adapter's registration directory rather than on the reward, for a reason that does not depend on that: a model-driven trial's reward conflates delivery with the model's own behaviour, since a model that never greps scores 0 with the skill perfectly delivered.
The registration directory is the deterministic witness; the reward is not.
The falsifiability control runs under the oracle, which greps skill directories and never reads the verifier.
