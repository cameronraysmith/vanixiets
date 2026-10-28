### Task 2: Host table, certificates and the agent by role

Implements `tasks.md` 2.1–2.10 (design D1–D6, D9's notified-unit union, D10's R3.1 changes; FII `One host table declares the agent hosts and what each reports`, `The collection CA issues each agent host one certificate`, `The ingress receiver accepts only certificate holders on magnetite's ZeroTier address`, `Each agent exports by its role`, `pyrite's NVMe health is read by a loopback exporter`; the HMC, TSI, DCI and DC requirements named in those items).
This is the first part of pull request 1; Task 3 adds `otel-envelope` and `fleet-ingress` to the same pull request, which is opened only in Task 3 Step 6.
Every regulator comes first: R3.1's endpoint clause fails before the receiver exists (Step 1), the queue assertion fails before the exporters exist (Step 5), the per-host assertions are shown failing by overrides (Step 2), and the fixture leg fails before the rules take the host table (Step 9).
Every commit evaluates: the notified-unit assertion requires `otel-envelope` only from Task 3 Step 3, which defines the unit and adds it to the table in one commit.
cinnabar and pyrite have `collect = false` throughout this task, so their agent configuration is evaluated in the scratch tree of plan Global Constraints; nothing here deploys; the vars step (Step 4) only writes `vars/` in the working copy, and no command runs on pyrite.

**Files:**
- Create: `modules/lib/observability-hosts.nix`
- Modify: `modules/clan/services/otel-collector/flake-module.nix` (FM): `collectorCore` (`:58-82`), the agent fragment (`:85-339`), the ingress fragment (`:341-524`), the clan roles (`:526-572`)
- Modify: `modules/clan/services/otel-collector/schema.nix` (SC): add `fleetBytesPerMinute`, `otelcolKeep`, `smartctlKeep`, `systemdUnitsNotifierPattern` after `process.minBytes` (`:76`)
- Modify: `modules/clan/inventory/services/otel-collector.nix:1-14`
- Modify: `modules/nixos/devloop-collection.nix` (DC): `sourceReceivers` (`:363-368`), the `file_log/deploy-record` receiver (`:978-990`), `flake.lib.devloopCollection` (`:784-796`)
- Modify: `modules/checks/otel-collector-config.nix` (CC): inputs (`:22-100`), `failures` (`:206-403`), `mutants` (`:406-582`), the derivation (`:584-599`)
- Modify: `modules/checks/greptimedb-envelope.nix`: the view (`:511-513`), `usersFilesNonWorker` (`:534-539`), mutants (`:590-602`)
- Modify: `modules/nixos/fleet-alert/rules.nix:14-17,39-40,67-71`; `modules/nixos/fleet-alert.nix:573-576`; `modules/checks/fleet-alert.nix:52-54,622,625-637,945-960`
- Modify: `modules/machines/nixos/magnetite/default.nix:332-353` (the notified-unit list goes); `modules/machines/nixos/cinnabar/fleet-alert.nix:23-26` (`units` applies only while cinnabar's `collect` is false; `tokenFile` and the dead-man's `tokenFile` stay)
- Create (committed): `vars/shared/otel-ca/**`, `vars/per-machine/<host>/otel-cert/**` for the six hosts, and the reader entries `clan vars fix` writes for `otel-ca` and `ntfy-alerter`
- Create (git-ignored): `logs/s4-evidence/2.<n>-*.log`, `logs/s4-evidence/2.2-overrides.nix`, `logs/s4-evidence/2.4-overrides.nix`, and the scratch tree `$SCRATCH`

**Interfaces:**
- Consumes: Task 1's baselines (`logs/s4-evidence/1.2-baseline-*.log`) and its live reading of the collector's metric names; `flake.lib.hosts.magnetite.zt` (`modules/lib/hosts.nix:8`); `flake.modules.nixos.ntfy-alerter` (`modules/nixos/ntfy-alerter.nix:18-26`), the shared `ntfy-alerter` generator; the `nix-grpc-ca`/`nix-grpc-cert` generators (`modules/clan/services/nix-builders/flake-module.nix:106-148`); perInstance's `{ roles, machine }` arguments as `modules/clan/services/nix-builders/flake-module.nix:154` uses them.
- Produces: everything in plan.md's Interface contract marked Task 2, which Tasks 3 to 7 rely on: `flake.lib.observabilityHosts`; the options `vanixiets.otelCollector.{ingress,caFile,smartDevices}`; the generators and credentials; the collector names; SC's new keys; `flake.lib.devloopCollection.{keepAttributes,dropBody,deployRecordFile}`; `flake.lib.fleetAlertRules { lib, hosts ? … }`.

- [ ] **Step 1: R3.1's endpoint clause, seen failing (tasks.md 2.1)**

The two value sources, named before any mutant: A, the address clan's ZeroTier service assigned to magnetite, `vars/shared/zerotier-ip-magnetite-zerotier/ip/value`; B, magnetite's evaluated `receivers."otlp/mesh".protocols.http.endpoint`, which FM renders from `flake.lib.hosts.magnetite.zt`.
The certificate's IP SAN is not compared: it is rendered from the same registry attribute at issue time, and clan's `validation.subjectAltNames` regenerates it when the registry changes (design D10).
In CC's `input` add:

```nix
ztAddress = lib.trim (builtins.readFile "${self}/vars/shared/zerotier-ip-magnetite-zerotier/ip/value");
```

Replace the loopback clause (`:299-302`) with:

```nix
# Loopback, with exactly one exception: otlp/mesh on the address ZeroTier
# assigned to magnetite (ADR-003 item 9).
(check "R3.1: an endpoint off loopback other than otlp/mesh, or otlp/mesh not on magnetite's assigned address" (
  lib.all isLoopback (
    collectEndpoints (builtins.removeAttrs r [ "otlp/mesh" ])
    ++ collectEndpoints e ++ promTargets ++ [ i.node.listenAddress ]
  )
  && (r."otlp/mesh".protocols.http.endpoint or null) == "[${i.ztAddress}]:4318"
  && !(r."otlp/mesh".protocols ? grpc)
))
```

Add the mutants:

```nix
meshWildcard = onSettings { receivers."otlp/mesh".protocols.http.endpoint = "[::]:4318"; };
secondMeshReceiver = i: onSettings {
  receivers."otlp/second".protocols.http.endpoint = i.settings.receivers."otlp/mesh".protocols.http.endpoint;
} i;
ztAddressOther = i: i // { ztAddress = "fddb:4344:343b:14b9:399:930f:39db:40d3"; };
```

`receiverEndpointWildcard` stays and still fails, now on the loopback part.
Run:

```bash
jj st --no-pager >/dev/null
nix build .#checks.x86_64-linux.otel-collector-config 2>&1 | tee logs/s4-evidence/2.1-red-$(/bin/date -u +%Y%m%dT%H%M%SZ).log | tail -n 5
```

Expected: FAIL, at evaluation, on `R3.1: an endpoint off loopback other than otlp/mesh…`, because `otlp/mesh` does not exist yet (RED).

- [ ] **Step 2: The host table and the per-host assertions, seen failing (tasks.md 2.2)**

Create `modules/lib/observability-hosts.nix`:

```nix
# The agent hosts and what each reports (design D6). The inventory's agent
# machines, whether each collects, each host's notified units, its SMART
# devices and the alert rules' always-on hosts, expected hosts and
# SystemdUnitFailed exclusion are read from here. `collect = false` keeps
# the agent role off a host until its watched first deploy; a host joins
# alwaysOn only by an edit here when it becomes permanently provisioned
# (ADR-009 item 16).
{ ... }:
{
  flake.lib.observabilityHosts =
    let
      agent = extra: { collect = true; alwaysOn = false; smartDevices = [ ]; notifiedUnits = [ "opentelemetry-collector" ] ++ extra; };
    in
    {
      magnetite = agent [ <GR §4's 15 units other than opentelemetry-collector, in its order> ] // { alwaysOn = true; };
      cinnabar = agent [ "fleet-deadman" ] // { collect = false; alwaysOn = true; };
      pyrite = agent [ ] // { collect = false; smartDevices = [ "/dev/nvme0" ]; };
      electrum = agent [ ];
      galena = agent [ ];
      scheelite = agent [ ];
    };
}
```

Magnetite's 15 are `devloop-pg-grants`, `devloop-reconcile`, `fleet-alert`, `greptimedb`, `greptimedb-envelope`, `greptimedb-schema`, the four `zfs-assert-root-*-noautosnap` and the five `zfs-set-root-*` units, copied from `modules/machines/nixos/magnetite/default.nix:336-353` at the time of the step.
In SC, after `process.minBytes`, add `systemdUnitsNotifierPattern = "observability-notify@*.service";` with the comment that notifier instances are bounded by the host's notified units, not by the cap of 40 (ADR-004 as amended under charter v23).
In the agent fragment's `assertions`, add the three relations; the value sources are the host's evaluated `systemd.services` against the notified-unit list (set from the table in Step 8), SC's `systemdUnits`, and SC's `ownerAliases`:

```nix
let
  services = config.systemd.services;
  notified = config.services.observability-notify.units;
  unitRegex = p: builtins.replaceStrings [ "." "*" ] [ "\\." ".*" ] p;
  capped = builtins.filter (n:
    builtins.match (unitRegex schema.systemdUnitsNotifierPattern) "${n}.service" == null
    && lib.any (p: builtins.match (unitRegex p) "${n}.service" != null) schema.systemdUnits
  ) (builtins.attrNames services);
  owners = lib.concatMap (n: let m = builtins.match "omnigent-host-(.+)" n; in lib.optional (m != null) (builtins.head m)) (builtins.attrNames services);
in [
  { assertion = lib.all (u: (services.${u}.serviceConfig or { }) ? ExecStart) notified
      && builtins.elem "opentelemetry-collector" notified;
    message = "otel-collector agent: ${hostName}'s notified units ${builtins.toJSON notified} must be services with an ExecStart and include opentelemetry-collector (design D6)."; }
  { assertion = builtins.length capped <= 40;
    message = "otel-collector agent: ${toString (builtins.length capped)} of ${hostName}'s services match the unit allow-list, above ADR-004's 40: ${builtins.toJSON capped}"; }
  { assertion = lib.all (o: schema.ownerAliases ? ${o}) owners
      && lib.all (a: lib.all (o: !(lib.hasInfix o a)) owners) (builtins.attrValues schema.ownerAliases);
    message = "otel-collector agent: every omnigent-host-<owner> service on ${hostName} needs an alias in ownerAliases that does not contain an owner's name; owners ${builtins.toJSON owners}"; }
]
```

Remove from CC the clauses `R3.1: more than 40 allow-listed units`, `R3.1: omnigent-host owner without alias` and `R3.1: an alias carries an owner name` (`:309-321`), the binding `maxUnits` (`:46-47`) and the mutants `systemdUnitsOverCap` and `ownerWithoutAlias`; keep `builtins.elem "transform/omnigent-alias" pipelines."metrics/host".processors` as its own clause `R3.1: the alias transform is not in the host pipeline`, whose mutant `aliasTransformUnwired` removes it.
Run:

```bash
jj st --no-pager >/dev/null
nix eval --json .#.lib.observabilityHosts | jq -c 'to_entries[] | [.key, .value.collect, .value.alwaysOn, (.value.smartDevices|length), (.value.notifiedUnits|length)]'
nix eval --raw .#nixosConfigurations.magnetite.config.system.build.toplevel.drvPath 2>&1 | tail -n 3
```

Expected: six lines, `["magnetite",true,true,0,16]`, `["cinnabar",false,true,0,2]`, `["pyrite",false,false,1,1]` and `true,false,0,1` for electrum, galena and scheelite; magnetite evaluates (evaluation).
After Step 9 has wired the notified units from the table, create `logs/s4-evidence/2.2-overrides.nix` with three `extendModules` evaluations, cinnabar adding `"zfs-set-root-typo-quota"` to `services.observability-notify.units`, pyrite with `systemd.services = lib.genAttrs (map (n: "zfs-set-cap-${toString n}") (lib.range 1 41)) (_: { script = "true"; })` (41 services the `zfs-set-*.service` pattern matches), and cinnabar with `systemd.services.omnigent-host-nobody.script = "true"`, and run it in the scratch tree:

```bash
jj st --no-pager >/dev/null
SCRATCH=$REPO/../vanixiets-worktrees/scratch
git -C $REPO worktree add --detach $SCRATCH "$(jj log --no-graph -r @ -T commit_id)"
# in $SCRATCH, set collect = true for cinnabar and pyrite in modules/lib/observability-hosts.nix
L=$REPO/logs/s4-evidence/2.2-assertions-$(/bin/date -u +%Y%m%dT%H%M%SZ).log
cd $SCRATCH
for h in cinnabar pyrite; do nix eval --raw ".#nixosConfigurations.$h.config.system.build.toplevel.drvPath"; echo; done 2>&1 | tee "$L"
for o in cinnabarTypo pyrite41 cinnabarNobody; do echo "== $o"
  nix eval --impure --raw --expr "(import $REPO/logs/s4-evidence/2.2-overrides.nix (builtins.getFlake (toString ./.))).$o" 2>&1 | grep -o 'otel-collector agent[^(]*' | head -n 1
done 2>&1 | tee -a "$L"
cd $REPO && git worktree remove --force $SCRATCH
```

Expected: two drvPaths; each override prints its own assertion's message, the notified units, `41 of pyrite's services match the unit allow-list` and the alias (negative controls).

- [ ] **Step 3: The certificate generators (tasks.md 2.3, code)**

In the clan agent role, `perInstance = { roles, machine, ... }:`, add to `nixosModule` the generators, the credentials and the CA option:

```nix
{ config, lib, pkgs, ... }:
let
  # Static data, so it can select imports without evaluating the host (design D6).
  collect = flakeLib.observabilityHosts.${machine.name}.collect;
  isIngress = roles.ingress.machines ? ${machine.name};
  sans = lib.optionalString isIngress "IP:${flakeLib.hosts.magnetite.zt},DNS:magnetite.zt";
  usage = if isIngress then "serverAuth,clientAuth" else "clientAuth";
  restart = lib.optional collect "opentelemetry-collector.service";
  gens = config.clan.core.vars.generators;
in {
  # Declared on every agent host, so one vars step covers all six; on a host
  # that does not collect yet they are uploaded files no unit reads.
  imports = [ nixosModules.ntfy-alerter ] ++ lib.optional collect nixosModules.otel-collector-agent;
  clan.core.vars.generators = {
    # Shared: every agent trusts one CA; its key signs at generation time
    # only and is never deployed (ADR-003 Q2; design D1).
    otel-ca = {
      share = true;
      files."ca.key".deploy = false;
      files."ca.crt".secret = false;
      runtimeInputs = [ pkgs.openssl ];
      script = ''
        openssl genpkey -algorithm EC -pkeyopt ec_paramgen_curve:P-256 -out "$out"/ca.key
        openssl req -x509 -new -key "$out"/ca.key -sha256 -days 3650 -subj "/CN=otel-ca" \
          -addext "basicConstraints=critical,CA:TRUE" \
          -addext "keyUsage=critical,keyCertSign,cRLSign" \
          -addext "subjectKeyIdentifier=hash" -out "$out"/ca.crt
      '';
    };
    # The SANs and the usage enter validation, so moving a host into the
    # ingress role regenerates its certificate (design D1).
    otel-cert = {
      dependencies = [ "otel-ca" ];
      files."key.pem".restartUnits = restart;
      files."cert.pem" = { secret = false; restartUnits = restart; };
      validation = { subjectAltNames = sans; extendedKeyUsage = usage; };
      runtimeInputs = [ pkgs.openssl ];
      script = ''
        openssl genpkey -algorithm EC -pkeyopt ec_paramgen_curve:P-256 -out "$out"/key.pem
        openssl req -new -key "$out"/key.pem -subj "/CN=${machine.name}" -out cert.csr
        {
          echo "basicConstraints=critical,CA:FALSE"
          echo "keyUsage=critical,digitalSignature"
          echo "extendedKeyUsage=${usage}"
          ${lib.optionalString isIngress ''echo "subjectAltName=${sans}"''}
        } > cert.ext
        openssl x509 -req -in cert.csr -CA "$in"/otel-ca/ca.crt -CAkey "$in"/otel-ca/ca.key \
          -set_serial "0x$(openssl rand -hex 16)" -sha256 -days 3650 -extfile cert.ext -out "$out"/cert.pem
      '';
    };
  };
  config = lib.mkIf collect {
    vanixiets.otelCollector.caFile = pkgs.writeText "otel-ca.crt" gens.otel-ca.files."ca.crt".value;
    systemd.services.opentelemetry-collector.serviceConfig.LoadCredential = [
      "otel-cert:${gens.otel-cert.files."cert.pem".path}"
      "otel-key:${gens.otel-cert.files."key.pem".path}"
    ];
  };
}
```

`flakeLib` is FM's outer `config.flake.lib`, bound in FM's top `let` beside `nixosModules`, so it is not shadowed by the NixOS `config`.
This module replaces the role's existing `nixosModule.imports = [ nixosModules.otel-collector-agent ]` (FM `:536-540`); with `imports` and `config` both present, the generator attrset above sits under `config` as well (`config = lib.mkMerge [ { clan.core.vars.generators = …; } (lib.mkIf collect { … }) ]`).
`ca.crt` carries no `restartUnits`: the CA reaches the collector as a store path, so a new CA changes the configuration and restarts it (design D1).
The two credentials load on magnetite too, where the ingress receiver uses them.
Declare in `collectorCore` the three options of the Interface contract, with descriptions; `caFile` is `nullOr path`, default `null`.
Run:

```bash
jj st --no-pager >/dev/null
nix eval --json .#nixosConfigurations.cinnabar.config.clan.core.vars.generators.otel-cert.validation
nix eval --json .#nixosConfigurations.magnetite.config.clan.core.vars.generators.otel-cert.validation
```

Expected: `{"extendedKeyUsage":"clientAuth","subjectAltNames":""}` and `{"extendedKeyUsage":"serverAuth,clientAuth","subjectAltNames":"IP:fddb:4344:343b:14b9:399:930f:39db:40d2,DNS:magnetite.zt"}` (evaluation).

- [ ] **Step 4: The vars step (tasks.md 2.3, vars)**

First the inventory, so the six hosts are agent machines; replace `modules/clan/inventory/services/otel-collector.nix` with:

```nix
# Collector roles. Every host of flake.lib.observabilityHosts runs the agent;
# magnetite also runs the ingress, joined in-process by `forward`.
{ config, lib, ... }:
{
  clan.inventory.instances.otel-collector = {
    module = { name = "otel-collector"; input = "self"; };
    roles.agent.machines = lib.mapAttrs (_: _: { }) config.flake.lib.observabilityHosts;
    roles.ingress.machines.magnetite = { };
  };
}
```

Step 3's module already imports `nixosModules.ntfy-alerter` on every agent host, so each declares the shared `ntfy-alerter` generator whatever its `collect`.
Then, recording hashes around every command (`h` records the decrypted `ntfy-alerter` token's sha256 and, once it exists, `otel-ca`'s certificate's, and stops on any change):

```bash
set -euo pipefail
L=logs/s4-evidence/2.3-vars-$(/bin/date -u +%Y%m%dT%H%M%SZ).log
# The token is compared by its decrypted value: `clan vars fix` re-encrypts
# the file for a new reader, so the encrypted file's own hash changes by design.
tok() { clan vars get magnetite ntfy-alerter/token | sha256sum | cut -d' ' -f1; }
T0=$(tok); C0=""
h() {
  t=$(tok); echo "== $1 token=$t" | tee -a "$L"
  [ "$t" = "$T0" ] || { echo "STOP: the ntfy-alerter token changed at $1" | tee -a "$L"; return 1; }
  if [ -e vars/shared/otel-ca/ca.crt/value ]; then
    c=$(sha256sum < vars/shared/otel-ca/ca.crt/value | cut -d' ' -f1); echo "   otel-ca=$c" | tee -a "$L"
    [ -n "$C0" ] || C0=$c
    [ "$c" = "$C0" ] || { echo "STOP: otel-ca's certificate changed at $1" | tee -a "$L"; return 1; }
  fi
}
jj st --no-pager >/dev/null
h before
CLAN_NO_COMMIT=1 clan vars generate magnetite --generator otel-cert 2>&1 | tee -a "$L"
h magnetite
for host in cinnabar pyrite electrum galena scheelite; do
  CLAN_NO_COMMIT=1 clan vars fix "$host" --generator otel-ca 2>&1 | tee -a "$L"; h "$host-fix-ca"
  CLAN_NO_COMMIT=1 clan vars generate "$host" --generator otel-cert 2>&1 | tee -a "$L"; h "$host-cert"
done
for host in pyrite electrum galena scheelite; do
  CLAN_NO_COMMIT=1 clan vars fix "$host" --generator ntfy-alerter 2>&1 | tee -a "$L"; h "$host-fix-ntfy"
done
grep -c '^== ' "$L"
```

Expected: 16 `==` records, every `token=` equal, every `otel-ca=` from `magnetite` on equal, and no `STOP` line; a `STOP` ends the script under `set -e`, and `vars/` is restored from the working copy's parent (`jj restore --from @- vars/`) before the cause is investigated.
The token value is hashed in a pipe and never printed; `clan vars get` decrypts with the operator's key on stibnite.
`otel-ca` is created exactly once, by the first command, as the missing dependency of magnetite's `otel-cert`: no `otel-ca` value exists yet, so nothing shared is overwritten, which is what the rule against `clan vars generate` on a shared generator protects; from then on `otel-ca` only gains readers through `clan vars fix`, and the `otel-ca=` hash proves it is never regenerated.
`vars/shared/ntfy-alerter/token/machines/` lists pyrite, electrum, galena and scheelite beside cinnabar and magnetite afterwards.
Then verify the issued certificates (tasks.md 2.3's verify):

```bash
for host in magnetite cinnabar pyrite electrum galena scheelite; do
  c=vars/per-machine/$host/otel-cert/cert.pem/value
  echo "== $host"; openssl x509 -noout -subject -dates -ext subjectAltName,extendedKeyUsage,keyUsage -in "$c"
  openssl verify -CAfile vars/shared/otel-ca/ca.crt/value "$c"
done 2>&1 | tee -a "$L"
```

Expected: each `subject=CN=<host>`, `notAfter` about 3650 days on, `<path>: OK`; magnetite shows `IP Address:` with the address, `DNS:magnetite.zt`, `TLS Web Server Authentication, TLS Web Client Authentication`; the others `TLS Web Client Authentication` and no SAN extension.
Then rerun Step 1's build, which still fails, now only on the missing `otlp/mesh` endpoint (RED).

- [ ] **Step 5: The role switch, the exporters and the queue assertion (tasks.md 2.4)**

First the regulator.
Move `fleetBytesPerMinute = 256000;` with its comment from CC (`:26-31`) to SC beside `process.minBytes`, and make CC read `i.schema.fleetBytesPerMinute`.
In the agent fragment, under `lib.mkIf (!config.vanixiets.otelCollector.ingress)`, add the assertion; its two value sources are the exporters' queue literals in FM and SC's rate assumption, and `MemoryMax` against the limiter, each defined in its own place:

```nix
let
  e = config.services.opentelemetry-collector.settings.exporters;
  agentExporters = [ "otlp_http/ingress" "otlp_http/ingress-logs" ];
  q = n: e.${n}.sending_queue or { };
  memMax = builtins.match "([0-9]+)M" (config.systemd.services.opentelemetry-collector.serviceConfig.MemoryMax or "");
  limit = config.services.opentelemetry-collector.settings.processors.memory_limiter.limit_mib or 0;
in {
  assertion =
    lib.all (n: (q n).storage or null == "file_storage" && (q n).sizer or null == "bytes"
                && (e.${n}.retry_on_failure.max_elapsed_time or null) == "0s") agentExporters
    && ((q "otlp_http/ingress").queue_size or 0) >= 24 * 60 * schema.fleetBytesPerMinute
    && lib.foldl' (s: n: s + ((q n).queue_size or 0)) 0 agentExporters < mib 512
    && memMax != null && limit < lib.toInt (builtins.head memMax);
  message = "otel-collector agent on ${hostName}: both ingress exporters must queue in file_storage by bytes with unlimited retry, the metrics queue must hold 24 h at fleetBytesPerMinute, the queues must sum below 512 MiB, and the limiter must be below MemoryMax (ADR-003 envelope; design D2).";
}
```

Run electrum's evaluation (`collect = true`, no ingress) and see it fail on this assertion (RED).
Then the implementation.
Move `extensions.file_storage` and its `service.extensions` entry from the ingress fragment (`:387-390`, `:442-445`) to `collectorCore`, unchanged (directory `/var/lib/opentelemetry-collector/queue`).
In the ingress fragment set `vanixiets.otelCollector.ingress = true;`.
Make the agent's pipelines end in `agentExport.metrics` and `agentExport.logs`, which are `[ "forward" ]` on the ingress host and `[ "otlp_http/ingress" ]` and `[ "otlp_http/ingress-logs" ]` elsewhere, and add elsewhere:

```nix
let
  credentials = "/run/credentials/opentelemetry-collector.service";
  ingressExporter = queueSize: {
    endpoint = "https://[${flakeLib.hosts.magnetite.zt}]:4318";
    tls = {
      ca_file = config.vanixiets.otelCollector.caFile;
      cert_file = "${credentials}/otel-cert";
      key_file = "${credentials}/otel-key";
      min_version = "1.3";
    };
    sending_queue = { storage = "file_storage"; sizer = "bytes"; queue_size = queueSize; };
    retry_on_failure = { enabled = true; max_interval = "60s"; max_elapsed_time = "0s"; };
  };
in {
  services.opentelemetry-collector.settings = {
    processors.memory_limiter = { limit_mib = lib.mkForce 150; spike_limit_mib = 30; };
    exporters."otlp_http/ingress" = ingressExporter (mib 400);
    exporters."otlp_http/ingress-logs" = ingressExporter (mib 16);
  };
  systemd.services.opentelemetry-collector.serviceConfig.MemoryMax = "256M";
}
```

The `MemoryMax = "512M"` and `OOMScoreAdjust = 300` of the ingress fragment (`:509-515`) stay on the ingress host only.
Create `logs/s4-evidence/2.4-overrides.nix`, which takes the flake and returns two `extendModules` evaluations, cinnabar with `services.opentelemetry-collector.settings.exporters."otlp_http/ingress".sending_queue.queue_size = lib.mkForce (64 * 1024 * 1024)` and pyrite with `processors.memory_limiter.limit_mib = lib.mkForce 300`, each `config.system.build.toplevel.drvPath`; run the block below in the scratch tree (created as in Step 2, `cd $SCRATCH`, `L` and the overrides file under `$REPO/logs/s4-evidence/`), then remove it.
Run:

```bash
jj st --no-pager >/dev/null
L=logs/s4-evidence/2.4-queue-$(/bin/date -u +%Y%m%dT%H%M%SZ).log
nix eval --json .#nixosConfigurations.cinnabar.config.services.opentelemetry-collector.settings.exporters 2>&1 | jq -c 'with_entries(.value |= {endpoint, queue: .sending_queue, retry: .retry_on_failure.max_elapsed_time, tls: (.tls|keys)})' | tee "$L"
nix eval --raw .#nixosConfigurations.cinnabar.config.systemd.services.opentelemetry-collector.serviceConfig.MemoryMax | tee -a "$L"; echo
nix eval --json .#nixosConfigurations.magnetite.config.services.opentelemetry-collector.settings.service.pipelines --apply 'p: builtins.mapAttrs (_: v: v.exporters) p' | tee -a "$L"
for o in cinnabarQueue64 pyriteLimiter300; do nix eval --impure --raw --expr "(import $REPO/logs/s4-evidence/2.4-overrides.nix (builtins.getFlake (toString ./.))).$o" 2>&1 | grep -o 'otel-collector agent on [a-z]*: both ingress exporters[^.]*' | tee -a "$L"; done
```

Expected: cinnabar's two exporters with the endpoint `https://[fddb:4344:343b:14b9:399:930f:39db:40d2]:4318`, queues 419430400 and 16777216, retry `0s`, tls keys `ca_file cert_file key_file min_version`; `256M`; magnetite's agent pipelines still `["forward"]`; each override prints its assertion message (negative control).

- [ ] **Step 6: The ingress receiver on ZeroTier (tasks.md 2.5)**

In the ingress fragment add the receiver and feed both ingress pipelines with it:

```nix
receivers."otlp/mesh".protocols.http = {
  endpoint = "[${flakeLib.hosts.magnetite.zt}]:4318";
  tls = {
    cert_file = "${credentialsDir}/otel-cert";
    key_file = "${credentialsDir}/otel-key";
    client_ca_file = config.vanixiets.otelCollector.caFile;
    min_version = "1.3";
  };
};
service.pipelines."metrics/ingress".receivers = [ "forward" "otlp/mesh" ];
# and, inside lib.mkIf devloopLogs:
service.pipelines."logs/ingress".receivers = [ "forward" "otlp/mesh" ];
```

In the clan ingress role add `networking.firewall.interfaces."zt+".allowedTCPPorts = [ 4318 ];` with the comment that magnetite's `net.ipv6.ip_nonlocal_bind = 1` (`modules/machines/nixos/magnetite/default.nix:836-838`) lets the bind succeed before zerotierone holds the address.
In CC, change `isOtlpReceiver`'s use in the logs clause so `otlp/mesh` is admitted and every other `otlp` receiver is not, with the clause renamed `R3.1: a logs pipeline takes an OTLP receiver other than otlp/mesh`; its existing mutant adding the local receiver to a logs pipeline is renamed `otlpInLogsPipeline` if it is not already.
Run:

```bash
jj st --no-pager >/dev/null
nix build .#checks.x86_64-linux.otel-collector-config -L 2>&1 | tee logs/s4-evidence/2.5-r31-$(/bin/date -u +%Y%m%dT%H%M%SZ).log | grep -E '^(ok|FAIL)'
nix eval --json .#nixosConfigurations.magnetite.config.networking.firewall.interfaces --apply 'i: builtins.mapAttrs (_: v: v.allowedTCPPorts or [ ]) i'
NIX_SHOW_STATS=1 NIX_SHOW_STATS_PATH=/tmp/otel-collector-config-stats.json nix eval --option eval-cache false --raw .#.checks.x86_64-linux.otel-collector-config.drvPath >/dev/null && jq '.gc.totalBytes, .cpuTime' /tmp/otel-collector-config-stats.json
```

Expected: the build passes, and the evaluation-time mutants `meshWildcard`, `secondMeshReceiver`, `ztAddressOther`, `receiverEndpointWildcard` and `otlpInLogsPipeline` are all rejected (the check's `assert` would fail otherwise); `"zt+": [4318]` and no other interface with 4318; the cost below 536,870,912, recorded beside 1.2's; above it, stop and apply design D10's remedies.

- [ ] **Step 7: Scrapes, file systems, self-telemetry and SMART (tasks.md 2.6)**

The filesystem scraper's mountpoints are read from the host's own `fileSystems` in one place, so no assertion restates them (design D4); the strict match type is what keeps container mounts under `/var/lib/docker` out.
In the agent fragment's `let`, bind:

```nix
zfsMounts = lib.sort lib.lessThan (map (fs: fs.mountPoint)
  (builtins.filter (fs: fs.fsType == "zfs") (builtins.attrValues config.fileSystems)));
```

and add to `host_metrics/memory.scrapers`:

```nix
filesystem = {
  include_mount_points = { match_type = "strict"; mount_points = zfsMounts; };
  metrics = {
    "system.filesystem.usage".enabled = true;
    "system.filesystem.inodes.usage".enabled = false;
    "system.filesystem.utilization".enabled = false;
  };
};
```

Wrap the gitea, niks3, nixbot and greptimedb scrapes (`:253-256`) as `lib.optional config.services.<name>.enable (scrape …)`, `greptimedb` reading `config.services.greptimedb.enable or false`, because only magnetite imports that module; do the same for `niks3` and `nixbot` with `or false`.
Add the self-telemetry scrape:

```nix
(scrape "otelcol" "127.0.0.1:8888" {
  metric_relabel_configs = [
    { source_labels = [ "__name__" ]; regex = lib.concatStringsSep "|" schema.otelcolKeep; action = "keep"; }
    # A new identifier at every collector start (ADR-004's process-identifier ban).
    { regex = "service_instance_id"; action = "labeldrop"; }
  ];
})
```

with SC's `otelcolKeep` the eight names of design D4, and `smartctlKeep` the eight names of ADR-004:91.
The counters carry no `_total` suffix at 0.155.0 (read live on magnetite on 2026-10-29, confirmed in Task 1 Step 3), so the keep regex is the names joined with `|`.
Add the SMART exporter under `lib.mkIf (config.vanixiets.otelCollector.smartDevices != [ ])`:

```nix
services.prometheus.exporters.smartctl = {
  enable = true;
  listenAddress = "127.0.0.1";
  port = 9633;
  devices = config.vanixiets.otelCollector.smartDevices;
  openFirewall = false;
};
systemd.services.prometheus-smartctl-exporter.serviceConfig = {
  MemoryMax = "64M";
  # The module's udev rule grants this ACL only on an `add` event, which a
  # switch does not replay (GR §5; design D4); `+` runs it privileged.
  ExecStartPre = map (d: "+${pkgs.acl}/bin/setfacl -m g:smartctl-exporter-access:rw ${d}") config.vanixiets.otelCollector.smartDevices;
};
services.opentelemetry-collector.settings.receivers.prometheus.config.scrape_configs = [
  (scrape "smartctl" "127.0.0.1:9633" {
    metric_relabel_configs = [ { source_labels = [ "__name__" ]; regex = lib.concatStringsSep "|" schema.smartctlKeep; action = "keep"; } ];
  })
];
```

and extend the firewall assertion to `!(config.services.prometheus.exporters.node.openFirewall || config.services.prometheus.exporters.smartctl.openFirewall)`.
In the clan agent role's `lib.mkIf collect` block (Step 3) set `vanixiets.otelCollector.smartDevices = flakeLib.observabilityHosts.${machine.name}.smartDevices;`.
Run:

```bash
jj st --no-pager >/dev/null
L=$REPO/logs/s4-evidence/2.6-scrapes-$(/bin/date -u +%Y%m%dT%H%M%SZ).log
jobs='c: map (j: j.job_name) c.services.opentelemetry-collector.settings.receivers.prometheus.config.scrape_configs'
# magnetite in $REPO; cinnabar and pyrite in the scratch tree of Step 2, where their collect is true
for h in magnetite cinnabar pyrite; do echo "== $h"; d=$REPO; [ $h = magnetite ] || d=$SCRATCH
  ( cd "$d"; nix eval --json ".#nixosConfigurations.$h.config" --apply "$jobs"
    nix eval --json ".#nixosConfigurations.$h.config.services.opentelemetry-collector.settings.receivers.\"host_metrics/memory\".scrapers.filesystem.include_mount_points.mount_points"
    nix eval --json ".#nixosConfigurations.$h.config.fileSystems" --apply 'f: map (x: x.mountPoint) (builtins.filter (x: x.fsType == "zfs") (builtins.attrValues f))' ); done 2>&1 | tee "$L"
(cd $SCRATCH && nix eval --json .#nixosConfigurations.pyrite.config.systemd.services.prometheus-smartctl-exporter.serviceConfig.ExecStartPre) | tee -a "$L"
```

Expected: magnetite's jobs equal `node gitea niks3 nixbot greptimedb otelcol` (the `main@origin` list of Task 1 plus `otelcol`), cinnabar's and pyrite's `node otelcol`, pyrite's also `smartctl`; each host's scraper mountpoints equal its ZFS `fileSystems`, `["/","/home","/nix"]` on cinnabar and pyrite and seven on magnetite (design Context), recorded as evidence; one `+/nix/store/…-acl-…/bin/setfacl -m g:smartctl-exporter-access:rw /dev/nvme0`.
The zerotierone job stays in `prometheus/zerotier` (FM `:313-336`), so it is not in the list above.

- [ ] **Step 8: The deploy-record receiver moves into the agent (tasks.md 2.7)**

Record the current values first, at `origin/main` in `$DEPLOY` (after `git -C $REPO fetch origin && git -C $DEPLOY checkout --detach origin/main`), writing to `$REPO/logs/s4-evidence/`:

```bash
for a in 'receivers."file_log/deploy-record"' 'receivers."sqlquery/ci_attribute".queries' 'receivers."sqlquery/ci_build".queries'; do
  nix eval --json ".#nixosConfigurations.magnetite.config.services.opentelemetry-collector.settings.$a" | sha256sum
done | tee logs/s4-evidence/2.7-before-$(/bin/date -u +%Y%m%dT%H%M%SZ).log
```

In DC, export through `flake.lib.devloopCollection` the existing `keepAttributes`, `dropBody` and `deployRecordFile`; remove `deploy_record` from `sourceReceivers` (`:367`) and the `file_log/deploy-record` receiver (`:978-990`), so DC's processors and pipelines no longer render it.
In the agent fragment add, reading `flakeLib.devloopCollection` and `schema.devloop.tables.deploy_record`, the receiver with the same settings (`include = [ deployRecordFile ]`, `start_at = "beginning"`, `storage = "file_storage"`, the same `json_parser` operator, `keepAttributes (map (c: c.name) tables.deploy_record.columns)`, `dropBody`), the processor `resource/devloop-deploy_record` setting `vanixiets.database = devloop`, `vanixiets.table = deploy_record` and `host.name`, and the pipeline `logs/devloop-deploy_record` with `memory_limiter` and that processor, exporting to `agentExport.logs`.
Run the same three evaluations in the working copy and `diff` the hashes; then:

```bash
nix eval --json '.#nixosConfigurations.electrum.config.services.opentelemetry-collector.settings.service.pipelines."logs/devloop-deploy_record".exporters'
nix eval --json '.#nixosConfigurations.magnetite.config.services.opentelemetry-collector.settings.service.pipelines."logs/devloop-deploy_record".exporters'
```

Expected: the three hashes equal (the receiver's id and settings and both query texts unchanged, so magnetite's stored offset and both cursors carry over); `["otlp_http/ingress-logs"]` and `["forward"]` (evaluation).

- [ ] **Step 9: Notified units from the table, and the alert rules' union (tasks.md 2.8)**

First the fixture leg.
In `modules/checks/fleet-alert.nix`, replace `:52-54` with `hosts = self.lib.observabilityHosts; notifiedUnits = lib.unique (lib.concatMap (h: h.notifiedUnits) (builtins.attrValues hosts)); rules = self.lib.fleetAlertRules { inherit lib hosts; };`, so `exclusionLeg` (`:622-637`) replays a failed state for every unit of the union, `fleet-deadman` included.
Add `twoHostExclusionLeg`, whose rules come from a two-host table `{ a = { collect = true; alwaysOn = true; notifiedUnits = [ "unit-a" ]; smartDevices = [ ]; }; b = { collect = true; alwaysOn = false; notifiedUnits = [ "unit-b" ]; smartDevices = [ ]; }; }` and whose fixture replays `systemd_unit_state{systemd_unit_active_state="failed"} == 1` for `unit-a.service` on host `b`, `unit-b.service` on host `a` and `nginx.service` on `a`, expecting exactly one `[FIRING] SystemdUnitFailed a`, for nginx; add it to `legs`.
Build and see it fail at evaluation, because `fleetAlertRules` takes no `hosts` (RED).
Then in `modules/nixos/fleet-alert/rules.nix` change the signature to `{ lib, hosts ? config.flake.lib.observabilityHosts }:` (the file's outer arguments become `{ config, ... }`), set `units = lib.unique (lib.naturalSort (lib.concatMap (h: h.notifiedUnits) (builtins.attrValues hosts)));`, and replace the header comment's `:14-17` with one saying the exclusion is the union of every host's notified units (design D9).
In `modules/nixos/fleet-alert.nix:573-576` call `flakeLib.fleetAlertRules { inherit lib; }`.
In the clan agent role's `lib.mkIf collect` block (Step 3) set:

```nix
services.observability-notify = {
  units = flakeLib.observabilityHosts.${machine.name}.notifiedUnits;
  tokenFile = config.clan.core.vars.generators.ntfy-alerter.files.token.path;
};
```

and remove `services.observability-notify.units = [ "opentelemetry-collector" ];` from the agent fragment (`:298`), the list at `modules/machines/nixos/magnetite/default.nix:332-353` with its comment, and magnetite's `services.observability-notify.tokenFile` (`:808-809`).
In cinnabar's `fleet-alert.nix` (`:23-26`) keep `tokenFile` (an equal definition merges with the role's) and make the list `units = lib.mkIf (!config.flake.lib.observabilityHosts.cinnabar.collect) [ "fleet-deadman" ];`, reading the flake-parts `config` of the file's outer arguments (`{ config, ... }:` replacing `{ ... }:`, the NixOS module's own argument renamed `nixosArgs`), so `fleet-deadman` stays notified exactly once both before and after cinnabar's flag flips, and the flip stays a one-line change; update the header comment, which says cinnabar runs no collector, to say it runs one once its `collect` is true.
Run:

```bash
jj st --no-pager >/dev/null
L=logs/s4-evidence/2.8-notify-$(/bin/date -u +%Y%m%dT%H%M%SZ).log
for h in magnetite cinnabar pyrite electrum galena scheelite; do
  printf '%s ' "$h"; nix eval --json ".#nixosConfigurations.$h.config.services.observability-notify" --apply 'n: { inherit (n) units; token = n.tokenFile != null; }'
done 2>&1 | tee "$L"
# cinnabar and pyrite must evaluate to what they run today
for h in cinnabar pyrite; do for a in services.observability-notify.units systemd.services.zerotierone.serviceConfig.ExecStartPre; do
  diff <(nix eval --json ".#nixosConfigurations.$h.config.$a" 2>&1) <(cd $DEPLOY && nix eval --json ".#nixosConfigurations.$h.config.$a" 2>&1) && echo "$h $a unchanged"
done; done 2>&1 | tee -a "$L"
nix eval --json .#.lib.observabilityHosts --apply 'h: builtins.mapAttrs (_: v: v.notifiedUnits) h' | tee -a "$L"
nix build .#checks.x86_64-linux.fleet-alert -L 2>&1 | tee -a "$L" | grep -E 'exclusion|twoHost|FAIL'
```

Expected: magnetite's, electrum's, galena's and scheelite's `units` equal their table rows and `token` true; cinnabar's `["fleet-deadman"]` as at `origin/main`, and pyrite's evaluation error `does not provide attribute … observability-notify` as at `origin/main` (pyrite imports no notifier while it does not collect); each `unchanged` line printed (`$DEPLOY` is at `origin/main`); the build passes, with the exclusion leg and `twoHostExclusionLeg` passing; cost recorded with the method of plan Global Constraints.
Then run Step 2's overrides in the scratch tree.

- [ ] **Step 10: R8.2 covers the collection key (tasks.md 2.9)**

The two sources: the evaluated attributes of magnetite's `otel-cert` `key.pem` file, and magnetite's enabled omnigent workers (`:29-31`).
In `modules/checks/greptimedb-envelope.nix`, add to the view `otelKey = magnetite.clan.core.vars.generators.otel-cert.files."key.pem";`, extend `usersFilesNonWorker` with `&& v.otelKey.mode == "0400" && !(builtins.elem v.otelKey.owner workerUsers)`, and add the mutant:

```nix
workerOwnsOtelKey = {
  clause = "usersFilesNonWorker";
  apply = v: v // { otelKey = v.otelKey // { owner = builtins.head workerUsers; }; };
};
```

Run `nix build .#checks.x86_64-linux.greptimedb-envelope -L 2>&1 | tee logs/s4-evidence/2.9-r82-<ts>.log | grep -E 'workerOwnsOtelKey|FAIL'` and record its cost.
Expected: the build passes and the log shows `workerOwnsOtelKey` rejected; the cost is below 0.38 GiB (design D10).

- [ ] **Step 11: Evaluate every agent host (tasks.md 2.10)**

After Task 3 Step 3, run, then repeat the first loop for cinnabar and pyrite in the scratch tree:

```bash
L=logs/s4-evidence/2.10-hosts-$(/bin/date -u +%Y%m%dT%H%M%SZ).log
for h in magnetite cinnabar pyrite electrum galena scheelite; do
  printf '%s ' "$h"; nix eval --raw ".#nixosConfigurations.$h.config.system.build.toplevel.drvPath"; echo
done 2>&1 | tee "$L"
for c in nixos-magnetite nixos-cinnabar nixos-pyrite nixos-electrum nixos-galena; do
  NIX_SHOW_STATS=1 NIX_SHOW_STATS_PATH=/tmp/$c.json nix eval --option eval-cache false --raw ".#.checks.x86_64-linux.$c.drvPath" >/dev/null
  printf '%s %s\n' "$c" "$(jq '.gc.totalBytes' /tmp/$c.json)"
done 2>&1 | tee -a "$L"
```

Expected: six drvPaths, two more from the scratch tree, and five costs beside 1.2's; machine toplevels are outside the 0.5 GiB budget (design D10), and scheelite, which has no machine check, is evaluated only here (evaluation).

- [ ] **Step 12: Commit**

Commit the work of Steps 1 to 11 as changes off `main@origin` after `nix fmt`, with messages in plain words, for example "Give every NixOS host a collection certificate and run the collector agent on it" and "Accept certificate holders on magnetite's ZeroTier address and read pyrite's NVMe health"; the vars written in Step 4 are in the first.
