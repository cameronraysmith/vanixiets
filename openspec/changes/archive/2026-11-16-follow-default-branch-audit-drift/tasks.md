Evidence logs are under `logs/` (git-ignored), named `ghq-d2*-…-<timestamp>.log`.
x86_64-linux package tests build on magnetite with `--eval-store auto --store ssh-ng://magnetite.zt`; the VM test needs kvm and builds on pyrite with `--store ssh-ng://root@pyrite.zt`; darwin is evaluated only. Every build evaluates the chain's pinned commit as `git+file://$PWD?rev=<commit>`.

## 1. Default branch (D28)

- [x] 1.1 Add to `test_handler.py`, before the handler changes, upstreams whose default branch moves from `master` to `main` with `master` deleted and kept, lazy clones of each, and full clones on the old default, on it with a local change, and on a feature branch. — verify: the test fails against the handler as it was (local run with the built-in substitutions).
- [x] 1.2 Follow the remote's default branch in `run_get` on update (`follow_default_branch`). — verify: the same test passes (local run), and `checks.x86_64-linux.package-ghq-shared-test-handler` builds on magnetite (build).
- [x] 1.3 Add a VM subtest in which upstream renames `master` to `main` and a reader's `ghq-sync -u` follows it through the writer. — verify: the VM test passes on pyrite, and fails on a throwaway commit that drops the call to `follow_default_branch` (build).

## 2. Audit (D29)

- [x] 2.1 Add `ghq-sync --audit [QUERY]`, its help text, and `jq` as a runtime input; `gh` comes from the account. — verify: `checks.x86_64-linux.package-ghq-shared-test-wrapper` builds on magnetite with the audit cases (a fake `gh` answering a rename, a rename beside the new clone, a deleted, an archived, a case-only and a drifted repository; the tree unchanged; no token) (build); a read-only run over stibnite's tree (command).

## 3. Writer umask (D32)

- [x] 3.1 Set umask `0027` in the handler's `main()`; start every handler in `test_handler.py` with umask 022 and fail on any entry under the test root open to others or group-writable. — verify: the test fails against the handler as it was and passes with the change (local runs; build on magnetite).
- [x] 3.2 Write the operator script that strips `o+rwx` and `g+w` under the shared root as the writer, dry run by default. — verify: a dry run on stibnite lists 105,754 entries in the repositories recorded in `verify.md` (command).

## 4. Boundary (D30) and guidance

- [x] 4.1 State in the trust boundary that the writer never deletes, renames or relocates a repository, and update `modules/home/README.md` for the audit. — verify: `openspec validate --strict` on the change, and `prek run --files` on every changed file (command).
- [x] 4.2 Evaluate both full check sets from the pinned commit. — verify: `nix eval` of `checks.x86_64-linux` and `checks.aarch64-darwin` drv paths from `git+file://$PWD?rev=<commit>` succeeds (evaluation).
