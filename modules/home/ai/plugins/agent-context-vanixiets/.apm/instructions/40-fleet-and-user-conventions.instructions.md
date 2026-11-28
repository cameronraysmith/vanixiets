---
description: vanixiets machine and user conventions — provisioning state, admin-username split, and where the authoritative fleet inventory lives.
---

## Machine configuration

Cloud machines are declared through terranix in `modules/terranix/`, one file per provider.
Each machine carries an `enabled` boolean: setting it to `false` and running `nix run .#terraform`, which runs `tofu apply` on the configuration rendered from the current tree and asks for confirmation, removes the cloud resources while leaving the machine's full NixOS configuration, clan inventory entry, and disko layout in the repository.
A machine present in `machines/` is therefore not necessarily provisioned, and agents should not assume any machine is reachable or attempt remote operations against one.

Every account on every host has `fastfetch` and `nix-info` (`cli-host-inspection`, imported by the NixOS and nix-darwin `base` aspects and `homeManager.engineering-tools`), so `fastfetch --format json -s <modules>` (for example `-s os:kernel:cpu:memory`) and `nix-info -m` describe a host without root.
NixOS hosts add `systemd-detect-virt`, `lscpu -J` and `lsblk -J` for virtualisation, CPU and block-device detail.

From an agent session on a Mac, reach fleet services by their `*.vanixiets.internal` (tincr) names, not `*.zt`: macOS Local Network privacy refuses ZeroTier's Ethernet-like `feth` interface to a Nix-built client (the store's curl or python, for instance) whose responsible program, herdr for instance, holds no Local Network grant, failing in milliseconds with "No route to host", while tincr's tunnel interface is outside that privacy.

Two admin-username conventions coexist: older machines force the username `crs58`, and newer ones use `cameron` as a home-manager alias for the same account.
Modules that hardcode a username are following one convention or the other, and which one is a property of the machine.

The authoritative fleet inventory is the host registry, `modules/lib/hosts.nix`, one record per machine whose fields include its tags and description; the clan inventory (`modules/clan/inventory/machines.nix`) is computed from those records, and the authoritative user list is the set of directories under `modules/home/users/`.
This file intentionally does not reproduce either inventory as a table — consult those paths directly rather than a snapshot that will drift.
