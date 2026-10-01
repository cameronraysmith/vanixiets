---
title: Cryolite cluster programme charter
---

# Cryolite cluster programme charter

Version 1, 2026-09-04.
This document is the orientation for the programme that builds `cryolite`, the fleet's first Cluster-API-managed, Flux-reconciled, Nix-built k3s cluster.
It cites; the ADRs decide and the OpenSpec changes specify.
A reader who needs a decision's reasoning follows the code (ADR-009 D9.19, parent design D6) to the record that holds it.

Sources of record:
- ADR-007 `decisions/ADR-007-nixos-vm-tests-for-k3s.md`: VM tests for the k3s substrate, the `cryolite` platform leaf, stage plan, frozen prototypes.
- ADR-008 `decisions/ADR-008-reconciler-and-artifact-transport.md`: Flux, OCI artifact, image producers, SOPS, cosign, the in-guest registry.
- ADR-009 `decisions/ADR-009-capi-node-management-and-networking.md`: Cluster API, cluster-api-k3s, CAPH, the `platform` sum, image path, networking, spend gate.
- ADR-010 `decisions/ADR-010-identity-tiers-and-non-circular-bootstrap.md`: identity tiers, bootstrap levels, machine inventory, etcd-S3.
- `openspec/changes/k3s-nixos-vm-tests/` (the parent change): stages S0–S2.
- `openspec/changes/capi-hetzner-cluster/` (the sibling change, depends on the parent): stages S3, S4, S4b, and deferred S5.

Codes used here: `A<n>` are numbered world assumptions from the two changes' `world-assumptions` delta specs; `W<n>` are world assumptions this charter names that no delta spec numbers yet; `R<n>` are programme requirements; `SP<n>` are specification properties; `S0`–`S5` are stages; `D<adr>.<n>` are ADR decisions; `Q<n>` in the last section are this charter's open questions.
The parent and sibling changes number their own design decisions and questions; a reference to one of those is always qualified with the change or the word "design".

## 1. Intent

Nix builds the cluster: the node operating system, the k3s binary and its embedded containerd, the nix snapshotter, the Flux controllers, the rendered Kubernetes configuration, and the workload images are all outputs of one evaluation, so the Kubernetes configuration and the package set it runs on share one hash and change together or not at all.
The first target is `cryolite`, a two-node NixOS k3s cluster on Hetzner Cloud whose nodes are created and replaced by Cluster API (cluster-api-k3s for bootstrap and control plane, CAPH for infrastructure) from a per-role snapshot of that closure, and whose contents Flux reconciles from a digest-pinned, cosign-signed OCI artifact that the same evaluation produced.
The cluster module's core is provider-neutral: everything that is not a cloud's own object is rendered from one easykubenix module, the cloud is a typed `platform` variant, and the same node image derivation is transported to each cloud by a provider-specific effect.
Every property the programme claims is regulated by a Nix check or a recorded effect transcript; checks that need a virtual machine run under KVM, checks that do not run anywhere Nix does, and nothing bills a cloud without a per-revision release from the operator.

## 2. WRSPM strata

The programme is described in the reference model of Gunter, Gunter, Jackson, and Zave: indicative world assumptions W, optative requirements R, a specification S stated in phenomena the machine shares with the world, and the program P and machine M that realize S.
The repository contract is W ∧ S ⇒ R; a requirement that lacks a discharging W or S is marked undischarged rather than assumed.

### 2.1 W — world assumptions (indicative)

Numbered assumptions live in `openspec/changes/k3s-nixos-vm-tests/specs/world-assumptions/spec.md` (A13–A16) and `openspec/changes/capi-hetzner-cluster/specs/world-assumptions/spec.md` (A17–A21); the numbering assumes the two unmerged changes adding A9–A12 land first and is renumbered at sync otherwise.

| Code | Assumption | Status |
|---|---|---|
| A13 | The Nix build sandbox has no network, so every remote artifact a check needs is a build input | verified (Nix semantics) |
| A14 | GitHub-hosted runner nested virtualization is unsupported by the vendor | verified (vendor documentation) |
| A15 | A Gateway becomes `Programmed` only once an address is assigned to it | verified (Gateway API) |
| A16 | An OCI manifest digest is a function of the manifest bytes alone | verified (OCI distribution spec) |
| A17 | cluster-api-k3s defaults the cloud provider to `external` | verified (read in source) |
| A18 | Cilium ClusterMesh requires non-overlapping PodCIDRs and a covering native-routing CIDR | verified (Cilium documentation) |
| A19 | Hetzner Cloud offers no image-upload API | believed (CAPH documentation; not confirmed against the hcloud API reference) |
| A20 | cloud-init's NoCloud datasource reads user-data from a labelled seed | verified (cloud-init documentation) |
| A21 | `clusterctl move` carries the Secrets labelled with the cluster name | verified (read in cluster-api source) |

World assumptions this charter relies on that no delta spec numbers yet; Q8 recommends numbering them at sync:

| Code | Assumption | Status | Where it matters |
|---|---|---|---|
| W1 | CAPH `HCloudMachineTemplate.Spec` is immutable, so a rollout or rollback references the previous template until every `Machine` is replaced | immutability verified (`pkg/webhook/v1beta2/hcloudmachinetemplate_webhook.go`); the rollout consequence inferred (ADR-009 R9.k) | snapshot retention, S4.2 |
| W2 | cluster-api-k3s is absent from clusterctl's built-in provider registry and needs a `clusterctl.yaml` override | read in source (ADR-009 R9.b), not yet exercised | S3.1, S3.5 |
| W3 | cluster-api-k3s and CAPH work together | inferred; no reference deployment found (ADR-009 R9.c) | S3.5, S4.3 |
| W4 | A NixOS image boots through a CAPI NoCloud seed into cluster-api-k3s `airGapped` mode | unverified (ADR-009 R9.d) | S3.7 |
| W5 | The `hcloud` Terraform provider exposes no Object Storage bucket resource | believed (ADR-009 R9.j) | S4.0 |
| W6 | Clan's `wireguard` service accepts a peer that is not a Clan machine | unverified (ADR-009 R9.g) | S4b.1 |
| W7 | A KVM-capable host exists on which the VM leaves can run and gate a merge | true of the developer host today; no CI runner is provisioned | S1–S3 gates |
| W8 | The pinned nixpkgs `services.dockerRegistry` module, backed by `pkgs.distribution` 3.1.1, serves an OCI layout pushed by `crane` | module and package verified in the pinned revision; the serve path inferred | S2.5 |

### 2.2 R — requirements (optative)

Each requirement names the assumptions and specification properties that discharge it; "undischarged" means no S property in either change discharges it in this revision.

| Code | Requirement | Discharged by |
|---|---|---|
| R1 | Kubernetes configuration, node closure, and workload images share one hash chain from `kubernetes/clusters/cryolite` to the CAPI `imageName` | A16; SP2, SP5, SP10 |
| R2 | Every regulator is a sandboxed derivation with no network and no runtime Nix evaluation in the cluster | A13; SP1, SP2, SP24 |
| R3 | The production k3s module is exercised unmodified by every VM leaf | SP6, SP7, SP8 |
| R4 | The VM envelope matches the production envelope for `cryolite` (Cilium replaces kube-proxy; F1 is closed for this cluster) | A15; SP8 |
| R5 | Node identity is disposable and nothing in the repository, inventory, or management cluster names a node | A21; SP3, SP10, SP17 |
| R6 | No T0 private material is in any image closure; T0 reaches a node only through `contentFrom.secret` | A20; SP4, SP10, SP13 |
| R7 | The L0 root set (repository, Clan vars, one Hetzner token, stibnite) suffices to reach a running cluster; no seed host exists | W2, W3; SP14, SP17 |
| R8 | No effect bills Hetzner without a per-revision release in the operator's shell | SP15, SP16 |
| R9 | The cloud-invariant core renders identically for every implemented `platform` variant modulo platform-owned fields | SP11 today; SP19 deferred to S5 — partially undischarged until S5 |
| R10 | Flux reconciles only a digest-pinned, cosign-verified artifact whose digest equals the sandbox-built digest | A16; SP5, SP8 |
| R11 | Every cloud-init `platform` variant renders a cloud-controller manager | A17; SP12 |
| R12 | `local` and `local-k3d` are unchanged by this programme | SP21 |
| R13 | VM leaves gate merges only from a KVM-probed runner and leave buildbot inert | A14, W7; SP22 — W7 is asserted for the developer host only, so the CI half is undischarged until a KVM runner exists (Q9) |
| R14 | The cluster is recoverable from etcd-S3 snapshots plus L0 | W5; SP17 configures the snapshots; the restore path has no regulator in this revision — undischarged until a rehearsal is authorized |
| R15 | First-deploy administration needs no overlay; a later overlay is one gateway per cluster controlled by the primary VPS | W6; SP17, SP18 |
| R16 | Every regulator is non-vacuous: a named mutation makes it fail | SP23 |
| R17 | Every `cryolite` render and KVM-free regulator evaluates with import-from-derivation disabled on every flake system | A13; SP24 |

### 2.3 S — specification properties (shared phenomena)

Each property is a check, golden, or effect transcript whose inputs and outputs are phenomena both the machine and the world observe: store paths, rendered manifests, VM console assertions, API responses, exit codes.

| Code | Property | Name | Stage | Change |
|---|---|---|---|---|
| SP1 | Rendered tree has no `flakeRef`, `nixExpr`, `:latest`, or untagged image; images ⊆ preload set | `checks.k8s-purity-cryolite` | S0 | parent |
| SP2 | Closure provenance report is a pure derivation listing every image digest and its producing derivation | `checks.k8s-provenance-cryolite` | S0 | parent |
| SP3 | No CAPI CR, Flux manifest, Clan inventory entry, or Secret names a node or node key | `checks.k8s-node-identity-free-cryolite` | S0, extended S3 | parent, sibling |
| SP4 | Node image closures contain no sops file, T0 fingerprint, or fixture private key | `checks.k8s-closure-secret-free-cryolite` | S2 | parent |
| SP5 | Registry digest after push equals the layout digest built in the sandbox | `apps.k8s.oci-push` (effect transcript), `k8s-oci-cryolite` digest | S0 | parent |
| SP6 | k3s substrate boots CNI-free with `KubeletNotReady`, NRI socket present, firewall as declared | `vm-k3s-substrate` | S1 | parent |
| SP7 | A pod's rootfs is store paths through the nix snapshotter | `vm-k3s-snapshotter` | S1 | parent |
| SP8 | Two guests run the `cryolite` core: Cilium kube-proxy replacement, Flux from an in-guest registry at the recorded digest, Chainsaw suite green | `vm-k3s-platform` | S2 | parent |
| SP9 | Exactly three providers, digest-pinned, store-path `url`s in `clusterctl.yaml` | `checks.k8s-capi-providers` | S3 | sibling |
| SP10 | The Hetzner render equals per-object goldens; `imageName` equals the image label; T0 only through `contentFrom.secret` | `checks.k8s-capi-render-cryolite` | S3 | sibling |
| SP11 | `platform` is total over `hetzner \| gcp \| aws \| kubevirt`; `aws` and `kubevirt` throw by name; unknown names are type errors | `checks.k8s-capi-platform-sum` | S3 | sibling |
| SP12 | Every cloud-init variant renders a CCM | `checks.k8s-capi-ccm-present` | S3 | sibling |
| SP13 | The production image boots from a NoCloud seed, `k3s.service` starts from `configPath`, host key fresh per boot and signed by the CA, CA private key absent | `vm-k3s-capi-bootstrap` | S3 | sibling |
| SP14 | k3d handler reaches three providers `Ready` and the `Cluster` accepted from L0 alone | `apps.k8s.mgmt-k3d` (effect transcript) | S3, S4 | sibling |
| SP15 | Every Hetzner-calling effect refuses with the gate unset or wrong and plans exactly the expected actions with it set | `checks.k8s-spend-gate-cryolite` | S3 | sibling |
| SP16 | Snapshot publication is idempotent on label, deletes M4, retains two per role | `apps.k8s.hetzner-snapshot-publish` (effect transcript) | S4 | sibling |
| SP17 | The S4 runbook touches only M1–M6 and the load balancer; CA fingerprint equals Clan vars; pivot carries T0 Secrets; a flake bump yields a new node identity | S4 runbook transcript, `hetzner-cluster-deployment` review rules | S4 | sibling |
| SP18 | The overlay carries `kubectl` and `ssh`; scaling the gateway to zero fails the overlay path only | S4b transcript, `k8s-admin-overlay` | S4b | sibling |
| SP19 | `hetzner` and `gcp` renders are byte-identical after masking platform-owned fields | `checks.k8s-capi-core-equivalence-cryolite` | S5 (deferred) | sibling |
| SP20 | PodCIDRs disjoint and native-routing CIDR covering at evaluation | `checks.k8s-clustermesh-preconditions` | S5 (deferred) | sibling |
| SP21 | `git diff --stat` over the frozen paths, `.github/workflows`, and `flake.lock` is empty | review rule (parent IV.6, sibling IV.3) | every stage | both |
| SP22 | VM leaves are Linux-only, `kvm`-requiring, discovered by prefix, inert on buildbot | `k3s-integration-ci-execution` | S1 | parent |
| SP23 | Each regulator's PR body records a mutation that made it fail and the revert | review rule in every stage's tasks | every stage | both |
| SP24 | Renders and `k8s-*` leaves evaluate with `allow-import-from-derivation = false`; goldens equal the sandbox re-render | `checks.k8s-render-golden-cryolite` + IFD-off evaluation (CI job outcome) | S0, extended S3 | parent, sibling |

### 2.4 P and M

P, the program, is empty in this revision: both changes are planning-only and no implementation task is checked.
M, the machine, is fixed: the Nix evaluator and build sandbox for KVM-free leaves, a KVM-capable Linux host for `vm-*` leaves, stibnite for effects, and the Hetzner Cloud API and GHCR as the effects' remote ends.
The `local-k3d` prototype and its ArgoCD stack are outside both P and M for this programme.

## 3. Designations

| Term | Designation |
|---|---|
| `cryolite` | The sibling cluster: Na₃AlF₆, the ice-stone of Ivittuut, Greenland, mined as flux for aluminium smelting; continues stibnite, magnetite, cinnabar (ADR-007 D7.20) |
| `cryolite-server`, `cryolite-agent` | The two per-role NixOS machine configurations, image-only, role fixed at build |
| T0 | Cluster identity: stable, generated once by Clan vars, sops-encrypted; join token, k3s CA set, Flux age key, cosign key, SSH CA, etcd-S3 credentials, later the overlay gateway key (ADR-010 D10.1) |
| T1 | Node identity: disposable, never referenced outside the cluster; `Machine` name, host keys, Cilium WireGuard key, `CiliumNode` |
| T2 | Cluster endpoints: stable; the CAPH load balancer in front of the API server, later the overlay gateway |
| L0 | Root set: repository, Clan vars, one Hetzner API token, stibnite (ADR-010 D10.2) |
| L1 | Former seed host; removed, no standing extra machine (ADR-010 D10.3) |
| L2 | Throwaway management cluster: k3d on stibnite, deleted after pivot |
| L3 | The workload cluster, self-hosting CAPI after `clusterctl move` |
| M1–M6 | The machines of one end-to-end deployment; §4 |
| Handler A | Management cluster as the k3s closure in a NixOS QEMU VM (Darwin/HVF, Linux KVM); deferred (ADR-009 D9.17) |
| Handler B | Management cluster as k3d on stibnite's Colima Docker; the effect `apps.k8s.mgmt-k3d`; first |
| Handler contract | Kubeconfig on the operator host, three providers `Ready`, identical CRs and T0 Secrets applied, `clusterctl move` succeeds |
| `platform` sum | Typed variant `hetzner \| gcp \| aws \| kubevirt` owning `*Cluster`, `*MachineTemplate`, image reference, CCM, optional CSI; `aws` and `kubevirt` throw (ADR-009 D9.10, D9.20) |
| Cloud-invariant core | `Cluster`, `KThreesControlPlane`, `KThreesConfigTemplate`, `MachineDeployment`, `MachineHealthCheck`, Flux, Cilium, rendered without reading `platform` |
| `airGapped` mode | cluster-api-k3s bootstrap that skips the k3s download; the NixOS image supplies the binary and a Nix-written `/opt/install.sh` shim starts `k3s.service` (ADR-009 D9.2, D9.3) |
| Bootstrap seam | `k3s-server.bootstrap = "clan-vars" \| "cloud-init"`; the only point where fleet hosts and CAPI nodes differ (ADR-009 D9.8) |
| NoCloud | cloud-init datasource reading user-data from a labelled seed; the VM leaf's stand-in for CAPH's bootstrap-data delivery |
| `contentFrom.secret` | `KThreesConfig.spec.files[].contentFrom.secret{name,key}`; the only T0 delivery path (ADR-010 D10.4) |
| OCI artifact | The rendered `cryolite` tree as an OCI image layout, digest known in-sandbox, pushed to GHCR, consumed by Flux at that digest (ADR-008 D8.4–D8.7) |
| OCI layout | `oci-layout`, `index.json`, `blobs/sha256/`, `$out/digest`; output of `k8s-oci-cryolite` |
| Preload closure | The set of images `services.k3s.images` carries into the node closure; rendered image references must be a subset of it |
| Image path O1 | Per-role snapshot from one pure image derivation on the fleet disko layout; transport is provider-specific (ADR-009 D9.16, D9.18) |
| O2 | Rejected alternative: stock image plus reinstall from cloud-init after first boot |
| Snapshot label | `caph-image-name=cryolite-<role>-<closure-hash-prefix>`; the only thing a CR sees of the image |
| Envelope drift F1 | The finding that `local-k3d` runs kube-proxy and ServiceLB while production intends Cilium's replacement; closed for `cryolite`, left as-is for `local-k3d` |
| CAPI | Cluster API, the node-management contract |
| CAPH | cluster-api-provider-hetzner, the infrastructure provider |
| cluster-api-k3s | The bootstrap and control-plane provider for k3s |
| Flux | The reconciler of `cryolite`: source, kustomize, notification controllers only, installed from `services.k3s.manifests` |
| SOPS | Flux's decryption of sops-encrypted manifests with the per-cluster T0 age key (ADR-008 D8.9) |
| Snapshotter | nix-snapshotter through k3s's embedded containerd `--snapshotter nix`; pod rootfs is store paths |
| ClusterMesh | Cilium's cross-cluster service mesh; the multi-cloud shape, never stretched etcd (ADR-009 D9.13) |
| Administrative overlay | Clan `wireguard` instance controlled by the primary VPS with one gateway per cluster; S4b (ADR-009 D9.15) |
| Effect | An `apps.k8s.*` program with side effects, run by the operator, evidenced by transcript; never a check |
| Regulator | A check, golden, or review rule that fails when a claimed property does not hold |
| KVM-free evaluation | A regulator that needs only the Nix evaluator and sandbox; runs on buildbot |
| KVM runtime | A regulator that boots a NixOS VM; requires the `kvm` system feature |
| Golden | A committed rendering compared per object; a diff names the object |
| Mutation evidence | A recorded change that makes a regulator fail, with the failure output and the revert |
| Non-vacuity evidence | Proof that a regulator can fail: the mutation evidence or a scenario that is itself the mutation |
| Coverage bin | The CCV placement of a regulator: a T1/T2/T3 check leaf, an effect, or an interface rule (review, recipe outcome, CI job outcome) |
| Spend gate | `VANIXIETS_HETZNER_SPEND_APPROVED=<flake rev>` read by every Hetzner-calling effect; §7 (ADR-009 D9.19) |
| Frozen prototype | `kubernetes/clusters/local`, `local-k3d`, `kubernetes/nixidy`, `kubernetes/tests/local-k3d`, `modules/apps/cluster`, the k3d workflow; §9 |

## 4. Machines and bootstrap levels

Machines in one end-to-end deployment (ADR-010 D10.5):

| Machine | What | Role | Lifetime |
|---|---|---|---|
| M1 | stibnite, `aarch64-darwin` | Operator: flake evaluation, Clan vars T0 generation, management-cluster host, snapshot upload, `clusterctl init/apply/move`; retains kubectl, flux, ssh | bootstrap and administration |
| M2 | Linux builder (existing magnetite builder or nix-darwin `linux-builder`) | Builds the `x86_64-linux` node image | bootstrap only |
| M3 | Management cluster, a k3d process on stibnite | Runs CAPI, CAPH, cluster-api-k3s until pivot | bootstrap only; deleted after `clusterctl move` |
| M4 | Hetzner throwaway server in rescue mode | Image written with `dd`, snapshotted with the label, deleted | bootstrap only; bills Hetzner |
| M5 | Hetzner k3s server node | Created by CAPH from the server snapshot; receives T0 via `contentFrom.secret`; hosts CAPI after pivot | cluster; bills Hetzner |
| M6 | Hetzner k3s agent node | Created by CAPH from the agent snapshot; receives T0 via `contentFrom.secret` | cluster; bills Hetzner |
| — | CAPH-created load balancer | kube-apiserver endpoint (T2) | not a machine; bills Hetzner |

Terranix, nixos-anywhere, and `clan machines install` never touch M5 or M6; Terranix provisions fleet hosts and the etcd-S3 bucket only (ADR-010 D10.3, D10.8).

Bootstrap levels (ADR-010 D10.2):

| Level | Content | Regulated by |
|---|---|---|
| L0 | Repository, Clan vars under `secrets/clusters/cryolite/`, one Hetzner API token, stibnite; nothing else may be required | SP14, SP17 (IV.4 of the sibling change) |
| L1 | Removed; no seed host and no standing extra Hetzner machine | SP17 (M1–M6 are the complete set) |
| L2 | k3d on stibnite; `clusterctl init` with the override; T0 Secrets and CRs applied | SP9, SP14 |
| L3 | `cryolite` self-hosts CAPI after `clusterctl move`; Flux reconciles from the digest in the closure; L2 deleted | SP17 (pivot), A21 |
| DR | etcd-S3 snapshots plus L0: rebuild L2, restore on a fresh M5, re-pivot | undischarged (R14); rehearsal separately authorized |

## 5. Acceptance criteria and regulators

| AC | Criterion | Regulator | Kind | Stage | Evidence required |
|---|---|---|---|---|---|
| AC1 | Rendered tree is pure and its images are preloaded | `checks.k8s-purity-cryolite` | KVM-free eval | S0 | reintroduce `:latest` and an unpreloaded image; both fail naming the reference |
| AC2 | Provenance report is reproducible | `checks.k8s-provenance-cryolite` | KVM-free eval | S0 | `nix build --rebuild` byte-identical; a changed image digest changes the report |
| AC3 | Nothing names a node | `checks.k8s-node-identity-free-cryolite` | KVM-free eval | S0, S3 | add `nodeName: cryolite-server-0`; fails naming the file |
| AC4 | Published digest equals built digest | `apps.k8s.oci-push` | effect transcript | S0 | push a modified layout under the same tag; exit non-zero |
| AC5 | Substrate boots as declared without a CNI | `vm-k3s-substrate` | KVM runtime | S1 | `ip_forward = 0`, firewall without 6443, `snapshotter = overlayfs`; each fails |
| AC6 | Pod rootfs is store paths | `vm-k3s-snapshotter` | KVM runtime | S1 | reference the image by registry tag instead of `nix:0`; fails |
| AC7 | Two-node core runs with Cilium kube-proxy replacement and Flux at the recorded digest | `vm-k3s-platform` | KVM runtime | S2 | wrong digest, foreign cosign key, extra Gateway listener; each fails |
| AC8 | Image closures carry no T0 private material | `checks.k8s-closure-secret-free-cryolite` | KVM-free eval | S2 | add a sops file to the image; fails naming the path |
| AC9 | Provider install is pinned and reproducible | `checks.k8s-capi-providers` | KVM-free eval | S3 | tag in place of a digest; missing `k3s` entry; each fails |
| AC10 | CAPI render matches goldens and T0 flows only through `contentFrom.secret` | `checks.k8s-capi-render-cryolite` | golden | S3 | `replicas: 2`; inline token; each fails naming the object |
| AC11 | `platform` sum is total and throws by name | `checks.k8s-capi-platform-sum` | KVM-free eval | S3 | the scenarios are the mutation (`azure`, `kubevirt`, `aws`) |
| AC12 | Every cloud-init variant has a CCM | `checks.k8s-capi-ccm-present` | KVM-free eval | S3 | remove the Hetzner CCM; fails |
| AC13 | Production image boots from a NoCloud seed into k3s with fresh, CA-signed host keys | `vm-k3s-capi-bootstrap` | KVM runtime | S3 | drop `runcmd`; inline token; foreign CA; each fails |
| AC14 | k3d handler reaches the contract from L0 | `apps.k8s.mgmt-k3d` | effect transcript | S3 | transcript shows three providers `Ready`, `InfrastructureReady=False` awaiting credentials, no spend |
| AC15 | No Hetzner call without the released revision | `checks.k8s-spend-gate-cryolite` | KVM-free eval | S3 | an effect edited to skip the gate read; fails naming the effect |
| AC16 | Snapshot publish is idempotent and leaves no M4 | `apps.k8s.hetzner-snapshot-publish` | effect transcript | S4 | second run creates no server; `hcloud server list` empty of M4 |
| AC17 | Two nodes `Ready` with the pre-provisioned CA and no inline T0 | S4 runbook | effect transcript | S4 | CA fingerprint equals Clan vars; management cluster objects carry no T0 value |
| AC18 | Pivot carries T0 Secrets; M3 deleted | S4 runbook | effect transcript | S4 | `clusterctl describe` against `cryolite` lists the Secrets; `k3d cluster list` empty |
| AC19 | A flake bump replaces a node with a new identity | S4 runbook | effect transcript | S4 | new `Machine` name, host key, `wg-pub-key`; old objects gone |
| AC20 | Overlay carries administrative traffic and fails alone when the gateway is gone | S4b transcript | effect transcript | S4b | gateway scaled to zero: overlay path fails, public path works |
| AC21 | Core renders identically across `hetzner` and `gcp` | `checks.k8s-capi-core-equivalence-cryolite` | golden | S5 (deferred) | a core object reads `platform.hetzner.region`; fails naming the leak |
| AC22 | ClusterMesh preconditions hold at evaluation | `checks.k8s-clustermesh-preconditions` | KVM-free eval | S5 (deferred) | overlapping PodCIDRs; fails |
| AC23 | Frozen paths, workflows, and flake inputs untouched | `git diff --stat` review rule | review | every stage | any line under those paths fails the review |
| AC24 | Renders are import-from-derivation-free and goldens are current | `checks.k8s-render-golden-cryolite`; IFD-off `nix eval` | KVM-free eval + CI job outcome | S0, S3 | reintroduce `chart2json` at eval: eval fails naming the derivation; bump `cilium-src` without regenerating: fails naming the object |

## 6. Stage plan

Common gates for every stage: a human reads the plan before the PR is opened (the tasks of the stage are agreed in the OpenSpec change), and a human reviews the PR body's mutation evidence before merge.
Every VM leaf is verified on the KVM developer host until a KVM runner exists (Q9); buildbot regulates the KVM-free leaves only.
Estimates are in agent sessions of the kind that produced this document, excluding external waits.

| Stage | Deliverables | Regulators | KVM | Gates | Estimate |
|---|---|---|---|---|---|
| S0 | `k3s-server.snapshotter` option; `kubernetes/clusters/cryolite`; `k8s-manifests-cryolite`, `k8s-oci-cryolite`; Flux install and root modules; `secrets/clusters/cryolite/` generators; `oci-push`, `cosign-sign` effects | AC1–AC4, AC24, `k3s-server-eval` | none | plan and merge review | 1 session |
| S1 | `vm-k3s-substrate`, `vm-k3s-snapshotter`; dead containerd block deleted; buildbot inertness confirmed | AC5, AC6, SP22 | yes | plan and merge review; KVM host available | 1 session |
| S2 | `cryolite-server`/`agent` machines; `k3s-flux.nix`; preload set; test fixtures; `vm-k3s-platform`; Chainsaw suite in `kubernetes/tests/cryolite` | AC7, AC8 | yes | plan and merge review; S1 green | 1–2 sessions (W8 and the 1.5–2.5 GiB preload bound are the unknowns) |
| S3 | `capi/providers.nix`; `kubernetes/modules/capi`, `platform/{hetzner,aws,kubevirt}`; goldens; `capi-bootstrap.nix` seam; `vm-k3s-capi-bootstrap`; `apps.k8s.mgmt-k3d`; spend-gate function and check | AC9–AC15, AC24 | yes for the bootstrap leaf | plan and merge review; S2 green; no Hetzner call (the handler stops at `InfrastructureReady=False`) | 1–2 sessions (W3, W4 are the unknowns) |
| S3→S4 | First paid action | — | — | operator sets `VANIXIETS_HETZNER_SPEND_APPROVED` to the S4 revision; the etcd-S3 bucket is declared in fleet Terranix | — |
| S4 | `hetzner/{image,snapshot}.nix`; `hetzner-snapshot-publish`; two-node deployment; pivot; node roll; etcd-S3 enabled; runbook pages | AC16–AC19, AC3, AC15 | no (effects) | per-revision gate on every effect; review of transcripts and fingerprints | 1 session plus external waits (image build on M2, snapshot minutes, CAPH reconciliation) |
| S4b | Clan `wireguard` instance on the primary VPS; gateway peer key in T0; gateway workload; stibnite peer | AC20, AC3 | no | plan and merge review; W6 settled at S4b.1 | 1 session |
| S5 | `platform/gcp.nix`; per-object goldens; core-equivalence and ClusterMesh regulators; dataplane allowlist derivation | AC21, AC22 | no | deferred; scheduling is a separate decision | 1 session |

The S0–S3 total is 4–6 sessions rather than the 3–5 the review proposed: S2 and S3 each carry a KVM leaf whose mutation evidence must be recorded, and S3 rests on two unverified assumptions (W3, W4) whose failure would cost a session each to route around.
S4 is bounded by Hetzner and CAPH, not by the agent; the single session covers the runbook and its evidence.

## 7. Billing surface

Hetzner spend is approved in principle and released one flake revision at a time (ADR-009 D9.19, ADR-007 D7.21).
Every action that bills the Hetzner Cloud project:

| Action | What bills | When | Task |
|---|---|---|---|
| Snapshot publication | M4 server-hours while the image is written (minutes, rounded up by Hetzner); snapshot storage per GB-month, two roles × two retained revisions | S4.2, and every later revision | S4.2 |
| Cluster creation | One load balancer and two servers (M5, M6) at hourly rates until deleted; public IPv4 addresses | S4.3 onward, continuous | S4.3 |
| etcd-S3 bucket | Object Storage: storage and requests; fleet-level, outlives the cluster | S4.0 onward, continuous | S4.0, S4.7 |
| Node cycle or rebuild | One more snapshot publication and one replacement server's hours overlapping the old one | every flake bump that rolls nodes | S4.6 and later operations |

The gate: every `apps.k8s.*` effect that calls the Hetzner Cloud API reads `VANIXIETS_HETZNER_SPEND_APPROVED` before its first API call, exits non-zero naming the expected flake revision if the variable is unset or differs from the revision it acts on, and records the released revision in its transcript otherwise.
Approval is a per-revision act in the operator's shell; nothing in a PR body, a merged planning change, or a green earlier stage releases a revision.
The regulator is `checks.k8s-spend-gate-cryolite` (AC15), and every S4 task in the sibling change's `tasks.md` carries `[bills Hetzner]` and a cost line.
Exact prices are recorded at S4.0 in the PR body and copied into this section at S4.8 (Q7).
S4b bills nothing new; S5 bills nothing.

## 8. Rejected alternatives

| Alternative | Rejected because |
|---|---|
| kubeadm | The nodes are k3s; cluster-api-k3s bootstraps k3s in `airGapped` mode without a second distribution (ADR-009 D9.1, D9.2) |
| nixkube runtime evaluation | Runtime `flakeRef`/`nixExpr` breaks hermeticity and the one-hash property; forbidden by the purity regulator (ADR-007 D7.1, ADR-008 D8.11) |
| ArgoCD for `cryolite` | Flux consumes a digest-pinned OCI artifact with SOPS and cosign natively; ArgoCD stays for `local-k3d` (ADR-008 D8.1, D8.15) |
| Seed host / L1 | A standing machine outside L0 that must itself be bootstrapped; L2 on stibnite is disposable (ADR-010 D10.3) |
| Node identity inheritance | A replaced node would carry a key the repository or inventory names; identity is made worthless instead (ADR-010 D10.6) |
| O2 reinstall in place | Hetzner-special, double boot per replacement, needs reachable cache credentials, pins `debian-12` rather than a closure (ADR-009 D9.16) |
| Yggdrasil or ZeroTier for nodes | Per-machine identity overlays are incompatible with T1 churn; Yggdrasil worst since key equals address (ADR-009 D9.15) |
| Crossplane or Anthos | Another control plane between the declaration and the cloud; CAPI already is that layer (ADR-009 D9.14) |
| Stretched etcd | Cross-cloud quorum latency and partition risk; ClusterMesh between per-cloud clusters instead (ADR-009 D9.13) |
| Handler A first | QEMU on Darwin/HVF adds a virtualization path to debug before any CAPI object exists; k3d reuses the existing Colima path (ADR-009 D9.17) |
| AWS first | No AWS Terranix exists in the fleet; GCP Terranix does, and a GCS etcd-S3 variant falls out of it (ADR-009 D9.20) |
| Just-in-time image build in the transport | Puts a Linux builder in the loop of every unattended node replacement (ADR-009 D9.18) |

## 9. Frozen-prototype policy

`kubernetes/clusters/local`, `kubernetes/clusters/local-k3d`, `kubernetes/nixidy`, `kubernetes/tests/local-k3d`, `modules/apps/cluster`, and the existing k3d workflow are frozen prototypes: no task in either change edits them, and AC23 fails any PR that does.
ArgoCD, nixidy, sops-secrets-operator, kube-proxy, and ServiceLB continue to run in `local-k3d` exactly as today.
Their migration or deletion, the global reversal of ADR-006, and the retirement of nixidy and sops-secrets-operator are a later, separately authorized feedback change; nothing here presumes its outcome (ADR-007 D7.15, ADR-008 D8.10).

## 10. Ledger policy

OpenSpec is the planning ledger: the two changes hold the requirements, design, and tasks, and this charter orients across them.
Linear (team CAM) is added when execution starts, one Linear issue per PR, every issue assigned to Cameron; no Linear issue exists for the planning stages.
The stack of planning PRs is #2955 → #2979 → #2983 and its successors, published through Mergify with the GitHub App as author; merging is Cameron's act.

## 11. Open questions

Each carries a recommended answer; silence adopts the recommendation except where a question spends money or is irreversible, which none of these does by itself.

- Q1 Which Terraform provider declares the Hetzner Object Storage bucket (W5)?
  Recommendation: attempt the `hcloud` provider at S4.0; if it exposes no bucket resource, use the `minio` provider against Hetzner's S3 endpoint (simpler credential semantics than `aws` for a non-AWS endpoint), with the access key created once in the console and entered into T0 through Clan vars; record which applied in ADR-009 R9.j.
- Q2 GCP image publication details for S5 (bucket, image format, `images.insert` options, UEFI and guest-OS features)?
  Recommendation: defer to the S5 planning revision; use a bucket from the existing GCP Terranix and the raw-disk tarball format, and mark every detail unverified until then.
- Q3 Does Clan's `wireguard` service accept a peer that is not a Clan machine (W6)?
  Recommendation: read `clanServices/wireguard` at S4b.1; if a machine entry is required, register the gateway as a Clan machine with no deploy target and name it as the one non-node exception.
- Q4 Which registry does the real cluster pull the Flux artifact and images from?
  Recommendation: GHCR, as ADR-008 D8.4 states, with the artifact package public since it carries only rendered manifests whose secrets are SOPS-encrypted; if Cameron prefers private, a pull secret enters T0 and `KThreesConfig` delivers it, decided in the S3 PR.
- Q5 When are old snapshots pruned?
  Recommendation: inside `hetzner-snapshot-publish` after a successful publish, pruning only labels for the same role that no `HCloudMachineTemplate` in the management cluster references and that are older than the newest two.
- Q6 cluster-api-k3s and CAPH have not been observed together (W3).
  Recommendation: no action before S3.5, whose transcript (three providers `Ready`, `Cluster` accepted with `InfrastructureReady=False`) is the first evidence, and S4.3 the second; if S3.5 fails, the fallback is a `KThreesConfig` fixture run against CAPH's docker provider before any spend.
- Q7 Exact cost values for the billing surface?
  Recommendation: none now, since list prices move; record Hetzner list prices for the chosen server type, load balancer type, snapshot GB-month, and Object Storage GB-month at S4.0 in the PR body and copy them into §7 at S4.8.
- Q8 W1–W8 are world assumptions without A-numbers.
  Recommendation: number W1–W6 and W8 as A22–A28 in the sibling change's `world-assumptions` delta spec at sync, in this order; W7 becomes a requirement on infrastructure rather than an assumption (Q9).
- Q9 Which KVM-capable host gates the VM leaves in CI (R13)?
  Recommendation: the developer host verifies S1–S3 by hand and records the run in each PR body; provisioning a KVM runner (a Linux fleet host or a self-hosted runner) is a separate change, and until it exists R13's CI half stays undischarged and is stated so in every VM-leaf PR.
- Q10 When is disaster recovery rehearsed (R14)?
  Recommendation: after S4.7 and before S4b, as a separately approved effect that restores a snapshot onto a fresh M5 under the spend gate; until then R14 is undischarged and the charter says so.
- Q11 Does the sibling change's `capi-cluster-rendering` delta need an A-numbered assumption that the NixOS image boots from a NoCloud seed into `airGapped` mode (W4)?
  Recommendation: yes, at sync (Q8), since SP13 rests on it and its failure would send S3 to an alternative bootstrap-data path.
- Q12 The S0–S3 estimate.
  Recommendation: 4–6 sessions as §6 argues; the review's 3–5 stands if W3 and W4 hold on first contact.
