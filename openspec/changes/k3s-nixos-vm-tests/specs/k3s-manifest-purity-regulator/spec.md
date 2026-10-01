## ADDED Requirements

### Requirement: The rendered tree contains no runtime Nix evaluation and no floating image reference

There SHALL be a regulator, `checks.k8s-purity-cryolite` (`modules/kubernetes/purity.nix`), that scans every rendered manifest of the `cryolite` easykubenix cluster module for each target and fails when any object contains a `flakeRef` or `nixExpr` field, any image reference whose tag is `latest`, any image reference with a tag and no `@sha256:` digest, or any untagged image reference; the regulator SHALL run without `kvm` or `nixos-test` system features.
Coverage bin: T1 integrity regulator for ADR-008 D8.11; non-vacuity: the two mutations below.

#### Scenario: A runtime evaluation field appears

- **WHEN** a rendered object gains a `spec.flakeRef` or `spec.nixExpr` field and the regulator is rebuilt
- **THEN** the regulator fails naming the object and the field

#### Scenario: A floating tag appears

- **WHEN** a rendered container image is changed to `alpine/curl:latest` and the regulator is rebuilt
- **THEN** the regulator fails naming the object and the image string

### Requirement: The `cryolite` tree renders without import-from-derivation

The `cryolite` easykubenix cluster module, `k8s-manifests-cryolite`, `k8s-oci-cryolite`, and every `k8s-*` and `flux-*` leaf of this change SHALL evaluate on every system in the flake's `systems` with `allow-import-from-derivation = false`; Helm releases, CRDs, and upstream YAML SHALL enter evaluation only as committed JSON goldens under `kubernetes/tests/cryolite/golden/` or as files of a flake input read without a build, never through a derivation output read at evaluation time (easykubenix `helm.nix` `chart2json`, `importyaml.nix` `yaml2json`, or any `runCommand` passed to `importJSON`, `readFile`, `pathExists`, or `builtins.path`).
A regulator, `checks.k8s-render-golden-cryolite`, SHALL re-render every Helm release and YAML import from the same flake inputs inside the sandbox and fail, naming the object, when the result differs from the committed golden; a recipe regenerates the goldens.
This requirement rests on world assumption A13.
Coverage bin: T1 integrity regulator for R2 and R17 (golden drift) plus an interface rule (the CI evaluation runs with import-from-derivation disabled); non-vacuity: the mutations below.

#### Scenario: The render evaluates with import-from-derivation disabled

- **WHEN** `nix eval --option allow-import-from-derivation false .#checks.<system> --apply builtins.attrNames` and `.#packages.<system>.k8s-manifests-cryolite.drvPath` are run for `x86_64-linux`, `aarch64-linux`, and `aarch64-darwin`
- **THEN** each evaluation succeeds and no derivation is built

#### Scenario: A chart is rendered at evaluation time

- **WHEN** a module under `kubernetes/clusters/cryolite` or `kubernetes/modules` is changed to `lib.importJSON (pkgs.chart2json …)` and the flake is evaluated with import-from-derivation disabled
- **THEN** evaluation fails with "cannot build '…' during evaluation because the option 'allow-import-from-derivation' is disabled", naming the derivation

#### Scenario: A chart input is bumped without regenerating the golden

- **WHEN** `cilium-src` is bumped to a release whose rendered `DaemonSet` differs and `checks.k8s-render-golden-cryolite` is rebuilt without regenerating the goldens
- **THEN** the regulator fails naming the `DaemonSet`, and regenerating the goldens through the recipe makes it pass

### Requirement: Rendered image references are a subset of the preload set

The same `checks.k8s-purity-cryolite` regulator SHALL compute the set of image references in the rendered `cryolite` tree for a target and the set of image names and digests in that target's `services.k3s.images` list (each derived from the same rendered tree by string context, not maintained by hand), and fails when the first set is not contained in the second.
Coverage bin: T1 adequacy regulator for the platform leaf's hermeticity; non-vacuity: the mutation below.

#### Scenario: A workload image is added without a preload entry

- **WHEN** a new `Deployment` referencing an image absent from the preload derivation is rendered and the regulator is rebuilt
- **THEN** the regulator fails naming the image before any VM is started

### Requirement: The closure provenance report is a pure derivation

There SHALL be a derivation, `checks.k8s-provenance-cryolite` (`modules/kubernetes/provenance.nix`), that writes, for a target, the `nix path-info -r` closure listing of the `cryolite-server` node image, the list of every OCI image digest in the preload set with the derivation that produced it, and the OCI-layout digest of the configuration artifact, and it SHALL be built without network and be byte-identical across two builds of the same flake revision.
Coverage bin: T1 traceability regulator for ADR-008 D8.12; non-vacuity: a differing flake revision produces a differing report.

#### Scenario: The report is reproducible

- **WHEN** `nix build .#checks.x86_64-linux.k8s-provenance-cryolite --rebuild` is run
- **THEN** the rebuilt output is byte-identical to the cached output

#### Scenario: An image is bumped

- **WHEN** one preloaded image's digest changes and the report is rebuilt
- **THEN** exactly that digest line differs between the two reports

### Requirement: No rendered artifact names a node or a node key

There SHALL be a regulator, `checks.k8s-node-identity-free-cryolite` (`modules/kubernetes/identity.nix`), that evaluates the rendered Flux artifact of `cryolite`, the sops file index under `secrets/clusters/cryolite/`, the Clan inventory, and, once the sibling change renders them, the `capi-cryolite` Cluster API objects, and fails when any of them contains a node hostname pattern (`cryolite-server-*`, `cryolite-agent-*`, a CAPI `Machine` name), an SSH host key or its fingerprint, a Cilium WireGuard public key, or a `CiliumNode` name; it SHALL run without `kvm` or `nixos-test`.
T1 node identity is disposable and never referenced outside the cluster (ADR-010 D10.1, D10.6); the regulator makes that a property of the repository rather than a habit.
Coverage bin: T1 integrity regulator for ADR-010 R10.1; non-vacuity: the two mutations below.

#### Scenario: A Secret is keyed by a node name

- **WHEN** a sops-encrypted file `secrets/clusters/cryolite/cryolite-server-0.yaml` is added and the regulator is rebuilt
- **THEN** the regulator fails naming the file and the node pattern

#### Scenario: The Clan inventory gains a node

- **WHEN** an inventory entry `machines.cryolite-agent` is added and the regulator is rebuilt
- **THEN** the regulator fails naming the entry; k3s nodes are not Clan machines

### Requirement: The node image closure contains no T0 private material

There SHALL be a regulator, `checks.k8s-closure-secret-free-cryolite`, that walks the `nix path-info -r` closure of the `cryolite-server` and `cryolite-agent` images and fails when any path contains a sops-encrypted file from `secrets/clusters/cryolite/`, a private-key fingerprint from the T0 set, or the test-only fixture private keys; public material (authorized keys, the SSH CA public key, the cosign public key) is allowed.
Snapshots are secret-free and per role (ADR-010 D10.4); T0 material reaches a node only at first boot.
Coverage bin: T1 integrity regulator for ADR-010 R10.2; non-vacuity: the mutation below.

#### Scenario: A private key is baked in

- **WHEN** the test-only age private key is added to `environment.etc` of `cryolite-server` and the regulator is rebuilt
- **THEN** the regulator fails naming the store path that carries the key

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
