# injection-canary

Instrument-integrity canary for the harborize instrument.

Instrument version: 0.2.1 (frozen for the duration of the
`validate-harborize-instrument` change).

Upstream pins every source anchor cites: harbor
`ac398bbda7c4c1073461797d3b95c2455cc671b5`, benchflow
`d30527b82027a416e72014920cdf43a534967ad3`, skillsbench
`9a1f4dd5f7659f75707435da3ce854b6e48321d1`.

## What it asserts

The oracle greps every skill discovery root (`/harbor/skills`, the per-agent
`.claude`/`.codex`/`.opencode`/`.agents` paths, and `/skills`) for the canary
token and writes what it finds to `/logs/verifier/canary-output.txt`; the
verifier rewards 1 exactly when that file holds `HARBORIZE-CANARY-9F3A21`. The
token lives only in the injected `SKILL.md`, so a reward of 1 is evidence that
delivered skill content reached a container discovery path.

## Verifier fork: shared

No `verifier/Dockerfile` and no `[verifier.sandbox]` table, so the verifier runs
in the agent sandbox. The fork is forced rather than preferred: under BenchFlow
a separate verifier sandbox is parsed but not executed
(`task/runtime_capabilities.py:186-192`), and under Harbor a separate verifier
container binds only `/logs/verifier` (`trial.py:681-692`), so shared is the one
fork both runners execute identically.

## Known leakage flag

`audit_leakage.py` check 1 flags the token (`MIN_LITERAL_LENGTH` at `:44`,
`check_literals` at `:96`) because the asserted literal appears in both the
verifier and the injected `SKILL.md`. That is by design: the canary's mechanism
is its answer key. The instrument is frozen at 0.2.1 and is not edited to exempt
it; the instrument-side question is deferred to the next revision.

Second consequence, accepted: because the fork is shared, a real agent in the
metered rung can read the token out of the verifier script without the skill
being delivered. That costs nothing here — rung 6's pass criterion is the
adapter's registration directory rather than the reward, and the falsifiability
control runs under the oracle, which greps skill directories and never reads the
verifier.
