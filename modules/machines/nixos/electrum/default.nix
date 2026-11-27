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
  flake.modules.nixos."machines/nixos/electrum" =
    {
      config,
      pkgs,
      ...
    }:
    {
      imports = [
        inputs.srvos.nixosModules.server
        inputs.home-manager.nixosModules.home-manager
      ]
      ++ (with flakeModules; [
        hetzner-cloud
        base
        home-manager-integration
        deploy-record
        kvm-declaration
        ssh-known-hosts
      ]);

      # Disko disk configuration extracted to disko.nix
      # Auto-merged via import-tree

      # Bootloader: UEFI with systemd-boot (CCX23 has native UEFI support)
      # GRUB off: the hetzner-cloud aspect's srvos module sets only grub.devices (mkDefault)
      boot.loader.grub.enable = false;
      boot.loader.systemd-boot.enable = true;
      boot.loader.efi.canTouchEfiVariables = true;

      # Hostname configuration
      networking.hostName = "electrum";

      networking.search = [ ];

      # Hetzner CCX23 with no nested virtualisation, so no /dev/kvm.
      declaredKvm.present = false;

      # User configuration now managed via clan inventory users service
      # See: modules/clan/inventory/services/users.nix (user-cameron instance)
      # Provides: cameron user, wheel/networkmanager groups, zsh shell,
      #           home-manager integration, vars-based password management

      # Allow wheel group sudo without password
      security.sudo.wheelNeedsPassword = false;

      # Firewall configuration
      networking.firewall = {
        enable = true;
        # Allow SSH (configured by srvos.nixosModules.server)
        # Additional ports can be opened as needed
      };
    };
}
