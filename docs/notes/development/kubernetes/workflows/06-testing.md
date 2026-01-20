---
title: Testing
---

# Testing

This document covers the testing strategy for the Kubernetes + Nix platform, including local validation, chainsaw integration tests, and CI workflow execution.

## Testing layers

The platform uses a layered testing approach:

1. **Nix evaluation tests** - Validate module composition and rendered manifests at build time via `nix eval` and `nix-unit`
2. **Chainsaw integration tests** - Validate deployed resources reach expected state in a real cluster
3. **Manual verification** - Exploratory testing and edge case validation

## Chainsaw integration tests

[Chainsaw](https://kyverno.github.io/chainsaw/) provides declarative end-to-end testing for Kubernetes resources.
Tests are YAML-based with apply/assert steps that verify resources reach expected state.

### Test structure

Tests live in `tests/kubernetes/` with a structure mirroring deployment stages:

```text
tests/kubernetes/
├── foundation/           # Cilium, ArgoCD base
│   ├── chainsaw-test.yaml
│   └── assert-cilium.yaml
├── infrastructure/       # cert-manager, step-ca, sops-operator
│   ├── chainsaw-test.yaml
│   └── assert-*.yaml
└── common/               # Shared assertions
    └── assert-*.yaml
```

### Test pattern

Each chainsaw test follows the apply/assert pattern:

```yaml
apiVersion: chainsaw.kyverno.io/v1alpha1
kind: Test
metadata:
  name: foundation
spec:
  steps:
    - try:
        - apply:
            file: manifests/cilium.yaml
        - assert:
            file: assert-cilium.yaml
        - apply:
            file: manifests/argocd.yaml
        - assert:
            file: assert-argocd.yaml
```

Assert files verify expected state:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: cilium-operator
  namespace: kube-system
status:
  availableReplicas: 1
```

### Reference implementation

See `~/projects/sciops-workspace/crossplane-kubernetes/tests/` for a production example with:
- Provider-specific tests (aws/, azure/, google/)
- Shared assertions (common/)
- Template bindings for parameterized tests

## CI workflow integration

The `.github/workflows/kubernetes.yaml` workflow executes tests in three phases:

1. **Nix validation** - Evaluate modules, build derivations dry-run
2. **k3d cluster** - Spin up ephemeral k3d cluster in CI runner
3. **Chainsaw execution** - Run integration tests against live cluster

### Workflow structure

```yaml
jobs:
  validate:
    # Nix evaluation and build checks

  integration:
    needs: validate
    # k3d cluster creation
    # Chainsaw test execution
```

### Local test execution

Run tests locally against the k3d cluster:

```bash
# Ensure cluster is running
just k3d-full

# Run chainsaw tests
chainsaw test tests/kubernetes/

# Run specific test suite
chainsaw test tests/kubernetes/foundation/
```

## Test development workflow

When adding new infrastructure components:

1. Add the component via easykubenix/nixidy modules
2. Deploy to local k3d cluster
3. Identify assertions (pod ready, service available, CRD established)
4. Create assert YAML files capturing expected state
5. Add apply/assert steps to chainsaw-test.yaml
6. Verify tests pass locally before committing

## Related resources

- [Chainsaw documentation](https://kyverno.github.io/chainsaw/)
- [crossplane-kubernetes tests](https://github.com/upbound/configuration-kubernetes) - Reference implementation
- [Local development workflow](02-local-development.md) - k3d cluster setup
