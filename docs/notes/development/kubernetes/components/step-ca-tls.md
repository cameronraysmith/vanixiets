---
title: step-ca TLS
---

# step-ca TLS

step-ca provides a local ACME server for development environments, enabling the same cert-manager workflow used in production with Let's Encrypt.
This document covers deploying step-ca in a k3s cluster, integrating with cert-manager, and establishing browser trust for local TLS certificates.

## Why step-ca for local development

Production TLS uses Let's Encrypt via cert-manager, which requires public DNS and internet-reachable endpoints for ACME challenges.
Local development clusters lack public DNS and internet accessibility, preventing direct Let's Encrypt usage.
step-ca solves this by providing an ACME-compatible CA that runs inside the cluster.

The key benefit is workflow parity.
Certificate resources, ClusterIssuers, and Ingress annotations remain identical between local and production.
Only the ACME server URL changes.
This catches TLS configuration errors, missing annotations, and cert-manager integration issues before production deployment.

Self-signed certificates could work but require manual certificate generation for each service.
step-ca's ACME protocol support means cert-manager handles all certificate lifecycle automatically, exactly as it does in production.

## step-ca deployment

step-ca deploys via the official Helm chart from Smallstep.
The chart manages the CA server, persistent storage for keys, and service exposure within the cluster.

### Helm chart configuration

```nix
let
  stepCaVersion = "1.25.0";
  src = builtins.fetchTree {
    type = "github";
    owner = "smallstep";
    repo = "helm-charts";
    ref = "step-certificates-${stepCaVersion}";
  };
in {
  helm.releases.step-certificates = {
    namespace = "step-ca";
    chart = "${src}/charts/step-certificates";
    values = {
      # CA configuration
      inject = {
        enabled = true;
        config = {
          files = {
            "ca.json" = builtins.toJSON {
              root = "/home/step/certs/root_ca.crt";
              crt = "/home/step/certs/intermediate_ca.crt";
              key = "/home/step/secrets/intermediate_ca_key";
              address = ":9000";
              dnsNames = [
                "step-ca.step-ca.svc.cluster.local"
                "step-ca.step-ca.svc"
                "step-ca"
              ];
              authority = {
                provisioners = [
                  {
                    type = "ACME";
                    name = "acme";
                  }
                ];
              };
            };
          };
        };
      };

      # Persistence for CA keys
      persistence = {
        enabled = true;
        size = "1Gi";
        storageClass = "local-path";
      };

      # Service configuration
      service = {
        type = "ClusterIP";
        port = 9000;
      };
    };
  };
}
```

### Namespace selection

step-ca runs in its own `step-ca` namespace rather than `cert-manager`.
This separates the CA infrastructure from the certificate consumer.
cert-manager needs only network access to the step-ca service, not co-location.

```shell
kubectl create namespace step-ca
```

### Persistent volume requirements

The CA private keys must persist across pod restarts.
Losing the CA key invalidates all issued certificates and breaks trust relationships.
The `local-path` storage class works for single-node development clusters.

For Colima with k3s, the default local-path provisioner handles this automatically.
Multi-node clusters require a distributed storage class or node affinity to ensure the volume remains accessible.

## Root CA setup

The root CA certificate establishes the trust anchor.
step-ca generates this on first startup, but you can also inject a pre-generated CA for consistent trust across multiple clusters.

### Generating root CA

For fresh installation, step-ca generates the root CA automatically.
Extract it after deployment:

```shell
kubectl -n step-ca exec deploy/step-certificates -- step ca root > step-root-ca.crt
```

For reproducible environments, generate the CA outside the cluster:

```shell
# Generate root CA with step CLI
step certificate create \
  --profile root-ca \
  --no-password \
  --insecure \
  "Local Development Root CA" \
  root_ca.crt \
  root_ca.key

# Generate intermediate CA signed by root
step certificate create \
  --profile intermediate-ca \
  --no-password \
  --insecure \
  --ca root_ca.crt \
  --ca-key root_ca.key \
  "Local Development Intermediate CA" \
  intermediate_ca.crt \
  intermediate_ca.key
```

### Importing root CA into macOS keychain

Browser trust requires the root CA in the system keychain.
This is a one-time setup per development machine.

```shell
# Import to system keychain (requires admin password)
sudo security add-trusted-cert \
  -d \
  -r trustRoot \
  -k /Library/Keychains/System.keychain \
  step-root-ca.crt
```

Firefox uses its own certificate store and requires separate import:

1. Open Firefox Preferences
2. Navigate to Privacy and Security, then Certificates
3. Click View Certificates, then Import
4. Select the root CA certificate and trust for website identification

### Exporting root CA for cert-manager

cert-manager needs the CA bundle to trust the step-ca ACME endpoint.
Create a ConfigMap in the cert-manager namespace:

```shell
kubectl -n cert-manager create configmap step-ca-bundle \
  --from-file=ca.crt=step-root-ca.crt
```

This ConfigMap gets referenced in the ClusterIssuer configuration.

## ACME configuration

step-ca supports multiple provisioner types.
The ACME provisioner enables standard ACME protocol challenges for certificate issuance.

### Enabling ACME provisioner

The Helm values above include the ACME provisioner in the authority configuration.
Verify it works after deployment:

```shell
# Get ACME directory
curl -k https://step-ca.step-ca.svc.cluster.local:9000/acme/acme/directory
```

Expected response:

```json
{
  "newNonce": "https://step-ca.step-ca.svc.cluster.local:9000/acme/acme/new-nonce",
  "newAccount": "https://step-ca.step-ca.svc.cluster.local:9000/acme/acme/new-account",
  "newOrder": "https://step-ca.step-ca.svc.cluster.local:9000/acme/acme/new-order",
  "revokeCert": "https://step-ca.step-ca.svc.cluster.local:9000/acme/acme/revoke-cert",
  "keyChange": "https://step-ca.step-ca.svc.cluster.local:9000/acme/acme/key-change"
}
```

### ACME directory URL

The ACME directory URL for cert-manager integration:

```
https://step-ca.step-ca.svc.cluster.local:9000/acme/acme/directory
```

The path structure is `/acme/{provisioner-name}/directory`.
Since the provisioner is named `acme`, the path becomes `/acme/acme/directory`.

## cert-manager integration

cert-manager connects to step-ca via a ClusterIssuer that points to the local ACME endpoint.

### ClusterIssuer for step-ca

```yaml
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: step-ca-acme
spec:
  acme:
    server: https://step-ca.step-ca.svc.cluster.local:9000/acme/acme/directory
    privateKeySecretRef:
      name: step-ca-acme-account-key
    caBundle: <base64-encoded-root-ca>
    solvers:
      - http01:
          ingress:
            class: nginx
```

In Nix with kubenix:

```nix
{
  resources.cert-manager.io.v1.ClusterIssuer.step-ca-acme = {
    spec = {
      acme = {
        server = "https://step-ca.step-ca.svc.cluster.local:9000/acme/acme/directory";
        privateKeySecretRef.name = "step-ca-acme-account-key";
        caBundle = builtins.readFile ./step-root-ca.crt |> builtins.hashString "base64";
        solvers = [
          {
            http01.ingress.ingressClassName = "nginx";
          }
        ];
      };
    };
  };
}
```

### Certificate resource example

Certificate resources work identically with either issuer.
Only the `issuerRef` changes between local and production.

```yaml
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: app-tls
  namespace: default
spec:
  secretName: app-tls-secret
  dnsNames:
    - app.192.168.5.2.sslip.io
  issuerRef:
    name: step-ca-acme  # Local: step-ca-acme, Production: letsencrypt-prod
    kind: ClusterIssuer
```

### Ingress annotation pattern

For Ingress resources, cert-manager annotations trigger automatic certificate creation:

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: app
  annotations:
    cert-manager.io/cluster-issuer: step-ca-acme
spec:
  ingressClassName: nginx
  tls:
    - hosts:
        - app.192.168.5.2.sslip.io
      secretName: app-tls
  rules:
    - host: app.192.168.5.2.sslip.io
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: app
                port:
                  number: 80
```

## DNS requirements

ACME challenges require DNS names that resolve to the cluster.
Local development uses wildcard DNS services that map any hostname to embedded IP addresses.

### sslip.io integration

sslip.io provides wildcard DNS where any subdomain containing an IP address resolves to that IP.
For a Colima cluster with ingress at 192.168.5.2:

```
app.192.168.5.2.sslip.io -> 192.168.5.2
api.192.168.5.2.sslip.io -> 192.168.5.2
*.192.168.5.2.sslip.io   -> 192.168.5.2
```

This requires no DNS server configuration.
Public DNS resolution works immediately for any service.

### HTTP-01 challenge flow

With sslip.io DNS pointing to the cluster ingress:

1. cert-manager requests certificate from step-ca ACME
2. step-ca responds with HTTP-01 challenge token
3. cert-manager creates temporary Ingress for `/.well-known/acme-challenge/{token}`
4. step-ca fetches the challenge URL (resolves via sslip.io to cluster ingress)
5. Challenge succeeds, step-ca issues certificate
6. cert-manager stores certificate in Secret

The entire flow happens within or adjacent to the cluster.
No external network access required.

### DNS-01 alternative

DNS-01 challenges require dynamic DNS record creation, which adds complexity for local development.
HTTP-01 with sslip.io provides the simplest path.
Reserve DNS-01 for wildcard certificates in production where Let's Encrypt requires it.

## Local versus production issuers

The architecture enables issuer substitution without changing Certificate or Ingress resources.

### Local development issuer

```yaml
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: local-issuer
spec:
  acme:
    server: https://step-ca.step-ca.svc.cluster.local:9000/acme/acme/directory
    privateKeySecretRef:
      name: local-issuer-account-key
    caBundle: <step-ca-root-ca>
    solvers:
      - http01:
          ingress:
            ingressClassName: nginx
```

### Production issuer

```yaml
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: production-issuer
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: admin@example.com
    privateKeySecretRef:
      name: letsencrypt-account-key
    solvers:
      - http01:
          ingress:
            ingressClassName: nginx
```

### Environment-based selection

Nix configuration can select the appropriate issuer based on environment:

```nix
{ config, lib, ... }:
let
  isProduction = config.environment == "production";
  issuerName = if isProduction then "letsencrypt-prod" else "step-ca-acme";
in {
  resources.networking.k8s.io.v1.Ingress.app.metadata.annotations = {
    "cert-manager.io/cluster-issuer" = issuerName;
  };
}
```

This pattern keeps Certificate resources environment-agnostic while the deployment tooling selects the correct issuer.

## Troubleshooting

Certificate issuance failures typically stem from connectivity, DNS resolution, or challenge validation issues.

### Checking step-ca logs

```shell
kubectl -n step-ca logs deploy/step-certificates -f
```

Successful ACME requests show the challenge type and domain:

```
level=info msg="http-01 challenge accepted" domain=app.192.168.5.2.sslip.io
```

Failed challenges indicate the validation error:

```
level=error msg="http-01 challenge failed" domain=app.192.168.5.2.sslip.io error="connection refused"
```

### Checking cert-manager events

```shell
kubectl describe certificate app-tls
kubectl describe certificaterequest app-tls-xxxxx
kubectl describe order app-tls-xxxxx-xxxxxxx
kubectl describe challenge app-tls-xxxxx-xxxxxxx-xxxxxxx
```

The Challenge resource shows the current validation state and any errors.

### Common issues

The step-ca service is unreachable from cert-manager when DNS resolution fails within the cluster.
Verify with:

```shell
kubectl -n cert-manager run -it --rm debug --image=curlimages/curl -- \
  curl -k https://step-ca.step-ca.svc.cluster.local:9000/health
```

HTTP-01 challenge fails when the temporary Ingress does not route correctly.
Check the challenge Ingress exists during validation:

```shell
kubectl get ingress -A | grep acme
```

Certificate stuck in pending state often indicates the ClusterIssuer cannot reach the ACME server.
Check ClusterIssuer status:

```shell
kubectl describe clusterissuer step-ca-acme
```

CA bundle mismatch causes TLS verification errors.
Ensure the caBundle in ClusterIssuer matches the actual step-ca root certificate:

```shell
kubectl -n step-ca exec deploy/step-certificates -- step ca root | base64
```

### Verifying issued certificates

After successful issuance, verify the certificate chain:

```shell
kubectl get secret app-tls-secret -o jsonpath='{.data.tls\.crt}' | base64 -d | openssl x509 -text -noout
```

Check the issuer matches your step-ca intermediate CA.

## Example configuration

Complete example deploying step-ca and cert-manager integration for local development.

### step-ca namespace and deployment

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: step-ca
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: step-ca-config
  namespace: step-ca
data:
  ca.json: |
    {
      "root": "/home/step/certs/root_ca.crt",
      "crt": "/home/step/certs/intermediate_ca.crt",
      "key": "/home/step/secrets/intermediate_ca_key",
      "address": ":9000",
      "dnsNames": [
        "step-ca.step-ca.svc.cluster.local",
        "step-ca.step-ca.svc",
        "step-ca"
      ],
      "authority": {
        "provisioners": [
          {
            "type": "ACME",
            "name": "acme"
          }
        ]
      }
    }
```

### ClusterIssuer

```yaml
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: step-ca-acme
spec:
  acme:
    server: https://step-ca.step-ca.svc.cluster.local:9000/acme/acme/directory
    privateKeySecretRef:
      name: step-ca-acme-account-key
    caBundle: LS0tLS1CRUdJTi... # base64 encoded root CA
    solvers:
      - http01:
          ingress:
            ingressClassName: nginx
```

### Test certificate

```yaml
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: test-tls
  namespace: default
spec:
  secretName: test-tls-secret
  dnsNames:
    - test.192.168.5.2.sslip.io
  issuerRef:
    name: step-ca-acme
    kind: ClusterIssuer
```

### Verification commands

```shell
# Wait for certificate to be ready
kubectl wait --for=condition=Ready certificate/test-tls --timeout=60s

# Verify certificate contents
kubectl get secret test-tls-secret -o jsonpath='{.data.tls\.crt}' | \
  base64 -d | \
  openssl x509 -text -noout | \
  grep -E "(Subject:|Issuer:)"

# Expected output:
# Issuer: CN=Local Development Intermediate CA
# Subject: CN=test.192.168.5.2.sslip.io
```
