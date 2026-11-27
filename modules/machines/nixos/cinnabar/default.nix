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
  flake.modules.nixos."machines/nixos/cinnabar" =
    {
      config,
      pkgs,
      lib,
      ...
    }:
    {
      # cinnabar's features, each under its own key in this directory, sit
      # where import-tree's file order placed them when they were sibling
      # definitions of this module: the three caddy files before this body's
      # imports, the rest after them.
      imports =
        (with flakeModules; [
          caddy-root-ca
          caddy-root-check
          caddy
        ])
        ++ [
          inputs.srvos.nixosModules.server
          inputs.home-manager.nixosModules.home-manager
        ]
        ++ (with flakeModules; [
          hetzner-cloud
          base
          home-manager-integration
          deploy-record
          fleet-alert
          fleet-deployer
          hm-sops-bridge
          kvm-declaration
          ntfy-alerter
          observability-notify
          ssh-known-hosts
          fleet-alert-deadman
          matrix-server
          ntfy-server
          radicle-node
          zt-dns-server
        ]);

      # Disko disk configuration extracted to disko.nix
      # Auto-merged via import-tree

      # Bootloader: GRUB BIOS mode (CX43 has legacy BIOS only, not UEFI)
      # The hetzner-cloud aspect (srvos's Hetzner hardware module) handles GRUB BIOS configuration

      # Hostname configuration
      networking.hostName = "cinnabar";

      networking.search = [ ];

      # Hetzner CX43 with no nested virtualisation, so no /dev/kvm.
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
