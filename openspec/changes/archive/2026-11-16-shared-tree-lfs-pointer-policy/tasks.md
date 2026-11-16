Evidence logs are under `logs/` (git-ignored), named `ghq-lfs-*-<timestamp>.log`.
x86_64-linux package tests build on magnetite with `--eval-store auto --store ssh-ng://magnetite.zt`; the VM test needs kvm and builds on pyrite with `--store ssh-ng://root@pyrite.zt`; darwin is evaluated only. Every build evaluates the chain's pinned commit as `git+file://$PWD?rev=<commit>`.

## 1. Writer

- [x] 1.1 Set the four LFS keys at command scope in `ghq-writer-handler.py`'s `environment()` and add the `hydrate` action with its revision check; add `hydrate REV PATH` to `ghq-writer-client.py`. — verify: `checks.x86_64-linux.package-ghq-shared-test-handler` builds on magnetite (build).
- [x] 1.2 Add to `test_handler.py` an LFS fixture whose clone requires `git-lfs`, an update that changes the LFS path, and a control clone updated without the policy; and hydrate cases over an allowed and a disallowed protocol, a missing revision, and refused revisions. — verify: the handler test passes, and with `LFS_POLICY` removed from the handler it fails on the LFS case (build; local run with the policy removed).
- [x] 1.3 Add `--hydrate REV` to `ghq-sync`, handed to `GHQ_SYNC_DELEGATE` on a shared tree, and its cases to `test-wrapper.nix`. — verify: `checks.x86_64-linux.package-ghq-shared-test-wrapper` builds on magnetite (build).

## 2. Readers

- [x] 2.1 Add `flake.lib.sharedReferenceTreeLfsPolicy` and a `programs.git.includes` entry per root form in the `ghq` Home Manager module when `programs.ghq-shared.root` is set. — verify: `nix eval` of `home-manager.users.crs58.programs.git.includes` on stibnite shows both `gitdir:` forms and of `cameron`, `omnigent-cameron` and `omnigent-janettesmith` on pyrite and `cameron` on magnetite shows `gitdir:/var/lib/ghq/`; the rendered stibnite `git/config` places both `includeIf` sections after `[filter "lfs"]` (evaluation).
- [x] 2.2 Assert the include for every participant and root form in the darwin and NixOS adapters. — verify: `config.assertions` has no failure on stibnite, pyrite and magnetite, and fails with this message when cameron's includes are emptied on pyrite or crs58 keeps only the `/var` form on stibnite (evaluation).

## 3. Migration

- [x] 3.1 Set smudged LFS paths back to pointers as the writer after `link_root`, keeping content and index in the record directory, and undo it on rollback. — verify: the VM test's migration case, where cameron's clone holds smudged LFS content, reports the step, leaves the pointer, and rollback restores the tree exactly (build of `vmTests.x86_64-linux.shared-reference-tree` on pyrite).

## 4. Runtime

- [x] 4.1 Extend `modules/vm-tests/shared-reference-tree.nix` with the reader include check, hydrate through the writer, and an LFS case: pointer checkout, readers whose git runs git-lfs at system scope see no change and write nothing, a control that re-enables git-lfs above the include fails, and an update of a clone requiring git-lfs fast-forwards. — verify: the VM test passes on pyrite, and fails on a throwaway commit that removes the handler's `LFS_POLICY` (build).

## 5. Guidance

- [x] 5.1 Update the `dependency-source-acquisition` skill, the reference-repositories context, `modules/home/README.md`, and `ghq-sync --help` for hydrate and the LFS policy. — verify: `prek run --files` on every changed file passes (command).
