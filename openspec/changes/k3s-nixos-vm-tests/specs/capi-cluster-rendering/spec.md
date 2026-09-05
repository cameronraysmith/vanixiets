## ADDED Requirements

### Requirement: The cloud-invariant core renders identically across platform variants

The easykubenix cluster module SHALL render `Cluster`, `KThreesControlPlane`, `KThreesConfigTemplate`, `MachineDeployment`, `MachineHealthCheck`, the Flux install and root objects, and Cilium from a core that does not read the selected `platform`, except through a declared list of platform-owned fields (`Cluster.spec.infrastructureRef`, `KThreesControlPlane.spec.machineTemplate.infrastructureRef`, `MachineDeployment.spec.template.spec.infrastructureRef`, the node-image reference, and the CCM and CSI objects); a regulator, `capi-cloud-invariant-render`, SHALL render every variant, mask those fields, and fail on any remaining difference.
Coverage bin: T1 integrity regulator for ADR-009 D9.10; non-vacuity: the mutation below.

#### Scenario: Variants agree modulo platform-owned fields

- **WHEN** the module is rendered with `platform = hetzner`, `platform = gcp`, and `platform = aws` and the platform-owned fields are masked
- **THEN** the three rendered trees are byte-identical

#### Scenario: A platform leaks into the core

- **WHEN** a core object is changed to read `config.platform.hetzner.region` and the regulator is rebuilt
- **THEN** the regulator fails with a diff naming the object and the leaked field

### Requirement: The platform sum is total and an unhandled provider is an evaluation error

The `platform` option SHALL be a sum over `hetzner | gcp | aws | kubevirt`; selecting a name outside that set SHALL fail at evaluation with a message naming the set; selecting `kubevirt` before it is implemented SHALL fail at evaluation with a distinct "not implemented" message; a regulator, `capi-platform-sum-total`, SHALL assert both errors through `builtins.tryEval`.
Coverage bin: T1 existence regulator for ADR-009 D9.10; non-vacuity: the scenarios below are themselves the mutation.

#### Scenario: An unknown provider is selected

- **WHEN** the module is evaluated with `platform = "azure"`
- **THEN** evaluation fails and the message lists `hetzner`, `gcp`, `aws`, `kubevirt`

#### Scenario: A reserved provider is selected

- **WHEN** the module is evaluated with `platform = "kubevirt"`
- **THEN** evaluation fails with a message stating the variant is not implemented

### Requirement: Every cloud-init platform variant renders a cloud-controller manager

For every `platform` variant, when the node module's `k3s-server.bootstrap` is `cloud-init`, the rendered tree SHALL contain a `Deployment` or `DaemonSet` labelled as the variant's cloud-controller manager, and the `KThreesConfigTemplate` SHALL NOT set `disableCloudController: false` or a `cloudProviderName` other than `external`; a regulator, `capi-ccm-present`, SHALL fail when the CCM object is absent; when `bootstrap` is `clan-vars` the assertion is vacuous and the module passes `--disable-cloud-controller` as it does today.
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

### Requirement: ClusterMesh preconditions hold at evaluation

For the set of clusters that declare mesh membership, the cluster module SHALL assert at evaluation that PodCIDRs are pairwise disjoint, that `cluster.id` values are unique and non-zero, that `cluster.name` values are unique, and that every PodCIDR is contained in the shared `ipv4-native-routing-cidr`; a violation SHALL be an evaluation error, and a regulator, `clustermesh-preconditions`, SHALL assert each error through `builtins.tryEval` and assert the production declaration evaluates.
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

### Requirement: The node closure's dataplane allowlist derives from the same node set as the machine declarations

The nftables rule that allows UDP 51871 (Cilium WireGuard) from peer nodes SHALL be derived from the same value that produces `MachineDeployment` replicas and control-plane addresses, and a T1 assertion SHALL fail when the two sets differ in cardinality or membership.
Coverage bin: T1 integrity regulator for ADR-009 D9.12c and R9.h; non-vacuity: the mutation below.

#### Scenario: A node is added in one place

- **WHEN** a control-plane address is added to the allowlist source without a corresponding machine declaration
- **THEN** evaluation fails naming the address without a machine
