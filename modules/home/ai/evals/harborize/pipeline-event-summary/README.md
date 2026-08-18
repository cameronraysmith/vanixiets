# pipeline-event-summary

The change's one mechanical evaluation package, sampling the claimed contract of
the `preferences-json-querying` skill (NDJSON aggregation, grouping, and nested
access with DuckDB or jaq) rather than that skill's own examples: given a build
event log, produce an exact aggregate summary.

Instrument version: 0.2.1 (frozen for the duration of the
`validate-harborize-instrument` change).

Upstream pins every source anchor cites: harbor
`ac398bbda7c4c1073461797d3b95c2455cc671b5`, benchflow
`d30527b82027a416e72014920cdf43a534967ad3`, skillsbench
`9a1f4dd5f7659f75707435da3ce854b6e48321d1`.

## Reward

A single binary reward key. The verifier recomputes the summary from its own
copy of the fixture (`verifier/_deps/build-events.jsonl`) and rewards 1 only on
exact structural equality with integers-only values, so the predicate is
decidable on final state and multi-dimensional rubrics — which would silently
disable Harbor's pass@k and BenchFlow's compare-lift — are not in play.

## Verifier fork: separate

This package declares a separate verifier environment: `verifier/Dockerfile`
installs its own python and places `/tests/test.sh` beside its own `_deps`
fixture copy, because Harbor uploads nothing into a separate verifier image.
The fixture copy is the verifier's independent grounds for recomputation.

The fork is exercised on the Harbor arm only: under BenchFlow a separate
verifier sandbox is parsed but not executed (`task/runtime_capabilities.py:186-192`),
so the verifier runs in the agent sandbox whatever the package declares, and
`test.sh` resolves its fixture relative to its own location so both layouts
execute the same script (`/tests/_deps` under Harbor, `/verifier/_deps` under
BenchFlow).

The agent-to-verifier channel is `/logs/verifier/summary.json`, bind-mounted
into the agent environment and into a separate verifier environment from the
same host directory, so the channel survives a later change of the fork.

## Leakage audit

`audit_leakage.py --task pipeline-event-summary --skills
<preferences-json-querying skill dir>` exits 0: the verifier carries no quoted
expectation literal recoverable from the skill (the summary key `per_pipeline`
was chosen over `pipelines`, which appears in the skill's prose and would trip
check 1 as a false positive on a schema key).
