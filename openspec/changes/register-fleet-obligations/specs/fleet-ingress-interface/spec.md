## ADDED Requirements

### Requirement: The envelope budget has a declared shape

`vanixiets.otelCollector.envelopeBudget` SHALL be either `null` or a record of exactly `storeUrl` (a string), `notifiedUnits` (an attribute set of string lists, keyed by host) and `databases` (an attribute set of retention strings, keyed by database). A definition with any other field, or a field of another type, SHALL fail evaluation of the configuration that sets it. Typing the option SHALL leave the rendered `otel-envelope` program, and so the ingress host's toplevel, unchanged.

**Discharged by**: an `extendModules` mutant of magnetite's configuration that sets `envelopeBudget.storeURL` (misspelled), which fails evaluation naming the option; the cross-revision identity oracle showing `nixos-magnetite` and `vmTests.x86_64-linux.fleet-ingress` unchanged apart from any difference named under the fleet package set.

#### Scenario: A writer misspells a field

- **WHEN** an ingress configuration sets `vanixiets.otelCollector.envelopeBudget = { storeURL = "http://127.0.0.1:4000"; notifiedUnits = { }; databases = { }; }`
- **THEN** evaluation fails naming `envelopeBudget.storeURL` as an option that does not exist

#### Scenario: The existing writers

- **WHEN** magnetite's ingress role and the `fleet-ingress` test's store container set the budget
- **THEN** both evaluate, and the `otel-envelope` unit's `ExecStart` is the same store path as before

### Requirement: Each observability host row conforms to one schema

`flake.lib.observabilityHostProblems` SHALL return, for a host table, one message per row field outside the row schema, one per schema field missing from a row, and one per value of the wrong type. It SHALL return `[ ]` for `flake.lib.observabilityHosts`. The table SHALL remain a static value that its readers read without running the validator.

**Discharged by**: `checks.x86_64-linux.otel-collector-config`, which judges the real table (0 problems) and one mutant per rule (1 problem each) through `flake.lib.judgeCases`, with its drvPath unchanged.

#### Scenario: A row misspells a field

- **WHEN** a row sets `agentTelemtry = true`
- **THEN** the validator returns one message naming the unknown field and one naming the missing `agentTelemetry`, and `otel-collector-config` fails evaluation if the row is in the table

#### Scenario: The table as committed

- **WHEN** the validator is applied to `flake.lib.observabilityHosts`
- **THEN** it returns `[ ]`

### Requirement: The observability host row schema has nine typed fields

The row schema's fields SHALL be exactly `collect`, `platform`, `alwaysOn`, `smartDevices`, `textfile`, `agentTelemetry`, `langfuse`, `agentSpanQueueMiB` and `notifiedUnits`. `platform` SHALL be `"nixos"` or `"darwin"`; `collect`, `alwaysOn`, `textfile`, `agentTelemetry` and `langfuse` SHALL be booleans; `smartDevices` and `notifiedUnits` SHALL be lists of strings; `agentSpanQueueMiB` SHALL be a positive integer.

**Discharged by**: `checks.x86_64-linux.otel-collector-config`'s mutants, one per rule, each giving exactly one problem.

#### Scenario: A row gives a field the wrong type

- **WHEN** a row sets `agentSpanQueueMiB = 0`
- **THEN** the validator returns one message naming `agentSpanQueueMiB`

#### Scenario: A row names an unknown platform

- **WHEN** a row sets `platform = "linux"`
- **THEN** the validator returns one message naming `platform`
