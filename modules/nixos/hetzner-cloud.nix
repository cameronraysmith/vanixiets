# The shape a Hetzner Cloud server takes, declared once for every host on
# that provider: srvos's hardware module (cloud-init, the QEMU guest
# profile, growPartition, GRUB devices at mkDefault, networkd with DHCP off),
# the boot loader its server type gives, remote unlock over initrd SSH, ZFS
# device nodes by path, and the primary uplink. A host imports the aspect of
# the provider it runs on (modules/nixos/gcp-cloud.nix is the other); the
# assertion holds that choice to the registry's
# flake.fleet.hosts.<host>.cloud.provider, so the two cannot disagree.
{
  config,
  inputs,
  lib,
  ...
}:
let
  inherit (config.flake.lib) hosts;
  inherit (config.flake.modules.nixos) initrd-networking;
  provider = "hetzner";

  # Dedicated (ccx) and ARM (cax) types boot native UEFI; shared-vCPU (cx)
  # types boot legacy BIOS through the GRUB devices srvos declares. null for
  # a type with no mapping.
  loaderFor =
    type:
    if lib.hasPrefix "ccx" type || lib.hasPrefix "cax" type then
      "systemd-boot"
    else if lib.hasPrefix "cx" type then
      "grub"
    else
      null;

  loaderOf =
    boot:
    let
      grub = boot.loader.grub.enable;
      systemdBoot = boot.loader.systemd-boot.enable;
    in
    if grub && systemdBoot then
      "both grub and systemd-boot"
    else if grub then
      "grub"
    else if systemdBoot then
      "systemd-boot"
    else
      "no boot loader";

  problems =
    {
      name,
      type,
      boot,
    }:
    let
      expected = loaderFor type;
      actual = loaderOf boot;
    in
    if expected == null then
      [
        "${name}'s Hetzner server type ${type} has no boot loader in modules/nixos/hetzner-cloud.nix's loaderFor"
      ]
    else
      lib.optional (
        actual != expected
      ) "${name} boots with ${actual}, but its Hetzner server type ${type} boots with ${expected}";
in
{
  flake.lib.hetznerBootLoader = {
    inherit loaderFor problems;
  };

  # The aspect sets the loader from the type, so this catches a host file
  # overriding it.
  fleetObligations.hetznerBootLoader = {
    classes = [ "nixos" ];
    failures =
      name: hostConfig:
      let
        cloud = hosts.${name}.cloud or null;
      in
      lib.optionals (cloud != null && cloud.provider == provider) (problems {
        inherit name;
        inherit (cloud) type;
        inherit (hostConfig) boot;
      });
  };

  flake.modules.nixos.hetzner-cloud =
    { config, ... }:
    let
      inherit (config.networking) hostName;
      cloud = hosts.${hostName}.cloud or null;
    in
    {
      imports = [
        inputs.srvos.nixosModules.hardware-hetzner-cloud
        initrd-networking
      ];

      assertions = [
        {
          assertion = cloud != null && cloud.provider == provider;
          message = "${hostName} imports flake.modules.nixos.hetzner-cloud, but flake.fleet.hosts.${hostName}.cloud.provider is ${
            if cloud == null then "unset" else builtins.toJSON cloud.provider
          }, not ${builtins.toJSON provider}";
        }
      ];

      boot.loader =
        lib.mkIf (cloud != null && cloud.provider == provider && loaderFor cloud.type == "systemd-boot")
          {
            grub.enable = false;
            systemd-boot.enable = true;
            efi.canTouchEfiVariables = true;
          };

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
