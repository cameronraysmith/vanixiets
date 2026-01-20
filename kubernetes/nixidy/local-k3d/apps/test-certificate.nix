# Test Certificate Application for verification
#
# Creates a test Certificate to verify cert-manager and ClusterIssuer work correctly.
# Issues a TLS certificate using the step-ca ACME ClusterIssuer with HTTP-01 challenge.
#
# Uses sslip.io wildcard DNS for HTTP-01 challenge resolution.
# sslip.io resolves *.127.0.0.1.sslip.io to 127.0.0.1, enabling HTTP-01 challenges
# for local development where the Gateway is exposed on localhost.
#
# Uses yamls option for cert-manager CRDs (no typed options generated).
# Sync wave 2: after ClusterIssuer (1).
{ lib, ... }:
let
  # Test namespace for certificate verification
  testNamespace = "cert-manager-test";

  # sslip.io domain for HTTP-01 challenge validation
  # 127.0.0.1 is reachable from k3d cluster via host networking
  testDomain = "test.127.0.0.1.sslip.io";
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
          # Certificate subject using sslip.io domain
          commonName: ${testDomain}
          # DNS SANs - sslip.io domain for HTTP-01 validation
          dnsNames:
            - ${testDomain}
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
