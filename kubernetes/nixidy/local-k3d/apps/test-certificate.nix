# Test Certificate Application for verification
#
# Creates a test Certificate to verify cert-manager and ClusterIssuer work correctly.
# Issues a TLS certificate using the step-ca ACME ClusterIssuer.
#
# Uses yamls option for cert-manager CRDs (no typed options generated).
# Sync wave 2: after ClusterIssuer (1).
{ lib, ... }:
let
  # Test namespace for certificate verification
  testNamespace = "cert-manager-test";
in
{
  applications.test-certificate = {
    namespace = testNamespace;

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

    # Use yamls for cert-manager CRDs (no typed options)
    yamls = [
      ''
        apiVersion: cert-manager.io/v1
        kind: Certificate
        metadata:
          name: test-cert
          namespace: ${testNamespace}
        spec:
          # Secret to store the issued certificate
          secretName: test-cert-tls
          # Certificate duration and renewal
          duration: 24h
          renewBefore: 8h
          # Reference to ClusterIssuer
          issuerRef:
            name: step-ca-acme
            kind: ClusterIssuer
          # Certificate subject
          commonName: test.local.cluster
          # DNS SANs
          dnsNames:
            - test.local.cluster
            - test.${testNamespace}.svc.cluster.local
          # Private key configuration
          privateKey:
            algorithm: ECDSA
            size: 256
          # Usages for TLS
          usages:
            - server auth
            - client auth
      ''
    ];
  };
}
