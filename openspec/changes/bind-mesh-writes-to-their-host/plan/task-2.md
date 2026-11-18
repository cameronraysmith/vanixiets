### Task 2: Identity and addresses

Implements `tasks.md` 2.1–2.5 (design D2, D4, D7; FII `One host table declares the agent hosts and what each reports`, `The collection CA issues each agent host one certificate`, `magnetite pins each collecting host's neighbour entry`).
It is pull request 1; it starts only after Task 1 Step 3 passed.

**Files:**
- Modify: `modules/checks/otel-collector-config.nix`, `modules/clan/services/otel-collector/flake-module.nix` (the `otel-cert` generator and the agent role's host-name assertion)
- Create: `modules/lib/zerotier-mac.nix`, `modules/checks/otel-collector-config/zerotier-macs.json`
- Regenerate (committed): `vars/per-machine/<machine>/otel-cert/` for the seven collecting hosts
- Not modified: `modules/lib/hosts.nix` (CAM-109's registry, which already declares every member) and `modules/clan/inventory/services/zerotier.nix` (whose `allowedIps` CAM-109 rewrites to read that registry)

**Interfaces:**
- Consumes: `flake.lib.observabilityHosts`; CAM-109's `flake.lib.hosts.<host>.zerotier.address` and `.zerotier.memberId`; `vars/shared/zerotier-ip-<host>-zerotier/ip/value`; `vars/shared/zerotier-network-zerotier/network-id/value`.
- Produces: `flake.lib.zerotierMac`, the address and MAC clauses of `otel-collector-config`, the URI SAN on every `otel-cert`; no `flake.lib.hosts` field.
- Retirement: when CAM-109 retires ZeroTier, its retirement removes `flake.lib.zerotierMac`, the address and MAC clauses with their fixture and sources, and the neighbour pinning of Task 4, and the binding reads the derived `flake.lib.hosts.<host>.address` (design D4, D7).

- [ ] **Step 1: The address clause, failing first (tasks.md 2.1)**

The registry already holds every collecting host's ZeroTier address and member id (`modules/lib/hosts.nix`, CAM-109), so this step adds only the clause that judges it.
The clause's two sources: `flake.lib.hosts.<host>.zerotier.address` (first-party registry) and, for each collecting host, `vars/shared/zerotier-ip-<host>-zerotier/ip/value` if it exists, else (stibnite) the rfc4193 rendering of `fd` + the network id + `9993` + `flake.lib.hosts.<host>.zerotier.memberId`, grouped in fours and rendered canonically, which gives `fddb:4344:343b:14b9:399:9324:19d9:3451` for stibnite's `2419d93451`.
The member id is a second source only for an external member, whose `memberId` CAM-109 copied from the controller's record and checks against cinnabar's controller (migrate-mesh-to-tincr 2.1); a clan peer's `memberId` was derived from its own address, which is why clan peers are compared with their vars file instead.
The clause also requires each address to lie in the /88 formed from `vars/shared/zerotier-network-zerotier/network-id/value` (`fd` followed by the network id, then `9993`, which gives `fddb:4344:343b:14b9:399:93` for `db4344343b14b903`), to have eight groups, to be lower case, and to equal its own canonical RFC 5952 rendering, which with eight groups means no group with a leading zero.
Add it to `modules/checks/otel-collector-config.nix` beside R3.1, with the mutants:
- `addressDigitChanged`: `flake.lib.hosts.pyrite.zerotier.address` with its last digit changed;
- `externalAddressDiffers`: `flake.lib.hosts.stibnite.zerotier.address` set to `flake.lib.hosts.blackphos.zerotier.address` with stibnite's `memberId` unchanged, an address the controller admits, which a membership test would accept and the by-name comparison rejects.

Run each mutant alone first: `nix build .#.checks.x86_64-linux.otel-collector-config -L` with only that mutant applied.
Expected: FAIL naming pyrite for `addressDigitChanged` and stibnite for `externalAddressDiffers`.
Then run the unmutated check.
Expected after: the check passes, prints `mutant addressDigitChanged rejected` and `mutant externalAddressDiffers rejected`; its cost is recorded (build).

- [ ] **Step 2: The MAC clause, failing first (tasks.md 2.2)**

Write `modules/checks/otel-collector-config/zerotier-macs.json`, the pairs read from magnetite on 2026-11-06 (`brainstorm.md` "Resolved after the decisions"):

```json
{
  "network": "db4344343b14b903",
  "observed": "2026-11-06, magnetite ip -j -6 neigh show and ip -j link show",
  "pairs": {
    "fddb:4344:343b:14b9:399:9324:19d9:3451": "02:9d:0d:e2:00:15",
    "fddb:4344:343b:14b9:399:93db:4344:343b": "02:62:57:7f:00:7f",
    "fddb:4344:343b:14b9:399:937e:8067:8028": "02:c7:94:5c:b4:6c",
    "fddb:4344:343b:14b9:399:933c:8999:9bb8": "02:85:9d:a2:af:fc",
    "fddb:4344:343b:14b9:399:930f:39db:40d2": "02:b6:2d:e0:74:96"
  }
}
```

The clause compares `flake.lib.zerotierMac { inherit network; address = a; }` with each recorded MAC; mutant `macBytesReversed` reverses the function's output bytes.
Expected: FAIL, `attribute 'zerotierMac' missing`.
Then write `modules/lib/zerotier-mac.nix`, which implements `MAC::fromAddress` (`zerotierone@1.16.0:node/MAC.hpp:163-196`) without a 64-bit network integer, because Nix integers are signed and the network id exceeds 2^63:

```nix
# The MAC ZeroTier gives a member on a network (zerotierone 1.16.0
# node/MAC.hpp:163-196): the first octet from the network id's low byte, the
# member's 40-bit node id, XORed with network id bytes 1 to 5. The node id is
# the last 40 bits of its rfc4193 address; flake.lib.hosts holds eight groups.
{ lib, ... }:
{
  flake.lib.zerotierMac =
    { network, address }:
    let
      groups = lib.splitString ":" address;
      hex = lib.concatMapStrings (lib.fixedWidthString 4 "0") groups;
      node = lib.fromHexString (builtins.substring 22 10 hex);
      byte = i: lib.fromHexString (builtins.substring (14 - 2 * i) 2 network);
      first0 = builtins.bitOr (builtins.bitAnd (byte 0) 254) 2;
      first = if first0 == 82 then 50 else first0;
      pow = n: if n == 0 then 1 else 256 * pow (n - 1);
      mask = builtins.foldl' (m: i: builtins.bitXor m (byte i * pow (5 - i))) 0 [ 1 2 3 4 5 ];
      m = builtins.bitXor (first * pow 5 + node) mask;
      octet = i: lib.fixedWidthString 2 "0" (lib.toLower (lib.toHexString (lib.mod (m / pow i) 256)));
    in
    assert lib.assertMsg (builtins.length groups == 8) "zerotierMac: ${address} is not eight groups";
    lib.concatMapStringsSep ":" octet [ 5 4 3 2 1 0 ];
}
```

This body was evaluated on 2026-11-06 against the pinned nixpkgs `lib` and returned the five recorded MACs, and `02:ac:20:0a:3a:ac` for rosegold's `…:9315:3431:ee8`, whose last group has three digits.
Expected after: the check passes and rejects `macBytesReversed`, the MAC clause being the regulator; as a smoke reading only, `nix eval --raw .#lib.zerotierMac --apply 'f: f { network = "db4344343b14b903"; address = "fddb:4344:343b:14b9:399:9324:19d9:3451"; }'` prints `02:9d:0d:e2:00:15` (build, evaluation).

- [ ] **Step 3: The host-name assertion and the URI SAN (tasks.md 2.3)**

First add to the agent role, in its NixOS module and its `darwinModule`, an assertion that `config.networking.hostName == machine.name`, with the message naming both values, because the agent stamps `host.name` and deploy records stamp `host` from `networking.hostName` (FM:150, :301-302; `modules/system/deploy-record.nix:103-106`, :120-123) while the SAN carries `machine.name`.
Override `hostNameDiffers`: an `extendModules` override of cinnabar setting `networking.hostName = "cinnabar-typo"`.
Expected: every agent host evaluates, and the override fails cinnabar's evaluation with the assertion's message (evaluation).

In the `otel-cert` generator of `modules/clan/services/otel-collector/flake-module.nix` (FM:941-986), replace the SAN binding:

```nix
                uri = "URI:spiffe://vanixiets/host/${machine.name}";
                sans = uri + lib.optionalString isIngress ",IP:${flakeLib.hosts.magnetite.zerotier.address},DNS:magnetite.zt";
```

and write `echo "subjectAltName=${sans}"` unconditionally in `cert.ext`; `validation.subjectAltNames = sans` is unchanged in form; the `otel-ca` definition is not touched.
Expected: as a smoke reading only, `nix eval --json .#nixosConfigurations.cinnabar.config.clan.core.vars.generators.otel-cert.validation` shows `URI:spiffe://vanixiets/host/cinnabar` and magnetite's shows the URI followed by its IP and DNS SANs, Step 4's `openssl` reading being the regulator; `nix eval --json` of `generators.otel-ca` on magnetite equals the same `nix eval` run in the same step at the change's parent commit (`git+file://$REPO?rev=<parent>#nixosConfigurations.magnetite…`) (evaluation).

- [ ] **Step 4: The vars step (tasks.md 2.4)**

```bash
L=logs/cam81-evidence/2.4-vars-$(date -u +%Y%m%dT%H%M%SZ).log
sha256sum vars/shared/otel-ca/ca.crt/value | tee "$L"
CLAN_NO_COMMIT=1 clan vars get magnetite ntfy-alerter/token | sha256sum | tee -a "$L"
for m in magnetite cinnabar pyrite electrum galena scheelite stibnite; do
  CLAN_NO_COMMIT=1 clan vars generate "$m" --generator otel-cert 2>&1 | tee -a "$L"
  openssl x509 -noout -subject -ext subjectAltName,extendedKeyUsage -in vars/per-machine/$m/otel-cert/cert.pem/value | tee -a "$L"
  openssl verify -CAfile vars/shared/otel-ca/ca.crt/value vars/per-machine/$m/otel-cert/cert.pem/value | tee -a "$L"
done
sha256sum vars/shared/otel-ca/ca.crt/value | tee -a "$L"
CLAN_NO_COMMIT=1 clan vars get magnetite ntfy-alerter/token | sha256sum | tee -a "$L"
```

Expected: each certificate shows `URI:spiffe://vanixiets/host/<machine>` (magnetite's also `IP Address:fddb:4344:343b:14b9:399:930f:39db:40d2, DNS:magnetite.zt`), every verify prints `OK`, and the closing hashes equal Task 1 Step 2's; a differing hash stops the step and the regenerated files are discarded with `jj restore vars/`.
If clan regenerates only on `--regenerate`, rerun each command with it, still naming `otel-cert` alone, and record that in `$L`.
Commit the regenerated vars with Step 3's change.

- [ ] **Step 5: Format and open pull request 1 (tasks.md 2.5)**

`nix fmt`, keeping its log; `nix fmt -- --fail-on-change`; record each changed check's cost; open the pull request in plain words (for example "Name each collecting host in its collection certificate and record every host's ZeroTier address").
Expected: nixbot green on `otel-collector-config`, `otel-envelope` and `nixos-magnetite`, and `darwin-stibnite` evaluates; each changed check's cost below 536,870,912 B, and the machine checks' cost before and after by the same method, any rise put to the operator (command).
