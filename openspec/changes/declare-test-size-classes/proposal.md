---
linear_story_id: CAM-123
linear_story_identifier: CAM-123
linear_story_title: "Declare and enforce test size classes"
linear_story_url: https://linear.app/cameronraysmith/issue/CAM-123/declare-and-enforce-test-size-classes
linear_story_state: Todo
linear_team: CAM
linear_project: nixbot-herculesci-cicd
last_synced_state: Todo
last_synced_at: "2026-11-24T10:00:46Z"
review_round: 0
max_review_rounds: 3
attempt_log:
  - { at: "2026-11-24T10:00:46Z", transition: "Backlog->Todo", outcome: "posted", note: "Issue CAM-123 created in Todo in project 82a27ad740f7 (Migrate to nixbot and herculesCI CI/CD), no label, with description seeded from proposal.md's Why and What Changes; state and project confirmed by read-only view; bind comment posted" }
---

## Why

The fleet's test size policy (pull request #4224, 2026-11-24) gives every test a class by the wall-clock time of one run and says where each class may run, but nothing in code declares a class or notices when a test outgrows one. On 2026-11-24 a 36–39 minute `fleet-ingress` run was started to check a two-line filter change, with no notice. Three tests are enormous, twenty package builds are large and 155 checks and tests have no measurement. Declaring each class beside its definition, failing a runtime test that outlasts its class, and reporting a build that outgrows its class turn the policy from text into regulators, and splitting the two enormous runtime tests puts their routing and filtering assertions back in the medium class where an agent can run them before publishing.

## What Changes

**fleet-ingress split (stage 1)**
- From: one container test of 14 cases, 2,115–2,200 s of script, 36–39 minutes per cold run; the no-leak scans cost 283–316 s in ~6,200 driver round trips.
- To: `fleet-ingress` keeps the eight filtering, routing, refusal and no-leak cases, with each scan run as one command inside the container; `fleet-ingress-outage` takes the six cases whose behaviour needs real time (back-pressure, loss controls, crash loop, long run, absent client CA, Langfuse).
- Impact: non-breaking; the routing test is expected to be medium (accepted only if one cold run measures at most 300 s), the outage test enormous (~1,650 s).

**devloop-ingest split (stage 2)**
- From: one container test, 1,690–1,701 s, whose `reconcile` case takes ~1,468 s and can first wait up to an hour for the UTC day to turn.
- To: `devloop-ingest` keeps every other case (~225 s); `devloop-ingest-reconcile` takes `reconcile`, with its midnight guard cut to 30 minutes so its worst case stays under 60.

**Declared classes and runtime-test timeouts (stage 3)**
- Each runtime test declares its class beside its definition; the test framework's global timeout is set from the class, so a test whose script outlasts its class fails. The seven tests never measured are declared medium until their next run measures them.

**Every check classed, and the structural check (stage 4)**
- Each check on x86_64-linux and aarch64-darwin declares its class; a check fails the gate if any attribute lacks a class, any check is enormous, or a large check has no recorded reason. `package-omnigraph`, now a binary repackage, is re-measured before it is classed.

**The size rule (stage 5)**
- A low-priority alert reports any check whose median uncached build over 30 days exceeds its class, or which ran over an hour.

**The weekly enormous run (stage 6)**
- pyrite builds each enormous test from `main` once a week; a failure is posted as a failure notice, and a test without a success for eight days raises an alert.

**Non-goals**: shortening the outage or reconcile cases to large; moving runtime tests onto the pull-request gate; classes for `checks.aarch64-linux`, which nothing builds; enforcing the five-minute notice in code.

## Capabilities

### New Capabilities

- `test-size-classes` (stratum: behavioral): every test has one declared size class; a runtime test that outlasts its class fails; no enormous test and no unexplained large check gates a pull request; a check that outgrows its class reaches the operator without paging; every enormous test runs weekly with a visible result; a property that needs no real time is shown by a test of medium class or smaller.
- `test-size-classes-interface` (stratum: interface): the per-system `testSizes` declarations and class limits, the `vmTests` timeout application, `checks.<system>.test-size-classes`, the `CheckOutgrewItsClass` and `EnormousTestStale` rules, the `enormous-tests` timer on pyrite, and the split test attributes. Trust boundary: the timeout bounds a runtime test's script, not its driver and node builds; the size rule sees only builds nixbot recorded and the dev-loop collection copied; the weekly run sees only what pyrite could build while on and on the mesh; nothing here checks that a person or agent gave the five-minute notice.

### Modified Capabilities

- `world-assumptions` (stratum: world): A221–A225 (the test driver's global timeout, the absence of a per-derivation time limit, nixbot's duration record, pyrite as the only kvm host, and the measured durations the initial classes rest on); designations for test, check, size class, run (test sense), run notice, scheduled run and pull-request gate.
- Corpus requirements that cite a case moved by stages 1 and 2 (in `fleet-ingress-interface`, `devloop-collection-interface` and `world-assumptions` A52) are restated in the stage that moves the case; design D7 lists the candidates.

## Impact

- Code: `modules/vm-tests/{default,fleet-ingress,devloop-ingest,omnigent-worker-isolation,zerotier-mss-clamp-runtime}.nix` and `modules/vm-tests/fleet-ingress/helpers.py`; every module under `modules/checks/` and `modules/vm-tests/` gains its `testSizes` entries; a new `modules/checks/test-size-classes.nix` and the `testSizes` option module; `modules/nixos/fleet-alert/rules.nix`; a new pyrite timer module.
- Hosts: magnetite (the size rule and the stale rule), pyrite (the weekly timer).
- Docs: the repository fragment's test-size paragraph and the skill's `references/test-sizes.md` ("What is not enforced") are updated as each regulator lands.
- Evaluation: one new attribute per gated system, reading key sets nixbot already computes; its cold cost is measured before stage 4 merges.
