# Register fleet obligations implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** register the twelve host judges once beside their definitions and fold them in the machine checks; give every judge-over-fixtures check one constructor that reports per case; drop 26 unreachable inner system conditions; evaluate runtime tests and fixture checks against `fleetPkgs`; remove the unused `patched` channel with an ADR-0017 amendment; validate `observabilityHosts`, and type `envelopeBudget` once the change holding the collector service lands (tasks.md groups 1–7).

**Architecture:** a flake-parts option `fleetObligations` (not a flake output) collects `{ classes; failures; }` entries; `modules/checks/machines.nix` folds the entries for each configuration's class into one assertion. `flake.lib.judgeCases` wraps a check derivation in per-case assertions, and `flake.lib.mkJudgeCheck` applies it to the empty marker derivation the fixture checks already build. Every edit is drvPath-neutral except the docs pages, whose 28 consuming checks change (`drv-delta.txt`).

**Tech Stack:** flake-parts with import-tree; the NixOS module system (`lib.types.submodule`, `functionTo`); nixpkgs `import`, `appendOverlays` and the NixOS test framework's `node.pkgs`; `just drv-diff` and `just eval-cost` from `establish-refactor-oracle`.

**Spec:** `openspec/changes/register-fleet-obligations/`: `design.md` (D1–D10, alignment table), `specs/` (`fleet-obligation-registry-interface`, `fleet-package-set-interface`, `database-backup-interface`, `fleet-ingress-interface`, `world-assumptions` A330–A332), `tasks.md`, `drv-delta.txt`, `brainstorm.md`, `proposal.md`.

## Global Constraints

- One commit, parented on `main` at `9055ae0f1333`, accepted on one `just drv-diff <parent> <commit> openspec/changes/register-fleet-obligations/drv-delta.txt` (about 16 minutes). Each task group keeps its evidence by evaluating its attributes in one process per side against the join commit the working copy sits on.
- `drv-delta.txt` takes exact attribute paths only. The base allow-list (`modules/apps/drv-diff-base-allow.txt`) covers `gitleaks`, `treefmt` and `ntfy-tls-verification`. Checks that build or consume `packages.vanixiets-docs` change whenever a file under `packages/docs` changes; `checks.x86_64-linux.fleet-alert` changes whenever a `testSizes.checks` entry is added or removed (none is here); a test importing `${./x.nix}` changes with `x.nix`.
- Stay off the files another session holds: `vm-tests/{shared-reference-tree,perses-greptimedb}.nix`, `checks/fleet-alert.nix`, `checks/fleet-alert/**`, `checks/test-sizes.nix`, `clan/services/otel-collector/**`. Tasks 4.4, 6.1 and 6.2 wait on them.
- Never edit: the `testSizes` literal entries, their keys or how they are declared, apart from deleting an unreachable inner condition in 3.4; `checks/omnigent-workers.nix:16-21`; the literal oracles `omnigent-workers.nix` `hostMatrix`/`serverMatrix`, `omnigent-acp-spawn-env.nix:19-22`, `nix-builders-wiring.nix`, `sops-correspondence.nix:35-62`; the perSystem asserts in `machines.nix` apart from appending the key-list assert; `nixidy.nix`; the `nixpkgs`/`unstable` channel attributes; `perses-config.nix`; the `mkEvalCheck` users. No check is renamed.
- Registry keys are exactly the names machines.nix printed (design Context table); no judge's `flake.lib` export is renamed or changed. Obligation modules stay imported by `base`.
- A new check, if any, is declared `class = "medium"; measured = false;` in `testSizes` (`modules/README.md`); this change adds none.
- Mutants run in a throwaway copy of the tree under `/tmp`, never in the committed tree. A run expected to take over 5 minutes is announced first with its duration, what it proves that a cheaper run cannot, and what waits on it.

## Review Focus

- A judge that returns a non-string element breaks the fold's `functionTo (listOf str)` type. Every machine check evaluating unchanged is the witness that none does today.
- A judge that throws on a class it does not apply to, such as `resolverReloadObligations` reading darwin-only `system.activationScripts.script.text`: the fold must never call it for NixOS. Task 2.4's third mutant pins this.
- A fixture case set whose cases carry a field named `judge` for another purpose would be taken as a per-case judge override. None of the ten does.
- `fleet-ingress`'s import appended its own overlay; `fleetPkgs.appendOverlays` keeps the overlay order.
- A row in `observabilityHosts` built by `agent [ ] // { … }` that adds a new field intentionally (none today): the validator rejects it. That is the intended behavior, and the rule set in D8 is the one to extend.

## Interface contract

| Kind | Name | Defined in |
|---|---|---|
| flake-parts option | `fleetObligations : attrsOf { classes : nonEmptyListOf (enum [ "nixos" "darwin" ]) = [ "nixos" "darwin" ]; failures : name -> hostConfig -> [ str ]; }` | `modules/lib/fleet-obligations.nix` |
| machines.nix function | `withFleetObligations : class -> name -> machineConfig -> toplevel -> toplevel` | `modules/checks/machines.nix` |
| machines.nix assert | `attrNames config.fleetObligations == registeredObligations`, the literal twelve keys | `modules/checks/machines.nix` |
| Lib | `flake.lib.judgeCases : { name; judge; cases : attrsOf { problems : int; judge ? fn; … }; assertions ? [ { assertion : bool; message : str; } ]; } -> drv -> drv` | `modules/lib/judge-check.nix` |
| Lib | `flake.lib.mkJudgeCheck : pkgs -> args -> drv` = `judgeCases args (pkgs.runCommand args.name { } "touch $out")` | `modules/lib/judge-check.nix` |
| Lib | `flake.lib.observabilityHostProblems : attrsOf row -> [ str ]` | `modules/lib/observability-hosts.nix` |
| Option type (after 6.1) | `vanixiets.otelCollector.envelopeBudget : nullOr { storeUrl : str; notifiedUnits : attrsOf (listOf str); databases : attrsOf str; }` | the file holding the option once the collector change lands |

## Steps

- [ ] **Step 1 (tasks 1.1, 1.2):** record the parent and the base drvPaths of every attribute the groups compare, in one evaluation of the join commit (`logs/rfo-base-drvpaths-<ts>.json`).
- [ ] **Step 2 (tasks 2.1–2.3):** create `modules/lib/fleet-obligations.nix`; add `fleetObligations.<key>` beside each of the twelve exports, reading the same value the file exports (a `let`-bound judge directly, an inline export through `config.flake.lib.<name>.failures`); rewrite `machines.nix`'s fold as D2 specifies and append the key-list assert.
- [ ] **Step 3 (tasks 3.1–3.2, 3.4):** create `modules/lib/judge-check.nix`; migrate the ten fixture checks; drop the inner condition in the 26 modules of design D4; add the header line to `mk-eval-check.nix`.
- [ ] **Step 4 (tasks 4.1–4.3):** move the nine runtime-test modules, `omnigent-workers.nix` and `devin-worker.nix` to `fleetPkgs`.
- [ ] **Step 5 (tasks 5.1–5.2):** drop `patched`; amend ADR-0017 and the six pages; `just docs-build`.
- [ ] **Step 6 (task 6.3):** add `observabilityHostProblems` and wrap `otel-collector-config`'s derivation in `judgeCases`.
- [ ] **Step 7 (tasks 1.2–6.3 evidence):** evaluate the same attributes at the working copy (`logs/rfo-head-drvpaths-<ts>.json`); the only difference is `package-vanixiets-docs`. Run the mutants of 2.4, 3.3 and 6.3 in throwaway trees (`logs/rfo-mutants-<ts>.log`).
- [ ] **Step 8 (tasks 2.5, 4.5, 7.1):** after the orchestrator commits: `just eval-cost` on the three cost points, then `just drv-diff <parent> <commit> openspec/changes/register-fleet-obligations/drv-delta.txt`.
- [ ] **Step 9 (tasks 4.4, 6.1, 6.2):** once the change holding those files lands, move the two runtime tests to `fleetPkgs` and type `envelopeBudget`, with the `storeURL` mutant, as a second commit with its own oracle run.
- [ ] **Step 10 (tasks 7.2, 7.3):** archive order and the `delegate-fleet-deploys` note.
