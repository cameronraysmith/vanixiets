## ADDED Requirements

### Requirement: Native authenticated DankGreeter configuration

The pyrite NixOS configuration SHALL enable native nixpkgs DankGreeter and greetd with native niri, DMS and Quickshell, disable GDM and GNOME, and register only the niri desktop session.
It SHALL select native greetd PAM for authenticated login and native dms-greeter PAM for the dedicated greeter account, preserve password authentication and login keyring integration, and provide no autologin, initial session, passwordless bypass or authentication wrapper.
Shared login PAM SHALL reject empty passwords for both greetd and console login, as explicitly approved by the user.
The dedicated greeter PAM service SHALL enable native systemd session registration for logind seat access, and login authentication SHALL retain the enabled, required native `pam_deny.so` rule.
For this unsynchronized configuration, `configHome` SHALL remain null, `configFiles` SHALL remain empty, and both the root synchronization `preStart` and generated `ExecStartPre` SHALL be absent.
Native greeter account/home/tmpfiles creation and greetd privilege separation SHALL remain enabled.

#### Scenario: Inspect the prepared login boundary

- **WHEN** the candidate's merged configuration is evaluated
- **THEN** greeter options originate in the pinned native module and the selected PAM rules delegate authenticated login to native login PAM
- **AND** the dedicated greeter account and niri-only session registration are distinct from cameron's desktop service
- **AND** login PAM retains Unix password authentication with `allowNullPassword=false` and no `nullok` option on authentication rules
- **AND** the greeter session enables native `pam_systemd.so` with its native `optional` control, while login auth ends in the enabled, required native deny module
- **AND** the unsynchronized greeter has no privileged synchronization hook and retains its native user/home/tmpfiles setup

#### Scenario: Reject regressions in the login boundary

- **WHEN** evaluation disables greeter PAM session registration, restores the native synchronization hook, or substitutes `pam_permit.so` for the login deny module
- **THEN** the corresponding configuration assertion fails

### Requirement: Typed and validated greeter compositor configuration

The greeter compositor configuration SHALL be generated through the unchanged epireyn configuration-only input, select native niri, set greeter mode and disable ordinary power-key handling.
It SHALL have no declared mutable includes or extra startup commands.
A flake check SHALL validate the actual custom configuration with the installed native niri and verify the native launcher and packaged greeter assets without starting them.

#### Scenario: Build the greeter configuration check

- **WHEN** `checks.x86_64-linux.pyrite-dankgreeter-config` is built on Linux
- **THEN** native niri validates the actual generated greeter configuration and the launcher and QML asset existence checks succeed

### Requirement: Preserve the prepared desktop and supporting policy

The candidate SHALL preserve B's single niri-scoped DMS owner, controls, bindings, lock PAM, native portal/polkit support, zero AC/battery suspend timers, 1800-second lock timers and existing supporting services.
It SHALL retain lid lock/lock/ignore, ordinary power-key ignore, manual suspend availability and existing boot/LUKS/SSH/network/hardware policy.
It SHALL NOT claim GNOME as a locking fallback after removing GDM.

#### Scenario: Compare against the prepared B configuration

- **WHEN** preserved interfaces are evaluated against B
- **THEN** desktop ownership, power policy, hardware safeguards and supporting services remain equivalent apart from the specified display-manager replacement and approved rejection of empty passwords in shared login PAM

### Requirement: Build evidence remains separate from physical acceptance

Preparation SHALL use immutable source revisions and SHALL NOT activate the candidate or disturb existing remote sessions or services.
Physical login/logout, rendering, locking, keyring, polkit and portal acceptance SHALL remain pending until separately observed.
Build receipts SHALL identify the exact final frozen revision; unchanged Nix blobs in a later metadata revision SHALL NOT substitute for an exact-revision system build.

#### Scenario: Complete the authorized remote build

- **WHEN** the private candidate revision is built on pyrite
- **THEN** build receipts identify the exact revision and outputs
- **AND** current and booted system paths, boot ID, existing GDM/SSH/greeter identities, inactive niri/DMS services and remote checkout state remain unchanged
