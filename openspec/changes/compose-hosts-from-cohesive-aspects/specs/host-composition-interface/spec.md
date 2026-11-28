## ADDED Requirements

### Requirement: The server aspects and cinnabar feature keys

`flake.modules.nixos.{omnigraph,greptimedb,perses,fleet-alert}-server` SHALL hold the clan generators, credential wiring and host-side settings magnetite's host module held for those services, import no other `flake.modules` value, and be imported by magnetite; the site-neutral keys SHALL read no clan vars. Each of cinnabar's eight feature files SHALL assign its own `flake.modules.nixos.<key>`, imported by cinnabar's host module.

#### Scenario: The store's assertions stay with the host

- **WHEN** magnetite's host module is read after the move
- **THEN** it still holds the store's credential-holder and unit-relation assertions

#### Scenario: The host keys are searched for

- **WHEN** `machines/nixos/cinnabar/` is searched for files assigning `flake.modules.nixos."machines/nixos/cinnabar"`
- **THEN** only `default.nix` and `disko.nix` do

#### Scenario: The keys are listed

- **WHEN** `nix eval .#modules.nixos --apply builtins.attrNames` runs
- **THEN** it lists the four `<svc>-server` keys and cinnabar's eight feature keys, and the site-neutral keys keep their names

#### Scenario: magnetite's credentials are unchanged

- **WHEN** magnetite's `LoadCredential` lists for `greptimedb`, `greptimedb-schema`, `greptimedb-envelope`, `devloop-reconcile`, `perses` and `omnigraph-server` are evaluated
- **THEN** each equals its value before the move, in order

#### Scenario: A host imports perses-server without greptimedb-server

- **WHEN** a host imports `perses-server` or `fleet-alert-server` and not `greptimedb-server`
- **THEN** evaluation fails naming the missing `vanixiets.secrets` entry: `greptimedb-users`, or for `perses-server` on a host without kanidm (pyrite) first `kanidm-oauth2-perses`

### Requirement: The provider aspects

`flake.modules.nixos.hetzner-cloud` and `flake.modules.nixos.gcp-cloud` SHALL each set `boot.zfs.devNodes = "/dev/disk/by-path"` and a `10-uplink` network, `hetzner-cloud` also importing srvos's `hardware-hetzner-cloud`, and each SHALL assert that the importing host's `flake.fleet.hosts.<host>.cloud.provider` is its provider. `services.openssh.settings.MaxAuthTries = 20` SHALL be set in `nixos.base` and in no host module.

#### Scenario: The provider aspects are read

- **WHEN** the two aspects and the host modules are read
- **THEN** `hetzner-cloud`'s uplink matches `en*` and it is imported by cinnabar, electrum and magnetite; `gcp-cloud`'s matches `en* eth*`, it imports no srvos Hetzner module, and it is imported by galena and scheelite; pyrite imports neither

#### Scenario: A Hetzner host imports the GCP aspect

- **WHEN** electrum imports `gcp-cloud`
- **THEN** evaluation fails naming electrum, its recorded provider and `gcp-cloud`

#### Scenario: The NixOS hosts keep their values

- **WHEN** each NixOS host's `boot.zfs.devNodes`, `10-uplink`, `MaxAuthTries` and `boot.loader.grub.enable` are evaluated
- **THEN** each equals its value before the change

### Requirement: The darwin-workstation aspect

`flake.modules.darwin.darwin-workstation` SHALL hold the import list, documentation options, `networking.computerName`, `clan.core.networking.targetHost`, `declaredSshd.serving` and the human accounts' `users.users` fields and `users.knownUsers` that `darwin/laptop.nix`, blackphos and stibnite each wrote, and all four darwin hosts SHALL import it. The documentation options SHALL be written once, without `mkForce`.

#### Scenario: The Macs keep their values

- **WHEN** each Mac's `users.knownUsers`, human `users.users` fields, documentation options, `computerName`, `targetHost` and `declaredSshd.serving` are evaluated
- **THEN** each equals its value before the change, `users.knownUsers` in the same order

### Requirement: Hosts read their state version from the registry

`flake.modules.darwin.base` SHALL set `system.stateVersion` to `flake.fleet.hosts.<host>.stateVersion` of the host named by `networking.hostName`, and no darwin host module SHALL set it. The registry field's description SHALL no longer say it is unread.

#### Scenario: The state versions are evaluated

- **WHEN** `darwinConfigurations.<h>.config.system.stateVersion` is evaluated for each Mac
- **THEN** it is 4, the registry's value, and `ids.gids.nixbld` is unchanged

### Requirement: Importing a module is the decision

The modules memory-pressure-guards, colima, shared-reference-tree, greptimedb, `stibnite-session`, `stibnite-session-host`, homebrew and moshi SHALL take effect wherever imported and SHALL declare no `enable` option that every importer sets. `custom.profile` SHALL NOT exist. A reader that probed a deleted flag SHALL test whether the option exists instead. mergify's default-on, dnscrypt-proxy's and fleet-services-trust's `enable`, and k3s-server SHALL be kept.

#### Scenario: A deleted flag is searched for

- **WHEN** the repository's modules are searched for a set or a read of a deleted flag
- **THEN** none is found

#### Scenario: A runtime test diverges from magnetite

- **WHEN** magnetite stops importing memory-pressure-guards while `greptimedb-oom-order` imports it
- **THEN** the runtime test fails evaluation

### Requirement: exportAs and the key spelling

`flake.lib.exportAs` SHALL assign one home module under several names with `key = "vanixiets/<name>"`, or `"vanixiets/<name>?<param>=<value>"` for a parameterised module, and every module that is exported under more than one name SHALL use it. Every first-party `key` SHALL use the `vanixiets/` spelling.

#### Scenario: A home imports an aggregate and one of its parts

- **WHEN** claude-sandbox's home imports `terminal` and `fd`
- **THEN** the module system applies `fd`'s module once, and the home's derivation is unchanged

#### Scenario: The two git instances

- **WHEN** a home imports both `development` and `git`
- **THEN** their keys differ and both apply

### Requirement: The activation order and the record-last judge

`flake.lib.activationOrder` SHALL give each darwin `postActivation` contributor its `mkOrder` priority, with the deploy record's the largest, and the contributors SHALL use it. `flake.lib.deployRecordObligations` SHALL report a problem when any `postActivation` text lies between the record's invocation and the relink of `/run/current-system`, and `checks.x86_64-linux.deploy-record-order` SHALL include the case `darwinSnippetAfterRecord` with one expected problem.

#### Scenario: The order is unchanged on the Macs

- **WHEN** each Mac's `system.activationScripts.postActivation.text` is evaluated
- **THEN** it equals its text before the change

#### Scenario: A snippet is placed after the record

- **WHEN** a host module adds `postActivation` text at a priority above the record's
- **THEN** that host's `darwin-<host>` machine check fails naming `deployRecordObligations`

### Requirement: The ZFS dataset table

`flake.lib.zfsBootInvariants.magnetite` SHALL list each boot-time dataset property of magnetite as `{ unit, dataset, property, value, when }`; magnetite's `zfs-*` oneshots and the `zfs-*` entries of its notified units SHALL be generated from it; `machines/nixos/magnetite/disko.nix` SHALL stay a literal independent of it.

#### Scenario: The generated units are compared

- **WHEN** each of the fourteen `zfs-*` units' derivations is compared before and after
- **THEN** each is identical, and when the root store is `r2` the omnigraph quota unit is empty (no `ExecStart`, no `wantedBy`), as before

### Requirement: One cache writer per class

`flake.modules.darwin.base` and `flake.modules.nixos.base` SHALL each receive `lib/caches.nix`'s substituters and keys from exactly one definition.

#### Scenario: A darwin host's caches are evaluated

- **WHEN** `nix.settings.substituters` is evaluated on a Mac
- **THEN** each of `lib/caches.nix`'s ten substituters appears once, followed by nix-darwin's `https://cache.nixos.org/`

### Requirement: Named parts of base and ai, and the otel-collector split

`flake.modules.{darwin,nixos}.base` SHALL be an import list of named `base-<concern>` aspects, and `flake.modules.homeManager.ai` an import list of one aspect per harness, each ordered to reproduce the earlier merge. `clan/services/otel-collector/` SHALL hold `agent.nix`, `ingress.nix`, `service.nix` and `_shared.nix`, assigning the same three outputs as before.

#### Scenario: The key-set cost is measured

- **WHEN** `just eval-cost checks.<system> <parent> <commit> 2 keys` runs for x86_64-linux and aarch64-darwin
- **THEN** CPU and wall time stay within the parent's run-to-run spread

### Requirement: Only the declared derivations change

Each of the change's ten pull requests SHALL pass `just drv-diff <parent> <commit> openspec/changes/compose-hosts-from-cohesive-aspects/<allow-list>` against its own `drv-delta-*.txt`. Only 4452, 4454 and 4468 SHALL name a host toplevel, each a darwin one, by declaration: `drv-delta-darwin-caches.txt`, `drv-delta-record-last.txt` and `drv-delta-stibnite-workstation.txt` declare those toplevels and their `checks.aarch64-darwin.darwin-<host>` as `changed`.

#### Scenario: A commit's diff runs

- **WHEN** the operator runs a commit's drv-diff
- **THEN** it exits 0, every `may-change` entry having been resolved

### Requirement: Trust boundary of the host-composition interface

The drvPath diff SHALL be read as showing only that evaluated derivations are equal at two revisions; the record-last judge as reading the generated activation script, not activation as it runs; and the provider assertion as comparing two declarations, not the machine's actual provider.

#### Scenario: What the interface does not show

- **WHEN** the interface's guarantees are relied on
- **THEN** they do not show that a deployed Mac activated the new `nix.conf`, that a cloud server really runs at the provider recorded for it, or that a ZFS property holds on disk after a boot oneshot ran
