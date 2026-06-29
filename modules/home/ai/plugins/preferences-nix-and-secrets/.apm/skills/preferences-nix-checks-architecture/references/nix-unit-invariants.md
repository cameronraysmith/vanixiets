# Nix-unit structural invariants

nix-unit validates structural properties of flake outputs that successful builds alone cannot verify.
This reference provides the test case template derived from the ironstar project and guidance on when invariants add value.

## The 6 test cases from ironstar

The ironstar project established 6 standard structural test cases that form a reusable template for any nix flake repository.

### TC-001: Flake outputs exist

Validates that the flake produces the expected top-level output categories.

```nix
# Assert devShells and checks exist for the target system
{
  testFlakeOutputs = {
    expr = builtins.attrNames (self.outputs);
    expected = assert builtins.elem "devShells" (builtins.attrNames self.outputs);
             assert builtins.elem "checks" (builtins.attrNames self.outputs);
             true;
  };
}
```

This catches regressions where a flake-parts module is accidentally removed or misconfigured, silently dropping an entire output category.

### TC-002: System devShells exist

Validates that devShells are defined for each supported system.

```nix
{
  testSystemDevShells = {
    expr = builtins.hasAttr system self.devShells;
    expected = true;
  };
}
```

### TC-003: Default devShell exists

Validates that a default devShell is defined, so `nix develop` works without specifying an attribute.

```nix
{
  testDefaultDevShell = {
    expr = builtins.hasAttr "default" self.devShells.${system};
    expected = true;
  };
}
```

### TC-004: System checks exist

Validates that checks are defined for the current system.

```nix
{
  testSystemChecks = {
    expr = builtins.hasAttr system self.checks;
    expected = true;
  };
}
```

### TC-005: Formatter configured

Validates that a formatter is defined for the current system.

```nix
{
  testFormatterConfigured = {
    expr = builtins.hasAttr system self.formatter;
    expected = true;
  };
}
```

### TC-006: Relational invariant (package-to-check coverage)

The most valuable test case.
Asserts that every package has a corresponding check, with an explicit exclusion list for packages that intentionally lack one.

```nix
let
  packageNames = builtins.attrNames self.packages.${system};
  checkNames = builtins.attrNames self.checks.${system};

  # Packages that intentionally have no corresponding check.
  # Each exclusion must have a comment explaining why.
  exclusions = [
    "default"            # alias, not a real package
    "release"            # meta-package, tested via constituents
    "mylib-clippy"       # is itself a check derivation
    "mylib-nextest"      # is itself a check derivation
  ];

  uncovered = builtins.filter
    (pkg: !(builtins.elem pkg exclusions) && !(builtins.elem pkg checkNames))
    packageNames;
in
{
  testPackageCheckCoverage = {
    expr = uncovered;
    expected = [];
  };
}
```

When a developer adds a new package without a corresponding check, this test fails and names the uncovered package.
The exclusion list is explicit and reviewable: adding a package to the exclusion list requires justification in the comment.


## The relational invariant design pattern

TC-006 exemplifies a general pattern applicable beyond package/check coverage.
The structure is: enumerate set A, enumerate set B, assert a relationship (coverage, naming convention, configuration consistency) between them, and document exclusions.

The pattern works for any cross-cutting relationship between independently-defined flake outputs.
Examples include verifying that every NixOS machine configuration has a corresponding deployment target, that every home-manager user has a corresponding secrets configuration, or that every module in a directory tree is imported somewhere.

The key properties of a well-designed relational invariant are explicit enumeration (no wildcards that silently pass when outputs are missing), documented exclusions (each exclusion has a comment), and actionable failure messages (the test output names the specific uncovered items).


## Vanixiets infrastructure invariants

The vanixiets repository defines 9 structural invariants specific to declarative infrastructure management.
These validate properties of the clan configuration, home-manager modules, secrets architecture, and machine fleet that are not exercised by building packages alone.

*clan-inventory-consistency* verifies that every machine listed in the clan inventory has a corresponding NixOS or nix-darwin configuration, and vice versa.
Drift between the inventory and the configuration tree means a machine is either declared but unconfigured or configured but invisible to clan provisioning.

*deployment-safety* validates that deployment-critical configurations (disk layout, bootloader, network identity) do not change without explicit intent markers.
This catches accidental changes to disko layouts or network addresses that could brick a remote machine.

*home-configurations-exposed* verifies that home-manager configurations are exposed as flake outputs for independent building and testing.

*home-module-exports* validates that home-manager modules defined in the module tree are actually imported by at least one machine or user configuration.
Orphaned modules indicate either dead code or a missing import.

*machine-registry-completeness* verifies that every machine in the fleet documentation table has a corresponding entry in the configuration tree.

*naming-conventions* enforces consistent naming across machine hostnames, user identifiers, secret paths, and module filenames.

*secrets-encryption-integrity* validates that all sops-encrypted files can be decrypted with the expected key set.
A missing key in `.sops.yaml` means a secret is encrypted for a key set that does not include all intended recipients.

*secrets-tier-separation* verifies that secrets are organized into the correct tier (machine-scoped, user-scoped, shared) and that cross-tier references do not exist.

*vars-user-password-validation* validates that clan vars for user passwords are defined for all machines that have those users, preventing machines from being provisioned without authentication credentials.


## When to add invariants vs rely on build/eval checks

Invariants enforce structural properties that build success cannot verify.
Building a package proves it compiles, but does not prove it has a test suite.
Evaluating a NixOS configuration proves it is well-typed, but does not prove it is consistent with the inventory.

Add an invariant when the property depends on cross-cutting relationships between independently-defined outputs.
Two developers can independently add a package and a check without coordinating; the TC-006 invariant catches when they forget the check.

Do not add an invariant when the nix module system already enforces the property.
If a module option has a type declaration, invalid values produce an evaluation error without any test.
Duplicating the module system's type checking in nix-unit adds maintenance burden without additional confidence.

A useful heuristic: if the failure mode is "this builds fine but does the wrong thing in production" or "this evaluates but is missing a piece that would only be noticed during deployment," an invariant likely adds value.
If the failure mode is "nix evaluation fails with a type error," the module system already handles it.
