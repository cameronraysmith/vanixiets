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

Hooks use a three-layer architecture reflecting the dendritic flake-parts separation of concerns.
The first layer is hook configuration in `settings.json` (matchers, events, handler metadata), managed by `modules/home/ai/claude-code/hooks.nix` which contributes to `programs.claude-code.settings.hooks` and references hook commands by bare name.
The second layer is hook script packaging in `modules/home/tools/hooks/default.nix`, which defines `writeShellApplication` packages for each hook script with explicit `runtimeInputs` for dependencies, adds them to `home.packages` so they are on the global PATH, and resolves beads via `flake.inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.beads`.
The third layer is hook source scripts as `.sh` files in `modules/home/tools/hooks/`, living alongside the nix module that packages them.

This separation places script packaging (what a hook does and its dependencies) in the tools layer and hook configuration (when a hook fires and what it matches) in the AI layer.
Scripts on PATH enables manual debugging (e.g. `echo '{}' | validate-epic-close`) and `writeShellApplication` provides shellcheck validation at build time.
Bare command names in settings.json trade nix-level build-time path linkage for home-manager activation-time PATH guarantee, which is negligible practical risk since both happen before any hook runs.

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

These capture valuable enforcement concepts but need rework for generalized Task dispatch (not supervisor-typed agents).
The adapted hooks should preserve worktree awareness following The-Claude-Protocol's `.worktrees/bd-{BEAD_ID}/` pattern.
Worktree compatibility was validated: absolute symlinks work correctly in worktrees, beads hooks already handle worktrees (the planning repo has worktree-aware pre-commit and post-merge hooks), nix flakes work from worktrees, and sops-nix has no issues.

**enforce-branch-before-edit** (PreToolUse, Edit/Write matcher): Merged with concepts from `block-orchestrator-tools.sh`, this hook prevents file edits on main/master branch.
It allows edits to `.claude/`, `CLAUDE.md`, coordination files, and any path within `.worktrees/`.
A quick-fix escape hatch asks permission for small changes on feature branches when no bead is active.
The hook enforces the existing git preference "check the current branch name first... pause to ask the user whether to create or switch to a matching branch."
Edits within `.worktrees/` paths are always allowed since worktrees are the standard isolation mechanism for bead tasks.
When denying an edit on main/master, the hook's denial message should guide the user toward creating a worktree via `git worktree add .worktrees/bd-{BEAD_ID} -b bd-{BEAD_ID}`.
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
Checks include: (1) if prompt contained `BEAD_ID:`, verify bead status was updated, (2) verify any modified files were committed, (3) verify branch was pushed to remote if remote exists, (4) if working in a `.worktrees/bd-{BEAD_ID}/` directory, verify the worktree has no uncommitted changes and the worktree's branch has been pushed.
This hook does not enforce response verbosity limits (which conflict with detailed subagent returns) or Protocol-specific completion format.
For agent teams, it uses the TaskCompleted hook event.
Source: inspired by `templates/hooks/validate-completion.sh` but rewritten.
Dependencies: `git`, `bd`, `jq`.

## Worktree workflow convention

Each bead task gets a dedicated worktree at `.worktrees/bd-{BEAD_ID}/` created via `git worktree add .worktrees/bd-{BEAD_ID} -b bd-{BEAD_ID}`.
The `.worktrees/` directory should be listed in `.gitignore` to avoid tracking worktree checkouts.

Worktrees provide isolation: each task works in its own checkout without interfering with the main branch or other concurrent tasks.
Beads issues track which worktree is active via the branch name matching the bead ID (e.g., bead `nix-d4o` maps to branch and worktree `bd-nix-d4o`).

On completion: commit all changes, push the branch to remote, and mark the bead `inreview`.
The worktree can be cleaned up after merge via `git worktree remove .worktrees/bd-{BEAD_ID}`.

Agent team teammates each work in their own worktree for their assigned bead, ensuring parallel work streams do not conflict.
The enforce-branch-before-edit hook denies edits on main/master and guides the user toward worktree creation as the standard path for starting work on a bead.
The validate-completion hook verifies worktree state as part of its quality gate: no uncommitted changes in the worktree and the worktree's branch pushed to remote.

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

`modules/home/tools/hooks/default.nix` — Hook script packaging module contributing to `homeManager.tools`.
Defines `writeShellApplication` packages for all 9 hook scripts with explicit `runtimeInputs` for each script's dependencies (jq, bd, gh, git, etc.).
Adds all hook packages to `home.packages` so they are available on the global PATH.
Resolves beads via `flake.inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.beads` following the established pattern from the commands module.

`modules/home/tools/hooks/*.sh` — Hook shell script source files (9 total across all phases), living alongside the nix module:

- `validate-epic-close.sh`
- `log-dispatch-prompt.sh`
- `memory-capture.sh`
- `nudge-claude-md-update.sh`
- `enforce-branch-before-edit.sh`
- `enforce-sequential-dispatch.sh`
- `session-start.sh`
- `clarify-vague-request.sh`
- `validate-completion.sh`

`modules/home/ai/claude-code/hooks.nix` — Hook configuration contributing to `programs.claude-code.settings.hooks`.
Defines all 9 hooks with their event types, matchers, and bare command name references (PATH-resolved at runtime since scripts are on PATH via the tools/hooks module).

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

Phase 1 covers hooks infrastructure using the two-layer architecture.
Create `modules/home/tools/hooks/default.nix` and the hook shell scripts in `modules/home/tools/hooks/` first, packaging each script as a `writeShellApplication` with its dependencies on the global PATH.
Then create `modules/home/ai/claude-code/hooks.nix` with settings-only configuration referencing hooks by bare command name.
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

Note: nix-d4o.6 tracks reworking the adapted hooks to restore worktree support, ensuring enforce-branch-before-edit and validate-completion properly handle the `.worktrees/bd-{BEAD_ID}/` pattern.

## Human-only epic closure convention

Epics represent aggregate work packages that require human judgment before being marked complete.
The convention is that AI agents close individual issues but never close epics directly.

When all children of an epic are closed, the Kanban UI's `compute_epic_status_from_children` function automatically infers the epic status as `inreview`, presenting it for human verification without any agent action.
This removes the need for agents to run `bd epic close-eligible` to close epics and instead positions them as reporters of readiness.

Enforcement operates at three levels.
The `validate-epic-close` hook (PreToolUse, Bash matcher) intercepts any `bd close` command targeting an epic and unconditionally denies it within Claude Code sessions.
Since this hook only runs inside Claude Code, humans closing epics from their terminal are unaffected.
The `agents-md.nix` orchestrator instructions include a directive that agents must never close epics directly.
All beads skill files (`issues-beads`, `issues-beads-prime`, `issues-beads-checkpoint`, `issues-beads-evolve`, `issues-beads-audit`) replace any `bd epic close-eligible` usage with dry-run checks and guidance to report readiness to the user.

The resulting workflow is: agents close individual issues, the Kanban UI automatically sets the parent epic to "In Review" when all children are closed, and a human reviews and closes the epic.

## Reference documentation

- Hooks documentation: `./claude-code-hooks.md` (not committed)
- Agent teams documentation: `./claude-code-agent-teams.md` (not committed)
- The-Claude-Protocol source: `~/projects/planning-workspace/The-Claude-Protocol/`
- Beads-Kanban-UI source: `~/projects/planning-workspace/Beads-Kanban-UI/` (separate derivation in progress at `pkgs/by-name/beads-kanban-ui/`)
- Existing beads skills: `~/.claude/skills/issues-beads-*/SKILL.md` (8 skills)
- Git preferences: `~/.claude/skills/preferences-git-version-control/SKILL.md`
