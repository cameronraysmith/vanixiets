---
linear_story_id: CAM-81
linear_story_identifier: CAM-81
linear_story_title: "Accept mesh writes only under the host they come from"
linear_story_url: https://linear.app/cameronraysmith/issue/CAM-81/accept-mesh-writes-only-under-the-host-they-come-from
linear_story_state: Backlog
linear_team: CAM
linear_project: fleet-observability
last_synced_state: null
last_synced_at: null
review_round: 0
max_review_rounds: 3
attempt_log: []
---

## Why

Any holder of an `otel-ca` certificate can write series or deploy records as any host, including as an always-on host whose absence alert would then never fire, because the ingress never ties what a write claims to who sent it.
Stibnite now collects, and CAM-74 will route journald logs and omp metrics through the same ingress, so the gap widens with every stream.
This change makes a writer's identity a URI SAN in its certificate, checked by caddy together with the writer's ZeroTier address, and stores a mesh write only under the host that identity names.

## What Changes

Decisions tagged `O<n>` were made by the operator on 2026-11-06, each as `design.md` recommended under the question `Q<n>` of the same number; `brainstorm.md` records each with the operator's additions.

**A writer's identity**
- From: `otel-cert` carries `CN=<machine>` and no SAN, and nothing reads either (FM:966-986).
- To: every `otel-cert` also carries `URI:spiffe://vanixiets/host/<machine>`; caddy on magnetite's ZeroTier address verifies it, refuses with 403 a certificate whose SAN names no collecting host or a connection from an address other than that host's, and forwards the host name in a header it always overwrites (design D1, D2, D3; O1, O2, O5).
- Reason: the SAN names a writer on any path, which a source address cannot do once a Kubernetes writer arrives through a shared gateway; the address check turns a copied key into nothing on the mesh.
- Impact: every collecting host's certificate is reissued in one vars step, with `otel-ca` unchanged; non-breaking for honest hosts once each presents its new certificate.

**What the ingress stores**
- From: `otlp/mesh` listens on magnetite's ZeroTier address and feeds `metrics/ingress` and `logs/ingress` directly.
- To: `otlp/mesh` listens on a Unix socket only caddy can reach and feeds `metrics/mesh` and `logs/mesh`, which drop any resource whose `host.name`, and any record whose `host`, differs from caddy's header, and any point or record carrying its own host attribute, before the existing `forward` connector (D3, D5, D8; O3).
- Reason: dropping keeps forged data out and leaves a counted trace, where an overwrite would store the forgery under the sender's name without one.
- Impact: magnetite only; magnetite's own agent keeps its in-process path.

**The neighbour-spoofing gap**
- From: a member with root can overwrite magnetite's neighbour entry for another member's address with one unsolicited advertisement, and a ZeroTier `ipauth` rule would not stop it, because at 1.16.0 it accepts any address in the network's /88 from any member.
- To: magnetite holds a permanent neighbour entry for every collecting host's ZeroTier address, naming the MAC derived from that host's node id; the derivation matched magnetite's live table for all five addresses present on 2026-11-06, and the same comparison is a mandatory gate before the deploy, with a rollback over magnetite's public SSH (D4; O4).
- Impact: magnetite only; no controller or flow-rule change.

**Regulation**
- magnetite's `otel-envelope` gains C6, failing when the binding filter drops a write, caddy refuses one, or a collecting host's neighbour entry is not permanent with its derived MAC; C2 watches caddy's metrics endpoint (D6).
- `flake.lib.hosts` becomes the one source of every collecting host's ZeroTier address, checked against the clan vars and the controller's `allowedIps` (D7).

**Deployment**
- Implementation starts only after `stand-up-darwin-collection` archives (O6).
- Pull request 1 reissues the certificates and deploys magnetite, cinnabar and pyrite and activates stibnite; pull request 2 adds caddy, the mesh pipelines, the filter, the neighbour entries and C6, and deploys magnetite alone after the MAC gate; pull request 3 carries the documentation and the charter v30 entry (design "Migration Plan").

## Capabilities

### New Capabilities

None.
The binding narrows an existing capability's trust boundary rather than adding an area of behaviour.

### Modified Capabilities

- `fleet-ingress-interface` (stratum: `interface`): `One host table declares the agent hosts and what each reports` gains each host's overlay address from `flake.lib.hosts`, checked against its second source; `The collection CA issues each agent host one certificate` adds the URI SAN and the reissue; `The ingress receiver accepts only certificate holders on magnetite's ZeroTier address` moves the listener to caddy and the receiver to a socket; five requirements are added: `A mesh write is accepted only from the host its certificate names, at that host's overlay address`, `A mesh write is stored only under the host that sent it`, `magnetite pins each collecting host's neighbour entry`, `otel-envelope on the ingress host fails when the binding refuses or drops a write` and `The ingress proxy runs inside a declared envelope`; `This capability states its own trust boundary` is rewritten.
  Trust boundary: a certificate holder writes over the mesh only under its own host, and only from its own overlay address; root on a collecting host can still write anything as that host, a local account on an agent host can still inject points as that host through its loopback agent, root on magnetite can write anything, a stolen laptop writes as itself until deauthorized on cinnabar, and certificates still have no revocation; nothing here guarantees a series reaches the store end to end.
- `telemetry-store-interface` (stratum: `interface`): `This capability states its own trust boundary` gains `A guarantee about a series' host is sought`: yes over the mesh, no for root on magnetite and for magnetite's own in-process path.
- `devloop-collection-interface` (stratum: `interface`): `This capability states its own trust boundary` changes `A guarantee about a record's host is sought` to yes over the mesh, no for magnetite's own rows.
- `host-metrics-collection` (stratum: `behavioral`): adds `A series is stored only under the host that gathered it` (O7).
- `devloop-collection` (stratum: `behavioral`): adds `A deploy record names the collected host that sent it` (O7).
- `world-assumptions` (stratum: `world`): A71 to A76 record ZeroTier's MAC binding, its unauthenticated rfc4193 sources and advertisements, Linux's permanent neighbour entries, the network's rfc4193 assignment with the accept-all rule, caddy's SAN, header, status and count behaviour, and the filter's 200 on a drop; `Grounded vocabulary for behavioral requirements` revises `overlay network` and adds `overlay member` and `overlay address`.
  Every modified requirement is written on top of `stand-up-darwin-collection`'s delta to it, where that change modifies it, and is rebased onto the archived corpus before pull request 1.

## Impact

- New: caddy on magnetite, on the ZeroTier address at port 4318, with its own memory bound, kill-order place and failure notice; the binding filters; the neighbour entries; C6.
- Changed: FM (`otel-cert`'s SAN, the receiver on a socket, the mesh pipelines and filters, caddy's configuration), HS (every collecting host's address), OE (C6), OCC (the address sources, the endpoint clause naming caddy's listener), `checks.x86_64-linux.otel-envelope` (C6 cases), `flake.lib.otelTestPki` (one certificate per fixture identity), FI (the binding and neighbour legs), magnetite's machine module (kill order, `09-zerotier` neighbours).
- Vars: every collecting host's `otel-cert` is regenerated with `CLAN_NO_COMMIT=1`; `otel-ca` and `ntfy-alerter` are unchanged, and their hashes are compared before and after.
- Documentation: ADR-003's Consequences (:199-201) and its R3.1, the reference architecture (:102), `components/otel-collector.md`, the collector README and the runbook's lost-machine steps, and the charter v30 entry after S5's v29.
- Sequencing: implementation after `stand-up-darwin-collection` archives and before CAM-74 (O6).
- Residual risk: certificates still live 10 years with no revocation, which CAM-82 owns (O8); other mesh services that trust a source address, ntfy's per-address rate limit among them, keep the spoofing gap, which a follow-up issue owns (O9).
- Out of scope: Kubernetes write paths themselves, short-lived certificates, a ZeroTier flow rule, and the content stages CAM-74 repeats in the mesh pipelines.
