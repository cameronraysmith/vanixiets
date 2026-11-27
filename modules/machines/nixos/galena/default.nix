{
  config,
  inputs,
  ...
}:
let
  # Capture outer config for use in imports
  flakeModules = config.flake.modules.nixos;
in
{
  # Export host module to flake namespace
  flake.modules.nixos."machines/nixos/galena" =
    {
      config,
      ...
    }:
    {
      imports = [
        inputs.srvos.nixosModules.server
        inputs.home-manager.nixosModules.home-manager
      ]
      ++ (with flakeModules; [
        gcp-cloud
        base
        home-manager-integration
        deploy-record
        hm-sops-bridge
        kvm-declaration
        ssh-known-hosts
      ]);

      # Disko disk configuration extracted to disko.nix
      # Auto-merged via import-tree

      # Bootloader: UEFI with systemd-boot (GCP defaults to UEFI since April 2020)
      boot.loader.grub.enable = false;
      boot.loader.systemd-boot.enable = true;
      boot.loader.efi.canTouchEfiVariables = true;

      # Hostname configuration
      networking.hostName = "galena";

      networking.search = [ ];

      # GCP VM with no nested virtualisation, so no /dev/kvm.
      declaredKvm.present = false;

      # User configuration managed via clan inventory users service

      # Allow wheel group sudo without password
      security.sudo.wheelNeedsPassword = false;

      # Networking configuration
      # Configure networkd for GCP VMs; the uplink is gcp-cloud's
      networking.useNetworkd = true;
      networking.useDHCP = false;

      # Firewall configuration
      networking.firewall = {
        enable = true;
        # Allow SSH (configured by srvos.nixosModules.server)
        # Additional ports can be opened as needed
      };
    };
}
