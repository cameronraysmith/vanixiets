## ADDED Requirements

### Requirement: Every image and chart the platform needs is a build input

The platform regulator SHALL obtain every OCI image its rendered manifests reference — including the k3s pause and CoreDNS images and every Cilium, ArgoCD, cert-manager, step-ca, sops-secrets-operator, and helper image — from fixed-output derivations pinned by digest and passed through `services.k3s.images`, and every Helm chart from a flake input or store path, so that the regulator builds with no network.
This requirement rests on world assumption A13.

#### Scenario: An image reference is not pinned by digest

- **WHEN** a rendered manifest consumed by the regulator references an image by a floating tag such as `latest`
- **THEN** the regulator's image inventory check fails naming the reference, before any VM is started

#### Scenario: A workload needs an image that was not preloaded

- **WHEN** a pod in the regulator's guest enters `ImagePullBackOff` or `ErrImagePull`
- **THEN** the regulator fails at the readiness assertion for that workload and its diagnostics name the missing image

### Requirement: The rendered GitOps tree is consumed as the cluster consumes it

The platform regulator SHALL serve the rendered nixidy environment to ArgoCD as a git repository reachable by a `file://` URL on the node, created from a store path during activation, and ArgoCD SHALL reach every Application `Synced` and `Healthy` from that repository.

#### Scenario: All Applications sync from the local repository

- **WHEN** the app-of-apps Application is applied to the guest cluster
- **THEN** within the test timeout every Application the environment declares reports `sync.status == Synced` and `health.status == Healthy`

#### Scenario: The repository URL differs from the rendered target

- **WHEN** the rendered environment's `nixidy.target.repository` does not match the URL of the repository served on the node
- **THEN** ArgoCD reports the Applications as `Unknown` or `OutOfSync` and the regulator fails at the sync assertion

### Requirement: Certificate issuance completes without network

The platform regulator SHALL answer the hostnames named by the environment's Certificates from the guest cluster's own DNS, without forwarding to any public resolver, and SHALL assert that the step-ca ACME `ClusterIssuer` is `Ready` and every declared Certificate is `Ready`.

#### Scenario: Certificates are issued

- **WHEN** the ClusterIssuer is `Ready` and the Gateway is Programmed
- **THEN** within the test timeout `Certificate/argocd-tls` and `Certificate/test-cert-tls` report `Ready=True`

#### Scenario: A hostname is not answerable in the guest

- **WHEN** a Certificate's DNS name has no answer from the guest's CoreDNS
- **THEN** the ACME HTTP-01 challenge does not complete and the regulator fails at the Certificate assertion

### Requirement: Gateway address assignment follows production's mechanism

The platform regulator SHALL supply the Gateway's LoadBalancer address by the mechanism the production cluster declares — a `CiliumLoadBalancerIPPool`, Cilium Gateway host-network mode, or an explicitly re-enabled ServiceLB — and SHALL assert `Gateway/main-gateway` reaches `Programmed=True` with all four listeners `Accepted=True`.
A regulator that re-enables ServiceLB SHALL record that it regulates the k3d envelope rather than the production one.
This requirement rests on world assumption A15.

#### Scenario: The Gateway is Programmed under the production mechanism

- **WHEN** Cilium is ready and the production address mechanism is applied
- **THEN** within the test timeout `Gateway/main-gateway` reports `Programmed=True` and each of its four listeners reports `Accepted=True`

#### Scenario: The address mechanism is removed

- **WHEN** the `CiliumLoadBalancerIPPool` (or the equivalent for the chosen mechanism) is removed from the environment
- **THEN** the Gateway reports `AddressNotAssigned` and the regulator fails at the Programmed assertion

### Requirement: Secrets decrypt with a test-only key whose non-coverage is stated

The platform regulator SHALL install a committed test-only age private key on the node during activation and SHALL encrypt the environment's `SopsSecret` payloads to the matching public key, so that sops-secrets-operator decrypts them without any host or GitHub secret.
The regulator SHALL NOT be cited as evidence about production key provisioning, recipient management, key rotation, or the wiring of `SOPS_AGE_KEY` in any CI system.

#### Scenario: A SopsSecret decrypts

- **WHEN** sops-secrets-operator is ready and a `SopsSecret` encrypted to the test public key is applied
- **THEN** within the test timeout the operator creates the target Secret and reports no decryption error

#### Scenario: The private key is absent

- **WHEN** the test-only private key is not present on the node
- **THEN** the operator reports a decryption failure and the regulator fails at the secret assertion

### Requirement: The Chainsaw suite is the oracle

The platform regulator SHALL run the repository's Chainsaw suite for the platform inside the guest against the node's kubeconfig, SHALL fail if any Chainsaw step fails, and SHALL NOT re-implement Chainsaw's assertions in the test script.

#### Scenario: Chainsaw runs in the guest

- **WHEN** the platform workloads are applied
- **THEN** `chainsaw test` executed on the node against `/etc/rancher/k3s/k3s.yaml` exits zero and its report is copied to the test output

#### Scenario: A Chainsaw assertion is violated

- **WHEN** a Chainsaw assert file is edited to expect a listener count of five
- **THEN** the regulator fails with Chainsaw's own step failure for `infrastructure-gateway`

### Requirement: The platform regulator is one leaf unless measured cost forces a split

The platform stack SHALL be regulated by one `vm-k3s-platform` leaf; it SHALL be split into per-slice leaves only after a measured wall time exceeding fifteen minutes on the reference KVM host, and the split SHALL be recorded with the measurement.

#### Scenario: Wall time exceeds the threshold

- **WHEN** `nix build .#checks.x86_64-linux.vm-k3s-platform` completes in more than fifteen minutes on the reference host with warm image inputs
- **THEN** a follow-up change splits `vm-k3s-cilium` out first and records the measured time in its description
