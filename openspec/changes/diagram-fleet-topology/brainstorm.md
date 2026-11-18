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
