# Split DNS for the ZeroTier .zt zone
#
# cinnabar's dnsmasq (machines/nixos/cinnabar/zt-dns.nix) answers for .zt on
# its ZeroTier address. Clients send only .zt names there; every other name
# keeps its usual path (the local dnscrypt-proxy where enabled).
{ ... }:
let
  ztDnsServer = "fddb:4344:343b:14b9:399:93db:4344:343b";
in
{
  # macOS consults /etc/resolver/<domain> for names under that domain
  flake.modules.darwin.zt-dns = {
    environment.etc."resolver/zt" = {
      enable = true;
      text = ''
        nameserver ${ztDnsServer}
      '';
    };
  };

  # systemd-resolved routes names under a link's route-only domain (~zt) to
  # that link's servers. 09-zerotier is the network clan's zerotier module
  # defines for the zt* interfaces.
  flake.modules.nixos.zt-dns = {
    systemd.network.networks."09-zerotier" = {
      dns = [ ztDnsServer ];
      domains = [ "~zt" ];
    };
  };
}
