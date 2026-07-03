# Board and gates

The board is forge-agnostic in concept but re-cast onto Linear's canonical states so every board state maps one-to-one onto a Linear state with none skipped.
The board is a per-change spine projected onto the change's own `linear_team` board, so state names resolve against `linear_team` and the one-to-one mapping holds within that team's state set (state names are team-scoped).
This one-to-one mapping is what makes the whole binding automatable.
The unit of work is the forge-agnostic board unit and the terminal artifact is the archived OpenSpec change; a pull request into the monorepo, including docs and handbook, is one realization of that terminal artifact, consistent with the repo's fast-forward-merge-by-default, PR-when-warranted policy.

This file owns the state machine, its gates, the In-Review sub-gates, the shared re-queue, the bounded-retries policy, and a concrete router walkthrough.
The per-mode ledger rules live in references/execution-modes.md; the abstract sub-gates and delegation contract live in references/delegation.md.

### Board diagram

A stateDiagram-v2 rendering of the unified seven-state board, its four file-anchored forward transitions, the execution-mode fork, the two ordered In-Review sub-gates, the shared re-queue, and the inert terminals is maintained separately so the prose and the visual stay in sync.
See references/board-state-machine.mermaid.

## The seven Linear-canonical states

Five states are active and two are inert terminals.

Backlog, Todo, In Progress, In Review, and Done are the five active states a unit of work passes through in order.
Canceled and Duplicate are inert terminals carrying no active work, reachable from any non-terminal active state (every active state except Done) exactly like Backlog.

## The four forward transitions

Each forward transition is named by its transition rather than by an ordinal and fires on exactly one file-anchored condition.
The four anchors are all observable file milestones, which is why the whole binding is automatable.

The readiness gate fires Backlog to Todo when a change directory acquires a committed proposal.md.
That firing also seeds the Linear issue description from the committed proposal.md's business-facing content, as a best-effort bind effect.
The proposal.md anchor is more substantive than brainstorm.md: a transition firing before the change has a committed proposal is weaker visibility for little gain.

The apply gate fires Todo to In Progress on the first tasks.md `- [x]` checkbox marked complete.
The first checkbox is the grep-detectable anchor that survives the jj worktree substitution; the using-git-worktrees and jj-diamond acts are fallback heuristics only.

The In-Review gate fires In Progress to In Review when verify.md is created for an in-progress change.
This is the best-grounded of the four anchors because verify.md is one of the two signals machine-enforced in the bridge PRECHECKs.

The archive gate fires In Review to Done when the change is archived (openspec archive succeeds).
Done is reached only after archive; the archive step is the sole anchor that fires Done.

A change directory with brainstorm.md but no proposal.md stays in Backlog: no forward transition fires.
This brainstorm-exists-proposal-pending window is explicit so a reader does not expect a brainstorm-only change to leave Backlog.

## The file anchors are HIL/OpenSpec-native; each mode has its own firing signal

Three of the four forward anchors (proposal.md, verify.md, and the archived change) are OpenSpec artifacts that exist only in HIL mode.
The board states are mode-agnostic, but the firing signals are not: AFK and Manual reach the same states on different observable signals.
The four-anchor model above is the HIL realization; the per-mode firing signals are:

| Forward transition | HIL (OpenSpec) | AFK (Claude Code Workflows) | Manual (beads + session-checkpoint) |
|---|---|---|---|
| Backlog to Todo | committed proposal.md | the Workflows plan file exists (the proposal-equivalent) | beads issue moves to ready/open |
| Todo to In Progress | first tasks.md `- [x]` | first plan checkbox completed | beads issue status set to in_progress |
| In Progress to In Review | verify.md created | the plan's completion record (the verify-equivalent) | beads issue status set to in_review at a session-checkpoint |
| In Review to Done | openspec archive succeeds | the human accepts the completion record at the In-Review gates | beads issue closed at a session-checkpoint |

In Manual mode the board is reduced and driven by beads issue status plus session-checkpoint rather than the full file-anchored spine, and the Manual Linear binding lives in a beads issue field (see references/execution-modes.md) carrying the status.
This keeps the seven-state board honest: the states are universal, but the AFK and Manual arms traverse them on their own signals, not on the OpenSpec file anchors.

## The mode fork at Todo to In Progress

The human execution-mode fork sits at the Todo to In Progress boundary.
The human picks AFK, HIL, or Manual per-issue with no automatic Linear-label selection, and all three modes converge on In Review.
The apply gate that fires Todo to In Progress is the same gate regardless of mode; what differs is the authoritative ledger the chosen mode fixes (see references/execution-modes.md).

## In Review decomposes into two ordered sub-gates

In Review internally decomposes into two ordered human-steered sub-gates.
The current execution model for both is human-steered: a human operating the workflow orchestrator supplies the verdict, and the router presents the gate and routes on that verdict rather than auto-executing review.

The roborev sub-gate runs first.
roborev is the code-review point linking out from the superpowers-bridge apply and verify stage.
Its concrete code-review automation is the inline codex review documented in references/codex-review.md, which composes into this abstract gate without introducing a fourth agent or a new board state; it augments rather than replaces superpowers:requesting-code-review, whose apply-phase review continues alongside.
The codex binding is advisory in all three execution modes: codex emits a verdict and findings as evidence, and the orchestrating session or a human always makes the advance-versus-re-queue decision, so the currently-human-steered framing above is preserved and codex layers under it as the evidence generator (even AFK pauses here for human adjudication and does not auto-advance on a codex pass).
The findings are a triage surface rather than an autonomous block: all findings are presented grouped by priority with the recommended-blocking set (priority `<= 1`, plus an overall `incorrect` signal) flagged as the default must-address set, and the session or human chooses the subset to address; that triage decision, not the raw threshold, drives the transition.
An accept decision advances the router to the documenter sub-gate; a re-queue decision routes into the shared re-queue, recorded by checking the existing verify.md Overall Decision checkbox from `- [ ] (fail) FAIL` to `- [x] (fail) FAIL` so it reuses the existing machine-detected re-queue path described below, incrementing `review_round` under the bounded-retries policy.
The verify.md-checkbox recording and the review_round increment are the HIL realization of the re-queue; in AFK the equivalent is the plan completion record and in Manual it is the human-rejection re-queue path at a session-checkpoint, while the advisory codex verdict itself is generated identically in all three modes.

The documenter sub-gate runs second.
documenter is documentation authoring plus review linking out from the verify and retrospective stage.
On a passing verdict the router proceeds to the archive step, which is the sole anchor that fires Done; on a failing verdict it routes into the shared re-queue.

documenter's review surface is repo-dependent.
For the sciexp monorepo it is apps/handbook/src/content/docs/; for vanixiets-internal work it is docs/notes/ plus the affected skill and module docs.

The joint approval of both sub-gates is the precondition for the archive gate, consistent with the invariant that a unit is never Done before archive.

## The shared re-queue and bounded-retries policy

A single shared re-queue node receives both sub-gate rejections and re-queues into In Progress above the mode fork (In Review to In Progress), so a bounced unit re-selects its execution mode.
The re-queue fires on either a verify.md Overall Decision of checked-FAIL (machine-detected) or a human rejection at either sub-gate.

Termination toward Done is not guaranteed by the board structure; it holds only under a fairness assumption or a bounded-retries policy.
A bounded-retries policy supplies the documented termination guarantee: a maximum review-round counter (recommended default 3) that increments once per re-queue and resets when the change archives.
The counter-backed guarantee holds for the modes whose ledger carries the review-round counter (HIL, and AFK where the plan file backs it).
Manual mode carries no review-round counter; there the human is the regulator and termination is human-judged at session-checkpoint, the fairness-assumption path named above rather than the counter-backed one.
The `review_round` counter is per-change, persisted in that change's proposal.md frontmatter, with the default ceiling sourced from linear.yaml `defaults.max_review_rounds` (a change may override it in its frontmatter).
On exhaustion the board escalates to the human PM layer and stops firing automatic re-queues, parking the unit for human decision.

## Router walkthrough

One unit of work traversing the board.

A change directory is created with brainstorm.md only.
No forward transition fires; the unit stays in Backlog (the brainstorm-exists-proposal-pending window).

The human authors and commits proposal.md.
The readiness gate fires Backlog to Todo.
The bind also seeds the Linear issue description from proposal.md.

The unit reaches the Todo to In Progress boundary.
The human picks HIL at the mode fork (no Linear label mechanizes this), fixing tasks.md as the authoritative ledger.
Apply marks the first tasks.md `- [x]` complete; the apply gate fires Todo to In Progress.

Apply and verify run; verify.md is created.
The In-Review gate fires In Progress to In Review.

Inside In Review the roborev sub-gate runs first.
The human reviews the code diff and supplies an approved verdict; the router advances to documenter.
The documenter sub-gate runs second over docs/notes/ and the affected skill docs; the human supplies a passing verdict.

The change is archived (openspec archive succeeds).
The archive gate fires In Review to Done; the review-round counter resets.

A rejection variant: had the human rejected at roborev, the router would route the unit into the shared re-queue (In Review to In Progress, above the fork); the unit would re-select its mode, defaulting to HIL, the review-round counter incrementing once.
Three exhausted rounds would escalate to the human PM layer and park the unit.

## Spec and feature alignment (pre-apply)

At the Todo to In Progress boundary, upstream of the apply gate and symmetric to the two In-Review sub-gates, a mode-agnostic pre-apply gate aligns spec and feature encodings when the change carries behavioral requirements.
When a change's delta specs contain behavioral requirements, the delta specs and the corresponding Gherkin `.feature` files are laid out and aligned per the openspec-bdd-bridge skill before the apply-change executor starts working tasks.md; the gate no-ops when no delta spec carries behavioral requirements, so AFK and Manual paths without specs are unaffected.
That same skill owns the modality routing, the tag-and-guard traceability convention, the per-runner feature and step-definition conventions, and the spec-to-Gherkin mapping.
That modality routing is not Gherkin-exclusive: behavioral requirements become scenarios, while non-behavioral requirements — properties, design-by-contract assertions, and symbolic or SMT edges — route through the same gate's concept-layer decision table, Gate 1 in the atdd-outer-loop skill, whose owner assignments the openspec-bdd-bridge skill already defers to.
See ../../openspec-bdd-bridge/SKILL.md for the substance.

The correspondence is maintained rather than established once, and it is reconciled before archive per the same openspec-bdd-bridge skill, which frames that reconciliation as a soft guidance layer on top of openspec-verify-change's existing non-blocking Scenario Coverage check rather than a new blocking gate.

## Future automation extension point

Automation hooks may trigger the right tools at each sub-gate (code-review automation for roborev; doc-generation and review automation for documenter), composing into the existing abstract gates without introducing a fourth agent; the board structure, the two sub-gates, and the shared re-queue are unchanged.

The roborev hook is realized: references/codex-review.md binds it to the inline codex review.
The review defaults to a single advisory round, with optional panel-mode escalation that takes the majority of K identical runs for contested or high-criticality verdicts, detailed in references/codex-review.md.
codex plugs in strictly upstream of the existing In Progress to In Review to Done transitions, stays advisory in all three modes, and adds no new board state or Linear state; its accept decision advances to documenter and its re-queue decision drives the shared re-queue by checking the verify.md `- [x] (fail) FAIL` box, reusing the existing machine-detected path.
The documenter hook remains an abstract extension point: a future doc-generation-and-review binding would compose into the documenter sub-gate the same way, leaving the structure unchanged.
