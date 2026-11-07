## Context

This change closes CAM-81: the fleet ingress on magnetite accepts any `otel-ca` certificate holder and never ties a write's `host.name`, or a deploy record's `host`, to the holder that sent it (`docs/notes/development/observability/decisions/ADR-003-collection-topology.md:199`; `openspec/specs/fleet-ingress-interface/spec.md:177-180`).
The abbreviations and upstream citations are those of `brainstorm.md`: FM is the collector's `flake-module.nix`, HT the host table, HS `modules/lib/hosts.nix`, OE the envelope, FI the container test, OCC the collector check, ZI the ZeroTier inventory, K9 and K10 the Kubernetes ADR-009 and ADR-010.

The current state, from `brainstorm.md` "Grounding evidence":

- `otlp/mesh` listens on `[${flake.lib.hosts.magnetite.zt}]:4318` with mTLS against `otel-ca` at TLS 1.3 and feeds `metrics/ingress` and `logs/ingress`, which also receive magnetite's own agent through `forward` (FM:783-791, :815-825, :871-878).
- The pinned collector cannot see the client certificate (`confighttp@v0.155.0:server.go:142-150`; `client@v1.61.0:client.go:91-107`), and its filter answers 2xx for a dropped write (`filterprocessor@v0.155.0:logs.go:120-121`).
- caddy 2.11.7 can verify a client certificate, read its URI SAN, map it, refuse with 403 and overwrite a forwarded header; nginx on magnetite cannot read a SAN.
- At ZeroTier 1.16.0 neither the network nor `ipauth` ties an rfc4193 source address or neighbour-advertisement target to its sender (`ZT:node/Membership.hpp:118`, :180-222), and Linux lets an override NA rewrite magnetite's non-permanent neighbour entry (`net/ipv6/ndisc.c:1100-1108`).
- The Kubernetes plans keep nodes off ZeroTier and route a cluster's admin traffic through one WireGuard gateway (K9:144, :158-165), with disposable node identity (K10:54-59).

Constraints:

- The operator's principle of 2026-11-06: choose the architecturally durable option, without pedantry.
- The charter's R5 and A6: every new artifact names its envelope and its regulator (`docs/notes/development/observability/charter.md:99`, :159); C1 and A8: every layer names the failure it prevents (:129, :162).
- Each flake check stays within 536,870,912 B of evaluation, measured with `nix eval .#.checks.x86_64-linux.<check>.drvPath` cold (charter v19, :346-347); a relation within one host is that host's assertion, not a check clause (v19, :348).
- CAM-72's change (S5) is open and modifies the same `fleet-ingress-interface` requirements; CAM-74 must land after this change.
- magnetite has no `/dev/kvm` (A32), so runtime legs run as systemd-nspawn containers in `vmTests.x86_64-linux.fleet-ingress`.

## Goals / Non-Goals

**Goals:**

- A mesh write is accepted only from a certificate whose URI SAN names a collecting host, arriving from that host's ZeroTier address.
- A mesh write is stored only under the host that identity names, for metrics, deploy records and every later stream through `otlp/mesh`.
- A member with root cannot claim another member's address toward magnetite.
- Every write the binding refuses at HTTP or drops fails magnetite's `otel-envelope` within one run, and every new layer has an envelope and a regulator; a refusal during the TLS handshake and a connection from a spoofed address that never completes are not counted, so neither is detected.
- The identity holds on any future write path, so a non-ZeroTier path adds a listener, not a new identity scheme.

**Non-Goals:**

- Certificate lifetime, revocation and the lost-key runbook, which CAM-82 owns (O8).
- The Kubernetes write paths themselves; only the identity they will use is fixed here.
- A ZeroTier flow rule, and the source-address trust of mesh services other than the ingress, which a follow-up issue owns (O9).
- Unauthenticated loopback injection on an agent host, which A3:200 records and this change leaves as it is.
- CAM-74's content stages, which it adds to `metrics/mesh` and `logs/mesh` after the binding.

## Decisions

### Layout

| Path | Change |
|---|---|
| `modules/clan/services/otel-collector/flake-module.nix` | `otel-cert`'s SAN; the agent role's host-name assertion; the ingress role's caddy, socket receiver, mesh pipelines, binding filters and `09-zerotier` neighbours, all rendered from one list; `restartUnits` adds caddy on the ingress host; the pipeline-coverage, socket-group and caddy-version assertions |
| `modules/lib/hosts.nix` | every collecting host's `zt` address |
| `modules/clan/inventory/services/zerotier.nix` | the controller's external members keyed by name |
| `modules/lib/observability-hosts.nix` | `caddy` in magnetite's `notifiedUnits` |
| `modules/lib/zerotier-mac.nix` (new) | `flake.lib.zerotierMac`, the MAC of an rfc4193 address on its network |
| `modules/lib/otel-envelope.nix` | C6 and caddy's metrics target |
| `modules/machines/nixos/magnetite/default.nix` | caddy in the kill-order assertion |
| `modules/checks/otel-collector-config.nix` | the address cross-source clause; the endpoint clause naming caddy's listener |
| `modules/checks/mesh-binding.nix` (new) | the pinned collector run over magnetite's rendered binding filters |
| `modules/checks/otel-envelope.nix` and fixtures | C6 cases and mutants |
| `modules/vm-tests/otel-test-pki.nix` | one certificate per fixture identity, with URI SANs |
| `modules/vm-tests/fleet-ingress.nix` and `fleet-ingress/helpers.py` | caddy in the container, the binding legs, the neighbour leg |

### Data flow

```
agent host H (NixOS or darwin)                         magnetite
otel-cert: CN=H, URI:spiffe://vanixiets/host/H
resource/agent stamps host.name=H
otlp_http/ingress[-logs] --mTLS, from H's zt address--> caddy [zt]:4318  (TLS 1.3, require_and_verify otel-ca)
                                                          SAN -> (H, addr_H) by map; 403 unless peer == addr_H
                                                          header_up X-Vanixiets-Host: H
                                                        reverse_proxy unix//run/otelcol-mesh/otlp.sock
                                                          otlp/mesh (include_metadata)
                                                          metrics/mesh: memory_limiter -> filter/mesh-host-metrics -> forward
                                                          logs/mesh:    memory_limiter -> filter/mesh-host-logs    -> forward
                                            magnetite's agent pipelines -> forward
                                                          forward -> metrics/ingress, logs/ingress -> routing -> store
09-zerotier: permanent neighbour addr_H -> zerotierMac(addr_H) for every collecting H
otel-envelope C6: filter drops, caddy 403s, neighbour entries
```

### What each attacker can still do

| Attacker | Address binding alone | SAN alone | SAN with the address factor (recommended) |
|---|---|---|---|
| A copied `otel-key`, used from a phone or other member outside the table | dropped | writes as the key's host until `otel-ca` is rotated | 403 |
| A copied `otel-key`, used from another collecting host | writes as that other host only | writes as the key's host | 403 |
| A phone or other member without a key | refused at the handshake | refused at the handshake | refused at the handshake |
| Root on a collecting host | writes as any host whose neighbour entry it overwrites, unless D4 pins them | writes as its own host only, into the streams an agent writes (D5) | writes as its own host only, into the streams an agent writes (D5) |
| A stolen laptop, with its key and ZeroTier identity | writes as itself until deauthorized on cinnabar | writes as itself from any member until `otel-ca` is rotated | writes as itself until deauthorized on cinnabar |
| A writer on a non-ZeroTier path behind a shared address | not identifiable | identified by its SAN | identified by its SAN; the address factor is a property of the ZeroTier listener only |
| Root on magnetite | anything | anything | anything |

### D1: A writer's identity is its certificate's URI SAN, with its ZeroTier address as a second factor on the mesh (O1)

- **Choice**: caddy accepts a mesh write only when the client certificate verifies against `otel-ca`, its first URI SAN maps to a collecting host, and the connection's peer address is that host's ZeroTier address.
- **Rationale**: a source address cannot name a writer behind a shared gateway with a disposable node identity (K9:158-165; K10:54-59), so it fails the durability test as the identity; a SAN names a writer on any path.
  The address factor costs one map entry per host and makes a copied key useless on the mesh, because completing the handshake needs the node whose ZeroTier identity secret only that host's root reads; it also makes deauthorization on cinnabar the immediate cut-off for a lost laptop.
- **Alternatives considered**: address binding in the collector alone, which fails the durability test and depends entirely on D4; the SAN alone, which leaves a copied key usable from any member for the certificate's 10 years; one receiver and CA per host, which multiplies ports, CAs and firewall openings and still needs a reissue.
  nginx 1.30.6, which already fronts magnetite's public sites, was rejected in both of its forms (O1): it exposes no SAN variable (`ngx_http_ssl_module.c:394-435`); pinning each host's `$ssl_client_fingerprint` ties identity to one certificate, so every reissue, and the short-lived issuance CAM-82 may adopt, would need a configuration change and a deploy; and matching the CN through a `map` over `$ssl_client_s_dn` relies on a field RFC 6125 retires for identity and that a SPIFFE certificate does not carry.
- **Boundary**: vendored-versus-first-party. The SAN check, the map and the 403 are caddy's vendored behaviour (A75), configured first-party from one Nix table.

### D2: The SAN and the vars step (O2)

- **Choice**: `otel-cert`'s extension file always writes `subjectAltName=URI:spiffe://vanixiets/host/${machine.name}`, followed on the ingress host by the existing `IP:` and `DNS:` SANs; the CN stays.
  `validation.subjectAltNames` carries the full string, so clan regenerates every collecting host's `otel-cert`.
- **Vars step**: record the sha256 of `vars/shared/otel-ca/ca.crt/value` and of the decrypted `ntfy-alerter` token; run `CLAN_NO_COMMIT=1 clan vars generate <machine> --generator otel-cert` for magnetite, cinnabar, pyrite, electrum, galena, scheelite and stibnite; compare both hashes; read each `cert.pem` with `openssl x509 -ext subjectAltName`; commit the regenerated files in pull request 1.
  `otel-ca` is a shared generator whose definition does not change, so it is never passed to `--regenerate`, and clan's comparison of shared definitions across machines (FM:937-940) still agrees.
- **Rationale**: a URI is an identity rather than a resolvable name, and the trust domain names the repository rather than the transport, so a later cluster writer can carry `spiffe://vanixiets/cluster/<name>`.
- **Alternatives considered**: a DNS SAN such as `cinnabar.otel.vanixiets`, which caddy reads equally but which TLS libraries would also treat as a host name; a `.zt` trust domain, which ties identity to the transport D1 is chosen to outlive.
- **Boundary**: source-versus-delivered. The certificate is generated by clan at vars time and delivered as a secret; darwin reads the same generator definition and reloads on a reissue through its plist hash (S5 design D5).

### D3: caddy in front of a socket receiver

- **Choice**: nixpkgs' `services.caddy` on magnetite with `enableReload = false`, and a rendered Caddyfile:
  - global: `auto_https off`, `admin off`, `metrics`;
  - one site listening on each address of `vanixiets.otelCollector.meshListen`, by default only `https://[${flake.lib.hosts.magnetite.zt}]:4318`, with magnetite's `otel-cert` and `otel-key` loaded through `LoadCredential`, `protocols tls1.3`, `client_auth { mode require_and_verify; trust_pool file <otel-ca> }`;
  - `map {http.request.tls.client.san.uris.0} {mesh_host} {mesh_addr}` with one line per collecting host other than magnetite and no `default`, so an unmapped SAN yields empty values;
  - `@refused not vars {http.request.remote.host} {mesh_addr}` and `respond @refused 403`, which refuses an unmapped SAN because a peer address is never empty (`modules/caddyhttp/map/map.go:166-169`; `replacer.go:159-173`);
  - `reverse_proxy unix//run/otelcol-mesh/otlp.sock` with `header_up X-Vanixiets-Host {mesh_host}`;
  - a second site, `http://127.0.0.1:2019` with `bind 127.0.0.1`, holding only the `metrics` handler (`caddy@v2.11.7:modules/metrics/metrics.go:31-33`), so C2's probe and C6's scrape keep their address and no handler on that site can change configuration.
- **No admin endpoint**: `admin off` leaves caddy with no API through which a local account could load a configuration that removes the 403 or sets `X-Vanixiets-Host` to another host; nixpkgs' `reload` path needs the admin API (`nixos/modules/services/web-servers/caddy/default.nix:326-339`, `:462-483` at the root pin), so `enableReload = false`.
  The trade-off is that every Caddyfile change restarts caddy instead of reloading it; a restart refuses mesh connections until caddy has started again, a duration not yet measured, and the agents retry from their file-backed queues, as on the certificate `restartUnits` restart this design already accepts.
- The collector's `otlp/mesh` takes `transport: unix`, `endpoint: /run/otelcol-mesh/otlp.sock`, no TLS, and `include_metadata: true`.
  `systemd.tmpfiles` creates `/run/otelcol-mesh` owned by `root:otelcol-mesh` with mode 2770; `otelcol-mesh` is a static group whose only other member is caddy; the collector, which runs with `DynamicUser`, gets `SupplementaryGroups = [ "otelcol-mesh" ]`, `ReadWritePaths` on the directory and `UMask = 0007`, so the socket is group-writable and no other account can connect.
  Neither this form's nor the fallback's interaction with `DynamicUser` has been run, so the socket case of the vendored probe (tasks.md 1.5) and the container test's socket-access case decide it before the configuration is written; the fallback is a static `Group = "otelcol-mesh"` on the collector beside `DynamicUser`.
- **Envelope**: caddy runs with `MemoryMax = 128M` (revised from the deploy measurement), `OOMScoreAdjust = 700`, between the evaluator's 900 and Perses' 600, because it holds no state and the agents retry while it is down; it is a notified unit of magnetite; magnetite's kill-order assertion adds it.
- **Regulator**: C2 of magnetite's `otel-envelope` probes `http://127.0.0.1:2019/metrics`; C6 reads its 403 count (D6); FI's legs exercise it, among them a `POST /load` to `127.0.0.1:2019` after which the mesh site's 403 and header behaviour are unchanged; the map, the filters and the neighbours are rendered from one list (D7); an ingress-role assertion `config.services.caddy.package.version == "2.11.7"` fails evaluation when caddy moves, with a message requiring `fleet-ingress` to be rerun and A75 updated (D9).
- **Failure prevented**: a write whose identity or address does not match is refused where the sender can see it (C3 in `brainstorm.md`), no local process but caddy can post a forged identity header (C4), and no local process can rewrite caddy's configuration, because caddy has no admin endpoint.
- **Alternatives considered**: a loopback TCP receiver with a bearer token only caddy holds, which adds a secret where file permissions suffice; nginx, which cannot read a SAN; the collector reading `otelcol.client.addr` itself, which sees only the socket once caddy fronts it.
  The admin API on `admin unix//run/caddy/admin.sock|0200`, which caddy creates owned by its own account with mode 0200 (`internal/sockets.go:34-55`), with `RuntimeDirectory = "caddy"`, keeps reloads: only caddy's account and root reach it, and `caddy reload` from `ExecReload` runs as that account; it costs a socket path and its mode as one more property to judge, for zero-downtime reloads that a configuration changed only by deploys does not need.
  The admin API on `127.0.0.1:2019`, the first draft, lets any local account `POST /load` a configuration, and magnetite runs pull-request builds through its buildbot worker and nixbot.
- **Boundary**: vendored-versus-first-party. Header replacement, status pass-through and the 403 count are caddy's (A75); 503 back-pressure still originates in the collector's limiter and passes through unchanged.

### D4: Permanent neighbour entries close the spoofing gap (O4)

- **Choice**: the ingress role sets `systemd.network.networks."09-zerotier".neighbors` on magnetite to one `{ Address; LinkLayerAddress; }` per collecting host, the address from HS and the MAC from `flake.lib.zerotierMac`, which implements `MAC::fromAddress` on the node id embedded in the rfc4193 address and the network id (`ZT:node/MAC.hpp:163-196`; `node/InetAddress.cpp:490-513`), the network id read from `vars/shared/zerotier-network-zerotier/network-id/value`.
  The entries are rendered only while `vanixiets.otelCollector.meshPinNeighbours` is true, its default; the container test sets it false, because its loopback identities are not rfc4193 addresses on a ZeroTier link (D10).
- **Rationale**: a permanent entry resists every NA (`net/core/neighbour.c:1351-1353`), and a frame to the derived MAC reaches only the node that owns it, so a SYN forged from another host's address is answered to that host and the handshake never completes.
  The entries need no new data and hold against root on any member, cinnabar's included.
- **Alternatives considered**: `drop not chr ipauth` on cinnabar's controller, which at 1.16.0 admits any rfc4193 address in the /88 from any member and drops all link-local traffic (C1 in `brainstorm.md`); per-host `ipsrc`/`ztsrc` rules, which match no NA target; `drop_unsolicited_na`, which an attacker defeats by setting the solicited flag (`ndisc.c:1019-1021`); relying on the SAN alone, which leaves D1's address factor resting on a forgeable address.
- **Regulator**: C6 reads `ip -j -6 neigh show` and fails when any collecting host's address on `zt*` is missing, not `PERMANENT`, or names another MAC; FI's neighbour leg (D10); the live acceptance (O10).
- **Derivation, checked against the live table**: on 2026-11-06 magnetite's neighbour table held stibnite, cinnabar, pyrite and the phone `pixel11`, and its own link `zt554fbdjy` carried `02:b6:2d:e0:74:96`; `MAC::fromAddress` for each of the five addresses on network `db4344343b14b903` gave exactly the MAC recorded (`02:9d:0d:e2:00:15`, `02:62:57:7f:00:7f`, `02:c7:94:5c:b4:6c`, `02:85:9d:a2:af:fc`, `02:b6:2d:e0:74:96`).
  These pairs become the MAC clause's fixture in `checks.x86_64-linux.otel-collector-config`; electrum, galena and scheelite were not provisioned and are judged only by the function the fixture holds.
- **Pre-deploy gate, mandatory (O4)**: a wrong entry cuts magnetite off from that host over ZeroTier entirely, SSH, builds and telemetry included, and stibnite is the deploy source.
  Immediately before the deploy that installs or changes the entries, the operator reads magnetite's live table and every present collecting host's entry must equal its computed MAC; the deploy does not run otherwise.
- **Rollback**: magnetite's public SSH on port 22 (`networking.firewall.allowedTCPPorts`; `magnetite.scientistexperience.net`, A record 49.12.12.74) does not cross ZeroTier; a session over it is opened before the deploy and kept open, and a wrong entry is removed with `ip -6 neigh del <address> dev <zt link>`, after which ZeroTier's emulation answers the next solicitation correctly.
  networkd may reinstall an entry it manages on the next link event `[INFERENCE]`, so the first rollback does not wait for the merge queue: magnetite is deployed from `$DEPLOY` detached at the merge-base before pull request 2, with `clan machines update magnetite --target-host root@magnetite.scientistexperience.net`, a named exception in plan Global Constraints to the deploy-from-`origin/main` rule; the revert then lands through the queue and is deployed normally, and the entries are read absent after the rollback deploy.
- **Boundary**: vendored-versus-first-party. networkd installs the entry and the kernel enforces it (A73); whether a zerotierone restart, which recreates its link, leaves the entries installed is observed in an operator-present step after the deploy, and C6 reads the live table on every run rather than the configuration, so a lost entry fails within one period.
  No step before the deploy exercises networkd's `[Neighbor]` installation on the ZeroTier link: the container's neighbour leg installs its entries with `ip -6 neigh replace`, so only C6 and the operator-present restart (tasks.md 6.1) judge the installed path.

### D5: Drop a mismatched host, and count it (O3)

- **Choice**: `filter/mesh-host-metrics` and `filter/mesh-host-logs`, each after `memory_limiter`, drop:
  - a resource whose `X-Vanixiets-Host` header names no collecting host, or whose `host.name` differs from it, one condition per collecting host generated from the table;
  - a resource whose `vanixiets.database` and `vanixiets.table` attributes, which choose the destination database and devloop table (FM:793-797, :850-854), are not a pair an agent sets for that signal: `fleet` for metrics, `devloop` with `deploy_record` for logs; the allow-list is rendered from the values the agent role's `resource/agent` and `resource/devloop-deploy_record` processors stamp (FM:299-308, :546-556), not written as literals, so a new honest stream extends it with its agent;
  - a log record whose `host` attribute is present and differs from the header;
  - a data point or log record carrying its own `host.name` or `host_name` attribute.
- **Rationale**: an honest agent stamps `host.name` from `config.networking.hostName` (FM:150, :301-302), and deploy records use it too (`modules/system/deploy-record.nix:103-106`, :120-123), while its SAN carries `machine.name`; an agent-role assertion on nixos and darwin holds `networking.hostName == machine.name`, with an `extendModules` override that fails it, so a mismatch from an honest agent is a configuration fault caught at evaluation, and overwriting would hide it; overwriting a forgery would store attacker-chosen series and deploy records under the sender's name without a trace.
  The allow-list closes the path by which a certificate holder on a collecting host would write `ci_build`, `batch_event` or `ci_attribute` rows or `devloop` metrics, none of which carry a host column.
  The point- and record-level rule closes a second path: a point attribute named like the promoted column could collide with `host_name` in the store.
  How the store resolves that collision does not matter once such points are dropped; what matters is that the rule drops nothing honest, and on 2026-11-06 no line of any Prometheus target the agents scrape on cinnabar (`node`, `otelcol`, `zerotierone`), pyrite (`node`, `otelcol`, `smartctl`, `zerotierone`) or stibnite (`node`, `otelcol`) carried a `host_name` or `host.name` label; the host-metrics and systemd receivers emit fixed attribute sets, and the agents stamp `host.name` on the resource only.
  The survey is repeated as a gate before pull request 2, and the container test's point-attribute case holds the drop.
- **Alternatives considered**: a `transform` that overwrites `host.name` and the record's `host` from the header, which keeps an honest sender's data during a misconfiguration but makes forgery invisible; dropping in caddy, which cannot read the OTLP body.
- **The header's OTTL form, read from source**: the receiver stores metadata keys lower-cased and `Get` lower-cases the key it is asked for (`client@v1.61.0:client.go:146-175`); `otelcol.client.metadata["x-vanixiets-host"]` returns the values as a slice, and one index returns the string (`pkg/ottl@v0.155.0:contexts/internal/ctxotelcol/client.go:194-215`; `otelcol.go:44-61`); an absent header returns nil before indexing, so `otelcol.client.metadata["x-vanixiets-host"][0] != "<host>"` is true for it and the resource is dropped.
  caddy's `header_up` sets one value, so index 0 is the only value.
- **Boundary**: vendored-versus-first-party. The exact filter configuration is still probed against the vendored 0.155.0 binary before pull request 2 with the consumer's exact arguments (schema `plan` rule from #3690), because the source reading does not exercise `metric_conditions`' context inference.

### D6: Refusals the sender sees, drops only magnetite sees, and C6 (O5)

- **Choice**: caddy answers 403 for an unmapped SAN or a wrong peer address; the sender's exporter treats 403 as permanent, drops the request and counts `otelcol_exporter_send_failed_*`, which its own C4 reports.
  magnetite's `otel-envelope` gains C6, judged on every run on the ingress host only, failing when since the previous run:
  - `otelcol_processor_filter_datapoints_filtered` or `otelcol_processor_filter_logs_filtered` rose for `filter="filter/mesh-host-metrics"` or `filter="filter/mesh-host-logs"`;
  - `caddy_http_request_duration_seconds_count{code="403"}` rose on the mesh server;
  - a collecting host's neighbour entry is missing, not permanent, or names another MAC;
  - a liveness series that a previous run recorded is absent: `otelcol_processor_incoming_items{processor="filter/mesh-host-metrics"}` and `{processor="filter/mesh-host-logs"}`, and caddy's request count for server `mesh`, so a renamed series or a wrong fixture name fails C6 instead of reading zero for ever.
  A drop or refusal counter that is absent reads 0, a counter below its recorded value counts its current value, and a run with no recorded state only records, as C4 does; the series names are read from the vendored probe's scrape (tasks.md 1.5) before C6's fixtures are written.
- **Rationale**: a dropped write still answers 200, so the counter is the only evidence of it, and a forging sender does not report its own refusals, so the ingress counts them too.
- **Alternatives considered**: a retryable 503 for a refusal, which would keep a misconfigured honest host's data queued for up to 24 h before its C3 fails but would also tell a forger to retry; alerting through the store, which waits for the export path the envelope exists to watch.
- **Regulator**: `checks.x86_64-linux.otel-envelope` with mutants that ignore each C6 input, the liveness rule among them, each run only against the case it must fail; FI's legs on the real collector and caddy.

### D7: One source of mesh addresses

- **Choice**: HS gains a `zt` address for every host in HT; an OCC clause compares each with `vars/shared/zerotier-ip-<host>-zerotier/ip/value` for the clan peers and with ZI's `externalMembers.<host>` for stibnite, and requires each address to lie in the /88 formed from `vars/shared/zerotier-network-zerotier/network-id/value`, to be lower case, and to equal its own canonical RFC 5952 rendering, which `{http.request.remote.host}` produces `[INFERENCE: Go's IP.String form]`.
  ZI's external members become an attribute set keyed by name, `externalMembers = { stibnite = "…"; … }` with `allowedIps = attrValues externalMembers`, so the clause compares stibnite by name rather than by membership in a list whose host names are comments.
  The caddy map, the filter's conditions and the neighbour entries are rendered from one `let`-bound list taken from `vanixiets.otelCollector.meshIdentities` (host to address), an internal option defaulting to HT's collecting hosts joined with HS and set otherwise only in the container test; no assertion compares the three renderings, because they share one expression, and `mesh-binding` (D11) and FI's binding legs judge what the rendering produces.
- **Rationale**: HS already claims to be the canonical registry (HS:1-4) while holding one host; the clan peers' addresses live in vars and stibnite's in a comment (C5 in `brainstorm.md`).
  Two independent sources compared at evaluation catch a mistyped address before it becomes a 403.
- **Mutants**: pyrite's HS address off by one digit; stibnite's HS address differing from `externalMembers.stibnite` while still listed in `allowedIps`; each shown failing.
- **Boundary**: source-versus-delivered. HT and HS are read from magnetite's own closure, so a change to either takes effect only when magnetite deploys (Migration Plan).

### D8: Every pipeline that accepts mesh writes is bound

- **Choice**: a magnetite assertion requires that `otlp/mesh` appears only in pipelines whose processors begin with `memory_limiter` and the binding filter for that signal, and that `metrics/ingress` and `logs/ingress` receive only `forward`; that no collector endpoint is off loopback, and that no traces pipeline exists, are OCC R3.1's clauses.
  Mutants by `extendModules`: `otlp/mesh` added to `metrics/ingress`; `logs/mesh` without its filter.
- **Rationale**: CAM-74's journald and omp streams, and any later signal, then either inherit the binding or fail evaluation; CAM-74 adds its content stages after the binding in the same pipelines, because a certificate holder posting directly skips the agent's (RA:130-132).

### D9: World assumptions

Each new assumption carries the trigger "the vendored version moves" where it names one (#3690).
A75 is guarded by the ingress-role assertion `config.services.caddy.package.version == "2.11.7"`, following `modules/checks/pyrite-desktop.nix:222`, whose message requires `fleet-ingress` to be rerun and A75 updated; A76 has no tripwire, because `mesh-binding` (D11) re-judges the collector's filter on every bump of the pin.

| Number | Assumption | Evidence | Violation |
|---|---|---|---|
| A71 | ZeroTier delivers a frame for a member's MAC only to that member, whose MAC derives from its node id and the network id | `ZT:node/MAC.hpp:163-196`; `node/IncomingPacket.cpp:842`, :963-971 | a ZeroTier version or bridging setting lets a node receive another node's unicast frames |
| A72 | ZeroTier neither inspects an inbound NA nor ties an rfc4193 source or NA target to its sender | `node/Network.cpp:408-462`; `node/Membership.hpp:118`, :180-222 | a version authenticates rfc4193 sources, which would make D4 redundant but not wrong |
| A73 | Linux never changes a permanent neighbour entry on an NA and lets an override NA rewrite a non-permanent one | `net/core/neighbour.c:1351-1353`, :1414-1427; `net/ipv6/ndisc.c:1100-1108` | a kernel version updates permanent entries from NAs |
| A74 | the fleet network assigns rfc4193 addresses with NDP emulation and carries only the accept-all rule | `clan-core@dbae2101:clanServices/zerotier/default.nix:292-307`; `ZT:nonfree/controller/EmbeddedNetworkController.cpp:2050-2054` | the network gains a flow rule, another assignment mode or a managed route |
| A75 | caddy exposes a verified client certificate's URI SANs, replaces a `header_up` header, passes an upstream status through, and counts a `respond` status | `caddy@v2.11.7:modules/caddyhttp/replacer.go:514-545`; `headers/headers.go:258-275`; `reverseproxy/reverseproxy.go:1313`, :1326; `caddyhttp/metrics.go:346-385` | a caddy version changes any of these |
| A76 | the collector's filter answers 2xx for a dropped write and counts it per processor id | `filterprocessor@v0.155.0:logs.go:120-121`; `telemetry.go:45` | a collector version rejects dropped data or renames the counter |

The designation table's `overlay network` row (`openspec/specs/world-assumptions/spec.md:199`) adds that the network carries a member's packets without proving which member sent them from which address; `overlay member` and `overlay address` are added, because the behavioral requirements of `host-metrics-collection` and `devloop-collection` use them.
A71's evidence includes the five MAC pairs read from magnetite's live table on 2026-11-06 (D4).

### D10: Tests

- **Choice**: `vmTests.x86_64-linux.fleet-ingress` runs caddy in the `store` container in front of the socket receiver, with `vanixiets.otelCollector.meshListen` set to `127.0.0.1:4318` and `[::1]:4318`, `vanixiets.otelCollector.meshPinNeighbours` set false, and `vanixiets.otelCollector.meshIdentities` set to electrum at `127.0.0.1`, `budgethost` at `127.0.0.2`, `cinnabar` at `127.0.0.3` and one IPv6 identity at `::1`; `flake.lib.otelTestPki` issues one certificate per identity with its URI SAN, and one without a SAN.
  Each budget fixture writes with its own certificate through `curl --interface <address>`.
- **New legs**, each reading C6 afterwards:
  - a matching write is stored;
  - a write whose `host.name` differs from its certificate is not stored, and C6 fails on the filter;
  - a deploy record whose `host` differs is not stored, and C6 fails on the filter;
  - a write from an unlisted address, a certificate without a mapped SAN, and a valid certificate from another identity's address each get 403, and C6 fails on caddy;
  - a client-sent `X-Vanixiets-Host: cinnabar` with electrum's certificate is stored only under electrum;
  - a local account outside `otelcol-mesh` cannot connect to the socket;
  - a point carrying its own `host_name` attribute is not stored;
  - a log record from electrum's address with electrum's certificate whose resource sets `vanixiets.database` to `devloop` and `vanixiets.table` to `ci_build` is not stored, and C6 fails on the filter;
  - a `POST /load` to `127.0.0.1:2019` carrying a configuration without the 403 and with a fixed `X-Vanixiets-Host` leaves the mesh site's 403 for an unlisted address and its header replacement unchanged.
- **Neighbour leg**: an `attacker` network namespace joined to a namespace holding the store side's address by a veth pair inside the `store` container, which needs no second container; whether two `runNixOSTest` containers share a link is not relied on.
  The store side carries permanent entries rendered by the same function as magnetite's `09-zerotier` neighbours; the attacker, as root in its namespace, adds the victim's address with `nodad`, sends an unsolicited NA with the override and solicited flags for it, and connects from it with the victim's test certificate.
  The entry stays permanent with the victim's MAC, the connection does not complete, and C6 passes; a mutant store without the entries first pings the victim, so the store holds a `REACHABLE` entry that the override advertisement rewrites, and then accepts the write under the victim, showing the entries are load-bearing; the first run of the case, made before the entries exist, also shows whether `ip netns` works inside the container.
- **Live acceptance** (O10): only after the entries are deployed and verified, and with the operator present, root on pyrite adds stibnite's overlay address, advertises it with the override flag and opens a TCP connection to magnetite's mesh site from it, with no certificate and no key copied; magnetite's entry for stibnite stays permanent and the connection never completes.
  A baseline against a phone's unpinned address shows the overwrite A72 and A73 predict; the overwritten entry is deleted at once, and magnetite's neighbour table is read before and after each.
- **Boundary**: the container's loopback and test network stand in for ZeroTier, as FI's header records (FI:20-23); A71 and A72 are discharged only by the live acceptance.
  The neighbour leg installs its entries with `ip -6 neigh replace`, so networkd's `[Neighbor]` installation on the ZeroTier link is judged only by C6 and the operator-present zerotierone restart (tasks.md 6.1), which stays the step that observes it.

### D11: Checks and evaluation cost

- **Choice**: OCC gains the address cross-source clause (mutants `addressDigitChanged`, `externalAddressDiffers`), the MAC clause over the five pairs of D4 (mutant `macBytesReversed`), and its endpoint clause now requires the collector to have no endpoint off loopback and caddy's site address to equal the address in `vars/shared/zerotier-ip-magnetite-zerotier/ip/value`; `checks.x86_64-linux.otel-envelope` gains C6's cases.
  A new gating check, `checks.x86_64-linux.mesh-binding`, runs only the pinned `otelcol-contrib` in the build sandbox over the filter text magnetite's ingress role renders, posting the vendored probe's cases (tasks.md 1.5) through a Unix socket, so the rendered conditions are judged on every change and every bump of the pin; caddy stays in the `fleet-ingress` container, and the check is kept apart from `otel-collector-config` so its cost is measured on its own; the probe is its first run.
  Relations within one host, pipeline coverage, socket group membership, the caddy version and the kill order on magnetite and `networking.hostName == machine.name` on every agent host, are assertions, which each host's toplevel evaluation already pays for (charter v19).
  The socket-group assertion scans every `systemd.services.*.serviceConfig.Group` and `SupplementaryGroups` and every `users.users.*.extraGroups` for `otelcol-mesh` and requires exactly the collector and caddy, because a group's `members` line misses a `DynamicUser` unit and every other way in.
- Each check this change adds or changes is measured with `nix eval .#.checks.x86_64-linux.<check>.drvPath`, cold and with the evaluation cache off, before and after, and must stay below 536,870,912 B.
  The machine checks, `nixos-magnetite` among them, evaluate a whole machine above that budget (2,866,533,808 B at `1bdc59782d29`), so their cost is recorded before and after with the same method and any rise is put to the operator.

### Spec deltas and decision records

- `fleet-ingress-interface`: the modified and added requirements listed in `proposal.md`, layered on S5's deltas to the same requirements and rebased onto the archived corpus before pull request 1 (O6); the Purpose paragraph's trust boundary is rewritten at archive to match the trust-boundary requirement.
- `telemetry-store-interface` and `devloop-collection-interface`: their trust-boundary requirements as `proposal.md` lists.
- `host-metrics-collection` and `devloop-collection`: one behavioral requirement each (O7), discharged by the new `fleet-ingress-interface` requirements under A71 to A76.
- Amended under charter v30: ADR-003's Consequences (:199-201), its R3.1 endpoint clause, its envelope and Implementation surface; the reference architecture (:102); `components/otel-collector.md`; the collector README; the runbook's lost-machine section, whose first step becomes deauthorizing the member on cinnabar.

## Risks / Trade-offs

- [Risk] A wrong computed MAC in a pinned entry cuts magnetite off from that host over ZeroTier entirely, SSH, builds and telemetry included, and stibnite is the deploy source. → Mitigation: the MAC clause's fixture of five pairs read from magnetite's live table on 2026-11-06, all equal (D4); the mandatory pre-deploy gate reading the live table again; a public-SSH session opened before the deploy, through which a wrong entry is deleted and the pre-binding commit deployed directly (D4 "Rollback").
- [Risk] A collecting host absent while pull request 1 deploys comes back holding its old certificate; caddy answers it 403, which its exporter treats as permanent, so it drops up to 24 h of queued data. → Mitigation: before the binding deploys, every collecting row of `flake.lib.observabilityHosts` is either seen holding its reissued certificate or carries an operator decision accepting the loss of its queued backlog (tasks.md 3.4, 5.1).
- [Risk] A handshake refused for a missing or foreign certificate, and a copied key used from a spoofed pinned address, which never completes TCP, reach neither caddy's 403 count nor C6, so neither is detected. → Accepted: the handshake refusal and the pinned entry still stop the write; the trust boundary of `fleet-ingress-interface` states it.
- [Risk] A zerotierone restart recreates its link and networkd does not reinstall the entries, reopening the gap silently. → Mitigation: C6 reads the live table on every run and fails on a missing entry; an operator-present restart over the public SSH path after the deploy observes it once, and a finding there is decided before acceptance continues.
- [Risk] The filter's context inference treats the conditions differently from the source reading, and the filter drops every write or none. → Mitigation: the header's form is read from source (D5); the exact configuration is probed against the vendored binary before pull request 2, and FI's matching and mismatching cases fail on either error.
- [Risk] An honest host's points carry a host attribute and the point rule drops them. → Mitigation: the 2026-11-06 survey found none (D5); it is repeated as a gate before pull request 2, and C6 fails within one run of any drop after the deploy.
- [Risk] A wrong address in HS turns an honest host's writes into 403s, which its exporter drops as permanent. → Mitigation: D7's two-source comparison at evaluation; the gate that every present host runs its reissued certificate before pull request 2 merges; C6 fails within one run of the first 403.
- [Risk] caddy becomes a single process on every ingest path. → Mitigation: the agents queue for 24 h; C2 and caddy's failure notice report a stopped caddy within 10 min; its kill-order place keeps the store and collector alive under memory pressure.
- [Trade-off] Every collecting host's certificate is reissued and four deploys are coordinated once. → Accepted: it buys an identity every later path reuses.
- [Trade-off] caddy runs with no admin endpoint, so every Caddyfile change restarts it instead of reloading it, refusing mesh connections for a duration not yet measured. → Accepted: the configuration changes only by deploys, and the agents retry from their file-backed queues (D3).
- [Trade-off] caddy adds up to 128 MiB on magnetite, whose memory is shared with evaluation (A31). → Accepted, with the bound revisited from the first day's peak.
- [Trade-off] A stolen laptop writes as itself until deauthorized, and certificates still last 10 years. → Accepted here; CAM-82 owns lifetime and revocation (O8).

## Migration Plan

Implementation starts only after `stand-up-darwin-collection` (CAM-72) has archived, with this change's MODIFIED requirements rebased onto the archived corpus and `openspec validate bind-mesh-writes-to-their-host --strict` passing (O6); the change lands before CAM-74, as three pull requests:

| Pull request | Contains | Deploy |
|---|---|---|
| 1 | the SAN and the vars step; the agent-role host-name assertion; HS's addresses; ZI's external members keyed by name; `flake.lib.zerotierMac`; OCC's address and MAC clauses | magnetite, cinnabar, pyrite, then stibnite by `just activate` **[operator]**; electrum, galena and scheelite take theirs when next provisioned |
| 2 | caddy, the socket receiver, the mesh pipelines and filters, the neighbour entries, C6, `mesh-binding`, caddy in magnetite's `notifiedUnits` and kill order, `flake.lib.otelTestPki`'s identities, FI's cases | magnetite, after the MAC gate |
| 3 | the documentation, the decision-record amendments and the charter v30 entry | none |

1. Before pull request 1, the plan review, the baselines and the rehearsal of every verification block run, the public-SSH rollback path among them.
2. The vars step of D2 runs with `CLAN_NO_COMMIT=1` on every clan vars command, its hashes recorded before and after, in the commit that changes the SAN.
3. magnetite deploys pull request 1 first, because its own server certificate is reissued and HS is in its closure; cinnabar and pyrite follow, then stibnite with the operator present; each agent's `otel-envelope` passes after its restart, and every alert and notice posted since each deploy started is read from magnetite's evaluator and notifier journals and stibnite's wrapper log and recorded with its cause.
4. Gate: every collecting row of `flake.lib.observabilityHosts` either is seen holding its reissued certificate, read on the host, or carries an operator decision, recorded before the binding deploys, accepting the loss of its queued backlog.
5. Gates before pull request 2: the vendored probe passes; the honest-attribute survey finds no host attribute on any present host's points; every collecting host passes gate 4 again; the MAC gate finds every present host's entry equal to its computed MAC.
6. Pull request 2 merges and magnetite deploys with the public-SSH session open; the pinned entries read `PERMANENT` with their computed MACs, magnetite reaches each present host over ZeroTier, the agents' queues drain to 0, C6 passes, every host's series keep arriving under its own name, and the posts since the deploy are recorded.
7. With the operator present: the zerotierone restart over the public SSH path, then the spoofing acceptance from pyrite, then the forced mismatch and the 403 control.
8. Close-out: no migration flag is added; the pre-deploy gates are the only one-shot steps, and none remains in configuration.

Rollback: a wrong pinned entry is deleted over the public SSH path at once (D4); magnetite is then deployed over the public path from `$DEPLOY` detached at the merge-base before pull request 2, which restores `otlp/mesh` on the ZeroTier address and removes caddy and the entries, and the entries are read absent afterwards; the revert of pull request 2 then lands through the merge queue and is deployed normally; the reissued certificates stay valid and their SANs are harmless without caddy.

## Open Questions

The operator answered Q1 to Q11 on 2026-11-06, each as recommended; question `Q<n>` is decision `O<n>`, with the operator's additions recorded here and in `brainstorm.md`.

1. O1, identity: the URI SAN verified by caddy, with the source address as a second factor on the mesh; the nginx variants are rejected for the reasons in D1's alternatives, the fingerprint form because it pins one certificate against the short-lived issuance CAM-82 may adopt.
2. O2, the SAN: `URI:spiffe://vanixiets/host/<machine>`.
3. O3, a mismatched host: drop, count, and fail C6.
4. O4, the spoofing gap: permanent neighbour entries on magnetite, with the computed MAC compared against magnetite's live table as a mandatory pre-deploy gate and a rollback step (D4).
5. O5, caddy's refusal: 403.
6. O6, sequencing: the specs, tasks and plan are written now; implementation starts only after `stand-up-darwin-collection` archives, a gate task.
7. O7, behavioral requirements: added to `host-metrics-collection` and `devloop-collection`.
8. O8, scope: certificate lifetime and revocation stay in CAM-82.
9. O9, other mesh services: a follow-up issue, drafted by the orchestrator, lists the other mesh services that trust a source address; Q9's recommended reason was wrong in one respect, because ntfy on cinnabar keys each publisher's rate limit by its full source address, so a member claiming magnetite's or cinnabar's address can spend their budget.
10. O10, live acceptance: run from pyrite as root with the operator present, only after the entries are deployed and verified.
11. O11, Linear: the operator binds CAM-81 and corrects its text.

No question remains open.
