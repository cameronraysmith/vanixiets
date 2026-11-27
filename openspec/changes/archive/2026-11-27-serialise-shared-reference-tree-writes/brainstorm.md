# Brainstorm: serialise shared reference tree writes

Captured 2026-11-26 from the commit "fix(ghq-shared): serialise writer requests per repository" (`ebd5daae2` on `main`), the investigation of the collision it fixes, and the runtime test's measured times.
The behaviour is already merged; this change records it in the specs and makes room for it in the runtime test.

## Background

On 2026-11-26 on stibnite two `get -u` requests for `github.com/nixos/nixpkgs` reached the writer together.
The writer's service starts one handler per connection, and nothing ordered two handlers acting on one repository.
One handler moved `refs/remotes/origin/master` twice (`pull --ff-only` at 16:23:38, `fetch --no-tags origin` at 16:23:53, as `shallow_tags` does for a `--tags` request) while the other's `git pull --ff-only` was transferring, so the second failed with "cannot lock ref ... is at X but expected Y" and left the remote-tracking ref ahead of the checked-out branch.
The same writer log shows the first request's caller had disconnected (`BrokenPipeError`) while its handler carried on to exit 0.

The commit made each request that writes a repository hold an exclusive `flock` on a lock file in `/var/lib/ghq-writer` for the whole operation, waiting up to 3600 s and then failing with exit 75; told a waiting caller so, on a note line, when the caller announced on a second request line that it accepts notes; refused a `get` whose target names no directory under the root, because such a target has no lock name; replaced the handler's log line with one carrying a UTC timestamp, the caller and the repository, never the target; and made a disconnected caller's handler finish its operation and log the disconnection instead of a traceback.

None of this is in `openspec/specs/shared-reference-tree-interface/spec.md`.
"Acquisition is delegated…" ends at one handler per connection with umask `0027`; "The writer accepts only constrained requests" ends at one request per connection of at most 4 KiB.

The runtime test `vmTests.x86_64-linux.shared-reference-tree` (class `small`, a 60 s script limit) ran 25.99 to 31.96 s in eight runs on 2026-10-17, 43.60 and 48.47 s on 2026-11-16, and 51.76 and 50.04 s on 2026-11-26 after the lock's subtest was added.
Boot to `multi-user.target` took 19.97 and 21.88 s of that.
The next case would put it over its limit.

## Q1: Which requirements does the lock change?

The interface requirement "Acquisition is delegated to the writer through a socket-activated entry point" gains the serialisation: one repository at a time, different repositories in parallel, the lock directory and its mode, the lock's name, the wait's limit and exit status.
"The writer accepts only constrained requests" gains the second request line and the note it enables, the refusal of a `get` that names no directory under the root, the log line, and the disconnected caller.

Superseded in part while drafting the specs: `openspec validate --strict` fails any requirement text over 500 characters, and both requirements above are already longer (737 and 1,447 characters), so the behaviour is recorded as six added requirements instead and the two keep their text, which stays true; design D1 records why.

The behavioral requirement "Only the writer changes the reference tree" is unchanged: the lock orders the writer's own work and gives no other account any write.
"A missing reference repository can be requested without a person" is unchanged in wording; the serialisation is what makes two simultaneous requests both carried out, which its existing scenario already demands.
No world assumption names the writer's concurrency or the runtime test.
`packages/docs/src/content/docs/development/traceability/satisfaction.md` names neither the runtime test's attribute nor its cases, and is regenerated wholesale at archive.

## Q2: What witnesses each new scenario?

The handler's package test (`pkgs/by-name/ghq-shared/test_handler.py`, built as `checks.x86_64-linux.package-ghq-shared-test-handler`) holds one case per behaviour, each under a comment naming it: two updates of one repository, updates of two repositories, the lock timeout, the disconnected caller, the log lines, and the lock names.
The runtime test's subtest "a request takes its repository's lock in the writer's lock directory, and a second one waits" witnesses the lock directory's owner and mode, the lock file's, and the note relayed through the real client, socket and service.
Every new scenario names one of these.

## Q3: How is the runtime test cut?

Options considered:

1. Raise the class to `medium`. Rejected: the repository's rule is that a test larger than its purpose is split or its slow part moved, and a class is not raised to make room.
2. Shorten the slow cases. The lock case already lost its fixed hold (3.54 s to 0.96 s); the rest are git work against fixtures, not waits, so there is no idle time to remove.
3. Split into two tests built from one node definition. Each boots its own VM (about 20 to 22 s), so the cases must divide so that both scripts stay at least 15 s under 60 s.

Per-case times from the two logs of 2026-11-26 (`logs/ghq-writer-lock-vmtest-pyrite-20261126-170617.log`, `…-171209.log`), in seconds:

| case | first | second |
|---|---|---|
| boot to `multi-user.target` | 19.97 | 21.88 |
| each reader resolves the shared root | 0.55 | 0.50 |
| a reader acquires a repository through the writer | 0.85 | 0.84 |
| lock and waiting request | 3.54 | 0.96 |
| every reader reads it with git | 0.48 | 0.51 |
| deepen, promote and update | 2.25 | 2.20 |
| hydrate | 1.95 | 1.91 |
| LFS | 2.18 | 2.19 |
| default branch renamed upstream | 1.80 | 1.74 |
| tags | 4.15 | 4.32 |
| control | 0.05 | 0.05 |
| readers cannot write the tree | 1.41 | 0.68 |
| malformed requests | 3.40 | 3.42 |
| safe.directory | 0.05 | 0.05 |
| bare repository | 0.31 | 0.30 |
| outsider | 0.15 | 0.14 |
| fsmonitor threat | 0.19 | 0.20 |
| migration | 7.55 | 7.48 |
| script total | 51.76 | 50.04 |

Decision: migration and tags move to a new test, `shared-reference-tree-migration`; every other case stays in `shared-reference-tree`.
Migration is the largest case and has its own purpose (moving per-account trees in and back out); its rollback step has the writer clone the tags case's `fixture/tagged` upstream, so tags travels with it, and tags is the next largest case.
The kept test holds the writer's request protocol, its lock, its refusals and the permission model: 15 cases, about 15.5 s of cases, about 38 s with boot.
The new test holds 2 cases plus a precondition that acquires and promotes `hello` (the tags case updates it as a full clone), about 14 s of cases, about 36 s with boot.
Putting tags in the kept test instead would leave the new test at about 31 s and the kept one at about 42 s, closer to the 45 s that leaves 15 s of margin.

## Q4: Which name keeps the history?

`devloop.runtime_test_result` keys records by test name, so a rename loses the earlier runs.
The half with most cases keeps `shared-reference-tree`; the new test starts a history of its own.

## Q5: Where do the mutation variants go?

`passthru.mutations.group-writable` (a group-writable root under a permissive service umask) and `passthru.mutations.broken-control` (a control write that always fails) break the permission and control cases, which stay in `shared-reference-tree`, so both stay attached to it.
Nothing in the repository runs mutations on a schedule or as a check; they are built on demand, so each is built once on pyrite after the split to show it still fails for its reason.
The handler now sets umask `0027` itself, so the group-writable variant's service drop-in no longer reaches the handler; its root mode `2770` is what still lets a reader write.

## Q6: Commits

Recent small changes landed as a `docs(openspec): …` commit for the plan followed by the implementation commit (`7ffb76200` then `7d02f0a58` for serve-omnigraph-from-local-disk), so this change uses two commits: `docs(openspec): …` for the artifacts and `test(shared-reference-tree): …` for the split.
