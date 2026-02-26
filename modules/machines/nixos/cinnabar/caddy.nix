{ ... }:
{
  flake.modules.nixos."machines/nixos/cinnabar" = {
    services.caddy = {
      enable = true;
      virtualHosts = {
        "kanban.zt" = {
          listenAddresses = [
            "fddb:4344:343b:14b9:399:93db:4344:343b"
            "10.147.17.1"
          ];
          extraConfig = ''
            tls internal
            reverse_proxy localhost:3008
          '';
        };
        "beads.zt" = {
          listenAddresses = [
            "fddb:4344:343b:14b9:399:93db:4344:343b"
            "10.147.17.1"
          ];
          extraConfig = ''
            tls internal
            reverse_proxy localhost:3009
          '';
        };
        "matrix.zt" = {
          listenAddresses = [
            "fddb:4344:343b:14b9:399:93db:4344:343b"
            "10.147.17.1"
          ];
          extraConfig = ''
            tls internal
            reverse_proxy [::1]:8008
          '';
        };
        "ntfy.zt" = {
          listenAddresses = [
            "fddb:4344:343b:14b9:399:93db:4344:343b"
            "10.147.17.1"
          ];
          extraConfig = ''
            tls internal
            reverse_proxy [::1]:2586
          '';
        };
        "openclaw.zt" = {
          listenAddresses = [
            "fddb:4344:343b:14b9:399:93db:4344:343b"
            "10.147.17.1"
          ];
          extraConfig = ''
            tls internal
            reverse_proxy [::1]:18789
          '';
        };
      };
    };

    # only allow https on zerotier interfaces
    networking.firewall.interfaces."zt+".allowedTCPPorts = [ 443 ];
  };
}
