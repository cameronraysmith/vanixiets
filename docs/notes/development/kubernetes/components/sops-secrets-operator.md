---
title: SOPS Secrets Operator
---

# SOPS Secrets Operator

The sops-secrets-operator (isindir/sops-secrets-operator) provides Kubernetes-native secret management using Mozilla SOPS encryption.
This operator reads SopsSecret custom resources containing encrypted data and creates standard Kubernetes Secrets by decrypting at runtime.
This approach maintains secrets in git while preventing plaintext exposure in version control.

## Architecture decisions

The vanixiets Kubernetes deployment uses sops-secrets-operator rather than alternatives like HashiCorp Vault or External Secrets Operator (ESO) for several reasons.
HashiCorp Vault introduces significant operational overhead requiring a dedicated cluster, unsealing procedures, and high availability configuration that exceeds the complexity budget for this deployment.
External Secrets Operator primarily targets external secret stores (Vault, AWS Secrets Manager, GCP Secret Manager) rather than git-native encrypted secrets.

The sops-secrets-operator aligns with existing vanixiets patterns where sops-nix already manages secrets for nix-darwin and nixos hosts using age encryption.
Secrets remain encrypted in git, the operator decrypts them using age keys at runtime, and the same tooling (`sops` CLI, `.sops.yaml` configuration) works across both infrastructure and Kubernetes contexts.
This creates a unified secret management workflow where age key distribution is the primary operational concern rather than managing external secret stores.

## Operator deployment

### Helm installation

The operator deploys via Helm chart from the official repository.

```yaml
# values.yaml for sops-secrets-operator
replicaCount: 1
namespaced: false  # watch SopsSecret resources cluster-wide

image:
  repository: quay.io/isindir/sops-secrets-operator
  tag: "0.17.3"
  pullPolicy: Always

# Age key configuration
secretsAsFiles:
  - name: sops-age-key-file
    mountPath: /etc/sops-age-key-file
    secretName: sops-age-key-file

extraEnv:
  - name: SOPS_AGE_KEY_FILE
    value: /etc/sops-age-key-file/key

rbac:
  enabled: true

serviceAccount:
  enabled: true
```

Install with:

```bash
kubectl create namespace sops-secrets-operator
helm repo add sops https://isindir.github.io/sops-secrets-operator/
helm upgrade --install sops-secrets-operator sops/sops-secrets-operator \
  --namespace sops-secrets-operator \
  -f values.yaml
```

### Namespace considerations

The operator typically runs in a dedicated namespace (`sops-secrets-operator`) with cluster-wide permissions.
Setting `namespaced: true` restricts the operator to watch only SopsSecret resources in its own namespace, which limits utility for multi-namespace deployments.
The default cluster-wide mode allows SopsSecret resources in any namespace to generate Kubernetes Secrets in that same namespace.

### RBAC requirements

The operator requires a ClusterRole with the following permissions:

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: sops-secrets-operator
rules:
  - apiGroups: [""]
    resources: ["secrets"]
    verbs: ["*"]
  - apiGroups: [""]
    resources: ["secrets/status"]
    verbs: ["get", "patch", "update"]
  - apiGroups: ["isindir.github.com"]
    resources: ["sopssecrets"]
    verbs: ["create", "delete", "get", "list", "patch", "update", "watch"]
  - apiGroups: ["isindir.github.com"]
    resources: ["sopssecrets/finalizers"]
    verbs: ["update"]
  - apiGroups: ["isindir.github.com"]
    resources: ["sopssecrets/status"]
    verbs: ["get", "patch", "update"]
```

The Helm chart creates this ClusterRole automatically when `rbac.enabled: true`.

## Decryption key setup

### Age key as Kubernetes Secret

The operator requires access to an age private key for decryption.
Create a Kubernetes Secret containing the age key:

```bash
# Create the secret from an existing age key file
kubectl create secret generic sops-age-key-file \
  --namespace sops-secrets-operator \
  --from-file=key=/path/to/age-private-key.txt
```

The age private key file format:

```text
# created: 2024-01-15T10:00:00Z
# public key: age1js028xag70wpwpp47elpq50mjjv7zn7sxuwuhk8yltkjzqzdvq5qq8w8cy
AGE-SECRET-KEY-1QQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQ
```

### Relationship to vanixiets age keys

The vanixiets repository maintains age keys in `.sops.yaml` with distinct key classes:

| Key class | Purpose | Kubernetes usage |
|-----------|---------|------------------|
| `&dev` | Development/repository work | Primary cluster decryption key |
| `&ci` | CI/CD pipelines | GitOps pipeline decryption |
| `&admin` | Offline recovery | Emergency access only |
| `&admin-user` | Admin user identity | User-scoped secrets |
| `&<host>` | Host-specific keys | Not used in Kubernetes |

For Kubernetes clusters, the `&dev` or `&ci` key serves as the decryption key depending on whether the cluster operates in development or production mode.
The same age public key appears in both `.sops.yaml` (for encryption) and as a Kubernetes Secret (for decryption).

### Key distribution to cluster

Key distribution differs between local development and production:

For local development clusters (kind, k3d, minikube):

```bash
# Source the key from Bitwarden or local storage
bw get item "sops-dev-ssh" --field notes > /tmp/sops-dev-key.txt
kubectl create secret generic sops-age-key-file \
  --namespace sops-secrets-operator \
  --from-file=key=/tmp/sops-dev-key.txt
rm /tmp/sops-dev-key.txt
```

For production clusters, the age key should be provisioned through the cluster bootstrap process using terranix or ClusterAPI machine configuration, never committed to git.

## SopsSecret CRD

### CRD structure

The SopsSecret custom resource (v1alpha3 API) defines one or more Kubernetes Secrets to create from encrypted data.

```yaml
apiVersion: isindir.github.com/v1alpha3
kind: SopsSecret
metadata:
  name: example-sopssecret
  namespace: default
spec:
  suspend: false  # set true to pause reconciliation
  secretTemplates:
    - name: my-secret-name
      labels:
        app.kubernetes.io/component: backend
      annotations:
        description: "Database credentials"
      type: Opaque  # optional, defaults to Opaque
      stringData:
        username: plaintext-or-encrypted-value
        password: plaintext-or-encrypted-value
      data:
        binary-key: base64-encoded-value
sops:
  # SOPS metadata added during encryption
  age:
    - recipient: age1js028xag70wpwpp47elpq50mjjv7zn7sxuwuhk8yltkjzqzdvq5qq8w8cy
      enc: |
        -----BEGIN AGE ENCRYPTED FILE-----
        ...
        -----END AGE ENCRYPTED FILE-----
  encrypted_suffix: Templates
  version: 3.9.0
```

### Key fields

The `spec.secretTemplates` array defines the Kubernetes Secrets to create:

- `name`: Name of the resulting Kubernetes Secret (required)
- `labels`: Labels to apply to the Secret
- `annotations`: Annotations to apply to the Secret
- `type`: Secret type (Opaque, kubernetes.io/dockerconfigjson, kubernetes.io/tls, etc.)
- `stringData`: Key-value pairs stored as strings (encrypted by SOPS)
- `data`: Key-value pairs stored as base64 (encrypted by SOPS)

The `spec.suspend` field allows pausing reconciliation without deleting the resource.

### Supported Secret types

```yaml
# Opaque (default)
type: Opaque

# Docker registry credentials
type: kubernetes.io/dockerconfigjson

# TLS certificates
type: kubernetes.io/tls

# Basic authentication
type: kubernetes.io/basic-auth

# SSH authentication
type: kubernetes.io/ssh-auth
```

## SOPS file structure

### Configuration with .sops.yaml

The `.sops.yaml` configuration controls which age keys encrypt which files.
Extend the existing vanixiets configuration for Kubernetes secrets:

```yaml
keys:
  - &dev age1js028xag70wpwpp47elpq50mjjv7zn7sxuwuhk8yltkjzqzdvq5qq8w8cy
  - &ci age1ldx73kk4kvl3mycjdhngxrrv69wn7cvhreqwzl0gphuftnj5pulqaprgel
  - &admin age1vy7wsnf8eg5229evq3ywup285jzk9cntsx5hhddjtwsjh0kf4c6s9fmalv

creation_rules:
  # Kubernetes secrets for local development
  - path_regex: k8s/secrets/local/.*\.yaml$
    key_groups:
      - age:
        - *admin
        - *dev

  # Kubernetes secrets for production
  - path_regex: k8s/secrets/production/.*\.yaml$
    key_groups:
      - age:
        - *admin
        - *ci

  # Shared Kubernetes secrets (both environments)
  - path_regex: k8s/secrets/shared/.*\.yaml$
    key_groups:
      - age:
        - *admin
        - *dev
        - *ci
```

### Age encryption setup

Generate an age key pair if needed:

```bash
age-keygen -o /path/to/new-key.txt
# Public key: age1xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
```

Add the public key to `.sops.yaml` and distribute the private key to authorized decryptors.

### Encryption suffix pattern

SOPS encrypts fields matching the suffix pattern while leaving metadata readable:

```bash
# Encrypt only secretTemplates field
sops --encrypt \
  --age age1js028xag70wpwpp47elpq50mjjv7zn7sxuwuhk8yltkjzqzdvq5qq8w8cy \
  --encrypted-suffix Templates \
  sopssecret.yaml > sopssecret.enc.yaml
```

This preserves:
- `apiVersion`, `kind`, `metadata` in plaintext for GitOps tooling
- `spec.secretTemplates` encrypted

### Path conventions

Organize Kubernetes secrets alongside other vanixiets secrets:

```text
vanixiets/
├── .sops.yaml
├── secrets/
│   ├── hosts/           # Host-specific secrets (sops-nix)
│   ├── users/           # User-specific secrets (sops-nix)
│   └── services/        # Shared service secrets (sops-nix)
└── k8s/
    ├── secrets/
    │   ├── local/       # Local cluster SopsSecrets
    │   ├── production/  # Production cluster SopsSecrets
    │   └── shared/      # Multi-environment SopsSecrets
    └── manifests/       # Non-secret Kubernetes manifests
```

## Workflow

### Encrypt a secret

Create the plaintext SopsSecret resource:

```yaml
# database-credentials.yaml (plaintext, do not commit)
apiVersion: isindir.github.com/v1alpha3
kind: SopsSecret
metadata:
  name: database-credentials
  namespace: application
spec:
  secretTemplates:
    - name: postgres-credentials
      stringData:
        username: app_user
        password: super-secret-password
        connection-string: postgresql://app_user:super-secret-password@db:5432/app
```

Encrypt using SOPS:

```bash
sops --encrypt \
  --encrypted-suffix Templates \
  database-credentials.yaml > k8s/secrets/local/database-credentials.enc.yaml
```

### Apply the SopsSecret

Deploy the encrypted SopsSecret to the cluster:

```bash
kubectl apply -f k8s/secrets/local/database-credentials.enc.yaml
```

The operator detects the SopsSecret, decrypts using the configured age key, and creates the Kubernetes Secret `postgres-credentials` in the `application` namespace.

### Verify the result

```bash
# Check SopsSecret status
kubectl get sopssecret database-credentials -n application

# View created Secret
kubectl get secret postgres-credentials -n application -o yaml

# Decode a value
kubectl get secret postgres-credentials -n application \
  -o jsonpath='{.data.password}' | base64 -d
```

### Update secrets

Edit the encrypted file in place:

```bash
sops k8s/secrets/local/database-credentials.enc.yaml
# Edit values in your editor, save and exit
# SOPS re-encrypts automatically
```

Apply the updated SopsSecret and the operator reconciles the Kubernetes Secret.

## Local vs production environments

### Local development

Local development clusters (kind, k3d, minikube) use the `&dev` age key.
The key can be sourced from Bitwarden or a local secrets file during cluster bootstrap.

```bash
# Bootstrap local cluster with SOPS support
kind create cluster --name local-dev

# Deploy operator
helm install sops-secrets-operator sops/sops-secrets-operator \
  --namespace sops-secrets-operator \
  --create-namespace \
  -f values-local.yaml

# Create decryption key secret
kubectl create secret generic sops-age-key-file \
  --namespace sops-secrets-operator \
  --from-literal=key="$(bw get item sops-dev-ssh --field notes)"
```

### Production clusters

Production clusters use the `&ci` age key distributed through secure bootstrap mechanisms.
Options include:

- **Terranix provisioning**: Age key injected during VM provisioning via cloud-init or similar
- **ClusterAPI**: Age key embedded in machine configuration secret
- **Manual bootstrap**: Age key applied during initial cluster setup before GitOps sync

The production age key should never appear in git, only in:
- Bitwarden (source of truth)
- Cluster bootstrap configuration (encrypted or ephemeral)
- Running cluster Secret

## Integration with nixidy

### SopsSecrets in rendered manifests

Nixidy generates Kubernetes manifests from Nix expressions.
SopsSecret resources integrate as pre-encrypted YAML files referenced in the nixidy configuration.

```nix
# nixidy application definition
{
  applications.my-app = {
    namespace = "application";
    resources = {
      # Reference pre-encrypted SopsSecret
      "SopsSecret/database-credentials" = builtins.readFile ./secrets/database-credentials.enc.yaml;

      # Or inline the encrypted content
      "SopsSecret/api-keys" = {
        apiVersion = "isindir.github.com/v1alpha3";
        kind = "SopsSecret";
        metadata = {
          name = "api-keys";
          namespace = "application";
        };
        # Content from encrypted file
        spec = builtins.fromJSON (builtins.readFile ./secrets/api-keys.enc.json);
      };
    };
  };
}
```

### ArgoCD integration

ArgoCD applies the SopsSecret resources as normal Kubernetes manifests.
The sops-secrets-operator runs in the cluster and creates Secrets when SopsSecret resources appear.
No ArgoCD plugins or special configuration required since decryption happens cluster-side.

```yaml
# ArgoCD Application
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: my-app
  namespace: argocd
spec:
  source:
    repoURL: https://github.com/org/repo
    path: k8s/rendered/my-app
    targetRevision: main
  destination:
    server: https://kubernetes.default.svc
    namespace: application
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
```

### GitOps workflow

The complete workflow:

1. Create plaintext SopsSecret resource locally
2. Encrypt with `sops --encrypt --encrypted-suffix Templates`
3. Commit encrypted SopsSecret to git
4. Nixidy renders manifest including SopsSecret reference
5. ArgoCD syncs rendered manifests to cluster
6. sops-secrets-operator decrypts and creates Kubernetes Secrets
7. Applications consume Secrets normally

## Troubleshooting

### Decryption failures

Check operator logs for decryption errors:

```bash
kubectl logs -n sops-secrets-operator deployment/sops-secrets-operator
```

Common causes:
- Age key Secret not mounted correctly
- `SOPS_AGE_KEY_FILE` environment variable not set
- Age public key in encrypted file does not match available private key
- Corrupted encrypted data

Verify the age key is accessible:

```bash
kubectl exec -n sops-secrets-operator deployment/sops-secrets-operator -- \
  cat $SOPS_AGE_KEY_FILE
```

### Key access issues

If the operator cannot access the age key:

```bash
# Check Secret exists
kubectl get secret sops-age-key-file -n sops-secrets-operator

# Check volume mount
kubectl describe pod -n sops-secrets-operator -l app.kubernetes.io/name=sops-secrets-operator

# Check environment variable
kubectl exec -n sops-secrets-operator deployment/sops-secrets-operator -- \
  env | grep SOPS
```

### SopsSecret status

The SopsSecret resource includes status indicating reconciliation result:

```bash
kubectl get sopssecret -A -o wide
```

Status messages indicate success or describe failures:
- `Healthy`: Secrets created successfully
- `Decryption error: ...`: Failed to decrypt data
- `Secret creation error: ...`: Decryption succeeded but Secret creation failed

### Operator events

Check Kubernetes events for SopsSecret resources:

```bash
kubectl describe sopssecret <name> -n <namespace>
```

### Re-sync secrets

Force reconciliation by updating the SopsSecret:

```bash
kubectl annotate sopssecret <name> -n <namespace> \
  reconcile.time="$(date +%s)" --overwrite
```

Or delete and recreate the SopsSecret (existing Secrets remain until garbage collected).

## Example configurations

### Basic Opaque secret

```yaml
apiVersion: isindir.github.com/v1alpha3
kind: SopsSecret
metadata:
  name: app-secrets
  namespace: default
spec:
  secretTemplates:
    - name: app-credentials
      stringData:
        api-key: sk-1234567890abcdef
        api-secret: secret-value-here
```

Encrypt:

```bash
sops --encrypt --encrypted-suffix Templates app-secrets.yaml > app-secrets.enc.yaml
```

### Docker registry credentials

```yaml
apiVersion: isindir.github.com/v1alpha3
kind: SopsSecret
metadata:
  name: registry-credentials
  namespace: default
spec:
  secretTemplates:
    - name: ghcr-login
      type: kubernetes.io/dockerconfigjson
      stringData:
        .dockerconfigjson: |
          {
            "auths": {
              "ghcr.io": {
                "username": "cameronraysmith",
                "password": "ghp_xxxxxxxxxxxx",
                "auth": "Y2FtZXJvbnJheXNtaXRoOmdocF94eHh4eHh4eHh4eHg="
              }
            }
          }
```

### TLS certificate

```yaml
apiVersion: isindir.github.com/v1alpha3
kind: SopsSecret
metadata:
  name: tls-secrets
  namespace: ingress-nginx
spec:
  secretTemplates:
    - name: wildcard-tls
      type: kubernetes.io/tls
      data:
        tls.crt: LS0tLS1CRUdJTi... # base64 encoded certificate
        tls.key: LS0tLS1CRUdJTi... # base64 encoded private key
```

### Multiple secrets from one SopsSecret

```yaml
apiVersion: isindir.github.com/v1alpha3
kind: SopsSecret
metadata:
  name: application-secrets
  namespace: my-app
spec:
  secretTemplates:
    - name: database-credentials
      stringData:
        host: postgres.database.svc
        port: "5432"
        username: app_user
        password: db-password
    - name: redis-credentials
      stringData:
        host: redis.cache.svc
        port: "6379"
        password: redis-password
    - name: external-api-keys
      stringData:
        stripe-key: sk_live_xxx
        sendgrid-key: SG.xxx
```

### Complete values.yaml for Helm

```yaml
# values.yaml
replicaCount: 1
namespaced: false

image:
  repository: quay.io/isindir/sops-secrets-operator
  tag: "0.17.3"
  pullPolicy: IfNotPresent

secretsAsFiles:
  - name: sops-age-key-file
    mountPath: /etc/sops-age-key-file
    secretName: sops-age-key-file

extraEnv:
  - name: SOPS_AGE_KEY_FILE
    value: /etc/sops-age-key-file/key

logging:
  development: false
  encoder: json
  level: info
  stacktraceLevel: error

healthProbes:
  port: 8081
  liveness:
    initialDelaySeconds: 15
    periodSeconds: 20
  readiness:
    initialDelaySeconds: 5
    periodSeconds: 10

rbac:
  enabled: true

serviceAccount:
  enabled: true
  annotations: {}

resources:
  requests:
    cpu: 10m
    memory: 64Mi
  limits:
    cpu: 100m
    memory: 128Mi

metrics:
  enabled: true
  additionalLabels:
    prometheus: cluster-prometheus
```
