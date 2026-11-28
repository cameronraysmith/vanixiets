---
linear_story_id: CAM-141
linear_story_identifier: CAM-141
linear_story_title: "Name the parts of the shared host and agent settings, so each can be read and taken alone"
linear_story_url: https://linear.app/cameronraysmith/issue/CAM-141/name-the-parts-of-the-shared-host-and-agent-settings-so-each-can-be
linear_story_state: Done
linear_team: CAM
linear_project: den-ready-fleet
last_synced_state: Done
last_synced_at: "2026-11-28T07:07:15Z"
review_round: 0
max_review_rounds: 3
attempt_log:
  - { at: "2026-11-27T23:41:24Z", transition: "Backlog->Todo", outcome: "posted", note: "Issue CAM-141 created in Todo in project 06049a4f18a4 (Den-ready fleet architecture), no label, with description seeded from proposal.md's Why and What Changes, and the bind comment posted; state and project confirmed by read-only view" }
  - { at: "2026-11-28T07:07:01Z", transition: "archive->mirror", outcome: "posted", note: "Documents in project Den-ready fleet architecture (06049a4f18a4): OpenSpec: aspect-parts (49de908d) and aspect-parts-interface (438c9648) created; ids stored in openspec/linear.yaml" }
  - { at: "2026-11-28T07:07:01Z", transition: "archive->mirror", outcome: "dropped", note: "world-assumptions (69e977af) not updated: it is listed in defaults.archive_documents.unmirrored, and the synced spec is 290743 characters, over Linear's 250000-character document limit; the document still holds an earlier archive's copy" }
  - { at: "2026-11-28T07:07:15Z", transition: "In Progress->Done", outcome: "posted", note: "Catch-up in one transition: the intermediate transitions (Todo->In Progress, In Progress->In Review) were not recorded in this ledger, and Linear read In Progress before the transition. Archived with 9 of 29 tasks open, each with its reason in tasks.md and the retrospective, after aspect-parts, aspect-parts-interface and world-assumptions were synced (9 designation rows added to main's table, A375-A377 added). Review gates: no review-gate decision is recorded for this change beyond the reviews that ran before each commit landed; verify.md's Overall Decision is PASS WITH WARNINGS. Workspace confirmed by linear auth whoami; state confirmed Done by read-only view; archive comment posted" }
---

## Why

The settings every NixOS host shares (`flake.modules.nixos.base`), every Mac shares (`flake.modules.darwin.base`) and every agent-using home shares (`flake.modules.homeManager.ai`) are each assembled from whichever files happen to assign into them: 33, 37 and 19 files at commit `fcf3a652e6f1`.
No file says what they consist of, a host or test cannot take one part of them, and a new file widens them without any list changing.
Naming the parts was designed before and set aside because it reorders lists in the delivered systems; that reorder is now measured to be order only, so the change can be made the way stibnite joined the darwin workstation aspect: declared, compared and deployed once.

## What Changes

**Each aspect becomes one explicit list of named parts**
- From: `base` (NixOS and darwin) and `ai` are the implicit union of every file that assigns into them.
- To: each contributing file defines its own named part (`base-<concern>`, `ai-<harness>`; a file that only imported an already named module contributes that name), and one file per class lists the parts: `modules/nixos/base.nix`, `modules/darwin/base.nix`, `modules/home/ai/default.nix`.
- Reason: what `base` and `ai` consist of can be read in one place, and a host or test can take one part.
- Impact: NixOS hosts unchanged. Each Mac's system package list and each reached home's package list keep their members and change order; nothing else changes.

**Adding a part is registering it**
- New small structure check that fails when a file assigns into `base` or `ai` directly, when a second file assigns into an existing part, or when a part is in no list.

**Three pull requests, each accepted on its own derivation comparison**
- NixOS `base` with the check (no host or home changes); darwin `base` (the four Macs); `ai` (all ten hosts and the six `crs58`/`cameron` homes).
- The operator deploys each host once and activates each reached standalone home once, after the third lands.

## Capabilities

### New Capabilities
- `aspect-parts` (behavioral): the base settings of each kind of host and the agent tooling are each a stated list of parts that can be taken one at a time, and restating them changes no delivered system beyond declared order.
- `aspect-parts-interface` (interface): the three list files and their `flake.lib` lists, the structure check and its size, and the per-pull-request derivation comparison; trust boundary stated.

### Modified Capabilities
- `world-assumptions` (world): adds A375-A377 on the import levels flake-parts and the deferred-module merge add, buildEnv's collision rule, and nix-darwin's deletion of an undeclared known account; adds designations for the new terms.

## Impact

- New `modules/nixos/base.nix`, `modules/home/ai/default.nix`, `modules/darwin/base-essentials.nix` (`darwin/base.nix`'s own settings), `modules/checks/structure/aspect-parts.nix` and its `testSizes` entry; `modules/darwin/base.nix` becomes the darwin list.
- The 33 NixOS, 37 darwin and 19 ai contributing files rename their assignment or drop it (listed in design D2; the inventory is retaken at each pull request's parent).
- drvPaths (measured on prototypes at `fcf3a652e6f1`, recorded in `logs/ntp-1-drvpaths-20261127-181533.log` and `logs/ntp-5-check-drvpaths-20261127-181533.log`): the NixOS step changes none; the darwin step the four darwin toplevels and `checks.aarch64-darwin.darwin-*`; the ai step the ten toplevels, six homes, `checks.x86_64-linux.nixos-{cinnabar,electrum,galena,magnetite,pyrite}`, `checks.aarch64-darwin.darwin-*` and `checks.{x86_64-linux,aarch64-darwin}.home-manager-crs58`. Recorded per pull request in `drv-delta-*.txt` at apply, each changed derivation judged by `drv-order-trace.py` in this change's directory.
- Deploy: ten hosts and the standalone `crs58@*`/`cameron@*` homes in use, once, by the operator.
