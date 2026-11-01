## Why

Every alert, failure notice and dead-man post reaches a person only through ntfy on cinnabar, so an outage of cinnabar, ntfy, caddy or the mesh path to them is noticed only by a missing Monday `WeeklyPipelineTest`, up to 7 days later.
ADR-009 deferred Q5, whether something outside the fleet watches cinnabar, and charter v21 scheduled it as CAM-76 before S5 (CAM-72).
This change has cinnabar's dead-man ping a healthchecks.io check after each fully passing run, so a broken alert path produces an email that does not depend on cinnabar within about 15 minutes, and stibnite's collection work can start.

## What Changes

Decisions tagged `O<n>` were made by the operator on 2026-11-01; `brainstorm.md` records each, and `design.md` "Open Questions" lists O2 to O6 with their reasons.

**An external heartbeat from the dead-man**
- `fleet-deadman` pings a healthchecks.io check after a run that passes completely: the anonymous-publish probe was refused with 403, the heartbeat poll answered with at least one heartbeat from magnetite's evaluator in the window, and every pending post was sent (O1, O4).
- A run that fails any of those conditions, or does not run, sends nothing, neither a success ping nor `/fail`, so healthchecks.io emails the operator once the check's 5 min period and 10 min grace pass (O3, O5).
- Email is the only channel, and it does not depend on cinnabar; no push channel is added (O1, O2).
- The ping reads healthchecks.io's answer and fails the run on anything but `OK`, because an unknown check is answered `200 OK (not found)`.

**The ping URL as a secret**
- A per-machine clan vars generator `fleet-deadman-ping` on cinnabar takes the ping URL through a hidden, persisted prompt, as `modules/machines/nixos/magnetite/default.nix:404-422` takes the R2 keys, validates its form, and writes a curl configuration file (O6).
- `fleet-deadman.service` loads that file through `LoadCredential`, and curl reads it on stdin, so the URL never appears on a command line, in the unit's environment or in the Nix store.

**Regulators**
- R9.6, a new leg of `checks.x86_64-linux.fleet-alert`: the dead-man runs against the existing ntfy stand-in and a ping stand-in, and a fully passing run sends exactly one ping while each failing run and each run without a heartbeat sends none, with mutants that ping before the probe and that accept any 200.
- A package-style test of the ping step with a recording curl, asserting the URL arrives on stdin and never on argv, with a mutant that passes it on argv.
- At deployment, a deliberate stop of `ntfy-sh.service` on cinnabar produces the healthchecks.io email within 15 min of the last accepted ping and the recovery email after restart, and a 20 min stop of `fleet-alert.timer` on magnetite produces the email beside `AlertEvaluatorSilent`.

**Decision records amended through a charter version entry**
- From: ADR-009 lists a hosted dead-man service as rejected and defers its Q5; cinnabar is the single delivery path and nothing reports its outage (ADR-009:181, :193-194, :264-266).
- To: ADR-009 Q5 is resolved: healthchecks.io watches the dead-man, which watches magnetite's heartbeat through caddy and the mesh; ADR-009 gains envelope E9.6 and regulator R9.6; the component, reference architecture, observability README and runbook follow.
- Reason: the reasoning of ADR-009 Q5's original recommendation, that a cinnabar outage is noticed because `.zt` resolution breaks, weakened when S4's agents stopped depending on cinnabar's resolver (charter v23; ADR-009:195).
- Impact: non-breaking; adds one third-party account, one egress from cinnabar to `hc-ping.com`, and one secret.

## Capabilities

### New Capabilities

None.
The watch extends the existing alerting capabilities rather than adding a new area of behaviour.

### Modified Capabilities
- `fleet-alerting` (stratum: `behavioral`): a new requirement, `An outage of the alert path reaches the operator by email from outside the fleet`, covering an outage of cinnabar, its notification service or the path to it, and the evaluator's silence (O4), within 15 minutes; `A silent evaluator is reported from another host`, which the active S4 change modifies, is left unchanged.
- `fleet-alerting-interface` (stratum: `interface`): new requirements for the ping's conditions and the `OK` answer check, the ping URL's transport by credential and stdin, and R9.6 with its mutants; the trust-boundary requirement's ntfy-outage scenario is revised and gains scenarios for the watch.
  Trust boundary: healthchecks.io is trusted to evaluate the check's period and grace and to send the email, and this machine only pings it; the operator's mail provider is trusted to deliver the email; the ping URL is a bearer credential, so anyone holding it, including any root process on cinnabar, can keep the check green; the check's period, grace and integrations live in healthchecks.io's interface and are observed at acceptance, never asserted by the flake; nothing here guarantees that an email reaches a person, only that the ping is sent exactly when the dead-man's run passes, which the fixture check and the acceptance observations show.
- `world-assumptions` (stratum: `world`): A33's evidence that nothing reports an outage is revised under its existing "A second delivery path appears" scenario; new assumptions, numbered from A53 because the active `stand-up-linux-fleet-collection` change takes A50 to A52, record healthchecks.io's ping and lateness behaviour (A53), its hosting outside the fleet on Hetzner in Germany (A54), and the operator's mailbox being reached without the fleet (A55); the designation table gains `watch service`, `email` and `ping`.

## Impact

- Changed: `modules/nixos/fleet-alert.nix` (a nullable ping-configuration option on the dead-man, the ping step at the end of `fleetAlertDeadman`, the credential), `modules/machines/nixos/cinnabar/fleet-alert.nix` (the generator and the option), `modules/checks/fleet-alert.nix` and `modules/checks/fleet-alert/` (the ping stand-in, the legs and mutants).
- New secret: the per-machine generator on cinnabar holding the ping URL; nothing shared, no reader added on magnetite.
- New external dependency: a healthchecks.io account on the free tier, its check and its email integration, configured by hand in its web interface.
- Documentation: the charter version entry and the amendments to ADR-009, `components/fleet-alert.md`, `architecture/reference-architecture.md`, `docs/notes/development/observability/README.md` and the runbook; `traceability/satisfaction.md` is regenerated at archive.
- Deployment: one human step in healthchecks.io's interface, one `clan vars generate` with a hidden prompt, one cinnabar deploy, and two negative controls with the operator present: the ntfy stop on cinnabar and the evaluator-timer stop on magnetite.
- Residual risk, accepted by the operator (O2): an outage of Hetzner's `fsn1` that also takes healthchecks.io down produces no email (`[INFERENCE]`: healthchecks.io is hosted on Hetzner in Germany, region not stated); a broken phone subscription is still noticed only by the Monday test.
- Unblocks: CAM-72 (S5), whose start the S3 retrospective gates on an alert over a channel other than ntfy.
