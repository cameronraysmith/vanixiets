{ config, ... }:
let
  tincrPort = toString config.flake.lib.mesh.port;
  gcpMachines = config.flake.lib.cloudMachines.gcp;
in
{
  flake.modules.terranix.gcp =
    {
      config,
      pkgs,
      lib,
      ...
    }:
    let
      # GCP project configuration
      # Project ID configured here, credentials via clan secrets at runtime
      gcpProject = "sciexp";
      defaultRegion = "us-central1";
      defaultZone = "us-central1-b";

      # Machine deployment definitions: flake.lib.cloudMachines.gcp
      # (modules/lib/cloud-machines.nix), with the cost reference table.
      machines = gcpMachines;

      # Filter to enabled machines
      enabledMachines = lib.filterAttrs (_name: cfg: cfg.enabled) machines;
    in
    {
      # Version constraint needs to be compatible with nixpkgs terraform-providers.hashicorp_google
      terraform.required_providers.google = {
        source = "hashicorp/google";
        version = "~> 8.0";
      };
      terraform.required_providers.tls.source = "hashicorp/tls";
      terraform.required_providers.null.source = "hashicorp/null";

      # Fetch GCP service account credentials from clan secrets
      data.external.gcp-service-account = {
        program = [
          (lib.getExe (
            pkgs.writeShellApplication {
              name = "get-gcp-secret";
              text = ''
                jq -n --arg secret "$(clan secrets get gcp-service-account-json)" '{"secret":$secret}'
              '';
            }
          ))
        ];
      };

      # Configure Google Cloud provider with service account credentials
      provider.google = {
        project = gcpProject;
        region = defaultRegion;
        zone = defaultZone;
        credentials = config.data.external.gcp-service-account "result.secret";
      };

      # Generate ED25519 SSH key for terraform deployment
      resource.tls_private_key.gcp_deploy_key = {
        algorithm = "ED25519";
      };

      # Store private key locally for clan machines install
      resource.local_sensitive_file.gcp_deploy_key = {
        filename = "${lib.tf.ref "path.module"}/.gcp-terraform-deploy-key";
        file_permission = "600";
        content = config.resource.tls_private_key.gcp_deploy_key "private_key_openssh";
      };

      # Firewall rule: Allow SSH (tcp/22) for clan machines install
      resource.google_compute_firewall.allow_ssh = {
        name = "allow-ssh-terraform";
        network = "default";
        allow = [
          {
            protocol = "tcp";
            ports = [ "22" ];
          }
        ];
        source_ranges = [ "0.0.0.0/0" ];
        target_tags = [ "terraform-managed" ];
      };

      # Firewall rule: Allow ZeroTier (udp/9993) for mesh networking
      resource.google_compute_firewall.allow_zerotier = {
        name = "allow-zerotier-terraform";
        network = "default";
        allow = [
          {
            protocol = "udp";
            ports = [ "9993" ];
          }
        ];
        source_ranges = [ "0.0.0.0/0" ];
        target_tags = [ "terraform-managed" ];
      };

      # Firewall rule: Allow tincr (tcp and udp, flake.lib.mesh.port) for the tincr mesh
      resource.google_compute_firewall.allow_tincr = {
        name = "allow-tincr-terraform";
        network = "default";
        allow = [
          {
            protocol = "tcp";
            ports = [ tincrPort ];
          }
          {
            protocol = "udp";
            ports = [ tincrPort ];
          }
        ];
        source_ranges = [ "0.0.0.0/0" ];
        target_tags = [ "terraform-managed" ];
      };

      # GCP Compute instances (generated from enabled machines)
      resource.google_compute_instance = lib.mapAttrs (
        name: cfg:
        {
          inherit name;
          machine_type = cfg.machineType;
          zone = cfg.zone or defaultZone;
          tags = [ "terraform-managed" ];

          boot_disk = {
            initialize_params = {
              # Debian 12 image for NixOS installation (same as Hetzner pattern)
              image = "debian-cloud/debian-12";
              size = 100; # GB, default size
            };
          };

          # Network interface with external IP for SSH access
          network_interface = {
            network = "default";
            # access_config block grants external IP
            access_config = { };
          };

          # SSH key via instance metadata (GCP-specific pattern)
          # Format: "username:ssh-key-type key-data comment"
          metadata = {
            ssh-keys = "root:${config.resource.tls_private_key.gcp_deploy_key "public_key_openssh"}";
            # Startup script to enable root SSH (Debian defaults to PermitRootLogin no)
            # Required for nixos-anywhere/clan machines install
            startup-script = ''
              #!/bin/bash
              set -e
              # Enable root login for nixos-anywhere installation
              sed -i 's/^PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config
              sed -i 's/^#PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config
              # Ensure root authorized_keys is set from metadata
              mkdir -p /root/.ssh
              chmod 700 /root/.ssh
              curl -sf "http://metadata.google.internal/computeMetadata/v1/instance/attributes/ssh-keys" \
                -H "Metadata-Flavor: Google" | grep "^root:" | cut -d: -f2- > /root/.ssh/authorized_keys
              chmod 600 /root/.ssh/authorized_keys
              # Restart sshd
              systemctl restart sshd
            '';
          };
        }
        // lib.optionalAttrs (cfg ? gpuType && cfg ? gpuCount) {
          guest_accelerator = [
            {
              type = cfg.gpuType;
              count = cfg.gpuCount;
            }
          ];
          # GPU instances require on_host_maintenance = "TERMINATE"
          scheduling = {
            on_host_maintenance = "TERMINATE";
          };
        }
      ) enabledMachines;

      # Provision NixOS via clan machines install (generated from enabled machines)
      resource.null_resource = lib.mapAttrs' (
        name: cfg:
        lib.nameValuePair "install-gcp-${name}" {
          provisioner.local-exec = {
            command = "clan machines install ${name} --update-hardware-config nixos-facter --target-host root@${
              config.resource.google_compute_instance.${name} "network_interface[0].access_config[0].nat_ip"
            } -i '${config.resource.local_sensitive_file.gcp_deploy_key "filename"}' --yes";
          };
        }
      ) enabledMachines;
    };
}
