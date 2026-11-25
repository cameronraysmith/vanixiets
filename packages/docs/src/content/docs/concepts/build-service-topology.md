---
title: Build service topology
description: nixbot, the one Nix CI build service on magnetite, and the boundaries that scope what it builds
sidebar:
  order: 8
---

Magnetite carries one Nix CI build service, [nixbot](https://github.com/Mic92/nixbot), served at `nixbot.scientistexperience.net`.
It is one service that evaluates with a bundled nix-eval-jobs and builds through the host's nix daemon, and it serves both of the fleet's GitHub repositories, `cameronraysmith/vanixiets` and `sciexp/ironstar`.
It replaced [buildbot-nix](https://github.com/nix-community/buildbot-nix), which no longer runs anywhere in the fleet.

## How the service is composed

It follows the repository's ordinary deferred-module pattern.
The upstream NixOS module is imported at the host in `modules/machines/nixos/magnetite/default.nix`, and the site configuration lives in its own aspect, `modules/nixos/nixbot.nix`, named in that host's aspect list.
The service is not fetched or updated independently of activation, so what runs on the host is a function of the machine's NixOS generation and `clan machines update magnetite` is what changes it.

## A dedicated forge application

nixbot has its own GitHub App.
It needs Checks write access, Pull requests read and write access, and the `check_run` and `check_suite` events.
Its three forge credentials are `clan.core.vars` generators named for their consumer: the application private key and the OAuth client secret are operator-populated slots, and the webhook secret is generated.
Each names `nixbot.service` in its restart list, because the unit snapshots its credentials at start and a rotation without a restart would leave the service holding the superseded value.

The application was registered through GitHub's App manifest flow, which generated a webhook secret of its own, while the `nixbot-github-webhook-secret` generator independently generates a different one.
The generator is authoritative, so the application's webhook secret has to carry its value, or every delivery fails signature validation.

## What scopes the repositories nixbot builds

The forge application's installation selection bounds which repositories nixbot can see at all.
It is set by hand on the forge and is not something the machine can assert or review.

`services.nixbot.github.topic` is null.
Its default, `build-with-buildbot`, performs a one-shot import of every repository carrying that topic against an empty database.

`services.nixbot.github.repoAllowlist` names the two repositories explicitly, and `checks.x86_64-linux.nixbot-wiring` asserts that the allowlist admits both.

## Verdicts and the merge queue

nixbot's `statusContextPrefix` is its own default, `nixbot`, so it posts `nixbot/nix-eval`, `nixbot/nix-build` and `nixbot/effects`.
Those three contexts are what the forge ruleset and [gitea-mq](https://github.com/Mic92/gitea-mq) require before a pull request lands (`modules/nixos/gitea-mq.nix`).

## Ports, state and capacity

nixbot binds no TCP port.
Its nginx integration stays enabled, so it listens only on the unix socket `/run/nixbot/web.sock` and the module-managed vhost proxies to it with `forceSSL` and its own ACME certificate.

It has its own systemd unit, user and group, its own database and role on the host's single PostgreSQL instance, its own state directory, and its own GC-root directory under `/nix/var/nix/gcroots/per-user/`.
Successful builds are pushed to the fleet's binary cache through its niks3 uploader.

Magnetite is a Hetzner CX53: 16 vCPU, 32 GiB of memory, and `/nix` under a 250 G ZFS quota with a free-space reaper.
nixbot evaluates `x86_64-linux` and `aarch64-darwin` with six workers at 3 GiB each, sized by measurement in `modules/nixos/nixbot.nix`.
Every nix-eval-jobs on the host, nixbot's included, queues on the host evaluation lock (`modules/nixos/nix-eval-lock.nix`), so a remote `just check-fast` evaluation never overlaps it.
`aarch64-darwin` attributes are built, and required, on the darwin builders (see [Darwin build access](/concepts/darwin-build-access/)).

## What this topology does not guarantee

It does not guarantee that no unintended repository is ever built.
The outermost boundary is the forge application's installation selection, which a person sets on the forge and which the machine cannot observe, so the machine's contribution is the boundaries it can assert and no more.

## Related

- [Clan Integration](/concepts/clan-integration/) — how `clan machines update` deploys the service
- [Deferred module composition](/concepts/deferred-module-composition/) — the aspect pattern the service follows
- [Fleet topology](/concepts/fleet-topology/) — every host's services and networks, magnetite's among them
- [Secrets management](/guides/secrets-management/) — how `clan.core.vars` credentials reach a service
