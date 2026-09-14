## ADDED Requirements

### Requirement: Reproducible checked-kernel wake candidate

The Pyrite boot candidate SHALL contain one replacement `hci_uart.ko` built from the selected Linux 6.18.42 source, native configuration, prepared headers, symbol table and compiler.
Its source difference SHALL be exactly the historical six-line power-transition wake omission, retaining the seven native UART constituent objects and all other power/error/suspend/resume behavior.
The runtime package SHALL exclude diagnostic sources, objects and kernel development references.

#### Scenario: Build the supported candidate

- **WHEN** the candidate is built for the checked kernel contract
- **THEN** source assertions and zero-fuzz patching succeed and the runtime output contains only the stripped replacement module
- **AND** the build does not compile a kernel image or compiler

#### Scenario: Selected inputs drift

- **WHEN** the kernel release or checked source/configuration/symbol-table/autoconf content differs
- **THEN** candidate evaluation or build fails rather than silently extending compatibility claims

### Requirement: Effective Pyrite module selection and preservation

The actual full Pyrite aggregate module tree SHALL select the candidate for both `hci_uart` and `acpi:BCM2E7C:APPLE-UART-BLTH:`.
The candidate SHALL preserve the selected kernel image, native Bluetooth dependencies, UART/LPSS/WiFi support, ZFS and CS8409 packages, and non-Bluetooth initrd content including encrypted-root support.
The source contribution SHALL be Pyrite-only, without native-module deletion, blacklisting or added Bluetooth initrd preload.

#### Scenario: Resolve the candidate by name and hardware alias

- **WHEN** module metadata lookup queries the aggregate tree by module name or the controller's ACPI alias
- **THEN** both resolve to the replacement package's module
- **AND** native dependencies and the existing extra modules remain selected

#### Scenario: Native selection regression

- **WHEN** the aggregate tree instead selects native `hci_uart`
- **THEN** the focused selection check fails

### Requirement: Separate artifact verification from hardware acceptance

Preparation records SHALL distinguish source/evaluation/build results from loaded-module attestation and hardware observations.
A store build SHALL NOT be reported as deployment or boot acceptance.
Acceptance records SHALL require separately authorized normal source-based deployment, a fresh candidate boot attested before manual intervention, adapter initialization and intended-headset pairing/acoustic observations in GNOME and niri.
These interface observations SHALL NOT be reported as proof of optimality or long-term suspend/reboot reliability.

#### Scenario: Store outputs verified without a fresh boot

- **WHEN** package, module-tree, initrd and system builds pass but no fresh candidate boot is attested
- **THEN** hardware acceptance remains explicitly pending

#### Scenario: Manual reload precedes attestation

- **WHEN** a driver reload or other intervention occurs before the candidate's fresh-boot identity is recorded
- **THEN** those observations do not satisfy the unassisted boot gate
