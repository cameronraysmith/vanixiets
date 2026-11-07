### Task 2: caddy's root as clan vars

Implements `tasks.md` 2.1–2.7 (design D10–D13; O8–O12; FAI `caddy on cinnabar loads its root from the caddy-root-ca vars`; FA `A reinstall of cinnabar keeps the service authority`; WA A79, A83).
It starts only after Task 1 Step 2, and lands as pull request 1.
Order inside the task: the VM test goes red (Step 1), the module turns it green (Step 2), the generator is declared (Step 3), the operator imports the vars (Step 4), cinnabar imports the module with the vars (Step 5), and CR is removed (Step 6).
Step 4 runs in the primary checkout on stibnite, with the operator present; no other step reads or writes the key.

**Files:**
- Create: `modules/vm-tests/caddy-root-from-vars.nix`, `modules/nixos/caddy-local-root.nix`, `modules/machines/nixos/cinnabar/caddy-root-ca.nix`, `vars/per-machine/cinnabar/caddy-root-ca/root.key/{secret,machines/cinnabar,users/…}`, `vars/per-machine/cinnabar/caddy-root-ca/root.crt/value`.
- Modify: `modules/darwin/zt-services-trust.nix`.
- Delete: `modules/machines/nixos/cinnabar/pki/caddy-root-ca.crt`.
- Create (git-ignored): `logs/cam87-evidence/2.<n>-*.log`.

**Interfaces:**
- Consumes: caddy 2.11.7 at the root pin (`services.caddy.package`); clan-core `dbae2101`'s `clan vars set`, `get` and `check`; caddy's storage on cinnabar, `/var/lib/caddy/.local/share/caddy/pki/authorities/local/`, read only by Step 4.
- Produces: `flake.modules.nixos.caddy-local-root` with `vanixiets.caddyLocalRoot.{certFile,keyFile,fingerprint}`; the generator `caddy-root-ca`; RV, which Tasks 4 and 5 read.

Grounding, caddy 2.11.7 (`/nix/store/…-source` of `services.caddy.package.src`): the Caddyfile global option `pki { ca local { root { cert <path> key <path> } } }` (`caddyconfig/httpcaddyfile/pkiapp.go:32-55`, `:126-153`) adapts to `apps.pki.certificate_authorities.local.root.{certificate,private_key}`; `modules/caddypki/ca.go:150-158` loads it, `crypto.go:91-118` refuses a mismatched key, `ca.go:175` and `:345-375` load or issue the intermediate, `maintain.go:68-100` skips root maintenance and renews the intermediate from the configured files.

- [ ] **Step 1: The reinstall test, red (2.1)**

Create `modules/vm-tests/caddy-root-from-vars.nix`, in the shape of `modules/vm-tests/fleet-ingress.nix` (a `perSystem` `vmTests` attribute on `x86_64-linux` only, `pkgs.testers.runNixOSTest`):

```nix
# vmTests.x86_64-linux.caddy-root-from-vars (CAM-87 design D11): a caddy whose
# storage is empty serves ntfy.zt under the root flake.modules.nixos.
# caddy-local-root configures, and writes no root of its own; the control
# node "minting", the same caddy without the module, mints a root, so the
# same client refuses it. The values related are the root made here and the
# chain each caddy serves. Non-gating: built on magnetite, as every
# x86_64-linux build of this change is.
{ config, lib, ... }:
let
  module = config.flake.modules.nixos.caddy-local-root;
in
{
  perSystem =
    { pkgs, system, ... }:
    let
      pki = pkgs.runCommand "caddy-root-from-vars-pki" { nativeBuildInputs = [ pkgs.openssl ]; } ''
        mkdir $out
        openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 -nodes -keyout $out/root.key -sha256 -days 3650 \
          -subj "/CN=caddy-root-from-vars test root" -addext basicConstraints=critical,CA:TRUE,pathlen:1 \
          -addext keyUsage=critical,keyCertSign,cRLSign -out $out/root.crt
        openssl x509 -in $out/root.crt -noout -fingerprint -sha256 | cut -d= -f2 | tr -d '\n' > $out/fingerprint
      '';
      site = {
        services.caddy.enable = true;
        services.caddy.virtualHosts."ntfy.zt".extraConfig = ''
          tls internal
          respond "ok"
        '';
        networking.firewall.allowedTCPPorts = [ 443 ];
      };
    in
    {
      vmTests = lib.optionalAttrs (system == "x86_64-linux") {
        caddy-root-from-vars = pkgs.testers.runNixOSTest {
          name = "caddy-root-from-vars";
          nodes = {
            restored = {
              imports = [ module site ];
              vanixiets.caddyLocalRoot = {
                certFile = "${pki}/root.crt";
                keyFile = "/etc/caddy-test/root.key";
                fingerprint = builtins.readFile "${pki}/fingerprint";
              };
              environment.etc."caddy-test/root.key" = {
                source = "${pki}/root.key";
                user = "caddy";
                mode = "0400";
              };
            };
            minting = site;
            client = { environment.systemPackages = [ pkgs.curl pkgs.openssl ]; };
          };
          testScript = ''
            start_all()
            for node in (restored, minting):
                node.wait_for_unit("caddy.service")
                node.wait_for_open_port(443)
            ca = "${pki}/root.crt"
            def get(host):
                return client.succeed(f"curl -s -o /dev/null -w '%{{http_code}}' --cacert {ca} --resolve ntfy.zt:443:$(getent hosts {host} | cut -d' ' -f1) https://ntfy.zt/ ; echo \" rc=$?\"").strip()
            with subtest("restored serves under the configured root"):
                assert get("restored").startswith("200"), get("restored")
                client.succeed(f"openssl s_client -connect restored:443 -servername ntfy.zt -CAfile {ca} -verify_return_error < /dev/null")
                restored.fail("test -e /var/lib/caddy/.local/share/caddy/pki/authorities/local/root.crt")
            with subtest("minting: without the module the same client is refused"):
                assert get("minting").endswith("rc=60"), get("minting")
          '';
        };
      };
    };
}
```

The VM test's `get` helper and quoting are adjusted while writing until `minting` alone fails as expected; the step records the final command lines in its log.
`/etc/caddy-test/root.key` stands in for the deployed var, which a VM has no sops key to decrypt.
Run `jj st --no-pager >/dev/null` and `nix eval --raw .#vmTests.x86_64-linux.caddy-root-from-vars.drvPath`.
Expected: evaluation fails because `config.flake.modules.nixos.caddy-local-root` is missing; log to `logs/cam87-evidence/2.1-red-<ts>.log`.

- [ ] **Step 2: The module, green (2.2)**

Create `modules/nixos/caddy-local-root.nix`:

```nix
# flake.modules.nixos.caddy-local-root (CAM-87 design D11): caddy's local
# certificate authority signs with the root and key in certFile and keyFile
# instead of the root in its storage, so a host reinstalled with the same
# files serves the same root (caddy 2.11.7: caddyconfig/httpcaddyfile/
# pkiapp.go:32-55; modules/caddypki/ca.go:150-158). caddy refuses a key that
# does not match certFile's first certificate, never renews the root, and
# issues intermediates under it.
#
# system.checks gains caddy-root-from-vars, built with the host's toplevel:
# "configured root" adapts the rendered Caddyfile with caddy itself and
# requires apps.pki.certificate_authorities.local.root to name certFile and
# keyFile; "recorded root" requires certFile's first certificate to have the
# sha256 fingerprint `fingerprint`. Each is shown failing by an
# extendModules override on cinnabar (pkiDropped, fingerprintOther).
{ ... }:
{
  flake.modules.nixos.caddy-local-root =
    { config, lib, pkgs, ... }:
    let
      cfg = config.vanixiets.caddyLocalRoot;
      caddy = config.services.caddy;
    in
    {
      options.vanixiets.caddyLocalRoot = {
        certFile = lib.mkOption {
          type = lib.types.str;
          description = "PEM file whose first certificate is the local authority's root; further certificates are ignored by caddy and serve a rotation's overlap for clients.";
        };
        keyFile = lib.mkOption {
          type = lib.types.str;
          description = "PEM private key of certFile's first certificate, readable by caddy.";
        };
        fingerprint = lib.mkOption {
          type = lib.types.strMatching "([0-9A-F]{2}:){31}[0-9A-F]{2}";
          description = "sha256 fingerprint, as openssl prints it, recorded for certFile's first certificate.";
        };
      };
      config = {
        services.caddy.globalConfig = ''
          pki {
            ca local {
              root {
                cert ${cfg.certFile}
                key ${cfg.keyFile}
              }
            }
          }
        '';
        system.checks = [
          (pkgs.runCommand "caddy-root-from-vars"
            {
              nativeBuildInputs = [ caddy.package pkgs.jq pkgs.openssl pkgs.gawk ];
            }
            ''
              set -euo pipefail
              adapted=$(caddy adapt --adapter caddyfile --config ${caddy.configFile})
              cert=$(jq -r '.apps.pki.certificate_authorities.local.root.certificate // empty' <<< "$adapted")
              key=$(jq -r '.apps.pki.certificate_authorities.local.root.private_key // empty' <<< "$adapted")
              if [ "$cert" != ${lib.escapeShellArg cfg.certFile} ] || [ "$key" != ${lib.escapeShellArg cfg.keyFile} ]; then
                echo "caddy-root-from-vars: configured root: caddy adapts the root to cert '$cert' key '$key', expected ${cfg.certFile} and ${cfg.keyFile}" >&2
                exit 1
              fi
              fp=$(awk '/BEGIN CERTIFICATE/{n++} n==1' ${cfg.certFile} | openssl x509 -noout -fingerprint -sha256 | cut -d= -f2)
              if [ "$fp" != ${lib.escapeShellArg cfg.fingerprint} ]; then
                echo "caddy-root-from-vars: recorded root: certFile's root is $fp, recorded ${cfg.fingerprint}" >&2
                exit 1
              fi
              echo "caddy-root-from-vars: caddy's root is ${cfg.certFile}, fingerprint $fp" > $out
            '')
        ];
      };
    }
  ;
}
```

`services.caddy.configFile` evaluates to the formatted Caddyfile itself, `…-Caddyfile-formatted/Caddyfile` on cinnabar, so the check passes it to `caddy adapt` directly.
The `recorded root` clause reads `certFile` at build time, which works because cinnabar's `root.crt` is a public var whose `path` is a store path; a `keyFile` under `/run/secrets` is named, never read, by the check.
Run `jj st --no-pager >/dev/null`, then from a checkout of this commit, built on magnetite:

```bash
nix build .#vmTests.x86_64-linux.caddy-root-from-vars -L --option builders "$(grep 930f /etc/nix/machines | head -1)" 2>&1 | tee "logs/cam87-evidence/2.2-vm-$(/bin/date -u +%Y%m%dT%H%M%SZ).log"
```

Expected: both subtests pass, `minting` with `rc=60`, and the `restored` node's build-time `caddy-root-from-vars` built as part of its toplevel.
Commit: "caddy-local-root: load caddy's local root from given files".

- [ ] **Step 3: The generator (2.3)**

Create `modules/machines/nixos/cinnabar/caddy-root-ca.nix`:

```nix
# caddy's local root on cinnabar as clan vars (CAM-87 design D10): the root
# and key caddy generated on 2026-01-27, imported once by the operator with
# `clan vars set` (runbook "caddy's root"), never generated: the script only
# fails, and a generator without `validation` whose files exist counts as
# current, so no clan command mints a root that the fleet's clients and the
# operator's phone would not trust.
{ ... }:
{
  flake.modules.nixos."machines/nixos/cinnabar" =
    { ... }:
    {
      clan.core.vars.generators.caddy-root-ca = {
        files."root.key" = {
          owner = "caddy";
          group = "caddy";
          mode = "0400";
          restartUnits = [ "caddy.service" ];
        };
        files."root.crt".secret = false;
        script = ''
          echo "caddy-root-ca is imported from cinnabar's caddy storage with clan vars set, never generated; see the fleet observability runbook, \"caddy's root\"" >&2
          exit 1
        '';
      };
    };
}
```

Run `jj st --no-pager >/dev/null`, then:

```bash
{
  nix eval --json .#nixosConfigurations.cinnabar.config.clan.core.vars.generators.caddy-root-ca.files \
    --apply 'fs: builtins.mapAttrs (n: f: { inherit (f) secret owner group mode restartUnits; path = if f.secret then f.path else "store"; }) fs'
  CLAN_NO_COMMIT=1 clan vars check cinnabar --generator caddy-root-ca; echo "rc=$?"
} 2>&1 | tee "logs/cam87-evidence/2.3-generator-$(/bin/date -u +%Y%m%dT%H%M%SZ).log"
```

Expected: `root.key` secret, owner and group `caddy`, mode `0400`, `restartUnits` `[ "caddy.service" ]`, path `/run/secrets/vars/per-machine/cinnabar/caddy-root-ca/root.key`; `root.crt` public; `clan vars check` reports both files missing with a non-zero `rc`.
Commit the declaration with the next step's files, not alone, so no commit on `main` declares the generator without its files.

- [ ] **Step 4: The import (2.4) [operator]**

The operator confirms in the session that they are present and that the step may read caddy's key from cinnabar; the confirmation and its time open the log.
On stibnite in the primary checkout, at the commit of Step 3, the two `clan vars set` commands run with `TMPDIR` on a RAM disk made for this step and detached after it.
`clan vars set` writes a secret's value to a `NamedTemporaryFile` in `/dev/shm`, or in Python's temporary directory when `/dev/shm` is missing, as on stibnite, before `sops encrypt --in-place` overwrites it and clan unlinks it (`clan-core@dbae2101:pkgs/clan-cli/clan_cli/secrets/sops.py:527-555`); Python takes that directory from `TMPDIR`, so the key's one plaintext file lands on the RAM disk.
`diskutil erasevolume` formats and mounts the attached device in one step, a volume under `/Volumes` ignores ownership until `enableOwnership`, and `.metadata_never_index` keeps Spotlight from reading the volume into its index on the system disk.
`/Volumes/cam87ram` must not exist before the step attaches the RAM disk; if it does, the step stops.

```bash
log="logs/cam87-evidence/2.4-import-$(/bin/date -u +%Y%m%dT%H%M%SZ).log"
store=/var/lib/caddy/.local/share/caddy/pki/authorities/local
vol=/Volumes/cam87ram
dev=$(/usr/bin/hdiutil attach -nomount ram://2097152 | awk 'NR == 1 { print $1 }')
{
  echo "== RAM disk $dev"
  /usr/sbin/diskutil erasevolume APFS cam87ram "$dev"
  /usr/bin/sudo /usr/sbin/diskutil enableOwnership "$vol"
  /usr/bin/sudo /usr/bin/touch "$vol/.metadata_never_index"
  /usr/bin/sudo /usr/bin/install -d -m 0700 -o "$(id -u)" -g "$(id -g)" "$vol/tmp"
  /usr/bin/stat -f '%Sp %Su %N' "$vol/tmp"
} 2>&1 | tee "$log"
export TMPDIR="$vol/tmp"
py=$(sed -n '1s/^#!//p' "$(dirname "$(readlink -f "$(command -v clan)")")/.clan-wrapped")
{
  echo "== TMPDIR"
  /bin/df "$TMPDIR"
  "$py" -c 'import tempfile; print(tempfile.gettempdir())'
  echo "== live root before"
  ssh cinnabar.zt "sudo cat $store/root.crt" | openssl x509 -noout -fingerprint -sha256 -enddate
  ssh cinnabar.zt "sudo cat $store/root.key" | CLAN_NO_COMMIT=1 clan vars set cinnabar caddy-root-ca/root.key; echo "set root.key rc=$?"
  ssh cinnabar.zt "sudo cat $store/root.crt" | CLAN_NO_COMMIT=1 clan vars set cinnabar caddy-root-ca/root.crt; echo "set root.crt rc=$?"
  echo "== var root"
  openssl x509 -in vars/per-machine/cinnabar/caddy-root-ca/root.crt/value -noout -fingerprint -sha256 -enddate
  echo "== public keys (hashes only)"
  clan vars get cinnabar caddy-root-ca/root.key | openssl pkey -pubout | sha256sum
  openssl x509 -in vars/per-machine/cinnabar/caddy-root-ca/root.crt/value -pubkey -noout | sha256sum
  echo "== readers"
  readers=$(cd vars/per-machine/cinnabar/caddy-root-ca/root.key && find machines users groups -mindepth 1 -maxdepth 1 2>/dev/null | LC_ALL=C sort | tr '\n' ' ')
  echo "$readers"
  case "$readers" in
    "machines/cinnabar users/cameron " | "machines/cinnabar users/crs58 ") echo "readers as expected" ;;
    *) echo "readers differ" ;;
  esac
  CLAN_NO_COMMIT=1 clan vars check cinnabar --generator caddy-root-ca; echo "check rc=$?"
  echo "== TMPDIR after"
  find "$TMPDIR" -maxdepth 1 -type f
  echo "top-level files: $(find "$TMPDIR" -maxdepth 1 -type f | wc -l | tr -d ' ')"
} 2>&1 | tee -a "$log"
unset TMPDIR
/usr/bin/hdiutil detach "$dev" 2>&1 | tee -a "$log"
echo "detach rc=${PIPESTATUS[0]}" | tee -a "$log"
grep -c 'PRIVATE KEY' "$log"
```

Expected: the RAM disk's `tmp` is `drwx------` and owned by the operator; `df` names the RAM disk's volume mounted on `/Volumes/cam87ram`, and clan's interpreter prints `/Volumes/cam87ram/tmp`; the live and var fingerprints both `7E:78:F6:7C:83:BD:DC:81:51:FF:EB:8F:82:1A:68:5D:02:89:9F:93:27:33:7F:9B:F2:41:9B:F9:3B:AA:2E:82` with `notAfter=Dec  6 14:29:17 2035 GMT`; the two public-key hashes equal; the readers exactly `machines/cinnabar` and one of `users/cameron` or `users/crs58`, which hold the same age key, and `readers as expected`; `check rc=0`; `top-level files: 0`, so clan's temporary files are gone; `detach rc=0`; the final `grep -c` prints `0`, so the log holds no key.
The log shows where clan's temporary files went, which the code path above makes the only place the key was written in clear; no check can show that a deleted file was never written elsewhere.
The key still exists in clear in the memory of `ssh`, the pipe and clan, which no file holds; macOS encrypts swap.
On any difference, including another reader entry, the step stops: the RAM disk is detached with `/usr/bin/hdiutil detach "$dev"` if it is still attached, `jj restore vars/per-machine/cinnabar/caddy-root-ca` removes the files from the working copy, and the operator decides; no `clan vars generate` runs.
Commit Steps 3 and 4 together: "cinnabar: keep caddy's existing local root as clan vars".

- [ ] **Step 5: cinnabar loads the root from the vars (2.5)**

In `modules/machines/nixos/cinnabar/caddy-root-ca.nix`, import `config.flake.modules.nixos.caddy-local-root` into cinnabar's module and set:

```nix
vanixiets.caddyLocalRoot = {
  certFile = "${config.clan.core.vars.generators.caddy-root-ca.files."root.crt".path}";
  keyFile = config.clan.core.vars.generators.caddy-root-ca.files."root.key".path;
  # Recorded from cinnabar's caddy storage on 2026-11-06; a rotation changes it with the vars.
  fingerprint = "7E:78:F6:7C:83:BD:DC:81:51:FF:EB:8F:82:1A:68:5D:02:89:9F:93:27:33:7F:9B:F2:41:9B:F9:3B:AA:2E:82";
};
```

Run `jj st --no-pager >/dev/null`, record `nixos-cinnabar`'s cost, then:

```bash
{
  nix build .#checks.x86_64-linux.nixos-cinnabar -L --option builders "$(grep 930f /etc/nix/machines | head -1)"
  for m in pkiDropped fingerprintOther; do
    case $m in
      pkiDropped) o='{ services.caddy.globalConfig = lib.mkForce (lib.concatStrings (lib.filter builtins.isString (builtins.split "pki [{]\n([ \t][^\n]*\n)*[}]\n?" f.nixosConfigurations.cinnabar.config.services.caddy.globalConfig))); }' ;;
      fingerprintOther) o="{ vanixiets.caddyLocalRoot.fingerprint = lib.mkForce \"$(openssl x509 -in vars/shared/otel-ca/ca.crt/value -noout -fingerprint -sha256 | cut -d= -f2)\"; }" ;;
    esac
    nix build --no-link --impure --option builders "$(grep 930f /etc/nix/machines | head -1)" --expr "let f = builtins.getFlake (toString ./.); lib = f.inputs.nixpkgs.lib; in (f.nixosConfigurations.cinnabar.extendModules { modules = [ ($o) ]; }).config.system.build.toplevel" 2>&1 | grep -E 'caddy-root-from-vars: (configured|recorded) root' && echo "override $m rejected"
  done
} 2>&1 | tee "logs/cam87-evidence/2.5-cinnabar-$(/bin/date -u +%Y%m%dT%H%M%SZ).log"
```

`pkiDropped` removes only the `pki` block, whose inner lines are indented and whose closing brace starts a line, and keeps the rest of cinnabar's global block, which evaluates to `log { level ERROR }` besides it; the step prints the override's `services.caddy.globalConfig` once and confirms that it holds `log {` and no `pki`.
Expected: `nixos-cinnabar` builds; `pkiDropped` fails with `configured root`, `fingerprintOther` with `recorded root`, each printing `override <name> rejected`; the cost after is recorded.
Commit: "cinnabar: load caddy's local root from its clan vars".

- [ ] **Step 6: One source (2.6)**

Delete `modules/machines/nixos/cinnabar/pki/caddy-root-ca.crt`, and in `modules/darwin/zt-services-trust.nix` set `caddyCert = ../../vars/per-machine/cinnabar/caddy-root-ca/root.crt/value;` with a comment naming the generator.
Run `jj st --no-pager >/dev/null`, then:

```bash
{
  rg -n 'pki/caddy-root-ca.crt' modules pkgs || echo "no reader of the old file"
  nix eval --raw .#darwinConfigurations.stibnite.config.system.build.toplevel.drvPath
  nix eval --raw .#darwinConfigurations.stibnite.config.system.activationScripts.postActivation.text | grep -o '/nix/store/[^"]*-value' | head -1 | xargs -I{} sh -c 'nix build --no-link {} 2>/dev/null; cmp {} vars/per-machine/cinnabar/caddy-root-ca/root.crt/value && echo "keychain root equals RV"'
} 2>&1 | tee "logs/cam87-evidence/2.6-source-$(/bin/date -u +%Y%m%dT%H%M%SZ).log"
```

Expected: `no reader of the old file`; stibnite evaluates; `keychain root equals RV`.
Commit: "zt-services-trust: read caddy's root from cinnabar's clan vars".

- [ ] **Step 7: Pull request 1 (2.7)**

Run `nix fmt` and keep its log, then `nix fmt -- --fail-on-change`; open pull request 1, titled "Keep caddy's local root on cinnabar as clan vars caddy loads", whose description states the import in words (who imported it, when, the fingerprint, the readers `machines/cinnabar` and the recorded user entry), the security trade-off (the root's key, until now one file on cinnabar, is in the repository sops-encrypted to cinnabar's age key and the importing admin's age key), and the `vmTests` run of Step 2 (commit, host, date).
Expected: nixbot green on `nixos-cinnabar` and `nixos-magnetite`, `darwin-stibnite` evaluates; the pull request merges through the queue.
