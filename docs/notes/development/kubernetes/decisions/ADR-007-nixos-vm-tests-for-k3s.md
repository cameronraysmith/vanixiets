# ADR-007: NixOS VM tests for the k3s substrate and platform stack

## Status

Proposed (2026-09-04).
Research and design only; no VM test, check leaf, or workflow change lands with this record.
The staged plan that implements it is the OpenSpec change `openspec/changes/k3s-nixos-vm-tests/`.

## Context

The repository verifies its Kubernetes platform through one GitHub Actions workflow, `.github/workflows/test-cluster.yaml`, which runs a k3d cluster inside Docker on `ubuntu-latest` and drives it through `modules/apps/cluster/k3d-integration-ci.sh`.
That workflow was built when no KVM-capable host was available for NixOS VM tests.
PR #2954 has since established the repository's first full QEMU/KVM regulator, `checks.x86_64-linux.vm-nixos-base` in `modules/checks/vm-nixos-base.nix`, and made `just test-integration` build every `checks.<system>.vm-*` leaf.
The question this record answers is how the k3d workflow's coverage is re-expressed as NixOS VM tests and pure Nix checks, and what remains that genuinely cannot move.

The vocabulary is the repository's compositional-continuous-verification (CCV) framing: each check is a regulator paired with a declared operating envelope; regulators are placed at the cheapest sufficient tier; every leaf is an independent, cacheable `checks.<system>.<name>`; and `nix flake check` is the closure operator over all of them.
The four suite properties used below are existence (a regulator of the kind exists), traceability (every artifact has a regulator pointing at it), adequacy (the regulators saturate the envelope's declared bins), and integrity (the regulator would fail if its target broke, shown by mutation evidence).

Every factual claim below cites a path and line range.
Paths under `~/ghq/` refer to the reference trees listed in the appendix at the revisions recorded there; paths without a prefix are in this repository.

## Findings

### F1: the production NixOS k3s module is unregulated, and part of it is inert

`modules/nixos/k3s-server/default.nix` defines `flake.modules.nixos.k3s-server` and imports the sibling deferred modules `k3s-server-kernel`, `k3s-server-networking`, and `k3s-server-packages`.
No machine under `modules/machines/` and no check under `modules/checks/` imports it: `rg k3s-server modules --glob '!modules/nixos/k3s-server/*'` returns nothing.
Under CCV this is a traceability gap, not an adequacy gap: the artifact has zero regulators.

A standalone evaluation of the module (`logs/k3s-server-eval-*.log`, expression reproduced in the OpenSpec design) shows what it actually produces:

- `systemd.services.k3s.serviceConfig.ExecStart` is `k3s server --token-file … --disable=flannel --disable=local-storage --disable=metrics-server --disable=servicelb --disable=traefik --kubelet-arg=config=… --cluster-init --flannel-backend=none --disable-network-policy --disable-kube-proxy --disable-cloud-controller --cluster-cidr=10.42.0.0/16 --service-cidr=10.43.0.0/16` (from `modules/nixos/k3s-server/default.nix:84-102`, rendered by `~/ghq/github.com/NixOS/nixpkgs/nixos/modules/services/cluster/rancher/default.nix` and `k3s.nix:12`).
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

Correcting the inert block is a module change, not a test change, and is out of scope for this record.
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
Which of those the production cluster intends is a decision this record does not make (D-P1 below).

### F3: the VM regulators need a runner decision before they can gate anything in CI

`nixosLib.runTest` stamps every VM test with `requiredSystemFeatures = ["kvm" "nixos-test"]` (`~/ghq/github.com/NixOS/nixpkgs/nixos/lib/testing/run.nix:48-63`, `162`).
The nixbot/buildbot worker intentionally exposes no KVM, so VM leaves are unschedulable there.
GitHub's documentation for hosted runners states: "While nested virtualization is technically possible while using runners, it is not officially supported. Any use of nested VMs is experimental and done at your own risk, we offer no guarantees regarding stability, performance, or compatibility."
The same vendor's changelog documents hardware-accelerated Android virtualization on Linux runners and shows the runner user being granted `/dev/kvm` through a udev rule, and the current `ubuntu-latest` image is Ubuntu 24.04.4 on an Azure 6.17 kernel (runner-images release notes retrieved 2026-09-04).
Local evidence — `/dev/kvm` present, `nix config show` listing `kvm nixos-test` — does not transfer to any remote host.
The design therefore treats GitHub-hosted KVM as unverified until a probe job establishes it, and offers a supported fallback (D-C1 below).

### F4: the Nix sandbox has no network, so every image is a build input

Every OCI image the platform stack needs must be preloaded through `services.k3s.images`, which links each image into `/var/lib/rancher/k3s/agent/images` before k3s starts so the embedded containerd imports it (`rancher/default.nix:28`, `648-667`, `854`).
Nixpkgs' own tests build their pause image with `dockerTools.buildLayeredImage` and preload it this way (`nixos/tests/rancher/single-node.nix:22`, `66`).
The locked Nixpkgs k3s (`1.35.6+k3s1`) ships its core airgap bundle as `k3s.airgap-images-amd64-tar-zst`, built here at roughly 236 MiB compressed.
The rendered `local-k3d-ci` manifests (146 files, 2.4 MiB) reference thirteen third-party images, listed in the Q4 section; their compressed sizes were not all retrievable from registries during this research, so the platform closure is bounded rather than measured.

### F5: three current phases already have cheaper regulators

`modules/checks/nixidy-k8s.nix:24-30` exposes `k8s-manifests-local-k3d`, `k8s-manifests-local-k3d-json`, `nixidy-env-local-k3d`, and `nixidy-bootstrap-local-k3d` as build checks, for the `local-k3d` environment.
The k3d script's phase 1 builds the sibling `local-k3d-ci` environment, which differs only in `nixidy.target.repository = "file:///manifests"` (`modules/nixidy.nix:52`; `modules/apps/cluster/k3d-integration-ci.sh:57`), and its `file:///manifests` grep at line 63 is a pure property of that build; only the runtime consumption of the rendered tree needs a cluster.
The `local-k3d-ci` environment has no check leaf of its own today, which is a one-line T1 addition.

## Q1: assertion-to-tier table

Tiers, cheapest first:

- T1 — pure evaluation or build (`nix eval`, nix-unit, package build). No sandbox features.
- T2 — NixOS VM substrate (one or more QEMU nodes composed from `flake.modules.nixos.k3s-server`, no platform workloads). Requires `kvm nixos-test`.
- T3 — live platform stack in a NixOS VM (Cilium, ArgoCD, cert-manager, step-ca, sops-secrets-operator, Gateway API with preloaded images). Requires `kvm nixos-test` and the preload closure.
- K — stays on k3d/Docker. Used only where a concrete blocker is named.

Current k3d phases (`k3d-integration-ci.sh:38-45`):

| Phase | Property | Cheapest sufficient tier | Notes |
|---|---|---|---|
| 1 nixidy-build `local-k3d-ci` | manifests render | T1 | `nixidy-env-local-k3d` covers the sibling env; add the `-ci` leaf |
| 1 grep for `file:///manifests` | rendered repo URL is local | T1 | nix-unit or `runCommand` over the built env |
| 2 stage `/tmp/k3d-manifests` as git repo | manifests are consumable as a git remote | T3 | in a VM: a store-path bare repo or `git daemon` on the node; the `file://` scheme works unchanged |
| 3 `k3d-full` (ctlptl + kluctl deploy) | cluster boots; foundation applies | T2 (boot) / T3 (apply) | replaced by `services.k3s` plus `services.k3s.manifests`/`autoDeployCharts` |
| 4 `k3d-wait-ready` | Cilium, ArgoCD, step-ca, sops operator Ready | T3 | |
| 5 `nixidy-bootstrap` | app-of-apps applies | T3 | `nixidy-bootstrap-local-k3d` already builds the bootstrap manifest at T1 |
| 6 `k3d-wait-argocd-sync` | ten Applications Healthy+Synced; Gateway Programmed | T3 | `Programmed` needs an LB address (F2) |
| 7 `k3d-test-coverage` (Chainsaw) | see below | T3 | Chainsaw runs in-guest (Q7) |
| — `k3d-configure-dns` | CoreDNS forwards `sslip.io` to `1.1.1.1` | K→T3 with substitution | needs network; replaced by a CoreDNS `hosts`/`template` answer inside the VM |
| — `k3d-bootstrap-secrets` | `sops-age-key` Secret exists | T3 with fixture | Q5 |

Chainsaw assertions (`kubernetes/tests/local-k3d/{foundation,infrastructure}/*.yaml`, ordered by `chainsaw-test.yaml:8-48`):

| Assertion | Tier | Substrate-only variant available at T2? |
|---|---|---|
| Cilium DaemonSet ready | T3 | no; T2 O-a asserts the node is `NotReady` for exactly the missing-CNI reason |
| Cilium operator ready | T3 | no |
| ArgoCD controller/server/repo-server/redis/applicationset ready | T3 | no |
| ArgoCD Applications adopted/Synced | T3 | the rendered Application objects and their `repoURL` are T1 |
| cert-manager controller/cainjector/webhook ready | T3 | no |
| step-ca StatefulSet ready | T3 | no |
| sops-secrets-operator Deployment ready | T3 | no |
| `ClusterIssuer/step-ca-acme` Ready=True | T3 | the ACME server URL and solver shape are T1 |
| `Gateway/main-gateway` Programmed=True | T3 | needs LB address (F2) |
| Gateway has four listeners, each Accepted=True | T3 | listener count and hostnames are T1 over the rendered Gateway |
| Certificates `argocd-tls`, `test-cert-tls` Ready=True | T3 | needs in-VM DNS for the sslip hostnames (Q4 B3) |
| HTTPRoute `argocd` Accepted=True | T3 | parentRef shape is T1 |

Properties no current assertion covers but the production module claims (`k3s-server/default.nix:83-100`, `kernel.nix`, `networking.nix`):

| Property | Tier |
|---|---|
| ExecStart carries every intended `--disable`/flag | T1 (nix-unit over `systemd.services.k3s.serviceConfig.ExecStart`) |
| `--cluster-cidr`/`--service-cidr` effective | T2 (`kubectl get node -o jsonpath={.spec.podCIDR}`; `kubectl get svc kubernetes` in 10.43.0.0/16) |
| flannel/kube-proxy actually absent | T2 (`ip link` shows no `flannel.1`/`cni0`; no `kube-proxy` process; `kubectl -n kube-system get ds` has no kube-proxy) |
| kernel modules loaded, sysctls applied | T2 (`lsmod`, `sysctl -n`) |
| firewall ports open, trusted interfaces | T2 (`nft list ruleset` or `iptables-save`) |
| kernel ≥ 5.10 with Cilium's required config | T1 for version; T2 for `zcat /proc/config.gz` bins from `system_requirements.rst:157-227` |
| `virtualisation.containerd` inert (F1) | T1 today; the eventual fix is a module change |
| unprivileged user cannot read the kubeconfig | T2 (`single-node.nix:87`) |
| `k3s-killall.sh` cleans up | T2 (`single-node.nix:98-108`) |
| two-node join, cross-node pod connectivity | T2 multi-node (Q3) |

## Q2: one-node design, `vm-k3s-single-node`

### Shape

One `perSystem.checks` leaf in a new `modules/checks/vm-k3s-single-node.nix`, following `modules/checks/vm-nixos-base.nix` from PR #2954 exactly: `nixosLib.runTest`, `imports = [ inputs.clan-core.modules.nixosTest.clanTest ]`, `extraPythonPackages = lib.mkForce (_: [ ])`, `clan.test.useContainers = false`, `clan.directory = pkgs.emptyDirectory`, one inventory machine, `system.stateVersion = config.system.nixos.release`, and the `boot.initrd.network.ssh` direct-boot workaround if `base` is imported.
The machine imports `config.flake.modules.nixos.k3s-server` unmodified and sets `k3s-server.enable = true; clusterInit = true; tokenFile = <fixture>`.
Whether it also imports `base` depends on whether fleet k3s nodes will import `base`; no k3s node exists yet, so this is D-S1.

The full QEMU regulator is warranted here rather than nspawn because the properties are kernel-level: loaded modules, sysctls, nftables, and a CNI-shaped network namespace.

### Options for a CNI

- O-a: no CNI. Assert the node exists and is `NotReady` with `.status.conditions[?(@.type=="Ready")].reason == "KubeletNotReady"` and a message containing `cni plugin not initialized`; assert CoreDNS stays `Pending`; assert every substrate property in the table above.
- O-b: ship Cilium. Add a test-only `services.k3s.autoDeployCharts.cilium` from the `cilium-src` input (or `services.k3s.manifests` from the rendered `kubernetes/modules/cilium` output) and preload `cilium`, `operator-generic`, and `cilium-envoy` via `services.k3s.images`; assert `Ready` and run the single-node pod test from `single-node.nix:90-92`.
- O-c: fetch Cilium at runtime. Rejected: the Nix build sandbox has no network, so no chart, image, or DNS lookup succeeds.

### Recommendation: O-a for `vm-k3s-single-node`, with O-b deferred to the platform leaf

O-a regulates exactly the artifact that is unregulated (F1): the module's own claims about the node.
It has no image closure beyond the ~236 MiB core bundle, boots in the time k3s itself needs, and every assertion is independent of Cilium's version.
Its `NotReady` assertion is deliberately narrow: `reason` and `message` are checked, not merely the condition, so a node that is `NotReady` for a different cause fails the test.
O-b in the single-node leaf would conflate two envelopes (substrate and CNI) in one regulator and pull a ~1 GiB-class image closure into the cheapest VM leaf; it belongs in the T3 leaf where the rest of the platform already requires those images.

### Sizing and wall time

Nixpkgs sizes k3s tests at `memorySize = 1536; diskSize = 4096` (`nixos/tests/rancher/default.nix:76-79`).
O-a runs the same workload as `single-node.nix` minus flannel, so the same numbers are the starting point; `diskSize` is raised to 8192 only if the images bundle plus `linuxPackages_latest` push the root image past 4 GiB, which the first build will show.
Expected wall time is the k3s-server startup (roughly 30–60 s to `kubectl get node` on a KVM host) plus the test-driver boot; the working estimate is two to four minutes per run, to be recorded from the first passing build.

### Integrity (mutation evidence)

The required mutation is a one-line change to the production module, for example removing `"--disable-kube-proxy"` from `k3s-server/default.nix`, which must make the kube-proxy absence assertion fail with its message; the second mutation removes `"br_netfilter"` from `kernel.nix:23` and must fail the `lsmod` assertion.
Both are recorded in the implementing PR body per PR #2954's convention.

## Q3: two-node design, `vm-k3s-multi-node`

### Shape

Two `clan.machines`: `server` (`role = "server"; clusterInit = true`) and `agent` (`role = "agent"; serverAddr = "https://server:6443"`), both importing `k3s-server` and sharing one `tokenFile`.
The test driver puts both on `virtualisation.vlans = [ 1 ]` (`nixos/lib/testing/network.nix:72`); nixpkgs' test uses `networking.primaryIPAddress` for `nodeIP` and `serverAddr` (`multi-node.nix:98`, `160-161`, `198-199`).
The production module does not expose `nodeIP`; if the agent needs it the leaf sets `services.k3s.nodeIP` directly, which is synthetic glue, not duplicated logic.

### Token delivery

- Store-path token, as nixpkgs does: `tokenFile = pkgs.writeText "token" "…"` (`multi-node.nix:60`, `93`, `155`, `193`). The file is world-readable in the store, which is acceptable only because the value is a test fixture that authorizes nothing outside the sandbox.
- Clan shared var: a `clan.core.vars.generators.k3s-token` with `share = true`, generated in-sandbox by clanTest's vars executor, encrypted to the test age key (`~/ghq/git.clan.lol/clan/clan-core/lib/clanTest/vars-executor.nix:165`, `231`), and consumed on both nodes as `config.clan.core.vars.generators.k3s-token.files.token.path`.

Recommendation: store-path token in the first multi-node leaf, Clan shared var once a production generator exists.
Today no k3s machine and no generator exist, so a shared var in the test would be inventing production shape inside a test, which the repository's invariant forbids.
When the production generator is written, the leaf switches to it and thereby regulates the generator too; that switch is a task in the OpenSpec plan, gated on D-S2.

### What it adds and costs

It adds the join path (`--server`, token acceptance, agent registration), the agent-role flag set (no `--cluster-cidr`/`--service-cidr`, per `k3s-server/default.nix:98-102`), and cross-node reachability of the k3s supervisor and kubelet ports through the production firewall rules.
Cross-node pod-to-pod connectivity as in `multi-node.nix:233-247` requires a CNI, so on the substrate leaf it reduces to node-level assertions (both nodes registered, both `NotReady` for the CNI reason, agent can reach `server:6443` and `server:10250`); pod connectivity moves to the T3 leaf when Cilium is present.
Cost is two VMs of the single-node size, roughly double the wall time and memory of Q2.

## Q4: platform stack

### Image and chart inventory

Charts rendered by nixidy/easykubenix from local sources (`kubernetes/modules/{cilium,argocd,step-ca,sops-secrets-operator}/default.nix`; Gateway API CRDs from the `gateway-api-src` input; cert-manager and the repository's own Gateway, HTTPRoute, ClusterIssuer, and Application objects): the rendered `local-k3d-ci` environment contains 146 files including 13 CRDs, 9 Deployments, 2 StatefulSets, 2 DaemonSets, 1 Job, 9 Applications, 1 Gateway, 1 HTTPRoute, 1 GatewayClass, 1 ClusterIssuer.
No chart is fetched at runtime; every chart is a Nix input already.

Images referenced by the rendered manifests:

| Image | Component |
|---|---|
| `quay.io/cilium/cilium:v1.18.6` | Cilium agent |
| `quay.io/cilium/operator-generic:v1.18.6` | Cilium operator |
| `quay.io/cilium/cilium-envoy:v1.35.9-…@sha256:81398e…` | Cilium Envoy (Gateway) |
| `quay.io/argoproj/argocd:v3.2.5` | ArgoCD (all components) |
| `ecr-public.aws.com/docker/library/redis:8.2.2-alpine` | ArgoCD redis |
| `quay.io/jetstack/cert-manager-{controller,webhook,cainjector,startupapicheck,acmesolver}:v1.21.1` | cert-manager |
| `cr.smallstep.com/smallstep/step-ca:0.30.0` | step-ca |
| `isindir/sops-secrets-operator:0.16.0` | sops-secrets-operator |
| `alpine/curl:latest` | a Job; unpinned |
| `docker.io/rancher/mirrored-pause:3.6`, `docker.io/rancher/mirrored-coredns-coredns:1.12.3` | k3s core, in the airgap bundle |

The `alpine/curl:latest` reference is a finding in itself: an unpinned tag cannot be preloaded reproducibly and must be pinned by digest before any T3 leaf is built.

Closure estimate: the k3s core bundle is 236 MiB compressed (built).
Cilium agent and Envoy images are the largest third-party items; registry metadata for step-ca, sops-secrets-operator, and Cilium could not be retrieved during this research (requests timed out).
The bound used for planning is 1.5–2.5 GiB compressed for the full platform, to be measured by `nix path-info -S` on the first `dockerTools.pullImage` set.
Each pulled image is a fixed-output derivation, so it is fetched once per digest and cached like any other input.

### Blockers to running the Chainsaw suite in a VM, and their hermetic substitutes

- B1 no network: every image preloaded (F4); every chart is already a Nix input.
- B2 `file:///manifests` repo: the k3d run mounts a host git repo into the node. In a VM the rendered environment is a store path; ArgoCD needs a git remote, so the node runs `git init --bare` over the store copy at activation, or serves it with `git daemon` on the node, and the `local-k3d-ci`-style target repository URL points at it. The T1 grep at `k3d-integration-ci.sh:63` continues to hold.
- B3 DNS for `*.192.168.100.3.sslip.io`: the ACME HTTP-01 solver (`kubernetes/nixidy/local-k3d/apps/cluster-issuer.nix:44-62`) requires step-ca to resolve the certificate hostnames (`argocd-route.nix:22`, `gateway.nix:25`) to the Gateway address; today CoreDNS forwards `sslip.io` to `1.1.1.1` (`modules/apps/cluster/k3d-configure-dns.sh:12`). In a VM CoreDNS must answer those names itself (a `hosts` or `template` stanza) and the hostnames must embed the VM node's address rather than k3d's `192.168.100.3`. This needs a nixidy environment variant for the VM, not the k3d one (D-P2).
- B4 LoadBalancer address for `Programmed=True` (F2): a test-only `CiliumLoadBalancerIPPool`, host-network Gateway mode, or ServiceLB re-enabled in the test. The choice should match the production intent (D-P1); a test that re-enables ServiceLB regulates the k3d envelope again, not production.
- B5 secrets: `SOPS_AGE_KEY` from GitHub Secrets is replaced by the Q5 fixture.
- B6 Chainsaw in the guest: `pkgs.chainsaw` exists in the locked nixpkgs (`pkgs/by-name/ch/chainsaw/package.nix:9`, 2.16.2); the test directory is a store path; see Q7 for kubeconfig handling.

None of these is a blocker in the sense of impossibility; each is work with a known shape.
What is genuinely lost is the check that the rendered tree can be consumed from a Docker volume mount and that the platform works on k3d's kube-proxy envelope — both properties of the k3d substrate, not of the platform.

### Options

- O-1: one `vm-k3s-platform` leaf boots one node with Cilium, ArgoCD, cert-manager, step-ca, sops-secrets-operator, and the Gateway, then runs the whole Chainsaw suite in-guest.
- O-2: several leaves each preloading a slice: `vm-k3s-cilium` (Cilium + Gateway API CRDs + Gateway Programmed via B4), `vm-k3s-gitops` (Cilium + ArgoCD sync from B2), `vm-k3s-pki` (Cilium + cert-manager + step-ca + ClusterIssuer + Certificates via B3), `vm-k3s-secrets` (Cilium + sops operator + fixture key).
- O-3: substrate leaves move; the platform Chainsaw suite stays on k3d/Docker permanently.

### Recommendation: O-1 first, O-2 only when measured cost demands it; O-3 rejected

The Chainsaw steps are ordered dependencies, not independent slices: Certificates need the ClusterIssuer, which needs step-ca and the Gateway solver, which needs Cilium and an LB address; ArgoCD manages all of them.
Splitting into O-2 duplicates Cilium's image closure in every leaf and re-creates the wait-for-ready scaffolding four times for the same envelope.
O-1 is one regulator for one envelope — the platform as deployed — and is what the k3d workflow already is, minus Docker.
O-2 becomes the right shape only if O-1's measured wall time exceeds what a developer will run locally (working threshold: 15 minutes), at which point `vm-k3s-cilium` splits off first because Gateway `Programmed` is the assertion most sensitive to the production/k3d envelope difference (F2).
O-3 is rejected because every blocker B1–B6 has a hermetic substitute; the only property that cannot move is a property of k3d itself, and the direction of record is to stop regulating the k3d envelope.
Retaining k3d until O-1 is green is the migration's containment, not its end state.

## Q5: secrets

### Design

The k3d bootstrap reads `SOPS_AGE_KEY` from the environment or `~/.config/sops/age/keys.txt` and creates the `sops-age-key` Secret in namespace `sops-secrets-operator` (`modules/apps/cluster/k3d-bootstrap-secrets.sh:7-19`).
The VM replacement is a test-only age keypair committed as a fixture, following clan-core: a public key baked into the test library (`~/ghq/git.clan.lol/clan/clan-core/lib/clanTest/flake-module.nix:94`) and a private key installed on the machine at activation from a fixture file (`lib/test/age.nix:6-7`, `21-27`, reading `nixosModules/clanCore/vars/tests/age-fixtures/key.txt`).
sops-nix's own VM tests do the same with `sops.age.keyFile = "/run/age-keys.txt"` (`~/ghq/github.com/Mic92/sops-nix/checks/nixos-test.nix:17`, `89`, `97-98`).

In this repository the fixture lives under `modules/checks/fixtures/` or a non-`modules/` path (it is not a `.nix` module and must not be auto-imported), and the rendered environment used by the T3 leaf encrypts its `SopsSecret` payloads to that public key instead of the production recipients.
That is a second reason for a VM-specific nixidy environment (D-P2): the encrypted payloads differ by recipient.
When clanTest is the harness, the alternative is a `clan.core.vars` generator with `share = true` whose output is encrypted by the in-sandbox executor to the clanTest public key (`vars-executor.nix:231`); either mechanism is hermetic, and the fixture-file variant has fewer moving parts until the fleet has k3s generators.

### What this does not cover

The fixture regulates that sops-secrets-operator decrypts a payload with a key present on the node.
It does not regulate production key provisioning, recipient lists in `.sops.yaml`, operator rotation, the GitHub Secret wiring, or that the production age key is where the production node expects it.
Those remain properties of the deployment path, regulated (where they are regulated at all) by clan vars checks of the kind clan-infra runs as a pure derivation (`~/ghq/git.clan.lol/clan/clan-infra/checks/vars.nix`).

## Q6: where it runs, and the migration

### Developer host

`just test-integration` (`justfile:663-670`) builds named `vm-*` checks today; PR #2954 makes it discover every `checks.<system>.vm-*` leaf, so new leaves need no recipe change.
The developer verifies KVM with `ls -l /dev/kvm` and `nix config show | grep system-features` first.

### GitHub Actions

Because F3 leaves hosted-runner KVM unverified, the first workflow change is a probe, not a rewiring: a manually dispatched job on `ubuntu-latest` that runs the udev rule from GitHub's own changelog, checks `/dev/kvm`, and builds `.#checks.x86_64-linux.vm-k3s-single-node` with `--option system-features 'kvm nixos-test benchmark big-parallel'`.
If it passes repeatedly, `test-cluster.yaml` gains a `vm` job alongside `integration`.
If it does not, the supported path is a KVM-capable runner (a larger GitHub-hosted runner class documented to expose it, or a self-hosted runner on a KVM host), and the design records that as D-C1.
`cached-ci-job` hashing continues to apply; the `hash-sources` list at `.github/workflows/test-cluster.yaml:57` would name `modules/checks/vm-k3s-*.nix`, `modules/nixos/k3s-server/**`, and the fixture path in place of `kubernetes/**` for the substrate job.
For a Nix check, the store path is the better cache key: `nix build` of an already-built derivation is a no-op, so the `cached-ci-job` layer is redundant once the derivation is in a binary cache.

### nixbot/buildbot

VM leaves remain under `lib.optionalAttrs pkgs.stdenv.hostPlatform.isLinux` and are unschedulable on a worker without `kvm`.
Whether the worker's job scheduler skips them or reports them as failed depends on how nixbot handles `requiredSystemFeatures` it cannot satisfy; the OpenSpec plan includes a task to observe this on the first push rather than assume it, and to filter them from the worker's evaluation if they surface as failures.
No non-VM check depends on a VM check.

### Stages and deletions

- Stage 0 (this record): ADR and OpenSpec change; nothing else.
- Stage 1: `vm-k3s-single-node` (O-a) plus the T1 leaf `k3s-server-eval` (nix-unit over the evaluated module) alongside the k3d workflow unchanged.
- Stage 2: `vm-k3s-multi-node` with store-path token.
- Stage 3: `vm-k3s-platform` (O-1) with the VM nixidy environment, LB address decision, DNS substitute, and age fixture; Chainsaw in-guest.
- Stage 4: KVM probe job; then `test-cluster.yaml` runs the VM leaves where KVM is available; then deletion.

Deleted at the end of stage 4: `modules/apps/cluster/k3d-integration-ci.sh`, `k3d-full.sh`, `k3d-up.sh`/`k3d-down.sh`/`k3d-deploy.sh` if present only for CI, `k3d-wait-ready.sh`, `k3d-wait-argocd-sync.sh`, `k3d-bootstrap-secrets.sh`, `k3d-configure-dns.sh`, `k3d-test-coverage.sh` and `scripts/k3d-test-coverage.sh`, the `integration` job and Docker steps in `.github/workflows/test-cluster.yaml`, the `SOPS_AGE_KEY` env line at `test-cluster.yaml:47`, the `local-k3d-ci` nixidy environment in `modules/nixidy.nix`, and the k3d-specific justfile recipes.
Whether `kubernetes/clusters/local-k3d/` itself is deleted depends on whether developers still want a k3d cluster for interactive work on Darwin, which the VM leaves cannot replace (D-C2).

## Q7: reference patterns cited

- NixOS test framework: `requiredSystemFeatures` at `nixos/lib/testing/run.nix:48-63`, `162`; VLANs at `nixos/lib/testing/network.nix:72`; driver API `succeed` (`nixos/lib/test-driver/src/test_driver/machine/__init__.py:479`), `wait_until_succeeds` (`516`), `wait_for_open_port` (`599`), `copy_from_host` (`783`), `forward_port` (`1516`).
- Nixpkgs k3s tests: sizing `nixos/tests/rancher/default.nix:76-79`; single-node assertions `single-node.nix:84-108`; multi-node topology and token `multi-node.nix:60`, `93-98`, `155-161`, `193-199`, script `233-247`.
- Nixpkgs k3s module: `role` (`rancher/default.nix:413`), `serverAddr` (`422`), `tokenFile` (`440`), `extraFlags` (`467`), `disable` (`491`), `nodeIP` (`515`), `manifests` (`533`), `containerdConfigTemplate` (`628-647`), `images` (`648-667`, linked at `854`), `gracefulNodeShutdown` (`668`), `autoDeployCharts` (`731`); `clusterInit` (`rancher/k3s.nix:86`, flag at `12`, agent assertion at `131-132`).
- clan-core clanTest: `useContainers` option (`lib/clanTest/flake-module.nix:220`), VM/container node split (`311-312`), mixed-mode hard fail (`297-298`), minify and age modules (`353-357`), shared-var encryption (`lib/clanTest/vars-executor.nix:165`, `231`); a multi-machine VM service test at `clanServices/zerotier/tests/vm/default.nix:5-7`.
- clan-infra: pure-derivation vars and toplevel checks (`checks/flake-module.nix`, `checks/vars.nix`); it runs no VM tests, which is consistent with a fleet whose CI host lacks KVM.
- hetzkube: kubeadm plus standalone containerd (`nixos/kubernetes.nix:17-27`), Cilium with `kubeProxyReplacement = true` and `routingMode = "tunnel"` (`kubenix/configuration/cilium.nix:72-93`); the source of the containerd settings found inert in F1.
- k3s: conditional CNI section (`pkg/agent/templates/templates.go:134-137`, `225-228`), flannel-path CNI dirs (`pkg/executor/embed/embed.go:184-185`).
- Chainsaw: the default cluster is loaded through `clientcmd.NewDefaultClientConfigLoadingRules()` (`pkg/utils/rest/config.go:12-19`, called at `pkg/commands/test/command.go:365`), so `KUBECONFIG=/etc/rancher/k3s/k3s.yaml chainsaw test <dir>` in the guest works with no flag; `--cluster name=<kubeconfig path>` (`command.go:456`) and the `--kube-*` override flags (`command.go:421`; `website/docs/reference/commands/chainsaw_test.md:16`, `36-47`) exist, `--no-cluster` at `command.go:460`. There is no `--kube-config` flag in this version. Running Chainsaw from the test driver via `forward_port` is possible but adds a host-side Chainsaw and a TLS SAN concern for nothing; in-guest is the design.
- Cilium: k3s install flags (`Documentation/installation/k3s.rst:28-40`); kernel `>= 5.10` and required config (`Documentation/operations/system_requirements.rst:23`, `40`, `144-147`, `157-227`); Gateway API requires `kubeProxyReplacement=true`, creates a LoadBalancer Service, needs the standard CRDs (`Documentation/network/servicemesh/gateway-api/installation.rst:5-16`); host-network mode (`host-network-mode.rst:15-20`); Programmed semantics (`operator/pkg/gateway-api/status_gateway_address.go:70-81`, `136`, `162`).
- Gateway API: standard CRDs under `config/crd/standard/`; conformance under `conformance/`.
- disko and sops-nix: `makeTest`-based VM tests (`disko/lib/tests.nix:90-92`; `sops-nix/checks/nixos-test.nix:17`, `89`).
- GitHub: nested virtualization statement and Android KVM changelog quoted in F3; `ubuntu-latest` image Ubuntu 24.04.4, kernel 6.17.0-1022-azure (runner-images release notes, retrieved 2026-09-04).

## Decisions requested before implementation

- D-S1: does a fleet k3s node import `base`? If yes, `vm-k3s-single-node` imports it too.
- D-S2: is a `k3s-token` clan vars generator with `share = true` going to be the production token path? If yes, stage 2 adopts it once written; otherwise store-path stays.
- D-P1: how does the production cluster assign Gateway LoadBalancer addresses — Cilium LB-IPAM pool, host-network Gateway, or ServiceLB re-enabled? The T3 leaf must match.
- D-P2: is a VM-specific nixidy environment (`local-vm`) acceptable, carrying the VM node hostnames, CoreDNS answer, `file://` repo path, and test-key recipients?
- D-C1: if the `ubuntu-latest` KVM probe fails or flakes, which runner is acceptable — a larger GitHub-hosted class or a self-hosted KVM runner?
- D-C2: does `kubernetes/clusters/local-k3d/` survive as a Darwin developer convenience after stage 4?
- D-M1: should the inert `virtualisation.containerd.settings` block (F1) be corrected in a separate module PR before stage 1, or left for the VM leaf to expose?

## Open questions

- Whether nixbot reports a `kvm`-requiring derivation as skipped or failed; observed in stage 1.
- Whether Cilium in the O-1 leaf needs any `pkgs.cni-plugins` binary at all in this configuration (F1's activation script).
- Exact compressed sizes of the step-ca, sops-secrets-operator, and Cilium images; measured when the pulls are written.
- Whether `diskSize = 4096` suffices with `linuxPackages_latest` and the core bundle; measured in stage 1.

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

## Related

- ADR-005: local cluster architecture revision (k3d + ctlptl), the envelope this record proposes to stop regulating in CI.
- ADR-006: nixidy manifest distribution, which fixes the `file:///manifests` pattern the T3 leaf reuses.
- `openspec/changes/k3s-nixos-vm-tests/`: the staged implementation plan.
- PR #2954: `vm-nixos-base`, the VM-leaf pattern followed here.
