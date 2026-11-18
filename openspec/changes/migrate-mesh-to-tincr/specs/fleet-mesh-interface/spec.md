## ADDED Requirements

### Requirement: flake.lib.hosts declares every overlay member

`flake.lib.hosts.<name>` SHALL hold one entry per overlay member, phones included, with `class` (`"nixos"`, `"darwin"` or `"android"`), `endpoints` (dial addresses, empty behind NAT), `deployUser` and `services` (labels whose canonical name resolves to this member).
No field SHALL be named `zt`.

#### Scenario: The registry is evaluated

- **WHEN** `nix eval --json .#lib.hosts` runs
- **THEN** it lists cinnabar, electrum, galena, scheelite, magnetite, pyrite, stibnite, blackphos, argentum, rosegold, pixel7 and pixel11, each with `class`, `endpoints`, `deployUser` and `services`

### Requirement: A member's name and address are derived, never written

Each entry's `fqdn` SHALL equal `"<name>.${flake.lib.fleet.domain}"` and its `address` SHALL equal `flake.lib.mesh.addressOf flake.lib.mesh.instance name`; neither SHALL appear as a literal anywhere in `modules/`.

#### Scenario: The derived fields are read

- **WHEN** `nix eval --json .#lib.hosts` runs
- **THEN** every `fqdn` ends in `.vanixiets.internal` and every `address` lies in `fd09:836d:82f8:3d7d::/64`

#### Scenario: A literal address reappears

- **WHEN** `rg -n 'fd09:836d:82f8:3d7d:' modules` runs outside `modules/lib/mesh.nix`'s test file
- **THEN** it prints nothing

### Requirement: ZeroTier addresses live only in a transitional registry field

Until ZeroTier is retired an entry MAY carry `zerotier = { address; memberId; }`, which SHALL be the only place in `modules/` a ZeroTier IPv6 address is written; after retirement no entry SHALL carry it and no ZeroTier address, IPv6 or IPv4, SHALL remain in `modules/`.

#### Scenario: A ZeroTier literal outside the registry

- **WHEN** `rg -n 'fddb:4344:343b:14b9:' modules` runs during the mirror
- **THEN** it matches only `modules/lib/hosts.nix`, and `rg -l '10\.147\.17\.' modules` lists only `machines/nixos/cinnabar/zt-dns.nix`, `clan/inventory/services/openclaw.nix` (disabled), `checks/otel-collector-config.nix` and `machines/nixos/pyrite/containers.nix` (a comment)

#### Scenario: After retirement

- **WHEN** both searches run after retirement, together with `nix eval .#lib.hosts --apply 'hs: builtins.any (h: h ? zerotier) (builtins.attrValues hs)'`
- **THEN** both searches print nothing and the evaluation prints `false`

### Requirement: The mesh prefix and addresses are pure functions of names

`flake.lib.mesh.prefixOf instance` and `flake.lib.mesh.addressOf instance name` SHALL compute the prefix from sha256(`"tincr-" + instance`) and the host part from sha256(`name`), and the clan service and its invitation hook SHALL use the same computation.

#### Scenario: Known vectors

- **WHEN** the nix-unit test beside `modules/lib/mesh.nix` runs
- **THEN** `prefixOf "vanixiets"` equals `fd09:836d:82f8:3d7d::/64`, two host addresses equal their recorded vectors, and the invitation hook's shell computation for a phone name equals `addressOf` for that name

### Requirement: Derived addresses are unique

The tincr service SHALL fail evaluation when two peers or devices derive the same address.

#### Scenario: Two names collide

- **WHEN** an override gives two peers names whose derived addresses are equal
- **THEN** evaluation fails with the service's uniqueness assertion naming both

### Requirement: Every peer runs StrictSubnets without TunnelServer

Every node of the `tincr` instance `vanixiets` SHALL run `StrictSubnets = yes` and no `TunnelServer`, holding one host file per peer and per `devices` entry, each with exactly one `Subnet` equal to that member's `address`/128.
This rests on world assumption A131.

#### Scenario: A peer's delivered configuration is read

- **WHEN** after a deploy `/etc/tinc/vanixiets/tinc.conf` and `/etc/tinc/vanixiets/hosts/` are read on a NixOS peer and on a darwin peer
- **THEN** `tinc.conf` contains `StrictSubnets = yes` and no `TunnelServer`, and `hosts/` holds one file per peer and device with its one `Subnet`

#### Scenario: An undeclared key advertises a subnet

- **WHEN** the mesh VM test starts a node whose key no host file declares and has it advertise a peer's address
- **THEN** no peer routes that address to it

### Requirement: The tincr service joins every NixOS and darwin machine from the inventory

The instance SHALL put every NixOS and darwin machine in its `peer` role, generate each machine's Ed25519 key as a clan var, dial every peer whose `endpoints` is non-empty, and open `flake.lib.mesh.port` on TCP and UDP on NixOS peers.

#### Scenario: The instance is evaluated

- **WHEN** `nix eval --json .#clan.inventory.instances.vanixiets.roles.peer` runs
- **THEN** it covers all six NixOS and all four darwin machines

### Requirement: The service exports the mesh to clan's network selection

The service SHALL export `networking.priority = 1100` and each peer's `fqdn` under `peer.hosts`.

#### Scenario: Clan lists the network

- **WHEN** `clan network list` runs on stibnite after the mirror deploys
- **THEN** it lists the tincr instance with priority 1100 above zerotier's 900

### Requirement: The mesh runs tincr's default crypto while a phone is a member

The mesh SHALL run tincr's default crypto mesh-wide: the service's `crypto` setting SHALL default to `"default"`, under which no `SPTPSCipher` or `SPTPSKex` line is written, and `crypto = "pq"`, if set, SHALL write those lines only into clan peers' host files and never into a device's.
This rests on world assumption A132.

#### Scenario: Post-quantum crypto with a phone declared

- **WHEN** an override sets `crypto = "pq"` with `devices` non-empty and `nix eval` reads a peer's host files
- **THEN** each device's host file carries no `SPTPSCipher` or `SPTPSKex` line, and each clan peer's carries both

### Requirement: Two name services answer the zone from the registry

cinnabar and magnetite SHALL each answer every `flake.lib.meshRecords` name on its own `address`, forward other names to quad9, accept queries only on `flake.lib.meshInterfaces`, and leave tincr's in-mesh DNS stub disabled.

#### Scenario: A member and a service are resolved

- **WHEN** `dig AAAA cinnabar.vanixiets.internal @<magnetite address>` and `dig AAAA ntfy.vanixiets.internal @<cinnabar address>` run from pyrite
- **THEN** both answer cinnabar's `address`

#### Scenario: A name outside the zone is resolved

- **WHEN** `dig A example.org @<cinnabar address>` runs from pyrite over `tinc-vanixiets`
- **THEN** the answer is forwarded and returned

### Requirement: Every member class routes the zone to both name services

NixOS members SHALL route `~vanixiets.internal` to both name services through systemd-networkd on `tinc-vanixiets`, darwin members SHALL carry `/etc/resolver/vanixiets.internal` naming both, and each phone's rendered `network.conf` SHALL name both as `DNSServer` with `SearchDomain = vanixiets.internal`.
This rests on world assumptions A133 and A134.

#### Scenario: Each class is read after deploy

- **WHEN** `resolvectl domain tinc-vanixiets` runs on pyrite, `scutil --dns` on stibnite, and the phone's `network.conf` package is built
- **THEN** each names both name services for `vanixiets.internal`

### Requirement: One helper names the mesh interfaces for every firewall opening

`flake.lib.meshInterfaces config` SHALL return the interface keys of every overlay network a NixOS host carries (ZeroTier's key and `tinc-vanixiets` until retirement, `tinc-vanixiets` after), and every overlay-only firewall opening SHALL use it.

#### Scenario: A raw key is reintroduced

- **WHEN** `rg -n '"zt[+*]"|"tinc-vanixiets"' modules` runs outside `modules/lib/mesh-interfaces.nix`
- **THEN** it prints nothing

### Requirement: Deploy targets are generated from the registry

After the flip, every NixOS machine's inventory `deploy.targetHost` SHALL equal `"root@${hosts.<name>.fqdn}"` and every darwin machine's `clan.core.networking.targetHost` SHALL equal `"${hosts.<name>.deployUser}@${hosts.<name>.fqdn}"`.

#### Scenario: Targets are evaluated after the flip

- **WHEN** `nix eval --json .#clan.inventory.machines --apply 'ms: builtins.mapAttrs (_: m: m.deploy.targetHost or null) ms'` runs
- **THEN** every NixOS machine's value ends in `.vanixiets.internal`

### Requirement: Certificate names are generated from the registry

The otel ingress certificate SHALL carry `IP:` magnetite's `address` and `DNS:` its `fqdn`, and each nix-grpc builder certificate SHALL carry its own `fqdn` and `address`; the ZeroTier entries SHALL be present until retirement and absent after.

#### Scenario: A delivered certificate is read

- **WHEN** after the reissue `openssl x509 -noout -ext subjectAltName` reads magnetite's delivered otel certificate
- **THEN** it lists `magnetite.vanixiets.internal` and magnetite's `address`

### Requirement: This capability states its own trust boundary

The capability's README SHALL state that admitted members are trusted to relay others' packets unread; `StrictSubnets` binds an address to its declared key and nothing more; no sender person or service is authenticated; the name services are trusted to answer from the registry; tincr is trusted for each link's confidentiality; and no direct path is guaranteed between members behind NAT.

#### Scenario: A guarantee about a packet's sender is sought

- **WHEN** a service needs to know which member sent a request
- **THEN** this capability answers only that the source overlay address belongs to the member whose declared key holds it, and the service authenticates the sender itself
