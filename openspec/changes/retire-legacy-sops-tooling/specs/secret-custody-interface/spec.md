## ADDED Requirements

### Requirement: This capability states its own trust boundary

The properties in this capability SHALL be read as guarantees only about what the repository declares, what evaluation of the flake and the `sops-correspondence` check accept, and what the `.#darwin` app and the `justfile` recipes do when run, and never as an end-to-end guarantee.

**Outside the boundary**: which keys a host or workstation holds outside an activation the `.#darwin` app performs; what the key store holds; what earlier revisions in the repository's history disclose to their former readers; whether a credential value was copied while a former reader could read it.

#### Scenario: A former reader keeps an old revision
- **WHEN** an identity removed from `.sops.yaml` decrypts a revision of `secrets/shared.yaml` from before its removal
- **THEN** this capability is not violated, because history is outside its boundary; the residual exposure is the one the `secret-custody` requirement on narrowing readers names

### Requirement: Operator-credential files are encrypted to the recovery key and the operator identity only

The `.sops.yaml` creation rule matching `secrets/shared.yaml`, `secrets/test.yaml` and `secrets/services/*.yaml` SHALL list exactly the anchors `&admin` and `&admin-user`, and each tracked file matching it SHALL carry exactly the two corresponding age recipients.

#### Scenario: The narrowed files are read for recipients
- **WHEN** `yq '.sops.age[].recipient'` is read from `secrets/shared.yaml` and `secrets/test.yaml`
- **THEN** each prints exactly the `&admin` and `&admin-user` age keys

#### Scenario: A removed identity attempts decryption
- **WHEN** `sops -d secrets/shared.yaml` runs with `SOPS_AGE_KEY_FILE` holding only the `&dev` identity
- **THEN** sops exits non-zero, while the same command with the operator's key file succeeds

### Requirement: No rule names the retired development key, and every rule names the operator identity

`.sops.yaml` SHALL define no `&dev` anchor and no rule SHALL list `*dev`; every creation rule SHALL list `*admin-user`; and no tracked file under `secrets/` SHALL carry the `&dev` age key as a recipient.

#### Scenario: A dev-only key file is tried on every secret
- **WHEN** `sops -d` runs on every tracked file under `secrets/` with `SOPS_AGE_KEY_FILE` holding only the former `&dev` identity
- **THEN** every decryption exits non-zero, while the operator's `&admin-user`-only key file decrypts every file and each home-manager file also decrypts with its user's key

#### Scenario: The development key is reintroduced
- **WHEN** a mutant case adds `&dev` back as an anchor
- **THEN** the correspondence check's unclassified-anchor case fails naming `dev`

### Requirement: No retired host's key is an anchor or a rule

`.sops.yaml` SHALL define no `&stibnite` or `&orb-nixos` anchor and no `secrets/hosts/stibnite/` or `secrets/hosts/orb-nixos/` rule, and no rule, including the fallback rule, SHALL list either key.

#### Scenario: The retired keys are searched for
- **WHEN** `rg -n 'age1a696klqy|age140evke8t|orb-nixos|&stibnite|\*stibnite' .sops.yaml` runs
- **THEN** it finds nothing

### Requirement: Narrowed files carry a renewed data key

Each file whose recipients were narrowed SHALL have been re-encrypted with a new data key by `sops rotate --in-place` after the `sops updatekeys` that narrowed them.

#### Scenario: The data key is compared across the narrowing
- **WHEN** the `sops.mac` and the `enc` value of any one key in `secrets/shared.yaml` are compared between the commit before the narrowing and after it
- **THEN** both differ, while `sops -d` of the two commits yields equal plaintext for the operator

### Requirement: The correspondence check runs on public data at static cost

`checks.x86_64-linux.sops-correspondence` SHALL exist on x86_64-linux only, under an attribute name that depends on no evaluated host configuration, SHALL read only `.sops.yaml`, `sops/users/*/key.json`, `sops/machines/*/key.json`, sops metadata of files under `secrets/`, user `meta.sshKeys` and the static darwin host-key attribute, and SHALL fail when it finds no anchor, no rule or no file.

#### Scenario: The check runs on the repository as it is
- **WHEN** `nix build .#checks.x86_64-linux.sops-correspondence` runs on a tree satisfying every invariant
- **THEN** it succeeds and its log names the count of anchors, rules and files compared

#### Scenario: The scan is emptied
- **WHEN** a control case runs the scan against a tree with no `secrets/` files
- **THEN** that case fails with the empty-scan message

### Requirement: The correspondence check compares user anchors and clan user keys with login keys

The check SHALL fail when a `.sops.yaml` user anchor, or a `sops/users/<u>/key.json` public key, differs from `ssh-to-age` of the first `meta.sshKeys` entry of the flake user it is mapped to by the check's static table.

#### Scenario: A user anchor is changed
- **WHEN** a mutant case replaces the `&raquel-user` key with another valid age key
- **THEN** that case fails naming `raquel-user`

### Requirement: The correspondence check compares machine anchors with clan machine keys

The check SHALL fail when a `.sops.yaml` machine anchor differs from the public key in `sops/machines/<m>/key.json`, or names a machine with no such file.

#### Scenario: A machine anchor is changed
- **WHEN** a mutant case replaces the `&magnetite` key
- **THEN** that case fails naming `magnetite`

### Requirement: The correspondence check compares host-key anchors with pinned darwin host keys

The check SHALL fail when a `.sops.yaml` host-key anchor differs from `ssh-to-age` of the darwin host key the flake pins for that host.

#### Scenario: The host-key anchor is changed
- **WHEN** a mutant case replaces the `&blackphos` key
- **THEN** that case fails naming `blackphos`

### Requirement: The correspondence check compares each file's recipients with its rule

The check SHALL fail when a tracked file under `secrets/` carries a recipient set different from the keys of the anchors listed by the first `.sops.yaml` rule whose `path_regex` matches its repository-relative path.

#### Scenario: A file's recipients drift from its rule
- **WHEN** a mutant case adds one recipient to the rule matching `secrets/shared.yaml` without re-encrypting it
- **THEN** that case fails naming `secrets/shared.yaml`

### Requirement: The correspondence check accounts for every anchor

The check SHALL fail when a `.sops.yaml` anchor is not classified in its static table as user, machine, host key, runner or recovery, or when a classified name has no anchor.

#### Scenario: An unclassified anchor is added
- **WHEN** a mutant case adds an anchor `&stranger` with a valid age key
- **THEN** that case fails naming `stranger`

### Requirement: Darwin host keys are static flake data

The darwin host keys the fleet pins SHALL be defined once as a flake-level attribute of literal strings, read both by `modules/system/ssh-known-hosts.nix` and by the correspondence check, so that reading them evaluates no host configuration.

#### Scenario: The known-hosts entries are evaluated after the hoist
- **WHEN** `programs.ssh.knownHosts."blackphos.zt".publicKey` and `."stibnite.zt".publicKey` are evaluated for a host before and after the hoist
- **THEN** the values are identical

### Requirement: Each NixOS host asserts it is a recipient of the bridge files it uses

For every user in `hm-sops-bridge.users`, the NixOS host's evaluation SHALL fail unless the public key in `sops/machines/<host>/key.json` is a recipient of `secrets/bridge/<sopsIdentity>-age-key.enc`, with a message naming the host, the identity and `just update-all-keys`.

#### Scenario: A host is added without re-encrypting the bridge file
- **WHEN** a NixOS host enables the bridge for an identity whose bridge file is not encrypted to that host's machine key
- **THEN** `nix eval` of that host's toplevel fails with the assertion message

### Requirement: The `.#darwin` app refuses activation without the host's machine key

Before invoking `nh darwin switch`, the `.#darwin` app SHALL, for a hostname whose `sops/secrets/<host>-age.key/secret` exists in the flake it was built from, compare `age-keygen -y /var/lib/sops-nix/key.txt` with `sops/machines/<host>/key.json`, and on a missing file or a mismatch SHALL exit non-zero before activation, naming `clan vars upload <host>`.
It SHALL print at most public keys, never the private key.

#### Scenario: Dry run
- **WHEN** the app runs with `--dry` and the key is missing or differs
- **THEN** it prints the same message and continues to `nh darwin switch --dry`

#### Scenario: Host without a machine key
- **WHEN** the hostname has no `sops/secrets/<host>-age.key/secret`, as for blackphos
- **THEN** the app skips the comparison and does not read `/var/lib/sops-nix/key.txt`

#### Scenario: Key file missing on a host with a machine key
- **WHEN** `just activate-darwin argentum` runs on argentum and `/var/lib/sops-nix/key.txt` does not exist
- **THEN** the app exits non-zero before `nh` runs and the message names `clan vars upload argentum`

#### Scenario: Matching key
- **WHEN** the public key of `/var/lib/sops-nix/key.txt` equals `sops/machines/<host>/key.json`
- **THEN** the app proceeds to `nh darwin switch`

### Requirement: `provision-bridge-key` keeps plaintext out of the repository tree

`just provision-bridge-key` SHALL pipe the derived age private key directly into `sops encrypt` reading stdin with `--filename-override secrets/bridge/<identity>-age-key.enc`, SHALL write only sops ciphertext, to a temporary file that is then moved onto the target, and SHALL leave the previous target untouched on any failure.

#### Scenario: Encryption fails
- **WHEN** `sops encrypt` exits non-zero during `just provision-bridge-key <identity>`
- **THEN** the target is unchanged, no file under the repository contains an `AGE-SECRET-KEY-` line, and the recipe exits non-zero

### Requirement: The retired recipes, scripts and app are absent

The `justfile` SHALL define no `sops-extract-keys`, `sops-update-yaml`, `sops-deploy-host-key`, `sops-validate-correspondences`, `sops-sync-keys`, `sops-rotate`, `bootstrap-setup-user`, `hash-encrypt` or `verify-hash` recipe; `scripts/sops/` SHALL not exist; the flake SHALL define no `apps.<system>.setup-user`; the `Makefile` SHALL define no `setup-user` target; no home-manager profile SHALL define the `npmbw` alias; and `update-all-keys` and `provision-bridge-key` SHALL remain.

#### Scenario: Recipe and app listing
- **WHEN** `just --summary` and `nix eval .#apps.aarch64-darwin --apply builtins.attrNames` run
- **THEN** neither lists a retired name, and `just --summary` lists `update-all-keys` and `provision-bridge-key`

#### Scenario: The npm Bitwarden alias
- **WHEN** `nix eval .#homeConfigurations."crs58@aarch64-darwin".config.home.shellAliases --apply 'a: a ? npmbw'` runs
- **THEN** it prints `false`
