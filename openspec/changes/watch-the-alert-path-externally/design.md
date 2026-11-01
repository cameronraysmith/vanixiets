## Context

This change resolves ADR-009 Q5, whether something outside the fleet watches cinnabar, which charter v21 scheduled as CAM-76 before S5 (CAM-72).
The S3 retrospective sets the gate this change must meet: "CAM-72 does not start until CAM-76's watcher alerts over a channel other than ntfy" (S3-RT:170-172).
On 2026-11-01 the operator chose the direction (O1): a healthchecks.io heartbeat, pinged by cinnabar's `fleet-deadman` after a fully passing run, with email as the channel that does not depend on cinnabar, gating CAM-72.
The same day the operator answered the five questions this design put, each as recommended (O2 to O6); `brainstorm.md` records how the options were narrowed, and "Open Questions" lists each answer.

Citation keys:
A9 is `docs/notes/development/observability/decisions/ADR-009-alerting.md`, CH is `docs/notes/development/observability/charter.md`, FA is `components/fleet-alert.md` and RA is `architecture/reference-architecture.md` under the same directory, and README is that directory's `README.md`.
RB is the runbook `packages/docs/src/content/docs/development/operations/fleet-observability.md`, and SAT is `packages/docs/src/content/docs/development/traceability/satisfaction.md`.
FAN is `modules/nixos/fleet-alert.nix`, CFA is `modules/machines/nixos/cinnabar/fleet-alert.nix`, CK is `modules/checks/fleet-alert.nix` and MG is `modules/machines/nixos/magnetite/default.nix`.
S3 is the archived change `openspec/changes/archive/2026-10-21-stand-up-fleet-alerting/`, S3-RT its `retrospective.md`, and S4 the active change `openspec/changes/stand-up-linux-fleet-collection/`.
HC is healthchecks.io's Pinging API documentation, https://healthchecks.io/docs/http_api/, read on 2026-11-01.

The current state:

- `fleet-deadman.timer` runs `fleet-deadman.service` on cinnabar every 5 min at `*:0/5 UTC` (FAN:834-842).
  Each run sends an anonymous publish to `fleet-heartbeat` on ntfy's own listener `[::1]:2586` and fails unless it is refused with 403 (R9.4), polls the topic for the last 10 min and fails if the poll fails, raises or resolves `AlertEvaluatorSilent` through the shared jq transition, and posts through `ntfy-send` with the `alerter` token, failing the run on a failed post and leaving it pending for the next run (FAN:453-535).
- The probe and the poll bypass caddy, while every post goes to `https://ntfy.zt` through caddy on cinnabar's ZeroTier addresses (CFA:18-25; FAN:810-813).
- magnetite's evaluator posts its heartbeat through `ntfy-send` to `https://ntfy.zt`, resolved by cinnabar's dnsmasq (A9:195), so a heartbeat in the dead-man's window shows that magnetite, the mesh path, cinnabar's resolver, caddy and ntfy all worked within the last 10 min.
- caddy serves `ntfy.zt` only on cinnabar's ZeroTier addresses, opens 443 only on `zt+`, and ntfy listens on `[::1]:2586` (`modules/machines/nixos/cinnabar/caddy.nix:5-8`, `:29-35`, `:100`; `modules/machines/nixos/cinnabar/ntfy.nix:36`), so nothing outside the mesh can probe ntfy without a new public listener, which A9:252 excludes.
- The dead-man runs under the shared hardening with `DynamicUser`, `AF_INET` and `AF_INET6` allowed (FAN:554-571), and has no `TimeoutStartSec`, so a wedged run blocks the next one.
- `fleet-deadman` is cinnabar's notified unit, so a failed run posts `FAILED fleet-deadman on cinnabar` through the same ntfy (CFA:28-31).
- cinnabar and magnetite are both Hetzner cloud servers in `fsn1` (`modules/terranix/hetzner.nix:10-29`), and no Hetzner firewall restricts their egress in that file.
- A9 lists "a hosted dead-man service such as healthchecks.io watching cinnabar" as a rejected alternative deferred to Q5 (A9:181), and records that nothing detects an outage of cinnabar or its ntfy (A9:193-194).

Facts about healthchecks.io that shape the decisions:

- A success ping is a `HEAD`, `GET` or `POST` to `https://hc-ping.com/<uuid>`, a failure signal is the same URL with `/fail`, and the UUID is assigned by the service and cannot be chosen (HC).
- A ping to an unknown UUID is answered `200 OK (not found)`, and a rate-limited ping `200 OK (rate limited)`, so the HTTP status alone does not show that a ping counted (HC).
- More than 5 pings per minute to one check may be dropped (HC).
- The free tier allows 20 checks and keeps 100 log entries per check, about 8 h at one ping per 5 min (https://healthchecks.io/pricing/).
- healthchecks.io lists Hetzner as its host and states its servers are in Germany (https://healthchecks.io/privacy/, https://healthchecks.io/docs/healthchecks_sentry_comparison/); whether that is `fsn1` is not stated.
- A check's period, grace and notification integrations are set in the service's web interface or through its Management API, not by the pinging client.

Constraints that shape every decision below:

- Every artifact names an envelope and a regulator shown able to fail (CH R5, A6).
- Each check states a 0.5 GiB evaluation budget, measured with `NIX_SHOW_STATS=1 nix eval --option eval-cache false --raw .#.checks.x86_64-linux.<check>.drvPath`, before and after the change.
- A relation within one host is a module assertion, paid for by that host's toplevel evaluation, not a check clause.
- A credential never appears on a command line, in a unit's environment or in the Nix store; S3 carried the `alerter` token by file and `LoadCredential` and the store password on curl's stdin (S3 design D2, Data flow).
- A human step that a later observation depends on is a gated task (S3-RT §6).

Stakeholders are the operator, who receives both the ntfy alerts and the new email, and S5 (CAM-72), which is blocked until this change's acceptance is recorded.

## Goals / Non-Goals

**Goals:**

- An outage of cinnabar, ntfy, caddy, cinnabar's resolver or ZeroTier, or of the dead-man itself, produces an email to the operator within 15 min, by a path that does not pass through cinnabar.
- A misconfigured ntfy access entry, which R9.4 today reports only through ntfy, reaches the operator by the same email.
- The ping is sent exactly when the dead-man's run passes completely, shown by a build-time regulator with mutants (R9.6).
- The ping URL is carried as a credential and never on a command line, in the environment or in the store.
- A deliberate stop of ntfy on cinnabar produces the email at acceptance, which meets S3-RT's gate on CAM-72.
- ADR-009 Q5 is recorded as resolved in A9 and every artifact that cites it.

**Non-Goals:**

- Reporting a broken phone subscription; the Monday `WeeklyPipelineTest` stays its only monitor.
- Watching healthchecks.io itself, the operator's mail provider, or the account's continued existence.
- Declaring the check's period, grace and integrations in the flake (D6).
- Probing ntfy or caddy from outside the mesh, which needs a public listener (A9:252).
- Changing the dead-man's rule, window, timer, or the evaluator on magnetite.

## Decisions

### Failure classes

This design numbers the outage classes it reasons about W1 to W9.
"Today" is the state before this change.

| Class | What fails | Reported today | Reported after this change |
|---|---|---|---|
| W1 | cinnabar is down | by the missing Monday test, up to 7 days later | email: no run, no ping |
| W2 | ntfy is down, including a refused start on a malformed `environmentFile` | R9.4 fails the dead-man, whose failure notice also goes through ntfy, so nothing arrives (A9:193-194) | email: the probe answers 000, the run fails |
| W3 | caddy is down | `AlertEvaluatorSilent` fires, but its post goes through caddy and fails | email: no heartbeat arrives, and the pending post fails |
| W4 | cinnabar's ZeroTier or dnsmasq is down, or magnetite's path to cinnabar is broken | as W3 | email: no heartbeat arrives; a post from cinnabar may also fail |
| W5 | magnetite or its evaluator is down | `AlertEvaluatorSilent` through ntfy, while W1 to W4 do not hold | `AlertEvaluatorSilent` through ntfy and the email (O4) |
| W6 | the dead-man's timer is stopped, or a run is wedged | nothing | email: no run completes, no ping |
| W7 | ntfy's access entries are wrong | R9.4 through ntfy | email: the probe is not refused, the run fails |
| W8 | all of `fsn1` is down | nothing | email, unless healthchecks.io fails at the same time (O2) |
| W9 | the phone's subscription is broken | the Monday test | unchanged |

W1, W2, W6 and W7 are covered by any ping sent only after a passing run.
W3 and W4 are covered because magnetite's heartbeat crosses caddy and the mesh, and the heartbeat requirement (O4) keeps the check red for as long as that path is broken, rather than only until the dead-man's own `FIRING` is posted.

### Layout

No new file in `modules/`; the change extends S3's files.

| Path | Change |
|---|---|
| FAN | `flake.lib.fleetDeadmanPing pkgs { curl ? lib.getExe pkgs.curl }`, the ping step as a `writeShellApplication` named `fleet-deadman-ping` reading `FLEET_DEADMAN_PING_CONFIG` (D4); `fleetAlertDeadman` takes `ping ? null`, an executable path beside `ntfySend`, and when it is set calls it as the run's last step if the poll held a heartbeat (D2); the option `services.fleet-alert.deadman.pingConfigFile` (`nullOr str`, default `null`), which passes `ping`, adds `LoadCredential=external-ping:<path>` and `FLEET_DEADMAN_PING_CONFIG=%d/external-ping`; an assertion that the path is not under the Nix store (D5) |
| CFA | the per-machine generator `fleet-deadman-ping` and `services.fleet-alert.deadman.pingConfigFile` set from its `curl-config` file (D5) |
| CK and `modules/checks/fleet-alert/` | `modules/checks/fleet-alert/ping_stub.py` beside `ntfy_stub.py`; the R9.6 legs `deadmanPingRehearsal` and its two mutants; `pingTransport`, the ping step run with a recording curl, and its argv mutant; both added to the check's `passthru` and build (D7, D8) |
| `vars/per-machine/cinnabar/fleet-deadman-ping/` | the encrypted `curl-config` |
| A9, FA, RA, README, RB, CH | the amendments listed in "Implementation surface" |

### Data flow

```
fleet-deadman.timer (5 min) ─▶ fleet-deadman.service (cinnabar, DynamicUser)
   │  LoadCredential: alerter-token, external-ping
   │  1. R9.4 probe   anonymous POST http://[::1]:2586/fleet-heartbeat   pass only on 403
   │  2. poll         GET  http://[::1]:2586/fleet-heartbeat/json?poll=1&since=10m
   │  3. transition   AlertEvaluatorSilent, state in /var/lib/fleet-deadman/state.json
   │  4. posts        ntfy-send ─▶ https://ntfy.zt (caddy, ZeroTier) ─▶ fleet-alerts
   │  5. ping, only if 1–4 passed and the poll held ≥ 1 heartbeat (O4)
   │        curl -K - < $CREDENTIALS_DIRECTORY/external-ping   (url = "https://hc-ping.com/<uuid>")
   │        body must be exactly "OK", else the run fails
   ▼
hc-ping.com ─▶ healthchecks.io check (period 5 min, grace 10 min, set in its web interface)
   │  no ping for period + grace
   ▼
email to the operator (O2)
```

### Credential flow

| Generator | File | Delivered as | Consumer |
|---|---|---|---|
| `fleet-deadman-ping` (per machine, cinnabar only) | prompt `ping-url` (`type = "hidden"`, `persist = true`, `deploy = false`) | not deployed | the generator's script |
| | `curl-config` (secret, one line `url = "<ping URL>"`, no `restartUnits`, because each run reads it afresh) | `LoadCredential=external-ping:<path>` | `fleet-deadman.service`, which feeds it to curl on stdin |

The ping URL's UUID is a bearer credential: whoever holds it can keep the check green while the fleet's alert path is down.

### D1: healthchecks.io watches the dead-man

- **Choice**: a healthchecks.io check on the free tier, pinged by `fleet-deadman` (O1).
- **Rationale**: it is the only free option that sees W1 to W7 together, because the dead-man already exercises ntfy's listener, its access entries, and (through magnetite's heartbeat) caddy and the mesh, and an external heartbeat adds only "did that pass recently".
  Detection drops from up to 7 days to at most period plus grace, 15 min under O5.
  It needs no new listener, so A9:252 holds.
- **Boundary**: vendored versus first-party; the watcher's evaluation and email are healthchecks.io's, and this change only pings it.
- **Alternatives considered**:
  - Better Stack or Cronitor heartbeats with the same wiring: equal coverage; Better Stack's free tier has 10 monitors and charges for push, Cronitor's has 5 monitors and one user (https://betterstack.com/pricing, https://cronitor.io/pricing); rejected as no better on any axis that matters here.
  - Dead Man's Snitch: one free snitch and integrations only on paid plans (https://deadmanssnitch.com/plans); rejected.
  - magnetite probing `https://ntfy.zt` and posting to the public ntfy.sh: no account, but it dies with magnetite, misses W5, W6 and W8, and sends message content to ntfy.sh; rejected.
  - UptimeRobot probing cinnabar's public address: sees W1 only; rejected.
  - A launchd probe on stibnite with a local notification: sees W1 to W4 only while the laptop is awake and on the mesh; rejected.
  - Hetzner's monitoring: its system monitor exists only for dedicated servers in Robot (https://docs.hetzner.com/robot/dedicated-server/security/system-monitor/); not available.
  - None of the clan configurations surveyed (Mic92/dotfiles, pinpox/nixos, clan-infra, mirkolenz/infra) watches its own alert path from outside; Mic92's alertmanager sends through SMTP and Telegram on other hosts, which is a second delivery path, not a watch of the first.

### D2: The ping is the dead-man's last step, after a fully passing run

- **Choice**: when the configuration carries a ping, `fleetAlertDeadman` calls the ping step after the post loop and only then; every earlier failure exits non-zero before it, under `writeShellApplication`'s `errexit`.
  A passing run is one in which the probe was refused with 403, the poll answered and held at least one heartbeat (O4), and every post the transition produced was sent.
- **Rationale**: placing the ping after the posts makes a failed post, which is how W3 and W4 show on cinnabar, withhold the ping without a separate condition.
  The heartbeat condition is the one addition to the run's existing pass criteria; without it, a run whose `FIRING` was posted successfully passes, and the check turns green while magnetite's path stays broken.
  `ping` and `pingConfigFile` default to `null`, so S3's existing legs and every host but cinnabar are unchanged.
- **Boundary**: first-party; the script is this repository's.
- **Alternatives considered**: a separate timer or unit that pings when `fleet-deadman.service` last succeeded, rejected because it adds a unit whose own failure modes need a regulator and reads the result indirectly; healthchecks.io's `/start` signal and run-time measurement, rejected because a wedged run already withholds the ping (W6).

### D3: A failing run sends no ping (O3)

- **Choice**: a failing run sends nothing; healthchecks.io reports the check down when period plus grace pass without a success ping.
- **Rationale**: every cinnabar deploy that changes ntfy's environment file restarts `ntfy-sh.service` (`modules/machines/nixos/cinnabar/ntfy.nix:18`), and a run that coincides with the restart fails its probe; with `/fail` that single run would email, and with silence the next run's ping absorbs it within the grace.
  Silence also leaves one code path to test: a ping happens or it does not.
- **Alternatives considered**: `/fail` from an `EXIT` trap on a non-zero exit, which emails within one run of the failure rather than after the grace; it needs a second credential file holding the `/fail` URL, cannot fire when cinnabar is down or its egress is broken, and emails on every transient failure.

### D4: The ping step checks the answer and fails the run on anything else

- **Choice**: `fleetDeadmanPing` runs `curl -sS --max-time 10 --retry 2 -K -` with `curl-config` on stdin, sends an empty body, and fails unless the response body is exactly `OK`; its failure message names the body, never the URL.
  A failed ping fails the run, so the notifier posts `FAILED fleet-deadman on cinnabar` through ntfy.
- **Rationale**: an unknown UUID and a rate-limited ping both answer 200 (HC), so `curl -f` would count a mistyped URL as success and the check would never receive a ping.
  Failing the run on a failed ping puts a message through ntfy that explains the email that follows: the egress to `hc-ping.com` is broken, not the alert path.
  The step is a separate function taking `curl` as a parameter, as `fleetAlertDeadman` takes `ntfySend`, so the check can build it with a recording curl.
- **Boundary**: source versus delivered; the URL exists only in the delivered credential, and the script in the store reads it from `$CREDENTIALS_DIRECTORY`.
- **Alternatives considered**: logging a failed ping without failing the run, rejected because the operator then gets an email with nothing in ntfy to say the fleet is fine; a `POST` body carrying the run's summary, rejected because healthchecks.io stores bodies and nothing it would gain needs host or unit names.

### D5: The ping URL is a per-machine generator on cinnabar, read from stdin (O6)

- **Choice**: `clan.core.vars.generators.fleet-deadman-ping` in CFA, with `prompts.ping-url` (`type = "hidden"`, `persist = true`, a `display` group and label) and `files.ping-url.deploy = false`, as MG:404-430 declares `omnigraph-r2`.
  Its script fails unless the prompt matches `^https://hc-ping\.com/[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}$`, and writes `curl-config` with `printf 'url = "%s"\n'`.
  `services.fleet-alert.deadman.pingConfigFile` takes `clan.core.vars.generators.fleet-deadman-ping.files.curl-config.path`, never a literal, and FAN asserts the path is not under `builtins.storeDir`.
- **Rationale**: only cinnabar pings, so a shared generator would add readers with no use.
  curl's `-K -` reads the URL as configuration from stdin, so it never appears in `/proc/<pid>/cmdline`; the unit's environment carries only the credential's path.
  Validating the form at generation catches a pasted slug URL, a project ping key or stray whitespace before a deploy, which the `OK` check would otherwise catch only at the first run.
  The store-path assertion is a relation within cinnabar's own configuration, and it fails if a later edit points the option at a file written with `pkgs.writeText`.
- **Boundary**: source versus delivered; the plaintext exists only in the operator's prompt and in the sops-decrypted file at `/run/secrets/vars/per-machine/cinnabar/fleet-deadman-ping/curl-config`.
- **Alternatives considered**: the URL in an environment file, rejected because systemd exposes `Environment=` through `systemctl show` and the environment is inherited by every child; a URL on curl's argv, rejected by the constraint above; the Management API creating the check and returning its URL at generation time, rejected because it needs an API key secret, network access during `clan vars generate`, and a second vendor surface to test.

### D6: The check's period, grace and integrations live in healthchecks.io's interface (O5)

- **Choice**: the operator creates the check by hand with period 5 min, grace 10 min and an email integration, and the runbook records the values; acceptance observes the email, which tests the values that are actually set.
- **Rationale**: these are properties of the vendor's service, not of anything the flake builds, and the only regulator that can see them is the acceptance observation and any later real outage.
  A 5 min period matches the dead-man's timer; a 10 min grace absorbs one failed run and a timer that fires late.
  Worst case, an outage that starts just after a ping is reported about 15 min later; the free tier's 100 log entries cover the last 8 h.
- **Boundary**: vendored versus first-party; the check is configured outside the repository, so a change to it leaves no diff.
- **Alternatives considered**: declaring the check through the Management API from a deploy-time unit, rejected for the API-key secret and the reconciler it needs, and because drift between that unit and the vendor would still be seen only by observation.

### D7: Envelope E9.6 and regulator R9.6

- **Choice**:
  - Envelope E9.6, the external watch: the dead-man sends exactly one success ping per run that passes under D2, and nothing on any run that fails; an absence of success pings for period plus grace produces an email to the operator from outside the fleet.
  - Regulator R9.6, deterministic, build time, a leg of `checks.x86_64-linux.fleet-alert`: the dead-man, built with `ping` set to `fleetDeadmanPing` over the real curl, runs against S3's ntfy stand-in and a ping stand-in on loopback that records each request and answers a configured body.
    Its legs: a passing run with a heartbeat sends exactly one ping to the configured path; a probe answered 200, 500 or a closed port, a failed poll, and a failed post each send none; an empty window sends one `FIRING` and no ping; a stand-in answering `OK (not found)` fails the run.
    Its mutants, each of which the legs must reject: a dead-man that pings before the probe, and one whose ping step accepts any 200.
  - The ping step's transport leg, built with a recording curl in the pattern of `package-ntfy-send-test-token-transport`, asserts the URL is absent from argv and present on stdin, with a mutant passing the URL as an argument.
  - The runtime regulator of the whole watch is the acceptance negative control in the Migration Plan and, after it, healthchecks.io itself.
- **Rationale**: the legs compare the dead-man's behaviour, observed through the stand-ins, with expectations written in the legs, not with values rendered from the module, so they are not restatements.
  The probe and poll legs reuse S3's stand-in and its 200, 500 and closed cases, so R9.6 adds only the ping assertions and one stand-in.
- **Boundary**: first-party; the check builds the same functions cinnabar deploys.

### D8: Test selection

| Lane | What it covers | Host needed |
|---|---|---|
| Evaluation-time assertion | the ping credential's path is not under the Nix store (D5), shown able to fail by an `extendModules` override pointing it at a `writeText` file | none; cinnabar's toplevel |
| `checks.x86_64-linux.fleet-alert` | R9.6's legs and mutants, and the transport leg (D7) | none; nixbot |
| Deployment on cinnabar | the first accepted ping; the ntfy-stop control; the evaluator-stop control; 24 h without a false email (Migration Plan) | cinnabar and magnetite, with the operator present |

The evaluation cost of `checks.fleet-alert` is measured before and after against the 0.5 GiB budget; the new legs add derivations and no host evaluation.

### Spec deltas

No requirement that the active S4 change modifies is touched, so the two changes' deltas do not overlap except in the designation table.

- `fleet-alerting`: ADDED `An outage of the alert path reaches the operator by email from outside the fleet`, whose scenarios are the ntfy stop and the evaluator stop (O4); `A silent evaluator is reported from another host`, which S4 modifies, is left alone.
- `fleet-alerting-interface`: ADDED `The dead-man pings the watch service only after a passing run` and `The ping URL travels only as a credential read on stdin`; MODIFIED `The rule check runs promtool, fixture mutants and a property test`, which gains R9.6's stand-in and mutants, and `This capability states its own trust boundary`, whose ntfy-outage scenario now names the watch and which gains scenarios for the watch's configuration and the ping URL's secrecy; the capability's Purpose paragraph (`openspec/specs/fleet-alerting-interface/spec.md:6`) is edited at sync, since deltas carry no Purpose.
- `world-assumptions`: MODIFIED `Grounded vocabulary for behavioral requirements`, copying main's table whole and adding `watch service`, `email` and `ping`; MODIFIED A33, whose evidence and "A second delivery path appears" scenario record the watch; ADDED A53 (healthchecks.io's ping and lateness semantics), A54 (healthchecks.io runs outside the fleet, on Hetzner in Germany) and A55 (the operator's mailbox is reached without the fleet), numbered after S4's A50 to A52.

### Implementation surface: artifacts amended when ADR-009 Q5 resolves

The orchestrator records these under the next charter version entry (v26 at the time of writing), each an amendment in place.

- A9:7-9: the status line no longer excepts ADR-009 Q5.
- A9:181: the healthchecks.io entry leaves the rejected alternatives and becomes the adopted watch.
- A9:193-194: the Consequences state that the external watch reports an outage of cinnabar or ntfy by email within period plus grace, and that the watch adds an account and an egress.
- A9 "Operating envelope and regulator", "Failure prevented" and "Implementation surface": E9.6, R9.6, the generator and the option; A9:252's "no new listener" still holds.
- A9:264-266: ADR-009 Q5's resolution.
- FA:32 and FA:164-169: ADR-009 Q5 resolved, and the "Deferred" entry moves to the component's design.
- RA:73: the deferred external watcher node becomes healthchecks.io, pinged from cinnabar; RA:182-183, RA:280-281 and RA:286 follow, and RA's sequencing records that CAM-72 is unblocked.
- README:18, :34, :129, :142 and :214: ADR-009 Q5 is resolved by CAM-76.
- RB:145-146 and RB:816: the runbook states what the email means, how to read the check, how to pause it before cinnabar maintenance longer than the grace, and how to rotate the ping URL.
- SAT:425 and SAT:493 change when SAT is regenerated wholesale at archive, as `openspec/config.yaml` requires; it is not patched.

### Later slices

| Slice | Touches | Rule it must keep |
|---|---|---|
| S5 (CAM-72) | darwin agents | starts only after this change's ntfy-stop control is recorded (S3-RT:170-172) |
| any slice that restarts ntfy, caddy or zerotierone on cinnabar | the deploy | the restart completes within the grace, or the check is paused first |

## Risks / Trade-offs

- [Risk] An outage of `fsn1` that also takes healthchecks.io down produces no email (`[INFERENCE]`: its servers are on Hetzner in Germany, region not stated). → Accepted by the operator as residual (O2); the Monday test stays in place.
- [Risk] A cinnabar reboot or a deploy that restarts ntfy for longer than the grace sends a false email. → Mitigation: the runbook's pause step for planned maintenance; D3's silence on failure absorbs a single failed run.
- [Risk] The ping URL leaks and someone keeps the check green. → Mitigation: it lives only in sops and the credential directory; the runbook's rotation creates a new check, regenerates `fleet-deadman-ping` with its URL, deploys cinnabar and then deletes the old check, because a UUID cannot be changed (HC).
- [Risk] A mistyped URL makes every ping count for nothing. → Mitigation: D5's form validation at generation and D4's `OK` check at every run, which fails the unit and posts through ntfy.
- [Risk] The account lapses, its email integration is removed, or healthchecks.io changes its free tier, and nothing in the fleet notices. → Accepted; the Monday test still proves the ntfy path, and the operator receives healthchecks.io's own account mail.
- [Risk] S4's active `world-assumptions` delta copies main's designation table, as this change's will. → Mitigation: whichever archives second rebases its delta on the synced main before its sync, as S3 did with `share-ghq-reference-tree`.
- [Trade-off] A magnetite outage now produces two reports, `AlertEvaluatorSilent` through ntfy and the email (O4). → Accepted: they arrive by different paths, and only the email survives an outage that also takes down caddy.
- [Trade-off] healthchecks.io learns cinnabar's public address and a ping time every 5 min. → Accepted: the ping carries no body and no host or unit name.
- [Trade-off] The check's configuration leaves no diff in the repository (D6). → Accepted; the runbook records the values and acceptance observes them.

## Migration Plan

The change lands as two pull requests, merged in order:

| Pull request | Contains | Deploy |
|---|---|---|
| 1 | FAN's ping step, option and assertion; CFA's generator and option; the encrypted `vars/per-machine/cinnabar/fleet-deadman-ping/`; R9.6 and the transport leg | cinnabar |
| 2 | the charter entry and the amendments in "Implementation surface" | none |

1. Gated, the operator: create a healthchecks.io account and one check named for the dead-man, with period 5 min, grace 10 min and an email integration to an address not hosted on the fleet (O2, O5), and keep its ping URL.
2. Gated, the operator: run `clan vars generate cinnabar --generator fleet-deadman-ping` and paste the URL at the hidden prompt; the agent verifies only that `vars/per-machine/cinnabar/fleet-deadman-ping/curl-config/secret` exists and that no other generator's files changed.
3. Deploy cinnabar from pull request 1's head.
   Verified by: the dead-man's journal shows the ping accepted on each run for 30 min; healthchecks.io shows the check up with pings every 5 min; `systemctl show fleet-deadman -p Environment` names only the credential path; no `FAILED fleet-deadman` arrives.
4. Negative control, with the operator present: `systemctl stop ntfy-sh.service` on cinnabar, recording the time.
   Expected: the next dead-man run fails its probe; the healthchecks.io email arrives within 15 min of the last accepted ping; the time is recorded.
   Then `systemctl start ntfy-sh.service`; the next run pings and healthchecks.io sends its recovery email.
   Expected side effects, recorded rather than avoided: magnetite's heartbeats and any notifier posts fail while ntfy is stopped, so `AlertEvaluatorSilent` may fire and resolve after the restart, and `FAILED fleet-deadman on cinnabar` arrives once ntfy is back.
5. A second control (O4): stop `fleet-alert.timer` on magnetite for 20 min; `AlertEvaluatorSilent` arrives through ntfy and the email arrives; start it, and both recover.
6. Over the next 24 h, no healthchecks.io email arrives; cinnabar's journal counts the day's pings, and the check's log, which keeps its last 100 pings (about 8 h), is read at the end.
7. Pull request 2 merges; the orchestrator records step 4's times in CAM-76, and CAM-72 may start.

Rollback: pause the check in healthchecks.io first, so the rollback itself sends no email, then unset `pingConfigFile` and deploy cinnabar; the vars stay committed and unused, and the check is deleted once the rollback is final.

## Open Questions

None.
The operator answered on 2026-11-01 the five questions this design put, each as recommended:

1. O2, the channel and the shared region: email alone, with no Pushover or ntfy.sh channel, and the risk that an outage of Hetzner's region silences healthchecks.io together with cinnabar and magnetite is accepted as residual.
   Email already reaches the phone through the mail provider's own notifications, and the region risk is the same whichever channel is chosen, because healthchecks.io is the sender.
2. O3, failing runs: a failing run sends no ping and no `/fail` (D3).
   `/fail` would email on every single failed run, including one that meets an ntfy restart during a cinnabar deploy, and would need a second credential file.
3. O4, the heartbeat: the ping requires at least one heartbeat from magnetite's evaluator in the 10 min window (D2).
   It keeps the check red while caddy, cinnabar's resolver or magnetite's mesh path is broken (W3, W4), at the cost of the email beside `AlertEvaluatorSilent` when only magnetite is down (W5).
4. O5, period and grace: 5 min and 10 min, set in healthchecks.io's web interface and not in the flake (D6).
5. O6, the ping URL: the per-machine generator `fleet-deadman-ping` on cinnabar with a hidden, persisted prompt, and curl reading its configuration from stdin, never from argv (D5).
