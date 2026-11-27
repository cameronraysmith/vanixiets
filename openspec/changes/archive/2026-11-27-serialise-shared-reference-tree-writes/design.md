## Context

The shared reference tree's writer (`pkgs/by-name/ghq-shared/ghq-writer-handler.py`) is started once per connection by a socket-activated service on NixOS (systemd `Accept=yes`) and on darwin (launchd `inetdCompatibility`).
On 2026-11-26 two `get -u` requests for one clone ran together on stibnite and the second failed with "cannot lock ref", leaving the remote-tracking ref ahead of the branch.
The commit "fix(ghq-shared): serialise writer requests per repository" (`ebd5daae2`) added a lock per repository, a note to a waiting caller, a refusal of a `get` with no lock name, a structured log line and quiet handling of a disconnected caller.
`openspec/specs/shared-reference-tree-interface/spec.md` states none of it.

The runtime test `vmTests.x86_64-linux.shared-reference-tree` is class `small`, whose driver timeout is 60 s of script.
With the lock's subtest its script measured 51.76 and 50.04 s on pyrite on 2026-11-26, about 20 to 22 s of it boot to `multi-user.target`.

Both boundaries named by the repository's rules are untouched: the change edits first-party sources only (a spec, a test module, and the writer and its package test), and the test is source that the weekly runner on pyrite evaluates from `main`, not a delivered artifact.

Verification of the merged behaviour found two gaps between the spec and the writer: a command that outlasted its 3600 s limit raised `subprocess.TimeoutExpired`, which nothing caught, so Python's traceback, holding the command's arguments and with them the target as given, went to the writer's log, and the request ended with no exit line and no reply; and the lock requirement said both that requests for different repositories never wait for each other and that the lock is named by the case-folded path.
A second verification found that git's automatic maintenance, detached by default, left the command's process group and wrote the repository after the lock was released, and that the blobless clones on stibnite had accumulated up to 2,533 packs (D9).

## Goals / Non-Goals

**Goals:**
- The interface spec states every behaviour the lock commit added, each scenario with a named witness.
- Each runtime test of the shared reference tree runs at least 15 s under its 60 s limit, so a new case has room.
- `shared-reference-tree` keeps its name and its history in `devloop.runtime_test_result`.

**Non-Goals:**
- Changing the writer beyond how it ends a failed or timed-out request and how git's automatic maintenance runs, its client, or the NixOS and darwin modules.
- Making the lock cover writes that do not go through the writer.
- Running mutation variants on a schedule.

## Decisions

### D1: Record the merged behaviour as added interface requirements, one behaviour each

- **Choice**: add six requirements to `shared-reference-tree-interface` (one repository at a time; the bounded wait and the note; the refused `get`; the log line; the disconnected caller; the runtime tests' classes) and modify "Each property is backed by evidence that can fail" to speak of runtime tests in the plural. Each new scenario carries a `Witness:` line naming a case of `pkgs/by-name/ghq-shared/test_handler.py` by its comment or a runtime test's subtest by name.
- **Rationale**: the first plan modified "Acquisition is delegated to the writer through a socket-activated entry point" and "The writer accepts only constrained requests". Their text is 737 and 1,447 characters, and `openspec validate --strict` (openspec 2.2.0) fails any requirement over 500, so any MODIFIED delta of either fails the gate; shortening them would rewrite requirements this change has no reason to touch. Both stay true as written: one handler still starts per connection, and the second line is an option, not a second request. "Each property is backed…" was 625 characters and is restated in 492.
- **Alternatives considered**: modifying the two requirements and accepting the warnings (fails `--strict`); one added requirement holding all of it (over 500 characters again).
- **Boundary**: first-party; the spec describes first-party code.

### D2: Leave the behavioral spec and world assumptions unchanged

- **Choice**: no delta for `shared-reference-tree` or `world-assumptions`.
- **Rationale**: "Only the writer changes the reference tree" concerns which account writes, and the lock gives no other account a write; "A missing reference repository can be requested without a person" already demands that a well-formed request is carried out, which the collision violated and the lock restores. No assumption names the writer's concurrency, and none names the runtime test.
- **Alternatives considered**: a world assumption that `flock` on darwin and Linux excludes across processes. Rejected: it is the operating system's documented behaviour, exercised by the handler's package test on each build platform, and no requirement's discharge rests on it beyond that test.

### D3: Cut the runtime test into access and migration

- **Choice**: `vmTests.x86_64-linux.shared-reference-tree` keeps 15 cases: root resolution, acquisition, the lock, reading, deepen/promote/update, hydrate, LFS, the renamed default branch, the control, the write refusals, malformed requests, `safe.directory`, bare repositories, the outsider and the fsmonitor threat. `vmTests.x86_64-linux.shared-reference-tree-migration` takes the tags case and migration, after a precondition that acquires `hello` and promotes it to a full clone.
- **Rationale**: from the per-case times of 2026-11-26, the kept cases total about 15.5 s and the moved ones about 12 s plus 1 to 2 s of precondition; with 20 to 22 s of boot each script is about 36 to 38 s. Migration has a purpose of its own (moving per-account trees in and out); its rollback step clones the tags case's `fixture/tagged` upstream through the writer, so tags goes with it, and tags is the next-largest case.
- **Alternatives considered**: raising the class to `medium` (rejected by the repository's rule that a class is not raised to make room); moving only migration (the kept test would stay at about 42 s, 18 s under the limit with one case's growth to spare); moving renamed-default-branch as well (balances about 36 and 38 s the other way, with no shared fixture to justify it).
- **Boundary**: first-party test source; the weekly runner reads it from `main`.

### D4: One node definition through `mkTest`

- **Choice**: `mkTest { name, cases, prelude ? "", passthru ? { } }` builds every test from one node and one script header (accounts, fixtures, helpers, readiness waits); `accessCases { control ? "touch" }` and `migrationCases` are the two case sets, each importing what it uses.
- **Rationale**: the node is the thing under test; two definitions could drift apart.
- **Alternatives considered**: a second module file. Rejected: it would duplicate the node or need a shared helper file for one consumer.

### D5: Names and history

- **Choice**: the half with most cases keeps `shared-reference-tree`; the new test is `shared-reference-tree-migration`.
- **Rationale**: `devloop.runtime_test_result` keys runs by test name, and `RuntimeTestCostDrift` judges a test by its own newest runs; the kept test's history continues, with a step down in its time at the split, and the new test starts its own.

### D6: Mutation variants stay with the kept test

- **Choice**: `passthru.mutations.group-writable` and `passthru.mutations.broken-control` stay on `shared-reference-tree` and build its case set.
- **Rationale**: they break the permission model and the control, whose cases stay there. Nothing in the repository builds them on a schedule or as a check, so each is built on demand after the split to show it still fails for its reason.

### D7: One lock for paths differing only in letter case, on every host

- **Choice**: keep the lock name the SHA-256 of the case-folded path, and state in the spec that repositories whose paths differ only in letter case share a lock and run in sequence.
- **Rationale**: on a case-insensitive file system such as stibnite's, `github.com/O/r` and `github.com/o/r` are one clone, so two requests spelling it differently must take one lock. On a case-sensitive host they are two clones, which can only be made deliberately, and waiting for each other costs them time and nothing else. One rule on every host keeps the lock name independent of the platform and of whether the file system beneath the root folds case.
- **Alternatives considered**: folding case only on darwin, or probing the root's file system for case sensitivity. Rejected: either makes the key depend on the host, for no gain beyond letting two such clones run side by side.

### D8: A command that outlasts its limit is stopped with its process group, and its request ends like any other failure

- **Choice**: the handler starts each command in a process group of its own (`process_group=0`); when the command outlasts its limit (3600 s, `commandTimeout` in the handler's configuration for tests), the handler sends `SIGTERM` to the group, waits up to 10 s for every process in it to exit, then sends `SIGKILL` to the group, and ends the request with exit status 124 (as `timeout(1)` does), a reply and an exit line whose reason names the program and its subcommand only. Every failure ends with ` reason: <reason>` on its exit line; an exception nothing else handles is caught at the outermost level, logged by its type and its message with the target replaced, answered with exit status 70 (`EX_SOFTWARE`), and ends the handler with that status. Commands run with standard input from `/dev/null` rather than the caller's connection. A requirement of its own states the stopping.
- **Rationale**: `subprocess.run` kills only the command it started, so a `git` started by `ghq` kept running and writing the repository after its request ended. `SIGTERM` first lets `git clone` remove its partial clone, which `repo_dir` would otherwise take for a clone. The exception's default text is not logged because `TimeoutExpired` and `CalledProcessError` format the whole argument list.
- **Alternatives considered**: a new session (`start_new_session`), which also detaches the commands from the handler's controlling terminal, of which it has none, and gains nothing over a process group.
- **Boundary**: a process that moves itself to another process group escapes the signal. git's automatic maintenance did so by default: after a fetch, `git maintenance run --auto --detach` leaves the command's process group and session, and went on writing the repository after the lock was released. D9 keeps it in the foreground; with that, the package test shows no process of a local clone, fetch or their maintenance leaving the group. Transports over ssh are not exercised.

### D9: Automatic maintenance runs in the foreground with the gc strategy

- **Choice**: `environment()` adds `maintenance.autoDetach=false`, `gc.autoDetach=false` and `maintenance.strategy=gc` to the command-scope configuration of the writer's git, which outranks a repository's own. Maintenance after a fetch then runs inside the command, in its process group, under the repository's lock and within the command limit, and runs `gc --auto`, which consolidates a clone's packs once they exceed `gc.autoPackLimit` (50).
- **Why packs accumulated**: on stibnite the blobless clones held up to 2,533 packs (`github.com/can1357/oh-my-pi`), 1,688 for `github.com/nixos/nixpkgs`, and ten clones held 350 or more; the NixOS trees hold at most 5 per clone. Detachment was not the cause. Without `maintenance.strategy`, git 2.56.0 runs unscheduled maintenance with the geometric strategy (`builtin/gc.c`, the comment "Unscheduled maintenance uses our default strategy" above `strategy = geometric_strategy`), whose need check (`odb_source_files_optimize_required` in `odb/source-files.c`, case `ODB_OPTIMIZE_GEOMETRIC`) repacks only when `geometry.split` is set, and `pack_geometry_init` in `repack-geometry.c` sets promisor packs aside into `promisor_pack`, outside that split. Every pack of a blobless clone is a promisor pack, so the check never fires. On a copy of `oh-my-pi`, `git maintenance is-needed --auto --task=geometric-repack` exits 1 with the packs' `.promisor` files and 0 without them, and `git maintenance run --auto` ran only `commit-graph`, which writes nothing in a shallow clone, in 0.18 s, leaving 2,533 packs; on a copy of `nixpkgs` 0.14 s, leaving 1,688.
- **Cost**: measured on copies on stibnite with the writer's environment. `oh-my-pi` (661 MB of objects): `gc` 2,533 packs to 1 in 12.9 s. `nixpkgs` (2.5 GB): `maintenance run --auto` with the gc strategy 1,688 packs to 2 in 45.8 s and 42.9 s. Each is paid once, on the first update past the limit, and then only each time a clone passes 50 packs again; the caller waits that long for its reply, with no note, and receives gc's "Auto packing the repository" line in its standard error.
- **What gc does that the writer did not**: `pack-refs --all --prune --auto`, `reflog expire --all`, `worktree prune --expire 3.months.ago`, `rerere gc`, `repack -d -l --cruft --cruft-expiration=2.weeks.ago`, `prune --expire 2.weeks.ago --exclude-promisor-objects` and a commit-graph write (skipped in a shallow clone); no bitmap or multi-pack-index is written. A reader reads refs and objects, which gc replaces by rename; it needs no reflog, and `worktree prune` removes only the records of linked worktrees whose directories are gone (stibnite's tree holds eight such records and two live ones). New packs and indexes are mode `0440` under the writer's umask `0027`, readable by the group. Objects in promisor packs are kept: `repack_promisor_objects` in `repack-promisor.c` writes every object of the promisor packs into the new promisor pack, without a reachability walk, and `prune` runs with `--exclude-promisor-objects`; the package test checks blobs hydrated for an older commit and for a commit a forced update left unreachable, with `gc.reflogExpireUnreachable` and `gc.pruneExpire` set to `now`.
- **Interruption**: git's repack writes new packs under temporary names and removes the old ones only after the new ones are in place, so a stop mid-repack leaves the old packs. On copies of `nixpkgs`, maintenance with the gc strategy was stopped with `SIGTERM` at 15 s and at 33 s, and with `SIGKILL` at 15 s and at 33 s. Every copy kept its 1,688 packs and passed `git fsck --connectivity-only` with lazy fetch off (124 to 242 s). After `SIGTERM` git had removed its temporary files and its locks, and the next maintenance consolidated the copy (42.9 and 48.6 s), removing the stale `tmp_pack_*` of 2026-08-27 as well. After `SIGKILL` at 33 s the copy held a complete temporary pack (`.tmp-<pid>-pack-*`); after either `SIGKILL`, `gc.pid` and `objects/maintenance.lock` remained, and the next `git maintenance run --auto` returned at once, doing nothing: it skips silently while that lock file exists (`maintenance_run_tasks` in `builtin/gc.c`). The handler's stop sends `SIGTERM` and waits 10 s before `SIGKILL`; git exited within 3 s of `SIGTERM` in both runs.
- **Alternatives considered**: `maintenance.autoDetach=false` alone, which keeps maintenance under the lock but leaves the packs accumulating; `maintenance.auto=false` and `gc.auto=0`, which run nothing implicit and leave consolidation to an explicit repack verb that does not exist.

## Risks / Trade-offs

- [Risk] Boot time varies (19.97 to 21.88 s measured) and is half of each script. → Mitigation: each test keeps at least 15 s of margin; `RuntimeTestCostDrift` reports a margin narrower than a test's spread over its weekly runs.
- [Trade-off] Two VMs boot where one did, about 22 s more per weekly run on pyrite. → Accepted: the alternative is a larger class or no room for new cases.
- [Risk] `RuntimeTestCostDrift` sees `shared-reference-tree` drop by about 12 s at the split. → Accepted: the rule posts on growth or a narrow margin, not on a drop.
- [Trade-off] The group-writable variant's service drop-in (`UMask=0007`) no longer reaches the handler, which sets umask `0027` itself; the variant still fails because its root mode `2770` lets a reader create an entry. → Accepted; recorded beside the variant's result in tasks.md.
- [Risk] A maintenance killed with `SIGKILL` (the 10 s grace exceeded, a host crash, a service manager's kill) leaves `objects/maintenance.lock`, after which automatic maintenance of that clone silently does nothing. On stibnite `github.com/block/buzz` holds one, dated 2026-08-20, with 366 packs. → Accepted for this change: removing a stale lock is writer-side cleanup for a later change, as is removing the stale `tmp_pack_*` files of clones that never reach the gc threshold.

## Migration Plan

N/A — this change does not involve a deployment change. The weekly runner on pyrite picks up `shared-reference-tree-migration` from `main` on its next run.

## Open Questions

None.
