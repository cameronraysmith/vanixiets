### Task 4: The binding

Implements `tasks.md` 4.1–4.6 (design D3–D8, D10, D11; FII `The ingress receiver accepts only certificate holders on magnetite's ZeroTier address`, `A mesh write is accepted only from the host its certificate names, at that host's overlay address`, `A mesh write is stored only under the host that sent it`, `magnetite pins each collecting host's neighbour entry`, `otel-envelope on the ingress host fails when the binding refuses or drops a write`, `The ingress proxy runs inside a declared envelope`).
It is pull request 2; it starts after Task 3 Step 5 passed.
Every regulator is written and seen failing before the configuration it judges.

**Files:**
- Modify: `modules/clan/services/otel-collector/flake-module.nix` (the ingress role and its options), `modules/lib/otel-envelope.nix`, `modules/lib/observability-hosts.nix` (`caddy` in magnetite's `notifiedUnits`), `modules/machines/nixos/magnetite/default.nix` (the kill order), `modules/checks/otel-envelope.nix` and `modules/checks/otel-envelope/` fixtures, `modules/checks/otel-collector-config.nix`, `modules/vm-tests/otel-test-pki.nix`, `modules/vm-tests/fleet-ingress.nix`, `modules/vm-tests/fleet-ingress/helpers.py`
- Create: `modules/checks/mesh-binding.nix`

**Interfaces:**
- Consumes: `flake.lib.hosts`, `flake.lib.zerotierMac`, `externalMembers` (Task 2); the filter conditions, counter names, caddy series and socket form Task 1 Step 5 confirmed.
- Produces: everything in the plan's interface contract marked Task 4.

- [ ] **Step 1: C6, failing first (tasks.md 4.1)**

Add fixtures under `modules/checks/otel-envelope/`: `binding-telemetry-{base,filter,dead}.prom` (the collector's telemetry with `otelcol_processor_filter_logs_filtered{filter="filter/mesh-host-logs"}` at 0 and then 1, and each binding filter's `otelcol_processor_incoming_items` present in `base` and `filter` and absent in `dead`, under the names Task 1 Step 5 printed), `binding-caddy-{base,refused}.prom` (copied from Task 1 Step 5's caddy scrape: the mesh server's request count, and its `code="403"` series 0 then 1), and `binding-neigh-{good,bad}.json` (`ip -j -6 neigh show` output: every entry `PERMANENT` with its computed MAC; then one `STALE`, one with another MAC, one absent).
Add the cases: base then filter fails `C6 binding` naming `filter/mesh-host-logs`; base then refused fails naming caddy; good passes; bad fails naming all three addresses; base then dead fails naming each missing liveness series; no counters at all passes; a run with no state file records and passes; a counter below its recorded value counts its current value; an unanswered caddy scrape fails naming `caddy-metrics-unanswered`.
Mutants: `c6IgnoresFilter`, `c6IgnoresRefusal`, `c6IgnoresNeighbour`, `c6IgnoresLiveness`, each removing one input.
Run `nix build .#.checks.x86_64-linux.otel-envelope -L`; expected: FAIL at the first C6 case.
Then add to `flake.lib.otelEnvelope` the argument `binding ? null` (`{ caddyMetricsUrl; filters; neighbours; ip; }`), `pkgs.jq` and `pkgs.iproute2` to `runtimeInputs` when `binding != null`, and, interpolated after C4 only when `binding != null`, a clause on C4's pattern (`prev`'s `absent`, the `awk` comparison, the `baseline` skip):

```bash
c6=""
: > "$tmp/caddy"
curl -fsS --max-time 10 "$binding_caddy_url" -o "$tmp/caddy" || c6="$c6 caddy-metrics-unanswered;"
c6_rise() {
  local was
  was=$(prev "$1"); echo "$1 $2" >> "$next"
  if [ "$baseline" = 1 ]; then echo 0; return; fi
  [ "$was" != absent ] || was=0
  awk -v n="$2" -v p="$was" 'BEGIN { print (n < p) ? n : n - p }'
}
# A liveness series once seen stays recorded while absent, so a renamed series
# fails every run instead of reading as zero drops.
c6_live() {
  if [ "$2" = 1 ]; then echo "live $1 1" >> "$next"
  elif [ "$(prev "live $1")" != absent ]; then echo "live $1 1" >> "$next"; [ "$baseline" = 1 ] || c6="$c6 $1 absent;"
  fi
}
for f in $binding_filters; do
  now=$(awk -v f="$f" '/^otelcol_processor_filter_(datapoints|logs)_filtered/ && index($0, "filter=\"" f "\"") {s+=$NF} END {print s+0}' "$tmp/now")
  r=$(c6_rise "c6 $f" "$now"); [ "$r" = 0 ] || c6="$c6 $f dropped $r;"
  seen=$(awk -v f="$f" '/^otelcol_processor_incoming_items/ && index($0, "processor=\"" f "\"") {n=1} END {print n+0}' "$tmp/now")
  c6_live "$f-incoming" "$seen"
done
now=$(awk '/^caddy_http_request_duration_seconds_count/ && /server="mesh"/ && /code="403"/ {s+=$NF} END {print s+0}' "$tmp/caddy")
r=$(c6_rise "c6 caddy403" "$now"); [ "$r" = 0 ] || c6="$c6 caddy refused $r;"
seen=$(awk '/^caddy_http_request_duration_seconds_count/ && /server="mesh"/ {n=1} END {print n+0}' "$tmp/caddy")
c6_live caddy-mesh-requests "$seen"
"$binding_ip" -j -6 neigh show > "$tmp/neigh"
while read -r addr mac; do
  got=$(jq -r --arg a "$addr" '.[] | select(.dst == $a) | "\(.lladdr // "") \((.state // []) | join(","))"' "$tmp/neigh")
  [ "$got" = "$mac PERMANENT" ] || c6="$c6 neighbour $addr ${got:-absent};"
done <<< "$binding_neighbours"
if [ -n "$c6" ]; then fail "C6 binding" "${c6% }"; else ok "C6 binding"; fi
```

`binding_neighbours` holds one `address mac` line per entry, rendered from `binding.neighbours`; `ip` is injected so the check passes a stub printing the fixture; the series names and labels are those Task 1 Step 5 printed, corrected here if they differ.
Expected after: every C6 case passes or fails as stated and the four mutants are rejected; `nix eval --raw` of cinnabar's `otel-envelope` `ExecStart` equals the same `nix eval` run in the same step at the change's parent commit; the cost is recorded (build, evaluation).

- [ ] **Step 2: magnetite's assertions, failing first (tasks.md 4.2)**

Add to the ingress role, under `config.assertions`:
- `meshPipelineCoverage`: for every pipeline whose `receivers` contain `otlp/mesh`, `processors` begins `[ "memory_limiter" "filter/mesh-host-<signal>" ]`, where `<signal>` is the pipeline name's prefix, and `metrics/ingress` and `logs/ingress` have `receivers = [ "forward" ]`; a traces pipeline is R3.1's to reject (`modules/checks/otel-collector-config.nix:308-311`), so no traces override is added here;
- `meshSocketGroup`: the units whose `serviceConfig.Group` or `serviceConfig.SupplementaryGroups` name `otelcol-mesh`, across every `systemd.services.*`, together with the accounts whose `users.users.*.extraGroups` or the group's `members` name it, are exactly the collector's unit and caddy, because a `DynamicUser` unit joins through its unit settings and never appears in `members`;
- `caddyVersion`: `config.services.caddy.package.version == "2.11.7"`, following `modules/checks/pyrite-desktop.nix:222`, with the message "caddy moved off 2.11.7: rerun vmTests.x86_64-linux.fleet-ingress and update world assumption A75 before raising this pin";
- in `modules/machines/nixos/magnetite/default.nix`'s kill order (`:734-740`), `caddy = unitAdj "caddy";` between `nix-eval-jobs` and `perses`.

The map, the filters and the neighbours are rendered from one `let`-bound list in Step 4, so no assertion compares them; `mesh-binding` (Step 3) and the container's binding legs judge what the rendering produces.
Overrides, each run alone: `meshInIngress`, `logsMeshUnfiltered`, `extraSocketMember` (another unit, for example `nginx`, given `SupplementaryGroups = [ "otelcol-mesh" ]`), `caddyVersionMoved` (`services.caddy.package = pkgs.caddy.overrideAttrs { version = "0.0.0"; }`), `caddyBelowPerses` (`OOMScoreAdjust = 500`).
Expected: each override fails magnetite's evaluation with its message; the unmodified configuration fails because caddy and the mesh pipelines do not exist yet (evaluation).

- [ ] **Step 3: The test PKI, the container cases and `mesh-binding`, failing first (tasks.md 4.3)**

In `modules/vm-tests/otel-test-pki.nix`, issue `id-electrum`, `id-budgethost`, `id-cinnabar` and `id-v6host` with `subjectAltName=URI:spiffe://vanixiets/host/<name>`, `nosan` with none, and `outsider` naming `spiffe://vanixiets/host/outsider`, all from the test CA; `ingress.crt` keeps its `IP:127.0.0.1` SAN and gains `IP:::1`.
In `modules/vm-tests/fleet-ingress.nix`, set the ingress role's internal options for the container: `vanixiets.otelCollector.meshIdentities = { electrum = "127.0.0.1"; budgethost = "127.0.0.2"; cinnabar = "127.0.0.3"; v6host = "::1"; }`, `meshListen = [ "127.0.0.1:4318" "[::1]:4318" ]` in place of the ZeroTier address, and `meshPinNeighbours = false`, because the loopback identities are not eight-group rfc4193 addresses and `zerotierMac` asserts eight groups; the agent collector uses `id-electrum`; `mesh_write` in `helpers.py` takes `identity` and `source` arguments and calls `curl --interface <source> --cert id-<identity>.crt`; the budget fixtures write `budgethost` from `127.0.0.2` and `cinnabar` from `127.0.0.3`.
Add a case `binding` with the legs `bindingMatch`, `bindingWrongAddress` (electrum's certificate from `127.0.0.2`), `bindingNoSan`, `bindingOutsider`, `bindingUnlisted` (`127.0.0.9`), `bindingHeaderForged`, `bindingHostMismatch`, `bindingRecordMismatch`, `bindingPointAttribute`, `bindingForeignTable` (electrum's certificate from `127.0.0.1`, a log record whose resource sets `host.name=electrum`, `vanixiets.database=devloop` and `vanixiets.table=ci_build`, after which no `ci_build` row exists) and `bindingBackPressure` (the existing `limiterRefusing` mutant behind caddy, expecting 503 at the agent), each asserting the status, the store's rows by `regulator`, and C6's verdict on the next ingress envelope run; `adminLoadIgnored` (`curl -X POST http://127.0.0.1:2019/load -H 'Content-Type: application/json'` with a configuration that has no 403 route and a fixed `X-Vanixiets-Host: cinnabar`, then `bindingUnlisted` and `bindingHeaderForged` rerun with their original results); and `socketAccess` (`runuser -u nobody -- curl --unix-socket /run/otelcol-mesh/otlp.sock` fails with a permission error).
Add `checks.x86_64-linux.mesh-binding` in `modules/checks/mesh-binding.nix`: a `runCommand` that writes a collector configuration holding `otlp/mesh` on a Unix socket in `$TMPDIR` with `include_metadata: true`, magnetite's evaluated `filter/mesh-host-metrics` and `filter/mesh-host-logs` (read from `nixosConfigurations.magnetite.config.services.opentelemetry-collector.settings.processors`), and a `file` exporter, runs the pinned `otelcol-contrib` with `--config=file:<path>`, posts Task 1 Step 5's filter cases for two of magnetite's collecting hosts through the socket, and requires the matching metric and record in the exporter's file and every other case absent, with the dropped counts on the telemetry endpoint.
Run `nix build .#vmTests.x86_64-linux.fleet-ingress -L` on magnetite and `nix build .#.checks.x86_64-linux.mesh-binding -L`.
Expected: the container test FAILS at `bindingWrongAddress` or the first mismatch leg, because the current ingress stores what it receives; `mesh-binding` FAILS on the missing filters; the check's cost is recorded (container, magnetite; build).

- [ ] **Step 4: caddy, the socket and the mesh pipelines (tasks.md 4.4)**

In the ingress role, add the internal options of the interface contract, `meshIdentities`, `meshListen` and `meshPinNeighbours`, with their defaults; bind `identities = lib.mapAttrsToList (host: address: { inherit host address; }) config.vanixiets.otelCollector.meshIdentities` once in a `let`, and render the caddy map, the filters' host conditions and (Step 5) the neighbours from it alone.
Add the socket in the form Task 1 Step 5's socket test passed; for the form of design D3:

```nix
users.groups.otelcol-mesh.members = [ "caddy" ];
systemd.tmpfiles.rules = [ "d /run/otelcol-mesh 2770 root otelcol-mesh" ];
systemd.services.opentelemetry-collector.serviceConfig = {
  SupplementaryGroups = [ "otelcol-mesh" ];
  ReadWritePaths = [ "/run/otelcol-mesh" ];
  UMask = "0007";
};
services.opentelemetry-collector.settings.receivers."otlp/mesh".protocols.http = lib.mkForce {
  transport = "unix";
  endpoint = "/run/otelcol-mesh/otlp.sock";
  include_metadata = true;
};
```

If the socket test passed only with the fallback, the collector's `serviceConfig` also takes `Group = "otelcol-mesh"` beside `DynamicUser`, and `meshSocketGroup` counts it.
caddy:

```nix
services.caddy = {
  enable = true;
  enableReload = false;
  globalConfig = ''
    auto_https off
    admin off
    metrics
  '';
  virtualHosts.${lib.concatMapStringsSep ", " (a: "https://${a}") meshListen}.extraConfig = ''
    tls {$CREDENTIALS_DIRECTORY}/otel-cert {$CREDENTIALS_DIRECTORY}/otel-key {
      protocols tls1.3
      client_auth {
        mode require_and_verify
        trust_pool file ${config.vanixiets.otelCollector.caFile}
      }
    }
    map {http.request.tls.client.san.uris.0} {mesh_host} {mesh_addr} {
      ${lib.concatMapStrings (i: "spiffe://vanixiets/host/${i.host} ${i.host} ${i.address}\n") identities}
    }
    @refused not vars {http.request.remote.host} {mesh_addr}
    respond @refused 403
    reverse_proxy unix//run/otelcol-mesh/otlp.sock {
      header_up X-Vanixiets-Host {mesh_host}
    }
  '';
  virtualHosts."http://127.0.0.1:2019".extraConfig = ''
    bind 127.0.0.1
    metrics
  '';
};
systemd.services.caddy = {
  serviceConfig = {
    LoadCredential = [ "otel-cert:${certPath}" "otel-key:${keyPath}" ];
    MemoryMax = "128M";
    OOMScoreAdjust = 700;
  };
  after = [ "opentelemetry-collector.service" ];
};
```

`admin off` removes the API a local account could `POST /load` to, and nixpkgs' reload path needs that API, so `enableReload = false` and a Caddyfile change restarts caddy (design D3).
The `server` label C6 reads is the mesh site's server name, set with a `servers` block naming it `mesh`; the `tls` placeholder syntax for credential paths is the one Task 1 Step 5 ran, and a literal `/run/credentials/caddy.service/` path is the fallback.
`otel-cert` and `otel-key` gain `caddy.service` in `restartUnits` on the ingress host; `caddy` joins magnetite's `notifiedUnits`; `metrics/mesh` and `logs/mesh` are added and `otlp/mesh` removed from `metrics/ingress` and `logs/ingress`; the two filters render Task 1 Step 5's conditions over `identities`, and their allow-list conditions from the `vanixiets.database` and `vanixiets.table` values the agent role's `resource/agent` and `resource/devloop-deploy_record` processors stamp, bound once in the role's `let` and read by both, so a new honest stream extends the allow-list with its agent.
The port opening on `zt+` is unchanged; R3.1's endpoint clause now collects caddy's site addresses beside the collector's endpoints, requires the collector's to be loopback or the socket and caddy's mesh site to equal `[<ZeroTier address file>]:4318`, with mutants `meshTcpEndpoint` and `caddyWildcard`.
The existing OCC mutants written against `otlp/mesh`'s TCP endpoint (`modules/checks/otel-collector-config.nix:391-398`) move with it: `meshWildcard`, which sets that endpoint to `[::]:4318`, is replaced by `meshTcpEndpoint`, which gives the socket receiver the same TCP endpoint, and removed; `secondMeshReceiver` is rewritten to give `otlp/second` the socket path, so it still shows a second receiver sharing the mesh endpoint rejected; `ztAddressOther`, which changes the check's ZeroTier address input, is kept and now fails on caddy's mesh site address instead of the collector's endpoint.
Expected: Step 2's assertions pass; `caddy validate --config <rendered> --adapter caddyfile` with the root pin's caddy exits 0; `otel-collector-config` and `mesh-binding` pass with their mutants rejected; Step 3's binding legs pass (evaluation, build, container).

- [ ] **Step 5: The neighbour case and the pinned entries (tasks.md 4.5)**

In `fleet-ingress`, add `neighbourPinned`: inside the `store` container, `ip netns add victim`, `ip netns add attacker`, a veth pair from the root namespace's `pin0` (address `fd00:81:1:1:1:1:1:1/64`) to a bridge joining both namespaces, with `fd00:81:1:1:1:1:1:2` on `victim`, an eight-group address `zerotierMac` accepts, and the entries rendered by the same function as magnetite's for `{ victim = "fd00:81:1:1:1:1:1:2"; }` on network `db4344343b14b903` installed on `pin0` with `ip -6 neigh replace … nud permanent`, the victim's link carrying the computed MAC; `meshListen` gains `[fd00:81:1:1:1:1:1:1]:4318` and `meshIdentities.victim = "fd00:81:1:1:1:1:1:2"`.
In `attacker`, root adds `fd00:81:1:1:1:1:1:2/64 nodad`, sends an unsolicited advertisement with the override and solicited flags (`ndsend` from `iputils`, or a short Python `socket(AF_INET6, SOCK_RAW, IPPROTO_ICMPV6)` writer in `helpers.py`), and runs `curl --interface fd00:81:1:1:1:1:1:2 --max-time 10 --cert id-victim.crt …`.
Expected: `ip -j -6 neigh show dev pin0` still shows the victim's MAC `PERMANENT`, curl exits 28, nothing is stored under `victim`; mutant `noPinnedEntries`, without the entry, first pings the victim from `pin0` so the store holds a `REACHABLE` entry, because Linux creates no entry from an untracked advertisement (`net/ipv6/ndisc.c:1074-1079`), then sends the advertisement, which rewrites that entry, and the write goes through and is stored under `victim`.
The first run, before the entries exist, also shows whether `ip netns` works inside the systemd-nspawn container; if it does not, the case is put to the operator before the entries are added.
Then add on the ingress host, while `meshPinNeighbours` is true:

```nix
systemd.network.networks."09-zerotier".neighbors = map (i: {
  Address = i.address;
  LinkLayerAddress = config.flake.lib.zerotierMac { inherit network; inherit (i) address; };
}) identities;
```

with `network = lib.fileContents "${inputs.self}/vars/shared/zerotier-network-zerotier/network-id/value"` bound in the role's `let`.
Expected: the case passes and the mutant fails it; as a smoke reading only, `nix eval --json .#nixosConfigurations.magnetite.config.systemd.network.networks.09-zerotier.neighbors` lists the six hosts with their computed MACs and no magnetite, the MAC clause, C6 and Task 6 Step 1 being the regulators (container, evaluation).
networkd's installation of these entries on the ZeroTier link is not exercised here, because the container installs its entries with `ip`; only C6 and Task 6 Step 1 judge it (design D4).

- [ ] **Step 6: Format and open pull request 2 (tasks.md 4.6)**

`nix fmt`, keeping its log; `nix fmt -- --fail-on-change`; record each changed check's cost, and `nixos-magnetite`'s before and after; open the pull request in plain words (for example "Accept mesh telemetry only from the host each certificate names"), its description stating the `fleet-ingress` run (commit, host, date and cases passed).
Expected: nixbot green on `otel-collector-config`, `otel-envelope`, `mesh-binding` and `nixos-magnetite`; each changed check below 536,870,912 B, and any rise in `nixos-magnetite`'s cost put to the operator (command).
