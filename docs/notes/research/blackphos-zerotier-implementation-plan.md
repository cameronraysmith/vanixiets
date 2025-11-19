# blackphos zerotier Integration Implementation Plan

**Date**: 2025-11-19
**Status**: Ready for implementation
**Repository**: `~/projects/nix-workspace/test-clan`

## Executive Summary

This plan details how to integrate blackphos (nix-darwin laptop) into the clan-managed zerotier network in test-clan.
The approach maximizes declarative configuration while respecting clan-core's architectural constraint that zerotier service modules only support nixosModule, not darwinModule.

## Architecture Overview

```
test-clan inventory
├─ cinnabar (nixos, controller)  → clan zerotier service with controller role
├─ electrum (nixos, peer)        → clan zerotier service with peer role
└─ blackphos (darwin, managed)   → nix-darwin config, homebrew zerotier-one, activation script
```

**Key insight**: blackphos is in inventory for management but NOT in zerotier service roles.
Zerotier configuration happens via nix-darwin + home-manager, not clan services.

## Prerequisites

- test-clan repository at `~/projects/nix-workspace/test-clan`
- cinnabar deployed and running as zerotier controller
- Network ID: `db4344343b14b903` (stored in cinnabar's clan vars)
- blackphos accessible via SSH from development machine

## Implementation Phases

### Phase 1: Add blackphos to Inventory (Declarative)

**Objective**: Register blackphos as a darwin machine in clan inventory

**Files to modify**:

1. `modules/clan/inventory/machines.nix`:
```nix
blackphos = {
  tags = ["darwin" "laptop" "client"];
  machineClass = "darwin";
  description = "raquel's nix-darwin laptop with zerotier client";
};
```

2. Create `machines/blackphos/default.nix`:
```nix
{ config, lib, pkgs, ... }:
{
  imports = [
    ./hardware-configuration.nix  # If available
    ./homebrew.nix
    ./zerotier.nix
  ];

  clan.core.networking.targetHost = "raquel@blackphos.local";

  # Basic nix-darwin configuration
  system.stateVersion = 5;

  # Enable nix-darwin managed homebrew
  homebrew.enable = true;
}
```

3. Create `machines/blackphos/homebrew.nix`:
```nix
{ config, lib, pkgs, ... }:
{
  homebrew = {
    enable = true;

    casks = [
      "zerotier-one"  # Installs GUI + CLI + launchd service
    ];

    onActivation = {
      autoUpdate = false;
      cleanup = "zap";
    };
  };
}
```

**Validation**:
```bash
cd ~/projects/nix-workspace/test-clan
nix flake check  # Should pass with blackphos in darwinConfigurations
```

**Commit**:
```bash
git add modules/clan/inventory/machines.nix machines/blackphos/
git commit -m "feat(inventory): add blackphos darwin machine with homebrew zerotier-one"
```

---

### Phase 2: Configure Automated Network Join (Declarative)

**Objective**: Create home-manager activation script to automatically join zerotier network

**Files to modify**:

1. Create `machines/blackphos/zerotier.nix`:
```nix
{ config, lib, pkgs, ... }:
let
  # Reference the zerotier network ID from cinnabar's vars
  # In production, this could be a clan var or imported secret
  networkId = "db4344343b14b903";
in
{
  # Home-manager activation script for zerotier network join
  home-manager.users.raquel = { ... }: {
    home.activation.zerotierJoin = lib.hm.dag.entryAfter ["writeBoundary"] ''
      # Check if zerotier-one is installed
      if ! command -v zerotier-cli &> /dev/null; then
        $DRY_RUN_CMD echo "zerotier-cli not found, skipping network join"
        exit 0
      fi

      # Check if already joined the network
      if zerotier-cli listnetworks | grep -q "${networkId}"; then
        $DRY_RUN_CMD echo "Already joined zerotier network ${networkId}"
      else
        $DRY_RUN_CMD echo "Joining zerotier network ${networkId}..."
        $DRY_RUN_CMD zerotier-cli join ${networkId}

        # Wait for join to complete
        sleep 2

        # Display member ID for controller authorization
        MEMBER_ID=$(zerotier-cli info | awk '{print $3}')
        $DRY_RUN_CMD echo "Zerotier member ID: $MEMBER_ID"
        $DRY_RUN_CMD echo "Run this on cinnabar to authorize:"
        $DRY_RUN_CMD echo "  zerotier-members allow --member-ip <ipv6-address>"
      fi
    '';
  };
}
```

**Alternative approach** (if home-manager not used):

2. Create nix-darwin activation script directly:
```nix
{ config, lib, pkgs, ... }:
let
  networkId = "db4344343b14b903";
  zerotierJoinScript = pkgs.writeShellScript "zerotier-join" ''
    set -euo pipefail

    if ! command -v zerotier-cli &> /dev/null; then
      echo "zerotier-cli not found, skipping" >&2
      exit 0
    fi

    if zerotier-cli listnetworks | grep -q "${networkId}"; then
      echo "Already joined network ${networkId}"
    else
      echo "Joining zerotier network ${networkId}..."
      zerotier-cli join ${networkId}
      sleep 2

      MEMBER_ID=$(zerotier-cli info | awk '{print $3}')
      echo "Member ID: $MEMBER_ID"
      echo "IPv6 will be: fd${networkId}:9993:${MEMBER_ID}"
    fi
  '';
in
{
  system.activationScripts.postActivation.text = lib.mkAfter ''
    echo "Running zerotier network join..."
    ${zerotierJoinScript}
  '';
}
```

**Commit**:
```bash
git add machines/blackphos/zerotier.nix
git commit -m "feat(blackphos): add automated zerotier network join activation script"
```

---

### Phase 3: Deploy to blackphos (First-time Setup)

**Objective**: Deploy nix-darwin configuration and install zerotier

**Prerequisites**:
- SSH access to blackphos as raquel
- blackphos has nix with flakes enabled

**Commands**:

1. Build configuration locally (test):
```bash
cd ~/projects/nix-workspace/test-clan
nix build .#darwinConfigurations.blackphos.system
```

2. Deploy to blackphos:
```bash
clan machines update blackphos
```

**Expected output**:
```
Building nix-darwin configuration for blackphos...
Installing homebrew cask: zerotier-one
Running activation scripts...
Joining zerotier network db4344343b14b903...
Member ID: a1b2c3d4e5
IPv6 will be: fddb4344343b14b903:9993:a1b2c3d4e5
```

3. **Manual step**: Note the member ID and calculated IPv6 address from output

4. Verify zerotier status on blackphos:
```bash
ssh raquel@blackphos.local
zerotier-cli info
zerotier-cli listnetworks
```

**Expected output**:
```
200 info a1b2c3d4e5 1.14.0 ONLINE
200 listnetworks db4344343b14b903 fddb:4344:343b:14b9:9993:a1b2:c3d4:e5 ACCESS_DENIED zerotier
```

Note: `ACCESS_DENIED` is expected until cinnabar authorizes the member.

---

### Phase 4: Configure Controller Authorization

**Objective**: Authorize blackphos on cinnabar controller

**Two options available**:

#### Option A: Declarative (Pre-authorization via allowedIps)

Modify `modules/clan/inventory/services/zerotier.nix` to add external member:

```nix
{
  clan.inventory.instances.zerotier = {
    module = { name = "zerotier"; input = "clan-core"; };

    roles.controller.machines."cinnabar" = {
      settings = {
        # Add blackphos IPv6 (calculated from member ID)
        allowedIps = [
          "fddb:4344:343b:14b9:9993:a1b2:c3d4:e5"  # blackphos
        ];
      };
    };

    roles.peer.tags."all" = { };
  };
}
```

Then redeploy cinnabar:
```bash
clan machines update cinnabar
```

#### Option B: Imperative (Manual authorization)

SSH to cinnabar and authorize:
```bash
ssh root@cinnabar.zerotier
zerotier-members allow --member-ip fddb:4344:343b:14b9:9993:a1b2:c3d4:e5
```

**Recommended**: Use Option A for declarative infrastructure.

**Commit**:
```bash
git add modules/clan/inventory/services/zerotier.nix
git commit -m "feat(zerotier): authorize blackphos darwin client via allowedIps"
```

---

### Phase 5: Verification

**Objective**: Confirm end-to-end zerotier connectivity

1. Check blackphos network status:
```bash
ssh raquel@blackphos.local zerotier-cli listnetworks
```

Expected: `OK` status instead of `ACCESS_DENIED`

2. Verify IP assignment:
```bash
ssh raquel@blackphos.local ifconfig | grep -A 4 zt
```

Expected: Interface with `fddb:4344:343b:14b9:9993:` prefix

3. Test connectivity to cinnabar via zerotier:
```bash
ssh raquel@blackphos.local
ping6 fddb:4344:343b:14b9:399:93db:4344:343b  # cinnabar zerotier IP
```

4. Test connectivity from cinnabar to blackphos:
```bash
ssh root@cinnabar
ping6 fddb:4344:343b:14b9:9993:a1b2:c3d4:e5  # blackphos zerotier IP
```

5. List all network members on controller:
```bash
ssh root@cinnabar zerotier-members list
```

Expected output:
```
cinnabar    fddb:4344:343b:14b9:399:93db:4344:343b  ONLINE   controller
electrum    fddb:4344:343b:14b9:399:93d1:7e6d:27cc  ONLINE   peer
blackphos   fddb:4344:343b:14b9:9993:a1b2:c3d4:e5  ONLINE   external
```

---

## Migration to infra Repository

Once validated in test-clan, migrate pattern to infra:

1. **Add to infra inventory**:
   - Copy `machines/blackphos/` structure
   - Update `modules/darwin/all/homebrew.nix` to include zerotier-one cask
   - Add zerotier activation script to darwin common config

2. **Update cinnabar config**:
   - Add blackphos IPv6 to cinnabar's zerotier allowedIps
   - Use same network ID from infra's production zerotier network

3. **Repeat for other darwin machines**:
   - stibnite (crs58's laptop)
   - argentum (christophersmith's laptop)
   - rosegold (janettesmith's laptop)

---

## Troubleshooting

### zerotier-cli command not found after deployment

**Cause**: Homebrew cask installation incomplete or path not updated

**Fix**:
```bash
brew reinstall zerotier-one
# Or manually install: https://www.zerotier.com/download/
```

### Network join fails with "Unable to connect to service"

**Cause**: zerotier-one service not running

**Fix**:
```bash
# Check launchd service status
launchctl list | grep zerotier

# Start service if needed
sudo launchctl load /Library/LaunchDaemons/com.zerotier.one.plist
```

### ACCESS_DENIED persists after authorization

**Cause**: Authorization not applied or wrong IPv6 address

**Fix**:
```bash
# On cinnabar, check zerotier-members output
ssh root@cinnabar zerotier-members list

# Verify IPv6 matches between blackphos and cinnabar config
ssh raquel@blackphos zerotier-cli listnetworks
```

### Activation script runs on every darwin-rebuild

**Cause**: Script doesn't properly detect existing join state

**Fix**: Add sentinel file check:
```nix
if [ ! -f "$HOME/.zerotier-joined" ]; then
  zerotier-cli join ${networkId}
  touch "$HOME/.zerotier-joined"
fi
```

---

## Known Limitations

1. **No clan service integration**: blackphos cannot use `roles.peer.machines.blackphos` because zerotier service only provides `nixosModule`

2. **Manual member ID extraction**: First deployment requires noting member ID from output for controller authorization

3. **IPv6 only**: zerotier assigns IPv6 by default; IPv4 requires additional controller config

4. **No automatic controller updates**: Adding new darwin machines requires manual update to cinnabar's allowedIps list

---

## Future Improvements

1. **Create darwin-compatible zerotier module**: Implement `darwinModule` in clan-core to enable full service integration

2. **Automatic member registration**: Use clan's machinery to automatically register darwin machines with controller

3. **Unified vars structure**: Store zerotier identity secrets in clan vars for all machine types

4. **CI/CD integration**: Automate member ID extraction and allowedIps updates via GitHub Actions

---

## Related Documentation

- Research: `docs/notes/research/clan-darwin-support/clan-core-macos-support.md`
- Research: `docs/notes/research/zerotier-nix-darwin-research.md`
- Research: `docs/notes/research/zerotier-member-admission-research.md`
- test-clan README: `~/projects/nix-workspace/test-clan/README.md`
- Clan-core macOS guide: `~/projects/nix-workspace/clan-core/docs/site/guides/macos.md`
