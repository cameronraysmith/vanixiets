## Context

The platform's only integration regulator is a k3d cluster in Docker driven by `modules/apps/cluster/k3d-integration-ci.sh` from `.github/workflows/test-cluster.yaml`.
The production NixOS k3s module `flake.modules.nixos.k3s-server` (`modules/nixos/k3s-server/`) has no regulator at all, and its k3d stand-in runs a different Cilium and load-balancer envelope.
The research behind this design is ADR-007 (VM regulators and stage plan), ADR-008 (reconciler and artifact transport), ADR-009 (Cluster API node management and networking), and ADR-010 (identity tiers and bootstrap levels) under `docs/notes/development/kubernetes/decisions/`; their findings (F1–F6, F8.x, F9.x, F10.x), decisions (D7.x, D8.x, D9.x, D10.x), and risk tables (R7.x, R8.x, R9.x, R10.x) are cited by code below rather than restated.
Revision 2 of this design (2026-09-04, scope review; numbered as the ADRs number it — the initial #2955 draft, then the D1–D31 fold as revision 1, then this) narrows every property to one new sibling cluster `kubernetes/clusters/cryolite`; the frozen prototypes `local` and `local-k3d` keep ArgoCD, nixidy, sops-secrets-operator, kube-proxy, and the k3d workflow, and no artifact in this change edits them.
Stages S3–S5 live in `openspec/changes/capi-hetzner-cluster/`, which depends on this change; decisions that belonged to those stages in revision 1 are marked moved below rather than deleted.
The charter-v1 fold of the same day (ADR-007 D7.20–D7.22) names the cluster `cryolite`, fixes the in-guest registry, and closes A4, A10, A11, and A12 below; the programme-level view is `docs/notes/development/kubernetes/cryolite-charter.md`.

Constraints fixed by the repository:
- Each VM test is one independent, cacheable `perSystem.checks` leaf named `vm-<subject>`, under `lib.optionalAttrs pkgs.stdenv.hostPlatform.isLinux`, built through `nixosLib.runTest` with the clanTest module exactly as `modules/checks/vm-nixos-base.nix` does (PR #2954).
- Machines under test import production deferred modules unmodified; a module that cannot be composed into a test is a finding about the module.
- `nixosLib.runTest` requires `kvm nixos-test`; the buildbot worker exposes neither and this is intentional.
- The Nix build sandbox has no network; no check opens a connection outside itself, and anything that must (registry push, snapshot upload) is an `apps` effect under `modules/apps/k8s/`.
- Every runtime assertion is shown non-vacuous by a recorded mutation of the artifact it regulates.
- No new flake input is added for this change; nixkube in particular is not an input (ADR-007 D7.1).
- Existing files grow only additively through default-off options or lose only dead code (ADR-007 D7.15): `modules/kubernetes.nix` (`evalCluster` gains `cryolite`), `modules/nixos/k3s-server/default.nix` (`snapshotter` option; inert containerd block deleted), `modules/devshells/kubernetes.nix` (flux, clusterctl, hcloud, cosign, crane).

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

## Target module layout

This tree is the single record of where the `cryolite` architecture lives (ADR-007 D7.17); the sibling change references it rather than restating it.
`[keep]` paths are untouched by either change; `[add]` paths are new and dendritically additive, so deleting them makes `cryolite` disappear with no other edit; `[+opt]` paths are existing files that gain a default-off option or lose dead code.
Stage annotations name the stage that lands the path; unannotated `[add]` paths under `modules/kubernetes/` and `kubernetes/modules/flux/` land in S0 or S2 of this change, and `capi/`, `hetzner/`, `platform/`, and `capi-bootstrap.nix` land in the sibling change.

```text
modules/
  kubernetes.nix                        [+opt] evalCluster gains cryolite
  nixidy.nix                            [keep]
  kubernetes/                           [add]
    README.md
    artifacts.nix                       k8s-manifests-cryolite, k8s-oci-cryolite (OCI image-layout drv; digest = build output)
    oci-lib.nix                         mkOciLayout, mkNixSnapshotterImage, readDigest
    purity.nix                          checks.k8s-purity-cryolite (S0)
    provenance.nix                      checks.k8s-provenance-cryolite (S0)
    identity.nix                        checks.k8s-node-identity-free-cryolite (S0/S3)
    flux/install.nix  flux/root.nix
    capi/providers.nix  capi/management.nix (apps.k8s.mgmt-k3d; vm handler later)  capi/render.nix
    hetzner/image.nix  hetzner/snapshot.nix
  nixos/
    k3s-server/{default.nix [+opt], kernel.nix, networking.nix, packages.nix [keep], snapshotter.nix [add], capi-bootstrap.nix [add]}
    k3s-flux.nix                        [add]
  machines/nixos/cryolite-server.nix, cryolite-agent.nix   [add] image-only, role fixed at build
  checks/
    vm-nixos-base*.nix                  [keep]
    vm-k3s-substrate.nix  vm-k3s-snapshotter.nix     [add S1]
    vm-k3s-platform.nix                 [add S2]
    vm-k3s-capi-bootstrap.nix           [add S3]
    k8s-capi-render.nix                 [add S3/S5]
  apps/cluster/                         [keep]
  apps/k8s/                             [add] oci-push, cosign-sign, hetzner-snapshot-publish, clusterctl-init/move
  devshells/kubernetes.nix              [+opt]
kubernetes/
  modules/{cluster-options.nix, lib/, argocd/, cilium/, sops-secrets-operator/, step-ca/}  [keep]
  modules/flux/  modules/capi/  modules/platform/{default,hetzner,gcp(S5),aws(S5),kubevirt(throws)}.nix  [add]
  clusters/local/  clusters/local-k3d/  [keep, untouched]
  clusters/cryolite/{default.nix, topology.nix}  [add]
  nixidy/local-k3d/                     [keep]
  tests/local-k3d/                      [keep]
  tests/cryolite/                            [add]
secrets/clusters/cryolite/                   [add]
```

Rationale, one line each (ADR-007 D7.17):
- Two module systems, deliberately not merged: `modules/` is the flake-parts export system, `kubernetes/` is easykubenix cluster content, and `modules/kubernetes.nix` is the single bridge. Boundary: first-party on both sides; the bridge is the only place the two vocabularies meet.
- Dendritic additivity: every `[add]` path is reachable only from `evalCluster`'s `cryolite` entry, so removing the `[add]` set removes the cluster.
- One evaluation, one hash chain: `clusters/cryolite` → `k8s-manifests-cryolite` → `k8s-oci-cryolite` digest → `k3s-flux.nix` pins the digest → `cryolite-server` closure → snapshot label → `capi-cryolite` CRs.
- Variance placement: per-cloud Kubernetes objects live in `kubernetes/modules/platform/` as a typed sum; per-cloud NixOS content lives in `modules/kubernetes/<provider>/`.
- Flux normalized to Nix-first: the Flux layout is the contents of the OCI artifact; Flux keeps fetch, server-side apply, prune, drift detection, ordering, SOPS, and notification, and loses self-install, `postBuild` substitution, and git sources.
- Checks are leaves by kind: `vm-*` is KVM runtime, `k8s-*` is KVM-free evaluation or golden.
- Effects live only under `modules/apps/k8s/`; no check reaches one.

## Goals / Non-Goals

Goals:
- Give `flake.modules.nixos.k3s-server` regulators at the cheapest sufficient tier for each property it claims (ADR-007 Q1), including the `nix` snapshotter and NRI state.
- Regulate the `cryolite` core — Cilium with kube-proxy replacement, Flux from a digest-pinned OCI artifact, easykubenix rendering, Cilium LB-IPAM, cert-manager and step-ca — in a hermetic two-guest VM against the production envelope.
- Regulate the rendered `cryolite` tree and its artifacts without KVM (purity, preload coverage, provenance, node-identity freedom, pinned sources) so the buildbot worker regulates every push.
- Make the KVM runner question an observed fact before any VM leaf gates CI.
- Leave the frozen prototypes and the k3d `integration` job running unchanged.

Non-goals:
- Implementing any leaf, module option, easykubenix module, Flux artifact, or fixture in this change.
- Regulating production T0 key provisioning, recipients, rotation, or Clan vars generation (ADR-007 Q5, ADR-010 D10.1); the VM leaf uses fixtures and says so.
- Cluster API rendering, the management-cluster handler, the NoCloud bootstrap leaf, Hetzner images, the admin overlay, or cloud variants — sibling change.
- Migrating, editing, or deleting `local`, `local-k3d`, nixidy, ArgoCD, sops-secrets-operator, or the k3d workflow — Future Work in a separately authorized feedback change.
- Any change to the buildbot worker's feature set.

## Decisions

Revision-3 status is given in brackets: `[kept]`, `[narrowed]` (now `cryolite`-only), `[moved]` (to the sibling change), or `[superseded]` with the replacing decision.

### D1: Five tiers, assigned per assertion [narrowed]

Every assertion of the `cryolite` core is placed at T1 (pure eval/build), T2 (VM substrate), T3 (VM platform), E (effect, never a check), or K (k3d, only as the sibling change's management handler B) per the ADR-007 Q1 table.
The k3d-only properties — Docker volume mount consumption and behavior under kube-proxy plus ServiceLB — are properties of `local-k3d`, stay regulated by its own workflow, and are not properties of `cryolite`.
Revision 1 read "k3d surviving only as management handler B"; revision 2 keeps `local-k3d` as a frozen prototype in its own right (ADR-007 D7.15).
Alternative considered: a permanent k3d residue for the `cryolite` suite (O-3); rejected because every blocker in ADR-007 Q4 has a hermetic substitute.

### D2: The single-node leaf ships no CNI and asserts the snapshotter and NRI (O-a) [kept]

`vm-k3s-substrate` imports `k3s-server` with `enable`, `clusterInit`, and a store-path `tokenFile`, and asserts the substrate table in ADR-007 Q1: `NotReady` with `reason == "KubeletNotReady"` and a message containing `cni plugin not initialized`, CoreDNS `Pending`, the generated containerd config containing `[plugins."io.containerd.snapshotter.v1.nix"]`, `ctr plugins ls` showing the `nix` snapshotter `ok`, and NRI's state recorded as an observation (ADR-007 F6; the design does not assume it).
Sizing starts at nixpkgs' `memorySize = 1536; diskSize = 4096` and is raised only when the first build shows it short.
Alternative: O-b, Cilium via `autoDeployCharts`; deferred to D6 because it would place a GiB-class closure and a second envelope in the cheapest VM leaf.
The node imports `base` (ADR-007 D7.11).

### D3: T1 leaves regulate the evaluated module and the rendered `cryolite` tree [narrowed]

`k3s-server-eval` asserts the evaluated `ExecStart` contains each intended flag including `--snapshotter nix`, that `pkgs.nix` is on the unit path, that `virtualisation.containerd.enable` is `false` and no `/etc/containerd/config.toml` is produced, and that kernel modules, sysctls, and firewall lists match the module's declarations.
`k8s-purity-cryolite` (`modules/kubernetes/purity.nix`), `k8s-provenance-cryolite` (`provenance.nix`), `k8s-node-identity-free-cryolite` (`identity.nix`), `flux-sources-pinned`, and `flux-install-rendered` are `runCommand` leaves over the easykubenix-rendered tree of `cryolite` (ADR-008 D8.11, D8.12, D8.4, D8.2; ADR-010 D10.6).
Revision 1's `k8s-manifest-purity` and `k8s-images-preloaded` are the two assertion groups of `k8s-purity-cryolite`; `k8s-closure-provenance` is `k8s-provenance-cryolite`; the rename follows the module tree.
The CAPI rendering leaves (`capi-cloud-invariant-render`, `capi-platform-sum-total`, `capi-ccm-present`, `clustermesh-preconditions`) are moved to the sibling change as `k8s-capi-render`.
All of these run on the buildbot worker.
When the module change deletes the inert containerd block, `k3s-server-eval`'s containerd assertion flips to assert the corrected shape; the flip is the mutation evidence.

### D4: The join path is asserted in the platform leaf [superseded by D6]

Revision 1 planned a standalone `vm-k3s-multi-node` leaf (server and agent, CNI-free, store-path token).
Revision 2 has no such leaf: `vm-k3s-platform` boots the `cryolite` server and agent (D6), so the join assertions — both nodes registered, the agent's `ExecStart` carries `--server=` and no `--cluster-cidr`/`--service-cidr`, the agent reaches `server:6443` and `server:10250` through the production firewall — live there, with Cilium present, and pod-to-pod connectivity across nodes is asserted alongside.
`services.k3s.nodeIP` is set directly on each machine as glue because the production module does not expose it.
Rationale: the CNI-free two-node variant would add a leaf whose only property beyond D2 is the join, and the join is regulated anyway where it matters.

### D5: Store-path token in VM leaves; production identity is T0 and out of this change's tests [narrowed]

The token is `pkgs.writeText`, as nixpkgs does, world-readable in the store and authorizing nothing outside the sandbox.
In production the join token, the CA set, the Flux age key, and the cosign key are T0 cluster identity generated once by Clan vars and delivered to nodes at first boot (ADR-010 D10.1, D10.4); the `k3s-server.bootstrap` seam (`clan-vars | cloud-init`) and its NoCloud regulator are the sibling change's S3.
This change's VM leaves never invent production shape: fixtures stand in for T0 material and the spec states what they do not cover.

### D6: One platform leaf, two guests, Flux from an in-guest registry, in-guest Chainsaw (O-1) [narrowed]

`vm-k3s-platform` boots `cryolite-server` and `cryolite-agent` (both importing `base` and `k3s-server`; the agent with `role = "agent"` and `serverAddr` pointing at the server over one test-driver VLAN), preloads every image the rendered tree references through `services.k3s.images` (the set is derived from the tree by string context, ADR-008 D8.11), applies Cilium with `kubeProxyReplacement=true` and the Flux install through `services.k3s.manifests`, runs `services.dockerRegistry` in the server guest (the pinned nixpkgs module backed by `pkgs.distribution`; ADR-008 D8.6, verified as R8.h) seeded from the sandbox-built OCI layout, renders the root `OCIRepository` with that layout's digest and a `spec.verify` public key from a test-only cosign pair, and runs `chainsaw test` on `kubernetes/tests/cryolite` from a store path with `KUBECONFIG=/etc/rancher/k3s/k3s.yaml`.
The `cryolite` suite has two phases: foundation (Cilium `Ready`, Flux root `Kustomization` `Ready=True` with `status.lastAppliedRevision` equal to the pinned digest) and infrastructure (cert-manager, step-ca, `ClusterIssuer`, `Gateway`, `Certificate`s, `HTTPRoute`).
It is authored for `cryolite`, not copied from `kubernetes/tests/local-k3d`, and carries no ArgoCD or sops-secrets-operator step.
Wait-for-ready logic is the Chainsaw suite's own timeouts.
Alternative: O-2 slice leaves; taken only if O-1's measured wall time exceeds 15 minutes, splitting `vm-k3s-cilium` first.

### D7: The VM's DNS and Gateway address are hermetic and production-shaped [kept]

CoreDNS answers the certificate hostnames itself through a `hosts` or `template` stanza in the rendered tree's VM variant, replacing the `sslip.io` forward to `1.1.1.1`.
The Gateway LoadBalancer address is supplied by a `CiliumLoadBalancerIPPool` declared by the `cryolite` cluster module (ADR-007 D7.9); ServiceLB stays disabled and kube-proxy is replaced by Cilium.

### D8: Test-only age and cosign keys installed at activation [kept]

A committed test age keypair and cosign keypair (outside `modules/`) are installed to the server guest at activation, as clan-core's `lib/test/age.nix` and sops-nix's `checks/nixos-test.nix` do; the VM variant of the rendered tree encrypts its SOPS payloads to the age public key and the in-guest artifact is signed with the cosign private key.
Production uses per-cluster Clan vars generators for both, as T0 identity under `secrets/clusters/cryolite/` (ADR-008 D8.9, D8.14; ADR-010 D10.1); the uncovered production properties are listed in the `k3s-platform-vm-regulator` spec.

### D9: easykubenix for `cryolite`; a VM target of the `cryolite` cluster module, not a nixidy environment [narrowed]

The rendered tree is produced by the easykubenix cluster module `kubernetes/clusters/cryolite/` with a `target` that selects VM fixtures (hostnames, CoreDNS answer, registry URL, key material) from production values.
No nixidy environment is created for `cryolite`; `modules/nixidy.nix` and `kubernetes/nixidy/local-k3d/` keep serving `local-k3d` and are not edited.
Revision 1's "deleted when the k3d workflow is" is Future Work.
The `platform` sum the module also carries is specified in the sibling change; in this change the module is evaluated with `platform = hetzner` only so that the S0 leaves have a concrete tree.

### D10: The CAPI bootstrap seam and the management cluster [moved]

`vm-k3s-capi-bootstrap`, the NoCloud renderer, `k3s-server.bootstrap`, `capi-bootstrap.nix`, the `clusterctl.yaml` override, and the management-cluster handler are design decisions of `openspec/changes/capi-hetzner-cluster/` (its D1–D4).
Revision 1's handler A (`vm-capi-management`, the k3s closure as a QEMU VM) is deferred there; handler B (k3d on stibnite) comes first (ADR-009 D9.17).

### D11: The CI runner is probed, then chosen [kept]

A manually dispatched job on `ubuntu-latest` applies the udev rule GitHub's changelog shows, checks `/dev/kvm`, and builds `vm-k3s-substrate` with `--option system-features 'kvm nixos-test benchmark big-parallel'`.
Three consecutive passes promote the VM leaves into `test-cluster.yaml` as a `vm` job beside the untouched `integration` job; any failure leaves VM leaves as developer-host regulators through `just test-integration` until a KVM-capable runner exists (ADR-007 D7.10).

### D12: Deletion is Future Work [superseded by ADR-007 D7.15]

Revision 1 gated one deletion commit (k3d scripts, `integration` job, `SOPS_AGE_KEY`, `local-k3d-ci`, `modules/nixidy.nix`, `kubernetes/nixidy/`, ArgoCD, sops-secrets-operator) on a green `vm-k3s-platform`.
Revision 2 deletes nothing: the frozen prototypes are migrated or retired by a later, separately authorized feedback change, and ADR-006 is not marked superseded until then.
The gate survives as advice to that change: it should not delete the k3d path before `vm-k3s-platform` has passed on the chosen runner.

### D13: Spend [moved]

S4 spends money; it is the sibling change's D10, released per flake revision by the gate of ADR-009 D9.19, and nothing in this change's stages touches a cloud or reads that gate.

### D14: `cryolite` is a sibling, and the prototypes are frozen [new, rev 2; ADR-007 D7.15]

The sibling is `cryolite` (ADR-007 D7.20: Na₃AlF₆, the fleet's mineral naming continued), with machines `cryolite-server` and `cryolite-agent` and paths `kubernetes/clusters/cryolite`, `kubernetes/tests/cryolite`, `secrets/clusters/cryolite`.
Every regulator, module, artifact, and secret this change plans is keyed by `cryolite`; `evalCluster` gains one entry; nothing under `kubernetes/clusters/local*`, `kubernetes/nixidy/`, `kubernetes/tests/local-k3d/`, or `modules/apps/cluster/` is read differently or edited.
ArgoCD (for `local-k3d`) and Flux (for `cryolite`) coexist; this is a per-cluster reconciler choice, not a migration.
Boundary: first-party throughout; the only source-versus-delivered seam is the OCI artifact, whose delivered digest is a build output.

## Risks / Trade-offs

- R1 kubelet message wording: the O-a `NotReady` assertion checks the message text, which a kubelet upgrade may change. Mitigation: assert `reason` and a short substring.
- R2 platform closure size: bounded at 1.5–2.5 GiB compressed, not measured; two guests double the memory footprint. Mitigation: `k8s-provenance-cryolite` reports it in S0; if S2 wall time exceeds 15 minutes, apply O-2.
- R3 hosted-runner KVM: unsupported by the vendor; may flake. Mitigation: D11's probe; VM leaves never gate a merge from a runner that has not passed it.
- R4 buildbot behavior on `kvm`-requiring derivations is unobserved. Mitigation: observe on S1's first push and filter if they surface as failures.
- R5 NRI behavior under root k3s with the `nix` snapshotter is inferred from the template, not observed (ADR-007 F6). Mitigation: D2 records it; `containerdConfigTemplate` is introduced only if the observation shows NRI disabled (ADR-007 D7.8).
- R6 OCI-layout digest equality across push tools is inferred (ADR-008 R8.c). Mitigation: S2 proves it against the in-guest registry with the same tool `apps.k8s.oci-push` uses; the sibling change's S4 asserts it against GHCR.
- R7 the `cryolite` Chainsaw suite is new and its first green run is also its first run. Mitigation: each assertion has a recorded mutation (tasks S2.7); the `local-k3d` suite is left as an independent oracle of the shared components' behavior under the old envelope.
- R8 store-path token and test keys are readable by every sandbox process. Accepted: they authorize nothing outside the test, and production identity is T0 material that never enters a check.
- R9 the two-guest leaf regulates the join under Cilium only; a CNI-free join regression would surface as a Cilium-era failure. Accepted: attribution costs one extra look at the agent's `ExecStart`, which the leaf prints.
- R10 the frozen prototypes drift from `cryolite` as `cryolite` evolves (two reconcilers, two secret mechanisms). Accepted by the scope review; the feedback change owns convergence or retirement.

## Migration Plan

1. S0 lands the T1 leaves listed in D3 against an initial `kubernetes/clusters/cryolite/` with `platform = hetzner` only, `modules/kubernetes/{artifacts,oci-lib,purity,provenance,identity}.nix`, `modules/kubernetes/flux/`, and the `apps.k8s.oci-push` and `apps.k8s.cosign-sign` effects (not run); the k3d workflow is untouched.
2. A separate module change adds `modules/nixos/k3s-server/snapshotter.nix` and the `snapshotter` option, puts `pkgs.nix` on the unit path, and deletes the inert containerd block; `k3s-server-eval` flips with it.
3. S1 lands `vm-k3s-substrate` and `vm-k3s-snapshotter`; mutation evidence for two assertions per leaf is in the PR body; unchanged workflow.
4. S2 lands `kubernetes/tests/cryolite/`, `modules/nixos/k3s-flux.nix`, `machines/nixos/cryolite-{server,agent}.nix`, the age and cosign fixtures, the LB-IPAM pool, and `vm-k3s-platform`; unchanged workflow.
5. Execution: the KVM probe job; promotion of VM leaves into `test-cluster.yaml` as a `vm` job on a passing runner; the `integration` job is not edited.
6. The sibling change's S3 begins once S2 is green; S4 additionally needs explicit written spend approval.

Rollback at any stage is deletion of the stage's `[add]` paths; the k3d workflow keeps running throughout.

## Gate 1 modality verdicts

No requirement in this change's delta specs routes to a Gherkin scenario, so no `.feature` file is laid out.
The repository has no BDD runner, and every observable here is an evaluated Nix value (witnessed by `nix eval`/nix-unit/`runCommand`), a test-driver assertion inside a QEMU guest (witnessed by `nixosLib.runTest`), an `apps` effect's exit status, or a CI job outcome.
`world`-stratum requirements are witnessed by their own violation conditions; `interface`-stratum requirements by the derivation attributes and job results named in their scenarios.

## Open Questions

Ambiguities found while folding the design and scope reviews into this change; each carries a recommendation, and silence adopts it except where marked.
A1–A3, A5, and A9 of revision 1 concerned S3–S4 and are carried by the sibling change's open questions; A1, A2, A3, A6, A7 were accepted as recommended and are now decisions there.
The owner answered A4 and A10–A12 in the charter-v1 review; they are recorded here as resolved and their answers live in D6 and D14.

- A4 [resolved] the in-guest registry is `services.dockerRegistry` from the pinned nixpkgs, backed by `pkgs.distribution` (ADR-008 D8.6, R8.h; `pkgs.docker-distribution` is a throwing alias there); it exists only in the S2 guest, and the real cluster pulls from GHCR or the registry the sibling change selects.
- A8 [accepted] delta-spec numbering: the `world-assumptions` additions are numbered A13–A16 here and A17–A21 in the sibling change, assuming the two unmerged changes that add A9–A12 land first; renumber at sync if not.
- A10 [resolved] the cluster is `cryolite` (ADR-007 D7.20); applied throughout both changes and ADR-007–ADR-010.
- A11 [resolved] the `cryolite` Chainsaw suite copies and adapts the `local-k3d` step YAML for cert-manager, step-ca, and Gateway into `kubernetes/tests/cryolite`; no file is shared with the frozen prototype (D14).
- A12 [resolved] the agent guest hosts no registry mirror; images arrive on both guests through `services.k3s.images`, and the registry serves only the Flux artifact to the server's source-controller.
