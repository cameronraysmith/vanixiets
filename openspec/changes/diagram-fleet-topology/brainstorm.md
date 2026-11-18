<!--
Raw capture of superpowers:brainstorming output.

This file captures the output of the brainstorming skill verbatim; it does not impose any structure.
The skill's natural output is usually a decision-log format (background → decision chain Q1-Qn → design trade-offs),
but the organization may vary depending on the conversation.

design.md is extracted from this file and reorganized into a structured design document.

Do not copy this file's content into design.md — design.md is an independent, reorganized artifact;
the two are complementary but do not overlap.
-->

# Brainstorm: diagram the fleet topology from the flake

## How this was reached

The approaches were laid out in a research pass on 2026-11-18 (the CAM-112 session), compared against the criteria below, and the operator picked one.
The operator approved the recommendation as its own OpenSpec change on 2026-11-18 and fixed its scope: tier 1 (inventory to JSON plus two D2 views), the `fleet-topology-fresh` check on x86_64-linux only, `just topology-generate`, rendering in `diagrams-build`, and a `concepts/fleet-topology` docs page; tier 2 is a small hand-written per-host attribute set that never evaluates a host configuration.
Nothing below reopens that choice; the questions recorded here are the forks along the chosen path.

## Background

CAM-112 asks to rebalance the fleet (magnetite dedicated to nixbot, a larger host for omnigent and agent sessions after cinnabar's ZeroTier controller goes away).
Deciding that needs a picture of where every service runs and which networks every host joins, and the picture has to change in review whenever the placement does.
Today no such picture exists. The fleet's facts are spread over `modules/clan/inventory/**` (clan service instances and their roles), `modules/clan/inventory/machines.nix` (machine class, tags, description), `modules/lib/hosts.nix` (the member registry: class, public endpoints, mesh service labels, overlay addresses, including phones), and the individual NixOS modules on magnetite and cinnabar (nixbot, buildbot, niks3, gitea, gitea-mq, kanidm, sso-gateway, perses, cognee, matrix…), whose public names are scattered across `modules/nixos/*.nix` and `modules/terranix/cloudflare.nix`.
`concepts/build-service-topology.md` and `concepts/architecture-overview.md` describe parts of this in prose only.

## Criteria the operator set

- Derived from configuration, not hand-maintained.
- Text diffs, plus rendered visuals.
- Covers darwin and NixOS hosts, clan services, and more than one network (tincr, ZeroTier, the public edge).
- Evaluation cost: not a per-PR check unless it is cheap (preferences-nix-checks-architecture).
- Fits the Starlight docs site in `packages/docs`.
- Maintained upstream.

## Approaches compared

| Criterion | oddlama/nix-topology | inventory → D2 (chosen) | inventory → LikeC4 | Structurizr DSL | inventory → Mermaid | clan built-in |
|---|---|---|---|---|---|---|
| Derived | NixOS module with extractors (networkd, kea, microvm, containers, ~130 service defs) | `clan.inventory` plus `flake.lib.hosts` | same source, `.c4` output | same source, DSL output | same source | nothing; 26.05 exports are experimental and our tincr service exports nothing |
| Text diff | no, SVG only | yes | yes | yes | yes | — |
| darwin | no (issue #144 open since 2026-04, no reply) | yes, 4 of 10 machines are darwin | yes | yes | yes | — |
| clan roles | no | first-class | yes (deployment model) | yes | yes | — |
| Networks | networkd/kea only; tincr and ZeroTier by hand | both overlays from their instances | yes | yes | weak layout | — |
| Eval cost | every NixOS host, ~20 s each (magnetite measured at 20.4 s) | ~0.4 s (inventory only, measured `--no-eval-cache`) | same plus Node toolchain | same plus JVM | same | — |
| Starlight | copy SVG | matches the typst `diagrams-build` pipeline; d2 already in home tools | needs `@astrojs/react` or web components | poor | needs a remark/rehype plugin | — |
| Maintenance | active (2026-11-16) | d2 v0.9.0 active | very active (v1.61.0) | CLI and Lite archived 2026-02-04 | active | — |
| Skill fit | own style | primary format for architecture/deployment | off-preference | off-preference | inline sketches only | — |

A prototype in `/tmp/topo-proto` (outside the repo) evaluated `.#clanInternals.inventoryClass.inventory` with a small extraction function, resolved tags (including `all`) and explicit machines into role members for 15 instances and 10 machines, emitted a 99-line D2 file with jq, and rendered it with `d2 --layout elk` in about one second. The single combined view was correct but very tall, so the real thing needs separate views.

## Decision chain

**Q1. Which inventory attribute does the generator read?**
The prototype read `clanInternals.inventoryClass.inventory`. That is clan's internal merged class. `self.clan.inventory` is the declared inventory the flake module writes, and preferences-nix-checks-architecture names "clan inventory metadata" as static data a check key set may depend on, with `self.clan.inventory.instances.zerotier.roles.controller.machines` as its worked example.
Its `tags` attribute resolves only the built-in tags (`all`, `nixos`, `darwin`; checked on 2026-11-18), so user tags such as `peer` must be resolved by our own function over `machines.<name>.tags`.
Chosen: `self.clan.inventory`, plus our own resolution, unit-tested. Avoids depending on clan internals.

**Q2. Where do the facts outside clan roles come from?**
Three kinds of fact are not in clan roles: members outside clan (phones, darwin hosts joined to ZeroTier by address), public names, and services configured directly as NixOS modules.
`flake.lib.hosts` (modules/lib/hosts.nix) already holds each member's class, its public `endpoints`, its mesh service labels and its overlay addresses, including the android devices; the tincr instance's `roles.peer.settings.devices` lists the phones that joined tincr, and the ZeroTier controller's `allowedIps` lists external members by address from that registry.
So the overlay view and the hosts' own public names need no new data.
What is missing is "which services does magnetite run that clan doesn't know about, under which public names, on which ports". The operator fixed this as tier 2: a small hand-written per-host attribute set, never evaluated from host configuration.
Chosen: read the existing registry for everything it already states; add only the missing facts in a new attribute set. Do not copy registry fields into it (one convention per fact).

**Q3. Where does the generator live, and does it need a derivation?**
Options: (a) a `packages.<system>.fleet-topology` derivation using jq, as in the prototype; (b) a pure Nix function in `flake.lib` that returns the file contents as strings.
(a) gives an identical derivation on four systems (a fourfold evaluation tax if not gated) and, if gated to x86_64-linux, cannot be built on a laptop without a remote builder, so `just topology-generate` would be awkward. jq formatting also ties the committed bytes to one jq version.
(b) needs no system, no build, and `nix eval --raw` writes each file. JSON pretty-printing without jq is solved by emitting one top-level entry per line with `builtins.toJSON` for each value, which is valid JSON and diffs per host and per instance.
Chosen: (b), `flake.lib.fleetTopology` with `model` and `files`.

**Q4. Which views?**
One combined view was unreadable in the prototype. The skill's semantic-layers principle says add a view, not redraw.
Chosen: `fleet.d2` (placement: hosts grouped by platform, each host's clan service roles and declared services, public names on the services that have them) and `network.d2` (each fleet network as a cloud with its members, including phones; the public edge as the internet node with each public name pointing at its host).
Roles that every host holds (emergency-access, the per-person user instances when they cover all hosts) would repeat on every host; they are listed once in a legend titled "on every host". Legend, title and key on both views, per the skill's label-everything rule.

**Q5. What does the check compare, and what does it cost?**
The check is the codegen drift pattern the skill endorses: regenerate, diff against the committed files, fail with the command that fixes it.
Its key is a literal gated on `system == "x86_64-linux"`; its value evaluates only `self.clan.inventory`, `self.lib.hosts` and the tier-2 set. It also runs `d2 validate` on both views so a generator bug that emits invalid D2 fails here rather than in the docs build.
The inventory evaluation measured about 0.4 s. The apply phase measures the check's own evaluation allocation and confirms an unrelated check's drvPath and cost are unchanged, per the skill's evaluation-cost protocol.

**Q6. Where does the pure logic get tested?**
Placement ladder: facts about our own pure logic belong in an in-process unit test. Role resolution (explicit machines, user tags, `all`, unknown names), overlay membership including devices and ZeroTier external members, the every-host legend, unknown hosts in the tier-2 set, and the line-per-entry JSON emitter are pure functions.
Chosen: `modules/lib/fleet-topology.test.nix` via `flake.lib.mkEvalCheck`, as `modules/lib/mesh.test.nix` does, over literal fixtures, so a defect cannot move the expectation with it.

**Q7. Rendering and the docs page.**
SVGs in `packages/docs/public/diagrams/` are gitignored and rebuilt by `just diagrams-build` and, separately, by the `vanixiets-docs` package's buildPhase, which mirrors that recipe. Both need a d2 step, and the devshell needs `pkgs.d2` (today only home-manager's tools.nix has it, so CI would not).
Chosen: render `packages/docs/diagrams/topology/*.d2` with `d2 --layout elk` to `public/diagrams/topology-<view>.svg`, then the existing svgo pass; a new page `concepts/fleet-topology.md` embeds both, says what is derived and what is declared, and how to regenerate.

**Q8. Visual diffs in review?**
The text diff of `fleet.json` and the two `.d2` files is the review artifact. Rendering base and head side by side in CI is extra machinery; the docs preview already shows the rendered head.
Chosen: out of scope.

## Trade-offs accepted

- Tier 2 is declared, not observed: it can drift from what a host actually runs. The page says so. An obligation on the existing machine checks could compare declared public names with configured virtual hosts at no new evaluation, but the operator scoped tier 2 to never evaluate host configuration, so that is an open question, not part of this change.
- We maintain a small generator ourselves instead of adopting a tool. It is a few dozen lines of pure Nix and is unit-tested.
- ELK layout of D2 is automatic; readability depends on keeping views small.

## Revision after Gate 1 (2026-11-18): presentation and browser verification

After the proposal merged (CAM-114, #4016) the operator stepped back at Gate 1 and asked where the diagrams are presented and how the browser verifies them. The direction came back as: same pipeline as the typst diagrams (d2 → SVG → svgo → `public/diagrams`), words kept as `<text>`, home at `concepts/fleet-topology` linked from the architecture overview and build-service-topology, themes handled as the existing diagrams handle them; a Playwright witness in the existing e2e suite with a data-derived oracle and a negative control; screenshots of both views in the browser-evidence report on each pull request so a reviewer sees before and after; no pixel-snapshot gate; vitest only if the page has TypeScript logic.

What the repository says (grounding for the forks below):
- `justfile:963-983`: typst loop, then `svgo --quiet` over every SVG, no config file; `package.nix:121-136` mirrors it.
- Existing diagrams are `<img>` (`reading-paths.md:21`, `development/index.md:11`); `custom.css:19-28` only centres them; nothing handles dark mode.
- typst SVGs have no `<text>` at all: `reading-paths.typ` compiled to 0 `<text>`, 239 `<use>`, 153 `<path>`.
- svgo 4.1.0 default preset on the prototype's D2 render: 94 `<text>` before and after; 94 `<rect>` became paths; styles merged; fonts kept.
- The e2e suite: `e2e/*.spec.ts` import `test` from `e2e/fixtures.ts`; `tests/report/policy.ts` fixes the required cases; negative controls are one config, one report override and one `check-negative-report.ts` mode each, and each asserts exactly one failing test.
- Screenshots are kept only on failure (`playwright.config.ts:122`); WebKit's are empty in the Nix build unless repaired.
- The reporter, validator and uploader already carry attachments of passing attempts (`completion-reporter.ts:113-115`, `validate-report.ts:320-321`, `publish-evidence.sh:580-582`), but the comment only tabulates failed attempts (`publish-evidence.sh:853-897`) and the docs say passing attempts keep none (`browser-evidence.md:28`). The publisher reads no base revision (`publish-evidence.sh:299-305`).

**R1. How are the views embedded?** `<img>`, like every other diagram. Inside an `<img>` the SVG's text is not in the page DOM: not found by find-in-page, not read by a screen reader beyond the alt text. It is still text in the served file, which the oracle reads. Inlining through MDX would make it page text but would be the only diagram embedded that way; left as an open question.

**R2. svgo settings?** None needed: the default preset keeps every `<text>`, and svgo has no text-to-outline plugin. The oracle is what guards it.

**R3. Dark theme?** Match the existing diagrams: no variant. D2's `--dark-theme` follows the OS through the SVG's own media query, which in an `<img>` disagrees with Starlight's toggle. D2's opaque white background keeps the light view legible on the dark page.

**R4. Oracle source?** The committed `fleet.json`, read by the test with Node; SVGs fetched through `page.request` and parsed with `DOMParser`. Whole-element `textContent` equality, not substring.

**R5. Negative control?** Its own config and check: adding it to an existing negative config would break their exactly-one-failure assertion.

**R6. Screenshots: which engine, and how do they reach the reviewer?** Chromium only, attached on the passing attempt. They already reach the uploaded bundle; only the comment needs a `Rendered views` section, with the base revision's same-named views beside them. The base revision's field in nixbot's event is unknown; open question.

**R7. Pixel snapshots, vitest?** Neither: an intended topology change would fail a snapshot, the text diffs are the record, and the page has no TypeScript logic for vitest to test.
