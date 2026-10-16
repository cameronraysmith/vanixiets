# Shared ghq reference tree implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** One ghq reference tree per host on magnetite, pyrite and stibnite, written only by a dedicated writer account (`ghq` on NixOS, `_ghq` on darwin) and read by every participating human and Omnigent worker account.

**Architecture:** `services.shared-reference-tree` declares participation per host; NixOS and darwin adapter aspects named `shared-reference-tree` create the writer account and group, the root, and a socket-activated writer service, and set `programs.ghq-shared.root` in each participant's Home Manager configuration. That option sets `ghq.root`, one `safe.directory` entry and the `~/ghq` link, and swaps `ghq` and `ghq-sync` for delegating variants from `pkgs/by-name/ghq-shared/`. Declared invariants are module assertions on the existing machine checks; runtime behaviour is an executed NixOS test plus post-activation smoke. Existing trees are moved, not re-fetched, by `ghq-shared-migrate`.

**Tech Stack:** nix flakes with flake-parts and import-tree; NixOS and nix-darwin modules; Home Manager; Python 3 standard library for the handler, client and migration tool; bash for the `ghq` wrapper; ghq and git from nixpkgs; `pkgs.testers.runNixOSTest`.

**Spec:** `design.md`, `specs/shared-reference-tree/spec.md`, `specs/shared-reference-tree-interface/spec.md`, `specs/world-assumptions/spec.md` in this change directory.

## Global Constraints

- Sharing hosts are exactly magnetite, pyrite and stibnite. Participants: magnetite and pyrite `cameron`, `omnigent-cameron`, `omnigent-janettesmith`; stibnite `crs58`, `omnigent-cameron`.
- Roots `/var/lib/ghq` (NixOS) and `/Users/Shared/ghq` (darwin), mode `0750`, owner and group the writer. Writer umask `0027`.
- Each participant's git settings: `ghq.root = <root>`; `safe.directory` gains exactly `<root>/*`; never `*`.
- The writer has no password, `nologin` shell, no SSH keys, no extra groups, no sudo rule, no trusted-user entry, no credentials.
- Sockets: `/run/ghq-writer.sock` (NixOS) and `/var/run/ghq-writer.sock` (darwin), group the writer's, mode `0660`; one handler per connection.
- Writer git: no system or global configuration; `protocol.allow=never` plus each of `services.shared-reference-tree.allowedProtocols` (default `[ "https" ]`).
- Verify every task against its own commit, `git+file://$PWD?rev=<commit>`, never the shared working copy. Hosts' `toplevel.drvPath` changes with every commit, so "unchanged" means the sharing projection defined at the top of `tasks.md`.
- Capture long commands: `<cmd> 2>&1 | tee logs/<name>-$(date +%Y%m%d-%H%M%S).log`.
- Each task is one commit created with `jj new --no-edit -A <chain tip> -B <join>` and filled by a path-scoped `jj squash --from @ --into <commit> --use-destination-message --keep-emptied <paths>`; `@` never moves.
- Activate nothing and move no real tree before group 9; group 9 is human-gated.

## File map

| Path | Tasks | Responsibility |
|---|---|---|
| `modules/system/shared-reference-tree.nix` | 1.1 | Platform-neutral `services.shared-reference-tree` options for NixOS and darwin |
| `modules/nixos/shared-reference-tree.nix` | 1.1, 1.3, 2.1, 3.2, 4.4, 5.1 | NixOS adapter: writer, group, tmpfiles, Home Manager wiring, socket and service, assertions |
| `modules/darwin/shared-reference-tree.nix` | 1.1, 8.1–8.5 | Darwin adapter: `_ghq`, root, Home Manager wiring, launchd daemon, assertions |
| `modules/machines/{nixos/magnetite,nixos/pyrite,darwin/stibnite}/default.nix` | 1.1 | Participation |
| `modules/lib/omnigent-fleet-obligations.nix` | 1.2 | Admit the writer's group for participating workers |
| `modules/home/development/repository-acquisition.nix`, `modules/home/tools/ghq-sync.nix` | 3.1, 4.3 | `programs.ghq-shared.root`, git settings, link activation, package swap |
| `pkgs/by-name/ghq-shared/` | 4.1, 6.1 | Wrapper `ghq`, client, handler, migration tool, handler test |
| `pkgs/by-name/ghq-sync/` | 4.2 | `delegate` argument, `GHQ_SYNC_NO_ZOXIDE` |
| `modules/checks/package-tests.nix` | 4.1 | Declare `ghq-shared`'s `handler` test |
| `modules/vm-tests/shared-reference-tree.nix` | 5.2, 6.1 | Executed NixOS test |
| `modules/darwin/omnigent-host.nix` | 8.1, 8.3 | Credential delivery group; worker-home root |
| Skill, instruction fragment, two READMEs | 7.1–7.3 | Documentation at sources |

## Interfaces

- `config.services.shared-reference-tree.{enable,participants,writer,root,allowedProtocols}` (NixOS and darwin).
- `config.programs.ghq-shared.root` (Home Manager; null or string).
- `pkgs.ghq-shared`: `bin/ghq` (wrapper), `libexec/ghq-shared/ghq-writer-client`, `libexec/ghq-shared/ghq-writer-handler`, `bin/ghq-shared-migrate`; `passthru.tests.handler`. The socket path defaults by platform.
- Handler: `ghq-writer-handler <config.json>`, config `{ root, group, allowedProtocols, ghq, ghqSync, git }`; one JSON request on standard input (the connection), one JSON reply `{ stdout, stderr, exit }`.
- Requests: `{"action":"get","target":T,"lazy":bool,"update":bool}`, `{"action":"deepen","depth":N,"path":P}`, `{"action":"promote","path":P}`.
- Client: `ghq-writer-client get [--lazy] [--update] T`, `ghq-writer-client deepen N P`, `ghq-writer-client promote P`; prints the reply's streams and exits with its status.
- `pkgs.ghq-sync.override { ghq = pkgs.ghq-shared; delegate = "<client>"; }`.

## Task outlines

Task numbers match `tasks.md`; each task's verify line there is its acceptance test.

1.1 Options module and empty adapters; participation in three machines. 1.2 Obligation `memberships` admits the writer's group when `hostConfig.services.shared-reference-tree` lists the worker. 1.3 `users.users.ghq` (system, `nologin`, locked) and `users.groups.ghq.members = participants`.

2.1 `systemd.tmpfiles.rules = [ "d ${root} 0750 ghq ghq -" ]`.

3.1 Option module `homeManager.ghq-shared-option` (stable `key`), imported by `ghq` and `ghq-sync`; when set: `programs.git.settings.ghq.root`, `programs.git.settings.safe.directory = [ "${root}/*" ]`, `home.activation.ghqSharedLink` (link only if absent or a link, otherwise warn), assertion `programs.git.enable`. 3.2 `home-manager.users = genAttrs participants (_: { programs.ghq-shared.root = root; })`.

4.1 Handler validates the request (D5), checks the peer (`SO_PEERCRED` / `LOCAL_PEERCRED`) against the group, runs `ghq` or `ghq-sync` without a shell in a fixed environment, and replies. The wrapper dispatches on the subcommand. The `handler` test drives the handler over a `socketpair` with the build user's own group and an in-sandbox `git://`-free fixture: refused classes are asserted refused before any process runs; the accepted case uses a local `file://` fixture with `file` added to the test configuration's allowed protocols. 4.2 `deepen_one` and the in-place branch of `full_one` call `"$GHQ_SYNC_DELEGATE"` when set; `register_targets` returns early when `GHQ_SYNC_NO_ZOXIDE` is set. 4.3 Package swap in the option branches. 4.4 Socket and template service on NixOS with the handler configuration as a store file.

5.1 Assertions in the NixOS adapter; mutations through `extendModules`. 5.2 One node, `services.gitDaemon` serving `/srv/git`, `allowedProtocols = [ "https" "git" ]`, readers `cameron` and `omnigent-cameron`, an outsider; the assertions of D8. 5.3 Full builds.

6.1 `ghq-shared-migrate` per D10; the NixOS test seeds a tree for `cameron` and asserts list, move, ownership, sanitisation, sidecar and rollback.

7.1–7.3 Documentation edits at their sources.

8.1–8.5 Darwin, after `_ghq` UID/GID approval.

9.1–9.4 Human-gated activation, migration and deletion.
