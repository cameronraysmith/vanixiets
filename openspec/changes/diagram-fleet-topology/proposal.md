---
linear_story_id: CAM-114
linear_story_identifier: CAM-114
linear_story_title: "Diagram the fleet topology from the flake"
linear_story_url: https://linear.app/cameronraysmith/issue/CAM-114/diagram-the-fleet-topology-from-the-flake
linear_story_state: Todo
linear_team: CAM
linear_project: nixbot-herculesci-cicd
last_synced_state: Todo
last_synced_at: "2026-11-18T20:54:19Z"
review_round: 0
max_review_rounds: 3
attempt_log:
  - { at: "2026-11-18T20:54:19Z", transition: "Backlog->Todo", outcome: "posted", note: "Issue CAM-114 created in Todo in project 82a27ad740f7 (Migrate to nixbot and herculesCI CI/CD) with description seeded from proposal.md, related to CAM-112; state and project confirmed by read-only view" }
---

## Why

No picture shows where the fleet's services run or which networks each host joins; the facts are spread over the clan inventory, the member registry and individual host modules. CAM-112 (dedicate magnetite to CI, replace cinnabar with a host for agent workloads) needs that picture, and so does every later placement change. A map generated from the flake, committed as text and rendered in the docs, makes each topology change a reviewable diff and costs under a second to keep honest.

## What Changes

Decisions tagged `D<n>` are developed in `design.md`; the operator approved the approach and its scope on 2026-11-18.

**A fleet map derived from the flake (tier 1)**
- From: no map; placement is read file by file.
- To: `flake.lib.fleetTopology` reads `self.clan.inventory` and `flake.lib.hosts` and produces `fleet.json` (one line per host and per service instance) plus two D2 views, `fleet.d2` (placement by host and platform) and `network.d2` (the tincr and ZeroTier networks with their members, and the public edge) (D1-D4).
- The three files are committed under `packages/docs/diagrams/topology/`; `just topology-generate` rewrites them (D3).
- Impact: non-breaking; no host configuration changes.

**Declared facts outside the inventory (tier 2)**
- A small hand-written `flake.lib.topologyFacts` records, per host, the services clan does not know about (nixbot, buildbot, niks3, gitea, gitea-mq, kanidm, sso-gateway, perses, cognee on magnetite; cinnabar's services) with their public hostnames and ports. It never evaluates a host configuration (D5).

**Kept honest by a cheap check**
- `checks.x86_64-linux.fleet-topology-fresh` regenerates the three files, fails when the committed ones differ (naming `just topology-generate`), and runs `d2 validate` on both views; its key set is a literal and its value evaluates only the inventory, the registry and the tier-2 set (D6).
- The generator's pure logic is unit-tested with nix-unit over literal fixtures (D7).

**Rendered in the docs**
- `just diagrams-build` and the `vanixiets-docs` package render both views to SVG with d2 and pass them through the existing svgo step, whose default preset keeps every label as SVG `<text>`; the devshell gains d2 (D8, D11).
- A new page `concepts/fleet-topology` embeds both views as images, light theme only, the same way every existing diagram is embedded, and says what is derived and what is declared (D9, D12).

**Witnessed in the browser**
- A Playwright spec in the existing e2e suite checks that the page and both images load and that every host and fleet network in the committed `fleet.json` is text in the served SVGs; a negative control drops one host and must fail (D13, D14).
- On Chromium the spec attaches both views to the browser-evidence report, and the evidence comment shows them beside the base revision's, so a reviewer sees the map before and after; no pixel snapshot gates the change (D15).

## Capabilities

### New Capabilities
- `fleet-topology-map` (stratum: `behavioral`): the documentation shows a map of every host, its platform, the services it runs and the role each gives it, every fleet network and its members, and each public hostname with the host that answers it, with names as text in its pictures; the map is derived, never hand-edited; a change that moves a service or a network member without the matching map change fails before merge; and a reviewer sees the pictures before and after.
- `fleet-topology-map-interface` (stratum: `interface`): `flake.lib.fleetTopology` and its inputs (`self.clan.inventory`, `flake.lib.hosts`, `flake.lib.topologyFacts`), the three committed files and their format, the `fleet-topology-fresh` check's key and comparison, the `topology-generate` recipe, and the rendered SVG paths.
  Trust boundary: this machine guarantees that the committed files equal what the declared inventory, the registry and the declared facts produce, that both views parse as D2, and that the served SVGs carry every committed host and network name as text. It does not guarantee that the declarations match what any host actually runs, that a declared public hostname resolves or answers, or that the rendered layout or the evidence screenshots read well.

### Modified Capabilities
- `world-assumptions` (stratum: `world`): A154 records that clan's declared inventory names every machine's class and each service role's members but nothing about services a host configures outside clan; `Grounded vocabulary for behavioral requirements` gains `fleet map`, `NixOS host`, `service role`, `fleet network`, `network member`, `device`, `declared fact` and `port`.

## Impact

- Code: new `modules/lib/fleet-topology.nix`, `modules/lib/topology-facts.nix`, `modules/lib/fleet-topology.test.nix`, `modules/checks/fleet-topology.nix`; `justfile` (`topology-generate`, `diagrams-build`); `pkgs/by-name/vanixiets-docs/package.nix` (d2 render step, `e2e-topology-negative-control`); `modules/devshells/default.nix` (`pkgs.d2`); `modules/checks/package-tests.nix`; `modules/apps/docs/publish-evidence.sh` and `modules/checks/publish-evidence-rehearsal.nix` (`Rendered views` section).
- Docs package tests: new `packages/docs/e2e/fleet-topology{.ts,.spec.ts}`, `tests/negative-control/fleet-topology.spec.ts`, `playwright.topology-negative.config.ts`; `tests/report/policy.ts`, `tests/report/check-negative-report.ts`, `tests/report/README.md`. No vitest change: the page has no TypeScript logic.
- Docs: new `packages/docs/diagrams/topology/{fleet.json,fleet.d2,network.d2}` and `packages/docs/src/content/docs/concepts/fleet-topology.md`; links from `concepts/index.md`, `concepts/architecture-overview.md` and `concepts/build-service-topology.md`; `concepts/browser-evidence.md` corrected for passing-attempt view screenshots.
- CI: one new x86_64-linux check plus one nix-unit check, evaluation cost measured at apply; three new e2e cases in the existing report; one new negative-control check.
- Hosts: none; no deploy.
- No new flake input; d2 comes from nixpkgs.
