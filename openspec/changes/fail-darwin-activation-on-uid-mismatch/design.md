## Context

Each account a person holds on a darwin host records its uid in `flake.fleet.hosts.<host>.users.<account>.uid` (`modules/lib/host-users.nix`); `modules/system/home-manager-integration.nix` applies it as `users.users.<account>.uid`. Every attached account is in `users.knownUsers` on stibnite, blackphos, argentum and rosegold, so nix-darwin's users activation manages it.

At the locked nix-darwin revision, an existing account whose uid differs from `users.users.<name>.uid` is warned about and skipped (`modules/users/default.nix:285-288`, and the permission preflight at `:197-198`); activation succeeds (A346). A wrong record therefore leaves the account unmanaged and fails nothing.

The fact to check is a relation between the recorded uid and the uid in one Mac's Directory Services. Evaluation cannot read the second value. The constraint that follows decides the design: only code running on the Mac can observe the failure.

Relevant nix-darwin behaviour (each a world assumption in this change):
- `activate` runs under `set -e` and runs `preActivation`, then `checks`, then `createRun`, `extraActivation`, `groups`, `users` and the rest (`modules/system/activation-scripts.nix:88-89,114-140`) (A370).
- `darwin-rebuild switch` sets the system profile, then runs `activate` (`pkgs/nix-tools/darwin-rebuild.sh:218-224`); clan-core deploys darwin with `darwin-rebuild switch` (`clan_lib/machines/update.py:713-725`) (A371).
- The boot-time `activate-system` daemon relinks `/run/current-system` to the profile and runs `checks`, `etc` and `keyboard`, not `preActivation` (`modules/services/activate-system/default.nix:61-70`) (A372).
- `darwin-rebuild check` must run as root (`darwin-rebuild.sh:149-152`) and runs `activate` with `checkActivation=1` exported (`darwin-rebuild.sh:230-233`), but `activate`'s `#!/usr/bin/env -i` line drops it (`modules/system/activation-scripts.nix:84`), so the exit after `checks` (`modules/system/checks.nix:320-323`) is not taken and every step runs, through linking `/run/current-system`, without setting the system profile; observed on stibnite 2026-11-27 (`logs/stibnite-darwin-rebuild-check-20261127-171145.log`, `logs/stibnite-post-activation-supplement-20261127-171547.log`) (A373).
- `id -u <name>` prints the account's uid from Directory Services and fails for an absent account; nix-darwin uses the same lookup (A374).

## Goals / Non-Goals

**Goals:**
- A Mac's activation fails, before it changes anything on the Mac, when an attached account exists with a uid other than the recorded one, naming every such account and the record to correct.
- The operator can run the same comparison on a Mac (`darwin-rebuild check`): a disagreement stops it before any step that changes the Mac; an agreement goes on to activate the new configuration without setting the system profile.
- A build check demonstrates the comparison fails on a mutant uid and passes on a match and on an absent account.

**Non-Goals:**
- An evaluation-time pin of the recorded uids against a second literal. It catches an accidental edit only, not a record that was wrong from the start, and both sides come from the same belief (check-vacuity: self-comparison). Not added.
- Accounts outside the attachments (service accounts such as `_otelcol`, `_otelagent`, `omnigent-cameron`, `nix-grpc-daemon`, build users). They belong to their services' modules.
- Changing a uid on the Mac. The check reports; the operator corrects the record or the account.
- Gids, home directories, shells.
- NixOS hosts, where clan allocates uids and the attachment's uid is null.

## Decisions

### D1: The check runs on the Mac, at activation
- **Choice**: compare on the Mac during nix-darwin activation.
- **Rationale**: only the Mac can read the account's real uid; activation is the one path every deploy takes (clan's deploy, a local `darwin-rebuild switch`, `darwin-rebuild check`).
- **Alternatives considered**: (A) evaluation-time literal pin — changes no host but cannot catch a record wrong from the start, which is the operator's failure; (E) ssh preflight recipe or deployer step — changes no toplevel but runs only when someone remembers it; clan's darwin deploy calls `darwin-rebuild switch` directly and would bypass it.
- **Boundary**: first-party module text running inside a vendored script's slot; nix-darwin is not patched.

### D2: `preActivation`, not `system.checks.text`, not a nix-darwin patch
- **Choice**: append the comparison to `system.activationScripts.preActivation.text` at order 600: after deploy-record's `mkBefore` read of `/run/current-system` (which only reads) and before nix-darwin's own `preActivation` text at the default priority, which removes a leftover `/var/lib/linux-builder` and prints the closure diff. At the default priority the comparison rendered after that removal, so a mismatch would have been reported after one change to the Mac; evaluated on stibnite, the rendered order is the read, the comparison, then the removal.
- **Rationale**: preActivation is a public option, runs first under `set -e`, before every step that changes the system, and also under `darwin-rebuild check` (A370, A373). It is not run by the boot daemon (A372), so a wrong record does not also break the boot-time `etc` relink at every boot.
- **Alternatives considered**: `system.checks.text` — internal, and also run by the boot daemon, where a failure would abort `etc` and `keyboard` at every boot; patching nix-darwin's users module to make the warning fatal — vendored-versus-first-party boundary, carried on every lock update, changes semantics for system accounts this change does not own.

### D3: What is compared, and what passes
- **Choice**: for each attachment of the host, `u=$(id -u <name> 2>/dev/null) || u=`; a non-empty `u` different from the recorded uid is a mismatch; an empty `u` (no such account) is not. Collect every mismatch, then print one line each (host, account, recorded, real, `flake.fleet.hosts.<host>.users.<account>.uid`) and `exit 1`.
- **Rationale**: an absent account is created by nix-darwin with the recorded uid, so nothing is left unmanaged. Reporting all mismatches in one run avoids one deploy per wrong record.
- **Alternatives considered**: comparing every `users.knownUsers` entry — broadens the scope to service accounts and their modules; failing on an absent account — would break first deployment of a new attachment.
- **Fail closed**: `id` printing something non-numeric is a mismatch (the `[[ … != … ]]` string comparison treats it as different), never a pass.

### D4: Generated from the attachments in the integration aspect
- **Choice**: the darwin branch of `modules/system/home-manager-integration.nix`, which already turns `attachments` into `users.users.<a>.uid`, also renders the comparison from the same attachments, and exposes the rendered text as a read-only internal option `home-manager-integration.uidPreflight` (beside the existing `home-manager-integration.attachments`) so the check reads it without re-deriving it.
- **Rationale**: one source for both the applied uid and the compared uid; the check exercises the exact text the Mac runs.
- **Alternatives considered**: a separate darwin module reading `flake.fleet.hosts` — a second reader of the attachments for the same host.

### D5: The mutant check
- **Choice**: `checks.x86_64-linux.darwin-uid-preflight`, a `runCommand` that, for each darwin host in the fleet registry, runs the host's rendered `home-manager-integration.uidPreflight` with a stub `id` first on `PATH` in three cases: every account at its recorded uid (must exit 0), every account absent (must exit 0), and one account at recorded+1 (must exit non-zero and name that account). `testSizes.checks.darwin-uid-preflight = { class = "medium"; measured = false; }`.
- **Rationale**: integrity: the check fails when the comparison is removed, inverted or made to pass absent-or-mismatch alike. Each mutant runs only the case it must fail.
- **Key set**: the attribute name is a literal; the host list is read from `flake.fleet.hosts` class metadata inside the value. Gated to x86_64-linux: the derivation is a bash script with a stub and does not differ by system.
- **Alternatives considered**: a nix-unit string assertion on the rendered text — would pass a script that renders the right words but compares wrongly.

### D6: Intended derivation change, deployed by the operator
- **Choice**: the four darwin toplevels change (their activate script gains the comparison); `darwin-uid-preflight` is added; `fleet-alert` changes because it renders every `testSizes.checks` entry. These are listed exactly in `drv-delta.txt`; `just drv-diff <parent> <commit> openspec/changes/fail-darwin-activation-on-uid-mismatch/drv-delta.txt` is the oracle and every other attribute keeps its drvPath.

## Risks / Trade-offs

- [Risk] A record is wrong today, so the first deploy after this change fails on that Mac. → Mitigation: before deploying, the operator runs `darwin-rebuild check --flake .#<host>` (`just darwin-test <host>`, as root) on each Mac; it runs the comparison at order 600, before the steps that change the Mac, so a disagreement stops it there with the Mac unchanged (A373). A failure there is the finding the change exists to produce. A passing check is itself an activation of the new configuration that does not set the system profile, so a reboot relinks `/run/current-system` to the profile's generation and runs only that generation's `checks`, `etc` and `keyboard` steps (A372).
- [Risk] The check fails after `darwin-rebuild switch` has set the system profile (A371): the profile is one generation ahead of the running system, and a reboot in that state relinks `/run/current-system` to the unactivated generation and runs its `etc` (A372). → Mitigation: this is nix-darwin's existing behaviour for any failed activation, not new to this change; the runbook says to correct the record and redeploy, or `darwin-rebuild --rollback`, before rebooting.
- [Risk] Blast radius: a mismatch blocks every activation on that Mac (clan deploy, local switch, check) until corrected; other hosts are unaffected. → Accepted: blocking is the point; the message names the record to fix.
- [Trade-off] The check runs as root at every activation, one `id` call per attached account (at most two). → Negligible.
- [Risk] `id` resolves a network directory account instead of the local one. → All attached accounts are local; A374 names the assumption.

## Migration Plan

1. Land the change (one commit); `just drv-diff` against `drv-delta.txt` confirms only the declared attributes move.
2. On each Mac (stibnite, blackphos, argentum, rosegold), the operator runs `sudo darwin-rebuild check --flake .#<host>`: it exits 0 with no `unexpected uid` line, having run the whole activation without setting the system profile (no `ok` line is printed, A373), or stops naming the mismatch before any step that changes the Mac; any mismatch is fixed in `modules/lib/host-users.nix` first.
3. The operator deploys each Mac. Each host's behaviour changes when it is deployed, or earlier when its `darwin-rebuild check` passes, which activates the new configuration without setting the system profile.
4. Rollback: revert the commit and redeploy, or `darwin-rebuild --rollback` on a Mac.

## Open Questions

- None blocking. Whether to extend the comparison to service accounts' uids is a separate decision for their owning modules.
