## MODIFIED Requirements

### Requirement: The correspondence check compares user anchors and clan user keys with login keys

The check SHALL fail when a `.sops.yaml` user anchor, or a `sops/users/<u>/key.json` public key, differs from `ssh-to-age` of the first `meta.sshKeys` entry of the flake user it is mapped to by the check's static table, except that `sops/users/fleet-deployer/key.json` SHALL instead equal `flake.lib.fleetDeployer.agePublicKey`; a `sops/users/<u>` mapped to neither SHALL fail the check.

#### Scenario: A user anchor is changed
- **WHEN** a mutant case replaces the `&raquel-user` key with another valid age key
- **THEN** that case fails naming `raquel-user`

#### Scenario: The deployer's clan user key is changed
- **WHEN** a mutant case replaces `sops/users/fleet-deployer/key.json` with another valid age key
- **THEN** that case fails naming `fleet-deployer`

## ADDED Requirements

### Requirement: The correspondence check compares the deployer's reach with the deploy targets

While `flake.lib.fleetDeployer.keys` is null, the check SHALL fail when `sops/users/fleet-deployer` or `sops/groups/fleet-deployers` exists. Once it is set, the check SHALL fail when:
- `sops/users/fleet-deployer/key.json` is not `keys.age`;
- `sops/groups/fleet-deployers/users/` holds anything but `fleet-deployer`;
- `sops/secrets/<m>-age.key` lacks the group for an `<m>` in `flake.lib.fleetDeployer.targets`.

In both states, any `groups/fleet-deployers` or `users/fleet-deployer` reader under `sops/secrets/` or `vars/` SHALL fail the check unless it belongs to a target's machine key or to a var under `vars/per-machine/<target>/`.

#### Scenario: the group reaches stibnite
- **WHEN** a mutant case adds `fleet-deployers` to `sops/secrets/stibnite-age.key/groups/`
- **THEN** that case fails naming `sops/secrets/stibnite-age.key/groups/fleet-deployers`

#### Scenario: the deployer reads a shared var
- **WHEN** a mutant case adds `fleet-deployer` as a reader of `vars/shared/ntfy-alerter/token`
- **THEN** that case fails naming that var

#### Scenario: the deployer's user appears before its keys
- **WHEN** a mutant case adds `sops/users/fleet-deployer` while `keys` is null
- **THEN** that case fails

#### Scenario: a target's machine key lacks the group
- **WHEN** `keys` is set and a mutant case removes `fleet-deployers` from the first target's machine key
- **THEN** that case fails naming that machine key
