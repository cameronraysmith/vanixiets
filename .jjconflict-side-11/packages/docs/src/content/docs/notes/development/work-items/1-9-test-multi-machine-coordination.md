---
title: "Story 1.9: Test multi-machine coordination across Hetzner + GCP"
---

Status: drafted

## Story

As a system administrator,
I want to validate multi-machine coordination features across Hetzner and GCP VMs,
So that I can confirm clan inventory and service instances work correctly in multi-cloud environment.

## Context

Story 1.9 validates multi-machine coordination capabilities after successful Hetzner + GCP deployments.
This tests clan inventory service instances, vars sharing, and coordination patterns critical for Phase 1+ multi-host infrastructure.

**Coordination Patterns**: Clan inventory enables service instances with roles (controller/peer, server/client) that coordinate across machines.
This story validates these patterns work correctly across cloud providers.

**Foundation for Phase 1+**: Multi-machine coordination patterns tested here are essential for Phase 1 (cinnabar + darwin hosts) and Phase 2+ (multiple darwin hosts coordinating).

## Acceptance Criteria

1. 2-machine zerotier network fully operational:
   - Hetzner VM (controller role) online
   - GCP VM (peer role) online
   - Full mesh connectivity: bidirectional ping successful
   - Network latency acceptable (< 200ms, varies by region)
2. SSH via zerotier works in both directions:
   - From Hetzner to GCP via zerotier IP
   - From GCP to Hetzner via zerotier IP
   - Certificate-based authentication functional
3. Clan service instances deployed correctly:
   - emergency-access on both machines (root access recovery)
   - sshd-clan server + client roles on both machines
   - users-root on both machines
4. Vars shared appropriately (if any configured with share = true)
5. Multi-machine rebuild test successful:
   - Update shared configuration affecting both machines
   - Rebuild both machines: `nixos-rebuild switch`
   - Validate changes applied identically
6. Service coordination test successful:
   - Modify service instance setting (e.g., zerotier config)
   - Verify change propagates to both machines
   - Confirm services coordinate correctly after change
7. Network stability validated: 24-hour monitoring shows no disconnections or errors

## Tasks / Subtasks

- [ ] Validate zerotier mesh network (AC: #1)
  - [ ] Check Hetzner controller status: `ssh root@<hetzner-ip> "zerotier-cli info"`
  - [ ] Check GCP peer status: `ssh root@<gcp-ip> "zerotier-cli info"`
  - [ ] List networks on both machines: `zerotier-cli listnetworks`
  - [ ] Test bidirectional ping:
    - From Hetzner to GCP: `ssh root@<hetzner-ip> "ping -c 5 <gcp-zerotier-ip>"`
    - From GCP to Hetzner: `ssh root@<gcp-ip> "ping -c 5 <hetzner-zerotier-ip>"`
  - [ ] Measure network latency: record ping times
  - [ ] Verify latency < 200ms (acceptable for cross-cloud coordination)

- [ ] Test SSH via zerotier in both directions (AC: #2)
  - [ ] From Hetzner to GCP: `ssh root@<hetzner-ip> "ssh root@<gcp-zerotier-ip> hostname"`
  - [ ] Verify SSH connection successful
  - [ ] From GCP to Hetzner: `ssh root@<gcp-ip> "ssh root@<hetzner-zerotier-ip> hostname"`
  - [ ] Verify SSH connection successful
  - [ ] Check certificate-based authentication working
  - [ ] Verify no password prompts (key-based auth only)

- [ ] Validate clan service instances (AC: #3)
  - [ ] Check emergency-access service on Hetzner: `ssh root@<hetzner-ip> "systemctl status emergency-access || echo 'not found'"`
  - [ ] Check emergency-access service on GCP: `ssh root@<gcp-ip> "systemctl status emergency-access || echo 'not found'"`
  - [ ] Check sshd-clan service on both machines
  - [ ] Check users-root configuration on both machines: `ssh root@<hetzner-ip> "id root"` and `ssh root@<gcp-ip> "id root"`
  - [ ] Review clan inventory configuration: `nix eval .#clan.inventory --json | jq .instances`
  - [ ] Verify service instances match expected configuration

- [ ] Test vars sharing (if configured) (AC: #4)
  - [ ] Review clan inventory for vars with share = true
  - [ ] If shared vars exist:
    - Verify vars accessible on both machines
    - Check /run/secrets/ on both machines for shared secrets
    - Test shared vars deployed correctly
  - [ ] If no shared vars, document for future reference

- [ ] Test multi-machine configuration update (AC: #5)
  - [ ] Identify shared configuration to update:
    - Option: Change nix settings (experimental-features)
    - Option: Update base module configuration
    - Option: Modify service instance setting
  - [ ] Update configuration in test-clan repository
  - [ ] Rebuild Hetzner VM: `ssh root@<hetzner-ip> "nixos-rebuild switch --flake github:user/test-clan#hetzner-vm"`
  - [ ] Rebuild GCP VM: `ssh root@<gcp-ip> "nixos-rebuild switch --flake github:user/test-clan#gcp-vm"`
  - [ ] Verify changes applied to both machines
  - [ ] Confirm configurations consistent

- [ ] Test service coordination update (AC: #6)
  - [ ] Modify service instance configuration:
    - Option: Change zerotier network settings
    - Option: Update sshd configuration
    - Option: Modify emergency-access settings
  - [ ] Rebuild both machines with updated configuration
  - [ ] Verify service coordination still functional:
    - Zerotier mesh still connected
    - SSH still works via zerotier
    - Services operational

- [ ] Monitor network stability for 24 hours (AC: #7)
  - [ ] Set up monitoring script (optional):
    - Periodic ping between machines
    - Log connectivity status
    - Alert on disconnections
  - [ ] Manual checks (minimum):
    - Check at start (hour 0)
    - Check at 6 hours
    - Check at 12 hours
    - Check at 18 hours
    - Check at 24 hours
  - [ ] For each check:
    - Test bidirectional ping
    - Test SSH via zerotier
    - Check zerotier status on both machines
    - Review system logs for errors
  - [ ] Document any disconnections or issues
  - [ ] If stability issues found, troubleshoot before proceeding

## Dev Notes

### Clan Service Instances Pattern

**Service instance structure:**
```nix
clan.inventory.instances.zerotier-local = {
  module = { name = "zerotier"; input = "clan-core"; };
  roles.controller.machines.hetzner-vm = {};
  roles.peer.machines.gcp-vm = {};
};
```

**Role targeting:**
- Per-machine: `roles.controller.machines.hetzner-vm = {}`
- By tags: `roles.peer.tags."all" = {}`
- Multiple machines: `roles.peer.machines = { gcp-vm = {}; other-vm = {}; }`

**Service coordination:**
- Controller role generates network ID (fact)
- Peer role consumes network ID (joins network)
- Vars can be shared between roles (share = true)

### Expected Services for Phase 0

**emergency-access:**
- Provides root access recovery mechanism
- Should be on all machines: `roles.default.tags."all"`

**sshd-clan:**
- Server role: SSH daemon configuration
- Client role: SSH client configuration
- Should be on all machines: server + client roles

**zerotier-local:**
- Controller role: Hetzner VM (always-on)
- Peer role: GCP VM (connects to controller)
- Provides VPN mesh for cross-cloud coordination

**users-root:**
- Root user configuration
- Should be on all machines: `roles.default.tags."all"`

### Multi-Machine Rebuild Pattern

**Options for rebuilding:**

1. **Direct rebuild on machine:**
   ```bash
   ssh root@<machine-ip> "nixos-rebuild switch"
   ```

2. **Remote rebuild from workstation:**
   ```bash
   nixos-rebuild switch --flake .#hetzner-vm --target-host root@<machine-ip>
   ```

3. **Clan machines update:**
   ```bash
   clan machines update hetzner-vm
   ```

Choose method based on current SSH access and configuration location.

### Network Stability Monitoring

**Minimum monitoring (24 hours):**
- Manual checks every 6 hours
- Test connectivity (ping, SSH)
- Review logs for errors
- Document any issues

**Optional automated monitoring:**
- Script periodic pings between machines
- Log results to file
- Alert on failures (email, notification)
- Requires additional setup time

Manual monitoring sufficient for Phase 0 validation.

### Solo Operator Workflow

This story is primarily validation and testing - medium operational risk.
Expected execution time: 2-4 hours (excluding 24-hour stability monitoring).
Stability monitoring is calendar time (periodic checks, not continuous work).

### Architectural Context

**Why multi-machine coordination important:**
- Essential for Phase 1 (cinnabar VPS + darwin hosts)
- Validates clan inventory service instances
- Proves zerotier mesh enables cross-cloud coordination
- Foundation for service orchestration at scale

**Patterns validated here apply to:**
- Phase 1: cinnabar (Hetzner) + darwin hosts (local)
- Phase 2+: Multiple darwin hosts coordinating
- Future infrastructure: Additional cloud VMs

### References

- [Source: docs/notes/development/epic-1-infrastructure-restructure-proposal.md#Story-1.9]
- [Upstream: clan-core service instances documentation]
- [Upstream: clan-infra inventory patterns]

### Expected Validation Points

After this story completes:
- Multi-machine coordination validated
- Service instances working across clouds
- Zerotier mesh stable for 24+ hours
- Configuration updates apply consistently
- Ready for Story 1.10 (long-term stability monitoring)

**What Story 1.9 does NOT validate:**
- Long-term stability (1 week minimum, Story 1.10)
- Vars sharing at scale (only 2 machines)
- Complex service orchestration (future work)

### Important Constraints

**24-hour stability requirement:**
- Minimum validation period before proceeding
- Can run in parallel with other activities
- Periodic checks sufficient (not continuous monitoring)

**Decision point**: If stability issues discovered (frequent disconnections, service failures), troubleshoot and resolve before proceeding to Story 1.10.
Multi-machine coordination must be reliable for Phase 1 confidence.

**Zero-regression mandate does NOT apply**: Test infrastructure, experimental coordination.

## Dev Agent Record

### Context Reference

<!-- Path(s) to story context XML will be added here by context workflow -->

### Agent Model Used

<!-- Agent model will be recorded during implementation -->
