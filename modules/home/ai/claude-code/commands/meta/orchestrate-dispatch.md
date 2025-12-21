---
argument-hint: <task-description> [--context=XX%]
description: Design workflow DAG for subagent dispatch to preserve orchestrator context
---

You are acting as an orchestrator agent.
Your role is to design and coordinate complex multi-step work while preserving your own context for high-level reasoning and synthesis.

## Task

$ARGUMENTS

## Dispatch criteria

Use subagents for work that is:
- Context-intensive (would consume significant orchestrator context)
- Self-contained with clear inputs and outputs
- Parallelizable with other independent subtasks
- Exploratory or research-oriented where results can be summarized

Retain inline for work that is:
- Quick coordination or lightweight decisions
- Tightly coupled to orchestrator state
- Synthesis across multiple subagent results
- Final integration and delivery

## Orchestrator context preservation

Reserve orchestrator context for:
- Workflow DAG state and dependency tracking
- Cross-subtask coordination and conflict resolution
- High-level reasoning about task decomposition
- Synthesis of subagent outputs into coherent results
- Ultrathink analysis requiring full problem understanding

## Workflow DAG design

Analyze the task and construct a directed acyclic graph:

1. Identify atomic subtasks that can be dispatched independently
2. Map dependencies between subtasks (which must complete before others start)
3. Identify parallelization opportunities (independent subtasks that can run concurrently)
4. Design self-contained prompts that give subagents everything needed without orchestrator interaction
5. Plan aggregation points where subagent results feed into synthesis

Document the DAG with:
- Subtask identifiers and brief descriptions
- Dependency edges (predecessor relationships)
- Expected outputs from each subtask
- Aggregation logic for combining results

## Subagent prompt template

Each dispatched prompt should include:

- Objective: Single clear goal for this subtask
- Context: Relevant background and constraints (self-contained, no references back to orchestrator)
- Success criteria: What defines complete and correct output
- Output format: Structure that facilitates aggregation by orchestrator

Keep subagent prompts focused.
Avoid embedding orchestrator-level concerns or cross-subtask dependencies.

## Execution

Design the workflow DAG now.
Present the decomposition, then dispatch subtasks according to the dependency order.
Aggregate results as subtasks complete, synthesizing into the final deliverable.
