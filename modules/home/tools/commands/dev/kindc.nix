{ ... }:
{
  flake.modules.homeManager.tools =
    { pkgs, ... }:
    {
      home.packages = [
        (pkgs.writeShellApplication {
          name = "kindc";
          runtimeInputs = with pkgs; [ kind ];
          text = ''
            case "''${1:-}" in
              -h|--help)
                cat <<'HELP'
            Create a kind Kubernetes cluster with ingress support

            Usage: kindc

            Creates a local Kubernetes cluster using kind with:
              - Control plane node with ingress support
              - Port mappings: 8080->80, 8443->443
              - Node labels for ingress readiness

            Example:
              kindc    # Create the configured cluster
            HELP
                exit 0
                ;;
            esac

            cat <<EOF | kind create cluster --config=-
            kind: Cluster
            apiVersion: kind.x-k8s.io/v1alpha4
            nodes:
            - role: control-plane
              - |
                kind: InitConfiguration
                nodeRegistration:
                  kubeletExtraArgs:
                    node-labels: "ingress-ready=true"
              extraPortMappings:
              - containerPort: 80
                hostPort: 8080
                protocol: TCP
              - containerPort: 443
                hostPort: 8443
                protocol: TCP
            EOF
          '';
          meta.description = "Create kind Kubernetes cluster with ingress support";
        })
      ];
    };
}
