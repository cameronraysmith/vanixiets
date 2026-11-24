# tincr service

Clan service `tincr` runs one tincr mesh per instance on every machine in its `peer` role, NixOS and darwin alike.
The fleet runs one instance, `vanixiets` (`modules/clan/inventory/services/tincr.nix`), beside ZeroTier until the cutover of the change `migrate-mesh-to-tincr`.
tincr is Mic92's Rust implementation of tinc 1.1, taken as the flake input `tincr`; the service imports its `nixosModules.tincr` and `darwinModules.tincr` and configures `services.tincr.networks.<instance>` on each machine.

## Settings

The `peer` role takes three settings.

- `endpoints`: the addresses other peers dial this machine at, each `"<name or address> [port]"`, written as `Address` lines in its host file; empty behind NAT. The inventory reads them from `flake.lib.hosts.<name>.endpoints`.
- `devices`: members outside clan, keyed by name, each with the `publicKey` its tinc client generated; every peer carries a host file for each.
- `crypto`: `"default"` (ChaCha20-Poly1305 and X25519, no extra lines), the fleet's setting, or `"pq"` (`SPTPSCipher = aes-256-gcm` and `SPTPSKex = x25519-mlkem768`), which the service writes into clan peers' host files only, never a device's; tincr applies them on a link only when both ends' host files ask (tincr `docs/COMPAT.md`), so links to devices keep the defaults.

## Addresses, keys and host files

Every member's address is `flake.lib.mesh.addressOf <instance> <name>`, the instance's ULA `/64` plus 64 bits of sha256 of the name, so nothing reads a vars file to learn an address.
The service asserts that the instance is `flake.lib.mesh.instance`, that no two peers or devices derive the same address, and that no two share an Ed25519 public key.
Each machine's Ed25519 key is the per-machine clan var `tincr-<instance>`, with the secret `ed25519_key.priv` and the public `ed25519_key.pub`.
Its generator runs nixpkgs' `tinc_pre` (C tinc 1.1, `tinc generate-ed25519-keys`), because `clan vars generate` builds a generator for the system it runs on, and `tinc_pre` is in cache.nixos.org for aarch64-darwin and x86_64-linux while tincr has no binary cache; tincr reads the tinc 1.1 key format, which `vmTests.x86_64-linux.tincr-mesh` exercises by connecting with keys made by this generator.
Every machine carries one host file per peer and per device, each with exactly one `Subnet`, that member's address as a `/128`, its public key, and its endpoints.
Every node runs `StrictSubnets = yes`, so it routes a subnet only to the node whose host file it comes from, and none runs `TunnelServer`.
Every node also runs `Broadcast = no`: the mesh carries IPv6 unicast only, and krebs' retiolum stopped a mesh-wide packet storm from broadcast loops with it (kartei `modules/retiolum/nixos.nix`).
A machine dials every other peer that has endpoints (`ConnectTo`), and `AutoConnect` finds the rest.
`flake.lib.meshHostFiles` holds every peer's and device's host file, rendered by the same `flake.lib.tincrHostFile` from the same registry values and public vars, for members that carry host files by hand: each phone's `tincapp-network-<phone>` package ships every other member's file in `hosts/`.
A reload does not apply `StrictSubnets` changes (tincr `docs/COMPAT.md`), so tincd restarts whenever its host files change: on NixOS through the unit's restart triggers, on darwin because the launchd definition carries a hash of the host files, so activation reloads the daemon.
`UPnP` (tincr's PCP and UPnP-IGD port mapping) is not enabled, because it opens ports on routers in other people's homes; it is an option if NAT traversal proves weak.

On NixOS the interface is `flake.lib.mesh.interface.nixos`, carrying the machine's address with the mesh `/64`, and the daemon is `tincr-<instance>.service`, which opens `flake.lib.mesh.port` on TCP and UDP.
tincr's module hands the link to systemd-networkd, so the service lists it in `networking.networkmanager.unmanaged` for hosts that also run NetworkManager (pyrite), and pins its MTU to 1377 against PMTU black holes over double-NAT relays, as kartei does and as tincr's darwin module defaults to.
tincr's own DNS stub stays off: the zone is answered by the name services built from `flake.lib.meshRecords`, and every NixOS and darwin peer also answers it from its own `/etc/hosts`, generated from the same records (`modules/system/mesh-hosts.nix`), so peers name each other while neither name service is reachable.
On NixOS the service also installs two invitation hooks, both computing the invitee's address with the same slicing of sha256 as `flake.lib.mesh.addressOf`: `invitation-created`, so `tinc -n <instance> invite <device>` run as the `tincr` user hands the device its address as `Subnet = <address>/128`, and `invitation-accepted`, which writes the same `Subnet` into the inviter's runtime copy of the device's host file, because tincd writes that copy with only the key and it hides the declared file.
An invitation carries only the inviter's host file, so a device gets the rest from `flake.lib.meshHostFiles`, and a device is invited before it is declared, because `tinc invite` refuses a name whose host file exists.

On darwin the network runs as the launchd daemon `org.tincr.<instance>` on `flake.lib.mesh.interface.darwin`, whose unit number the service passes to tincr's module, and tincr's `tinc-up` assigns the address.
launchd orders no job after another, so at boot tincd can start before sops-install-secrets has written its private key; its start script polls once a second, for at most 60 seconds, for every `/run/secrets` path that `/etc/tinc/<instance>/` names, then starts tincd, which fails and is relaunched as before if the key is still missing (`flake.lib.launchdSecretPoll`, which says why not `/bin/wait4path`), and an assertion in the darwin module holds that.
The darwin module has no firewall, DNS or socket-activation options, so what reaches a Mac is read on it after activation.
Its daemon writes its pidfile to `/var/run/tincr-<instance>.pid`, where the `tinc` CLI does not look, so the service installs a `tinc` wrapper passing `--pidfile`, and `tinc -n <instance> info` works on a Mac.
Its log, `/var/log/tincr-<instance>.log`, grows without rotation: launchd holds the file open and macOS `newsyslog` has no copy-and-truncate mode, so rotation would need a daemon restart; tincd runs at its default debug level 0, and this is accepted.

## Exports

Each instance exports `networking.priority = 1100`, above wireguard (1000) and ZeroTier (900), and each peer exports its `flake.lib.hosts.<name>.fqdn` under `peer.hosts` and its `flake.lib.hosts.<name>.deployUser` under `peer.user`.
Inventory `deploy.targetHost` takes precedence over network selection, so the export does not choose deploy paths for the NixOS hosts while their targets are set.
The Macs set `clan.core.networking.targetHost`, which clan tries only after every network, so `clan machines update <mac>` without `--target-host` reaches a Mac over tincr; clan logs in as the export's `user`, root when it is unset, which is why the export carries the Mac's admin account (`cameron` or `crs58`; finding F36).
`flake.lib.networkTargetObligations` (`modules/lib/network-targets.nix`), asserted on every `nixos-<host>` and `darwin-<host>` check, fails a machine that any network export would log in to as another user; `checks.x86_64-linux.network-target-obligations` runs its judge over fixtures and mutants.

## Trust boundary

This service, the capability `fleet-mesh-interface`, guarantees less than a reader might assume.

- Admitted members are trusted to relay one another's packets unread: a member that cannot reach another directly is reached through a third, which forwards packets it cannot decrypt.
- `StrictSubnets` binds an address to the key declared for it in the inventory and nothing more: a packet's source address says which declared key sent it, not which person or process did.
- No sender person or service is authenticated by the mesh; a service that needs to know who called it authenticates the caller itself.
- The name services are trusted to answer from the registry, `flake.lib.meshRecords`; the mesh does not sign or verify answers.
- tincr is trusted for each link's confidentiality and integrity (SPTPS with the configured `crypto`).
- No direct path is guaranteed between members behind NAT: tincr punches UDP holes where both routers allow it and relays through a peer otherwise.

## Negative controls

`vanixiets.tincr.addresses`, `vanixiets.tincr.publicKeys`, `vanixiets.tincr.devices` and `vanixiets.tincr.crypto` are internal options holding what the host files are rendered from, so evaluation overrides reach the assertions and the rendering through the same values.
`addressCollision` forces two peers onto one address and `keyCollision` gives two peers one public key; each fails evaluation with the assertion naming them; `crypto = "pq"` with a device declared leaves the device's host file without `SPTPSCipher` and `SPTPSKex` (`openspec/changes/migrate-mesh-to-tincr/tasks.md` 3.4).
`vmTests.x86_64-linux.tincr-mesh` runs the service on QEMU nodes named after members, with two behind separate NAT gateways and cinnabar answering the zone through the fleet's resolver module `flake.modules.nixos."mesh-dns/cinnabar"`, and observes connections with generated keys, a direct UDP path between the NATed members, the zone, an undeclared key refused at authentication, a declared node's undeclared subnet routed by no peer, the invitation hooks, and a device joining by invitation that cinnabar then routes; it requires kvm, so it builds on pyrite.
`vmTests.x86_64-linux.tincr-mesh-partition` runs the service on cinnabar and magnetite, both answering the zone through their resolver modules, and on pyrite and electrum with `flake.modules.nixos.mesh-hosts`, and observes that after both resolvers shut down pyrite and electrum still resolve each other's names and a service name through `getaddrinfo` and reach each other by name; it requires kvm, so it builds on pyrite.

## Provenance

This service is first-party code written for this repository from tincr's `nix/module.nix` and `nix/darwin-module.nix` at the locked revision and from the shape of clan-core's `clanServices/wireguard` at clan-core `d718bcf9`.
Qubasa/infra `services/tincr/default.nix` at `a00b9b1` (2026-09-24) was read as a design reference only, for the ideas of hash-derived ULA addressing, a key generator, a host database from every peer's public key, `StrictSubnets` and invitation hooks; none of its code is copied, because the repository carries no licence file and is therefore all rights reserved.
No licence was asked for (operator decision 2026-11-18): the service is first-party and copies nothing from Qubasa/infra, so it needs no licence from that repository; Qubasa/infra `services/tincr` (read at `a00b9b1`) stays credited as a design reference.

tincr is pinned at `fd92f2164f8f4e2927d6c983a116bf41ac2337d5` (committed 2026-11-17, reviewed 2026-11-17); upgrades are deliberate `flake.lock` bumps.
tincr declares GPL-2.0-or-later in `Cargo.toml` and has no root licence file.
