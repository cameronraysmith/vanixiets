---
title: Darwin build access
description: How the fleet reaches its aarch64-darwin stores, and why the remote builder and the remote store are two mechanisms rather than one
sidebar:
  order: 9
---

Nix evaluation is portable and nix building is not.
Magnetite, which carries both CI services, is x86_64-linux, so it can evaluate an aarch64-darwin derivation and cannot build one.
Remote building is declared once for the whole fleet by the `nix-builders` clan service (`modules/clan/services/nix-builders/`, instance in `modules/clan/inventory/services/nix-builders.nix`), which gives each machine a `builder` role, a `dispatcher` role, or both.
Stibnite is the primary aarch64-darwin builder, and rosegold and argentum are opportunistic ones: laptops that take darwin work when they are awake and on the mesh.
No dispatcher sends work to rosegold or argentum yet; their builder side is in place, and each dispatcher excludes them.
Before that service, only stibnite was declared as a darwin build target, and before `stibnite-access.nix` nothing was, which left darwin derivations without a build target at all rather than with a slow one.

## Two mechanisms, two callers

The two ways to reach another machine's store are not interchangeable, and treating one as a synonym for the other is the mistake this page exists to prevent.

A remote builder is `nix.buildMachines` on the caller, or `--builders` on one invocation.
The caller's nix daemon copies the input closure out to the builder, builds there, and copies the output closure back, so the result exists in the *caller's* store.
That is what a caller wants when the verdict is wanted locally: a CI service that will sign the output and push it to the binary cache, or an operator on magnetite who feeds the result to a later local step.

A remote store build is `--store ssh-ng://…`, or `--eval-store` for the mirror-image split.
Evaluation stays with the caller and the entire build happens inside the builder's store: the derivation and its source inputs are copied there, while the output closure is not copied back.
That is what a caller wants when its own store is empty and stays empty — an ephemeral CI runner, a fresh container, an installer image — where a remote builder would spend the job populating a store that is about to be discarded.
Nothing lands locally, so a caller that needs the output path locally wants the builder instead.

| | Remote builder | Remote store |
|---|---|---|
| Configured as | `services.nix-builders.buildMachines`, spliced into `nix.buildMachines` | `/etc/nix/<builder>-store-uri` on each dispatcher, one per builder it uses |
| Evaluation | caller | caller |
| Build | the builder | the builder |
| Output closure | copied back to the caller | stays in the builder's store |
| Intended caller | nixbot building `checks.aarch64-darwin`, or a developer or operator who needs an aarch64-darwin result locally, such as building or testing Darwin configurations from magnetite | a machine whose store is empty and stays empty |

Both mechanisms speak `ssh-ng` to the same account through the same ssh alias, which is what the `nix-builders-wiring` check pins.
Legacy `ssh://`, which would run `nix-store --serve` on the far side, is deliberately not served.

## Who dispatches to whom

Stibnite dispatches to magnetite and pyrite, for native x86_64-linux work and x86_64-linux kvm work respectively, and does not dispatch to rosegold or argentum.
Magnetite dispatches aarch64-darwin work, nixbot's included, to stibnite only, with `builders-use-substitutes` so a builder fetches from the shared binary cache what it can rather than receiving it over ZeroTier, and does not dispatch to pyrite.
Magnetite excludes rosegold and argentum until the binary cache holds nixbot's darwin outputs; re-admitting one means deleting its name from magnetite's `exclude` in `modules/clan/inventory/services/nix-builders.nix` and redeploying magnetite.
Every builder authorizes every dispatcher's key, so an exclusion decides only where a dispatcher sends work, not who may connect.

On every builder, darwin included, the forced command is `nix-daemon --stdio` directly.
A darwin laptop accepts dispatched builds on battery or AC.
Darwin builders also run the nix daemon with `nix.daemonProcessType = "Background"` and `nix.daemonIOLowPriority = true`, so the owner's foreground work keeps the CPU and disk.
Those two settings are host-wide and apply to the owner's local builds too.

A builder that cannot be reached is skipped rather than waited on.
Every dispatcher's ssh block sets `BatchMode yes`, so the daemon is never parked on a prompt it cannot answer, `ConnectTimeout 5`, so an asleep or off-mesh host does not absorb the full TCP retry schedule, and `ServerAliveInterval 15` with `ServerAliveCountMax 2`, so a session to a host that suspends mid-transfer is torn down.
Nix then marks that machine disabled for the rest of the build and reconsiders the remaining builders, or builds locally where it can.
Work that only the missing builder could take fails as `missing system features` rather than degrading to some other route.

## What the builder entries claim, and why

`systems` is `aarch64-darwin` alone on every darwin builder.
`nix config show extra-platforms` on stibnite reports `aarch64-darwin` and nothing else, so advertising `x86_64-darwin` would route derivations the machine refuses to build.

Stibnite's `maxJobs` is 4.
Stibnite has 18 logical cores, 12 performance and 6 efficiency, and 64 GiB of memory, and it is also a laptop in interactive use that commits 12 cores and 48 GiB to the rosetta builder VM and the same again to colima when either runs.
The remote share is deliberately a minority of the machine.

Rosegold's and argentum's `maxJobs` is 2.
Their machine files record no hardware notes to size a share from, so they take the service contract's fallback of 2 rather than a number chosen without measurement.

`speedFactor` is 1 on all three darwin builders.
Nix compares speed factors only among machines that can build the same system, and with equal factors the scheduler chooses among them by current load.

Stibnite's `supportedFeatures` is `apple-virt` and `big-parallel`, and rosegold's and argentum's is `big-parallel` alone.
Stibnite is the only machine whose `apple-virt` has been confirmed.
`benchmark` is dropped because timings taken on a laptop under interactive load are not measurements, and `nixos-test` is dropped because it is a Linux sandbox capability that nix lists unconditionally.

## Two keys, two authorizations

The build and session keys are separately authorized so they can be revoked or rotated independently.

Each dispatcher generates its own build keypair as the `clan.core.vars` generator `nix-remote-build`.
Magnetite alone also generates `stibnite-agent-session`, the session keypair for stibnite.
No plaintext private key material is committed.
Each private half is committed age/SOPS-encrypted under `vars/per-machine/<dispatcher>/` and is decryptable only by that machine and the authorized users recorded beside it.
The public halves are committed under the same path, and each builder's configuration reads them at evaluation time.

The build keys are authorized on the build account, `builder` on NixOS and `nixbuild` on darwin, a non-admin account that exists only to serve the build protocol.
Each authorized-keys entry carries `restrict` and a forced command, which restricts the key to starting that program with no pty, forwarding, shell, or other command.
The forced command does not bound the nix daemon's authority.
The build account deliberately belongs to Nix's `trusted-users` because an untrusted account cannot receive unsigned store paths that a caller evaluated itself.
That membership is store-root-equivalent on the builder: the account can cause arbitrary paths to enter the store and influence what the daemon trusts.

The session key is the broader credential: it authorizes an ordinary login as `crs58` on stibnite, an admin-group member who is already a Nix trusted user through `@admin`.
It therefore includes build authority plus shell access, while giving automated sessions an identity that can be revoked or rotated independently of the human's keys and the build keys.

The `nix-builders-wiring` check asserts the separation in both directions: the session key does not appear in any build account's authorized keys, no build key appears in the session account's, and each build-account line is exactly the forced command plus one dispatcher's key.

## What an operator must do

Three steps are the operator's.

Run `clan vars generate <dispatcher>` when a dispatcher's keypair is rotated or first created, and commit the resulting encrypted private half and public value under `vars/per-machine/<dispatcher>/`.
The builders' authorizations read those values at evaluation time, so an ungenerated key is an evaluation failure rather than a silent grant.

Activate every builder and every dispatcher the change touches: `clan machines update magnetite` or `clan machines update pyrite` for the NixOS ends, and `just activate` on stibnite, rosegold and argentum for the darwin ends.
A dispatcher's activation installs its build-machine entries, ssh aliases and store URIs, and a builder's installs the account and its authorized keys.

Creating a macOS account requires Full Disk Access when `darwin-rebuild` runs over ssh, so the first activation of each Mac that gains `nixbuild` should run in a graphical session on the machine.
Each darwin builder's activation also adds `nixbuild` to macOS's `com.apple.access_ssh` service ACL: it checks membership with `dseditgroup -o checkmember` and adds the account with `dseditgroup -o edit -a nixbuild -t user com.apple.access_ssh` only when it is missing.
That ACL nests only the admin group, so without the entry the build account is refused by sshd before the key is ever consulted, and the failure reads as `Permission denied (publickey)` with a correct key installed.
The builder setting `authorizeSshAccessGroup = false` turns that step off for a host whose ACL is managed by hand.

## What CI asks of the darwin builders

nixbot on magnetite builds `checks.aarch64-darwin` alongside `checks.x86_64-linux`, as best-effort.
`nixbot.toml` sets `attribute = "checks"`, and `modules/nixos/nixbot.nix` sets both `buildSystems` and `evalSystems` to `[ "x86_64-linux" "aarch64-darwin" ]`.
`evalSystems` is what scopes the attribute, so aarch64-linux, which no builder here serves, is never evaluated.
`modules/nixos/buildbot.nix` still sets `buildSystems = [ "x86_64-linux" ]`.

Every darwin builder is a laptop without guaranteed availability, so a darwin build must not gate CI on whether a Mac is awake.
`modules/checks/nixbot-best-effort-darwin.nix` gives every darwin check, the `darwin-<host>` machine checks included, hercules-ci's `ignoreFailure` modifier.
A failed darwin attribute is therefore an ignored failure: shown on the build, excluded from the build's aggregate status, and retried on the next build.
The cost is real: nixbot cannot tell an absent Mac from a genuine darwin regression, so local `just check-fast` on a Mac remains the gate for darwin.
A darwin evaluation error is not covered and still fails the build.
The modifier changes no drvPath, so nothing rebuilds and the binary cache is unaffected.

The builds run on stibnite, the only Mac magnetite dispatches to, at Background QoS with low-priority I/O like all work on a darwin builder.
The `nixbot-wiring` check pins CI's system scope and the best-effort marking.

## Related

- [Build service topology](/concepts/build-service-topology/) — the two CI services kept separate from these development builders
- [Clan Integration](/concepts/clan-integration/) — how `clan machines update` deploys these ends
- [Secrets management](/guides/secrets-management/) — how `clan.core.vars` credentials reach a service
