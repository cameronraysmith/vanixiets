## Context

The platform's only integration regulator is a k3d cluster in Docker driven by `modules/apps/cluster/k3d-integration-ci.sh` from `.github/workflows/test-cluster.yaml`.
The production NixOS k3s module `flake.modules.nixos.k3s-server` (`modules/nixos/k3s-server/`) has no regulator at all, and its k3d stand-in runs a different Cilium and load-balancer envelope.
The research behind this design is ADR-007 (VM regulators and stage plan), ADR-008 (reconciler and artifact transport), and ADR-009 (Cluster API node management and networking) under `docs/notes/development/kubernetes/decisions/`; their findings (F1–F6, F8.x, F9.x), decisions (D7.x, D8.x, D9.x), and risk tables (R8.x, R9.x) are cited by code below rather than restated.
The first revision of this design (ArgoCD from a nixidy tree, four stages) is superseded; ADR-007's provenance table maps each replacement to the design-review note that fixed it.

Constraints fixed by the repository:
- Each VM test is one independent, cacheable `perSystem.checks` leaf named `vm-<subject>`, under `lib.optionalAttrs pkgs.stdenv.hostPlatform.isLinux`, built through `nixosLib.runTest` with the clanTest module exactly as `modules/checks/vm-nixos-base.nix` does (PR #2954).
- Machines under test import production deferred modules unmodified; a module that cannot be composed into a test is a finding about the module.
- `nixosLib.runTest` requires `kvm nixos-test`; the buildbot worker exposes neither and this is intentional.
- The Nix build sandbox has no network; no check opens a connection outside itself, and anything that must (registry push, snapshot upload) is an `apps` effect.
- Every runtime assertion is shown non-vacuous by a recorded mutation of the artifact it regulates.
- No new flake input is added for this change; nixkube in particular is not an input (ADR-007 D7.1).

The standalone evaluation that grounds F1 and the S0 `k3s-server-eval` leaf:

```nix
let
  flake = builtins.getFlake "git+file:///home/ubuntu/repos/vanixiets";
  sys = flake.inputs.nixpkgs.lib.nixosSystem {
    system = "x86_64-linux";
    modules = [
      flake.modules.nixos.k3s-server
      {
        k3s-server = { enable = true; clusterInit = true; tokenFile = "/tmp/token"; };
        system.stateVersion = "25.11";
      }
    ];
  };
  c = sys.config;
in {
  containerdEnabled = c.virtualisation.containerd.enable;          # false
  containerdEtc = c.environment.etc ? "containerd/config.toml";     # false
  k3sExecStart = c.systemd.services.k3s.serviceConfig.ExecStart;    # see ADR-007 F1
  k3sTemplate = c.services.k3s.containerdConfigTemplate;            # null
  k3sImages = map (i: i.name) c.services.k3s.images;                # [ ]
  tcp = c.networking.firewall.allowedTCPPorts;                      # [2379 2380 4240 4244 6443 10250]
}
```

## Goals / Non-Goals

Goals:
- Give `flake.modules.nixos.k3s-server` regulators at the cheapest sufficient tier for each property it claims (ADR-007 Q1), including the `nix` snapshotter and NRI state.
- Re-express every current Chainsaw assertion as a hermetic assertion against the production envelope — Flux from a digest-pinned OCI artifact, easykubenix rendering, Cilium LB-IPAM — not the k3d one.
- Regulate the rendered tree and its artifacts without KVM (purity, preload coverage, provenance, pinned sources, cloud-invariant rendering, CCM presence, ClusterMesh preconditions) so the buildbot worker regulates every push.
- Regulate the Cluster API bootstrap seam (NoCloud seed, `/opt/install.sh` shim, `services.k3s.configPath`) in a VM before any cloud is touched.
- Make the KVM runner question an observed fact before any VM leaf gates CI.
- End with the k3d integration scripts, the nixidy tree, ArgoCD, and sops-secrets-operator deleted.

Non-goals:
- Implementing any leaf, module option, easykubenix module, Flux artifact, CAPI CR, Clan `wireguard` instance, or cloud resource in this change.
- Regulating production key provisioning, recipients, rotation, or GitHub Secret wiring (ADR-007 Q5).
- Replacing k3d as an interactive Darwin developer cluster or as management handler B (ADR-009 D9.4).
- Cross-cloud ClusterMesh deployment; only its eval-time preconditions are regulated here (ADR-009 D9.13).
- Any change to the buildbot worker's feature set.

## Decisions

### D1: Five tiers, assigned per assertion, with k3d surviving only as management handler B

Every current phase and assertion is placed at T1 (pure eval/build), T2 (VM substrate), T3 (VM platform), E (effect, never a check), or K (k3d, only the ctlptl recipes as management handler B) per the ADR-007 Q1 table.
The k3d-only properties — Docker volume mount consumption and behavior under kube-proxy plus ServiceLB — are properties of k3d, not of the platform, and are dropped.
Alternative considered: a permanent k3d residue for the platform suite (O-3); rejected because every blocker in ADR-007 Q4 has a hermetic substitute.

### D2: The single-node leaf ships no CNI and asserts the snapshotter and NRI (O-a)

`vm-k3s-single-node` imports `k3s-server` with `enable`, `clusterInit`, and a store-path `tokenFile`, and asserts the substrate table in ADR-007 Q1: `NotReady` with `reason == "KubeletNotReady"` and a message containing `cni plugin not initialized`, CoreDNS `Pending`, the generated containerd config containing `[plugins."io.containerd.snapshotter.v1.nix"]`, `ctr plugins ls` showing the `nix` snapshotter `ok`, and NRI's state recorded as an observation (ADR-007 F6; the design does not assume it).
Sizing starts at nixpkgs' `memorySize = 1536; diskSize = 4096` and is raised only when the first build shows it short.
Alternative: O-b, Cilium via `autoDeployCharts`; deferred to D6 because it would place a GiB-class closure and a second envelope in the cheapest VM leaf.
The node imports `base` (ADR-007 D7.11).

### D3: A T1 leaf regulates the evaluated module, and S0's T1 leaves regulate the rendered tree

`k3s-server-eval` asserts the evaluated `ExecStart` contains each intended flag including `--snapshotter nix`, that `pkgs.nix` is on the unit path, that `virtualisation.containerd.enable` is `false` and no `/etc/containerd/config.toml` is produced, and that kernel modules, sysctls, and firewall lists match the module's declarations.
`k8s-manifest-purity`, `k8s-images-preloaded`, `k8s-closure-provenance`, `flux-sources-pinned`, and `flux-install-rendered` are `runCommand` leaves over the easykubenix-rendered tree (ADR-008 D8.11, D8.12, D8.4, D8.2).
`capi-cloud-invariant-render`, `capi-platform-sum-total`, `capi-ccm-present`, and `clustermesh-preconditions` are nix-unit or `runCommand` leaves over the cluster module's evaluation (ADR-009 D9.10–D9.13).
All of these run on the buildbot worker.
When the module change deletes the inert containerd block, `k3s-server-eval`'s containerd assertion flips to assert the corrected shape; the flip is the mutation evidence.

### D4: Multi-node adds the join path only

`vm-k3s-multi-node` boots `server` and `agent` on one VLAN with a shared store-path token and asserts registration of both nodes, that the agent's `ExecStart` carries `--server=` and no `--cluster-cidr`/`--service-cidr`, and that `agent` reaches `server:6443` and `server:10250` through the production firewall.
`services.k3s.nodeIP` is set directly on each machine as glue because the production module does not expose it.
Pod-to-pod connectivity as in nixpkgs' `multi-node.nix` needs a CNI and is asserted in D6's leaf.

### D5: Store-path token in VM leaves; the bootstrap-identity seam names the production paths

The token is `pkgs.writeText`, as nixpkgs does, world-readable in the store and authorizing nothing outside the sandbox.
The production module's `k3s-server.bootstrap` option (ADR-009 D9.8) takes `clan-vars` (token from a shared Clan vars generator) or `cloud-init` (token from the CAPI-generated `/etc/rancher/k3s/config.yaml`); VM leaves exercise both variants with test fixtures and never invent production shape.

### D6: One platform leaf, Flux from an in-guest registry, in-guest Chainsaw (O-1)

`vm-k3s-platform` boots one node importing `base` and `k3s-server`, preloads every image the rendered tree references through `services.k3s.images` (the set is derived from the tree by string context, ADR-008 D8.11), applies Cilium and the Flux install through `services.k3s.manifests`, runs a registry in the guest seeded from the sandbox-built OCI layout (ADR-008 D8.6), renders the root `OCIRepository` with that layout's digest and a `spec.verify` public key from a test-only cosign pair, and runs `chainsaw test` from a store path with `KUBECONFIG=/etc/rancher/k3s/k3s.yaml`.
The ArgoCD assertions in the Chainsaw suite become `Kustomization` `Ready=True` and `status.lastAppliedRevision` equal to the pinned digest.
Wait-for-ready logic is the Chainsaw suite's own timeouts.
Alternative: O-2 slice leaves; taken only if O-1's measured wall time exceeds 15 minutes, splitting `vm-k3s-cilium` first.

### D7: The VM's DNS and Gateway address are hermetic and production-shaped

CoreDNS answers the certificate hostnames itself through a `hosts` or `template` stanza in the rendered tree's VM variant, replacing the `sslip.io` forward to `1.1.1.1`.
The Gateway LoadBalancer address is supplied by a `CiliumLoadBalancerIPPool` declared by the cluster module (ADR-007 D7.9); ServiceLB stays disabled.

### D8: Test-only age and cosign keys installed at activation

A committed test age keypair and cosign keypair (outside `modules/`) are installed to the node at activation, as clan-core's `lib/test/age.nix` and sops-nix's `checks/nixos-test.nix` do; the VM variant of the rendered tree encrypts its SOPS payloads to the age public key and the in-guest artifact is signed with the cosign private key.
Production uses per-cluster Clan vars generators for both (ADR-008 D8.9, D8.14); the uncovered production properties are listed in the `k3s-platform-vm-regulator` spec.

### D9: easykubenix only; a VM variant of the cluster module, not a nixidy environment

The rendered tree is produced by one easykubenix cluster module with a `platform` sum (ADR-009 D9.10) and a `target` that selects VM fixtures (hostnames, CoreDNS answer, registry URL, key material) from production values.
No nixidy environment is created; `modules/nixidy.nix` and `kubernetes/nixidy/` are deleted when the k3d workflow is (D12).
Supersedes the first revision's `local-vm` nixidy environment.

### D10: The CAPI bootstrap seam is regulated by a NoCloud-seeded leaf and a management-cluster leaf

`vm-k3s-capi-bootstrap` boots a `bootstrap = "cloud-init"` node with a sandbox-built `cidata` ISO whose `write_files` and `runcmd` are rendered by a Nix function mirroring cluster-api-k3s' `controlplane_init.go` template in `airGapped` mode, and asserts the shim starts `k3s.service`, writes the sentinel file, and `kubectl get nodes` lists the node (ADR-009 D9.9).
`vm-capi-management` boots handler A (the k3s node closure), installs CAPI core, CAPH, and cluster-api-k3s from Nix-rendered manifests through a `clusterctl.yaml` override, applies the rendered `Cluster` CRs with a fake or absent Hetzner credential, and asserts the objects are accepted and the `KThreesControlPlane` reaches the state that waits on infrastructure (ADR-009 D9.4, R9.c).
Neither leaf touches a cloud.

### D11: The CI runner is probed, then chosen

A manually dispatched job on `ubuntu-latest` applies the udev rule GitHub's changelog shows, checks `/dev/kvm`, and builds `vm-k3s-single-node` with `--option system-features 'kvm nixos-test benchmark big-parallel'`.
Three consecutive passes promote the VM leaves into `test-cluster.yaml`; any failure leaves VM leaves as developer-host regulators through `just test-integration` until a KVM-capable runner exists (ADR-007 D7.10).

### D12: Deletion is the last step and is gated on green

The k3d integration scripts, the `integration` job, the `SOPS_AGE_KEY` env line, the `local-k3d-ci` environment, `modules/nixidy.nix`, `kubernetes/nixidy/`, the k3d integration justfile recipes, ArgoCD, and sops-secrets-operator are deleted in one commit after `vm-k3s-platform` has passed on the chosen runner and the first Flux SOPS cutover has converged.
`kubernetes/clusters/local-k3d/` and the ctlptl recipes survive as management handler B (ADR-007 D7.13, ADR-009 D9.4).

### D13: S4 spends money and starts only on explicit words

The Hetzner stage uploads a snapshot, creates two servers, and rolls one; it is never started from a recommendation adopted by silence.
Its rollback is `clusterctl delete cluster` plus snapshot deletion, recorded in the S4 runbook.

## Risks / Trade-offs

- R1 kubelet message wording: the O-a `NotReady` assertion checks the message text, which a kubelet upgrade may change. Mitigation: assert `reason` and a short substring.
- R2 platform closure size: bounded at 1.5–2.5 GiB compressed, not measured. Mitigation: `k8s-closure-provenance` reports it in S0; if S2 wall time exceeds 15 minutes, apply O-2.
- R3 hosted-runner KVM: unsupported by the vendor; may flake. Mitigation: D11's probe; VM leaves never gate a merge from a runner that has not passed it.
- R4 buildbot behavior on `kvm`-requiring derivations is unobserved. Mitigation: observe on S1's first push and filter if they surface as failures.
- R5 NRI behavior under root k3s with the `nix` snapshotter is inferred from the template, not observed (ADR-007 F6). Mitigation: D2 records it; `containerdConfigTemplate` is introduced only if the observation shows NRI disabled (ADR-007 D7.8).
- R6 OCI-layout digest equality across push tools is inferred (ADR-008 R8.c). Mitigation: S2 proves it against the in-guest registry with the same tool the `apps` effect uses; S4's first push asserts it against GHCR.
- R7 cluster-api-k3s and CAPH have not been run together by anyone in the reference set (ADR-009 R9.c). Mitigation: `vm-capi-management` accepts both providers and the rendered CRs in S3; S4 is the first real reconciliation and is sized as two nodes so that failure is cheap.
- R8 NixOS boot from a CAPI NoCloud seed through the shim is unverified (ADR-009 R9.d). Mitigation: `vm-k3s-capi-bootstrap` in S3 before any cloud spend.
- R9 the `platform` sum is total by construction but only `hetzner` is executed; `gcp`/`aws` are render-only (S5) and may hide runtime differences (CCM flags, CSI). Accepted: the seam's value now is that it is declared; runtime coverage arrives with the first non-Hetzner deployment.
- R10 store-path token and test keys are readable by every sandbox process. Accepted: they authorize nothing outside the test.
- R11 the UDP 51871 allowlist is derived from an eval-time node set that changes on CAPI rolls (ADR-009 R9.h). Mitigation: a T1 assertion that the allowlist and the `MachineDeployment` replica set derive from one value.

## Migration Plan

1. S0 lands the T1 leaves listed in D3 and the CAPI rendering leaves against an initial easykubenix cluster module with only `platform = hetzner` implemented; the k3d workflow is untouched.
2. A separate module change adds `k3s-server.snapshotter`, `k3s-server.bootstrap`, and `pkgs.nix` on the unit path, and deletes the inert containerd block; `k3s-server-eval` flips with it.
3. S1 lands `vm-k3s-single-node`, `vm-k3s-nix-workload`, and `vm-k3s-multi-node`; mutation evidence for two assertions per leaf is in the PR body; unchanged workflow.
4. S2 lands the OCI-layout derivation, the Flux install derivation, the age and cosign fixtures, the LB-IPAM pool, the Chainsaw assertion replacements, `vm-k3s-platform`, and the `push-cluster-artifact` effect (not run); unchanged workflow.
5. S3 lands the shim, the NoCloud renderer, `vm-k3s-capi-bootstrap`, the Nix-rendered CAPI provider manifests and `clusterctl.yaml`, `vm-capi-management`, and the handler A/B `just` recipes; unchanged workflow.
6. S4, on explicit approval: snapshot upload effect, Clan `wireguard` admin-plane instance, first `push-cluster-artifact` run, two Hetzner nodes, one flake-bump roll; runbook, not a check.
7. S5 lands `gcp` and `aws` variants as golden renders.
8. Execution: the KVM probe job; promotion of VM leaves into `test-cluster.yaml` on a passing runner; then the D12 deletion commit.

Rollback at any stage is deletion of the stage's leaves or objects; the k3d workflow keeps running until step 8's deletion commit, which is separate from the promotion commit.

## Gate 1 modality verdicts

No requirement in this change's delta specs routes to a Gherkin scenario, so no `.feature` file is laid out.
The repository has no BDD runner, and every observable here is an evaluated Nix value (witnessed by `nix eval`/nix-unit/`runCommand`), a test-driver assertion inside a QEMU guest (witnessed by `nixosLib.runTest`), an `apps` effect's exit status, or a CI job outcome.
`world`-stratum requirements are witnessed by their own violation conditions; `interface`-stratum requirements by the derivation attributes and job results named in their scenarios.

## Open Questions

Ambiguities found while folding the design review into this change; each carries a recommendation, and silence adopts it except where marked.

- A1 `KThreesConfig.spec.files` as the root `OCIRepository` carrier (ADR-009 D9.7) means a configuration-digest bump is a control-plane rollout, not a Flux-only change; the review says "flake bump rolls nodes" and also "digest delivered via files". Recommended: keep D9.7; accept that a digest change rolls control-plane machines, and document that worker `MachineDeployment`s do not roll because the file is control-plane-only.
- A2 `services.k3s.role` is fixed at evaluation, so one image cannot serve server and agent (ADR-009 D9.3). Recommended: per-role snapshots, two `caph-image-name` labels, one closure each; the two-unit alternative complicates the shim for no gain at two nodes.
- A3 the review names both `vm-k3s-platform` (S2) and "the VM leaf regulates the CAPI path by seeding a NoCloud datasource" (D28) without saying whether these are one leaf. Recommended: two leaves, `vm-k3s-platform` and `vm-k3s-capi-bootstrap`, because the second adds cloud-init to the closure and must fail independently.
- A4 which registry implementation seeds the in-guest OCI layout (ADR-008 D8.6): `pkgs.docker-distribution`, `zot`, or a static file server that speaks the distribution API. Recommended: `docker-distribution` from nixpkgs, as nix-snapshotter's push-and-pull test uses.
- A5 whether the Clan `wireguard` admin plane is created in S3 (so `vm-capi-management` can regulate the `tls-san` ULA) or S4. Recommended: S4; in S3 the leaves use test-driver VLAN addresses and the ULA assertion is a `k3s-server-eval` string check.
- A6 the `platform` sum lists `kubevirt` but no stage implements it. Recommended: reserve the name, render nothing, and make selecting it an evaluation error with a "not implemented" message distinct from the unhandled-provider error.
- A7 Chainsaw's ArgoCD assertions are replaced by Flux ones; whether the cert-manager, step-ca, and Gateway assertions are kept as-is. Recommended: kept unchanged until the Nix-image ports of step-ca and cert-manager (ADR-007 D7.5), which change image references only.
- A8 delta-spec numbering: the `world-assumptions` additions are numbered A13–A18 assuming the two unmerged changes that add A9–A12 land first. Recommended: renumber at sync if not.
- A9 S4 requires explicit spend approval (D13); this is not adopted by silence.
