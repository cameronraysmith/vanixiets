# ClusterIssuer Application for step-ca ACME integration
#
# Creates ClusterIssuer pointing to step-ca's ACME endpoint.
# Enables automated TLS certificate issuance via ACME protocol.
#
# Uses yamls option for cert-manager CRDs (no typed options generated).
# Sync wave 1: after cert-manager (0), before test certificates (2).
{ lib, ... }:
let
  # step-ca service endpoint in step-ca namespace
  stepCaNamespace = "step-ca";
  stepCaServiceName = "step-ca-step-certificates";
  stepCaAcmeProvisioner = "acme";
  stepCaAcmeUrl = "https://${stepCaServiceName}.${stepCaNamespace}.svc.cluster.local/acme/${stepCaAcmeProvisioner}/directory";
in
{
  applications.cluster-issuer = {
    # ClusterIssuer is cluster-scoped, but Application needs a namespace
    # Use cert-manager namespace for organization
    namespace = "cert-manager";

    # Standard sync policy for Phase 4 native
    syncPolicy = {
      autoSync = {
        enable = true;
        prune = true;
        selfHeal = true;
      };
    };

    # Sync wave 1: after cert-manager at wave 0
    annotations."argocd.argoproj.io/sync-wave" = "1";

    # Use yamls for cert-manager CRDs (no typed options)
    yamls = [
      ''
        apiVersion: cert-manager.io/v1
        kind: ClusterIssuer
        metadata:
          name: step-ca-acme
        spec:
          acme:
            # step-ca ACME endpoint
            server: "${stepCaAcmeUrl}"
            # Email for ACME account (required but not used for internal CA)
            email: admin@local.cluster
            # Secret to store ACME account private key
            privateKeySecretRef:
              name: step-ca-acme-account-key
            # Skip TLS verification for internal CA
            # step-ca uses self-signed certificates
            skipTLSVerify: true
            # Solvers for ACME challenges
            # Uses Gateway API HTTP-01 solver with Cilium Gateway
            solvers:
              - http01:
                  gatewayHTTPRoute:
                    parentRefs:
                      - name: main-gateway
                        namespace: gateway-system
                        kind: Gateway
      ''
    ];
  };
}
