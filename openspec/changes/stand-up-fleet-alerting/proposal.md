---
linear_story_id: CAM-70
linear_story_identifier: CAM-70
linear_story_title: "S3: Alert on the known failure classes through ntfy"
linear_story_url: https://linear.app/cameronraysmith/issue/CAM-70/s3-alert-on-the-known-failure-classes-through-ntfy
linear_story_state: In Progress
linear_team: CAM
linear_project: fleet-observability
last_synced_state: In Progress
last_synced_at: 2026-10-18T06:17:55Z
review_round: 0
max_review_rounds: 3
attempt_log:
  - { at: "2026-10-18T05:00:34Z", transition: "Backlog->Todo", outcome: "posted", note: "T1 bind; description seeded from this proposal" }
  - { at: "2026-10-18T06:17:55Z", transition: "Todo->In Progress", outcome: "posted", note: "first - [x] in tasks.md (1.1-1.3)" }
---

## Why

magnetite's metrics now reach the telemetry store, but nothing reads them: a memory squeeze, an OOM kill, a degraded pool or a unit failing in a loop is still found only when CI breaks.
S1's notifier reports only its own units, posts anonymously, and every mesh client can publish to `fleet-alerts`, so a stray post could mask a dead evaluator.
ADR-009 is accepted and S1 is deployed, so the alerting it decides can now run against stored series.
This change evaluates the failure classes S1's series cover, sends one FIRING and one RESOLVED per instance to a person, restricts `fleet-*` topics to one credential, and raises an alarm from cinnabar when the evaluator itself goes silent.

## What Changes

**An alert evaluator on magnetite**
- `fleet-alert.timer` runs a oneshot every 60 s that queries `fleet` over PromQL with the `regulator` store account and posts to `fleet-alerts` with the `alerter` token, keeping per-instance state in `/var/lib/fleet-alert`.
- Only rules whose signals S1 stores ship (D7): `HostMemoryPressure`, `HostOOMKill`, `ZfsPoolUnhealthy`, `SystemdUnitRestartLoop`, `SystemdUnitFailed`, `LocalExporterDown` and `WeeklyPipelineTest`, plus the evaluator's `StoreQueryFailing` and `RuleSignalMissing`; the filesystem, NVMe, launchd and probe-staleness rules wait for S4 and S5, and the dev-loop SLO burn rule lands with S2 (D8).
- `SystemdUnitFailed` excludes exactly the units the notifier already reports, derived from `services.observability-notify.units` (D10).
- Each run sends a heartbeat to `fleet-heartbeat`.

**A dead-man on cinnabar**
- `fleet-deadman.timer` polls `fleet-heartbeat` every 5 min and raises `AlertEvaluatorSilent` when no heartbeat arrived in 10 min, then RESOLVED when one does.
- Before polling it publishes anonymously to `fleet-heartbeat` and fails if that publish is accepted (R9.4).

**ntfy access control on cinnabar**
- From: every mesh client may publish to any topic, and all clients share one rate-limit budget because caddy connects from `::1`.
- To: an `alerter` user and token provisioned through `NTFY_AUTH_USERS` and `NTFY_AUTH_TOKENS`, access entries `alerter:fleet-*:rw` and `*:fleet-*:ro` with the default left read-write, and `behind-proxy` with `proxy-trusted-hosts = ::1` and `visitor-prefix-bits-ipv6 = 128`, so each mesh client is its own visitor (D1).
- Reason: the dead-man trusts heartbeats, and the evaluator's posts must not be starved by another client's burst.
- Impact: host-named topics, which the agent hooks and skills publish to, keep anonymous read-write; only `fleet-*` publishers need the token.

**One sender and one notifier, both carrying the token**
- `ntfy-send` gains `NTFY_TOKEN_FILE` and sends the token as `Authorization: Bearer`, never on argv (D2).
- The notifier moves out of the collector's agent role into `flake.modules.nixos.observability-notify`, keeping `services.observability-notify.units`, so cinnabar can import it for the dead-man's failures without a collector (D4).
- The template loads the token through `LoadCredential`, and the root resolve hooks read the same vars path through `NTFY_TOKEN_FILE` (D3).
- The notifier appends each posted FAILED to a log under `/var/lib/observability-notify`, which R9.1 counts (D9).

**Regulators**
- R9.1, a 24 h FIRING budget over the evaluator's state and the notifier's FAILED log, posting `AlertBudgetExceeded`.
- R9.2, `checks.x86_64-linux.fleet-alert`: `promtool` over the rendered rules, a sandboxed fixture server with five mutants, and a property-based check comparing the evaluator's pure jq transition function with a Python reference model (D11).
- R9.3, the dead-man and `WeeklyPipelineTest`; R9.4, the anonymous-publish probe; R9.5, an assertion that `fleet-alert.service` sets `MemoryMax = 64M` and `TimeoutStartSec = 50s`.
- A flake check that validates the rendered `NTFY_AUTH_*` strings before deploy (D6).

**Documentation**
- The `fleet-alert` component, ADR-009's amended items (the D1 settings, the D5 order, the D10 exclusion), the operator runbook for subscribing and reading alerts, and the notifier and `ntfy-send` READMEs.

## Capabilities

### New Capabilities
- `fleet-alerting` (stratum: `behavioral`): what the fleet requires of alerting — that each known failure class S1's series cover reaches a person as one FIRING and at most one RESOLVED per instance, with critical alerts repeated daily; that an unreachable store or a silent host freezes alerts rather than resolving or refiring them; that a renamed or missing signal is itself reported; that a silent evaluator is reported from another host; that only the alerting credential may publish to the alerting topics; that alert volume stays within a daily budget; that the evaluator stays inside a resource envelope; and that a weekly message proves the path.
- `fleet-alerting-interface` (stratum: `interface`): the properties at the machine's interface that discharge it — the query path, account and timeouts; the rule table rendered from one Nix source to the evaluator and to `promtool`; the state files; topic names, titles and priorities; the heartbeat and the dead-man's poll; the ntfy access entries, provisioning variables and proxy settings; token transport by file and `LoadCredential`; the notifier's FAILED log; and the R9.1 to R9.5 checks with their mutants.
  Trust boundary: ntfy enforces the access entries and rate limits, and delivers to subscribed devices, and this machine only configures it; any root process on magnetite or cinnabar can read the `alerter` token; cinnabar is the single delivery path, and nothing reports an ntfy outage until CAM-76; nothing here guarantees that an alert reaches a person, only that each stage's configuration, the fixture check and the recorded acceptance observations behave as stated.

### Modified Capabilities
- `world-assumptions` (stratum: `world`): A33 drops "accepts anonymous publishing", which this change makes false for `fleet-*`, and keeps reachability over ZeroTier and the single delivery path; new assumptions record ntfy 2.28.0's behaviour (declarative provisioning that refuses to start on an unprovisioned user and deletes removed entries, user-before-`*` access precedence, 401 for an unknown token even where anonymous access is allowed, visitors keyed by a masked client address) and caddy's forwarding (it connects to ntfy from `::1` and sets `X-Forwarded-For` to the mesh client's address), numbered from A37 because the active `share-ghq-reference-tree` change takes A34 to A36; the designation table gains the terms the new behavioral requirements use (alert, alert rule, alert instance, severity, evaluator, heartbeat, dead-man, topic, alert budget) and its notification-service `credential` row no longer says the service does not require one.
- `telemetry-store-interface` (stratum: `interface`): `Failure notices are posted to one topic` moves the template to `observability-notify`, posts with the `alerter` token and adds the FAILED log; `Credentials exist only as activation-resolved files owned by non-worker users` admits `fleet-alert` as a `regulator-password` holder; and the trust-boundary requirement's notice-publishing scenario no longer rests on ZeroTier membership alone.
- `telemetry-store` (stratum: `behavioral`): `The telemetry store's own failures reach a person` is discharged through the notifier's credential rather than A33's anonymous publishing.
- `host-metrics-collection` (stratum: `behavioral`): `A failed collection or store job notifies a person` drops "without the notifier holding any credential" and is discharged as `telemetry-store` is.

`telemetry-store`'s `Only the collector writes and only named readers read` is unchanged, because the evaluator uses the existing regulators' store account.

## Impact

- New: `modules/nixos/fleet-alert.nix`, `modules/nixos/fleet-alert/rules.nix`, `modules/checks/fleet-alert.nix`, the `flake.modules.nixos.observability-notify` module extracted from `modules/clan/services/otel-collector/flake-module.nix`, and the provisioning check.
- Changed: `pkgs/by-name/ntfy-send` (`NTFY_TOKEN_FILE`), the collector's agent role (imports the notifier), `modules/machines/nixos/magnetite/default.nix` (evaluator, `regulator-password` holder assertion, generator), `modules/machines/nixos/cinnabar/ntfy.nix` and cinnabar's imports (access entries, environment file, proxy settings, notifier, dead-man), ADR-009, the `fleet-alert` component, the reference architecture where it names the deploy order, and the operator docs.
- New secrets: the shared generator `ntfy-alerter` (`share = true`) on magnetite and cinnabar, holding only the `tk_` token (mode `0400`), and the per-machine generator `ntfy-alerter-env` on cinnabar only, which depends on it and writes the `ntfy-env` file with the bcrypt hash and token, restarting `ntfy-sh.service`.
- Deployment, three steps with no rejection window (D5): cinnabar provisions `alerter` and its token without access entries; magnetite deploys the token-bearing notifier and evaluator; cinnabar adds the access entries, and R9.4's probe confirms that an anonymous `fleet-*` publish is refused.
- Residual risk: a malformed `ntfy-env` stops ntfy for every publisher; the D6 check guards it before deploy, and an ntfy outage stays unreported until CAM-76.
- Out of scope, each in a later slice: the filesystem rules and other hosts' collectors (S4), the NVMe, launchd and probe-staleness rules (S4, S5), the dev-loop SLO burn rule (S2), and the external watch on cinnabar (CAM-76, ADR-009 Q5).
