# ADR-006: Nixidy Manifest Distribution Architecture

## Status

Accepted (2026-01-20)

## Context

Nixidy generates ArgoCD Application manifests from Nix expressions, enabling type-safe GitOps configuration.
The generated manifests include all Kubernetes resources that ArgoCD will deploy, including Secrets.

Helm charts commonly auto-generate secrets during template rendering (CA certificates, TLS keys, passwords).
These secrets contain sensitive data that should not be committed to public repositories.

Investigation of the nixidy and nixidy-cluster repositories revealed the intended pattern:
- Nixidy renders Secret manifests as empty stubs (no `data:` section)
- Actual secret values are stored encrypted via sops and injected by sops-secrets-operator at runtime

However, this pattern requires modifying every Helm chart that auto-generates secrets, which does not scale.
Charts like Cilium generate CA/TLS certificates at template time, embedding private keys in the rendered output.

## Decision

Adopt a **separate private repository per cluster** for rendered manifests.

### Architecture

```
vanixiets (source, public)              local-k3d (rendered, private)
┌────────────────────────────┐          ┌────────────────────────────┐
│ kubernetes/nixidy/         │          │ apps/                      │
│   └── local-k3d/           │  render  │   └── Application-*.yaml   │
│       └── apps/*.nix       │ ───────► │ cilium/                    │
│                            │          │   ├── DaemonSet-*.yaml     │
│ (Nix expressions)          │   push   │   └── Secret-*.yaml        │
│ (No rendered YAML)         │          │ (All rendered manifests)   │
│ (No secrets)               │          │ (Including secrets)        │
└────────────────────────────┘          └────────────────────────────┘
                                                    │
                                                    ▼
                                             ArgoCD watches
```

### Repository Naming Convention

Each cluster gets a dedicated private repository named after the cluster:
- `local-k3d` → `github.com/cameronraysmith/local-k3d` (private)
- `hetzner-prod` → `github.com/cameronraysmith/hetzner-prod` (private)
- etc.

### Workflow

1. Edit Nix expressions in vanixiets
2. Run `just nixidy-build` to render manifests to `result/`
3. Run `just nixidy-push` to push rendered manifests to the cluster's private repo
4. ArgoCD (watching the private repo) syncs the changes

### Nixidy Configuration

Each cluster's nixidy configuration points to its dedicated manifest repository:

```nix
nixidy.target = {
  repository = "https://github.com/cameronraysmith/local-k3d.git";
  branch = "main";
  rootPath = ".";  # Manifests at repo root
};
```

## Consequences

### Benefits

- **Security**: Secrets can be committed to private repos without exposure risk
- **Scalability**: No need to modify Helm chart behavior for secret handling
- **Separation of concerns**: Source config (Nix) vs deployment state (YAML) clearly separated
- **Access control**: Each cluster can have different access permissions
- **Auditability**: Private repo shows exact deployed state including secrets
- **CI/CD friendly**: Rendering and pushing can be automated in pipelines

### Trade-offs

- **Multiple repositories**: Each cluster requires a separate private repository
- **Sync overhead**: Manual or CI-driven push step required after Nix changes
- **Repository proliferation**: Many clusters means many repos to manage

### Mitigations

- Use GitHub organization with consistent naming convention
- Automate rendering and pushing via CI/CD (GitHub Actions)
- Consider monorepo with branch-per-cluster as alternative for fewer clusters

## Alternatives Considered

### Option A: Monorepo with secrets in .gitignore

Store rendered manifests in vanixiets, exclude secrets via `.gitignore`.

**Rejected**: ArgoCD needs the secrets to exist in git. Missing manifests cause sync failures or pruning.

### Option B: Modify Helm charts to not render secrets

Configure each Helm chart to skip secret generation, use external-secrets or sops-secrets-operator.

**Rejected**: Requires chart-by-chart configuration, does not scale, fights against chart defaults.

### Option C: Encrypt secrets with sops in source repo

Use sops-encrypted secrets committed alongside rendered manifests in vanixiets.

**Rejected**: Adds complexity, requires decryption workflow, mixes concerns in single repo.

## References

- nixidy documentation: https://arnarg.github.io/nixidy/
- nixidy-cluster example: https://github.com/arnarg/nixidy-cluster
- ArgoCD App of Apps pattern: https://argo-cd.readthedocs.io/en/stable/operator-manual/cluster-bootstrapping/
