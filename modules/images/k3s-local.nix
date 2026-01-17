# k3s local development VM image using nixos-generators
#
# Builds a qcow-efi format image for Colima x86_64-linux VMs with:
# - k3s server (Cilium CNI integration via k3s-server module)
# - Rosetta for x86_64 emulation on Apple Silicon
# - SSH access with authorized keys
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
        # Target x86_64-linux for Colima VM (Rosetta handles emulation on aarch64-darwin)
        system = "x86_64-linux";

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

              # Rosetta for x86_64 emulation on Apple Silicon hosts
              # Colima mounts the Rosetta binary via Virtualization.framework
              virtualisation.rosetta = {
                enable = true;
                mountTag = "vz-rosetta";
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

              # 60 GB disk for k3s workloads (images, volumes, logs)
              virtualisation.diskSize = 60 * 1024;

              system.stateVersion = "24.11";
            }
          )
        ];
      };
    };
}
