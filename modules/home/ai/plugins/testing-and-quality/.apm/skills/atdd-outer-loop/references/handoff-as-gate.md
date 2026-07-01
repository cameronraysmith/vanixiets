# Handoff as gate and verification independence

The outer loop coordinates its phases through durable handoffs rather than conversational continuity, and it enforces that verification is done by an agent other than the one whose work is being verified.
These two mechanisms are what let the loop survive long runs, context compaction, and agent swaps without silently eroding its own discipline.

## The handoff is the gate

Each phase ends by writing a handoff that asserts its exit criteria with evidence, and the next phase begins by reading that handoff rather than by trusting a spoken claim that the prior phase finished.
A handoff is durable: it records the checkpoint, the artifacts produced, an explicit assertion for each exit criterion with the evidence that criterion was met, and a note of what was deliberately not done and left for the next phase.
Coordination that lives only in a chat transcript is lost to a compaction; coordination written to a handoff survives it, which is why the handoff is the unit of phase-to-phase state rather than the conversation.
The entry gate reads the prior handoff and refuses to proceed if a criterion is unmet, so completion is a property asserted against evidence, not a status a previous agent announced.

## Verification independence

The agent that verifies a unit of work must have an `agent_id` different from the agent that implemented it, and different again from the agent that refined it.
An author cannot independently confirm their own output: they verify against the intent they held while writing, not against the specification as an outside reader meets it, and the same blind spot that produced a defect will pass over it on review.
This applies across the loop's roles — the spec author is not the leakage auditor, the implementer is not the verifier, the refiner is not the final verifier — and the orchestrator checks the `agent_id` distinctness rather than assuming it.
The independent leakage audit of P3 (`references/spec-leakage-and-guardian.md`) is the same principle applied one phase earlier.

## Fresh per phase resists role erosion

A single agent kept alive across a long-running feature compacts its context as the work proceeds, and compaction silently erodes role identity: the agent loses the constraints of its role, invents constraints that were never given, and skips expensive-but-required steps it no longer remembers were required.
Running each phase as a fresh agent invocation reloads the role's instructions clean, so the discipline is re-established at every phase boundary rather than decaying across one long context.
The fresh agents exist for correctness of role, not for parallelism within a single feature; parallelism belongs across features.
Dispatch of the fresh per-phase agents, and of the independent verifier, defers to `subagent-driven-development`.

## Relationship to the loop

Handoff-as-gate is how P1 through P8 in `references/outer-loop-workflow.md` connect: every phase's gate is asserted in its handoff, and every phase's entry re-checks the prior handoff.
Verification independence is the constraint P8 enforces before it accepts the work, and it is the reason the leakage audit and the code review are dispatched to agents distinct from the authors they review.
