## MODIFIED Requirements

### Requirement: Failure notices are posted to one topic

The machine SHALL define `observability-notify@.service` in `flake.modules.nixos.observability-notify`, posting through the one `ntfy-send` package to `fleet-alerts` with the `alerter` token and logging each posted `FAILED` in `/var/lib/observability-notify/failed.log`, and SHALL set `OnFailure=observability-notify@%n.service` on `greptimedb.service`, `greptimedb-schema.service`, `greptimedb-envelope.service`, `opentelemetry-collector.service` and magnetite's nine ZFS property oneshots.

**Discharged by**: the failure-wiring clause and notifier rehearsal of the evaluation-time collector check (R3.1) with their mutants, `checks.<system>.package-ntfy-send-test-token-transport` with its argv mutant, the token-wiring clause of `checks.x86_64-linux.fleet-alert` with its mutant, and the operator's recorded delivery of a forced failure after the access entries are in force.

#### Scenario: The failure wiring is evaluated

- **WHEN** the evaluation-time collector check (R3.1) reads magnetite's configuration
- **THEN** its failure-wiring clause finds every magnetite service named `greptimedb*`, `zfs-set-*`, `zfs-assert-*` or `opentelemetry-collector` listed in `services.observability-notify.units`, which today is `greptimedb.service`, `greptimedb-schema.service`, `greptimedb-envelope.service`, `opentelemetry-collector.service`, `zfs-set-root-greptimedb-quota`, `zfs-set-root-greptimedb-reservation`, `zfs-assert-root-greptimedb-noautosnap`, `zfs-assert-root-nix-noautosnap`, `zfs-assert-root-docker-noautosnap`, `zfs-assert-root-podman-noautosnap`, `zfs-set-root-nix-quota`, `zfs-set-root-nixos-reservation` and `zfs-set-root-home-reservation`, finds each listed name to be a unit with an `ExecStart`, and finds `OnFailure=observability-notify@%n.service` on each

#### Scenario: A new disk-share unit is not listed

- **WHEN** a mutant of magnetite's configuration adds a `zfs-set-root-foo-quota` service that `services.observability-notify.units` does not list
- **THEN** the evaluation-time collector check (R3.1) fails on its failure-wiring clause

#### Scenario: A listed name is not a unit

- **WHEN** a mutant lists a name in `services.observability-notify.units` for which magnetite defines no service of its own, so the wiring creates a unit with no `ExecStart`
- **THEN** the evaluation-time collector check (R3.1) fails on its failure-wiring clause

#### Scenario: A unit's failure handler is removed

- **WHEN** a mutant of magnetite's configuration drops `OnFailure` from one of the named units
- **THEN** the evaluation-time collector check (R3.1) fails on its failure-wiring clause

#### Scenario: The template is one module imported where it is needed

- **WHEN** magnetite's and cinnabar's configurations are evaluated
- **THEN** both define `observability-notify@.service` from `flake.modules.nixos.observability-notify`, magnetite through the collector's `agent` role and cinnabar by a direct import, with the option `services.observability-notify.units` unchanged

#### Scenario: The sender is one package

- **WHEN** the notifier and the home-manager `ntfy-send` command are evaluated
- **THEN** both resolve `ntfy-send` to `pkgs/by-name/ntfy-send`

#### Scenario: The notifier carries the alerter token

- **WHEN** the token-wiring clause of `checks.x86_64-linux.fleet-alert` reads magnetite's and cinnabar's configurations
- **THEN** it finds that the template loads the `ntfy-alerter` generator's `token` file through `LoadCredential` and sets `NTFY_TOKEN_FILE` to that credential, and that each notified unit's `ExecStartPost=` and `ExecStopPost=` hooks set `NTFY_TOKEN_FILE` to the same generator file's path, and a mutant template without `NTFY_TOKEN_FILE` makes the clause fail

#### Scenario: Each posted failure is logged

- **WHEN** the collector check's rehearsal runs the notifier's scripts against a temporary state directory and a recording `ntfy-send`, with one failure that posts and one that the 15-minute interval suppresses
- **THEN** `failed.log` gains exactly one line of the form `<epoch> <unit> <host>`, for the posted `FAILED`, and a mutant that drops the append makes the rehearsal fail

#### Scenario: A failure is delivered at first activation

- **WHEN** `greptimedb-envelope` is made to fail at first activation
- **THEN** a message naming `greptimedb-envelope.service` and magnetite appears on `fleet-alerts`, and the operator records it

#### Scenario: A failure is delivered after the access entries are in force

- **WHEN** after cinnabar's ntfy refuses anonymous publishing to `fleet-*`, `greptimedb-envelope` is made to fail on magnetite
- **THEN** a message naming `greptimedb-envelope.service` and magnetite appears on `fleet-alerts`, a line for it appears in `failed.log`, and the operator records both

### Requirement: Credentials exist only as activation-resolved files owned by non-worker users

Every store credential SHALL reach its consumer as a file resolved when magnetite's configuration is activated, readable only by its owner, owned by no omnigent worker account, and absent from the configuration that produced it.
Replacing the account file SHALL restart the telemetry store, and replacing the `collector` password SHALL restart the collector.

**Discharged by**: the evaluation-time ownership check (R8.2) with its mutant, magnetite's credential-holder assertion (R8.2), which admits `fleet-alert` as a `regulator-password` holder, and the evaluation-time envelope check (R7.1) with its restart-on-rotation mutant.

#### Scenario: The credential files are evaluated

- **WHEN** the evaluation-time ownership check (R8.2) reads magnetite's configuration
- **THEN** the account file is owned by `greptimedb` with mode `0400` and reaches the telemetry store through `LoadCredential`, each password file has mode `0400`, the `collector` password reaches the collector through `LoadCredential`, and the R2 generator's prompted values carry `deploy = false`

#### Scenario: A worker account owns a credential

- **WHEN** magnetite's configuration makes a worker account the owner of the `collector` password file
- **THEN** the evaluation-time ownership check (R8.2) fails, which its mutant shows

#### Scenario: A credential is loaded by a unit outside its holders

- **WHEN** magnetite's configuration is evaluated, which loads each password file into the units that name it
- **THEN** magnetite's credential-holder assertion (R8.2) finds `users` loaded only by `greptimedb`, `admin-password` only by `greptimedb-schema`, `collector-password` only by `opentelemetry-collector`, `regulator-password` only by `greptimedb-envelope` and `fleet-alert`, and `perses-password` by none, and an evaluation with a second unit loading `admin-password` fails on it

#### Scenario: The restart on rotation is removed

- **WHEN** magnetite's configuration drops `greptimedb.service` from the account file's restart list
- **THEN** the evaluation-time envelope check (R7.1) fails, which is one of its mutants

### Requirement: This capability states its own trust boundary

This capability SHALL state what its properties guarantee and what they do not, and SHALL NOT be described, by itself or in any downstream report, as an end-to-end guarantee that a series reaches the telemetry store or that a failure reaches a person.

**Discharged by**: the requirement's own statement in the scenarios below; no regulator applies.

#### Scenario: The properties above are read as a set

- **WHEN** the properties of this capability are read as a set
- **THEN** what they establish is that the telemetry store and its scrape targets listen only on loopback, that four accounts with fixed modes gate every `/v1/` path, that ingest and reads use the stated paths and headers, that the databases carry their declared retention, that object data is configured under one prefix of one bucket, that credentials exist only as activation-resolved files owned by non-worker users, that the store and collector run inside the declared envelope, that the queue is persistent and bounded, and that the named units hand their failures to the notifier, which posts with the `alerter` token, each as far as its own check, test or recorded first-activation observation reaches

#### Scenario: A guarantee about R2 is sought from this capability

- **WHEN** someone asks whether these properties guarantee that object data is durable or that the R2 token is scoped to the store prefix
- **THEN** the answer is no: the token's scope and the bucket's durability are set and provided by Cloudflare, and this machine does not assert them

#### Scenario: A guarantee about who can reach the loopback listener is sought

- **WHEN** someone asks whether loopback binding limits access to the named consumers
- **THEN** the answer is no: any root process on magnetite can reach the loopback listener, and only the account credentials distinguish it from the named consumers

#### Scenario: A guarantee about notice delivery or publishing is sought

- **WHEN** someone asks whether these properties guarantee that a failure notice reaches a person, or that only the notifier and the alert evaluator publish to `fleet-alerts`
- **THEN** the answer is no: ntfy on cinnabar enforces that only the `alerter` token publishes to `fleet-*`, and this machine only configures it; any root process on magnetite or cinnabar can read that token; and cinnabar is a single delivery path that nothing here watches

#### Scenario: An end-to-end guarantee is sought

- **WHEN** someone asks whether these properties guarantee that a given series reaches the telemetry store
- **THEN** the answer is no: each stage's configuration is checked and the tested pipeline behaves as stated, and nothing here observes the whole path on magnetite end to end
