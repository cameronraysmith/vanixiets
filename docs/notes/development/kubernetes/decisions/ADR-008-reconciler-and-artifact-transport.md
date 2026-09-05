# ADR-008: Reconciler and artifact transport

## Status

Proposed (2026-09-04).
Design only; no flake input, production module, or workflow changes land with this record.
Implemented by stages S0 and S2 of `openspec/changes/k3s-nixos-vm-tests/`.
Reverses ADR-006.

## Context

ADR-007 re-expresses the k3d `test-cluster` workflow as NixOS VM tests and pure checks.
Doing so exposed that the reconciler and the transport of desired state were the k3d workflow's least hermetic parts: ArgoCD read a git repository mounted from the Docker host, nixidy rendered it, secrets arrived through `SOPS_AGE_KEY` from GitHub Secrets, and the private manifest repository of ADR-006 existed to keep Helm-generated Secrets out of the public tree.
None of those pieces can be expressed as a store path with a known digest, so none of them can be regulated by a `checks.<system>.<name>` leaf without a network.

This record fixes how desired state reaches a cluster, which reconciler applies it, how images and configuration are packaged, and where the only effects (registry pushes) live.
The node-management and networking half of the design is ADR-009.

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

### D8.1: Flux is the reconciler

Flux (source-controller, kustomize-controller, notification-controller) replaces ArgoCD.
The reasons are the three F8.1 properties: offline install from a Nixpkgs package, digest-pinned OCI sources, and signature verification with a key that can live in the node closure.
ArgoCD has no equivalent of `.spec.ref.digest` for a git source and would require the ADR-006 repository to remain.
Chainsaw's ArgoCD assertions are replaced by `Kustomization` readiness and `status.lastAppliedRevision` equality with the pinned digest.

### D8.2: Flux is installed from `flux install --export` rendered in Nix, three controllers, images preloaded

A derivation runs `flux install --export --components=source-controller,kustomize-controller,notification-controller` from `pkgs.fluxcd` and captures the manifest.
No helm-controller (charts are rendered by easykubenix at evaluation), no image-reflector or image-automation controllers (the artifact is pinned, not discovered), no flux-operator.
The three controller images are preloaded through `services.k3s.images` by digest.
The rendered install manifest is a T1 artifact: the S0 purity leaf inspects it like any other rendered object.

### D8.3: bootstrap from `services.k3s.manifests`; the root `OCIRepository` carries a digest

Flux's install manifest and the CRDs it needs are placed in the node closure through `services.k3s.manifests`, which k3s applies from `/var/lib/rancher/k3s/server/manifests` at start (`rancher/default.nix:533`).
The root `OCIRepository` and root `Kustomization` are also rendered in Nix.
`OCIRepository.spec.ref.digest` is the digest of the OCI layout built in the sandbox (D8.5), so the node closure names the exact configuration the cluster will converge on.
Where the root object lives differs by target: in VM leaves it is baked into the same `services.k3s.manifests` (one hash, the VM is rebuilt anyway); on CAPI-managed nodes it is delivered per cluster through `KThreesConfig.spec.files` so that a configuration change does not roll nodes (ADR-009 D9.7).

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

### D8.7: publishing is an `apps` effect that asserts digest equality

`nix run .#apps.<system>.push-cluster-artifact` pushes the OCI layout to GHCR and then reads back the digest of the pushed manifest.
The effect fails if the registry's digest differs from the digest recorded in the derivation.
This is the only place the configuration artifact touches a network, and it never runs under `nix flake check`.
The same shape applies to `copyToRegistry` for portable images.

### D8.8: nixpod layering is carried over; a multi-architecture index only when arm64 is real

Portable images use nixpod's explicit layer ordering by change frequency.
The Crane `index append` step is adopted only when a second architecture is actually targeted (Hetzner arm64 CAX instances); until then every push is single-architecture and the manifest digest, not an index digest, is what consumers pin.

### D8.9: Flux SOPS decryption with a per-cluster age key; sops-secrets-operator retired after cutover

The kustomize-controller decrypts SOPS-encrypted Secrets inside the artifact using `spec.decryption.provider: sops` with a `flux-system/sops-age` Secret.
The per-cluster age key is generated by a Clan vars generator, delivered to the node by sops-nix, and mirrored into `flux-system/sops-age` by a `services.k3s.manifests` entry that reads the vars file at activation.
sops-secrets-operator stays until the first cluster converges through Flux SOPS; then it is deleted together with its Chainsaw assertion.
The VM leaf substitutes a committed test-only age keypair for the Clan generator (ADR-007 Q5).

### D8.10: ADR-006 is reversed

ADR-006 introduced a private manifest repository because nixidy rendered Helm-generated Secrets into the tree.
With Secrets SOPS-encrypted inside the OCI artifact and decrypted only in the cluster, the artifact can be public and the repository is unnecessary.
The `file:///manifests` pattern, the `local-k3d-ci` nixidy environment, and the T1 grep for it are retired with it.

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

The `apps` push effect signs the artifact with a cosign key pair generated by a Clan vars generator; the public key is placed in the node closure and mirrored into a Secret referenced by `OCIRepository.spec.verify.secretRef`.
Keyless (OIDC) verification is rejected because it requires network access to Fulcio and Rekor at verification time, which the VM leaf cannot provide.
The VM leaf signs the in-guest artifact with a test-only key pair and verifies against its public half.

## Requirements carried into the OpenSpec delta specs

| Code | Requirement | Regulator | Tier |
|---|---|---|---|
| R8.1 | rendered tree contains no `flakeRef`, `nixExpr`, `:latest`, or unpinned image reference | `k8s-manifest-purity` | T1 |
| R8.2 | rendered image references ⊆ preload set | `k8s-images-preloaded` | T1 |
| R8.3 | closure provenance report exists and agrees with R8.2 | `k8s-closure-provenance` | T1 |
| R8.4 | every `OCIRepository` carries `spec.ref.digest` and `spec.verify` | `flux-sources-pinned` | T1 |
| R8.5 | Flux install manifest contains exactly the three controllers | `flux-install-rendered` | T1 |
| R8.6 | OCI-layout digest equals registry digest after push | `push-cluster-artifact` | E |
| R8.7 | Flux converges from the in-guest registry with SOPS decryption and signature verification | `vm-k3s-platform` | T3 |

## Verified versus inferred

| Code | Claim | Status | Discharging regulator |
|---|---|---|---|
| R8.a | `flux install --export` from `pkgs.fluxcd` needs no network | read in source (F8.1) | `flux-install-rendered` (S0) |
| R8.b | `OCIRepository.spec.ref.digest` selects an immutable artifact | read in docs (F8.1) | `vm-k3s-platform` (S2) |
| R8.c | an OCI layout built by `oras`/`crane` in the sandbox has the same manifest digest after `crane push` | inferred; digests are content-addressed but the push tool must not re-encode the manifest | `push-cluster-artifact` digest-equality assertion (S4 is the first real push; S2 proves it against the in-guest registry) |
| R8.d | kustomize-controller decrypts SOPS with an age key from `flux-system/sops-age` | read in Flux docs | `vm-k3s-platform` (S2) |
| R8.e | keyed cosign verification needs no network | read in docs (`ocirepositories.md:563`) | `vm-k3s-platform` (S2) |
| R8.f | a `services.k3s.manifests` entry can mirror a sops-nix–delivered file into a Secret at activation | inferred from `rancher/default.nix:533` and sops-nix's activation ordering | `vm-k3s-platform` (S2) with the fixture key |

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

## Related

- ADR-006: nixidy manifest distribution; reversed by D8.10.
- ADR-007: the VM-test and stage plan this record's decisions are placed into.
- ADR-009: node management; consumes D8.3 (root object delivery) and D8.4 (digest references) at the CAPI bootstrap seam.
- `openspec/changes/k3s-nixos-vm-tests/specs/k3s-manifest-purity-regulator/spec.md` and `specs/k3s-platform-vm-regulator/spec.md`.
