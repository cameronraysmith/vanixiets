{
  config,
  lib,
  pkgs,
  ...
}:
{
  config = lib.mkIf config.k3s-server.enable {
    environment.systemPackages = with pkgs; [
      # k3s itself is configured via services.k3s.package
      kubectl # Kubernetes CLI
      k9s # Terminal UI for Kubernetes
      cilium-cli # Cilium network management
      kubernetes-helm # Helm package manager
    ];
  };
}
