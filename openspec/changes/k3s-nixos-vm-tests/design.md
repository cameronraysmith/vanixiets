## Context

The platform's only integration regulator is a k3d cluster in Docker driven by `modules/apps/cluster/k3d-integration-ci.sh` from `.github/workflows/test-cluster.yaml`.
The production NixOS k3s module `flake.modules.nixos.k3s-server` (`modules/nixos/k3s-server/`) has no regulator at all, and its k3d stand-in runs a different Cilium and load-balancer envelope.
The research behind this design is ADR-007 (`docs/notes/development/kubernetes/decisions/ADR-007-nixos-vm-tests-for-k3s.md`); findings F1–F5 and question sections Q1–Q7 are cited by code below rather than restated.

Constraints fixed by the repository:
- Each VM test is one independent, cacheable `perSystem.checks` leaf named `vm-<subject>`, under `lib.optionalAttrs pkgs.stdenv.hostPlatform.isLinux`, built through `nixosLib.runTest` with the clanTest module exactly as `modules/checks/vm-nixos-base.nix` does (PR #2954).
- Machines under test import production deferred modules unmodified; a module that cannot be composed into a test is a finding about the module.
- `nixosLib.runTest` requires `kvm nixos-test`; the buildbot worker exposes neither and this is intentional.
- The Nix build sandbox has no network.
- Every runtime assertion is shown non-vacuous by a recorded mutation of the module it regulates.

The standalone evaluation that grounds F1 and the stage 1 T1 leaf:

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
- Give `flake.modules.nixos.k3s-server` regulators at the cheapest sufficient tier for each property it claims (ADR-007 Q1).
- Re-express every current Chainsaw assertion as a hermetic NixOS VM assertion against the production envelope, not the k3d one.
- Make the KVM runner question an observed fact before any VM leaf gates CI.
- End with the k3d integration scripts deleted.

Non-goals:
- Fixing the inert `virtualisation.containerd.settings` block; that is a module change (D-M1).
- Regulating production key provisioning, recipients, rotation, or GitHub Secret wiring (ADR-007 Q5).
- Replacing k3d as an interactive Darwin developer cluster (D-C2).
- Any change to the buildbot worker's feature set.

## Decisions

### D1: Three tiers, assigned per assertion, with no permanent k3d residue

Every current phase and assertion is placed at T1 (pure eval/build), T2 (VM substrate), or T3 (VM platform) per the ADR-007 Q1 tables.
The k3d-only properties — Docker volume mount consumption and behavior under kube-proxy plus ServiceLB — are properties of k3d, not of the platform, and are dropped rather than preserved.
Alternative considered: a permanent k3d residue for the platform suite (O-3); rejected because every blocker in ADR-007 Q4 has a hermetic substitute.

### D2: The single-node leaf ships no CNI (O-a)

`vm-k3s-single-node` imports `k3s-server` with `enable`, `clusterInit`, and a store-path `tokenFile`, and asserts the substrate table in ADR-007 Q1, including that the node is `NotReady` with `reason == "KubeletNotReady"` and a message containing `cni plugin not initialized`, and CoreDNS is `Pending`.
Sizing starts at nixpkgs' `memorySize = 1536; diskSize = 4096` and is raised only when the first build shows the root image or memory is short.
Alternative: O-b, Cilium via `autoDeployCharts` with preloaded images; deferred to D6 because it would place a GiB-class closure and a second envelope in the cheapest VM leaf.
Whether the node also imports `base` is D-S1.

### D3: A T1 leaf regulates the evaluated module today

`k3s-server-eval` is a nix-unit (or `runCommand` over `nix eval --json`) check asserting the evaluated `ExecStart` contains each intended flag, that `virtualisation.containerd.enable` is `false` and no `/etc/containerd/config.toml` is produced, that `boot.kernelModules`, `boot.kernel.sysctl`, and the firewall lists match the module's declarations.
It is the existence regulator for F1 and runs on every host including the buildbot worker.
When D-M1 corrects the inert block, this leaf's containerd assertion flips to assert the corrected shape; the flip is the mutation evidence.

### D4: Multi-node adds the join path only

`vm-k3s-multi-node` boots `server` and `agent` on one VLAN with a shared store-path token and asserts registration of both nodes, that the agent's `ExecStart` carries `--server=` and no `--cluster-cidr`/`--service-cidr`, and that `agent` reaches `server:6443` and `server:10250` through the production firewall.
`services.k3s.nodeIP` is set directly on each machine as glue because the production module does not expose it.
Pod-to-pod connectivity as in nixpkgs' `multi-node.nix` needs a CNI and is asserted in D6's leaf, not here.

### D5: Store-path token until a production generator exists

The token is `pkgs.writeText`, as nixpkgs does, world-readable in the store and authorizing nothing outside the sandbox.
A `clan.core.vars` generator with `share = true` is adopted by the leaf only after the fleet declares one for production (D-S2); writing one in the test first would invent production shape in a test.

### D6: One platform leaf, in-guest Chainsaw (O-1)

`vm-k3s-platform` boots one node importing `k3s-server`, preloads every image in the ADR-007 Q4 inventory through `services.k3s.images` (each a fixed-output `dockerTools.pullImage` by digest; `alpine/curl:latest` pinned first), applies Cilium and the foundation through `services.k3s.manifests`, serves the rendered VM nixidy environment from a bare repository created on the node at activation and referenced by a `file://` URL, and runs `chainsaw test` from a store path with `KUBECONFIG=/etc/rancher/k3s/k3s.yaml`.
Wait-for-ready logic is the existing Chainsaw suite's own timeouts, not a port of `k3d-wait-*.sh`.
Alternative: O-2 slice leaves; taken only if O-1's measured wall time exceeds 15 minutes, splitting `vm-k3s-cilium` first.

### D7: The VM's DNS and Gateway address are hermetic and production-shaped

CoreDNS answers the certificate hostnames itself through a `hosts` or `template` stanza in the VM nixidy environment, and the hostnames embed the VM node's address, replacing the `sslip.io` forward to `1.1.1.1`.
The Gateway LoadBalancer address is supplied by whichever mechanism production adopts under D-P1 — a `CiliumLoadBalancerIPPool`, host-network Gateway mode, or ServiceLB; the leaf regulates the production choice, and a choice that re-enables ServiceLB is recorded as regulating the k3d envelope again.

### D8: Test-only age key installed at activation

A committed test keypair (outside `modules/`) is installed to the node at activation, as clan-core's `lib/test/age.nix` and sops-nix's `checks/nixos-test.nix` do, and the VM nixidy environment encrypts its `SopsSecret` payloads to that public key.
The uncovered production properties are listed in the `k3s-platform-vm-regulator` spec.
Alternative: a clanTest in-sandbox vars generator; equally hermetic, more moving parts, revisited when the fleet has k3s generators.

### D9: A VM nixidy environment, not the k3d one

`local-vm` (name provisional, D-P2) derives from `local-k3d` the way `local-k3d-ci` does and overrides the target repository URL, hostnames, CoreDNS answer, and secret recipients.
Its `environmentPackage` and `bootstrapPackage` gain T1 leaves like `nixidy-env-local-k3d`.

### D10: The CI runner is probed, then chosen

A manually dispatched job on `ubuntu-latest` applies the udev rule GitHub's changelog shows, checks `/dev/kvm`, and builds `vm-k3s-single-node` with `--option system-features 'kvm nixos-test benchmark big-parallel'`.
Three consecutive passes promote the VM leaves into `test-cluster.yaml`; any failure routes to the fallback runner chosen under D-C1.
Until then the VM leaves are developer-host regulators run through `just test-integration`.

### D11: Deletion is the last step and is gated on green

The k3d scripts, the `integration` job, the `SOPS_AGE_KEY` env line, the `local-k3d-ci` environment, and the k3d justfile recipes are deleted in one commit after `vm-k3s-platform` has passed in CI on the chosen runner.
`kubernetes/clusters/local-k3d/` is retained unless D-C2 decides otherwise.

## Risks / Trade-offs

- R1 kubelet message wording: the O-a `NotReady` assertion checks the message text, which a kubelet upgrade may change. Mitigation: assert `reason` and a short substring; a wording change fails loudly and is a one-line fix.
- R2 platform closure size: bounded at 1.5–2.5 GiB compressed, not measured. Mitigation: measure with `nix path-info -S` on the first pull set; if wall time exceeds 15 minutes, apply O-2.
- R3 hosted-runner KVM: unsupported by the vendor; may flake. Mitigation: D10's probe and D-C1's fallback; VM leaves never gate a merge from a runner that has not passed the probe.
- R4 buildbot behavior on `kvm`-requiring derivations is unobserved. Mitigation: observe on stage 1's first push and filter if they surface as failures.
- R5 Gateway address mechanism undecided (D-P1): the platform leaf cannot be finished without it. Mitigation: stage 3 is blocked on D-P1 explicitly.
- R6 F1's inert block is exposed, not fixed, by these tests; a reader may take a green `vm-k3s-single-node` as validating the containerd settings. Mitigation: D3's assertion states the block is inert until D-M1 lands.
- R7 store-path token is readable by every sandbox process. Accepted: the value authorizes nothing outside the test.

## Migration Plan

1. Stage 1 lands `k3s-server-eval`, `vm-k3s-single-node`, and the `local-k3d-ci` T1 leaf; the k3d workflow is untouched; mutation evidence for two assertions is in the PR body.
2. Stage 2 lands `vm-k3s-multi-node`; unchanged workflow.
3. Stage 3 lands the VM nixidy environment, the age fixture, the image pins, and `vm-k3s-platform`, gated on D-P1 and D-P2; unchanged workflow.
4. Stage 4a lands the KVM probe job; 4b promotes VM leaves into `test-cluster.yaml` on the passing runner; 4c deletes the k3d integration pieces.

Rollback at any stage is deletion of the stage's leaves; no stage edits `modules/nixos/k3s-server/`, and the k3d workflow keeps running until 4c.
Containment for 4c is that the deletion commit is separate from the promotion commit, so reverting it restores the k3d job without touching the VM job.

## Gate 1 modality verdicts

No requirement in this change's delta specs routes to a Gherkin scenario, so no `.feature` file is laid out.
The repository has no BDD runner, and every observable here is either an evaluated NixOS configuration (witnessed by `nix eval`/nix-unit), a test-driver assertion inside a QEMU guest (witnessed by `nixosLib.runTest`), or a CI job outcome (witnessed by the workflow run).
`world`-stratum requirements are witnessed by their own violation conditions; `interface`-stratum requirements by the derivation attributes and job results named in their scenarios.

## Open Questions

- D-S1: do fleet k3s nodes import `base`? Recommended: yes, and the single-node leaf imports it with the initrd SSH workaround from PR #2954.
- D-S2: will a shared `k3s-token` clan vars generator be the production token path? Recommended: yes, adopted in stage 2 once written.
- D-P1: how does production assign Gateway LoadBalancer addresses? Recommended: a `CiliumLoadBalancerIPPool`, because it keeps `kubeProxyReplacement = true` and ServiceLB disabled.
- D-P2: is a `local-vm` nixidy environment acceptable? Recommended: yes.
- D-C1: fallback runner if the `ubuntu-latest` probe fails? Recommended: a self-hosted runner on the KVM developer host, registered for this workflow only.
- D-C2: does `kubernetes/clusters/local-k3d/` survive stage 4? Recommended: yes, as a Darwin convenience with no CI role.
- D-M1: fix the inert containerd block before stage 1? Recommended: yes, as its own module PR, so stage 1's T1 leaf asserts the corrected shape from the start.
- Delta-spec numbering: the `world-assumptions` additions are numbered A13–A15 assuming the two unmerged changes that add A9–A12 land first; renumber at sync if not.
