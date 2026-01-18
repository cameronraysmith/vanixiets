# incus profile configuration for k3s local development
#
# Configures incus profiles for NixOS VMs running in Colima.
# Disables Secure Boot (NixOS images are unsigned) and sets resource limits.
#
# Usage: Profile is applied via home-manager activation on switch.
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
    {
      # Install incus client (Linux only - Darwin uses remote incus via Colima)
      home.packages = lib.optionals pkgs.stdenv.isLinux [ pkgs.incus ];

      # k3s-dev profile YAML (version-controlled)
      # Deployed on all platforms for reference; applied only when incus is available
      xdg.configFile."incus/profiles/k3s-dev.yaml".text = ''
        name: k3s-dev
        description: "k3s local development VM profile"
        config:
          security.secureboot: "false"
          limits.cpu: "4"
          limits.memory: "8GiB"
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

      # Activation script to ensure profile exists
      # Guards against incus not being available (e.g., Darwin without Colima)
      home.activation.incusProfiles = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        if command -v incus &> /dev/null && incus query /1.0 &> /dev/null 2>&1; then
          # Apply k3s-dev profile if incus is available
          $DRY_RUN_CMD incus profile show k3s-dev &> /dev/null 2>&1 || \
            $DRY_RUN_CMD incus profile create k3s-dev
          $DRY_RUN_CMD incus profile edit k3s-dev < ${config.xdg.configHome}/incus/profiles/k3s-dev.yaml
        fi
      '';
    };
}
