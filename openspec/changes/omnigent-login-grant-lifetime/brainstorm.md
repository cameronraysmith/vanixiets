# Brainstorm: Omnigent login grant lifetime

Captured 2026-11-14 from the investigation of omnigent 0.22.0, the version pinned in this repository, and the operator's decisions relayed by the orchestrator.

## Background

On 2026-10-15 every Omnigent worker in the fleet stopped: each refresh was refused, and the hosts failed with "stored login session … has EXPIRED", magnetite's units restart-looping about 3,200 times and stibnite's launchd job exiting 78 (`docs/notes/development/incidents/2026-10-15-omnigent-host-restart-loop.md`).
The cause is the server's absolute grant lifetime.
`/oauth/token` returns `expired_token` once `now - grant.approved_at >= _grant_max_lifetime` (`omnigent/server/routes/device_auth.py:522-525` in 0.22.0).
The lifetime defaults to 30 days (`device_auth.py:123`), is overridable in whole days by `OMNIGENT_GRANT_MAX_LIFETIME_DAYS` (`:127-156`), and is read once when the token router is mounted (`:408`).
`modules/nixos/omnigent.nix` set no override, so the 30-day default applied.
The workers logged in again on 2026-11-14, so their grants run out on 2026-12-14 unless the lifetime changes.

## Q1: Can a worker hold a credential that does not expire and still act as its owner?

No, not in 0.22.0.
`client_credentials` authenticates one principal per server, not one per owner, and launch tokens exist only for managed sandboxes.
A login grant is the only credential that carries an owner's identity to a worker.

## Q2: How long should a login grant last?

The operator decided on 90 days.
The lifetime is server-wide, so it also applies to browser and CLI logins, not only to workers.
First-party login grants do not rotate their refresh token (`device_auth.py:529-545`), so a leaked worker token stays usable for up to 90 days instead of 30.
`/oauth/revoke` revokes a grant when its refresh token or an access token naming it is presented (`device_auth.py:582-610`).

## Q3: Does raising the lifetime revive superseded grants?

Yes, unless they are purged first.
magnetite holds two superseded grants of the first owner, approved on 2026-10-17 and 2026-10-25, which under 90 days would become refreshable again until 2027-01-15 and 2027-01-23.
omnigent 0.22.0 cannot revoke a grant without its token: there is no admin route, the 0.22.0 CLI never calls `/oauth/revoke`, and the superseded grants' tokens were overwritten when the workers logged in again.
The supported path that needs no token is the server's own purge under the 30-day lifetime still in force (`omnigent/server/device_grant_store.py:586-640`), which runs at most every 300 s on any refresh (`device_auth.py:288`), and the workers refresh hourly because access tokens last 3,600 s (`:118`).
The operator first approved gating magnetite's deploy on the 30-day purge, which would have waited until after 2026-11-24 19:02Z.
On 2026-11-14 the operator chose instead a temporary 7-day lifetime and one refresh request with a placeholder token, which triggers the same purge at once, because the refresh endpoint purges before it checks the token (`device_auth.py:482-501`).

## Q4: Should the fleet warn before a grant runs out?

An early-warning alert was built and then shelved by the operator's decision, unchanged, as commit `cc0370f3` on branch `omnigent-grant-alert-shelved`.
It read the earliest expiry per owner from `device_grants` through the collector and warned 14 days ahead.
It was shelved because it couples the collector to omnigent's internal `device_grants` schema, needs its own database role and column grants, and would fire on superseded grants until the server purges them.
The exit-78 `SystemdUnitFailed` notice of #3863 already gives one clear notice at expiry.
