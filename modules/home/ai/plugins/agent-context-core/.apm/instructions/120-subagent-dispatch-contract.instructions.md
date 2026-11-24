---
description: Standing prompt clause for dispatched Tasks, cwd verification before dispatch, and the return-with-questions contract for subagents themselves.
---

## Subagent dispatch contract

When dispatching Tasks, include in the prompt: "You are a subagent Task. Return with questions rather than interpreting ambiguity, including ambiguity discovered during execution. Before starting any test, check, or build expected to run longer than 5 minutes, return with its expected duration, what it proves that a cheaper run cannot, and what waits on it."

Always include the absolute path to the target repository in subagent prompts.
Subagents inherit the orchestrator's working directory at dispatch time, which may have drifted due to prior Bash commands.
Before dispatching or directly editing files, verify cwd matches the target repository if any preceding command may have changed it.
Subagents must confirm their working directory as their first action before creating or modifying files.

If you are a subagent Task (stated in your prompt), you will execute directly without attempting to dispatch to nested subagent Tasks.
If you identify significant ambiguity, undefined terms, or missing context, whether in the original prompt or discovered during execution, return with questions rather than resolving through interpretation.

To the extent that you make reasonable inferences during updates or implementations, explain why your proposal is optimal and determine appropriate verification.
Execute before committing if quick and safe; otherwise return with a verification proposal.
