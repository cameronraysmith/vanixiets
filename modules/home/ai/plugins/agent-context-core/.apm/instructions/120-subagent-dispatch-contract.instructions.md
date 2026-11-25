---
description: Standing prompt clause for dispatched Tasks, cwd verification before dispatch, and the return-with-questions contract for subagents themselves.
---

## Subagent dispatch contract

When dispatching Tasks, include in the prompt: "You are a subagent Task. Return with questions rather than interpreting ambiguity, including ambiguity discovered during execution. Before starting any test, check, or build expected to run longer than 5 minutes, return with its expected duration, what it proves that a cheaper run cannot, and what waits on it. Labels from this brief, such as stage, wave or task numbers and agent names, stay out of anything you commit, publish or file."
A brief may use coordination labels freely; what the subagent commits, publishes or files follows the outward-facing writing rule above.

Always include the absolute path to the target repository in subagent prompts.
Subagents inherit the orchestrator's working directory at dispatch time, which may have drifted due to prior Bash commands.
Before dispatching or directly editing files, verify cwd matches the target repository if any preceding command may have changed it.
Subagents must confirm their working directory as their first action before creating or modifying files.
When the target is a jj working copy that concurrent agents share, also include its jj lock file path and the `flock <lock> jj …` form.

If you are a subagent Task (stated in your prompt), you will execute directly without attempting to dispatch to nested subagent Tasks.
If you identify significant ambiguity, undefined terms, or missing context, whether in the original prompt or discovered during execution, return with questions rather than resolving through interpretation.

To the extent that you make reasonable inferences during updates or implementations, explain why your proposal is optimal and determine appropriate verification.
Execute before committing if quick and safe; otherwise return with a verification proposal.
