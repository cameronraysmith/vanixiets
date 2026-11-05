# Brainstorm: watch the alert path from outside the fleet (CAM-76, ADR-009 Q5)

## Background

ADR-009 Q5 asks whether something outside the fleet watches cinnabar itself (`docs/notes/development/observability/decisions/ADR-009-alerting.md:264-266`).
The 2026-10-15 gate deferred it, and charter v21 scheduled it as CAM-76 before S5 (CAM-72).
The S3 retrospective sets the condition CAM-76 must meet: "CAM-72 does not start until CAM-76's watcher alerts over a channel other than ntfy" (`openspec/changes/archive/2026-10-21-stand-up-fleet-alerting/retrospective.md:170-172`).
Classification under `skill://brainstorming`: architectural, because it adds the fleet's first third-party dependency in the alert path and its first channel to a person that does not pass through cinnabar.

Abbreviations used below: `OBS` is `docs/notes/development/observability/`, `ADR-009` is `OBS/decisions/ADR-009-alerting.md`, `CH` is `OBS/charter.md`, `S3` is the archived change `openspec/changes/archive/2026-10-21-stand-up-fleet-alerting/`, and `S4` is the active change `openspec/changes/stand-up-linux-fleet-collection/`.
The outage classes are W1 to W9, defined in `design.md` "Failure classes": cinnabar down (W1), ntfy down (W2), caddy down (W3), cinnabar's ZeroTier or dnsmasq down or magnetite's path to it broken (W4), magnetite or its evaluator down (W5), the dead-man stopped or wedged (W6), ntfy's access entries wrong (W7), all of `fsn1` down (W8), and the phone's subscription broken (W9).

Inputs gathered for this brainstorm:

- The repository's alert path read on 2026-11-01: the dead-man, its unit and its check (`modules/nixos/fleet-alert.nix:447-535`, `:782-843`; `modules/machines/nixos/cinnabar/fleet-alert.nix`; `modules/checks/fleet-alert.nix:152-389`), cinnabar's caddy and ntfy, and the terranix locations.
- Vendor pages read on 2026-11-01: https://healthchecks.io/docs/http_api/, https://healthchecks.io/pricing/, https://healthchecks.io/privacy/, https://healthchecks.io/docs/healthchecks_sentry_comparison/, https://betterstack.com/pricing, https://cronitor.io/pricing, https://deadmanssnitch.com/plans, https://uptimerobot.com/pricing/, https://ntfy.sh/#pricing and https://docs.hetzner.com/robot/dedicated-server/security/system-monitor/.
- Four reference clan configurations, read for how they watch their own alert path: Mic92/dotfiles, pinpox/nixos, clan-infra and mirkolenz/infra.

## Status of the decisions

The operator chose the direction on 2026-11-01 (O1) and, the same day, answered the five questions the first draft of `design.md` put, each as recommended (O2 to O6).
Each is recorded once below, in a line beginning `Decision (O<n>, decided by the operator, 2026-11-01)`, and the proposal bullet tagged with the same `O<n>` carries it.

## Grounding evidence

### What is reachable from outside

- caddy serves `ntfy.zt` only on cinnabar's ZeroTier addresses and opens 443 only on `zt+`, and ntfy listens on `[::1]:2586` (`modules/machines/nixos/cinnabar/caddy.nix:5-8`, `:29-35`, `:100`; `modules/machines/nixos/cinnabar/ntfy.nix:36`).
- An outside service can therefore only receive pings from the fleet; probing ntfy from outside would need a public listener, which ADR-009 excludes ("no new listener", ADR-009:252).

### What the dead-man already proves on each run

- Its anonymous probe and its poll go to `[::1]:2586` and skip caddy; its posts go through `ntfy-send` to `https://ntfy.zt`, through caddy and ZeroTier (`modules/nixos/fleet-alert.nix:482-493`, `:810-813`).
- A run fails on a probe not refused with 403, on a failed poll, and on a failed post, which stays pending for the next run (`modules/nixos/fleet-alert.nix:484-533`).
- magnetite's heartbeat reaches the poll only through magnetite's `ntfy-send`, cinnabar's dnsmasq, caddy and ntfy (ADR-009:195), so a heartbeat in the window shows that whole path worked within 10 min.
- A run that finds no heartbeat posts `AlertEvaluatorSilent` once and then passes, so the run's pass alone does not show the path from magnetite is healthy.

### What is not covered today

- Nothing reports W1, W3, W4, W6 or W8; W2 and W7 are reported only through the ntfy they concern (ADR-009:193-194).
- The only backstop is the Monday `WeeklyPipelineTest`, up to 7 days later (`OBS/components/fleet-alert.md:166`).
- cinnabar and magnetite are both in Hetzner `fsn1` (`modules/terranix/hetzner.nix:13`, `:27`).

### healthchecks.io

- A success ping is a request to `https://hc-ping.com/<uuid>`, failure is `/fail` on the same URL, and the UUID is assigned by the service.
- An unknown UUID and a rate-limited ping are both answered `200`, with bodies `OK (not found)` and `OK (rate limited)`; more than 5 pings a minute to one check may be dropped.
- The free tier has 20 checks and 100 log entries per check; webhooks and email are on every plan.
- The service lists Hetzner as its host and its servers as in Germany, without naming the region.

### The reference configurations

- None of the four watches its own alert path from outside.
- Mic92/dotfiles sends alertmanager's notifications through SMTP and Telegram on other hosts, a second delivery path rather than a watch of the first, and keeps its SMTP secret in a clan vars generator.
- pinpox/nixos evaluates and delivers on one host, and clan-infra's monitoring module has no contact points; mirkolenz/infra has no alerting.

## Decision chain

### D1. The watcher and its channel (O1, O2)

Options:
- A. healthchecks.io, pinged by `fleet-deadman` after a fully passing run; sees W1 to W7, and W8 unless healthchecks.io fails with `fsn1`; email on the free tier.
- B. Better Stack or C. Cronitor with the same wiring; equal coverage, smaller free tiers, Better Stack's push paid.
- D. Dead Man's Snitch; one free snitch, integrations paid.
- E. magnetite probing `https://ntfy.zt` and posting to the public ntfy.sh; no account, but it dies with magnetite and misses W5, W6 and W8, and it sends message content to ntfy.sh.
- F. UptimeRobot probing cinnabar's public address; W1 only.
- G. A launchd probe on stibnite with a local notification; W1 to W4, and only while the laptop is awake on the mesh.
- H. Hetzner's own monitoring; its system monitor exists only for dedicated servers.

Decision (O1, decided by the operator, 2026-11-01): A, with email as the channel that does not depend on cinnabar, and CAM-72 gated on it.

Decision (O2, decided by the operator, 2026-11-01): email alone, with neither Pushover nor an ntfy.sh topic beside it, and the risk that an outage of Hetzner's region silences healthchecks.io together with cinnabar and magnetite is accepted as residual.

- Email already reaches the phone through the mail provider's own notifications.
- Pushover adds a paid account; an ntfy.sh topic adds a second ntfy server to subscribe to and a third party that sees the topic.
- The region risk does not depend on the channel, because healthchecks.io is the sender; only a second watcher at another provider removes it.

### D2. When the dead-man pings (O4)

Options: ping after any run that exits 0; ping only after a run that exits 0 and saw at least one heartbeat; ping from a separate unit that reads `fleet-deadman.service`'s last result.

Decision (O4, decided by the operator, 2026-11-01): the ping is the run's last step, sent only when the probe was refused with 403, the poll answered with at least one heartbeat in its 10 min window, and every pending post was sent.

- A failed post, which is how W3 and W4 show on cinnabar, withholds the ping because the ping follows the posts.
- Without the heartbeat condition, a run whose `AlertEvaluatorSilent` was posted successfully passes, and the check turns green while magnetite's path is still broken.
- The cost is a second report when only magnetite is down (W5): `AlertEvaluatorSilent` through ntfy and the email.
- A separate unit was rejected because it adds a unit whose own failures need a regulator.

### D3. What a failing run sends (O3)

Options: no ping, letting the check go late; an explicit `/fail` from an exit trap.

Decision (O3, decided by the operator, 2026-11-01): a failing run sends nothing.

- Every cinnabar deploy that replaces ntfy's environment file restarts `ntfy-sh.service` (`modules/machines/nixos/cinnabar/ntfy.nix:18`); with `/fail`, the one run that meets the restart would email.
- `/fail` needs a second credential file and cannot be sent when cinnabar or its egress is down, which are the outages that matter most.

### D4. Reading the answer

Decided while writing the design, from the 200-with-`OK (not found)` behaviour above: the ping step fails the run unless the body is exactly `OK`, and a failed ping fails the run so the notifier's `FAILED fleet-deadman` explains the email that follows.

### D5. Where the ping URL lives (O6)

Options: a per-machine clan vars generator on cinnabar with a hidden prompt; a shared generator; an environment file; the URL in the unit's configuration.

Decision (O6, decided by the operator, 2026-11-01): the per-machine generator `fleet-deadman-ping` on cinnabar, with a hidden, persisted prompt as `modules/machines/nixos/magnetite/default.nix:404-422` declares, writing a curl configuration file that the unit loads through `LoadCredential` and curl reads on stdin, never on argv.

- The UUID is a bearer credential: anyone holding it can keep the check green.
- Only cinnabar pings, so a shared generator would add readers with no use.
- An environment file is visible through `systemctl show` and inherited by every child process.

### D6. The check's period and grace (O5)

Options: set by hand in healthchecks.io's web interface; declared through its Management API from a deploy-time unit.

Decision (O5, decided by the operator, 2026-11-01): period 5 min and grace 10 min, set in the web interface, recorded in the runbook and observed at acceptance.

- The period matches the dead-man's timer, and the grace absorbs one failed or late run; an outage is reported about 15 min after the last accepted ping.
- The Management API needs an API key secret and a reconciler whose drift would still be seen only by observation.

## Rules adopted from earlier retrospectives

- Every artifact names an envelope and a regulator shown able to fail (CH R5): here E9.6, R9.6 with its mutants, and the ntfy-stop negative control.
- A check compares independently defined values; a relation within one host is a module assertion (S3 review F3).
- Each check states its evaluation cost against 0.5 GiB, before and after.
- A credential never appears on a command line, in a unit's environment or in the Nix store (S3 design D2).
- A human step that a later observation depends on is a gated task (S3 retrospective §6): here creating the check and entering the URL.
- Every runtime regulator gets a negative control at acceptance.

## Left for design

- The exact place of the ping in `fleetAlertDeadman`, the option's name, and how the check builds the dead-man with a ping stand-in.
- The generator's validation pattern and the store-path assertion.
- Which spec requirements change, given that S4 modifies `A silent evaluator is reported from another host` and the designation table.
- The deployment order and the two negative controls.
