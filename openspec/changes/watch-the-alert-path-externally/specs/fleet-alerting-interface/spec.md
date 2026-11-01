## ADDED Requirements

### Requirement: The dead-man pings the watch service only after a passing run

When `services.fleet-alert.deadman.pingConfigFile` is set, as it SHALL be on cinnabar, `fleet-deadman.service` SHALL send one request with an empty body to the URL that file holds as the last step of a run whose R9.4 probe was refused with 403, whose poll of `fleet-heartbeat` held a message from the last 10 min and whose posts were all sent, SHALL fail the run unless the answer is exactly `OK`, and SHALL send nothing, not even `/fail`, on any other run.

**Discharged by**: regulator R9.6, the dead-man legs of `checks.x86_64-linux.fleet-alert` against the ntfy stand-in and the ping stand-in, with its mutants; the deployed dead-man's journal after the first cinnabar deploy; the operator's recorded stops of `ntfy-sh.service` on cinnabar and of `fleet-alert.timer` on magnetite; resting on world assumption `A53 — healthchecks.io counts a ping by its URL and emails when pings stop for longer than a check's period and grace`.

#### Scenario: A passing run pings once

- **WHEN** the ping stand-in answers `OK`, the probe is refused with 403, the poll returns one heartbeat and no post is pending
- **THEN** the run exits 0 and the ping stand-in records exactly one request, to the configured path, after the probe and the poll

#### Scenario: A failing run sends nothing

- **WHEN** the probe is answered 200, 500 or not at all, or the poll fails, or a post fails
- **THEN** the run exits non-zero and the ping stand-in records no request

#### Scenario: The heartbeat window is empty

- **WHEN** the probe is refused with 403 and the poll returns no heartbeat
- **THEN** one `[FIRING] AlertEvaluatorSilent` is posted, the run exits 0, and the ping stand-in records no request

#### Scenario: The watch service does not know the check

- **WHEN** the ping stand-in answers `200` with the body `OK (not found)`
- **THEN** the run exits non-zero with a message naming that body and not the URL, so the notifier posts `FAILED fleet-deadman on cinnabar`

#### Scenario: The deployed dead-man pings

- **WHEN** cinnabar has been deployed with the option set for 30 min
- **THEN** each run's journal records the ping accepted, the watch service lists one ping per run, and no `FAILED fleet-deadman` arrives

#### Scenario: The notification service is stopped at acceptance

- **WHEN** the operator stops `ntfy-sh.service` on cinnabar and starts it again after the email arrives
- **THEN** the runs during the stop fail their probe and send no request, the watch service's down email arrives within 15 min of the last accepted ping, and the first run after the start pings and the up email follows

#### Scenario: The evaluator's timer is stopped at acceptance

- **WHEN** the operator stops `fleet-alert.timer` on magnetite for 20 min, then starts it
- **THEN** the dead-man's runs post `AlertEvaluatorSilent` and send no request, the down email arrives, and after the start the `RESOLVED`, a ping and the up email follow

### Requirement: The ping URL travels only as a credential read on stdin

The per-machine generator `fleet-deadman-ping` on cinnabar SHALL take the ping URL through a hidden, persisted, undeployed prompt, reject any value that is not an `https://hc-ping.com/<uuid>` URL, and write the secret `curl-config`; `fleet-deadman.service` SHALL load it with `LoadCredential=external-ping:<path>` and give it to curl on stdin with `-K -`, and the `fleet-alert` module SHALL assert that `pingConfigFile` is not under the Nix store.

**Discharged by**: the ping step's transport test with a recording curl and its argv mutant; the store-path assertion, shown able to fail by an `extendModules` override; the generator's validation at the gated `clan vars generate`; `systemctl show fleet-deadman -p Environment` after the first cinnabar deploy.

#### Scenario: A value that is not a ping URL is entered

- **WHEN** at `clan vars generate cinnabar --generator fleet-deadman-ping` the prompt receives a value that does not match `^https://hc-ping\.com/[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}$`, such as a slug URL or one with trailing whitespace
- **THEN** the generator fails and writes no `curl-config`

#### Scenario: The ping step is run with a recording curl

- **WHEN** the transport test runs the ping step with a recording curl stub and a fixture configuration
- **THEN** the URL never appears in the stub's argument list and arrives on its stdin, and a mutant passing the URL as an argument fails the test

#### Scenario: The credential path points into the Nix store

- **WHEN** an `extendModules` override sets cinnabar's `pingConfigFile` to a file written with `pkgs.writeText`
- **THEN** cinnabar's evaluation fails on the `fleet-alert` module's assertion

#### Scenario: The deployed unit is inspected

- **WHEN** after the first cinnabar deploy the operator reads `systemctl show fleet-deadman -p Environment -p LoadCredential`
- **THEN** the environment names only the credential's path under `%d`, and `LoadCredential` names the `curl-config` path under `/run/secrets/`

## MODIFIED Requirements

### Requirement: The rule check runs promtool, fixture mutants and a property test

`checks.x86_64-linux.fleet-alert` SHALL run `promtool check rules` over the rendered YAML, run the evaluator in the build sandbox against a loopback fixture server that replays canned query responses and records every ntfy post, compare the jq transition function with a Python reference model over Hypothesis-generated timelines, run the dead-man with its ping step against the ntfy stand-in and a loopback ping stand-in that records each request (R9.6), and fail on each of its mutants, within an evaluation budget of 0.5 GiB.

**Discharged by**: the check's own mutants, each of which must produce a non-empty failure list, and the plan-time measurement of its evaluation cost with `NIX_SHOW_STATS`.

#### Scenario: The mutants are run

- **WHEN** the check runs its mutants: no state write, a `for` of 0, no store freeze, no absence freeze, a malformed expression, and a notifier template without `NTFY_TOKEN_FILE`
- **THEN** each produces a non-empty failure list, and the unmutated evaluator produces none

#### Scenario: The ping mutants are run

- **WHEN** the check runs a dead-man that pings before its probe and a ping step that accepts any `200`
- **THEN** the dead-man legs reject each, the first on a probe answered 200 that still pinged and the second on an `OK (not found)` answer that did not fail the run, and the unmutated dead-man passes every leg

#### Scenario: The check's evaluation cost is measured

- **WHEN** the check's derivation is evaluated with `NIX_SHOW_STATS`
- **THEN** its evaluation stays within the 0.5 GiB budget

### Requirement: This capability states its own trust boundary

This capability SHALL state what its properties guarantee and what they do not, and SHALL NOT be described, by itself or in any downstream report, as an end-to-end guarantee that an alert reaches a person.

**Discharged by**: the requirement's own statement in the scenarios below; no regulator applies.

#### Scenario: The properties above are read as a set

- **WHEN** the properties of this capability are read as a set
- **THEN** what they establish is that the evaluator queries each rule's database as `regulator` on the path its language names, that the rules render from one source to the evaluator and to `promtool`, that instance state, freezes, presence watching, titles, priorities, heartbeats, the dead-man and its ping behave as the fixture check, its mutants, its property test and the recorded acceptance observations show, and that ntfy is configured with the stated access entries, provisioning and proxy settings

#### Scenario: A guarantee about ntfy's enforcement is sought

- **WHEN** someone asks whether these properties guarantee that ntfy refuses an anonymous `fleet-*` publish, rate-limits each client separately, or delivers a message to a subscribed device
- **THEN** the answer is no: ntfy enforces the access entries and rate limits and delivers to subscribed devices, and this machine only configures it, which R9.4's probe and the acceptance observations monitor

#### Scenario: A guarantee about the token's secrecy is sought

- **WHEN** someone asks whether only the evaluator, the dead-man and the notifier can read the `alerter` token
- **THEN** the answer is no: any root process on magnetite or cinnabar can read it

#### Scenario: A guarantee about an ntfy outage is sought

- **WHEN** someone asks whether an outage of cinnabar or its ntfy is reported
- **THEN** the answer is that the dead-man stops pinging healthchecks.io, which emails the operator once the check's period and grace pass; healthchecks.io evaluates the period and grace and sends the email, the operator's mail provider delivers it, and this machine only pings, so nothing reports the outage if healthchecks.io fails at the same time

#### Scenario: A guarantee about the watch's configuration is sought

- **WHEN** someone asks whether the check's period, grace and email integration are as the runbook states
- **THEN** the answer is no: they are set in healthchecks.io's web interface, not by this machine, and only the acceptance stops and later outages observe them

#### Scenario: A guarantee about the ping URL's secrecy is sought

- **WHEN** someone asks whether only the dead-man can send a ping that keeps the check up
- **THEN** the answer is no: the URL is a bearer credential, any root process on cinnabar can read it, and anyone holding it can keep the check up while the alert path is down

#### Scenario: An end-to-end guarantee is sought

- **WHEN** someone asks whether these properties guarantee that an alert reaches a person
- **THEN** the answer is no: each stage's configuration, the fixture check and the recorded acceptance observations behave as stated, and nothing here observes an alert or an email reaching a person's device
