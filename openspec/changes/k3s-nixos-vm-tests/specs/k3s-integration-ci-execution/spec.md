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

A VM regulator SHALL be added to a GitHub Actions job only after a manually dispatched probe on the same runner label has built `vm-k3s-single-node` under `--option system-features 'kvm nixos-test benchmark big-parallel'` three consecutive times; if the probe fails, VM leaves remain developer-host regulators run through `just test-integration` until a KVM-capable runner exists, and no k3d deletion proceeds in the meantime.
This requirement rests on world assumption A14.

#### Scenario: The probe passes

- **WHEN** the probe job passes three consecutive dispatches on `ubuntu-latest`
- **THEN** a `vm` job building the VM leaves is added to `test-cluster.yaml` on that label with the probe run links recorded in the change

#### Scenario: The probe fails

- **WHEN** `/dev/kvm` is absent or the build is refused for a missing system feature on the probed runner
- **THEN** no VM job is added to that runner, the change records the failure, and the VM leaves remain developer-host regulators

### Requirement: The buildbot worker leaves VM leaves inert without failing anything else

On the buildbot worker, which exposes neither `kvm` nor `nixos-test`, VM leaves SHALL be unschedulable or filtered, and no other check's verdict SHALL change because of them.

#### Scenario: A push with VM leaves reaches buildbot

- **WHEN** a branch adding `vm-k3s-single-node` is pushed and buildbot evaluates the flake
- **THEN** every non-VM check reports the same verdict as before the leaf existed, and the VM leaf is either absent from the schedule or reported as skipped for a missing feature, never as a failure of the branch

### Requirement: Cached CI hashing covers the VM leaves' inputs

When VM leaves run in GitHub Actions through `cached-ci-job`, its `hash-sources` SHALL include `modules/checks/vm-*.nix`, `modules/nixos/k3s-server/**`, the easykubenix cluster module sources, the OCI-layout and Flux install derivation sources, and the age and cosign fixtures, so that a change to any of them invalidates the cache.

#### Scenario: A module change invalidates the cache

- **WHEN** a sysctl value in `modules/nixos/k3s-server/kernel.nix` changes and the workflow runs
- **THEN** the cached job reports a cache miss and rebuilds the VM leaves

### Requirement: Registry and cloud publishing are effects, never checks

Pushing the configuration artifact to GHCR, pushing portable images, uploading a Hetzner snapshot, and applying Cluster API objects to a real management cluster SHALL be exposed as `apps.<system>.<name>` outputs that run outside the sandbox, SHALL NOT be reachable from any `checks.<system>.*` derivation, and each SHALL fail when the remote state disagrees with the store-resident value it published (registry digest, snapshot label, applied object generation).
Coverage bin: E; non-vacuity: the digest-mismatch scenario in `k3s-manifest-purity-regulator` and the scenario below.

#### Scenario: A check reaches for an effect

- **WHEN** a derivation under `checks.<system>` references the store path of an `apps` publishing script or opens a network connection
- **THEN** the sandbox build fails, and review rejects any change that relaxes the sandbox to make it pass

#### Scenario: The snapshot label disagrees

- **WHEN** `nix run .#apps.x86_64-linux.upload-node-snapshot` finishes and the Hetzner API reports a snapshot whose `caph-image-name` label differs from the flake-revision-derived value the derivation recorded
- **THEN** the effect exits non-zero naming both values

### Requirement: Management-cluster handlers satisfy one contract from every developer platform

The management cluster SHALL be reachable from `aarch64-darwin`, `x86_64-linux` with KVM, and `x86_64-linux` without KVM through the same contract — a kubeconfig plus CAPI core, CAPH, and cluster-api-k3s providers installed from Nix-rendered manifests via a `clusterctl.yaml` override — by handler A (the NixOS k3s node closure as a QEMU VM through `virtualisation.host.pkgs`) or handler B (k3d via the existing ctlptl recipes stripped to CAPI controllers); a `just` recipe SHALL select the handler, and the rendered CRs applied afterwards SHALL be identical.
Coverage bin: T3 for handler A (`vm-capi-management`), K for handler B (recipe, not a check); non-vacuity: the scenario below.

#### Scenario: The provider set is inspected on either handler

- **WHEN** `kubectl get providers -A` is run against a management cluster produced by handler A or handler B
- **THEN** the same three provider names and versions are listed, and `kubectl apply --dry-run=server` of the rendered `Cluster` CRs succeeds on both

#### Scenario: The provider manifests are not Nix-rendered

- **WHEN** a handler recipe runs `clusterctl init` without the `clusterctl.yaml` override pointing at store paths
- **THEN** the recipe fails before contacting the cluster, because the override file is a required argument

### Requirement: The k3d integration path is deleted only after the platform leaf is green

`modules/apps/cluster/k3d-integration-ci.sh`, `k3d-full.sh`, `k3d-wait-ready.sh`, `k3d-wait-argocd-sync.sh`, `k3d-bootstrap-secrets.sh`, `k3d-configure-dns.sh`, `k3d-test-coverage.sh`, `scripts/k3d-test-coverage.sh`, the `integration` job and `SOPS_AGE_KEY` line in `test-cluster.yaml`, the `local-k3d-ci` nixidy environment, `modules/nixidy.nix`, `kubernetes/nixidy/`, the ArgoCD and sops-secrets-operator manifests, and the k3d justfile recipes that only the CI path used SHALL be deleted in one commit that is separate from the commit promoting the VM job, and only after `vm-k3s-platform` has passed in CI on the chosen runner and the first Flux SOPS cutover has converged; `kubernetes/clusters/local-k3d/` and the ctlptl recipes SHALL survive as management handler B.

#### Scenario: Deletion is proposed before the platform leaf is green

- **WHEN** a change deleting any listed k3d file is opened while `vm-k3s-platform` has not passed on the chosen CI runner
- **THEN** review rejects the change

#### Scenario: The deletion is reverted

- **WHEN** the deletion commit is reverted
- **THEN** the k3d `integration` job runs again and the `vm` job is unaffected
