## MODIFIED Requirements

### Requirement: Failure notices are posted to one topic

The machine SHALL define `observability-notify@.service` in `flake.modules.nixos.observability-notify` on every NixOS agent host, posting through the one `ntfy-send` package to `fleet-alerts` with the `alerter` token and logging each posted `FAILED` in `/var/lib/observability-notify/failed.log`, and SHALL set `OnFailure=observability-notify@%n.service` on the units the scenarios below name.

**Discharged by**: the failure-wiring clause and notifier rehearsal of the evaluation-time collector check (R3.1) with their mutants, the agent role's notified-unit assertion on every NixOS agent host, `checks.<system>.package-ntfy-send-test-token-transport` with its argv mutant, the resolve-hook assertion in `observability-notify.nix`, shown able to fail by an `extendModules` override, `checks.x86_64-linux.otel-collector-darwin`'s wrapper cases with the mutant `postEveryFailure`, and the operator's recorded deliveries.

#### Scenario: The darwin envelope posts through the notifier wrapper

- **WHEN** `org.nixos.otel-envelope` runs on a darwin agent host
- **THEN** On every darwin agent host `org.nixos.otel-envelope` SHALL run under `observability-notify-run`, which posts `FAILED <label> on <host>` and `RESOLVED <label> on <host>` through the same posting code and `ntfy-send` to `fleet-alerts` with the `alerter` token, at most one `FAILED` per label per 900 s, appending each posted `FAILED` to `/var/lib/otel-envelope/notify.log`, the log path its caller names.

#### Scenario: Each named unit has the failure handler

- **WHEN** magnetite's configuration is evaluated
- **THEN** `OnFailure=observability-notify@%n.service` is set on `greptimedb.service`, `greptimedb-schema.service`, `greptimedb-envelope.service`, `opentelemetry-collector.service`, `otel-envelope.service`, `devloop-reconcile.service`, `devloop-pg-grants.service`, `fleet-alert.service` and magnetite's nine ZFS property oneshots

#### Scenario: Every agent host notifies its collector and regulator

- **WHEN** any NixOS agent host's configuration is evaluated
- **THEN** `services.observability-notify.units` equals that host's `notifiedUnits` in `flake.lib.observabilityHosts` and includes `opentelemetry-collector` and `otel-envelope`, and the notifier carries the `alerter` token from the `ntfy-alerter` generator

#### Scenario: The failure wiring is evaluated

- **WHEN** the evaluation-time collector check (R3.1) reads magnetite's configuration
- **THEN** its failure-wiring clause finds every magnetite service named `greptimedb*`, `devloop-*`, `zfs-set-*`, `zfs-assert-*`, `opentelemetry-collector` or `otel-envelope` listed in `services.observability-notify.units`, finds each listed name to be a unit with an `ExecStart`, and finds `OnFailure=observability-notify@%n.service` on each

#### Scenario: A new disk-share unit is not listed

- **WHEN** a mutant of magnetite's configuration adds a `zfs-set-root-foo-quota` service that `services.observability-notify.units` does not list
- **THEN** the evaluation-time collector check (R3.1) fails on its failure-wiring clause

#### Scenario: The reconcile is not listed

- **WHEN** a mutant of magnetite's configuration drops `devloop-reconcile` from `services.observability-notify.units`
- **THEN** the evaluation-time collector check (R3.1) fails on its failure-wiring clause

#### Scenario: A listed name is not a unit

- **WHEN** a mutant lists a name in `services.observability-notify.units` for which magnetite defines no service of its own, so the wiring creates a unit with no `ExecStart`
- **THEN** the evaluation-time collector check (R3.1) fails on its failure-wiring clause

#### Scenario: A unit's failure handler is removed

- **WHEN** a mutant of magnetite's configuration drops `OnFailure` from one of the named units
- **THEN** the evaluation-time collector check (R3.1) fails on its failure-wiring clause

#### Scenario: The template is one module imported where it is needed

- **WHEN** the NixOS agent hosts' configurations are evaluated
- **THEN** each defines `observability-notify@.service` from `flake.modules.nixos.observability-notify` through the collector's `agent` role, cinnabar's direct import merging with it, with the option `services.observability-notify.units` unchanged

#### Scenario: The sender is one package

- **WHEN** the notifier, the darwin wrapper and the home-manager `ntfy-send` command are evaluated
- **THEN** each resolves `ntfy-send` to `pkgs/by-name/ntfy-send`

#### Scenario: The notifier carries the alerter token

- **WHEN** the NixOS agent hosts' configurations are evaluated
- **THEN** `observability-notify.nix`'s assertion holds that, with `tokenFile` set, each notified unit's `ExecStartPost=` and `ExecStopPost=` hooks run under `env NTFY_TOKEN_FILE=<tokenFile>`, and an `extendModules` override that replaces one unit's hooks makes evaluation fail

#### Scenario: Each posted failure is logged

- **WHEN** the collector check's rehearsal runs the notifier's scripts against a temporary state directory and a recording `ntfy-send`, with one failure that posts and one that the 15-minute interval suppresses
- **THEN** `failed.log` gains exactly one line of the form `<epoch> <unit> <host>`, for the posted `FAILED`, and a mutant that drops the append makes the rehearsal fail

#### Scenario: The darwin wrapper posts once per episode

- **WHEN** `checks.x86_64-linux.otel-collector-darwin` runs `observability-notify-run` for `otel-envelope` on stibnite over a recording `ntfy-send` with runs that pass, fail, fail and pass, and separately with a first run that fails
- **THEN** the first sequence posts exactly one `FAILED otel-envelope on stibnite` and one `RESOLVED otel-envelope on stibnite`, the first failing run posts `FAILED`, the token reaches `ntfy-send` only as `NTFY_TOKEN_FILE`, each posted `FAILED` is appended to the log path the caller names, and the mutant `postEveryFailure` fails the check

#### Scenario: NixOS notices are unchanged by the shared posting code

- **WHEN** the NixOS template calls the posting code it shares with `observability-notify-run`, naming `/var/lib/observability-notify/failed.log` as its log path
- **THEN** `checks.x86_64-linux.otel-envelope` and the notice cases of `vmTests.x86_64-linux.fleet-ingress` and `vmTests.x86_64-linux.fleet-ingress-outage` pass unchanged, and each posted `FAILED` is still appended to `failed.log`, which the alert evaluator's budget reads on magnetite

#### Scenario: A failure is delivered at first activation

- **WHEN** `greptimedb-envelope` is made to fail at first activation
- **THEN** a message naming `greptimedb-envelope.service` and magnetite appears on `fleet-alerts`, and the operator records it

#### Scenario: A failure is delivered after the access entries are in force

- **WHEN** after cinnabar's ntfy refuses anonymous publishing to `fleet-*`, `greptimedb-envelope` is made to fail on magnetite
- **THEN** a message naming `greptimedb-envelope.service` and magnetite appears on `fleet-alerts`, a line for it appears in `failed.log`, and the operator records both

#### Scenario: Another agent host's regulator fails

- **WHEN** cinnabar's `otel-envelope` fails at acceptance
- **THEN** a message naming `otel-envelope.service` and cinnabar appears on `fleet-alerts`, and the operator records it

#### Scenario: stibnite's regulator fails at acceptance

- **WHEN** stibnite's `otel-envelope` fails because the operator stopped `org.nixos.otelcol` for two envelope periods
- **THEN** `FAILED otel-envelope on stibnite` appears on `fleet-alerts` and in `/var/lib/otel-envelope/notify.log`, and the operator records both

