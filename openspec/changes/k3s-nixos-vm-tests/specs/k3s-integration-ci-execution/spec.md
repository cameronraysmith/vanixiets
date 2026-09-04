## ADDED Requirements

### Requirement: VM leaves are independent Linux-only checks requiring KVM

Each VM regulator SHALL be exposed as one `perSystem.checks.vm-<subject>` derivation, present only where `pkgs.stdenv.hostPlatform.isLinux`, built through `nixosLib.runTest`, and SHALL carry `requiredSystemFeatures` containing `kvm` and `nixos-test`; no non-VM check SHALL depend on a VM check.

#### Scenario: A leaf is enumerated

- **WHEN** `nix eval .#checks.x86_64-linux --apply builtins.attrNames` is run
- **THEN** each `vm-k3s-*` leaf appears as its own attribute, and `nix eval .#checks.aarch64-darwin --apply builtins.attrNames` lists none of them

#### Scenario: A VM leaf's system features are inspected

- **WHEN** `nix derivation show .#checks.x86_64-linux.vm-k3s-single-node` is run
- **THEN** `env.requiredSystemFeatures` contains `kvm` and `nixos-test`

### Requirement: The developer host discovers VM leaves by prefix

`just test-integration` SHALL build every `checks.<system>.vm-*` leaf for the current system, including the k3s leaves, and SHALL NOT enumerate them by name.

#### Scenario: A new leaf is added

- **WHEN** a `vm-k3s-multi-node` leaf is added and `just test-integration` is run on a KVM-capable Linux host
- **THEN** the new leaf is built without any change to the justfile

### Requirement: VM leaves gate CI only from a runner whose KVM has been probed

A VM regulator SHALL be added to a GitHub Actions job only after a manually dispatched probe on the same runner label has built `vm-k3s-single-node` under `--option system-features 'kvm nixos-test benchmark big-parallel'` three consecutive times; if the probe fails, the fallback runner SHALL be chosen explicitly before any VM job is added.
This requirement rests on world assumption A14.

#### Scenario: The probe passes

- **WHEN** the probe job passes three consecutive dispatches on `ubuntu-latest`
- **THEN** a `vm` job building the VM leaves is added to `test-cluster.yaml` on that label with the probe run links recorded in the change

#### Scenario: The probe fails

- **WHEN** `/dev/kvm` is absent or the build is refused for a missing system feature on the probed runner
- **THEN** no VM job is added to that runner, and the change records the failure and the chosen fallback

### Requirement: The buildbot worker leaves VM leaves inert without failing anything else

On the buildbot worker, which exposes neither `kvm` nor `nixos-test`, VM leaves SHALL be unschedulable or filtered, and no other check's verdict SHALL change because of them.

#### Scenario: A push with VM leaves reaches buildbot

- **WHEN** a branch adding `vm-k3s-single-node` is pushed and buildbot evaluates the flake
- **THEN** every non-VM check reports the same verdict as before the leaf existed, and the VM leaf is either absent from the schedule or reported as skipped for a missing feature, never as a failure of the branch

### Requirement: Cached CI hashing covers the VM leaves' inputs

When VM leaves run in GitHub Actions through `cached-ci-job`, its `hash-sources` SHALL include `modules/checks/vm-k3s-*.nix`, `modules/nixos/k3s-server/**`, the VM nixidy environment sources, and the age fixture, so that a change to any of them invalidates the cache.

#### Scenario: A module change invalidates the cache

- **WHEN** a sysctl value in `modules/nixos/k3s-server/kernel.nix` changes and the workflow runs
- **THEN** the cached job reports a cache miss and rebuilds the VM leaves

### Requirement: The k3d integration path is deleted only after the platform leaf is green

`modules/apps/cluster/k3d-integration-ci.sh`, `k3d-full.sh`, `k3d-wait-ready.sh`, `k3d-wait-argocd-sync.sh`, `k3d-bootstrap-secrets.sh`, `k3d-configure-dns.sh`, `k3d-test-coverage.sh`, `scripts/k3d-test-coverage.sh`, the `integration` job and `SOPS_AGE_KEY` line in `test-cluster.yaml`, the `local-k3d-ci` nixidy environment, and the k3d justfile recipes that only the CI path used SHALL be deleted in one commit that is separate from the commit promoting the VM job, and only after `vm-k3s-platform` has passed in CI on the chosen runner.

#### Scenario: Deletion is proposed before the platform leaf is green

- **WHEN** a change deleting any listed k3d file is opened while `vm-k3s-platform` has not passed on the chosen CI runner
- **THEN** review rejects the change

#### Scenario: The deletion is reverted

- **WHEN** the deletion commit is reverted
- **THEN** the k3d `integration` job runs again and the `vm` job is unaffected
