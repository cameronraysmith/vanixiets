# Operational patterns

Operational patterns the WO process applies during execution.
Load when configuring subagent dispatch, when recovering from a harness write-gate, at first-cycle calibration with AC, at PR-cycle entry, at stream-completion time, or when interleaving streams that target the same repo.

## Orchestrator-mode subagent dispatch template

The WO process is the orchestrator of its execution; it dispatches ephemeral subagents to do the writes.
Each subagent dispatch follows a seven-field priming template:

1. *Absolute paths.* No working-directory drift assumption. Subagent confirms its working directory at start.
2. *Exact content.* The actual file edit, not a description. Subagent writes byte-for-byte.
3. *Commit message verbatim.* The commit message text is included in the brief, formatted as a heredoc the subagent passes to `jj describe`. Format is conventional commits (sentence case, no emojis, no `@`-mentions, no `#N` references unless explicitly authorized).
4. *Single logical change per dispatch.* One file, one purpose, one commit. No bundled multi-file edits.
5. *jj-write-command envelope.* Subagent runs `jj describe + jj new` itself. WO process does not run jj write commands.
6. *Return contract.* Subagent returns: working directory at start, file creation outcome, `wc -l` output, `change_id` from `jj log -r @-`, `jj st` after `jj new` (expected empty `@`), and any deviations or unexpected state.
7. *Escape-hatch instruction.* Subagent returns with questions on ambiguity rather than attempting recovery moves.

The template encodes the orchestrator-mode discipline: WO process stays read-only (orchestrate, prime, dispatch, inspect via `jj log`, `jj diff`, `jj st`); subagents do the writes.

## Harness write-gate empirical scope

The harness Write-gate gates `Write` and `Edit` tool calls from persistent teammate sessions targeting files inside the current working repo.
Empirical scope from dog-food observation:

- *Repo-scoped*: gates writes to files inside the current working repo (e.g., when WO's `pwd` is in vanixiets, vanixiets writes gate). Does NOT gate writes to files outside the working repo (e.g., observation logs under `~/.claude/jobs/`).
- *Tool-specific*: gates `Write` and `Edit` from persistent sessions. Does NOT gate Bash-invoked subprocess writes (`jj describe` via Bash works; `echo > file` via Bash works; subagent `Write` works because subagent is a separate session).

Default discipline: dispatch ephemeral subagents for writes within the working repo. Do not rely on Bash-write workaround; it works under current harness but is operationally-functional-but-theoretically-fragile.

Cross-repo writes from a persistent WO session (e.g., WO in planning writing to vanixiets) work without subagent dispatch under current harness, but the same fragility caveat applies. Default to subagent dispatch when authoring artifacts in target repos.

## First-cycle critique calibration

Subagent dispatch patterns are calibrated once per mission, then applied uniformly.

- *First-cycle*: WO surfaces the commit-1 priming prompt to AC BEFORE dispatching the subagent. AC reviews the seven-field structure, the canonical-text-quoting discipline, the jj-envelope step ordering, the return-contract completeness, and the escape-hatch coverage. AC ratifies the pattern or returns refinements.
- *Subsequent cycles*: WO dispatches direct (no per-priming review). Surface to AC at group boundaries (logical clusters of related commits).
- *Recalibration triggers*: subagent return reveals a structural problem with the dispatch template (e.g., return contract missing a load-bearing field, escape-hatch failed to catch an ambiguity case). WO surfaces the issue to AC; pattern is re-calibrated; subsequent dispatches use the revised template.

The first-cycle critique is not optional. Skipping it loses the AC's adversarial check on dispatch-template correctness, which compounds across the remaining commits.

## PR safety variants

GitHub's immutability of PR descriptions creates safety considerations.
Two variants of PR safety protocol are recognized; user-opt-out is supported.

- *Default: title-plus-body-as-comment.* The PR title carries the change-summary load-bearing text (user-reviewed and locked). PR body is left empty at creation; the substantive description is posted as the first comment on the PR. Rationale: comment edit history is preserved and the comment is mutable; PR description edits silently overwrite history.
- *Opt-out: title-only-no-body.* User directs that no body or comment is to be applied. The title alone carries all change context. Title length may exceed the 70-char convention; user supersession applies.

Both variants require human authorization at the Phase-4 gate (AC routes to user; user authorizes title text and bookmark name before push). The variant choice is recorded in the AC-to-master surface that authorizes the PR cycle.

## Observation-log path convention

Each role maintains a running observation log throughout its lifetime.
Path convention:

- *Primary*: `${CLAUDE_JOB_DIR}/observations/<role>.md` where `<role>` is one of `master-orchestrator`, `<repo>-<stream>-ac`, or `<repo>-<stream>-wo`
- *Fallback* (no `CLAUDE_JOB_DIR` set or no job context): `~/.claude/jobs/manual-handoff/observations/<role>.md`

Logs are append-only running narrative: friction points, parameterization candidates, calibration data, decisions, unexpected state.
Logs feed the per-role `/session-checkpoint` and the master's `/meta-orchestrator-checkpoint` synthesis.

## Stream-completion plus main-advance handling

Each stream produces an independent jj chain.
Tier-2 elevations may fire as streams complete, independently of each other.

Default for non-conflicting streams: independent merges as ready.
The fast-forward-only merge policy plus jj's auto-rebase handles late streams cleanly — when stream-X merges to main, stream-Y's tier-1 chain auto-rebases onto the advanced main on the next jj operation.

Master sequences when streams conflict.
Detection trigger: when a stream's tier-2 elevation candidate fails clean rebase onto current main (jj rebase produces conflicts the WO cannot auto-resolve from local state).

Master response on conflict detection:

1. Halt the conflicting stream's elevation
2. Surface to user with: which streams are involved, what the conflict is about, recommended sequencing (merge order)
3. On user authorization, merge streams in the user-chosen order; later streams rebase between merges

Streams that completed and merged before conflict detection are not rolled back. Only the conflicting elevation is halted pending sequencing.
