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
