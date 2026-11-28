Group 1 is one commit, the cases and the handler together, the cases first shown failing against the handler at `trunk()` and recorded under `logs/`; group 2 is one commit; group 3 is one commit; group 4 follows the deploys. The cases build as `checks.<system>.package-ghq-shared-test-handler-boundary`, whose class `modules/checks/package-tests.nix` declares; runs on magnetite go through the build lock.

## 1. The writer reports an update a shallow boundary blocks

- [x] 1.1 Add `pkgs/by-name/ghq-shared/test_handler_boundary.py` with its check `package-ghq-shared-test-handler-boundary` (`package.nix`, `test-handler.nix`, `testSizes.checks` and the declared list in `modules/checks/package-tests.nix`): a depth-1 blobless clone whose `master` upstream moves onto a tag's commit it fetched at depth 1; a blobless clone with `master`'s whole history, and one holding only the first three of six commits, each with a later `master` commit fetched by id at depth 1, upstream's `master` past it; each blocked update must exit 1 with git's `fatal:` line, end its standard error with the two lines, log ` boundary=blocked`, and leave `.git/shallow`, `HEAD` and every ref outside `refs/remotes` as before with no new file under `.git` outside the object store, the logs and the remote-tracking refs but `FETCH_HEAD` and `ORIG_HEAD`; an update of a depth-1 clone whose `master` upstream rewrote must hold no `shallow boundary` line and no `boundary=` token. — verify: the blocked updates fail against `trunk()` on the lines and the token only, `logs/cam140-report-red-boundary-20261128-023419.log` (build: the script run against `trunk()`'s handler). Done.
- [x] 1.2 After `ghq get -u` of an existing clone exits non-zero, read `.git/shallow`, `@{upstream}`, `merge-base --is-ancestor` and `rev-list <upstream> ^HEAD` with lazy fetching off, and on a boundary in that listing add the two lines and the token (D1, D2). — verify: case 1.1 passes, `logs/cam140-report-green-boundary-20261128-023425.log`; the history and request scripts pass against the new handler (23.8 s and 47.6 s on stibnite) (build). Done.
- [x] 1.3 The repair the reply names hides nothing (D3): in the cases of 1.1, `deepen` with depth 1,000,000 must leave every branch and remote-tracking ref reaching at least what it reached, no boundary with a parent the clone holds, no boundary at all in the clone holding a root, the filter `blob:none`, and the next update exiting 0 at upstream's tip with no `boundary=` token; a twin clone deepened by 2 must lose `master`'s held history. — verify: these assertions pass against `trunk()`'s handler and the new one, the logs of 1.1 and 1.2 (build). Done.
- [x] 1.4 Build the changed handler checks on magnetite with `nix-build-locked`, `trunk()`'s request check alternated with this one's; the request check must not grow. — verify: `logs/cam140-report-magnetite-20261128-023836.log`: request 47.5 and 47.6 s against `trunk()`'s 47.3 and 47.5 s, history 22.2 and 22.7 s, boundary 6.2 and 6.2 s (build). Done.

## 2. ghq-sync and the skill name the safe deepen

- [x] 2.1 `ghq-sync.sh`'s usage text for `--deepen` and the skill `dependency-source-acquisition` say that a sized `--deepen` can hide held history, that `--deepen 1000000` hides none, and that it is the repair a blocked update names. — verify: `prek run --files` passes on both (command). Done.

## 3. The record of the automatic heal

- [x] 3.1 Carry `verify.md` unchanged into this change with a first line saying which design it verified; record in `design.md` what each verification found and why the change reports (D4). — verify: `openspec validate heal-updates-blocked-by-shallow-boundaries --strict` passes (command). Done.

## 4. After the deploys

- [ ] 4.1 After each host's deploy, the copies an update fails on with ` boundary=blocked` are repaired with the command the reply names, and their next update succeeds. — verify: the writer's exit log lines on magnetite, pyrite and stibnite (command).
