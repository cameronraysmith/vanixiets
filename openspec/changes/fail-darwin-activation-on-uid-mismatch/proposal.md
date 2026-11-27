---
linear_story_id: CAM-139
linear_story_identifier: CAM-139
linear_story_title: "Stop a Mac's deploy when an account's real uid differs from the recorded one"
linear_story_url: https://linear.app/cameronraysmith/issue/CAM-139/stop-a-macs-deploy-when-an-accounts-real-uid-differs-from-the-recorded
linear_story_state: In Review
linear_team: CAM
linear_project: den-ready-fleet
last_synced_state: In Review
last_synced_at: "2026-11-27T19:15:09Z"
review_round: 0
max_review_rounds: 3
attempt_log:
  - { at: "2026-11-27T15:49:25Z", transition: "Backlog->Todo", outcome: "posted", note: "Issue CAM-139 created in Todo in project 06049a4f18a4 (Den-ready fleet architecture), no label, with description seeded from proposal.md's Why and What Changes; state and project confirmed by read-only view" }
  - { at: "2026-11-27T17:54:15Z", transition: "Todo->In Progress", outcome: "posted", note: "First tasks.md checkbox checked; state set to In Progress and a two-sentence comment posted; state confirmed by read-only view" }
  - { at: "2026-11-27T19:15:09Z", transition: "In Progress->In Review", outcome: "posted", note: "verify.md written (PASS WITH WARNINGS; operator tasks 4.2-4.4 open); state set to In Review and a two-sentence comment posted; state confirmed by read-only view" }
---

## Why

A darwin host's recorded account uid (`flake.fleet.hosts.<host>.users.<account>.uid`) is applied to the account, but when it differs from the uid the account really has, nix-darwin only warns, skips that account and reports a successful deploy. A wrong record leaves the account unmanaged and nothing fails. Evaluation cannot see a Mac's real uids, so the only check that can catch a wrong record is one that runs on the Mac and fails instead of warning.

## What Changes

**What can be checked, stated plainly**
- An evaluation-time check can only pin the recorded uids against a second literal in the repository. That catches an accidental later edit, not a record that was wrong from the start, which is the failure the operator saw. It is not proposed.
- Only something running on the Mac can compare the recorded uid with the account's real uid.

**Darwin activation fails on a uid mismatch**
- From: a recorded uid that differs from the existing account's uid produces a warning; activation skips the account and succeeds.
- To: before activation changes anything, each Mac compares the uid of every account attached to it with the recorded uid. Any mismatch stops the activation, naming the host, account, recorded uid, real uid and the record to correct. A missing account is not a mismatch (nix-darwin creates it with the recorded uid).
- Reason: the wrong record is caught at the first deploy instead of silently leaving an account unmanaged.
- Impact: an intended derivation change for the four darwin hosts (stibnite, blackphos, argentum, rosegold), which the operator deploys. A Mac whose record is wrong cannot be deployed until the record or account is corrected. `darwin-rebuild check` runs the same comparison without changing the Mac. NixOS hosts and homes are unchanged.

**A check that shows the comparison fails**
- New medium build check that runs each Mac's rendered comparison with a stand-in for the account lookup: matching uid passes, missing account passes, a mutant uid fails.

## Capabilities

### New Capabilities
- `darwin-account-uid-agreement` (behavioral): a Mac is not deployed while an account attached to it has a uid other than the recorded one.
- `darwin-account-uid-agreement-interface` (interface): the activation-time comparison at nix-darwin's activation script and the build check that exercises it; trust boundary stated.

### Modified Capabilities
- `world-assumptions` (world): adds A370-A374 on nix-darwin's activation order, `darwin-rebuild`'s profile-then-activate order, the boot daemon's steps, `darwin-rebuild check`, and the macOS uid lookup; adds designations for the new terms.

## Impact

- `modules/system/home-manager-integration.nix` (darwin branch): generates the comparison from the host's attachments into `system.activationScripts.preActivation`.
- New `modules/checks/darwin-uid-preflight.nix` and its `testSizes` entry (`class = "medium"; measured = false;`).
- drvPaths: the four darwin toplevels change; `checks.x86_64-linux.darwin-uid-preflight` is added; `checks.x86_64-linux.fleet-alert` changes (it renders every `testSizes.checks` entry). Recorded in `drv-delta.txt` at apply.
- Deploy: the operator deploys each Mac, after running `darwin-rebuild check` there.
