# Agentic planning, development, and management skills — implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) to implement this plan task-by-task, or take the documented manual-fallback opt-in path described in the Apply execution note below. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build three composing-by-delegation agent skills (a Claude-Code-only state-machine router, an agent-general project-management hub, and an agent-general linear-cli-driven Linear-to-OpenSpec sync overlay) realizing design.md D1 through D11.

**Architecture:** Three skill directories drop into the nix-discovery skills tree (router under `src/claude/`, hub and sync overlay under `src/core/`), auto-discovered by `readSkillsFrom` with no manual registration; each SKILL.md is a lean index plus Contents table under roughly 350 lines with operational detail in flat one-level references leaves; the only modified file is a stale comment in crs58's home module.

**Tech Stack:** Markdown skill authoring (agentskills spec), nix home-manager skills derivation, linear-cli, OpenSpec superpowers-bridge schema, jj diamond development join.

**Apply-gate open point:** The HIL apply-phase isolation mechanism (jj diamond development join versus the CLAUDE_JJ_WORKSPACE_ISOLATION jj-workspace hatch) is NOT decided here; it is confirmed at the apply gate per design Risks and Open Questions. No step below issues `git worktree add`; commit steps below describe the unit of work and the apply executor substitutes the agreed jj routing at the apply gate.

**Apply execution note:** The superpowers-bridge apply node hard-requires superpowers:using-git-worktrees, subagent-driven-development, and finishing-a-development-branch (STOP if any is missing), transitively enforces TDD, and does not support superpowers:executing-plans. This change takes the schema's documented manual-fallback opt-in path: orchestrator-routed commits onto the jj diamond development-join chain, with NO `git worktree add` and NO autonomous PR. The human operator (Cameron) opts into this manual fallback as an explicit decision, so the apply STOP precondition is satisfied by recorded human choice rather than by a hook-blocked worktree op; this records the resolution and does not re-open the apply-gate jj reconciliation. TDD RED/GREEN is not applicable to markdown and skill deliverables; verification severity shifts to the nix eval/build and `rg` presence checks already specified in the tasks below.

---

## Task 1: Router SKILL.md index (agentic-workflow-routing)

**Files:**
- Create: `modules/home/ai/skills/src/claude/agentic-planning-development-workflow/SKILL.md`

- [ ] **Step 1: Write the SKILL.md frontmatter and lean index**

Frontmatter `name: agentic-planning-development-workflow` (matching the directory). Description is the design D1 router trigger: "State-machine router across a Linear-canonical board with an AFK/HIL/Manual execution-mode fork. Load when selecting an execution mode for a change, driving the agentic planning-and-development board, or routing a change between board states." Body is a lean index plus a Contents table listing the four references files.

- [ ] **Step 2: Verify the file parses and resolves**

Run: `nix eval .#modules.homeManager.ai --apply 'x: "ok"'` (the lightweight eval gate; the full activation build is Task 9).
Expected: prints `"ok"`, confirming the `ai` aggregation attrset evaluates without error so the skills derivation including the new directory is discoverable.

- [ ] **Step 3: Verify length, frontmatter name, and one-level-deep references**

Run: `wc -l modules/home/ai/skills/src/claude/agentic-planning-development-workflow/SKILL.md`, `rg -n '^name: agentic-planning-development-workflow$' modules/home/ai/skills/src/claude/agentic-planning-development-workflow/SKILL.md` (asserting the frontmatter `name` equals the directory basename, load-bearing for `readSkillsFrom` discovery), and `rg -n "references/[^/]+/" modules/home/ai/skills/src/claude/agentic-planning-development-workflow/SKILL.md`
Expected: under ~350 lines; the frontmatter assertion returns one match; the last command returns nothing (no two-level nesting).

- [ ] **Step 4: Commit**

Commit the router SKILL.md index. (Apply executor: route this commit onto the chain per the jj routing agreed at the apply gate; do not run `git worktree add`.)

## Task 2: Router references leaves

**Files:**
- Create: `.../agentic-planning-development-workflow/references/execution-modes.md`
- Create: `.../agentic-planning-development-workflow/references/board-and-gates.md`
- Create: `.../agentic-planning-development-workflow/references/hil-isolation.md`
- Create: `.../agentic-planning-development-workflow/references/delegation.md`

- [ ] **Step 1: Write execution-modes.md**

Cover the AFK/HIL/Manual entry criteria, the per-mode authoritative ledger (HIL to tasks.md, AFK to plan checkboxes, Manual to the beads /session-orient to /session-checkpoint loop), and the re-queue-defaults-to-original-mode rule (D11). Assert that no parallel beads task list is created in HIL or AFK.

- [ ] **Step 2: Write board-and-gates.md**

Cover the seven-state board (Backlog/Todo/In Progress/In Review/Done plus Canceled/Duplicate), the four forward transitions with one firing condition each, the In-Review roborev-then-documenter sub-gates, the shared re-queue, the bounded-retries termination policy, the brainstorm-exists-proposal-pending Backlog window, and the router walkthrough (per design.md Tasks-foreshadow, worked-example bullet).

- [ ] **Step 3: Write hil-isolation.md**

Cover the jj diamond development join as the worktree substitute and the CLAUDE_JJ_WORKSPACE_ISOLATION hatch. State the reconciliation is an apply-gate open point. Do NOT include any `git worktree add` invocation.

- [ ] **Step 4: Write delegation.md**

Cover roborev and documenter as mode-agnostic human-steered abstract gates linking to the bridge apply/verify and verify/retrospective stages, the AFK handoff act, and the composition-by-delegation contract (never re-implement orient/plan/review/checkpoint; Manual pass-through to /session-orient; reference session-advisor without duplicating it).

- [ ] **Step 5: Verify references resolve and stay one level deep**

Run: `fd . modules/home/ai/skills/src/claude/agentic-planning-development-workflow/references -t f` and confirm exactly four files, each a flat leaf.
Expected: execution-modes.md, board-and-gates.md, hil-isolation.md, delegation.md.

- [ ] **Step 6: Verify the router does not re-implement routing state**

Run: `rg -n "beads graph metric|signal table|stigmergic" modules/home/ai/skills/src/claude/agentic-planning-development-workflow/`
Expected: matches only in the negative-assertion context (the router states it does NOT read these), confirming the no-parallel-surface boundary.

- [ ] **Step 7: Commit**

Commit the four router references. (Apply executor: route per the agreed jj routing; no `git worktree add`.)

## Task 3: PM hub SKILL.md index (project-management-hub)

**Files:**
- Create: `modules/home/ai/skills/src/core/project-management/SKILL.md`

- [ ] **Step 1: Write the SKILL.md frontmatter and prefix-grouped index**

Frontmatter `name: project-management`. Description is the design D1 hub trigger: "Human-facing project-management hub for the Linear Method ontology, conventions, and the workspace safety gate. Load when reasoning about project/issue structure, Linear conventions, or how OpenSpec, beads, and GitHub relate as PM layers." Body is a lean index with a Contents table grouped by the four filename prefixes (linear, github, beads, method).

- [ ] **Step 2: Verify the index parses, the frontmatter name matches the directory, and the Contents table groups by prefix**

Run: `wc -l modules/home/ai/skills/src/core/project-management/SKILL.md`, `rg -n '^name: project-management$' modules/home/ai/skills/src/core/project-management/SKILL.md` (asserting the frontmatter `name` equals the directory basename, load-bearing for `readSkillsFrom` discovery), and `rg -n "linear-|github-|beads-|method-" modules/home/ai/skills/src/core/project-management/SKILL.md`
Expected: under ~350 lines; the frontmatter assertion returns one match; the Contents table references the six prefixed leaves.

- [ ] **Step 3: Commit**

Commit the PM hub index. (Apply executor: route per the agreed jj routing; no `git worktree add`.)

## Task 4: PM hub references leaves

**Files:**
- Create: `.../project-management/references/linear-overview.md`
- Create: `.../project-management/references/linear-workspace-safety-gate.md`
- Create: `.../project-management/references/linear-conventions.md`
- Create: `.../project-management/references/github-overview.md`
- Create: `.../project-management/references/beads-overview.md`
- Create: `.../project-management/references/method-overview.md`

- [ ] **Step 1: Write linear-overview.md**

Initiative greater than Project greater than Milestone greater than Issue, with Cycles as an orthogonal scheduling overlay.

- [ ] **Step 2: Write linear-workspace-safety-gate.md**

The hardest constraint: the `linear auth whoami` (optionally `--workspace <slug>`) gate keyed on confirmed credentials; every mutation passes explicit `--workspace` or relies on the confirmed credentials.toml default; never key on LINEAR_WORKSPACE; never run mutating `linear auth` (credentials are nix-managed and immutable in the OS keyring).

- [ ] **Step 3: Write linear-conventions.md**

The issue-body TL;DR/Deliverables/Acceptance convention (status and progress in fields and comments, never the body), the SYNC and NOSYNC section markers, and issue sizing.

- [ ] **Step 4: Write github-overview.md**

The PR, buildbot, and Mergify surface, framing the PR as one realization of the terminal artifact (the archived OpenSpec change).

- [ ] **Step 5: Write beads-overview.md**

beads as the optional local drill-down sublayer and the Manual-mode task ledger; route to the existing issues-beads skill rather than duplicating it.

- [ ] **Step 6: Write method-overview.md**

Committed (not optional). Synthesize Linear Method plus CCPM principles with no copied text: the ontology, Cycles-as-overlay, sizing and estimation, triage versus backlog versus deferral, and the SYNC and NOSYNC markers.

- [ ] **Step 7: Verify references are flat and the safety gate is present**

Run: `fd . modules/home/ai/skills/src/core/project-management/references -t f` (expect six flat leaves) and `rg -n "linear auth whoami" modules/home/ai/skills/src/core/project-management/references/linear-workspace-safety-gate.md` (expect a match).
Expected: six files; the gate text present.

- [ ] **Step 8: Verify no copied upstream text**

Run: `rg -n "LINEAR_WORKSPACE" modules/home/ai/skills/src/core/project-management/references/linear-workspace-safety-gate.md`
Expected: matches appear only in the do-not-key-on-this negative context.

- [ ] **Step 9: Commit**

Commit the six PM hub references. (Apply executor: route per the agreed jj routing; no `git worktree add`.)

## Task 5: Sync overlay SKILL.md index (openspec-linear-sync)

**Files:**
- Create: `modules/home/ai/skills/src/core/openspec-linear-sync/SKILL.md`

- [ ] **Step 1: Write the SKILL.md frontmatter and lean index**

Frontmatter `name: openspec-linear-sync`. Description is the design D1 sync trigger: "linear-cli-driven Linear-to-OpenSpec lifecycle sync. Load when binding a Linear story to an OpenSpec change, mirroring lifecycle phase to Linear state, or running the archive-time document upsert." Body is a lean index plus a Contents table for the three references files; recommend against the disabled Linear MCP.

- [ ] **Step 2: Verify the index parses, the frontmatter name matches the directory, and recommends against MCP**

Run: `wc -l modules/home/ai/skills/src/core/openspec-linear-sync/SKILL.md`, `rg -n '^name: openspec-linear-sync$' modules/home/ai/skills/src/core/openspec-linear-sync/SKILL.md` (asserting the frontmatter `name` equals the directory basename, load-bearing for `readSkillsFrom` discovery), and `rg -n "MCP" modules/home/ai/skills/src/core/openspec-linear-sync/SKILL.md`
Expected: under ~350 lines; the frontmatter assertion returns one match; the MCP-disabled recommendation present.

- [ ] **Step 3: Commit**

Commit the sync overlay index. (Apply executor: route per the agreed jj routing; no `git worktree add`.)

## Task 6: Sync overlay references leaves

**Files:**
- Create: `.../openspec-linear-sync/references/lifecycle.md`
- Create: `.../openspec-linear-sync/references/linear-cli-mapping.md`
- Create: `.../openspec-linear-sync/references/config-and-frontmatter.md`

- [ ] **Step 1: Write lifecycle.md**

The four forward transitions plus the re-queue and two terminal exits; the gates; the invariants (never Done before archive; status/validate/sync/edit never move to Done; comments at most two sentences); the state-resolved-by-name rule (In Progress and In Review share the started type); the archive ordering readiness then sync deltas then archive then mirror then Done; graceful degradation for teams lacking an In Review state.

- [ ] **Step 2: Write linear-cli-mapping.md (including the end-to-end worked example)**

The per-phase verb mapping; the document UPSERT recipe (`linear document list --project <p> --json` match by title `OpenSpec: <capability>`, then `linear document update <id> --title <t> --content-file <f>` else `linear document create --project <p> --title <t> --content-file <f>`); the narrow `linear api` fallback (reparent, structured-id read-back); and one end-to-end HIL worked example tracing Backlog to Todo to In Progress to In Review to Done with literal linear-cli commands at each transition (the `linear auth whoami` gate, the guarded strictly-behind transition, the at-most-two-sentence comment, the archive-time document UPSERT).

- [ ] **Step 3: Write config-and-frontmatter.md**

The openspec/linear.yaml sync ledger (last_synced_state, last_synced_at, the review-round counter defaulting to a small max of 3 with a configurability note, the attempt log); the proposal.md linear_story_* frontmatter; the two-location write-before-read binding (sync writes both at the Backlog to Todo bind; apply reads frontmatter); the Manual-mode beads-field binding. Encode the one-question setup with an explicit no-label option, never auto-selecting a team/project/label, archive-time-only mirroring, best-effort non-blocking writes after setup, and the never-copy-design.md-or-tasks.md-to-Linear rule (realizing tasks.md 3.5 and the openspec-linear-sync three-scenario requirement, per design D7).

- [ ] **Step 4: Verify the worked example carries literal commands**

Run: `rg -n "linear auth whoami|document list --project|document update|document create" modules/home/ai/skills/src/core/openspec-linear-sync/references/linear-cli-mapping.md`
Expected: each command literal present in the worked example.

- [ ] **Step 5: Verify the one-question setup and best-effort properties are encoded**

Run: `rg -ni "one[- ]question|no[- ]label|never auto[- ]select|archive[- ]time|best[- ]effort|non[- ]blocking|never cop(y|ies)" modules/home/ai/skills/src/core/openspec-linear-sync/references/config-and-frontmatter.md modules/home/ai/skills/src/core/openspec-linear-sync/references/lifecycle.md`
Expected: the one-question-setup, explicit-no-label, never-auto-select, archive-time-only-mirroring, best-effort-non-blocking, and never-copy-design.md/tasks.md elements are each present (realizing tasks.md 3.5).

- [ ] **Step 6: Verify references are flat (three leaves)**

Run: `fd . modules/home/ai/skills/src/core/openspec-linear-sync/references -t f`
Expected: lifecycle.md, linear-cli-mapping.md, config-and-frontmatter.md.

- [ ] **Step 7: Commit**

Commit the three sync overlay references. (Apply executor: route per the agreed jj routing; no `git worktree add`.)

## Task 7: Trigger non-overlap and cross-reference assertions

**Files:**
- Verify: the three SKILL.md descriptions

- [ ] **Step 1: Adjudicate trigger non-overlap as a self-imposed skill-quality gate and record the verdict**

This is a self-imposed, human-adjudicated skill-quality gate with NO machine enforcement: the bridge verify check 6 is the `docs/superpowers/specs/*.md` output-routing leak detector (it passes trivially here because this change writes no such files), not a SKILL.md trigger-collision detector. Perform the comparison and record the verdict explicitly so a reviewer sees it was done.
Run: `rg -n "Load when" modules/home/ai/skills/src/{claude/agentic-planning-development-workflow,core/project-management,core/openspec-linear-sync}/SKILL.md`
Expected: the router trigger avoids routing-by-graph-metrics (session-advisor), issue-tracking (issues-beads), and raw Linear-verb (linear-cli) vocabulary; the hub avoids routing and raw verbs; the sync avoids PM ontology and mode-routing. Compare against `rg -n "description:" modules/home/ai/skills/src/core/session-advisor/SKILL.md modules/home/ai/skills/src/core/issues-beads/SKILL.md` and the bundled linear-cli skill description, then record the human-adjudicated non-collision verdict (carried into verify.md at the verify gate).

- [ ] **Step 2: Assert references-by-delegation, not duplication**

Run: `rg -n "session-orient|session-advisor|issues-beads|linear-cli|opsx|superpowers" modules/home/ai/skills/src/claude/agentic-planning-development-workflow/ modules/home/ai/skills/src/core/project-management/ modules/home/ai/skills/src/core/openspec-linear-sync/`
Expected: each skill references the existing skills by name (delegation) without inlining their content.

- [ ] **Step 3: Commit**

Commit any wording adjustments needed for trigger non-overlap. (Apply executor: route per the agreed jj routing; no `git worktree add`.)

## Task 8: Stale-comment fix in crs58's home module

**Files:**
- Modify: `modules/home/users/crs58/default.nix`

- [ ] **Step 1: Locate the stale comment**

Run: `rg -n "38 linear-\*/SKILL.md subdirs" modules/home/users/crs58/default.nix`
Expected: one match (the stale comment).

- [ ] **Step 2: Replace the comment**

Replace `# Inject linear-cli's bundled skills (38 linear-*/SKILL.md subdirs)` with a comment describing a single linear-cli/ skill directory with sixteen reference subfiles (per design.md Tasks-foreshadow, stale-comment bullet).

- [ ] **Step 3: Verify the edit evaluates**

Run: `nix eval .#modules.homeManager.ai --apply 'x: "ok"'`.
Expected: prints `"ok"` (evaluates cleanly); `rg -n "sixteen reference subfiles" modules/home/users/crs58/default.nix` returns the new comment.

- [ ] **Step 4: Commit**

Commit the stale-comment fix. (Apply executor: route per the agreed jj routing; no `git worktree add`.)

## Task 9: Nix verification and presence checks

**Files:**
- Verify: the built skills tree

- [ ] **Step 1: Build or evaluate the target host activation package**

Run the host home-manager or darwin activation build (for example `nix build .#darwinConfigurations.stibnite.system` or the home-manager activation attr).
Expected: the build succeeds and the three new skills are present in the store output.

- [ ] **Step 2: Confirm symlink wiring for src/core versus src/claude**

After switching the target host, enumerate the resolved Claude Code skill symlinks and assert membership:
Run: `fd -t l 'project-management|openspec-linear-sync|agentic-planning-development-workflow' ~/.claude/skills` and, for the agent-general pair, `fd -t l 'project-management|openspec-linear-sync' ~/.factory/skills`.
Alternatively, on the build host, a `nix eval` attrName-membership check on the skills attrset (for example `nix eval .#darwinConfigurations.stibnite.config.programs.claude-code.skills --apply 'x: builtins.attrNames x' 2>&1 | rg 'agentic-planning-development-workflow|project-management|openspec-linear-sync'`).
Expected: all three resolve under Claude Code (`~/.claude/skills`); only `project-management` and `openspec-linear-sync` resolve under the agent-general directories (`~/.factory/skills`), confirming the router is Claude-Code-only (src/claude) while the hub and sync are agent-general (src/core).

- [ ] **Step 3: OpenSpec delta-spec structural validity check**

Run: `openspec validate --all --json`
Expected: every item reports valid (this is the verify gate's first check; running it in-loop gives early delta-spec format feedback rather than discovering an invalid ADDED-Requirements block at the gate).

- [ ] **Step 4: Workspace-safety-gate presence check**

Run: `rg -n "linear auth whoami" modules/home/ai/skills/src/core/project-management/ modules/home/ai/skills/src/core/openspec-linear-sync/`
Expected: the gate text present in both the hub and the sync overlay surfaces.

- [ ] **Step 5: Commit**

Commit any wiring fixes surfaced by the build. (Apply executor: route per the agreed jj routing; no `git worktree add`.)

## Task 10: Acceptance criteria and deferred dogfood rows

**Files:**
- Verify: the change against design.md Migration Plan acceptance

- [ ] **Step 1: Confirm the structural acceptance criteria**

Run: `wc -l modules/home/ai/skills/src/{claude/agentic-planning-development-workflow,core/project-management,core/openspec-linear-sync}/SKILL.md`
Expected: each under ~350 lines, in lean-index plus Contents-table form with detail in references leaves.

- [ ] **Step 2: Confirm the dogfood lifecycle reaches archive without linear_story_* frontmatter**

Run: `rg -n "linear_story_" openspec/changes/agentic-planning-development-management-skills/proposal.md`
Expected: no match, because this change is not synced to a real Linear story (design Non-Goals and acceptance 7.4).

- [~] **Step 3: (Deferred dogfood) Live Linear Backlog-to-Done sync against a real story**

Deferred because design Non-Goals forbid a real workspace mutation on this dogfood change. Automated-test equivalent: the linear-cli-mapping.md end-to-end worked example plus the `rg` presence check in Task 6 Step 4, which assert the literal transition commands and the UPSERT recipe without mutating a live workspace. (Record this row in verify.md section 7.)

- [~] **Step 4: (Deferred dogfood) Live workspace-safety-gate refusal of a real mutation**

Deferred because no real Linear mutation is attempted on this change. Automated-test equivalent: the workspace-safety-gate presence check (Task 9 Step 4, `rg -n "linear auth whoami"`) plus the LINEAR_WORKSPACE negative-context check (Task 4 Step 8), which assert the gate is documented and keyed on confirmed credentials without exercising a live refusal. (Record this row in verify.md section 7.)

- [ ] **Step 5: Commit**

Commit the final acceptance confirmation. (Apply executor: route per the agreed jj routing; no `git worktree add`.)

---

## Post-apply lifecycle (dogfood completion)

After the final implementation task above, the dogfood proceeds through the bridge post-apply steps in order: invoke openspec-verify-change to produce verify.md (recording the two `[~]` deferred-dogfood rows from Task 10 in its section 7, alongside the recorded trigger-comparison verdict from Task 7 Step 1), then write retrospective.md, then run `openspec archive`. This is a sequencing clarification, not new implementation scope; the archive step is the terminal artifact that fires the In Review to Done transition.
