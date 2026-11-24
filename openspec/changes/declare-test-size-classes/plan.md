# Declare test size classes implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** every check and runtime test declares its size class beside its definition, runtime tests fail at their class limit, the gate refuses unclassed, enormous and unexplained large checks, slow builds reach the operator as a low-priority alert, enormous tests run weekly on pyrite, and the two enormous container tests are split so their routing and ingest assertions are medium (tasks.md groups 1–7).

**Architecture:** a perSystem option `testSizes` holds literal entries defined in each check or test module; `modules/vm-tests/default.nix` maps every runtime test through the test framework's `extend` to set `globalTimeout`; `checks.<system>.test-size-classes` compares key sets with the entries; fleet-alert renders the limits into an SQL rule over `devloop.ci_attribute`; a pyrite timer builds `lib.enormousTests` from `main`.

**Tech Stack:** flake-parts with import-tree; the NixOS test framework (`pkgs.testers.runNixOSTest`, systemd-nspawn and QEMU); fleet-alert's evaluator (PromQL and SQL rules against GreptimeDB 1.2.1); systemd timers; node exporter's textfile collector; nixbot's `build_attributes`.

**Spec:** `openspec/changes/declare-test-size-classes/` — `design.md` (D1–D12, regulators G1–G7), `specs/`, `tasks.md`, `brainstorm.md`, `proposal.md`.

---

## Global Constraints

- Six stacked chains, one per stage, each landing as one pull request in order (tasks.md groups 1–6); each commit evaluates and passes its checks alone. Edits are made in `@` and routed with `jj squash --into <chain> --use-destination-message --keep-emptied <paths>`.
- Every run is announced first when expected to exceed 5 minutes (tasks.md names each such run and its notice); a subagent returns the notice to its orchestrator instead of starting the run.
- Runtime tests run on pyrite itself (`ssh pyrite.vanixiets.internal nix build --builders ''` against a source archived on pyrite; `--store ssh-ng://pyrite…` from another host does not keep the build on pyrite, `logs/tsc-1-fleet-ingress-20261124-111732.log`); x86_64-linux builds on magnetite's store (`--eval-store auto --store ssh-ng://magnetite.zt`); never an aarch64-darwin system closure.
- Every regulator is seen failing on its mutant (design's regulator table) before it is trusted; each mutant runs only the case or clause it must fail, in a throwaway tree.
- `testSizes` entries are literal or depend only on `system`; any other form is a defect, found by task 4.7's key-set measurement.
- Deploys (stages 5 and 6) are `clan machines update <host>` by an agent after the stage's pull request merges, each followed by reading every alert and failure post since the deploy began.

## Grounding: the vendored consumers' interfaces

- NixOS test framework at the locked nixpkgs: `test.extend { modules = [ … ]; specialArgs ? { }; }` (`nixos/lib/testing/call-test.nix:30-41`) re-evaluates a test; `globalTimeout` is an int, default 3600 (`nixos/lib/testing/driver.nix:164-172`), passed to the driver as `global_timeout` (`driver-configuration.nix:99`); the driver prints `test script finished in <s>` and `[<s>s]` per line.
- fleet-alert's evaluator sends a rule with `language = "sql"` as `POST /v1/sql?db=<database>` (`modules/nixos/fleet-alert/rules.nix:51-53`); `PullRequestQueueWaitBurn` is the house example of an SQL rule over `devloop`.
- `devloop.ci_attribute` columns `attr`, `system`, `status`, `cached`, `started_at`, `finished_at` (`modules/nixos/devloop-collection.nix` `sources.ci_attribute.selects`).
- Node exporter's textfile collector takes one `--collector.textfile.directory` (`modules/checks/node-exporter-textfile.nix`; magnetite failed to start with two on 2026-11-19); a writer replaces its `.prom` file atomically (write a temporary file in the directory, then rename).
- `nix build` accepts a flake reference `github:cameronraysmith/vanixiets/<rev>#vmTests.x86_64-linux.<name>` and `--builders ''`, which keeps the build on the local daemon.

## Interface contract

| Kind | Name | Defined in |
|---|---|---|
| perSystem option | `testSizes.{checks,vmTests}.<name> = { class : enum [ small medium large enormous ]; reason : nullOr str = null; measured : bool = true; }` | Task 3 |
| Lib | `flake.lib.testSizeLimits = { small = 60; medium = 300; large = 900; enormous = 3600; }` | Task 3 |
| Lib | `flake.lib.enormousTests : listOf str` (x86_64-linux `vmTests` entries with `class = "enormous"`) | Task 3 |
| vmTests | `fleet-ingress`, `fleet-ingress-outage` (Task 1); `devloop-ingest`, `devloop-ingest-reconcile` (Task 2) | Tasks 1, 2 |
| Check | `checks.{x86_64-linux,aarch64-darwin}.test-size-classes` | Task 4 |
| Alert rule | `CheckOutgrewItsClass` (SQL, `devloop`, `info`, `for = "1d"`); `EnormousTestStale` (PromQL, `warning`) | Tasks 5, 6 |
| Units (pyrite) | `enormous-tests.service`, `enormous-tests.timer`; metrics `vanixiets_enormous_test_last_run_timestamp_seconds{test,result}`, `vanixiets_enormous_test_last_success_timestamp_seconds{test}` | Task 6 |

---

## Task 1: split `fleet-ingress` (tasks.md 1.1–1.9)

- [ ] **Step 1:** Wait for the operator's answer to design Open Question 1; record it (1.1).
- [ ] **Step 2:** `rg -n 'fleet-ingress|backPressure|lossControls|crashLoop|longRun|absentClientCa|langfuse' openspec/specs` and read each hit's requirement; write the list to `logs/tsc-1-corpus-<ts>.log` (1.2).
- [ ] **Step 3:** Add `modules/vm-tests/fleet-ingress/nonce_scan.py`, shipped as `/etc/fleet-ingress/nonce_scan.py` in the store container: it takes the regulator's netrc and the nonces as arguments, queries `information_schema.columns` as `regulator` exactly as `helpers.py` `nonce_hits` did, loops the columns on the container's loopback and prints the hit dictionary with the column and table counts as JSON.
- [ ] **Step 4:** Change `nonce_hits` in `modules/vm-tests/fleet-ingress/helpers.py` to one `store.succeed` of `python3 /etc/fleet-ingress/nonce_scan.py`, keeping its print line; evaluate the container's closure (1.3).
- [ ] **Step 5:** Turn the `fleet-ingress` binding into a function of `{ name, cases }` over the shared container and helpers; define `fleet-ingress` and `fleet-ingress-outage` with design D7's case lists; update the header comment (1.4). Commit: `test(fleet-ingress): split the outage cases into fleet-ingress-outage`.
- [ ] **Step 6:** Run `agentSession` and `agentSpans` alone, then `scanFirstTable` and `scanStringOnly` in throwaway trees; record results (1.5).
- [ ] **Step 7:** Run `fleet-ingress` cold on pyrite under `time`, tee to `logs/` (1.6). If over 300 s, apply the Open Question 1 answer.
- [ ] **Step 8:** Give the notice; on approval, run `fleet-ingress-outage` once (1.7).
- [ ] **Step 9:** Write the MODIFIED deltas from Step 2's list; `openspec validate declare-test-size-classes --strict` (1.8).
- [ ] **Step 10:** Update the repository fragment and the skill reference; `prek run --files <files>` (1.9). Commit: `docs(vanixiets): record the fleet-ingress split in the test-size text`.

## Task 2: split `devloop-ingest` (tasks.md 2.1–2.5)

- [ ] **Step 1:** In `modules/vm-tests/devloop-ingest.nix`, make the test a function of `{ name, cases }`; define `devloop-ingest` without `reconcile` and `devloop-ingest-reconcile` with it; change `if to_midnight < 3600` to `< 1800` and its comment (2.1). Commit: `test(devloop-ingest): split the reconcile case into devloop-ingest-reconcile`.
- [ ] **Step 2:** Read and restate the corpus requirements citing reconcile legs as MODIFIED deltas; validate (2.2).
- [ ] **Step 3:** Run `devloop-ingest` cold, timed (2.3); give the notice and run `devloop-ingest-reconcile` more than 30 minutes before 00:00 UTC (2.4).
- [ ] **Step 4:** Update the fragment sentence; `prek run --files` (2.5).

## Task 3: declared classes and runtime-test timeouts (tasks.md 3.1–3.7)

- [ ] **Step 1:** Create `modules/checks/test-sizes.nix` declaring the perSystem option with `flake-parts-lib.mkPerSystemOption` (not transposed), `flake.lib.testSizeLimits`, and `flake.lib.enormousTests` via `withSystem "x86_64-linux"` over the `vmTests` entries (3.1).
- [ ] **Step 2:** In each of the 14 test files under `modules/vm-tests/` (every `.nix` file there but `default.nix` and `otel-test-pki.nix`), add the `testSizes.vmTests.<name>` entry beside its `vmTests` definition (3.2).
- [ ] **Step 3:** In `modules/vm-tests/default.nix`, add to the option an `apply = lib.mapAttrs (name: test: test.extend { modules = [ { globalTimeout = limitOf name; } ]; })`, where `limitOf` throws `"vmTests.${system}.${name} has no testSizes.vmTests entry"`; the option needs `system` and the perSystem `config.testSizes`, so declare the `apply` from a perSystem module (3.3).
- [ ] **Step 4:** Evaluate each driver's `global_timeout` and the enormous tests' `drvPath`s against their pre-change values (3.3). Commit: `feat(vm-tests): take each runtime test's global timeout from its size class`.
- [ ] **Step 5:** Run the two mutants (3.4, 3.5).
- [ ] **Step 6:** Give the batch notice and measure the four unmeasured x86_64-linux tests; update their entries (3.6). Commit: `test(vm-tests): record the measured classes of four tests`.
- [ ] **Step 7:** Update the policy text (3.7).

## Task 4: every check classed, and the structural check (tasks.md 4.1–4.9)

- [ ] **Step 1:** Record the operator's answers to Open Questions 3 and 5 (4.1).
- [ ] **Step 2:** Change the two `vmTests` guards; run the drvPath-identity oracle over `vmTests` on both Linux systems (4.2). Commit: `refactor(vm-tests): key runtime-test names on system`.
- [ ] **Step 3:** Query nixbot's PostgreSQL on magnetite with the skill reference's SQL for every gated attribute; time the `package-omnigraph` rebuild (4.3).
- [ ] **Step 4:** Add entries module by module; for `packages.nix`, `package-tests.nix`, `home.nix`, `containers.nix` and the machine checks, a literal set keyed by generated name, selected by `system` where classes differ (4.4).
- [ ] **Step 5:** Create `modules/checks/test-size-classes.nix`: per system, compute the four finding lists from `builtins.attrNames config.checks`, `builtins.attrNames config.testSizes.checks` and, on x86_64-linux, the two `vmTests` key sets through `self.vmTests`; `runCommand` that prints the findings and exits 1 when any list is non-empty (4.5). Commit: `feat(checks): add test-size-classes`.
- [ ] **Step 6:** Run the five mutants (4.6).
- [ ] **Step 7:** Measure the evaluation cost (4.7); give the notice and run the A/B/A/B benchmark (4.8).
- [ ] **Step 8:** Update the policy text (4.9).

## Task 5: the size rule (tasks.md 5.1–5.5)

- [ ] **Step 1:** Run a median query by hand through `obs-query` against `devloop.ci_attribute` for one attribute and compare with nixbot's PostgreSQL (5.1).
- [ ] **Step 2:** In `modules/nixos/fleet-alert/rules.nix`, render `CheckOutgrewItsClass` with a `VALUES` list built from both gated systems' `testSizes.checks` and `testSizeLimits`; pin the rendered list in `modules/checks/fleet-alert.nix` (5.2). Commit: `feat(fleet-alert): report checks that outgrow their size class`.
- [ ] **Step 3:** Add the `sizeRule` case and `sizeRuleLimitOff` mutant to `devloop-ingest`; run (5.3).
- [ ] **Step 4:** Deploy magnetite; read alert posts for 24 hours (5.4); update the policy text (5.5).

## Task 6: the weekly enormous run (tasks.md 6.1–6.8)

- [ ] **Step 1:** Record the operator's answers to Open Questions 2 and 6 (6.1).
- [ ] **Step 2:** Evaluate pyrite's node exporter flags; add the textfile directory if absent and extend `node-exporter-textfile` (6.2).
- [ ] **Step 3:** Add the module defining `enormous-tests.service` (oneshot; `Environment=ENORMOUS_TESTS_FLAKE=github:cameronraysmith/vanixiets/main`; script: resolve the revision with `nix flake metadata --json`, `nix eval --json "<ref>#lib.enormousTests"`, then per name `nix build --no-link --builders '' "<ref>#vmTests.x86_64-linux.<name>"`, writing both metrics atomically after each) and `enormous-tests.timer`; add the unit to pyrite's `notifiedUnits` (6.3). Commit: `feat(pyrite): run the enormous runtime tests weekly`.
- [ ] **Step 4:** Add `EnormousTestStale` and its fixture legs and mutant (6.4). Commit: `feat(fleet-alert): alert when an enormous test has not passed for eight days`.
- [ ] **Step 5:** Deploy pyrite, then magnetite; read posts (6.5).
- [ ] **Step 6:** Give the notice; start the service once; read the metrics and the rule (6.6).
- [ ] **Step 7:** Run the failure mutant through a runtime drop-in; remove it (6.7); update the policy text (6.8).

## Task 7: integration verification (tasks.md 7.1–7.4)

- [ ] **Step 1:** Open a throwaway pull request adding an unclassed check; observe the gate fail; add the entry; observe it pass; close it unmerged (7.1).
- [ ] **Step 2:** After the first Sunday, read the service's journal and both metrics (7.2).
- [ ] **Step 3:** After a week, account for every `CheckOutgrewItsClass` post (7.3); list the remaining `measured = false` entries (7.4).
