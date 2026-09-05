# ADR-009: Cluster API node management and cluster networking

## Status

Proposed (2026-09-04).
Design only; no flake input, production module, workflow, Terranix, or cloud change lands with this record.
Implemented by stages S3, S4, and S5 of `openspec/changes/k3s-nixos-vm-tests/`; S4 spends money and needs explicit approval.

## Context

ADR-007 regulates the k3s node OS and ADR-008 the reconciler and artifacts.
Neither says how nodes come to exist, how they join, or how they talk to each other and to their operators.
The fleet's existing answer is Terranix for hosts and ZeroTier for the overlay; neither is a node lifecycle manager and neither knows what a `MachineDeployment` is.
The proximal target is a two-node k3s cluster on Hetzner whose nodes are Cluster API objects, and whose declaration is cloud-invariant except for a typed platform submodule, so that a second cloud is a new submodule and not a fork.

Paths under `~/ghq/` refer to the reference trees listed in ADR-007's appendix at the revisions recorded there.
Claims read in source are stated as facts; claims that were not executed are marked as inferred and listed in the open-risk table with the regulator that would discharge them.

## Findings

### F9.1: cluster-api-k3s has an air-gapped bootstrap path that expects the k3s binary to be present

`KThreesConfigSpec.AirGapped` skips the `get.k3s.io` download; the operator is expected to place the k3s binary and the install script at `AirGappedInstallScriptPath`, default `/opt/install.sh` (`~/ghq/github.com/k3s-io/cluster-api-k3s/bootstrap/api/v1beta2/kthreesconfig_types.go:159-170`; `pkg/cloudinit/cloudinit.go:73`).
The generated cloud-init `runcmd` is `INSTALL_K3S_SKIP_DOWNLOAD=true INSTALL_K3S_EXEC='server' sh /opt/install.sh` for the control plane and the `agent` form for workers (`pkg/cloudinit/controlplane_init.go:30`, `worker_join.go:26`), preceded by `write_files` that include `/etc/rancher/k3s/config.yaml` (`pkg/k3s/config.go:10`) and any `KThreesConfig.spec.files` (`kthreesconfig_types.go:30`).
The webhook defaults `disableCloudController` to `true` and `cloudProviderName` to `external` (`kthreesconfig_webhook.go:67-72`), and `tls-san` always includes the control-plane endpoint (`pkg/k3s/config.go:49`) with `spec.serverConfig.tlsSan` appended (`kthreesconfig_types.go:72-74`).

### F9.2: cluster-api-k3s is not in clusterctl's built-in registry

clusterctl's provider table has `aws`, `gcp`, `hetzner`, `kubevirt`, and a `kubekey-k3s` bootstrap/control-plane pair (`~/ghq/github.com/kubernetes-sigs/cluster-api/cmd/clusterctl/client/config/providers_client.go:40`, `47`, `50`, `65`, `87`, `100`, `379`, `421`); the `k3s-io/cluster-api-k3s` providers are absent.
Its own samples install it through a `clusterctl.yaml` override that names local `bootstrap-components.yaml` and `control-plane-components.yaml` (`~/ghq/github.com/k3s-io/cluster-api-k3s/samples/clusterctl.yaml:1-7`).
For this design the override is a strength: the components are Nix-rendered manifests applied to the management cluster, and `clusterctl` never fetches anything.

### F9.3: CAPH boots from a named Hetzner snapshot

`HCloudMachineTemplate.spec.template.spec.imageName` selects the snapshot; `imageURL` is mutually exclusive (`~/ghq/github.com/syself/cluster-api-provider-hetzner/api/v1beta1/hcloudmachine_types.go:55-60`, `79`).
CAPH's documented image pipeline labels the snapshot `caph-image-name=<name>-<version>` and the template refers to that label (`docs/caph/02-topics/03-node-image.md:30`, `55`; `docs/caph/03-reference/03-hcloud-machine-template.md:19`).
hetzkube does exactly this with kubeadm: `imageName = "2505-x86"` in the rendered `HCloudMachineTemplate` (`~/ghq/github.com/Lillecarl/hetzkube/kubenix/modules/capi.nix:141`, `220`, `305`, `367`; `README.md:44-45`), and a `clusterctl move` from a bootstrap cluster (`README.md:110`).
Nobody in the reference set combines CAPH with cluster-api-k3s.

### F9.4: NixOS' QEMU VM can be built for a Darwin host

`virtualisation.host.pkgs` selects the host package set (`~/ghq/github.com/NixOS/nixpkgs/nixos/modules/virtualisation/qemu-vm.nix:728`), the run script checks KVM on Linux and HVF on Darwin (`299-318`), and QEMU is `qemu_kvm` when host and guest arches match and plain `qemu` otherwise (`741-751`).
A NixOS k3s node closure evaluated for `aarch64-linux` with `host.pkgs = aarch64-darwin` is therefore a runnable management cluster on stibnite; the same closure for `x86_64-linux` runs under KVM or TCG on Linux.
k3s is Linux-only, so there is no nix-darwin k3s module and the Darwin host contributes only the hypervisor.

### F9.5: NixOS can consume a NoCloud seed

Nixpkgs' own `cloud-init` test builds an ISO labelled `cidata` with `meta-data` and `user-data` and boots a NixOS guest against it (`~/ghq/github.com/NixOS/nixpkgs/nixos/tests/cloud-init.nix:14`, `28`, `52`, `68`, `78-79`).
The nixpkgs k3s module composes `ExecStart` from `role` at evaluation and accepts `--config <configPath>` at runtime (`nixos/modules/services/cluster/rancher/default.nix:485`, `932-940`).
Nothing in either tree runs cloud-init's `runcmd` into `k3s.service`; that shim (D9.3) is the untested piece.

### F9.6: the Clan `wireguard` service allocates a ULA per instance and distinguishes controllers from peers

Each instance gets a deterministic `/40` ULA; each controller a `/56`; each peer one 64-bit suffix used in every controller subnet; peers connect to all controllers (`~/ghq/git.clan.lol/clan/clan-core/clanServices/wireguard/default.nix:2-8`, `30-31`, `42-50`; `README.md:8-34`).
This is a hub-and-spoke admin network, not a dataplane.

### F9.7: Cilium's own encryption and ClusterMesh preconditions

Cilium WireGuard transparent encryption is node-to-node on UDP 51871 (`~/ghq/github.com/cilium/cilium/Documentation/security/network/encryption-wireguard.rst:13-14`, `34`).
ClusterMesh requires non-conflicting PodCIDRs across all clusters and nodes and, in native routing, a `ipv4-native-routing-cidr` covering every connected cluster's PodCIDR range (`Documentation/network/clustermesh/setup.rst:34-35`, `60`), a unique `cluster.name` and `cluster.id` (`126`), and mutually reachable ClusterMesh API servers (`373`).

## Decisions

### D9.1: Cluster API is the node-management contract; cluster-api-k3s and CAPH are the first providers

Nodes are `Machine` objects owned by a `KThreesControlPlane` and a `MachineDeployment`, with a `MachineHealthCheck`.
Terranix is not the node manager (this reverses the interim position that Terranix would create k3s hosts); it survives only to provision the seed/management host and any cloud objects CAPI does not own.
CAPI manages nodes from day one so that S4's first two Hetzner nodes are already rolled by flake bump (D9.6), not hand-replaced later.

### D9.2: remote k3s uses cluster-api-k3s `airGapped` mode; the NixOS image supplies the binary

`KThreesConfigTemplate.spec.agentConfig.airGapped: true` (and the control-plane equivalent) so the node never downloads k3s.
The NixOS snapshot carries `pkgs.k3s` from the locked nixpkgs, which is the same binary the VM leaves test.
No kubeadm anywhere: hetzkube's `KubeadmControlPlane`/`KubeadmConfigTemplate` are replaced by the KThrees kinds.

### D9.3: a Nix-written `/opt/install.sh` shim starts `k3s.service`

The NixOS image ships a script at `/opt/install.sh` (an `environment.etc`-style symlink or `systemd.tmpfiles` entry into the store) that ignores `INSTALL_K3S_*` download semantics, copies nothing, and does two things: it verifies `/etc/rancher/k3s/config.yaml` exists (written by cloud-init `write_files` from the `KThreesConfig`) and runs `systemctl start k3s.service`.
`services.k3s.configPath = "/etc/rancher/k3s/config.yaml"` so the unit reads the CAPI-generated config.
`services.k3s.role` is fixed at evaluation (F9.5); the image is therefore built per role, or the shim selects between `k3s-server.service` and `k3s-agent.service` units both declared in the closure and only one enabled at boot.
The choice between per-role images and a two-unit image is ambiguity A2 in the change's design.
The sentinel file the template expects (`{{ .SentinelFileCommand }}`) is written by the shim after `systemctl is-active k3s` succeeds.

### D9.4: management cluster is a capability with two handlers behind one contract

The contract is: a kubeconfig, the CAPI core plus CAPH plus cluster-api-k3s providers installed from Nix-rendered manifests through a `clusterctl.yaml` override (F9.2), and then identical CRs applied by `kubectl apply` or `clusterctl move`.

- Handler A: the NixOS k3s node closure as a QEMU VM via `virtualisation.host.pkgs` (F9.4), running on `aarch64-darwin` (HVF), `x86_64-linux` with KVM, or `x86_64-linux` under TCG (slow, correct). This is the preferred handler because it is the production closure.
- Handler B: k3d via the existing ctlptl recipes in `kubernetes/clusters/local-k3d/`, stripped to the CAPI controllers; a Docker fallback for hosts without a working hypervisor.

Both handlers are exercised by S3: handler A as the `vm-capi-management` leaf's management node, handler B by a `just` recipe that is not a check.
`kubernetes/clusters/local-k3d/` therefore survives the k3d workflow deletion in ADR-007 D7.13.

### D9.5: no nix-darwin k3s module

k3s is Linux-only; a Darwin host runs handler A's VM and nothing else.
The Darwin side is a `packages.aarch64-darwin.management-vm` output produced from the `aarch64-linux` node closure with `host.pkgs` set to the Darwin package set, plus a script that waits for the kubeconfig.

### D9.6: node OS is a Hetzner snapshot labelled by flake revision; a flake bump rolls nodes

The node image is built from the same NixOS k3s configuration the VM leaves import, uploaded as a Hetzner snapshot labelled `caph-image-name=k3s-<flake-rev-short>` by an `apps` effect (packer is not required; `hcloud` upload of a Nix-built disk image is sufficient and is inferred from CAPH's label contract, F9.3).
The easykubenix cluster module emits `HCloudMachineTemplate.spec.template.spec.imageName` from the same string.
Changing the flake revision changes the template, which makes CAPI create replacement machines and delete the old ones; that is the only node-roll mechanism.
Configuration-only changes must not roll nodes, which is why the root `OCIRepository` digest travels through `KThreesConfig.spec.files` (D9.7) and not through the image.

### D9.7: the root `OCIRepository` digest is delivered through `KThreesConfig.spec.files`

The Flux install manifest is in the image (`services.k3s.manifests`, ADR-008 D8.3); the root `OCIRepository` and root `Kustomization` are rendered into `KThreesConfig.spec.files` as `/var/lib/rancher/k3s/server/manifests/flux-root.yaml`.
The CAPI control plane then carries the desired-state digest per cluster, and bumping it is a `KThreesControlPlane` rollout rather than a snapshot rebuild.

### D9.8: one k3s NixOS module, one bootstrap-identity seam

`flake.modules.nixos.k3s-server` gains a `bootstrap` option with two values, `clan-vars` (token and server address from Clan vars; the existing fleet path and the multi-node VM leaf) and `cloud-init` (token, server address, and role config from the CAPI-generated `/etc/rancher/k3s/config.yaml`; the CAPH path and the NoCloud VM leaf).
Everything else in the module — kernel, networking, packages, `snapshotter`, disabled components — is identical in both, which is the invariant the two VM leaves regulate together.

### D9.9: the NoCloud VM leaf regulates the CAPI path

`vm-k3s-capi-bootstrap` boots one node from the `cloud-init` bootstrap variant with a `cidata` ISO built in the sandbox containing the `write_files` and `runcmd` that cluster-api-k3s would generate (rendered by a Nix function that mirrors `pkg/cloudinit/controlplane_init.go`), and asserts that `k3s.service` reaches `active`, the sentinel file exists, and `kubectl get nodes` reports the node.
It does not run the CAPI controllers.
Mutation: remove `write_files` for `/etc/rancher/k3s/config.yaml` and expect the shim to fail before `systemctl start`.

### D9.10: one easykubenix cluster module with a cloud-invariant core and a typed `platform` sum

The cluster module owns `Cluster`, `KThreesControlPlane`, `KThreesConfigTemplate`, `MachineDeployment`, `MachineHealthCheck`, the Flux install and root objects, and Cilium.
`platform` is a submodule typed as a sum over `hetzner | gcp | aws | kubevirt`; the selected variant alone owns `*Cluster`, `*MachineTemplate`, the node-image reference, the cloud-controller manager, and an optional CSI.
An unhandled provider name is an evaluation error (`throw`), not an empty render.
Only `hetzner` is implemented in S4; `gcp` and `aws` are render-only golden variants in S5; `kubevirt` is the name reserved for a self-hosted variant and is not implemented.

### D9.11: a per-cloud CCM is mandatory (R6)

Because cluster-api-k3s defaults `cloud-provider=external` (F9.1), a cluster without a cloud-controller manager never clears node taints.
The `platform` variant must render its CCM; a T1 leaf fails when the rendered tree for any variant lacks a CCM `Deployment` or `DaemonSet`, and the assertion is tied to the bootstrap seam: it applies when `bootstrap = "cloud-init"` and is vacuous under `clan-vars`, where the module passes `--disable-cloud-controller` as it does today.

### D9.12: two networks with partially overlapping membership

- D9.12a The existing ZeroTier fleet network is untouched; Kubernetes nodes never join it.
- D9.12b A dedicated Clan `wireguard` instance (its own `/40` ULA, F9.6) is the Kubernetes admin plane: members are every Kubernetes node plus admin workstations (stibnite and peers), never schedulable; control-plane nodes are the WireGuard controllers. It carries the API server on 6443 (the node's ULA is in `tls-san`, F9.1), SSH and Clan deploys, ClusterMesh API-server reachability, and node joins (`server` address is the controller's ULA).
- D9.12c The dataplane does not use the Clan WireGuard (hub-and-spoke would route pod traffic through controllers). Cilium WireGuard transparent encryption runs directly between node IPs (F9.7); cross-cloud it runs over public IPs, with UDP 51871 allowlisted through nftables in the node closure to the eval-time-known node set.
- D9.12d Cross-cloud is ClusterMesh between per-cloud clusters with disjoint PodCIDRs and a native-routing CIDR that covers every participating node network; etcd is never stretched across clouds.

### D9.13: ClusterMesh preconditions are evaluation-time assertions

The cluster module asserts, for the set of clusters that declare mesh membership, that PodCIDRs are pairwise disjoint, `cluster.id` values are unique, and every PodCIDR is contained in the shared `ipv4-native-routing-cidr` (F9.7).
A violation is an evaluation error, which the S0 purity leaf turns into a failing check.

### D9.14: no Crossplane, no Anthos

Neither adds a property the CAPI contract lacks for this fleet; both add a reconciler.

## Requirements carried into the OpenSpec delta specs

| Code | Requirement | Regulator | Tier |
|---|---|---|---|
| R9.1 | cloud-invariant core renders identically across `platform` variants modulo platform-owned fields (golden diff) | `capi-cloud-invariant-render` | T1 |
| R9.2 | unhandled `platform` is an evaluation error | `capi-platform-sum-total` | T1 |
| R9.3 | every variant with `bootstrap = "cloud-init"` renders a CCM (R6) | `capi-ccm-present` | T1 |
| R9.4 | ClusterMesh preconditions hold at evaluation | `clustermesh-preconditions` | T1 |
| R9.5 | a NoCloud seed boots a `cloud-init` node through the shim into `k3s.service` | `vm-k3s-capi-bootstrap` | T2 |
| R9.6 | handler A runs the CAPI providers from Nix-rendered manifests and accepts the rendered CRs | `vm-capi-management` | T3 |
| R9.7 | two Hetzner nodes are `Ready`, Flux converges, and a flake bump rolls one node | S4 runbook (not a check) | E |

## Verified versus inferred

| Code | Claim | Status | Discharging regulator |
|---|---|---|---|
| R9.a | cluster-api-k3s `airGapped` emits `INSTALL_K3S_SKIP_DOWNLOAD=true ... sh /opt/install.sh` | read in source (F9.1) | `vm-k3s-capi-bootstrap` renders and consumes the same text |
| R9.b | cluster-api-k3s installs through a `clusterctl.yaml` override | read in source (F9.2) | `vm-capi-management` (S3) |
| R9.c | CAPH and cluster-api-k3s work together | inferred; no reference deployment found | `vm-capi-management` applies both providers and a rendered `Cluster`; S4 is the first real reconciliation |
| R9.d | NixOS boots from a CAPI-generated NoCloud seed and the shim starts `k3s.service` | inferred from F9.5 | `vm-k3s-capi-bootstrap` (S3) |
| R9.e | a Nix-built disk image uploaded as a Hetzner snapshot satisfies CAPH's `imageName` contract without packer | inferred from F9.3 | S4 first node boot |
| R9.f | `virtualisation.host.pkgs` on `aarch64-darwin` runs the k3s closure fast enough to serve as a management cluster | inferred from F9.4 | handler A `just` recipe timing on stibnite (S3) |
| R9.g | Clan `wireguard` ULA in `tls-san` plus `server` on the controller ULA suffices for node join across clouds | inferred from F9.6 and F9.1 | S4 two-node join; cross-cloud only in a later stage |
| R9.h | UDP 51871 allowlist to an eval-time node set is stable under CAPI node rolls | inferred; the node set changes when a `MachineDeployment` scales | a T1 assertion that the allowlist is derived from the same `MachineDeployment` replica set, plus S4 roll observation |

## Provenance

| ADR decision | Design-review code | Note |
|---|---|---|
| D9.1 | D27 (reversed), D20 | `cross-cloud-node-management.md` §D27; `oci-caph-timoni-decisions.md` D20 |
| D9.2 | D19 | `oci-caph-timoni-decisions.md` F18–F20, D19 |
| D9.3 | D19 | `oci-caph-timoni-decisions.md` D19 |
| D9.4 | D20 | `oci-caph-timoni-decisions.md` F21, D20 |
| D9.5 | D20 | `oci-caph-timoni-decisions.md` D20 |
| D9.6 | D21 | `oci-caph-timoni-decisions.md` F22, D21 |
| D9.7 | D22 | `oci-caph-timoni-decisions.md` D22 |
| D9.8 | D28 | `cross-cloud-node-management.md` D28 |
| D9.9 | D28 | `cross-cloud-node-management.md` D28 |
| D9.10 | D29 | `cross-cloud-node-management.md` D29 |
| D9.11 | D29, R6 | `cross-cloud-node-management.md` R6 |
| D9.12 | D30a–D30d | `cross-cloud-node-management.md` D30 |
| D9.13 | D30d | `cross-cloud-node-management.md` D30d |
| D9.14 | D31 | `cross-cloud-node-management.md` D31 |

## Related

- ADR-007: VM regulators and stage plan; D7.11–D7.13 are constrained by D9.4 and D9.8.
- ADR-008: the artifact the CAPI bootstrap delivers (D8.3, D8.4) and the Flux install it assumes in the image.
- `openspec/changes/k3s-nixos-vm-tests/specs/capi-cluster-rendering/spec.md` and `specs/k3s-substrate-vm-regulator/spec.md`.
