---
execution_mode: HIL
linear_story_id: "691c9e9f-548d-40f1-8424-3490a2ab4795"
linear_story_identifier: CAM-79
linear_story_title: Deliver the omp browser relay extension declaratively
linear_story_url: https://linear.app/cameronraysmith/issue/CAM-79/deliver-the-omp-browser-relay-extension-declaratively
linear_story_state: Done
linear_team: CAM
linear_project: pi-agent-environment
last_synced_state: Done
last_synced_at: "2026-11-06T00:59:05Z"
review_round: 0
attempt_log:
  - at: "2026-11-05T22:48:30Z"
    transition: Backlog->Todo
    outcome: posted
    note: Created CAM-79 in Backlog in the existing pi-agent-environment project with the business description seeded from this proposal, moved it to Todo, confirmed Todo by readback, and posted the binding comment.
  - at: "2026-11-05T22:57:00Z"
    transition: Todo->In Progress
    outcome: posted
    note: T2 on the first checked tasks.md boxes (1.1-4.1, 6.2); state confirmed In Progress by readback and comment posted.
  - at: "2026-11-05T23:43:35Z"
    transition: In Progress->In Review
    outcome: posted
    note: T3 on verify.md (PASS WITH WARNINGS; 5.2 loaded in one of six Helium profiles, 5.4 deferred); state confirmed In Review by readback and comment posted.
  - at: "2026-11-06T00:59:05Z"
    transition: In Review->Done
    outcome: posted
    note: T4 after archive to openspec/changes/archive/2026-11-05-deliver-omp-browser-relay; spec mirror created OpenSpec documents browser-relay-delivery (3818e4f0-8aa1-43c2-bedc-da9db0e44d57) and browser-relay-delivery-interface (f765de2b-e8e5-4f1e-a1f3-60b921d4cfe6) in pi-agent-environment and updated the shared world-assumptions document (a7f9d24e-8fe2-4120-9ba0-e7d4d3a23fe1); state confirmed Done by readback and comment posted. Task 5.4 archived undischarged by the person's decision, follow-up CAM-80.
---

## Why

omp's browser API can drive the person's own Helium browser, where they are signed in and Bitwarden lives, only through a relay extension loaded into it.
Today getting that extension means running `omp browser-relay install` by hand on each laptop and repeating it on every omp upgrade, and a careless delivery would change the extension's identity on every upgrade so each browser profile would have to load it again.
Delivering it with the fleet keeps the extension at the agent's own release and leaves one manual step per browser profile, done once.

## What Changes

**Where the relay extension comes from**
- From: nothing; the person would run `omp browser-relay install` by hand on each laptop after each omp upgrade.
- To: a package built from the omp the fleet deploys, so the extension is always the same release as the relay it talks to.
- Reason: no imperative step, no second version or hash to keep in step with omp.
- Impact: non-breaking; a new package.

**Where the browser loads it from**
- From: no extension folder exists.
- To: on darwin hosts, each activation refreshes a real, person-writable folder at `~/.omp/browser-relay/extension`, omp's own default relay folder, with the package's files.
- Reason: Helium names an unpacked extension by the resolved path of its folder, so a fixed real folder keeps the extension's identity across upgrades, and omp's own updater recognises the folder as the one it may refresh and reload.
- Impact: non-breaking; nothing changes on NixOS hosts.

**When an agent drives the person's browser**
- Unchanged: only a call that asks for the relay (`app.relay: true`) reaches the person's browser; the fleet does not turn the relay on for every session.

**What stays manual**
- Once per Helium profile, the person loads the folder with Developer mode → Load unpacked; the procedure and its hazards are documented beside the omp module.
- Bitwarden stays installed by hand in each profile, as it already is; the fleet installs and forces no browser extension.

## Capabilities

### New Capabilities

- `browser-relay-delivery` [behavioral]: the relay extension is present on each macOS host of the fleet for each account that runs the agent, matches the agent release, keeps its identity across agent upgrades so each browser profile loads it once, follows an upgrade without the person reloading it, reaches the person's browser only when a request asks for it, and leaves every browser profile's extensions to the person.
- `browser-relay-delivery-interface` [interface]: the extension package's content and its version stamp, the delivered folder's path, kind, contents and modes after activation, the platforms on which it is delivered, and the absence of a `browser.relay` setting in omp's managed configuration.

The interface trust boundary covers what the Home Manager configuration builds and writes, observed by building the package and the darwin home and host checks and by inspecting the delivered folder after activation on stibnite.
It does not cover how Helium derives an extension's identity, whether a person has loaded the folder in a given profile, what omp's relay writes into the folder between activations, or whether omp honours a per-call relay request; those rest on world assumptions or on omp itself.
It confers no isolation between the agent and the person's browser once the person has loaded the extension.

### Modified Capabilities

- `world-assumptions` [world]: adds A67 (Helium identifies an unpacked extension by its folder's resolved path), A68 (omp's relay refreshes and reloads only the extension folder that is its own and only toward a newer release) and A69 (omp's default relay folder is `~/.omp/browser-relay/extension` while no XDG data folder or profile for omp exists), and adds the designation rows this change's behavioral nouns need, giving `browser` and `release` a second sense.

## Impact

Source: `pkgs/by-name/omp-browser-relay-extension/package.nix` (new package with a build-time version-stamp check), `modules/home/ai/omp/default.nix` (`programs.omp.browserRelay.extension` options and the `ompBrowserRelayExtension` activation step), `modules/home/ai/omp/README.md` (new; the manual load step and its hazards).
Hosts: the darwin hosts, at their next activation; stibnite is the one verified here.
State: a new folder `~/.omp/browser-relay/extension` per darwin account with omp enabled; per-profile browser state is the person's.
No new flake input.
