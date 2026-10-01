# ADR-007: NixOS VM tests for the k3s substrate and platform stack

## Status

Proposed (2026-09-04; revision 1 the same day after the design review recorded in the provenance table below; revision 2 the same day after the scope review recorded in D7.15–D7.19; charter v1 the same day, naming the cluster and recording D7.20–D7.22).
The programme-level view that binds this record to ADR-008, ADR-009, ADR-010, and both OpenSpec changes is `../cryolite-charter.md`; the charter cites, the ADRs decide.
Research and design only; no VM test, check leaf, flake input, production module change, or workflow change lands with this record.
The staged plan that implements stages S0–S2 is the OpenSpec change `openspec/changes/k3s-nixos-vm-tests/`; stages S3, S4, S4b, and the deferred S5 are the sibling change `openspec/changes/capi-hetzner-cluster/`, which depends on the first.

The first revision of this record proposed ArgoCD synced from a nixidy-rendered tree as the platform path, a VM-specific nixidy environment, and a four-stage migration.
Revision 1 replaced that with Flux consuming a digest-pinned OCI artifact (ADR-008), easykubenix rendering, Cluster API node management (ADR-009), and a six-stage plan S0–S5 that ended by deleting the k3d workflow, nixidy, ArgoCD, and sops-secrets-operator.
Revision 2 narrows the target: every new property belongs to one new sibling cloud cluster, `kubernetes/clusters/cryolite` (named in D7.20), while `kubernetes/clusters/local` and `kubernetes/clusters/local-k3d` are frozen prototypes that this plan does not migrate, delete, or edit.
The retirement of nixidy, the reversal of ADR-006, the retirement of sops-secrets-operator, and the deletion of the k3d workflow leave this plan and become Future Work in a later, separately authorized "feedback" change; until then ArgoCD reconciles `local-k3d` and Flux reconciles `cryolite`.
Findings F1–F6, the assertion-to-tier table (Q1), the substrate leaf designs (Q2, Q3), the platform analysis (Q4), and every citation in Q7 stand; the leaves are renamed to the module tree of D7.17 (`vm-k3s-substrate`, `vm-k3s-snapshotter`, `vm-k3s-platform`), and Q3's two-node join path is regulated inside the two-guest `vm-k3s-platform` rather than by a standalone leaf.
Every decision of revision 1 is retained below with a revision-2 status of kept, narrowed, or superseded; a superseded decision names the decision that replaces it and is never deleted.

## Context

The repository verifies its Kubernetes platform through one GitHub Actions workflow, `.github/workflows/test-cluster.yaml`, which runs a k3d cluster inside Docker on `ubuntu-latest` and drives it through `modules/apps/cluster/k3d-integration-ci.sh`.
That workflow was built when no KVM-capable host was available for NixOS VM tests.
PR #2954 has since established the repository's first full QEMU/KVM regulator, `checks.x86_64-linux.vm-nixos-base` in `modules/checks/vm-nixos-base.nix`, and made `just test-integration` build every `checks.<system>.vm-*` leaf.
The question this record answers is how the k3d workflow's coverage is re-expressed as NixOS VM tests and pure Nix checks, and what remains that genuinely cannot move.

The target the plan converges on is stated once here and detailed in ADR-008, ADR-009, and ADR-010: a two-node k3s cluster on Hetzner, declared as `kubernetes/clusters/cryolite`, whose nodes are NixOS closures built by this flake, managed by Cluster API (cluster-api-k3s plus the Hetzner provider CAPH), whose workloads are reconciled by Flux from an OCI artifact pinned by digest, whose identity is split into stable cluster identity and disposable node identity (ADR-010), and whose declaration is one easykubenix cluster module with a typed `platform` seam so the same declaration reaches any CAPI-compatible cloud later.
Every property of that target that can be regulated without money or a network is regulated by a `checks.<system>.<name>` leaf before the first Hetzner node exists.
The existing clusters `local` and `local-k3d` are frozen prototypes: they keep ArgoCD, nixidy, sops-secrets-operator, kube-proxy, and the k3d workflow exactly as they are, and nothing in this plan edits `kubernetes/clusters/local*`, `kubernetes/nixidy/`, `kubernetes/tests/local-k3d/`, or `modules/apps/cluster/`.
Existing files grow only additively and default-off: `modules/kubernetes.nix` gains `cryolite` in `evalCluster`; `modules/nixos/k3s-server/default.nix` gains a `snapshotter` option and loses its inert containerd block (F1); `modules/devshells/kubernetes.nix` gains `flux`, `clusterctl`, `hcloud`, `cosign`, and `crane`.

The vocabulary is the repository's compositional-continuous-verification (CCV) framing: each check is a regulator paired with a declared operating envelope; regulators are placed at the cheapest sufficient tier; every leaf is an independent, cacheable `checks.<system>.<name>`; and `nix flake check` is the closure operator over all of them.
The four suite properties used below are existence (a regulator of the kind exists), traceability (every artifact has a regulator pointing at it), adequacy (the regulators saturate the envelope's declared bins), and integrity (the regulator would fail if its target broke, shown by mutation evidence).

Every factual claim below cites a path and line range.
Paths under `~/ghq/` refer to the reference trees listed in the appendix at the revisions recorded there; paths without a prefix are in this repository.
Claims read in source are stated as facts; claims that follow from reading but were not executed are marked "inferred" and listed again in the open-risk table (Q8).

## Findings

### F1: the production NixOS k3s module is unregulated, and part of it is inert

`modules/nixos/k3s-server/default.nix` defines `flake.modules.nixos.k3s-server` and imports the sibling deferred modules `k3s-server-kernel`, `k3s-server-networking`, and `k3s-server-packages`.
No machine under `modules/machines/` and no check under `modules/checks/` imports it: `rg k3s-server modules --glob '!modules/nixos/k3s-server/*'` returns nothing.
Under CCV this is a traceability gap, not an adequacy gap: the artifact has zero regulators.

A standalone evaluation of the module (`logs/k3s-server-eval-*.log`, expression reproduced in the OpenSpec design) shows what it actually produces:

- `systemd.services.k3s.serviceConfig.ExecStart` is `k3s server --token-file … --disable=flannel --disable=local-storage --disable=metrics-server --disable=servicelb --disable=traefik --kubelet-arg=config=… --cluster-init --flannel-backend=none --disable-network-policy --disable-kube-proxy --disable-cloud-controller --cluster-cidr=10.42.0.0/16 --service-cidr=10.43.0.0/16` (from `modules/nixos/k3s-server/default.nix:84-102`, rendered by `~/ghq/github.com/NixOS/nixpkgs/nixos/modules/services/cluster/rancher/default.nix:932-933` and `k3s.nix:12`).
- `boot.kernelPackages.kernel.version` is `7.1.6` (`modules/nixos/k3s-server/kernel.nix:19`); `boot.kernelModules` contains the nine modules at `kernel.nix:22-31`; the sysctls at `kernel.nix:34-50` are present.
- `networking.firewall.allowedTCPPorts` is `[2379 2380 4240 4244 6443 10250]`, `allowedUDPPorts` is `[4789 8472]`, and `trustedInterfaces` is `["cni+" "cilium+" "lxc+" "lo"]` (`modules/nixos/k3s-server/networking.nix:37-55`).
- `virtualisation.containerd.enable` is `false` and `environment.etc` has no `containerd/config.toml`.

The last point means the whole `virtualisation.containerd.settings` block at `networking.nix:61-84` is inert.
Nixpkgs' containerd module guards all of its output behind `config = lib.mkIf cfg.enable` (`~/ghq/github.com/NixOS/nixpkgs/nixos/modules/virtualisation/containerd.nix:57`), and nothing sets `enable`.
K3s does not use the host containerd anyway: it runs an embedded containerd whose configuration is generated under its data directory, and the supported customization point is `services.k3s.containerdConfigTemplate`, which writes `/var/lib/rancher/k3s/agent/etc/containerd/config.toml.tmpl` (`rancher/default.nix:29`, `628-647`, `877-879`).
That option is `null` in the evaluated configuration.
The settings were carried over from hetzkube, where they are live because hetzkube runs kubeadm with a standalone containerd that it explicitly enables (`~/ghq/github.com/Lillecarl/hetzkube/nixos/kubernetes.nix:17-27`).

A related but distinct point concerns the CNI paths.
K3s emits a `cni` section into its containerd config only when `CNIBinDir` or `CNIConfDir` is populated (`~/ghq/github.com/k3s-io/k3s/pkg/agent/templates/templates.go:134-137`, `225-228`), and it populates them only on the embedded-flannel path (`pkg/executor/embed/embed.go:184-185`).
With `--flannel-backend=none` the section is absent and containerd falls back to its defaults, `/opt/cni/bin` and `/etc/cni/net.d`, which are the same paths the Cilium chart installs into (`~/ghq/github.com/cilium/cilium/install/kubernetes/cilium/values.yaml:811-813`).
The activation script at `networking.nix:89-95` copying `pkgs.cni-plugins` into `/opt/cni/bin` is therefore harmless but is not what makes Cilium work; whether Cilium needs any of those plugins in this repository's configuration is a runtime question for the VM leaf.

Correcting the inert block is a module change, not a test change, and is out of scope for this record; its scope is fixed by D7.8 below.
The VM leaf designed below is what would have caught it, and the eval-tier leaf designed below catches it today.

### F2: the k3d run does not regulate the production envelope

The k3d cluster keeps kube-proxy and ServiceLB (`kubernetes/clusters/local-k3d/cluster.yaml:3-13`, `21-48`) and overrides Cilium to `kubeProxyReplacement = false`, `bpf.masquerade = false`, `sysctlfix.enabled = false`, `gatewayAPI.hostNetwork.enabled = false`, `nodePort.enabled = true` (`kubernetes/clusters/local-k3d/default.nix:60-73`).
The production Cilium module sets `kubeProxyReplacement = true`, `routingMode = "tunnel"`, `tunnelProtocol = "geneve"`, `bpf.masquerade = true` (`kubernetes/modules/cilium/default.nix:61-82`), and the production k3s module passes `--disable-kube-proxy` and `--disable=servicelb`.
The two envelopes differ exactly where Cilium's eBPF datapath, kube-proxy replacement, and LoadBalancer address assignment are concerned.

One consequence is concrete.
The Chainsaw suite asserts `Gateway/main-gateway` reaches `Programmed=True` (`kubernetes/tests/local-k3d/infrastructure/02-assert-gateway.yaml`, step `infrastructure-gateway` at `kubernetes/tests/local-k3d/chainsaw-test.yaml:38`).
Cilium marks a Gateway Programmed only after its generated LoadBalancer Service has at least one ingress address (`~/ghq/github.com/cilium/cilium/operator/pkg/gateway-api/status_gateway_address.go:136`, `162`), and until then reports `AddressNotAssigned` (`status_gateway_address.go:70-81`).
In k3d that address comes from K3s ServiceLB.
The production module disables ServiceLB and the production Cilium module declares no `CiliumLoadBalancerIPPool` (only the CRD API mapping at `kubernetes/modules/cilium/default.nix:112`).
So `Programmed=True` is discharged today only under the k3d envelope, and would be unreachable under the production envelope without an LB-IPAM pool, host-network Gateway mode (`~/ghq/github.com/cilium/cilium/Documentation/network/servicemesh/gateway-api/host-network-mode.rst:15-20`), or re-enabling ServiceLB.
The production mechanism is now decided: Cilium LB-IPAM (D7.9).

### F3: the VM regulators need a runner decision before they can gate anything in CI

`nixosLib.runTest` stamps every VM test with `requiredSystemFeatures = ["kvm" "nixos-test"]` (`~/ghq/github.com/NixOS/nixpkgs/nixos/lib/testing/run.nix:48-63`, `162`).
The nixbot/buildbot worker intentionally exposes no KVM, so VM leaves are unschedulable there.
GitHub's documentation for hosted runners states: "While nested virtualization is technically possible while using runners, it is not officially supported. Any use of nested VMs is experimental and done at your own risk, we offer no guarantees regarding stability, performance, or compatibility."
The same vendor's changelog documents hardware-accelerated Android virtualization on Linux runners and shows the runner user being granted `/dev/kvm` through a udev rule, and the current `ubuntu-latest` image is Ubuntu 24.04.4 on an Azure 6.17 kernel (runner-images release notes retrieved 2026-09-04).
Local evidence — `/dev/kvm` present, `nix config show` listing `kvm nixos-test` — does not transfer to any remote host.
The design therefore treats GitHub-hosted KVM as unverified until a probe job establishes it, and offers a supported fallback (D7.10).

### F4: the Nix sandbox has no network, so every image and every artifact is a build input

Every OCI image the platform stack needs must be preloaded through `services.k3s.images`, which links each image into `/var/lib/rancher/k3s/agent/images` before k3s starts so the embedded containerd imports it (`rancher/default.nix:28`, `648-667`, `854`).
Nixpkgs' own tests build their pause image with `dockerTools.buildLayeredImage` and preload it this way (`nixos/tests/rancher/single-node.nix:22`, `66`).
The locked Nixpkgs k3s (`1.35.6+k3s1`) ships its core airgap bundle as `k3s.airgap-images-amd64-tar-zst`, built here at roughly 236 MiB compressed.
The rendered `local-k3d-ci` manifests (146 files, 2.4 MiB) reference thirteen third-party images, listed in the Q4 section; their compressed sizes were not all retrievable from registries during this research, so the platform closure is bounded rather than measured.
The same constraint applies to the Flux configuration artifact introduced by ADR-008: inside a VM leaf it is served by a registry running in the guest and loaded from a store path, never fetched.

### F5: three current phases already have cheaper regulators

`k8s-manifests-local-k3d`, `k8s-manifests-local-k3d-json`, `nixidy-env-local-k3d`, and `nixidy-bootstrap-local-k3d` (from `modules/kubernetes.nix` and `modules/nixidy.nix`) build the `local-k3d` environment; they are not `checks` leaves, because their evaluation needs import-from-derivation (easykubenix `chart2json` and `yaml2json`, nixidy's Helm rendering), and they stay buildable on demand.
The k3d script's phase 1 builds the sibling `local-k3d-ci` environment, which differs only in `nixidy.target.repository = "file:///manifests"` (`modules/nixidy.nix:52`; `modules/apps/cluster/k3d-integration-ci.sh:57`), and its `file:///manifests` grep at line 63 is a pure property of that build; only the runtime consumption of the rendered tree needs a cluster.
The frozen `local-k3d` prototype (D7.15) is therefore regulated by those on-demand builds and the k3d `integration` job, not by `checks`; `cryolite` has no nixidy environment, so its T1 leaves are the easykubenix render leaf and the purity, provenance, and identity leaves of S0, all evaluating without import-from-derivation.

### F6: k3s embeds nix-snapshotter, and its NRI plugin is enabled unless k3s runs in a user namespace

The locked k3s vendors `github.com/pdtpartners/nix-snapshotter v0.4.0` (`~/ghq/github.com/k3s-io/k3s/go.mod:129`).
The agent flag `--snapshotter` selects the containerd snapshotter (`pkg/cli/cmds/agent.go:165-166`); when its value is `nix`, the generated containerd template enables `plugins."io.containerd.snapshotter.v1.nix"` with its image service and sets `snapshotter = "nix"` in the `linux/amd64` and `linux/arm64` unpack configs (`pkg/agent/templates/templates.go:113-131`), and `disable_snapshot_annotations` becomes `false` for both `stargz` and `nix` (`templates.go:86`).
Selecting `nix` requires `nix-store` on the k3s service's `PATH`: `NixSupported` returns an error otherwise (`pkg/agent/containerd/config_linux.go:138-142`), which is why nix-snapshotter's own k3s module adds `pkgs.nix` to `systemd.services.k3s.path` when `snapshotter == "nix"` (`~/ghq/github.com/pdtpartners/nix-snapshotter/modules/nixos/k3s.nix:30-35`).
The NRI plugin section `plugins.'io.containerd.nri.v1.nri'` is emitted with `disable = true` only under `IsRunningInUserNS` (`templates.go:322-326`); a root k3s therefore leaves NRI enabled by containerd's default.
That last sentence is inferred from the template, not observed on a running node; the substrate leaf asserts it (D7.2) and the containerd correction depends on the observation (D7.8).

## Q1: assertion-to-tier table

Tiers, cheapest first:

- T1 — pure evaluation or build (`nix eval`, nix-unit, package build, `runCommand` over a rendered tree). No sandbox features. Runs everywhere, including the nixbot worker.
- T2 — NixOS VM substrate (one or more QEMU nodes composed from `flake.modules.nixos.k3s-server`, no platform workloads). Requires `kvm nixos-test`.
- T3 — live platform stack in a NixOS VM (Cilium, Flux, cert-manager, step-ca, Gateway API, with preloaded images and an in-guest registry serving the OCI artifact). Requires `kvm nixos-test` and the preload closure.
- E — an `apps` effect that touches a registry or a cloud; never a check. Asserts its own postcondition (ADR-008 D8.7, ADR-009 D9.16).
- K — stays on k3d/Docker. Used only where a concrete blocker is named; for `cryolite` the only K row is the k3d management handler B on Colima (ADR-009 D9.4, D9.17). The `local-k3d` workflow is also K, and stays as it is.

Current k3d phases (`k3d-integration-ci.sh:38-45`), read as the properties the `cryolite` regulators must cover; the k3d run itself continues unchanged for `local-k3d`:

| Phase | Property | Cheapest sufficient tier | Notes |
|---|---|---|---|
| 1 nixidy-build `local-k3d-ci` | manifests render | T1 | for `cryolite`: the easykubenix render leaf and the S0 purity leaves; the nixidy leaf stays for `local-k3d` (D7.15) |
| 1 grep for `file:///manifests` | rendered repo URL is local | T1 | no ArgoCD in `cryolite`; the analogous property is that every Flux `OCIRepository` carries `spec.ref.digest` (ADR-008 D8.3), a T1 leaf |
| 2 stage `/tmp/k3d-manifests` as git repo | manifests are consumable by the reconciler | T3 | in a VM: the OCI layout is loaded into an in-guest registry and Flux pulls it by digest (ADR-008 D8.6) |
| 3 `k3d-full` (ctlptl + kluctl deploy) | cluster boots; foundation applies | T2 (boot) / T3 (apply) | replaced by `services.k3s` plus `services.k3s.manifests` carrying Cilium and Flux |
| 4 `k3d-wait-ready` | Cilium, reconciler, step-ca ready | T3 | |
| 5 `nixidy-bootstrap` | root reconciler object applies | T3 | the root `OCIRepository` and `Kustomization` are in the node closure; T1 asserts their shape |
| 6 `k3d-wait-argocd-sync` | every workload reconciled; Gateway Programmed | T3 | `Kustomization` `Ready=True` replaces `Synced`+`Healthy`; `Programmed` needs LB-IPAM (F2, D7.9) |
| 7 `k3d-test-coverage` (Chainsaw) | see below | T3 | Chainsaw runs in-guest (Q7) |
| — `k3d-configure-dns` | CoreDNS forwards `sslip.io` to `1.1.1.1` | K→T3 with substitution | needs network; replaced by a CoreDNS `hosts`/`template` answer inside the VM |
| — `k3d-bootstrap-secrets` | `sops-age-key` Secret exists | T3 with fixture | Q5; the Secret becomes `flux-system/sops-age` (ADR-008 D8.9) |

Chainsaw assertions of the prototype (`kubernetes/tests/local-k3d/{foundation,infrastructure}/*.yaml`, ordered by `chainsaw-test.yaml:8-48`), with the `cryolite` counterpart each gets in `kubernetes/tests/cryolite` (D7.16); the `local-k3d` suite itself is not edited:

| Assertion | Tier | Substrate-only variant available at T2? |
|---|---|---|
| Cilium DaemonSet ready | T3 | no; T2 O-a asserts the node is `NotReady` for exactly the missing-CNI reason |
| Cilium operator ready | T3 | no |
| ArgoCD controller/server/repo-server/redis/applicationset ready | none in `cryolite` | counterpart: Flux `source-controller`, `kustomize-controller`, `notification-controller` ready (ADR-008 D8.2) |
| ArgoCD Applications adopted/Synced | none in `cryolite` | counterpart: every `Kustomization` `Ready=True` with `status.lastAppliedRevision` equal to the pinned digest; the rendered objects are T1 |
| cert-manager controller/cainjector/webhook ready | T3 | no |
| step-ca StatefulSet ready | T3 | no |
| sops-secrets-operator Deployment ready | none in `cryolite` | counterpart: a Flux `Kustomization` with `spec.decryption` decrypts a fixture Secret (ADR-008 D8.9); the operator stays in `local-k3d` |
| `ClusterIssuer/step-ca-acme` Ready=True | T3 | the ACME server URL and solver shape are T1 |
| `Gateway/main-gateway` Programmed=True | T3 | needs LB address (F2, D7.9) |
| Gateway has four listeners, each Accepted=True | T3 | listener count and hostnames are T1 over the rendered Gateway |
| Certificates `argocd-tls`, `test-cert-tls` Ready=True | T3 | needs in-VM DNS for the sslip hostnames (Q4 B3); `argocd-tls` is renamed with its consumer |
| HTTPRoute `argocd` Accepted=True | T3 | parentRef shape is T1; the route's backend changes with the reconciler |

Properties no current assertion covers but the production module or the target architecture claims:

| Property | Tier |
|---|---|
| ExecStart carries every intended `--disable`/flag, including `--snapshotter nix` once D7.1 lands | T1 (nix-unit over `systemd.services.k3s.serviceConfig.ExecStart`) |
| `--cluster-cidr`/`--service-cidr` effective | T2 (`kubectl get node -o jsonpath={.spec.podCIDR}`; `kubectl get svc kubernetes` in 10.43.0.0/16) |
| flannel/kube-proxy actually absent | T2 (`ip link` shows no `flannel.1`/`cni0`; no `kube-proxy` process; `kubectl -n kube-system get ds` has no kube-proxy) |
| kernel modules loaded, sysctls applied | T2 (`lsmod`, `sysctl -n`) |
| firewall ports open, trusted interfaces | T2 (`nft list ruleset` or `iptables-save`) |
| kernel ≥ 5.10 with Cilium's required config | T1 for version; T2 for `zcat /proc/config.gz` bins from `system_requirements.rst:157-227` |
| `virtualisation.containerd` inert (F1) | T1 today; the correction is D7.8 |
| embedded containerd runs the `nix` snapshotter; NRI plugin enabled (F6) | T2 (`ctr --address /run/k3s/containerd/containerd.sock plugins ls` shows `io.containerd.snapshotter.v1.nix` ok and `io.containerd.nri.v1.nri` not disabled; a `nix-snapshotter.buildImage` pod's rootfs mounts are store paths) |
| unprivileged user cannot read the kubeconfig | T2 (`single-node.nix:87`) |
| `k3s-killall.sh` cleans up | T2 (`single-node.nix:98-108`) |
| two-node join, cross-node pod connectivity | T2 multi-node (Q3) |
| no `flakeRef`, `nixExpr`, `:latest`, or untagged image reference in the rendered tree; rendered images ⊆ preload set | T1 (ADR-008 D8.11; OpenSpec `k3s-manifest-purity-regulator`) |
| closure provenance report: `nix path-info -r` of the manifest closure plus the image digest inventory | T1 (ADR-008 D8.12) |
| OCI-layout digest computed in the sandbox equals the digest the registry reports after push | E (ADR-008 D8.7) |
| cloud-invariant core renders identically for every `platform` variant modulo platform-owned fields; unhandled provider is an evaluation error | T1 golden diff (ADR-009 D9.8, D9.9) |
| selected `platform` renders its CCM; omitted CCM fails (R6) | T1 (ADR-009 D9.10) |
| ClusterMesh preconditions: PodCIDRs disjoint, native-routing CIDR covers every node network | T1 eval-time assertion (ADR-009 D9.17) |
| NixOS node boots from a NoCloud seed carrying KThrees-shaped user-data and joins through the air-gapped shim | T2 (ADR-009 D9.3; leaf `vm-k3s-capi-bootstrap`) |
| management-cluster handlers A and B expose the same kubeconfig-plus-providers contract | T2 for A (QEMU VM), K for B (Docker) (ADR-009 D9.4) |

## Q2: one-node design, `vm-k3s-substrate`

### Shape

One `perSystem.checks` leaf in a new `modules/checks/vm-k3s-substrate.nix`, following `modules/checks/vm-nixos-base.nix` from PR #2954 exactly: `nixosLib.runTest`, `imports = [ inputs.clan-core.modules.nixosTest.clanTest ]`, `extraPythonPackages = lib.mkForce (_: [ ])`, `clan.test.useContainers = false`, `clan.directory = pkgs.emptyDirectory`, one inventory machine, `system.stateVersion = config.system.nixos.release`, and the `boot.initrd.network.ssh` direct-boot workaround because `base` is imported (D7.11).
The machine imports `config.flake.modules.nixos.k3s-server` unmodified and sets `k3s-server.enable = true; clusterInit = true; tokenFile = <fixture>`.

The full QEMU regulator is warranted here rather than nspawn because the properties are kernel-level: loaded modules, sysctls, nftables, a CNI-shaped network namespace, and the snapshotter's bind mounts of store paths into container rootfs.

### Options for a CNI

- O-a: no CNI. Assert the node exists and is `NotReady` with `.status.conditions[?(@.type=="Ready")].reason == "KubeletNotReady"` and a message containing `cni plugin not initialized`; assert CoreDNS stays `Pending`; assert every substrate property in the table above, including the F6 snapshotter and NRI rows.
- O-b: ship Cilium. Add a test-only `services.k3s.autoDeployCharts.cilium` from the `cilium-src` input (or `services.k3s.manifests` from the rendered `kubernetes/modules/cilium` output) and preload `cilium`, `operator-generic`, and `cilium-envoy` via `services.k3s.images`; assert `Ready` and run the single-node pod test from `single-node.nix:90-92`.
- O-c: fetch Cilium at runtime. Rejected: the Nix build sandbox has no network, so no chart, image, or DNS lookup succeeds.

### Decision: O-a for `vm-k3s-substrate` (D7.2); a Nix-workload leaf beside it (D7.3)

O-a regulates exactly the artifact that is unregulated (F1): the module's own claims about the node.
It has no image closure beyond the ~236 MiB core bundle, boots in the time k3s itself needs, and every assertion is independent of Cilium's version.
Its `NotReady` assertion is deliberately narrow: `reason` and `message` are checked, not merely the condition, so a node that is `NotReady` for a different cause fails the test.
O-b in the single-node leaf would conflate two envelopes (substrate and CNI) in one regulator and pull a ~1 GiB-class image closure into the cheapest VM leaf; it belongs in the T3 leaf where the rest of the platform already requires those images.

The snapshotter rows need a running pod, which O-a's `NotReady` node cannot schedule.
They therefore live in a sibling T2 leaf, `vm-k3s-snapshotter` (D7.3): one node importing `k3s-server`, a test-only `services.k3s.extraFlags = ["--flannel-backend=vxlan"]` override plus `lib.mkForce` removal of `flannel` from `disable` as synthetic glue, one `nix-snapshotter.buildImage` pod whose reference is `nix:0<store path>` (`~/ghq/github.com/pdtpartners/nix-snapshotter/package.nix:74-76`), and assertions that the pod runs, that `findmnt` inside its rootfs shows the store paths of the image closure, and that `ctr plugins ls` lists the `nix` snapshotter `ok`.
The override is glue because the production module has no flannel and the leaf regulates the snapshotter, not the CNI; a mutation that sets `k3s-server.snapshotter = "overlayfs"` must fail the `findmnt` assertion.

### Sizing and wall time

Nixpkgs sizes k3s tests at `memorySize = 1536; diskSize = 4096` (`nixos/tests/rancher/default.nix:76-79`).
O-a runs the same workload as `single-node.nix` minus flannel, so the same numbers are the starting point; `diskSize` is raised to 8192 only if the images bundle plus `linuxPackages_latest` push the root image past 4 GiB, which the first build will show.
Expected wall time is the k3s-server startup (roughly 30–60 s to `kubectl get node` on a KVM host) plus the test-driver boot; the working estimate is two to four minutes per run, to be recorded from the first passing build.

### Integrity (mutation evidence)

The required mutation is a one-line change to the production module, for example removing `"--disable-kube-proxy"` from `k3s-server/default.nix`, which must make the kube-proxy absence assertion fail with its message; the second mutation removes `"br_netfilter"` from `kernel.nix:23` and must fail the `lsmod` assertion.
Both are recorded in the implementing PR body per PR #2954's convention.

## Q3: two-node join path (regulated inside `vm-k3s-platform` since revision 2)

Revision 2 has no standalone multi-node substrate leaf: the module tree (D7.17) names `vm-k3s-substrate`, `vm-k3s-snapshotter`, and `vm-k3s-platform`, and the platform leaf boots the server and agent of `cryolite` (D7.16), so the join path below is asserted there, with Cilium present, and its CNI-free variant is not built.
The analysis stands as the specification of what the two-guest leaf asserts about the join.

### Shape

Two `clan.machines`: `server` (`role = "server"; clusterInit = true`) and `agent` (`role = "agent"; serverAddr = "https://server:6443"`), both importing `k3s-server` and sharing one `tokenFile`.
The test driver puts both on `virtualisation.vlans = [ 1 ]` (`nixos/lib/testing/network.nix:72`); nixpkgs' test uses `networking.primaryIPAddress` for `nodeIP` and `serverAddr` (`multi-node.nix:98`, `160-161`, `198-199`).
The production module does not expose `nodeIP`; if the agent needs it the leaf sets `services.k3s.nodeIP` directly, which is synthetic glue, not duplicated logic.

### Token delivery

- Store-path token, as nixpkgs does: `tokenFile = pkgs.writeText "token" "…"` (`multi-node.nix:60`, `93`, `155`, `193`). The file is world-readable in the store, which is acceptable only because the value is a test fixture that authorizes nothing outside the sandbox.
- Clan shared var: a `clan.core.vars.generators.k3s-token` with `share = true`, generated in-sandbox by clanTest's vars executor, encrypted to the test age key (`~/ghq/git.clan.lol/clan/clan-core/lib/clanTest/vars-executor.nix:165`, `231`), and consumed on both nodes as `config.clan.core.vars.generators.k3s-token.files.token.path`.

Decision (D7.12): store-path token in the two-guest platform leaf.
Under ADR-009 the production join path for CAPI-managed nodes is the cluster-api-k3s token delivered by cloud-init from a T0 Secret (ADR-010 D10.4), not a Clan var, so the Clan generator this record once anticipated is not the shape `cryolite` uses; the bootstrap-identity seam (ADR-009 D9.8) names both handlers, `vm-k3s-platform` regulates the join with a store-path stand-in, and `vm-k3s-capi-bootstrap` (`capi-hetzner-cluster`, S3) regulates the cloud-init handler.

### What it adds and costs

It adds the join path (`--server`, token acceptance, agent registration), the agent-role flag set (no `--cluster-cidr`/`--service-cidr`, per `k3s-server/default.nix:98-102`), and cross-node reachability of the k3s supervisor and kubelet ports through the production firewall rules.
Cross-node pod-to-pod connectivity as in `multi-node.nix:233-247` requires a CNI, so on the substrate leaf it reduces to node-level assertions (both nodes registered, both `NotReady` for the CNI reason, agent can reach `server:6443` and `server:10250`); pod connectivity moves to the T3 leaf when Cilium is present.
Cost is two VMs of the single-node size, roughly double the wall time and memory of Q2.

## Q4: platform stack

### Image and chart inventory (current k3d envelope)

Charts rendered by nixidy/easykubenix from local sources (`kubernetes/modules/{cilium,argocd,step-ca,sops-secrets-operator}/default.nix`; Gateway API CRDs from the `gateway-api-src` input; cert-manager and the repository's own Gateway, HTTPRoute, ClusterIssuer, and Application objects): the rendered `local-k3d-ci` environment contains 146 files including 13 CRDs, 9 Deployments, 2 StatefulSets, 2 DaemonSets, 1 Job, 9 Applications, 1 Gateway, 1 HTTPRoute, 1 GatewayClass, 1 ClusterIssuer.
No chart is fetched at runtime; every chart is a Nix input already.

Images referenced by the rendered manifests:

| Image | Component | Fate in `cryolite` under ADR-008 (the `local-k3d` set is untouched) |
|---|---|---|
| `quay.io/cilium/cilium:v1.18.6` | Cilium agent | stays vendor OCI, pinned by digest (D7.5) |
| `quay.io/cilium/operator-generic:v1.18.6` | Cilium operator | stays vendor OCI, pinned by digest |
| `quay.io/cilium/cilium-envoy:v1.35.9-…@sha256:81398e…` | Cilium Envoy (Gateway) | stays vendor OCI |
| `quay.io/argoproj/argocd:v3.2.5` | ArgoCD (all components) | not deployed in `cryolite` (D7.6); the three Flux controller images take its place there; stays in `local-k3d` |
| `ecr-public.aws.com/docker/library/redis:8.2.2-alpine` | ArgoCD redis | not deployed in `cryolite`; stays in `local-k3d` |
| `quay.io/jetstack/cert-manager-{controller,webhook,cainjector,startupapicheck,acmesolver}:v1.21.1` | cert-manager | vendor OCI by digest now; ported to `nix-snapshotter.buildImage` in its own PR (D7.5) |
| `cr.smallstep.com/smallstep/step-ca:0.30.0` | step-ca | vendor OCI by digest now; ported to `nix-snapshotter.buildImage` in its own PR (D7.5) |
| `isindir/sops-secrets-operator:0.16.0` | sops-secrets-operator | not deployed in `cryolite`, whose decryptor is Flux SOPS (ADR-008 D8.9); stays in `local-k3d`, its retirement is Future Work |
| `alpine/curl:latest` | a Job; unpinned | fails the S0 purity leaf until pinned by digest |
| `docker.io/rancher/mirrored-pause:3.6`, `docker.io/rancher/mirrored-coredns-coredns:1.12.3` | k3s core, in the airgap bundle | unchanged |

The `alpine/curl:latest` reference is a finding in itself: an unpinned tag cannot be preloaded reproducibly and must be pinned by digest before any T3 leaf is built; the S0 purity regulator (ADR-008 D8.11) makes that a failing check rather than a review note.

Closure estimate: the k3s core bundle is 236 MiB compressed (built).
Cilium agent and Envoy images are the largest third-party items; registry metadata for step-ca, sops-secrets-operator, and Cilium could not be retrieved during this research (requests timed out).
The bound used for planning is 1.5–2.5 GiB compressed for the full platform, to be measured by `nix path-info -S` on the first `dockerTools.pullImage` set.
Each pulled image is a fixed-output derivation, so it is fetched once per digest and cached like any other input.

### Blockers to running the Chainsaw suite in a VM, and their hermetic substitutes

- B1 no network: every image preloaded (F4); every chart is already a Nix input; the Flux configuration artifact is a store path loaded into an in-guest registry (ADR-008 D8.6).
- B2 desired-state transport: the k3d run mounts a host git repo into the node for ArgoCD. Under ADR-008 the reconciler pulls an OCI artifact by digest, so the VM leaf starts a registry in the guest (`services.dockerRegistry`, D7.22, following nix-snapshotter's own push-and-pull test pattern, `~/ghq/github.com/pdtpartners/nix-snapshotter/modules/nixos/tests/push-n-pull.nix`), loads the OCI layout from the store into it, and points the root `OCIRepository` at `localhost:<port>/<name>@sha256:<digest>` with the same digest the node closure pins.
- B3 DNS for `*.192.168.100.3.sslip.io`: the ACME HTTP-01 solver (`kubernetes/nixidy/local-k3d/apps/cluster-issuer.nix:44-62`) requires step-ca to resolve the certificate hostnames (`argocd-route.nix:22`, `gateway.nix:25`) to the Gateway address; today CoreDNS forwards `sslip.io` to `1.1.1.1` (`modules/apps/cluster/k3d-configure-dns.sh:12`). In a VM CoreDNS must answer those names itself (a `hosts` or `template` stanza) and the hostnames must embed the VM node's address rather than k3d's `192.168.100.3`. Under D7.6 this is a test variant of the `cryolite` easykubenix cluster module (its `topology.nix` evaluated for the VM VLAN), not a nixidy environment and not an edit to `local-k3d`.
- B4 LoadBalancer address for `Programmed=True` (F2): a `CiliumLoadBalancerIPPool` declared by the cluster module (D7.9); a test that re-enables ServiceLB would regulate the k3d envelope again, not production.
- B5 secrets: `SOPS_AGE_KEY` from GitHub Secrets is replaced by the Q5 fixture, mirrored into `flux-system/sops-age`.
- B6 Chainsaw in the guest: `pkgs.chainsaw` exists in the locked nixpkgs (`pkgs/by-name/ch/chainsaw/package.nix:9`, 2.16.2); the test directory is a store path; see Q7 for kubeconfig handling.

None of these is a blocker in the sense of impossibility; each is work with a known shape.
What is genuinely lost is the check that the rendered tree can be consumed from a Docker volume mount and that the platform works on k3d's kube-proxy envelope — both properties of the k3d substrate, not of the platform.

### Options

- O-1: one `vm-k3s-platform` leaf boots the `cryolite` core (revision 2: a server and an agent guest, D7.16) with Cilium, Flux, cert-manager, step-ca, and the Gateway, serves the OCI artifact from an in-guest registry, then runs the `kubernetes/tests/cryolite` Chainsaw suite in-guest.
- O-2: several leaves each preloading a slice: `vm-k3s-cilium` (Cilium + Gateway API CRDs + Gateway Programmed via B4), `vm-k3s-gitops` (Cilium + Flux reconciling from B2), `vm-k3s-pki` (Cilium + cert-manager + step-ca + ClusterIssuer + Certificates via B3), `vm-k3s-secrets` (Cilium + Flux SOPS + fixture key).
- O-3: substrate leaves move; the platform Chainsaw suite stays on k3d/Docker permanently.

### Decision: O-1 first, O-2 only when measured cost demands it; O-3 rejected (D7.4)

The Chainsaw steps are ordered dependencies, not independent slices: Certificates need the ClusterIssuer, which needs step-ca and the Gateway solver, which needs Cilium and an LB address; Flux reconciles all of them.
Splitting into O-2 duplicates Cilium's image closure in every leaf and re-creates the wait-for-ready scaffolding four times for the same envelope.
O-1 is one regulator for one envelope — the `cryolite` platform as deployed — and has the shape of the k3d workflow minus Docker, but its Chainsaw suite is `kubernetes/tests/cryolite`, written for `cryolite` (foundation: Cilium, Flux ready; infrastructure: cert-manager, step-ca, ClusterIssuer, Gateway, Certificates, HTTPRoute), not a copy of `kubernetes/tests/local-k3d`, and it asserts nothing about ArgoCD or sops-secrets-operator.
O-2 becomes the right shape only if O-1's measured wall time exceeds what a developer will run locally (working threshold: 15 minutes), at which point `vm-k3s-cilium` splits off first because Gateway `Programmed` is the assertion most sensitive to the production/k3d envelope difference (F2).
O-3 is rejected because every blocker B1–B6 has a hermetic substitute; the only property that cannot move is a property of k3d itself.
Revision 2 leaves the k3d workflow in place as the regulator of the frozen `local-k3d` prototype; whether and when it is retired is a Future Work question for the feedback change, not a consequence of O-1 turning green.
The preload set of O-1 is derived from the rendered manifests, never hand-listed (ADR-008 D8.11): the set of image references in the rendered tree is computed at evaluation time and each element is a fixed-output pull by digest, so adding a workload without a preload is an evaluation failure.

## Q5: secrets

### Design

The k3d bootstrap reads `SOPS_AGE_KEY` from the environment or `~/.config/sops/age/keys.txt` and creates the `sops-age-key` Secret in namespace `sops-secrets-operator` (`modules/apps/cluster/k3d-bootstrap-secrets.sh:7-19`).
Under ADR-008 D8.9 the in-cluster decryptor is Flux's kustomize-controller reading `flux-system/sops-age`, and the production key is a per-cluster age key generated by Clan vars and delivered to the node by sops-nix, then mirrored into the Secret by `services.k3s.manifests`.
The VM replacement is a test-only age keypair committed as a fixture, following clan-core: a public key baked into the test library (`~/ghq/git.clan.lol/clan/clan-core/lib/clanTest/flake-module.nix:94`) and a private key installed on the machine at activation from a fixture file (`lib/test/age.nix:6-7`, `21-27`, reading `nixosModules/clanCore/vars/tests/age-fixtures/key.txt`).
sops-nix's own VM tests do the same with `sops.age.keyFile = "/run/age-keys.txt"` (`~/ghq/github.com/Mic92/sops-nix/checks/nixos-test.nix:17`, `89`, `97-98`).

In this repository the fixture lives under a non-`modules/` path (it is not a `.nix` module and must not be auto-imported), and the platform variant of the cluster module encrypts its SOPS payloads to that public key instead of the production recipients.
When clanTest is the harness, the alternative is a `clan.core.vars` generator with `share = true` whose output is encrypted by the in-sandbox executor to the clanTest public key (`vars-executor.nix:231`); once the production per-cluster key is a Clan generator (D8.9), the leaf switches to that generator and thereby regulates it.

### What this does not cover

The fixture regulates that Flux decrypts a SOPS payload with a key present in `flux-system/sops-age`.
It does not regulate production key provisioning, recipient lists in `.sops.yaml`, key rotation, or that the production age key is where the production node expects it.
Those remain properties of the deployment path, regulated (where they are regulated at all) by clan vars checks of the kind clan-infra runs as a pure derivation (`~/ghq/git.clan.lol/clan/clan-infra/checks/vars.nix`).

## Q6: where it runs, and the stage plan S0–S5 (revision 2: S0–S2 here, S3–S5 in `capi-hetzner-cluster`)

### Developer host

`just test-integration` (`justfile:663-670`) builds named `vm-*` checks today; PR #2954 makes it discover every `checks.<system>.vm-*` leaf, so new leaves need no recipe change.
The developer verifies KVM with `ls -l /dev/kvm` and `nix config show | grep system-features` first.
On `aarch64-darwin` no `vm-*` leaf exists; the management cluster there is k3d on Colima (handler B, ADR-009 D9.4), and the NixOS QEMU handler A that would run the node closure under HVF is deferred (D9.17).

### GitHub Actions

Because F3 leaves hosted-runner KVM unverified, the first workflow change is a probe, not a rewiring: a manually dispatched job on `ubuntu-latest` that runs the udev rule from GitHub's own changelog, checks `/dev/kvm`, and builds `.#checks.x86_64-linux.vm-k3s-substrate` with `--option system-features 'kvm nixos-test benchmark big-parallel'`.
If it passes repeatedly, `test-cluster.yaml` gains a `vm` job alongside `integration`; the `integration` job itself is not edited by this plan (D7.15).
If it does not, the supported path is a KVM-capable runner (a larger GitHub-hosted runner class documented to expose it, or a self-hosted runner on a KVM host), and the design records that as D7.10.
`cached-ci-job` hashing continues to apply; the `hash-sources` list at `.github/workflows/test-cluster.yaml:57` would name `modules/checks/vm-k3s-*.nix`, `modules/nixos/k3s-server/**`, and the fixture path in place of `kubernetes/**` for the substrate job.
For a Nix check, the store path is the better cache key: `nix build` of an already-built derivation is a no-op, so the `cached-ci-job` layer is redundant once the derivation is in a binary cache.

### nixbot/buildbot

VM leaves remain under `lib.optionalAttrs pkgs.stdenv.hostPlatform.isLinux` and are unschedulable on a worker without `kvm`.
Whether the worker's job scheduler skips them or reports them as failed depends on how nixbot handles `requiredSystemFeatures` it cannot satisfy; the OpenSpec plan includes a task to observe this on the first push rather than assume it, and to filter them from the worker's evaluation if they surface as failures.
No non-VM check depends on a VM check.
Every S0 leaf is T1 and runs on the worker; S0 therefore lands first so that the worker regulates purity and provenance on every push regardless of KVM.

### Stages (each stage one PR, each with a killed mutant; S4 requires explicit spend approval)

Every stage names its KVM requirement, its CCV regulators, and the mutation that shows each regulator non-vacuous; the OpenSpec tasks carry the exact mutations.
All leaves are scoped to `cryolite`; the `-cryolite` suffix on `k8s-*` leaves is written once here and elided below.

| Stage | Change | Contents | KVM | Tier | Gate |
|---|---|---|---|---|---|
| S0 | `k3s-nixos-vm-tests` | `k8s-purity` (no runtime `flakeRef`/`nixExpr`, no `:latest`, no tag-without-digest, images ⊆ preload set), `k8s-provenance` (`nix path-info -r` closure report with image digest inventory and the OCI-layout digest), `k8s-node-identity-free` (no CAPI CR, Flux manifest, Clan inventory entry, or Secret names a node or node key; ADR-010 D10.6), `flux-sources-pinned`, `flux-install-rendered`, `k3s-server-eval`; OCI digest equality asserted by the `apps.k8s.oci-push` effect, written here and first run in S4 | no | T1 (E for the effect) | none beyond this record |
| S1 | `k3s-nixos-vm-tests` | `k3s-server.snapshotter` option (default `"nix"`) and `pkgs.nix` on the k3s unit path; inert containerd block deleted (D7.8); `vm-k3s-substrate` (O-a: CNI-free, `NotReady` for exactly the missing-CNI reason, NRI socket observed); `vm-k3s-snapshotter` (pod rootfs is Nix store paths) | yes | T1, T2 | S0 |
| S2 | `k3s-nixos-vm-tests` | `vm-k3s-platform` (O-1) for the core of `cryolite`: two guests (server and agent), Cilium with `kubeProxyReplacement=true`, Flux controllers preloaded in the closure, root `OCIRepository` pinned by digest and served from an in-guest registry, Flux SOPS with the fixture key, LB-IPAM pool, in-VM DNS, Chainsaw suite from `kubernetes/tests/cryolite` run in-guest (D7.16) | yes | T3 | S1 |
| S3 | `capi-hetzner-cluster` | management handler B (k3d on stibnite/Colima, `apps.k8s.mgmt-k3d`); CAPI core, CAPH, and cluster-api-k3s installed from Nix-rendered manifests through a `clusterctl.yaml` override; `capi-cryolite` CR render; `k8s-capi-render` golden for `platform = hetzner` only; `vm-k3s-capi-bootstrap` (NoCloud seed → air-gapped join, T0 material delivered through `contentFrom.secret` and proven in-VM, ADR-010 D10.4) | yes (bootstrap leaf); no (render, handler B) | T1, T2, K (handler B) | S2 |
| S4 | `capi-hetzner-cluster` | first paid action: `apps.k8s.hetzner-snapshot-publish` (per-role image and snapshot, D9.16), two-node deployment using machines M1–M6 (ADR-010 D10.5), `clusterctl move`, admin access through the CAPH load balancer and the SSH CA; no admin overlay | no | E | S3; spend is approved in principle and released per revision by `VANIXIETS_HETZNER_SPEND_APPROVED=<flake rev>` (D7.21, ADR-009 D9.19), never by silence |
| S4b | `capi-hetzner-cluster` | admin overlay: one WireGuard gateway per cluster peering with the controller on the existing primary VPS (D9.15) | no | E | S4 |
| S5 (deferred) | `capi-hetzner-cluster` | `platform = gcp` render-only goldens and the platform-core render-equivalence regulator; `platform = aws` is declared and throws (ADR-009 D9.20); no cloud account is touched | no | T1 | S3 (S4 is not a prerequisite) |

Nothing is deleted by either change.
The deletion plan of revision 1 (k3d CI scripts, the `integration` job, `SOPS_AGE_KEY`, `modules/nixidy.nix`, `kubernetes/nixidy/`, the ArgoCD and sops-secrets-operator manifests, the CI-only k3d justfile recipes) is Future Work for a later, separately authorized feedback change that migrates or retires the frozen prototypes; `kubernetes/clusters/local-k3d/`, the ctlptl recipes, and the k3d `integration` job keep running unchanged until then (D7.15).

## Q7: reference patterns cited

- NixOS test framework: `requiredSystemFeatures` at `nixos/lib/testing/run.nix:48-63`, `162`; VLANs at `nixos/lib/testing/network.nix:72`; driver API `succeed` (`nixos/lib/test-driver/src/test_driver/machine/__init__.py:479`), `wait_until_succeeds` (`516`), `wait_for_open_port` (`599`), `copy_from_host` (`783`), `forward_port` (`1516`).
- Nixpkgs k3s tests: sizing `nixos/tests/rancher/default.nix:76-79`; single-node assertions `single-node.nix:84-108`; multi-node topology and token `multi-node.nix:60`, `93-98`, `155-161`, `193-199`, script `233-247`.
- Nixpkgs k3s module: `role` (`rancher/default.nix:413`), `serverAddr` (`422`), `tokenFile` (`440`), `extraFlags` (`467`), `configPath` (`485`), `disable` (`491`), `nodeIP` (`515`), `manifests` (`533`), `containerdConfigTemplate` (`628-647`), `images` (`648-667`, linked at `854`), `gracefulNodeShutdown` (`668`), `autoDeployCharts` (`731`), `ExecStart` composition with `${cfg.role}` fixed at evaluation (`932-940`); `clusterInit` (`rancher/k3s.nix:86`, flag at `12`, agent assertion at `131-132`).
- Nixpkgs QEMU VM: `virtualisation.host.pkgs` (`nixos/modules/virtualisation/qemu-vm.nix:728`), KVM check on Linux and HVF check on Darwin (`299-318`), QEMU package selection by host arch (`741-751`).
- Nixpkgs fluxcd: release manifests vendored as a fixed-output `fetchzip` (`pkgs/by-name/fl/fluxcd/package.nix:15-19`) and copied into the build (`36`); version 2.9.3 (`12`).
- k3s: `--snapshotter` flag (`pkg/cli/cmds/agent.go:165-166`); nix snapshotter template (`pkg/agent/templates/templates.go:86`, `113-131`); NRI disabled only in a user namespace (`322-326`); `NixSupported` (`pkg/agent/containerd/config_linux.go:138-142`); nix-snapshotter vendored (`go.mod:129`); conditional CNI section (`templates.go:134-137`, `225-228`), flannel-path CNI dirs (`pkg/executor/embed/embed.go:184-185`).
- nix-snapshotter: `buildImage` producing `nix:0<store path>` references and `copyToRegistry`/`copyToContainerd` passthrus (`package.nix:31-38`, `76`, `85-86`, `101`, `117`); k3s module adding `--snapshotter` and `pkgs.nix` to the unit path (`modules/nixos/k3s.nix:20`, `30-35`); VM tests including k3s and push-and-pull (`modules/nixos/tests/{k3s,k3s-external,push-n-pull}.nix`).
- clan-core clanTest: `useContainers` option (`lib/clanTest/flake-module.nix:220`), VM/container node split (`311-312`), mixed-mode hard fail (`297-298`), minify and age modules (`353-357`), shared-var encryption (`lib/clanTest/vars-executor.nix:165`, `231`); a multi-machine VM service test at `clanServices/zerotier/tests/vm/default.nix:5-7`; the `wireguard` service's controller/peer model and `/40` ULA allocation (`clanServices/wireguard/README.md:8-34`).
- clan-infra: pure-derivation vars and toplevel checks (`checks/flake-module.nix`, `checks/vars.nix`); it runs no VM tests, which is consistent with a fleet whose CI host lacks KVM.
- hetzkube: kubeadm plus standalone containerd (`nixos/kubernetes.nix:17-27`), Cilium with `kubeProxyReplacement = true` and `routingMode = "tunnel"` (`kubenix/configuration/cilium.nix:72-93`); CAPI resources rendered from Nix (`kubenix/modules/capi.nix:141`, `161`, `166`, `198`, `261`, `269`, `283`, `323`) with `imageName` literals (`220`, `305`, `367`) and `caph-image-name` labels (`README.md:44-45`); `clusterctl move` (`README.md:110`).
- Chainsaw: the default cluster is loaded through `clientcmd.NewDefaultClientConfigLoadingRules()` (`pkg/utils/rest/config.go:12-19`, called at `pkg/commands/test/command.go:365`), so `KUBECONFIG=/etc/rancher/k3s/k3s.yaml chainsaw test <dir>` in the guest works with no flag; `--cluster name=<kubeconfig path>` (`command.go:456`) and the `--kube-*` override flags (`command.go:421`; `website/docs/reference/commands/chainsaw_test.md:16`, `36-47`) exist, `--no-cluster` at `command.go:460`. There is no `--kube-config` flag in this version. Running Chainsaw from the test driver via `forward_port` is possible but adds a host-side Chainsaw and a TLS SAN concern for nothing; in-guest is the design.
- Cilium: k3s install flags (`Documentation/installation/k3s.rst:28-40`); kernel `>= 5.10` and required config (`Documentation/operations/system_requirements.rst:23`, `40`, `144-147`, `157-227`); Gateway API requires `kubeProxyReplacement=true`, creates a LoadBalancer Service, needs the standard CRDs (`Documentation/network/servicemesh/gateway-api/installation.rst:5-16`); host-network mode (`host-network-mode.rst:15-20`); Programmed semantics (`operator/pkg/gateway-api/status_gateway_address.go:70-81`, `136`, `162`); ClusterMesh prerequisites (`Documentation/network/clustermesh/setup.rst:34-35`, `60`); WireGuard transparent encryption on UDP 51871 (`Documentation/security/network/encryption-wireguard.rst:13-14`, `34`).
- Gateway API: standard CRDs under `config/crd/standard/`; conformance under `conformance/`.
- disko and sops-nix: `makeTest`-based VM tests (`disko/lib/tests.nix:90-92`; `sops-nix/checks/nixos-test.nix:17`, `89`).
- GitHub: nested virtualization statement and Android KVM changelog quoted in F3; `ubuntu-latest` image Ubuntu 24.04.4, kernel 6.17.0-1022-azure (runner-images release notes, retrieved 2026-09-04).
- Cluster API, cluster-api-k3s, CAPH, Flux, nix2container, nixpod, Timoni, nixkube: cited in ADR-008 and ADR-009.

## Q8: verified versus inferred, and the regulator that discharges each open risk

| Code | Claim | Status | Discharging regulator |
|---|---|---|---|
| R7.1 | k3s embedded containerd runs with the `nix` snapshotter when `--snapshotter nix` is passed and `nix-store` is on the unit path | read in source (F6) | `vm-k3s-snapshotter` (S1) |
| R7.2 | NRI is enabled on a root k3s node | inferred from the template (F6) | `vm-k3s-substrate` `ctr plugins ls` assertion (S1); if it proves disabled, D7.8 adds `containerdConfigTemplate` |
| R7.3 | cluster-api-k3s and CAPH work together | not run by anyone found; cluster-api-k3s ships samples for aws, azure, docker, nutanix, openstack, proxmox, vsphere and none for Hetzner (`~/ghq/github.com/k3s-io/cluster-api-k3s/samples/`) | rendered-CR leaf in S3 for shape; S4 for behavior (both `capi-hetzner-cluster`) |
| R7.4 | cluster-api-k3s is absent from clusterctl's built-in registry | read in source: `providers_client.go` lists `kubekey-k3s` bootstrap and control-plane providers (`~/ghq/github.com/kubernetes-sigs/cluster-api/cmd/clusterctl/client/config/providers_client.go:87`, `100`) but no `k3s`; the project's own `samples/clusterctl.yaml:1-8` shows the override | a T1 leaf asserting the rendered `clusterctl.yaml` names both k3s providers (S3) |
| R7.5 | a NixOS node boots from a CAPI NoCloud seed and the air-gapped shim starts `k3s.service` idempotently while cloud-init holds the boot sequence | unverified | `vm-k3s-capi-bootstrap` (S3, `capi-hetzner-cluster`) |
| R7.6 | exact compressed platform image closure | bounded 1.5–2.5 GiB, not measured | `nix path-info -S` recorded in the S2 PR body |
| R7.7 | GitHub-hosted `ubuntu-latest` exposes usable KVM | vendor says unsupported (F3) | the probe job (S2) |
| R7.8 | nixbot skips rather than fails a `kvm`-requiring derivation | unobserved | observed on the S1 push |
| R7.9 | Flux `spec.verify` with a keyed cosign public key succeeds against an artifact signed at push, with no network | read in docs (`~/ghq/github.com/fluxcd/source-controller/docs/spec/v1/ocirepositories.md:548-549`) | `vm-k3s-platform` (S2) with the fixture signing key |
| R7.10 | the Hetzner Cloud API has no image-upload endpoint, so a snapshot of a NixOS image requires a throwaway server in rescue mode (`hcloud-upload-image` pattern) | read in CAPH docs (`~/ghq/github.com/syself/cluster-api-provider-hetzner/docs/caph/02-topics/03-node-image.md:22`; ADR-009 R9.i) | S4's first `hetzner-snapshot-publish` run |

## Decisions

Decisions are numbered D7.n in this record, D8.n in ADR-008, D9.n in ADR-009, and D10.n in ADR-010.
The provenance table maps each to the design-review note that resolved it and to the earlier code it supersedes; the four notes are the authoritative record of the first review, and the revision-2 dispatch (codes D-a–D-j) is the authoritative record of the second.
Each revision-1 decision carries a bracketed revision-2 status: kept, narrowed (the decision stands for `cryolite` and no longer claims the frozen prototypes), or superseded (a named later decision replaces it; the text is retained).

- D7.1 [kept] The node's container snapshotter is nix-snapshotter through k3s's embedded `--snapshotter nix`; the production module gains `k3s-server.snapshotter` with default `"nix"` and adds `pkgs.nix` to the k3s unit path (F6). nixkube is not added as a flake input; runtime `flakeRef` and `nixExpr` are forbidden in every hermetic regulator.
- D7.2 [kept; leaf renamed `vm-k3s-substrate`] The substrate leaf is CNI-free (O-a) and asserts the substrate rows of Q1 including the snapshotter plugin and NRI state.
- D7.3 [kept; leaf renamed `vm-k3s-snapshotter`] A separate T2 leaf regulates one `nix-snapshotter.buildImage` pod with a test-only flannel override as glue.
- D7.4 [narrowed by D7.16] One `vm-k3s-platform` leaf (O-1) with the preload set derived from the rendered manifests; split only on measured wall time above fifteen minutes. Revision 2 fixes its content to the two-guest `cryolite` core.
- D7.5 [kept] Third-party operators are vendored as OCI images pinned by digest now; step-ca and cert-manager are ported to `nix-snapshotter.buildImage` one PR each; Cilium stays vendor OCI.
- D7.6 [narrowed by D7.15] The reconciler of `cryolite` is Flux and its only manifest evaluation framework is easykubenix. Revision 1 also retired nixidy, the `kubernetes/nixidy/` tree, the nixidy environments, and the Phase-3/Phase-4 adoption split, and reversed ADR-006 through ADR-008 D8.10; those retirements are Future Work for the feedback change (D7.15), nixidy and ArgoCD stay for `local-k3d`, and ADR-006 stands until then. The `local-vm` nixidy environment proposed in the first revision (D-P2) remains withdrawn.
- D7.7 [kept] KVM-free purity and provenance regulators land first (S0) so the nixbot worker regulates the rendered tree on every push.
- D7.8 [kept] The inert `virtualisation.containerd.settings` block (F1) is deleted in S1; `services.k3s.containerdConfigTemplate` is introduced only if the D7.2 NRI assertion shows NRI disabled. This and the `snapshotter` option are the only edits to `modules/nixos/k3s-server/default.nix`.
- D7.9 [kept] The Gateway address mechanism of `cryolite` is Cilium LB-IPAM through a `CiliumLoadBalancerIPPool` declared by the cluster module; ServiceLB stays disabled. `local-k3d` keeps its own mechanism.
- D7.10 [narrowed by D7.15] If the `ubuntu-latest` KVM probe fails or flakes, VM leaves gate only on a KVM-capable runner (a larger GitHub-hosted class documented to expose it, or a self-hosted KVM host); until one exists they run through `just test-integration`. The clause "and the k3d workflow is retained as containment" is moot: the k3d workflow is retained unconditionally.
- D7.11 [kept] Fleet k3s nodes import `base`; every k3s VM leaf imports `base` and `k3s-server`.
- D7.12 [kept; leaf changed] The two-guest platform leaf uses a store-path token; the production join paths are named by the bootstrap-identity seam (ADR-009 D9.8) and the T0 token is delivered by `contentFrom.secret` (ADR-010 D10.4).
- D7.13 [Superseded by D-a (rev 2, D7.15)] `kubernetes/clusters/local-k3d/` and the ctlptl recipes survive for Darwin development and as management handler B; only the CI scripts, the workflow job, and the nixidy tree are deleted. Rationale: revision 2 deletes nothing; `local-k3d` is a frozen prototype whose CI scripts and workflow job also survive, and handler B is a separate k3d cluster on Colima, not `local-k3d`.
- D7.14 [Superseded by D-i (rev 2, D7.18)] Stages are S0–S5 as tabulated in Q6; S4 is gated on explicit spend approval and is never inferred from silence. Rationale: the stage plan is split across two OpenSpec changes and gains S4b; the S4 spend gate is unchanged.

Revision-2 decisions (codes D-a–D-j of the dispatch; D-c and D-e are ADR-010 D10.1–D10.7, D-d, D-f, and D-g are ADR-009 D9.15–D9.17, and ADR-008 D8.15 records the narrowing):

- D7.15 (D-a) Scope. The plan builds one sibling cloud cluster, `kubernetes/clusters/cryolite`; `kubernetes/clusters/local` and `kubernetes/clusters/local-k3d` are frozen prototypes that it does not migrate, edit, or delete. nixidy retirement, ADR-006 reversal, sops-secrets-operator retirement, k3d workflow deletion, and any edit to `kubernetes/nixidy/local-k3d` are Future Work for a later, separately authorized feedback change. ArgoCD (in `local-k3d`) and Flux (in `cryolite`) coexist. Existing files change only additively through default-off options: `modules/kubernetes.nix` (`evalCluster` gains `cryolite`), `modules/nixos/k3s-server/default.nix` (`snapshotter` option; dead containerd block removed), `modules/devshells/kubernetes.nix` (`flux`, `clusterctl`, `hcloud`, `cosign`, `crane`). #2955's D-C1, D-C2, and D-P2 are moot; D11 and D13 of the first review narrow to `cryolite`.
- D7.16 (D-b) `vm-k3s-platform` regulates the core of `cryolite`: two guests (server and agent), Cilium with `kubeProxyReplacement=true` (which closes F2's envelope drift for `cryolite` only; `local-k3d` keeps kube-proxy), Flux controllers preloaded in the closure, the root `OCIRepository` pinned by digest and served from an in-VM registry, and the `kubernetes/tests/cryolite` Chainsaw suite run in-guest (foundation: Cilium, Flux ready; infrastructure: cert-manager, step-ca, ClusterIssuer, Gateway, Certificates, HTTPRoute). It is not a replica of the `local-k3d` suite and asserts nothing about ArgoCD or sops-secrets-operator.
- D7.17 (D-h) Module layout. The target tree is recorded once, in `openspec/changes/k3s-nixos-vm-tests/design.md` §"Target module layout", with each path marked `[keep]`, `[add]`, or `[+opt]`. Its rationale: `modules/` (flake-parts exports) and `kubernetes/` (easykubenix cluster contents) are two module systems deliberately not merged, bridged only by `modules/kubernetes.nix`; the `[add]` paths are dendritically additive, so deleting them makes `cryolite` disappear with no other edit; one evaluation yields one hash chain, `clusters/cryolite` → `k8s-manifests-cryolite` → `k8s-oci-cryolite` digest → `k3s-flux.nix` pins the digest → `cryolite-server` closure → snapshot label → `capi-cryolite` CRs; per-cloud variance lives in `kubernetes/modules/platform/` (typed sum) on the Kubernetes side and `modules/kubernetes/<provider>/` on the NixOS side; Flux is normalized to Nix-first (the artifact contents are the Flux layout; Flux keeps fetch, SSA, prune, drift, ordering, SOPS, and notification, and loses self-install, `postBuild` substitution, and git sources); checks are leaves by kind (`vm-*` KVM runtime, `k8s-*` KVM-free eval and golden); effects live only under `modules/apps/k8s/`.
- D7.18 (D-i) Stage plan. S0 (KVM-free: purity, provenance, node-identity-free, OCI digest equality), S1 (KVM: `vm-k3s-substrate`, `vm-k3s-snapshotter`), S2 (KVM: `vm-k3s-platform` per D7.16) in `k3s-nixos-vm-tests`; S3 (handler B, provider install rendering, `capi-cryolite` render and `k8s-capi-render` golden for Hetzner only, `vm-k3s-capi-bootstrap`, T0 delivery proven in-VM), S4 (first paid action, explicit gate: Hetzner image and snapshot effect, two-node deploy with M1–M6, `clusterctl move`, admin via LB and SSH CA, no overlay), S4b (admin overlay gateway, controller on the primary VPS), and deferred S5 (GCP render-only goldens and platform-core render equivalence; narrowed from GCP/AWS to GCP-only by ADR-009 D9.20 in charter v1, `platform.aws` declared and throwing) in `capi-hetzner-cluster`. Every stage is tabulated in Q6 with its KVM requirement and CCV regulators, and every regulator keeps a mutation that shows it non-vacuous.
- D7.19 (D-j) Document structure. Two OpenSpec changes, the second depending on the first; ADR-010 added for identity tiers and bootstrap; ADR-009 revised for D-d, D-f, D-g and the removed seed host; ADR-008 narrowed to `cryolite`. R6 of the first review is resolved: OpenSpec stays the planning ledger and a Linear binding is added only when execution of a stage begins. Every accepted first-review decision D1–D31 carries a revision-2 status in the table below.

Charter-v1 decisions (the owner's answers to the revision-2 questions; the charter at `../cryolite-charter.md` binds them to the other records):

- D7.20 Name. The sibling cluster is `cryolite` (Na₃AlF₆, the ice-stone of Ivittuut, Greenland, mined as the flux for aluminium smelting), continuing the fleet's mineral names (stibnite, magnetite, cinnabar). The machines are `cryolite-server` and `cryolite-agent`; the paths are `kubernetes/clusters/cryolite`, `kubernetes/tests/cryolite`, and `secrets/clusters/cryolite`. Resolves OQ7.1 and the parent change's A10; the name is a design constant, not a design change, and every `k8s-*` leaf carries the `-cryolite` suffix.
- D7.21 Spend gate. Hetzner spend is approved in principle for S4 and is released one flake revision at a time: every `apps.k8s.*` effect that calls the Hetzner Cloud API refuses to run unless `VANIXIETS_HETZNER_SPEND_APPROVED` equals the flake revision it is about to act on, and the billing surface is listed in the charter, on every S4 task, and in `openspec/changes/capi-hetzner-cluster/`. The decision and its regulator are ADR-009 D9.19; this record only makes the S4 gate in Q6 refer to it. No task of `k3s-nixos-vm-tests` bills anything.
- D7.22 In-guest registry. The S2 registry is `services.dockerRegistry` from the pinned nixpkgs (ADR-008 D8.6, verified as R8.h); it exists only inside the `vm-k3s-platform` guest. Resolves B2 of Q4 and the parent change's A4.

### Provenance

| ADR decision | Design-review code | Note | Supersedes |
|---|---|---|---|
| D7.1 | D1, D3, D4, D8 | `k3s-nixkube-decisions.md` §4 D1, D3, D4, D8; `k8s-architecture-current-vs-nixified.md` §4 D1, D3, D4, D8 | ADR-007 rev. 1 Q2 "no snapshotter statement" |
| D7.2 | D2, D3 | `k3s-nixkube-decisions.md` D2, D3 | ADR-007 rev. 1 Q2 O-a (retained, extended) |
| D7.3 | D2 | `k3s-nixkube-decisions.md` D2; `k8s-architecture-current-vs-nixified.md` D2 | — |
| D7.4 | D6 | `k8s-architecture-current-vs-nixified.md` D6 | ADR-007 rev. 1 Q4 O-1 (retained) |
| D7.5 | D5 | `k8s-architecture-current-vs-nixified.md` D5; `k3s-nixkube-decisions.md` D5 | — |
| D7.6 | D10, D11 | `k8s-architecture-current-vs-nixified.md` §3, D10, D11 | ADR-007 rev. 1 Q4 ArgoCD path, D-P2; ADR-006 |
| D7.7 | D7 | `k8s-architecture-current-vs-nixified.md` D7; `k3s-nixkube-decisions.md` D7 | ADR-007 rev. 1 stage order |
| D7.8 | D9 (D-M1 re-scoped) | `k8s-architecture-current-vs-nixified.md` D9 | ADR-007 rev. 1 D-M1 |
| D7.9 | D9 (D-P1), D23 | `k8s-architecture-current-vs-nixified.md` D9; `oci-caph-timoni-decisions.md` D23 | ADR-007 rev. 1 D-P1 |
| D7.10 | D9 (D-C1) | `k8s-architecture-current-vs-nixified.md` D9 | ADR-007 rev. 1 D-C1 |
| D7.11 | D9 (D-S1) | `k8s-architecture-current-vs-nixified.md` D9 | ADR-007 rev. 1 D-S1 |
| D7.12 | D9 (D-S2), D28 | `k8s-architecture-current-vs-nixified.md` D9; `cross-cloud-node-management.md` D28 | ADR-007 rev. 1 D-S2 |
| D7.13 | D9 (D-C2), D20 | `k8s-architecture-current-vs-nixified.md` D9; `cross-cloud-node-management.md` §Resolved D20 | ADR-007 rev. 1 D-C2 |
| D7.14 | staging sections | all four notes §Staging; dispatch message "Stage plan to encode" | ADR-007 rev. 1 stages 0–4 |
| D7.15 | D-a | revision-2 dispatch §D-a | D7.6 (global retirements), D7.10 (containment clause), D7.13 |
| D7.16 | D-b | revision-2 dispatch §D-b | D7.4 (one-node content) |
| D7.17 | D-h | revision-2 dispatch §D-h (tree and rationale D1–D7 of the tree message) | — |
| D7.18 | D-i | revision-2 dispatch §D-i | D7.14 |
| D7.19 | D-j | revision-2 dispatch §D-j | first-review R6 (planning ledger) |

### First-review decisions D1–D31: revision-2 status

The codes are those of the four design-review notes and the first dispatch.
A superseded decision is retained in the ADR that carries it; its replacement is named here.

| Code | Subject | Revision-2 status | Carried by |
|---|---|---|---|
| D1 | nix-snapshotter first; nixkube never an input; no runtime `flakeRef`/`nixExpr` | kept | D7.1, D8.11 |
| D2 | substrate leaf CNI-free with NRI and snapshotter assertions | kept (leaves renamed) | D7.2, D7.3 |
| D3 | NRI socket assertion | kept | D7.2 |
| D4 | `k3s-server.snapshotter` option, default `"nix"` | kept | D7.1 |
| D5 | operators vendor OCI by digest; step-ca and cert-manager ported one PR each; Cilium stays OCI | kept | D7.5 |
| D6 | one `vm-k3s-platform` leaf, preload set from manifests | narrowed | D7.4, D7.16 |
| D7 | KVM-free purity checks first | kept | D7.7, D8.11, D8.12 |
| D8 | no nixkube input | kept | D7.1 |
| D9 (D-S1) | fleet k3s nodes import `base` | kept | D7.11 |
| D9 (D-S2) | no shared `k3s-token` Clan generator now | kept; the T0 join token is a Clan var for `cryolite` delivered by CAPI, not a shared fleet generator | D7.12, D10.1 |
| D9 (D-P1) | Gateway address by Cilium LB-IPAM | kept for `cryolite` | D7.9 |
| D9 (D-P2) | `local-vm` nixidy environment | superseded by D11 in rev. 1; moot in rev. 2 (no nixidy edit) | D7.6 |
| D9 (D-C1) | fallback runner if the KVM probe fails | narrowed; its containment clause is Superseded by D-a (rev 2, D7.15): the k3d workflow is retained unconditionally, so no fallback containment decision remains | D7.10 |
| D9 (D-C2) | keep `local-k3d` for Darwin, delete CI scripts and workflow job | Superseded by D-a (rev 2, D7.15): nothing is deleted; `local-k3d` is frozen | D7.13 |
| D9 (D-M1) | delete dead containerd block; `containerdConfigTemplate` only if NRI disabled | kept | D7.8 |
| D10 | Flux via digest-pinned OCI artifact, bootstrapped from `services.k3s.manifests` | narrowed to `cryolite` | D8.1, D8.3 |
| D11 | easykubenix only; retire nixidy; reverse ADR-006 | narrowed to `cryolite`: easykubenix renders `cryolite`; the retirement and reversal halves are Superseded by D-a (rev 2, D7.15) and become Future Work | D7.6, D8.10 |
| D12 | ghcr.io artifact, tag = flake rev, digest pinned in closure; in-VM registry offline | kept for `cryolite` | D8.3, D8.4, D8.6 |
| D13 | Flux SOPS with per-cluster Clan-vars age key; retire sops-secrets-operator | narrowed to `cryolite`: Flux SOPS stands; the retirement half is Superseded by D-a (rev 2, D7.15) and becomes Future Work | D8.9, D10.1 |
| D14 | `flux install --export` rendered in Nix; three controllers only | kept | D8.2 |
| D15 | artifact split by consumer (nix-snapshotter / nix2container / OCI layout) | kept | D8.5, D8.7 |
| D16 | nixpod layering; multi-arch index only when arm64 is real | kept | D8.8 |
| D17 | tags alias, consumers pin by digest | kept | D8.4 |
| D18 | keyed cosign at push; Flux `spec.verify` public key from Clan vars | kept; the key is T0 material | D8.14, D10.1 |
| D19 | remote k3s via cluster-api-k3s `airGapped` and a Nix shim | kept; regulated in `capi-hetzner-cluster` S3 | D9.2, D9.3 |
| D20 | management cluster as a capability with handlers A and B | narrowed by D-g (rev 2, D9.17): handler B first, handler A deferred, contract kept | D9.4 |
| D21 | Hetzner snapshot labelled `caph-image-name=<rev>`; flake bump rolls nodes | kept; refined by D-f (rev 2, D9.16): per-role, disko layout, named effect | D9.6, D9.16 |
| D22 | root `OCIRepository` digest via `KThreesConfig.spec.files` | kept; T0 secrets travel the same way via `contentFrom.secret` | D9.7, D10.4 |
| D23 | LB-IPAM pool declared by the cluster module | kept | D7.9 |
| D24 | Timoni excluded as reconciler | kept | D8.13 |
| D25 | Timoni only as digest-pinned offline ingest renderer | kept | D8.13 |
| D26 | Timoni-style CRD validation adopted | kept | D8.13 |
| D27 | terranix not the node manager; survives as seed-host provisioner | Superseded by D-e (rev 2, D10.3): there is no seed host; terranix stays for fleet hosts (magnetite, cinnabar) and is unrelated to k3s nodes | D9.1 |
| D28 | one k3s NixOS module with a bootstrap-identity seam | kept | D9.8, D9.9 |
| D29 | multi-cloud seam: cloud-invariant core plus typed `platform` sum | kept; gcp variant deferred to S5, aws declared-but-throwing (charter v1) | D9.10, D9.11, D9.20 |
| D30a | ZeroTier fleet network untouched; nodes never join it | kept | D9.12 |
| D30b | dedicated Clan `wireguard` instance as admin plane, control-plane nodes as controllers, nodes as members | Superseded by D-d (rev 2, D9.15): nodes join no Clan overlay; one gateway per cluster peers with the controller on the existing primary VPS; deferred to S4b | D9.12 |
| D30c | dataplane on Cilium WireGuard, not the Clan overlay | kept | D9.12 |
| D30d | cross-cloud is ClusterMesh with disjoint PodCIDRs; no stretched etcd | kept | D9.13 |
| D31 | no Crossplane, no Anthos | kept | D9.14 |

## Open questions

- OQ7.1 Resolved by D7.20: the cluster is `cryolite`.
- OQ7.2 Whether nixbot reports a `kvm`-requiring derivation as skipped or failed; observed in S1 (R7.8).
- OQ7.3 Whether Cilium in the O-1 leaf needs any `pkgs.cni-plugins` binary at all in this configuration (F1's activation script).
- OQ7.4 Exact compressed sizes of the step-ca and Cilium images; measured when the pulls are written (R7.6).
- OQ7.5 Whether `diskSize = 4096` suffices with `linuxPackages_latest` and the core bundle; measured in S1.
- Ambiguities raised to the repository owner with each revision are listed in the OpenSpec designs' Open Questions and repeated in the PR conversation; none is resolved here by inference.

## Appendix: reference tree revisions

| Tree | Revision |
|---|---|
| `~/ghq/github.com/NixOS/nixpkgs` | `044bfe75bfe4` (the flake lock's root `nixpkgs`) |
| `~/ghq/git.clan.lol/clan/clan-core` | `1c21a2388ffb` |
| `~/ghq/git.clan.lol/clan/clan-infra` | `027f8479fb4e` |
| `~/ghq/github.com/k3s-io/k3s` | `a305766d0b86` |
| `~/ghq/github.com/k3d-io/k3d` | `46f3480daa74` |
| `~/ghq/github.com/cameronraysmith/easykubenix` | `221e5b87bd22` |
| `~/ghq/github.com/Lillecarl/hetzkube` | `d022931faf26` |
| `~/ghq/github.com/kyverno/chainsaw` | `b7d4a4f5dd45` |
| `~/ghq/github.com/cilium/cilium` | `a3af3581ee3b` |
| `~/ghq/github.com/kubernetes-sigs/gateway-api` | `2b2128cc43e7` |
| `~/ghq/github.com/arnarg/nixidy` | `6ec84e1121d3` |
| `~/ghq/github.com/farcaller/nix-kube-generators` | `810dcf792081` |
| `~/ghq/github.com/nix-community/disko` | `ff8702b4de27` |
| `~/ghq/github.com/Mic92/sops-nix` | `fbf759290e0c` |
| `~/ghq/github.com/kubernetes-sigs/cluster-api` | `b20f84f2aec0` |
| `~/ghq/github.com/k3s-io/cluster-api-k3s` | `ecba04b5d0e6` |
| `~/ghq/github.com/syself/cluster-api-provider-hetzner` | `b5e7742262bb` |
| `~/ghq/github.com/Lillecarl/nixkube` | `f6734bfb9315` |
| `~/ghq/github.com/fluxcd/flux2` | `602d14817c2c` |
| `~/ghq/github.com/fluxcd/source-controller` | `3d828e0b9c87` |
| `~/ghq/github.com/pdtpartners/nix-snapshotter` | `8e875fb8eeb2` |
| `~/ghq/github.com/nlewo/nix2container` | `76be9608a7f4` |
| `~/ghq/github.com/cameronraysmith/nixpod` | `3db40c4ce3f7` |
| `~/ghq/github.com/stefanprodan/timoni` | `9d369ca134a5` |

## Related

- ADR-005: local cluster architecture revision (k3d + ctlptl), the envelope of the frozen `local-k3d` prototype; its k3d pattern is reused by management handler B on Colima.
- ADR-006: nixidy manifest distribution; stands for `local-k3d`; its reversal for the fleet is Future Work (ADR-008 D8.10).
- ADR-008: reconciler and artifact transport for `cryolite` (Flux, OCI artifact, nix-snapshotter/nix2container/OCI-layout split, signing, Timoni boundary).
- ADR-009: Cluster API node management and networking (cluster-api-k3s, CAPH, management handlers, multi-cloud seam, image path, admin overlay, ClusterMesh).
- ADR-010: identity tiers and non-circular bootstrap (T0/T1/T2, L0–L3, machines M1–M6, T0 delivery, node-identity-free regulator).
- `openspec/changes/k3s-nixos-vm-tests/`: stages S0–S2.
- `openspec/changes/capi-hetzner-cluster/`: stages S3, S4, S4b, and deferred S5; depends on the first.
- PR #2954: `vm-nixos-base`, the VM-leaf pattern followed here.
