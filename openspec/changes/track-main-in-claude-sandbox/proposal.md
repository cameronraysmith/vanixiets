---
linear_story_id: CAM-119
linear_story_identifier: CAM-119
linear_story_title: "Track main in Claude Code cloud sessions"
linear_story_url: https://linear.app/cameronraysmith/issue/CAM-119/track-main-in-claude-code-cloud-sessions
linear_story_state: Todo
linear_team: CAM
linear_project: pi-agent-environment
last_synced_state: Todo
last_synced_at: "2026-11-22T01:07:00Z"
review_round: 0
max_review_rounds: 3
attempt_log:
  - { at: "2026-11-22T01:07:00Z", transition: "Backlog->Todo", outcome: "posted", note: "Issue CAM-119 created in Todo in project d7d743a19249 (Agent environment), team CAM, description seeded from proposal.md, no labels; binding comment posted; state and project confirmed by read-only view" }
---

## Why

Claude Code cloud sessions get the operator's agent environment from one closure pinned in the cloud environment's setup step (`bootstrap-claude-sandbox`, CAM-118).
Every profile change then needs a regenerated setup step and an approval card, and a pinned closure must be renewed every 30 days or the cache drops it.
A probe on 2026-11-22 showed a cloud session can evaluate `main` itself in 46 s with every input source served from the fleet's cache, so the environment can follow `main` with a setup step whose text never changes.

## What Changes

**Follow `main` by default**
- From: the setup step names one closure; profile changes reach cloud sessions only after the operator regenerates and swaps the setup step.
- To: the setup box holds three fixed lines that run the flake app `claude-sandbox-setup` from `main`, which follows the newest commit on `main` whose closure the fleet's cache already holds, walking back at most 5 commits; a store path argument pins one closure.
- Reason: profile changes reach cloud sessions without a per-change approval card, and the monthly renewal is no longer needed while following `main`.
- Impact: non-breaking; one approval card per environment to switch, and a pin stays available.

**Know when a session is behind**
- From: nothing tells a session or the operator that its environment is older than `main`.
- To: each session start logs which commit its closure came from, how far behind `main` that was when the snapshot was made, and whether `main` has moved on since, without changing anything.
- Reason: a snapshot lives about a week; the operator needs to see when to refresh it.
- Impact: non-breaking.

**Keep every input source in the cache**
- From: input sources reach the cache as a side effect of a check added on 2026-11-22, with nothing stating why it matters.
- To: every lock change keeps all input sources in the fleet's cache, stated as a requirement, because a cloud session cannot fetch them from GitHub.
- Reason: a missing source makes the environment fall back to an older commit, or to no profile.
- Impact: non-breaking; makes an existing check load-bearing.

## Capabilities

### New Capabilities

None.

### Modified Capabilities
- `claude-sandbox-bootstrap` (behavioral): `One closure defines the environment` now follows `main`'s newest published closure by default and can be pinned; adds a staleness notice and the requirement that every input source stays in the cache.
- `claude-sandbox-interface` (interface): the pinned-path and script-limit requirements are replaced by R1–R7 (the closure follows `main`, a pin as an argument, a fixed three-line box, the logic as a flake app whose every command comes from the flake, setup never failing the session, the profile's closure substituted, never built); adds the bounded walk over `main`'s first-parent history, its marker line, the read-only staleness hook, and the input-sources check.
  Trust boundary: these properties guarantee what the setup step evaluates, fetches and runs, and what the hook reads; they do not guarantee that any of the 5 newest commits is published, that the platform rebuilds the snapshot when documented, or that activation succeeds.
- `world-assumptions` (world): adds the probe's measurement of evaluating `main` from the cache, the platform's documented snapshot expiry (not yet measured), and how the harness applies its own git configuration.

## Impact

- `modules/apps/claude-sandbox-setup.{nix,sh}`: the setup app, replacing `modules/apps/claude-sandbox-setup-script.nix` (the generator of pasted scripts, removed with `flake.lib.claudeSandboxSetupScript`).
- `modules/checks/claude-sandbox-setup-script.nix`: checks the app and the documented bootstrap against `lib/caches.nix`.
- `modules/home/users/claude-sandbox/default.nix`: a staleness SessionStart hook.
- `modules/checks/flake-input-sources.nix` (#4127) becomes load-bearing; no code change.
- The cloud environments `nix-sandbox-test`, then Default, switched to a pasted track-mode script (one approval card each); Default then takes the fixed bootstrap (one approval card), and `nix-sandbox-test` is deleted.
