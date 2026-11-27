## ADDED Requirements

### Requirement: The comparison runs in pre-activation and fails the activation

Each darwin host's `system.activationScripts.preActivation.text` SHALL include `home-manager-integration.uidPreflight`, which compares `id -u <account>` with each attachment's `uid` and SHALL exit non-zero, after comparing all, on any successful lookup that differs.

Trust boundary: activation stops before any change when `id -u` disagrees with the record (A370). Not covered: whether `id -u` sees nix-darwin's account (A374), service accounts, the already-set profile (A371).

#### Scenario: Matching and absent accounts

- **WHEN** `activate` runs on a host where every attachment's `id -u` prints its `uid`, or fails
- **THEN** the comparison exits 0 and activation continues to `checks`

#### Scenario: A mismatch

- **WHEN** `id -u` prints, for one attachment, a value other than its `uid`, including a non-numeric value
- **THEN** after comparing every attachment, the comparison prints to stderr one line per mismatched attachment carrying the host name, the account, the uid `id` printed, the recorded uid and the option path `flake.fleet.hosts.<host>.users.<account>.uid`, and exits non-zero, and `activate` exits before `checks`

#### Scenario: A host boots

- **WHEN** a host boots and nix-darwin's `activate-system` daemon runs
- **THEN** the comparison does not run (A372)

#### Scenario: Only darwin hosts render it

- **WHEN** a NixOS host's configuration is evaluated
- **THEN** its activation contains no comparison and its toplevel drvPath is unchanged by this requirement

### Requirement: The comparison is shown to fail on a mutant uid

`checks.x86_64-linux.darwin-uid-preflight`, a literally named check whose host list is read only in its value, SHALL run every darwin host's `home-manager-integration.uidPreflight` under a stub `id` and SHALL fail unless the matching and absent cases pass and the mutant-uid case fails naming its account.

Trust boundary: this guarantees the rendered text behaves as stated under a stub lookup. It does not observe any host's real accounts.

#### Scenario: The check's cases and size

- **WHEN** `checks.x86_64-linux.darwin-uid-preflight` and `testSizes.checks.darwin-uid-preflight` are read
- **THEN** each darwin host is run with every attachment at its `uid` (exit 0), every attachment absent (exit 0), and one attachment at `uid + 1` (non-zero exit and a line naming it), and the size entry is `{ class = "medium"; measured = false; }`

#### Scenario: The comparison is removed or inverted

- **WHEN** a throwaway tree renders an empty comparison, or one that passes a mismatch
- **THEN** `darwin-uid-preflight` fails on the mutant-uid case

#### Scenario: The comparison fails an absent account

- **WHEN** a throwaway tree renders a comparison that treats a failed lookup as a mismatch
- **THEN** `darwin-uid-preflight` fails on the absent case
