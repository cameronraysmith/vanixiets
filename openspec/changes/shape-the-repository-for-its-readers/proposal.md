---
linear_story_id: CAM-142
linear_story_identifier: CAM-142
linear_story_title: "Shape the repository for the people and agents who read it"
linear_story_url: https://linear.app/cameronraysmith/issue/CAM-142/shape-the-repository-for-the-people-and-agents-who-read-it
linear_story_state: Todo
linear_team: CAM
linear_project: den-ready-fleet
last_synced_state: Todo
last_synced_at: "2026-11-28T00:44:46Z"
review_round: 0
max_review_rounds: 3
attempt_log:
  - { at: "2026-11-28T00:44:46Z", transition: "Backlog->Todo", outcome: "posted", note: "Issue CAM-142 created in Todo in project 06049a4f18a4 (Den-ready fleet architecture), no label, with description seeded from proposal.md's Why and What Changes, and the bind comment posted; state and project confirmed by read-only view" }
---

## Why

On main `1e8fb9ff6d66`, fresh read-only agents answered 20 of 20 lookups right in a median of two files, so layout is not the cost. Three runs per task showed the costs: a new host goes into 12 host lists, 4 unenforced, and every run missed a step; listing a host's composition took 26-33 files; a home's systems are not readable without evaluation; checks and hand-entered secrets each have two conventions. A full re-layout would move none of these. This change takes the smallest shape the evidence supports.

## What Changes

**Host lists derived or checked**
- From: a host is written in 12 lists outside its own directory, 4 kept by convention only, and the generated steps (keys, bridge re-encryption, deployer group link, topology) are listed nowhere.
- To: tags, description, inventory machines, sops anchors and ssh logins derived from the registry; the cloud and observability tables keep their data and gain key checks; the onboarding guide lists each generated step with the check that fails until it is done; the justfile's two host lists are deleted in favour of the registry's class; the one list left (`ztRecords`, removed by the mesh migration) is named there; a new server's `serverType` and `stateVersion` are required, and its boot mode follows its server type.
- Impact: no host or home changes.

**Composition on request**
- From: a host's named modules arrive by several routes in several alias forms, with no view; a home's systems are recorded only in a pin.
- To: `just composition <host-or-home>` prints each named module with its route, read from the evaluated import tree, and a home's systems; a fleet obligation in the machine checks fails when a named module arrives by a route kind the entry point does not list.

**Placement rules**: the modules README states one rule per kind of addition; the checks README and the checks skill one check ladder with its one exception; the secrets module one shape for a hand-entered secret. Texts that misled lookups are corrected.

**Priority, then order**: equal-priority packages that provide differing files at one path were to get explicit priorities matching today's winners; measured on every host, none provides one, so no priority was set. System and home package lists and the Brewfile's taps, brews and casks are sorted, the overlay order is one named list, the review bindings are keyed and the darwin activation snippets take their slots from one table. Every configuration changes order only, apart from two texts delivered into homes and pyrite's loss of one part.

**Parts lists resumed**: the darwin `base` and `ai` steps of `name-the-parts-of-base-and-ai` land after the order step with their names and change no derivation; then the darwin halves leave `nixos/`.

**People's literals**: usernames, aggregate lists, the per-user content recipe and the clan user instances are derived from the people registry.

**Measure**: lookups bound regressions; the harder tasks set per-run targets, in a tree arm (as at the baseline) and a commands arm (with the named read-only commands). Had the harder tasks come out good on today's tree, the case for restructuring would have rested only on the architectural principles; they did not, but only for the costs named above.

## Capabilities

### New Capabilities
- `repository-shape` (behavioral): no host list kept by convention alone, each configuration's composition stated on request with known routes, one placement rule per kind of addition, and restructuring that changes nothing delivered beyond the differences each step declares: order, two texts delivered into homes, and pyrite's loss of one part; no priority pins were needed.
- `repository-shape-interface` (interface): the derived and checked host lists, the onboarding steps and their checks, the composition command and the route obligation, the priority and order mechanisms, the documented rules, and the reader measure; trust boundary stated.

### Modified Capabilities
- `world-assumptions` (world): adds A383-A386 (definition provenance through `flake.modules`; re-declaring an upstream list option with `apply` alone; a clan service's per-machine module reaching every machine of its instances; the import tree recorded on an evaluated configuration) and designations for the terms this change introduces.

## Impact

- Code: `modules/lib/hosts.nix`, `clan/inventory/machines.nix`, `checks/sops-correspondence.nix`, `home/core/ssh.nix`, `checks/machines.nix`, `checks/structure/flake-shape.nix`, new key checks and route judge, a `just composition` recipe, `modules/README.md`, a new `modules/checks/README.md`, the checks skill source, `system/secrets.nix` and `darwin/darwin-workstation.nix` headers, package priority marks and sort modules, `nixpkgs/compose.nix`, `home/development/gh-dash.nix`, `modules/home/users/**` and `clan/inventory/services/users/*`; open changes touching the same files are named per step in design D5.
- Derivations: the order step changes every host and home (order, and two texts delivered into homes), and the step importing parts only where used changes pyrite; no priority step was needed, since no equal-priority collision was measured; every other step is accepted on a comparison changing only declared checks.
- Deploy: once, after the last step, to the enabled hosts (cinnabar, magnetite, pyrite, stibnite, argentum, rosegold) and the standalone homes in use; electrum, galena and scheelite are disabled and blackphos has no machine, so their derivations change and nothing is deployed.
- Plans: `name-the-parts-of-base-and-ai` steps 2 and 3 are held until the order step lands; the overlay seam stays with `migrate-mesh-to-tincr`.
