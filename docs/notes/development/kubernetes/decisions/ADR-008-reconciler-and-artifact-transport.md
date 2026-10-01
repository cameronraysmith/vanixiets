# ADR-008: Reconciler and artifact transport

## Status

Proposed (2026-09-04; revision 2 the same day, narrowing every decision to the sibling cluster `cryolite`; charter v1 fold the same day, fixing the in-guest registry implementation in D8.6).
The programme-level view that places this record among ADR-007, ADR-009, and ADR-010 is `../cryolite-charter.md`.
Design only; no flake input, production module, or workflow changes land with this record.
Implemented by stages S0 and S2 of `openspec/changes/k3s-nixos-vm-tests/`; the `apps.k8s.oci-push` effect first runs in S4 of `openspec/changes/capi-hetzner-cluster/`.

Scope after revision 2 (ADR-007 D7.15, recorded here as D8.15): every decision below governs `kubernetes/clusters/cryolite` and nothing else.
`local` and `local-k3d` are frozen prototypes that keep ArgoCD, nixidy, the `local-k3d-ci` environment, sops-secrets-operator, and ADR-006's manifest repository; ArgoCD and Flux coexist in the repository, one per cluster.
Revision 1 of this record reversed ADR-006 and retired ArgoCD, nixidy, and sops-secrets-operator for the fleet; those global retirements are Future Work for a later, separately authorized feedback change, and the decisions that carried them (D8.1, D8.9, D8.10) are retained below with their revision-2 status.
ADR-006 is not reversed by this revision.

## Context

ADR-007 re-expresses the k3d `test-cluster` workflow as NixOS VM tests and pure checks.
Doing so exposed that the reconciler and the transport of desired state were the k3d workflow's least hermetic parts: ArgoCD read a git repository mounted from the Docker host, nixidy rendered it, secrets arrived through `SOPS_AGE_KEY` from GitHub Secrets, and the private manifest repository of ADR-006 existed to keep Helm-generated Secrets out of the public tree.
None of those pieces can be expressed as a store path with a known digest, so none of them can be regulated by a `checks.<system>.<name>` leaf without a network.

This record fixes how desired state reaches `cryolite`, which reconciler applies it, how images and configuration are packaged, and where the only effects (registry pushes) live.
The node-management and networking half of the design is ADR-009; the identity material this record consumes (the SOPS age key, the cosign key) is T0 cluster identity as defined in ADR-010.
The module tree that places these pieces is ADR-007 D7.17: `modules/kubernetes/artifacts.nix` (`k8s-manifests-cryolite`, `k8s-oci-cryolite`), `modules/kubernetes/oci-lib.nix` (`mkOciLayout`, `mkNixSnapshotterImage`, `readDigest`), `modules/kubernetes/flux/{install,root}.nix`, `modules/nixos/k3s-flux.nix`, `kubernetes/modules/flux/`, and `modules/apps/k8s/{oci-push,cosign-sign}`.

Paths under `~/ghq/` refer to the reference trees listed in ADR-007's appendix at the revisions recorded there.
Claims read in source are stated as facts; claims that were not executed are marked as inferred and listed in the open-risk table.

## Findings

### F8.1: Flux can be installed offline from Nixpkgs, and can pin an OCI artifact by digest

Nixpkgs' `fluxcd` package (2.9.3) fetches the release `manifests.tar.gz` as a fixed-output `fetchzip` and copies it into the build (`~/ghq/github.com/NixOS/nixpkgs/pkgs/by-name/fl/fluxcd/package.nix:12`, `15-19`, `36`), so `flux install --export` runs with no network and its output is a function of the package revision.
The source-controller's `OCIRepository` accepts `.spec.ref.digest`, which selects an immutable artifact and takes precedence over `.spec.ref.tag` and `.spec.ref.semver` (`~/ghq/github.com/fluxcd/source-controller/docs/spec/v1/ocirepositories.md:495-504`).
`.spec.verify` enables Cosign or Notation signature verification, keyed through a Secret holding public keys or keyless through an OIDC identity match (`ocirepositories.md:548-549`, `563`).

### F8.2: two artifact kinds, two consumers

The rendered Kubernetes tree is one artifact kind: a set of manifests Flux applies.
Container images are another: filesystems containerd unpacks.
A tool that serves one need not serve the other.
nix-snapshotter's `buildImage` writes the image and its manifest to the store and produces a reference of the form `nix:0<store path>` that only a node running the `nix` snapshotter can resolve (`~/ghq/github.com/pdtpartners/nix-snapshotter/package.nix:31-38`, `76`); it exposes `copyToRegistry` and `copyToContainerd` passthrus (`85-86`, `101`, `117`).
nix2container describes layers as JSON of store paths with precomputed digests and streams tarballs at push time, exposing `copyToRegistry`, `copyToDockerDaemon`, `copyToPodman`, and `copyTo` (`~/ghq/github.com/nlewo/nix2container/default.nix:73-88`); it targets any OCI runtime.
nixpod's `modules/containers/build-image.nix` declares explicit layers ordered by change frequency and `manifest-builder.nix` pushes per-architecture images with Skopeo and appends them into an index with Crane (`~/ghq/github.com/cameronraysmith/nixpod/modules/containers/`).

### F8.3: k3s preloads images from a directory, so a store path is a legitimate image source

`services.k3s.images` links each image into `/var/lib/rancher/k3s/agent/images` before the unit starts (`~/ghq/github.com/NixOS/nixpkgs/nixos/modules/services/cluster/rancher/default.nix:648-667`, `854`).
The VM leaf never needs a registry for images; it needs one only for the Flux configuration artifact, because `OCIRepository` has no file-URL source type.

### F8.4: Timoni renders offline but reconciles online

`timoni build INSTANCE ./module --values v.cue --output yaml` renders a module with no cluster (`~/ghq/github.com/stefanprodan/timoni/cmd/timoni/build.go`).
Its runtime features — instance inventory Secrets, `timoni apply`, bundle runtime values read from the cluster, and the `flux-aio` distribution (`~/ghq/github.com/stefanprodan/timoni/skills/timoni/SKILL.md`) — form a second reconciler beside Flux.
The value Timoni adds over a Nix module is a typed schema for authors writing CUE; the repository's configuration is already typed by the NixOS module system through easykubenix.

### F8.5: the k3d envelope's image references are not all pinned

The rendered `local-k3d-ci` tree contains `alpine/curl:latest` (ADR-007 Q4).
Nothing in the current check set rejects a floating tag; the property is regulated by review alone.

## Decisions

### D8.1: Flux is the reconciler of `cryolite` [narrowed, rev 2]

Flux (source-controller, kustomize-controller, notification-controller) is the reconciler of `cryolite`.
The reasons are the three F8.1 properties: offline install from a Nixpkgs package, digest-pinned OCI sources, and signature verification with a key that can live in the node closure.
ArgoCD has no equivalent of `.spec.ref.digest` for a git source and would require an ADR-006-style repository for `cryolite`.
The `cryolite` Chainsaw suite asserts `Kustomization` readiness and `status.lastAppliedRevision` equality with the pinned digest where the `local-k3d` suite asserts ArgoCD sync.
Revision 1 wrote "replaces ArgoCD" for the fleet; ArgoCD continues to reconcile `local-k3d`, and its replacement there is Future Work (D8.15).

### D8.2: Flux is installed from `flux install --export` rendered in Nix, three controllers, images preloaded

A derivation runs `flux install --export --components=source-controller,kustomize-controller,notification-controller` from `pkgs.fluxcd` and captures the manifest.
No helm-controller (charts are rendered by easykubenix at evaluation), no image-reflector or image-automation controllers (the artifact is pinned, not discovered), no flux-operator.
The three controller images are preloaded through `services.k3s.images` by digest.
The rendered install manifest is a T1 artifact: the S0 purity leaf inspects it like any other rendered object.

### D8.3: bootstrap from `services.k3s.manifests`; the root `OCIRepository` carries a digest

Flux's install manifest and the CRDs it needs are placed in the node closure through `services.k3s.manifests`, which k3s applies from `/var/lib/rancher/k3s/server/manifests` at start (`rancher/default.nix:533`).
The root `OCIRepository` and root `Kustomization` are also rendered in Nix.
`OCIRepository.spec.ref.digest` is the digest of the OCI layout built in the sandbox (D8.5), so the node closure names the exact configuration the cluster will converge on.
Where the root object lives differs by target: in VM leaves it is baked into the same `services.k3s.manifests` (one hash, the VM is rebuilt anyway); on CAPI-managed nodes it is delivered per cluster through `KThreesConfig.spec.files` (ADR-009 D9.7), and the hash chain of ADR-007 D7.17 (`clusters/cryolite` → `k8s-manifests-cryolite` → `k8s-oci-cryolite` digest → `k3s-flux.nix` → node closure) means a configuration change is a flake bump and rolls nodes; accepting that was ambiguity 1 of the first revision.

### D8.4: the artifact is hosted on GHCR; the tag is the flake revision; consumers use the digest

The configuration artifact is pushed to `ghcr.io/<owner>/<repo>/<cluster>` tagged with the flake revision.
Tags are aliases for humans and CI logs only.
Every consumer — Flux `OCIRepository`, `services.k3s.images`, `KThreesConfig` files, CAPH `imageName` (ADR-009 D9.6) — refers by digest or by a Nix store path.
A T1 leaf rejects any `OCIRepository` whose `spec.ref` lacks `digest`.

### D8.5: three artifact producers, split by consumer

- Nix-native workload images run only on nodes with the `nix` snapshotter (ADR-007 D7.1): `nix-snapshotter.buildImage`, referenced as `nix:0<store path>`. No push; the store path is the transport.
- Portable images that must run on non-nix-snapshotter nodes or be public: nix2container, pushed with `copyToRegistry`.
- Flux configuration artifacts: a Nix derivation that writes an OCI image layout (`oci-layout`, `index.json`, `blobs/sha256/`) from the rendered easykubenix tree using `oras` or `crane` on store inputs. The manifest digest is a file in the derivation output and is therefore known inside the sandbox before any push.

`dockerTools.buildLayeredImage` is the baseline for anything that fits none of the three; it is not forbidden, but every new image names which of the three consumers it serves.

### D8.6: VM leaves seed an in-guest registry from the OCI layout, offline

The `vm-k3s-platform` leaf runs a registry service in the guest, loads the OCI layout from the store into it with `crane push --index` or `oras cp` against `localhost`, and points the root `OCIRepository` at `oci://localhost:<port>/<name>` with the same digest the derivation reported.
The pattern is nix-snapshotter's push-and-pull test (`~/ghq/github.com/pdtpartners/nix-snapshotter/modules/nixos/tests/push-n-pull.nix`).
Images do not pass through the registry; they are preloaded (F8.3).
Nothing in `checks` opens a network connection outside the VM.

The registry is the NixOS module `services.dockerRegistry` (`nixos/modules/services/misc/docker-registry.nix` in the pinned nixpkgs, `044bfe75`), whose `package` option defaults to `pkgs.distribution` (CNCF Distribution 3.1.1); the older attribute name `pkgs.docker-distribution` is a throwing alias in that revision, so no artifact may name it.
The module exists only in the S2 guest: `cryolite` on Hetzner pulls the artifact from GHCR (D8.4) or from whatever registry `openspec/changes/capi-hetzner-cluster/` selects, and no production node closure carries a registry service.
This resolves the parent change's open question A4 (design.md) and ADR-007's B2.

### D8.7: publishing is an `apps` effect that asserts digest equality

`nix run .#apps.<system>.k8s.oci-push` (the tree of ADR-007 D7.17; revision 1 called it `push-cluster-artifact`) pushes the OCI layout to GHCR and then reads back the digest of the pushed manifest.
The effect fails if the registry's digest differs from the digest recorded in the derivation.
This is the only place the configuration artifact touches a network, and it never runs under `nix flake check`; it is written in S0 and first run against GHCR in S4.
The same shape applies to `copyToRegistry` for portable images.

### D8.8: nixpod layering is carried over; a multi-architecture index only when arm64 is real

Portable images use nixpod's explicit layer ordering by change frequency.
The Crane `index append` step is adopted only when a second architecture is actually targeted (Hetzner arm64 CAX instances); until then every push is single-architecture and the manifest digest, not an index digest, is what consumers pin.

### D8.9: Flux SOPS decryption with a per-cluster age key [narrowed, rev 2]

The kustomize-controller decrypts SOPS-encrypted Secrets inside the artifact using `spec.decryption.provider: sops` with a `flux-system/sops-age` Secret.
The per-cluster age key is T0 cluster identity (ADR-010 D10.1): generated once by a Clan vars generator and sops-encrypted in the repository under `secrets/clusters/cryolite/`.
On CAPI-managed nodes it reaches a server node at first boot through `KThreesConfig.spec.files[].contentFrom.secret` (ADR-010 D10.4), and the server drops the `flux-system/sops-age` Secret manifest into `/var/lib/rancher/k3s/server/manifests/`; the node closure never contains the private key, so the snapshot is secret-free.
Revision 1 delivered the key by sops-nix and mirrored it at activation; that path is what `vm-k3s-platform` still exercises with a committed test-only age keypair in place of the Clan generator (ADR-007 Q5), and it is retained as the VM-leaf shape only.
sops-secrets-operator is not deployed in `cryolite`; revision 1's clause "deleted together with its Chainsaw assertion" referred to `local-k3d`, where the operator stays, and that retirement is Future Work (D8.15).

### D8.10: `cryolite` needs no private manifest repository; the reversal of ADR-006 is Future Work [Superseded in its global form by D-a (rev 2, D8.15)]

ADR-006 introduced a private manifest repository because nixidy rendered Helm-generated Secrets into the tree.
With Secrets SOPS-encrypted inside the OCI artifact and decrypted only in the cluster, the `cryolite` artifact can be public and needs no such repository.
Revision 1 concluded from this that ADR-006 is reversed and that the `file:///manifests` pattern, the `local-k3d-ci` nixidy environment, and the T1 grep for it are retired.
Rationale for superseding: those artifacts belong to the frozen `local-k3d` prototype, which this plan does not edit; ADR-006 stands for `local-k3d` until the feedback change decides its fate.

### D8.11: purity regulators, no runtime Nix

Rendered manifests are checked by a T1 leaf for the absence of `flakeRef`, `nixExpr`, `:latest`, and any image reference that is neither digest-pinned nor a `nix:0` store-path reference, and for the inclusion of every rendered image reference in the preload set derived from the same tree.
nixkube is not added as a flake input and its runtime-injection mechanisms are forbidden in hermetic regulators (ADR-007 D7.1); the purity leaf is what makes that a failing check.
Manifests are rendered so that Nix string context is preserved from the image derivation to the manifest, which is what lets the preload set be derived rather than listed.

### D8.12: closure provenance report

A T1 derivation emits `nix path-info -r` for the rendered manifest closure together with an inventory of every image reference and its digest.
The report is a check output, not a document; a downstream comparison leaf fails when the inventory contains an entry absent from the preload set, which is the same predicate as D8.11 stated from the closure side.

### D8.13: Timoni is an ingest renderer at most

Custom charts are easykubenix modules, not Timoni modules.
If an upstream project ships a Timoni module the repository wants, it is rendered inside a derivation with `timoni build` from a digest-pinned module reference, and the output enters the easykubenix tree like a rendered Helm chart.
`timoni apply`, bundle runtime values, instance inventory, and `flux-aio` are excluded.
Timoni's idea of CRD-schema validation of rendered manifests is adopted as a KVM-free leaf (kubeconform against vendored CRD schemas), without the tool.

### D8.14: keyed cosign at push; Flux verifies with a public key from Clan vars

The `apps.k8s.cosign-sign` effect signs the artifact with a cosign key pair generated by a Clan vars generator; the key pair is T0 cluster identity (ADR-010 D10.1), the public half is baked into the node closure (public material may be, ADR-010 D10.4) and mirrored into a Secret referenced by `OCIRepository.spec.verify.secretRef`.
Keyless (OIDC) verification is rejected because it requires network access to Fulcio and Rekor at verification time, which the VM leaf cannot provide.
The VM leaf signs the in-guest artifact with a test-only key pair and verifies against its public half.

### D8.15: this record governs `cryolite` only; ArgoCD and Flux coexist [new, rev 2]

Every decision D8.1–D8.14 is scoped to `kubernetes/clusters/cryolite`.
What stands for `cryolite`: Flux from `flux install --export` with exactly source-controller, kustomize-controller, and notification-controller (D8.2); bootstrap through `services.k3s.manifests` (D8.3); the root `OCIRepository` pinned by digest (D8.3, D8.4); GHCR tagged by flake revision, consumers by digest (D8.4); nix-snapshotter images for Nix-native workloads and nix2container for portable images (D8.5); the OCI-layout derivation for Flux configuration (D8.5); in-VM registry seeding (D8.6); push as an `apps` effect asserting digest equality (D8.7); keyed cosign (D8.14); Flux SOPS with a per-cluster Clan-vars age key (D8.9); Timoni only as a digest-pinned offline ingest renderer (D8.13); no runtime `flakeRef` or `nixExpr` (D8.11).
What this record no longer claims: ArgoCD retirement, nixidy retirement, sops-secrets-operator retirement, and the reversal of ADR-006.
ArgoCD reconciles `local-k3d` from its nixidy-rendered tree; Flux reconciles `cryolite` from its easykubenix-rendered OCI artifact; `modules/nixidy.nix` and `kubernetes/nixidy/` are `[keep]` in the module tree, and the nixidy and `local-k3d` builds are outside `checks` because their evaluation needs import-from-derivation.
The global retirements and the reversal are Future Work for a later, separately authorized feedback change that migrates or retires the prototypes with the evidence `cryolite` produces.

## Requirements carried into the OpenSpec delta specs

| Code | Requirement | Regulator | Tier |
|---|---|---|---|
| R8.1 | rendered tree contains no `flakeRef`, `nixExpr`, `:latest`, or unpinned image reference | `k8s-manifest-purity` | T1 |
| R8.2 | rendered image references ⊆ preload set | `k8s-images-preloaded` | T1 |
| R8.3 | closure provenance report exists and agrees with R8.2 | `k8s-closure-provenance` | T1 |
| R8.4 | every `OCIRepository` carries `spec.ref.digest` and `spec.verify` | `flux-sources-pinned` | T1 |
| R8.5 | Flux install manifest contains exactly the three controllers | `flux-install-rendered` | T1 |
| R8.6 | OCI-layout digest equals registry digest after push | `apps.k8s.oci-push` | E |
| R8.7 | Flux converges from the in-guest registry with SOPS decryption and signature verification, on the two-guest `cryolite` core | `vm-k3s-platform` | T3 |
| R8.8 | the `local-k3d` rendered tree, nixidy environments, and Chainsaw suite are byte-identical before and after each `cryolite` stage | `git diff --stat` over the frozen paths in each stage PR | T1 |

## Verified versus inferred

| Code | Claim | Status | Discharging regulator |
|---|---|---|---|
| R8.a | `flux install --export` from `pkgs.fluxcd` needs no network | read in source (F8.1) | `flux-install-rendered` (S0) |
| R8.b | `OCIRepository.spec.ref.digest` selects an immutable artifact | read in docs (F8.1) | `vm-k3s-platform` (S2) |
| R8.c | an OCI layout built by `oras`/`crane` in the sandbox has the same manifest digest after `crane push` | inferred; digests are content-addressed but the push tool must not re-encode the manifest | `apps.k8s.oci-push` digest-equality assertion (S4 is the first real push; S2 proves it against the in-guest registry) |
| R8.d | kustomize-controller decrypts SOPS with an age key from `flux-system/sops-age` | read in Flux docs | `vm-k3s-platform` (S2) |
| R8.e | keyed cosign verification needs no network | read in docs (`ocirepositories.md:563`) | `vm-k3s-platform` (S2) |
| R8.f | a `services.k3s.manifests` entry can mirror a sops-nix–delivered file into a Secret at activation | inferred from `rancher/default.nix:533` and sops-nix's activation ordering | `vm-k3s-platform` (S2) with the fixture key |
| R8.g | a file written by cloud-init `write_files` into `/var/lib/rancher/k3s/server/manifests/` before `k3s.service` starts is applied by k3s like a `services.k3s.manifests` entry | inferred from `rancher/default.nix:533` (k3s reads the directory at start) | `vm-k3s-capi-bootstrap` (S3, `capi-hetzner-cluster`) |
| R8.h | `services.dockerRegistry` exists in the pinned nixpkgs and its default package is `pkgs.distribution` | read in source (`nixos/modules/services/misc/docker-registry.nix`, `pkgs/by-name/di/distribution/package.nix`, `pkgs/top-level/aliases.nix` at `044bfe75`) | `vm-k3s-platform` (S2) |

## Provenance

| ADR decision | Design-review code | Note |
|---|---|---|
| D8.1 | D10 | `k8s-architecture-current-vs-nixified.md` §3, §4 D10 |
| D8.2 | D14 | `k8s-architecture-current-vs-nixified.md` D14; `oci-caph-timoni-decisions.md` F16 |
| D8.3 | D10, D22 | `k8s-architecture-current-vs-nixified.md` D10; `oci-caph-timoni-decisions.md` D22 |
| D8.4 | D12, D17 | `k8s-architecture-current-vs-nixified.md` D12; `oci-caph-timoni-decisions.md` D17 |
| D8.5 | D15 | `oci-caph-timoni-decisions.md` F12–F14, O1–O4, D15 |
| D8.6 | D12, R2 | `k8s-architecture-current-vs-nixified.md` D12; `oci-caph-timoni-decisions.md` R2 |
| D8.7 | D15, R1 | `oci-caph-timoni-decisions.md` D15, R1 |
| D8.8 | D16 | `oci-caph-timoni-decisions.md` F15, D16 |
| D8.9 | D13 | `k8s-architecture-current-vs-nixified.md` D13 |
| D8.10 | D11 | `k8s-architecture-current-vs-nixified.md` D11 |
| D8.11 | D1, D7, D8 | `k3s-nixkube-decisions.md` §1, R1, D7, D8 |
| D8.12 | D7, R5 | `k3s-nixkube-decisions.md` R5, D7 |
| D8.13 | D24, D25, D26 | `oci-caph-timoni-decisions.md` F23–F25, D24–D26 |
| D8.14 | D18 | `oci-caph-timoni-decisions.md` F17, D18 |
| D8.15 | D-a | revision-2 dispatch §D-a; narrows D8.1, D8.9, D8.10 |

## Related

- ADR-006: nixidy manifest distribution; stands for `local-k3d`; its reversal is Future Work (D8.10, D8.15).
- ADR-007: the VM-test and stage plan this record's decisions are placed into; D7.15 is the scope decision D8.15 records here; D7.17 is the module tree.
- ADR-009: node management; consumes D8.3 (root object delivery) and D8.4 (digest references) at the CAPI bootstrap seam.
- ADR-010: identity tiers; the SOPS age key and cosign key of D8.9 and D8.14 are T0 material and travel by `contentFrom.secret`.
- `openspec/changes/k3s-nixos-vm-tests/specs/k3s-manifest-purity-regulator/spec.md` and `specs/k3s-platform-vm-regulator/spec.md`.
- `openspec/changes/capi-hetzner-cluster/`: the S4 stage in which `apps.k8s.oci-push` first touches GHCR.
