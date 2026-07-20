## ADDED Requirements

### Requirement: The pyrite host provides a local GNOME desktop under GDM

The pyrite host module SHALL enable a stock GNOME desktop with `services.displayManager.gdm.enable = true` and `services.desktopManager.gnome.enable = true`, the two options nixpkgs seeds into `nixos-generate-config` at `nixos/modules/services/desktop-managers/gnome.nix:250-251`.
The desktop SHALL be system-level: no home-manager desktop configuration is required, because a stock GNOME session takes nothing from the admin user's already-imported home-manager.
niri and its Wayland shell assembly are NOT part of this capability; niri is the eventual daily-driver target and is deferred to a separate, reversible follow-up change deployed via `clan machines update`, and MUST NOT be assembled into this change.

#### Scenario: the two GNOME system options are set

- **WHEN** `nix eval .#nixosConfigurations.pyrite.config.services.displayManager.gdm.enable` and `nix eval .#nixosConfigurations.pyrite.config.services.desktopManager.gnome.enable` are evaluated
- **THEN** both return `true`
- **AND** these are the post-rename option paths at the pinned nixpkgs — not `services.xserver.displayManager.gdm` or `services.xserver.desktopManager.gnome`, which are renamed away — so the eval resolving at all is part of the check

#### Scenario: no home-manager desktop configuration is required

- **WHEN** the admin user cameron's home-manager is imported at the machine level and carries no desktop module
- **THEN** the GNOME session is nonetheless complete, because `services.desktopManager.gnome.enable` supplies the shell, portals, polkit agent, keyring, dconf, settings daemon, applet, and control center at system level
- **AND** the user side of the desktop is therefore near-zero and no home-manager desktop toggle is added by this change

#### Scenario: the machine reaches a graphical login

- **WHEN** the installed machine boots, the LUKS container holding the ZFS root is unlocked at the stage-1 prompt, and boot completes
- **THEN** the GDM greeter renders on the internal Retina panel, and an operator authenticating as cameron with the clan-generated user password (`clan vars get pyrite user-password-cameron/user-password`) reaches an interactive GNOME shell whose Activities overview responds
- **AND** `systemctl is-active display-manager` returning `active` is necessary but NOT sufficient evidence, because GDM reports `active` while `i915` KMS leaves the panel blank on the installed 6.18.37 kernel and while a session restart-loops back to the greeter — so the criterion is discharged only by a rendered greeter plus a reached, interactive shell observed at the machine
- **AND** the check depends on no audio, which is a Non-Goal, and on no network, since the login is local — which is what travel-readiness requires
- **AND** travel-readiness now also depends on a physical credential, because reaching this login means first passing the stage-1 unlock: an enrolled token seated with its client PIN typed, or the committed clan-vars passphrase typed as fallback

#### Scenario: enabling GDM does not perturb the stage-1 unlock prompt

- **WHEN** GDM is enabled on a machine whose root is unlocked by a stage-1 initrd prompt against a LUKS container (D1, D11)
- **THEN** the unlock prompt remains a stage-1 initrd event that unlocks the root before any graphical target starts, because `systemd.services.display-manager` is a stage-2 unit ordered after `systemd-user-sessions.service` (`nixos/modules/services/display-managers/gdm.nix:294-300`) and is reached only after the root the prompt gates is mounted
- **AND** GDM enables no plymouth: its only plymouth definition is guarded by `lib.mkIf config.boot.plymouth.enable` (`gdm.nix:313`), so with plymouth off per D11 the console ask-password path `systemd-cryptsetup` uses is unchanged, decidable by `nix eval .#nixosConfigurations.pyrite.config.boot.plymouth.enable` returning `false`
- **AND** the stage-1/stage-2 separation is unaffected by the FIDO2 enrollment, because disko forces `boot.initrd.systemd.enable = true` (`lib/types/luks.nix:354`) and that option was already true on this machine through `modules/system/initrd-networking.nix:7`, so the initrd's agent stack does not change
