---
title: Break-glass recovery
description: "Reaching or recovering each fleet host when the overlay network fails: the VPSes over their public addresses, pyrite over iroh, the Macs by the person at the machine booting the previous nix-darwin generation, and pixel11 by the operator at the phone."
---

This runbook is for the moment the overlay network (the mesh) is down for a host, or a deploy has broken it there.
Every host the operator administers remotely has one recovery path that does not depend on the mesh, chosen per host class in the `migrate-mesh-to-tincr` design (D4).

| Host class | Hosts | Recovery path |
|---|---|---|
| VPS with a public address | cinnabar, magnetite (and galena, scheelite when provisioned) | SSH on the public address, the provider console, clan `emergency-access` for boot failures |
| NixOS behind an address-translating router | pyrite | SSH over iroh from stibnite (see "pyrite over iroh") |
| darwin laptops of other people | argentum, rosegold | the person at the machine boots the previous nix-darwin generation (see "Macs: the person at the machine") |
| darwin, the operator's own | stibnite | the operator at the machine, with the same steps |
| Android phone | pixel11 | the operator at the phone: complete tincapp's `hosts/`, or reconnect the ZeroTier app while ZeroTier runs (see "pixel11") |

blackphos is a reserved name in the nix-darwin laptop class with no machine and no person behind it, so it has no recovery path until a machine takes the name.

## VPSes over their public address

Each VPS's public endpoint is recorded in `flake.lib.hosts.<name>.endpoints`.
Deploy over it with an explicit override, which bypasses the inventory target on the mesh:

```bash
clan machines update <host> --target-host root@<public address> --flake "git+file://$PWD?rev=<main commit>"
```

If SSH itself is gone, use the provider console (Hetzner for cinnabar and magnetite, GCP for galena and scheelite).

## pyrite over iroh

pyrite runs a `p2p-ssh-iroh` listener (clan instance `iroh`, `modules/clan/inventory/services/p2p-ssh-iroh.nix`) that forwards iroh connections to its sshd.
iroh punches through address-translating routers itself and falls back to its relays, so it does not depend on the mesh.
The client is the `clan` CLI on stibnite; nothing is installed for it on stibnite beyond the CLI, which fetches `dumbpipe` through nix.

pyrite keeps `deploy.targetHost` on the mesh in the inventory, and `clan ssh` always prefers an inventory target over every network, so a plain `clan ssh pyrite` never uses iroh.
`clan ssh` has no option to choose a network, so the break-glass session passes the iroh tunnel as the SSH `ProxyCommand`, from a vanixiets checkout on stibnite:

```bash
ticket="$(clan vars get pyrite p2p-ssh-iroh-iroh/ticket)"
dumbpipe="$(nix build --no-link --print-out-paths nixpkgs#dumbpipe)/bin/dumbpipe"
clan ssh pyrite --ssh-option ProxyCommand "$dumbpipe connect $ticket"
```

With a `ProxyCommand`, SSH never resolves pyrite's mesh name, so the session works with the mesh stopped.
To deploy over the same tunnel, give the option in the target override; clan reads SSH options from the query of an `ssh://` target and passes them to `nix copy` as well:

```bash
clan machines update pyrite --target-host "ssh://root@pyrite?ProxyCommand=$dumbpipe connect $ticket" \
  --flake "git+file://$PWD?rev=<main commit>"
```

The ticket is public by design: it is a non-secret var committed to this repository, so anyone holding it reaches pyrite's sshd through iroh's relays.
SSH authentication is then the only guard, which is why iroh on pyrite requires sshd to accept keys only.
At the time of writing pyrite's sshd has `PasswordAuthentication = false` and `PermitRootLogin = "prohibit-password"`, and also `KbdInteractiveAuthentication = true` (the NixOS default) with `UsePAM = true`; PAM denies every keyboard-interactive attempt, because pyrite's `sshd` auth stack is a single `auth required pam_deny.so`, but a `sufficient` rule added to that stack later (such as a global u2f switch) would open it; evidence: `logs/cam109-evidence/7.2-iroh-prereqs-20261117-205427.log` and `docs/notes/development/hardware/pyrite-fido2-login-design.md`.
The listener is not deployed until `KbdInteractiveAuthentication = false` is in force on pyrite, which removes that path.
The alternative is to keep the ticket secret: set `clan.core.vars.generators.p2p-ssh-iroh-iroh.files.ticket.secret = lib.mkForce true` in pyrite's configuration and regenerate the generator, so the ticket is stored encrypted for the admins and `clan vars get` decrypts it on stibnite; the commands above are unchanged.

Whether iroh stays is decided by evidence: `clan ssh pyrite` over it succeeding with `tincr-vanixiets` stopped on pyrite and pyrite behind an address-translating router.

## Macs: the person at the machine

iroh has no darwin module, and the Macs of other people have no second transport, so their recovery path is a person at the machine undoing the last change and then telling the operator.
A nix-darwin deploy that breaks the mesh, or anything else, is undone by switching back to the previous generation, which is the configuration the Mac ran before that deploy.

The steps need an administrator password on that Mac.
The nix-darwin administrator account is named per Mac below; if the person's own account is an administrator, their own password works too.

### Steps on any of these Macs

1. Log in and open Terminal (Spotlight: press Command and Space, type `Terminal`, press Return).
2. List the generations, to see which one is current:

   ```bash
   sudo darwin-rebuild --list-generations
   ```

3. Switch back to the previous generation:

   ```bash
   sudo darwin-rebuild --rollback
   ```

   If `darwin-rebuild` is not found, the broken generation has lost it; run the previous generation's own activation instead, where `<N>` is the number listed just before the one marked `(current)` in step 2's list:

   ```bash
   sudo /nix/var/nix/profiles/system-<N>-link/activate
   ```

4. Restart the Mac (Apple menu, Restart).
5. Report to the operator: the Mac's name, the generation numbers from step 2, and whether the Mac works again (internet, and the operator can reach it).

### argentum

The person at the machine is christophersmith; the nix-darwin administrator account is `cameron`.
Follow the steps above to boot the previous generation of argentum, then report.

### rosegold

The person at the machine is janettesmith; the nix-darwin administrator account is `cameron`.
Follow the steps above to boot the previous generation of rosegold, then report.

### stibnite

The operator is the person at the machine (account `crs58`) and follows the same steps to boot the previous generation.

## pixel11

pixel11 joins the mesh through tincapp, which keeps its own copy of the mesh's host files in `hosts/` of its network directory.
tincapp is a C tinc client: it asks for an unknown member's key with `REQ_PUBKEY`, which tincr refuses (`REQ_PUBKEY/ANS_PUBKEY unsupported - provision hosts/<name> with Ed25519PublicKey` in the member's journal), so the phone reaches only the members whose files it holds.
After the join it holds only cinnabar's file and its own.

To give the phone every member:

1. Build the phone's files with `nix build .#tincapp-network-pixel11`.
2. Copy them into tincapp's network directory through tincapp's "Edit configuration", using Android's Files app; Termux cannot write there, because Android gives each app private storage.
3. Check that `hosts/` lists a file for every member, not only cinnabar and the phone.
4. Disconnect and reconnect the network in tincapp.

Repeat the copy whenever a member is added or rekeyed.

`network.conf` routes `2000::/128` into the VPN only to satisfy Android's address-family check: Android's resolver asks for AAAA records only if a socket to `2000::` gets a source address, and every mesh name has only an AAAA record, so without the route Java apps such as ntfy cannot resolve mesh names on an IPv4-only network.
The route can go once the mesh has IPv4 addresses or the phones move to headscale.

Android runs one VPN at a time, and connecting tincapp disconnects the ZeroTier app.
While ZeroTier still runs, reconnecting the ZeroTier app restores the phone's `.zt` names and drops the mesh.
