---
title: pyrite FIDO2 login design (deferred)
status: working-note
decision: deferred
---

# pyrite FIDO2 login design (deferred)

## Scope and provenance

This note records a design for replacing pyrite's typed login password with a FIDO2 touch via `pam_u2f`.
The design is deferred.
Nothing in it is implemented: no `security.pam` option is set on any NixOS host in this repository, no credential is registered, no token was touched, and no deploy was run.
The operator will resurrect this by referring to "FIDO2 login".

The design is not bound to an OpenSpec change or a Linear story.
It arose alongside the pyrite bare-metal install work but is outside that change's scope, which covers LUKS2 plus FIDO2 disk unlock and suspend behaviour.
The FIDO2 credentials this design would create are separate from the LUKS2 keyslot enrollments and do not disturb them; see "No conflict with the disk unlock" below.

It was produced on 2026-07-30 by a four-lane investigation: three grounding lanes reading the pinned nixpkgs, pyrite's live PAM stack, and the provisioning and alternatives space, and one synthesis lane.
Every nixpkgs citation is keyed to the nixpkgs actually pinned for pyrite, `/nix/store/4i3i344ri09m4vyh1c1gda80fpq8cymh-9156j7pgzar14qf3yabphr61g3qp637r-source`, NixOS 26.11, which ships `pam_u2f` 1.4.0 from the upstream Yubico release tarball, built at `/nix/store/ijmhhh690bk1pxg6kf4ll05vfi56kszm-pam_u2f-1.4.0`.
Citations of the form `util.c:682` are into that pam_u2f 1.4.0 source; citations of the form `nixos/modules/security/pam.nix:2160-2178` are into the pinned nixpkgs; repository paths are relative to `/Users/crs58/projects/vanixiets` and their line anchors were read on 2026-07-30, so they drift with subsequent edits.

Each claim below carries the epistemic status the investigation recorded: verified against pinned source or against pyrite live, inferred, or unverified.
Do not upgrade an inference to a fact when acting on this note.

## The verified answer: replacement, not a second factor

`pam_u2f` gives genuine replacement of the password, not a second factor, and this was verified rather than assumed.

`security.pam.u2f.control` defaults to `"sufficient"` (`nixos/modules/security/pam.nix:2160-2178`), and the option's own description says "If you want to have multi factor authentication, use \"required\". If you want to use U2F device instead of regular password, use \"sufficient\"."
PAM `sufficient` means the auth stack terminates immediately with success on module success, and continues as if the module were absent on module failure.

The rule is auto-ordered ahead of the password.
It is the ninth entry of the auth rule list passed to `utils.pam.autoOrderRules`, which assigns `order = 10000 + index * 100` (`nixos/lib/utils.nix:596-604`), and rules are emitted sorted ascending by order (`nixos/modules/security/pam.nix:897-936`).
The rendered `login` stack is therefore:

| Order | Rule | Control |
|---|---|---|
| 10900 | `u2f` | sufficient |
| 11700 | `unix-early` | optional |
| 12200 | `gnome_keyring` | optional |
| 12900 | `unix` | sufficient |
| 13700 | `deny` | required |

Rule construction is at `nixos/modules/security/pam.nix:1097-1108`; `unix-early` at `:1216-1226`; `unix` at `:1314-1325`.
Verified against pyrite's real configuration by evaluation with the change applied, and the emitted first auth line of `/etc/pam.d/login` reads:

```
auth sufficient /nix/store/ijmhhh690bk1pxg6kf4ll05vfi56kszm-pam_u2f-1.4.0/lib/security/pam_u2f.so authfile=/etc/u2f-mappings cue origin=pam://pyrite pinverification=1 userverification=0 # u2f (order 10900)
```

The evaluation was `nix eval` against `nixosConfigurations.pyrite.extendModules`, with nothing built and nothing deployed.
Upstream nixpkgs ships a VM test asserting exactly this passwordless behaviour: with `control = "sufficient"`, alice logs in on tty2 by touching an emulated U2F device and is never asked for a password (`nixos/tests/pam/pam-u2f.nix:16-23` for the config, `:56-68` for the assertion; sibling test `nixos/tests/pam/pam-u2f-polkit.nix`).

Replacement is the nixpkgs default and second-factor behaviour is what would have to be opted into by setting `control = "required"`.

## The trade-off that caused the deferral

A successful token authentication at order 10900 short-circuits the auth stack before `unix-early` at 11700 and before `pam_gnome_keyring` at 12200.
`unix-early` is the optional `pam_unix` whose only job is to place the password into `PAM_AUTHTOK`; nixpkgs annotates that block with the comment that "Modules in this block require having the password set in PAM_AUTHTOK. pam_unix is marked as sufficient on NixOS which means nothing will run after it succeeds" (`nixos/modules/security/pam.nix:1184-1226`).
`security.pam.services.login.enableGnomeKeyring` evaluates to true on pyrite, and the live `/etc/pam.d/login` carries both the auth-stage `pam_gnome_keyring.so` at order 12200 and the session-stage `auto_start` at order 12600.

The consequence is that the GNOME login keyring will no longer auto-unlock on a token login.
The keyring's password is the login password, so the first time anything in the session touches libsecret — NetworkManager, a browser, seahorse — the operator is prompted for the exact long password the change set out to stop typing.
The session-stage `auto_start` module still runs but has no password to work with.
This is inferred from the rendered ordering plus standard PAM `sufficient` semantics; it was not observed on a running token login, because that requires a deploy and a touch.

How often the prompt would actually fire is unquantified and is the single input that most affects whether the change is worth doing.
It may never fire on a stock GNOME desktop with system-scoped NetworkManager connections, or it may fire daily.
There is no clean fix: `control = "required"` restores the keyring, because `pam_unix` still runs and still caches the password, but that reverts the design to two-factor authentication rather than password replacement.

## What this actually replaces

Without `pinverification=1` the login is possession-only: anyone holding the machine with a registered key seated is in.
pyrite's lid handler is `HandleLidSwitch = "lock"` and `HandleLidSwitchExternalPower = "lock"` (`modules/machines/nixos/pyrite/default.nix:167-171`), so in the carry-the-laptop case the boundary is the lock screen rather than a powered-off encrypted disk.

With `pinverification=1`, the honest description of the change is that it replaces a six-word password with a short PIN plus a touch — the same client PIN the same tokens already take at the LUKS unlock.
That is an ergonomic improvement and a security improvement over possession-only, and it is not zero-input.

## Three settings that would break this

`nouserok` makes authentication succeed when the authfile is missing or has no line for the user (`man/pam_u2f.8`, and in code `util.c:697-702` returns `PAM_IGNORE` on `ENOENT` when it is set).
Combined with `sufficient` that is an unauthenticated login rather than a lockout guard.
The upstream man page ties it to the CVE-2020-24612 discussion in its SELinux NOTES section.
The default already gives password fallthrough, so setting it buys nothing and loses the security property.
Never set it.

`alwaysok` forces every authentication to succeed (`pam-u2f.c:315-318`: `if (cfg->alwaysok && retval != PAM_SUCCESS) retval = PAM_SUCCESS`).
It is a presentation and demo mode.
Never set it.

`userverification=1` is on-authenticator user verification — biometrics — and not the client PIN.
The operator's tokens report `CLIENTPIN` and `UP` supported and `UV`/`ALWAYSUV` unsupported.
`match_device_opts` queries the CBOR info options and returns 0, meaning skip, when `opts->uv == FIDO_OPT_TRUE && uv != 1` (`util.c:938-956`, with `get_device_opts` at `:904-934` and the skip site at `:1232-1238`).
It skips such an authenticator rather than falling back, so with every authenticator skipped the module fails and every login would fail.
The PIN knob is `pinverification=1`.

Omitting the three verification knobs is not the same as setting them to 0: `cfg_reset` initialises `userpresence`, `userverification` and `pinverification` to -1 (`cfg.c:240-245`), which `parse_opts` maps to `FIDO_OPT_OMIT`, deferring to the authenticator's own behaviour (`util.c:879-903`).
Upstream's documented passwordless recipe is `cue pinverification=1 userverification=0`, and that is what this design recommends.

## Why the rule is scoped to `login`

`security.pam.services.login.u2f.enable = true` is the recommended form, not the global `security.pam.u2f.enable = true`.
Two reasons, both verified.

The greeter and the lock screen both route through `login`.
`/etc/pam.d/gdm-password` on pyrite consists solely of `auth substack login`, and `gdm-password` is declared with `useDefaultRules = false` (`nixos/modules/services/display-managers/gdm.nix:493-522`), which makes `security.pam.services.gdm-password.u2f.enable` a silent no-op.
The operator's live graphical session reports `Service=gdm-password` from `loginctl show-session`, and the GNOME lock screen reauthenticates through the same service — there is no `gnome-screensaver` PAM file on the machine, and `libshell` exports `open_reauthentication_channel` with `gdm-password` among its embedded strings.
So `login` is the single policy point for the greeter, the GNOME lock screen, and TTY login alike.
The greeter and TTY parts are verified; the lock-screen routing is inferred from strong circumstantial evidence rather than read from gnome-shell source.

The global switch inserts the rule into every PAM service that does not opt out, and two of those are hazards.
`sshd`'s auth stack today is a single `auth required pam_deny.so` at order 12500, with `UsePAM yes`, `PasswordAuthentication no`, and `KbdInteractiveAuthentication yes` (read from live `sshd -T` and `/etc/pam.d/sshd`).
Under the global switch it becomes `10900 sufficient u2f` then `12500 required deny`, converting remote keyboard-interactive from unconditionally refused into succeeds-on-a-touch of the token physically seated in the machine.
`passwd` likewise gains `10900 sufficient u2f` ahead of `11700 sufficient unix`, letting a touch substitute for knowledge of the current password when changing it.
The surgical form was verified by evaluation to leave `sshd` at bare `pam_deny` and `sudo` untouched.
If the global form were taken anyway, it would need `security.pam.services.sshd.u2f.enable = lib.mkForce false` and the same for `passwd`.

`sudo` is deliberately not a target.
pyrite's sudoers is `%wheel ALL=(ALL:ALL) NOPASSWD:SETENV: ALL`, from `security.sudo.wheelNeedsPassword = false` set fleet-wide at `modules/system/admins.nix:34`, and `sudo -n true` succeeds.
Adding FIDO2 to `sudo` changes nothing the operator experiences.
`polkit-1` — the GNOME "Authentication required" dialog — is the password prompt that actually survives in a GNOME session and is the real optional second target.

Note that `security.pam.u2f.settings` is global regardless of scoping: the rule construction site reads `enable` and `control` per-service but `inherit (u2f) settings` from the global attrset (`nixos/modules/security/pam.nix:1097-1108`).
One settings block therefore serves whichever services are enabled, and setting it while no service is enabled is inert.
That is what makes the phase split below possible.

## The recommended configuration

All placement is in `modules/machines/nixos/pyrite/default.nix`, inside `flake.modules.nixos."machines/nixos/pyrite"`, whose module body opens at line 20.
Nothing in this repository currently sets any `security.pam` option on a NixOS host — the only existing uses are the four darwin `sudo_local.touchIdAuth` lines — so this is net-new configuration with no existing site to extend.

Phase A is tooling only: zero PAM change, zero risk.
Edit the existing list at lines 315-320:

```nix
      environment.systemPackages = with pkgs; [
        cryptsetup
        gptfdisk
        age
        libfido2
        # pam_u2f supplies pamu2fcfg. It is auto-installed only under the
        # global security.pam.u2f.enable (pinned nixpkgs
        # nixos/modules/security/pam.nix:2610), which this host deliberately
        # does not use, so it is listed explicitly.
        pam_u2f
      ];
```

Phase B is the credential mapping, still with no PAM rule.
Insert after line 304, the `services.desktopManager.gnome.enable = true;` line:

```nix
      clan.core.vars.generators.u2f-mappings = {
        prompts.mappings = {
          description = ''
            pam_u2f mapping for cameron, on ONE line: the output of
            `pamu2fcfg -u cameron -o pam://pyrite -N` for the first key,
            concatenated with `pamu2fcfg -o pam://pyrite -N -n` for the second.
          '';
          type = "line";
        };
        files."mappings" = { };
        runtimeInputs = [ pkgs.coreutils ];
        script = ''
          printf '%s\n' "$(cat "$prompts"/mappings)" > "$out"/mappings
        '';
      };
```

`files."mappings"` takes the clan default `secret = true`, so this lands at `/run/secrets/vars/u2f-mappings/mappings` with owner root, group root, mode 0400 (clan-core `modules/clan/export-modules/generic-generator.nix:149-174`).
That satisfies pam_u2f's hard ownership check — the authfile must be a regular file owned by the authenticating user or root (`util.c:740-757`) — and is well inside the 0644-or-tighter mode it wants (`util.c:715-731`).
Registration cannot be automated inside a clan generator, because the generator script runs in a sandbox on the invoking host without the token, which is why the generator carries an operator prompt.

Phase C is the PAM rule, inserted alongside the generator:

```nix
      # A FIDO2 touch replaces the password rather than adding a factor:
      # control defaults to "sufficient" (pinned nixpkgs
      # nixos/modules/security/pam.nix:2160-2178) and the rule auto-orders to
      # 10900, ahead of pam_unix at 12900, so success ends the auth stack and
      # every failure falls through to the password.
      #
      # Scoped to `login` rather than the global switch for two reasons.
      # gdm-password is declared useDefaultRules = false with `auth substack
      # login` (nixos/modules/services/display-managers/gdm.nix:493-522), so
      # `login` is the single policy point for the greeter, the GNOME lock
      # screen and TTY login alike, and enabling gdm-password directly would be
      # inert. The global switch would additionally insert the rule ahead of
      # sshd's bare pam_deny, which with UsePAM + KbdInteractiveAuthentication
      # would let a remote attempt drive the token seated in this machine.
      #
      # settings.nouserok is deliberately absent: it makes auth succeed when
      # the mapping file is missing, which under `sufficient` is an
      # unauthenticated login rather than a lockout guard.
      security.pam.services.login.u2f.enable = true;
      security.pam.u2f.settings = {
        authfile = config.clan.core.vars.generators.u2f-mappings.files."mappings".path;
        origin = "pam://pyrite";
        cue = true;
        pinverification = 1;
        userverification = 0;
      };
```

`origin` is the FIDO2 relying-party ID.
Its default is `pam://` plus `gethostname()` (`pam-u2f.c:110-129`), which for pyrite is already `pam://pyrite` and already survives a reinstall because the hostname is declarative (`modules/machines/nixos/pyrite/default.nix:49`).
Stating it explicitly makes the binding visible and a future rename a deliberate edit rather than a silent breakage.
A fleet-wide value such as `pam://vanixiets` is not recommended: it would make one registration serve argentum, rosegold, blackphos and stibnite too, which also means one stolen token logs into all of them.

Settings render to module arguments as: boolean true becomes a bare flag, boolean false and null are omitted, everything else becomes `key=value` (`nixos/modules/security/pam.nix:121-133`).
`security.pam.u2f.settings` is a freeform submodule (`:2180-2303`, freeform type at `:2182`), so `pinverification`, `userverification`, `nouserok` and the rest of pam_u2f's arguments are settable even though only `authfile`, `appid`, `origin`, `debug`, `interactive`, `prompt`, `cue_prompt` and `cue` are declared options.

### Alternative Phase B, without a clan generator

The mapping line is public-key material: a credential ID and a COSE public key, useless without the physical token and, with `pinverification=1`, without the PIN.
Upstream calls it "much the same concept as the SSH authorized_keys file" (`README:439`), and this repository already commits SSH public keys as clear clan vars (`modules/system/initrd-networking.nix:9`, `modules/nixos/niks3.nix:53`).
So this is defensible:

```nix
      environment.etc."u2f-mappings".text = ''
        cameron:KH1,PK1,es256,+presence+pin:KH2,PK2,es256,+presence+pin
      '';
```

paired with `authfile = "/etc/u2f-mappings";`.
That resolves to a root-owned 0444 store file behind an `/etc` symlink, which pam_u2f follows — it opens the authfile without `O_NOFOLLOW` (`util.c:696`) — and which satisfies both the ownership and the mode check.

The clan-vars form is recommended regardless, not because the line is secret but because `github.com/cameronraysmith/vanixiets` is a public repository (`gh repo view` reports `"visibility":"PUBLIC"`) and committing the line publishes a username plus a stable per-token identifier.
That is a privacy call rather than a cryptographic one, and the generator costs about the same either way while keeping the decision reversible.

## Registering the credentials

Nine steps, recorded verbatim from the design.
Steps 3 and 4 require a token touch; every other step is marked as touch-free.

1. Prerequisite, on the Mac in `/Users/crs58/projects/vanixiets`: land Phase A only and deploy it. No PAM change is involved. No touch.
2. On pyrite, verify the tool arrived: `command -v pamu2fcfg`. It is absent today (checked). No touch.
3. On pyrite, from a logged-in local seat session (the `/dev/hidraw` nodes carry a logind uaccess ACL for the seated user; over ssh use sudo). Seat only key 1, remove key 2. Run `pamu2fcfg -u cameron -o pam://pyrite -N > /tmp/u2f-line`. **Touch required** — this is a FIDO2 makeCredential; the token will blink and must be touched, and because of `-N` it will also prompt for the client PIN.
4. On pyrite, remove key 1 and seat only key 2. Run `pamu2fcfg -o pam://pyrite -N -n >> /tmp/u2f-line`. **Touch required** — same makeCredential, same PIN prompt. The `-n` flag prints only the credential fields for appending, without a username.
5. On pyrite, terminate the line: `echo >> /tmp/u2f-line`. `pamu2fcfg` emits no trailing newline (`pamu2fcfg.c:291-303`), which is what makes the two outputs concatenate onto one line. No touch.
6. On pyrite, verify the file before it goes anywhere near PAM: `wc -l /tmp/u2f-line` must print 1, and `cat /tmp/u2f-line` must show a single line beginning `cameron:` with two colon-separated credential groups after the username. If the second chunk did not begin with a literal `:`, insert one. No touch.
7. On the Mac, in `/Users/crs58/projects/vanixiets` after landing Phase B: `clan vars generate pyrite --generator u2f-mappings` and paste the line at the prompt. The `--generator, -g` flag is documented in `clan vars generate --help`. Transfer the line from pyrite by reading it over the existing ssh session. No touch.
8. On pyrite after deploying Phase B: confirm delivery and permissions without enabling anything — `sudo stat -c '%U %G %a %n' /run/secrets/vars/u2f-mappings/mappings` should report `root root 400`, and `sudo wc -l` on it should still print 1. No touch.
9. On pyrite, clean up: `shred -u /tmp/u2f-line`, or simply `rm`; the line is not secret, but leaving stray copies around is untidy. No touch.

Step 6 is load-bearing rather than hygiene.
The parser resets its device list on each line matching a user and keeps only the last one — `util.c:230-247`, whose own comment reads "only keep last line for this user".
A two-line file therefore silently yields one working key, with no error at deploy time and no error at login time, and the operator would discover it only when the other key failed.
Multiple credentials per user are supported up to `MAX_DEVS`, which is 24 (`util.h:14`), and `do_authentication` loops over each registered credential against every inserted authenticator (`util.c:1210`), but all of them must be on one line.

Resident (discoverable) credentials, `pamu2fcfg -r`, do not help and are not recommended.
pam_u2f always parses the authfile to enumerate a user's devices and read the public key — the read at `util.c:696-770` is unconditional, and resident merely skips the allow-cred call at `util.c:1013-1027`.
They consume a token slot, and because `pamu2fcfg` generates a fresh random FIDO user id on every run (`pamu2fcfg.c:143`), re-registration accumulates slots rather than replacing them, needing `fido2-token -D -i <cred_id>` to clean up.

## Lockout safety

The structural fallback is the mechanism itself.
`control = "sufficient"` means pam_u2f can only add a way in; it cannot take one away.
Every failure mode — both tokens lost, PIN forgotten, sops decryption failed, authfile missing or malformed or mis-owned, wrong origin, unregistered user — is a module failure, and a `sufficient` module failure is non-fatal, so PAM continues to `pam_unix` at order 12900 and the clan-vars password still works.
In code, a missing authfile returns `PAM_AUTHINFO_UNAVAIL` (`util.c:682`, `:696-702`) and a user absent from the file returns `PAM_USER_UNKNOWN` (`util.c:787`), both non-granting and both non-fatal here.
The ordering was confirmed by rendering pyrite's actual login stack rather than by reading documentation.

The one setting that would break this property is `nouserok`.
It is off by default and must stay off.

Three independent recovery layers sit behind that, and each must be verified before the Phase C deploy rather than after.

The change requires no reboot.
`clan machines update` runs `nixos-rebuild switch`, and PAM configuration is read at the next authentication, so it takes effect live.
The failure mode that matters most on this machine — dropping off the network after a reboot — is not triggered by this change at all, provided no reboot is performed as part of it.
Do not reboot during the rollout.

SSH publickey authentication does not consult the PAM auth stack.
This is directly observable rather than assumed: pyrite's `/etc/pam.d/sshd` auth section is a single `auth required pam_deny.so`, `PasswordAuthentication no`, and the investigation authenticated over it repeatedly.
Even a completely broken auth stack therefore leaves remote root access intact.
Note that the account and session stacks do run under pubkey auth, so breaking those would still bite.
Verify before Phase C by opening a second ssh session and leaving it open for the duration, confirming rollback availability there with `sudo nix-env --list-generations -p /nix/var/nix/profiles/system | tail -3`, and writing down the exact rollback command, which needs neither flake nor network: `sudo /nix/var/nix/profiles/system-<N>-link/bin/switch-to-configuration switch`.
Read the generation number out; do not assume it.

The physical layer: before Phase C, switch to tty3, log in with the password, run `sudo -i`, and leave that root shell open across the deploy.
Verify it works before deploying, not after.
This is the layer that survives even a total loss of ZeroTier.

Behind all three is the systemd-boot previous generation at the console, which requires the LUKS unlock — either FIDO2 or the keyslot-0 clan-vars passphrase — and is therefore a genuine last resort rather than a convenient one.
Confirm the keyslot-0 recovery passphrase is to hand before starting.
`boot.initrd.systemd.emergencyAccess` from the clan emergency-access service is initrd-only; it is not a stage-2 login recovery path and will not help here.

One shared blast radius is worth knowing before relying on the PIN.
Recovering a forgotten FIDO2 PIN requires `fido2-token -R`, a factory reset.
The investigation is fairly confident from CTAP 2.1 semantics that this invalidates existing credentials and would therefore take out the LUKS2 keyslot-1 and keyslot-2 enrollments alongside the pam_u2f registrations, but the local `fido2-token(1)` man page does not say so.
Treat it as inferred, not verified.

## No conflict with the disk unlock

pam_u2f and the LUKS unlock use different relying parties, so a pam_u2f enrollment creates a separate, independent credential and neither reuses nor disturbs the existing keyslots.
`cryptsetup luksDump /dev/nvme0n1p2` shows tokens `0: systemd-fido2 Keyslot: 1` and `1: systemd-fido2 Keyslot: 2`; systemd's relying party string is `io.systemd.cryptsetup`, confirmed in the pinned systemd store path; pam_u2f's origin and appid default to `pam://pyrite` (`pam-u2f.c:110-129`, `:133-136`).

The upstream encrypted-home caveat does not apply.
`/home` is the ZFS dataset `zroot/root/home` under the LUKS root, already decrypted at stage 1 long before login, so a mapping file would not be unreadable at authentication time; a central `/etc` or `/run` authfile is still preferred for declarativeness.

There is no pre-existing per-user u2f state to migrate: `/home/cameron/.config/Yubico` does not exist, no `pam_u2f` store path is on the machine, and `pamu2fcfg` is absent from `PATH`.

## Rollout order

Eight steps, recorded verbatim from the design.

STEP 0 — establish and verify all three fallback layers before touching the repository.
Open a second ssh session to pyrite and leave it open.
On the physical console, switch to tty3, log in with the password, run `sudo -i`, and leave that root shell open.
In the ssh session, record the current system generation number from `sudo nix-env --list-generations -p /nix/var/nix/profiles/system | tail -3` and write down the literal rollback command `sudo /nix/var/nix/profiles/system-<N>-link/bin/switch-to-configuration switch`.
Confirm the keyslot-0 LUKS recovery passphrase is available.
Do not proceed until all four are verified working, not merely assumed.

STEP 1 — deploy Phase A alone.
No PAM configuration changes; the risk is zero.
Verify before proceeding: `command -v pamu2fcfg` on pyrite returns a path, and `/etc/pam.d/login` still contains no pam_u2f line.
Do not reboot.

STEP 2 — operator registration, both keys, per the registration steps above.
Two token touches.
Verify before proceeding: `/tmp/u2f-line` is exactly one line, begins `cameron:`, and contains two colon-separated credential groups.
A two-line file will silently give one working key.

STEP 3 — deploy Phase B, the clan vars generator and `security.pam.u2f.settings`, without the enable.
The settings block is inert while no service enables u2f, so this deploy still cannot change any authentication outcome.
Verify before proceeding: `sudo stat -c '%U %G %a' /run/secrets/vars/u2f-mappings/mappings` reports `root root 400`, `sudo wc -l` on it prints 1, and `/etc/pam.d/login` still contains no pam_u2f line.
Do not reboot.

STEP 4 — prove the module end to end on a service that cannot lock the operator out.
Deploy `security.pam.services.su.u2f.enable = true;` alone.
From the existing ssh session run `su - cameron`.
This exercises pam_u2f, the authfile, the origin, the PIN, and each key, with zero exposure to the greeter and zero lockout risk, because a failed `su` just falls through to the password prompt.
Verify before proceeding: with key 1 alone seated, `su - cameron` prompts for the PIN and a touch and succeeds without asking for the password; repeat with key 2 alone seated; repeat with no key seated and confirm the normal password prompt appears.
All three must pass.
If any fails, fix it here — this is the cheap place to be wrong.

STEP 5 — deploy Phase C, `security.pam.services.login.u2f.enable = true;`, keeping or dropping the `su` rule as preferred.
This is the only step with real risk, and the risk is a stalled greeter rather than a lockout: nixpkgs disables fprintd inside `login` precisely because a blocking auth module there blocks the gdm-password prompt (`gdm.nix:600-604`), and pam_u2f has no equivalent parallel-service arrangement in GDM.
Before deploying, re-confirm the second ssh session and the tty3 root shell are both still alive.
Then verify in escalating order: (a) switch to a free VT such as tty4 and log in at the getty prompt, which is the plain `login` path and what upstream's VM test exercises; (b) return to the GNOME session and lock the screen with Super+L, then unlock, since the lock screen reauthenticates through gdm-password, which substacks login; (c) log out fully and log back in at the GDM greeter.
If any stage stalls, roll back immediately from the held ssh session with the command recorded in step 0.
Do not reboot.

STEP 6 — optional: `security.pam.services.polkit-1.u2f.enable = true;`.
sudo is deliberately not a target, for the reason given under scoping.
polkit-1 is the password prompt that actually survives in a GNOME session.
Verify by triggering a GNOME "Authentication required" dialog and confirming it accepts the touch rather than hanging.
Roll back if it hangs; a hung polkit dialog is annoying but not a lockout.

STEP 7 — do not declare this done at step 5.
Run a normal day and observe how often GNOME prompts for the login keyring, since a token login no longer auto-unlocks it.
If the prompt fires often enough to negate the benefit, revisit the alternatives rather than living with a change that trades one password prompt for another.

## Alternatives considered

Do nothing and shorten the password instead.
This is the cheapest option and it deserves a hearing, but it has fleet-wide reach: `user-password-cameron` is a shared clan var (`modules/clan/inventory/services/users/cameron.nix:29-32`, `share = true`), auto-generated as a six-word xkcdpass via `xkcdpass --numwords 6` and used on all seven machines including the always-on VPS admin accounts, with per-machine hashes under `vars/shared/user-password-cameron/`.
Flipping `prompt = true` to choose a shorter one weakens every one of them and re-hashes the var everywhere.
A pyrite-specific override would be a different and larger design.

Keep the token as a genuine second factor, `security.pam.u2f.control = "required"`.
This preserves the GNOME keyring auto-unlock, because `pam_unix` still runs and still caches the password, and it is a real security improvement.
It also means typing the long password and touching the token, which is not password replacement.
Recorded so the trade is explicit.

Sidestep the keyring regression by giving the login keyring an empty password via seahorse, so gnome-keyring auto-unlocks without needing PAM to hand it anything.
On a laptop whose real boundary is LUKS2 full-disk encryption this is arguably an acceptable posture, and it removes the single biggest practical dent in this change.
It is not recommended outright for two reasons: it is exactly the imperative per-user state the nix configuration does not declare, which is the failure mode that stranded this machine after the reinstall; and it was not verified against the pinned gnome-keyring 50.0 that an empty-password login keyring auto-unlocks.
Unverified.

systemd-homed.
The module exists in the pinned nixpkgs (`nixos/modules/system/boot/systemd/homed.nix`) and homed is inactive on pyrite, but adopting it means migrating cameron's home off the plain `zroot/root/home` dataset into a homed-owned record, colliding with clan's users service which declares cameron from the shared password var (clan-core `clanServices/users/default.nix:208-214`), and duplicating encryption that LUKS2 plus FIDO2 already provides at stage 1.
Poor fit; recommended against.

Resident (discoverable) credentials.
Named only to rule out; see the reasoning under "Registering the credentials" above.
No benefit here.

## Residual uncertainties

The greeter is the real unknown and it is why step 5 is structured as it is.
Whether GDM 50's greeter renders pam_u2f's `cue` message and accepts the touch, or stalls the password field, could not be tested.
The concern is not speculative: nixpkgs sets `login.fprintAuth = false` with the comment that it "would block password prompt when included by gdm-password" (`gdm.nix:600-604`), and pam_u2f is likewise a blocking auth module inside `login` with no parallel-service arrangement in GDM.
The mitigating factor is that pam_u2f's default detect behaviour probes inserted tokens check-only and fails fast when no registered key is present, so a block should occur only while a registered token is seated, which is the wanted case.
What would settle it: step 5's tty4-then-lock-screen-then-greeter sequence with rollback held ready.

The GNOME lock-screen path is inferred rather than directly observed, on the evidence recorded under scoping above.
That is strong circumstantial evidence, not a read of gnome-shell's source.
What would settle it: step 5(b).

The gnome-shell polkit agent's handling of a pam_u2f-only conversation — a `PAM_TEXT_INFO` cue followed by a wait with no input requested — is untested.
This matters only if step 6 is taken.

The `-n` append format.
The claim that `pamu2fcfg -n` emits a leading `:` so the two outputs concatenate correctly rests on the man page ("Print only registration information... Useful for appending") and on `pamu2fcfg.c:291-303` showing the username printed only when `!nouser`.
It was not run.
Registration step 6 catches it either way.

Whether `fido2-token -R` invalidates existing credentials — and thus whether a forgotten PIN would take out the LUKS2 keyslots 1 and 2 alongside the pam_u2f registrations — is inferred from CTAP 2.1 semantics and is not stated in the local `fido2-token(1)` man page.
If that shared blast radius drives the decision, confirm it against the CTAP 2.1 `authenticatorReset` text or Yubico's documentation first.

The clan vars `neededFor` default, and hence the exact activation stage at which `/run/secrets/vars/u2f-mappings/mappings` becomes readable, was not verified.
It is immaterial to safety — a file that is not there yet produces a password prompt, not a lockout — but it could in principle mean a very early TTY login does not see the token.
Step 3's verification observes the file after activation, which is the case that matters.

The two grounding lanes reported different counts for pyrite's PAM services and for the global switch's blast radius: one recorded 28 services defined, the other 26 files in `/etc/pam.d` with 23 receiving the rule.
The discrepancy was not reconciled.
The exception set is consistent across both and is what matters: the three gdm services and `other` set `useDefaultRules = false` and receive nothing.
Re-enumerate before relying on any count.

The planned niri successor invalidates the scoping, not the registration.
This design rests on `gdm-password` being `auth substack login`, which makes `login` the single policy point.
A greetd or tuigreet successor registers its own PAM service and may not include `login`, at which point `security.pam.services.<greeter>.u2f.enable` would need adding.
The credentials, the authfile, and the origin all survive that change untouched; only the enable line moves.

Least quantified, and most decisive: how often the GNOME keyring prompt will actually fire in daily use.
That is why step 7 exists and why the change should not be called finished at step 5.

## The four options left open

The operator was offered these four and deferred rather than choosing.
They are recorded so the choice resumes where it was left.

(a) The phased rollout as designed: Phase A, then registration, then Phase B, then the `su` proving step, then Phase C on `login`, accepting the keyring cost and measuring it at step 7.

(b) The token as a second factor via `control = "required"`, which preserves the GNOME keyring auto-unlock and means typing the password and touching the token.

(c) Hold, because the keyring cost is too high relative to the benefit.

(d) Land Phase A and Phase B only — install `pam_u2f`, register both keys, provision the mapping — and enable no PAM rule, leaving the credentials in place and the decision open.

Option (d) is the one that preserves optionality: it costs two token touches and one clan var, changes no authentication outcome, and reduces the later decision to a one-line enable.
