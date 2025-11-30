# Story 7.2: CPU-Only Togglable Node Definition and Deployment

Status: in-progress

## Story

As a system administrator,
I want to define CPU-only GCP compute instances with an enabled/disabled toggle,
so that I can control costs by disabling nodes when not in use while maintaining infrastructure-as-code definitions.

## Context

Story 7.2 builds on the GCP terranix module foundation established in Story 7.1.
The module structure, provider configuration, SSH key generation, firewall rules, and instance template are already implemented.
This story focuses on configuration and deployment validation rather than structural changes.

**Business Drivers:**
- GCP contract obligations
- Cost-effective CPU compute for general workloads
- Toggle mechanism for cost control (disabled = zero ongoing cost)

**Machine Type Selection:**
Per user guidance: use `e2-standard-8` (8 vCPU, 32GB RAM) for initial deployment.
e2-* family is typically 20-30% cheaper than n2-* for equivalent specs.

## Acceptance Criteria

1. CPU-only machine entries defined in `modules/terranix/gcp.nix` `machines` attribute set
2. At least one machine uses `e2-standard-8` machine type (8 vCPU, 32GB RAM)
3. Machines default to `enabled = false` for cost control
4. Toggle mechanism validated: `nix run .#terraform.plan` shows 0 resources when all disabled
5. Toggle mechanism validated: enabling a machine adds expected resources to plan
6. At least one node deployed successfully via `nix run .#terraform.apply`
7. `clan machines install` provisioner executes successfully for deployed node
8. SSH connectivity validated from darwin workstation to deployed GCP node
9. Zerotier not required for this story (Story 7.4 scope), but machine should be SSH-accessible via external IP
10. Basic cost documentation in Dev Notes (approximate hourly rate for e2-standard-8)

## Tasks / Subtasks

- [x] Task 1: Define CPU-only machine entries (AC: #1, #2, #3)
  - [x] Uncomment and populate `machines` attribute in `modules/terranix/gcp.nix`
  - [x] Add `galena` entry with `machineType = "e2-standard-8"`
  - [x] Set `enabled = false` as default
  - [x] Add `zone = "us-central1-b"` (or allow default)
  - [x] Add descriptive `comment` field

- [ ] Task 1A: Create minimal clan machine definition for galena (AC: #7)
  - [ ] Create `modules/machines/nixos/galena/default.nix` following cinnabar pattern
  - [ ] Define minimal NixOS configuration (bootloader, networking, SSH)
  - [ ] Configure for GCP-specific requirements (console access, metadata)

- [ ] Task 1B: Add galena to clan inventory (AC: #7)
  - [ ] Add galena entry to `modules/clan/machines.nix`
  - [ ] Assign tags: `["nixos", "vps", "cloud", "gcp"]`
  - [ ] Note: Zerotier service instance deferred to Story 7.4

- [x] Task 2: Validate toggle mechanism - disabled state (AC: #4)
  - [x] Run `nix run .#terraform.plan` with all machines disabled
  - [x] Verify plan shows no new compute_instance resources
  - [x] Document expected output (firewall rules + SSH key only)

- [x] Task 3: Validate toggle mechanism - enabled state (AC: #5)
  - [x] Set `galena.enabled = true`
  - [x] Run `nix run .#terraform.plan`
  - [x] Verify plan shows `google_compute_instance.galena` to be created
  - [x] Verify plan shows `null_resource.install-gcp-galena` provisioner

- [ ] Task 4: Deploy test node (AC: #6, #7)
  - [ ] Run `nix run .#terraform.apply` to provision GCP instance
  - [ ] Monitor provisioner execution (`clan machines install`)
  - [ ] Capture provisioner output in Debug Log References
  - [ ] Note external IP from terraform output

- [ ] Task 5: Validate SSH connectivity (AC: #8, #9)
  - [ ] SSH to deployed node: `ssh -i terraform/.gcp-terraform-deploy-key root@<external-ip>`
  - [ ] Verify NixOS installed and operational
  - [ ] Note: zerotier integration deferred to Story 7.4

- [ ] Task 6: Cost documentation and cleanup (AC: #10)
  - [ ] Document e2-standard-8 hourly cost in Dev Notes
  - [ ] Set machine back to `enabled = false` after validation
  - [ ] Run `nix run .#terraform.apply` to destroy instance (cost control)

## Dev Notes

### Story 7.1 Foundation Already Provides

Story 7.1 created the complete GCP terranix module (`modules/terranix/gcp.nix`, 172 lines) with:

- `flake.modules.terranix.gcp` namespace
- `hashicorp/google` provider v7.x
- Service account credentials via `clan secrets get gcp-service-account-json`
- ED25519 SSH key generation (`tls_private_key.gcp_deploy_key`)
- Firewall rules: SSH (tcp/22) and ZeroTier (udp/51820)
- Instance template consuming `cfg.machineType`, `cfg.zone or defaultZone`
- Provisioner pattern: `null_resource.install-gcp-${name}` with `clan machines install`
- Toggle mechanism: `enabledMachines = lib.filterAttrs (_name: cfg: cfg.enabled) machines;`

**Story 7.2 scope is configuration and deployment, not structural changes.**

### Gap Resolution (Party Mode Decision)

During implementation, the `dev-story` agent discovered a planning gap: Acceptance Criteria #7 requires `clan machines install` to succeed, but the original story scope explicitly excluded clan integration ("Clan inventory integration (Story 7.4)").

**The Party Mode team resolved this on 2025-11-30:**

1. **Scope Expansion**: Minimal clan machine definition is now IN SCOPE for Story 7.2
   - Required for AC #7: provisioner validation needs clan machine configuration
   - Ensures terraform provisioner can execute `clan machines install galena` successfully

2. **What's IN SCOPE (Story 7.2)**:
   - Minimal clan machine definition (`modules/machines/nixos/galena/default.nix`)
   - Clan inventory entry (`modules/clan/machines.nix`)
   - Basic NixOS configuration for GCP deployment (bootloader, networking, SSH)

3. **What remains OUT OF SCOPE (Story 7.4)**:
   - Zerotier service integration and mesh networking
   - Full clan vars deployment and configuration management
   - Multi-machine coordination features

4. **Naming Decision**: Metallurgical naming theme
   - CPU node: `galena` (lead ore mineral, replacing generic `gcp-cpu-1`)
   - GPU node: `scheelite` (tungsten ore mineral, for Story 7.3 reference)

**Rationale**: The terraform provisioner pattern established in Story 7.1 calls `clan machines install`, which requires a valid clan machine definition.
Minimal clan configuration is necessary infrastructure, distinct from full clan orchestration features deferred to Story 7.4.

**Pattern Reference**: Follow `modules/machines/nixos/cinnabar/default.nix` structure for GCP-specific adaptations (console access, metadata service, GRUB BIOS bootloader).

### Machine Type Reference

| Family | Type | vCPU | RAM | Approximate Cost (us-central1) |
|--------|------|------|-----|--------------------------------|
| e2-standard | e2-standard-8 | 8 | 32GB | ~$0.27/hr (~$195/month) |
| n2-standard | n2-standard-8 | 8 | 32GB | ~$0.39/hr (~$280/month) |

e2-standard-8 selected per user guidance for cost-effectiveness.

### GCP Configuration Values

From Story 7.1 implementation:
- Project: `pyro-284215`
- Default Zone: `us-central1-b`
- Default Region: `us-central1`

### Expected Machine Definition

```nix
machines = {
  galena = {
    enabled = false;  # Toggle for cost control
    machineType = "e2-standard-8";  # 8 vCPU, 32GB RAM
    zone = "us-central1-b";
    image = "debian-12";
    comment = "CPU-only GCP node (~$0.27/hr) - named for lead ore mineral";
  };
};
```

### Learnings from Previous Story

**From Story 7.1 (Status: done - APPROVED)**

- **Module Created**: `modules/terranix/gcp.nix` (172 lines) with complete structure
- **Provider Version**: hashicorp/google 7.10.0 (constraint `~> 7.0`)
- **Secret Prerequisite**: `gcp-service-account-json` clan secret already created
- **Terraform Plan Validated**: 4 base resources (2 firewall rules, SSH keypair, credentials read)
- **Review Advisory Notes**:
  - Consider narrowing firewall source_ranges post-deployment if static admin IPs available
  - Consider making gcpProject configurable via clan vars for multi-project scenarios
  - Add nix-unit tests for GCP resources in Stories 7.2-7.4

[Source: docs/notes/development/work-items/7-1-terranix-gcp-provider-base-config.md#Dev-Agent-Record]

### References

- [Pattern Template: modules/terranix/gcp.nix]
- [Source: docs/notes/development/epics/epic-7-gcp-multi-node-infrastructure.md#Story-7.2]
- [Architecture: docs/notes/development/architecture/deployment-architecture.md#Terraform-Deployment]
- [Story 7.1: docs/notes/development/work-items/7-1-terranix-gcp-provider-base-config.md]
- [Upstream: GCP Compute Instance Pricing](https://cloud.google.com/compute/vm-instance-pricing)

### NFR Coverage

| NFR | Coverage |
|-----|----------|
| NFR-7.2 (Cost management) | Default `enabled = false`, toggle validation, cost documentation |

### Estimated Effort

**2-3 hours** (configuration and deployment validation)

- Machine definition and toggle validation: 0.5-1 hour
- Deployment and provisioner execution: 0.5-1 hour
- SSH validation and documentation: 0.5-1 hour

## Dev Agent Record

### Context Reference

<!-- Path(s) to story context XML will be added here by context workflow -->

### Agent Model Used

{{agent_model_name_version}}

### Debug Log References

### Completion Notes List

### File List

## Change Log

**2025-11-30 (Gap Resolution - Party Mode Decision)**:
- Scope expanded: Minimal clan machine definition now in scope (required for AC #7)
- Naming updated: gcp-cpu-1 → galena (metallurgical naming theme)
- New tasks added: Task 1A (clan machine definition), Task 1B (clan inventory)
- Story 7.4 scope clarified: Zerotier integration, mesh networking remain deferred
- GPU node name established: scheelite (for Story 7.3 reference)

**2025-11-30 (Story Drafted)**:
- Story file created from Epic 7, Story 7.2 specification
- Context from Story 7.1 completion incorporated
- Machine type selection per user guidance: e2-standard-8
- Cost documentation scope simplified per user request
- Estimated effort: 2-3 hours
