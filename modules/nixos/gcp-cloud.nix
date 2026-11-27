# The shape a Google Compute Engine server takes, declared once for every
# host on that provider: ZFS device nodes by path and the primary uplink,
# matching both interface namings GCE images use. It imports no srvos
# hardware module (srvos's is Hetzner's). A host imports the aspect of the
# provider it runs on (modules/nixos/hetzner-cloud.nix is the other); the
# assertion holds that choice to the registry's
# flake.fleet.hosts.<host>.cloud.provider, so the two cannot disagree.
{ config, ... }:
let
  inherit (config.flake.lib) hosts;
  provider = "gcp";
in
{
  flake.modules.nixos.gcp-cloud =
    { config, ... }:
    let
      inherit (config.networking) hostName;
      cloud = hosts.${hostName}.cloud or null;
    in
    {
      assertions = [
        {
          assertion = cloud != null && cloud.provider == provider;
          message = "${hostName} imports flake.modules.nixos.gcp-cloud, but flake.fleet.hosts.${hostName}.cloud.provider is ${
            if cloud == null then "unset" else builtins.toJSON cloud.provider
          }, not ${builtins.toJSON provider}";
        }
      ];

      # ZFS device node path - more stable for cloud VMs
      boot.zfs.devNodes = "/dev/disk/by-path";

      systemd.network.networks."10-uplink" = {
        matchConfig.Name = "en* eth*";
        networkConfig = {
          DHCP = "yes";
          IPv6AcceptRA = true;
        };
        dhcpV4Config.UseDNS = true;
        dhcpV6Config.UseDNS = true;
      };
    };
}
