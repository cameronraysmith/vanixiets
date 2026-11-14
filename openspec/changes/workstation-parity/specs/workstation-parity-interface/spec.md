## ADDED Requirements

### Requirement: The parity interface's trust boundary is evaluated and delivered configuration

The properties in this capability SHALL be read as holding of evaluated NixOS, nix-darwin and home-manager configurations and of the files activation delivers from them, and of nothing beyond that boundary.
They SHALL NOT be cited as establishing that a vault or security key holds the key a public key names, that an unlock succeeds, that a host has deployed a key, that a window occupies the region a niri action requests, or that the two laptops feel equivalent.

#### Scenario: A remote login is claimed from evaluation alone

- **WHEN** a review cites an evaluated `users.users.cameron.openssh.authorizedKeys.keys` on magnetite containing a newly added key as evidence that pyrite reaches magnetite
- **THEN** the citation is incomplete until magnetite's deploy record shows the closure carrying that key and a remote login from pyrite with that key is observed

### Requirement: stibnite's properties are claimed from evaluation until its activation

aarch64-darwin attributes in this capability SHALL be claimed from evaluation only, until stibnite's operator-authorized activation builds and delivers them.

#### Scenario: A stibnite property is cited before activation

- **WHEN** a review cites stibnite's evaluated git signing key before stibnite has activated the configuration carrying it
- **THEN** the citation establishes the declaration only, not the delivered `~/.config/git` file

### Requirement: stibnite's operator home keeps Apple's SSH client

The `ssh` that the operator's home on stibnite resolves first SHALL remain Apple's `/usr/bin/ssh`, and a Nix OpenSSH client MUST NOT be placed ahead of it (A90).

#### Scenario: Resolve the SSH client on stibnite

- **WHEN** stibnite's operator home packages are evaluated, and `command -v ssh` is run in the operator's login shell after activation
- **THEN** no Nix `openssh` client is among the home packages, and `command -v ssh` prints `/usr/bin/ssh`

### Requirement: Commit signing uses no SSH agent and needs no touch

Commit signing on both laptops SHALL follow the `commit-signing-key-interface` capability: it MUST NOT go through an SSH agent, and a signer with no person present MUST sign without a touch or other interactive confirmation, under the signer principal the `commit-author-identity-interface` capability fixes.

#### Scenario: Evaluate an unattended signer's configuration

- **WHEN** the git signing configuration of an account an unattended agent signs from is evaluated
- **THEN** its signing program asks no key agent, its key signs without a touch, and its principal is the one `commit-author-identity-interface` fixes

### Requirement: Interactive SSH login goes through the Bitwarden agent with one pinned key per host

On both laptops, interactive SSH login SHALL go through the Bitwarden SSH agent, and the operator's SSH client configuration MUST pin, per host pattern, the one public key that host accepts, with `IdentitiesOnly`, so no host is offered more keys than its sshd's `MaxAuthTries`, which defaults to 6.
On pyrite, `*.zt` MUST be pinned to `~/.ssh/bitwarden-login.pub` and `github.com` to `~/.ssh/bitwarden-github.pub`.

#### Scenario: Log in to a host while the vault offers many keys

- **WHEN** the Bitwarden agent holds more keys than a host's `MaxAuthTries` and the operator opens a remote shell to that host
- **THEN** the client offers only the pinned key, and the host accepts the operator

### Requirement: pyrite's only SSH agent is Bitwarden's, unlocked through polkit

pyrite SHALL install `bitwarden-desktop` in `environment.systemPackages`, so that its polkit action `com.bitwarden.Bitwarden.unlock` loads, and the operator's home MUST enable `programs.bitwarden-ssh-agent` with home-manager's `services.ssh-agent` and `services.gnome.gcr-ssh-agent` disabled.

#### Scenario: Evaluate pyrite's agent configuration

- **WHEN** pyrite's system and cameron home are evaluated
- **THEN** `bitwarden-desktop` is a system package, the Bitwarden agent is enabled, and neither other agent is enabled

### Requirement: pyrite's touch unlock is confined to polkit

pyrite SHALL enable `pam_u2f` on the `polkit-1` PAM service only, with control `sufficient`, `cue`, origin and appid `pam://pyrite`, and the authfile from the committed `modules/machines/nixos/pyrite/u2f-keys`; the `polkit-agent-helper@` sandbox MUST admit the security key, and login and the DMS lock screen MUST stay password-only.

#### Scenario: Evaluate pyrite's PAM services

- **WHEN** pyrite's `security.pam.services` are evaluated
- **THEN** only `polkit-1` carries a `pam_u2f` rule with those settings, and the login, greeter and `dankshell` services carry none

### Requirement: pyrite's niri binds the decided chords from one chord table

pyrite's niri bindings SHALL be generated from one first-party chord table that maps each chord to an intent.
The table MUST map the launcher chord to `Mod+Space` running DMS's launcher, and the fill-screen chord to `Mod+Alt+F` running `maximize-window-to-edges`.
The pinned niri MUST validate the generated configuration.
Which physical key acts as `Mod` on pyrite's built-in keyboard is outside this requirement until decided.

#### Scenario: Evaluate and validate the chord bindings

- **WHEN** pyrite's cameron home is evaluated and its generated niri configuration is validated with the installed niri
- **THEN** `Mod+Space` runs the DMS launcher, `Mod+Alt+F` runs `maximize-window-to-edges`, every other existing bind is unchanged, and validation exits 0

### Requirement: pyrite's niri input and screenshots match stibnite's settings

pyrite's niri configuration SHALL set keyboard `repeat-delay` 225 and `repeat-rate` 33, touchpad `tap` true and `natural-scroll` false, and `screenshot-path` inside `~/Downloads`.

#### Scenario: Evaluate pyrite's input settings

- **WHEN** `programs.niri.settings.input` and `programs.niri.settings.screenshot-path` of pyrite's cameron home are evaluated
- **THEN** they hold the values this requirement names

### Requirement: pyrite's trust store carries the CAs stibnite trusts

pyrite's system trust store SHALL include the caddy `.zt` root certificate and the local k8s development CA certificate, taken from the same first-party source that stibnite's trust declarations use, so that the two laptops cannot diverge.

#### Scenario: Evaluate pyrite's trust store

- **WHEN** pyrite's `security.pki` certificates and stibnite's trust declarations are evaluated
- **THEN** both contain the same two certificates, byte for byte

### Requirement: Zen and its Bitwarden extension are declared on both laptops

The operator's home on both laptops SHALL configure Zen through the home-manager module of `0xc000022070/zen-browser-flake`, with the Bitwarden browser extension declared, and the `youwen5/zen-browser-flake` input MUST be removed.

#### Scenario: Evaluate the Zen declaration

- **WHEN** the operator's home on pyrite and on stibnite is evaluated
- **THEN** the Zen module is enabled with the Bitwarden extension declared, and `flake.lock` has no `youwen5/zen-browser-flake` node

### Requirement: rbw is declared on both laptops with a graphical pinentry

The operator's home on both laptops SHALL enable `rbw` with a graphical pinentry suited to that OS.

#### Scenario: Evaluate the rbw declaration

- **WHEN** the operator's home on pyrite and on stibnite is evaluated
- **THEN** `rbw` is enabled, and its pinentry is a graphical program rather than `pinentry-tty` or `pinentry-curses`

### Requirement: Fonts are declared in Nix on both laptops

The fifteen fonts currently installed on stibnite as Homebrew cask fonts SHALL be declared as Nix font packages on both laptops, and the Homebrew `caskFonts` list MUST no longer carry them.

#### Scenario: Evaluate the font declarations

- **WHEN** stibnite's Homebrew casks and both laptops' declared font packages are evaluated
- **THEN** no cask font remains, and each of the fifteen fonts is provided by a Nix package on both laptops

### Requirement: Linux has a Zed binary and darwin-only commands stay on Darwin

On Linux the operator's home SHALL set `programs.zed-editor.package` to a Zed package, while on Darwin it MUST remain null so the cask supplies the binary.
`dnsreset` MUST be installed only on Darwin, and `zerotier-join` MUST print its launchctl hint only on Darwin.

#### Scenario: Evaluate the platform-specific packages

- **WHEN** the operator's home on pyrite and on stibnite is evaluated
- **THEN** pyrite has a Zed package and no `dnsreset`, stibnite has a null Zed package and `dnsreset`, and pyrite's `zerotier-join` contains no `launchctl`
