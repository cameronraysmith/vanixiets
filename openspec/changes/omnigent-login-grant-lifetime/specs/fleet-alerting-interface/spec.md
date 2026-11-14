## ADDED Requirements

### Requirement: The Omnigent server runs with a 90-day login grant lifetime

`systemd.services.omnigent` SHALL run with `OMNIGENT_GRANT_MAX_LIFETIME_DAYS = "90"`, from the same Nix binding the expiry query adds to `approved_at`.
Trust boundary: omnigent enforces the lifetime and purges aged grants; this machine only sets the variable.

**Discharged by**: magnetite's evaluated `systemd.services.omnigent.environment`, and after the deploy the unit's environment on magnetite; resting on world assumption `A105 — omnigent refuses a login grant's refresh once its age reaches a lifetime fixed at server start, and later purges it`.

#### Scenario: The lifetime is evaluated

- **WHEN** magnetite's configuration is evaluated
- **THEN** `systemd.services.omnigent.environment.OMNIGENT_GRANT_MAX_LIFETIME_DAYS` is `90`

### Requirement: The collector reads each owner's earliest login grant expiry as a column-limited role

On a host whose collector is enabled, the receiver `sqlquery/omnigent-grants` in the collector's `metrics/host` pipeline SHALL read the gauge `omnigent_login_grant_expiry_timestamp_seconds` every 60 s as the peer-authenticated PostgreSQL role `opentelemetry-collector`, which SHALL hold `SELECT` on `device_grants` only for `user_id`, `client_id`, `status` and `approved_at`.
Trust boundary: the series reports only what `device_grants` holds, which does not say which grant a worker holds.

**Discharged by**: magnetite's evaluated collector settings; a run of `omnigent-pg-grants`' grant and the query as the role on PostgreSQL 16; the query run read-only on magnetite; resting on world assumption `A105 — omnigent refuses a login grant's refresh once its age reaches a lifetime fixed at server start, and later purges it`.

#### Scenario: One series per owner alias

- **WHEN** the query runs over `device_grants`
- **THEN** it returns, per `omnigent_owner`, the alias of `flake.lib.otelCollectorSchema.ownerAliases` whose `flake.users.<owner>.meta.email` equals `user_id`, or `unaliased`, the minimum `approved_at` plus 7,776,000 over rows with `client_id = 'omnigent-cli'` and `status = 4`

#### Scenario: The role cannot read a token hash

- **WHEN** `opentelemetry-collector` selects `refresh_token_hash` from `device_grants`
- **THEN** PostgreSQL refuses with `permission denied for table device_grants`

#### Scenario: A collecting server host has no exporter for the series

- **WHEN** a host runs the Omnigent server with its collector enabled and its `metrics/host` pipeline has no exporter
- **THEN** that host's evaluation fails with the assertion naming the missing agent role

### Requirement: OmnigentLoginGrantExpiring warns 14 days before an owner's earliest expiry

The rule `OmnigentLoginGrantExpiring` SHALL be `omnigent_login_grant_expiry_timestamp_seconds - time() < 1209600`, `for` 15m, `warning`, with presence selector `omnigent_login_grant_expiry_timestamp_seconds` expected from the collecting NixOS hosts in `[ "magnetite" ]`.
Trust boundary: the alert reaches a person only through the existing alert path, and nothing here renews a worker.

**Discharged by**: `checks.x86_64-linux.fleet-alert`'s `promtoolRehearsal`, which runs `promtool test rules` on the rule and fails the mutant `grantThresholdInDays`; `modules/nixos/omnigent.nix`'s assertion that a collecting server host is among the rule's expected hosts; resting on world assumptions `A105 — omnigent refuses a login grant's refresh once its age reaches a lifetime fixed at server start, and later purges it` and `A106 — A login grant is revocable only by presenting its own token`.

#### Scenario: The rule fires within 14 days and not before

- **WHEN** promtool evaluates the rendered rules over owner-1's expiry 14 days and 1 hour after the epoch and owner-2's 24 days after it
- **THEN** no alert holds at 30 min, and at 2 h exactly one alert holds, labelled `omnigent_owner="owner-1"`, `host_name="magnetite"` and `severity="warning"`

#### Scenario: A threshold in days is rejected

- **WHEN** the rendered rule compares with `14` instead of `1209600`
- **THEN** `promtool test rules` fails the firing case, and `promtoolRehearsal` fails unless it does

#### Scenario: A collecting server host is not expected by the rule

- **WHEN** a host runs the Omnigent server with its collector enabled and is not among the rule's expected hosts
- **THEN** that host's evaluation fails with the assertion naming the rule's expected hosts
