# Brainstorm: Omnigent login grant lifetime and its expiry alert

Captured 2026-11-14 from the investigation of omnigent 0.22.0, the version pinned in this repository, and the operator's decisions relayed by the orchestrator.

## Background

On 2026-10-15 every Omnigent worker in the fleet stopped: each refresh was refused with "stored login session … has EXPIRED", magnetite's units restart-looped about 3,200 times, and stibnite's launchd job exited 78 (`docs/notes/development/incidents/2026-10-15-omnigent-host-restart-loop.md`).
The cause is the server's absolute grant lifetime.
`/oauth/token` returns `expired_token` once `now - grant.approved_at >= _grant_max_lifetime` (`omnigent/server/routes/device_auth.py:522-525` in 0.22.0).
The lifetime defaults to 30 days (`device_auth.py:123`), is overridable in whole days by `OMNIGENT_GRANT_MAX_LIFETIME_DAYS` (`:127-156`), and is read once when the token router is mounted (`:408`).
`modules/nixos/omnigent.nix` sets no override, so the 30-day default applies.
The workers logged in again on 2026-11-14, so their grants run out on 2026-12-14 unless something changes.
The incident's detection gap is still open: nothing warns before a login reaches its lifetime.

## Q1: Can a worker hold a credential that does not expire and still act as its owner?

No, not in 0.22.0.
`client_credentials` authenticates one principal per server, not one per owner, and launch tokens exist only for managed sandboxes.
A login grant is the only credential that carries an owner's identity to a worker.

## Q2: How long should a login grant last?

The operator decided on 90 days.
The trade-off is that the lifetime is server-wide: it applies to every login grant, browser and CLI logins included, not only to workers.
First-party login grants do not rotate their refresh token (`device_auth.py:529-545`), so a leaked worker token stays usable for up to 90 days instead of 30.
`/oauth/revoke` revokes a grant when its refresh token or an access token naming it is presented (`device_auth.py:582-610`).

## Q3: What should the alert watch?

The decision: one series per owner, holding the earliest expiry of that owner's redeemed CLI login grants.
That is `min(approved_at) + lifetime` over `device_grants` rows with `client_id = 'omnigent-cli'` and status redeemed.
The server cannot tell which grant a worker holds, because a grant records no use, so the earliest one fails toward alerting.
A superseded grant keeps the alert firing until the server purges it, which it does once the grant passes the lifetime (`omnigent/server/device_grant_store.py:586-640`, at most every 300 s on any refresh).
The owner is stored as its alias from `flake.lib.otelCollectorSchema.ownerAliases`, as the worker units are, so no address becomes a label value.
The rule `OmnigentLoginGrantExpiring` warns when fewer than 14 days are left.

## Q4: Should a missing series alert?

Yes.
The expiry series is the only warning before workers stop, so losing it silently would reopen the incident's detection gap.
The rule declares a presence selector expected from the host running the Omnigent server, and `RuleSignalMissing` reports a lost series after 30 min.
A server with no redeemed CLI grant at all also raises it, which is correct, because then no worker can run.

## Q5: How does the series reach the telemetry store, and as whom?

The collector on the server's host already reads nixbot's PostgreSQL with `sqlquery` receivers as the peer-authenticated role `opentelemetry-collector` (`modules/nixos/devloop-collection.nix`).
The same pattern applies here: a `sqlquery` receiver joins the collector's `metrics/host` pipeline, whose `resource/agent` processor stamps `host.name` and the `fleet` database.
The role reads only `device_grants(user_id, client_id, status, approved_at)` through a column grant, so it cannot read token hashes, device codes or grant ids.

## Q6: Does raising the lifetime revive superseded grants?

Yes, unless the deploy waits.
magnetite holds two superseded grants of owner-1, approved on 2026-10-17 and 2026-10-25.
Under 90 days they would become refreshable again until 2027-01-15 and 2027-01-23.
omnigent 0.22.0 has no way to revoke a grant without presenting its token: there is no admin route, and the 0.22.0 CLI never calls `/oauth/revoke`.
The superseded grants' tokens were overwritten when the workers logged in again.
The supported path that needs no token is the server's own purge under the 30-day lifetime still in force.
The 2026-10-17 grant is purged after 2026-11-16 19:24Z and the 2026-10-25 grant after 2026-11-24 19:02Z, on the next refresh, and the workers refresh hourly because access tokens last 3,600 s (`device_auth.py:118`).
The operator approved gating magnetite's deploy on a read-only query showing no redeemed CLI grant older than 30 days at deploy time.
The change may merge before the gate is met.
