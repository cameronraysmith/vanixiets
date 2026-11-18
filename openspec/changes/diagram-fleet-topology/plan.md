# Fleet Topology Map Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Generate a fleet map (one JSON summary, two D2 views) from the declared clan inventory, the member registry and a small set of declared facts, commit it as text, keep it fresh with a cheap x86_64-linux check, render it on a docs concepts page, witness the published page with Playwright against the committed data, and show the rendered views before and after in the browser-evidence comment.

**Architecture:** A pure Nix function `flake.lib.mkFleetTopology` turns `self.clan.inventory`, `self.lib.hosts` and `self.lib.topologyFacts` into `{ model, files }`. `just topology-generate` writes `files` with `nix eval --raw`; `checks.x86_64-linux.fleet-topology-fresh` diffs them against the committed copies and runs `d2 validate`; a nix-unit check tests the pure logic over literal fixtures. Both docs pipelines render the `.d2` views to gitignored SVGs through the existing svgo pass. A Playwright spec checks the page and that every host and network in `fleet.json` is `<text>` in the served SVGs, with a negative control; on Chromium it attaches view screenshots, which the evidence publisher shows beside the base revision's.

**Tech Stack:** Nix (flake-parts, import-tree), clan-core inventory, nix-unit via `flake.lib.mkEvalCheck`, d2 v0.9.0 (nixpkgs) with ELK layout, svgo 4.1.0 default preset, Astro Starlight, Playwright with the typed browser-evidence report, bash/jq publisher.

**Spec:** `openspec/changes/diagram-fleet-topology/` — `design.md` (D1-D15, Gate 1 table G1-G7), `specs/fleet-topology-map/spec.md`, `specs/fleet-topology-map-interface/spec.md`, `specs/world-assumptions/spec.md` (A154 and seven designation rows), `tasks.md`.

## Global Constraints

- Never read `nixosConfigurations`, `darwinConfigurations`, `clanInternals` or an instantiated package set from the generator or the facts.
- Fleet networks are exactly the instances whose `module.name` is `tincr` or `zerotier`.
- Committed files: `packages/docs/diagrams/topology/{fleet.json,fleet.d2,network.d2}`, byte-equal to `flake.lib.fleetTopology.files`.
- Rendered files: `packages/docs/public/diagrams/topology-{fleet,network}.svg`, gitignored, via `d2 --layout elk`.
- Check names `fleet-topology-fresh` and `eval-fleet-topology`, literals under `lib.optionalAttrs (system == "x86_64-linux")`.
- `fleet.json`: one JSON object, one top-level entry per line, keys `machine/<n>`, `instance/<n>`, `network/<n>`, `facts/<host>`, sorted, values from `builtins.toJSON`.
- Every-host legend title: `on every host`. Edge labels for non-role overlay members: `device` (tincr devices), `external` (ZeroTier `allowedIps`).
- `flake.lib` is `lazyAttrsOf raw`: each new `flake.lib.<name>` lives in exactly one file.
- No svgo configuration file; D2 SVGs take the existing `svgo --quiet` pass. D2 default theme only, no `--dark-theme`.
- Diagrams are embedded as Markdown images (`<img>`), like every existing diagram.
- e2e test titles: `fleet topology page loads`, `both fleet topology diagrams load`, `every host and network in fleet.json is text in the diagrams`; negative-control title: `dropped host is rejected by the fleet topology oracle`.
- View attachments: `view-fleet.png`, `view-network.png`, Chromium only, on the passing attempt.
- No `toHaveScreenshot`, no vitest for this change.

## Review Focus

- A role naming a tag that no machine carries: the role has no members and must not throw; the host blocks simply lack it. Add a case to Task 2.
- A role that names both a tag and an explicit machine that also carries that tag: the machine appears once. Add a case to Task 2.
- A machine with no role memberships other than fleet-wide ones (blackphos today): its host block must still appear, empty except for its declared services. Add a case to Task 2.
- Names with characters D2 treats specially (`-`, `.` in hostnames such as `nixbot.scientistexperience.net`): ids are sanitized, labels quoted. Add a case to Task 2 asserting the emitted line for a dotted hostname.
- A ZeroTier `allowedIps` entry that is an IPv4 address or carries a prefix length: matching is exact string equality against `hosts.<m>.zerotier.address`; an IPv4 entry with no member throws with the address in the message. Covered by the unmatched-address case.
- A machine name that also appears as a substring of another label (e.g. `pyrite` inside a hostname): the oracle matches whole `<text>` contents, not substrings. Add a case to Task 6 by asserting equality on trimmed `textContent`.
- D2 splitting a long label across several `<text>` or `<tspan>` elements: the oracle reads each `<text>` element's full `textContent`; host and network labels must be single-line. Assert in Task 2's emitter that host and network labels contain no newline.
- The negative control's interception missing because the SVG is served from a cache-busted or differently cased path: route on `**/diagrams/topology-fleet.svg*` and assert in the control that the route was hit.
- A WebKit or Firefox attempt attaching views: the publisher would show duplicates; attach only when `browserName === "chromium"`.

---

### Task 1: Declared facts

**Files:**
- Create: `modules/lib/topology-facts.nix`

**Interfaces:**
- Produces: `flake.lib.topologyFacts :: { <member> = { services = [ { name :: string; hostnames :: [string] ? []; ports :: [int] ? []; } ]; }; }`

- [ ] **Step 1:** Read each public name from its module: `modules/nixos/nixbot.nix` (`nixbot.`), `buildbot.nix` (`buildbot.`), `niks3.nix` (`niks3.`, `cache.`), `gitea.nix` (`git.`), `gitea-mq.nix` (`mq.`), `kanidm.nix` (`accounts.`), `sso-gateway.nix` (`auth.`), `perses.nix` (`obs.`), `modules/lib/cognee.nix` (`kb.`), `matrix.nix` (`matrix.`), each under `scientistexperience.net`; confirm which host imports each module (`rg -n 'nixos\.(nixbot|buildbot|…)' modules/machines`).
- [ ] **Step 2:** Write the literal set with a header comment stating it is declared, never derived, and what keys mean. Ports: 443 for HTTPS services unless the operator says otherwise; ask the operator for any non-HTTPS port rather than reading firewall settings.
- [ ] **Step 3:** Run `nix eval --json .#lib.topologyFacts | jq 'keys'`. Expected: `["cinnabar","magnetite"]`.
- [ ] **Step 4:** Commit: route to the change's chain (`jj squash --into <chain> --use-destination-message --keep-emptied modules/lib/topology-facts.nix`).

### Task 2: Generator and its unit test

**Files:**
- Create: `modules/lib/fleet-topology.nix`
- Create: `modules/lib/fleet-topology.test.nix`

**Interfaces:**
- Consumes: `config.flake.clan.inventory`, `config.flake.lib.hosts`, `config.flake.lib.topologyFacts`.
- Produces: `flake.lib.mkFleetTopology :: { inventory, hosts, facts } -> { model, files }`; `flake.lib.fleetTopology = mkFleetTopology { … }`; `model = { machines.<n> = { class; tags; description; }; instances.<i> = { module; roles.<r> = [n]; }; networks.<i> = { module; members.<m> = role; }; everyHost = [ "<i>/<r>" ]; publicNames = [ { hostname; host; service; ports; } ]; }`; `files = { "fleet.json"; "fleet.d2"; "network.d2" }` (strings).

- [ ] **Step 1: Write the failing tests** in `fleet-topology.test.nix` following `modules/lib/mesh.test.nix`: `config.flake.lib.mkEvalCheck pkgs { name = "fleet-topology"; testFile = pkgs.writeText … }`, importing `${./fleet-topology.nix}` with `{ inherit lib; config = { flake.clan.inventory = { }; flake.lib = { hosts = { }; topologyFacts = { }; }; }; }` and taking `.flake.lib.mkFleetTopology`. Fixture: four machines (`a` nixos tags `[peer]`, `b` nixos tags `[peer]`, `c` darwin, `d` nixos tags `[]`), instances `everywhere` (`roles.default.tags.all`), `tagged` (`roles.peer.tags.peer` plus `machines.a` and `machines.ghost`), `vanixiets` (module `tincr`, peers a b c, `settings.devices.phone`), `zerotier` (controller `d` with `allowedIps = [ "fd00::c" ]`, peers by tag `peer`, so no member holds two roles in one network, as in the real inventory where cinnabar carries no `peer` tag). Hosts registry with `c.zerotier.address = "fd00::c"`, `phone.class = "android"`. Cases: `testTagResolution` (`tagged.roles.peer == ["a" "b"]`), `testAll`, `testAbsentMachine` (no `ghost`), `testNoMemberTag`, `testDevices` (`networks.vanixiets.members.phone == "device"`), `testExternal` (`networks.zerotier.members.c == "external"`), `testUnmatchedAddress` (`expectedError.type = "ThrownError"; expectedError.msg = "fd00::9"`), `testUnknownFactsKey` (msg names the key), `testEveryHost` (`everyHost == ["everywhere/default"]` and `fleet.d2` has no `everywhere/default` inside a host block), `testJsonLines` (literal expected `fleet.json` text), `testDottedHostname` (literal emitted edge line). Register `checks = lib.optionalAttrs (system == "x86_64-linux") { eval-fleet-topology = check; };`.
- [ ] **Step 2: Run to see it fail.** Run: `nix build .#checks.x86_64-linux.eval-fleet-topology`. Expected: FAIL (file `fleet-topology.nix` missing).
- [ ] **Step 3: Implement `model`** in `fleet-topology.nix` (`{ config, lib, ... }:`): `mkFleetTopology` in a `let` independent of `config`; role resolution per the interface spec; fleet-wide when the sorted members equal the sorted machine names; overlay instances by `module.name`; external members by matching `allowedIps` to `hosts.<m>.zerotier.address or null`, throwing `"fleet-topology: zerotier allowedIps entry ${addr} matches no flake.lib.hosts member"`; facts keys checked against `hosts`, throwing `"fleet-topology: topologyFacts key ${k} is not a flake.lib.hosts member"`.
- [ ] **Step 4: Implement `files`.** `fleet.json`: `"{\n" + concatStringsSep ",\n" (map (k: "  ${toJSON k}: ${toJSON v.${k}}") (sort lessThan (attrNames v))) + "\n}\n"`. `fleet.d2`: header comment `# generated by flake.lib.fleetTopology; run just topology-generate`, `title`, `direction: right`, one container per class, one per host with one child per `<i>/<r>` (not fleet-wide) and per declared service (label `name\nhostname…\n:port…`), the `on every host` legend container, and a `key` container explaining shapes. `network.d2`: a `shape: cloud` node per network, `member -> network: role` dashed edges, `internet` node and `internet -> host: hostname` solid edges. Ids via `replaceStrings`-style sanitize (`[^A-Za-z0-9_]` → `_`), labels quoted.
- [ ] **Step 5: Expose the flake values:** `flake.lib.mkFleetTopology = mkFleetTopology; flake.lib.fleetTopology = mkFleetTopology { inventory = config.flake.clan.inventory; hosts = config.flake.lib.hosts; facts = config.flake.lib.topologyFacts; };`.
- [ ] **Step 6: Run to see it pass.** Run: `nix build .#checks.x86_64-linux.eval-fleet-topology`. Expected: PASS.
- [ ] **Step 7: Integrity.** For each case, apply a one-line mutation that breaks only that behaviour (e.g. drop tag resolution, drop the `all` branch, stop filtering absent machines, drop devices, drop the throw), rerun, confirm exactly that case fails, revert. Record the list in `verify.md` later.
- [ ] **Step 8: Real data.** Run `nix eval --json .#lib.fleetTopology.model | jq '{m: (.machines|length), i: (.instances|length), n: (.networks|keys)}'`. Expected: `{"m":10,"i":15,"n":["vanixiets","zerotier"]}`; `nix eval --raw .#lib.fleetTopology.files."fleet.d2" > /tmp/f.d2 && d2 validate /tmp/f.d2`, same for `network.d2`.
- [ ] **Step 9: Commit** both files to the chain.

### Task 3: Recipe and committed files

**Files:**
- Modify: `justfile` (new recipe in the `## diagrams` section)
- Create: `packages/docs/diagrams/topology/{fleet.json,fleet.d2,network.d2}` (generated)

**Interfaces:**
- Consumes: `flake.lib.fleetTopology.files`.
- Produces: `just topology-generate`.

- [ ] **Step 1:** Add the recipe in group `diagrams`: `mkdir -p packages/docs/diagrams/topology`, then for each of the four names (`fleet.json`, `fleet.d2`, `network.d2`, `fleet-table.md`) `nix eval --raw ".#lib.fleetTopology.files.\"$f\"" > "packages/docs/diagrams/topology/$f"`.
- [ ] **Step 2:** Run `just topology-generate` twice. Expected: four files after the first; `jj diff packages/docs/diagrams/topology` unchanged by the second.
- [ ] **Step 3:** Read the files against tasks.md 2.2's list; render both with `d2 --layout elk` to `/tmp` and rasterize with `rsvg-convert` to look at them (tasks.md 2.3).
- [ ] **Step 4: Commit** the recipe and the four files to the chain.

### Task 4: Freshness check

**Files:**
- Create: `modules/checks/fleet-topology.nix`

**Interfaces:**
- Consumes: `self.lib.fleetTopology.files`, `packages/docs/diagrams/topology/`.
- Produces: `checks.x86_64-linux.fleet-topology-fresh`.

- [ ] **Step 1:** Write the module: header comment (what it pins, why x86_64-linux only, that its key set is a literal and it evaluates no host); `src = lib.fileset.toSource { root = ../../packages/docs/diagrams/topology; fileset = ../../packages/docs/diagrams/topology; }`; `pkgs.runCommand "fleet-topology-fresh" { nativeBuildInputs = [ pkgs.d2 ]; }` which, for each name, `diff -u ${src}/$name ${pkgs.writeText name files.${name}} || { echo "fleet-topology: $name is stale; run just topology-generate"; fail=1; }`, then `d2 validate` on both committed views, then `touch $out` if nothing failed.
- [ ] **Step 2:** Run `nix build .#checks.x86_64-linux.fleet-topology-fresh`. Expected: PASS.
- [ ] **Step 3:** Mutants (tasks.md 3.2): move one role's machine in a scratch edit without regenerating → FAIL naming `fleet.json` and `fleet.d2` and printing `just topology-generate`; hand-edit `fleet.d2` → FAIL naming `fleet.d2`; make the emitter drop a closing brace and regenerate → FAIL in `d2 validate`. Revert each.
- [ ] **Step 4:** Cost (tasks.md 3.3): follow `references/evaluation-cost.md` of preferences-nix-checks-architecture; record `NIX_SHOW_STATS=1 nix eval --raw .#checks.x86_64-linux.fleet-topology-fresh.drvPath` time and allocation, the same for `eval-fleet-topology`, and an unrelated check (e.g. `mesh-hosts-obligations`) before and after; confirm `nix eval --json .#checks.aarch64-darwin --apply builtins.attrNames` lacks both names.
- [ ] **Step 5: Commit** to the chain.

### Task 5: Rendering and the docs page

**Files:**
- Modify: `modules/devshells/default.nix` (add `pkgs.d2` beside `pkgs.typstWithPackages`)
- Modify: `justfile` (`diagrams-build`)
- Modify: `pkgs/by-name/vanixiets-docs/package.nix` (argument `d2`, `nativeBuildInputs`, buildPhase loop)
- Create: `packages/docs/src/content/docs/concepts/fleet-topology.mdx` (imports `fleet-table.md`, D16)
- Modify: `packages/docs/src/content/docs/concepts/index.md`, `concepts/architecture-overview.md`, `concepts/build-service-topology.md`

**Interfaces:**
- Consumes: the committed `.d2` views.
- Produces: `/diagrams/topology-fleet.svg`, `/diagrams/topology-network.svg`, page `/concepts/fleet-topology/`.

- [ ] **Step 1:** In `diagrams-build` (`justfile:965`), after the typst loop and before the svgo loop: `for v in fleet network; do d2 --layout elk "topology/$v.d2" "../public/diagrams/topology-$v.svg"; done` (run from `packages/docs/diagrams`). Mirror the same loop in the package buildPhase inside the `( cd diagrams … )` block (`package.nix:121-136`); add `d2` to the argument list and `nativeBuildInputs`. Leave the svgo loops unchanged.
- [ ] **Step 2:** Add `pkgs.d2` to the devshell. Run `nix develop -c just diagrams-build`. Expected: both SVGs exist, `git check-ignore` reports them ignored, and `grep -c '<text'` on each equals the count in d2's own output before svgo (render once to `/tmp` to compare).
- [ ] **Step 3:** Write the page (frontmatter `title: Fleet topology`, `description`, `sidebar.order` after build-service-topology): what the map shows, both images with descriptive alt text, "Derived and declared" section naming `flake.lib.hosts`, the clan inventory and `flake.lib.topologyFacts` and stating that declared facts are true only as last recorded, "Updating the map" naming `just topology-generate` and `fleet-topology-fresh`. Add the index entry and the two links.
- [ ] **Step 4:** Run `just docs-linkcheck`. Expected: PASS.
- [ ] **Step 5:** Run `nix build .#vanixiets-docs`. Expected: output contains `diagrams/topology-fleet.svg`, `diagrams/topology-network.svg`, `concepts/fleet-topology/index.html`.
- [ ] **Step 6: Commit** to the chain.

### Task 6: Playwright witness

**Files:**
- Create: `packages/docs/e2e/fleet-topology.ts`, `packages/docs/e2e/fleet-topology.spec.ts`
- Modify: `packages/docs/tests/report/policy.ts`

**Interfaces:**
- Consumes: page `/concepts/fleet-topology/`, `/diagrams/topology-{fleet,network}.svg`, committed `diagrams/topology/fleet.json`.
- Produces: `expectTopologyText(page: Page): Promise<void>` and `topologyNames(): { machines: string[]; networks: Record<string, string[]> }` in `e2e/fleet-topology.ts`, reused by Task 7.

- [ ] **Step 1:** Write `topologyNames()` reading `diagrams/topology/fleet.json` relative to the working directory (`packages/docs`, as in the report build), returning machine names from `machine/*` keys and, per `network/*` key, its member names.
- [ ] **Step 2:** Write `expectTopologyText(page)`: for each view, `page.request.get('/diagrams/topology-<view>.svg')`, expect status 200 and non-empty body, pass the text to `page.evaluate` which parses with `DOMParser` as `image/svg+xml` and returns the trimmed `textContent` of every `<text>`; `expect(texts).toContain(name)` for each machine (fleet view) and each network and member (network view), with the missing name in the message.
- [ ] **Step 3:** Write the spec: `fleet topology page loads` (goto, 200, heading level 1 `Fleet topology`, the declared-facts sentence visible); `both fleet topology diagrams load` (for each image located by `getByRole('img', { name: /fleet topology/i })`: alt non-empty, `naturalWidth > 0` as `homepage.spec.ts:80-86`, `src` answering 200 with `image/svg+xml`); `every host and network in fleet.json is text in the diagrams` (call `expectTopologyText`, then, when `browserName === "chromium"`, `locator.screenshot({ path: testInfo.outputPath('view-<view>.png') })` and `testInfo.attach('view-<view>', { path, contentType: 'image/png' })`).
- [ ] **Step 4:** Add the three cases to `requiredCases["playwright.config.ts"]`.
- [ ] **Step 5:** Run `just docs-test-e2e` (after `just docs-build`). Expected: PASS on every local engine. Then `nix build .#checks.x86_64-linux.package-vanixiets-docs-test-e2e`. Expected: PASS; in the `e2e-report` output, `completion.json` lists `view-fleet.png` and `view-network.png` on the Chromium attempt only.
- [ ] **Step 6: Commit** to the chain.

### Task 7: Negative control

**Files:**
- Create: `packages/docs/tests/negative-control/fleet-topology.spec.ts`, `packages/docs/playwright.topology-negative.config.ts`
- Modify: `packages/docs/tests/report/check-negative-report.ts`, `packages/docs/tests/report/policy.ts`, `pkgs/by-name/vanixiets-docs/package.nix`, `modules/checks/package-tests.nix`

**Interfaces:**
- Consumes: `expectTopologyText`, `topologyNames` from Task 6.
- Produces: `checks.<system>.package-vanixiets-docs-test-e2e-topology-negative-control`.

- [ ] **Step 1:** Write the spec `dropped host is rejected by the fleet topology oracle`: `page.route('**/diagrams/topology-fleet.svg*', …)` fetching the response and removing the `<text …>NAME</text>` element for `topologyNames().machines[0]`, recording that the route was hit; then `expectTopologyText(page)`.
- [ ] **Step 2:** Write the config (copy `playwright.action-negative.config.ts`, `testMatch: "fleet-topology.spec.ts"`, the negative-control test directory).
- [ ] **Step 3:** Add mode `topology` to `check-negative-report.ts` (`:8-14`), with its title match and `results.json` containing the dropped name; add the config's case and `["chromium"]` in `policy.ts`.
- [ ] **Step 4:** Add `passthru.tests.e2e-topology-negative-control` to `package.nix` after `e2e-action-negative-control` (`:463-478`), with `PLAYWRIGHT_CONFIG = "playwright.topology-negative.config.ts"`, `PLAYWRIGHT_PROJECTS = "chromium"` and `check-negative-report.ts ${report} topology`; add `"e2e-topology-negative-control"` to the `vanixiets-docs` list in `modules/checks/package-tests.nix:36-44`.
- [ ] **Step 5:** Run `nix build .#checks.x86_64-linux.package-vanixiets-docs-test-e2e-topology-negative-control`. Expected: PASS, printing that the oracle rejected the dropped host. Run the three existing negative controls. Expected: PASS.
- [ ] **Step 6: Commit** to the chain.

### Task 8: Rendered views in the evidence comment

**Files:**
- Modify: `modules/apps/docs/publish-evidence.sh`, `modules/checks/publish-evidence-rehearsal.nix`, `packages/docs/src/content/docs/concepts/browser-evidence.md`, `packages/docs/tests/report/README.md`

**Interfaces:**
- Consumes: passing-attempt attachments named `view-*.png` in `completion.json`; the bundled file set; nixbot's build API as `main` mode uses it (`publish-evidence.sh:265-354`).
- Produces: a `Rendered views` section in `comment.md`.

- [ ] **Step 1:** Resolve design open question 7: read nixbot's `pull_request` event fields (the event JSON the rehearsal fixtures model) for a base revision; record the field, or the fallback to the newest report published from `main`.
- [ ] **Step 2:** Add rehearsal fixtures: a report with `view-fleet.png` on a passing attempt and no base report; a report without views. Run `nix build .#checks.x86_64-linux.publish-evidence-rehearsal`. Expected: FAIL (no section rendered).
- [ ] **Step 3:** In the comment block (`publish-evidence.sh:853-897`), after the failed-attempt table, render the section only when bundled passing-attempt attachments match `view-*.png`: a two-column table per view, base link (or "unavailable") and head link; resolve the base report's object path and probe ttl-90d read-only for the same name.
- [ ] **Step 4:** Rerun the rehearsal. Expected: PASS; the fixture's `comment.md` has the section with the head link and the unavailable note, and the no-views fixture has no section.
- [ ] **Step 5:** Correct `concepts/browser-evidence.md:28` and the README's artifact contract to describe passing-attempt view screenshots. Run `just docs-linkcheck`. Expected: PASS.
- [ ] **Step 6: Commit** to the chain.

### Task 9: Integration verification

- [ ] **Step 1:** On the implementing pull request, read the browser-evidence comment: the `Rendered views` section shows both head views and says the base views are unavailable; open both and confirm magnetite's declared services and `omnigent/server`, cinnabar's `zerotier/controller`, and both networks with their members (tasks.md 6.1).
- [ ] **Step 2:** End-to-end review loop on a scratch change (tasks.md 6.2): move one role, see the freshness check fail, regenerate, see a one-line `fleet.json` diff, see the freshness check and `package-vanixiets-docs-test-e2e` pass, abandon the scratch change.
- [ ] **Step 3:** `openspec validate diagram-fleet-topology --strict`; `prek run --all-files`. Expected: both pass.
