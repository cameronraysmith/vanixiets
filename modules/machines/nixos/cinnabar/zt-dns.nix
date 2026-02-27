# DNS server for .zt zone on cinnabar's zerotier interface
#
# dnsmasq serves authoritative A and AAAA records for .zt hostnames,
# resolving service names (kanban, beads, etc.) to cinnabar and machine
# hostnames (stibnite, blackphos, etc.) to their zerotier addresses.
# Non-.zt queries are forwarded to quad9 for clients that use
# zerotier-pushed DNS globally.
# The zerotier controller pushes this DNS server to all network members.
# systemd-resolved routes .zt queries to dnsmasq via split DNS on the
# zerotier interface.
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
            "/kanban.zt/fddb:4344:343b:14b9:399:93db:4344:343b"
            "/kanban.zt/10.147.17.1"
            "/beads.zt/fddb:4344:343b:14b9:399:93db:4344:343b"
            "/beads.zt/10.147.17.1"
            "/matrix.zt/fddb:4344:343b:14b9:399:93db:4344:343b"
            "/matrix.zt/10.147.17.1"
            "/ntfy.zt/fddb:4344:343b:14b9:399:93db:4344:343b"
            "/ntfy.zt/10.147.17.1"
            "/openclaw.zt/fddb:4344:343b:14b9:399:93db:4344:343b"
            "/openclaw.zt/10.147.17.1"

            # Machine hostnames (for non-SSH service discovery via meta.domain = "zt")
            "/cinnabar.zt/fddb:4344:343b:14b9:399:93db:4344:343b"
            "/cinnabar.zt/10.147.17.1"
            "/electrum.zt/fddb:4344:343b:14b9:399:93d1:7e6d:27cc"
            "/galena.zt/fddb:4344:343b:14b9:399:9315:c67a:dec9"
            "/scheelite.zt/fddb:4344:343b:14b9:399:9380:46d5:3400"
            "/stibnite.zt/fddb:4344:343b:14b9:399:933e:1059:d43a"
            "/blackphos.zt/fddb:4344:343b:14b9:399:930e:e971:d9e0"
            "/argentum.zt/fddb:4344:343b:14b9:399:93f7:54d5:ad7e"
            "/rosegold.zt/fddb:4344:343b:14b9:399:9315:3431:ee8"
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

      # Pin cinnabar's own zerotier member to 10.147.17.1 so dnsmasq and
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

      # TCP MSS clamping on zerotier interfaces to avoid PMTU black holes.
      # Mobile carriers (5G/LTE) silently drop packets exceeding ~1374 bytes
      # without sending ICMP fragmentation-needed. The zerotier tun0 advertises
      # MTU 2800 but the real path MTU is lower, causing TLS handshakes (~1500
      # bytes) to time out. Clamping MSS to 1300 keeps TCP segments within the
      # constrained path MTU. OUTPUT clamps cinnabar's SYN-ACK (tells remote
      # to send small segments). INPUT clamps incoming SYN (tells Caddy the
      # remote accepts small segments, so Caddy sends small responses).
      networking.firewall.extraCommands = ''
        iptables -t mangle -A OUTPUT -o zt+ -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --set-mss 1300
        ip6tables -t mangle -A OUTPUT -o zt+ -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --set-mss 1300
        iptables -t mangle -A INPUT -i zt+ -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --set-mss 1300
        ip6tables -t mangle -A INPUT -i zt+ -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --set-mss 1300
      '';

      # Route .zt queries to local dnsmasq via systemd-resolved split DNS
      systemd.network.networks."09-zerotier" = {
        dns = [ "fddb:4344:343b:14b9:399:93db:4344:343b" ];
        domains = [ "~zt" ];
      };
    };
}
