---
title: Dynamize hardcoded zerotier addresses
---

# Dynamize hardcoded zerotier addresses

## Problem

75 hardcoded zerotier IPv6 addresses, IPv4 addresses, and network IDs are scattered across 12 files.
If the zerotier network is regenerated (new identity secrets, new network ID), every reference must be updated manually.
This was exposed during the clan-core update in PR #1701, where `clan machines update` silently regenerated all zerotier vars with fresh cryptographic material.

## Current state

Seven nix config files contain hardcoded zerotier values:

| File | Hardcoded values | Count |
|---|---|---|
| `modules/machines/nixos/cinnabar/zt-dns.nix` | All machine IPs, subnet config, listen addresses | ~25 |
| `modules/machines/nixos/cinnabar/caddy.nix` | Controller IP in trusted_proxies | ~12 |
| `modules/darwin/zt-dns.nix` | Controller IP as nameserver | 1 |
| `modules/system/ssh-known-hosts.nix` | All machine IPs in hostNames | ~9 |
| `modules/home/core/ssh.nix` | All machine IPs as SSH hostnames | ~9 |
| `modules/clan/inventory/services/zerotier.nix` | Darwin external member IPs | ~5 |
| `modules/home/tools/commands/network-tools.nix` | Network ID and prefix | ~4 |

Five documentation files contain hardcoded network IDs and subnet references (~10 occurrences).

## Available mechanisms

### `flake.nixosConfigurations.<machine>.config` (cross-machine eval)

Already proven in this repo at `modules/system/ssh-known-hosts.nix` for SSH public keys.
Vars values come from `builtins.readFile` on the `vars/` directory tree, not from recursive module evaluation, so no evaluation cycle risk.

```nix
flake.nixosConfigurations.electrum.config.clan.core.vars.generators.zerotier.files.zerotier-ip.value
```

Works for all four NixOS machines (cinnabar, electrum, galena, scheelite).

### `clanLib.getPublicValue` (filesystem read)

Used by clan's own `zerotier-inventory-autoaccept` service to read peer IPs dynamically.
Only available inside `clanService` modules, not regular NixOS/darwin modules.
Not directly usable in our existing module structure without importing the function.

### Manual vars files for darwin machines

`getPublicValue` and `builtins.readFile` don't care how a file was created.
Manually committing zerotier-ip values for darwin machines makes them accessible via the same pattern:

```
vars/per-machine/stibnite/zerotier/zerotier-ip/value
vars/per-machine/blackphos/zerotier/zerotier-ip/value
vars/per-machine/argentum/zerotier/zerotier-ip/value
vars/per-machine/rosegold/zerotier/zerotier-ip/value
```

Values are obtainable from each machine via `sudo zerotier-cli listnetworks`.

## Implementation plan

### Phase 1: shared helper module

Create a module that builds a complete machine-to-zerotier-IP mapping, accessible to all other modules.

```nix
# modules/clan/networking/zerotier-addresses.nix (conceptual)
let
  nixosMachines = ["cinnabar" "electrum" "galena" "scheelite"];
  darwinMachines = ["stibnite" "blackphos" "argentum" "rosegold"];

  nixosZtIp = name:
    flake.nixosConfigurations.${name}.config.clan.core.vars.generators.zerotier.files.zerotier-ip.value;

  darwinZtIp = name:
    builtins.readFile (../../vars/per-machine/${name}/zerotier/zerotier-ip/value);

  networkId =
    flake.nixosConfigurations.cinnabar.config.clan.core.vars.generators.zerotier-controller.files.zerotier-network-id.value;
in {
  ztIPs = lib.genAttrs nixosMachines nixosZtIp
       // lib.genAttrs darwinMachines darwinZtIp;
  inherit networkId;
  # IPv4 subnet and prefix can be derived from networkId
}
```

Design decisions to resolve during implementation:

- Where to expose this: as a `flake.lib` function, a shared module option, or a let-binding imported by consumers.
- Whether to derive the IPv4 subnet deterministically from the network ID or keep it as a separate configuration.
- Whether the android device IP should be included (currently no vars file, would need manual creation like darwin).

### Phase 2: create manual vars files for darwin machines

Obtain each machine's zerotier IPv6 from the running machines:

```bash
# On each darwin machine:
sudo zerotier-cli listnetworks | awk '{print $NF}' | grep -oP 'fd[^/]+'
```

Commit one-line files to `vars/per-machine/<machine>/zerotier/zerotier-ip/value`.

### Phase 3: migrate consumers

Replace hardcoded addresses in each file with references to the shared helper:

| File | Change |
|---|---|
| `zt-dns.nix` | Replace all IP literals with `ztIPs.<machine>` lookups; derive listen-address, DNS records, subnet from helper |
| `caddy.nix` | Replace trusted_proxies literals with `ztIPs.cinnabar` |
| `darwin/zt-dns.nix` | Replace nameserver literal with `ztIPs.cinnabar` |
| `ssh-known-hosts.nix` | Replace IP literals with `ztIPs.<machine>` (SSH keys already dynamic) |
| `ssh.nix` | Replace hostname literals with `ztIPs.<machine>` |
| `zerotier.nix` (inventory) | Replace `allowedIps` literals with `ztIPs.<machine>` for darwin external members |
| `network-tools.nix` | Replace network ID literal with shared helper; derive prefix |

### Phase 4: update documentation

Replace hardcoded network IDs in tutorial and guide files with references to the vars system, or accept that documentation examples use specific values as illustrations.

## Scope and limitations

Approximately 65 of 75 references become dynamic after phases 1-3.
The remaining ~10 are:

- Android device IP (no nix management; could add manual vars file)
- Documentation examples (illustrative, not functional)

Darwin machine IPs remain version-controlled but are manually maintained.
A network regeneration would still require updating 4 darwin vars files and 1 android vars file, but this is a controlled update in one directory rather than a search-and-replace across 12 files.

## Risk considerations

The `flake.nixosConfigurations` cross-reference pattern is safe for vars because vars values resolve to `builtins.readFile` calls, not recursive module evaluation.
However, referencing `config.clan.core.vars.generators.zerotier.files.zerotier-ip.value` triggers evaluation of the zerotier module's option declarations on the target machine.
If the target machine's zerotier module has strict assertions or conditional logic that depends on the calling machine's config, cycles could occur.
Testing each consumer migration individually with `nix eval` is essential.

## Origin

This plan emerged from the clan-core update session (2026-04-02) where `clan machines update cinnabar` silently regenerated all zerotier vars, revealing the brittleness of 75 hardcoded addresses.
