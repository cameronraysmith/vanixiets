# k3s server module for NixOS
#
# Configures k3s with Cilium CNI integration via disabled bundled components.
# Imports sub-modules for kernel, networking, and packages configuration.
# See docs/notes/development/kubernetes/components/nixos-k3s-server.md for details.
{
  flake.modules.nixos.k3s-server =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    {
      imports = [
        ./_kernel.nix
        ./_networking.nix
        ./_packages.nix
      ];

      options.k3s-server = {
        enable = lib.mkEnableOption "k3s server configuration";

        role = lib.mkOption {
          type = lib.types.enum [
            "server"
            "agent"
          ];
          default = "server";
          description = "k3s role (server or agent)";
        };

        clusterInit = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Initialize new cluster (first server node)";
        };

        serverAddr = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          description = "Address of server to join (for additional nodes)";
        };

        clusterCidr = lib.mkOption {
          type = lib.types.str;
          default = "10.42.0.0/16";
          description = "Pod CIDR range (must match easykubenix Cilium IPAM)";
        };

        serviceCidr = lib.mkOption {
          type = lib.types.str;
          default = "10.43.0.0/16";
          description = "Service CIDR range (must match easykubenix)";
        };

        tokenFile = lib.mkOption {
          type = lib.types.nullOr lib.types.path;
          default = null;
          description = "Path to cluster token file (sops-nix secret)";
        };
      };

      config = lib.mkIf config.k3s-server.enable {
        services.k3s = {
          enable = true;
          role = config.k3s-server.role;
          clusterInit = config.k3s-server.clusterInit;
          tokenFile = config.k3s-server.tokenFile;

          # Disable bundled components for Cilium CNI
          disable = [
            "flannel" # Cilium replaces flannel
            "local-storage" # Use external storage provisioner
            "metrics-server" # Deploy via Helm for control
            "servicelb" # Cilium provides load balancing
            "traefik" # Use external ingress controller
          ];

          extraFlags = [
            "--flannel-backend=none" # Required for external CNI
            "--disable-network-policy" # Cilium handles NetworkPolicy
            "--disable-kube-proxy" # Cilium replaces kube-proxy
            "--disable-cloud-controller" # No cloud provider integration
          ]
          ++ lib.optionals (config.k3s-server.role == "server") [
            "--cluster-cidr=${config.k3s-server.clusterCidr}"
            "--service-cidr=${config.k3s-server.serviceCidr}"
          ]
          ++ lib.optional (config.k3s-server.serverAddr != null) "--server=${config.k3s-server.serverAddr}";

          gracefulNodeShutdown = {
            enable = true;
            shutdownGracePeriod = "30s";
            shutdownGracePeriodCriticalPods = "10s";
          };
        };
      };
    };
}
