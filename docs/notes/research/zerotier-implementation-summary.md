# ZeroTier Implementation Summary for blackphos

## Quick Decision Matrix

| Approach | Complexity | Launch Daemon | GUI | Pure-Nix | Reproducibility | Recommendation |
|----------|-----------|---------------|-----|----------|-----------------|-----------------|
| **Homebrew Cask** | Low | Built-in | Yes | No | Medium | **Recommended** |
| **nixpkgs + launchd** | Medium | Manual | No | Yes | High | Alternative |
| **nixpkgs only** | High | None | No | Yes | High | Not recommended |

## Recommended: Homebrew Cask Installation

### Why This Approach?

1. **Zero additional setup**: Homebrew cask handles launch daemon registration automatically
2. **GUI included**: ZeroTier One menubar app provides visual network status
3. **Official channel**: Homebrew cask is the official distribution for macOS
4. **Lowest friction**: Simple one-line addition to nix-darwin config
5. **Already used**: Project already uses homebrew for other casks (Discord, Claude, etc.)

### Implementation

Add to blackphos nix-darwin configuration:

```nix
# In the machine configuration for blackphos
{
  homebrew = {
    enable = true;
    casks = [
      "zerotier-one"
      # ... other existing casks
    ];
  };
}
```

### First-Time Setup Procedure

After `darwin-rebuild switch`:

1. **Verify daemon started**:
   ```bash
   launchctl list | grep zerotier
   ```
   Should show the zerotier service loaded.

2. **Get member ID** (10-char hex):
   ```bash
   zerotier-cli info | awk '{print $3}'
   ```

3. **Send to admin** (crs58):
   - Slack/message the member ID to admin
   - Member ID allows zerotier network controller to admit this machine

4. **Join the network**:
   ```bash
   zerotier-cli join a8a2c3c10c1a68de  # (use actual network ID from cinnabar admin)
   ```
   Output should be: `200 join OK`

5. **Verify network joined**:
   ```bash
   zerotier-cli listnetworks
   ```
   Should show the network with status info.

6. **Get assigned IPv6 address** (check multiple times as it takes a moment):
   ```bash
   zerotier-cli info | grep "zt"
   # Or via network interface:
   ifconfig | grep -A3 "^zt"
   ```
   Should show IPv6 address like `fd5d:bbe3:...`

7. **Share zerotier IP with admin** for cinnabar admission
   - Once assigned, the zerotier IPv6 address is what the controller uses for authorization

### Subsequent Boots

After first join and admission, the zerotier network should automatically rejoin on boot.

To verify after restart:
```bash
zerotier-cli listnetworks
```

Should immediately show the network as joined.

## Network Joining Mechanics

### Why Manual First Join?

ZeroTier's declarative configuration has a limitation on new nodes:

- **Can do**: Create empty network config files in `networks.d/` (tells zerotier to join on startup)
- **Cannot do**: Automatically join a network you've never joined before
- **Must happen**: First join is always imperative (CLI or GUI)
- **Why**: ZeroTier generates node identity on first startup; network must be pre-configured with that identity

### What Happens on First Join

```
1. zerotier-cli join <network-id>
2. zerotier-one generates identity.secret and identity.public
3. Node sends membership request to network controller
4. Controller sees new node, must explicitly admit it
5. Controller assigns IPv6 address from network's allocation pool
6. On subsequent boots: rejoins automatically from networks.d config
```

### Member ID vs IPv6 Address

- **Member ID** (10-char hex): Unique identifier of the zerotier node, derived from identity.secret
  - Example: `a8a2c3c10c`
  - Used by controller to identify and admit the machine
  - Derived from the cryptographic identity

- **IPv6 Address** (zerotier's 6plane allocation): Network-assigned address
  - Example: `fd5d:bbe3:cbc5:fe6b:f699:935d:bbe3:cbc5`
  - Used for actual network communication
  - Assigned by controller after admission

Both are needed for full network integration.

## Networking Architecture

### On macOS

When zerotier is running:

- **Network interface**: `zt0`, `zt1`, etc. (virtual interfaces for each joined network)
- **Accessible from**: Any process on the machine can reach zerotier IPs
- **Routing**: Handled by zerotier daemon (no additional route management needed)
- **DNS**: Optional (ZeroTier doesn't provide DNS by default unless network configured)

### From cinnabar Perspective

Once blackphos is admitted:

- **Access method**: SSH via IPv6 zerotier address
  ```bash
  ssh raquel@fd5d:bbe3:cbc5:fe6b:f699:935d:bbe3:cbc5
  ```
- **Firewall**: Zerotier network acts as VPN; only admitted nodes can communicate
- **Relaying**: If blackphos is behind NAT, cinnabar's zerotier moon provides relay capability

## Troubleshooting Quick Reference

| Issue | Command | Expected Result |
|-------|---------|-----------------|
| Service not running | `launchctl list \| grep zerotier` | Service listed with PID |
| Daemon hung | `launchctl stop com.zerotier.one` then `start` | Service restarts |
| Network not joining | `zerotier-cli join <id>` | `200 join OK` |
| No IP assigned | `zerotier-cli info` | Status should be `UP` |
| Can't reach network | `ping6 fd5d:bbe3::1` (controller IP) | Should respond |

## Post-Implementation Steps

Once zerotier is working on blackphos:

1. **Update documentation** with blackphos zerotier address for remote access
2. **Test connectivity** from cinnabar to blackphos via zerotier IP
3. **Consider static IP** if frequently accessed (requires controller config)
4. **Backup identity** (optional): `cp /Library/Application\ Support/ZeroTier/One/identity.* ~/.zerotier-backup/`

## Related Configuration

For blackphos raquel user setup, consider:

- **SSH key**: Ensure raquel's public key is in cinnabar's authorized_keys
- **Home-manager**: Can configure raquel's SSH client to use zerotier IPs
- **Firewall**: macOS firewall should allow zerotier (usually automatic with GUI app)

## Advanced: Declarative Post-Join Configuration

Once blackphos has joined and received an IPv6 address, future configurations could pre-seed:

```nix
environment.etc."zerotier/networks.d/<network-id>.conf" = {
  text = "";  # Empty file signals to rejoin on startup
};

# Optional: Set TCP fallback relay (for NAT traversal)
environment.etc."zerotier/local.conf".text = builtins.toJSON {
  settings = {
    tcpFallbackRelay = "65.21.12.51/4443";  # Clan-core's relay
  };
};
```

However, these require:
- Running `darwin-rebuild switch` as root
- `/Library/Application Support/ZeroTier/One` directory access
- May conflict with Homebrew management

**Current recommendation**: Keep it simple with just the homebrew cask; manual declarative config is not necessary for basic connectivity.

## References

- Full research: `docs/notes/research/zerotier-nix-darwin-research.md`
- ZeroTier official docs: https://docs.zerotier.com/
- Project repos:
  - `/Users/crs58/projects/nix-workspace/infra` (this repo)
  - `/Users/crs58/projects/nix-workspace/test-clan` (validation repo with clan zerotier)
  - `/Users/crs58/projects/nix-workspace/clan-core` (zerotier service source)
