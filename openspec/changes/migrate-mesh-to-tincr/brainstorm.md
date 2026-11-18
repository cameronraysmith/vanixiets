<!--
Raw capture of the brainstorming that preceded this change.
The exploration ran in two sessions on 2026-11-17: a research session that produced findings F1–F14, R1 and A1–A3, and the orchestrator's Backlog explore window, which re-verified them through three scouts (F15–F22) and reached consensus with the operator on Q1 and D1–D5.
This file keeps that decision log in its natural order; design.md reorganizes it.
-->

# Brainstorm: migrate the fleet mesh from ZeroTier to tincr

## Background

The question put on 2026-11-17: given how clan-core and its users' repositories have evolved, and given the vpn-bench results, is there a reason to migrate vanixiets off ZeroTier to something better and as future-proof as is available in 2026?

### Research session findings (leads, later re-verified)

- F1 – ZeroTier is still Stable in clan-core; clan-infra still runs it.
  Since 1.16 the controller code under `nonfree/` is under ZeroTier's Source-Available, non-commercial licence.
  Correction (re-verification): before 1.16 the whole repository, agent included, was BSL 1.1; 1.16 moved the agent to MPL-2.0, so "still MPL-2.0" was wrong.
- F2 – clan-core builds the controller with nixpkgs' `enableUnfree` (which adds `ZT_NONFREE=1`) and relabels every zerotierone it builds `apple-psl20` ("halalify zerotierone"); nixpkgs labels the same build `unfree`.
  Several clan users dropped ZeroTier during 2026: Mic92/dotfiles (`e02ea06d`, 2026-07-15), Lassulus/superconfig (`7a448003`, 2026-06-12, "RIP zerotier"), mulatta/dots (`4afcb755`, 2026-08-29).
  Correction (F13 and re-verification): in every removal the replacement networks were already running; nobody switched straight from ZeroTier to tincr, and no commit cites the licence.
- F3 – clan's next default management transport is `p2p-ssh-iroh`, already Stable in the unreleased `next.md` at vanixiets' clan-core pin `dbae2101`; it carries `clan ssh` and `clan machines update` only, and has no darwin module.
- F4 – tincr (Mic92's Rust tinc) fits best but is young.
  Correction: the post-quantum key exchange (x25519-mlkem768) and AES-256-GCM are Qubasa/infra's opt-in settings, not tincr defaults; vpn-bench measured tincr's defaults (ChaCha20-Poly1305, X25519).
- F5 – clan selects a network per machine by priority and falls back.
  Correction: priority is hard-coded per service in its `exports` (iroh 3000, internet 2000, yggdrasil 2000, wireguard 1000, zerotier 900, mycelium 800, tor 10), and `clan_lib/network/network.py` uses inventory `deploy.targetHost` first and skips network selection entirely when it is set.
  vanixiets sets `deploy.targetHost = "root@<host>.zt"` on all six NixOS hosts, so the fallback never runs today.
- F7 – Performance is no reason to leave: in vpn-bench (2026-11, bare metal, 1 GbE, no NAT) ZeroTier 1.16.2 ties WireGuard on baseline TCP (832 vs 833 Mbit/s); its weakness is reordering (130 Mbit/s vs tincr's 549).
  The bench measured neither NAT traversal nor controller failure, and ran no darwin hosts.
- F8 – The reasons to leave are the licence trajectory, the single controller on cinnabar, relay dependence on vendor or clan infrastructure, and the protocol's lack of forward secrecy and rekeying (from an LLM source analysis, cited but unverified).
- F9 – No candidate wins every axis (wireguard: hub-and-spoke; Headscale/NetBird: no clan service; mycelium/yggdrasil: NixOS-only in clan; Nebula: CA key controls everything).
- F10 – clan is splitting deploy traffic from the mesh.
- F11 – The migration is fleet-wide (corrected counts below).
- F12 – tincr's community is small and close to its author; maintainer risk if Mic92 moves on.
- F14 – Templates: SBEE-Lab/infra `modules/tinc.nix`, mulatta/dots `naru`, Qubasa/vpn-bench `clanModules/tincr`, and Qubasa/infra `services/tincr`.
- R1 – Do not migrate to something that is itself a downgrade.
- A1 – First build the O07/O08 address registry and make names transport-independent.
- A2 – Decide whether vanixiets counts as "Commercial Use" under the nonfree licence.
- A3 – Before committing to any candidate, benchmark Headscale and NetBird with NAT in the path.

### Re-verification in the explore window

- F11 corrected: 15 Nix files under `modules/` hold a literal `fddb:4344:343b:14b9:` address, plus `home/tools/commands/network/zerotier-join.sh` and 8 vars files; 5 files hold `10.147.17.x`; 9 firewall openings in 8 files match `zt+` (2 through `flake.lib.zerotierInterfaces`), plus the MSS clamp and an nginx `allow fddb:…::/64`; cinnabar's dnsmasq carries 6 service and 11 machine records by hand; about 10 checks and VM tests; ADR-009 D9.15's wireguard is a deferred Kubernetes admin overlay, not a fleet mesh.
- F15 – CAM-81 (`bind-mesh-writes-to-their-host`) collides with A1: its Task 2 grows `flake.lib.hosts.<host>.zt`, a field named after the transport, to seven hosts and pins neighbour MACs computed with ZeroTier's own algorithm.
- F16 – A1 does not make a switch "one file": the certificate reissue, the controller hooks and MSS clamp, a DNS path for Android (ZeroTier's controller pushes DNS today) and the device clients remain; A1 removes about 40 hand-edited sites from the switch.
- F17 – Two partial abstractions already exist: `flake.lib.hosts` (one host, `magnetite.zt`) and `flake.lib.zerotierInterfaces` (2 of 9 firewall openings).
- F18 – cinnabar's 1.16.0 controller contains the `nonfree/` objects; NixOS peers are pure MPL-2.0.
- F19 – ZeroTier 1.14.2's controller passed its BSL change date on 2026-01-01 [INFERENCE: a reading of the BSL terms].
- F20 – The official macOS package is built with `ZT_NONFREE=1`, so the four Macs probably carry unused controller code [INFERENCE].
- F21 – tincr has no release (the only tag, `assets`, holds screenshots), no LICENSE file at its root (`Cargo.toml` declares GPL-2.0-or-later), aarch64-darwin only on darwin, and its TCP simultaneous-open punching fails behind port-translating NAT ("known v1 limitation", `docs/PUNCH.md`), with fallback to the TCP meta connection or relay through a peer.
- F22 – Wireguard may not be needed at all: tincapp (`org.pacien.tincapp`, a C tinc 1.1 client on F-Droid and Play) joins a tincr mesh if the mesh keeps the default cipher and key exchange, and tincr's darwin module covers aarch64 Macs.
- Qubasa/infra 404s on GitHub, but a local clone at `a00b9b1` holds `services/tincr/default.nix`: one `peer` role, `endpoints` and `devices` settings, an `sptps_keypair` vars generator, a host database from every peer's public key, hash-derived ULA addressing, `StrictSubnets`, tincr's in-mesh DNS, invitation hooks; no darwin module, no `exports`, crypto lines hard-coded.

## Decision chain

### Q1 — Is vanixiets "Commercial Use" under the nonfree controller licence?

Orchestrator's recommendation was "cannot rule out", with a stop-gap pin of cinnabar's controller to 1.14.2.
Operator (2026-11-17): vanixiets is not in violation.
The migration is prospective: follow the technology along its trajectory rather than being forced off legacy software in a panic at deprecation or end of life.
Consequences: no stop-gap controller pin; F20 is moot; no deadline.

### Q2 — One change or a staged series?

Orchestrator first proposed a staged series (groundwork registry → tincr pilot with go/no-go → iroh for deploys → retire ZeroTier).
Operator: design a DAG of parallel subagent tasks instead of gating everything on the groundwork.
The new mesh mirrors the topology while ZeroTier stays in place, so the system is redundant until cutover, and the only go/no-go needed is at the cutover decision.
Agreed (D1): one change, `migrate-mesh-to-tincr`, with task groups that run in parallel from an agreed contract (the registry schema and tincr addressing), and one operator-approved cutover decision gating the only irreversible part.
The one real dependency, the new zone needing the new mesh addresses, is a contract fixed up front, not a reason to serialize.

### Q3 — The name suffix

Operator: `.zt` names the transport; migrate to an industry-standard suffix.
Options weighed: `<host>.internal` / `<host>.vanixiets.internal` (ICANN reserved `.internal` for private use in 2024; never delegated), a subdomain of an owned domain (public CA possible, but certificate transparency logs expose host names and the name depends on the registration), `.vanixiets` (not reserved; same flaw as `.zt`), `home.arpa` (RFC 8375; residential scope).
Agreed (D2): `<host>.vanixiets.internal`; the fleet label lets a second fleet reuse the framework as `<host>.<fleet>.internal` without collision.
`.zt` is not kept.

### Q4 — The registry shape

Extend the existing `flake.lib.hosts` (it has consumers in otel, cognee and the fleet-alert check) with transport-neutral fields, rather than create the `flake.machines.<host>.meta` namespace O07/O08 name; update O07/O08 to match.
Generate the zone records, ssh HostName blocks, known-hosts, certificate SANs, firewall interface helper usage and `targetHost` from it.

### Q5 — `matrix.zt`

A Matrix homeserver's server name is its identity: it is the suffix of every user ID and room ID (for example the hermes home room `!Tthf05aI9YvVVsCF2d:matrix.zt`).
Options: keep one `matrix.zt` record indefinitely, or stand up a fresh homeserver as `matrix.vanixiets.internal`.
Operator: the server was a test server and its history is not needed; redeploy fresh (D3).

### Q6 — Why p2p-ssh-iroh in addition to tincr?

iroh does not make the mesh better: it carries no service traffic, is not faster, and has no darwin module.
Its one merit is a separate failure domain: when a change to the mesh breaks the mesh, a fix cannot be deployed over the mesh.
During the migration ZeroTier is that second path; after it, the question is break-glass access.
Operator: do not overzealously rule out a second recovery path; be reasonable and introduce things as relevant.
Agreed (D4): break-glass access is a requirement, not a preset answer; the design states which hosts need a recovery path independent of the mesh and introduces one where warranted, with iroh the leading candidate for NixOS hosts behind NAT, neither ruled in nor out.

### Q7 — CAM-81

Agreed (D5): CAM-81's Task 2 is rewritten to consume the neutral registry; its ZeroTier MAC pinning lives only until ZeroTier is retired.

### Q8 — The transport, and what if it fails

tincr stays the lead.
If the cutover decision rejects it, Headscale with self-hosted DERP is the recorded fallback, justified then by A3's NAT benchmark; it is not built here.

### Q9 — Crypto

tincr's defaults (ChaCha20-Poly1305, X25519) or Qubasa's opt-in x25519-mlkem768 with AES-256-GCM?
Every link to a C-tinc node, tincapp included, must stay on the defaults, and host files carry the setting mesh-wide [INFERENCE].
Operator (2026-11-17, relayed): tincapp's Google Play build is already installed on one of the Android phones (pixel7 or pixel11, unconfirmed), ready for experimentation.
Direction: defaults mesh-wide, with the post-quantum choice exposed as a setting and revisited when the phone client can carry it.

## Trade-offs carried into design

- Mirror-then-cutover costs running two meshes for a while and dual certificate SANs, and buys a reversible path up to the cutover decision.
- Vendoring Qubasa's service saves design work but the local clone carries no licence file; adapting it needs either Qubasa's grant or a first-party rewrite that uses it only as reference.
- tincr's maturity (no release, small circle) is accepted because the fallback (ZeroTier, untouched until cutover) costs nothing to keep while evidence accumulates.
- Deriving mesh addresses from host names at evaluation time means every consumer (zone, SANs, known-hosts, firewall, targetHost) needs no vars read, at the cost of addresses changing if a host is renamed.

## Operator answers after the proposal (2026-11-17)

- Qubasa/infra has no licence file, so its code is all rights reserved: the service is written first-party with it as reference only, and Qubasa is asked for a grant in parallel.
- CAM-81 holds its Task 2 (tasks 1.1–1.3 done, 2.x not started) until the contract lands; group K then rewrites it.
- pyrite needs unattended recovery, because it runs VM tests and remote builds; `p2p-ssh-iroh` is the lean, decided from evidence.
- tincapp is on pixel11, the Android test device and the only phone in the cutover verification; pixel7 is mostly retired, enrolled best-effort, and gates nothing, its own ZeroTier removal included.
- Soak: seven days.
- Linear: no fleet, infrastructure or networking project exists, so CAM-109 stays in CAM-106's project.
