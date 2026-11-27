## ADDED Requirements

<!--
Stratum: interface.
Trust boundary: the type rejects a malformed definition when the configuration that sets it is evaluated. It does not check that `storeUrl` reaches a store, that the named units exist on their hosts, or that the retention strings are ones the store accepts.
-->

### Requirement: The envelope budget has a declared shape

`vanixiets.otelCollector.envelopeBudget` SHALL be either `null` or a record of exactly `storeUrl` (a string), `notifiedUnits` (an attribute set of string lists, keyed by host) and `databases` (an attribute set of retention strings, keyed by database). A definition with any other field, or a field of another type, SHALL fail evaluation of the configuration that sets it. Typing the option SHALL leave the rendered `otel-envelope` program, and so the ingress host's toplevel, unchanged.

**Discharged by**: an `extendModules` mutant of magnetite's configuration that sets `envelopeBudget.storeURL` (misspelled), which fails evaluation naming the option; the cross-revision identity oracle showing `nixos-magnetite` and `vmTests.x86_64-linux.fleet-ingress` unchanged.

#### Scenario: A writer misspells a field

- **WHEN** an ingress configuration sets `vanixiets.otelCollector.envelopeBudget = { storeURL = "http://127.0.0.1:4000"; notifiedUnits = { }; databases = { }; }`
- **THEN** evaluation fails naming `envelopeBudget.storeURL` as an option that does not exist

#### Scenario: The existing writers

- **WHEN** magnetite's ingress role and the `fleet-ingress` test's store container set the budget
- **THEN** both evaluate, and the `otel-envelope` unit's `ExecStart` is the same store path as before
