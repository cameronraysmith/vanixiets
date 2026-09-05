## Why

The production NixOS k3s module, `flake.modules.nixos.k3s-server`, is imported by no machine and no check, so nothing regulates it; its `virtualisation.containerd.settings` block has been inert since it was written and nothing noticed.
The one integration workflow the platform has, the k3d run in `.github/workflows/test-cluster.yaml`, keeps kube-proxy and ServiceLB and disables Cilium's kube-proxy replacement, so it regulates an envelope that differs from the production one exactly where Cilium's datapath and Gateway address assignment are concerned; it also depends on a mounted git tree, ArgoCD, and a GitHub-held age key, none of which is a store path with a digest.
PR #2954 has established the repository's full QEMU/KVM regulator pattern and a KVM-capable developer host now exists, so the reason the k3d workflow was the only option no longer holds.
The design review of 2026-09-04 fixed the target this change plans toward: a two-node, Cluster-API-managed (cluster-api-k3s + CAPH), Nix-native, Flux-reconciled k3s cluster on Hetzner whose declaration is cloud-invariant except for a typed platform submodule, with every regulator hermetic and placed at its cheapest sufficient tier.

## What Changes

This change is planning-only.
It records the research and decisions in ADR-007, ADR-008, and ADR-009 (`docs/notes/development/kubernetes/decisions/`) and writes the artifacts six later stages implement against; no check leaf, module edit, flake input, workflow edit, cloud resource, or deletion happens here.
The first revision of this change planned ArgoCD synced from a nixidy-rendered tree in four stages; that plan is superseded here, ADR-006 is reversed, and nixidy is retired in favour of easykubenix.

**S0 — purity and provenance regulators (KVM-free)**
T1 leaves over the easykubenix-rendered tree: `k8s-manifest-purity` (no `flakeRef`, `nixExpr`, `:latest`, or unpinned image reference), `k8s-images-preloaded` (rendered image references ⊆ preload set), `k8s-closure-provenance` (a `nix path-info -r` and image-digest report), `flux-sources-pinned` (every `OCIRepository` has `spec.ref.digest` and `spec.verify`), `flux-install-rendered` (`flux install --export` from `pkgs.fluxcd`, exactly source, kustomize, and notification controllers), `k3s-server-eval` (the module's rendered `ExecStart`, kernel, sysctls, firewall, `--snapshotter nix`, no host containerd), and the CAPI rendering leaves `capi-cloud-invariant-render`, `capi-platform-sum-total`, `capi-ccm-present`, `clustermesh-preconditions`.
These run on the buildbot worker on every push.

**S1 — substrate and snapshotter leaves**
`vm-k3s-single-node` boots one QEMU node importing `flake.modules.nixos.k3s-server` unmodified with no CNI and asserts the substrate: node registered and `NotReady` for exactly the missing-CNI reason, CoreDNS `Pending`, no flannel or kube-proxy artifacts, CIDRs in effect, modules and sysctls applied, firewall present, containerd's `nix` snapshotter plugin active, NRI state recorded, kubeconfig unreadable by an unprivileged user, `k3s-killall.sh` cleans up.
`vm-k3s-nix-workload` runs one `nix-snapshotter.buildImage` pod through the `nix:0` reference with a test-only flannel override as glue.
`vm-k3s-multi-node` joins a `role = "agent"` node to a `role = "server"` node over one VLAN with a store-path token through the production firewall.
The production module gains `k3s-server.snapshotter` (default `"nix"`) and `pkgs.nix` on the unit path, and the inert host containerd block is deleted, in a separate module change sequenced before S1.

**S2 — platform stack in a VM through Flux**
One T3 leaf `vm-k3s-platform` preloads every image the rendered tree references through `services.k3s.images`, installs Flux from `services.k3s.manifests`, seeds an in-guest registry from the sandbox-built OCI layout, points the root `OCIRepository` at it by digest with a test-only cosign public key in `spec.verify`, decrypts SOPS Secrets with a test-only age key, supplies the Gateway address through Cilium LB-IPAM, and runs the Chainsaw suite in the guest with the ArgoCD assertions replaced by `Kustomization` readiness and `lastAppliedRevision` equality.
The `apps` effect `push-cluster-artifact` that pushes the same layout to GHCR and asserts digest equality is written here and run for the first time in S4.

**S3 — management-cluster handlers and the CAPI bootstrap seam**
`vm-k3s-capi-bootstrap` boots a `bootstrap = "cloud-init"` node from a sandbox-built NoCloud `cidata` seed carrying the `write_files` and `runcmd` cluster-api-k3s would emit in `airGapped` mode, and asserts the Nix-written `/opt/install.sh` shim starts `k3s.service` from `services.k3s.configPath`.
`vm-capi-management` runs handler A (the k3s node closure as a QEMU VM) with CAPI core, CAPH, and cluster-api-k3s installed from Nix-rendered manifests through a `clusterctl.yaml` override and accepts the rendered `Cluster` CRs without a cloud.
Handler B (k3d via ctlptl stripped to CAPI controllers) is a `just` recipe, not a check.

**S4 — two Hetzner nodes (spend; explicit approval)**
The node image is uploaded as a Hetzner snapshot labelled `caph-image-name=k3s-<flake-rev>`, the rendered CRs are applied to a management cluster, two nodes become `Ready`, Flux converges on the pushed artifact, and a flake bump rolls one node.
Nothing in S4 starts without explicit words from the owner.

**S5 — render-only platform variants**
`gcp` and `aws` variants of the `platform` sum are added as golden-diff render tests; `capi-cloud-invariant-render` proves the core is identical modulo platform-owned fields.

**Execution and deletion**
A manually dispatched probe establishes whether `ubuntu-latest` can build a VM leaf under KVM; if not, VM leaves run only on developer KVM hosts through `just test-integration` until a KVM runner exists.
The buildbot worker leaves VM leaves unschedulable and nothing else fails because of it.
Once `vm-k3s-platform` is green, the k3d integration scripts, the `integration` job, the `SOPS_AGE_KEY` wiring, the `local-k3d-ci` environment, the nixidy tree, and sops-secrets-operator are deleted; `kubernetes/clusters/local-k3d/` and the ctlptl recipes survive as management handler B.

## Capabilities

### New Capabilities
- `k3s-substrate-vm-regulator` (stratum: `behavioral`): what the fleet requires of regulators for the NixOS k3s node substrate — that the production module is exercised unmodified, that each claimed node property is observed on a booted kernel, that a missing CNI is detected for its actual reason, that the `nix` snapshotter and NRI state are asserted rather than assumed, that a second node can join through the production firewall, that a `cloud-init` bootstrap node starts from a NoCloud seed, and that each assertion is shown to fail under a mutation.
- `k3s-platform-vm-regulator` (stratum: `behavioral`): what the fleet requires of a hermetic regulator for the deployed platform stack — that every image is a build input, that Flux consumes a digest-pinned, signature-verified OCI artifact from an in-guest registry, that Secrets decrypt with a test-only age key whose non-coverage of production key lifecycle is stated, that certificate issuance and Gateway address assignment complete without network, and that the Chainsaw suite is the oracle.
- `k3s-manifest-purity-regulator` (stratum: `behavioral`): the KVM-free properties of the rendered tree and its artifacts — purity, preload coverage, closure provenance, pinned and verified Flux sources, the rendered Flux install, and OCI-layout digest equality at the push boundary.
- `capi-cluster-rendering` (stratum: `behavioral`): the eval-time properties of the easykubenix cluster module — a cloud-invariant core, a total `platform` sum, a mandatory per-cloud CCM tied to the bootstrap seam, and ClusterMesh preconditions.
- `k3s-integration-ci-execution` (stratum: `interface`): the properties at the CI and developer-host boundary — that VM leaves are independent `checks.<system>.vm-*` derivations requiring `kvm nixos-test`, discovered by `just test-integration`, built in CI only on a probed KVM runner, inert on the buildbot worker without failing anything else, that registry and cloud publishing are `apps` effects and never checks, and that the k3d scripts are deleted only after the platform leaf is green.

### Modified Capabilities
- `world-assumptions` (stratum: `world`): assumptions are added — the Nix build sandbox has no network; GitHub-hosted runner nested virtualization is unsupported by the vendor; a Gateway becomes Programmed only once an address is assigned; an OCI manifest digest is a function of its bytes; cluster-api-k3s defaults `cloud-provider=external`; ClusterMesh requires disjoint PodCIDRs.

## Impact

Implementation, in later changes, touches: new leaves under `modules/checks/` named in the stage list; a `modules/kubernetes/` easykubenix cluster module with the `platform` sum; a Nix-rendered Flux install and OCI-layout derivation; `apps` effects for artifact push and snapshot upload; test-only age and cosign fixtures outside `modules/`; `k3s-server.snapshotter` and `k3s-server.bootstrap` options and the deletion of the inert containerd block in `modules/nixos/k3s-server/`; a Clan `wireguard` instance for the Kubernetes admin plane; a probe job and then a `vm` job in `.github/workflows/test-cluster.yaml`; and the deletions listed above.
Nothing under `modules/nixos/k3s-server/`, `modules/nixidy.nix`, `kubernetes/`, `.github/workflows/`, or the flake inputs is edited by this change.
S4 spends money on Hetzner and requires explicit approval that is never inferred from silence.
