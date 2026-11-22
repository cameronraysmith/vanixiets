## MODIFIED Requirements

### Requirement: A database keeps its series for its retention and no longer

The fleet SHALL keep one telemetry store on magnetite with three databases, `fleet` with a retention of 30 days, `devloop` with a retention of 365 days and `agent` with a retention of 30 days, and the telemetry store SHALL return each database's series to a reader for that database's retention and SHALL NOT keep them past it.
A changed retention SHALL take effect on a database that already exists.

**Discharged by**: `telemetry-store-interface` requirements `Databases and their retention are set at the telemetry store` and `Object data lives under one prefix of one bucket`, resting on world assumption `A29 — Cloudflare R2 behaves as S3-compatible object storage for the telemetry store's client`; the container runtime test's retention case discharges it.

#### Scenario: The telemetry store starts with no databases

- **WHEN** the telemetry store starts for the first time
- **THEN** the databases `fleet`, `devloop` and `agent` exist with retentions of 30, 365 and 30 days, which the container runtime test confirms by reading each database's retention back

#### Scenario: A database already exists with a different retention

- **WHEN** the telemetry store starts while one of the three databases already exists with a retention other than its declared one
- **THEN** that database's retention is changed to the declared value rather than left as it was, which the container runtime test confirms by creating the database with another retention first

#### Scenario: agent's retention is shortened on the running store

- **WHEN** magnetite's schema job runs after the deploy that changes `agent` from 90 to 30 days
- **THEN** `agent` carries a retention of 30 days, which the operator reads back from the store and records, and no data is lost because `agent` held none

