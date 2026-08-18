# pipeline-event-summary

The change's one mechanical evaluation package, sampling the claimed contract of the `preferences-json-querying` skill (NDJSON aggregation, grouping, and nested access with DuckDB or jaq) rather than that skill's own examples: given a build event log, produce an exact aggregate summary.

Instrument version: 0.2.1 (frozen for the duration of the `validate-harborize-instrument` change).

Upstream pins every source anchor cites: harbor `ac398bbda7c4c1073461797d3b95c2455cc671b5`, benchflow `d30527b82027a416e72014920cdf43a534967ad3`, skillsbench `9a1f4dd5f7659f75707435da3ce854b6e48321d1`.

## Reward

A single binary reward key, so the predicate is decidable on final state and multi-dimensional rubrics — which would silently disable Harbor's pass@k and BenchFlow's compare-lift — are not in play.

The verifier holds its expectation as a literal, hand-derived by reading the fifteen fixture records, and rewards 1 only on exact structural equality with integers-only values.
It does not recompute the summary from a copy of the fixture.
Recomputation is the obvious shape and it is wrong here: the verifier would run the oracle's own algorithm, agree with a wrong oracle, and be structurally incapable of failing on one.
That is not hypothetical for this task.
The median convention is the case that bites — a verifier sharing the oracle's `durations[n // 2]` accepts the upper median and rejects the true median the task statement asks for, and the disagreement is invisible while the fixture holds an odd number of records.
Both sides now state the convention explicitly: `task.md` defines the even-count case and `oracle/solve.sh` implements it.

The literal is what makes the oracle-inhabitation rung a real check on the oracle rather than a check that the oracle agrees with itself.
It also fixes the answer to the shipped fixture: growing `environment/build-events.jsonl` without updating the literal fails `harbor run -k 5` loudly instead of silently redefining the expected answer on both sides at once.

## Verifier fork: shared

No `verifier/Dockerfile` and no `verifier.sandbox_mode`, so the verifier runs in the agent sandbox.
The fork is forced rather than preferred, and both runners force it independently against harbor 0.21.0 and benchflow 0.7.4.

BenchFlow does not fall back to shared when a package declares separate: it refuses to launch the task at all.
`runtime_capabilities.py:186-192` raises an unsupported-feature issue whose reason string is "separate verifier sandboxes are parsed but not executed", and `raise_for_task_runtime_support` is a fail-closed pre-launch gate (`sandbox/setup.py:676`, `:819-842`).
Reproduced: `bench tasks check <pkg> --level runtime-capability --sandbox docker` exits 0 on this package as shipped and reports that one issue the moment `verifier.sandbox_mode: separate` is added.
The proposal requires this package to pass under both runners, so a Harbor-only fork is not available to it.

Harbor's separate verifier would also destroy this package's agent-to-verifier channel.
`_run_separate_verifier` empties `/logs/verifier` before the verifier runs (`trial.py:599`, `environments/base.py:626-638`), and that path is bind-mounted from the host (`trial.py:686-692`), so `summary.json` is deleted and every agent including the oracle scores 0.
Surviving it would mean moving the deliverable to `/logs/artifacts/`, which the artifact re-upload restores after the wipe (`trial.py:601-607`, `artifact_handler.py:210-254`) — a different task contract, not a fork choice.

`_run_shared_verifier` (`trial.py:536-567`) performs no wipe, and both packages are single-step, which is the precondition that claim needs: the multi-step path calls `_reset_shared_step_verifier_dirs` (`multi_step.py:202`, defined at `:338-342`) before every shared step verifier, so a package that ever grows `[[steps]]` loses this channel. `SingleStepTrial.__init__` raises on a stepped task (`single_step.py:28-29`), so the two cannot be confused silently.
That is why `/logs/verifier/summary.json` is a sound channel under the fork actually used.

## What the agent can and cannot see

The verifier's expectation is a literal, so it is worth stating why that is not a leak.
On both runners the verifier's own directory is uploaded during the verification phase, after the agent phase has ended — Harbor at `verifier/verifier.py:147-153`, reached from `_run_shared_verifier`, with the phase order fixed at `trial/single_step.py:41` then `:52`; BenchFlow at `task/verifier_core.py:385` in `_verify_test_script` (`:346`), reached from `verify()` (`:260`).
No agent phase ever observes `test.sh`, under either fork.

## Leakage audit

`audit_leakage.py --task pipeline-event-summary --skills <preferences-json-querying skill dir>` exits 0: the verifier carries no quoted expectation literal recoverable from the skill (the summary key `per_pipeline` was chosen over `pipelines`, which appears in the skill's prose and would trip check 1 as a false positive on a schema key).

## Environment pinning

The package's one Dockerfile, `environment/Dockerfile`, pins its base image by index digest, `ubuntu:24.04@sha256:561618e2c15bf2397621dd04f96926663a3b5616c189cf7e38db7e82f5c538ea`, which is the image this corpus's recorded evidence was produced against.
The floating tag had already drifted to a later build at rung-0 time, so an unpinned instrument would compare measurements taken in different environments.
The index digest is pinned rather than a platform manifest, so the same line resolves correctly on `linux/arm64` and `linux/amd64`.
