<!--
Raw capture of superpowers:brainstorming output.
-->

# Brainstorm: catch a wrong darwin uid in a host's user attachments

## Background

`flake.fleet.hosts.<host>.users.<account>.uid` (`modules/lib/host-users.nix`) records the uid of each account a person holds on a darwin host. `modules/system/home-manager-integration.nix` applies it as `users.users.<account>.uid`. Every attached account is in `users.knownUsers` on all four Macs (stibnite: crs58; blackphos: crs58, raquel; argentum: christophersmith, cameron; rosegold: janettesmith, cameron; read from each host's evaluated `users.knownUsers`), so nix-darwin's users activation manages each one.

When the recorded uid differs from the uid the existing account has, nix-darwin does not fail. Its users activation (`modules/users/default.nix:285-288` at the locked revision) prints `warning: existing user '<name>' has unexpected uid <u>, skipping...` and carries on; the permission preflight at `:197-198` skips the account the same way. A wrong record therefore leaves the account unmanaged (no home, shell, description or key changes applied by nix-darwin's users step) while the deploy reports success. The prior change that introduced the attachment records stated this as world assumption A346.

The operator wants a check that catches a wrong darwin uid.

## Q1: What can be checked at all?

The fact in question is a relation between two values: the uid recorded in the repository and the uid the account really has on one Mac. The second value lives in that Mac's Directory Services. Nix evaluation is pure and runs on whatever host evaluates the flake, usually not the Mac, so no evaluation-time or build-time check can read it.

What evaluation can do is compare the recorded uids against an independent literal kept somewhere else in the repository. That catches an accidental later edit of a record (a typo while editing the attachments), but not a record that was wrong from the start, because the literal would have been copied from the same wrong belief. The operator's failure is the second kind: a record that never matched the account. In the check-vacuity terms of the nix-checks skill, a second literal is close to self-comparison: both sides come from the operator's belief, not from the Mac, so the check cannot fail under the incorrect implementation it is meant to catch.

Only something running on the Mac, as root or as any user, can read the real uid (`id -u <name>`, the same lookup nix-darwin uses at `:285`).

Decision: the check has to run on the Mac. An evaluation-only check is not a sound answer to the operator's question and is not proposed as one.

## Q2: Where on the Mac?

Candidates:

A. **Evaluation-time pin** (rejected by Q1): a nix-unit or structure check that pins every recorded uid to a literal table. Changes no host. Catches an accidental edit only.

B. **`system.checks.text` snippet.** nix-darwin's `activate` runs `preActivation`, then `checks`, then `createRun`, `groups`, `users`, ... under `set -e` (`modules/system/activation-scripts.nix:88-89,114-120`). A non-zero exit in checks stops activation before anything is changed. But `system.checks.text` is an internal option, and the boot-time `activate-system` launchd daemon also runs `checks` (`modules/services/activate-system/default.nix:61-70`), after relinking `/run/current-system` to the system profile; a failing uid check would then abort the boot daemon's `etc` and `keyboard` steps at every boot.

C. **`system.activationScripts.preActivation` snippet.** A public option. Runs at the very start of `activate`, before nix-darwin's checks and before every step that changes the system; under the same `set -e`. Not run by the boot daemon. Also run by `darwin-rebuild check` (`pkgs/nix-tools/darwin-rebuild.sh:230-233` sets `checkActivation=1`; `activate` runs preActivation and checks, then exits 0 at `modules/system/checks.nix:320-323`), so the operator can preflight a Mac without changing it. The fleet's deploy-record already places a read of `/run/current-system` first in preActivation with `mkBefore` (`modules/system/deploy-record.nix:207-211`); that read changes nothing, and the uid check goes after it at default priority.
Correction (2026-11-27): `activate`'s `#!/usr/bin/env -i` line (`modules/system/activation-scripts.nix:84`) drops `checkActivation`, so `darwin-rebuild check` does not exit after `checks`: a disagreement stops at the comparison before any step that changes the Mac, and an agreement runs the whole activation without setting the profile (observed on stibnite, `logs/stibnite-darwin-rebuild-check-20261127-171145.log`; A373).

D. **Make nix-darwin's warning fatal** by patching or overriding the vendored users module. Vendored-versus-first-party boundary: a patch to nix-darwin is carried on every lock update and changes semantics for every account, including system accounts this change does not own. Rejected.

E. **Out-of-band preflight over ssh** (a `just` recipe or deployer step that evaluates the recorded uids and runs `ssh <host> id -u <name>` before deploying). Changes no toplevel. But it runs only when someone runs it: `clan machines update` on darwin calls `darwin-rebuild switch` directly (clan-core `clan_lib/machines/update.py:713-725`), and the operator also deploys locally with `darwin-rebuild switch`. Neither path would run it. It is an effect, not a flake check. It could have caught the failure only if remembered.

Decision: C. It is the only option that runs on every activation path into the Mac (deploy by clan, local switch, `darwin-rebuild check`) and fails instead of warning.

## Q3: What exactly does the check compare?

For each account attached to the host (the attachments, not every `users.knownUsers` entry: system accounts such as `_otelcol` belong to their services and are out of scope):
- `id -u <name>` succeeds and prints the recorded uid: pass.
- `id -u <name>` fails (no such account): pass. nix-darwin's users step creates the account with the recorded uid; nothing is unmanaged.
- `id -u <name>` prints another uid: mismatch.

All attachments are checked before failing, so one run names every mismatch on the host. On any mismatch, print one line per account (host, account, recorded uid, real uid, and the record's option path `flake.fleet.hosts.<host>.users.<account>.uid`) and exit non-zero.

## Q4: Blast radius

- A mismatch stops every activation on that Mac (deploy, local switch, `darwin-rebuild check`) until the record or the account is corrected. Nothing else on the fleet is affected; each Mac judges only its own attachments.
- The check runs before activation changes anything on the Mac. It does not run before `darwin-rebuild switch` sets the system profile: `darwin-rebuild` sets `/nix/var/nix/profiles/system` to the new generation and only then runs `activate` (`darwin-rebuild.sh:218-224`). After a failed switch the profile is one generation ahead of the running system. A reboot in that state runs the boot daemon, which links `/run/current-system` to that profile and runs its checks and etc (but not preActivation). This is nix-darwin's existing behaviour for any failed activation (for example its own wrong-home-directory abort in the users step), not something this check introduces. Remedy: correct the record and redeploy, or `darwin-rebuild --rollback`.
- Today's records are believed correct (the Macs have been deploying with them). If one is wrong, the first deploy after this change fails on that Mac; that is the purpose. To learn it before the deploy, the operator runs `darwin-rebuild check --flake .#<host>` (`just darwin-test <host>`) on each Mac after the change lands; it changes nothing.
  Correction (2026-11-27): `darwin-rebuild check` needs root and changes the Mac when the comparison passes: it runs the whole activation without setting the system profile; only a disagreement stops it before any change (A373).

## Q5: Is this an intended derivation change?

Yes. The four darwin toplevels gain a preActivation snippet, so their drvPaths change and the change needs a deploy the operator performs on each Mac. NixOS hosts and every home are unchanged. Per the operator's instruction, this change is planned only; implementation waits for approval.

## Q6: How is the check itself shown to fail?

A medium build check runs each Mac's rendered snippet with a stub `id` on `PATH`: the recorded uid (pass), no account (pass), and a mutant uid one higher for one account (must fail, naming the account). The key set reads only the fleet registry's darwin host names (static data); the snippet text is read in the value. Gated to `x86_64-linux`: the derivation runs a bash snippet with a stub and does not differ by system.

## Agreed approach

Option C, with the stub-`id` mutant check, planned now and implemented after the operator approves the derivation change and the four-Mac deploy.
