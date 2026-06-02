## 1. Router skill (agentic-workflow-routing)

- [x] 1.1 Create `modules/home/ai/skills/src/claude/agentic-planning-development-workflow/SKILL.md` as a lean index plus Contents table under roughly 350 lines, with frontmatter `name` matching the directory and a description ending in the router "Load when" trigger from design D1 (keywords avoid the session-advisor, issues-beads, and linear-cli vocabularies)
- [x] 1.2 Create `references/execution-modes.md` covering the AFK, HIL, and Manual entry criteria and the per-mode authoritative ledger (HIL to tasks.md, AFK to plan checkboxes, Manual to the beads /session-orient to /session-checkpoint loop), and the re-queue-defaults-to-original-mode rule from D11
- [x] 1.3 Create `references/board-and-gates.md` covering the seven-state Linear-canonical board, the four forward transitions (one firing condition each), the In-Review roborev-then-documenter sub-gates, the shared re-queue, the bounded-retries termination policy, the brainstorm-exists-proposal-pending Backlog window, and the router walkthrough required by the design tasks-foreshadow
- [x] 1.4 Create `references/hil-isolation.md` covering the jj diamond development join as the worktree substitute and the CLAUDE_JJ_WORKSPACE_ISOLATION hatch, recording the reconciliation as an apply-gate open point and not baking in `git worktree add`
- [x] 1.5 Create `references/delegation.md` covering roborev and documenter as mode-agnostic human-steered abstract gates linking to the bridge apply/verify and verify/retrospective stages, the future-automation extension point (later code-review/doc-gen hooks compose into the existing roborev and documenter gates without introducing a fourth agent, per design D5), the AFK handoff act, and the composition-by-delegation contract (never re-implement orient/plan/review/checkpoint; Manual pass-through to /session-orient; reference session-advisor without duplicating it)
- [x] 1.6 Confirm the router SKILL.md is one level deep in its references and asserts that the router does not read beads graph metrics or the stigmergic signal table

## 2. Project-management hub skill (project-management-hub)

- [x] 2.1 Create `modules/home/ai/skills/src/core/project-management/SKILL.md` as a lean index plus Contents table grouped by reference-file prefix under roughly 350 lines, with frontmatter `name` matching the directory and the PM-hub "Load when" trigger from design D1
- [x] 2.2 Create `references/linear-overview.md` covering the Initiative greater than Project greater than Milestone greater than Issue ontology with Cycles as an orthogonal overlay
- [x] 2.3 Create `references/linear-workspace-safety-gate.md` encoding the hardest constraint: the `linear auth whoami` gate keyed on confirmed credentials and an explicit `--workspace`, never on LINEAR_WORKSPACE, never running mutating `linear auth`
- [x] 2.4 Create `references/linear-conventions.md` covering the issue-body TL;DR/Deliverables/Acceptance convention, the SYNC and NOSYNC markers, and issue sizing
- [x] 2.5 Create `references/github-overview.md` covering the PR, buildbot, and Mergify surface, framing the PR as one realization of the terminal artifact (the archived OpenSpec change)
- [x] 2.6 Create `references/beads-overview.md` documenting beads as the optional local drill-down sublayer and the Manual-mode task ledger, routing to issues-beads without duplicating it
- [x] 2.7 Create `references/method-overview.md` (committed, not optional) synthesizing the Linear Method plus CCPM principles with no copied text, covering the ontology, Cycles-as-overlay, sizing and estimation, triage versus backlog versus deferral, and the SYNC and NOSYNC markers
- [x] 2.8 Confirm the four sub-areas are flat one-level filename prefixes (linear, github, beads, method) presented via a prefix-grouped Contents table, with no two-level nesting

## 3. Sync overlay skill (openspec-linear-sync)

- [x] 3.1 Create `modules/home/ai/skills/src/core/openspec-linear-sync/SKILL.md` as a lean index plus Contents table under roughly 350 lines, with frontmatter `name` matching the directory and the sync-overlay "Load when" trigger from design D1, recommending against the disabled Linear MCP
- [x] 3.2 Create `references/lifecycle.md` covering the four forward transitions plus the re-queue and the two terminal exits, the gates, the invariants (never Done before archive; status/validate/sync/edit never move to Done; comments at most two sentences), the state-resolved-by-name rule, the archive ordering readiness then sync deltas then archive then mirror then Done, and the graceful-degradation branch (stay In Progress until Done) for teams lacking an In Review state
- [x] 3.3 Create `references/linear-cli-mapping.md` covering the per-phase verb mapping, the document UPSERT recipe (`document list --json` match by `OpenSpec: <capability>`, then `update` else `create --project`), the narrow `linear api` fallback, and the end-to-end HIL worked example (Backlog to Todo to In Progress to In Review to Done with literal linear-cli commands at each transition: the `linear auth whoami` gate, the guarded strictly-behind transition, the at-most-two-sentence comment, and the archive-time document UPSERT)
- [x] 3.4 Create `references/config-and-frontmatter.md` covering the openspec/linear.yaml sync ledger (last_synced_state, last_synced_at, the review-round counter defaulting to a small max with a configurability note, the attempt log) and the proposal.md linear_story_* frontmatter, the two-location write-before-read binding, and the Manual-mode beads-field binding
- [x] 3.5 Confirm the overlay carries one-question setup with an explicit no-label option, never-auto-select, archive-time-only mirroring, best-effort non-blocking writes, and never copying design.md or tasks.md to Linear

## 4. Trigger non-overlap and cross-reference assertions

- [x] 4.1 As a self-imposed, human-adjudicated skill-quality gate with no machine enforcement (the bridge verify check 6 is the `docs/superpowers/specs/*.md` output-routing leak detector, not a trigger-collision detector), compare the three SKILL.md "Load when" triggers against session-advisor (routing), issues-beads (issue tracking), and the bundled linear-cli skill (Linear verbs) per design D1, and record the trigger-comparison verdict explicitly so a reviewer sees the comparison was performed

  Trigger-comparison verdict (recorded): the three "Load when" triggers are mutually non-overlapping and do not collide with the three reference skills.
  - router: "selecting an execution mode for a change, driving the agentic planning-and-development board, or routing a change between board states" — execution-mode and board-state vocabulary. Avoids session-advisor's beads-graph-metric routing vocabulary, issues-beads' issue-tracking verbs, and linear-cli's raw Linear verbs.
  - project-management hub: "reasoning about project/issue structure, Linear conventions, or how OpenSpec, beads, and GitHub relate as PM layers" — PM-model/conventions vocabulary. It documents structure rather than mutating a tracker, so it does not collide with linear-cli (verbs) or issues-beads (bd CLI).
  - openspec-linear-sync: "binding a Linear story to an OpenSpec change, mirroring lifecycle phase to Linear state, or running the archive-time document upsert" — link-and-sync-policy vocabulary. Distinct from linear-cli (it composes linear-cli rather than re-stating verbs) and from the router (no execution-mode/board-routing keywords).
  - session-advisor (routing) reads beads graph metrics and the stigmergic signal table; none of the three triggers use that vocabulary, and the router explicitly defers graph-metric routing to session-advisor. issues-beads (issue tracking) and the bundled linear-cli skill (Linear verbs) are referenced by name from the hub and overlay rather than re-triggered. The build review independently confirmed non-overlap. The session-advisor↔router routing overlap is a recorded deferred follow-up, not a trigger collision in scope here.
- [x] 4.2 Verify each skill references existing skills (session-orient, session-advisor, issues-beads, linear-cli, the opsx and superpowers bridge skills) by delegation rather than duplicating their content

## 5. Stale-comment fix

- [x] 5.1 Update the stale comment at `modules/home/users/crs58/default.nix` from `# Inject linear-cli's bundled skills (38 linear-*/SKILL.md subdirs)` to describe a single linear-cli/ skill directory with sixteen reference subfiles, per design.md Tasks-foreshadow, stale-comment bullet

## 6. Nix verification

- [x] 6.1 Build or evaluate the target host home-manager skills derivation and confirm the three new skills resolve and symlink-wire under the claude/factory/hermes/agents skills directories (router only under Claude Code via src/claude; hub and sync under all agents via src/core)
- [x] 6.2 Confirm auto-discovery via `readSkillsFrom` requires no manual nix registration and that the stale-comment fix evaluates cleanly
- [x] 6.3 Run the cross-reference-not-duplicate check and the workspace-safety-gate presence check against the built skills tree

## 7. Acceptance criteria (per design Migration Plan)

- [x] 7.1 The three skills resolve in the activation package; the router delegates without re-implementing and is a pass-through to /session-orient in Manual mode
- [x] 7.2 The sync overlay's workspace safety gate refuses any mutation before `linear auth whoami` confirmation
- [x] 7.3 Each SKILL.md is in lean-index plus Contents-table form under roughly 350 lines with detail in references leaves
- [x] 7.4 The dogfood lifecycle reaches archive without authoring linear_story_* frontmatter, since this change is not synced to a real Linear story
