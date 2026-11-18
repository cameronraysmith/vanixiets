---
title: Build service topology
description: Two CI build services coexisting on magnetite, and the boundaries that keep them apart
sidebar:
  order: 8
---

Magnetite carries two Nix CI build services.
The incumbent is [buildbot-nix](https://github.com/nix-community/buildbot-nix), a master-and-worker pair reachable at `buildbot.scientistexperience.net`, and it remains authoritative for every repository the fleet builds.
The second is [nixbot](https://github.com/Mic92/nixbot), buildbot-nix's successor by the same maintainer, served at `nixbot.scientistexperience.net`, which collapses the master and worker pair into one service that evaluates with a bundled nix-eval-jobs and builds through the host's nix daemon.

nixbot exists so that migrating a repository becomes a small reviewable opt-in rather than a cutover.
It builds no repository, and the sections below say what enforces that and what it does not enforce.

:::note[Rollout status]
nixbot's configuration is complete and the host builds with it, but the service is not yet deployed.
Its two operator-populated credential slots are unpopulated, so the application private key and the OAuth client secret resolve to no path until they are set.
One thing deployment must not miss: the application was registered through GitHub's App manifest flow, which generated a webhook secret of its own, while the `nixbot-github-webhook-secret` generator independently generates a different one.
The generator is authoritative, so the application's webhook secret has to be replaced with its value, or every delivery fails signature validation.
:::

## How each service is composed

Both follow the repository's ordinary deferred-module pattern.
The upstream NixOS modules are imported at the host in `modules/machines/nixos/magnetite/default.nix`, and each service's site configuration lives in its own aspect named in that host's aspect list: `modules/nixos/buildbot.nix` for the incumbent and `modules/nixos/nixbot.nix` for nixbot.
Neither service is fetched or updated independently of activation, so what runs on the host is a function of the machine's NixOS generation and `clan machines update magnetite` is what changes it.

## A dedicated forge application

nixbot has its own GitHub App rather than sharing the incumbent's.
nixbot needs Checks write access, Pull requests read access, and the `check_run` and `check_suite` events, none of which buildbot-nix asks for, so adding them to the incumbent's application would edit a registration a running service depends on.
One shared application would also give both services one identity, one application-level webhook, and one coupled permission history.

The cost accepted is one further registration and one further credential set to rotate.
nixbot's three forge credentials are `clan.core.vars` generators named for their consumer: the application private key and the OAuth client secret are operator-populated slots, and the webhook secret is generated.
Each names `nixbot.service` in its restart list, because the unit snapshots its credentials at start and a rotation without a restart would leave the service holding the superseded value.

## What keeps nixbot from building anything

Three independent boundaries, so that a mistake in one does not by itself produce a build.

The forge application's installation selection bounds which repositories nixbot can see at all.
This one is set by hand on the forge and is not something the machine can assert or review.

`services.nixbot.github.topic` is null.
Its default is `build-with-buildbot`, which is exactly the topic the incumbent's repositories carry, and the topic performs a one-shot import against an empty database — precisely the state on the day of first deployment.
Left at its default it would sweep in the repositories the incumbent already builds and double-build them.

`services.nixbot.github.repoAllowlist` names an explicit set, currently empty.
The auto-import runs against an empty database, so the allowlist alone would not be sufficient; the two machine-side boundaries are complementary rather than redundant.

## Verdicts do not gate merges

nixbot's `statusContextPrefix` is left at its own default, `nixbot`, rather than adopted from the incumbent.
The forge's required checks currently name the incumbent's `buildbot/...` contexts, so a prefix collision would either capture those names or make two services fight over one verdict.
Keeping the default makes nixbot's verdicts advisory by construction rather than by promise.

Migration recipes written for deployments that *replaced* buildbot-nix recommend adopting the incumbent's prefix, and that is correct there, because in those deployments the incumbent no longer runs.
Under coexistence the same move collides with a service that is still running.

When a repository is later opted in, its required-checks configuration must be edited deliberately for nixbot's verdicts to matter.

## What the two services do not share

Each has its own systemd unit, its own user and group, its own database and role on the host's single PostgreSQL instance, its own state directory, and its own GC-root directory under `/nix/var/nix/gcroots/per-user/`.
No name or path among them is shared, so emptying one service's state leaves the other's untouched.

nixbot binds no TCP port.
Its nginx integration stays enabled, so it listens only on the unix socket `/run/nixbot/web.sock` and the module-managed vhost proxies to it with `forceSSL` and its own ACME certificate.
Disabling that integration would make the service bind its TCP fallback port, whose default happens to equal the nixpkgs buildbot default — the single port collision available on this host.

## What remains common-mode

Disjoint names bound the ways the two services can interfere without eliminating them.
They share the host's nginx, its PostgreSQL instance, its nix store and the disk under it, its ACME account, and its finite capacity.

Capacity is the one that matters in practice.
Magnetite is a Hetzner CX53: 16 vCPU, 32 GiB of memory, and `/nix` under a 250 G ZFS quota with a free-space reaper.
The incumbent already sizes four evaluation workers at 2 GiB each, so nixbot is sized explicitly at two workers at 2 GiB rather than by a default derived from the host's core count, which would size it as though it were alone.
Both are restricted to building `x86_64-linux`; other systems would come from the host's remote-builder configuration, which neither service alters.

A sizing argument made while one service builds nothing establishes nothing about the pair under load, so the change that opts the first repository in owns re-observing what the pair actually draws.

## What this topology does not guarantee

It does not guarantee that the incumbent is unaffected.
The shared surfaces above are real, and a capacity or store incident reaches both services.

It does not guarantee that no unintended repository is ever built.
The outermost boundary is the forge application's installation selection, which a person sets on the forge and which the machine cannot observe, so the machine's contribution is the two boundaries it can assert and no more.

## Related

- [Clan Integration](/concepts/clan-integration/) — how `clan machines update` deploys these services
- [Deferred module composition](/concepts/deferred-module-composition/) — the aspect pattern both services follow
- [Fleet topology](/concepts/fleet-topology/) — every host's services and networks, magnetite's among them
- [Secrets management](/guides/secrets-management/) — how `clan.core.vars` credentials reach a service
