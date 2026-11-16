# Key for the ZeroTier interfaces in networking.firewall.interfaces. The
# iptables firewall hands the key to -i, whose wildcard is a trailing +; the
# nftables firewall writes it unquoted after iifname, where the wildcard is a
# trailing * and a + fails the ruleset check, so one literal cannot serve both.
{ ... }:
{
  flake.lib.zerotierInterfaces =
    config: if config.networking.firewall.backend == "nftables" then "zt*" else "zt+";
}
