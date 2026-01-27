# ZeroTier .zt domain resolver for darwin hosts
#
# Creates /etc/resolver/zt to route .zt queries directly to cinnabar's
# ZeroTier DNS server. The macOS resolver checks /etc/resolver/* before
# the default nameserver, so .zt queries bypass local DNS (dnscrypt-proxy
# or dnsmasq) and go straight to cinnabar over the ZeroTier network.
{ ... }:
{
  flake.modules.darwin.zt-dns = {
    environment.etc."resolver/zt" = {
      enable = true;
      text = ''
        nameserver fddb:4344:343b:14b9:399:93db:4344:343b
      '';
    };
  };
}
