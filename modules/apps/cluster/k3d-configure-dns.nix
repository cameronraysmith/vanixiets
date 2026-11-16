# k3d-configure-dns.nix - Patch CoreDNS to answer IPv4 sslip.io names in-cluster.
#
# The ACME HTTP-01 self-check resolves the *.192.168.100.3.sslip.io route
# hostnames through CoreDNS; they are computed in-cluster because resolvers
# with DNS-rebinding protection strip private-address answers. Other
# sslip.io queries still forward to 1.1.1.1 and 8.8.8.8.
# Idempotent: second invocation exits 0 without patching.
{ ... }:
{
  perSystem =
    { pkgs, lib, ... }:
    {
      apps.k3d-configure-dns = {
        type = "app";
        program = lib.getExe (
          pkgs.writeShellApplication {
            name = "k3d-configure-dns";
            runtimeInputs = [
              pkgs.bash
              pkgs.coreutils
              pkgs.gnugrep
              pkgs.jq
              pkgs.kubectl
            ];
            text = builtins.readFile ./k3d-configure-dns.sh;
          }
        );
      };
    };
}
