# Gateway Application for Cilium Gateway API integration
#
# Creates Gateway resource for ingress traffic routing.
# Uses Cilium as GatewayClass with HTTP and HTTPS listeners.
#
# cert-manager annotation enables automatic TLS certificate provisioning
# via the step-ca ACME ClusterIssuer.
#
# Sync wave 2: after ClusterIssuer (1) to ensure issuer is ready.
{ lib, ... }:
let
  # Gateway configuration
  gatewayNamespace = "gateway-system";
  gatewayName = "main-gateway";
  clusterIssuerName = "step-ca-acme";

  # sslip.io domain for local development
  # k3d with hostNetwork exposes on localhost
  localDomain = "127.0.0.1.sslip.io";
  wildcardDomain = "*.${localDomain}";
in
{
  applications.gateway = {
    namespace = gatewayNamespace;

    # Phase 4 native: create namespace
    syncPolicy = {
      autoSync = {
        enable = true;
        prune = true;
        selfHeal = true;
      };
      syncOptions = {
        createNamespace = true;
      };
    };

    # Sync wave 2: after ClusterIssuer at wave 1
    annotations."argocd.argoproj.io/sync-wave" = "2";

    # Use yamls for Gateway API resources (no typed options)
    yamls = [
      # Gateway resource
      ''
        apiVersion: gateway.networking.k8s.io/v1
        kind: Gateway
        metadata:
          name: ${gatewayName}
          namespace: ${gatewayNamespace}
          annotations:
            # cert-manager integration: automatically provision TLS certificate
            cert-manager.io/cluster-issuer: ${clusterIssuerName}
        spec:
          # Cilium provides GatewayClass
          gatewayClassName: cilium
          listeners:
            # HTTP listener for ACME HTTP-01 challenges and HTTP traffic
            - name: http
              protocol: HTTP
              port: 80
              allowedRoutes:
                namespaces:
                  from: All
            # HTTPS listener for TLS-terminated traffic
            - name: https
              protocol: HTTPS
              port: 443
              hostname: "${wildcardDomain}"
              tls:
                mode: Terminate
                certificateRefs:
                  # cert-manager creates this secret via annotation
                  - name: gateway-tls
              allowedRoutes:
                namespaces:
                  from: All
      ''
    ];
  };
}
