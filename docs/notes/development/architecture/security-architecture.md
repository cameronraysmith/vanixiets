# Security Architecture

## Secrets Encryption

**Age-Based Encryption** (via clan vars):
- **Admin group keys**: `sops/groups/admins/` (multiple admin age keys)
- **Per-machine keys**: Generated during clan init, used for machine-specific secrets
- **Encryption**: Secrets encrypted with all admin keys + target machine key
- **Decryption**: Only target machine + admins can decrypt secrets

**Key Distribution**:
```bash
# Admin generates age key
clan secrets key generate

# Admin provides public age key to repository maintainer
cat ~/.config/sops/age/keys.txt | grep "public key:"

# Maintainer adds admin to admins group
clan secrets groups add-user admins <username> <age-public-key>

# Admin can now decrypt all secrets
clan vars generate <machine-name>
```

## SSH Access Control

**Certificate-Based Authentication** (clan sshd service):
- **SSH CA**: Centralized certificate authority managed by clan
- **Certificate issuance**: Automatic certificate generation for authorized users
- **No password authentication**: `PasswordAuthentication no` enforced
- **Public key fallback**: SSH keys in `users.users.<user>.openssh.authorizedKeys.keys`

**Root Access**:
```nix
# Auto-grant root access to all wheel users (clan-infra pattern)
users.users.root.openssh.authorizedKeys.keys = builtins.concatMap
  (user: user.openssh.authorizedKeys.keys)
  (builtins.attrValues (
    lib.filterAttrs (_name: value:
      value.isNormalUser && builtins.elem "wheel" value.extraGroups
    ) config.users.users
  ));
```

**Emergency Access** (clan emergency-access service):
- **Password recovery**: Root password set via clan vars (workstations only)
- **Console access**: Login via console/physical access with emergency password
- **Not on VPS**: Emergency access disabled on VPS to prevent remote exploitation

## Firewall Configuration

**NixOS Firewall** (cinnabar/electrum):
```nix
networking.firewall = {
  enable = true;
  allowedTCPPorts = [ 22 ];         # SSH
  allowedUDPPorts = [ 9993 ];       # Zerotier
  interfaces."zt*".allowedTCPPorts = [ ];  # Zerotier interfaces (mesh-internal services)
};
```

**Darwin Firewall**:
```nix
# macOS built-in firewall (socketfilterfw)
system.defaults.alf = {
  globalstate = 1;                  # Firewall enabled
  allowsignedenabled = 1;           # Allow signed applications
  stealthenabled = 1;               # Stealth mode (don't respond to ping)
};
```

## VPS Hardening

**srvos Modules** (clan-infra pattern):
```nix
imports = [
  inputs.srvos.nixosModules.server            # Security baseline
  inputs.srvos.nixosModules.mixins-nix-experimental  # Nix experimental features
];
```

**Hardening Features**:
- Minimal package set (no unnecessary packages)
- SSH hardening (key-only auth, no root password login)
- Automatic security updates (nixpkgs tracking)
- Restricted systemd service permissions
- Audit logging enabled

## Zerotier Network Security

**Mesh VPN Encryption**:
- **End-to-end encryption**: All traffic encrypted with AES-256
- **Network isolation**: Separate zerotier network for infrastructure
- **Controller authorization**: Peers require controller approval (auto-accept via inventory)

**Network Access Control**:
```nix
# Cinnabar controller auto-accepts peers from inventory
systemd.services.zerotier-inventory-autoaccept = {
  # Automatically authorize peers based on zerotier-ip fact
  # Only machines in clan inventory are auto-accepted
};
```
