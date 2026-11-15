## ADDED Requirements

### Requirement: Declarative default bar auto-hide

The pyrite cameron DMS settings SHALL enable `autoHide` on the existing `default` bar while preserving its other settings and the existing false default for `showOnWindowsOpen`.

#### Scenario: Default bar settings are rendered

- **WHEN** the pyrite cameron DMS settings are rendered
- **THEN** the default bar has `autoHide` set to true and all other bar fields remain unchanged

### Requirement: Host-local Zen Browser

The pyrite cameron home package set SHALL contain exactly one wrapped Zen Browser, the beta variant from 0xc000022070/zen-browser-flake, following the root nixpkgs and home-manager inputs.
Its profile configuration is owned by workstation-parity design D10; other host and user package sets, existing browsers and browser defaults SHALL remain unchanged.

#### Scenario: Browser package is prepared

- **WHEN** the pyrite cameron home package set is built
- **THEN** it includes the `zen-beta.desktop` entry backed by the wrapped executable without a browser-default change

#### Scenario: Another configuration is evaluated

- **WHEN** another host or user configuration is evaluated
- **THEN** this addition does not install Zen Browser there
