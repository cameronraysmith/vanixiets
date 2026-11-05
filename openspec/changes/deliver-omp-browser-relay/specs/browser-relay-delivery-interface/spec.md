## ADDED Requirements

### Requirement: The extension package is omp's own install output for the deployed omp release

The flake SHALL expose a package `omp-browser-relay-extension` whose output is exactly the files `omp browser-relay install --dir <output>` writes when run, inside the build sandbox with `HOME` set to the build's temporary directory, by the omp package it is given, which by default is the omp the fleet deploys from the `llm-agents` input.
Its name SHALL carry that omp's version, and its build SHALL fail unless the first line of the output's `background.js` declares `OMP_INSTALL_VERSION` equal to that version.
The package SHALL depend on no fetched source other than the omp package.

#### Scenario: The package is built for the deployed omp

- **WHEN** `packages.aarch64-darwin.omp-browser-relay-extension` is built
- **THEN** the build succeeds, its output holds `background.js`, `manifest.json`, `options.html`, `options.js` and `LICENSE`, `background.js` begins with `const OMP_INSTALL_VERSION = "<omp version>";`, and `manifest.json`'s `version_name` is the same version

#### Scenario: The installer stamps a different version from the omp the package names

- **WHEN** the package is built with an omp whose installer stamps a version other than that omp's declared version
- **THEN** the build fails, naming the expected and the stamped version

### Requirement: Activation leaves a real, account-writable extension folder holding exactly the package

For an account whose Home Manager configuration enables `programs.omp.browserRelay.extension`, every activation that completes SHALL leave `programs.omp.browserRelay.extension.directory`, by default `~/.omp/browser-relay/extension`, as a directory that is not itself a symbolic link and whose resolved path is that path, holding regular files whose names and contents equal those of `programs.omp.browserRelay.extension.package`, each owned by and writable by that account, and no other file.
Activation SHALL refuse, failing without changing anything at that path, when the path is a symbolic link.

#### Scenario: The folder is inspected after activation

- **WHEN** an account's home configuration with the option enabled has been activated
- **THEN** `test -d` succeeds and `test -L` fails on the folder, `realpath` of the folder prints the folder's own path, `diff -r` against the package's output reports no difference, and every file in it is writable by that account

#### Scenario: The folder's path is a symbolic link before activation

- **WHEN** activation runs while `programs.omp.browserRelay.extension.directory` is a symbolic link
- **THEN** activation fails with a message naming the path and stating that it must be a real directory, and leaves the link and its target unchanged

#### Scenario: A newer omp release drops or renames a file

- **WHEN** activation runs with a package that no longer contains a file the folder holds from an earlier activation or from omp's updater
- **THEN** that file is absent from the folder after activation

### Requirement: The extension folder is delivered by default on darwin only

`programs.omp.browserRelay.extension.enable` SHALL default to true when the Home Manager configuration's host platform is darwin and to false otherwise, and its package SHALL by default be built from `programs.omp.package`.
A Home Manager configuration that does not enable the option SHALL contain no activation step that writes the folder.

#### Scenario: A Linux home configuration is evaluated

- **WHEN** a Home Manager configuration for an `x86_64-linux` or `aarch64-linux` account that enables omp is evaluated without setting the option
- **THEN** `programs.omp.browserRelay.extension.enable` evaluates to false and its activation contains no `ompBrowserRelayExtension` step

#### Scenario: The darwin home configuration is evaluated

- **WHEN** `homeConfigurations."crs58@aarch64-darwin"` is evaluated
- **THEN** the option evaluates to true, its package's omp version equals `programs.omp.package`'s version, and its activation contains the `ompBrowserRelayExtension` step

### Requirement: omp's managed configuration leaves the relay off by default

The `config.yml` that `managedConfigs` writes for omp SHALL NOT set `browser.relay`.

#### Scenario: The managed omp configuration is evaluated

- **WHEN** the declared content of omp's managed `config.yml` for any account is evaluated
- **THEN** it has no `browser.relay` key

### Requirement: The fleet sets no Helium extension or debugger policy

The fleet's configuration SHALL install no configuration profile carrying Chromium policy, and the defaults it writes for the `net.imput.helium` domain, at user or system level, SHALL carry none of the Chromium policy keys `ExtensionInstallForcelist`, `ExtensionInstallBlocklist`, `ExtensionInstallAllowlist`, `ExtensionSettings`, `DeveloperToolsAvailability` or `DisableScreenshots`.
Defaults that are not Chromium policy, such as the `SUAutomaticallyUpdate` key already written for that domain by `modules/darwin/system-defaults/custom-user-prefs.nix`, are outside this requirement.

#### Scenario: A darwin host's configuration is evaluated

- **WHEN** a darwin host's configuration and the Home Manager configurations it embeds are evaluated
- **THEN** no configuration profile carrying Chromium policy is declared, and no defaults declared for `net.imput.helium` contain any of the listed keys

### Requirement: Trust boundary of the delivery interface

These requirements SHALL be read as guaranteeing only what the flake builds and what Home Manager activation writes, observed by building the package and the darwin home and host checks and by inspecting the folder after activation.
They SHALL NOT be read as guaranteeing how Helium derives an extension's identity, whether a person has loaded the folder in any browser profile, what omp's relay writes into the folder between activations, whether omp honours or refuses a per-request relay choice, or any isolation between an agent and the person's browser once the extension is loaded; those rest on world assumptions A61, A62 and A63 and on omp itself.

#### Scenario: A property outside the boundary is claimed

- **WHEN** a verification report cites these requirements as evidence that a browser profile runs the current relay extension or that a session cannot drive the person's browser
- **THEN** the claim is out of bounds, and the report must cite runtime observation in the browser instead
