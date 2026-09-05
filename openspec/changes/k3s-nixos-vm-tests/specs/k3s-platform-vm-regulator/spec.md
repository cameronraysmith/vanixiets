## ADDED Requirements

### Requirement: Every image and chart the platform needs is a build input

The platform regulator SHALL obtain every OCI image its rendered manifests reference — including the k3s pause and CoreDNS images and every Cilium, Flux, cert-manager, step-ca, and helper image — from fixed-output derivations pinned by digest or from nix2container/nix-snapshotter outputs, passed through `services.k3s.images`, and every Helm chart from a flake input or store path, so that the regulator builds with no network.
The preload set SHALL be derived from the rendered tree, not maintained by hand.
This requirement rests on world assumption A13 and on the `k3s-manifest-purity-regulator` requirement `Rendered image references are a subset of the preload set`.
Coverage bin: T3 integrity regulator for hermeticity; non-vacuity: the two scenarios below.

#### Scenario: An image reference is not pinned by digest

- **WHEN** a rendered manifest consumed by the regulator references an image by a floating tag such as `latest`
- **THEN** the regulator's image inventory check fails naming the reference, before any VM is started

#### Scenario: A workload needs an image that was not preloaded

- **WHEN** a pod in the regulator's guest enters `ImagePullBackOff` or `ErrImagePull`
- **THEN** the regulator fails at the readiness assertion for that workload and its diagnostics name the missing image

### Requirement: Flux consumes a digest-pinned, signature-verified OCI artifact from an in-guest registry

The platform regulator SHALL install Flux from the manifest `services.k3s.manifests` carries in the node closure (rendered by `flux install --export` from `pkgs.fluxcd`, exactly the source, kustomize, and notification controllers), SHALL run a registry inside the guest seeded during activation from the sandbox-built OCI image layout of the rendered easykubenix tree, SHALL point the root `OCIRepository` at `oci://localhost:<port>/<name>` with `spec.ref.digest` equal to the digest the layout derivation recorded and `spec.verify.provider: cosign` with a test-only public key, and SHALL assert the root `Kustomization` reaches `Ready=True` with `status.lastAppliedRevision` ending in that digest.
No image SHALL traverse the in-guest registry; images arrive through `services.k3s.images`.
Coverage bin: T3 adequacy regulator for ADR-008 D8.1–D8.3, D8.6, D8.14; non-vacuity: the two mutations below.

#### Scenario: The root Kustomization applies the pinned digest

- **WHEN** Flux's controllers are `Ready` and the in-guest registry serves the seeded layout
- **THEN** within the test timeout the root `OCIRepository` reports `Ready=True` with `status.artifact.revision` ending in the recorded digest and the root `Kustomization` reports `Ready=True` with `status.lastAppliedRevision` ending in the same digest

#### Scenario: The digest does not match the seeded layout

- **WHEN** `spec.ref.digest` on the root `OCIRepository` is replaced with the digest of a different layout
- **THEN** the `OCIRepository` reports a fetch failure naming the digest and the regulator fails at the readiness assertion

#### Scenario: The signature does not verify

- **WHEN** the artifact is signed with a key whose public half is not the one in `spec.verify`
- **THEN** the `OCIRepository` reports `SourceVerified=False` and the regulator fails at the readiness assertion

### Requirement: Certificate issuance completes without network

The platform regulator SHALL answer the hostnames named by the rendered tree's Certificates from the guest cluster's own DNS, without forwarding to any public resolver, and SHALL assert that the step-ca ACME `ClusterIssuer` is `Ready` and every declared Certificate is `Ready`.
Coverage bin: T3 adequacy for the certificate chain; non-vacuity: the DNS mutation below.

#### Scenario: Certificates are issued

- **WHEN** the ClusterIssuer is `Ready` and the Gateway is Programmed
- **THEN** within the test timeout every Certificate the rendered tree declares (today `Certificate/test-cert-tls`; `Certificate/argocd-tls` is deleted with ArgoCD) reports `Ready=True`

#### Scenario: A hostname is not answerable in the guest

- **WHEN** a Certificate's DNS name has no answer from the guest's CoreDNS
- **THEN** the ACME HTTP-01 challenge does not complete and the regulator fails at the Certificate assertion

### Requirement: Gateway address assignment follows production's mechanism

The platform regulator SHALL supply the Gateway's LoadBalancer address through a `CiliumLoadBalancerIPPool` declared by the cluster module, with ServiceLB disabled as the production module disables it, and SHALL assert `Gateway/main-gateway` reaches `Programmed=True` with all four listeners `Accepted=True`.
This requirement rests on world assumption A15.
Coverage bin: T3 adequacy for ADR-007 D7.9; non-vacuity: the mutation below.

#### Scenario: The Gateway is Programmed under the production mechanism

- **WHEN** Cilium is ready and the production address mechanism is applied
- **THEN** within the test timeout `Gateway/main-gateway` reports `Programmed=True` and each of its four listeners reports `Accepted=True`

#### Scenario: The address mechanism is removed

- **WHEN** the `CiliumLoadBalancerIPPool` is removed from the rendered tree
- **THEN** the Gateway reports `AddressNotAssigned` and the regulator fails at the Programmed assertion

### Requirement: Secrets decrypt with a test-only key whose non-coverage is stated

The platform regulator SHALL install a committed test-only age private key as the `sops-age` Secret in `flux-system` during activation and SHALL encrypt the rendered tree's SOPS-encrypted Secrets to the matching public key, so that kustomize-controller's `decryption.provider: sops` decrypts them without any host or GitHub secret; a test-only cosign keypair is installed the same way for artifact signing and verification.
The regulator SHALL NOT be cited as evidence about production key provisioning through Clan vars generators, recipient management, key rotation, or the wiring of `SOPS_AGE_KEY` in any CI system.
Coverage bin: T3 adequacy for ADR-008 D8.9 and D8.14 in the test envelope only; non-vacuity: the mutation below.

#### Scenario: An encrypted Secret decrypts

- **WHEN** kustomize-controller applies a `Kustomization` with `decryption.provider: sops` whose tree contains a Secret encrypted to the test public key
- **THEN** within the test timeout the plaintext Secret exists in the target namespace and the `Kustomization` reports no decryption error

#### Scenario: The private key is absent

- **WHEN** the `sops-age` Secret is not present in `flux-system`
- **THEN** the `Kustomization` reports a decryption failure and the regulator fails at the secret assertion

### Requirement: The Chainsaw suite is the oracle

The platform regulator SHALL run the repository's Chainsaw suite for the platform inside the guest against the node's kubeconfig, SHALL fail if any Chainsaw step fails, and SHALL NOT re-implement Chainsaw's assertions in the test script.
The suite's ArgoCD assertions SHALL be replaced by Flux `Kustomization` readiness and `lastAppliedRevision` assertions; the sops-secrets-operator assertion SHALL be replaced by the decrypted-Secret assertion above; the cert-manager, step-ca, ClusterIssuer, and Gateway assertions are unchanged.
Coverage bin: T3 traceability regulator; non-vacuity: the mutation below.

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
