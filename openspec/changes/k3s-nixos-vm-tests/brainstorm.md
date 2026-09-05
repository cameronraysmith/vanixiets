<!--
Raw capture of the brainstorming step for this change.

Procedural note, recorded rather than elided: the interactive `superpowers:brainstorming`
dialogue was NOT run. This change was authored by a child session whose launch brief fixed
the questions to answer (Q1-Q7 of ADR-007) and instructed it to stop after publishing the
design as a draft PR. What follows is the decision log the interactive skill would have
produced. Answers fixed by the brief are marked `[given]`; answers taken from research
evidence are marked `[decided]`, with the evidence in ADR-007 cited by section; answers
that require the human are marked `[open]` and appear as D-codes in the ADR and as
Open Questions in design.md.

Second pass (2026-09-04): the human resolved the open questions and the wider design space
in a design review recorded in four notes (k3s-nixkube-decisions, k8s-architecture-current-
vs-nixified, oci-caph-timoni-decisions, cross-cloud-node-management). Answers taken from
those notes are marked `[reviewed]`; the original Q1-Q10 entries are kept as history and
annotated where superseded.
-->

# Background

The Kubernetes platform is verified by one GitHub Actions workflow, `.github/workflows/test-cluster.yaml`, which runs a k3d cluster in Docker on `ubuntu-latest` and drives `modules/apps/cluster/k3d-integration-ci.sh` through seven phases ending in a Chainsaw suite.
It was written when no KVM host was available for NixOS VM tests.
PR #2954 has since landed the pattern for full QEMU/KVM regulators in this repository (`modules/checks/vm-nixos-base.nix`) and made `just test-integration` build every `checks.<system>.vm-*` leaf.

Research for this change (ADR-007, `docs/notes/development/kubernetes/decisions/ADR-007-nixos-vm-tests-for-k3s.md`) established five findings that shape every decision below.
F1: `flake.modules.nixos.k3s-server` is imported by no machine and no check, and its `virtualisation.containerd.settings` block is inert because `virtualisation.containerd.enable` is never set.
F2: the k3d run keeps kube-proxy and ServiceLB and disables Cilium's kube-proxy replacement, so it regulates an envelope that differs from the production module's exactly where Cilium's datapath and LoadBalancer address assignment are concerned; Gateway `Programmed=True` depends on an address that ServiceLB supplies in k3d and nothing supplies in production.
F3: `nixosLib.runTest` requires `kvm nixos-test`; the buildbot worker has no KVM; GitHub documents nested virtualization on hosted runners as unsupported.
F4: the Nix sandbox has no network, so every OCI image is a build input; the k3s core bundle is 236 MiB compressed and the platform images are bounded at 1.5–2.5 GiB.
F5: manifest rendering already has T1 build checks.

# Decision chain

## Q1 [given]: is this change planning-only?

Yes.
No VM leaf, no check, no workflow edit, no k3d deletion lands here.
The change writes the artifacts that four later implementation stages are applied against.

## Q2 [decided]: which tier does each current assertion belong to?

Three tiers plus a residual class: T1 pure eval/build, T2 NixOS VM substrate, T3 live platform stack in a NixOS VM, K residual k3d.
Every current Chainsaw assertion is T3 because every one of them observes a live controller.
Every property the production k3s module claims about the node — flags, kernel modules, sysctls, firewall, CIDRs, absence of flannel and kube-proxy — is T1 for its evaluated form and T2 for its effective form.
Manifest rendering and the `file:///manifests` grep are T1.
Nothing is K once the six blockers in ADR-007 Q4 are given their hermetic substitutes.
Evidence: ADR-007 Q1 tables.

## Q3 [decided]: how does the single-node leaf get a CNI?

O-a: no CNI.
The single-node leaf regulates the substrate only and asserts the node is `NotReady` for exactly the missing-CNI reason with CoreDNS `Pending`.
O-b (ship Cilium via `autoDeployCharts` with preloaded images) conflates two envelopes in the cheapest VM leaf and pulls a GiB-class image closure into it; it is deferred to the T3 leaf where those images are needed anyway.
O-c (fetch at runtime) is impossible in the sandbox.
Evidence: ADR-007 Q2.

## Q4 [decided]: how many platform leaves?

O-1: one `vm-k3s-platform` leaf.
The Chainsaw steps form a dependency chain (Certificates need the ClusterIssuer, which needs step-ca and the Gateway solver, which needs Cilium and an LB address; ArgoCD manages all of them), so O-2's slice leaves would each preload Cilium and rebuild the same readiness scaffolding.
O-2 is the fallback if O-1's measured wall time exceeds 15 minutes, splitting `vm-k3s-cilium` first.
O-3 (platform stays on k3d permanently) is rejected because each blocker has a hermetic substitute; the only unmovable property is a property of k3d itself.
Evidence: ADR-007 Q4.

## Q5 [decided]: how is the multi-node token delivered?

Store-path token (`pkgs.writeText`) as nixpkgs does, until a production `clan.core.vars` generator exists.
Writing a `share = true` generator inside the test before production has one would invent production shape in a test.
The switch to the generator is a task gated on the human's answer to D-S2.
Evidence: ADR-007 Q3.

## Q6 [decided]: what replaces `SOPS_AGE_KEY`?

A committed test-only age keypair, installed at activation, modeled on clan-core's `lib/test/age.nix` and sops-nix's `checks/nixos-test.nix`.
The rendered environment for the VM encrypts `SopsSecret` payloads to the test public key.
What this does not cover is stated in the spec: production key provisioning, recipients, rotation, GitHub Secret wiring.
Evidence: ADR-007 Q5.

## Q7 [decided]: where does Chainsaw run?

In the guest.
`pkgs.chainsaw` exists in the locked nixpkgs; the default cluster loads through client-go's default rules so `KUBECONFIG=/etc/rancher/k3s/k3s.yaml chainsaw test <store path>` needs no flag; the `--cluster` and `--kube-*` flags exist for the alternative.
Running from the test driver via `forward_port` adds a host-side Chainsaw and a TLS SAN concern for no gain.
Evidence: ADR-007 Q7.

## Q8 [decided]: how does the CI runner question get settled?

By a probe job, not by assumption.
Stage 4 begins with a manually dispatched job on `ubuntu-latest` that grants `/dev/kvm` via the udev rule GitHub's own changelog shows, checks the device, and builds `vm-k3s-single-node` with `--option system-features 'kvm nixos-test benchmark big-parallel'`.
Only a repeatedly passing probe promotes the VM leaves into the workflow; a failing probe routes to D-C1.
Evidence: ADR-007 F3, Q6.

## Q9 [decided, superseded by Q11]: is a VM-specific nixidy environment required?

Originally yes, pending D-P2.
Superseded: nixidy is retired; the VM variant is a `target` of the easykubenix cluster module (design D9).

## Q10 [resolved]: which decisions must the human take before stage 1?

All seven were answered in the design review: D-S1 yes (`base` is imported); D-S2 not now (store-path token; production paths are named by the bootstrap seam, ADR-009 D9.8); D-P1 Cilium LB-IPAM; D-P2 superseded by easykubenix-only; D-C1 developer-KVM-only until a runner exists; D-C2 `local-k3d/` survives as management handler B; D-M1 re-scoped to delete the dead block and use `containerdConfigTemplate` only if NRI proves disabled.

## Q11 [reviewed]: which reconciler and which manifest framework?

Flux consuming a digest-pinned OCI artifact, bootstrapped from `services.k3s.manifests`; easykubenix is the only rendering framework, nixidy and the Phase-3/4 adoption split are retired, ADR-006 is reversed.
ArgoCD needs a git source and cannot pin by digest; Flux installs offline from `pkgs.fluxcd` and verifies signatures with a key from the closure.
Evidence: ADR-008 F8.1, D8.1, D8.10.

## Q12 [reviewed]: how are images and configuration packaged?

By consumer: `nix-snapshotter.buildImage` for Nix-native workloads on `nix`-snapshotter nodes; nix2container for portable images; a Nix derivation emitting an OCI image layout for Flux configuration, digest known in the sandbox, pushed by an `apps` effect that asserts digest equality.
Tags are the flake revision and are aliases only; every consumer uses a digest or a store path.
Evidence: ADR-008 F8.2, D8.4, D8.5, D8.7.

## Q13 [reviewed]: how does the VM leaf obtain the Flux artifact without a network?

An in-guest registry seeded from the store-resident OCI layout, as nix-snapshotter's push-and-pull test does; images are preloaded through `services.k3s.images` and never traverse the registry.
Evidence: ADR-008 F8.3, D8.6.

## Q14 [reviewed]: which container snapshotter?

k3s's embedded `--snapshotter nix` (nix-snapshotter is vendored in k3s); the production module gains `k3s-server.snapshotter` defaulting to `"nix"`; nixkube is not a flake input; runtime `flakeRef`/`nixExpr` are forbidden and rejected by the S0 purity leaf.
NRI behaviour is asserted in the substrate leaf, not assumed.
Evidence: ADR-007 F6, D7.1, D7.2, D7.8.

## Q15 [reviewed]: who manages nodes?

Cluster API with cluster-api-k3s and CAPH from day one; Terranix is only the seed/management-host provisioner (the interim Terranix-as-node-manager position is reversed).
Remote nodes boot a NixOS Hetzner snapshot labelled by flake revision in `airGapped` mode; a Nix-written `/opt/install.sh` shim starts `k3s.service` from `services.k3s.configPath`; no kubeadm.
The management cluster is a capability with two handlers (NixOS QEMU VM; k3d via ctlptl) behind one contract.
Evidence: ADR-009 F9.1–F9.4, D9.1–D9.7.

## Q16 [reviewed]: how is multi-cloud declared?

One easykubenix cluster module: cloud-invariant core plus a `platform` sum over `hetzner | gcp | aws | kubevirt` that alone owns `*Cluster`, `*MachineTemplate`, node image, CCM, optional CSI; unhandled provider is an evaluation error; a per-cloud CCM is mandatory because cluster-api-k3s defaults `cloud-provider=external`.
Evidence: ADR-009 D9.10, D9.11.

## Q17 [reviewed]: how are the networks arranged?

ZeroTier untouched and k8s nodes never join it; a dedicated Clan `wireguard` instance is the admin plane (API server, SSH, deploys, ClusterMesh API reachability, node join); Cilium WireGuard is the dataplane directly between node IPs with UDP 51871 allowlisted; cross-cloud is ClusterMesh between per-cloud clusters with disjoint PodCIDRs and never stretched etcd; no Crossplane, no Anthos.
Evidence: ADR-009 F9.6, F9.7, D9.12–D9.14.

## Q18 [reviewed]: how many stages?

Six: S0 purity/provenance (KVM-free), S1 substrate and snapshotter leaves, S2 `vm-k3s-platform`, S3 management handlers and the NoCloud-seeded bootstrap leaf, S4 two Hetzner nodes on explicit spend approval, S5 gcp/aws render-only variants.
Evidence: ADR-007 Q6.

## Q19 [open]: ambiguities found while folding the review in

Listed as A1–A9 in design.md Open Questions with recommendations; A9 (S4 spend) is never adopted by silence.

# Design trade-offs recorded

- Reusing the production deferred module unmodified means the test cannot set `nodeIP`, which the module does not expose; the multi-node leaf sets `services.k3s.nodeIP` directly as glue rather than adding an option speculatively.
- The O-a `NotReady` assertion is narrow by intent (reason and message), accepting brittleness against kubelet message wording in exchange for non-vacuity.
- The single platform leaf trades granular failure attribution for one envelope and one image closure; Chainsaw's own step names recover most of the attribution.
- Store-path tokens are world-readable in the store; acceptable only because the value authorizes nothing outside the sandbox, and stated as such.
- The `platform` sum is declared from day one but only `hetzner` executes; the render-only `gcp`/`aws` variants buy a stable seam at the cost of untested runtime differences until a second cloud is deployed.
- Delivering the root `OCIRepository` digest through `KThreesConfig.spec.files` keeps configuration changes off the snapshot at the cost of a control-plane machine rollout per digest bump (design A1).
- Keyed cosign is chosen over keyless because verification must work in a sandbox without Fulcio or Rekor; key rotation becomes a Clan vars concern.
