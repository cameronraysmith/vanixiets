## ADDED Requirements

<!--
Stratum: interface.
Trust boundary: this property guarantees only that, when the flake is evaluated, the runtime tests that set a package set for their nodes evaluate those nodes against the same nixpkgs instance the fleet's hosts and homes use. It does not cover the runtime tests that set none: the five built with `pkgs.testers.runNixOSTest` (`caddy-root-from-vars`, `tuwunel`, the two `zerotier` tests and `postgresql-backup-restore`) take the per-system `pkgs` of `modules/nixpkgs/per-system.nix`, and the two `tincr` tests take the test framework's own. An equal derivation does not show that a runtime test behaves the same at run time. Nothing here constrains which packages that instance permits; the fleet's allowance is its own policy.
-->

### Requirement: Runtime tests evaluate against the fleet package set

Every runtime test under `vmTests.<system>` that sets its nodes' package set SHALL take it from the per-system `fleetPkgs` of the system it evaluates for and SHALL NOT instantiate a package set of its own. The drvPaths these tests keep rest on A330.

**Discharged by**: `rg -n 'import inputs\.nixpkgs' modules/vm-tests` returning no match; the cross-revision identity oracle showing no `vmTests` difference that its exact-path allow-list does not name with its cause.

#### Scenario: A runtime test's node package set

- **WHEN** `vmTests.x86_64-linux.greptimedb-pipeline` is evaluated
- **THEN** its nodes' `pkgs` is `fleetPkgs` for `x86_64-linux`, which carries `greptimedb-bin` and `ntfy-send` from the fleet overlay

#### Scenario: No runtime test instantiates a package set of its own

- **WHEN** `modules/vm-tests` is searched for `import inputs.nixpkgs`
- **THEN** no file matches, `perses-greptimedb.nix` and `shared-reference-tree.nix` included

#### Scenario: The moved tests keep their derivations

- **WHEN** the oracle compares the revisions before and after `perses-greptimedb` and `shared-reference-tree` move to `fleetPkgs`
- **THEN** every `vmTests` attribute the two modules define has the same drvPath, or its difference is named in the allow-list with its cause
