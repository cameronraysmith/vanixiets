# ArgoCD HTTPRoute for Gateway API ingress
#
# Exposes ArgoCD UI via Cilium Gateway API.
# Routes argocd.192.168.100.3.sslip.io to the ArgoCD server service.
#
# ArgoCD server runs in insecure mode (HTTP on port 80) for local development,
# so the HTTPRoute targets port 80. TLS termination happens at the Gateway.
#
# Sync wave 3: after Gateway (2) to ensure Gateway is ready to accept routes.
{ lib, ... }:
let
  # Route configuration
  routeNamespace = "argocd";
  routeName = "argocd";

  # Gateway reference
  gatewayNamespace = "gateway-system";
  gatewayName = "main-gateway";

  # sslip.io domain for local development (k3d server node IP)
  # .3 = k3s node where servicelb binds LoadBalancer IPs
  hostname = "argocd.192.168.100.3.sslip.io";

  # ArgoCD server service (from Helm chart)
  # Server runs in insecure mode (HTTP on port 80)
  serviceName = "argocd-server";
  servicePort = 80;
in
{
  applications.argocd-route = {
    namespace = routeNamespace;

    # Phase 4 native: no namespace creation needed (argocd namespace exists)
    syncPolicy = {
      autoSync = {
        enable = true;
        prune = true;
        selfHeal = true;
      };
      syncOptions = {
        createNamespace = false;
      };
    };

    # Sync wave 3: after Gateway at wave 2
    annotations."argocd.argoproj.io/sync-wave" = "3";

    # Use yamls for Gateway API resources (no typed options in nixidy)
    yamls = [
      ''
        apiVersion: gateway.networking.k8s.io/v1
        kind: HTTPRoute
        metadata:
          name: ${routeName}
          namespace: ${routeNamespace}
        spec:
          parentRefs:
            - name: ${gatewayName}
              namespace: ${gatewayNamespace}
          hostnames:
            - "${hostname}"
          rules:
            - backendRefs:
                - name: ${serviceName}
                  port: ${toString servicePort}
      ''
    ];
  };
}
