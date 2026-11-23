---
linear_story_id: CAM-103
linear_story_identifier: CAM-103
linear_story_title: "Raise omnigent's login grant lifetime to 90 days"
linear_story_url: https://linear.app/cameronraysmith/issue/CAM-103/raise-omnigents-login-grant-lifetime-to-90-days
linear_story_state: Todo
linear_team: CAM
linear_project: omnigent-magnetite
last_synced_state: Todo
last_synced_at: "2026-11-14T20:36:41Z"
review_round: 0
max_review_rounds: 3
attempt_log:
  - { at: "2026-11-14T20:36:41Z", transition: "Backlog->Todo", outcome: "posted", note: "Issue CAM-103 created in Todo in project 53fe2d07fd03 with description seeded from proposal.md; state, project and labels confirmed by read-only view" }
---

## Why

On 2026-10-15 every Omnigent worker stopped at once: the server refused each refresh with `expired_token`, and the hosts failed with "stored login session … has EXPIRED", restart-looping about 3,200 times on magnetite and exiting 78 on stibnite (`docs/notes/development/incidents/2026-10-15-omnigent-host-restart-loop.md`).
omnigent 0.22.0 refuses to refresh a grant once `now - approved_at` reaches its absolute lifetime (`omnigent/server/routes/device_auth.py:522-525`), which defaults to 30 days (`:123`) and is overridden only by `OMNIGENT_GRANT_MAX_LIFETIME_DAYS`, read once when the token router is mounted (`:127-156`, `:408`).
`modules/nixos/omnigent.nix` sets no override.
The workers logged in again on 2026-11-14, so they stop again on 2026-12-14 unless the lifetime changes.
omnigent 0.22.0 offers no machine credential that keeps an owner's identity, so each worker must keep holding a login grant and be renewed before it runs out.

## What Changes

Decisions tagged `D<n>` are developed in `design.md`; the operator decided D1, D2 and D3 on 2026-11-14.

- The Omnigent server runs with `OMNIGENT_GRANT_MAX_LIFETIME_DAYS = "90"` (D1).
- The superseded grants are purged first, by a temporary 7-day lifetime on magnetite that never reaches `main` and the server's own purge, so raising the lifetime revives none (D2).
- No early-warning alert is added; the one built for this change is shelved on branch `omnigent-grant-alert-shelved` (D3).

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `world-assumptions` (stratum: `world`): adds A105, that omnigent refuses a login grant's refresh at a lifetime fixed at server start and later purges the grant, on which the lifetime and the deploy gate rest, and A106, that a login grant is revocable only by presenting its own token, which is why the gate waits for the purge.

No behavioral or interface requirement changes: the change sets one configuration value of a vendored service and gates its deploy.

## Impact

- Changed: `modules/nixos/omnigent.nix` (the variable) and `modules/clan/services/omnigent/README.md` (the lifetime and the renewal cue).
- Security trade-off: the lifetime is server-wide, so every login grant, browser and CLI logins included, lives 90 days instead of 30; login grants do not rotate (`device_auth.py:529-545`), so a leaked worker refresh token stays usable up to 90 days unless revoked through `/oauth/revoke` with that token.
- Deployment: only magnetite runs the server; a temporary 7-day deploy and a read-only query precede the 90-day deploy, which follows the same day.
- The pull request waits for the gate as well: once the variable is on `main`, any magnetite deploy from `main` would apply it.
- Out of scope: an early-warning alert (shelved), renewing workers automatically, and the restart policy.
