## ADDED Requirements

### Requirement: The Hetzner variant of `cryolite` renders to a golden Cluster API tree

The `cryolite` easykubenix cluster module SHALL render, from `kubernetes/modules/capi/` and `kubernetes/modules/platform/hetzner.nix`, the `Cluster`, `KThreesControlPlane`, `KThreesConfigTemplate`, `MachineDeployment`, `MachineHealthCheck`, `HetznerCluster`, and two `HCloudMachineTemplate` objects (one per role) for `cryolite`; a regulator, `checks.k8s-capi-render-cryolite` (`modules/checks/k8s-capi-render.nix`), SHALL compare the rendered tree against a committed golden and fail on any difference.
Each `HCloudMachineTemplate.spec.template.spec.imageName` SHALL equal the `caph-image-name` label value the per-role snapshot derivation computes from the closure of `cryolite-server` or `cryolite-agent` (ADR-009 D9.6, D9.16), so the hash chain `clusters/cryolite → k8s-oci-cryolite → k3s-flux.nix → cryolite-server closure → snapshot label → capi-cryolite` closes in one evaluation.
`KThreesControlPlane.spec.replicas` SHALL be 1 and `MachineDeployment.spec.replicas` SHALL be 1 for the first deployment (M5, M6 of ADR-010).
Coverage bin: T1 traceability regulator for ADR-009 D9.1, D9.6, D9.16; non-vacuity: the two mutations below.

#### Scenario: The image label is the closure revision

- **WHEN** `checks.k8s-capi-render-cryolite` is built
- **THEN** both `imageName` values equal the label the snapshot derivation writes for the same closure, and the golden matches

#### Scenario: A node option changes

- **WHEN** a sysctl in `modules/nixos/k3s-server/kernel.nix` changes and the regulator is rebuilt without updating the golden
- **THEN** the regulator fails with a diff on both `imageName` fields, because the closure changed

#### Scenario: A replica count is edited

- **WHEN** `MachineDeployment.spec.replicas` is set to 2 and the regulator is rebuilt without updating the golden
- **THEN** the regulator fails with a diff naming the field

### Requirement: The `capi-cryolite` render inherits import-from-derivation freedom

The `capi-cryolite` render and `checks.k8s-capi-render-cryolite`, `k8s-capi-providers`, `k8s-capi-platform-sum`, and `k8s-capi-ccm-present` SHALL satisfy the `k3s-manifest-purity-regulator` requirement `The cryolite tree renders without import-from-derivation`; vendored CRD schemas and provider release manifests SHALL be read from flake inputs or committed JSON, and the golden comparison SHALL run inside the check's build, not at evaluation.
Coverage bin: interface rule (CI evaluation with import-from-derivation disabled); non-vacuity: the mutation below.

#### Scenario: A provider manifest is converted at evaluation time

- **WHEN** `modules/kubernetes/capi/providers.nix` reads a vendored manifest through a `runCommand` YAML-to-JSON conversion and the flake is evaluated with import-from-derivation disabled
- **THEN** evaluation fails naming the conversion derivation

### Requirement: The bootstrap template delivers T0 material only through `contentFrom.secret` and names no node

The rendered `KThreesControlPlane.spec.kthreesConfigSpec` and `KThreesConfigTemplate.spec.template.spec` SHALL set `agentConfig.airGapped: true`, SHALL carry every T0 item a node needs (`/etc/rancher/k3s/config.yaml.d/` drop-ins for the token, the pre-provisioned CA references, and the etcd-S3 credentials on the server; the Flux SOPS age-key `Secret` manifest under `/var/lib/rancher/k3s/server/manifests/` on the server; the SSH CA and cosign public material on both) as `files[]` entries whose content is `contentFrom.secret{name,key}` referencing a management-cluster `Secret` named for `cryolite` and a T0 item, never inline, and SHALL contain no node hostname, host key, or WireGuard key.
The `k8s-node-identity-free-cryolite` regulator of `k3s-nixos-vm-tests` SHALL take the rendered `capi-cryolite` tree as an additional input once it exists.
Coverage bin: T1 integrity regulator for ADR-010 D10.4, D10.6 and R10.1; non-vacuity: the two mutations below.

#### Scenario: A T0 value is inlined

- **WHEN** a `files[]` entry is changed from `contentFrom.secret` to inline `content` holding a token and the regulator is rebuilt
- **THEN** `checks.k8s-capi-render-cryolite` fails naming the path of the inlined file before the golden comparison

#### Scenario: The token drop-in is absent

- **WHEN** the `files[]` entry for the token drop-in is removed from the server template and the regulator is rebuilt
- **THEN** the regulator fails naming the missing T0 item, because the template is checked against the T0 inventory of `secrets/clusters/cryolite/`

### Requirement: The provider install is rendered from Nix and pinned by a `clusterctl.yaml` override

The management handler SHALL install the Cluster API core, CAPH, and cluster-api-k3s providers through `clusterctl init` with a `clusterctl.yaml` whose `providers[]` entries point at store paths of the Nix-vendored release manifests at pinned versions (`modules/kubernetes/capi/providers.nix`), because cluster-api-k3s is absent from clusterctl's built-in registry (ADR-009 F9.2); a regulator, `checks.k8s-capi-providers`, SHALL assert the override names exactly those three providers, each with a version and a store-path `url`, and that every image reference in the vendored manifests is digest-pinned.
Coverage bin: T1 existence regulator for ADR-009 D9.4 and F9.2; non-vacuity: the mutation below.

#### Scenario: A provider is fetched from the network

- **WHEN** a `providers[].url` in the override is changed to an `https://github.com/...` release URL and the regulator is rebuilt
- **THEN** the regulator fails naming the provider and the non-store URL

#### Scenario: The handler runs without the override

- **WHEN** `apps.k8s.mgmt-k3d` runs `clusterctl init` and the override file argument is missing
- **THEN** the effect exits non-zero before contacting the cluster, because the override path is a required argument

### Requirement: The cloud-invariant core renders identically across platform variants [S5, deferred]

The easykubenix cluster module SHALL render `Cluster`, `KThreesControlPlane`, `KThreesConfigTemplate`, `MachineDeployment`, `MachineHealthCheck`, the Flux install and root objects, and Cilium from a core that does not read the selected `platform`, except through a declared list of platform-owned fields (`Cluster.spec.infrastructureRef`, `KThreesControlPlane.spec.machineTemplate.infrastructureRef`, `MachineDeployment.spec.template.spec.infrastructureRef`, the node-image reference, and the CCM and CSI objects); a regulator, `checks.k8s-capi-core-equivalence-cryolite`, SHALL render every implemented variant, mask those fields, and fail on any remaining difference.
Until S5 lands only `hetzner` is implemented and this regulator renders one variant; it becomes non-trivial when `gcp` is added as the render-only variant (ADR-009 D9.20; `aws` is not scheduled).
Coverage bin: T1 integrity regulator for ADR-009 D9.10; non-vacuity: the mutation below.

#### Scenario: Variants agree modulo platform-owned fields

- **WHEN** the module is rendered with `platform = hetzner` and `platform = gcp` and the platform-owned fields are masked
- **THEN** the two rendered trees are byte-identical

#### Scenario: A platform leaks into the core

- **WHEN** a core object is changed to read `config.platform.hetzner.region` and the regulator is rebuilt
- **THEN** the regulator fails with a diff naming the object and the leaked field

### Requirement: The platform sum is total and an unhandled provider is an evaluation error

The `platform` option SHALL be a sum over `hetzner | gcp | aws | kubevirt` from day one (S3); selecting a name outside that set SHALL fail at evaluation with a message naming the set; selecting `kubevirt` or `aws` (declared, unimplemented; ADR-009 D9.20), or `gcp` before S5 implements it, SHALL fail at evaluation with a distinct "not implemented" message naming the variant; a regulator, `checks.k8s-capi-platform-sum`, SHALL assert both errors through `builtins.tryEval`.
Coverage bin: T1 existence regulator for ADR-009 D9.10; non-vacuity: the scenarios below are themselves the mutation.

#### Scenario: An unknown provider is selected

- **WHEN** the module is evaluated with `platform = "azure"`
- **THEN** evaluation fails and the message lists `hetzner`, `gcp`, `aws`, `kubevirt`

#### Scenario: A reserved provider is selected

- **WHEN** the module is evaluated with `platform = "kubevirt"` or `platform = "aws"`
- **THEN** evaluation fails with a message stating that variant, by name, is not implemented

### Requirement: Every cloud-init platform variant renders a cloud-controller manager

For every implemented `platform` variant, when the node module's `k3s-server.bootstrap` is `cloud-init`, the rendered tree SHALL contain a `Deployment` or `DaemonSet` labelled as the variant's cloud-controller manager, and the `KThreesConfigTemplate` SHALL NOT set `disableCloudController: false` or a `cloudProviderName` other than `external`; a regulator, `checks.k8s-capi-ccm-present`, SHALL fail when the CCM object is absent; when `bootstrap` is `clan-vars` the assertion is vacuous and the module passes `--disable-cloud-controller` as it does today.
This requirement rests on world assumption A17 and discharges ADR-009 R6 / D9.11.
Coverage bin: T1 adequacy regulator; non-vacuity: the mutation below.

#### Scenario: The CCM is present for Hetzner

- **WHEN** the module is rendered with `platform = hetzner` and `bootstrap = "cloud-init"`
- **THEN** the tree contains the hcloud cloud-controller-manager `Deployment` with an image reference in the preload set

#### Scenario: The CCM is removed

- **WHEN** the Hetzner variant's CCM object is deleted and the regulator is rebuilt
- **THEN** the regulator fails naming the variant and the missing object kind

#### Scenario: The seam is clan-vars

- **WHEN** the module is rendered with `bootstrap = "clan-vars"`
- **THEN** the regulator passes without a CCM and the `k3s-server-eval` regulator asserts `--disable-cloud-controller` is present

### Requirement: ClusterMesh preconditions hold at evaluation [S5, deferred]

For the set of clusters that declare mesh membership (empty until a second cluster exists), the cluster module SHALL assert at evaluation that PodCIDRs are pairwise disjoint, that `cluster.id` values are unique and non-zero, that `cluster.name` values are unique, and that every PodCIDR is contained in the shared `ipv4-native-routing-cidr`; a violation SHALL be an evaluation error, and a regulator, `clustermesh-preconditions`, SHALL assert each error through `builtins.tryEval` and assert the production declaration evaluates.
This requirement rests on world assumption A18 and implements ADR-009 D9.13.
Coverage bin: T1 integrity regulator; non-vacuity: the scenarios below are themselves the mutation.

#### Scenario: PodCIDRs overlap

- **WHEN** two meshed clusters are declared with `10.42.0.0/16` and `10.42.128.0/17`
- **THEN** evaluation fails naming both clusters and both CIDRs

#### Scenario: A PodCIDR escapes the native-routing CIDR

- **WHEN** a meshed cluster declares PodCIDR `10.50.0.0/16` under a native-routing CIDR of `10.40.0.0/13`
- **THEN** evaluation fails naming the cluster and both CIDRs

#### Scenario: The production declaration evaluates

- **WHEN** the committed cluster set is evaluated
- **THEN** evaluation succeeds and the regulator passes

### Requirement: The node closure's dataplane allowlist derives from the same node set as the machine declarations [S5, deferred]

Within one Hetzner cluster the Cilium WireGuard dataplane runs over the CAPH private network and needs no public allowlist; when a second cloud is meshed, the nftables rule that allows UDP 51871 (Cilium WireGuard) from peer nodes over public addresses SHALL be derived from the same value that produces `MachineDeployment` replicas and control-plane addresses, and a T1 assertion SHALL fail when the two sets differ in cardinality or membership.
Coverage bin: T1 integrity regulator for ADR-009 D9.12c and R9.h; non-vacuity: the mutation below.

#### Scenario: A node is added in one place

- **WHEN** a control-plane address is added to the allowlist source without a corresponding machine declaration
- **THEN** evaluation fails naming the address without a machine
