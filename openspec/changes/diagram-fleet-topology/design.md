## Context

The fleet's placement facts live in four places today:
- `modules/clan/inventory/machines.nix` declares each machine's `machineClass`, `tags` and `description` (ten machines, four darwin).
- `modules/clan/inventory/services/*.nix` declares fifteen clan service instances and their roles, by explicit machine or by tag (`all`, `nixos`, `peer`…). The two overlay instances are `vanixiets` (module `tincr`, peers by name plus `roles.peer.settings.devices` for phones) and `zerotier` (controller cinnabar, peers by tag `peer`, external darwin and android members by address in `roles.controller.machines.cinnabar.settings.allowedIps`).
- `modules/lib/hosts.nix` is the member registry (`flake.lib.hosts`): each member's `class` (including `android`), public `endpoints`, mesh service labels, `zerotier.address`, and the derived `fqdn` and overlay `address`. It is "the only place a member's name or overlay address is written".
- Services configured directly as NixOS modules (`modules/nixos/{nixbot,buildbot,niks3,gitea,gitea-mq,kanidm,sso-gateway,perses,matrix}.nix`, `modules/lib/cognee.nix`) carry their public names in their own files; `modules/terranix/cloudflare.nix` holds some of the DNS records.

Measured on 2026-11-18: evaluating the declared inventory with an extraction function took about 0.4 s with `--no-eval-cache`; evaluating magnetite's toplevel drvPath took 20.4 s. `self.clan.inventory.tags` resolves only `all`, `nixos` and `darwin`.

Diagrams in the docs are typst sources in `packages/docs/diagrams/*.typ`, compiled to gitignored SVGs in `packages/docs/public/diagrams/` by `just diagrams-build` and, separately, by the buildPhase of `pkgs/by-name/vanixiets-docs/package.nix`, which mirrors the recipe. d2 v0.9.0 is in `modules/home/development/tools.nix` but not in the devshell.

The research pass and the approach comparison are in `brainstorm.md`; the operator approved the inventory-to-D2 approach and this scope on 2026-11-18. Stakeholders: the operator (reads the map to plan CAM-112 and reviews placement changes), and agents that change placement and must regenerate.

## Goals / Non-Goals

**Goals:**
- A fleet map showing every host and platform, each host's clan service roles and declared services, both fleet networks with their members (phones included), and the public edge.
- The map is committed as text, so a placement change shows as a diff in the same change, and a stale map fails a check before merge.
- Keeping the map honest costs about as much as evaluating the inventory, with no host configuration evaluated and a static check key set.
- Both views render in the docs site through the existing diagrams pipeline.

**Non-Goals:**
- Discovering services from host configurations (tier 2 is declared by hand).
- Rendered visual diffs in CI (the docs preview shows the rendered head).
- Committing SVGs, or making the map interactive (LikeC4, Structurizr).
- Changing any host's configuration, the registry's existing fields, or the inventory.
- Modeling dependencies between services beyond placement and networks (e.g. "nixbot uses niks3"); see open question 3.

## Decisions

### D1: Read `self.clan.inventory`, resolve tags ourselves
- **Choice**: The generator reads the declared inventory (`config.flake.clan.inventory`, exposed as `self.clan.inventory`), only the fields the interface spec names. Role members are the union of explicitly named inventory machines and machines carrying any of the role's tags, with `all` meaning every machine.
- **Rationale**: preferences-nix-checks-architecture lists clan inventory metadata as static data a check key set may depend on, and its worked example reads `self.clan.inventory.instances.zerotier.roles.controller.machines`. Its `tags` attribute resolves only the built-in tags, so user tags (`peer`) need our own resolution, which is unit-tested (D7).
- **Boundary**: vendored-versus-first-party. clan-core owns the inventory schema; we read a documented, declared surface instead of `clanInternals.inventoryClass` (internal, used in the prototype). A clan-core bump that changes the shape fails `eval-fleet-topology` only if fixtures go stale, so the freshness check is the live guard; A154 records the assumption.
- **Alternatives considered**: `clanInternals.inventoryClass.inventory` (internal API); evaluating `nixosConfigurations.*.config.clan.*` (host evaluation, ~20 s each, and no darwin parity).

### D2: Overlay membership from the instances plus the registry
- **Choice**: An instance whose `module.name` is `tincr` or `zerotier` is a fleet network. Its members are its role members (role label on the edge), the names in tincr's `roles.peer.settings.devices` (label `device`), and the registry members whose `zerotier.address` appears in the ZeroTier controller's `allowedIps` (label `external`). An unmatched address throws, naming it.
- **Rationale**: That is exactly how the inventory declares membership today; matching addresses back to registry names avoids a second list of ZeroTier external members. Throwing on an unmatched address makes a registry/controller mismatch visible in the check instead of silently dropping a member.
- **Alternatives considered**: listing all `android` registry members as members of both networks (pixel7 is a ZeroTier member but has not joined tincr; this would be wrong).

### D3: Pure Nix generator in `flake.lib`, no derivation for the files
- **Choice**: `modules/lib/fleet-topology.nix` defines `flake.lib.mkFleetTopology { inventory, hosts, facts } → { model, files }` and `flake.lib.fleetTopology` applied to the flake's values. `files` holds the three strings. `just topology-generate` writes them with `nix eval --raw .#lib.fleetTopology.files.<name>`; the check compares them with the committed bytes.
- **Rationale**: The text is identical on every system, so a per-system package would be a fourfold evaluation tax, and gating it to x86_64-linux would make the recipe unusable on a laptop without a remote builder. A pure function needs no system and no build, and the unit test imports it with fixtures as `mesh.test.nix` imports `mesh.nix`.
- **Boundary**: source-versus-delivered. The committed files are the source of review; the SVGs are delivered artifacts built from them (D8) and stay gitignored.
- **Alternatives considered**: jq-based derivation as in the prototype (ties committed bytes to one jq build and needs a system); generating in the docs build only (no reviewable text).

### D4: Two D2 views and a line-per-entry JSON
- **Choice**: `fleet.json` is one JSON object, one sorted top-level entry per line (`machine/…`, `instance/…`, `network/…`, `facts/…`), each value from `builtins.toJSON`. `fleet.d2` groups hosts by class with each host's `<instance>/<role>` memberships and declared services; roles held by every machine go once into an `on every host` legend. `network.d2` draws each fleet network as a cloud with labelled member edges and an `internet` node with one edge per public hostname. Both carry a title and a key; dashed edges for overlay membership, solid for public reachability.
- **Rationale**: The prototype's single view was correct but too tall to read. Separate views follow the skill's semantic-layers rule (add a layer, don't redraw), and the every-host legend removes the repetition (emergency-access, sshd, tor, the user instances when they span every machine). One entry per line makes a placement change a one-line JSON diff without needing jq.
- **Alternatives considered**: one combined view (unreadable); JSON via `builtins.toJSON` on the whole model (one line, useless diff); omitting JSON (the D2 files alone mix layout with facts).

### D5: Tier 2 as `flake.lib.topologyFacts`, beside the registry, not inside it
- **Choice**: A new literal attribute set in `modules/lib/topology-facts.nix`, keyed by registry member, `services = [ { name; hostnames ? []; ports ? []; } ]`. Seeded at apply from the modules named in Context: magnetite (nixbot, buildbot, niks3/cache, gitea, gitea-mq, kanidm, sso-gateway, perses/obs, cognee/kb, omnigent's `omni` is already a clan role) and cinnabar (matrix and the services in its registry `services` labels where they have public names). Ports are written as the operator knows them, not read from firewall settings. The generator throws on a key that is not a registry member and never reads a host configuration.
- **Rationale**: The operator fixed tier 2 as a small hand-written per-host set that never evaluates host configurations. Putting it in `hosts.nix` would mix "facts the mesh needs" with "facts only the map needs", and `flake.lib` is `lazyAttrsOf raw`, so it can't be split across files at the same path; a sibling attribute keeps one owner per fact. Class, public endpoints and overlay addresses stay in the registry and are read from there, never restated.
- **Boundary**: source-versus-delivered. These are declarations about what is delivered on hosts; nothing ties them to the delivered configuration (trust boundary in the interface spec; open question 1).
- **Alternatives considered**: new fields on `flake.lib.hosts` members (couples the map to the mesh registry's consumers); deriving public names from `modules/terranix/cloudflare.nix` (a separate module evaluation, and incomplete: `git`, `nixbot`, `mq` and `buildbot` are not there).

### D6: `fleet-topology-fresh`, a codegen drift check on x86_64-linux
- **Choice**: `modules/checks/fleet-topology.nix` defines `checks = lib.optionalAttrs (system == "x86_64-linux") { fleet-topology-fresh = …; }`. The value is a `runCommand` whose source is `lib.fileset.toSource` over `packages/docs/diagrams/topology/` only; it `diff`s each committed file against `pkgs.writeText` of its `files` string, prints the differing file and `just topology-generate` on mismatch, and runs `d2 validate` on both committed views. `nativeBuildInputs = [ pkgs.d2 ]`.
- **Rationale**: It is the skill's codegen drift pattern. The key set is a literal, so computing check names never forces the inventory. The value evaluates only the inventory, the registry and the facts. One system, because the derivation's inputs don't vary by system. `d2 validate` is behaviour of a built artifact (the views parse), so it belongs in a derivation, and catching it here beats catching it in the docs build.
- **Cost**: measured at apply per `references/evaluation-cost.md`: the check's own drvPath evaluation (time and allocation), and an unrelated check's drvPath cost before and after, which must not change.
- **Alternatives considered**: no check, regenerate in the docs build (drift goes unnoticed in review); running the freshness check on every system (needless duplication).

### D7: Unit-test the pure logic with nix-unit
- **Choice**: `modules/lib/fleet-topology.test.nix` builds `checks.x86_64-linux.eval-fleet-topology` with `flake.lib.mkEvalCheck`, importing `./fleet-topology.nix` with a stub `config`, over literal fixtures: user-tag resolution, `all`, a named machine absent from the inventory, tincr devices, ZeroTier external members by address, an unmatched address (throws), an unknown facts key (throws), the every-host legend, and the `fleet.json` line format. Expected values are literals, not recomputed.
- **Rationale**: Placement ladder: facts about our own pure logic belong in an in-process unit test. Each case is one failure mode the freshness check can't isolate. Throw cases use `expectedError`, since `builtins.tryEval` doesn't see the message.
- **Alternatives considered**: relying on the freshness check alone (it only shows that output changed, not that the logic is right).

### D8: Render with d2 in both diagram pipelines
- **Choice**: `just diagrams-build` and the `vanixiets-docs` buildPhase each add a loop: `d2 --layout elk diagrams/topology/<view>.d2 public/diagrams/topology-<view>.svg` for `fleet` and `network`, before the existing svgo pass. `pkgs.d2` joins the package's `nativeBuildInputs` and the default devshell. The `lib.fileset` of the docs package already includes `packages/docs`, so the `.d2` sources are in its source.
- **Rationale**: The docs package mirrors the recipe by design ("so the nix-built artifact matches the deployed site with diagrams present"); adding to one without the other would ship a site without the map. ELK gives the hierarchical layout the skill recommends for C4-like views.
- **Boundary**: source-versus-delivered. Sources are committed; SVGs are delivered by the build and stay gitignored.
- **Alternatives considered**: astro-d2 code blocks (renders inline Markdown fences, not generated files, and adds an Astro integration); committing SVGs (binary-ish diffs, a second drift surface).

### D9: A concepts page
- **Choice**: `packages/docs/src/content/docs/concepts/fleet-topology.md` embeds `/diagrams/topology-fleet.svg` and `/diagrams/topology-network.svg` with descriptive alt text, explains what is derived (inventory, registry) and what is declared (`flake.lib.topologyFacts`, true only as last recorded), and names `just topology-generate` and the freshness check. Listed in `concepts/index.md` and linked from `architecture-overview.md` and `build-service-topology.md`.
- **Rationale**: The map belongs with the other architecture concepts; the trust statement is the behavioral requirement that a person can tell how far to trust it.

### D10: Fleet-wide roles and naming in the views
- **Choice**: A role is "fleet-wide" when its resolved members equal the set of all inventory machines. Node ids are sanitized names (`[^A-Za-z0-9_]` → `_`); labels keep the original names.
- **Rationale**: Equality with the full set is exact and needs no list of special instances; a role that covers all but one machine stays visible on each host, which is the case worth seeing.

## Risks / Trade-offs

- [Risk] Declared facts drift from what hosts run → Mitigation: the page says they are declared; open question 1 offers an obligation on the existing machine checks at no added evaluation, if the operator wants it.
- [Risk] Concurrent changes regenerate the files and conflict in `fleet.json` → Mitigation: line-per-entry format confines conflicts to the touched entries; regenerate after rebase, and the check catches a bad merge.
- [Risk] ELK layout of `fleet.d2` grows unreadable as hosts are added → Mitigation: the every-host legend; a further view per platform is a cheap addition later.
- [Risk] d2's output or validation changes on a nixpkgs bump → Mitigation: the check pins d2 from the flake's nixpkgs; committed `.d2` text doesn't depend on d2's version, only rendering does.
- [Risk] The check's evaluation turns out more expensive than the inventory measurement → Mitigation: measured at apply (task 3.3); if the value forces anything heavy, it's a defect in D1's field discipline.
- [Trade-off] We maintain a small generator instead of adopting nix-topology → accepted: nix-topology has no darwin support (issue #144) and costs a full evaluation per host.
- [Trade-off] Service-to-service dependencies are not drawn → accepted for this change; open question 3.

## Migration Plan

N/A — this change does not involve a deployment change. It adds library code, two checks, committed text files, a docs page and build steps; no host's closure changes, so nothing deploys. The docs site picks up the page at its next deploy.

## Open Questions

1. Should a fleet obligation on the existing `nixos-<host>` machine checks compare `flake.lib.topologyFacts` hostnames with each host's configured virtual hosts? It adds no evaluation (those checks already evaluate the configuration) but it does read host configuration, which the operator's scope for tier 2 excludes. Deferred to the operator.
2. Should tier 2 also seed cinnabar's mesh-only services (registry `services` labels: kanban, matrix, hermes, ntfy, omnigraph, radicle) as declared services, or is drawing them as mesh names from the registry enough?
3. Should a later view draw dependencies between services (nixbot → niks3, services → kanidm, agents → otel ingress)? That needs either more declared facts or host evaluation.
4. A154 is the next free number after the in-flight A153 (`evaluate-nixbot-with-iets`); if another change archives first with A154, renumber at archive. Likewise this change and `migrate-mesh-to-tincr` both modify the designation table (that change generalises `overlay network`); whichever archives second merges the other's rows.
5. After the tincr cutover (CAM-109) the ZeroTier instance disappears; D2's ZeroTier branch then has nothing to read. Remove it in the cutover change, or keep it for history?

## Gate 1 modality verdicts

This table is the pre-apply spec-and-feature alignment record.
The repository has no BDD runner and no `.feature` file (`features/` is empty), so no row routes to a Gherkin scenario; each requirement is witnessed by a build gate (`nix eval`, the nix-unit check, the freshness check, the docs package build) or an observation recorded in `verify.md`.

| Requirement | Capability | Stratum | Modality | Witness |
|---|---|---|---|---|
| The documentation shows a fleet map of every host and the services it runs | `fleet-topology-map` | behavioral | build gate (unit check, freshness check) and observation of the rendered page | tasks 1.2, 1.3, 2.1, 4.3, 5.1 |
| The fleet map shows each fleet network and the public edge | `fleet-topology-map` | behavioral | build gate (unit check, freshness check) and observation | tasks 1.2, 1.4, 2.2, 4.3, 5.1 |
| The fleet map is derived and says which of its facts are declared | `fleet-topology-map` | behavioral | build gate (freshness check fails on a hand edit) and observation of the page text | tasks 3.2, 4.2, 5.2 |
| A change to the fleet's placement carries its fleet map change | `fleet-topology-map` | behavioral | build gate (freshness check fails on an unregenerated placement change) | tasks 3.2, 5.2 |
| Each `fleet-topology-map-interface` requirement | `fleet-topology-map-interface` | interface | build gate | tasks 1.1-1.5, 2.1-2.3, 3.1-3.3, 4.1-4.3 |
| A154 | `world-assumptions` | world | monitoring (violation scenarios) | `eval-fleet-topology` and `fleet-topology-fresh` fail on a clan-core bump that changes the declared inventory's shape; task 3.3's cost measurement re-checks the no-host-evaluation half |
