# k3d-configure-dns.nix - Patch CoreDNS to forward sslip.io queries to public DNS.
#
# Required because OrbStack's default DNS (192.168.107.1) cannot resolve
# sslip.io wildcards used by the local ArgoCD application routes.
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
