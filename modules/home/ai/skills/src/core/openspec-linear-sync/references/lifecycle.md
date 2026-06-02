# Lifecycle: transitions, invariants, and the local sync ledger

This reference defines the lifecycle binding between the OpenSpec change and the Linear board, the invariants that hold across it, and the local sync ledger that makes the binding idempotent and observable.
It describes policy; references/linear-cli-mapping.md carries the literal linear-cli commands for each transition.

## The four forward transitions

The overlay binds the eight-artifact superpowers-bridge lifecycle to Linear's canonical states (Backlog, Todo, In Progress, In Review, Done, plus the inert terminals Canceled and Duplicate) via four forward transitions, the shared re-queue, and the two terminal exits, covering every Linear state with none skipped.
Each forward transition is anchored on an observable local file milestone and fires a short, best-effort, non-blocking Linear comment of at most two sentences.

The first transition, Backlog to Todo, fires when proposal.md is created; it is the bind point at which the overlay writes the story-to-change binding into both locations (see references/config-and-frontmatter.md).
A change with brainstorm.md but no proposal.md is still Backlog and no transition fires, so the brainstorm-exists-proposal-pending window is explicit.
The second transition, Todo to In Progress, fires on the first checked tasks.md checkbox (`- [x]`); this anchor is grep-detectable and survives the jj worktree substitution, so the using-git-worktrees or jj-diamond act are fallback heuristics only.
The third transition, In Progress to In Review, fires when verify.md is created; it is the best-grounded of the four because verify.md is one of the two signals machine-enforced in the bridge PRECHECKs.
The fourth transition, In Review to Done, fires only when `openspec archive` succeeds; Done binds to archive, not to the step6 PR, because the PR diff already contains the complete archived cycle and archive precedes the PR.

## The re-queue and the terminal exits

A single shared re-queue node receives both In Review sub-gate rejections and re-queues into In Progress above the execution-mode fork, so a bounced issue re-selects its mode.
The re-queue In Review to In Progress fires on either a verify.md Overall Decision of checked "(fail) FAIL" (machine-detected) or a human rejection at either In Review sub-gate (roborev for code review, then documenter for docs/handbook review).
It is governed by the bounded-retries policy below, which escalates to the human PM layer on exhaustion.

Canceled and Duplicate are inert terminals reachable from any active state and are best-effort and human-driven: Canceled corresponds to a change directory removed without archive, and Duplicate to a change superseded by another.
Like Backlog, they carry no active work.

## Invariants

The issue is never moved to Done before archive; status, validate, sync, and edit operations never move the issue to Done.
Comments stay at most two sentences.
The archive ordering is fixed: readiness checks, then sync deltas, then archive, then mirror (the document UPSERT), then Done.

## State resolved by name, never by type

Every transition resolves and passes the team's Linear state NAME (for example "In Review") via linear-cli, never the workflow-state type.
In Progress and In Review both carry the workflow-state type "started" in the live workspace, so keying on type would conflate the two; passing the exact state name is what disambiguates them.
That `--state` accepts a name or a type is a linear-cli fact documented in `~/.claude/skills/linear-cli/references/issue.md`.

The overlay degrades gracefully for a team that lacks an In Review state.
The transition is attempted and its NotFoundError is caught as a dropped best-effort write recorded in the attempt log, leaving the issue In Progress until Done; the NotFoundError error-class on an unresolvable `--state` is a linear-cli behavior documented in `~/.claude/skills/linear-cli/references/issue.md`, and the literal command appears once in references/linear-cli-mapping.md rather than being restated here.
No Linear state is fabricated, and the dropped write is observable in the ledger rather than silently absorbed.

## The local sync ledger (D10)

The overlay maintains a minimal local sync ledger adjacent to the bridge, persisted as fields in openspec/linear.yaml (the schema is in references/config-and-frontmatter.md).
The ledger records `last_synced_state`, `last_synced_at`, a review-round counter, and a short attempt log.
This single mechanism closes detection, idempotency, the bounded-retries counter, and observability.

Local milestone-file existence is the authoritative current-phase signal: proposal.md, the first tasks.md `- [x]`, verify.md, and the archived change directory together determine the local phase.
The Linear state is treated as a best-effort projection that a catch-up reconciliation step corrects rather than trusting.
When the local phase and the Linear state disagree, the catch-up reconciliation computes the local phase from the milestone files, reads the Linear state, and fires the catch-up transition rather than assuming Linear is current.

### Idempotency: the strictly-behind rule

A transition fires only when the resolved Linear state is strictly behind the local milestone; if Linear is already at or past the target the transition is a no-op.
Each milestone comment posts at most once per crossing.
apply and verify are routinely re-invoked, so this is what prevents re-runs from re-firing transitions and spamming the team-visible comment surface; it generalizes the openspec-linearized guarded form ("if the issue is in Todo, transition it to In Progress") into a strictly-behind comparison against the resolved Linear state name.

### Bounded-retries counter

The review-round counter lives in openspec/linear.yaml because Linear writes are best-effort and a counter stored in Linear could be dropped, which would make the termination guarantee unsound.
It defaults to a small max (recommended default 3, with a documented configurability note in the schema), increments once per re-queue (one per In Review to In Progress crossing), and resets when the change archives (forward progress past In Review).
On exhaustion the mechanical escalation action is to post a single escalation comment to the human PM layer and stop firing automatic re-queues, leaving the issue parked for a human decision; this gives the board a documented termination guarantee that its structure alone does not provide.

### Attempt log

The ledger records dropped best-effort writes in the attempt log so the system can distinguish a never-attempted transition from a failed one, and a human can see that Linear is stale.
The Linear comment is the only other transition record, and it is exactly the surface that fails under the best-effort write model, so the attempt log is the observability backstop for dropped writes.

## Re-queue resume and mid-lifecycle mode hand-off (D11)

A bounced issue is recognized as resuming, not starting fresh, by the combination of the In Progress state with a verify.md "(fail) FAIL" or a recorded sub-gate rejection in the ledger's attempt log.
The rejection feedback is read from verify.md (machine-detected fail) or the ledger entry the router wrote at the human rejection.
The re-selected execution mode defaults to the original mode across re-queues unless the human explicitly overrides at the mode fork; keeping the original mode avoids the two-authoritative-ledger problem, where an issue started in one mode with one authoritative task ledger, bounced, then re-picked in another mode with a different authoritative ledger, would have two ledgers with no reconciliation rule.
If the human does override the mode on re-queue, the cost is an explicit ledger hand-off the human accepts, noted in the attempt log.
