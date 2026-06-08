# Retrospective: agentic-planning-development-management-skills

> Written: 2026-06-02 (after verify passed)
> Commit range: `88dc7cd7..29114371` (chain tip at write time; the retrospective commit seals above the verify commit)
> Worktree: jj diamond development join on bookmark `agentic-planning-development-management-skills` (no git worktree; worktree-creating surfaces are hook-blocked in jj mode)

---

## 0. Evidence

> Up-front quantified data; the Wins / Misses sections below reference these numbers rather than re-citing per line.

- **Commit range**: `88dc7cd7..29114371` (8 commits on the chain above the `main` fork point: 3 artifact-doc commits, 4 implementation commits, 1 verify commit; the retrospective commit seals above the verify commit and is orchestrator-owned)
- **Diff size**: +2379 / -4 lines across 27 files; the implementation slice under `modules/` is +1050 / -4 across 17 files, the remainder being the eight OpenSpec lifecycle artifacts
- **Tasks done**: 29/29 in tasks.md (`grep -cE '^\s*- \[x\]' tasks.md` → 29; `grep -cE '^\s*- \[ \]'` → 0). plan.md carries a separate planning ledger of 50 items, of which 2 are intentionally `[~]` deferred-dogfood rows (live Linear sync and live safety-gate refusal); the apply-phase authoritative ledger is tasks.md per the D2 ownership-by-layer rule
- **Active hours**: estimate ~6-8 hours wall-clock across one extended session (orchestrator-led research fan-out, four design/review rounds, four-commit apply, verify)
- **Subagent dispatches**: many; the brainstorm was an orchestrator-led ten-reader research fan-out, and the apply/review phases dispatched per-deliverable authoring plus four review-round Tasks; exact count n/a (not instrumented)
- **New external dependencies**: none. Composes the already-bundled `linear-cli` skill (crs58-scoped) and the vendored superpowers-bridge OpenSpec schema; no new nix inputs, packages, or services
- **Bugs encountered post-merge**: none post-merge (not yet merged). Two runnable-CLI defects were caught pre-merge by the final integrated review's red-team and fixed in the sync overlay before the verify commit (see §1 and §5): the `documentsConnection .nodes[]` parse and the workspace-omitting reads
- **OpenSpec validate state at archive**: not-run (pre-archive). `openspec validate --all --json` at verify reported `items: 1, passed: 1, failed: 0` (valid=true, issues=[]); archive-time sync of the three pending deltas is the lifecycle's job
- **Test coverage signal**: n/a — the deliverables are agent skill documents (markdown), not executable code. Verification is the nix home-manager skills-derivation eval (the three skills resolve and symlink-wire under the agent skills directories) plus static `rg` presence assertions for the literal transition commands, the `linear auth whoami` gate, and the archive-time UPSERT recipe

Commit chain (chronological):

```
88dc7cd7 fix(pkgs): linear-cli — writable DENO_DIR so deno persists perf caches at runtime   (base, on main)
b7e09bc9 docs(agentic-planning): scaffold superpowers-bridge change + brainstorm artifact
03872564 docs(agentic-planning): proposal + design artifacts
c2636986 docs(agentic-planning): specs + tasks + plan artifacts
623d18f8 feat(skills/agentic-planning-development-workflow): state-machine router skill
70a6e054 feat(skills/project-management): human-facing PM hub skill
a17212f5 feat(skills/openspec-linear-sync): linear-cli Linear/OpenSpec sync overlay skill
f91a755e fix(home/crs58): correct stale linear-cli bundled-skills comment (38 -> 1 dir/16 refs)
29114371 docs(agentic-planning): verify artifact (PASS WITH WARNINGS)
```

---

## 1. Wins

- [§0 diff size; commits 623d18f8/70a6e054/a17212f5] Three skills delivered additively with zero new external dependencies and no manual nix registration: auto-discovery via `readSkillsFrom` picks up all three directories, src/core flows the hub and sync overlay to all agents while src/claude scopes the router to Claude Code, exactly as D1 specified.
- [§0 tasks 29/29; verify check 1] The dogfood reached verify with every apply task complete and a clean structural validate (valid=true, issues=[]), demonstrating the superpowers-bridge HIL lifecycle end-to-end on a real change — the dogfood premise (build the lifecycle through the lifecycle) held as a correctness test.
- [§0 bugs; final review red-team] The four-round review discipline paid off concretely: each round caught something real rather than rubber-stamping. The design review hardened two decision-thin spots into D10 (the local sync ledger as authoritative current-phase signal and idempotency home) and D11 (re-queue resume and mid-lifecycle mode hand-off), and flattened the references tree to one level per the agentskills spec. The apply-readiness review fixed the eval-attr and supplied the previously unauthored sync-setup step.
- [§0 bugs; final review red-team source-verified] The final integrated review's red-team caught two source-verified runnable CLI defects in the sync overlay before they could ship: the `documentsConnection .nodes[]` parse (which would have produced a duplicate document per archive) and reads that omitted `--workspace` (which would have leaked to the personal workspace). Both are now corrected in `linear-cli-mapping.md`.
- [composition audit; commit f91a755e] The composition audit found that linear-cli mechanics had been re-documented inline where they would drift from the vendored linear-cli skill, driving a cross-reference refactor so the overlay composes the linear-cli skill rather than re-stating its verbs; the same audit surfaced and corrected the stale `38 linear-*/SKILL.md subdirs` nix comment to the accurate single-dir/16-reference shape.
- [verify check 4] Design/specs coherence spot-check passed with no gaps across all eight sampled decisions (seven-state board, In-Review sub-gates, compose-by-delegation, re-queue, linear-cli-exclusive UPSERT, local sync ledger, workspace safety gate, flat four reference areas), and no design-output routing leak (verify check 6).

## 2. Misses

- [med] [painful | §0 op log; §5] A parallel-writer divergence occurred during apply: a stale partial twin of `@` accumulated alongside the live chain (~22 working-copy snapshots visible in `jj op log`), the known jj concurrent-subagent `@`-sharing tangling hazard. It was resolved by abandoning the stale partial twin, but it cost reconciliation effort and is a recurring class of friction when multiple writers share the working-copy commit.
- [med] [painful | D5; deferred record 1] The In-Review `roborev` gate ships naming no default composition target even though the environment already exposes code-review, security-review, and superpowers:requesting-code-review and the name "roborev" implies automated review — making the In-Review gate the least-elite part of the system on day one. This is a deliberate human-steered-gate decision, not an oversight, but it leaves an obvious capability one config flip away (folded into §6 / deferred-work below; since realized — the roborev half is now wired to inline codex review, see §6).
- [low] [nit | verify check 3] Three delta-spec capabilities report "pending sync" at verify. This is the expected pre-archive state (the lifecycle syncs deltas at archive), not a defect; recorded here only so the audit trail shows it was considered and dismissed.
- [low] [nit | proposal.md] The dogfood was deliberately not synced to a real Linear story, so the two most operationally interesting transitions (a live Backlog→Done sync and a live workspace-safety-gate refusal) were exercised only via static-assertion equivalents, never against a live workspace. Adequate for v1 by design, but the live path remains unproven by this change.

## 3. Plan deviations

| Plan task | What changed | Why |
|-----------|--------------|-----|
| Design decisions | Two new decisions (D10 sync ledger, D11 re-queue resume) added after the design review | The design review found detection, idempotency, the bounded-retries counter, and observability all bottomed out in one missing primitive (a local ledger), and that re-queue resume was structural-only; both were hardened from decision-thin spots into explicit decisions |
| References tree | Flattened to one level deep across all three skills; the PM hub's four sub-areas became filename prefixes in a single flat `references/` rather than nested subdirectories | Agentskills spec ("keep file references one level deep", specification.mdx:235) and house precedent; the design review caught the proposed two-level nesting |
| Sync overlay (Task 3.3) | The inline linear-cli mechanics were refactored to cross-reference the vendored linear-cli skill, and two runnable CLI defects (documentsConnection parse, missing `--workspace` on reads) were fixed | The composition audit found re-documented mechanics that would drift; the final review red-team source-verified the two defects |
| State machine (D5/D6) | Unified to the seven Linear-canonical states with four file-anchored forward transitions; the draft's Ready folded into Todo and Review+Document both folded into In Review with roborev/documenter as ordered sub-gates | The user pushed back on a framing that skipped In Review; verify.md is a PRECHECK-grepped milestone that maps cleanly onto Linear's In Review state, so collapsing it would leave a Linear state uncovered |
| Apply isolation | Apply ran in the jj diamond development join with orchestrator-routed commits onto the chain — no git worktree, no autonomous PR | superpowers:using-git-worktrees resolves to a hook-blocked `git worktree add` in jj mode; the diamond join is the sanctioned substitute (D-risk and hil-isolation.md) |

## 4. Skill / workflow compliance

| Skill                                            | Used |
|--------------------------------------------------|------|
| superpowers:brainstorming                        | yes  |
| superpowers:writing-plans                        | yes  |
| superpowers:using-git-worktrees                  | no (diamond-adapted) |
| superpowers:subagent-driven-development          | yes  |
| (transitive) superpowers:test-driven-development | no (non-code deliverable) |
| (transitive) superpowers:requesting-code-review  | yes  |
| superpowers:finishing-a-development-branch       | no (diamond-adapted) |

> **Default expectation**: all yes. Skips below are jj-mode boundary conditions and a non-code-deliverable condition, each with its prevention plan.

### Deliberately Skipped Skills

- **`superpowers:using-git-worktrees`**
  - **What was skipped**: the `git worktree add` isolation step; the apply ran in a jj diamond development join with orchestrator-routed commits onto the chain instead.
  - **Why this cycle**: the environment is jj-mode (colocated jujutsu); the harness denies EnterWorktree/ExitWorktree and worktree-isolated Task dispatches at the PreToolUse layer, and `superpowers:using-git-worktrees` resolves to a raw `git worktree add` that is hook-blocked. This is the documented apply-gate jj incompatibility recorded in design.md Risks and brainstorm.md "Key constraints" (the jj-diamond-act fallback).
  - **How to prevent recurrence**: `schema graph fix` plus `CLAUDE.md trigger`. The schema's apply phase should treat the diamond development join as the sanctioned worktree substitute when `.jj/` is present, and the adopter CLAUDE.md already encodes "worktree isolation is hook-blocked at the Agent tool surface; the diamond development join is the isolation mechanism." The pending jj workspace-vs-diamond policy follow-up (deferred record 8) is the durable home for codifying this so the next jj-mode cycle does not re-derive it.

- **`superpowers:finishing-a-development-branch`**
  - **What was skipped**: the autonomous PR-open step; version control was orchestrator-owned and the chain was not opened as a PR from the apply phase.
  - **Why this cycle**: same jj-mode condition — `finishing-a-development-branch` opens a PR, but in jj-mode this workspace integrates via the diamond's sequential-rebase linearization and fast-forward, and commits/pushes are orchestrator-owned by binding directive. The subagent edit-gate forbids the apply Task from owning VCS writes.
  - **How to prevent recurrence**: `schema graph fix`. The apply/finish phase should defer integration to the orchestrator under a diamond development join rather than calling a PR-opening skill; the jj-policy follow-up (deferred record 8) should articulate how finish maps onto diamond linearization.

- **`(transitive) superpowers:test-driven-development`**
  - **What was skipped**: writing executable tests first; the deliverables are agent skill markdown documents with no executable surface.
  - **Why this cycle**: the three deliverables are SKILL.md indices plus references leaves, not code. The verifiable contract is the nix home-manager skills-derivation eval (the three skills resolve and symlink-wire) plus static `rg` presence assertions for the literal transition commands, the safety gate, and the UPSERT recipe — this is the test-equivalent, exercised in tasks §6.
  - **How to prevent recurrence**: `one-off — schema boundary case, no prevention possible`. It is a genuine boundary case because the schema's TDD edge presumes an executable artifact; a markdown skill bundle has no unit under test, so the eval-plus-presence-assertion is the type-appropriate severe check, not a degraded substitute. The next non-code-deliverable cycle should likewise route to eval + static presence assertions rather than fabricating an executable harness.

## 5. Surprises

- The dogfood premise was load-bearing as evidence, not just rhetoric: friction discovered while authoring the artifacts was itself data about the lifecycle. The clearest instance is that the apply phase's known jj incompatibility (worktrees hook-blocked) was confronted in practice and resolved via the diamond-adapted apply, validating that the bridge's HIL apply can run in jj-mode at all.
- The review rounds were not redundant. Going in, four rounds looked like over-process; in practice each round caught something a single pass would have shipped: D10/D11 hardening and the references flattening (design review), the eval-attr and the missing sync-setup step (apply-readiness review), two source-verified runnable CLI defects (final red-team), and inline-drift in the linear-cli mechanics (composition audit).
- The two runnable CLI defects were real bugs in shipped recipe text, not hypotheticals — the `documentsConnection .nodes[]` parse would have produced a duplicate document per archive, and `--workspace`-omitting reads would have silently read from the personal workspace. A documentation deliverable can still carry executable-correctness bugs.
- A parallel-writer divergence (a stale partial twin of `@`, ~22 working-copy snapshots) materialized during apply — the known jj concurrent-subagent `@`-sharing tangling hazard — and had to be reconciled by abandoning the stale twin. Concurrency hazards in the working copy are not purely theoretical even within a single orchestrated session.
- The state machine needed a user correction: an initial framing skipped In Review, and the user pushed back, driving the unification to the seven Linear-canonical states with four file-anchored transitions (and In Review decomposed into roborev/documenter sub-gates). The "obvious" three-transition collapse would have left a Linear state uncovered.

## 6. Promote candidates → long-term learning

- [x] [med] **Name a default roborev composition target** → **Realized**: the roborev sub-gate is now wired to an inline codex review (references/codex-review.md) as an advisory hook (cross-model verdict, advisory in all modes, no fourth agent); the documenter default remains TBD.
  > **Why**: the In-Review roborev gate is human-steered by binding decision (no fourth agent), but the environment already exposes code-review, security-review, and superpowers:requesting-code-review, and "roborev" implies automation; naming a default is one config flip away yet is a decision-touching change to the human-steered-gate decision, not a legibility fix.
  > **How to apply**: when the future automation extension is opened, candidate default is code-review for the roborev sub-gate; documenter sub-gate default is TBD. Until then, hold against the human-steered decision.

- [ ] [med] **Codify the jj diamond development join as the schema's sanctioned worktree substitute** → **Promote to schema** (superpowers-bridge apply/finish phases)
  > **Why**: two apply-phase skills (using-git-worktrees, finishing-a-development-branch) were skipped this cycle for the same jj-mode reason; per the §4-to-§6 rule, a shared skill + shared "how to prevent" answer across the same situation is a schema PR motivator, not a norm to accumulate.
  > **How to apply**: at the apply gate when `.jj/` is present — the schema should branch to the diamond development join and orchestrator-owned integration rather than to git-worktree isolation and autonomous PR. The standalone jj workspace-vs-diamond policy follow-up (deferred record 8) is the durable design home.

- [ ] [low] **Documentation deliverables can carry runnable-correctness bugs; red-team the literal commands against source** → **Promote to memory** (type: feedback)
  > **Why**: the final review found two source-verified CLI defects (documentsConnection parse, missing --workspace) in shipped recipe text that a prose review would have passed; a skill that documents commands is an executable artifact in disguise.
  > **How to apply**: when reviewing a skill or doc that embeds literal CLI commands, verify each command against the tool's source/`--help`, do not treat it as prose; especially flag JSON-parse shapes and workspace/scope flags.

### Deferred work, follow-ups, and non-goals

The following records are carried forward verbatim-in-spirit so they are not lost. They are deferred or out-of-scope by deliberate decision, not gaps.

- The In-Review roborev gate now names a default composition target: the inline codex review (references/codex-review.md), wired as an advisory hook that stays human-steered (codex emits a verdict and findings as evidence; a human or the orchestrating session decides the transition). The gate is human-steered by binding decision (roborev/documenter are human-steered abstract gates; no fourth agent; automation is a future extension). The final review's high-severity finding notes the environment already exposes code-review, security-review, and superpowers:requesting-code-review and the name "roborev" implies automated review, yet no default is named — making the In-Review gate the least-elite part of the system on day one even though wiring a named default is one config flip away. The documenter half remains the deferred extension point (default TBD); the roborev half is realized rather than deferred.

- Cross-project Initiative and Cycle binding as a live surface. The sync binds strictly one-story-one-change; cross-project Initiative and Cycle modeling is documented as an orthogonal overlay only and never becomes a live binding surface. This is a real ceiling on project-management eliteness, left implicit. A future change could bind Initiative/Cycle as live surfaces with the attendant multi-story/multi-change reconciliation rules; out of scope for the current single-operator dogfood.

- Requirements-drift reconciliation (human edits the Linear body mid-flight) as an explicit non-goal. Status drift up is handled by the D10 catch-up, but a human editing the Linear issue body mid-flight is never detected and reconciled against the OpenSpec proposal. Low-risk for one operator, a genuine gap for a multi-stakeholder system. The resolved sync policy is business-what-down / status-up, best-effort; body-content reconciliation is outside it. Non-goal: the overlay does not detect or reconcile human edits to the Linear issue body; the OpenSpec proposal remains the source of truth for business-what, pushed down, never pulled up from a human Linear edit.

- The crs58-scoped linear-cli surface as an explicit scope boundary. The linear-cli skill is contributed user-scoped for crs58 only, while the openspec-linear-sync overlay lands in src/core and reaches all agents; a non-crs58 agent loading the overlay would reference a linear-cli skill that is not present (noted at openspec-linear-sync/SKILL.md:19 as accepted because crs58 is the only operator). Ratified scope boundary, not an inline aside: the overlay's Linear-verb execution is crs58-scoped and degrades gracefully (references a skill absent for other agents) by accepted design.

- Aggregate sync observability across issues. The D10 local sync ledger gives per-issue observability (last_synced_state, last_synced_at, review-round counter, attempt log in openspec/linear.yaml). There is no aggregate/cross-issue observability surface for dropped writes across the fleet of changes. Deferred enhancement (v2): a future aggregate view (a roll-up of attempt logs across all openspec/linear.yaml files, or a board-level dropped-write report) would improve operability for a multi-change workload.

- AFK dispatch target / verify-equivalent that fires the In-Review gate. The board spine is presented as mode-agnostic, but three of its four forward anchors (proposal.md, first tasks.md [x], verify.md) are OpenSpec artifacts absent in Manual mode, and AFK's authoritative ledger is plan checkboxes with no stated mapping to a verify-equivalent that fires the In-Review gate. The AFK dispatch target is an explicitly documented deferred decision (deferred to the apply gate). Record: the AFK arm's verify-equivalent and its dispatch target are resolved at the apply gate; until then the universal board is in practice HIL/OpenSpec-shaped and the AFK/Manual arms cannot traverse it on the OpenSpec anchors as written.

- jj file-anchor-at-grep-time follow-up. The Todo→In Progress transition anchors on the first checked tasks.md checkbox (`- [x]`), which lifecycle.md notes is grep-detectable and survives the jj worktree substitution (using-git-worktrees / jj-diamond acts are fallback heuristics only). The precise timing of when the file-anchor is grepped under jj (working-copy vs sealed-commit visibility, given the known jj+git pre-seal eval staleness for new files) is deferred to the jj-policy follow-up. Record: confirm the grep-at-detection-time semantics hold under jj's new-file pre-seal visibility before relying on the anchor in a jj-diamond context.

- Separate jj workspace-vs-diamond policy follow-up. A standalone follow-up (distinct from the linear-cli skill refactor) to articulate the jj workspace-vs-diamond policy as it interacts with the file-anchored board transitions: which milestone files exist in which working copy under a development join, and how the AFK/HIL anchors resolve across a diamond. This is its own future OpenSpec change.
