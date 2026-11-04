## MODIFIED Requirements

### Requirement: Credentials exist only as activation-resolved files owned by non-worker users

Every store credential and every `otel-cert` key SHALL reach its consumer as a file resolved when its host's configuration is activated, readable only by its owner, owned by no omnigent worker account, and absent from the configuration that produced it.
Replacing the account file SHALL restart the telemetry store, replacing the `collector` password or a host's `otel-cert` SHALL restart that host's collector, and replacing the `perses` password SHALL restart `perses.service`, the only unit that loads it.

**Discharged by**: the evaluation-time ownership check (R8.2) with its mutant, magnetite's credential-holder assertion (R8.2), which admits `fleet-alert`, `devloop-reconcile` and `otel-envelope` as `regulator-password` holders and `perses` as the `perses-password` holder, the evaluation-time envelope check (R7.1) with its restart-on-rotation mutant, the `otel-cert` generator's `restartUnits`, and `perses-password`'s `restartUnits`.

#### Scenario: The credential files are evaluated

- **WHEN** the evaluation-time ownership check (R8.2) reads magnetite's configuration
- **THEN** the account file is owned by `greptimedb` with mode `0400` and reaches the telemetry store through `LoadCredential`, each password file and the `otel-cert` key have mode `0400` and are owned by no worker account, the `collector` password and the `otel-cert` key reach the collector through `LoadCredential`, the `perses` password reaches `perses.service` through `LoadCredential`, and the R2 generator's prompted values carry `deploy = false`

#### Scenario: A worker account owns a credential

- **WHEN** magnetite's configuration makes a worker account the owner of the `collector` password file
- **THEN** the evaluation-time ownership check (R8.2) fails, which its mutant shows

#### Scenario: A credential is loaded by a unit outside its holders

- **WHEN** magnetite's configuration is evaluated, which loads each password file into the units that name it
- **THEN** magnetite's credential-holder assertion (R8.2) finds `users` loaded only by `greptimedb`, `admin-password` only by `greptimedb-schema`, `collector-password` only by `opentelemetry-collector`, `regulator-password` only by `greptimedb-envelope`, `fleet-alert`, `devloop-reconcile` and `otel-envelope`, and `perses-password` only by `perses`, and an evaluation with a second unit loading `admin-password` or `perses-password` fails on it

#### Scenario: The restart on rotation is removed

- **WHEN** magnetite's configuration drops `greptimedb.service` from the account file's restart list
- **THEN** the evaluation-time envelope check (R7.1) fails, which is one of its mutants

#### Scenario: The perses password is replaced

- **WHEN** `greptimedb-users` is regenerated and magnetite is deployed
- **THEN** `perses.service` restarts with the new password, because `perses-password` lists it in `restartUnits`, and its next query through `greptimedb-promql` succeeds
