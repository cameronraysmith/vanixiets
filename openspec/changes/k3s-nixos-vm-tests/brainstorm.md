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

## Q9 [decided]: is a VM-specific nixidy environment required?

Yes, pending D-P2.
Three things differ from `local-k3d-ci`: the hostnames embed the VM node address rather than `192.168.100.3`; CoreDNS must answer the `sslip.io` names itself instead of forwarding to `1.1.1.1`; `SopsSecret` payloads are encrypted to the test key.
Evidence: ADR-007 Q4 B3, Q5.

## Q10 [open]: which decisions must the human take before stage 1?

D-S1 whether fleet k3s nodes import `base`; D-S2 whether a shared `k3s-token` generator is the production token path; D-P1 how production assigns Gateway LoadBalancer addresses; D-P2 whether a `local-vm` nixidy environment is acceptable; D-C1 the fallback runner if the `ubuntu-latest` probe fails; D-C2 whether `kubernetes/clusters/local-k3d/` survives for Darwin developers; D-M1 whether the inert containerd block is fixed before stage 1 or exposed by it.

# Design trade-offs recorded

- Reusing the production deferred module unmodified means the test cannot set `nodeIP`, which the module does not expose; the multi-node leaf sets `services.k3s.nodeIP` directly as glue rather than adding an option speculatively.
- The O-a `NotReady` assertion is narrow by intent (reason and message), accepting brittleness against kubelet message wording in exchange for non-vacuity.
- The single platform leaf trades granular failure attribution for one envelope and one image closure; Chainsaw's own step names recover most of the attribution.
- Store-path tokens are world-readable in the store; acceptable only because the value authorizes nothing outside the sandbox, and stated as such.
