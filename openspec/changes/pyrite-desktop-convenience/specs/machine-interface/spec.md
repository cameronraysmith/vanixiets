## ADDED Requirements

### Requirement: Declarative default bar auto-hide

The pyrite cameron DMS settings SHALL enable `autoHide` on the existing `default` bar while preserving its other settings and the existing false default for `showOnWindowsOpen`.

#### Scenario: Default bar settings are rendered

- **WHEN** the pyrite cameron DMS settings are rendered
- **THEN** the default bar has `autoHide` set to true and all other bar fields remain unchanged

### Requirement: Host-local install-only Zen Browser

The pyrite cameron home package set SHALL contain exactly one wrapped Zen Browser from youwen5/zen-browser-flake revision `4036109214cf20632000558935bd823b901fa886`, following the root nixpkgs input.
Other host and user package sets, existing browsers, browser defaults and profile configuration SHALL remain unchanged.

#### Scenario: Browser package is prepared

- **WHEN** the pyrite cameron home package set is built
- **THEN** it includes a Zen Browser desktop entry backed by the wrapped executable without a browser-default or profile migration

#### Scenario: Another configuration is evaluated

- **WHEN** another host or user configuration is evaluated
- **THEN** this addition does not install Zen Browser there
