# k3s local development VM image for incus
#
# Builds an aarch64-linux VM image for local ClusterAPI bootstrap:
# - k3s server (Cilium CNI integration via k3s-server module)
# - SSH access with authorized keys
#
# Runs natively on Apple Silicon via incus without emulation.
# Used to provision and manage x86_64-linux Hetzner production clusters.
# Architecture independence documented in ADR-002.
#
# Outputs:
#   k3s-local-image - Unified incus tarball (metadata + qcow2)
#   k3s-local-qcow  - Raw qcow2 for Hetzner, QEMU, other hypervisors
#
# Usage (incus):
#   nix build .#k3s-local-image
#   incus image import ./result/k3s-local.tar.gz --alias k3s-local
#   incus launch k3s-local k3s-dev --vm
#
# Usage (raw qcow2):
#   nix build .#k3s-local-qcow
#   # Upload ./result/nixos.qcow2 to Hetzner or use with QEMU
{
  inputs,
  config,
  ...
}:
let
  # Capture flake-level modules for use in nixosGenerate
  flakeModules = config.flake.modules.nixos;

  # Target architecture for local development
  targetSystem = "aarch64-linux";
in
{
  perSystem =
    { pkgs, ... }:
    let
      # Base qcow2 image from nixos-generators
      qcowImage = inputs.nixos-generators.nixosGenerate {
        # Native aarch64-linux for Apple Silicon (no emulation overhead)
        # ClusterAPI provisions x86_64-linux Hetzner clusters from this image
        system = targetSystem;

        # UEFI boot for modern VM compatibility
        format = "qcow-efi";

        # Pass flake modules and inputs via specialArgs for import access
        specialArgs = {
          inherit flakeModules;
          inherit inputs;
        };

        modules = [
          (
            {
              config,
              lib,
              pkgs,
              flakeModules,
              inputs,
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

              # Incus agent for incus exec support
              virtualisation.incus.agent.enable = true;

              # SSH access for VM management
              services.openssh = {
                enable = true;
                settings.PasswordAuthentication = false;
              };

              # Root user SSH access via centralized identity
              users.users.root.openssh.authorizedKeys.keys = inputs.self.lib.userIdentities.crs58.sshKeys;

              # Cloud-init for runtime configuration injection
              # Incus provides NoCloud datasource via user.network-config and user.meta-data
              services.cloud-init = {
                enable = true;
                network.enable = true;
              };

              # Use systemd-networkd for network management (required by cloud-init.network)
              networking.useNetworkd = true;

              # Delegate hostname to cloud-init meta-data
              # Priority 1337 is lower than mkDefault (1000) but higher than mkForce (50)
              networking.hostName = lib.mkOverride 1337 "";

              # DHCP fallback when no cloud-init network-config is provided
              # Cloud-init network-config v2 will override this when present
              systemd.network.networks."10-dhcp-fallback" = {
                matchConfig.Name = "en*";
                networkConfig = {
                  DHCP = "yes";
                  IPv6AcceptRA = true;
                };
                dhcpV4Config.UseDomains = true;
              };

              # Nix configuration for flake-based workflows
              nix.settings = {
                experimental-features = [
                  "flakes"
                  "nix-command"
                ];
                trusted-users = [ "@wheel" ];
              };

              # Console access for debugging (ttyAMA0 for ARM64 serial, tty0 for VGA)
              boot.kernelParams = [
                "console=ttyAMA0"
                "console=tty0"
              ];

              # 20 GB disk for development (expand at runtime if needed)
              virtualisation.diskSize = 20 * 1024;

              system.stateVersion = "24.11";
            }
          )
        ];
      };

      # incus architecture naming convention
      incusArch =
        if targetSystem == "aarch64-linux" then
          "aarch64"
        else if targetSystem == "x86_64-linux" then
          "x86_64"
        else
          throw "Unsupported system: ${targetSystem}";
    in
    {
      packages = {
        # Raw qcow2 for Hetzner VPS, QEMU, and other hypervisors
        k3s-local-qcow = qcowImage;

        # Unified incus image (metadata + qcow2 in tarball)
        k3s-local-image = pkgs.runCommand "k3s-local-incus-image" { } ''
          mkdir -p $out

          # Generate incus metadata
          cat > metadata.yaml <<EOF
          architecture: ${incusArch}
          creation_date: $(date +%s)
          properties:
            os: nixos
            release: unstable
            variant: k3s-local
            description: NixOS k3s local development VM (${targetSystem})
          EOF

          # Create unified incus image tarball
          # incus expects: metadata.yaml + rootfs.img (qcow2 renamed)
          # Use symlink + dereference (-h) to avoid copying 3GB+ file
          ln -s ${qcowImage}/nixos.qcow2 rootfs.img
          tar -czhvf $out/k3s-local.tar.gz metadata.yaml rootfs.img
        '';
      };
    };
}
