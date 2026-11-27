## ADDED Requirements

<!--
Stratum: interface.
Trust boundary: these properties guarantee only that, when the flake is evaluated, fixture checks are evaluated against the same nixpkgs instance the fleet's hosts and homes use, and that the channels overlay offers no patched channel. Top-level outputs that import nixpkgs for their own purposes (nixidy's environments) are outside them. Nothing here constrains which packages that instance permits; the fleet's allowance is its own policy.
-->

### Requirement: Fixture checks evaluate against the fleet package set

Every check under `checks.<system>` that evaluates a home or system configuration against a package set it chooses SHALL take it from the per-system `fleetPkgs` of the system it evaluates for and SHALL NOT import nixpkgs itself. A check that evaluates configurations for several systems SHALL bind one `fleetPkgs` per system once and share it across them. The drvPaths these checks keep rest on A330.

**Discharged by**: `rg -n 'import inputs\.nixpkgs' modules/checks` returning no match; the cross-revision identity oracle showing every check that switched to `fleetPkgs` unchanged.

#### Scenario: The devin-worker check across two systems

- **WHEN** `checks.x86_64-linux.devin-worker-structural` evaluates its `x86_64-linux` and `aarch64-darwin` homes
- **THEN** it reads one package set per system, bound once, and its drvPath equals the revision before

#### Scenario: Checks, systems and homes are unchanged

- **WHEN** the oracle compares the revisions before and after the package-set move
- **THEN** every NixOS, darwin and home toplevel and every `checks.{x86_64-linux,aarch64-darwin}` attribute, including the `omnigent-workers` checks and `devin-worker-structural`, has the same drvPath

### Requirement: The channels overlay offers no patched channel

The overlay in `modules/nixpkgs/overlays/channels.nix` SHALL NOT define `patched`, and no repository document SHALL describe `pkgs.patched` as available. ADR-0017 SHALL carry a dated amendment stating that Layer 1 no longer exports `patched`, why, and that an upstream fix is applied per package with `overrideAttrs` and `fetchpatch` in an overlay.

**Discharged by**: `rg -n '\bpatched\b' modules/nixpkgs packages/docs/src/content/docs` returning only the amendment's own text; `just docs-build` succeeding; the oracle showing no drvPath difference outside the checks built from the docs site, whose amended pages change their source.

#### Scenario: A reader looks for the patching path

- **WHEN** a reader follows `guides/handling-broken-packages.md` to apply an unmerged upstream fix
- **THEN** the guide shows a per-package `overrideAttrs` with `fetchpatch` in an overlay and does not mention `pkgs.patched`
