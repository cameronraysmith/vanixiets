# TCP MSS clamping on zerotier interfaces to avoid PMTU black holes.
#
# Mobile carriers (5G/LTE) silently drop packets exceeding ~1374 bytes without
# sending ICMP fragmentation-needed. The zerotier interface advertises MTU 2800
# but the real path MTU is lower, so any TCP segment between those sizes (TLS
# handshakes, SSH key exchange) is dropped and the connection stalls.
#
# Clamping MSS to 1300 on every SYN crossing a zerotier interface keeps TCP
# segments within the constrained path MTU in both directions: OUTPUT clamps
# this host's SYN/SYN-ACK so the remote sends small segments; INPUT clamps the
# remote's SYN so local services send small responses.
#
# Attached to every zerotier role through the clan inventory so each host that
# joins the network carries the clamp; a client-side MTU change is never needed.
{ ... }:
{
  flake.modules.nixos.zerotier-mss-clamp =
    { ... }:
    {
      networking.firewall.extraCommands = ''
        iptables -t mangle -A OUTPUT -o zt+ -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --set-mss 1300
        ip6tables -t mangle -A OUTPUT -o zt+ -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --set-mss 1300
        iptables -t mangle -A INPUT -i zt+ -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --set-mss 1300
        ip6tables -t mangle -A INPUT -i zt+ -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --set-mss 1300
      '';
    };
}
