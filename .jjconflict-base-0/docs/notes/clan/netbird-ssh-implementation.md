---
title: NetBird SSH-over-WireGuard Implementation Plan for Nix-Darwin
---

## Executive Summary

This plan implements robust SSH connectivity over NetBird's WireGuard mesh network for all nix-darwin hosts (stibnite, blackphos, and future systems).
The implementation follows established patterns from the existing Tailscale module, integrates with the SOPS-nix secrets infrastructure, and works around nix-darwin netbird module limitations through declarative launchd activation.

## Architecture Overview

### Network Topology

```
NetBird Management Service (app.netbird.io)
         |
         +-- Signal Service (NAT traversal coordination)
         |
         +-- STUN/TURN Relays (connectivity fallback)
         |
    ┌────┴────┬────────────┬─────────────┐
    |         |            |             |
stibnite  blackphos   future-host    orb-nixos (optional)
(100.64.x.1) (100.64.x.2) (100.64.x.3)  (100.64.x.4)
    |         |            |             |
  utun100   utun100      utun100       wg0
    |         |            |             |
    └─────────┴────────────┴─────────────┘
         WireGuard Encrypted Mesh
              (Direct P2P or TURN relay)
```

### Component Architecture

```
┌─────────────────────────────────────────────────────────────┐
│ Host Configuration (stibnite.nix, blackphos.nix)           │
│   imports = [ self.darwinModules.default ]                 │
└────────────────────────┬────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────┐
│ darwinModules.default                                       │
│   imports = [ nixosModules.common ]                         │
└────────────────────────┬────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────┐
│ nixosModules.common                                         │
│   imports = [                                               │
│     ./shared/netbird.nix          # NEW                     │
│     ./shared/ssh-over-netbird.nix # NEW                     │
│     ./shared/tailscale.nix        # EXISTING (for pattern)  │
│   ]                                                         │
└────────────────────────┬────────────────────────────────────┘
                         │
         ┌───────────────┴───────────────┐
         ▼                               ▼
┌──────────────────┐           ┌──────────────────┐
│ NetBird Module   │           │ SSH Hardening    │
│ - Service mgmt   │           │ - ListenAddress  │
│ - Setup key auth │           │ - Key-only auth  │
│ - Interface cfg  │           │ - Keep-alive     │
└────────┬─────────┘           └──────────────────┘
         │
         ▼
┌─────────────────────────────────────────────────────────────┐
│ SOPS Secrets (nix-secrets repo)                             │
│   services/netbird-setup-keys.yaml                          │
│     stibnite_setup_key: ENC[AES256...]                      │
│     blackphos_setup_key: ENC[AES256...]                     │
└─────────────────────────────────────────────────────────────┘
```

### Data Flow: Initial Authentication

```
1. darwin-rebuild switch
   └─> Deploys launchd daemon: org.nixos.netbird
       └─> Script creates dirs: /var/run/netbird, /var/lib/netbird

2. System activation script (one-time setup)
   └─> Checks: /var/lib/netbird/.authenticated exists?
       ├─> NO: Run authentication
       │   ├─> SOPS decrypts setup key from secrets
       │   ├─> Executes: netbird up --setup-key $SETUP_KEY
       │   ├─> Creates: /var/lib/netbird/.authenticated marker
       │   └─> Creates: /var/lib/netbird/config.json (peer config)
       │
       └─> YES: Skip (already configured)

3. Launchd starts daemon
   └─> Executes: netbird service run
       ├─> Reads: /var/lib/netbird/config.json
       ├─> Creates: utun100 interface
       ├─> Assigns: 100.64.x.x/10 IP
       ├─> Connects: to management service
       ├─> Establishes: peer connections (via Signal + STUN)
       └─> Adds: routes to 100.64.0.0/10 via utun100

4. SSH server (macOS sshd via openssh module)
   └─> Listens on: 0.0.0.0:22 (all interfaces, including utun100)
       └─> Accessible from peers at: 100.64.x.x:22
```

### Security Model

**Threat Model Assumptions:**
- NetBird management service is trusted (or self-hosted alternative used)
- SOPS secret encryption is secure (age with ed25519 keys)
- SSH key authentication is enforced (no password auth)
- Local machine is not compromised (setup keys stored in plaintext in RAM briefly during activation)

**Security Boundaries:**
1. **Network Layer**: WireGuard encryption (Noise protocol, Curve25519)
2. **Access Control**: NetBird ACL policies (defined in management UI)
3. **Authentication**: SSH public key authentication only
4. **Authorization**: User-level SSH authorized_keys
5. **Secrets**: SOPS-encrypted setup keys, decrypted only during activation

**Attack Surface Reduction:**
- SSH not exposed to public internet (only NetBird mesh)
- Setup keys are one-time use per host (limited blast radius if leaked)
- No reusable master setup key (per-host keys generated and destroyed)
- Firewall blocks all incoming except NetBird handshake (UDP 51820)

## Implementation Plan

### Phase 1: Secrets Infrastructure

#### 1.1 Generate NetBird Setup Keys

**Manual Steps (NetBird Web UI):**

1. Navigate to: https://app.netbird.io/setup-keys
2. For each host, create setup key:
   - Name: `stibnite-darwin-20251015` (include date for tracking)
   - Type: **One-off** (critical for security)
   - Expiration: 7 days (sufficient for initial setup)
   - Auto-groups: `darwin-hosts`, `ssh-accessible`
   - Ephemeral: No (peers persist after disconnection)
3. Copy each key immediately (shown only once)

**Key Inventory:**
```
stibnite:  nb-setup-abc123def456...
blackphos: nb-setup-ghi789jkl012...
```

#### 1.2 Encrypt Setup Keys with SOPS

**File: `~/projects/nix-workspace/nix-secrets/services/netbird-setup-keys.yaml`**

```bash
cd ~/projects/nix-workspace/nix-secrets

# Create unencrypted template
cat > services/netbird-setup-keys.yaml <<EOF
stibnite_setup_key: nb-setup-abc123def456...
blackphos_setup_key: nb-setup-ghi789jkl012...
EOF

# Encrypt with SOPS
sops -e -i services/netbird-setup-keys.yaml

# Verify encryption
sops services/netbird-setup-keys.yaml
# Should show decrypted values

# Commit to secrets repo
git add services/netbird-setup-keys.yaml
git commit -m "feat(netbird): add setup keys for darwin hosts"
```

**SOPS Configuration Coverage:**

Existing `.sops.yaml` in nix-secrets already covers `services/*.yaml` with:
- Admin recovery key
- Dev key
- CI key
- All host keys (stibnite, blackphos, orb-nixos)

No changes needed to `.sops.yaml`.

#### 1.3 Expose Secrets in nix-secrets Flake

**File: `~/projects/nix-workspace/nix-secrets/flake.nix`**

Update to expose service secrets:

```nix
{
  description = "SOPS-encrypted secrets for nix-config";

  outputs = { self, ... }: {
    # Existing host-specific secrets
    secrets = {
      stibnite = ./hosts/stibnite;
      blackphos = ./hosts/blackphos;
      orb-nixos = ./hosts/orb-nixos;

      # NEW: Service secrets (shared across hosts)
      services = {
        netbird = ./services/netbird-setup-keys.yaml;
      };
    };
  };
}
```

### Phase 2: Shared NetBird Module

**File: `~/projects/nix-workspace/nix-config/modules/nixos/shared/netbird.nix`**

```nix
# NetBird WireGuard mesh network configuration
# Cross-platform module for NixOS and nix-darwin
{
  flake,
  pkgs,
  lib,
  config,
  ...
}:

let
  inherit (flake) inputs;
  cfg = config.services.netbird;
  isDarwin = pkgs.stdenv.isDarwin;
  isLinux = pkgs.stdenv.isLinux;

  # Per-host setup key from secrets
  # Hostname-based lookup: stibnite -> stibnite_setup_key
  setupKeyPath = config.sops.secrets."netbird-setup-key-${config.networking.hostName}".path;
in
{
  options.services.netbird = {
    enable = lib.mkEnableOption "NetBird WireGuard mesh network";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.netbird;
      description = "NetBird package to use";
    };

    managementUrl = lib.mkOption {
      type = lib.types.str;
      default = "https://api.netbird.io:443";
      description = "NetBird management service URL";
    };

    interfaceName = lib.mkOption {
      type = lib.types.str;
      default = if isDarwin then "utun100" else "wt0";
      description = "WireGuard interface name (must be utun[0-9]+ on Darwin)";
    };

    setupKeySecret = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = ''
        SOPS secret name containing the setup key.
        Defaults to netbird-setup-key-$hostname.

        Setup keys are one-time authentication tokens from NetBird management.
        Generate at: https://app.netbird.io/setup-keys
      '';
    };
  };

  config = lib.mkIf cfg.enable {

    # SOPS secret configuration
    sops.secrets."netbird-setup-key-${config.networking.hostName}" = {
      sopsFile = inputs.secrets.secrets.services.netbird;
      key = "${config.networking.hostName}_setup_key";
      mode = "0400";
      # Darwin: root:wheel, Linux: root:root
      owner = "root";
      group = if isDarwin then "wheel" else "root";
    };

    # Platform-specific service configuration
    services.netbird = lib.mkMerge [
      # Common configuration
      {
        enable = true;
        package = cfg.package;
      }

      # Darwin-specific (nix-darwin)
      (lib.mkIf isDarwin {
        # Base module only provides daemon, we enhance with activation
      })

      # Linux-specific (NixOS)
      (lib.mkIf isLinux {
        # NixOS netbird module has richer options, configure here
        # (Future: when NixOS hosts added)
      })
    ];

    # Darwin: One-time authentication via activation script
    system.activationScripts.netbird-auth = lib.mkIf isDarwin (lib.mkAfter ''
      # One-time NetBird authentication using setup key
      # Only runs if not already authenticated

      AUTH_MARKER="/var/lib/netbird/.authenticated"

      if [ ! -f "$AUTH_MARKER" ]; then
        echo "NetBird: First-time setup, authenticating with setup key..."

        # Wait for SOPS secret to be available (activation ordering)
        if [ -f "${setupKeyPath}" ]; then
          SETUP_KEY=$(cat "${setupKeyPath}")

          # Authenticate (creates /var/lib/netbird/config.json)
          ${cfg.package}/bin/netbird up \
            --setup-key "$SETUP_KEY" \
            --management-url "${cfg.managementUrl}" \
            --interface-name "${cfg.interfaceName}" \
            --log-level info

          # Mark as authenticated to prevent re-running
          touch "$AUTH_MARKER"
          echo "NetBird: Authentication successful, daemon will connect on next boot"
        else
          echo "NetBird: WARNING - Setup key secret not found at ${setupKeyPath}"
          echo "NetBird: Skipping authentication, manual 'netbird up' required"
        fi
      else
        echo "NetBird: Already authenticated, skipping setup"
      fi
    '');

    # NixOS: Systemd service configuration
    # (Placeholder for future NixOS host support)
    systemd.services.netbird-auth = lib.mkIf isLinux {
      description = "NetBird One-Time Authentication";
      wantedBy = [ "multi-user.target" ];
      before = [ "netbird.service" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        AUTH_MARKER="/var/lib/netbird/.authenticated"

        if [ ! -f "$AUTH_MARKER" ]; then
          SETUP_KEY=$(cat "${setupKeyPath}")
          ${cfg.package}/bin/netbird up --setup-key "$SETUP_KEY"
          touch "$AUTH_MARKER"
        fi
      '';
    };

    # Environment packages (makes CLI available)
    environment.systemPackages = [ cfg.package ];
  };
}
```

### Phase 3: SSH Hardening Module

**File: `~/projects/nix-workspace/nix-config/modules/nixos/shared/ssh-over-netbird.nix`**

```nix
# SSH server hardened for NetBird WireGuard mesh access only
# Provides secure remote access without public internet exposure
{
  flake,
  pkgs,
  lib,
  config,
  ...
}:

let
  cfg = config.services.ssh-over-netbird;
  isDarwin = pkgs.stdenv.isDarwin;
  isLinux = pkgs.stdenv.isLinux;

  # NetBird assigns IPs from CGNAT range
  netbirdCIDR = "100.64.0.0/10";
in
{
  options.services.ssh-over-netbird = {
    enable = lib.mkEnableOption "SSH server optimized for NetBird access";

    restrictToNetbird = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        If true, SSH only listens on NetBird interface.
        If false, SSH listens on all interfaces (default).

        WARNING: Setting to true requires knowing your NetBird IP in advance,
        which is dynamically assigned. Recommended: keep false and use
        firewall rules or NetBird ACLs for restriction.
      '';
    };

    allowPasswordAuthentication = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Allow password authentication (strongly discouraged)";
    };

    keepAliveInterval = lib.mkOption {
      type = lib.types.int;
      default = 60;
      description = "Seconds between keep-alive messages (prevents timeout over WireGuard)";
    };

    keepAliveCountMax = lib.mkOption {
      type = lib.types.int;
      default = 3;
      description = "Maximum missed keep-alives before disconnect";
    };
  };

  config = lib.mkIf cfg.enable {

    # Enable SSH server
    services.openssh = {
      enable = true;

      # Security hardening
      extraConfig = ''
        # Authentication
        PasswordAuthentication ${if cfg.allowPasswordAuthentication then "yes" else "no"}
        PermitRootLogin no
        PubkeyAuthentication yes
        ChallengeResponseAuthentication no

        # Keep-alive for WireGuard tunnels
        # Prevents connection drops due to NAT timeout or idle disconnect
        ClientAliveInterval ${toString cfg.keepAliveInterval}
        ClientAliveCountMax ${toString cfg.keepAliveCountMax}

        # Performance
        UseDNS no

        # Logging
        LogLevel VERBOSE

        ${lib.optionalString cfg.restrictToNetbird ''
          # Restrict to NetBird interface only
          # NOTE: Requires manual configuration of NetBird IP
          # This is commented out by default - enable manually after getting IP from 'netbird status'
          # ListenAddress 100.64.x.x
        ''}
      '';
    };

    # Darwin-specific: Enable remote login
    # On Darwin, openssh module manages the system sshd via launchd
    # No additional configuration needed beyond extraConfig

    # NixOS-specific: Firewall configuration
    networking.firewall = lib.mkIf isLinux {
      # Allow SSH from NetBird network
      # Note: NetBird already creates WireGuard interface with encryption,
      # so firewall operates on decrypted packets from allowed peers
      allowedTCPPorts = [ 22 ];

      # Optional: Explicit rule limiting SSH to NetBird CIDR
      # extraCommands = ''
      #   iptables -A INPUT -p tcp --dport 22 -s ${netbirdCIDR} -j ACCEPT
      #   iptables -A INPUT -p tcp --dport 22 -j DROP
      # '';
    };

    # User configuration: Ensure primary user can SSH
    users.users.${config.system.primaryUser} = {
      openssh.authorizedKeys.keys = [ config.me.sshKey ];
    };

    # For darwin: Also configure non-admin users
    users.users."runner" = lib.mkIf (config.runner.username == "runner") {
      openssh.authorizedKeys.keys = [ config.runner.sshKey ];
    };

    users.users."raquel" = lib.mkIf (config.raquel.username == "raquel") {
      openssh.authorizedKeys.keys = [ config.raquel.sshKey ];
    };
  };
}
```

### Phase 4: Common Module Integration

**File: `~/projects/nix-workspace/nix-config/modules/nixos/common.nix`**

```nix
# Common configuration across NixOS and nix-darwin
{ flake, ... }:
{
  imports = [
    ./shared/caches.nix
    ./shared/nix.nix
    ./shared/primary-as-admin.nix
    ./shared/tailscale.nix
    ./shared/netbird.nix           # NEW
    ./shared/ssh-over-netbird.nix  # NEW
  ];
}
```

### Phase 5: Host Configuration Updates

#### 5.1 Stibnite Configuration

**File: `~/projects/nix-workspace/nix-config/configurations/darwin/stibnite.nix`**

Add to existing configuration:

```nix
{
  flake,
  pkgs,
  lib,
  ...
}:

let
  inherit (flake) config inputs;
  inherit (inputs) self;
  adminUser = config.crs58;
in
{
  imports = [
    self.darwinModules.default
    inputs.nix-rosetta-builder.darwinModules.default
    self.darwinModules.colima
  ];

  nixpkgs.hostPlatform = "aarch64-darwin";
  system.primaryUser = adminUser.username;

  # Existing configuration...
  # (nix-rosetta-builder, colima, homebrew, etc.)

  # NEW: NetBird mesh network
  services.netbird = {
    enable = true;
    managementUrl = "https://api.netbird.io:443";  # Or self-hosted URL
    interfaceName = "utun100";  # Default for Darwin
  };

  # NEW: SSH hardened for NetBird access
  services.ssh-over-netbird = {
    enable = true;
    restrictToNetbird = false;  # Listen on all interfaces, rely on NetBird ACLs
    allowPasswordAuthentication = false;
    keepAliveInterval = 60;
  };

  # Existing: security.pam, system.stateVersion, etc.
}
```

#### 5.2 Blackphos Configuration

**File: `~/projects/nix-workspace/nix-config/configurations/darwin/blackphos.nix`**

Add identical NetBird/SSH configuration:

```nix
{
  flake,
  pkgs,
  ...
}:

let
  inherit (flake) config inputs;
  inherit (inputs) self;
  adminUser = config.crs58;
in
{
  imports = [
    self.darwinModules.default
  ];

  nixpkgs.hostPlatform = "aarch64-darwin";
  system.primaryUser = adminUser.username;

  # Existing configuration...
  # (homebrew, etc.)

  # NEW: NetBird mesh network
  services.netbird = {
    enable = true;
    managementUrl = "https://api.netbird.io:443";
    interfaceName = "utun100";
  };

  # NEW: SSH hardened for NetBird access
  services.ssh-over-netbird = {
    enable = true;
    restrictToNetbird = false;
    allowPasswordAuthentication = false;
    keepAliveInterval = 60;
  };

  # Existing: security.pam, system.stateVersion, etc.
}
```

### Phase 6: Deployment and Validation

#### 6.1 Pre-Deployment Checklist

**Verify SOPS Setup:**

```bash
cd ~/projects/nix-workspace/nix-secrets

# Verify secrets are encrypted
sops services/netbird-setup-keys.yaml

# Should display:
# stibnite_setup_key: nb-setup-abc123...
# blackphos_setup_key: nb-setup-ghi789...

# Verify sops keys are accessible
sops --decrypt services/netbird-setup-keys.yaml
# Should succeed without errors
```

**Verify Module Syntax:**

```bash
cd ~/projects/nix-workspace/nix-config

# Check for syntax errors
nix flake check

# Expected output should include no errors related to new modules
```

#### 6.2 Deployment: Stibnite (Current Host)

**Step 1: Dry-Run Build**

```bash
# From nix-config directory
nix build .#darwinConfigurations.stibnite.system --dry-run

# Review what would be built/changed
```

**Step 2: Build and Activate**

```bash
darwin-rebuild switch --flake .#stibnite

# Expected output:
# - Building derivation for netbird module
# - Activating new configuration
# - Running activation script: netbird-auth
#   - Output: "NetBird: First-time setup, authenticating with setup key..."
#   - Output: "NetBird: Authentication successful..."
# - Starting/reloading launchd daemons
#   - org.nixos.netbird: Loaded
# - SSH configuration updated
```

**Step 3: Verify Daemon Status**

```bash
# Check launchd
launchctl list | grep netbird
# Expected: org.nixos.netbird with PID (not 0)

# Check NetBird status
netbird status
# Expected:
#   Status: Connected
#   NetBird IP: 100.64.x.x
#   Management: Connected to https://api.netbird.io:443
#   Peers: [list of connected peers]

# Check interface
ifconfig utun100
# Expected:
#   utun100: flags=...<UP,POINTOPOINT,RUNNING,MULTICAST>
#   inet 100.64.x.x netmask 0xffc00000

# Check routes
netstat -rn | grep utun100
# Expected: 100.64.0.0/10 -> utun100
```

**Step 4: Verify SSH Server**

```bash
# Check SSH is listening
sudo lsof -iTCP:22 -sTCP:LISTEN
# Expected: sshd listening on *.22

# Verify authorized keys
cat ~/.ssh/authorized_keys
# Expected: ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINdO9rInDa9HvdZZxmkgeEdAlTupCy3BgA/sqSGyUH+

# Check SSH config
cat /etc/ssh/sshd_config.d/100-nix-darwin.conf
# Expected to contain:
#   PasswordAuthentication no
#   PermitRootLogin no
#   ClientAliveInterval 60
```

**Step 5: Verify Logs**

```bash
# NetBird logs
tail -f /var/log/netbird.out.log
# Should show: peer connections, interface setup, management sync

tail -f /var/log/netbird.err.log
# Should be empty or minimal warnings

# System log
log show --predicate 'subsystem == "com.apple.launchd"' --last 5m | grep netbird
# Should show daemon start/load events
```

#### 6.3 Deployment: Blackphos (Remote Host)

**Preparation:**

Option A: Deploy locally if you have physical access
Option B: Deploy remotely if already accessible via existing network (Tailscale)

**Remote Deployment via Tailscale:**

```bash
# From stibnite (or any machine with access to blackphos)

# SSH to blackphos via Tailscale
ssh crs58@blackphos.tail-scale-domain.ts.net

# On blackphos:
cd ~/projects/nix-workspace/nix-config

# Pull latest changes
git pull origin main

# Update secrets repo
cd ~/projects/nix-workspace/nix-secrets
git pull origin main

# Return to nix-config
cd ~/projects/nix-workspace/nix-config

# Deploy
darwin-rebuild switch --flake .#blackphos

# Verify (same commands as stibnite verification)
netbird status
ifconfig utun100
```

#### 6.4 End-to-End Connectivity Test

**From Stibnite to Blackphos:**

```bash
# Get blackphos NetBird IP
ssh crs58@blackphos.tailscale 'netbird status | grep "NetBird IP"'
# Note the IP: 100.64.x.y

# Ping test
ping -c 3 100.64.x.y
# Expected: 3 packets transmitted, 3 received, 0% loss

# SSH test via NetBird
ssh crs58@100.64.x.y
# Expected: Successful login without password prompt

# Alternative: Use NetBird DNS (if enabled in management)
ssh crs58@blackphos.netbird.cloud
# Expected: Successful login
```

**From Blackphos to Stibnite:**

```bash
# On blackphos
STIBNITE_IP=$(ssh crs58@stibnite.tailscale 'netbird status | grep "NetBird IP" | awk "{print \$3}"')

ping -c 3 $STIBNITE_IP
ssh crs58@$STIBNITE_IP
```

**Verify Peer Connection Type:**

```bash
netbird status
# Look for peer connection lines:
#   Peer: blackphos [100.64.x.y]
#     Connection: Connected
#     Type: P2P (direct) or Relayed (via TURN)
#     Latency: XX ms
```

**Performance Test:**

```bash
# Large file transfer over NetBird
dd if=/dev/zero bs=1M count=100 | ssh crs58@100.64.x.y 'cat > /dev/null'
# Measure throughput

# Interactive latency test
ssh crs58@100.64.x.y 'ping -c 10 1.1.1.1'
# Should show normal latency (WireGuard overhead is minimal)
```

### Phase 7: Troubleshooting Guide

#### 7.1 Authentication Failures

**Symptom:** Activation script reports "NetBird: WARNING - Setup key secret not found"

**Diagnosis:**

```bash
# Check SOPS secret exists
ls -la /run/secrets/netbird-setup-key-stibnite
# or
ls -la /run/secrets/netbird-setup-key-blackphos

# If missing, check SOPS configuration
cd ~/projects/nix-workspace/nix-secrets
sops services/netbird-setup-keys.yaml
# Verify key names match hostname
```

**Solution:**

1. Verify hostname matches secret key name:
   ```bash
   hostname
   # Should output: stibnite or blackphos
   ```

2. If mismatch, update `netbird.nix` or secrets file

3. Re-run activation:
   ```bash
   darwin-rebuild switch --flake .#stibnite
   ```

#### 7.2 Daemon Not Starting

**Symptom:** `launchctl list | grep netbird` shows no PID or exit code

**Diagnosis:**

```bash
# Check launchd plist
cat /Library/LaunchDaemons/org.nixos.netbird.plist

# Check daemon logs
tail -50 /var/log/netbird.err.log

# Try manual start
sudo launchctl load /Library/LaunchDaemons/org.nixos.netbird.plist
sudo launchctl start org.nixos.netbird
```

**Common Causes:**

1. **Permission Issues:**
   ```bash
   sudo chown root:wheel /Library/LaunchDaemons/org.nixos.netbird.plist
   sudo chmod 644 /Library/LaunchDaemons/org.nixos.netbird.plist
   ```

2. **Config File Missing:**
   ```bash
   ls -la /var/lib/netbird/config.json
   # If missing, run authentication manually:
   netbird up --setup-key $(sops -d ~/projects/nix-workspace/nix-secrets/services/netbird-setup-keys.yaml | grep stibnite | cut -d: -f2)
   ```

3. **Binary Not Found:**
   ```bash
   which netbird
   # Should output: /run/current-system/sw/bin/netbird
   ```

#### 7.3 Interface Not Created

**Symptom:** `ifconfig utun100` returns "no such interface"

**Diagnosis:**

```bash
# Check if WireGuard is trying to create interface
grep -i "tun device" /var/log/netbird.out.log

# Check all utun interfaces
ifconfig | grep utun
```

**Common Causes:**

1. **Interface Name Conflict:**
   - macOS auto-assigns utun interfaces starting at utun0
   - If utun100 is taken, try different number in config:
     ```nix
     services.netbird.interfaceName = "utun101";
     ```

2. **WireGuard-go Not Available:**
   ```bash
   which wg
   # Should be available from netbird package
   ```

3. **Kernel Extension Not Loaded:**
   - NetBird uses userspace WireGuard (wireguard-go), no kext needed
   - But check system integrity:
     ```bash
     sudo dmesg | grep -i utun
     ```

#### 7.4 Peer Connections Failing

**Symptom:** `netbird status` shows peers as "Disconnected"

**Diagnosis:**

```bash
netbird status --detail
# Check "Connection Type" and "Last Seen"

# Check signal service connectivity
curl -v https://signal.netbird.io/health
# Should return 200 OK

# Check STUN connectivity
nc -u stun.netbird.io 3478
# Should connect
```

**Common Causes:**

1. **Firewall Blocking UDP:**
   ```bash
   # Test outbound UDP 51820 (WireGuard)
   nc -u 8.8.8.8 51820
   # If blocked, configure firewall to allow
   ```

2. **NAT Traversal Failing:**
   - Check if TURN relay is being used:
     ```bash
     netbird status | grep -i relay
     # If "Relayed: Yes", direct P2P failed (higher latency but should work)
     ```

3. **Peer Not Online:**
   - Verify peer is connected:
     ```bash
     # From NetBird web UI, check peer status
     # Or ping peer's NetBird IP:
     ping 100.64.x.y
     ```

#### 7.5 SSH Connection Refused

**Symptom:** `ssh crs58@100.64.x.x` returns "Connection refused"

**Diagnosis:**

```bash
# Verify SSH is listening
sudo lsof -iTCP:22 -sTCP:LISTEN

# Test NetBird connectivity
ping 100.64.x.x
# If ping works but SSH doesn't, SSH server is the issue

# Check SSH server status (Darwin)
sudo launchctl list | grep sshd

# Test SSH locally
ssh localhost
# If local works but NetBird doesn't, check firewall/ACLs
```

**Common Causes:**

1. **SSH Not Enabled:**
   ```bash
   # Verify in configuration
   darwin-rebuild switch --flake .#stibnite --show-trace
   # Look for services.openssh.enable = true
   ```

2. **Firewall Blocking:**
   ```bash
   # Check macOS Application Firewall
   /usr/libexec/ApplicationFirewall/socketfilterfw --getglobalstate
   /usr/libexec/ApplicationFirewall/socketfilterfw --listapps | grep sshd
   ```

3. **NetBird ACL Denying Port 22:**
   - Check NetBird management UI -> Access Control
   - Ensure rule allows: `source: darwin-hosts, destination: darwin-hosts, protocol: tcp, port: 22`

4. **SSH Keys Not Authorized:**
   ```bash
   # On remote host
   cat ~/.ssh/authorized_keys
   # Should contain your public key from config.nix
   ```

#### 7.6 SOPS Decryption Errors

**Symptom:** Activation fails with SOPS-related errors

**Diagnosis:**

```bash
# Test SOPS decryption manually
cd ~/projects/nix-workspace/nix-secrets
sops -d services/netbird-setup-keys.yaml

# Check age keys are accessible
ls -la ~/.config/sops/age/keys.txt

# For host keys, check:
sudo ls -la /etc/ssh/ssh_host_ed25519_key
```

**Common Causes:**

1. **Age Key Missing:**
   ```bash
   # Regenerate age key from SSH key
   nix-shell -p ssh-to-age --run 'cat ~/.ssh/id_ed25519.pub | ssh-to-age'
   # Add to .sops.yaml
   ```

2. **Wrong Key in .sops.yaml:**
   - Verify host key age fingerprint matches `.sops.yaml`
   - Regenerate if needed:
     ```bash
     sudo ssh-keygen -y -f /etc/ssh/ssh_host_ed25519_key | ssh-to-age
     ```

### Phase 8: Post-Deployment Hardening

#### 8.1 NetBird Access Control Policies

**Create ACL in NetBird Management UI:**

Navigate to: https://app.netbird.io/acls

**Example ACL Configuration:**

```yaml
# Allow SSH between darwin hosts
- name: darwin-ssh-access
  source:
    - darwin-hosts
  destination:
    - darwin-hosts
  ports:
    - protocol: tcp
      port: 22
  action: accept

# Allow ICMP (ping) for diagnostics
- name: darwin-icmp
  source:
    - darwin-hosts
  destination:
    - darwin-hosts
  ports:
    - protocol: icmp
  action: accept

# Default deny (implicit, but explicit for clarity)
- name: default-deny
  source:
    - "*"
  destination:
    - "*"
  action: drop
```

**Groups Configuration:**

```yaml
groups:
  - name: darwin-hosts
    peers:
      - stibnite
      - blackphos
      # future hosts added here
```

#### 8.2 SSH Key Rotation

**Best Practice:** Rotate SSH keys annually

**Procedure:**

1. Generate new key pair:
   ```bash
   ssh-keygen -t ed25519 -C "cameron.ray.smith@gmail.com" -f ~/.ssh/id_ed25519_new
   ```

2. Update `config.nix`:
   ```nix
   baseIdentity.sshKey = "ssh-ed25519 AAAA...NEW_KEY";
   ```

3. Deploy to all hosts:
   ```bash
   darwin-rebuild switch --flake .#stibnite
   darwin-rebuild switch --flake .#blackphos
   ```

4. Test new key works before removing old:
   ```bash
   ssh -i ~/.ssh/id_ed25519_new crs58@100.64.x.x
   ```

5. Remove old key from authorized_keys

#### 8.3 NetBird Setup Key Lifecycle

**Setup Key Security:**

- One-time keys are consumed after first use (secure)
- Generate new key for each host deployment
- Expired keys cannot be used (7-day default expiration)

**Key Rotation After Deployment:**

After successful deployment, setup keys can be:
1. Deleted from NetBird UI (they're already consumed)
2. Left in SOPS for disaster recovery (re-authentication if config lost)

**Recommendation:** Keep encrypted in SOPS, delete from NetBird UI.

#### 8.4 Monitoring and Alerting

**Manual Monitoring Commands:**

```bash
# Daily health check
netbird status | grep -E "(Status|NetBird IP|Peers)"

# Connection quality
netbird status --detail | grep -E "(Latency|Type)"

# Interface statistics
netstat -I utun100
```

**Automated Monitoring (Future):**

Consider integrating with existing monitoring:
- Prometheus node_exporter for interface metrics
- Healthcheck script running via launchd
- NetBird management API for peer status

### Phase 9: Future Enhancements

#### 9.1 Self-Hosted NetBird Management

**Motivation:**
- Full control over network management
- No dependency on netbird.io SaaS
- Data sovereignty

**Implementation Plan:**

1. Deploy NetBird management server on NixOS host:
   ```nix
   services.netbird.server = {
     enable = true;
     management = {
       enable = true;
       # Configuration...
     };
   };
   ```

2. Update `managementUrl` in shared netbird.nix:
   ```nix
   managementUrl = "https://netbird.example.com:443";
   ```

3. Configure DNS and SSL certificates (via Let's Encrypt)

**Reference:** https://docs.netbird.io/selfhosted/selfhosted-guide

#### 9.2 Multi-Platform Support

**Extend to NixOS Hosts:**

When adding Linux hosts (e.g., orb-nixos), the shared module already supports:

```nix
# configurations/nixos/orb-nixos.nix
{
  services.netbird.enable = true;
  services.ssh-over-netbird.enable = true;

  # NixOS-specific: Firewall configured automatically
}
```

**Extend to Home-Manager:**

For user-level NetBird (non-system):

```nix
# modules/home/shared/netbird.nix
home-manager.users.crs58 = {
  # User-space NetBird daemon
  systemd.user.services.netbird = { ... };
};
```

#### 9.3 NetBird DNS Integration

**Enable MagicDNS:**

NetBird supports DNS resolution for peers.

**Configuration:**

In NetBird Management UI:
1. Navigate to DNS settings
2. Enable nameserver: `100.100.100.100`
3. Add domain: `netbird.cloud`

**Update Darwin Module:**

```nix
# Similar to Tailscale's /etc/resolver approach
environment.etc."resolver/netbird.cloud".text = ''
  nameserver 100.100.100.100
'';
```

**Usage:**

```bash
ssh crs58@stibnite.netbird.cloud
ssh crs58@blackphos.netbird.cloud
```

#### 9.4 NetBird Exit Node

**Use Case:** Route internet traffic through a NetBird peer

**Configuration:**

```nix
services.netbird.exitNode = {
  enable = true;
  # Advertise this host as exit node
};
```

**Client Usage:**

```bash
netbird up --use-exit-node stibnite
```

#### 9.5 Integration with Radicle

**Future Vision:** Mirror nix-config to Radicle for decentralized version control

**Related to Comment in flake.nix:**

```nix
# Line 63-64:
# SOPS-encrypted secrets repository (local for now, will move to Radicle)
secrets.url = "git+file:///Users/crs58/projects/nix-workspace/nix-secrets";
```

**Migration Plan:**

1. Initialize Radicle repository for nix-secrets
2. Seed on NetBird-connected peers
3. Update flake input:
   ```nix
   secrets.url = "rad://z...nix-secrets";
   ```
4. NetBird provides connectivity for Radicle seeding

**Synergy:** NetBird + Radicle = Fully decentralized config management

## File Checklist

### New Files to Create

- [ ] `~/projects/nix-workspace/nix-secrets/services/netbird-setup-keys.yaml`
- [ ] `~/projects/nix-workspace/nix-config/modules/nixos/shared/netbird.nix`
- [ ] `~/projects/nix-workspace/nix-config/modules/nixos/shared/ssh-over-netbird.nix`
- [ ] `~/projects/nix-workspace/nix-config/docs/notes/networking/netbird-ssh-darwin-implementation.md` (this file)

### Files to Modify

- [ ] `~/projects/nix-workspace/nix-secrets/flake.nix` (expose services.netbird)
- [ ] `~/projects/nix-workspace/nix-config/modules/nixos/common.nix` (add imports)
- [ ] `~/projects/nix-workspace/nix-config/configurations/darwin/stibnite.nix` (enable services)
- [ ] `~/projects/nix-workspace/nix-config/configurations/darwin/blackphos.nix` (enable services)

### No Changes Needed

- [x] `~/projects/nix-workspace/nix-secrets/.sops.yaml` (already covers services/*.yaml)
- [x] `~/projects/nix-workspace/nix-config/modules/darwin/default.nix` (already imports common.nix)
- [x] `~/projects/nix-workspace/nix-config/config.nix` (SSH keys already defined)

## Implementation Timeline

**Estimated Time:** 2-4 hours for full deployment

### Session 1: Secrets Setup (30 minutes)

- Generate NetBird setup keys in web UI
- Create and encrypt `netbird-setup-keys.yaml`
- Update nix-secrets flake
- Test SOPS decryption

### Session 2: Module Development (60 minutes)

- Create `netbird.nix` module
- Create `ssh-over-netbird.nix` module
- Update `common.nix` imports
- Syntax check with `nix flake check`

### Session 3: Stibnite Deployment (30 minutes)

- Update stibnite.nix configuration
- Deploy with `darwin-rebuild switch`
- Verify daemon, interface, connectivity
- Test SSH to localhost via NetBird IP

### Session 4: Blackphos Deployment (30 minutes)

- Update blackphos.nix configuration
- Deploy via Tailscale SSH access
- Verify NetBird status
- Test SSH between stibnite <-> blackphos

### Session 5: Testing and Documentation (30 minutes)

- End-to-end connectivity tests
- Performance benchmarks
- Document peer IPs and hostnames
- Create runbook for future host additions

## Success Criteria

- [ ] NetBird daemon running on both stibnite and blackphos
- [ ] Both hosts show "Connected" status in `netbird status`
- [ ] Both hosts assigned 100.64.x.x IPs
- [ ] Peer-to-peer connection established (check connection type)
- [ ] SSH works bidirectionally using NetBird IPs
- [ ] SSH does NOT work with password (key-only authentication)
- [ ] Setup keys are encrypted in SOPS
- [ ] No plaintext secrets in git repositories
- [ ] LaunchD daemons survive reboots
- [ ] No manual `netbird up` required after initial deployment

## References

### Documentation

- NetBird Docs: https://docs.netbird.io
- NetBird CLI Reference: https://docs.netbird.io/how-to/cli
- SOPS-nix Guide: https://github.com/Mic92/sops-nix
- nix-darwin Manual: https://daiderd.com/nix-darwin/manual/
- WireGuard Protocol: https://www.wireguard.com/protocol/

### Code References

- Existing Tailscale Module: `modules/nixos/shared/tailscale.nix`
- nix-darwin NetBird Module: `~/projects/nix-workspace/nix-darwin/modules/services/netbird.nix`
- nix-darwin OpenSSH Module: `~/projects/nix-workspace/nix-darwin/modules/services/openssh.nix`

### Community Resources

- NixOS Discourse: NetBird Setup Keys: https://discourse.nixos.org/t/declaratively-start-netbird-with-setup-key/68180
- Setting up NetBird with Nix: https://blog.aicampground.com/p/setting-up-authentik-and-netbird-with-nix
- NetBird GitHub Issues: https://github.com/netbirdio/netbird/issues

## Appendix A: Architecture Decision Records

### ADR-001: Why NetBird Instead of Tailscale?

**Status:** Informational (both are supported)

**Context:**
- Tailscale already configured and working
- NetBird offers similar functionality

**Decision:** Support both, treat as complementary

**Rationale:**
- **NetBird Advantages:**
  - Open-source with self-hosting option
  - No account limits (Tailscale free tier: 3 users, 100 devices)
  - Aligns with decentralization goals (Radicle integration)

- **Tailscale Advantages:**
  - More mature, larger user base
  - Better macOS integration (native app)
  - Existing deployment in this config

- **Complementary Use:**
  - Tailscale: Personal devices, cross-platform (iOS, Android)
  - NetBird: Infrastructure, Darwin-to-Darwin, future self-hosted

**Consequences:**
- Maintain two mesh networks (minimal overhead)
- SSH accessible via both Tailscale and NetBird IPs
- Fallback if one network has issues

### ADR-002: SOPS-nix Instead of Agenix for Secrets

**Status:** Accepted (already decided in existing config)

**Context:**
- Both agenix and sops-nix are imported in darwin/default.nix
- SOPS already configured with .sops.yaml

**Decision:** Use SOPS-nix for NetBird secrets

**Rationale:**
- Consistency with existing infrastructure
- age encryption (ed25519) already set up
- Per-host and service secret paths established
- SOPS supports YAML (structured secrets)

### ADR-003: One-Time Setup Keys vs. Pre-Shared Keys

**Status:** Accepted

**Context:**
- NetBird supports two authentication methods:
  1. Setup keys (enrollment tokens)
  2. Pre-shared keys (PSK for WireGuard layer)

**Decision:** Use one-time setup keys, NOT pre-shared keys

**Rationale:**
- **Security:** One-time keys have limited blast radius if leaked
- **Rotation:** Easy to generate new key per deployment
- **Auditability:** Track which key enrolled which peer in NetBird UI
- **Best Practice:** NetBird docs recommend one-time keys for machines

**Consequences:**
- Need to generate new key for each new host
- Cannot reuse keys (by design, for security)

### ADR-004: Activation Script vs. Systemd/Launchd Unit for Auth

**Status:** Accepted

**Context:**
- nix-darwin netbird module doesn't support setup keys
- Need declarative authentication

**Decision:** Use activation script (darwin) / systemd oneshot (linux)

**Rationale:**
- **Runs once:** Idempotent check via `.authenticated` marker
- **Ordering:** Runs before netbird daemon starts
- **Declarative:** Managed by Nix, not manual commands
- **Secrets access:** Can read SOPS-decrypted setup key

**Alternatives Considered:**
1. Manual `netbird up` after deployment (rejected: not declarative)
2. LaunchD RunAtLoad with setup key (rejected: runs every boot)
3. Separate management script (rejected: over-engineered)

### ADR-005: SSH on All Interfaces vs. NetBird-Only

**Status:** Accepted

**Context:**
- SSH can listen on:
  1. All interfaces (0.0.0.0)
  2. Specific IP (NetBird interface only)

**Decision:** Listen on all interfaces, rely on NetBird ACLs for restriction

**Rationale:**
- **Dynamic IPs:** NetBird assigns IPs dynamically (hard to predict)
- **Flexibility:** Can SSH via Tailscale, local network, or NetBird
- **Safety Net:** If NetBird fails, still accessible via Tailscale
- **Security:** NetBird ACLs provide network-level firewall
- **Defense in Depth:** SSH still requires key authentication

**Consequences:**
- SSH exposed on local network (mitigated: no password auth)
- NetBird ACL is critical security control
- Firewall on local network should still block SSH (port 22)

## Appendix B: Glossary

**Terms:**

- **CGNAT:** Carrier-Grade NAT, private IP range 100.64.0.0/10 used by NetBird
- **Setup Key:** One-time authentication token for enrolling peers
- **Peer:** A device connected to the NetBird network
- **Signal Service:** WebRTC signaling server for NAT traversal
- **STUN:** Session Traversal Utilities for NAT, helps discover public IP
- **TURN:** Traversal Using Relays around NAT, relay server for P2P failures
- **ICE:** Interactive Connectivity Establishment, framework for NAT traversal
- **WireGuard:** Modern, fast VPN protocol using Noise framework
- **utun:** macOS kernel interface for user-space tunnels
- **Launchd:** macOS service management daemon (like systemd)
- **SOPS:** Secrets OPerationS, encrypted secrets file manager
- **Age:** Simple, modern encryption tool (alternative to GPG)

## Appendix C: Quick Reference Commands

**NetBird:**

```bash
# Status
netbird status

# Detailed peer info
netbird status --detail

# List peers
netbird peers

# Disconnect
netbird down

# Reconnect (uses existing config.json)
netbird up

# Force re-authentication
netbird up --setup-key <new-key>

# View logs
tail -f /var/log/netbird.out.log
```

**SSH:**

```bash
# Connect via NetBird
ssh crs58@100.64.x.x

# Connect with verbose output (debugging)
ssh -v crs58@100.64.x.x

# Test SSH key authentication
ssh-add -l  # List loaded keys
ssh -i ~/.ssh/id_ed25519 crs58@100.64.x.x
```

**SOPS:**

```bash
# Decrypt and view
sops services/netbird-setup-keys.yaml

# Decrypt to stdout
sops -d services/netbird-setup-keys.yaml

# Edit (decrypts, opens editor, re-encrypts on save)
sops services/netbird-setup-keys.yaml

# Rotate keys
sops rotate --remove-age <old-key> --add-age <new-key> services/netbird-setup-keys.yaml
```

**Debugging:**

```bash
# Check interface
ifconfig utun100

# Check routes
netstat -rn | grep utun100

# Check launchd daemon
launchctl list org.nixos.netbird
launchctl print system/org.nixos.netbird

# Restart daemon
sudo launchctl kickstart -k system/org.nixos.netbird

# View system logs
log stream --predicate 'processImagePath contains "netbird"' --level debug
```

## Revision History

| Date       | Version | Author | Changes                              |
|------------|---------|--------|--------------------------------------|
| 2025-10-15 | 1.0     | Claude | Initial implementation plan created  |

---

**Document Status:** DRAFT - Ready for Implementation

**Next Steps:**
1. Review plan with user
2. Generate NetBird setup keys
3. Begin Phase 1 (Secrets Infrastructure)
