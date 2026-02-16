---
name: meta-agent-teams
description: Agent team orchestration conventions for persistent multi-agent coordination via shared task lists and messaging.
---
# Agent teams orchestration

Agent teams are a second orchestration mode alongside DAG dispatch of subagent Tasks.
Use this reference when spawning or coordinating persistent agent teams.

## Teammate isolation conventions

Teammates do not inherit the orchestrator's conversation context, so spawn prompts must be self-contained with all necessary context, file paths, and objectives.
Teammates coordinate via shared task list (TaskCreate/TaskUpdate/TaskList) and messaging (SendMessage), not by returning results to the orchestrator.
The orchestrator remains responsible for teammate lifecycle management.

## Beads-to-task-list mirroring

Beads-to-task-list mirroring aligns ephemeral team coordination with persistent issue tracking.
When an agent team works on an epic lineage or cross-cutting collection of beads issues, mirror the relevant issues and their dependencies into the team's shared task list via TaskCreate with appropriate blockedBy/blocks relationships.
The team's shared task list is the ephemeral coordination substrate; beads issues remain the persistent source of truth.
Keep both in sync: when a team task completes, update the corresponding bead.

## Teammate lifecycle: orient, work, checkpoint, shutdown, replace

Teammate lifecycle management integrates with the orient/checkpoint pattern.
Every new teammate should be instructed to execute `/session-orient` at session start to establish full context on the issue graph and current state.
For repos without the full workflow (no `session-*` skills installed), fall back to `/issues-beads-orient`.
Teammates should monitor context usage and, when approaching 50% capacity (approximately 100k tokens), execute `/session-checkpoint` to capture learnings, update issue status, and produce a handoff narrative.
For repos without the full workflow, fall back to `/issues-beads-checkpoint`.
After checkpoint, the teammate requests shutdown; the orchestrator spawns a replacement oriented with `/session-orient` (or `/issues-beads-orient` in beads-only repos) to continue the work.
This creates a clean lifecycle: orient, work, checkpoint, shutdown, replace.

## Subagent identity in team context

The "You are a subagent Task" identity marker and return-with-questions pattern apply to DAG-dispatched tasks.
For agent team teammates, spawn prompts should include equivalent identity context plus instructions about the orient/checkpoint lifecycle.
