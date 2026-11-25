---
title: Bumping a package
description: "Checklist for moving a pkgs/by-name derivation to a new upstream release: resolve the release, realize it from its pin.json or run its updater, recheck carried patches, build and test on the right builder, review the diff and route one commit."
---

Use this checklist to move a derivation under `pkgs/by-name/<package>/` to a new upstream release.
A bump is done when every pin was derived by a tool (none written by hand), the package and everything that consumes it build, and someone other than the author reviewed the diff.

## 1. Resolve the release

- [ ] Name the target version. Use the latest stable release unless a specific version is requested, and skip pre-releases (alpha, beta, rc, `next` dist-tags).
- [ ] Find the release source in the derivation: its `src` fetcher (GitHub release, npm tarball, crates.io and so on), its `meta.changelog`, and the `# source:` comment if there is one.
- [ ] Read the release notes or changelog for every version between the current pin and the target. When the major version changes, or the minor version changes below 1.0, expect breaking changes and list them.

## 2. Realize a version

- [ ] Check whether the package is pinned. A pinned package has `pkgs/by-name/<package>/pin.json`, which declares its version, the hash of every artifact and the companion files that move with it, and realize-pin derives all of them; the rest of this step for a pinned package is the realization below.
  - Renovate, which runs hourly on magnetite, proposes each new release of a pinned package in a pull request of its own, on the branch `renovate/<package>` and titled `chore(deps): update <package> to <version>`. Its commit already ran realize-pin, so review it with steps 4 to 6 rather than opening a second change.
  - To realize a version by hand, run `just update-package <package> <version>`, which runs `nix run .#realize-pin -- <package> <version>`. realize-pin writes `version` first, then each hash and companion file as it derives it, and `realizedVersion` last.
  - `checks.<system>.pin-realized` fails on any `pin.json` whose `realizedVersion` is missing or differs from its `version`, so a run that stopped part-way fails the required checks rather than landing a pin with old hashes. Rerun realize-pin; never edit a pin's hashes by hand.
  - A pinned package's `passthru.updateScript`, where its builder supplies a default one (`buildPythonApplication` does), is not its updater: it does not write `pin.json`.
  - greptimedb-bin gets no branch until its update is approved on Renovate's Dependency Dashboard, because it runs as `services.greptimedb.package` on magnetite and a new release may change its storage format. Before approving, and again before enqueueing, read the upstream release notes for storage-format and compatibility changes, run `vmTests.greptimedb-pipeline`, `vmTests.fleet-ingress` and `vmTests.devloop-ingest`, and plan magnetite's deploy with a rollback that accounts for data the newer version wrote being unreadable by the older one. Its pin exists only on x86_64-linux, so realize it by hand on magnetite.
- [ ] For a package without `pin.json`, list every pin that has to change: the version (in `package.nix` or a sibling `manifest.json`), the source hash, per-platform binary hashes, and the dependency-closure hashes (`npmDepsHash`, `cargoHash`, `vendorHash` and similar).
- [ ] List what the derivation carries besides pins: patches, `postPatch` repairs, wrapper flags and environment variables, `--legacy-peer-deps`-style flags, and comments that justify them with a version number.
- [ ] Find the consumers: `rg -n '<package>' modules --glob '*.nix'` finds home-manager and NixOS modules, settings keys, wrappers and checks that build or run it.
- [ ] For a package without `pin.json`, find the updater, in this order:
  - a custom `update.sh` in `passthru.updateScript`, run with `just update-package <package>` or `nix run .#update-<package>` (`modules/apps/updates.nix`); `ls pkgs/by-name/*/update.sh` lists the packages that still carry one;
  - `nix-update --flake <package>` for packages that use `nix-update-script`;
  - none: the bump is manual, so derive each hash from a mismatch build (set the hash to `lib.fakeHash`, build, copy the `got:` value). Never type a hash in.

Changed 2026-11-25 (CAM-124): a package with `pin.json` is realized by realize-pin, by hand or in Renovate's pull request, and the updater lookup above applies only to packages without one.

## 3. Run the updater

- [ ] For a package without `pin.json`, run the updater for the target version. Updaters that end with a `nix build` build for the local system. On a Mac, stop before that step and build on magnetite (step 4) instead of building aarch64-darwin locally.
- [ ] Check the diff touches only the pins from step 2, plus whatever the updater regenerates (a repairs patch, a lockfile). For a pinned package, the diff touches only its `pin.json` and the companion files that pin declares (an `apm.yml` under `modules/home/ai/plugins`, its `hashes.json`, or `pkgs/by-name/apm-skills-compose/skills.json`).
- [ ] Every version-keyed hash changed. A dependency-closure hash may stay the same only if a build in step 4 confirms it.

## 4. Build and test

- [ ] Build the package for x86_64-linux on magnetite:
  `nix build -L --no-link --eval-store auto --store ssh-ng://magnetite.zt .#packages.x86_64-linux.<package>`, or several attributes at once with `nix-fast-build --remote magnetite.zt --skip-cached --no-download`.
  If a closure hash changed, the first build fails with `got: sha256-…`; copy that value into the derivation and build again.
- [ ] Run the package's tests: `checks.x86_64-linux.package-<package>` and `checks.x86_64-linux.package-<package>-*` (its `passthru.tests`, listed in `modules/checks/package-tests.nix`).
- [ ] Run every check that builds or runs the package (`rg -ln '<package>' modules/checks modules/vm-tests`). Run VM tests on pyrite, which has KVM.
- [ ] Smoke-test the built binary: `--version`, `--help`, and one command that needs no network or credentials.
- [ ] For hosts that are aarch64-darwin, instantiate their configurations without building them: `nix eval .#darwinConfigurations.<host>.config.system.build.toplevel.drvPath`.

## 5. Recheck what the derivation carries

- [ ] For each patch or repair, check whether the new release still needs it. Drop the repairs upstream has fixed, keep or adapt the rest, and record which applies to each.
- [ ] Update comments that cite a version or an upstream behavior the release changed.
- [ ] For each breaking change from step 1 that affects a consumer from step 2 (renamed binaries, settings keys, environment variables, directory layouts, removed commands or APIs), adapt the consumer in the same commit or record why it is unaffected.
- [ ] If the package ships skills that a module delivers, compare the delivered tree with upstream at the release tag. If local skills cite the package's behavior, recheck those claims against the new version.

## 6. Review and route

- [ ] Have the diff reviewed against the evidence (build logs, check results, the changelog), not against the author's summary.
- [ ] Run `prek` on the changed files.
- [ ] Commit the bump as one change titled `chore(deps): update <package> to <version>`, with the breaking changes and how each was handled in the body. In the jj development join, route only your paths into the change with `jj squash --into <change> --use-destination-message --keep-emptied <paths>`.
- [ ] Note which hosts the deploy changes and whether running sessions of the package are affected.
- [ ] If the new release migrates a service's database on first start (an Alembic, Diesel or similar upgrade, for example omnigent on magnetite), take a fresh `pg_dump -Fc` of that database right before the deploy. Store it under `/var/backup/postgresql/`, mode 0600, and record its schema revision. The nightly backup is up to 24 h old, and a migration usually cannot be rolled back without a dump.
