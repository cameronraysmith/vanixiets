# k3s local development VM image using nixos-generators
#
# Builds an aarch64-linux qcow-efi image for local ClusterAPI bootstrap:
# - k3s server (Cilium CNI integration via k3s-server module)
# - SSH access with authorized keys
#
# Runs natively on Apple Silicon via Colima/incus without emulation.
# Used to provision and manage x86_64-linux Hetzner production clusters.
# Architecture independence documented in ADR-002.
#
# Usage: nix build .#k3s-local-image
{
  inputs,
  config,
  ...
}:
let
  # Capture flake-level modules for use in nixosGenerate
  flakeModules = config.flake.modules.nixos;
in
{
  perSystem =
    { system, ... }:
    {
      packages.k3s-local-image = inputs.nixos-generators.nixosGenerate {
        # Native aarch64-linux for Apple Silicon (no emulation overhead)
        # ClusterAPI provisions x86_64-linux Hetzner clusters from this image
        system = "aarch64-linux";

        # UEFI boot for modern VM compatibility
        format = "qcow-efi";

        # Pass flake modules via specialArgs for import access
        specialArgs = {
          inherit flakeModules;
        };

        modules = [
          (
            {
              config,
              lib,
              pkgs,
              flakeModules,
              ...
            }:
            {
              imports = [
                flakeModules.k3s-server
              ];

              # Enable k3s server as cluster initializer
              k3s-server = {
                enable = true;
                clusterInit = true;
              };

              # SSH access for VM management
              services.openssh = {
                enable = true;
                settings.PasswordAuthentication = false;
              };

              # Root user SSH access (configure with your keys)
              # TODO: integrate with sops-nix or clan vars for key management
              users.users.root.openssh.authorizedKeys.keys = [
                # Add authorized keys here or via specialArgs
              ];

              # Nix configuration for flake-based workflows
              nix.settings = {
                experimental-features = [
                  "flakes"
                  "nix-command"
                ];
                trusted-users = [ "@wheel" ];
              };

              # Console access for debugging
              boot.kernelParams = [ "console=tty0" ];

              # 20 GB disk for development (expand at runtime if needed)
              virtualisation.diskSize = 20 * 1024;

              system.stateVersion = "24.11";
            }
          )
        ];
      };
    };
}
