# scheelite: GPU-capable GCP node (L4 NVIDIA accelerator)
# Named after tungsten ore mineral (CaWO4) - metallurgical naming theme
# Target: Headless ML training/inference (JAX, PyTorch)
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
  flake.modules.nixos."machines/nixos/scheelite" =
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
        kvm-declaration
        ssh-known-hosts
        nvidia # GPU/CUDA support (datacenter-optimized)
      ]);

      # Disko disk configuration extracted to disko.nix
      # Auto-merged via import-tree

      # Bootloader: UEFI with systemd-boot (GCP defaults to UEFI since April 2020)
      boot.loader.grub.enable = false;
      boot.loader.systemd-boot.enable = true;
      boot.loader.efi.canTouchEfiVariables = true;

      # Hostname configuration
      networking.hostName = "scheelite";

      networking.search = [ ];

      # GCP L4 node with no nested virtualisation, so no /dev/kvm. The GPU
      # features come from nixpkgs' nix-required-mounts nvidia-gpu preset, which
      # the kvm-declaration force would otherwise discard; they are carried over
      # from that module's own option rather than restated as literals.
      declaredKvm = {
        present = false;
        extraFeatures = config.programs.nix-required-mounts.allowedPatterns.nvidia-gpu.onFeatures;
      };

      # User configuration managed via clan inventory users service
      # Zerotier peer configuration via clan inventory

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
