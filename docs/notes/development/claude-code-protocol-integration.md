# Claude Code protocol integration plan

## Overview

This plan integrates enforcement hooks, custom agents, agent teams orchestration, and beads workflow automation into the vanixiets nix home-manager configuration.
The design extracts valuable patterns from The-Claude-Protocol (`~/projects/planning-workspace/The-Claude-Protocol/`) while preserving and extending the existing orchestrator mode, Session Protocol, and 8-skill beads workflow already in place.
No component of the existing CLAUDE.md preferences, beads skills, or git workflow should be disturbed; all changes are additive or extend existing patterns.

## Architecture context

Claude Code configuration in vanixiets follows a deferred module composition pattern with flake-parts and import-tree for automatic module discovery.
All user-level Claude Code configuration is declaratively generated from nix and placed via home-manager symlinks.

Key existing modules:

- `modules/home/ai/claude-code/default.nix` — generates `~/.claude/settings.json` via `programs.claude-code.settings`
- `modules/home/ai/claude-code/mcp-servers.nix` — MCP server configuration
- `modules/home/ai/claude-code/wrappers.nix` — alternative LLM backend wrappers
- `modules/home/ai/claude-code/ccstatusline-settings.nix` — status line configuration
- `modules/home/ai/claude-code/agents/` — custom agent definitions (currently only `git/git-committer.md`)
- `modules/home/ai/skills/default.nix` — skill discovery and registration
- `modules/home/ai/skills/src/core/` — shared skills, `src/claude/` — Claude-specific skills
- `modules/home/tools/agents-md.nix` — generates `~/.claude/CLAUDE.md` with orchestrator instructions
- `modules/home/modules/_agents-md.nix` — option module defining `programs.agents-md` interface

The hooks documentation is in `./claude-code-hooks.md` (not committed).
The agent teams documentation is in `./claude-code-agent-teams.md` (not committed).
The-Claude-Protocol source is at `~/projects/planning-workspace/The-Claude-Protocol/`.

## Hook system design

Hooks use a two-tier architecture: hook configuration in `settings.json` (matchers, events, handler metadata) pointing to hook scripts in `~/.claude/hooks/` (executable shell scripts).
All hooks are placed at user level so they apply globally but include runtime guards (checking for `.beads/` existence, git state, etc.) to degrade gracefully in projects without beads.

### Hooks to adopt directly

These require only mechanical changes: nix store paths for dependencies, removing Protocol-specific type checks.

**validate-epic-close** (PreToolUse, Bash matcher): Prevents `bd close` on epics with open children or without merged PRs.
Supports `--force` escape hatch.
Source: `templates/hooks/validate-epic-close.sh`.
Dependencies: `bd`, `gh`, `git`, `jq`.

**log-dispatch-prompt** (PostToolUse, Task matcher, async): Auto-logs Task dispatch prompts as bead comments with `DISPATCH_PROMPT` prefix.
Adaptation: remove the check for "supervisor" in subagent_type; log all Task dispatches that contain a `BEAD_ID:` marker.
Source: `templates/hooks/log-dispatch-prompt.sh`.
Dependencies: `bd`, `jq`.

**memory-capture** (PostToolUse, Bash matcher, async): Captures `LEARNED:` markers from `bd comment` commands to `.beads/memory/knowledge.jsonl`.
Includes auto-tagging and rotation (archive after 1000 lines).
Source: `templates/hooks/memory-capture.sh`.
Dependencies: `jq`, standard coreutils.

**nudge-claude-md-update** (PreCompact): Reminds to update "Current State" section in CLAUDE.md before context compaction.
Source: `templates/hooks/nudge-claude-md-update.sh`.
Dependencies: `git`, `sed`.

### Hooks to adapt

These capture valuable enforcement concepts but need rework for the branch-based workflow (not worktree-based) and generalized Task dispatch (not supervisor-typed agents).

**enforce-branch-before-edit** (PreToolUse, Edit/Write matcher): Merged with concepts from `block-orchestrator-tools.sh`, this hook prevents file edits on main/master branch.
It allows edits to `.claude/`, `CLAUDE.md`, and coordination files.
A quick-fix escape hatch asks permission for small changes on feature branches when no bead is active.
The hook enforces the existing git preference "check the current branch name first... pause to ask the user whether to create or switch to a matching branch."
If worktrees are adopted (`.worktrees/` directory pattern from The-Claude-Protocol), edits within worktree paths are allowed.
Source: adapted from `templates/hooks/enforce-branch-before-edit.sh` and `templates/hooks/block-orchestrator-tools.sh`.
Dependencies: `git`, `jq`.

**enforce-sequential-dispatch** (PreToolUse, Task matcher): Prevents dispatching work with unresolved blockers in the beads dependency graph.
Triggers on any Task dispatch whose prompt contains a `BEAD_ID:` marker (not just supervisor-typed agents).
Checks include: (1) bead not already closed, (2) no unresolved blockers for epic children, (3) design doc exists if specified on epic.
Source: adapted from `templates/hooks/enforce-sequential-dispatch.sh`.
Dependencies: `bd`, `jq`.

**session-start** (SessionStart): Lightweight automatic grounding before the user invokes `/issues-beads-orient`.
Shows: dirty repo warning, open PR reminder (via `gh`), recent knowledge base entries from `.beads/memory/knowledge.jsonl`.
This hook does not duplicate orient's full task status analysis.
Source: adapted from `templates/hooks/session-start.sh`.
Dependencies: `git`, `gh`, `jq`, `bd`.

**clarify-vague-request** (UserPromptSubmit): Aligns with Session Protocol rather than character-count thresholds.
Injects a `<system-reminder>` reinforcing the Session Protocol's 4-point assessment when prompts are very short (<50 chars).
For moderate prompts (<200 chars), it offers a soft suggestion to consider clarification.
The-Claude-Protocol's epic reminder is removed since it is handled by the existing beads workflow.
Source: adapted from `templates/hooks/clarify-vague-request.sh`.
Dependencies: `jq`.

**validate-completion** (TaskCompleted for teams, SubagentStop for individual tasks): Ground-up rewrite as a quality gate for subagent/teammate completion.
Checks include: (1) if prompt contained `BEAD_ID:`, verify bead status was updated, (2) verify any modified files were committed, (3) verify branch was pushed to remote if remote exists.
This hook does not enforce response verbosity limits (which conflict with detailed subagent returns) or Protocol-specific completion format.
For agent teams, it uses the TaskCompleted hook event.
Source: inspired by `templates/hooks/validate-completion.sh` but rewritten.
Dependencies: `git`, `bd`, `jq`.

## Custom agents

### Remove

**git-committer** (`agents/git/git-committer.md`): This agent is redundant with the extensive git preferences in `~/.claude/CLAUDE.md` (referenced from `preferences-git-version-control/SKILL.md`).
Delete the `agents/git/` directory entirely.

### Add

**code-reviewer** (`agents/code-reviewer.md`): An adversarial code review agent adapted from The-Claude-Protocol's Rex agent, stripped of persona ("Rex"), using a role-oriented name.
It provides DEMO re-execution before approving, spec compliance verification, and quality checks.
Tools: Read, Glob, Grep, Bash.
Model: haiku (cost-efficient for review passes).
This agent pairs with the `validate-completion` hook as complementary quality gates: the hook enforces mechanical invariants while the reviewer enforces semantic quality.

**merge-resolver** (`agents/merge-resolver.md`): A git merge conflict resolution agent adapted from The-Claude-Protocol's Mira agent, stripped of persona.
It provides intent analysis from both branches, conflict resolution preserving both sides' goals, and verification that the resolution compiles and passes tests.
Tools: Read, Write, Edit, Bash, Glob, Grep.
Model: sonnet (needs reasoning for conflict intent analysis).

Both agents should include the standard subagent identity marker ("You are a subagent Task. Return with questions rather than interpreting ambiguity.") and reference the beads workflow for context.

## Agent teams integration

### Settings configuration

Enable agent teams in `modules/home/ai/claude-code/default.nix`:

```nix
programs.claude-code.settings = {
  env = {
    CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS = "1";
  };
  teammateMode = "auto";
  # ... existing settings
};
```

### Orchestrator instructions update

The `settings.body` in `modules/home/tools/agents-md.nix` needs to expand the orchestrator mode section to acknowledge two orchestration modes with selection criteria.

The current text establishes only DAG dispatch:

```
You should usually operate in what we refer to as "orchestrator mode" where you
think deeply to design workflow DAGs of subagent Tasks...
```

The adapted version retains this as the default and adds agent teams as a second mode.

Orchestration mode selection criteria determine which approach to use.
Sequential dependencies, focused research, and tight orchestrator control favor DAG dispatch via subagent Tasks.
Parallel independent work streams, adversarial review, multi-perspective analysis, and long-running collaborative phases favor agent teams.
Hybrid approaches are valid: DAG dispatch for initial research, then a team for the implementation and review phase.

Agent teams conventions follow from the nature of teammate isolation.
Teammates do not inherit the orchestrator's conversation context, so spawn prompts must be self-contained.
Teammates coordinate via shared task list and messaging, not by returning results.
The orchestrator remains responsible for teammate lifecycle management.

Beads-to-task-list mirroring is the convention for aligning ephemeral team coordination with persistent issue tracking.
When an agent team is working on an epic lineage or epic cross-cutting lineage of beads issues, the orchestrator should mirror the relevant collection of issues and their dependencies into the team's shared task list (via TaskCreate with appropriate blockedBy/blocks relationships).
The team's shared task list becomes the ephemeral coordination substrate while the beads issues remain the persistent source of truth.
Both should be kept in sync: when a team task completes, the corresponding bead should be updated, and vice versa.

Teammate lifecycle management integrates with the orient/checkpoint pattern.
Every new agent team member instantiated by the orchestrator should be instructed to execute the `/issues-beads-orient` skill at the beginning of its session to establish full context on the issue graph and current state.
Teammates should monitor their context usage and, when approaching 50% context capacity (approximately 100k tokens), work toward executing `/issues-beads-checkpoint` to capture learnings, update issue status, and produce a handoff narrative.
After checkpoint, the teammate should request shutdown, and the orchestrator should spawn a replacement teammate oriented with `/issues-beads-orient` to continue the work.
This creates a clean lifecycle: orient, work, checkpoint, shutdown, then a new teammate with orient.

The existing "You are a subagent Task" identity marker and return-with-questions pattern remain unchanged for DAG-dispatched tasks.
For agent team teammates, the spawn prompt should include equivalent identity context plus instructions about the orient/checkpoint lifecycle.

## Module changes summary

### New files

`modules/home/ai/claude-code/hooks.nix` — Hook configuration contributing to `programs.claude-code.settings.hooks`.
Defines all 9 hooks with their event types, matchers, and references to script paths at `~/.claude/hooks/`.

`modules/home/ai/claude-code/hooks/` — Directory containing 9 adapted hook shell scripts.
Each script should have its tool dependencies (jq, bd, gh, git, etc.) available via PATH.
The nix module should ensure these are wrapped or that the PATH is set correctly in the hook execution environment.
Scripts are symlinked to `~/.claude/hooks/` via `home.file`.

Hook scripts (9 files):

- `validate-epic-close.sh`
- `log-dispatch-prompt.sh`
- `memory-capture.sh`
- `nudge-claude-md-update.sh`
- `enforce-branch-before-edit.sh`
- `enforce-sequential-dispatch.sh`
- `session-start.sh`
- `clarify-vague-request.sh`
- `validate-completion.sh`

`modules/home/ai/claude-code/agents/code-reviewer.md` — Code review agent definition.

`modules/home/ai/claude-code/agents/merge-resolver.md` — Merge conflict resolution agent definition.

### Modified files

`modules/home/ai/claude-code/default.nix` — Remove commented-out hooks section (lines ~94-111).
Add `env.CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS = "1"` and `teammateMode = "auto"` to settings.
Adjust the agents directory to remove git-committer and include new agents.

`modules/home/tools/agents-md.nix` — Expand orchestrator mode section in `settings.body` with agent teams selection criteria, beads-to-task-list mirroring convention, and teammate orient/checkpoint lifecycle.

### Deleted files

`modules/home/ai/claude-code/agents/git/git-committer.md` — Redundant with git preferences.

## Implementation phasing

Phase 1 covers hooks infrastructure.
Create `hooks.nix` and the `hooks/` directory with all 9 scripts.
Start with the 4 "adopt directly" hooks, then the 5 adapted hooks.
Test each hook individually by triggering its event.

Phase 2 covers custom agents.
Remove git-committer, add code-reviewer and merge-resolver.
Test by dispatching them as subagent Tasks.

Phase 3 covers the agents-md.nix update.
Expand orchestrator instructions with agent teams support, beads mirroring, and orient/checkpoint lifecycle.
This is the most sensitive change since it affects all sessions globally.

Phase 4 covers integration testing.
Test the full workflow: create a beads epic with children, start an agent team, verify hooks fire correctly, verify orient/checkpoint lifecycle works, verify beads-to-task-list mirroring.

## Reference documentation

- Hooks documentation: `./claude-code-hooks.md` (not committed)
- Agent teams documentation: `./claude-code-agent-teams.md` (not committed)
- The-Claude-Protocol source: `~/projects/planning-workspace/The-Claude-Protocol/`
- Beads-Kanban-UI source: `~/projects/planning-workspace/Beads-Kanban-UI/` (separate derivation in progress at `pkgs/by-name/beads-kanban-ui/`)
- Existing beads skills: `~/.claude/skills/issues-beads-*/SKILL.md` (8 skills)
- Git preferences: `~/.claude/skills/preferences-git-version-control/SKILL.md`
