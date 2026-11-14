## ADDED Requirements

### Requirement: The coexistence interface's trust boundary is evaluated home configuration

The properties of this capability SHALL be stated of evaluated home-manager configurations and of the package set this flake exports, and SHALL NOT be read as establishing that no person runs the packaged `ovnfs` binary by hand, that no ovnfs checkout exists on a host, or that any working tree on a host was made by a particular tree creator.

#### Scenario: An ovnfs checkout is found on a host

- **WHEN** an ovnfs checkout of this repository is found on a host whose evaluated home leaves `programs.omp.ovnfs.enable` false
- **THEN** this capability is not violated, and the finding is a drift-report matter under the `vcs-surface-coexistence` requirement `Stray history stores and orphaned working trees are detected without changing anything`

### Requirement: ovnfs is packaged and enabled in no evaluated home

This flake SHALL export the `ovnfs` package, and `programs.omp.ovnfs.enable` SHALL evaluate to `false` in every home configuration this flake defines, so that omp's ovnfs instructions reach no agent.
This requirement relies on A101 and records the operator's decision of 2026-11-14 that ovnfs is not enabled in the near term.

#### Scenario: A home enables ovnfs

- **WHEN** any home configuration this flake defines evaluates `programs.omp.ovnfs.enable` to `true`
- **THEN** this requirement is violated

#### Scenario: The package is removed

- **WHEN** this flake no longer exports `ovnfs` for a system it previously built it for
- **THEN** this requirement is violated
