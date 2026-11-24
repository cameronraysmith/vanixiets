---
description: Long-running, streaming, or later-input-needing commands run as managed background processes captured with tee into logs/, never a bare blocking call; test runs carry a size class, and a run expected to exceed five minutes is announced before it starts.
---

## Long-running commands

A command that will run for a long time, stream output, or need input later belongs in a managed background process, not a blocking foreground call that ties up the turn waiting on it.

The capture itself is absolute and the numeric thresholds are advisory.
Any command expected to run longer than roughly thirty seconds or produce more than roughly ten lines is run as:

    <command> 2>&1 | tee logs/<lower-kebab-identifier>-$(date +%Y%m%d-%H%M%S).log

A `tail` or filter may follow the `tee`, never replace it.
A pipeline reports the exit status of its last stage, so piping straight to `tail` has already reported a real lint failure as success in this fleet; output exists once, so a discarded portion is unrecoverable and every later question costs a re-run; a state-mutating command cannot be re-run at all, so its evidence is simply gone; and a human cannot `tail -f` a pipeline, so skipping capture silently removes their ability to watch work they delegated.

Where the log files live and how the directory is verified is owned by the `preferences-style-and-conventions` skill's "File organization" section.

## Test sizes

A test's size class says two things: what it may touch or wait on, and how long one run may take, after the feature table of Google's test sizes ([Test Sizes](https://testing.googleblog.com/2010/12/test-sizes.html)) and the limits Bazel implies for them.

| | small | medium | large | enormous |
|---|---|---|---|---|
| one run at most (a check's build, a runtime test's script) | 1 minute | 5 minutes | 15 minutes | 60 minutes |
| may wait on the passage of time (a sleep, a scrape, flush or retry interval) | no | yes, within its limit | yes, within its limit | yes, within its limit |

Behaviour whose point is the passage of time, such as an outage window, a queue filling at its real rate or a crash loop, belongs in a test kept for it, not in the test that checks routing or filtering.

A timeout is set as tight as it can be without flakiness ([Bazel test encyclopedia](https://bazel.build/reference/test-encyclopedia)); a test whose time varies with its own timers is fixed in the test, not given a looser timeout or a larger class.
Before starting any run expected to exceed 5 minutes, state its expected duration, what it proves that a cheaper run cannot, and what waits on its result.
A subagent returns to its orchestrator with that notice instead of starting the run; an orchestrator gives the notice to the operator before starting it.
A test larger than its purpose is a defect to report, with a proposal to split it or to move its slow part into a case of a larger class.
A repository that enforces classes says how in its own context; elsewhere classes are declared and announced by people and agents.
