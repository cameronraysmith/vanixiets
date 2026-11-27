# The shape a Hetzner Cloud server takes, declared once for every host on
# that provider: srvos's hardware module (cloud-init, the QEMU guest
# profile, growPartition, GRUB devices at mkDefault, networkd with DHCP off),
# ZFS device nodes by path, and the primary uplink. A host imports the
# aspect of the provider it runs on (modules/nixos/gcp-cloud.nix is the
# other); the assertion holds that choice to the registry's
# flake.fleet.hosts.<host>.cloud.provider, so the two cannot disagree.
{ config, inputs, ... }:
let
  inherit (config.flake.lib) hosts;
  provider = "hetzner";
in
{
  flake.modules.nixos.hetzner-cloud =
    { config, ... }:
    let
      inherit (config.networking) hostName;
      cloud = hosts.${hostName}.cloud or null;
    in
    {
      imports = [ inputs.srvos.nixosModules.hardware-hetzner-cloud ];

      assertions = [
        {
          assertion = cloud != null && cloud.provider == provider;
          message = "${hostName} imports flake.modules.nixos.hetzner-cloud, but flake.fleet.hosts.${hostName}.cloud.provider is ${
            if cloud == null then "unset" else builtins.toJSON cloud.provider
          }, not ${builtins.toJSON provider}";
        }
      ];

      # ZFS device node path - more stable for cloud VMs
      boot.zfs.devNodes = "/dev/disk/by-path";

      # srvos hardware-hetzner-cloud sets useNetworkd=true and useDHCP=false;
      # configure the primary interface with DHCP.
      systemd.network.networks."10-uplink" = {
        matchConfig.Name = "en*";
        networkConfig = {
          DHCP = "yes";
          IPv6AcceptRA = true;
        };
        dhcpV4Config.UseDNS = true;
        dhcpV6Config.UseDNS = true;
      };
    };
}
