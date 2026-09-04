## Why

The production NixOS k3s module, `flake.modules.nixos.k3s-server`, is imported by no machine and no check, so nothing regulates it; its `virtualisation.containerd.settings` block has been inert since it was written and nothing noticed.
The one integration workflow the platform has, the k3d run in `.github/workflows/test-cluster.yaml`, keeps kube-proxy and ServiceLB and disables Cilium's kube-proxy replacement, so it regulates an envelope that differs from the production one exactly where Cilium's datapath and Gateway address assignment are concerned.
PR #2954 has established the repository's full QEMU/KVM regulator pattern and a KVM-capable developer host now exists, so the reason the k3d workflow was the only option no longer holds.
This change plans the staged replacement of that workflow by NixOS VM tests composed from the production module and by pure Nix checks, so that the platform's regulators point at the artifacts the fleet deploys.

## What Changes

This change is planning-only.
It records the research in ADR-007 (`docs/notes/development/kubernetes/decisions/ADR-007-nixos-vm-tests-for-k3s.md`) and writes the artifacts four later stages implement against; no check leaf, module edit, workflow edit, or deletion happens here.

**Stage 1 — substrate regulators for the k3s module**
A T1 check `k3s-server-eval` evaluates the module standalone and asserts its rendered `ExecStart` flags, kernel modules, sysctls, firewall ports, and that no host containerd is configured.
A T2 leaf `vm-k3s-single-node` boots one QEMU node importing `flake.modules.nixos.k3s-server` unmodified with no CNI and asserts the effective substrate: node registered and `NotReady` for exactly the missing-CNI reason, CoreDNS `Pending`, no flannel or kube-proxy artifacts, pod and service CIDRs in effect, modules loaded, sysctls applied, firewall rules present, kubeconfig unreadable by an unprivileged user, `k3s-killall.sh` cleans up.
A T1 leaf for the `local-k3d-ci` nixidy environment closes the one rendering gap F5 found.

**Stage 2 — multi-node join**
A T2 leaf `vm-k3s-multi-node` boots a `role = "server"` node and a `role = "agent"` node on one test-driver VLAN with a shared store-path token, and asserts both register, the agent carries no server-only flags, and the agent reaches the supervisor and kubelet ports through the production firewall.
It switches to a `clan.core.vars` shared generator only if the fleet adopts one (design D5).

**Stage 3 — platform stack in a VM**
One T3 leaf `vm-k3s-platform` preloads every image the rendered manifests reference through `services.k3s.images`, serves the rendered environment as a `file://` git remote on the node, answers the test hostnames from CoreDNS without network, supplies a Gateway LoadBalancer address by the mechanism production chooses, installs a test-only age key, and runs the existing Chainsaw suite in the guest.
A VM-specific nixidy environment carries the differences from `local-k3d-ci`.

**Stage 4 — execution and deletion**
A manually dispatched probe establishes whether `ubuntu-latest` can build a VM leaf under KVM.
If it can, `test-cluster.yaml` runs the VM leaves; if not, the fallback runner the human chooses does.
The buildbot worker leaves VM leaves unschedulable and nothing else fails because of it.
Once `vm-k3s-platform` is green in CI, the k3d integration scripts, the `integration` job, the `SOPS_AGE_KEY` wiring, the `local-k3d-ci` environment, and the k3d justfile recipes are deleted.

## Capabilities

### New Capabilities
- `k3s-substrate-vm-regulator` (stratum: `behavioral`): what the fleet requires of regulators for the NixOS k3s node substrate — that the production module is exercised unmodified, that each claimed node property is observed on a booted kernel rather than inferred from evaluation, that a missing CNI is detected for its actual reason, that a second node can join through the production firewall, and that each assertion is shown to fail under a mutation of the module it regulates.
- `k3s-platform-vm-regulator` (stratum: `behavioral`): what the fleet requires of a hermetic regulator for the deployed platform stack — that every image and chart is a build input, that the rendered GitOps tree is consumed the way the cluster consumes it, that certificate issuance completes without network, that Gateway address assignment matches production's mechanism, that secrets decrypt with a test-only key whose non-coverage of production key lifecycle is stated, and that the existing Chainsaw suite is the oracle.
- `k3s-integration-ci-execution` (stratum: `interface`): the properties at the CI and developer-host boundary — that VM leaves are independent `checks.<system>.vm-*` derivations requiring `kvm nixos-test`, discovered by `just test-integration`, built in CI only on a runner whose KVM has been probed, inert on the buildbot worker without failing anything else, and that the k3d scripts are deleted only after the platform leaf is green.

### Modified Capabilities
- `world-assumptions` (stratum: `world`): three assumptions are added — the Nix build sandbox has no network, GitHub-hosted runner nested virtualization is unsupported by the vendor, and a Gateway becomes Programmed only once an address is assigned.

## Impact

Implementation, in later changes, touches: new leaves `modules/checks/k3s-server-eval.nix`, `modules/checks/vm-k3s-single-node.nix`, `modules/checks/vm-k3s-multi-node.nix`, `modules/checks/vm-k3s-platform.nix`; a test-only age fixture outside `modules/`; a VM nixidy environment in `modules/nixidy.nix` and `kubernetes/nixidy/`; a pinned digest for the `alpine/curl:latest` reference; a probe job and then a `vm` job in `.github/workflows/test-cluster.yaml`; and the deletions listed in ADR-007 Q6.
Nothing under `modules/nixos/k3s-server/` is edited by this change or by the test stages; correcting the inert containerd block (F1) is a separate module change whose sequencing is design open question D-M1.
`kubernetes/clusters/local-k3d/` is retained for interactive Darwin development unless D-C2 decides otherwise.
