## MODIFIED Requirements

### Requirement: One host table declares the agent hosts and what each reports

`flake.lib.observabilityHosts` SHALL map each agent host to its `platform`, `collect`, `alwaysOn`, `notifiedUnits` and `smartDevices`, `flake.lib.hosts` SHALL give each agent host's overlay address as its `zt` attribute, and the collector's `agent` role machines and whether each collects, each host's notified units, the evaluator's always-on hosts, expected hosts by platform and `SystemdUnitFailed` exclusion, and the devices whose disk health is read SHALL be read from it.
Each row's `platform`, `nixos` or `darwin`, SHALL equal the `machineClass` that `modules/clan/inventory/machines.nix` gives the same machine.
Each agent host's `zt` address SHALL equal its second source, `vars/shared/zerotier-ip-<host>-zerotier/ip/value` for a clan ZeroTier peer and the controller's `externalMembers` entry of the same name for an external member, SHALL lie in the rfc4193 /88 formed from the network id in `vars/shared/zerotier-network-zerotier/network-id/value`, and SHALL be lower case and equal to its own canonical RFC 5952 rendering; the ingress's identity map, its binding filters and its pinned neighbour entries SHALL be rendered from these two tables.

**Discharged by**: the agent role's per-host assertions with their `extendModules` overrides; `checks.x86_64-linux.otel-collector-config`'s address clause with its mutants `addressDigitChanged` and `externalAddressDiffers`; the `otel-collector` inventory instance's platform assertion with its scratch-edit control; `checks.x86_64-linux.fleet-alert`'s exclusion, absence and platform legs.

#### Scenario: The table is evaluated

- **WHEN** `flake.lib.observabilityHosts` is evaluated
- **THEN** it names magnetite, cinnabar, pyrite, electrum, galena, scheelite and stibnite, every host with `collect = true` once its first watched deploy has happened, only magnetite and cinnabar with `alwaysOn = true`, only stibnite with `platform = "darwin"` and every other host with `platform = "nixos"`, only pyrite with `smartDevices = [ "/dev/nvme0" ]` and stibnite with `smartDevices = [ "disk0" ]`, every NixOS host with `opentelemetry-collector` and `otel-envelope` among its `notifiedUnits`, cinnabar also with `fleet-deadman` and magnetite also with its store, dev-loop, evaluator and dataset units, and stibnite with `notifiedUnits = [ "otel-envelope" ]`, the one darwin job that posts its own notices

#### Scenario: A host does not collect yet

- **WHEN** a host's `collect` is false
- **THEN** its configuration carries none of the agent role's units, launchd jobs, collector settings or `zerotierone` change, and no alert rule expects it or counts it as always-on, while a darwin host's `otel-cert` key and `ntfy-alerter` token are already installed owned by `_otelcol`

#### Scenario: A notified unit is not a unit of its host

- **WHEN** a NixOS host's `notifiedUnits` names a unit for which the host defines no service with an `ExecStart`, or omits `opentelemetry-collector` or `otel-envelope`
- **THEN** that host's evaluation fails on the agent role's assertion, as an override of cinnabar's configuration that notifies `zfs-set-root-typo-quota` shows

#### Scenario: A row's platform disagrees with the inventory

- **WHEN** a row's `platform` differs from its machine's `machineClass` in `modules/clan/inventory/machines.nix`
- **THEN** evaluation fails on the `otel-collector` inventory instance's assertion naming that machine, as a scratch edit setting stibnite's `platform` to `"nixos"` shows

#### Scenario: An agent host's overlay address disagrees with its second source

- **WHEN** `checks.x86_64-linux.otel-collector-config` compares each agent host's `flake.lib.hosts` address with its ZeroTier vars file or the controller's `externalMembers` entry of the same name, and a mutant changes one digit of pyrite's address or gives stibnite another external member's listed address
- **THEN** each mutant fails the check naming the host, and the unmutated tables pass with every address inside the network's /88

### Requirement: The collection CA issues each agent host one certificate

The clan vars generator `otel-ca` SHALL be shared, with `ca.key` never deployed and `ca.crt` public, and `otel-cert` SHALL issue each agent host a P-256 certificate signed by it, valid 3650 days, with CN the machine name, the URI SAN `spiffe://vanixiets/host/<machine>` and `extendedKeyUsage=clientAuth`, or on the ingress host `serverAuth,clientAuth` with the same URI SAN followed by `IP:<flake.lib.hosts.magnetite.zt>` and `DNS:magnetite.zt`.
On a darwin agent host the key SHALL be owned by `_otelcol` with mode `0400` and declared without `restartUnits`, and the agent's plist SHALL carry the certificate's sha256 as `OTEL_CERT_SHA256`, so a reissued certificate reloads the agent.
Each agent host's `networking.hostName`, which its agent stamps as `host.name` and its deploy records as `host`, SHALL equal the machine name its URI SAN carries.

**Discharged by**: the plan's `openssl` reading of each issued certificate and its hash check after every vars step; the agent role's host-name assertion on NixOS and darwin with its `extendModules` override `hostNameDiffers`; `vmTests.x86_64-linux.fleet-ingress`'s refusal and delivery cases; stibnite's evaluation of the agent role's `darwinModule`; the operator's reading of the darwin key's owner and mode after stibnite's routine activation.

#### Scenario: The ingress host's certificate is read

- **WHEN** `openssl x509 -ext subjectAltName,extendedKeyUsage` reads `vars/per-machine/magnetite/otel-cert/cert.pem/value`
- **THEN** it shows `URI:spiffe://vanixiets/host/magnetite`, `IP Address:fddb:4344:343b:14b9:399:930f:39db:40d2`, `DNS:magnetite.zt`, `TLS Web Server Authentication` and `TLS Web Client Authentication`

#### Scenario: A vars step runs

- **WHEN** a certificate is generated for a host, or a host is added as a reader of a shared var
- **THEN** the sha256 of `otel-ca`'s `ca.crt` and of the `ntfy-alerter` token are unchanged afterwards, and the step stops otherwise

#### Scenario: A certificate's SANs or usage change

- **WHEN** the SAN string or the key usage rendered for a host's certificate differs from the one recorded in its `validation`
- **THEN** clan regenerates that host's `otel-cert`, and its new files restart a NixOS host's collector through `restartUnits` and change a darwin host's `OTEL_CERT_SHA256`, so the host's next activation reloads `org.nixos.otelcol`

#### Scenario: stibnite's certificate is read

- **WHEN** `openssl x509 -subject -ext extendedKeyUsage` reads `vars/per-machine/stibnite/otel-cert/cert.pem/value` and `openssl verify -CAfile vars/shared/otel-ca/ca.crt/value` checks it
- **THEN** it shows `CN=stibnite`, `URI:spiffe://vanixiets/host/stibnite` and `TLS Web Client Authentication`, and the verification succeeds

#### Scenario: A darwin key is installed

- **WHEN** stibnite has been activated with the agent role's `darwinModule`
- **THEN** its `otel-cert` declaration sets no `restartUnits`, which clan-core rejects on darwin, and the installed key is owned by `_otelcol` with mode `-r--------`, which the operator records

#### Scenario: Every agent host's certificate is reissued with its URI SAN

- **WHEN** the vars step regenerates `otel-cert` for every agent host with `CLAN_NO_COMMIT=1` after the URI SAN enters the generator's `validation`
- **THEN** `openssl x509 -ext subjectAltName` reads exactly one URI SAN, `spiffe://vanixiets/host/<machine>`, from each host's `cert.pem`, `openssl verify` against `otel-ca` succeeds for each, and the sha256 of `otel-ca`'s `ca.crt` and of the `ntfy-alerter` token are unchanged

### Requirement: The ingress receiver accepts only certificate holders on magnetite's ZeroTier address

On the ingress host, caddy SHALL be the only listener on `[${flake.lib.hosts.magnetite.zt}]:4318`, serving TLS 1.3 only with magnetite's `otel-cert` and requiring a client certificate that verifies against `otel-ca`, and TCP 4318 SHALL be open on `zt+` only.
The collector's `otlp/mesh` SHALL be an OTLP/HTTP receiver on the Unix socket `/run/otelcol-mesh/otlp.sock` with `include_metadata: true`, in a directory owned by `root:otelcol-mesh` with mode 2770, where `otelcol-mesh` is held only by the collector's unit and caddy's account, so no other account on magnetite can connect to it; caddy SHALL forward every accepted request to it unchanged except for the identity header it sets.
No collector endpoint SHALL be off loopback.

**Discharged by**: R3.1's endpoint clause in `checks.x86_64-linux.otel-collector-config` with its mutants; magnetite's socket-group assertion over every unit's `Group` and `SupplementaryGroups` and every account's `extraGroups`, with its `extendModules` override `extraSocketMember`; the vendored probe's socket case; `vmTests.x86_64-linux.fleet-ingress`'s refusal and socket-access cases; the operator's refused request from stibnite at deploy.

#### Scenario: The endpoint is evaluated

- **WHEN** the evaluation-time collector check (R3.1) builds against magnetite's configuration
- **THEN** every collector receiver, exporter and scrape-target endpoint is loopback or the `otlp/mesh` socket, and caddy's mesh site address equals the address in `vars/shared/zerotier-ip-magnetite-zerotier/ip/value` at port 4318

#### Scenario: The endpoint is widened or moved

- **WHEN** a mutant gives `otlp/mesh` a TCP endpoint off loopback, sets caddy's mesh site to `[::]:4318`, or gives the check a ZeroTier address file naming another address
- **THEN** the evaluation-time collector check (R3.1) fails

#### Scenario: A client without a valid certificate connects

- **WHEN** `fleet-ingress` connects to caddy's mesh site without a client certificate, with a certificate from another CA, or offering at most TLS 1.2
- **THEN** each connection is refused during the handshake and no request reaches the collector

#### Scenario: A local account outside the socket's group connects

- **WHEN** `fleet-ingress` connects to `/run/otelcol-mesh/otlp.sock` as an account outside `otelcol-mesh`
- **THEN** the connection is refused with a permission error and no request reaches a pipeline

#### Scenario: A mesh member without a certificate connects at deploy

- **WHEN** after magnetite's deploy the operator sends an OTLP request from stibnite to `https://[fddb:4344:343b:14b9:399:930f:39db:40d2]:4318` without a client certificate
- **THEN** the handshake is refused, and the operator records the client's error

### Requirement: This capability states its own trust boundary

This capability SHALL state what its properties guarantee and what they do not, and SHALL NOT be described, by itself or in any downstream report, as an end-to-end guarantee that a host's series reach the store.

**Discharged by**: the requirement's own statement in the scenarios below; no regulator applies.

#### Scenario: The properties above are read as a set

- **WHEN** the properties of this capability are read as a set
- **THEN** what they establish is that each agent host holds a certificate from `otel-ca` naming it in a URI SAN, that the ingress accepts a mesh write only from a holder whose SAN names a collecting host and only from that host's overlay address, at TLS 1.3, that it stores a mesh write only under that host and only into the database and table an agent writes for its signal, that magnetite pins each collecting host's neighbour entry, that each agent, darwin included, queues and retries toward it, that the darwin probe writes launchd job state and disk health for the loopback node_exporter, and that `otel-envelope` regulates each collector and the fleet budget, each as far as its check, assertion, container test or recorded observation reaches

#### Scenario: A guarantee about a certificate holder is sought

- **WHEN** someone asks whether a host can write series only under its own name
- **THEN** the answer is yes over the mesh, as far as the binding's container test, `mesh-binding`, C6 and the spoofing acceptance reach: a write is accepted only from the host its certificate's URI SAN names, at that host's overlay address, and stored only under that host and only into the streams an agent writes, `fleet` metrics and `devloop` deploy records; it is no for writers the binding does not see: root on a collecting host can write any series or deploy record as that host, though not into another database or table, any local account on an agent host can inject points as that host through its loopback agent, and root on magnetite can write anything as any host

#### Scenario: A guarantee about a copied key is sought

- **WHEN** someone asks whether a copy of one host's `otel-key` lets another member write
- **THEN** the answer is no over the mesh: caddy refuses the copy from any overlay address but the named host's, and magnetite's pinned entry sends the named host's replies only to it; a writer on the named host itself, or on a future path that does not arrive over the overlay network, is not refused by the address; a copy refused during the TLS handshake, or used from the named host's spoofed address, which never completes a connection, reaches neither caddy's 403 count nor C6, so it is stopped but not detected

#### Scenario: A guarantee about a lost key is sought

- **WHEN** someone asks whether a lost or stolen agent key stops being accepted
- **THEN** the answer is no: certificates have no revocation, and a lost key stays valid until `otel-ca` is rotated, which the CA key, kept only in the encrypted repository vars, makes possible; stibnite's key sits on a laptop that leaves the operator's premises; a lost laptop with its key and its ZeroTier identity writes as itself until the operator deauthorizes its member on cinnabar's controller

#### Scenario: A guarantee about the network is sought

- **WHEN** someone asks whether ZeroTier authenticates the writer
- **THEN** the answer is no: ZeroTier is trusted to carry packets between members and to deliver a frame for a member's MAC only to that member, under world assumption `A71 — ZeroTier delivers a frame for a member's MAC only to that member, whose MAC derives from its node id and the network id`, and nothing more; under world assumption `A72 — ZeroTier neither inspects an inbound neighbour advertisement nor ties an rfc4193 address to the member sending from it` a member with root can claim another member's address, which only magnetite's pinned entries defeat and only toward magnetite; the two Android members and the darwin machines without a certificate reach the handshake and only mTLS refuses them

#### Scenario: A guarantee about launchd's report is sought

- **WHEN** someone asks whether the probe's launchd series are correct after a macOS update
- **THEN** the answer is no: the probe trusts `launchctl print`'s text, which launchctl's manual page says is not API, and the parser's fixtures hold only for the text recorded on stibnite, under world assumption `A62 — launchctl print reports a system job's state, runs and last exit code as unversioned text, and omits the exit code for some killed jobs`

#### Scenario: A guarantee about root on a darwin host is sought

- **WHEN** someone asks whether a darwin host's collection runs without root
- **THEN** the answer is no: `org.nixos.otelcol-process` runs as root to read other accounts' process memory, confined to the `process` scraper with no receiver endpoint, telemetry listener or credential, and any root process on that host can read the `_otelcol` key and inject points on loopback

#### Scenario: An end-to-end guarantee is sought

- **WHEN** someone asks whether these properties guarantee that a given series reaches the store
- **THEN** the answer is no: each stage's configuration, the gating checks, the container test and `otel-envelope` behave as stated, and nothing here observes a series' whole path

## ADDED Requirements

### Requirement: A mesh write is accepted only from the host its certificate names, at that host's overlay address

caddy SHALL map a verified client certificate's first URI SAN, `spiffe://vanixiets/host/<host>`, to that collecting host and its `flake.lib.hosts` address, the ingress host excluded, and SHALL answer 403 without forwarding when the SAN maps to no host or the peer address differs from the mapped one.
For an accepted request it SHALL set `X-Vanixiets-Host` to the mapped host, replacing any client value, and pass the collector's status and body back unchanged.

**Discharged by**: `vmTests.x86_64-linux.fleet-ingress`'s binding cases, which run the identity map, the filters and the neighbours rendered from one list; the 403 control at acceptance; resting on world assumption `A75 — caddy 2.11.7 exposes a verified client certificate's URI SANs, replaces a forwarded header, passes an upstream status through, and counts a response status`.

#### Scenario: A collecting host writes from its own address

- **WHEN** `fleet-ingress` posts metrics and a deploy record with electrum's test certificate from electrum's mapped test address
- **THEN** caddy forwards both with `X-Vanixiets-Host: electrum`, and both are stored under `electrum`

#### Scenario: A certificate is used from another host's address

- **WHEN** `fleet-ingress` posts with electrum's test certificate from `budgethost`'s mapped test address
- **THEN** caddy answers 403, nothing is stored, and caddy's 403 count rises by one

#### Scenario: A certificate names no collecting host

- **WHEN** `fleet-ingress` posts with an `otel-ca` test certificate that carries no URI SAN, and with one whose URI SAN names a host outside the table
- **THEN** caddy answers 403 to each and nothing is stored

#### Scenario: A write comes from an unlisted address

- **WHEN** `fleet-ingress` posts with electrum's test certificate from a test address no identity maps to
- **THEN** caddy answers 403 and nothing is stored

#### Scenario: A client sends its own identity header

- **WHEN** `fleet-ingress` posts with electrum's test certificate from electrum's address and the header `X-Vanixiets-Host: cinnabar`
- **THEN** the collector receives `X-Vanixiets-Host: electrum` only, and nothing is stored under `cinnabar`

#### Scenario: The ingress is under back-pressure behind caddy

- **WHEN** `fleet-ingress` makes the ingress's limiter refuse while the agent keeps collecting
- **THEN** the agent receives HTTP 503 through caddy, its queue grows and then drains, and every point it scraped arrives in the store

#### Scenario: magnetite writes to its own mesh site at acceptance

- **WHEN** after the binding's deploy the operator posts one metric from magnetite to its own mesh site with magnetite's `otel-cert`
- **THEN** caddy answers 403, because the ingress host is not in the identity map, and the operator records the status and C6's failing run

### Requirement: A mesh write is stored only under the host that sent it

Every pipeline receiving `otlp/mesh` SHALL begin with `memory_limiter` and its signal's binding filter, and `metrics/ingress` and `logs/ingress` SHALL receive only `forward`.
A binding filter SHALL drop a resource whose `host.name` differs from `X-Vanixiets-Host`, whose header is absent, or whose `vanixiets.database` and `vanixiets.table` are not a pair an agent sets for that signal, a log record whose `host` differs from the header, and a point or record carrying its own host attribute.

**Discharged by**: magnetite's pipeline-coverage assertion with its `extendModules` overrides `meshInIngress` and `logsMeshUnfiltered`; R3.1's clause rejecting any traces pipeline; `checks.x86_64-linux.mesh-binding`, which runs the pinned collector over the filter text magnetite renders; `vmTests.x86_64-linux.fleet-ingress`'s mismatch and foreign-table cases; the forced mismatch at acceptance; resting on world assumption `A76 — The collector's filter answers success for a dropped write and counts it per processor`.

#### Scenario: A resource names another host

- **WHEN** `fleet-ingress` posts with electrum's test certificate from electrum's address a metric whose resource `host.name` is `cinnabar`
- **THEN** the sender receives 200, nothing is stored under `cinnabar` or `electrum` for that metric, and `otelcol_processor_filter_datapoints_filtered{filter="filter/mesh-host-metrics"}` rises

#### Scenario: A deploy record names another host

- **WHEN** `fleet-ingress` posts with electrum's test certificate a deploy record whose `host` is `cinnabar`
- **THEN** the sender receives 200, no `deploy_record` row names `cinnabar` from it, and `otelcol_processor_filter_logs_filtered{filter="filter/mesh-host-logs"}` rises

#### Scenario: A point carries its own host attribute

- **WHEN** `fleet-ingress` posts with electrum's test certificate a metric whose resource `host.name` is `electrum` and whose data point carries `host_name="cinnabar"`
- **THEN** the point is not stored and the filter's counter rises

#### Scenario: A write names a database or table no agent writes

- **WHEN** `fleet-ingress` posts with electrum's test certificate from electrum's address a log record whose resource `host.name` is `electrum`, `vanixiets.database` is `devloop` and `vanixiets.table` is `ci_build`
- **THEN** the sender receives 200, no `ci_build` row is stored from it, and `otelcol_processor_filter_logs_filtered{filter="filter/mesh-host-logs"}` rises

#### Scenario: A pipeline receives mesh writes without the binding

- **WHEN** an `extendModules` override of magnetite adds `otlp/mesh` to `metrics/ingress` or removes the filter from `logs/mesh`
- **THEN** magnetite's evaluation fails on the pipeline-coverage assertion naming the pipeline, while a traces pipeline is rejected by R3.1

#### Scenario: Every collecting host keeps writing after the binding's deploy

- **WHEN** magnetite has run the binding for one hour after its deploy
- **THEN** every present collecting host's memory series and deploy records have kept arriving under its own name, C6 has passed on every run, and the operator records both

### Requirement: magnetite pins each collecting host's neighbour entry

magnetite SHALL hold on its ZeroTier link a permanent neighbour entry for every other collecting host's overlay address, naming `flake.lib.zerotierMac` of that address, installed by networkd from `systemd.network.networks."09-zerotier".neighbors`.
A deploy that changes these entries SHALL run only after each present collecting host's computed MAC has been read equal to the MAC magnetite's live neighbour table holds for it.

**Discharged by**: `checks.x86_64-linux.otel-collector-config`'s MAC clause over the pairs recorded from magnetite's live table, with its mutant `macBytesReversed`; the pre-deploy MAC gate; C6's neighbour clause; `vmTests.x86_64-linux.fleet-ingress`'s neighbour case, whose entries are installed by `ip`, so networkd's installation path is judged only by C6 and the operator-present zerotierone restart; the spoofing acceptance; resting on world assumptions `A71 — ZeroTier delivers a frame for a member's MAC only to that member, whose MAC derives from its node id and the network id`, `A72 — ZeroTier neither inspects an inbound neighbour advertisement nor ties an rfc4193 address to the member sending from it`, `A73 — Linux never changes a permanent neighbour entry on an advertisement, and lets an overriding advertisement rewrite a non-permanent one` and `A74 — The fleet's overlay network assigns rfc4193 addresses with neighbour emulation and carries only the accept-all rule`.

#### Scenario: The MAC function is checked against magnetite's live table

- **WHEN** `checks.x86_64-linux.otel-collector-config` computes `flake.lib.zerotierMac` for the address and MAC pairs recorded from magnetite's neighbour table and link on 2026-11-06
- **THEN** each computed MAC equals its recorded MAC, and the mutant `macBytesReversed` fails the check

#### Scenario: The pre-deploy MAC gate runs

- **WHEN** immediately before the deploy that installs or changes the entries the operator reads magnetite's neighbour table and compares each present collecting host's entry with its computed MAC
- **THEN** every pair is equal and the deploy proceeds, or any pair differs and the deploy does not run

#### Scenario: An advertisement claims a pinned address in the container test

- **WHEN** in `fleet-ingress` an attacker node, as root, sends an unsolicited neighbour advertisement with the override flag for a pinned address and then connects from that address
- **THEN** the store side's entry stays permanent with its pinned MAC, the connection does not complete, and a mutant store without the entries accepts the connection

#### Scenario: A member with root claims stibnite's address at acceptance

- **WHEN** after the entries are deployed and verified, and with the operator present, root on pyrite adds stibnite's overlay address, advertises it with the override flag and opens a TCP connection to magnetite's mesh site from it
- **THEN** magnetite's entry for stibnite stays permanent with stibnite's MAC, pyrite's connection does not complete, and the operator records both, while the same attempt against a phone's unpinned address rewrites magnetite's entry for the phone to pyrite's MAC, which the operator records and then deletes

#### Scenario: zerotierone restarts on magnetite

- **WHEN** with the operator present zerotierone is restarted on magnetite over the public SSH path
- **THEN** within one envelope period every pinned entry is present and permanent again with its computed MAC, or C6 fails naming the missing entries and the operator records the finding

### Requirement: otel-envelope on the ingress host fails when the binding refuses or drops a write

The ingress host's `otel-envelope` SHALL fail its clause C6 on any run after which a binding filter's drop counter or caddy's mesh-site 403 count rose, a collecting host's pinned entry is missing, not permanent, or names another MAC, or a liveness series a previous run recorded is absent; an absent drop or refusal counter reads zero, and a counter below its recorded value counts its current value.
Its target clause SHALL also probe caddy's metrics on `127.0.0.1:2019`.

**Discharged by**: `checks.x86_64-linux.otel-envelope`'s C6 cases with their mutants `c6IgnoresFilter`, `c6IgnoresRefusal`, `c6IgnoresNeighbour` and `c6IgnoresLiveness`; `vmTests.x86_64-linux.fleet-ingress`'s binding cases, each reading C6; the forced mismatch and the 403 control at acceptance.

#### Scenario: A filter drop is read

- **WHEN** the C6 cases give the envelope telemetry in which `otelcol_processor_filter_logs_filtered{filter="filter/mesh-host-logs"}` rose by one since the previous run
- **THEN** the run fails on C6 naming the filter, and the mutant `c6IgnoresFilter` passes it and so fails the check

#### Scenario: A refusal is read

- **WHEN** the C6 cases give the envelope caddy metrics in which the mesh site's `code="403"` count rose
- **THEN** the run fails on C6 naming caddy, and the mutant `c6IgnoresRefusal` fails the check

#### Scenario: A neighbour entry is wrong

- **WHEN** the C6 cases give the envelope a neighbour table in which one collecting host's entry is `STALE`, another's names a different MAC, and a third is absent
- **THEN** the run fails on C6 naming all three, and the mutant `c6IgnoresNeighbour` fails the check

#### Scenario: A liveness series disappears

- **WHEN** the C6 cases give the envelope a run in which a binding filter's incoming-items series, recorded on the previous run, is absent
- **THEN** the run fails on C6 naming the series, and the mutant `c6IgnoresLiveness` fails the check

#### Scenario: A mismatched write is forced at acceptance

- **WHEN** after the binding's deploy the operator posts from pyrite, with pyrite's own certificate, one metric whose `host.name` is `cinnabar`
- **THEN** the sender receives 200, nothing is stored under `cinnabar` from it, magnetite's next envelope run fails on C6, one `FAILED otel-envelope.service on magnetite` reaches `fleet-alerts`, the run after passes and its `RESOLVED` follows, and the operator records each

### Requirement: The ingress proxy runs inside a declared envelope

caddy on magnetite SHALL run with `MemoryMax = 128M` and `OOMScoreAdjust = 700`, below the evaluator's and above Perses', the store's and the collector's, SHALL load magnetite's `otel-cert` and `otel-key` only through `LoadCredential`, restarting on a reissue of either, and SHALL be a notified unit of magnetite.
It SHALL run with `admin off` and reloads off, and serve only its metrics on `http://127.0.0.1:2019`.

**Discharged by**: magnetite's kill-order assertion with caddy added and its `extendModules` override swapping caddy's and Perses' values; the agent role's notified-unit assertion; R3.1's endpoint clause; `vmTests.x86_64-linux.fleet-ingress`'s case `adminLoadIgnored`; the resident-memory reading over the first day after the binding's deploy.

#### Scenario: A local account posts a configuration to caddy

- **WHEN** `fleet-ingress` sends `POST /load` to `127.0.0.1:2019` with a configuration that drops the 403 and sets `X-Vanixiets-Host` to a fixed host
- **THEN** a write from an unlisted address still gets 403, and a client-sent `X-Vanixiets-Host` is still replaced by the mapped host

#### Scenario: The kill order is evaluated

- **WHEN** magnetite's configuration is evaluated
- **THEN** its kill-order assertion holds `nix-eval-jobs` above caddy above Perses above the store above the collector above `fleet-alert`, and an override giving caddy `OOMScoreAdjust = 500` fails the evaluation

#### Scenario: caddy's memory is read after a day

- **WHEN** caddy has run for 24 hours after the binding's deploy
- **THEN** the operator records its cgroup's `memory.peak`, and a peak above 96 MiB is put to the operator to raise the bound
