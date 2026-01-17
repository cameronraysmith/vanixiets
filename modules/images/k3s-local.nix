# k3s local development VM image using nixos-generators
#
# Builds a qcow-efi format image for Colima x86_64-linux VMs with:
# - k3s server (Cilium CNI integration via k3s-server module)
# - SSH access with authorized keys
#
# The VM runs x86_64-linux. On Apple Silicon hosts, Colima uses
# Virtualization.framework with Rosetta for x86_64 translation at the
# hypervisor level — no guest-side Rosetta configuration needed.
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
        # Target x86_64-linux for production parity with Hetzner
        # On Apple Silicon, Colima uses Virtualization.framework + Rosetta
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
