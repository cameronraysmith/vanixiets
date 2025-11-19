# ZeroTier Installation and Configuration for nix-darwin (blackphos)

## Overview

This document synthesizes research on zerotier installation and configuration options for macOS (nix-darwin) systems, specifically for blackphos (raquel's nix-darwin laptop). The goal is to join the zerotier network coordinated by cinnabar (nixos controller).

## Option 1: nixpkgs zerotierone Package

### Package Details

**Location**: `/Users/crs58/projects/nix-workspace/nixpkgs/pkgs/by-name/ze/zerotierone/package.nix`

**Version**: 1.16.0

**Platform Support**: Unix platforms including macOS (darwin) with explicit darwin patches

### Build Configuration

The zerotierone package supports macOS with specific build configuration:

- **Darwin-specific patches**:
  - `0001-darwin-disable-link-time-optimization.patch` - fixes LTO issues
  - `0002-Support-single-arch-builds-on-macOS.patch` - single architecture builds (required because nixpkgs doesn't support multi-arch builds)

- **Darwin dependencies**: libiconv added for macOS

- **Build flags**: Platform-specific handling via `ARCH=${stdenv.hostPlatform.darwinArch}`

### Limitations

- **No self-tests on darwin**: The package disables check phase for darwin (`doCheck = ... && !stdenv.hostPlatform.isDarwin`) due to sandbox issues with UDP socket binding
- **No native service integration**: The nixpkgs package is just CLI binaries and libraries; it requires separate integration for macOS launch daemon

### What Gets Installed

- **CLI binary**: `/bin/zerotier-one` - main daemon executable
- **CLI tools**: `/bin/zerotier-cli`, `/bin/zerotier-idtool`
- **Man pages**: documentation for zerotier commands

### Clan's Custom zerotierone Package

**Location**: `/Users/crs58/projects/nix-workspace/clan-core/pkgs/zerotierone/default.nix`

The clan-core project provides a wrapper that:
- Conditionally enables controller support (requires `enableUnfree = true` for versions >= 1.16)
- Changes license from MPL2.0 to APSL2.0 for halal certification
- Applies the same darwin test skip

## Option 2: Homebrew Cask Installation

### Homebrew Formula

**Reference**: `https://github.com/Homebrew/homebrew-cask/blob/d782f3414b8116aafdcaf1bb3d726f1c3a41b2fd/Casks/z/zerotier-one.rb`

### What Gets Installed

The homebrew cask installs:

- **Application package**: `ZeroTier One.pkg` installer
- **Launch daemon**: Service registered as `com.zerotier.one` via launchd
- **GUI application**: `com.zerotier.ZeroTier-One` (system menubar app for management)
- **CLI binaries**: Same as nixpkgs (zerotier-one, zerotier-cli)
- **Preference plist**: `~/Library/Preferences/com.zerotier.ZeroTier-One.plist`

### nix-darwin Integration

nix-darwin provides homebrew module integration via `homebrew.casks`:

**File**: `/Users/crs58/projects/nix-workspace/nix-darwin/modules/homebrew.nix`

**Usage pattern**:

```nix
{
  homebrew = {
    enable = true;
    casks = [
      "zerotier-one"
      # other casks...
    ];
  };
}
```

**Key features**:
- Automatically generates Brewfile and runs `brew bundle install` during `darwin-rebuild switch`
- Supports cask arguments like `caskArgs.no_quarantine = true` to skip gatekeeper quarantine on install
- Supports cleanup policies: `none` (default), `uninstall`, or `zap`
- Respects `onActivation` settings for upgrade/autoUpdate behavior

### Advantages over nixpkgs

1. Includes native launch daemon registration (automatic service startup)
2. Includes GUI application for network management
3. Official homebrew cask (well-maintained, official distribution channel)
4. Simple declarative syntax in nix-darwin

### Disadvantages

1. Adds homebrew as dependency (requires installing/maintaining homebrew)
2. Less reproducible (homebrew versioning can vary)
3. Requires macOS-specific configuration (not cross-platform)

## Option 3: nixpkgs + Custom nix-darwin Service Module

For a pure-nix approach without homebrew, combine:

1. **zerotierone from nixpkgs** - provides binaries
2. **Custom nix-darwin launchd service** - registers launch daemon
3. **Configuration files** - manage networks.d and local.conf

### Launch Daemon Integration

nix-darwin provides `launchd.daemons.<name>` for creating launch agents. Example from `dnscrypt-proxy.nix`:

```nix
launchd.daemons.zerotierone = {
  script = ''
    ${pkgs.zerotierone}/bin/zerotier-one -p9993
  '';
  serviceConfig = {
    RunAtLoad = true;
    KeepAlive = true;
    StandardOutPath = "/var/log/zerotier-one.log";
    StandardErrorPath = "/var/log/zerotier-one.log";
  };
};
```

## macOS Configuration Paths

### System-Level Configuration (requires admin)

- **Working directory**: `/Library/Application Support/ZeroTier/One`
  - `networks.d/` - join networks by creating empty `<network-id>.conf` files
  - `identity.secret` / `identity.public` - node identity files
  - `local.conf` - JSON configuration file
  - `authtoken.secret` - API token for CLI access

### User-Level Configuration

- **User config directory**: `~/Library/Application Support/ZeroTier`
  - Can store user's copy of `authtoken.secret`
  - Can store saved networks list

### Important Notes

- Configuration directory must persist (not volatile)
- The system-level directory requires admin access to read identity/auth tokens
- ZeroTier doesn't issue DHCP - it assigns IPv6 addresses from the network's 6plane addresses

## ZeroTier CLI Commands

### Basic Operations

```bash
# Start the daemon
zerotier-one -p9993

# Check daemon status and member ID
zerotier-cli info
# Output format: zerotier-one 1.16.0 ADDR <member-id> ... status <UP|DOWN>

# List networks
zerotier-cli listnetworks

# List members (on controller only)
zerotier-cli members

# List networks in JSON format
zerotier-cli listnetworks -j
```

### Network Management (Imperative)

```bash
# Join a network
zerotier-cli join <network-id>

# Leave a network
zerotier-cli leave <network-id>

# Orbit a moon (use moon as relay)
zerotier-cli orbit <moon-member-id> <moon-member-id>
```

### Identity Management

```bash
# Get public identity from secret
zerotier-idtool getpublic /path/to/identity.secret

# Generate moon JSON
zerotier-idtool initmoon /path/to/identity.public > /path/to/moon.json
```

## Declarative Network Configuration (Pre-seeding)

### Option A: Create networks.d Files

ZeroTier will automatically join networks if empty config files exist in `networks.d/`:

```bash
touch /Library/Application\ Support/ZeroTier/One/networks.d/<network-id>.conf
```

Can be managed via nix-darwin `environment.etc`:

```nix
environment.etc."zerotier/networks.d/${networkId}.conf" = {
  text = "";
};
```

### Option B: local.conf Configuration

**File**: `/Library/Application Support/ZeroTier/One/local.conf` (JSON format)

**Example**:
```json
{
  "settings": {
    "tcpFallbackRelay": "65.21.12.51/4443"
  }
}
```

Can be managed via nix-darwin:

```nix
environment.etc."zerotier/local.conf".text = builtins.toJSON {
  settings = {
    tcpFallbackRelay = "65.21.12.51/4443";
  };
};
```

### Limitation: Networks Must Be Pre-Existing

Critical constraint for declarative approach:

- You **can** pre-seed the config directory with network IDs in `networks.d/`
- You **cannot** automatically join a network that doesn't exist yet on the node
- ZeroTier will attempt to join listed networks on startup
- If the network hasn't been joined before, the node must be admitted by the controller

**Workflow implications**:
1. First boot: join network imperative via `zerotier-cli join <id>` or UI
2. Extract member ID: `zerotier-cli info | grep -oP '(?<=ADDR )\w+'`
3. Admit node on controller (cinnabar)
4. On subsequent boots: can use declarative config to auto-rejoin

## Home-Manager Integration (Alternative to System-Level)

home-manager doesn't provide native zerotier module, but can use:

### Activation Scripts

```nix
home.activation.zerotierJoin = ''
  ${pkgs.zerotierone}/bin/zerotier-cli join <network-id> || true
'';
```

**Limitations**:
- Requires zerotier daemon to already be running
- Limited to user-accessible CLI operations
- Cannot manage system-level config files (require admin)
- On macOS, typical users don't have permission to restart zerotier service

**Better approach**: System-level nix-darwin configuration for daemon, user-level activation scripts for post-startup configuration if needed.

## Clan-Core Service Integration

Clan-core provides comprehensive zerotier support designed for multi-machine networks:

**Location**: `/Users/crs58/projects/nix-workspace/clan-core/clanServices/zerotier/`

### Architecture

- **Service manifest**: Defines zerotier as a clan service
- **Roles**: `peer`, `moon`, `controller`
  - `peer`: Standard network participant
  - `moon`: Relay node (publicly reachable)
  - `controller`: Network controller (admits peers, manages network settings)

### Key Features

- **Automatic identity generation**: `zerotier-identity-secret` and `zerotier-ip` generated per-machine
- **Network variable management**: Stores generated network ID and IP allocations
- **Auto-admission on controller**: `zerotier-inventory-autoaccept` service auto-admits known machines

### Generated Artifacts (in clan vars)

Per-machine in `vars/per-machine/<machine>/zerotier/`:
- `zerotier-identity-secret` - private key for node identity
- `zerotier-identity-public` - derived public key (auto-generated if missing)
- `zerotier-ip` - assigned IPv6 address from network's 6plane space
- `zerotier-network-id` - network ID (on controller only)

### nixOS Module Integration

clan-core provides `clan.core.networking.zerotier` nixOS module with options:
- `networkId` - the zerotier network ID to join
- `name` - zerotier network name
- `moon.stableEndpoints` - if this machine is a moon
- `moon.orbitMoons` - moons to orbit
- `controller.enable` - run as controller
- `controller.public` - allow public joins

Currently **NOT available for nix-darwin** (only nixOS).

## Recommendations for blackphos

### Best Approach: Homebrew Cask + Declarative Config

**Rationale**:
1. Simplest integration with nix-darwin
2. Includes launch daemon (automatic startup)
3. Includes GUI for troubleshooting
4. Official, well-maintained distribution
5. Minimal custom configuration

**Implementation**:

```nix
# In blackphos nix-darwin configuration

{
  homebrew = {
    enable = true;
    casks = [
      "zerotier-one"
      # ... other casks
    ];
  };

  # Optional: pre-create networks.d directory structure
  # This would require custom activation script since
  # /Library/Application Support is outside standard nix-darwin paths
  
  # First join: manual via GUI or CLI after installation
  # $ zerotier-cli join <network-id-from-cinnabar>
}
```

**First-time setup workflow**:

1. Build and switch nix-darwin configuration with zerotier-one cask
2. Verify zerotier service is running: `launchctl list | grep zerotier`
3. Get member ID: `zerotier-cli info`
4. Send member ID to cinnabar admin (crs58)
5. Admin admits blackphos on cinnabar controller
6. Verify network joined: `zerotier-cli listnetworks`
7. Verify zerotier IP: `ifconfig | grep -A3 "zt"`

### Alternative: Pure-Nix Approach (More Work)

If homebrew dependency is unacceptable:

1. **Use nixpkgs zerotierone** - provides binaries
2. **Create custom nix-darwin launchd module** - register launch daemon
3. **Manage configuration** - create networks.d files in activation script
4. **Requires imperative join** - still need to manually join first network

**Advantages**: Pure nix, no homebrew
**Disadvantages**: More boilerplate, no GUI, more maintenance

### Extract Member ID After Installation

```bash
# Get the full info
zerotier-cli info

# Extract just the member ID (16-char hex)
zerotier-cli info | awk '{print $3}'

# Verify it looks right (16 hex chars)
zerotier-cli info | awk '{print $3}' | grep -E '^[0-9a-f]{10}$'
```

Member ID is also stored in:
```bash
# Public identity (derived, safe to share)
cat /Library/Application\ Support/ZeroTier/One/identity.public
```

### Configuration for cinnabar Admission

Once blackphos is on the zerotier network and has been assigned an IPv6 address, the address appears in:

```bash
# Get assigned zerotier IP
zerotier-cli info | grep "zt"

# Or extract from config store
cat /Library/Application\ Support/ZeroTier/One/zerotier-ip.conf
```

On cinnabar (controller), add to admission whitelist (handled automatically by clan-core's `zerotier-inventory-autoaccept` if configured, or manually via):

```bash
zerotier-cli members allow <blackphos-member-id>
```

## File Locations Summary

| Path | OS | Purpose | Managed By |
|------|-----|---------|-----------|
| `/Library/Application Support/ZeroTier/One` | macOS | System zerotier data (requires admin) | zerotier daemon |
| `/Library/Application Support/ZeroTier/One/networks.d/*.conf` | macOS | Network join declarations | can be pre-created |
| `/Library/Application Support/ZeroTier/One/identity.{secret,public}` | macOS | Node cryptographic identity | generated on first run |
| `/Library/Application Support/ZeroTier/One/local.conf` | macOS | Configuration (tcpFallbackRelay, etc) | can be declarative |
| `/Library/Preferences/com.zerotier.ZeroTier-One.plist` | macOS | GUI preferences | ZeroTier GUI app |
| `/var/lib/zerotier-one/` | Linux/nixOS | Linux zerotier data | systemd |

## References

- **nixpkgs zerotierone**: `/Users/crs58/projects/nix-workspace/nixpkgs/pkgs/by-name/ze/zerotierone/package.nix`
- **nix-darwin homebrew module**: `/Users/crs58/projects/nix-workspace/nix-darwin/modules/homebrew.nix`
- **clan-core zerotier service**: `/Users/crs58/projects/nix-workspace/clan-core/clanServices/zerotier/`
- **Example nix-darwin config**: `/Users/crs58/projects/nix-workspace/infra/modules/darwin/all/homebrew.nix`
- **Example clan zerotier config**: `/Users/crs58/projects/nix-workspace/test-clan/modules/clan/inventory/services/zerotier.nix`
- **Official ZeroTier docs**: https://docs.zerotier.com/
- **Official ZeroTier macOS docs**: https://docs.zerotier.com/macos/
- **ZeroTier CLI docs**: https://docs.zerotier.com/cli/
