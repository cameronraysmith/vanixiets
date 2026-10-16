---
title: omnigent-host restart loops after expired Omnigent logins, 2026-10-15
---

On 2026-10-15 magnetite's `omnigent-host-cameron.service` and `omnigent-host-janettesmith.service` restart-looped about 3,200 times, from the 04:36 UTC deploy until the units were stopped.
Both hosts' stored Omnigent logins had expired, and every start failed with "stored login session … has EXPIRED".
stibnite's launchd job `org.nixos.omnigent-host-cameron` exited with status 78 for the same reason, and pyrite's `omnigent-host-*` units looped likewise.
Nothing in the fleet raised an alert, so the loops were found only by someone looking at the hosts.
This note records the cause, the resolution, and the detection gap.

## Evidence

Both magnetite workers first ran on 2026-09-15 06:42 UTC.
Their refreshes at earlier restarts on 2026-10-14, at 01:40, 05:01 and 15:52, succeeded.
After the 04:36 deploy restarted them, their refreshes at 04:37 were refused with HTTP 400, per the host log.
Neither worker's grant remained in the server's `device_grants` table afterwards.
Each unit then exited non-zero, and systemd restarted it under `Restart=on-failure` and `RestartSec=5` (`modules/clan/services/omnigent/README.md:54`).
A five-second retry does not exhaust systemd's default start limit of five starts in ten seconds (`modules/clan/services/omnigent/README.md:55`), so the loop had no natural end.

## Root cause

An Omnigent login has a fixed lifetime that nothing in the fleet tracked.
In omnigent 0.18.0, `omnigent login` issues a login grant (`server/routes/device_auth.py:333`), and the host refreshes it when it reconnects (`runner/_entry.py:717-735`).
The server refuses a refresh once the grant's `approved_at` is more than `_GRANT_MAX_LIFETIME_SECONDS`, 30 days, in the past, and then purges the aged grant (`device_grant_store.py:459-517`), as read for #3438.
The workers' logins dated from 2026-09-15, so the first restart after 30 days, the 04:36 deploy, was the first refresh to fail.

The renewal path covered model tools only.
`omnigent-worker-login` could renew Claude, Codex and the other model logins, but it had no way to renew the worker's own Omnigent login.

The restart policy suits network outages but not an expired credential.
It retries every nonzero exit indefinitely, which is correct for a transient outage and turns a permanent authentication failure into an unbounded loop.

## Resolution

#3438 added an `omnigent` tool to `omnigent-worker-login`, which runs `omnigent login` as the dedicated worker account against the server role's domain (`modules/clan/services/omnigent/README.md:342`).
Each affected worker was re-logged with `nix run .#omnigent-worker-login -- HOST OWNER omnigent` and its unit or job was restarted.
The omnigent README now records the 30-day lifetime and the server's `OMNIGENT_GRANT_MAX_LIFETIME_DAYS` override (`modules/clan/services/omnigent/README.md:343`).

## Detection gap

No alerting existed, so a unit that restarted about 3,200 times and a launchd job that exited 78 told nobody.
The observability work's ADR-009 adds `SystemdUnitRestartLoop`, `LaunchdJobFailed` and `LaunchdJobRestartLoop` rules for this failure class (`docs/notes/development/observability/decisions/ADR-009-alerting.md`).
Nothing yet warns before a login reaches 30 days, so renewal still depends on the README's interval or on the alert after expiry.
