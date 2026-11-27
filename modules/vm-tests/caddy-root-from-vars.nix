# vmTests.x86_64-linux.caddy-root-from-vars (CAM-87 design D11): a caddy whose
# storage is empty serves ntfy under both its names, ntfy.zt (until ZeroTier's
# retirement) and ntfy.<fleet domain>, under the root flake.modules.nixos.
# caddy-local-root configures, and writes no root of its own; the control
# node "minting", the same caddy without the module, mints a root, so the
# same client refuses it. The values related are the root made here and the
# chain each caddy serves. Non-gating: systemd-nspawn containers, because
# magnetite, where every x86_64-linux build of this change runs, offers
# uid-range and no kvm.
{ config, lib, ... }:
let
  module = config.flake.modules.nixos.caddy-local-root;
  # "ntfy.zt" goes with ZeroTier's retirement.
  names = [
    "ntfy.zt"
    "ntfy.${config.flake.lib.fleet.domain}"
  ];
in
{
  perSystem =
    { pkgs, system, ... }:
    let
      # The root is the same on every build, so its fingerprint is written
      # here rather than read from the build at evaluation: the key's scalar
      # is the sha256 of a fixed string, ECDSA signs with RFC 6979's
      # deterministic nonce, and the serial and validity are fixed (RFC 5280
      # 4.1.2.5's 99991231235959Z for no expiry). Were openssl to encode the
      # root differently, the module's recorded-root check fails the node's
      # build and prints the root's fingerprint.
      fingerprint = "34:B4:37:CE:5C:F2:7B:73:76:DD:33:68:AD:B5:D4:D2:CB:67:31:CF:DB:2D:0D:81:CA:AE:C9:C5:02:82:8D:ED";
      pki = pkgs.runCommand "caddy-root-from-vars-pki" { nativeBuildInputs = [ pkgs.openssl ]; } ''
        mkdir $out
        {
          printf '\x30\x31\x02\x01\x01\x04\x20'
          printf %s caddy-root-from-vars | openssl dgst -sha256 -binary
          printf '\xa0\x0a\x06\x08\x2a\x86\x48\xce\x3d\x03\x01\x07'
        } > key.der
        openssl ec -inform DER -in key.der -out $out/root.key
        openssl req -x509 -new -key $out/root.key -sha256 -sigopt nonce-type:1 -set_serial 1 \
          -not_before 20260101000000Z -not_after 99991231235959Z \
          -subj "/CN=caddy-root-from-vars test root" -addext basicConstraints=critical,CA:TRUE,pathlen:1 \
          -addext keyUsage=critical,keyCertSign,cRLSign -out $out/root.crt
      '';
      site = {
        services.caddy.enable = true;
        services.caddy.virtualHosts = lib.genAttrs names (_: {
          extraConfig = ''
            tls internal
            respond "ok"
          '';
        });
        networking.firewall.allowedTCPPorts = [ 443 ];
      };
    in
    {
      # Size class: the script measured 8.05 s, 20 s for the whole build with
      # the driver already built, on pyrite on 2026-11-24
      # (logs/tsc-3-measure-caddy-root-from-vars-20261124-133524.log).
      testSizes.vmTests = lib.optionalAttrs (system == "x86_64-linux") {
        caddy-root-from-vars.class = "small";
      };
      vmTests = lib.optionalAttrs (system == "x86_64-linux") {
        caddy-root-from-vars = pkgs.testers.runNixOSTest {
          name = "caddy-root-from-vars";
          requiredFeatures = {
            nixos-test = true;
            uid-range = true;
          };
          containers = {
            restored = {
              imports = [
                module
                site
              ];
              vanixiets.caddyLocalRoot = {
                certFile = "${pki}/root.crt";
                keyFile = "/etc/caddy-test/root.key";
                inherit fingerprint;
              };
              environment.etc."caddy-test/root.key" = {
                source = "${pki}/root.key";
                user = "caddy";
                mode = "0400";
              };
            };
            minting = site;
            client = {
              environment.systemPackages = [
                pkgs.curl
                pkgs.openssl
              ];
            };
          };
          testScript = ''
            start_all()
            for node in (restored, minting):
                node.wait_for_unit("caddy.service")
                node.wait_for_open_port(443)
            ca = "${pki}/root.crt"
            names = ${builtins.toJSON names}
            # The driver runs a command under errexit, so curl's exit code is
            # read from execute rather than echoed after it.
            def get(host, name):
                rc, code = client.execute(f"curl -s -o /dev/null -w '%{{http_code}}' --cacert {ca} --resolve {name}:443:$(getent ahostsv4 {host} | head -n 1 | cut -d' ' -f1) https://{name}/")
                got = f"{code.strip()} rc={rc}"
                print(f"{host} {name}: {got}")
                return got
            with subtest("restored serves under the configured root"):
                for name in names:
                    got = get("restored", name)
                    assert got.startswith("200"), got
                    client.succeed(f"openssl s_client -connect restored:443 -servername {name} -CAfile {ca} -verify_return_error < /dev/null")
                restored.fail("test -e /var/lib/caddy/.local/share/caddy/pki/authorities/local/root.crt")
            with subtest("minting: without the module the same client is refused"):
                for name in names:
                    got = get("minting", name)
                    assert got.endswith("rc=60"), got
          '';
        };
      };
    };
}
