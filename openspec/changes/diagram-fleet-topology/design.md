## Context

The fleet's placement facts live in four places today:
- `modules/clan/inventory/machines.nix` declares each machine's `machineClass`, `tags` and `description` (ten machines, four darwin).
- `modules/clan/inventory/services/*.nix` declares fifteen clan service instances and their roles, by explicit machine or by tag (`all`, `nixos`, `peer`…). The two overlay instances are `vanixiets` (module `tincr`, peers by name plus `roles.peer.settings.devices` for phones) and `zerotier` (controller cinnabar, peers by tag `peer`, external darwin and android members by address in `roles.controller.machines.cinnabar.settings.allowedIps`).
- `modules/lib/hosts.nix` is the member registry (`flake.lib.hosts`): each member's `class` (including `android`), public `endpoints`, mesh service labels, `zerotier.address`, and the derived `fqdn` and overlay `address`. It is "the only place a member's name or overlay address is written".
- Services configured directly as NixOS modules (`modules/nixos/{nixbot,buildbot,niks3,gitea,gitea-mq,kanidm,sso-gateway,perses,matrix}.nix`, `modules/lib/cognee.nix`) carry their public names in their own files; `modules/terranix/cloudflare.nix` holds some of the DNS records.

Measured on 2026-11-18: evaluating the declared inventory with an extraction function took about 0.4 s with `--no-eval-cache`; evaluating magnetite's toplevel drvPath took 20.4 s. `self.clan.inventory.tags` resolves only `all`, `nixos` and `darwin`.

Diagrams in the docs are typst sources in `packages/docs/diagrams/*.typ`. `just diagrams-build` (`justfile:963-983`) compiles each with `typst compile --format svg` into the gitignored `packages/docs/public/diagrams/` (`packages/docs/.gitignore:2`), then runs `svgo --quiet` with no config file over every SVG there (`justfile:976-982`); the `vanixiets-docs` buildPhase mirrors those two loops (`pkgs/by-name/vanixiets-docs/package.nix:121-136`). Pages embed the results as Markdown images, i.e. `<img>` (`guides/reading-paths.md:21`, `development/index.md:11`), centred by `custom.css:19-28`; there is no light/dark handling for diagrams anywhere in `custom.css`. typst emits glyphs as `<use>`/`<path>`: compiling `reading-paths.typ` on 2026-11-18 gave 0 `<text>`, 239 `<use>`, 153 `<path>`, so no existing diagram's words are text. d2 v0.9.0 is in `modules/home/development/tools.nix` but not in the devshell.

The docs package's browser checks are Playwright specs in `packages/docs/e2e/` (`documentation-pages.spec.ts`, `homepage.spec.ts`, `reader-journey.spec.ts`, all importing `test` from `e2e/fixtures.ts`), run by `just docs-test-e2e` (`justfile:1007`) and, in CI, by the report producer `passthru.tests.e2e-report` (`package.nix:234`) and verdict `e2e` (`package.nix:441-443`). `tests/report/policy.ts:3-23` lists every required case per config, so a new spec must be added there. Negative controls are separate configs and report overrides checked by `tests/report/check-negative-report.ts` (modes at `:8-14`, exactly one failing test asserted at `:19` and `:27-28`), e.g. `e2e-action-negative-control` (`package.nix:463-478`), registered in `modules/checks/package-tests.nix:36-44`. The config keeps screenshots only on failure (`playwright.config.ts:122`); WebKit screenshots in the Nix build are empty without the screencast repair (`tests/report/README.md`, "WebKit failure screenshots"). The completion reporter records every attachment with a path on every attempt (`completion-reporter.ts:113-115`), the validator requires only that each exists and is nonempty (`validate-report.ts:320-321`), and the publisher uploads every referenced PNG (`modules/apps/docs/publish-evidence.sh:580-582`), but its PR comment tabulates failed attempts only (`publish-evidence.sh:853-897`), and the docs say "Passing attempts keep no attachments" (`concepts/browser-evidence.md:28`). A comment is posted only when the report's output path differs from every report `main` published (`browser-evidence.md:32-41`). The publisher reads the event's `pullRequest.number` and `pullRequest.headRev` (`publish-evidence.sh:299-305`) and no base revision. Unit tests are vitest (`just docs-test-unit`, `justfile:1002`; `package.json:33`), covering `src/components/Card.astro` and `src/utils/formatters.ts`.

The research pass and the approach comparison are in `brainstorm.md`; the operator approved the inventory-to-D2 approach and this scope on 2026-11-18. Stakeholders: the operator (reads the map to plan CAM-112 and reviews placement changes), and agents that change placement and must regenerate.

## Goals / Non-Goals

**Goals:**
- A fleet map showing every host and platform, each host's clan service roles and declared services, both fleet networks with their members (phones included), and the public edge.
- The map is committed as text, so a placement change shows as a diff in the same change, and a stale map fails a check before merge.
- Keeping the map honest costs about as much as evaluating the inventory, with no host configuration evaluated and a static check key set.
- Both views render in the docs site through the existing diagrams pipeline, with their words kept as SVG `<text>`.
- A browser witness in the existing e2e suite proves the published page and both images load and that every host and fleet network in the committed `fleet.json` appears as text in the served SVGs, with a negative control proving the witness can fail.
- A reviewer of a change that alters the map sees the rendered views of the base and of the head in the change's browser-evidence comment.

**Non-Goals:**
- Discovering services from host configurations (tier 2 is declared by hand).
- Rendered visual diffs computed in CI (the evidence comment shows base and head side by side; no image is compared).
- A pixel-snapshot gate (`toHaveScreenshot`): an intended topology change would fail it, and the `fleet.json` and `.d2` diffs are the change record.
- vitest: the page is Markdown with two images and no TypeScript logic, so there is nothing for a unit test to exercise; add one only if a component renders from `fleet.json`.
- A dark-theme variant of the diagrams (none of the existing diagrams has one; see D12).
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
- **Choice**: `just diagrams-build` and the `vanixiets-docs` buildPhase each add a loop: `d2 --layout elk diagrams/topology/<view>.d2 public/diagrams/topology-<view>.svg` for `fleet` and `network`, after the typst loop and before the existing svgo loop, so the D2 SVGs take the same `svgo --quiet` pass (default preset, no config file) as the typst ones. `pkgs.d2` joins the package's `nativeBuildInputs` and the default devshell. The `lib.fileset` of the docs package already includes `packages/docs` (`package.nix:88-93`), so the `.d2` sources and `fleet.json` are in its source and in the e2e report's.
- **Rationale**: The docs package mirrors the recipe by design ("so the nix-built artifact matches the deployed site with diagrams present"); adding to one without the other would ship a site without the map. ELK gives the hierarchical layout the skill recommends for C4-like views.
- **Boundary**: source-versus-delivered. Sources are committed; SVGs are delivered by the build and stay gitignored.
- **Alternatives considered**: astro-d2 code blocks (renders inline Markdown fences, not generated files, and adds an Astro integration); committing SVGs (binary-ish diffs, a second drift surface).

### D9: A concepts page
- **Choice**: `packages/docs/src/content/docs/concepts/fleet-topology.md` embeds `/diagrams/topology-fleet.svg` and `/diagrams/topology-network.svg` as Markdown images, like every existing diagram, with alt text that names the view and says the names are in the image's text, explains what is derived (inventory, registry) and what is declared (`flake.lib.topologyFacts`, true only as last recorded), and names `just topology-generate` and the freshness check. Listed in `concepts/index.md` and linked from `architecture-overview.md` and `build-service-topology.md`.
- **Rationale**: The map belongs with the other architecture concepts; the trust statement is the behavioral requirement that a person can tell how far to trust it.

### D10: Fleet-wide roles and naming in the views
- **Choice**: A role is "fleet-wide" when its resolved members equal the set of all inventory machines. Node ids are sanitized names (`[^A-Za-z0-9_]` → `_`); labels keep the original names.
- **Rationale**: Equality with the full set is exact and needs no list of special instances; a role that covers all but one machine stays visible on each host, which is the case worth seeing.

### D11: svgo's default preset keeps D2's words as `<text>`
- **Choice**: No svgo configuration; the existing `svgo --quiet` pass applies.
- **Rationale**: Measured on 2026-11-18 with svgo 4.1.0 (the devshell's) on the prototype's ELK render of a ten-host `fleet.d2`: before, 94 `<text>`, 94 `<rect>`, 17 `<path>`, 51 538 bytes; after, 94 `<text>`, 1 `<rect>`, 96 `<path>`, 45 941 bytes. The default preset turned rectangles into paths and merged the two `<style>` blocks, keeping the three `@font-face` rules and every `<text>` with its content (`>magnetite<` once before and after). svgo has no plugin that converts text to outlines, so no preset change is needed to keep names as text; the oracle in D13 fails if a later svgo release changes that.
- **Boundary**: source-versus-delivered. Text survives from the committed `.d2` to the delivered SVG; the oracle reads the delivered SVG.
- **Alternatives considered**: a `svgo.config.mjs` disabling `convertShapeToPath` (no benefit for text; a second convention beside the existing no-config pass).

### D12: Light theme only, with D2's own background, as the existing diagrams
- **Choice**: Render with D2's default theme (0) and no `--dark-theme`; the SVG keeps D2's opaque background so its text stays legible on Starlight's dark page.
- **Rationale**: The existing typst diagrams have no theme handling (`custom.css` has only the centring rule at `:19-28`). D2's `--dark-theme` switches on the SVG's own `prefers-color-scheme` media query, which inside an `<img>` follows the operating system, not Starlight's theme toggle, so a reader who picks dark in the site while the OS is light would get the light diagram anyway; the two would disagree without a site-side mechanism no other diagram has.
- **Alternatives considered**: `--dark-theme 200` (disagrees with the site toggle, as above); a CSS `filter: invert()` for `[data-theme='dark']` (inverts the palette's meaning); two SVGs switched by `<picture>` (needs HTML in Markdown and the same OS-versus-toggle problem).

### D13: A browser witness in the existing e2e suite
- **Choice**: A helper `e2e/fleet-topology.ts` (as `e2e/reader-journey.ts` is shared with its negative control) and a spec `e2e/fleet-topology.spec.ts` importing `test` from `e2e/fixtures.ts`, with three tests:
  - `fleet topology page loads`: `/concepts/fleet-topology/` answers 200, shows the level-1 heading `Fleet topology`, and shows the sentence saying which facts are declared.
  - `both fleet topology diagrams load`: for each view, the image located by its alt text has non-empty alt text, `naturalWidth > 0` (as `homepage.spec.ts:80-86` does for the hero), and its `src` answers 200 with a non-empty `image/svg+xml` body.
  - `every host and network in fleet.json is text in the diagrams`: reads the committed `diagrams/topology/fleet.json` from the test's working directory with Node, takes every `machine/<name>` and `network/<name>` key, fetches both served SVGs through `page.request`, parses each in the page with `DOMParser`, and asserts each machine name is the content of a `<text>` in `topology-fleet.svg` and each network name and member is in `topology-network.svg`. On Chromium only, it then attaches element screenshots of both images as `view-fleet.png` and `view-network.png` via `testInfo.attach` with a path.
  The three cases join `requiredCases["playwright.config.ts"]` in `tests/report/policy.ts`.
- **Rationale**: The oracle is derived from the committed data, not from a hand list, so it can't drift from the map and fails exactly when a host or network falls out of the rendering (or svgo starts outlining text). Because the image is an `<img>`, its words are not in the page DOM, so the oracle reads the served SVG, which is what the browser decodes. Screenshots on Chromium only: one engine is enough for a reviewer's picture, and WebKit's screenshots are empty in the Nix build without the failure-only repair in `e2e/fixtures.ts`.
- **Alternatives considered**: a hard-coded host list (drifts); reading text through the accessibility tree (an `<img>` exposes only its alt text); inlining the SVG to read the DOM (open question 6).

### D14: A negative control for the oracle
- **Choice**: `tests/negative-control/fleet-topology.spec.ts` routes `**/diagrams/topology-fleet.svg`, removes the `<text>` whose content is the first `machine/<name>` in `fleet.json`, and runs the unchanged oracle from `e2e/fleet-topology.ts`; config `playwright.topology-negative.config.ts` (Chromium); report override and check `passthru.tests.e2e-topology-negative-control` in `package.nix`, registered in `modules/checks/package-tests.nix`; mode `topology` in `check-negative-report.ts`, asserting the single test failed on every attempt as a product failure with the dropped name in `results.json`; its case added to `policy.ts` for the new config and `requiredProjects` returning `["chromium"]` for it.
- **Rationale**: The same pattern as `e2e-action-negative-control` (`package.nix:463-478`): the deliberate defect is in the intercepted response, the spec under test is unchanged, and the check proves the oracle can fail.
- **Alternatives considered**: adding the case to `playwright.negative.config.ts` (`check-negative-report.ts:19-28` asserts exactly one failing test per report, so the existing controls would break).

### D15: Base and head views in the browser-evidence comment
- **Choice**: The publisher's comment gains a `Rendered views` section listing each passing-attempt attachment named `view-*.png` as an image link for the head, and beside it the same-named attachment from the report published for the pull request's base revision, resolved through the same nixbot build lookup `main` mode uses (`publish-evidence.sh:265-354`) and read from tier ttl-90d; when the base report or its `view-*.png` is absent, the section says so. `concepts/browser-evidence.md:28` and `tests/report/README.md` are corrected to say passing attempts may carry named view screenshots, and `modules/checks/publish-evidence-rehearsal.nix` gains a fixture with them.
- **Rationale**: The reporter, validator and uploader already carry passing-attempt attachments (Context); only the comment ignores them. A topology change changes the site build and therefore the report path, so such a change always gets a comment (`browser-evidence.md:32-40`). Showing base and head side by side gives the reviewer the visual before and after without an image comparison gate.
- **Boundary**: first-party only (publisher, docs, rehearsal).
- **Alternatives considered**: head only (no "before"); attaching base screenshots in the report itself (the report would depend on another revision's build, breaking its input-derived identity).
- **As implemented (Q21)**: a view is keyed by its file name with the `-<40 hex>` suffix removed that Playwright appends when it copies an attachment (`attachments/view-fleet-<sha1>.png` is `view-fleet.png`). The suffix is a SHA-1 of the source path, not of the image (`calculateSha1(options.path)`, `playwright/lib/worker/workerProcessEntry.js:96-100`), so it did not change when the picture changed from 632 to 1600 px wide. The base revision is resolved in order: (1) a base-revision field of nixbot's pull-request event, which does not exist at the pinned nixbot (`171a8c77`; the payload carries `baseRef`, a branch name, `nixbot/forge_pr.py:37-51`), so this step yields nothing today; (2) the merge base of the head with `baseRef`, from GitHub's compare API (`.merge_base_commit.sha`) rather than `git merge-base`, because the `browser-evidence` effect runs without a checkout (nixbot mounts the PR clone only when an effect sets `__nixbot_effect_checkout`, which this repository's registry sets for scheduled triggers only); (3) the newest of `main`'s five newest commits whose report is published. A merge base whose report is not in ttl-90d says so rather than falling back to (3), which would show another revision's picture. The main-mode build lookup moved unchanged into a shared `build_of`.

### D16: A generated Markdown table on the page (Q20)
- **Choice**: `flake.lib.fleetTopology.files` gains `fleet-table.md`: a table of hosts (platform, service roles, declared services, fleet networks), a line naming the roles held by every host, a table of fleet networks with their members, and a table of public hostnames with host, service and ports. It is committed beside the `.d2` files, covered by `fleet-topology-fresh`, and rendered on the page by importing it into `concepts/fleet-topology.mdx` (`import { Content as FleetTable } from ".../fleet-table.md"`). The images stay `<img>`.
- **Rationale**: The operator chose page text over inlined SVGs, so host names are found by find-in-page and read by screen readers without a second embedding convention. The table is generated by the same pure function and tested by `testTableRow`, so it needs no TypeScript and no vitest.
- **Boundary**: source-versus-delivered; the committed Markdown is rendered into the delivered page by Astro.
- **Alternatives considered**: a TypeScript component reading `fleet.json` (adds logic that would then need vitest); inlining the SVGs (rejected by the operator).

## Risks / Trade-offs

- [Risk] Declared facts drift from what hosts run → Mitigation: the page says they are declared; open question 1 offers an obligation on the existing machine checks at no added evaluation, if the operator wants it.
- [Risk] Concurrent changes regenerate the files and conflict in `fleet.json` → Mitigation: line-per-entry format confines conflicts to the touched entries; regenerate after rebase, and the check catches a bad merge.
- [Risk] ELK layout of `fleet.d2` grows unreadable as hosts are added → Mitigation: the every-host legend; a further view per platform is a cheap addition later.
- [Risk] d2's output or validation changes on a nixpkgs bump → Mitigation: the check pins d2 from the flake's nixpkgs; committed `.d2` text doesn't depend on d2's version, only rendering does.
- [Risk] The check's evaluation turns out more expensive than the inventory measurement → Mitigation: measured at apply (task 3.3); if the value forces anything heavy, it's a defect in D1's field discipline.
- [Trade-off] We maintain a small generator instead of adopting nix-topology → accepted: nix-topology has no darwin support (issue #144) and costs a full evaluation per host.
- [Trade-off] Service-to-service dependencies are not drawn → accepted for this change; open question 3.
- [Risk] Host names inside an `<img>` are not found by the browser's find-in-page or read by a screen reader → Mitigation: alt text and the page prose name the views; inlining is open question 6.
- [Risk] The base report for a pull request is older than ttl-90d or was never published → Mitigation: the comment says the base view is unavailable instead of omitting the section.
- [Risk] The `Rendered views` section adds two images to every comment on a docs change, topology or not → Mitigation: it appears only when the report carries `view-*.png`, which only the fleet-topology spec attaches.
- [Trade-off] Light diagrams on the dark site theme → accepted to match the existing diagrams (D12).

## Migration Plan

N/A — this change does not involve a deployment change. It adds library code, two checks, committed text files, a docs page and build steps; no host's closure changes, so nothing deploys. The docs site picks up the page at its next deploy.

## Open Questions

Settled by the operator on 2026-11-18 (Q20-Q22):

1. No hostname cross-check against host configurations: tier 2 stays pure, and declared facts are not compared with configured virtual hosts.
2. cinnabar's mesh-only services (kanban, matrix, hermes, ntfy, omnigraph, radicle) are listed in `flake.lib.topologyFacts`.
3. Dependency arrows between services come later, in their own change.
4. Numbering and table merges stay as stated: A154 is renumbered at archive if another change takes it first, and whichever of this change and `migrate-mesh-to-tincr` archives second merges the other's designation rows.
5. The CAM-109 cutover removes the generator's ZeroTier branch: `migrate-mesh-to-tincr` group 12 (Retire ZeroTier) carries the task, added by this change, to delete the `zerotier` branch of `mkFleetTopology` (the `allowedIps` matching and the `external` label in `modules/lib/fleet-topology.nix`), its fixture cases in `modules/lib/fleet-topology.test.nix`, and to regenerate `packages/docs/diagrams/topology/`.
6. No inline SVGs; the `<img>` convention stays. Instead a Markdown table of hosts, services and networks is generated from the same model as `fleet-table.md`, committed beside the `.d2` files, covered by the freshness check, and imported into the page (D16).
7. The "before" image is resolved, in order, from a base-revision field of nixbot's pull-request event if one exists, else the merge base computed with git in the effect, else the newest report published from `main` (D15).

## Approval

The operator approved Gate 1 rows G1-G7 and the implementation of CAM-114 on 2026-11-18 (Q22), with the decisions recorded under Open Questions (Q20, Q21 and the settled questions 1-5).

## Gate 1 modality verdicts

This table is the pre-apply spec-and-feature alignment record.
The repository has no BDD runner and no `.feature` file (`features/` is empty), so no row routes to a Gherkin scenario; each requirement is witnessed by a build gate (`nix eval`, the nix-unit check, the freshness check, the docs package build), by the Playwright e2e suite with its report and negative control, or by an observation recorded in `verify.md`.
No pixel snapshot is a witness (D13 and Non-Goals), and no vitest case is, because the page has no TypeScript logic.

| Row | Requirement | Capability | Stratum | Modality | Witness |
|---|---|---|---|---|---|
| G1 | The documentation shows a fleet map of every host and the services it runs | `fleet-topology-map` | behavioral | build gate (unit check, freshness check) and browser witness (Playwright) with negative control | `eval-fleet-topology`, `fleet-topology-fresh`; `e2e/fleet-topology.spec.ts` cases `fleet topology page loads`, `both fleet topology diagrams load`, `every host and network in fleet.json is text in the diagrams` in `package-vanixiets-docs-test-e2e`; `package-vanixiets-docs-test-e2e-topology-negative-control`; tasks 1.2, 1.3, 2.1, 4.3, 5.1, 5.2 |
| G2 | The fleet map shows each fleet network and the public edge | `fleet-topology-map` | behavioral | build gate (unit check, freshness check) and browser witness (Playwright) | `eval-fleet-topology`, `fleet-topology-fresh`; the oracle case over `topology-network.svg` in `package-vanixiets-docs-test-e2e`; tasks 1.2, 1.4, 2.2, 4.3, 5.1 |
| G3 | The fleet map is derived and says which of its facts are declared | `fleet-topology-map` | behavioral | build gate (freshness check fails on a hand edit) and browser witness (page states the declared facts) | `fleet-topology-fresh` mutants; case `fleet topology page loads`; tasks 3.2, 4.2, 5.1 |
| G4 | A change to the fleet's placement carries its fleet map change | `fleet-topology-map` | behavioral | build gate (freshness check fails on an unregenerated placement change) | `fleet-topology-fresh` mutants; tasks 3.2, 6.2 |
| G5 | A person reviewing a change to the fleet map sees its pictures before and after | `fleet-topology-map` | behavioral | build gate (publisher rehearsal) and observation of the evidence comment | `publish-evidence-rehearsal` view-screenshot fixture; tasks 5.3, 6.1 |
| G6 | Each `fleet-topology-map-interface` requirement | `fleet-topology-map-interface` | interface | build gate and browser witness | tasks 1.1-1.5, 2.1-2.3, 3.1-3.3, 4.1-4.3, 5.1-5.3 |
| G7 | A154 | `world-assumptions` | world | monitoring (violation scenarios) | `eval-fleet-topology` and `fleet-topology-fresh` fail on a clan-core bump that changes the declared inventory's shape; task 3.3's cost measurement re-checks the no-host-evaluation half |
