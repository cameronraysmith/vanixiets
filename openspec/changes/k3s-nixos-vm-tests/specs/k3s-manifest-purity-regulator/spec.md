## ADDED Requirements

### Requirement: The rendered tree contains no runtime Nix evaluation and no floating image reference

There SHALL be a regulator, `k8s-manifest-purity`, that scans every rendered manifest of the easykubenix cluster module for each target and fails when any object contains a `flakeRef` or `nixExpr` field, any image reference whose tag is `latest`, any image reference with a tag and no `@sha256:` digest, or any untagged image reference; the regulator SHALL run without `kvm` or `nixos-test` system features.
Coverage bin: T1 integrity regulator for ADR-008 D8.11; non-vacuity: the two mutations below.

#### Scenario: A runtime evaluation field appears

- **WHEN** a rendered object gains a `spec.flakeRef` or `spec.nixExpr` field and the regulator is rebuilt
- **THEN** the regulator fails naming the object and the field

#### Scenario: A floating tag appears

- **WHEN** a rendered container image is changed to `alpine/curl:latest` and the regulator is rebuilt
- **THEN** the regulator fails naming the object and the image string

### Requirement: Rendered image references are a subset of the preload set

There SHALL be a regulator, `k8s-images-preloaded`, that computes the set of image references in the rendered tree for a target and the set of image names and digests in that target's `services.k3s.images` list (each derived from the same rendered tree by string context, not maintained by hand), and fails when the first set is not contained in the second.
Coverage bin: T1 adequacy regulator for the platform leaf's hermeticity; non-vacuity: the mutation below.

#### Scenario: A workload image is added without a preload entry

- **WHEN** a new `Deployment` referencing an image absent from the preload derivation is rendered and the regulator is rebuilt
- **THEN** the regulator fails naming the image before any VM is started

### Requirement: The closure provenance report is a pure derivation

There SHALL be a derivation, `k8s-closure-provenance`, that writes, for a target, the `nix path-info -r` closure listing of the node image, the list of every OCI image digest in the preload set with the derivation that produced it, and the OCI-layout digest of the configuration artifact, and it SHALL be built without network and be byte-identical across two builds of the same flake revision.
Coverage bin: T1 traceability regulator for ADR-008 D8.12; non-vacuity: a differing flake revision produces a differing report.

#### Scenario: The report is reproducible

- **WHEN** `nix build .#checks.x86_64-linux.k8s-closure-provenance --rebuild` is run
- **THEN** the rebuilt output is byte-identical to the cached output

#### Scenario: An image is bumped

- **WHEN** one preloaded image's digest changes and the report is rebuilt
- **THEN** exactly that digest line differs between the two reports

### Requirement: Every Flux source is pinned by digest and verified

There SHALL be a regulator, `flux-sources-pinned`, that fails when any rendered `OCIRepository` lacks `spec.ref.digest`, carries `spec.ref.tag` or `spec.ref.semver` without a digest, or lacks `spec.verify.provider: cosign` with a `secretRef`; it SHALL also fail when any `GitRepository`, `HelmRepository`, or `Bucket` source is rendered, because the design admits none.
Coverage bin: T1 integrity regulator for ADR-008 D8.3, D8.4, D8.14; non-vacuity: the mutation below.

#### Scenario: A source pins a tag instead of a digest

- **WHEN** the root `OCIRepository` is rendered with `spec.ref.tag` and no `spec.ref.digest` and the regulator is rebuilt
- **THEN** the regulator fails naming the source

### Requirement: The Flux install is rendered from the Nix-packaged release manifests

There SHALL be a regulator, `flux-install-rendered`, that produces the Flux install manifest by running `flux install --export --components=source-controller,kustomize-controller,notification-controller` from `pkgs.fluxcd` in the sandbox and asserts the output contains exactly those three `Deployment`s, no `helm-controller` or `image-*-controller`, and that every image reference in it is present in the preload set.
Coverage bin: T1 existence regulator for ADR-008 D8.2; non-vacuity: the mutation below.

#### Scenario: A fourth controller is added

- **WHEN** `helm-controller` is added to the components list and the regulator is rebuilt
- **THEN** the regulator fails naming the unexpected `Deployment`

### Requirement: The published artifact's digest equals the sandbox-built digest

The `apps` effect that pushes the configuration OCI layout to GHCR SHALL, after pushing, read back the manifest digest the registry reports for the pushed tag and SHALL exit non-zero when it differs from the digest recorded in the layout derivation's output; the recorded digest is the only value any consumer pins.
This requirement rests on world assumption A16.
Coverage bin: E for the push, T3 for the same equality against the in-guest registry in `vm-k3s-platform`; non-vacuity: the mutation below.

#### Scenario: Digests agree

- **WHEN** `nix run .#apps.x86_64-linux.push-cluster-artifact` completes against GHCR
- **THEN** it prints the pushed digest, the digest returned by the registry, and exits zero because they are equal

#### Scenario: The registry reports a different digest

- **WHEN** the layout's `index.json` is altered between the derivation and the push (simulated by pushing a different layout under the same tag)
- **THEN** the effect exits non-zero naming both digests, and no consumer is updated
