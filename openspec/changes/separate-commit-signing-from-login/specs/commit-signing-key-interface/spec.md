## ADDED Requirements

### Requirement: The signing interface's trust boundary is evaluated configuration, recorded public keys and recorded recipients

The properties in this capability SHALL be read as holding of evaluated NixOS, nix-darwin and home-manager configurations, the files activation delivers from them, the public keys in `flake.users.<key>.meta`, and the sops recipients recorded in this repository, and of nothing beyond.
The limits below SHALL NOT be cited as checked.

#### Scenario: A delivered key is claimed from evaluation alone

- **WHEN** a review cites a passing `checks.x86_64-linux.nixos-magnetite` as evidence that Cameron's worker on magnetite no longer holds his login key
- **THEN** the citation is incomplete until `omnigent-worker-verify` has passed as `omnigent-cameron` on magnetite after magnetite's activation, because no check reads a delivered private key

#### Scenario: A hand-edited authorized_keys file is claimed as covered

- **WHEN** a review cites `signingKeyUnauthorized` as covering an account's `~/.ssh/authorized_keys`
- **THEN** the citation is wrong: that file is mutable state outside configuration, and only configured login sources are judged

#### Scenario: Other limits are claimed as covered

- **WHEN** a review cites this capability for a forge's signing registrations, for the login key itself, for a `valid-before` bound beyond the time a commit claims (A91), for stibnite's standalone worker home beyond its system-level declaration, or for darwin obligations as regulated in CI, where `checks.aarch64-darwin` is evaluated best-effort
- **THEN** the citation is wrong, because none of these is observed by any check here

### Requirement: Each profile records one signing key

`flake.users.<key>.meta` SHALL declare `signingKey`, an OpenSSH `ssh-ed25519` public key line with no default, and `retiredSigningKeys`, a list of `{ key; validBefore; }` where `key` is such a line and `validBefore` is null or a UTC timestamp `YYYYMMDDhhmmssZ`, defaulting to the empty list.

#### Scenario: Cameron's profile is evaluated

- **WHEN** `nix eval .#users.crs58.meta.signingKey` and `nix eval .#users.crs58.meta.retiredSigningKeys` are evaluated
- **THEN** the first is a key absent from every profile's `sshKeys`, and the second contains `ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINdO9rInDa9HvdtZZxmkgeEdAlTupCy3BgA/sqSGyUH+`

### Requirement: A profile's signing key is none of the fleet's login keys

For every profile, the key material of `signingKey` (its type and base64 fields, ignoring any comment) SHALL differ from that of every entry of every profile's `sshKeys` and of its own `retiredSigningKeys`, and `checks.x86_64-linux.commit-signing-key` SHALL assert this over every `flake.users` entry.

#### Scenario: The mutants are evaluated

- **WHEN** `checks.x86_64-linux.commit-signing-key` applies the predicate to `signingKeyIsLoginKey` (`signingKey` is `head meta.sshKeys`, the key `expected.signingPublicKey` named before this change), `signingKeyIsRecommentedLoginKey` (the same key with another comment) and `signingKeyIsOthersLoginKey` (another profile's login key)
- **THEN** each fails the predicate, and the check fails if any of these outcomes is inverted

### Requirement: Every configured login source of a host is enumerated

`flake.lib.commitSigningObligations.loginSources` SHALL return, for one evaluated host configuration, each `users.users.<name>.openssh.authorizedKeys.keys` entry of every declared account, `root` included, on NixOS and nix-darwin, and on NixOS each `boot.initrd.network.ssh.authorizedKeys` entry.

#### Scenario: magnetite's sources are enumerated

- **WHEN** `loginSources` is applied to `nixosConfigurations.magnetite.config`
- **THEN** it includes entries for `root`, `cameron`, `crs58` and every Omnigent worker account, and the initrd's entries where magnetite enables initrd SSH

### Requirement: A login source the enumeration cannot read fails closed

`loginSources` SHALL report as unjudgeable, which `signingKeyUnauthorized` counts as a failure, any non-empty `authorizedKeys.keyFiles` or `boot.initrd.network.ssh.authorizedKeyFiles`, an `authorizedKeysCommand` other than `"none"`, and an `authorizedKeysFiles` entry, or a file named by an `AuthorizedKeysFile` or `AuthorizedKeysCommand` line of `services.openssh.extraConfig`, other than `/etc/ssh/authorized_keys.d/%u` and `%h/.ssh/authorized_keys`.

#### Scenario: cinnabar's sshd file list is read

- **WHEN** `nixosConfigurations.cinnabar.config.services.openssh` is evaluated
- **THEN** `authorizedKeysCommand` is `"none"`, `authorizedKeysFiles` is `[ "/etc/ssh/authorized_keys.d/%u" ]` and its rendered `extraConfig` names only that file, as evaluated on 2026-11-13, so no current host is unjudgeable

### Requirement: No login source on any host carries a signing key

The case `signingKeyUnauthorized` of `flake.lib.commitSigningObligations.failures` SHALL fail on a host if the key material of any login source equals that of any profile's `signingKey` or of any worker's `credentials.expected.signingPublicKey` on that host.
`modules/checks/machines.nix` SHALL assert `commitSigningObligations.failures` on every `nixos-<machine>` and `darwin-<machine>` check, and the predicate SHALL be exposed as `flake.lib.commitSigningObligations.unauthorized`.

#### Scenario: A signing key is authorized for root

- **WHEN** a module adds Cameron's `signingKey` to `users.users.root.openssh.authorizedKeys.keys` on any NixOS host
- **THEN** that host's machine check fails naming `signingKeyUnauthorized`

#### Scenario: The mutants are evaluated

- **WHEN** `checks.x86_64-linux.commit-signing-key` applies `unauthorized` to one correct synthetic host and to seven mutants: a signing key in an ordinary account's keys, in `root`'s keys, in the initrd's keys, a signing key under another comment, a non-empty `keyFiles`, an `authorizedKeysCommand`, and an `extraConfig` `AuthorizedKeysFile` line naming an extra file
- **THEN** the control holds and each mutant fails, and the check fails if any of these eight outcomes is inverted

### Requirement: Every person's home signs with the signing key file

`flake.modules.homeManager.vcs-signing`, key `vanixiets/vcs-signing-home-module`, imported by `development`, SHALL declare `sops.secrets.commit-signing-key` with mode `0400` and set git's `signing` to `{ key = <that secret's path>; format = "ssh"; signByDefault = true; }` and jj's `signing` to `{ behavior = "own"; backend = "ssh"; key = <that secret's path>; }`.
`git.nix` and `jujutsu.nix` SHALL set no signing key, and `git.nix` SHALL have no darwin signing branch.

#### Scenario: stibnite's human home is evaluated

- **WHEN** `darwinConfigurations.stibnite.config.home-manager.users.crs58.programs.git.signing.key` is evaluated
- **THEN** it is the `commit-signing-key` secret's path, not the `ssh-public-key` secret's path it was before this change

### Requirement: Every person's home signs through the agent-free program

`vcs-signing` SHALL set git's `gpg.ssh.program` and jj's `signing.backends.ssh.program` to `flake.lib.agentFreeSshKeygen pkgs`, a program that removes `SSH_AUTH_SOCK` from its environment and then runs nixpkgs' `ssh-keygen` by store path with its own arguments, on Linux and on darwin.

#### Scenario: stibnite's programs are evaluated

- **WHEN** git's `gpg.ssh.program` and jj's `signing.backends.ssh.program` are evaluated for `home-manager.users.crs58` on stibnite
- **THEN** both are the store path of `agentFreeSshKeygen` for stibnite's packages

### Requirement: The agent-free program never asks a key agent

`checks.x86_64-linux.commit-signing-key` SHALL run a key agent that logs every request and holds a test key added with confirmation required, set `SSH_AUTH_SOCK` to it, and require `-Y sign -f <test private key> -n git` through `agentFreeSshKeygen` to succeed with no request logged after the key was added.

#### Scenario: The mutant is run

- **WHEN** the same invocation is run through plain `ssh-keygen`
- **THEN** the agent logs a request, and the check fails if it does not

### Requirement: A home's signing configuration is regulated on every host

The case `homeSigningBound` of `commitSigningObligations.failures` SHALL fail on a host if, for any `home-manager.users.<name>` that is a `flake.users` key, git's and jj's signing keys differ from each other or from that home's `commit-signing-key` path, either program differs from `agentFreeSshKeygen` for that host's packages, or the signers file differs from the lines the obligation assembles from `meta.signingKey`, `meta.retiredSigningKeys` and `meta.gitEmail`.

#### Scenario: The darwin branch returns

- **WHEN** git's signing key on a darwin home is set back to the `ssh-public-key` secret's path
- **THEN** that host's machine check fails naming `homeSigningBound`

#### Scenario: The mutants are evaluated

- **WHEN** `checks.x86_64-linux.commit-signing-key` applies the predicate to `homeConfigurations."ubuntu@x86_64-linux"`, one correct synthetic home, and four mutants: git's key at the `ssh-public-key` path, no program set, jj's key at the `ssh-signing-key` path, and a signers file missing the retired key's line
- **THEN** ubuntu's home and the control hold and each mutant fails, and the check fails if any outcome is inverted

### Requirement: The signers file lists the signing key and each retired key under the author address

`vcs-signing` SHALL write `~/.config/git/allowed_signers` from `flake.lib.allowedSigners` as the line `<vcs.author.email> namespaces="git" <meta.signingKey>` and, per `retiredSigningKeys` entry, `<vcs.author.email> namespaces="git"[,valid-before="<validBefore>"] <key>`, the option present when `validBefore` is not null; git's `gpg.ssh.allowedSignersFile` and jj's `signing.backends.ssh.allowed-signers` SHALL name that file.

#### Scenario: Cameron's signers file in phase A

- **WHEN** `homeConfigurations."crs58@x86_64-linux".config.xdg.configFile."git/allowed_signers".text` is evaluated after phase A
- **THEN** it holds two lines with principal `cameron.ray.smith@gmail.com`: his signing key, then his login key with no `valid-before`

#### Scenario: Cameron's signers file in phase B

- **WHEN** the same attribute is evaluated after phase B
- **THEN** the login key's line carries `valid-before="<cutover>"`, where `<cutover>` is the `validBefore` recorded in his profile

#### Scenario: A retired signature is verified around the cutover

- **WHEN** `checks.x86_64-linux.commit-signing-key` verifies, through `agentFreeSshKeygen`, a signature by a retired test key against a signers line with `valid-before`, once with `-Overify-time` before the bound and once after it
- **THEN** the first succeeds and the second fails

### Requirement: Each worker's signers file stays one line

Each Omnigent worker's signers file SHALL remain the single line `<credentials.expected.gitEmail> namespaces="git" <credentials.expected.signingPublicKey>`, with no retired key.

#### Scenario: Cameron's worker signers file is evaluated

- **WHEN** the signers file of `omnigent-cameron` on magnetite is evaluated
- **THEN** it holds one line naming `flake.users.cameron.meta.signingKey`

### Requirement: A worker's declared signing key is its owner's signing key

The inventory SHALL set each worker's `expected.signingPublicKey` to `flake.users.${owner}.meta.signingKey`, and `declaredCredentials` in `omnigentFleetObligations` SHALL compare it with `meta.signingKey` read directly.
The case `workerSigningKey` of `commitSigningObligations.failures` SHALL fail on any NixOS or darwin host where a worker's `expected.signingPublicKey` differs from its owner's `signingKey` or matches any profile's `sshKeys` entry.

#### Scenario: Cameron's workers are evaluated

- **WHEN** `services.omnigent-host.workers.cameron.credentials.expected.signingPublicKey` is evaluated on magnetite, pyrite and stibnite
- **THEN** each equals `flake.users.cameron.meta.signingKey`, and `commitSigningObligations.failures` is `[]` on all three

#### Scenario: The expected key is the login key

- **WHEN** `checks.x86_64-linux.omnigent-worker-inventory` applies `workerSigningKey` to `expectedLoginKey`, a worker whose `expected.signingPublicKey` is its owner's `head meta.sshKeys`
- **THEN** the predicate fails, and the check fails if it holds

#### Scenario: The delivered worker key still is the login key

- **WHEN** a worker host deploys with `expected.signingPublicKey` set to the owner's signing key while the worker's delivered key file still holds the owner's login key
- **THEN** `omnigent-worker-verify` fails with `signing public key mismatch`

### Requirement: A signing key is no decryption identity

`checks.x86_64-linux.commit-signing-key` SHALL fail if the `ssh-to-age` recipient of any profile's `signingKey` appears in `.sops.yaml`, any `sops/users/*/key.json` or `sops/machines/*/key.json`, or the sops metadata of any file under `secrets/` or any `secret` file under `vars/`.
It SHALL fail closed on an empty recipient set, a file it cannot parse in its sops format, or an `ssh-to-age` error.

#### Scenario: A signing key is added as a sops recipient

- **WHEN** a commit adds the age recipient of Cameron's `signingKey` to `.sops.yaml`
- **THEN** `checks.x86_64-linux.commit-signing-key` fails naming that recipient

#### Scenario: The mutant is run

- **WHEN** the check compares the signing keys' recipients with a fixture recipient set that contains one of them
- **THEN** that comparison fails, and the check fails if it does not

### Requirement: The signing change adds one check attribute

`checks.x86_64-linux` SHALL gain exactly one attribute, `commit-signing-key`, gated with `lib.optionalAttrs (system == "x86_64-linux")` and evaluating no host configuration; every per-host property here SHALL ride on the existing machine checks.

#### Scenario: The check key sets are compared

- **WHEN** `nix eval --json '.#.checks.x86_64-linux' --apply builtins.attrNames` and the same for `checks.aarch64-darwin` are compared before and after this change
- **THEN** the `x86_64-linux` list after is the list before plus `commit-signing-key`, and the `aarch64-darwin` lists are identical
