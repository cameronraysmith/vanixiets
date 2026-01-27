# DNS server for .zt zone on cinnabar's ZeroTier interface
#
# dnsmasq serves authoritative AAAA records for .zt hostnames, resolving
# them to cinnabar's ZeroTier IPv6 address. The ZeroTier controller pushes
# this DNS server to all network members. systemd-resolved routes .zt
# queries to dnsmasq via split DNS on the ZeroTier interface.
{ ... }:
{
  flake.modules.nixos."machines/nixos/cinnabar" = {
    services.dnsmasq = {
      enable = true;
      resolveLocalQueries = false;
      settings = {
        "listen-address" = "fddb:4344:343b:14b9:399:93db:4344:343b";
        "bind-dynamic" = true;
        "no-resolv" = true;
        "no-hosts" = true;
        address = [
          "/matrix.zt/fddb:4344:343b:14b9:399:93db:4344:343b"
          "/clawdbot.zt/fddb:4344:343b:14b9:399:93db:4344:343b"
        ];
      };
    };

    # Allow DNS queries from ZeroTier peers
    networking.firewall.interfaces."zt+".allowedTCPPorts = [ 53 ];
    networking.firewall.interfaces."zt+".allowedUDPPorts = [ 53 ];

    # Push DNS server to all ZeroTier network members
    clan.core.networking.zerotier.settings.dns = {
      domain = "zt";
      servers = [ "fddb:4344:343b:14b9:399:93db:4344:343b" ];
    };

    # Route .zt queries to local dnsmasq via systemd-resolved split DNS
    systemd.network.networks."09-zerotier" = {
      dns = [ "fddb:4344:343b:14b9:399:93db:4344:343b" ];
      domains = [ "~zt" ];
    };
  };
}
