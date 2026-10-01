## Why

The production NixOS k3s module, `flake.modules.nixos.k3s-server`, is imported by no machine and no check, so nothing regulates it; its `virtualisation.containerd.settings` block has been inert since it was written and nothing noticed.
The one integration workflow the platform has, the k3d run in `.github/workflows/test-cluster.yaml`, keeps kube-proxy and ServiceLB and disables Cilium's kube-proxy replacement, so it regulates an envelope that differs from the production one exactly where Cilium's datapath and Gateway address assignment are concerned; it also depends on a mounted git tree, ArgoCD, and a GitHub-held age key, none of which is a store path with a digest.
PR #2954 has established the repository's full QEMU/KVM regulator pattern and a KVM-capable developer host now exists, so the reason the k3d workflow was the only option no longer holds.
The design review of 2026-09-04 and the scope review the same day fixed the target: one new sibling cluster, `kubernetes/clusters/cryolite` (named in ADR-007 D7.20), that is two-node, Cluster-API-managed, Nix-native, and Flux-reconciled, with every regulator hermetic and placed at its cheapest sufficient tier, while the existing `local` and `local-k3d` clusters stay frozen prototypes that nothing here migrates, edits, or deletes.

## What Changes

This change is planning-only.
It records the research and decisions in ADR-007, ADR-008, ADR-009, and ADR-010 (`docs/notes/development/kubernetes/decisions/`) and writes the artifacts stages S0–S2 implement against; no check leaf, module edit, flake input, workflow edit, cloud resource, or deletion happens here.
Stages S3, S4, S4b, and the deferred S5 — Cluster API rendering, the management-cluster handler, the NoCloud-seeded bootstrap leaf, the Hetzner deployment, the admin overlay, and the render-only cloud variants — are the sibling change `openspec/changes/capi-hetzner-cluster/`, which depends on this one.
The initial draft of this change planned ArgoCD synced from a nixidy-rendered tree in four stages, and its first revision planned a global cutover to Flux and easykubenix with nixidy, ArgoCD, sops-secrets-operator, and the k3d workflow deleted at the end; revision 2 keeps the Flux and easykubenix architecture for `cryolite` only and moves every deletion and global reversal to Future Work below.

**S0 — purity, provenance, and identity regulators (KVM-free)**
T1 leaves over the easykubenix-rendered tree of `cryolite`: `k8s-purity-cryolite` (no `flakeRef`, `nixExpr`, `:latest`, tag-without-digest, or untagged image reference; rendered images ⊆ preload set), `k8s-provenance-cryolite` (a `nix path-info -r` and image-digest report including the OCI-layout digest), `k8s-node-identity-free-cryolite` (no CAPI CR, Flux manifest, Clan inventory entry, or Secret index names a node or node key; ADR-010 D10.6), `flux-sources-pinned` (every `OCIRepository` has `spec.ref.digest` and `spec.verify`), `flux-install-rendered` (`flux install --export` from `pkgs.fluxcd`, exactly source, kustomize, and notification controllers), and `k3s-server-eval` (the module's rendered `ExecStart`, kernel, sysctls, firewall, `--snapshotter nix`, no host containerd).
The `apps.k8s.oci-push` effect that pushes the OCI layout to GHCR and asserts registry digest equality is written here and first run in S4 of the sibling change.
These run on the buildbot worker on every push.

**S1 — substrate and snapshotter leaves (KVM)**
`vm-k3s-substrate` boots one QEMU node importing `flake.modules.nixos.k3s-server` unmodified with no CNI and asserts the substrate: node registered and `NotReady` for exactly the missing-CNI reason, CoreDNS `Pending`, no flannel or kube-proxy artifacts, CIDRs in effect, modules and sysctls applied, firewall present, containerd's `nix` snapshotter plugin active, NRI state recorded, kubeconfig unreadable by an unprivileged user, `k3s-killall.sh` cleans up.
`vm-k3s-snapshotter` runs one `nix-snapshotter.buildImage` pod through the `nix:0` reference with a test-only flannel override as glue.
The production module gains `k3s-server.snapshotter` (default `"nix"`) and `pkgs.nix` on the unit path, and the inert host containerd block is deleted, in a separate module change sequenced before S1; these are the only edits to an existing file, and they are additive or dead-code removal.
There is no standalone multi-node substrate leaf; the join path is asserted in S2 where Cilium is present.

**S2 — the `cryolite` core in a VM through Flux (KVM)**
One T3 leaf `vm-k3s-platform` boots two guests, a `cryolite` server and a `cryolite` agent, preloads every image the rendered tree references through `services.k3s.images`, runs Cilium with `kubeProxyReplacement=true` (the production envelope; this closes ADR-007 F2 for `cryolite` only, `local-k3d` keeps kube-proxy), installs Flux from `services.k3s.manifests`, seeds an in-guest registry from the sandbox-built OCI layout, points the root `OCIRepository` at it by digest with a test-only cosign public key in `spec.verify`, decrypts SOPS Secrets with a test-only age key standing in for the `cryolite` T0 key, answers the certificate hostnames from in-VM DNS, supplies the Gateway address through Cilium LB-IPAM, and runs the Chainsaw suite `kubernetes/tests/cryolite` in the guest: foundation (Cilium ready, Flux root `Kustomization` ready at the pinned digest) and infrastructure (cert-manager, step-ca, `ClusterIssuer`, `Gateway`, `Certificate`s, `HTTPRoute`).
That suite is written for `cryolite`; it is not a copy of `kubernetes/tests/local-k3d` and asserts nothing about ArgoCD or sops-secrets-operator.

**Execution**
A manually dispatched probe establishes whether `ubuntu-latest` can build a VM leaf under KVM; if it passes repeatedly, `test-cluster.yaml` gains a `vm` job beside the existing `integration` job, which is not edited; if not, VM leaves run only on developer KVM hosts through `just test-integration` until a KVM runner exists.
The buildbot worker leaves VM leaves unschedulable and nothing else fails because of it.

**Future Work (not this change, not the sibling change)**
A later, separately authorized feedback change decides whether the frozen prototypes are migrated to the `cryolite` architecture or retired; only that change may delete the k3d integration scripts, the `integration` job and its `SOPS_AGE_KEY` wiring, the `local-k3d-ci` environment, `modules/nixidy.nix`, `kubernetes/nixidy/`, ArgoCD, or sops-secrets-operator, or mark ADR-006 superseded.
Until then ArgoCD reconciles `local-k3d` and Flux reconciles `cryolite`; the two coexist in the repository, one per cluster.

## Capabilities

### New Capabilities
- `k3s-substrate-vm-regulator` (stratum: `behavioral`): what the fleet requires of regulators for the NixOS k3s node substrate — that the production module is exercised unmodified, that each claimed node property is observed on a booted kernel, that a missing CNI is detected for its actual reason, that the `nix` snapshotter and NRI state are asserted rather than assumed, and that each assertion is shown to fail under a mutation.
- `k3s-platform-vm-regulator` (stratum: `behavioral`): what the fleet requires of a hermetic regulator for the `cryolite` core — that every image is a build input, that a second node joins through the production firewall and Cilium runs with kube-proxy replacement, that Flux consumes a digest-pinned, signature-verified OCI artifact from an in-guest registry, that Secrets decrypt with a test-only age key whose non-coverage of the T0 key lifecycle is stated, that certificate issuance and Gateway address assignment complete without network, and that the `cryolite` Chainsaw suite is the oracle.
- `k3s-manifest-purity-regulator` (stratum: `behavioral`): the KVM-free properties of the rendered `cryolite` tree and its artifacts — purity, preload coverage, closure provenance, node-identity freedom, pinned and verified Flux sources, the rendered Flux install, OCI-layout digest equality at the push boundary, and import-from-derivation-free rendering with golden drift regulation.
- `k3s-integration-ci-execution` (stratum: `interface`): the properties at the CI and developer-host boundary — that VM leaves are independent `checks.<system>.vm-*` derivations requiring `kvm nixos-test`, discovered by `just test-integration`, built in CI only on a probed KVM runner, inert on the buildbot worker without failing anything else, and that registry publishing is an `apps` effect and never a check. Trust boundary: the runner's KVM availability and the registry's digest report are observed, not guaranteed; the effect's exit status is the only claim.

### Modified Capabilities
- `world-assumptions` (stratum: `world`): assumptions are added — the Nix build sandbox has no network; GitHub-hosted runner nested virtualization is unsupported by the vendor; a Gateway becomes Programmed only once an address is assigned; an OCI manifest digest is a function of its bytes. (The cluster-api-k3s cloud-provider default and the ClusterMesh preconditions move to the sibling change.)

## Impact

Implementation, in later changes, touches only the `[add]` and `[+opt]` paths of the target module layout in design.md §"Target module layout": new leaves `modules/checks/vm-k3s-{substrate,snapshotter,platform}.nix`; `modules/kubernetes/{artifacts,oci-lib,purity,provenance,identity}.nix` and `modules/kubernetes/flux/`; `modules/nixos/k3s-server/snapshotter.nix` and `modules/nixos/k3s-flux.nix`; `modules/apps/k8s/{oci-push,cosign-sign}`; `kubernetes/modules/flux/`, `kubernetes/clusters/cryolite/`, `kubernetes/tests/cryolite/`, and `secrets/clusters/cryolite/`; test-only age and cosign fixtures outside `modules/`; and the additive `[+opt]` edits — `modules/kubernetes.nix` gains `cryolite` in `evalCluster`, `modules/nixos/k3s-server/default.nix` gains `snapshotter` and loses the dead containerd block, `modules/devshells/kubernetes.nix` gains flux, cosign, and crane.
A probe job and then a `vm` job are added to `.github/workflows/test-cluster.yaml` beside the untouched `integration` job.
Nothing under `kubernetes/clusters/local*`, `kubernetes/nixidy/`, `kubernetes/tests/local-k3d/`, `modules/apps/cluster/`, `modules/nixidy.nix`, or the flake inputs is edited by this change or by S0–S2.
No stage of this change spends money.
