## ADDED Requirements

### Requirement: The attribute query derives abandoned from the unproven status

The attribute query SHALL compute `abandoned` as `status = 'unproven'`, true for every unproven attribute whatever its reason and false for every other status, and the build-outcome query SHALL count an attribute as failing on its own when its status is `failed`, `failed_eval` or `unrecognised`.

**Discharged by**: `checks.x86_64-linux.devloop-queries`' fixtures (an `unproven` row with each of the four reasons, an `unproven` row with a null `error`, a `failed` row from a Mac attribute, an `unrecognised` row, and an `ignored_failure` row), which must return `abandoned` true for exactly the `unproven` rows and count the `failed` and `unrecognised` rows against their builds.

#### Scenario: Reasons do not matter

- **WHEN** the fixtures hold `unproven` rows with the errors `no builder reachable`, `builder lost`, `no progress for 300 s` and `not finished by the deadline`, and one with no error
- **THEN** each returns `abandoned` as `true`

#### Scenario: A Mac verdict

- **WHEN** the fixtures hold a `failed` row for `checks.aarch64-darwin.darwin-stibnite`
- **THEN** it returns `abandoned` as `false` and its build does not count as passed

#### Scenario: An unrecognised ending

- **WHEN** the fixtures hold an `unrecognised` row for `checks.aarch64-darwin.darwin-stibnite`
- **THEN** it returns `abandoned` as `false`, its build does not count as passed, and a count by `status` returns it apart from the `failed` row

## REMOVED Requirements

### Requirement: The attribute query derives abandoned from the shared marker

**Reason**: nixbot records an attribute that ended without a verdict with its own status, `unproven`, so `abandoned` no longer depends on matching error text against a marker shared with a patch.

**Migration**: replaced by `The attribute query derives abandoned from the unproven status`; `flake.lib.devloopCollection.abandonMarker` is deleted with its uses.

### Requirement: devloop-queries binds the abandonment marker to the patch's production code

**Reason**: `nixbot-abandon-optional-attributes.patch` is removed and nothing matches error text any more, so there is no marker to bind.

**Migration**: the marker clause of `checks.x86_64-linux.devloop-queries` is deleted; the status the query reads is pinned by the query fixtures of `The attribute query derives abandoned from the unproven status`.
