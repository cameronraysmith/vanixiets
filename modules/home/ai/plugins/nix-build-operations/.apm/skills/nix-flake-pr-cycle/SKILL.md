---
name: nix-flake-pr-cycle
description: >
  Operational workflow for flake-bearing repositories — enumerate flake checks for the current platform, probe targeted slices via `nix eval` and `nix build .#checks.<name>`, run `just check-fast` with logged output, create a draft pull request in canonical form, monitor buildbot, mark ready, and optionally trigger Mergify auto-merge. Phase 1 (enumerate and probe) is a legitimate stand-alone invocation; the later phases compose into the full validate-to-merge cycle. Exercises the closure operator described in `preferences-compositional-continuous-verification`. Load when validating a flake before push, opening a PR, monitoring buildbot, debugging a failed CI check, or auditing flake-check coverage.
---

# Nix flake PR cycle

## Framing

This skill is the agent operationalizing the CCV closure operator on the local flake.
Every phase below executes a slice of `nix flake check` against pinned inputs and propagates the result through bookmark, push, draft PR, buildbot monitor, ready, and Mergify.
Phase 1 (enumerate and probe) is a legitimate stop-point on its own — an audit-only invocation that asks "does the current check set cover everything relevant in this repository?" without intending to push.
The later phases compose into the full validate-to-merge cycle when the intent is integration.
For the theoretical anchor — operating-envelope-plus-regulator pairs composing into a single closure operator over the build graph — see `preferences-compositional-continuous-verification`.

The workflow's structure mirrors the closure operator's structure: enumeration corresponds to surveying the regulator suite, the targeted probe and the parallel local check correspond to exercising the operator on `currentSystem`, push and PR creation hand the same operator off to buildbot-nix for the fleet-wide evaluation, and Mergify's fast-forward integration is the convergence step that pins the closure result onto `main`.
Treating the phases as separable invocations rather than a monolithic recipe is deliberate; the agent may legitimately enter at any phase given the right state, and the phase numbering reflects the natural order rather than a rigid sequence.

## Phase 1 — enumerate and probe

Enumeration serves a tactical purpose (find the slice to probe for the current change) and a strategic purpose (audit whether the check set actually covers the artifacts in the repository).
The canonical source for these commands is `preferences-compositional-continuous-verification`; this skill is the operational instance.

```bash
nix eval --json ".#checks.$(nix eval --impure --raw --expr 'builtins.currentSystem')" --apply builtins.attrNames | jaq -r '.[]' | wc -l
nix eval --json ".#checks.$(nix eval --impure --raw --expr 'builtins.currentSystem')" --apply builtins.attrNames | jaq -r '.[]'
```

Once the slice of interest is identified, exercise it directly without paying the cost of the full check matrix.

```bash
nix eval ".#checks.$(nix eval --impure --raw --expr 'builtins.currentSystem').<name>"
nix build ".#checks.$(nix eval --impure --raw --expr 'builtins.currentSystem').<name>" -L --show-trace
```

At this phase the agent answers two audit questions in addition to whatever tactical probe motivated the enumeration.
First, does the current check set cover everything relevant in the repository, or are unchecked components leaking?
Second, do existing checks include observability-interaction verification for each artifact's check set?

Enumeration as written covers `currentSystem` only; buildbot-nix in CI exercises the multi-platform `.#checks` attrset and is the authority for fleet coverage.
Auditing fleet coverage from a single workstation requires either dispatching `nix eval` against each declared system in the flake's `systems` list or reading the buildbot configuration directly; `preferences-nix-checks-architecture` documents the multi-system audit form.

VM-based (`nixosTest`) and nspawn-container check kinds may fail at `nix eval` or `nix build` locally when the workstation's nix daemon lacks the `kvm` and `nixos-test` sandbox features.
Such failures during Phase 1 probing are worker-capability gaps in the local environment, not check-set gaps in the flake — the same attribute will evaluate and build correctly on properly-configured buildbot workers (see `preferences-nix-ci-cd-integration` §"Pipeline architecture for multi-system repositories" on worker-capability heterogeneity).
Record the gap as an environmental note rather than a finding against the regulator.

Phase 1 invocations terminate here when the intent is audit-only — no push, no PR, no monitor.
The output of the audit is typically a beads issue (or update to an existing issue) describing the unchecked artifact and the regulator that needs to exist, rather than an immediate code change.
Per the no-leak principle in `preferences-compositional-continuous-verification`, an artifact discovered to be unchecked is a structural obligation toward traceability — wire the regulator in the same commit that touches the artifact, or open an issue when wiring is out of scope for the current session.

## Phase 2 — full local validation

`just check-fast` runs `nix-fast-build` over `.#checks.<currentSystem>` in parallel under the local content-addressed cache, with `--eval-workers 4` to throttle SQLite eval-cache contention.
This is the agent-side closure-operator invocation; a local pass against pinned inputs is a CI pass against the same inputs by hash equality.

Pipe through tee so subsequent failure investigation has structured evidence on disk.

```bash
mkdir -p logs
just check-fast 2>&1 | tee logs/check-fast-$(date +%Y%m%dT%H%M%S).log
```

The sibling `just check` recipe runs `nix flake check -L --show-trace` sequentially and is the slower, verbose alternative.
Prefer it when a single-derivation failure under `check-fast` is obscured by parallel buffering and the linear trace order matters more than wall-clock.

On failure, drop to `nix build .#checks.<name> -L --show-trace` for the failing slice in isolation, then dispatch a surgical-search subagent with the log as context for root-cause analysis and a minimal-fix proposal.
The single-slice rebuild with `-L --show-trace` is also the right form for capturing a clean trace for the issue tracker when the failure cause is non-obvious from the parallel `check-fast` output.
The `logs/` directory is already gitignored at the repo root, so failure logs persist on disk without polluting tracked state.

The relationship between `just check-fast` and `nix flake check` is one of execution strategy rather than coverage: both evaluate the same `.#checks.<currentSystem>` attrset against the same pinned inputs and produce the same pass-or-fail decision modulo parallel scheduling order.
Treat them as interchangeable for the closure-operator semantics and choose between them based on the diagnostic question being asked.

The closure operator is invariant under the position of `@` in the local change graph: the CCV property in `preferences-compositional-continuous-verification` §"What this means for an agent session" rests on hash equality of the content-addressed graph, not on which commit happens to be checked out as `@`.
`just check-fast` may therefore be run on any commit whose content-addressed closure matches what buildbot will see — the wip `@` of a development join, the linearized aggregate tip after Phase 4 of `diamond-workflow.md`, or any sealed chain commit in between — and the result is the same.
This is load-bearing for the diamond workflow: local validation on the development join wip-`@` is closure-equal to local validation on the post-linearization aggregate, so the agent may choose either as the local gate before push without affecting the integration-time decision.

## Phase 3 — bookmark and push

This repository runs colocated jj alongside git; bookmarks are the jj equivalent of git branches and the unit pushed to the GitHub remote.
Create a bookmark on the parent of `@` (the working-copy commit is conventionally empty) or advance an existing bookmark to track the most recent sealed change.

```bash
jj bookmark create -r @- <bookmark-name>
# or, advancing an existing bookmark:
jj bookmark set <bookmark-name> -r @-
```

If `main@origin` has advanced since the chain diverged, rebase first so the eventual merge is a true fast-forward against the remote tip.

```bash
jj git fetch
jj rebase -s <chain-base> -d main@origin
```

Push the bookmark to the GitHub remote.

```bash
jj git push -b <bookmark-name>
```

Pushes to non-default refs are auto-permitted by the `gate-dangerous-commands` hook with an ntfy NOTICE; pushes to `main` remain gated and require explicit confirmation.
The NOTICE is informational rather than blocking — it surfaces the push to the user's notification stream so a foreground operator can intervene if the push was accidental, while permitting routine bookmark publication without interactive prompts.

## Phase 4 — draft pull request creation

The `gate-dangerous-commands` hook's whitelist matches the canonical creation form exactly; deviating from this shape forces an interactive permission prompt.

```bash
gh pr create -d -a "@me" -B main -H <bookmark-name> -t "<conventional-commits title>" -b ""
```

The flags are `-d` for draft, `-a "@me"` to self-assign, `-B main` for the base branch, `-H <bookmark>` for the head, and `-b ""` to leave the body empty.
Per the user's PR creation protocol — referenced in full via the GitHub PR safety section of `preferences-git-version-control` — the immutable title and body fields stay generic at creation while richer description goes in as a post-creation comment.

```bash
gh pr comment <N> --body "<markdown description>"
```

Title and description in the immutable fields cannot be edited after creation, so the discipline is generic-at-creation, detailed-in-comment.
The conventional-commits title is the one mutable surface that survives into the merged-commit subject when Mergify uses `fast-forward` merge, so it is worth getting right at creation time even though `gh pr edit --title` remains available until merge.

For multi-chain epic integrations (a development join with two or more active chains), Phase 4 expands into the N+1 stacked-base submission pattern documented in `~/.claude/skills/jj-version-control/diamond-workflow.md` §"Phase 4: serialize (integrate)".
The `jj-linearize-join` sibling tool performs the diamond-workflow → linearized-chain transformation; the `jj-stack-submit` sibling tool performs the Phase A submission (push N+1 bookmarks, create N stacked-base chain PRs + 1 aggregate PR, optionally backlink and mark ready).
The aggregate PR is the merge gate, and Phases 5–7 of this skill apply to the aggregate PR; the chain PRs render the dependency structure on the forge and auto-close when GitHub observes their head commits reachable from `main`.

## Phase 5 — buildbot monitor

The set of buildbot checks should be derived dynamically from the PR rather than hardcoded; the prefix `^buildbot/` is stable but the suffixes evolve with the CI configuration.

```bash
gh pr checks <N> --json name,link,state | jaq -r '.[] | select(.name | test("^buildbot/")) | "\(.state)\t\(.name)\t\(.link)"'
```

Poll until every `^buildbot/` check reaches a terminal state (SUCCESS or FAILURE); typical wall-time is 3–6 minutes.
Use the `Bash` tool with `run_in_background: true` for the poll loop so it does not block other coordination work.

On failure, extract `builder_id` and `build_number` from the `.link` field — buildbot URLs follow the shape `https://buildbot.scientistexperience.net/#/builders/<builder_id>/builds/<build_number>` — and download the build log via `buildbot-logs`.

```bash
buildbot-logs <builder_id> <build_number> > logs/buildbot-<builder_id>-<build_number>.log
```

The `buildbot-logs` tool is defined locally at `modules/home/tools/commands/dev/buildbot-logs.nix` (interpolation wrapper around the sidecar `buildbot-logs.sh`), if its behavior needs auditing.
Dispatch a surgical-search subagent with the failure log as context for root-cause analysis and a minimal-fix proposal, then return to Phase 1 to revalidate the fix locally before re-pushing.

The authoritative gate identity lives in `.github/mergify.yml`'s `required_checks`: currently `buildbot/nix-eval`, `buildbot/nix-build`, and `buildbot/nix-effects`.
The dynamic prefix-match query above answers "are all buildbot checks terminal" for the monitor; `required_checks` answers "which checks does Mergify gate the merge on" for the integration decision.
Both are reference-worthy and should be cross-checked when the sets diverge — a buildbot check reporting terminal SUCCESS that is not listed in `required_checks` is informational only, and a check listed in `required_checks` that the prefix-match query never enumerates is a configuration drift worth surfacing.

A subagent dispatch for buildbot-failure investigation should bind to the foreground so the orchestrator can sequence remediation against the monitor; see `feedback_subagent-foreground-probes` in user-level memory for the convention.

## Phase 6 — mark ready and optional Mergify

When every buildbot check terminates SUCCESS, mark the PR ready for review.

```bash
gh pr ready <N>
```

For cameronraysmith-authored PRs, the `author-approved` label invokes Mergify auto-approval and the merge queue.

```bash
gh pr edit <N> --add-label author-approved
```

Per `.github/mergify.yml`, the auto-approve rule is gated on `author=cameronraysmith` — for any other author the label has no auto-approve effect and a human review is required before the queue admits the PR.
State this caveat plainly when proposing the label to a third-party PR.
The `default` queue's other conditions (no `work-in-progress` label, draft cleared, no merge conflict, all `required_checks` green, at least one approving review) are independent of the label and apply to every PR regardless of author.

## Phase 7 — converge

Mergify's `default` queue uses `merge_method: fast-forward`, so the merge is a true fast-forward against `main` with no merge commit.
The `bot-updates` queue uses `merge_method: rebase` for Renovate and flake-update batches, where preserving the original commit SHA is less important than tight batching.

Poll merge completion via the PR's JSON view.

```bash
gh pr view <N> --json mergedAt,state,closed
```

The `merged` field is not a valid JSON field on this view — use `mergedAt` (a timestamp present iff the PR was merged), `state` (MERGED, CLOSED, or OPEN), and `closed` (boolean).
On merge, fetch the new remote tip locally and rebase any in-flight chain onto it.

```bash
jj git fetch
jj rebase -s <next-chain-base> -d main@origin
```

This advances `main@origin` in the local view and keeps the next bookmark stack mergeable as a fast-forward when its turn arrives.
If Mergify's `max_parallel_checks: 1` setting forces serialization (the configured constraint as of writing), the queue admits one PR at a time and the rebase-against-new-tip step happens between each merge rather than once at the end of the session.

## Evidence convention

The `logs/` directory at the repo root is the canonical evidence directory and is already gitignored.
On failure, keep `logs/check-fast-*.log` and `logs/buildbot-*-*.log` for the duration of the investigation so subagents have stable input.
On success, no per-success file is retained — the merged commit on `main` is the artifact, and the trail stays lean.
The naming convention uses ISO-8601 timestamps for local check runs and `builder_id`-`build_number` for buildbot fetches so the filename itself answers "which run is this?" without requiring the contents to be opened.
Subagents tasked with failure analysis should be pointed at the specific log file path rather than at the `logs/` directory in general, both to avoid loading unrelated history into their context and to make the evidence chain explicit for later session checkpoints.

## NOTICEs at meaningful transitions

Use `ntfy-send "<message>" [<topic>]` to push a notification at meaningful transitions; the default topic is the local hostname (`hostname -s`).
Worthwhile transitions are bookmark pushed, PR draft created (include the PR URL), buildbot terminal (success or failure), PR marked ready, and PR merged.
Keep messages short — repo name plus state plus PR number is sufficient.

```bash
ntfy-send "vanixiets PR #<N> draft created — <url>"
ntfy-send "vanixiets PR #<N> buildbot SUCCESS"
ntfy-send "vanixiets PR #<N> merged"
```

The wrapper script lives at `modules/home/tools/commands/system/ntfy-send.sh` and uses `/usr/bin/curl` on Darwin to satisfy endpoint-security restrictions on ad-hoc-signed Nix store binaries; the topic argument is positional and defaults to the local hostname so the same script works unmodified across the fleet.
Suppress NOTICEs during dense local iteration (rapid push-monitor-fix cycles) and re-enable them once the cadence drops to integration-significant transitions, so the notification stream stays signal-rich.

## Caveats and known scope

`just check-fast` enumerates `currentSystem` only; multi-platform coverage across the fleet is buildbot's domain in CI and is not exercised by the local closure-operator invocation.
Mergify's `author-approved` label auto-approves only for `author=cameronraysmith`; for other authors the label is inert with respect to auto-approval.
Skill content (this SKILL.md) activates via `home-manager switch`; the working-tree path is canonical during authoring sessions, but the symlinked store path that agents read at runtime lags by one switch cycle.
The `gate-dangerous-commands` hook auto-permits non-default-ref pushes and the canonical `gh pr create -d ... -b ""` triad; updates to the hook itself similarly lag by one switch cycle.

The phase numbering is procedural rather than rigid — entering at Phase 3 with an already-validated chain is legitimate, as is iterating Phase 1–2 multiple times before any push.
The numbering reflects the natural order when starting from a fresh chain and pursuing integration; it is not a sequence the agent is obligated to execute monolithically.
Skipping Phase 2 (the full local validation) before push is a defensible shortcut only when the change is small enough that the targeted Phase 1 probe constitutes adequate evidence; for anything larger, the full local pass under `just check-fast` is the cheapest insurance against a buildbot round-trip on a trivially preventable failure.

## Cross-references

- `preferences-compositional-continuous-verification` — theoretical anchor; canonical source for the enumeration commands
- `preferences-nix-checks-architecture` — flake-side check taxonomy and meta-check derivation patterns; §"Choosing among integration regulators" for the three-way process-compose / nspawn / full VM regulator-kind framing referenced in Phase 1 worker-capability gap diagnosis
- `preferences-nix-ci-cd-integration` — buildbot-nix as the closure-operator executor in CI; effect system; migration patterns
- `preferences-validation-assurance` — severity, evidence quality, confidence promotion chain
- `preferences-git-version-control` — GitHub PR creation safety, branch workflow, working branch isolation
- `jj-version-control/diamond-workflow.md` — multi-chain epic integration via N+1 stacked-base + aggregate PR pattern; `jj-linearize-join` and `jj-stack-submit` sibling tools
- `session-orient` — session entry; reference for procedural-skill tone
