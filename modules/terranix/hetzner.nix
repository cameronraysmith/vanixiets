{ config, ... }:
let
  hetznerMachines = config.flake.lib.cloudMachines.hetzner;
in
{
  flake.modules.terranix.hetzner =
    { config, lib, ... }:
    let
      # Machine deployment definitions: flake.lib.cloudMachines.hetzner
      # (modules/lib/cloud-machines.nix).
      machines = hetznerMachines;

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

      # DNS A records for enabled Hetzner servers
      resource.cloudflare_dns_record = lib.mapAttrs (name: _cfg: {
        zone_id = config.data.cloudflare_zone.scientistexperience "id";
        inherit name;
        type = "A";
        content = config.resource.hcloud_server.${name} "ipv4_address";
        ttl = 1; # automatic
        proxied = false;
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
