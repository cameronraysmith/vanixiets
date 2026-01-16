---
title: External-DNS
---

# External-DNS

External-DNS synchronizes Kubernetes Service and Ingress/Gateway resources with external DNS providers.
This document covers deployment for production Hetzner clusters using Cloudflare as the DNS provider with sops-secrets-operator managing the API token.

## Scope

External-DNS is production-only infrastructure.
Local development clusters use sslip.io wildcard DNS which requires no DNS record management.
The component deploys as part of the full stage in easykubenix alongside other production infrastructure components.

## Cloudflare provider configuration

External-DNS supports multiple DNS providers through provider-specific flags and authentication.
The Cloudflare provider requires an API token with `Zone:DNS:Edit` permissions for target zones.

### Helm values

```nix
{
  # Provider configuration
  provider.name = "cloudflare";

  # Domain filtering - only manage records for specified zones
  domainFilters = [
    "example.com"
    "staging.example.com"
  ];

  # Zone ID filtering (optional, more specific than domain filters)
  # zoneIdFilters = [ "abcd1234..." ];

  # Source types to watch
  sources = [
    "service"
    "ingress"
    "gateway-httproute"
    "gateway-grpcroute"
    "gateway-tlsroute"
    "gateway-tcproute"
    "gateway-udproute"
  ];

  # Policy: sync creates, updates, and deletes records
  # upsert-only: creates and updates but never deletes
  policy = "sync";

  # Record ownership via TXT records
  txtOwnerId = "vanixiets-cluster";
  txtPrefix = "externaldns-";

  # Cloudflare-specific settings
  extraArgs = [
    "--cloudflare-proxied=false"  # or true for Cloudflare proxy
    "--cloudflare-dns-records-per-page=5000"
  ];
}
```

### Record ownership

External-DNS uses TXT ownership records to track which DNS records it manages.
The `txtOwnerId` uniquely identifies this cluster's records, preventing conflicts when multiple clusters manage the same zone.
The `txtPrefix` prepends a string to ownership TXT record names to distinguish them from application TXT records.

For a managed A record `app.example.com`, External-DNS creates a corresponding TXT record `externaldns-app.example.com` containing the owner ID.
This mechanism allows External-DNS to safely delete records it created without affecting records created by other systems.

### Sync policies

The `policy` setting controls record lifecycle management.

The `sync` policy (recommended for production) creates, updates, and deletes DNS records.
When a Service or Ingress is deleted, External-DNS removes the corresponding DNS records.
This keeps DNS consistent with cluster state.

The `upsert-only` policy creates and updates records but never deletes them.
Use this policy during initial deployment or when migrating to prevent accidental record deletion.

## Secrets management

The Cloudflare API token authenticates External-DNS to the Cloudflare API.
This secret uses sops-secrets-operator for GitOps-compatible encrypted storage.

### SopsSecret resource

Create the encrypted SopsSecret for the Cloudflare API token.

```yaml
# k8s/secrets/production/external-dns-cloudflare.yaml (before encryption)
apiVersion: isindir.github.com/v1alpha3
kind: SopsSecret
metadata:
  name: external-dns-cloudflare
  namespace: external-dns
spec:
  secretTemplates:
    - name: cloudflare-api-token
      stringData:
        CF_API_TOKEN: your-cloudflare-api-token-here
```

Encrypt the SopsSecret.

```bash
sops --encrypt \
  --encrypted-suffix Templates \
  external-dns-cloudflare.yaml > k8s/secrets/production/external-dns-cloudflare.enc.yaml
```

### Helm secret reference

Configure External-DNS to use the secret created by sops-secrets-operator.

```nix
{
  env = [
    {
      name = "CF_API_TOKEN";
      valueFrom.secretKeyRef = {
        name = "cloudflare-api-token";
        key = "CF_API_TOKEN";
      };
    }
  ];
}
```

### Cloudflare token permissions

Create a Cloudflare API token with minimal required permissions.

Required permissions:
- Zone: DNS: Edit (for all zones managed by External-DNS)
- Zone: Zone: Read (to list and filter zones)

Optional restrictions:
- Limit token to specific zone IDs for tighter security
- Set client IP filtering if cluster has stable egress IPs

Create tokens at Cloudflare Dashboard > My Profile > API Tokens > Create Token.
Store the token in Bitwarden as the source of truth before creating the SopsSecret.

## Domain filtering

Domain filters restrict which DNS zones External-DNS can modify.
Without filters, External-DNS attempts to create records in any zone the API token can access.

### Zone-level filtering

The `domainFilters` option specifies allowed domains.

```nix
domainFilters = [
  "example.com"      # manages *.example.com
  "other.example.com" # manages *.other.example.com
];
```

### Exclude patterns

The `excludeDomains` option prevents management of specific subdomains.

```nix
excludeDomains = [
  "internal.example.com"  # never manage internal subdomain
];
```

### Regex filtering

For complex patterns, use regex domain filters.

```nix
regexDomainFilter = ".*\\.prod\\.example\\.com$";
regexDomainExclusion = ".*\\.legacy\\.example\\.com$";
```

## Source configuration

External-DNS watches Kubernetes resources to discover DNS records.
Configure sources to match your ingress and gateway strategy.

### Service sources

Service resources with `type: LoadBalancer` or specific annotations trigger DNS record creation.

```yaml
apiVersion: v1
kind: Service
metadata:
  name: my-app
  annotations:
    external-dns.alpha.kubernetes.io/hostname: app.example.com
spec:
  type: LoadBalancer
  # ...
```

### Ingress sources

Ingress resources create records based on `spec.rules[].host`.

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: my-app
spec:
  rules:
  - host: app.example.com  # External-DNS creates A/AAAA record
    http:
      paths:
      # ...
```

### Gateway API sources

Gateway API HTTPRoute and other route types create records from hostnames.

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: my-app
spec:
  hostnames:
  - app.example.com  # External-DNS creates A/AAAA record
  parentRefs:
  - name: main-gateway
```

The gateway sources require Gateway API CRDs installed (provided by Cilium when `gatewayAPI.enabled = true`).

## Verification

### Deployment status

```bash
# Check External-DNS pod is running
kubectl get pods -n external-dns -l app.kubernetes.io/name=external-dns

# View logs for sync activity
kubectl logs -n external-dns -l app.kubernetes.io/name=external-dns --tail=100

# Check for errors
kubectl logs -n external-dns -l app.kubernetes.io/name=external-dns | grep -i error
```

### DNS record verification

```bash
# List TXT ownership records
dig TXT externaldns-app.example.com

# Verify A record creation
dig A app.example.com

# Query Cloudflare API directly (requires token)
curl -X GET "https://api.cloudflare.com/client/v4/zones/<zone-id>/dns_records" \
  -H "Authorization: Bearer $CF_API_TOKEN" \
  -H "Content-Type: application/json" | jq '.result[] | {name, type, content}'
```

### Dry-run mode

For initial deployment or debugging, enable dry-run mode to see what records would be created without making changes.

```nix
extraArgs = [
  "--dry-run=true"
];
```

Review logs for planned changes, then disable dry-run for production operation.

## Troubleshooting

### Authentication failures

If External-DNS logs show 401 or 403 errors from Cloudflare.

```bash
# Verify secret exists
kubectl get secret cloudflare-api-token -n external-dns

# Check secret contains expected key
kubectl get secret cloudflare-api-token -n external-dns -o jsonpath='{.data.CF_API_TOKEN}' | base64 -d

# Verify SopsSecret was decrypted
kubectl get sopssecret external-dns-cloudflare -n external-dns -o yaml
```

Common causes:
- SopsSecret not yet processed by operator
- Age decryption key missing from sops-secrets-operator
- Cloudflare token expired or revoked
- Token lacks required permissions

### No records created

If services or ingresses exist but no DNS records appear.

```bash
# Check External-DNS is watching the right namespaces
# Default watches all namespaces unless configured otherwise

# Verify source resource has correct annotations or hostnames
kubectl get ingress -A -o yaml | grep -A5 "external-dns"

# Check domain filters allow the hostname
kubectl logs -n external-dns -l app.kubernetes.io/name=external-dns | grep "Skipping"
```

### Records not deleted

If deleted services or ingresses leave orphaned DNS records.

```bash
# Verify policy is "sync" not "upsert-only"
kubectl get deployment -n external-dns external-dns -o yaml | grep policy

# Check TXT ownership records exist
dig TXT externaldns-app.example.com

# If txtOwnerId changed, old records become orphaned
# Manually delete from Cloudflare dashboard or API
```

### Rate limiting

Cloudflare API has rate limits that may affect large deployments.

```bash
# Check for rate limit errors
kubectl logs -n external-dns -l app.kubernetes.io/name=external-dns | grep -i "rate"

# Increase sync interval to reduce API calls
# Default is 1 minute, increase for large zones
extraArgs = [
  "--interval=5m"
];
```

## Example configuration

Complete easykubenix module for External-DNS with Cloudflare.

```nix
{
  config,
  lib,
  ...
}:
let
  moduleName = "external-dns";
  cfg = config.${moduleName};
in
{
  options.${moduleName} = {
    enable = lib.mkEnableOption moduleName;
    version = lib.mkOption {
      type = lib.types.str;
      default = "1.14.5";
    };
    domains = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      description = "Domains to manage DNS records for";
    };
    ownerId = lib.mkOption {
      type = lib.types.str;
      default = "vanixiets-cluster";
      description = "Unique identifier for this cluster's DNS records";
    };
  };

  config = lib.mkIf cfg.enable {
    helm.releases.${moduleName} = {
      namespace = "external-dns";
      createNamespace = true;
      chart = {
        repository = "https://kubernetes-sigs.github.io/external-dns/";
        name = "external-dns";
        version = cfg.version;
      };

      values = {
        provider.name = "cloudflare";

        domainFilters = cfg.domains;

        sources = [
          "service"
          "ingress"
          "gateway-httproute"
          "gateway-grpcroute"
          "gateway-tlsroute"
          "gateway-tcproute"
          "gateway-udproute"
        ];

        policy = "sync";
        txtOwnerId = cfg.ownerId;
        txtPrefix = "externaldns-";

        env = [
          {
            name = "CF_API_TOKEN";
            valueFrom.secretKeyRef = {
              name = "cloudflare-api-token";
              key = "CF_API_TOKEN";
            };
          }
        ];

        extraArgs = [
          "--cloudflare-proxied=false"
          "--cloudflare-dns-records-per-page=5000"
        ];

        resources = {
          requests = {
            cpu = "50m";
            memory = "64Mi";
          };
          limits = {
            cpu = "100m";
            memory = "128Mi";
          };
        };
      };
    };
  };
}
```

## Related documentation

- Upstream External-DNS documentation: https://kubernetes-sigs.github.io/external-dns/
- Cloudflare provider documentation: https://kubernetes-sigs.github.io/external-dns/v0.14.0/tutorials/cloudflare/
- sops-secrets-operator integration: see `docs/notes/development/kubernetes/components/sops-secrets-operator.md`
- Hetzner deployment workflow: see `docs/notes/development/kubernetes/workflows/04-hetzner-deployment.md`
