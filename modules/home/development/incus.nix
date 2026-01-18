# incus profile configuration for k3s local development
#
# Configures incus profiles for NixOS VMs running in Colima.
# Disables Secure Boot (NixOS images are unsigned) and sets resource limits.
# Includes cloud-init network-config v2 for static IP assignment per ADR-004.
#
# Usage: Profiles are applied via home-manager activation on switch.
# Note: incus client is Linux-only; Darwin machines use remote incus via Colima.
{ ... }:
{
  flake.modules.homeManager.development =
    {
      pkgs,
      lib,
      config,
      ...
    }:
    let
      cfg = config.incus;

      # Submodule type for k3s profile configuration
      profileModule = lib.types.submodule {
        options = {
          enable = lib.mkOption {
            type = lib.types.bool;
            default = true;
            description = "Whether to enable this incus profile.";
          };

          ip = lib.mkOption {
            type = lib.types.str;
            description = "Static IP address for the VM (e.g., '192.100.0.10').";
          };

          gateway = lib.mkOption {
            type = lib.types.str;
            default = "192.100.0.1";
            description = "Gateway address for the incus bridge network.";
          };

          cpu = lib.mkOption {
            type = lib.types.int;
            default = 4;
            description = "Number of CPU cores to allocate.";
          };

          memory = lib.mkOption {
            type = lib.types.str;
            default = "8GiB";
            description = "Memory limit for the VM.";
          };
        };
      };

      # Generate profile YAML with cloud-init configuration
      mkProfileYaml =
        name: profileCfg:
        ''
          name: ${name}
          description: "${name} VM profile with static IP"
          config:
            security.secureboot: "false"
            limits.cpu: "${toString profileCfg.cpu}"
            limits.memory: "${profileCfg.memory}"
            user.network-config: |
              network:
                version: 2
                ethernets:
                  enp5s0:
                    addresses:
                      - ${profileCfg.ip}/24
                    routes:
                      - to: default
                        via: ${profileCfg.gateway}
            user.meta-data: |
              #cloud-config
              hostname: ${name}
          devices:
            eth0:
              name: eth0
              network: incusbr0
              type: nic
            root:
              path: /
              pool: default
              type: disk
        '';

      # Filter to enabled profiles only
      enabledProfiles = lib.filterAttrs (_name: profileCfg: profileCfg.enable) cfg.k3sProfiles;

      # Generate xdg.configFile entries for all enabled profiles
      profileFiles = lib.mapAttrs' (name: profileCfg: {
        name = "incus/profiles/${name}.yaml";
        value.text = mkProfileYaml name profileCfg;
      }) enabledProfiles;

      # Generate activation script commands for all enabled profiles
      mkActivationCommands =
        profiles:
        lib.concatStringsSep "\n" (
          lib.mapAttrsToList (name: _profileCfg: ''
            # Apply ${name} profile
            $DRY_RUN_CMD incus profile show ${name} &> /dev/null 2>&1 || \
              $DRY_RUN_CMD incus profile create ${name}
            $DRY_RUN_CMD incus profile edit ${name} < ${config.xdg.configHome}/incus/profiles/${name}.yaml
          '') profiles
        );
    in
    {
      options.incus = {
        k3sProfiles = lib.mkOption {
          type = lib.types.attrsOf profileModule;
          default = { };
          description = "k3s cluster incus profiles with cloud-init configuration.";
        };
      };

      config = {
        # Install incus client (Linux only - Darwin uses remote incus via Colima)
        home.packages = lib.optionals pkgs.stdenv.isLinux [ pkgs.incus ];

        # Profile YAMLs (version-controlled)
        # Deployed on all platforms for reference; applied only when incus is available
        xdg.configFile = profileFiles;

        # Activation script to ensure profiles exist
        # Guards against incus not being available (e.g., Darwin without Colima)
        home.activation.incusProfiles = lib.mkIf (enabledProfiles != { }) (
          lib.hm.dag.entryAfter [ "writeBoundary" ] ''
            if command -v incus &> /dev/null && incus query /1.0 &> /dev/null 2>&1; then
              ${mkActivationCommands enabledProfiles}
            fi
          ''
        );
      };
    };
}
