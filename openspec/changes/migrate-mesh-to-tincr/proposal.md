---
linear_story_id: CAM-109
linear_story_identifier: CAM-109
linear_story_title: "Migrate the fleet mesh from ZeroTier to tincr"
linear_story_url: https://linear.app/cameronraysmith/issue/CAM-109/migrate-the-fleet-mesh-from-zerotier-to-tincr
linear_story_state: Todo
linear_team: CAM
linear_project: nixbot-herculesci-cicd
last_synced_state: Todo
last_synced_at: "2026-11-17T22:25:08Z"
review_round: 0
max_review_rounds: 3
attempt_log:
  - { at: "2026-11-17T22:25:08Z", transition: "Backlog->Todo", outcome: "posted", note: "Created in Backlog with the seeded description, related to CAM-81, moved to Todo, bind comment posted" }
---

## Why

The fleet's private network is one ZeroTier network whose controller on cinnabar now ships under a non-commercial source-available licence, whose clan maintainers moved off it during 2026, and whose names (`.zt`) and addresses are restated by hand across about forty sites.
vanixiets is not in violation; the move is prospective, to follow the technology's trajectory rather than be forced off it at deprecation.
tincr gives a peer-to-peer mesh with no single controller on NixOS, darwin and Android, and a registry of transport-neutral names makes this the last time a transport change touches every consumer.

## What Changes

Decisions D1–D18 are in `design.md`; Q1 and D1–D5 were settled with the operator on 2026-11-17 (`brainstorm.md`).

**Names**
- From: hosts and services are `<name>.zt`, served by a hand-written dnsmasq on cinnabar that ZeroTier's controller pushes.
- To: every member and service is `<name>.vanixiets.internal`, generated from `flake.lib.hosts` and served by two resolvers (cinnabar, magnetite) over the mesh (D2, D11).
- Reason: `.internal` is reserved for private use and never delegated; the fleet label lets another fleet reuse the framework.
- Impact: breaking for anything that uses a `.zt` name, at the flip (F); additive before it.

**Transport**
- From: ZeroTier, one controller, NixOS peers by clan service, four Macs and two phones admitted by hand.
- To: tincr through a first-party clan service written with Qubasa/infra `services/tincr` as reference only, on all six NixOS machines and all four Macs from the inventory, and on pixel11 through tincapp (pixel7 best-effort), with tincr's default crypto mesh-wide (D6, D8, D9, D10).
- Reason: no single controller, free licences, the direction clan's maintainers took.
- Impact: ZeroTier stays untouched until the cutover decision, then is retired completely (instance, controller hooks, MSS clamp, casks, checks and VM tests, the phones' ZeroTier app).

**One registry**
- From: `flake.lib.hosts` holds one ZeroTier address under a field named `zt`; addresses are literals in 15 files.
- To: `flake.lib.hosts.<name>` holds every member's class, derived name and mesh address, dial endpoints, deploy user and hosted services; zone records, ssh blocks, known-hosts, certificate SANs, firewall keys and deploy targets are generated from it; O07/O08 are rewritten to match (D2, D13, D14, D15).

**Matrix**
- From: tuwunel with `server_name = "matrix.zt"`.
- To: a fresh homeserver as `matrix.vanixiets.internal`, hermes re-pointed; a server name cannot be renamed on an existing database (D3).

**Recovery**
- Each host class has a stated path that does not depend on the mesh; `p2p-ssh-iroh` is the leading candidate for pyrite, decided from evidence (D4).

**CAM-81**
- Its Task 2 is rewritten to read the neutral registry instead of growing `flake.lib.hosts.<host>.zt`; its ZeroTier MAC pinning lives only until retirement (D5).

**Delivery**
- Task groups C (contract), R, T, A, K, M, B, S run in parallel from the contract as stacked pull requests; V (mirror acceptance) feeds one operator cutover decision X, then F (flip) and Z (retire); Headscale with self-hosted DERP is the recorded fallback if X rejects tincr (D1, D18).

## Capabilities

### New Capabilities

- `fleet-mesh` (stratum: `behavioral`): every overlay member reaches every fleet service and every other member by its canonical name over the overlay network without a single controller; one place names each member; a recovery path independent of the overlay network for each host the operator administers remotely.
- `fleet-mesh-interface` (stratum: `interface`): the registry fields and their derivations, the address and prefix functions, the generated zone and its two resolvers, the clan service's settings, crypto and `StrictSubnets`, the firewall helper, the deploy targets, and the phone's interface file.
  Trust boundary: every admitted member is trusted to carry and relay other members' packets without reading them, and `StrictSubnets` binds each overlay address to the key the inventory declares; nothing here authenticates which person or service sent a packet, the resolvers are trusted to answer from the registry, tincr's own implementation is trusted for confidentiality, and nothing guarantees a direct path rather than a relayed one between two members behind NAT.

### Modified Capabilities

- `world-assumptions` (stratum: `world`): adds A128–A135 and A142 (`.internal` is reserved; a homeserver's server name is permanent; tincr's NAT traversal and relay behaviour; unsigned gossip bounded by `StrictSubnets`; a C-tinc client needs the default crypto; tincapp configures its interface only from its network file; macOS routes a domain by its resolver file; macOS answers names its hosts file lists from that file; macOS asks a domain's resolver only for the address types its `flags` line names); A33 and A65 are renamed and no longer name ZeroTier; `Grounded vocabulary for behavioral requirements` revises `overlay network` and adds `overlay member`, `overlay address`, `canonical name`, `name service`, `recovery path`, `public address`, `address-translating router`, `chat service` and `phone`.
  A-numbers are renumbered at close-out if another change has taken them.
- `fleet-ingress-interface` (stratum: `interface`): `The ingress receiver accepts only certificate holders on magnetite's ZeroTier address` is renamed `The ingress receiver accepts only certificate holders on magnetite's overlay address` and modified to listen at `flake.lib.hosts.magnetite.address`, opened on `flake.lib.meshInterfaces`.
  Trust boundary unchanged except that the overlay network, not ZeroTier, is trusted to deliver packets between members and nothing more.
- `bare-metal-install-path` (stratum: `behavioral`): `ZeroTier admission requires redeploying the controller` is removed and `Overlay admission requires redeploying every member` added in its place.

Every other requirement that names ZeroTier, `.zt` or an `fddb:` address (73 matches in 9 specs on 2026-11-17) is rebased into these deltas at close-out, when the live state they describe has changed (D17).

## Impact

- New: flake input `tincr`; `modules/clan/services/tincr/`; `modules/lib/mesh.nix`, `modules/lib/fleet.nix`; the `tincr` inventory instance; generated dnsmasq on cinnabar and magnetite; split DNS for `vanixiets.internal` on NixOS and darwin; `tincapp-network-<phone>` packages; a clan VM test for the mesh; `p2p-ssh-iroh` on pyrite as its unattended recovery path, kept if it proves out (D4).
- Changed: `modules/lib/hosts.nix` (every member), `flake.lib.zerotierInterfaces` → `flake.lib.meshInterfaces` and the 9 firewall openings, `home/core/ssh.nix`, `system/ssh-known-hosts.nix`, `system/stibnite-access.nix`, cinnabar's caddy, `matrix.nix`, `hermes-agent.nix`, otel and nix-builders certificate SANs and endpoints, sshd `searchDomains`, clan `meta.domain`, deploy targets, `gate-dangerous-commands.sh`, `modules/terranix/gcp.nix`, about ten checks and VM tests, 32 documentation pages, O07/O08.
- Removed at retirement: the `zerotier` instance and controller hooks, `zerotier-mss-clamp`, `zt-dns` (both), the `zerotier-one` casks, `zerotier-join`, the transitional `zerotier` registry fields, `zerotierone-controller` and the MSS clamp checks and VM tests.
- Vars: tincr keys per machine; otel ingress, nix-grpc and sshd host certificates reissued twice (mirror, retirement), each with `CLAN_NO_COMMIT=1`; ZeroTier vars deleted at retirement.
- Dependencies: CAM-81 (`bind-mesh-writes-to-their-host`) holds its Task 2 until the contract lands, then consumes the registry (D5).
- Devices: pixel11 is the Android test device and the only phone in the cutover verification; pixel7 is enrolled best-effort and gates nothing (D10).
- Out of scope: Kubernetes networking, post-quantum crypto while a phone cannot carry it, Matrix history, a second fleet.
