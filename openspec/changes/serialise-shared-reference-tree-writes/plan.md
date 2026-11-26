# Serialise shared reference tree writes: implementation plan

> **For agentic workers:** Use superpowers:subagent-driven-development
> to implement this plan task-by-task.

**Goal:** Record the writer's per-repository lock and its protocol in `shared-reference-tree-interface`, and split the runtime test so that each half runs at least 15 s under its 60 s limit.

**Architecture:** Six added interface requirements and one modified one, each new scenario naming its witness (design D1). One node definition and script header in `modules/vm-tests/shared-reference-tree.nix`'s `mkTest`, two case sets, two `vmTests` attributes, both `small` (design D3, D4).

**Tech Stack:** OpenSpec 2.2.0, NixOS test driver, `ghq-shared`'s handler test.

Grounding: per-case times from `logs/ghq-writer-lock-vmtest-pyrite-20261126-170617.log` and `…-171209.log` (brainstorm Q3); witness names read from `pkgs/by-name/ghq-shared/test_handler.py` and the test module as merged in `ebd5daae2`.

---

## Task 1: Split the runtime test (tasks 1.1 to 1.3)

- [x] **Step 1:** Make `mkTest` take `name` and `cases`; keep the node, the script header and `${prelude}` in it, and interpolate `${cases}` after the prelude.
- [x] **Step 2:** Move the cases from root resolution to the fsmonitor threat, except tags and migration, into `accessCases { control ? "touch" }`; move tags and migration into `migrationCases` after a precondition `ghq-sync {URL} && ghq-sync --full {P}`.
- [x] **Step 3:** Move `import hashlib` into the access cases and `import json`, `import re` into the migration cases, so the driver's lint passes on each script.
- [x] **Step 4:** Define `vmTests.x86_64-linux.shared-reference-tree` (with both `passthru.mutations`, each building `accessCases`) and `vmTests.x86_64-linux.shared-reference-tree-migration`; declare both in `testSizes.vmTests` as `small`.
- [x] **Step 5:** Compare the evaluated scripts with `main`'s line by line (`nix eval --raw .#vmTests.x86_64-linux.<test>.driver.testScript`).
- [x] **Step 6:** Copy the commit to pyrite (`nix flake archive --json --to ssh-ng://pyrite.vanixiets.internal "git+file://$PWD?rev=<commit>"`), build both `.driver`s, then each test three times with `--builders ''`, the second and third with `--rebuild`, teeing to `logs/srt-split-<test>-pyrite-<timestamp>-run<n>.log`.
- [x] **Step 7:** Build each mutant on pyrite and read the failing subtest from its log.
- [x] **Step 8:** Write the measured times beside `testSizes.vmTests`.

## Task 2: Spec delta (tasks 2.1, 2.2)

- [x] **Step 1:** Write `specs/shared-reference-tree-interface/spec.md` with the added requirements and the modified evidence requirement, each requirement's text under 500 characters.
- [x] **Step 2:** `openspec validate serialise-shared-reference-tree-writes --strict`.
- [x] **Step 3:** Check each quoted case comment and subtest name against the sources, comment lines joined.
- [x] **Step 4:** `rg -n 'shared-reference-tree' --hidden -g '!logs' -g '!openspec/changes/archive'` and record what each hit names.

## Task 3: Checks and hooks (tasks 1.2, 3.2, 3.3)

- [x] **Step 1:** On magnetite (`/proc/pressure/memory` `some avg60` at most 20), from a `git clone --shared` of the commit, map `checks.x86_64-linux` to drvPaths at the commit and at `trunk()` and list those that differ.
- [x] **Step 2:** Holding `/tmp/cam124-build.lock` as root, build each differing attribute.
- [x] **Step 3:** `prek run --files <changed files>`.
