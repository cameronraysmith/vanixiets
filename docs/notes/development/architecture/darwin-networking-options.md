# Darwin Networking Options

**Problem**: Clan's zerotier service is NixOS-only (systemd dependencies, no darwin module). Darwin machines need alternative networking approach.

## Option 1: Homebrew Zerotier (Maintains Consistency)

**Status**: ⚠️ Unvalidated (theoretical, requires Story 1.8 testing)

**Setup**:
```nix
# modules/darwin/homebrew.nix
{
  homebrew.enable = true;
  homebrew.casks = [ "zerotier-one" ];
}

# Deploy
darwin-rebuild switch --flake .#blackphos

# Manual network join (after GUI installation)
# 1. Open Zerotier One from Applications
# 2. Join network: cat /run/secrets/zerotier-network-id
# 3. Verify: zerotier-cli status
```

**Integration with Clan Vars**:
```bash
# Network ID from clan vars (generated on controller)
NETWORK_ID=$(cat /run/secrets/zerotier-network-id)

# Join network (command-line alternative to GUI)
zerotier-cli join $NETWORK_ID

# Verify connection
zerotier-cli listnetworks
zerotier-cli listpeers
```

**Pros**:
- Maintains zerotier consistency with NixOS machines
- Uses clan-generated network-id (partial integration)
- GUI app for management
- Same VPN as test-clan validation

**Cons**:
- Not fully nix-managed (homebrew + GUI app)
- Manual network join required
- No automatic peer acceptance (controller auto-accept may not work)
- Requires testing in Story 1.8

## Option 2: Custom Launchd Service (Full Nix Control)

**Status**: ⚠️ Unvalidated (complex, inspired by mic92 hyprspace pattern)

**Setup**:
```nix
# modules/darwin/zerotier-custom.nix
{ config, pkgs, lib, ... }:
{
  # Install zerotier-one package
  environment.systemPackages = [ pkgs.zerotierone ];

  # Custom launchd service
  launchd.daemons.zerotierone = {
    serviceConfig = {
      ProgramArguments = [ "${pkgs.zerotierone}/bin/zerotier-one" ];
      KeepAlive = true;
      RunAtLoad = true;
      StandardOutPath = "/var/log/zerotier-one.log";
      StandardErrorPath = "/var/log/zerotier-one.log";
    };
  };

  # Deploy identity from clan vars
  environment.etc."zerotier-one/identity.secret" = {
    source = config.clan.core.vars.generators.zerotier.files.zerotier-identity-secret.path;
    mode = "0600";
  };

  # Join network on activation
  system.activationScripts.zerotier-join.text = ''
    sleep 5  # Wait for zerotier-one to start
    NETWORK_ID=$(cat ${config.clan.core.vars.generators.zerotier.files.zerotier-network-id.path})
    ${pkgs.zerotierone}/bin/zerotier-cli join $NETWORK_ID
  '';
}
```

**Pros**:
- Fully declarative (nix-managed)
- Integrates with clan vars (identity + network-id)
- No GUI app required
- Maximum control over zerotier configuration

**Cons**:
- Complex implementation (requires darwin launchd expertise)
- Untested (requires Story 1.8 validation)
- May have edge cases (identity deployment timing, service lifecycle)
- Higher maintenance burden

## Option 3: Hybrid Clan Vars + Manual Zerotier (Pragmatic)

**Status**: ✅ Recommended for Story 1.8 (minimal risk, validates integration)

**Setup**:
```nix
# Use clan vars generators (platform-agnostic)
clan.core.vars.generators.zerotier = {
  files.zerotier-ip.secret = false;
  files.zerotier-identity-secret = { };
  files.zerotier-network-id.secret = false;
  script = ''
    python3 ${./generate.py} --mode identity \
      --ip "$out/zerotier-ip" \
      --identity-secret "$out/zerotier-identity-secret" \
      --network-id ${networkId}
  '';
};

# Manual zerotier setup (homebrew or custom)
# Clan controller (cinnabar) auto-accepts peer using zerotier-ip fact
```

**Workflow**:
```bash
# 1. Generate vars on darwin machine
clan vars generate blackphos

# 2. Install zerotier (manual or homebrew)
# Option A: brew install zerotier-one
# Option B: Download from zerotier.com

# 3. Join network using clan-generated network-id
NETWORK_ID=$(cat /run/secrets/zerotier-network-id)
zerotier-cli join $NETWORK_ID

# 4. Verify controller auto-accepts (cinnabar sees blackphos zerotier-ip)
ssh root@cinnabar.zerotier.ip "zerotier-cli listpeers | grep blackphos"
```

**Pros**:
- Reuses clan vars infrastructure (identity generation proven)
- Minimal custom code (leverage existing zerotier installation methods)
- Validates clan var integration patterns before full automation
- Easy to upgrade to Option 2 or 3 later (vars already generated)

**Cons**:
- Partially manual (not fully declarative)
- Requires documentation for manual steps
- Network join not automatic on system activation

## Recommendation for Story 1.8

**Use Option 3 (Hybrid Clan Vars + Manual Zerotier)** for initial validation:

1. Validates clan vars integration with darwin
2. Proves controller auto-accept works with darwin peers
3. Minimal risk (manual fallback if issues)
4. Provides data for architecture refinement

**Future Enhancement** (Epic 2+):
- Implement Option 1 (Homebrew) if zerotier consistency is priority
- Implement Option 2 (Custom Launchd) if full nix control required

**Decision Deferred to Story 1.8**: Test hybrid approach, gather data, refine architecture based on findings.
