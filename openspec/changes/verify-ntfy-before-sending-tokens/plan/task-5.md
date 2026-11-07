### Task 5: cinnabar's served-root check

Implements `tasks.md` 5.1–5.4 (design D6; O5; Q2; FAI `cinnabar checks the root caddy serves weekly`; FA `The service authority's expiry reaches a person 180 days ahead`).
It starts after pull request 2 merges, from `main@origin`, and lands as pull request 3.

**Files:**
- Create: `modules/lib/caddy-root-check.nix`, `modules/machines/nixos/cinnabar/caddy-root-check.nix`.
- Modify: `modules/checks/ntfy-tls-verification.nix` (the legs), `modules/lib/observability-hosts.nix` (cinnabar's `notifiedUnits`).
- Create (git-ignored): `logs/cam87-evidence/5.<n>-*.log`.

**Interfaces:**
- Consumes: RV; `flake.modules.nixos.observability-notify`'s `OnFailure` wiring and zone assertion, which cinnabar imports; cinnabar's dnsmasq answering `ntfy.zt` with cinnabar's own mesh address, where caddy listens.
- Produces: `flake.lib.caddyRootCheck` and the units of plan "Interface contract".

- [ ] **Step 1: The legs, red (5.1)**

Add to `modules/checks/ntfy-tls-verification.nix`, after the scan, with `pkgs.openssl` in `nativeBuildInputs` and the module taking `config` to read `config.flake.lib`:

```bash
# Root-check legs (design D6): a root, an intermediate under it and a leaf
# for ntfy.zt, served by openssl s_server on loopback; validities relative to
# this build's clock. The values related are the served chain against the
# bundle, and the bundle's first root's notAfter against the clock.
mkroot() {
  openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 -nodes -keyout "$1.key" -sha256 -days "$2" \
    -subj "/CN=$1" -addext basicConstraints=critical,CA:TRUE,pathlen:1 -addext keyUsage=critical,keyCertSign,cRLSign -out "$1.crt" 2>/dev/null
  openssl req -new -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 -nodes -keyout "$1-int.key" -subj "/CN=$1 int" -out "$1-int.csr" 2>/dev/null
  printf 'basicConstraints=critical,CA:TRUE,pathlen:0\nkeyUsage=critical,keyCertSign,cRLSign\n' > int.ext
  openssl x509 -req -in "$1-int.csr" -CA "$1.crt" -CAkey "$1.key" -CAcreateserial -days 30 -extfile int.ext -out "$1-int.crt" 2>/dev/null
  openssl req -new -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 -nodes -keyout "$1-leaf.key" -subj "/CN=ntfy.zt" -out "$1-leaf.csr" 2>/dev/null
  printf 'subjectAltName=DNS:ntfy.zt\nextendedKeyUsage=serverAuth\n' > leaf.ext
  openssl x509 -req -in "$1-leaf.csr" -CA "$1-int.crt" -CAkey "$1-int.key" -CAcreateserial -days 7 -extfile leaf.ext -out "$1-leaf.crt" 2>/dev/null
}
mkroot r1 400; mkroot r2 400; mkroot r3 100
cat r1.crt r2.crt > overlap.crt
# serve ROOT PORT: serves ROOT's leaf with its intermediate on 127.0.0.1:PORT.
serve() { openssl s_server -quiet -accept "127.0.0.1:$2" -cert "$1-leaf.crt" -key "$1-leaf.key" -cert_chain "$1-int.crt" -www & sleep 0.5; }
serve r1 18441; serve r2 18442; serve r3 18443
check=${lib.getExe (config.flake.lib.caddyRootCheck pkgs { bundle = "$BUNDLE"; connect = "$CONNECT"; servername = "ntfy.zt"; })}
# leg NAME BUNDLE PORT EXPECTED [SCRIPT]: EXPECTED is ok or a message fragment.
leg() {
  local name=$1 bundle=$2 port=$3 expected=$4 script=${5:-$check} out rc=0
  out=$(BUNDLE=$bundle CONNECT=127.0.0.1:$port bash "$script" 2>&1) || rc=$?
  if [ "$expected" = ok ]; then [ "$rc" = 0 ] || { echo "FAIL $name: exit $rc: $out"; return 1; }
  else [ "$rc" != 0 ] && grep -qF -- "$expected" <<< "$out" || { echo "FAIL $name: exit $rc: $out"; return 1; }; fi
  echo "ok: $name"
}
leg servedHeld r1.crt 18441 ok || exit 1
leg servedInOverlap overlap.crt 18442 ok || exit 1
leg servedDrifted r1.crt 18442 "does not verify" || exit 1
leg rootExpiring r3.crt 18443 "expires" || exit 1
sed -e 's/ -verify_return_error//' -e 's/^verified=.*/verified=0/' "$check" > verificationSkipped
if leg servedDrifted r1.crt 18442 "does not verify" verificationSkipped; then echo "FAIL: mutant verificationSkipped passed"; exit 1; fi
echo "mutant verificationSkipped rejected"
sed 's/openssl x509 -checkend/true/' "$check" > expirySkipped
if leg rootExpiring r3.crt 18443 "expires" expirySkipped; then echo "FAIL: mutant expirySkipped passed"; exit 1; fi
echo "mutant expirySkipped rejected"
```

The block is embedded in the check's `runCommand` text, with `''${` escapes where Nix requires them.
Run `jj st --no-pager >/dev/null` and `nix build .#checks.x86_64-linux.ntfy-tls-verification -L --option builders "$(grep 930f /etc/nix/machines | head -1)"`.
Expected: evaluation fails with `attribute 'caddyRootCheck' missing`.

- [ ] **Step 2: The function, green (5.2)**

Create `modules/lib/caddy-root-check.nix`:

```nix
# flake.lib.caddyRootCheck pkgs { bundle; connect; servername; minRemainingSec ? 15552000; }
# (CAM-87 design D6): the script cinnabar runs weekly as caddy-root-check. It
# fails when the chain served at <connect> for <servername> does not verify
# against <bundle>, the public value of cinnabar's clan vars caddy-root-ca,
# and when the bundle's first certificate, the root caddy is configured with,
# expires within minRemainingSec (180 days). A chain that stops verifying
# means every ntfy-send refuses ntfy.zt too, so this unit's notice is not
# delivered then and its value is the cause it names in the journal; an
# approaching expiry is posted while the root still verifies.
# checks.x86_64-linux.ntfy-tls-verification runs it against openssl s_server
# over chains made in the sandbox, with a mutant for each clause.
{ ... }:
{
  flake.lib.caddyRootCheck =
    pkgs:
    {
      bundle,
      connect,
      servername,
      minRemainingSec ? 15552000,
    }:
    pkgs.writeShellApplication {
      name = "caddy-root-check";
      runtimeInputs = [
        pkgs.openssl
        pkgs.coreutils
        pkgs.gawk
      ];
      text = ''
        bundle="${bundle}"
        connect="${connect}"
        servername="${servername}"
        root=$(mktemp)
        trap 'rm -f "$root"' EXIT
        awk '/-----BEGIN CERTIFICATE-----/ { n++ } n == 1 { print }' "$bundle" > "$root"
        fp=$(openssl x509 -in "$root" -noout -fingerprint -sha256 | cut -d= -f2)
        notafter=$(openssl x509 -in "$root" -noout -enddate | cut -d= -f2)
        out=$(openssl s_client -connect "$connect" -servername "$servername" -CAfile "$bundle" -verify_return_error < /dev/null 2>&1) || true
        verified=0
        grep -q 'Verify return code: 0 (ok)' <<< "$out" && verified=1
        if [ "$verified" != 1 ]; then
          echo "caddy-root-check: the chain served for $servername does not verify against $bundle" >&2
          grep -m1 'Verify return code' <<< "$out" >&2 || true
          exit 1
        fi
        if ! openssl x509 -checkend ${toString minRemainingSec} -noout -in "$root" > /dev/null; then
          echo "caddy-root-check: caddy's root expires $notafter, within $(( ${toString minRemainingSec} / 86400 )) days" >&2
          exit 1
        fi
        echo "caddy-root-check: served chain verifies against root $fp, expires $notafter"
      '';
    };
}
```

The `verified=0` and `-verify_return_error` texts are those the mutant's `sed` edits; the step confirms with `diff` of the built script and the mutant that exactly those lines change.
Run `jj st --no-pager >/dev/null`, build the check and record its cost.
Expected: every leg prints `ok:`, both mutants print `rejected`, the scan's lines are unchanged, and the cost stays under 536,870,912 B.
Commit: "caddy-root-check: verify the chain caddy serves against its root and warn before expiry".

- [ ] **Step 3: The unit on cinnabar (5.3)**

Create `modules/machines/nixos/cinnabar/caddy-root-check.nix`:

```nix
# caddy-root-check on cinnabar (CAM-87 design D6): weekly, verify the chain
# caddy serves for ntfy.zt against the public value of the clan vars
# caddy-root-ca, and fail 180 days before that root expires. cinnabar's
# notifiedUnits lists it, so a failure posts one FAILED notice per episode
# through observability-notify.
{ config, ... }:
let
  flakeLib = config.flake.lib;
in
{
  flake.modules.nixos."machines/nixos/cinnabar" =
    { config, lib, pkgs, ... }:
    {
      systemd.services.caddy-root-check = {
        description = "Verify the chain caddy serves for ntfy.zt against caddy's root";
        after = [ "caddy.service" "network-online.target" ];
        wants = [ "network-online.target" ];
        serviceConfig = {
          Type = "oneshot";
          DynamicUser = true;
          ExecStart = lib.getExe (
            flakeLib.caddyRootCheck pkgs {
              bundle = "${config.clan.core.vars.generators.caddy-root-ca.files."root.crt".path}";
              connect = "ntfy.zt:443";
              servername = "ntfy.zt";
            }
          );
        };
      };
      systemd.timers.caddy-root-check = {
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnCalendar = "Mon *-*-* 14:00:00 UTC";
          Persistent = true;
        };
      };
    };
}
```

In `modules/lib/observability-hosts.nix`, append `"caddy-root-check"` to cinnabar's `notifiedUnits`.
Run `jj st --no-pager >/dev/null`, then:

```bash
{
  nix eval --json .#nixosConfigurations.cinnabar.config.systemd.services.caddy-root-check.onFailure
  nix eval --json .#nixosConfigurations.cinnabar.config.systemd.timers.caddy-root-check.timerConfig
  nix eval --json .#lib.observabilityHosts.cinnabar.notifiedUnits
  nix eval --raw .#nixosConfigurations.magnetite.config.systemd.services.fleet-alert.environment.FLEET_ALERT_CONFIG --apply builtins.readFile \
    | jq -c '.. | objects | select(.alert? == "SystemdUnitFailed")' | grep -o 'caddy-root-check' | head -1
  nix eval --impure --raw --expr 'let f = builtins.getFlake (toString ./.); lib = f.inputs.nixpkgs.lib; c = f.nixosConfigurations.cinnabar.extendModules { modules = [ { systemd.timers.caddy-root-check.timerConfig.OnCalendar = lib.mkForce "Mon *-*-* 14:00:00"; } ]; }; in c.config.system.build.toplevel.drvPath' 2>&1 | tail -3
} 2>&1 | tee "logs/cam87-evidence/5.3-units-$(/bin/date -u +%Y%m%dT%H%M%SZ).log"
```

`builtins.readFile` builds the rendered JSON by import from derivation, and the `jq` filter finds the rule wherever it sits.
Expected: `onFailure` names `observability-notify@%n.service`; the timer shows the UTC calendar and `Persistent`; `notifiedUnits` ends with `caddy-root-check`; magnetite's rendered configuration names `caddy-root-check` in the `SystemdUnitFailed` exclusion; the override fails with `observability-notify: the timers of notified units must name their zone in OnCalendar`.
Commit: "cinnabar: verify weekly the chain caddy serves for ntfy.zt".

- [ ] **Step 4: Pull request 3 (5.4)**

Run `nix fmt` and keep its log, then `nix fmt -- --fail-on-change`; record the costs of `ntfy-tls-verification`, `fleet-alert`, `nixos-cinnabar` and `nixos-magnetite`; open pull request 3, titled "Check weekly on cinnabar that the root caddy serves is the one clients trust".
Expected: nixbot green on those four; the pull request merges through the queue.
