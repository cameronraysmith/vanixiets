# Verification Report

**Change**: `finish-fleet-package-set-and-budget-typing`
**Verified at**: `2026-11-27 09:29 UTC`
**Verifier**: subagent session, cold read of the commit, the working copy and the recorded logs; no evaluation was run for this report

The change is the commit of jj change `msoxoszsxlos`, `a47c50a0463b6888f893430fe38977bea5f594c0`, parented on `main` `ec2c878bf4bc`. Its code is four files: `modules/vm-tests/perses-greptimedb.nix`, `modules/vm-tests/shared-reference-tree.nix`, `modules/clan/services/otel-collector/flake-module.nix` and `modules/checks/machines.nix`. The acceptance oracle ran on `c21a2dc87701 -> ccf786c25f99`; since then the commit was rebased onto a `main` that moved by OpenSpec text files only (`serve-omnigraph-from-local-disk`'s `tasks.md` and `verify.md`, the same two files in `c21a2dc87701..ec2c878bf4bc`) and its description reworded. `jj interdiff` of the rewritten commit against `79ac9e23c6ff` (the commit after the rebase) is empty.

---

## 1. Structural Validation (`openspec validate --all --json`)

- [x] All items of this change report `"valid": true`

**Result**:

```text
totals: 85 items, 82 passed, 3 failed (change 42/39/3, spec 43/43/0)
finish-fleet-package-set-and-budget-typing: valid (also `openspec validate finish-fleet-package-set-and-budget-typing --strict`)
```

The three failures are other changes, which this change does not touch:

| Item | Type | Issues |
|---|---|---|
| compose-hosts-from-cohesive-aspects | change | not this change |
| stand-up-gitea-mq-on-magnetite | change | not this change |
| stand-up-nixbot-on-magnetite | change | not this change |

---

## 2. Task Completion (`tasks.md`)

- [x] All `- [ ]` have been changed to `- [x]`

9 of 9 tasks are checked, each with its evidence: 1.1–1.2 baseline, 2.1–2.2 and 3.1 by drvPath comparison (`logs/ffp-{base,head}-drvpaths-*.json`, `logs/ffp-{base,head}-hosts-20261127T0902Z.json`, `logs/ffp-assertmsg-drvpaths-20261127T0906Z.log`), 3.2 and 4.1–4.2 by mutant (`logs/ffp-mutants-20261127T0904Z.log`), 5.1 by the full `just drv-diff` (`logs/drv-diff-c21a2dc87701-ccf786c25f99-20261127T090914Z`, PASS on the first judgement, 963.6 s).

**Incomplete tasks**:

| Task | Reason incomplete | Blocks archive? |
|---|---|---|
| — | — | — |

---

## 3. Delta Spec Sync State

| Capability | Sync status | Notes |
|---|---|---|
| fleet-package-set-interface | pending sync | ADDED "Runtime tests evaluate against the fleet package set" is not yet in `openspec/specs/fleet-package-set-interface/spec.md` |
| fleet-ingress-interface | pending sync | ADDED "The envelope budget has a declared shape" is not yet in `openspec/specs/fleet-ingress-interface/spec.md` |

### Requirement and scenario trace

**Runtime tests evaluate against the fleet package set** (`fleet-package-set-interface`)

- Code: `modules/vm-tests/perses-greptimedb.nix:44,58,175` and `modules/vm-tests/shared-reference-tree.nix:32,36,55` take `fleetPkgs` from `perSystem` and set `node.pkgs = lib.mkForce nodePkgs` with `nodePkgs = fleetPkgs`. `fleetPkgs` is defined at `modules/nixpkgs/base-defaults.nix:60-67`.
- Scenario "A runtime test's node package set": `modules/vm-tests/greptimedb-pipeline.nix:68,99` binds and forces `fleetPkgs`; `greptimedb-bin` and `ntfy-send` are in `pkgs/by-name`, which the fleet overlay carries. Covered by reading, unchanged by this change.
- Scenario "No runtime test instantiates a package set of its own": `rg -n 'import inputs\.nixpkgs' modules/vm-tests` exits 1 with no match (run for this report). Reading every `modules/vm-tests/*.nix`: eleven modules bind `nodePkgs = fleetPkgs` (or `fleetPkgs.appendOverlays`, `fleet-ingress.nix:80`) and force it as `node.pkgs`; none instantiates a package set. `tincr-mesh.nix:26` and `tincr-mesh-partition.nix:31` import nixpkgs' `nixos/lib`, the test library, not a package set; the scenario's pattern does not match them, and the change's wording now says "instantiates a package set" rather than "imports nixpkgs" for this reason. Covered.
- Scenario "The moved tests keep their derivations": `vmTests.x86_64-linux` 21 identical and `vmTests.aarch64-linux` 3 identical in the full drv-diff, and the per-attribute comparison in tasks 2.1–2.2 (every attribute the two modules define, mutations included). Covered.
- Package-set difference: `fleetPkgs` permits one insecure package (`permittedInsecurePackages = [ "radicle-node-1.10.3" ]`, `modules/nixpkgs/base-defaults.nix:48,60-67`) that the two removed imports did not. Under A330 this only decides whether evaluating that package throws; the drv-diff shows both tests' derivations unchanged regardless.

**The envelope budget has a declared shape** (`fleet-ingress-interface`)

- Code: `modules/clan/services/otel-collector/flake-module.nix:165-182`, `nullOr (submodule { storeUrl : str; notifiedUnits : attrsOf (listOf str); databases : attrsOf str; })`, read at `:631` and rendered by `modules/lib/otel-envelope.nix:398` (`budget.storeUrl`).
- Scenario "A writer misspells a field": task 3.2, `logs/ffp-mutants-20261127T0904Z.log:25`, ``The option `vanixiets.otelCollector.envelopeBudget.storeURL' does not exist``. Covered.
- Scenario "The existing writers": the writers are `modules/clan/services/otel-collector/flake-module.nix:1729-1733` and `modules/vm-tests/fleet-ingress.nix:2213`, both setting exactly the three fields. Both evaluate and keep their derivations: `checks.x86_64-linux.nixos-magnetite` and `vmTests.x86_64-linux.fleet-ingress` are identical in task 3.1 and in the full drv-diff, so the `otel-envelope` unit's `ExecStart` is unchanged. Covered (by derivation identity; `ExecStart` was not read separately).

**Mutants for scenarios other capabilities already state** (design D3, not requirements here)

- `fleet-host-registry` "A host disappears from the registry": task 4.1; the first run failed without naming the host, the assert at `modules/checks/machines.nix:78-79` now names it, and the rerun fails with `only in the inventory: [electrum]` (`logs/ffp-mutants-20261127T0904Z.log:194,218`). The assert change leaves `structure-fleet` and `nixos-cinnabar` unchanged (`logs/ffp-assertmsg-drvpaths-20261127T0906Z.log`).
- `database-backup-interface` "a database is added without a backup": task 4.2, `logs/ffp-mutants-20261127T0904Z.log:103-104`.

---

## 4. Design / Specs Coherence Spot Check

| Sampled item | design description | specs correspondence | Gap |
|---|---|---|---|
| D1 | the two tests bind `nodePkgs = fleetPkgs`; only `permittedInsecurePackages` differs (A330) | "Runtime tests evaluate against the fleet package set", drvPaths resting on A330 | none |
| D2 | submodule type; a field the record does not have fails at the option | "The envelope budget has a declared shape", both scenarios | none |
| D3 | two mutants as tasks; the registry assert names the hosts that differ | stated by `fleet-host-registry` and `database-backup-interface`; no delta here, as D5 says | none |
| D4 | one commit on `main`, accepted on one `just drv-diff` | task 5.1 | none |

**Drift warnings** (non-blocking):

- The requirement binds only runtime tests "that set" their nodes' package set. Seven runtime tests set none themselves: `caddy-root-from-vars`, `tuwunel-server-name-guard`, `zerotier-mss-clamp-runtime` (two tests) and `postgresql-backup-restore` use `pkgs.testers.runNixOSTest`, whose nodes get the perSystem `pkgs` (`modules/nixpkgs/per-system.nix:18-28`, a separate instance with `config.nixpkgsOverlays`); `tincr-mesh` and `tincr-mesh-partition` run `nixosLib.runTest` with no `node.pkgs`, so their nodes are evaluated against the test framework's own instance. The requirement holds as worded, but the spec's trust-boundary comment ("runtime-test nodes are evaluated against the same nixpkgs instance the fleet's hosts and homes use") reads wider than that. Recommendation: narrow the comment at `specs/fleet-package-set-interface/spec.md:5` to the tests that set `node.pkgs`, or track moving those seven in a later change.
- The working copy's `modules/vm-tests/shared-reference-tree.nix` differs from the commit outside this change's hunk: the commit's `extraSpecialArgs.flake` lines (`:66-68` at the commit) and the `.lazygit.yml` test-script assertions differ in the working copy, because two other changes in the development join (`oywttoqwttlt`, `nzvnkwwuvxvx`) edit the same file. This change's hunk (`fleetPkgs` at `:32`, `nodePkgs = fleetPkgs` at `:36`) is present in both. The other three files match the commit exactly.

---

## 5. Implementation Signal

- [x] All of this change's code is committed (`msoxoszsxlos`); the working copy holds only other changes' edits and this report's text
- [ ] All related commits have been pushed (no remote bookmark points at or descends from the commit)

**Commit range**: `ec2c878bf4bc..a47c50a0463b`

---

## 6. Front-Door Routing Leak Detector (warning, non-blocking)

- [x] No files: `ls docs/superpowers/specs/*.md` lists nothing

---

## 7. Deferred Manual Dogfood vs Automated Test Equivalence

`plan.md` has no `[~]` rows. Nothing deploys a host, and no runtime test was run: the change claims derivation identity at evaluation, and the spec's trust boundary states that equal derivations do not show equal run-time behaviour.

---

## 8. Designation Lint and Discharge Coherence

No capability is tagged `behavioral` or `world`, so 8a has no input.

| Requirement | Discharged by (S) | Under (W) | Status |
|---|---|---|---|
| Runtime tests evaluate against the fleet package set | `rg` over `modules/vm-tests` (no match); full drv-diff, `vmTests` 21 + 3 identical | A330 | discharged; A330 `not violated` (the derivations of the two moved tests are unchanged although `fleetPkgs` permits one more insecure package) |
| The envelope budget has a declared shape | `storeURL` mutant (task 3.2); `nixos-magnetite` and `fleet-ingress` identical (task 3.1, drv-diff) | none | discharged |

8c: both requirements are interface requirements naming option types, attribute paths and derivations, which the machine observes; no violation.

---

## Overall Decision

- [ ] (pass) PASS — may proceed to finishing-a-development-branch and archive
- [x] (warn) PASS WITH WARNINGS — may proceed to subsequent steps but note: the requirement's scope excludes seven runtime tests that set no node package set, and the spec's trust-boundary comment reads wider (section 4); the working copy's `shared-reference-tree.nix` carries other changes' edits beside this change's hunk; the commit is not pushed; both delta specs are pending sync
- [ ] (fail) FAIL — return to the failed artifact, correct it, then re-run verify

**Next step**:

Review, then sync the two delta specs and archive with the commit landing on `main`.
