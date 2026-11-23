## Context

omnigent 0.22.0, pinned here, issues each `omnigent login` a login grant in its PostgreSQL table `device_grants` with `client_id = 'omnigent-cli'`.
A worker refreshes its one-hour access token (`omnigent/server/routes/device_auth.py:118`) with the grant's refresh token, and the server refuses once `now - approved_at` reaches the lifetime (`:522-525`).
The lifetime is 30 days by default (`:123`), or `OMNIGENT_GRANT_MAX_LIFETIME_DAYS` whole days when that is a positive integer, read once at mount (`:127-156`, `:408`).
Each refresh may also purge, at most every 300 s (`:288`), every redeemed or revoked grant older than the lifetime then in force (`omnigent/server/device_grant_store.py:586-640`).
Login grants do not rotate their refresh token (`device_auth.py:529-545`).
The only revocation is `POST /oauth/revoke` with the grant's refresh token or an access token naming it (`:582-610`); there is no admin route, and the 0.22.0 CLI never calls it.

On 2026-11-14 magnetite's table held seven redeemed CLI grants: the first owner's of 2026-10-17 and 2026-10-25, superseded; three of the first owner's of 2026-11-14, one per worker on magnetite, pyrite and stibnite; and the second owner's two of 2026-11-14, one per worker on magnetite and pyrite (read-only query on magnetite; the worker matrix in `modules/clan/services/omnigent/README.md`).

## Goals / Non-Goals

**Goals:**
- Workers need a new login every 90 days instead of every 30.
- Raising the lifetime revives no superseded grant.

**Non-Goals:**
- Warning before a grant runs out (D3).
- Renewing workers automatically, which 0.22.0 cannot do without a person signing in.
- Changing the restart policy of `omnigent-host-*` units.

## Decisions

### D1: The server's grant lifetime is 90 days

`systemd.services.omnigent.environment.OMNIGENT_GRANT_MAX_LIFETIME_DAYS` is `"90"`.
Boundary: vendored-versus-first-party; the lifetime is omnigent's, set through its documented override, with no patch.
Alternatives: keep 30 days, which means renewing five workers every month; a longer lifetime, which widens the leak window further.
Trade-off: the variable is server-wide, so browser and CLI logins also live 90 days, and a leaked worker refresh token, which never rotates, stays usable up to 90 days unless revoked with that token.

### D2: The superseded grants are purged before the lifetime is raised

Raising the lifetime makes every unpurged grant younger than 90 days refreshable again, including the first owner's superseded grants of 2026-10-17 and 2026-10-25, which would revive until 2027-01-15 and 2027-01-23.
They cannot be revoked through a supported path, because their tokens were overwritten when the workers logged in again (A106).
The server purges every redeemed grant older than its lifetime, on the first refresh after a restart and at most every 300 s after that (A105), and the refresh endpoint runs that purge before it checks the presented token and needs no client secret (`omnigent/server/routes/device_auth.py:482-501`).
So magnetite is first deployed with a temporary 7-day lifetime, from an uncommitted edit in the deploy tree that never reaches `main`, and one refresh request with a placeholder token then makes the server purge both superseded grants, while the 2026-11-14 grants, hours old, stay live.
The gate is a read-only query returning 0: `SELECT count(*) FROM device_grants WHERE client_id = 'omnigent-cli' AND status = 4 AND approved_at <= extract(epoch FROM now())::bigint - 7 * 86400`, where status 4 is `redeemed` (`omnigent/db/enum_codecs.py:88-94`).
The merge waits on the gate: magnetite is deployed from `main` routinely, so once the variable is on `main` the next such deploy would apply it.
Under the temporary lifetime the 2026-11-14 grants would expire on 2026-11-21, so the 90-day deploy follows the same day.
Alternatives rejected: an `UPDATE` setting status 5, which is not omnigent's interface; deploying at once and accepting the revival; waiting for the 30-day purge, which the second grant would reach only after 2026-11-24 19:02Z, the plan until the operator chose this route on 2026-11-14.

### D3: The early-warning alert is shelved

An alert `OmnigentLoginGrantExpiring` was built for this change: the collector read each owner's earliest grant expiry from `device_grants` as a column-limited database role, and the rule warned 14 days ahead.
The operator shelved it on 2026-11-14, unchanged, as commit `cc0370f3` on branch `omnigent-grant-alert-shelved`.
Reasons: it couples the collector to omnigent's internal `device_grants` schema; it needs its own database role and column grants; and it would fire on superseded grants until the server purges them.
The exit-78 `SystemdUnitFailed` notice of #3863 already gives one clear notice at expiry, and owners can renew ahead of the date.

#### If revisited

The shelved mechanism, commit `cc0370f3`, ran on magnetite in three parts.
A oneshot unit granted the collector's database role `SELECT` on four columns of `device_grants`; an `sqlquery` receiver, written inline in `modules/nixos/omnigent.nix`, emitted `omnigent_login_grant_expiry_timestamp_seconds{omnigent_owner}`, each owner's earliest redeemed CLI grant plus the lifetime; and the rule warned 14 days ahead, with its expected host hard-coded as `magnetite`.
Besides the reasons above, it could not have caught two failures.
It grouped grants by owner, so a person's own CLI login counted as one more of that owner's grants, indistinguishable from a worker's.
It watched only the countdown, so a grant lost to a purge or a revocation removed a row and raised nothing.
The operator's own CLI login on stibnite was found expired on 2026-11-23; inferred, not confirmed against the table: it was most likely approved before 2026-11-07 and deleted by D2's purge, which counted the grants of 2026-10-17 and 2026-10-25 as superseded worker grants.

Worth keeping from it:
- The alert reads the server, the one place that holds every grant's age.
- The role reads only `user_id`, `client_id`, `status` and `approved_at`, never the token hashes, the codes or the grant id.
- The SQL maps each owner's login address to the owner's alias, so no email address becomes a label value.
- One Nix binding sets both `OMNIGENT_GRANT_MAX_LIFETIME_DAYS` and the lifetime in the SQL, so the alert cannot drift from the server.
- Three mutants: `grantThresholdInDays`, the threshold written in days, checked in `promtoolRehearsal`; `noExporter` and `otherHost`, which break the module's two assertions, run once by hand and never checked in.

A fresh change should cover:
- who holds each grant, a worker or a person, and on which host;
- loss as well as countdown, for example each owner's live grants against the worker accounts the inventory expects;
- whether persons' CLI logins are in scope;
- a receiver in the `sqlquery` library pattern of `modules/nixos/postgresql-collation.nix`, with a check against a real PostgreSQL as in `modules/checks/postgresql-collation.nix`;
- a flag in the host table, `modules/lib/observability-hosts.nix`, in place of the hard-coded host;
- A105, A106, the four columns and the status codes re-read against the omnigent version then pinned; on 2026-11-23 the cited lines of 0.23.0 still matched.

The grants approved on 2026-11-14 reach 90 days about 2027-02-12, so a countdown alert with a 14-day warning must be deployed by late January 2027 to warn before them.

## Risks / Trade-offs

- [A leaked worker refresh token lives up to 90 days] → whoever holds it can revoke it through `/oauth/revoke`; otherwise it lasts until the lifetime, the accepted cost of D1.
- [The first warning is the failure itself] → #3863's notice names the failed unit, and the README tells owners to renew ahead of the date; D3's "If revisited" records the shelved alert.
- [The 90-day deploy slips after the temporary one] → under 7 days the 2026-11-14 grants expire on 2026-11-21, so the 90-day deploy follows in the same session.

## Migration Plan

1. Deploy magnetite with the temporary 7-day lifetime from an uncommitted edit in the deploy tree, send one refresh request with a placeholder token, and run the gate's query read-only; continue only when it returns 0.
2. Enqueue the pull request, deploy magnetite from the merged commit, and discard the deploy tree's edit.
3. After the deploy, confirm the server's environment carries the variable.

Rollback: deploy without `OMNIGENT_GRANT_MAX_LIFETIME_DAYS`; grants older than 30 days then stop refreshing at once, so roll back only while the workers' grants are younger than 30 days or with a renewal ready.
