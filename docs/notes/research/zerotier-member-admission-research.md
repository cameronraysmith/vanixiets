# ZeroTier Member Admission and Authorization in clan-core

## Overview

Clan-core provides three primary roles for ZeroTier VPN networks:

1. **Controller**: Manages network membership and authorizes new peers
2. **Moon**: Optional relay node for devices behind NAT/firewalls
3. **Peer**: Standard network nodes

Member admission follows a model where identities are pre-generated for each machine, but authorization occurs post-join during network controller startup.

## Key Identifiers and Generation

### ZeroTier Identity Components

Each ZeroTier node has a unique **10-character hexadecimal node ID** derived from its identity keypair.

**File locations** (generated automatically via clan vars system):
- `zerotier-identity-secret`: Private key (must be secret)
- `zerotier-identity-public`: Public key (derived from private key)
- `zerotier-ip`: Computed IPv6 address (deterministic from network ID + node ID)
- `zerotier-network-id`: 16-character hex network identifier (controller-only)

### Identity Generation (Per-Machine)

**Peer machines** run in "identity" mode via `/nixosModules/clanCore/zerotier/generate.py`:
- Generates random identity keypair using `zerotier-idtool generate`
- Computes deterministic IPv6 address based on network ID and node ID
- Identity persists in clan vars for reproducibility

**Controller machine** runs in "network" mode:
- Spawns temporary ZeroTier daemon to create the network
- Generates both identity AND network ID simultaneously
- Network ID is fixed for all subsequent nodes joining the same network

### IPv6 Address Computation

The ZeroTier IPv6 address is **deterministically computed** from:
- Network ID (16 hex chars)
- Node ID (extracted from identity keypair)

Formula:
```
IPv6 = fd<network_id_bytes>:9993:<node_id_bytes>
Example: fd0e28cb903344475e9993:9344:f769:935d:bbe3:cbc5 (compressed)
```

## Member Admission Workflow

### Join-First, Authorize-Second Model

ZeroTier uses an **asynchronous authorization model**:

1. **Machine joins network**:
   - Node generates its identity (if not pre-provisioned)
   - Joins network using network ID
   - Computes its IPv6 address deterministically
   - Request is queued at controller as "unauthorized"

2. **Controller authorizes on startup**:
   - When controller boots, it reads its member list from disk
   - It **automatically authorizes** members matching configured identities
   - No pre-authorization possible; authorization happens post-join

3. **External members authorization**:
   - Via `allowedIps` setting in controller role config
   - Controller accepts members by their IPv6 address, not member ID

### Automatic Authorization Mechanism

**File**: `/clanServices/zerotier/default.nix` (lines 160-191)

The controller creates a systemd service `zerotier-inventory-autoaccept` that runs on startup:

```nix
systemd.services.zerotier-inventory-autoaccept = {
  wantedBy = [ "multi-user.target" ];
  after = [ "zerotierone.service" ];
  path = [ config.clan.core.clanPkgs.zerotierone ];
  serviceConfig.ExecStart = pkgs.writeShellScript "zerotier-inventory-autoaccept" ''
    ${lib.concatMapStringsSep "\n" (host: ''
      ${config.clan.core.clanPkgs.zerotier-members}/bin/zerotier-members allow --member-ip ${host}
    '') allHostIPs}
  '';
};
```

This script:
- Gathers all clan-configured machine IPv6 addresses (from vars system)
- Appends `allowedIps` setting (for external machines)
- Calls `zerotier-members allow --member-ip <ipv6>` for each

### Conversion: IPv6 Address ↔ Member ID

The `zerotier-members` tool can work with either IPv6 addresses or raw member IDs.

**IPv6 → Member ID** (from `zerotier-members.py`, lines 57-65):
```python
def compute_member_id(ipv6_addr: str) -> str:
    addr = ipaddress.IPv6Address(ipv6_addr)
    addr_bytes = bytearray(addr.packed)
    # Extract bytes 10-15 (last 6 bytes = 48 bits of the 128-bit IPv6)
    node_id_bytes = addr_bytes[10:16]
    node_id = int.from_bytes(node_id_bytes, byteorder="big")
    return format(node_id, "x").zfill(10)[-10:]  # Format as 10-char hex
```

**Member ID → IPv6** (deterministic, reverse direction):
- Member ID is encoded in the last 48 bits of the IPv6 address
- Reverse computation: extract bytes 10-15, format as 10-char hex

## Configuration Patterns

### Pattern 1: Clan Inventory (Declarative)

**File**: `clan.nix` or equivalent inventory file

```nix
inventory.instances.zerotier = {
  module = {
    name = "zerotier";
    input = "clan-core";
  };
  roles.controller.machines.cinnabar = { };
  roles.peer.tags.all = { };  # All other machines are peers
};
```

**What happens**:
- Controller machine (cinnabar) generates network ID
- All peer machines generate identities
- Controller's autoaccept service authorizes all configured peers by their IPv6 addresses

### Pattern 2: External Member Authorization

**File**: Clan service config for controller machine

```nix
inventory.instances.zerotier = {
  module = {
    name = "zerotier";
    input = "clan-core";
  };
  roles.controller.machines.cinnabar.settings.allowedIps = [
    "fd5d:bbe3:cbc5:fe6b:f699:935d:bbe3:cbc5"  # External machine IPv6
  ];
  roles.peer.tags.all = { };
};
```

**What happens**:
- Controller accepts both inventory machines AND external IPv6 addresses
- External machines must join the network separately (know network ID)
- Controller authorizes them based on their IPv6 address

### Pattern 3: Manual Post-Deployment Authorization

For machines added after controller is running:

```bash
ssh controller zerotier-members allow --member-ip fd5d:bbe3:cbc5:fe6b:f699:935d:bbe3:cbc5
# OR
ssh controller zerotier-members allow <10-char-member-id>
```

The `zerotier-members` tool is installed on controller via:
```nix
environment.systemPackages = [ config.clan.core.clanPkgs.zerotier-members ];
```

## Information Required from blackphos (New Peer)

To admit a new machine `blackphos` to an existing clan network:

### Pre-Deployment (before nixos-rebuild)

1. **Network ID** (from controller):
   - Required in configuration to join
   - Available at: `/etc/zerotier/network-id` or vars directory on controller
   - Example: `0e28cb903344475e`

2. **Determine identity strategy**:
   - **Option A**: Let clan vars generate a new identity (recommended)
   - **Option B**: Import existing zerotier identity (if blackphos had zerotier before)

### Post-Deployment (for authorization)

After blackphos boots and joins the network:

1. **Extract from blackphos**:
   - ZeroTier IP: `cat /etc/zerotier/ip` or `/etc/profile.d/zerotier-ip.sh`
   - Member ID: Extract from IPv6 (last 48 bits) or run `zerotier-cli info`

2. **Authorize at controller**:
   ```bash
   ssh root@cinnabar zerotier-members allow --member-ip <blackphos-ipv6>
   ```

OR configure declaratively (preferred):

```nix
# In infra/machines/controller-machine.nix or clan.nix
inventory.instances.zerotier = {
  # ... existing config ...
  roles.controller.machines.cinnabar.settings.allowedIps = [
    "fd5d:bbe3:cbc5:fe6b:f699:935d:bbe3:cbc5"  # blackphos computed IPv6
  ];
};
```

Then redeploy controller:
```bash
clan machines update cinnabar
```

## Authorization State Persistence

### Member State Storage

ZeroTier stores member records on the controller at:
```
/var/lib/zerotier-one/controller.d/network/<network-id>/member/<member-id>
```

Example member record (JSON):
```json
{
  "id": "9344f769935d",
  "authorized": true,
  "name": "blackphos",
  "ipAssignments": ["fd5d:bbe3:cbc5:fe6b:f699:935d:bbe3:cbc5"],
  "identity": "9344f769935d...",
  "creationTime": 1234567890
}
```

### Cluster Coordination

- **When controller is offline**: Existing peers can continue communicating
- **When controller comes online**: It re-authorizes members from persistent state
- **Network ID format**: First 10 chars are the controller's node ID
- **Controller itself**: Auto-authorized via whitelist (lines 286-292 of nixosModules/zerotier/default.nix)

## Reference Implementations

### test-clan (Minimal Working Example)

**File**: `/Users/crs58/projects/nix-workspace/test-clan/modules/clan/inventory/services/zerotier.nix`

```nix
clan.inventory.instances.zerotier = {
  module = {
    name = "zerotier";
    input = "clan-core";
  };
  roles.controller.machines."cinnabar" = { };
  roles.peer.tags."all" = { };
};
```

**Machines**: jon (peer), sara (moon), bam (controller)

### clan-infra (External Member Example)

**File**: `/Users/crs58/projects/nix-workspace/clan-infra/modules/zerotier.nix`

Shows hardcoded external member IDs approach:

```nix
memberIds = [
  "e3d6559697" # opnsense router
  "6688e8091d" # berwn@laptop
  "57042912f0" # Mic92@turingmachine
];

systemd.services.zerotier-accept-external = {
  wantedBy = [ "multi-user.target" ];
  after = [ "zerotierone.service" ];
  serviceConfig.ExecStart = pkgs.writeShellScript "zerotier-inventory-autoaccept" ''
    ${lib.concatMapStringsSep "\n" (zerotier-id: ''
      zerotier-members allow ${zerotier-id}
    '') memberIds}
  '';
};
```

(Note: Uses member IDs instead of IPv6 addresses; both work)

### mic92-clan-dotfiles

Minimal zerotier module that imports nixosModules, less relevant for this research.

## Decision Tree: How to Admit blackphos

```
┌─ Does blackphos exist in inventory?
│  │
│  ├─ YES → Declarative approach (clan.nix)
│  │         - Add to roles.peer or custom role
│  │         - clan will auto-generate identity
│  │         - Controller auto-authorizes on next deployment
│  │
│  └─ NO → Determine admission timing
│     │
│     ├─ Pre-deployment
│     │  └─ Add to inventory → Deploy controller first → Deploy blackphos
│     │
│     └─ Post-deployment (blackphos already has ZT with external ID)
│        └─ Get blackphos IPv6 → Add to controller.settings.allowedIps
│           → Redeploy controller → blackphos joins automatically
│
└─ Special case: Multiple controllers
   └─ Only one controller per network (first 10 chars of network ID)
   └─ Secondary controllers become peers with stableEndpoints
   └─ Authorization still centralized to primary controller
```

## Key Implementation Files

| File | Purpose |
|------|---------|
| `/clanServices/zerotier/default.nix` | Service module definition (roles, inventory integration) |
| `/clanServices/zerotier/shared.nix` | Shared moon orbit configuration |
| `/nixosModules/clanCore/zerotier/default.nix` | NixOS module integration (vars generation, systemd services) |
| `/nixosModules/clanCore/zerotier/generate.py` | Identity and network ID generation |
| `/pkgs/zerotier-members/zerotier-members.py` | Member authorization CLI tool |
| `/pkgs/clan-cli/clan_lib/network/zerotier/__init__.py` | SSH/networking integration |

## Troubleshooting

### Member doesn't authorize even after controller restart

1. Check network ID matches:
   ```bash
   ssh blackphos cat /etc/zerotier/network-id
   ssh controller cat /etc/zerotier/network-id
   ```

2. Check member list on controller:
   ```bash
   ssh controller zerotier-members list
   ```

3. Check IPv6 matches exactly:
   ```bash
   ssh blackphos cat /etc/zerotier/ip
   ssh controller zerotier-members list | grep <ipv6>
   ```

4. Manual authorization (temporary):
   ```bash
   ssh controller zerotier-members allow --member-ip <ipv6>
   ```

### Identity already exists but network ID differs

- Delete zerotier state on joining machine and redeploy
- OR preserve identity and manually compute new IPv6 for old network

---

**Last updated**: 2025-11-19
**Sources**: clan-core clanServices/zerotier, clan-core nixosModules/zerotier, test-clan, clan-infra
