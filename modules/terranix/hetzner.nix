{ ... }:
{
  flake.modules.terranix.hetzner =
    { config, lib, ... }:
    let
      # Machine deployment definitions
      # Set enabled = true to deploy, false to destroy
      # Run: nix run .#terraform (regenerates config and applies)
      machines = {
        cinnabar = {
          enabled = true; # Primary VPS, zerotier controller (CX43: BIOS + GRUB)
          serverType = "cx43";
          location = "fsn1";
          image = "debian-12";
          comment = "8 vCPU, 16GB RAM, 160GB SSD, legacy BIOS";
        };
        electrum = {
          enabled = false; # Secondary test VM, zerotier peer (CCX23: UEFI + systemd-boot)
          serverType = "ccx23";
          location = "fsn1";
          image = "debian-12";
          comment = "4 vCPU, 16GB RAM, 160GB SSD, native UEFI";
        };
      };

      # Filter to only enabled machines
      enabledMachines = lib.filterAttrs (_name: cfg: cfg.enabled) machines;
    in
    {
      # SSH key resources for terraform deployment
      terraform.required_providers.tls.source = "hashicorp/tls";
      terraform.required_providers.null.source = "hashicorp/null";

      # Generate ED25519 SSH key for terraform deployment
      resource.tls_private_key.ssh_deploy_key = {
        algorithm = "ED25519";
      };

      # Store private key locally for clan machines install
      resource.local_sensitive_file.ssh_deploy_key = {
        filename = "${lib.tf.ref "path.module"}/.terraform-deploy-key";
        file_permission = "600";
        content = config.resource.tls_private_key.ssh_deploy_key "private_key_openssh";
      };

      # Register SSH key with Hetzner Cloud
      resource.hcloud_ssh_key.terraform = {
        name = "test-clan-terraform-deploy";
        public_key = config.resource.tls_private_key.ssh_deploy_key "public_key_openssh";
      };

      # Hetzner Cloud servers (generated from enabled machines)
      resource.hcloud_server = lib.mapAttrs (name: cfg: {
        inherit name;
        server_type = cfg.serverType;
        location = cfg.location;
        image = cfg.image;
        ssh_keys = [
          (config.resource.hcloud_ssh_key.terraform "id")
        ];
      }) enabledMachines;

      # Provision NixOS via clan machines install (generated from enabled machines)
      resource.null_resource = lib.mapAttrs' (
        name: cfg:
        lib.nameValuePair "install-${name}" {
          provisioner.local-exec = {
            command = "clan machines install ${name} --update-hardware-config nixos-facter --target-host root@${
              config.resource.hcloud_server.${name} "ipv4_address"
            } -i '${config.resource.local_sensitive_file.ssh_deploy_key "filename"}' --yes";
          };
        }
      ) enabledMachines;
    };
}
