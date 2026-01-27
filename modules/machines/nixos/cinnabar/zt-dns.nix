# DNS server for .zt zone on cinnabar's ZeroTier interface
#
# dnsmasq serves authoritative A and AAAA records for .zt hostnames,
# resolving them to cinnabar's ZeroTier IPv4 and IPv6 addresses.
# Non-.zt queries are forwarded to Quad9 for clients that use
# ZeroTier-pushed DNS globally (Android).
# The ZeroTier controller pushes this DNS server to all network members.
# systemd-resolved routes .zt queries to dnsmasq via split DNS on the
# ZeroTier interface.
#
# Dual-stack (IPv4 + IPv6) is required because Android browsers query
# A records first and treat NXDOMAIN as a hard failure without falling
# back to AAAA.
{ lib, ... }:
{
  flake.modules.nixos."machines/nixos/cinnabar" =
    { config, pkgs, ... }:
    {
      services.dnsmasq = {
        enable = true;
        resolveLocalQueries = false;
        settings = {
          "listen-address" = "fddb:4344:343b:14b9:399:93db:4344:343b,10.147.17.1";
          "bind-dynamic" = true;
          "no-resolv" = true;
          "no-hosts" = true;
          server = [
            "9.9.9.9"
            "149.112.112.112"
          ];
          address = [
            "/matrix.zt/fddb:4344:343b:14b9:399:93db:4344:343b"
            "/matrix.zt/10.147.17.1"
            "/clawdbot.zt/fddb:4344:343b:14b9:399:93db:4344:343b"
            "/clawdbot.zt/10.147.17.1"
          ];
        };
      };

      networking.firewall.interfaces."zt+".allowedTCPPorts = [ 53 ];
      networking.firewall.interfaces."zt+".allowedUDPPorts = [ 53 ];

      clan.core.networking.zerotier.settings = {
        dns = {
          domain = "zt";
          servers = [
            "fddb:4344:343b:14b9:399:93db:4344:343b"
            "10.147.17.1"
          ];
        };

        # Enable IPv4 assignment for dual-stack (Android browsers need A records)
        v4AssignMode.zt = lib.mkForce true;
        ipAssignmentPools = [
          {
            ipRangeStart = "10.147.17.1";
            ipRangeEnd = "10.147.17.254";
          }
        ];
        routes = [
          {
            target = "10.147.17.0/24";
            via = null;
          }
        ];
      };

      # Pin cinnabar's own ZeroTier member to 10.147.17.1 so dnsmasq and
      # Caddy bind addresses are deterministic across rebuilds.
      # Appends to clan-core's ExecStartPost list (configure-interface,
      # whitelist-controller).
      systemd.services.zerotierone.serviceConfig.ExecStartPost = [
        "+${pkgs.writeShellScript "pin-controller-ipv4" ''
          NETWORK_ID="${config.clan.core.networking.zerotier.networkId}"
          MEMBER_ID=$(${pkgs.zerotierone}/bin/zerotier-cli info | ${pkgs.gawk}/bin/awk '{print $3}')
          AUTH=$(cat /var/lib/zerotier-one/authtoken.secret)
          IPV6="fddb:4344:343b:14b9:399:93db:4344:343b"

          ${pkgs.curl}/bin/curl -sf \
            -X POST \
            -H "X-ZT1-Auth: $AUTH" \
            -d "{\"ipAssignments\":[\"10.147.17.1\",\"$IPV6\"]}" \
            "http://localhost:9993/controller/network/$NETWORK_ID/member/$MEMBER_ID" \
            > /dev/null
        ''}"
      ];

      # Route .zt queries to local dnsmasq via systemd-resolved split DNS
      systemd.network.networks."09-zerotier" = {
        dns = [ "fddb:4344:343b:14b9:399:93db:4344:343b" ];
        domains = [ "~zt" ];
      };
    };
}
