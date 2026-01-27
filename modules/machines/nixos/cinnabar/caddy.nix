# Caddy reverse proxy on cinnabar's ZeroTier interface
{ ... }:
{
  flake.modules.nixos."machines/nixos/cinnabar" = {
    services.caddy = {
      enable = true;
      virtualHosts = {
        "matrix.zt" = {
          listenAddresses = [ "fddb:4344:343b:14b9:399:93db:4344:343b" ];
          extraConfig = ''
            tls internal
            reverse_proxy [::1]:8008
          '';
        };
        "clawdbot.zt" = {
          listenAddresses = [ "fddb:4344:343b:14b9:399:93db:4344:343b" ];
          extraConfig = ''
            tls internal
            reverse_proxy [::1]:18789
          '';
        };
      };
    };

    # Only allow HTTPS on ZeroTier interfaces, not public
    networking.firewall.interfaces."zt+".allowedTCPPorts = [ 443 ];
  };
}
