## Why

On 2026-10-15 every Omnigent worker stopped at once: the server refused each refresh with `expired_token`, and the hosts failed with "stored login session … has EXPIRED", restart-looping about 3,200 times on magnetite and exiting 78 on stibnite (`docs/notes/development/incidents/2026-10-15-omnigent-host-restart-loop.md`).
omnigent 0.22.0 refuses to refresh a grant once `now - approved_at` reaches its absolute lifetime (`omnigent/server/routes/device_auth.py:522-525`), which defaults to 30 days (`:123`) and is overridden only by `OMNIGENT_GRANT_MAX_LIFETIME_DAYS`, read once when the token router is mounted (`:127-156`, `:408`).
`modules/nixos/omnigent.nix` sets no override, and nothing warns before a grant runs out.
The workers logged in again on 2026-11-14, so they stop again on 2026-12-14 unless the lifetime changes.
omnigent 0.22.0 offers no machine credential that keeps an owner's identity: `client_credentials` is one principal per server, and launch tokens exist only for managed sandboxes.
So a worker must keep holding a login grant, and the fleet must renew each grant before it runs out.

## What Changes

Decisions tagged `D<n>` are developed in `design.md`; the operator decided D1 and approved D3 and D5 on 2026-11-14.

- The Omnigent server runs with `OMNIGENT_GRANT_MAX_LIFETIME_DAYS = "90"` (D1).
- The collector on the server's host reads, every 60 s, the earliest expiry of each owner's redeemed CLI login grants from the server's database, as the peer-authenticated role `opentelemetry-collector` holding a column grant on `device_grants(user_id, client_id, status, approved_at)` only (D2, D3).
- It stores this as the series `omnigent_login_grant_expiry_timestamp_seconds`, labelled by the owner's alias.
- The alert rule `OmnigentLoginGrantExpiring`, `warning`, fires when an owner's earliest expiry is less than 14 days away and has held for 15 min (D4).
- Its presence selector is expected from the server's host, so a lost series raises `RuleSignalMissing` (D4).
- `checks.x86_64-linux.fleet-alert`'s `promtoolRehearsal` evaluates the rule with `promtool test rules` and rejects a threshold-in-days mutant.
- magnetite deploys the new lifetime only once a read-only query shows no redeemed CLI grant older than 30 days, so the server's own purge has removed every superseded grant first and the deploy revives none (D5).

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `fleet-alerting` (stratum: `behavioral`): adds `An Omnigent worker's expiring login reaches a person 14 days ahead`.
- `fleet-alerting-interface` (stratum: `interface`): adds `The Omnigent server runs with a 90-day login grant lifetime`, `The collector reads each owner's earliest login grant expiry as a column-limited role` and `OmnigentLoginGrantExpiring warns 14 days before an owner's earliest expiry`.
  Trust boundary: the server enforces the lifetime and purges aged grants; the series reports what the server's table holds, which cannot say which grant a worker holds; the alert reaches a person only through the existing alert path, and nothing here guarantees that a worker is renewed.
- `world-assumptions` (stratum: `world`): adds A105, that omnigent refuses a login grant's refresh at a lifetime fixed at server start and later purges the grant, and A106, that a login grant is revocable only by presenting its own token.
  `Grounded vocabulary for behavioral requirements` gains the row `login grant` and widens `expected host` to the server's host for the login-grant rule.

## Impact

- Changed: `modules/nixos/omnigent.nix` (the lifetime, the role, the `omnigent-pg-grants` unit and the collector receiver), `modules/nixos/fleet-alert/rules.nix` (the rule), `modules/checks/fleet-alert.nix` (the rule test and its mutant) and `modules/clan/services/omnigent/README.md` (the lifetime and the renewal cue).
- Security trade-off: the lifetime is server-wide, so every login grant, browser and CLI logins included, lives 90 days instead of 30; login grants do not rotate (`device_auth.py:529-545`), so a leaked worker refresh token stays usable up to 90 days unless revoked through `/oauth/revoke` with that token.
- New privilege: the collector's database role reads four columns of `device_grants`, which name each owner's login address and when it signed in.
- Deployment: only magnetite runs the server; its deploy waits for the purge gate, which the 2026-10-25 grant meets after 2026-11-24 19:02Z, leaving about 20 days before the 2026-11-14 grants would expire under 30 days.
- Out of scope: renewing workers automatically, the restart policy that turns an expired login into a loop, and upstream changes to omnigent.
