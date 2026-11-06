# Brainstorm: accept mesh writes only under the host they come from (CAM-81)

## Background

CAM-81 closes the gap that ADR-003's Consequences record at `docs/notes/development/observability/decisions/ADR-003-collection-topology.md:199`: the ingress accepts any `otel-ca` certificate holder and never checks that the `host.name` it sends, or a deploy record's `host`, belongs to that holder.
Any holder can therefore write series or `deploy_record` rows as any host, including as an always-on host whose silence would otherwise raise `RuleSignalMissing`.
The issue asks for the binding to cover metrics, logs and every pipeline that accepts mesh writes, for the envelope to fail when the binding drops a write, for the neighbour-spoofing gap to be closed rather than accepted, and for certificate identity to be weighed on its merits against the source-address binding.
The operator's standing principle of 2026-11-06 governs the choice: take the architecturally durable option unless its cost is out of proportion, and do not accept short-term debt for expediency.
Classification under `skill://brainstorming`: architectural, because the change decides what a fleet writer's identity is, which every later write path (CAM-74's log streams, the planned Kubernetes paths) inherits.

Abbreviations used below: `OBS` is `docs/notes/development/observability/`; A3 is `OBS/decisions/ADR-003-collection-topology.md`; CH is `OBS/charter.md`; RA is `OBS/architecture/reference-architecture.md`; FM is `modules/clan/services/otel-collector/flake-module.nix`; SC is `schema.nix` beside it; HT is `modules/lib/observability-hosts.nix`; HS is `modules/lib/hosts.nix`; OE is `modules/lib/otel-envelope.nix`; FI is `modules/vm-tests/fleet-ingress.nix`; OCC is `modules/checks/otel-collector-config.nix`; ZI is `modules/clan/inventory/services/zerotier.nix`; K9 and K10 are `docs/notes/development/kubernetes/decisions/ADR-009-capi-node-management-and-networking.md` and `ADR-010-identity-tiers-and-non-circular-bootstrap.md`; S5 is the open change `openspec/changes/stand-up-darwin-collection/` (CAM-72).
Upstream sources are cited at the versions magnetite evaluates: ZeroTierOne 1.16.0 (`ZT`), Linux 6.18.58, caddy 2.11.7 (cinnabar's version and `pkgs.caddy` in magnetite's evaluation), otelcol-contrib 0.155.0 with core `confighttp` v0.155.0 and `client`, `confignet` v1.61.0, systemd networkd through nixpkgs `nixpkgs_10` at `3a32588c`, and clan-core at `dbae2101`.

Inputs gathered on 2026-11-06:

- `linear issue view CAM-81`, CAM-72 (Todo, stibnite collecting since `e3f30fd4`, pull requests 3 and 4 pending) and CAM-74 (Backlog).
- The 2026-11-06 research on certificate-name binding, whose citations were re-verified at the versions above; two of its premises did not survive, as "Contradictions found" records.
- The repository at `main` `2ea47ee5`: the collector service, the host table, the address registry, the envelope, the container test, the collector check, the specs, the charter at v28 and the Kubernetes decision records.
- Evaluations of magnetite's and electrum's configurations, recorded under "Found while preparing".

## Status of the decisions

The operator answered the eleven questions `design.md` put on 2026-11-06, each as recommended, with the additions recorded below; question `Q<n>` became decision `O<n>`.
Decisions the evidence settles are marked as the orchestrator's.

- Decision (O1, decided by the operator, 2026-11-06): the URI SAN verified by caddy, with the source address as a second factor; nginx's fingerprint form is rejected because it pins one certificate, which conflicts with the short-lived issuance CAM-82 may adopt, nginx 1.30.6 cannot read SANs, and CN matching is legacy and absent from SPIFFE certificates.
- Decision (O2, 2026-11-06): `URI:spiffe://vanixiets/host/<machine>`.
- Decision (O3, 2026-11-06): drop, count, and fail C6.
- Decision (O4, 2026-11-06): permanent neighbour entries on magnetite, with the computed MAC compared against magnetite's live neighbour table as a mandatory pre-deploy gate, because a wrong entry cuts magnetite off from that host over ZeroTier entirely (SSH, builds, telemetry), and a rollback step.
- Decision (O5, 2026-11-06): 403.
- Decision (O6, 2026-11-06): the specs, tasks and plan are written now; implementation starts only after `stand-up-darwin-collection` archives, held by a gate task.
- Decision (O7, 2026-11-06): behavioral requirements are added to `host-metrics-collection` and `devloop-collection`.
- Decision (O8, 2026-11-06): certificate lifetime stays in CAM-82.
- Decision (O9, 2026-11-06): a follow-up Linear issue lists the other mesh services that trust a source address; the orchestrator drafts it and the operator files it.
- Decision (O10, 2026-11-06): the spoofing acceptance runs from pyrite with the operator present, only after the entries are deployed and verified.
- Decision (O11, 2026-11-06): the operator binds CAM-81 and corrects its text from the orchestrator's draft.

### Resolved after the decisions (2026-11-06)

- The header's OTTL form, from source: metadata keys are stored and looked up lower-cased (`client@v1.61.0:client.go:146-175`), `otelcol.client.metadata["x-vanixiets-host"]` is a string slice and `[0]` a string, and an absent header yields nil before indexing (`pkg/ottl@v0.155.0:contexts/internal/ctxotelcol/client.go:194-215`; `otelcol.go:44-61`); the vendored-binary probe of the exact filter configuration stays a gate, because the reading does not exercise context inference.
- The MAC derivation against the live table: a read-only `ip -j -6 neigh show` on magnetite listed stibnite (`02:9d:0d:e2:00:15`, REACHABLE), cinnabar (`02:62:57:7f:00:7f`), pyrite (`02:c7:94:5c:b4:6c`) and the phone `pixel11` (`02:85:9d:a2:af:fc`, STALE), and `ip link` gave magnetite's own `zt554fbdjy` as `02:b6:2d:e0:74:96`; `MAC::fromAddress` (`zerotierone@1.16.0:node/MAC.hpp:163-196`) over network `db4344343b14b903` gave the same five values; the comparison is still repeated as the mandatory gate immediately before the deploy.
- Honest host attributes on points: no line of the Prometheus targets the agents scrape on cinnabar, pyrite and stibnite carried a `host_name` or `host.name` label; the store's own handling of a colliding point attribute therefore matters only for forged points, which the filter drops; the survey is repeated as a gate before pull request 2.
- zerotierone restart against permanent entries: not resolvable without restarting zerotierone on magnetite; it becomes an operator-present step over the public SSH path after the deploy, and C6's live-table clause catches a loss on every run meanwhile.
- The rollback path: magnetite's sshd listens on public port 22 (`networking.firewall.allowedTCPPorts`), `magnetite.scientistexperience.net` resolves to 49.12.12.74, and `clan machines update` accepts `--target-host`, so a deploy and a neighbour deletion both have a path that does not cross ZeroTier.
- Other mesh services and source addresses: ntfy on cinnabar keys each visitor by its full source address through caddy's forwarding header (`modules/machines/nixos/cinnabar/ntfy.nix:44-53`), and the alerter token carries no tier, so its posts are rate-limited per address (A40); a member claiming magnetite's or cinnabar's address toward cinnabar could spend the budget their alerts post from.
  Every other mesh listener found authenticates by credential or by membership alone: nix-grpc-daemon on 50051 by mTLS CN, omnigraph on 8090 by bearer token, radicle on 8776 by node identity, and caddy's `.zt` sites and dnsmasq on cinnabar by membership; their logs attribute requests by address.

## Grounding evidence

### What the ingress does today

- `otlp/mesh` is an OTLP/HTTP receiver on `[${flake.lib.hosts.magnetite.zt}]:4318` with `otel-cert`, `client_ca_file` the `otel-ca` certificate and `min_version: "1.3"` (FM:783-791), and it feeds `metrics/ingress` and `logs/ingress` beside the in-process `forward` connector that carries magnetite's own agent (FM:815-825, :871-878).
- The firewall opens TCP 4318 on `zt+` only (FM:1126); magnetite's evaluated `zt+` ports are 4318, 8090 and 50051.
- Every non-ingress agent stamps `host.name` with `resource/agent`, an upsert of the machine name, in `metrics/host` and `metrics/process` (electrum's evaluated pipelines, 2026-11-06), and `resource/devloop-deploy_record` stamps it on deploy records (FM:546-562).
- A deploy record's `host` column comes from the record's own JSON field, kept as a log attribute by `keepAttributes` (FM:533-545; SC:249-256), not from the resource.
- `otel-cert` carries `/CN=<machine>` and no SAN except on the ingress host, valid 3650 days; its SANs and usage enter clan's `validation`, so changing the SAN string regenerates every host's certificate, while the shared `otel-ca` definition stays unchanged (FM:941-986).
- The ingress container test runs one systemd-nspawn container whose loopback stands in for magnetite's ZeroTier address (FI:1-23, :745-746); its budget fixtures write `budgethost` and `cinnabar` through `otlp/mesh` with the single test agent certificate (FI:537-557, :582, :591, :602).
- OE's C4 exempts `otlp/mesh` refusals on the ingress host as back-pressure (OE:21-26, :452-460).
- OCC's R3.1 endpoint clause allows exactly one endpoint off loopback, `otlp/mesh` on the address in `vars/shared/zerotier-ip-magnetite-zerotier/ip/value` (OCC:78, :281-293).
- HS calls itself the canonical registry of mesh addresses and holds only magnetite's (HS:1-9); the six clan peers' addresses are in `vars/shared/zerotier-ip-<host>-zerotier/ip/value`, and stibnite's only in ZI's `allowedIps` comment list (ZI:18).

### What the trust boundary says now

- `openspec/specs/fleet-ingress-interface/spec.md:5` and its scenario at :177-180 state that a certificate's CN is not bound to the stamped `host.name`; :187-190 state that ZeroTier authenticates no writer.
- `openspec/specs/devloop-collection-interface/spec.md:383-386` states that any holder can send a `deploy_record` row naming any host.
- `openspec/specs/telemetry-store-interface/spec.md:532-561` states no host-attribution property at all.
- A3:199-201 and RA:102 carry the same gap; A3:200 also records that local emitters reach an agent over unauthenticated loopback, which this change does not alter.

### What the pinned collector can and cannot see

- The receiver wraps its listener in TLS and sets no `ConnContext` (`confighttp@v0.155.0:server.go:142-150`), so request handling never sees the peer certificate.
- `client.Info` holds only `Addr`, `Auth` and `Metadata` (`client@v1.61.0:client.go:91-107`); `Addr` comes from `RemoteAddr`, and headers reach `Metadata` only with `include_metadata` (`confighttp@v0.155.0:clientinfohandler.go:31-49`).
- OTTL exposes `otelcol.client.addr` and `otelcol.client.metadata` in the resource and log contexts (`pkg/ottl@v0.155.0:contexts/internal/ctxotelcol/client.go:48-67`, `:181-215`; `ottlresource/resource.go:94`, `:168`; `ottllog/log.go:144`, `:226`).
- The receiver can listen on a Unix socket: `NetAddr`'s transport accepts `unix` (`confighttp@v0.155.0:server.go:39-43`; `confignet@v1.61.0:confignet.go:27`, `:111-133`).
- A filter that drops data answers the sender 2xx: dropping everything returns `ErrSkipProcessingData`, which the processor helper turns into success (`filterprocessor@v0.155.0:logs.go:120-121`), and `error_mode: propagate` raises only OTTL evaluation errors (`:115-117`).
- The drop counters are `otelcol_processor_filter_datapoints_filtered` and `otelcol_processor_filter_logs_filtered`, labelled `filter="<processor id>"` (`filterprocessor@v0.155.0:metadata.yaml:28-43`; `telemetry.go:45`); whether the Prometheus name carries `_total` is unverified, and the repository's 0.155.0 fixtures show self-metrics without it (`modules/checks/otel-envelope/fixtures/`).
- The only collector stage that refuses with a status the sender retries is `memory_limiter`, whose refusal maps to 503 (`memorylimiterprocessor/memorylimiter.go:58`; `otlpreceiver/internal/errors/errors.go:15-24`, `:37-38`).
- The client address does not survive a batch processor (`batchprocessor@v0.155.0:batch_processor.go:153-156`); the ingress runs none, and the routing connector forwards the same context (`routingconnector@v0.155.0:logs.go:151`).

### What caddy 2.11.7 offers

- The verified client certificate's URI SANs are placeholders, `{http.request.tls.client.san.uris.<n>}` (`modules/caddyhttp/replacer.go:514-545`); without a client certificate the placeholder renders empty (:500-512).
- `require_and_verify` client authentication with a `trust_pool` of PEM files, and `protocols tls1.3` per connection policy (`modules/caddytls/connpolicy.go:592`, :622-637, :651-722, :850-861; :207-208, :373-374).
- `header_up <name> <value>` replaces any client-sent header of that name (`headers/caddyfile.go:281-285`; `headers/headers.go:258-275`; `reverseproxy/reverseproxy.go:702-716`).
- `reverse_proxy` passes an upstream status and body through unchanged, so the collector's 503 reaches the agent as 503 (`reverseproxy.go:1313`, `:1326`).
- `map` expands lazily, takes the first literal match, and falls back to its `default` (`modules/caddyhttp/map/map.go:127-174`); the `vars` matcher compares a placeholder with an expanded value (`vars.go:177-232`).
- `{http.request.remote.host}` is the peer address without brackets (`replacer.go:159-173`), in Go's compressed form `[INFERENCE]`, the form ZI's comments already use.
- With the global `metrics` option, the admin endpoint's `/metrics` serves `caddy_http_request_duration_seconds_count{server,handler,code,method}`, and a `respond 403` is counted with `code="403"` while `abort` is not counted (`httpcaddyfile/options.go:503-519`; `caddyhttp/metrics.go:103-163`, :346-385; `staticresp.go:183-184`); the admin endpoint can bind a Unix socket (`admin.go:229-230`).
- nginx 1.30.6, which already fronts magnetite's public sites, exposes no SAN variable (`ngx_http_ssl_module.c:394-435`), only the subject DN and the fingerprint.

### What ZeroTier 1.16.0 does with addresses

- The controller assigns each member the rfc4193 address `fd` + network id + `9993` + node id, turns on NDP emulation (`ZT:nonfree/controller/EmbeddedNetworkController.cpp:2050-2054`; `node/InetAddress.cpp:490-513`) and issues a certificate of ownership for exactly those addresses (:2249-2256).
- A member's MAC on the network is derived from its node id and the network id (`node/MAC.hpp:163-196`), and the receiver binds an inbound frame's source MAC to the authenticated sending peer (`node/IncomingPacket.cpp:842`, :963-971).
- With emulation, a node answers its own outbound neighbour solicitation for an rfc4193 address locally, with the MAC of the node the address names (`node/Switch.cpp:378-492`).
- An inbound neighbour advertisement is not inspected: no NDP handling exists on the inbound path, and the TLLA option is never read (`IncomingPacket.cpp:845`, :961; `Network.cpp:923-948`).
- The `ipauth` characteristic does not tie an rfc4193 address to its sender: for an IPv6 source or an NA target it falls back to `_isV6NDPEmulated`, which accepts any address inside the network's /88 whichever node sent it (`node/Network.cpp:408-462`; `node/Membership.hpp:118`, :180-222).
- `drop not chr ipauth;` would also drop every link-local frame, including MLD and the multicast DNS networkd enables on `zt*` (`Network.cpp:433-441`), while still admitting a member that claims another member's rfc4193 address.
- clan-core's zerotier service writes the network's JSON with `rules = [ { type = "ACTION_ACCEPT"; } ]` and `v6AssignMode.rfc4193 = true`, exposing rules only through the untyped `settings` JSON (`clan-core@dbae2101:clanServices/zerotier/default.nix:260-321`).
- External members, stibnite among them, are authorized by `zerotier-members allow --member-ip` from ZI's `allowedIps` (`default.nix:331-343`; ZI:15-22).

### What Linux 6.18.58 does with neighbour advertisements

- An unsolicited NA with the override flag replaces the link-layer address of an existing REACHABLE or STALE entry (`net/ipv6/ndisc.c:1100-1108`; `net/core/neighbour.c:1414-1427`).
- An NA never changes a `NUD_PERMANENT` or `NUD_NOARP` entry (`neighbour.c:1351-1353`).
- `drop_unsolicited_na` is no defence, because the attacker can set the solicited flag (`ndisc.c:1019-1021`).
- networkd installs a `[Neighbor]` entry as permanent (`systemd@v258:src/network/networkd-neighbor.c:293`, `[INFERENCE]` for the pinned systemd 262), exposed as `systemd.network.networks.<name>.neighbors` (`nixpkgs@3a32588c:nixos/modules/system/boot/networkd.nix:3080-3093`, :1335-1340).

### What the Kubernetes plans imply for write paths

- Kubernetes nodes never join the ZeroTier network (K9:144, :160-162).
- Their admin overlay is one gateway per cluster peering over a Clan `wireguard` instance (K9:158-165), so anything a cluster writes to the fleet reaches it from a gateway's address, shared by every workload behind it.
- Node identity is disposable and never referenced outside the cluster (K10:54-59).
- No current document plans a cluster write into the fleet store; the durability test is therefore that whatever writer identity this change adopts must also name a writer that arrives over a non-ZeroTier path, behind a shared address.

### Found while preparing (2026-11-06)

- magnetite runs systemd-networkd (`networking.useNetworkd = true`), and its ZeroTier link is configured by `09-zerotier` (`Name=zt*`, `KeepConfiguration=static`); its network id is `db4344343b14b903`.
- magnetite's collector runs with `DynamicUser`, `MemoryMax = 512M` and `OOMScoreAdjust = 300`; magnetite runs nginx and no caddy.
- magnetite's kill-order assertion compares `nix-eval-jobs`, `perses`, `greptimedb`, `opentelemetry-collector` and `fleet-alert` (`modules/machines/nixos/magnetite/default.nix:716-740`).
- The newest world assumption on `main` is A69; S5 uses up to A70, so this change starts at A71.
- The charter is at v28 on `main`, and S5 plans v29, so this change's entry is v30.
- nixpkgs at the pin has no ZeroTier NixOS test; clan-core's `clanServices/zerotier/tests/vm/default.nix` runs a controller, a moon and two peers offline, but needs QEMU, which magnetite lacks (A32).

### Contradictions found

- C1, the flow rule: the 2026-11-06 research proposed `drop not chr ipauth` on cinnabar's controller to stop a member from claiming another member's address; at 1.16.0 `ipauth` accepts any rfc4193 address in the network's /88 from any member, so the rule would not close the gap and would drop all link-local traffic.
- C2, the handshake argument: the research inferred that a forged source address cannot complete a TCP handshake because replies go to the address's owner; that holds only while magnetite's neighbour entry for the address names the owner's MAC, which a member with root can overwrite with one unsolicited NA.
- C3, a non-200 refusal: CAM-81 says a dropped write still returns 200; the filter has no reject action, so a refusal the sender can see must come from a stage in front of the collector.
- C4, header trust: the research's caddy option leaves a loopback receiver to which any local process on magnetite can post a forged identity header.
- C5, one source of addresses: HS claims to be the canonical address registry while holding one host, the clan peers' addresses live in vars, and stibnite's lives in a comment.

## Decision chain

### D1. What a writer's identity is (Q1)

Options:

1. The source ZeroTier address, checked in the collector against `otelcol.client.addr`.
2. A URI SAN on `otel-cert`, verified by caddy in front of a receiver only caddy can reach and forwarded in a header caddy always overwrites.
3. Both: the SAN is the identity on every path, and on the ZeroTier listener caddy also requires the connection to come from the address of the host the SAN names.

What each leaves an attacker:

| Attacker | 1. address | 2. SAN | 3. both |
|---|---|---|---|
| A copied `otel-key`, used from a phone or any member not in the table | dropped | writes as the key's host until `otel-ca` is rotated | refused with 403 |
| A copied `otel-key`, used from another collecting host | writes as that other host only | writes as the key's host | refused with 403 |
| A phone or other member without a key | refused at the handshake | refused at the handshake | refused at the handshake |
| Root on a collecting host | writes as any host whose neighbour entry it can overwrite on magnetite, unless D4 pins them | writes as its own host only | writes as its own host only |
| A stolen laptop with its key and its ZeroTier identity | writes as itself until deauthorized on cinnabar | writes as itself from any member until `otel-ca` is rotated | writes as itself until deauthorized on cinnabar |
| A writer arriving over a non-ZeroTier path behind a shared address | cannot be identified | identified by its SAN | identified by its SAN; the address factor applies only on the ZeroTier listener |
| Root on magnetite | anything | anything | anything |

Recommended (Q1): option 3.

- The SAN is the identity because it is the only one of the three that names a writer on any path; the address cannot pass the durability test, since a Kubernetes writer arrives behind a shared gateway address with a disposable node identity (K9:158-165; K10:54-59).
- The address is kept as a second factor on the ZeroTier listener because it costs one `map` entry per host and turns a copied key into nothing: the key is useful only from the node whose ZeroTier identity secret, readable only by that host's root, completes the handshake (`vars/shared/zerotier-identity-*/identity-secret/machines/`).
- It also makes deauthorization on cinnabar's controller the immediate cut-off for a lost laptop, without waiting for a CA rotation.
- Rejected: option 1 alone, which fails the durability test and leaves a copied key usable from any collecting host; option 2 alone, which leaves a copied key usable from any member for up to 10 years.
- Rejected: binding the CN through nginx, which needs no reissue but parses a DN string, couples the mesh ingress to the public nginx instance, and keeps identity in the subject CN, which RFC 6125 already retires for server identity.

### D2. The SAN and its issue (Q2)

Recommended (Q2): `URI:spiffe://vanixiets/host/<machine>` on every `otel-cert`, beside the CN, which stays.

- A URI says it is an identity rather than a name to resolve, and a URI SAN is the form an X.509 SPIFFE identity takes, so a later cluster writer can carry `spiffe://vanixiets/cluster/<name>` from the same or a sibling CA `[INFERENCE: cert-manager's URI support was not read at a pin]`.
- The trust domain names the repository, not a transport, so `.zt` is avoided.
- The SAN enters `validation`, so one vars step regenerates every collecting host's `otel-cert` (magnetite, cinnabar, pyrite, electrum, galena, scheelite, stibnite) with `CLAN_NO_COMMIT=1`; `otel-ca` is a shared generator whose definition does not change, so it is not regenerated, and the sha256 of `ca.crt` and of the `ntfy-alerter` token are compared before and after, as the existing scenario requires.

### D3. Where each check runs

Decision (orchestrator, from C3 and C4):

- caddy on magnetite listens on `[${flake.lib.hosts.magnetite.zt}]:4318` with `require_and_verify` against `otel-ca`, TLS 1.3 only, and magnetite's `otel-cert` as its server certificate.
- caddy maps the verified URI SAN to the host name and to the host's ZeroTier address, both rendered from one Nix table, and answers 403 when the SAN maps to no host or the peer address differs from the mapped address.
- caddy forwards the mapped host name in `X-Vanixiets-Host` with `header_up`, which replaces any value the client sent.
- The collector's `otlp/mesh` moves to a Unix socket in a directory that only the collector and caddy can traverse, with `include_metadata: true`, so no other local process can post a forged header (C4); root on magnetite still can, as it can already write the store.
- `otlp/mesh` feeds only `metrics/mesh` and `logs/mesh`, each `memory_limiter` then the binding filter, ending in the existing `forward` connector; `metrics/ingress` and `logs/ingress` keep `forward` alone, so magnetite's own agent never meets the binding.
- Boundary: caddy, the collector and networkd are vendored consumers whose configuration is first-party; the vendored behaviours this decision relies on are the world assumptions of D9.

### D4. Closing the neighbour-spoofing gap (Q4)

Options: an `ipauth` flow rule on cinnabar's controller; per-host `ipsrc`/`ztsrc` flow rules; permanent neighbour entries on magnetite; relying on the SAN alone.

Recommended (Q4): permanent neighbour entries on magnetite for every collecting host's ZeroTier address, each naming the MAC derived from that address's node id and the network id, through `systemd.network.networks."09-zerotier".neighbors`, with a regulator.

- The `ipauth` rule does not close the gap (C1), and per-host `ipsrc`/`ztsrc` rules could stop a forged source address but match no NA target, so they leave the poisoning path open `[INFERENCE: the rule primitives were not read at the pin]`.
- A permanent entry resists every NA (`neighbour.c:1351-1353`), and the MAC it names reaches only the node whose identity it derives from (`MAC.hpp:163-196`; `IncomingPacket.cpp:842`), so a forged-source SYN's SYN-ACK goes to the real owner and the handshake cannot complete.
- The entries are derived from the addresses alone, so they add no new data, and they hold against root on any member, cinnabar's included, because cinnabar can deauthorize a node but cannot make another node's MAC its own `[INFERENCE: unicast delivery follows MAC::toAddress, MAC.hpp:183-191; the bridging paths were not traced]`.
- The SAN alone would make the gap moot for this ingress, but the address factor of D1 rests on it, and the operator ruled out leaving it open.
- The gap stays open for other mesh services that trust a source address; none binds identity to one today, so this is recorded as a world assumption and a follow-up, not widened into this change (Q9).

### D5. Drop or overwrite a mismatched host (Q3)

Recommended (Q3): drop, count and fail the envelope.

- An honest sender stamps `host.name` with the same machine name its certificate carries, both rendered from `machine.name`, so a mismatch from an honest sender is a configuration fault that a check can catch before deploy; overwriting would only hide it.
- Overwriting a forged write would store attacker-chosen series and deploy records under the attacker's own name, and the forgery would leave no trace.
- Dropping keeps forged data out and turns every mismatch into a counted event the envelope reports within one run.
- The filter drops a resource whose `host.name` differs from the header, a log record whose `host` attribute differs from it, and any data point or log record carrying its own `host.name` or `host_name` attribute, which could otherwise collide with the promoted `host_name` column `[INFERENCE: the store's collision behaviour is unverified]`.

### D6. What a refused or dropped write tells the sender and the operator (Q5)

- caddy's 403 is visible to the sender, whose exporter treats it as permanent, drops the batch and counts `otelcol_exporter_send_failed_*`, which its own `otel-envelope` C4 reports.
- The filter's drop answers 200, so only magnetite sees it.
- Recommended (Q5): 403, not a retryable 503, for an unmapped SAN or a wrong address; a retryable status would keep an honest misconfigured host's queue growing for up to 24 h before C3 fails, while the address checks of D7 make the honest case a pre-deploy failure.
- magnetite's `otel-envelope` gains a binding clause C6: since the previous run, a rise of the filter's drop counters for the binding filters, a rise of caddy's 403 count on the mesh server, or any collecting host's neighbour entry on `zt*` that is not permanent with its derived MAC fails the run; C2 gains caddy's metrics endpoint as a target, so a stopped caddy fails on two consecutive runs.

### D7. One source of mesh addresses (C5)

Decision (orchestrator): HS gains every collecting host's `zt` address, stibnite's included, and an OCC clause compares each with its second source, `vars/shared/zerotier-ip-<host>-zerotier/ip/value` for the clan peers and ZI's `allowedIps` for stibnite, and checks that each address embeds the network id `db4344343b14b903`.
caddy's maps, the filter's host list and the neighbour entries are rendered from HT's collecting hosts joined with HS, and magnetite asserts that the three agree, each assertion shown failing by an `extendModules` override.

### D8. Every pipeline that accepts mesh writes

Decision (orchestrator):

- A magnetite assertion holds that `otlp/mesh` appears only in pipelines whose processors begin with `memory_limiter` and the binding filter for that signal, and that no other receiver is off loopback; a later traces pipeline or CAM-74's journald and omp streams therefore inherit the binding or fail evaluation.
- CAM-74 repeats its content stages in `logs/mesh` and `metrics/mesh` after the binding, because a certificate holder posting directly skips the agent's stages (RA:130-132).

### D9. World assumptions (A71 onward)

- A71: ZeroTier 1.16.0 delivers a frame for a member's MAC only to that member, whose MAC derives from its node id and the network id.
- A72: ZeroTier 1.16.0 neither inspects an inbound NA nor ties an rfc4193 source or NA target to its sender, so a member with root can claim another member's address on the wire.
- A73: Linux 6.18 never changes a permanent neighbour entry on an NA, and lets an override NA rewrite a non-permanent one.
- A74: the fleet network assigns rfc4193 addresses with NDP emulation and carries only the accept-all rule.
- A75: caddy 2.11.7 exposes a verified client certificate's URI SANs, replaces a `header_up` header, and passes an upstream status through.
- A76: otelcol-contrib 0.155.0's filter answers 2xx for a dropped write and counts it per processor id.
- The `overlay network` row (`openspec/specs/world-assumptions/spec.md:199`) adds that membership does not authenticate the source address a member sends from; new rows: `host identity`, `mesh write`.
- Each version-bound assumption carries a trigger that fires when its version moves (#3690).

### D10. Tests

Decision (orchestrator):

- `vmTests.x86_64-linux.fleet-ingress` runs caddy in front of the socket receiver on `127.0.0.1:4318`, with a test address table that maps electrum's identity to `127.0.0.1` and the budget fixtures' identities to `127.0.0.2` (`budgethost`) and `127.0.0.3` (`cinnabar`), each fixture writing with its own certificate from `flake.lib.otelTestPki` and `curl --interface`.
- New legs: a matching write is stored; a mismatched `host.name` is dropped and fails C6; a mismatched deploy-record `host` is dropped and fails C6; an unlisted source address and a certificate without a mapped SAN get 403 and fail C6; a forged `X-Vanixiets-Host` is overwritten; a non-caddy local user cannot open the socket.
- A neighbour leg adds a second container on the test network `[INFERENCE: runNixOSTest containers share a test network]`: the store side carries the permanent entries rendered by the same function as magnetite's, the attacker sends an unsolicited override NA for the victim's address and connects from it with a copy of the victim's key, the entry stays permanent and the handshake does not complete; a mutant without the entries lets the write through, showing the entries are load-bearing.
- At acceptance, with the operator present, pyrite as root makes the same attempt over the real mesh against stibnite's pinned address, and a baseline against a phone's unpinned address shows the overwrite that A72 and A73 predict (Q10).

### D11. Deployment (Q6)

Decision (orchestrator, from the schema's migration-plan rule):

- Pull request 1: the SAN, HS's addresses, the checks; the vars step regenerates every `otel-cert`; magnetite, cinnabar and pyrite deploy and stibnite activates, so each agent presents its SAN before any listener requires it; electrum, galena and scheelite take theirs when next provisioned (A50).
- Pull request 2: caddy, the socket receiver, the mesh pipelines and filters, the neighbour entries and C6; magnetite alone deploys.
- Pull request 3: documentation, the decision-record amendments and the charter v30 entry.
- Rollback of pull request 2 is a revert and a magnetite deploy; the reissued certificates are harmless without it.

## Rules adopted from earlier retrospectives (#3690)

- A pre-deploy probe of a vendored consumer runs its exact arguments: caddy with the rendered Caddyfile through `caddy validate`, and the collector's exact OTTL conditions against a scratch configuration.
- Each deploy task reads every alert and notice posted since its deploy started, and records each with its cause.
- Shared data another host's closure reads (HS, HT) lists that host in the deploy order.
- Each version-bound assumption carries a trigger on its version.
- An assumption's verified status names what was observed and over which window.

## Left for design and the specs

- The rendered Caddyfile, the socket's directory and group, caddy's envelope and kill-order place.
- The exact OTTL conditions, probed against the vendored collector.
- C6's state keys and its mutants in `checks.x86_64-linux.otel-envelope`.
- Each changed check's evaluation cost against 536,870,912 B, before and after.
- The spec deltas, layered on S5's deltas to the same requirements.
