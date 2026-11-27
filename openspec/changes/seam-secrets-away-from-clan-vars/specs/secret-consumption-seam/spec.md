## ADDED Requirements

### Requirement: A feature names its secrets without naming the secret backend

A feature SHALL state the secrets it owns, and the secrets it uses that other features own, in terms that do not name the secret backend: their names, their recipes, their custody and whether hosts share them. Only the secret seam SHALL name the secret backend, apart from the checks and runtime tests that run a secret's recipe.

#### Scenario: A feature uses a secret another feature owns

- **WHEN** one feature uses a secret that another feature owns
- **THEN** it names the secret and takes its location from the secret seam, and states nothing about which tool produced or installed it

#### Scenario: A new reader of the backend appears

- **WHEN** a feature outside the secret seam starts naming the secret backend
- **THEN** a check fails and names that feature's file

### Requirement: Moving a feature behind the seam changes no delivered secret

Moving a feature's secrets behind the secret seam SHALL leave every delivered secret's name, location, recipe and custody unchanged, and SHALL leave every host's configuration, every home configuration and every runtime test unchanged; the checks it changes SHALL be declared differences of the refactor.

#### Scenario: A delivery step is compared

- **WHEN** the comparison of a delivery step's base commit and candidate commit is taken
- **THEN** every host's configuration, home configuration and runtime test is the same, and every check that differs is a declared difference of that step

#### Scenario: A recipe is changed while moving

- **WHEN** a delivery step changes a secret's recipe while moving it
- **THEN** the configuration of every host that installs that secret differs, and the step is not accepted

### Requirement: A home configuration receives its secrets without reading the host's secret backend

A home configuration SHALL take the location of each secret it reads from what its host gives it, and SHALL NOT read the host's secret backend. A home configuration built on its own, with no host, SHALL see no secrets and behave as it does today.

#### Scenario: A workstation home signs commits

- **WHEN** a person's home configuration on a workstation needs the key with which that person signs commits
- **THEN** it takes the key's location from what the host gives it, on a NixOS host and on a nix-darwin host alike

#### Scenario: A home built on its own

- **WHEN** a home configuration is built with no host
- **THEN** it sees no secrets, and configures no signing, as before

### Requirement: Replacing the secret backend changes only the seam

Once every delivery step has landed, replacing the secret backend SHALL require changing only the secret seam and the checks and runtime tests that run a secret's recipe, and SHALL require no change to any feature or home configuration.

#### Scenario: The backend is replaced

- **WHEN** a later change replaces the secret backend
- **THEN** the files it must edit are the secret seam and the named checks and runtime tests that run a recipe, and no others

### Requirement: A runtime test that runs a secret's recipe runs production's

A check or runtime test that produces a secret by running its recipe SHALL run the recipe the host that owns the secret runs in production, so that changing that recipe changes the test.

#### Scenario: The telemetry store's store credentials are moved behind the seam

- **WHEN** the delivery step that moves the telemetry store's store credentials lands
- **THEN** each runtime test that runs their recipe still runs the recipe the telemetry store's host declares, and is unchanged

### Requirement: Each delivery step is shippable alone

Each delivery step SHALL move every declaration and every use of the secrets it covers together, so that no secret is left declared partly through the secret seam and partly directly, and so that the repository after any prefix of the delivery steps is a consistent tree.

#### Scenario: A step's secrets are searched

- **WHEN** the repository is searched for the names of the secrets a step moves, before the step lands
- **THEN** every place that names them is a place the step changes, or a check or runtime test that runs a recipe

#### Scenario: A step is reverted

- **WHEN** the operator reverts the last delivery step that landed
- **THEN** the repository is the step's base commit and every host builds as it did there
