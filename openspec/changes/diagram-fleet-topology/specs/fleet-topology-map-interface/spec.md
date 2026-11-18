## ADDED Requirements

### Requirement: The fleet map is a pure function of three declared inputs

`flake.lib.mkFleetTopology` SHALL be a pure function of `{ inventory, hosts, facts }` returning `{ model, files }`, and `flake.lib.fleetTopology` SHALL be that function applied to `self.clan.inventory`, `self.lib.hosts` and `self.lib.topologyFacts`.
It SHALL NOT read `nixosConfigurations`, `darwinConfigurations`, `clanInternals`, or an instantiated package set.

#### Scenario: The generator is evaluated

- **WHEN** `nix eval --raw .#lib.fleetTopology.files."fleet.d2"` runs
- **THEN** no NixOS or nix-darwin configuration is evaluated and no derivation is built

### Requirement: The generator reads only named inventory fields

From `inventory`, `mkFleetTopology` SHALL read only `machines.<name>.{machineClass, tags, description}`, each instance's `module.name`, and the attribute names of each role's `machines` and `tags`.
For an instance whose `module.name` is `tincr` or `zerotier` it SHALL additionally read the attribute names of `roles.peer.settings.devices` and the entries of `roles.controller.machines.<name>.settings.allowedIps`.

#### Scenario: A non-overlay instance carries settings

- **WHEN** an instance whose module is neither `tincr` nor `zerotier` carries role settings
- **THEN** evaluating `flake.lib.fleetTopology` does not force those settings

### Requirement: Role members are resolved from machines and tags

A role's members SHALL be the sorted, duplicate-free union of its explicitly named machines that are inventory machines and of every inventory machine carrying one of its tags.
The tag `all` SHALL name every inventory machine.

#### Scenario: A role names its members by a user tag

- **WHEN** an instance's role names the tag `peer` and three inventory machines carry `peer`
- **THEN** `model.instances.<instance>.roles.<role>` is those three machine names in sorted order

#### Scenario: A role names a machine that is not in the inventory

- **WHEN** a role's `machines` names a machine absent from `inventory.machines`
- **THEN** that name is not a member of the role

### Requirement: ZeroTier external members are matched to the registry by address

A ZeroTier external member SHALL be the `hosts` member whose `zerotier.address` equals an `allowedIps` entry, shown with the role `external`.
An `allowedIps` entry matching no `hosts` member SHALL make `mkFleetTopology` throw an error naming the address.

#### Scenario: A ZeroTier address matches no registry member

- **WHEN** the ZeroTier controller's `allowedIps` contains an address no `self.lib.hosts` member carries
- **THEN** evaluating `flake.lib.fleetTopology` throws an error naming that address

### Requirement: Declared facts are a hand-written per-host attribute set

`flake.lib.topologyFacts` SHALL be a literal attribute set in `modules/lib/topology-facts.nix`, keyed by `self.lib.hosts` member name, each value `{ services = [ { name; hostnames ? [ ]; ports ? [ ]; } ]; }`, and SHALL NOT be computed from any host configuration.
It SHALL NOT restate a member's class, public `endpoints` or overlay addresses, which the generator reads from `hosts`.

#### Scenario: A declared fact names an unknown host

- **WHEN** `flake.lib.topologyFacts` has a key that is not a member of `flake.lib.hosts`
- **THEN** evaluating `flake.lib.fleetTopology` throws an error naming that key

### Requirement: The fleet map is committed as three text files

`flake.lib.fleetTopology.files` SHALL be an attribute set of exactly `fleet.json`, `fleet.d2` and `network.d2`, each a string committed byte for byte at `packages/docs/diagrams/topology/<name>`.
`just topology-generate` SHALL write each string there with `nix eval --raw` and build nothing.

#### Scenario: The committed files are regenerated

- **WHEN** `just topology-generate` runs on a clean tree whose files are current
- **THEN** `packages/docs/diagrams/topology/` is unchanged and no derivation was built

### Requirement: fleet.json has one entry per line

`fleet.json` SHALL be one JSON object with one top-level entry per line, keyed `machine/<name>`, `instance/<name>`, `network/<name>` and `facts/<host>` in sorted key order, each value serialized with `builtins.toJSON`.

#### Scenario: One role moves to another machine

- **WHEN** a change moves one instance's role from one machine to another and regenerates
- **THEN** the diff of `fleet.json` touches only the line of that instance

### Requirement: fleet.d2 shows placement by host

`fleet.d2` SHALL group hosts by `machineClass` and list inside each host its role memberships as `<instance>/<role>` and its declared services with their hostnames and ports.
Each `<instance>/<role>` whose members are every inventory machine SHALL appear once, in a legend titled `on every host`, and in no host's block; the view SHALL carry a title and a key.

#### Scenario: A role spans every host

- **WHEN** an instance's role resolves to every inventory machine
- **THEN** `fleet.d2` lists `<instance>/<role>` in the `on every host` legend and in no host's block

### Requirement: network.d2 shows the fleet networks and the public edge

`network.d2` SHALL show each `tincr` and `zerotier` instance as a cloud joined by an edge, labelled with the role, to each of its role members, devices and external members.
It SHALL show an `internet` node with one edge per public hostname, from `hosts.<member>.endpoints` and the declared facts' hostnames, to the host that answers it, and SHALL carry a title and a key.

#### Scenario: A phone has joined tincr

- **WHEN** `roles.peer.settings.devices` of the tincr instance names `pixel11`
- **THEN** `network.d2` has an edge from `pixel11` to the tincr cloud labelled `device`

### Requirement: A freshness check pins the committed files

`checks.x86_64-linux.fleet-topology-fresh` SHALL fail when any committed file differs from its string in `flake.lib.fleetTopology.files`, printing the differing file and `just topology-generate`, and SHALL fail when `d2 validate` rejects either committed view.
Its source SHALL be only `packages/docs/diagrams/topology/`, selected with `lib.fileset`.

#### Scenario: The inventory changes without regeneration

- **WHEN** a change moves an instance's role to another machine and leaves `packages/docs/diagrams/topology/` untouched
- **THEN** `checks.x86_64-linux.fleet-topology-fresh` fails, naming `fleet.json` and `fleet.d2` and printing `just topology-generate`

#### Scenario: A committed view is invalid D2

- **WHEN** the generator emits a view with a D2 syntax error and the committed file matches it
- **THEN** `checks.x86_64-linux.fleet-topology-fresh` fails on `d2 validate`

### Requirement: The checks' key set is static and x86_64-linux only

The attribute names `fleet-topology-fresh` and `eval-fleet-topology` SHALL be literals gated on `system == "x86_64-linux"`, depending on no evaluated configuration, and SHALL be absent from every other system's `checks`.

#### Scenario: Another system's checks are listed

- **WHEN** the attribute names of `checks.aarch64-darwin` are evaluated
- **THEN** `fleet-topology-fresh` and `eval-fleet-topology` are absent

### Requirement: The generator's pure logic is unit-tested over literal fixtures

`checks.x86_64-linux.eval-fleet-topology` SHALL run nix-unit through `flake.lib.mkEvalCheck` over `mkFleetTopology` with literal fixtures, never `self`.
Its cases SHALL cover tag resolution, the `all` tag, an absent machine, devices, ZeroTier external members, an unmatched address, an unknown facts key, the `on every host` legend and the `fleet.json` line format.

#### Scenario: Tag resolution regresses

- **WHEN** `mkFleetTopology` stops resolving user tags into role members
- **THEN** `checks.x86_64-linux.eval-fleet-topology` fails on the tag-resolution case

### Requirement: Both views are rendered into the docs site through the existing svgo pass

`just diagrams-build` and the `vanixiets-docs` package build SHALL each render `fleet.d2` and `network.d2` with `d2 --layout elk` and D2's default theme to `packages/docs/public/diagrams/topology-fleet.svg` and `topology-network.svg`, after the typst loop and before the existing `svgo --quiet` loop, with no svgo configuration file; the default devshell SHALL provide `d2`.

#### Scenario: The docs package is built

- **WHEN** the `vanixiets-docs` package is built
- **THEN** its output contains `topology-fleet.svg` and `topology-network.svg`, each having passed through `svgo`

### Requirement: The rendered SVGs keep their words as text elements

After the svgo pass, every node and edge label of both views SHALL remain the content of an SVG `<text>` element in the delivered file, not glyph outlines.

#### Scenario: A host name in the delivered fleet view

- **WHEN** the delivered `topology-fleet.svg` is parsed as XML
- **THEN** each `machine/<name>` key of the committed `fleet.json` names a `<text>` element whose content is `<name>`

### Requirement: The concepts page embeds both views as images

`packages/docs/src/content/docs/concepts/fleet-topology.md` SHALL embed `/diagrams/topology-fleet.svg` and `/diagrams/topology-network.svg` as Markdown images with non-empty alt text, state that `flake.lib.topologyFacts` is declared rather than observed, and name `just topology-generate`; `concepts/index.md`, `concepts/architecture-overview.md` and `concepts/build-service-topology.md` SHALL link it.
No dark-theme variant of either view SHALL be rendered.

#### Scenario: The docs package is built with the page

- **WHEN** the `vanixiets-docs` package is built
- **THEN** its output contains the page `concepts/fleet-topology/` with both images and the declared-facts statement

### Requirement: A Playwright spec witnesses the page and both views

`packages/docs/e2e/fleet-topology.spec.ts` SHALL import `test` from `e2e/fixtures.ts` and define the tests `fleet topology page loads`, `both fleet topology diagrams load` and `every host and network in fleet.json is text in the diagrams`, and `tests/report/policy.ts` SHALL list all three under `playwright.config.ts`.

#### Scenario: The page and images load

- **WHEN** the e2e suite runs against the built site
- **THEN** `/concepts/fleet-topology/` answers 200 with the heading `Fleet topology` and the declared-facts statement, and each image has non-empty alt text, `naturalWidth` greater than zero, and a `src` answering 200 with a non-empty `image/svg+xml` body

### Requirement: The diagram oracle is derived from the committed fleet.json

The test `every host and network in fleet.json is text in the diagrams` SHALL read the committed `diagrams/topology/fleet.json`, and SHALL fail unless every `machine/<name>` key names a `<text>` element of the served `topology-fleet.svg` and every `network/<name>` key, and each member of that network, names a `<text>` element of the served `topology-network.svg`.
It SHALL NOT compare pixels; no `toHaveScreenshot` assertion SHALL witness either view.

#### Scenario: A host is added to the inventory and regenerated

- **WHEN** a machine is added to the inventory, the files are regenerated and the site is rebuilt
- **THEN** the oracle requires the new machine's name as text in `topology-fleet.svg` without any edit to the spec

### Requirement: A negative control proves the oracle fails

`passthru.tests.e2e-topology-negative-control` SHALL run `tests/negative-control/fleet-topology.spec.ts` under `playwright.topology-negative.config.ts` on Chromium, intercepting `topology-fleet.svg` to remove the `<text>` of the first `machine/<name>` in `fleet.json`, and `check-negative-report.ts` in mode `topology` SHALL require that its single test failed as a product failure on every attempt with that name in `results.json`; `modules/checks/package-tests.nix` SHALL expose it.

#### Scenario: One host is dropped from the served SVG

- **WHEN** the negative control runs
- **THEN** the oracle fails naming the dropped host, and the check `package-vanixiets-docs-test-e2e-topology-negative-control` passes

### Requirement: Both views are attached to the browser evidence on Chromium

On Chromium only, the oracle test SHALL attach element screenshots of the two images as `view-fleet.png` and `view-network.png` with `testInfo.attach` and a file path, so the completion report records them on the passing attempt.

#### Scenario: The report is validated

- **WHEN** `validate-report.ts validate` reads a passing report
- **THEN** the Chromium attempt of the oracle test lists `view-fleet.png` and `view-network.png`, each a nonempty PNG, and the Firefox and WebKit attempts list none

### Requirement: The evidence comment shows the views before and after

When the published report carries `view-*.png` attachments, the publisher's pull-request comment SHALL include a `Rendered views` section linking each head view and the same-named view from the report published for the pull request's base revision, or stating that the base view is unavailable; `concepts/browser-evidence.md` and `tests/report/README.md` SHALL describe passing-attempt view screenshots.

#### Scenario: The base report has no views

- **WHEN** a pull request's report carries `view-fleet.png` and its base revision's published report carries none
- **THEN** the comment links the head `view-fleet.png` and states that the base view is unavailable

#### Scenario: The report carries no views

- **WHEN** a pull request changes the docs report but no test attached a `view-*.png`
- **THEN** the comment has no `Rendered views` section

### Requirement: Trust boundary of the fleet map

This interface SHALL guarantee only that the committed files equal what the inventory, the registry and the declared facts produce, that both views parse as D2, and that the served SVGs carry every committed host and network name as `<text>`.
It SHALL NOT be relied on to show that a host runs what is declared, that a hostname answers on its ports, that a device is connected, or that a layout or screenshot reads well; screenshots are evidence, not a gate.

#### Scenario: A host runs a service nobody declared

- **WHEN** a host's configuration enables a public service that neither a clan role nor `flake.lib.topologyFacts` records
- **THEN** the fleet map omits it and `fleet-topology-fresh` still passes, because the check compares declarations with files and not with the host
