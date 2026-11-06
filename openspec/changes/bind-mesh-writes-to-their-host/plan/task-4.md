### Task 4: The binding

Implements `tasks.md` 4.1–4.6 (design D3–D8, D10, D11; FII `The ingress receiver accepts only certificate holders on magnetite's ZeroTier address`, `A mesh write is accepted only from the host its certificate names, at that host's overlay address`, `A mesh write is stored only under the host that sent it`, `magnetite pins each collecting host's neighbour entry`, `otel-envelope on the ingress host fails when the binding refuses or drops a write`, `The ingress proxy runs inside a declared envelope`).
It is pull request 2; it starts after Task 3 Step 5 passed.
Every regulator is written and seen failing before the configuration it judges.

**Files:**
- Modify: `modules/clan/services/otel-collector/flake-module.nix` (the ingress role and its options), `modules/lib/otel-envelope.nix`, `modules/lib/observability-hosts.nix` (`caddy` in magnetite's `notifiedUnits`), `modules/machines/nixos/magnetite/default.nix` (the kill order), `modules/checks/otel-envelope.nix` and `modules/checks/otel-envelope/` fixtures, `modules/checks/otel-collector-config.nix`, `modules/vm-tests/otel-test-pki.nix`, `modules/vm-tests/fleet-ingress.nix`, `modules/vm-tests/fleet-ingress/helpers.py`

**Interfaces:**
- Consumes: `flake.lib.hosts`, `flake.lib.zerotierMac` (Task 2); the filter conditions and counter names Task 1 Step 5 confirmed.
- Produces: everything in the plan's interface contract marked Task 4.

- [ ] **Step 1: C6, failing first (tasks.md 4.1)**

Add fixtures under `modules/checks/otel-envelope/`: `binding-telemetry-{base,filter}.prom` (the collector's telemetry with `otelcol_processor_filter_logs_filtered{filter="filter/mesh-host-logs"}` at 0 and then 1, under the names Task 1 Step 5 printed), `binding-caddy-{base,refused}.prom` (`caddy_http_request_duration_seconds_count{server="mesh",handler="static_response",code="403",method="POST"}` 0 then 1), and `binding-neigh-{good,bad}.json` (`ip -j -6 neigh show` output: every entry `PERMANENT` with its computed MAC; then one `STALE`, one with another MAC, one absent).
Add the cases: base then filter fails `C6 binding` naming `filter/mesh-host-logs`; base then refused fails naming caddy; good passes; bad fails naming all three addresses; no counters at all passes; a counter below its recorded value counts its current value.
Mutants: `c6IgnoresFilter`, `c6IgnoresRefusal`, `c6IgnoresNeighbour`, each removing one input.
Run `nix build .#checks.x86_64-linux.otel-envelope -L`; expected: FAIL at the first C6 case.
Then add to `flake.lib.otelEnvelope` the argument `binding ? null` (`{ caddyMetricsUrl; filters; neighbours; ip; }`) and, interpolated after C4 only when `binding != null`:

```bash
# C6 binding: since the previous run, a binding filter dropped data, caddy
# refused a mesh write, or a pinned neighbour entry is missing, not
# PERMANENT, or names another MAC (design D6).
c6=""
curl -fsS --max-time 10 "$binding_caddy_url" -o "$tmp/caddy" || c6="$c6 caddy-metrics-unanswered;"
for f in $binding_filters; do
  now=$(awk -v f="$f" '/^otelcol_processor_filter_(datapoints|logs)_filtered/ && index($0, "filter=\"" f "\"") {s+=$NF} END {print s+0}' "$tmp/now")
  was=$(prev "c6 $f"); echo "c6 $f $now" >> "$next"
  rise=$(( now < ${was:-0} ? now : now - ${was:-0} )); [ "$rise" -eq 0 ] || c6="$c6 $f dropped $rise;"
done
now=$(awk '/^caddy_http_request_duration_seconds_count/ && /server="mesh"/ && /code="403"/ {s+=$NF} END {print s+0}' "$tmp/caddy")
was=$(prev "c6 caddy403"); echo "c6 caddy403 $now" >> "$next"
rise=$(( now < ${was:-0} ? now : now - ${was:-0} )); [ "$rise" -eq 0 ] || c6="$c6 caddy refused $rise;"
"$binding_ip" -j -6 neigh show > "$tmp/neigh"
while read -r addr mac; do
  got=$(jq -r --arg a "$addr" '.[] | select(.dst == $a) | "\(.lladdr // "") \((.state // []) | join(","))"' "$tmp/neigh")
  [ "$got" = "$mac PERMANENT" ] || c6="$c6 neighbour $addr ${got:-absent};"
done <<< "$binding_neighbours"
if [ -n "$c6" ]; then fail "C6 binding" "${c6% }"; else ok "C6 binding"; fi
```

`binding_neighbours` holds one `address mac` line per entry, rendered from `binding.neighbours`; `ip` is injected so the check passes a stub printing the fixture.
Expected after: every C6 case passes or fails as stated and the three mutants are rejected; `nix eval --raw` of cinnabar's `otel-envelope` `ExecStart` equals Task 1 Step 2's store path; the cost is recorded (build, evaluation).

- [ ] **Step 2: magnetite's assertions, failing first (tasks.md 4.2)**

Add to the ingress role, under `config.assertions`:
- `meshPipelineCoverage`: for every pipeline whose `receivers` contain `otlp/mesh`, `processors` begins `[ "memory_limiter" "filter/mesh-host-<signal>" ]`, where `<signal>` is the pipeline name's prefix, and `metrics/ingress` and `logs/ingress` have `receivers = [ "forward" ]`;
- `meshTableAgreement`: the host lists of caddy's rendered map lines, of the filters' conditions and of the `09-zerotier` `neighbors` each equal `attrNames meshIdentities`, the addresses of the map and the neighbours each equal `meshIdentities`' values, and each neighbour's `LinkLayerAddress` equals `zerotierMac` of its address;
- `meshSocketGroup`: `users.groups.otelcol-mesh.members` is exactly the collector's and caddy's accounts;
- in `modules/machines/nixos/magnetite/default.nix`'s kill order (`:734-740`), `caddy = unitAdj "caddy";` between `nix-eval-jobs` and `perses`.

Overrides, each run alone: `meshInIngress`, `logsMeshUnfiltered`, `tracesMeshUnfiltered`, `mapLineSwapped` (cinnabar's map line given pyrite's address), `neighbourDropped`, `extraSocketMember` (`nobody`), `caddyBelowPerses` (`OOMScoreAdjust = 500`).
Expected: each override fails magnetite's evaluation with its message; the unmodified configuration fails because caddy and the mesh pipelines do not exist yet (evaluation).

- [ ] **Step 3: The test PKI and the container cases, failing first (tasks.md 4.3)**

In `modules/vm-tests/otel-test-pki.nix`, issue `id-electrum`, `id-budgethost`, `id-cinnabar` and `id-v6host` with `subjectAltName=URI:spiffe://vanixiets/host/<name>`, `nosan` with none, and `outsider` naming `spiffe://vanixiets/host/outsider`, all from the test CA; `ingress.crt` keeps its `IP:127.0.0.1` SAN and gains `IP:::1`.
In `modules/vm-tests/fleet-ingress.nix`, set `vanixiets.otelCollector.meshIdentities = { electrum = "127.0.0.1"; budgethost = "127.0.0.2"; cinnabar = "127.0.0.3"; v6host = "::1"; }` and caddy's site to `127.0.0.1:4318` and `[::1]:4318` in place of the ZeroTier address; the agent collector uses `id-electrum`; `mesh_write` in `helpers.py` takes `identity` and `source` arguments and calls `curl --interface <source> --cert id-<identity>.crt`; the budget fixtures write `budgethost` from `127.0.0.2` and `cinnabar` from `127.0.0.3`.
Add a case `binding` with the legs `bindingMatch`, `bindingWrongAddress` (electrum's certificate from `127.0.0.2`), `bindingNoSan`, `bindingOutsider`, `bindingUnlisted` (`127.0.0.9`), `bindingHeaderForged`, `bindingHostMismatch`, `bindingRecordMismatch`, `bindingPointAttribute` and `bindingBackPressure` (the existing `limiterRefusing` mutant behind caddy, expecting 503 at the agent), each asserting the status, the store's rows by `regulator`, and C6's verdict on the next ingress envelope run; and `socketAccess` (`runuser -u nobody -- curl --unix-socket /run/otelcol-mesh/otlp.sock` fails with a permission error).
Run `nix build .#vmTests.x86_64-linux.fleet-ingress -L` on magnetite.
Expected: FAIL at `bindingWrongAddress` or the first mismatch leg, because the current ingress stores what it receives (container, magnetite).

- [ ] **Step 4: caddy, the socket and the mesh pipelines (tasks.md 4.4)**

In the ingress role, add the option `vanixiets.otelCollector.meshIdentities` with the default of the interface contract, and:

```nix
users.groups.otelcol-mesh.members = [ "caddy" ];
systemd.services.opentelemetry-collector.serviceConfig = {
  SupplementaryGroups = [ "otelcol-mesh" ];
  UMask = "0007";
  RuntimeDirectory = "otelcol-mesh";
  RuntimeDirectoryMode = "2770";
};
services.opentelemetry-collector.settings.receivers."otlp/mesh".protocols.http = lib.mkForce {
  transport = "unix";
  endpoint = "/run/otelcol-mesh/otlp.sock";
  include_metadata = true;
};
```

The collector runs with `DynamicUser`, so the group is joined through `SupplementaryGroups` and the socket's group comes from the setgid runtime directory, which `systemd-tmpfiles` does not manage; `socketAccess` and `meshSocketGroup` judge both, and if the dynamic user cannot hold the group the plan review's disposition decides a static user for the collector.
caddy:

```nix
services.caddy = {
  enable = true;
  globalConfig = ''
    auto_https off
    admin 127.0.0.1:2019
    metrics
  '';
  virtualHosts."https://[${zt}]:4318".extraConfig = ''
    tls {$CREDENTIALS_DIRECTORY}/otel-cert {$CREDENTIALS_DIRECTORY}/otel-key {
      protocols tls1.3
      client_auth {
        mode require_and_verify
        trust_pool file ${config.vanixiets.otelCollector.caFile}
      }
    }
    map {http.request.tls.client.san.uris.0} {mesh_host} {mesh_addr} {
      ${lib.concatStrings (lib.mapAttrsToList (h: a: "spiffe://vanixiets/host/${h} ${h} ${a}\n") identities)}
    }
    @refused not vars {http.request.remote.host} {mesh_addr}
    respond @refused 403
    reverse_proxy unix//run/otelcol-mesh/otlp.sock {
      header_up X-Vanixiets-Host {mesh_host}
    }
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

The `server` label C6 reads is the site's server name, set with a `servers` block naming it `mesh`; the `tls` placeholder syntax for credential paths is checked with `caddy validate` before the commit, and a literal `/run/credentials/caddy.service/` path is the fallback.
`otel-cert` and `otel-key` gain `caddy.service` in `restartUnits` on the ingress host; `caddy` joins magnetite's `notifiedUnits`; `metrics/mesh` and `logs/mesh` are added and `otlp/mesh` removed from `metrics/ingress` and `logs/ingress`; the two filters render Task 1 Step 5's conditions over `attrNames identities`.
The port opening on `zt+` is unchanged; R3.1's endpoint clause now collects caddy's site addresses beside the collector's endpoints, requires the collector's to be loopback or the socket and caddy's mesh site to equal `[<ZeroTier address file>]:4318`, with mutants `meshTcpEndpoint` and `caddyWildcard`.
Expected: Step 2's assertions pass; `caddy validate --config <rendered> --adapter caddyfile` with the root pin's caddy exits 0; `otel-collector-config` passes with its mutants rejected; Step 3's binding legs pass (evaluation, build, container).

- [ ] **Step 5: The neighbour case and the pinned entries (tasks.md 4.5)**

In `fleet-ingress`, add `neighbourPinned`: inside the `store` container, `ip netns add victim`, `ip netns add attacker`, a veth pair from the root namespace's `pin0` (address `fd00:81::1/64`) to a bridge joining both namespaces, with `fd00:81::2` on `victim` and the entries rendered by the same function as magnetite's for `{ victim = "fd00:81::2"; }` installed on `pin0` with `ip -6 neigh replace … nud permanent`, the victim's link carrying the computed MAC; caddy also listens on `[fd00:81::1]:4318` with `meshIdentities.victim = "fd00:81::2"`.
In `attacker`, root adds `fd00:81::2/64 nodad`, sends an unsolicited advertisement with the override and solicited flags (`ndsend` from `iputils`, or a short Python `socket(AF_INET6, SOCK_RAW, IPPROTO_ICMPV6)` writer in `helpers.py`), and runs `curl --interface fd00:81::2 --max-time 10 --cert id-victim.crt …`.
Expected: `ip -j -6 neigh show dev pin0` still shows the victim's MAC `PERMANENT`, curl exits 28, nothing is stored under `victim`; mutant `noPinnedEntries`, without the entry, lets the write through and stores it under `victim`.
Then add `systemd.network.networks."09-zerotier".neighbors = lib.mapAttrsToList (_: a: { Address = a; LinkLayerAddress = config.flake.lib.zerotierMac { network = "db4344343b14b903"; address = a; }; }) identities;` on the ingress host.
Expected: the case passes and the mutant fails it; `nix eval --json .#nixosConfigurations.magnetite.config.systemd.network.networks.09-zerotier.neighbors` lists the six hosts with their computed MACs and no magnetite (container, evaluation).

- [ ] **Step 6: Format and open pull request 2 (tasks.md 4.6)**

`nix fmt`, keeping its log; `nix fmt -- --fail-on-change`; record each changed check's cost; open the pull request in plain words (for example "Accept mesh telemetry only from the host each certificate names"), its description stating the `fleet-ingress` run (commit, host, date and cases passed).
Expected: nixbot green on `otel-collector-config`, `otel-envelope` and `nixos-magnetite`; each check below 536,870,912 B (command).
