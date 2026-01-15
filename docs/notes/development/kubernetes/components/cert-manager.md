---
title: cert-manager
---

# cert-manager

cert-manager automates TLS certificate lifecycle management in Kubernetes clusters.
It handles certificate issuance, renewal, and revocation through integration with various certificate authorities including ACME-compatible services like Let's Encrypt and step-ca.
The controller watches for Certificate resources and ClusterIssuer/Issuer configurations to automatically provision and maintain TLS certificates stored as Kubernetes Secrets.

## Deployment

cert-manager installs via Helm chart or direct YAML manifest application.
The hetzkube reference applies the official release manifest directly using the `importyaml` pattern.

### Helm chart deployment (nixidy pattern)

```nix
{
  applications.cert-manager = {
    namespace = "cert-manager";
    createNamespace = true;

    helm.releases.cert-manager = {
      chart = charts.jetstack.cert-manager;
      values = {
        installCRDs = true;
        global.leaderElection.namespace = "cert-manager";
      };
    };
  };
}
```

### Direct manifest deployment (easykubenix pattern)

The hetzkube reference uses `importyaml` to apply the upstream release manifest directly.

```nix
{
  config,
  lib,
  ...
}:
let
  cfg = config.cert-manager;
in
{
  options.cert-manager = {
    enable = lib.mkEnableOption "cert-manager";
    url = lib.mkOption {
      type = lib.types.nonEmptyStr;
      default = "https://github.com/cert-manager/cert-manager/releases/download/v1.19.1/cert-manager.yaml";
    };
  };

  config = lib.mkIf cfg.enable {
    importyaml.cert-manager.src = cfg.url;
  };
}
```

### CRD API mappings

When using kubenix or easykubenix, register the cert-manager CRD API versions.

```nix
{
  kubernetes.apiMappings = {
    Certificate = "cert-manager.io/v1";
    CertificateRequest = "cert-manager.io/v1";
    Challenge = "acme.cert-manager.io/v1";
    ClusterIssuer = "cert-manager.io/v1";
    Issuer = "cert-manager.io/v1";
    Order = "acme.cert-manager.io/v1";
  };

  kubernetes.namespacedMappings = {
    Certificate = true;
    CertificateRequest = true;
    Challenge = true;
    ClusterIssuer = true;
    Issuer = true;
    Order = true;
  };
}
```

## Issuer types

cert-manager distinguishes between namespace-scoped Issuers and cluster-wide ClusterIssuers.

### ClusterIssuer

ClusterIssuer resources exist at cluster scope and can issue certificates for any namespace.
This simplifies multi-tenant configurations where a single ACME account serves the entire cluster.

```yaml
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: admin@example.com
    privateKeySecretRef:
      name: letsencrypt-prod-account-key
    solvers:
      - dns01:
          cloudflare:
            apiTokenSecretRef:
              name: cloudflare-api-token
              key: token
```

### Issuer (namespace-scoped)

Issuer resources exist within a specific namespace and can only issue certificates in that namespace.
Use namespace-scoped Issuers when different teams require separate certificate authorities or ACME accounts.

```yaml
apiVersion: cert-manager.io/v1
kind: Issuer
metadata:
  name: team-issuer
  namespace: team-namespace
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: team@example.com
    privateKeySecretRef:
      name: team-acme-account-key
    solvers:
      - http01:
          ingress:
            ingressClassName: nginx
```

### Self-signed issuer (bootstrapping)

Self-signed issuers generate certificates without external CA dependency.
Use for internal services, development environments, or bootstrapping certificate chains.

```yaml
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: selfsigned
spec:
  selfSigned: {}
```

## ACME solvers

ACME protocol proves domain ownership through challenge-response mechanisms.
cert-manager supports HTTP01 and DNS01 solver types.

### HTTP01 solver

HTTP01 challenges require the ACME server to reach a well-known HTTP endpoint on your domain.
This approach works for single-domain certificates and requires ingress configuration.

```yaml
solvers:
  - http01:
      ingress:
        ingressClassName: traefik
```

HTTP01 limitations include inability to issue wildcard certificates and requirement for publicly accessible ingress during challenge.

### DNS01 solver

DNS01 challenges prove domain ownership by creating TXT records in DNS.
This approach supports wildcard certificates and works for internal services without public ingress.

```yaml
solvers:
  - dns01:
      cloudflare:
        apiTokenSecretRef:
          name: cloudflare-api-token
          key: token
```

DNS01 requires API credentials for your DNS provider.
cert-manager supports Cloudflare, Route53, Google Cloud DNS, Azure DNS, and others.

### Local environment: HTTP01 with sslip.io

For local development, use HTTP01 challenges with sslip.io wildcard DNS.
sslip.io resolves hostnames like `app.192.168.1.100.sslip.io` to the embedded IP address.

```yaml
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: step-ca-local
spec:
  acme:
    server: https://step-ca.local.sslip.io/acme/acme/directory
    caBundle: <base64-encoded-step-ca-root-cert>
    privateKeySecretRef:
      name: step-ca-account-key
    solvers:
      - http01:
          ingress:
            ingressClassName: traefik
```

### Production environment: DNS01 with Cloudflare

Production deployments use DNS01 challenges with Cloudflare for wildcard certificate support.
The hetzkube reference demonstrates this pattern with both staging and production Let's Encrypt endpoints.

```nix
{
  kubernetes.resources.none.ClusterIssuer.le-staging.spec = {
    acme = {
      server = "https://acme-staging-v02.api.letsencrypt.org/directory";
      email = "admin@example.com";
      privateKeySecretRef.name = "le-staging-pk";
      solvers = lib.mkNumberedList {
        "0" = {
          dns01.cloudflare.apiTokenSecretRef = {
            name = "cloudflare";
            key = "token";
          };
        };
      };
    };
  };

  kubernetes.resources.none.ClusterIssuer.le-prod.spec = {
    acme = {
      server = "https://acme-v02.api.letsencrypt.org/directory";
      email = "admin@example.com";
      privateKeySecretRef.name = "le-prod-pk";
      solvers = lib.mkNumberedList {
        "0" = {
          dns01.cloudflare.apiTokenSecretRef = {
            name = "cloudflare";
            key = "token";
          };
        };
      };
    };
  };
}
```

## Certificate resources

Certificate resources define the desired certificate properties.
cert-manager watches these resources and manages the certificate lifecycle.

### Certificate CRD structure

```yaml
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: example-com-tls
  namespace: default
spec:
  secretName: example-com-tls-secret
  issuerRef:
    name: letsencrypt-prod
    kind: ClusterIssuer
  dnsNames:
    - example.com
    - www.example.com
  duration: 2160h    # 90 days
  renewBefore: 360h  # 15 days before expiry
```

### Key fields

The `secretName` specifies where cert-manager stores the certificate and private key.
The resulting Secret contains `tls.crt` (certificate chain) and `tls.key` (private key).

The `issuerRef` references either a ClusterIssuer (with `kind: ClusterIssuer`) or namespace-scoped Issuer (with `kind: Issuer`).

The `dnsNames` array lists all Subject Alternative Names (SANs) for the certificate.
Wildcard certificates use entries like `*.example.com`.

The `duration` and `renewBefore` fields control certificate validity and renewal timing.
Let's Encrypt certificates have a maximum 90-day validity, so `renewBefore: 360h` triggers renewal 15 days before expiry.

## Ingress integration

cert-manager integrates with Kubernetes Ingress resources through annotations.
The ingress-shim controller watches Ingress resources and creates Certificate resources automatically.

### Annotation-based certificate provisioning

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: example-ingress
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-prod
spec:
  ingressClassName: traefik
  tls:
    - hosts:
        - example.com
      secretName: example-com-tls
  rules:
    - host: example.com
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: example-service
                port:
                  number: 80
```

The `cert-manager.io/cluster-issuer` annotation tells cert-manager which ClusterIssuer to use.
For namespace-scoped Issuers, use `cert-manager.io/issuer` instead.

cert-manager creates a Certificate resource matching the Ingress TLS configuration.
The Certificate references the specified issuer and requests certificates for the listed hosts.

## Local vs production configuration

The same Certificate resources work in both local and production environments when ClusterIssuer names match.

### Local ClusterIssuer (step-ca ACME)

```yaml
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod  # Same name as production
spec:
  acme:
    server: https://step-ca.local:8443/acme/acme/directory
    caBundle: <base64-step-ca-root>
    skipTLSVerify: false
    privateKeySecretRef:
      name: step-ca-account-key
    solvers:
      - http01:
          ingress:
            ingressClassName: traefik
```

### Production ClusterIssuer (Let's Encrypt + Cloudflare)

```yaml
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: admin@example.com
    privateKeySecretRef:
      name: letsencrypt-prod-account-key
    solvers:
      - dns01:
          cloudflare:
            apiTokenSecretRef:
              name: cloudflare-api-token
              key: token
```

### Cloudflare API token configuration

Create a Cloudflare API token with `Zone:DNS:Edit` permissions for the target zones.
Store the token in a Kubernetes Secret in the cert-manager namespace.

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: cloudflare-api-token
  namespace: cert-manager
type: Opaque
stringData:
  token: <cloudflare-api-token>
```

The hetzkube reference uses Bitwarden Secrets Manager to inject the Cloudflare token.

```nix
{
  kubernetes.resources.cert-manager = {
    Secret.bw-auth-token.stringData.token = "{{ bwtoken }}";
    BitwardenSecret.cloudflare = {
      spec = {
        organizationId = "org-id";
        secretName = "cloudflare";
        map = [
          {
            bwSecretId = "secret-id";
            secretKeyName = "token";
          }
        ];
        authToken = {
          secretName = "bw-auth-token";
          secretKey = "token";
        };
      };
    };
  };
}
```

## Troubleshooting

### Certificate not ready

Check Certificate status for detailed error information.

```sh
kubectl describe certificate <name> -n <namespace>
kubectl get certificaterequest -n <namespace>
kubectl describe certificaterequest <name> -n <namespace>
```

Common causes include issuer misconfiguration, ACME account registration failure, and challenge solver issues.

### ACME challenges failing

Inspect Challenge resources during certificate issuance.

```sh
kubectl get challenges -A
kubectl describe challenge <name> -n <namespace>
```

HTTP01 challenge failures typically indicate ingress misconfiguration, firewall rules blocking port 80, or DNS not resolving to the cluster.

DNS01 challenge failures typically indicate invalid API credentials, insufficient DNS provider permissions, or DNS propagation delays.

### Order stuck in pending state

Orders represent ACME certificate requests.
Stuck orders indicate the ACME server has not validated all challenges.

```sh
kubectl get orders -A
kubectl describe order <name> -n <namespace>
```

### Checking cert-manager controller logs

```sh
kubectl logs -n cert-manager -l app=cert-manager --tail=100
```

### Verifying issued certificates

```sh
kubectl get secret <secret-name> -n <namespace> -o jsonpath='{.data.tls\.crt}' | base64 -d | openssl x509 -text -noout
```

## Example configurations

### Complete local development setup

```nix
# cert-manager module for local k3s cluster
{
  config,
  lib,
  ...
}: {
  applications.cert-manager = {
    namespace = "cert-manager";
    createNamespace = true;

    helm.releases.cert-manager = {
      chart = charts.jetstack.cert-manager;
      values = {
        installCRDs = true;
      };
    };

    resources = {
      clusterIssuers.step-ca-local.spec = {
        acme = {
          server = "https://step-ca.step-ca.svc.cluster.local/acme/acme/directory";
          caBundle = builtins.readFile ./step-ca-root.pem;
          privateKeySecretRef.name = "step-ca-account-key";
          solvers = [
            {
              http01.ingress.ingressClassName = "traefik";
            }
          ];
        };
      };
    };
  };
}
```

### Complete production setup

```nix
# cert-manager module for production cluster
{
  config,
  lib,
  ...
}: {
  applications.cert-manager = {
    namespace = "cert-manager";
    createNamespace = true;

    helm.releases.cert-manager = {
      chart = charts.jetstack.cert-manager;
      values = {
        installCRDs = true;
        global.leaderElection.namespace = "cert-manager";
      };
    };

    resources = {
      secrets.cloudflare-api-token = {
        type = "Opaque";
        stringData.token = "{{ cloudflareToken }}";
      };

      clusterIssuers.letsencrypt-staging.spec = {
        acme = {
          server = "https://acme-staging-v02.api.letsencrypt.org/directory";
          email = "admin@example.com";
          privateKeySecretRef.name = "letsencrypt-staging-account-key";
          solvers = [
            {
              dns01.cloudflare.apiTokenSecretRef = {
                name = "cloudflare-api-token";
                key = "token";
              };
            }
          ];
        };
      };

      clusterIssuers.letsencrypt-prod.spec = {
        acme = {
          server = "https://acme-v02.api.letsencrypt.org/directory";
          email = "admin@example.com";
          privateKeySecretRef.name = "letsencrypt-prod-account-key";
          solvers = [
            {
              dns01.cloudflare.apiTokenSecretRef = {
                name = "cloudflare-api-token";
                key = "token";
              };
            }
          ];
        };
      };
    };
  };
}
```

### Certificate for wildcard domain

```yaml
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: wildcard-example-com
  namespace: default
spec:
  secretName: wildcard-example-com-tls
  issuerRef:
    name: letsencrypt-prod
    kind: ClusterIssuer
  dnsNames:
    - "*.example.com"
    - example.com
  duration: 2160h
  renewBefore: 360h
```

### Ingress with automatic certificate

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: app-ingress
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-prod
spec:
  ingressClassName: traefik
  tls:
    - hosts:
        - app.example.com
      secretName: app-example-com-tls
  rules:
    - host: app.example.com
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: app
                port:
                  number: 8080
```
