## Context

omnigent 0.22.0, pinned here, issues each `omnigent login` a login grant in its PostgreSQL table `device_grants` with `client_id = 'omnigent-cli'`.
A worker refreshes its one-hour access token (`omnigent/server/routes/device_auth.py:118`) with the grant's refresh token, and the server refuses once `now - approved_at` reaches the lifetime (`:522-525`).
The lifetime is 30 days by default (`:123`), or `OMNIGENT_GRANT_MAX_LIFETIME_DAYS` whole days when that is a positive integer, read once at mount (`:127-156`, `:408`).
Each refresh may also purge, at most every 300 s (`:288`), every redeemed or revoked grant older than the lifetime (`omnigent/server/device_grant_store.py:586-640`).
Login grants do not rotate their refresh token (`device_auth.py:529-545`).
The only revocation is `POST /oauth/revoke` with the grant's refresh token or an access token naming it (`:582-610`); there is no admin route, and the 0.22.0 CLI never calls it.

On 2026-11-14 magnetite's table held seven redeemed CLI grants: owner-1's of 2026-10-17 and 2026-10-25, superseded, three of owner-1's of 2026-11-14, one per worker on magnetite, pyrite and stibnite, and owner-2's two of 2026-11-14, one per worker on magnetite and pyrite (`logs/streamA-query-*.log`; the worker matrix in `modules/clan/services/omnigent/README.md`).

## Goals / Non-Goals

**Goals:**
- No worker stops because its login grant aged out without a person being told 14 days ahead.
- Renewals are needed every 90 days instead of every 30.
- The collector reads no more of the server's database than the expiry needs.

**Non-Goals:**
- Renewing workers automatically, which 0.22.0 cannot do without a person signing in.
- Changing the restart policy of `omnigent-host-*` units.
- Tracking which grant each worker holds, which the server does not record.

## Decisions

### D1: The server's grant lifetime is 90 days

`systemd.services.omnigent.environment.OMNIGENT_GRANT_MAX_LIFETIME_DAYS` is `"90"`, from one Nix binding the expiry query also reads.
Boundary: vendored-versus-first-party; the lifetime is omnigent's, set through its documented override, with no patch.
Alternatives: keep 30 days with the alert only, which leaves a renewal every month for five workers; a longer lifetime, which widens the leak window further.
Trade-off: the variable is server-wide, so browser and CLI logins also live 90 days, and a leaked worker refresh token, which never rotates, stays usable up to 90 days unless revoked with that token.

### D2: The collector reads the grants with a column grant, as the existing dev-loop readers do

`modules/nixos/omnigent.nix`, when the host's collector is enabled, adds the role `opentelemetry-collector` to `services.postgresql.ensureUsers`, and the oneshot `omnigent-pg-grants`, run as `postgres` after `omnigent.service`, waits up to 300 s for the four columns and runs `GRANT SELECT ("user_id", "client_id", "status", "approved_at") ON "device_grants" TO "opentelemetry-collector"`.
The collector's DynamicUser connects over `/run/postgresql` and peer authentication admits it as that role, the pattern of `modules/nixos/devloop-collection.nix`.
The role cannot read `refresh_token_hash`, `device_code_hash`, `user_code` or `id`, which a local PostgreSQL run showed (`logs/streamA-pg-privilege-*.log`).
Alternatives: a periodic unit writing a textfile, which needs a textfile collector NixOS hosts do not run; reading as `omnigent`, which can read the token hashes.

### D3: One series per owner, holding the earliest expiry of its redeemed CLI grants

The `sqlquery/omnigent-grants` receiver runs every 60 s:
`SELECT CASE user_id WHEN <owner's login address> THEN <alias> … ELSE 'unaliased' END AS omnigent_owner, min(approved_at)::bigint + 90 × 86400 AS expires_at FROM device_grants WHERE client_id = 'omnigent-cli' AND status = 4 AND approved_at IS NOT NULL GROUP BY 1`.
Status 4 is `redeemed` (`omnigent/db/enum_codecs.py:88-94`).
The addresses come from `flake.users.<owner>.meta.email` and the aliases from `flake.lib.otelCollectorSchema.ownerAliases`, so the label carries `owner-1` rather than an address, as the worker units do (ADR-003 item 17).
The receiver joins the collector's `metrics/host` pipeline, whose `resource/agent` stamps `host.name` and `vanixiets.database = fleet`; the metric is the gauge `omnigent_login_grant_expiry_timestamp_seconds`.
The series is a timestamp rather than seconds left, so its value does not drift between collections, and the rule subtracts `time()`.
The earliest grant fails toward alerting: a superseded grant keeps the instance firing until the server purges it at the lifetime, which costs a lingering alert, never a missed one.
Alternative: the latest grant per owner, which misses a worker whose grant is older than the same owner's later login elsewhere.

### D4: The rule warns 14 days ahead, and a lost series is reported

`OmnigentLoginGrantExpiring`: `omnigent_login_grant_expiry_timestamp_seconds - time() < 1209600`, `for` 15 min, `warning`, with presence selector `omnigent_login_grant_expiry_timestamp_seconds` expected from the collecting NixOS hosts that run the server, `magnetite`.
`modules/nixos/omnigent.nix` asserts that a collecting server host is among those expected hosts and that its `metrics/host` pipeline has an exporter.
A lost series raises `RuleSignalMissing` after 30 min, because the series is the only warning before workers stop; this covers a failed grant, a schema change and a broken receiver.
`promtoolRehearsal` evaluates the rule with `promtool test rules` from the epoch: owner-1's expiry 14 days and 1 hour out is quiet at 30 min and firing at 2 h, and owner-2's, 10 days later, never fires; the mutant `grantThresholdInDays`, `< 14`, runs only the firing case and must fail it.

### D5: magnetite deploys the lifetime only after the server has purged every superseded grant

Raising the lifetime makes every grant younger than 90 days refreshable again, including owner-1's superseded grants of 2026-10-17 and 2026-10-25, which would revive until 2027-01-15 and 2027-01-23.
They cannot be revoked through a supported path, because their tokens were overwritten when the workers logged in again (A106).
Under the 30-day lifetime still in force, the server purges them itself: the first after 2026-11-16 19:24Z, the second after 2026-11-24 19:02Z, on the next refresh, and the workers refresh hourly.
The gate before the deploy is a read-only query returning 0: `SELECT count(*) FROM device_grants WHERE client_id = 'omnigent-cli' AND status = 4 AND approved_at <= extract(epoch FROM now())::bigint - 30 * 86400`.
The change merges independently; only magnetite's deploy waits.
Alternatives rejected: an `UPDATE` setting status 5, which is not omnigent's interface; deploying at once and accepting the revival.

## Risks / Trade-offs

- [A leaked worker refresh token lives up to 90 days] → whoever holds it can revoke it through `/oauth/revoke`; otherwise it lasts until the lifetime, the accepted cost of D1.
- [A superseded grant keeps the alert firing until purged] → the summary says the instance resolves at the purge; renewing every worker of the owner is still the correct response.
- [The series cannot say which of an owner's grants each worker holds] → the earliest is reported, so any grant a worker could hold expires no sooner than the series says.
- [omnigent renames `device_grants` columns or status codes in an upgrade] → the grant unit or the query fails and `RuleSignalMissing` fires; the column list and status code cite 0.22.0's source.
- [The deploy slips past 2026-12-14] → the series and the rule arrive with the same deploy, so nothing warns before it; the 2026-11-14 grants then expire under 30 days and the workers need renewal as in October, so the deploy is scheduled between 2026-11-24 19:02Z and 2026-12-14.

## Migration Plan

1. Merge the change; nothing runs it before magnetite deploys.
2. On or after 2026-11-24 19:02Z, run the gate's query read-only on magnetite; deploy only when it returns 0.
3. After the deploy, read the series from the `fleet` database and confirm the owners' expiries are their 2026-11-14 logins plus 90 days.

Rollback: deploy without `OMNIGENT_GRANT_MAX_LIFETIME_DAYS`; grants older than 30 days then stop refreshing at once, so roll back only after the workers' grants are younger than 30 days or with a renewal ready.
