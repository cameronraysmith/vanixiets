# Shape the repository for its readers: implementation plan

> **For agentic workers:** Use superpowers:subagent-driven-development to implement this plan task by task; groups 1, 2, 4 and 7 have disjoint files apart from those design D5 names, and group 3 follows group 2 (both edit `checks/machines.nix`).

**Goal:** no host list is kept by convention alone, any configuration's composition is printed by one command with its routes judged in the machine checks, the tree states one placement rule per kind of addition, package priority and then order stop depending on import depth, and the reader measure confirms it. Covers tasks.md groups 1-10.

**Architecture:** the registry (`flake.fleet.hosts`) gains inventory tags and descriptions, and three host lists are computed from it; the cloud and observability tables keep their data and gain key checks. Routes are read from each evaluated configuration's `graph` (A386) by a classifier in `flake.lib`, printed by `just composition` and judged by a fleet obligation. System-path collisions are settled by explicit priority, then `environment.systemPackages` and `home.packages` are re-declared with a sorting `apply` (A384).

**Tech Stack:** flake-parts `flake.modules`, import-tree, the NixOS module system (`graph`, `definitionsWithLocations`), clan-core inventory, `fleetObligations`, `flake.lib.mkStructuralCheck`, `just drv-diff`, `just eval-cost`, `just comment-gate`, `nix-stock`, `drv-order-trace.py` from `name-the-parts-of-base-and-ai`.

**Spec:** this directory: `design.md` (D1-D5), `specs/repository-shape`, `specs/repository-shape-interface`, `specs/world-assumptions` (A383-A386 and designations), `tasks.md`.

## Global Constraints

- The design's questions are resolved (design Resolved Questions); implementation starts with the steps that change no machine, then the second pass (5a, 5b, 6, 6b, 6c) and the deploy.
- One commit per pull request; land groups 1, 2, 4 and 7 in any order, 3 after 2, then 5a, 5b, then 6, then the deploy (8).
- `just drv-diff` (about 16 minutes) is run by the operator; the implementer returns the command and the allow-list.
- Code comments carry no design, task or assumption identifiers, dates, measurements, log paths or change history; `just comment-gate <rev>` passes before each publish.
- Evaluate with `nix-stock`; check `pgrep -fl nix-eval-jobs` first and wait while one runs.
- A check's name is a literal; it reads modules or configurations only in its value.
- A difference `drv-order-trace.py` rejects stops the step and becomes an open question in design.md; it is never added to an allow-list.
- Before starting any build or check expected to exceed five minutes (building every enabled host's system path in 5.2 and 5.9 is the candidate), report its expected duration, what it proves that a cheaper run cannot, and what waits on it.

## Grounding

- nixpkgs `lib/modules.nix:410` (`graph = (doCollect { }).graph`) and `:616-645` (`toGraph`: `key`, `file`, `imports`, `disabled`), A386; the deferred-module merge's `, via option` file string, A383; `lib/modules.nix:1157-1166`, A384. Re-read at the locked revision before tasks 3.1 and 5.4.
- `nixos/lib/eval-config.nix` (`withExtraAttrs` merges with `//`), nix-darwin `eval-config.nix` (`withExtraAttrs eval`), home-manager `modules/default.nix` (`withExtraAttrs rawModule`): each keeps `graph`. Integrated homes expose none.
- clan-core `lib/inventory/distributed-service/service-module.nix:714-745,830-840` (`perMachine` maps over every machine of a service), A385.
- `modules/checks/machines.nix:57-75`: judges are called as `entry.failures name machineConfig`; the configuration's `graph` is not passed today.
- NixOS `nixos/modules/config/system-path.nix:211` and nix-darwin's system path set `ignoreCollisions = true`; home-manager's `home-manager-path` does not (A376).
- Acceptance values: the graded E1 key (80 names for magnetite) and the 20 standalone homes pinned in `checks/structure/flake-shape.nix:47-70`.

## Task 1: Measure kit and misleading texts

- [ ] **Step 1:** Create `docs/notes/development/reader-measure/README.md` with the protocol and its two arms.
- [ ] **Step 2:** Write `lookup.yaml` and `hard.yaml` (keys from the graded baseline; Q1's key names the omnigent clan service route).
- [ ] **Step 3:** Write `grade.py`: reads transcripts, counts distinct files and searches, grades against keys, prints per target the count of runs meeting it, the baseline and the sample size.
- [ ] **Step 4:** Run `grade.py` on the baseline transcripts; its output equals design D1's baseline column.
- [ ] **Step 5:** Correct the texts of task 1.2; run `just comment-gate`; commit.

## Task 2: Host lists

- [ ] **Step 1:** In `modules/lib/hosts.nix`, add `tags` (listOf str) and `description` (str); move each host's values from `clan/inventory/machines.nix`.
- [ ] **Step 2:** Compute the inventory from the registry:

```nix
flake.clan.inventory.machines = lib.mapAttrs (name: h: {
  inherit (h) tags description;
  machineClass = h.class;
} // lib.optionalAttrs (h.class == "nixos") { deploy.targetHost = h.targetHost; })
  (lib.filterAttrs (_: h: h.system != null) hosts);
```

  Compare with the parent's value; delete the assert at `checks/machines.nix:78-79`.
- [ ] **Step 3:** Derive `machineAnchors`; derive `logins` if equal, else add its key check.
- [ ] **Step 4:** Add the cloud and observability key checks with phantom entries; the `structure-fleet` phantom.
- [ ] **Step 5:** Write the onboarding guide's section; run the `basalt` mutant tree.
- [ ] **Step 6:** `just comment-gate`; commit; return the drv-diff command and allow-list.

## Task 3: Composition command and route judge

- [ ] **Step 1:** Confirm `graph` on one NixOS, one darwin and one standalone home configuration (task 3.1).
- [ ] **Step 2:** Add `modules/lib/composition.nix`: a pure classifier `routes :: class -> graph -> [ { name; route; parentFile; } ]` that recognises a named module by a `file` ending `, via option flake.modules.<class>.<name>`, and takes its route kind from its nearest named or host ancestor: `host`, `base`, `include`, `clan`, `generated`, anything else `unknown`.
- [ ] **Step 3:** Add the `just composition <name>` recipe: `nix-stock eval --raw` of a rendering over `routes`, choosing `nixosConfigurations`, `darwinConfigurations` or `homeConfigurations` by name; for a home, also the systems it is built for.
- [ ] **Step 4:** Check `just composition magnetite` against the E1 key.
- [ ] **Step 5:** Measure the judge's cost on one host (task 3.3); report before registering if the fleet total would grow by more than five minutes.
- [ ] **Step 6:** In `checks/machines.nix`, pass `graph` to judges that declare `needsGraph = true`; register `composition-routes` (failures for every `unknown` route) and its fixture check with a mutant.
- [ ] **Step 7:** `just comment-gate`; commit; return the drv-diff command.

## Task 4: Placement rules

- [ ] **Step 1:** Rewrite `modules/README.md` per task 4.1.
- [ ] **Step 2:** Add `modules/checks/README.md`; edit the skill source; build the plugin output.
- [ ] **Step 3:** Edit the `secrets.nix` header and `darwin-workstation.nix:11-13`; `just comment-gate`; commit.

## Task 5: Priority, then order

- [ ] **Step 1:** Record the baseline (task 5.1).
- [ ] **Step 2:** Report the expected duration of building every enabled host's system path; then list the equal-priority collisions with differing contents (task 5.2).
- [ ] **Step 3:** Mark each winner; rebuild; compare content hashes; commit as 5a.
- [ ] **Step 4:** Add `modules/system/package-order.nix`:

```nix
{ lib, ... }:
let
  byName = a: b:
    let na = lib.getName a; nb = lib.getName b; in
    if na == nb then a.outPath < b.outPath else na < nb;
  sortPackages = { options.environment.systemPackages = lib.mkOption { apply = lib.sort byName; }; };
in
{
  flake.modules.nixos.base-package-order = sortPackages;
  flake.modules.darwin.base-package-order = sortPackages;
  flake.modules.homeManager.package-order = {
    options.home.packages = lib.mkOption { apply = lib.sort byName; };
  };
}
```

  List `base-package-order` in both `base` lists; add `package-order` to `home-manager.sharedModules` and `flake.lib.mkHome`; remove the `lib.mkAfter` at `lib/host-users.nix:166`.
- [ ] **Step 5:** Key the gh-dash bindings; write the overlay list; add the activation slots.
- [ ] **Step 6:** Run `drv-order-trace.py` on every changed toplevel and home; build and compare profiles by content.
- [ ] **Step 7:** `just comment-gate`; commit as 5b; return the drv-diff command and allow-list.

## Task 6: Parts lists resumed, then moves

- [ ] **Step 1:** Rebase `name-the-parts-of-base-and-ai`'s darwin and `ai` commits onto 5b; confirm drvPaths equal.
- [ ] **Step 2:** Split the four two-aggregate files.
- [ ] **Step 3:** Move the two darwin halves out of `nixos/`; confirm drvPaths equal; `just comment-gate`; commit.

## Task 7: People's literals

- [ ] **Step 1:** `username` default and aggregate default in `modules/home/users/lib.nix`.
- [ ] **Step 2:** The per-user content constructor; rewrite five users; drvPaths equal.
- [ ] **Step 3:** The clan user-instance constructor; rewrite three instances; ssh keys from the people registry at the four sites; inventory equal; `just comment-gate`; commit.

## Task 8: Deploy (operator)

Per tasks 8.1-8.5: cinnabar, magnetite, pyrite, stibnite, argentum, rosegold; the disabled hosts and blackphos are recorded, not deployed.

## Tasks 9 and 10: Close-out and integration verification

Per tasks 9.1-10.4; the re-measure is run by fresh agents with the kit of task 1, in both arms.
