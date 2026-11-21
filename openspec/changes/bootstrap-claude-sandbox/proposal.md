---
linear_story_id: CAM-118
linear_story_identifier: CAM-118
linear_story_title: "Bootstrap Claude Code cloud sessions from vanixiets"
linear_story_url: https://linear.app/cameronraysmith/issue/CAM-118/bootstrap-claude-code-cloud-sessions-from-vanixiets
linear_story_state: Todo
linear_team: CAM
linear_project: pi-agent-environment
last_synced_state: Todo
last_synced_at: "2026-11-21T19:54:50Z"
review_round: 0
max_review_rounds: 3
attempt_log:
  - { at: "2026-11-21T19:54:50Z", transition: "Backlog->Todo", outcome: "posted", note: "Issue CAM-118 created in Todo in project d7d743a19249 (Agent environment), team CAM, description seeded from proposal.md, no labels; binding comment posted; state and project confirmed by read-only view" }
  - { at: "2026-11-21T20:05:02Z", transition: "Todo (description sync)", outcome: "posted", note: "Description refreshed after the operator decided D1–D5; Linear deliverable no longer pending" }
---

## Why

Claude Code cloud sessions (claude.ai/code, on Anthropic-hosted environments) start without the operator's context, skills or tools, so every cloud session works below the standard of a local one.
Probes on 2026-11-21 showed the platform honours context and skills that the environment's setup step installs, caches that setup for later sessions, and lets a cloud session drive fresh sessions and read their results.
The repository already generates the context, composes the skills and packages the tools for its other hosts, so one pinned line can bring the same agent environment to cloud sessions without a second copy of any of it.

## What Changes

**Agent environment in cloud sessions**
- From: a cloud session starts with no user context, no composed skills, none of the command-line tools the skills call, and no repository context unless the repository commits it.
- To: a cloud session started on the operator's cloud environment has the user context, the skill corpus and the skills' required tools from its first prompt, and each attached repository's own context.
- Reason: cloud sessions should follow the same instructions and have the same skills as local sessions.
- Impact: non-breaking; affects only cloud environments whose setup step names this repository.

**Environment defined by one pinned line**
- From: the environment's setup script is hand-written shell edited in the claude.ai settings.
- To: the setup script is one line naming one revision of this repository; everything else is defined here and updated by changing that revision.
- Reason: the environment is reviewed, versioned and reproducible like the rest of the fleet.
- Impact: non-breaking; each update costs the operator one approval.

**A setup step that never blocks a session**
- From: a failing setup step leaves the session unable to start, with no way to recover it.
- To: the bootstrap degrades and reports instead of failing, so a session always starts.
- Reason: a probe showed a failed setup is fatal to the session.
- Impact: non-breaking.

**Linear in cloud sessions**
- From: cloud sessions cannot use the Linear skills.
- To: a credential scoped to the Linear workspace keys alone, decided by the operator on 2026-11-21, lets the Linear skills run; its exposure is recorded and it can be revoked on its own.
- Reason: the Linear-bound OpenSpec workflow is part of the operator's normal work.
- Impact: security-sensitive; the operator decided it explicitly, and the key it uses is readable by everything in a cloud session.

## Capabilities

### New Capabilities
- `claude-sandbox-bootstrap` (behavioral): what a cloud session started on the operator's cloud environment has from its first prompt, how the environment is defined and updated, and the bounds on the setup step (never blocking, idempotent, additive, secret-free, reporting).

### Modified Capabilities
- `world-assumptions` (world): adds the cloud-platform facts measured by the 2026-11-21 probes as indicative assumptions with their evidence and violation conditions, and adds the designation rows for the cloud-session vocabulary the new capability uses.

No interface capability is added yet.
The interface's shared phenomena (where the required tools appear to the agent's shell, whether a setup-installed session hook runs) are what probe P4 measures, so the interface capability is added once P4 has run.

## Impact

- New home configuration and a shared sandbox aggregate factored from the `ubuntu` profile (D1), under `modules/home/`.
- A bootstrap sub-flake under `bootstrap/claude-sandbox/` and one CI check that builds and caches the profile's activation package (D2).
- A SessionStart hook for the repository tier (D3), a change to `modules/home/ai/claude-code/hooks.nix` (D4), and a scoped sops file, age recipient and `.sops.yaml` rule (D5).
- The operator's cloud environment `nix-sandbox-test`, and later the default environment, whose setup script becomes the one pinned line, whose variables gain `SOPS_AGE_KEY`, and whose allowed hosts gain `api.linear.app`.
- Existing hosts: `ubuntu@x86_64-linux` imports the factored aggregate with unchanged behaviour; D4 changes every Claude Code host's hook commands from bare names to store paths.
