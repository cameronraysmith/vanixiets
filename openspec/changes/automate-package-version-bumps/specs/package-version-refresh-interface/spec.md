## Purpose

The machine-side contract that delivers package version refresh: the typed package pin and its checks, the one realizer that derives a release's digests and writes only the pin and its declared companions, and the Renovate manager, rule and allowlist entry that run it.
Trust boundary: it guarantees only what the repository controls, not when Renovate runs, what an upstream publishes, or whether a release builds on a platform.

## ADDED Requirements

### Requirement: Every package pin is validated when the flake is evaluated

Each migrated package SHALL keep its pin in `pkgs/by-name/<p>/pin.json` and SHALL read it in `package.nix` through one shared helper that parses it with `builtins.fromJSON` and checks it against a module-system type before any attribute of the package is used.

**In detail**: the type requires `name`, equal to the package's attribute name; `version`, a non-empty string; `source`, an `attrTag` of `githubRelease { owner, repo, tagTemplate }`, `npm { package }`, `pypi { package }`, `vendorJson { url, pointer }`, `vendorText { url, regex }` or `gitCommit { owner, repo, branch }`; `artifacts`, a non-empty attribute set of `attrTag` values, each `platformBinaries { urlTemplate, platforms, checksum, hashes }` (with `checksum` an `attrTag` of `upstreamFile { urlTemplate, format }` or `prefetch {}`, and one SRI hash in `hashes` per key of `platforms`) or `sourceBuild { fetcher, hash, depsHash }` (with `depsHash` an `attrTag` of `npm`, `cargo` or `go`, each carrying an SRI hash, or `none {}`); `rev`, a 40-character hexadecimal commit, present exactly when an artifact's fetcher or a companion needs the release tag's commit; and `companions`, a list of `{ path, kind }` with `kind` an `attrTag` of `apmRef { git }` or `fixedOutputHash { package, attr, fodAttr }`, where `fodAttr` is a required single attribute name of `package` matching `[A-Za-z_][A-Za-z0-9_'-]*`, not an attribute path, with no default. A `sourceBuild` entry not named `src` is exposed on the package's `passthru` under its entry name, and that name, like each `fodAttr`, resolves to an attribute with an `outputHash`.

#### Scenario: A pin is malformed

- **WHEN** `nix eval .#packages.x86_64-linux.<p>.drvPath` runs against a `pin.json` with an unknown `source` tag, a `platforms` key with no matching `hashes` key, or a companion path containing `..`
- **THEN** evaluation fails with a message naming the package and the offending option path

#### Scenario: A pin names the wrong package

- **WHEN** `pkgs/by-name/ic-wasm-bin/pin.json` carries `"name": "icp-cli-bin"`
- **THEN** evaluating the package fails naming both names

### Requirement: A file outside the package's directory changes only through a typed companion entry

A companion `path` SHALL be repository-relative, SHALL contain no `..` component and SHALL lie outside `pkgs/by-name/<p>/`, and a `fixedOutputHash` companion's `path` SHALL name a JSON file, so that no update of a package can reach a file the pin does not name with a kind the realizer knows how to write.

#### Scenario: A companion names a Nix file

- **WHEN** a pin's `fixedOutputHash` companion names `pkgs/by-name/apm-skills-compose/package.nix`
- **THEN** evaluating the package fails naming the companion's path

#### Scenario: A hash companion omits its derivation attribute

- **WHEN** a pin's `fixedOutputHash` companion has no `fodAttr`, an empty one, or a dotted one such as `passthru.deps`
- **THEN** evaluating the package fails naming the companion, and no default is taken from `attr`

### Requirement: The build and the realizer share one URL template and platform map

Each migrated package SHALL expose `passthru.pin`, the validated pin, and `passthru.pinPlan`, a function from a version string to the fetch plan for that version, and `package.nix` SHALL build its fetches from `pinPlan pin.version`.
The realizer SHALL obtain every URL it fetches by evaluating `pinPlan` for the target version, so that no URL template is restated outside the pin.

**In detail**: the plan holds the release tag, and for each artifact entry its URL per platform, its checksum-file URL per platform where `checksum` is `upstreamFile`, and its fetcher arguments where it is `sourceBuild`.

#### Scenario: The plan for the current version matches the build

- **WHEN** `nix eval --json .#packages.x86_64-linux.ic-wasm-bin.passthru.pinPlan --apply 'f: f "<current version>"'` is compared with the `url` of the package's `src` for each platform
- **THEN** the URLs are equal

### Requirement: The realizer realizes one version of one package, total over every source and artifact kind

`nix run .#realize-pin -- <p> <version>` SHALL rewrite the package's pin and companion files for exactly that version, handling every tag of both unions, and SHALL leave every file as it was when any step fails.

**In detail**: run in the repository root, it evaluates `passthru.pin` and `passthru.pinPlan <version>`; resolves `rev` from the release tag with `git ls-remote`, preferring the peeled commit, when the pin carries `rev`; computes each `platformBinaries` hash from the upstream checksum file's hexadecimal digest converted to SRI, or by prefetching the artifact when `checksum` is `prefetch`; obtains every other hash from `FixedOutputHasher.hash(package, attr, timeout)`, whose `attr` is one of the closed union `Src | CargoDeps | GoModules | NpmDeps | Custom(name)` and whose single handler runs nix-update 1.17.0 as a subprocess: a `sourceBuild` entry named `src` as `Src`, any other `sourceBuild` entry as `Custom(<entry name>)`, each `depsHash` other than `none` as `CargoDeps`, `GoModules` or `NpmDeps`; sets, for each `apmRef { git }` companion, the `ref:` following the line `git: <git>` in its YAML file to `rev`, and then, for each `fixedOutputHash { package, attr, fodAttr }` companion, the `attr` key of its JSON file to the hash `FixedOutputHasher` reports for `Custom(fodAttr)` of `package`, never `Custom(attr)`; and writes `version` and each computed value into `pin.json` as each step completes. The realizer, not nix-update, writes every hash, and it never writes a dummy hash. An unhandled tag is rejected at the realizer's type check, not at run time.

#### Scenario: Two runs for the same version

- **WHEN** the realizer runs twice for the same package and version with unchanged upstream content
- **THEN** the second run changes no file

### Requirement: The realizer leaves every file as it was when it fails or runs out of time

On any failed step, and once its overall deadline of 10 minutes passes, the realizer SHALL restore every file it changed to its content before the run and exit non-zero, naming the step and the package.

**In detail**: the deadline keeps the four commits Renovate makes at most per run inside the unit's 55-minute limit.

#### Scenario: A checksum file lacks a platform's asset

- **WHEN** the realizer runs with a fake network capability whose checksum file has no line for one platform's asset
- **THEN** it exits non-zero naming that platform, and `pin.json` and every companion file are byte-identical to their content before the run

#### Scenario: The fixed-output hasher reports an error

- **WHEN** `FixedOutputHasher.hash` returns an error, or exceeds its timeout, for a `depsHash` or a `fixedOutputHash` companion
- **THEN** the realizer restores the files it changed and exits non-zero naming the package and the attribute, and records no hash for it

### Requirement: The realizer writes only the package pin and the files its typed companions name

The set of files the realizer may change SHALL be `pkgs/by-name/<p>/pin.json` together with the `path` of each entry in the pin's `companions`, computed from the validated pin before any write, and the realizer SHALL fail, restoring its own writes and naming each stray path, when any other path changed during its run. It SHALL NOT write any `.nix` file.

**In detail**: before the first write the realizer records each path `git status --porcelain=v1 -z --untracked-files=all` lists, with its content hash or its absence; after the last write, a path outside the allowed set is a stray when it is new in that listing or its content hash differs from the record. In a clean checkout this is the strict rule that nothing outside the allowed set changes.

#### Scenario: A step writes outside the set

- **WHEN** a test injects a capability that creates a file outside the allowed set during a realizer run
- **THEN** the realizer exits non-zero naming that file, and the allowed files are restored

#### Scenario: The checkout was already dirty

- **WHEN** the realizer runs in a checkout with an unrelated modified file that no step touches
- **THEN** that file is not reported as a stray, and the run succeeds

### Requirement: The realizer makes no forge call and no mutating request

The realizer SHALL send only `GET` and `HEAD` requests, to the hosts that the pin's evaluated plan and `source` name, SHALL call no forge API, and SHALL read no credential from its environment.

**In detail**: the host policy checks the requested URL, not a redirect's target; nix and git run with an allowlisted environment and `--option access-tokens ""`.

#### Scenario: The realizer's requests are recorded

- **WHEN** the realizer's offline tests run it for each stage-1 pin with a recording network capability
- **THEN** every recorded request is a `GET` or `HEAD` to a URL derived from that pin's plan or source, and none is to `api.github.com`

### Requirement: One custom manager reads every package pin and names the package

`.github/renovate.json` SHALL declare exactly one `customType: "jsonata"` manager with `fileFormat: "json"` over `pkgs/by-name/**/pin.json`, emitting one dependency per file whose `depName` is the pin's `name`, and no hand-maintained list of packages SHALL exist in the configuration.

**In detail**: each dependency's `currentValue` is the pin's `version` (or its `currentDigest` is the pin's `rev` for a `gitCommit` source), and its datasource and lookup name follow from the `source` tag: `githubRelease` to `github-releases` with an `extractVersion` derived from `tagTemplate`, `npm` to `npm`, `pypi` to `pypi`, `vendorJson` and `vendorText` to `custom.<name>`, and `gitCommit` to `git-refs` on the branch.

#### Scenario: Renovate extracts the stage-1 pins

- **WHEN** Renovate's extraction runs over the repository with stage 1 landed
- **THEN** it reports exactly the six stage-1 packages from the custom manager, each with the datasource its `source` tag selects and its pin's version as the current value

### Requirement: Vendor endpoints are read through declared custom datasources

Each `vendorJson` or `vendorText` source SHALL have a `customDatasources.<name>` entry whose `defaultRegistryUrlTemplate` is the source's `url`, with format `json` and a `transformTemplates` entry derived from `pointer`, or format `plain` with the `regex` applied, so that Renovate reads the vendor's version list and orders it with its own versioning.

#### Scenario: A vendor text endpoint is read

- **WHEN** Renovate looks up moshi-hook
- **THEN** it reads the vendor's version text from the URL in moshi-hook's pin, through the custom datasource named for it

### Requirement: The pin rule fixes the branch, the task and the update window

A `packageRules` entry matching `matchManagers: ["custom.jsonata"]` SHALL fix the branch name, the commit topic, the update window, the limits and the single post-upgrade task of every package update, and SHALL add no merge authorization.

**In detail**: the rule sets no `automerge`, no `ignoreUnstable: false` and no queue label, and leaves every existing rule, including the lazyvim-nix `allowedVersions` rule, unchanged in content and order.

#### Scenario: The rule's branch, window and limits are read

- **WHEN** `.github/renovate.json` is parsed and its `custom.jsonata` rule selected
- **THEN** it sets `branchTopic` and `commitMessageTopic` to the package name, so branches are `renovate/<p>`; `schedule: ["* 14-17 * * 1,4"]` with `updateNotScheduled: false`; and `prHourlyLimit: 2`, `prConcurrentLimit: 6` and `branchConcurrentLimit: 6`; and `checks.renovate-config` passes

#### Scenario: The rule's task is read

- **WHEN** the same rule's `postUpgradeTasks` is read
- **THEN** it holds the single command `nix run .#realize-pin -- {{{depName}}} {{{newVersion}}}` (`{{{newDigest}}}` for a `gitCommit` source), `executionMode: "update"`, and `fileFilters` covering `pkgs/by-name/**/pin.json` and the companion paths of the migrated pins

### Requirement: The realizer's command is admitted by one allowlist entry, and the check renders it before matching

`flake.lib.renovateSettings.allowedCommands` SHALL gain one anchored entry admitting the realizer's command and nothing else, and `checks.renovate-allowed-commands` SHALL render each templated task command with every pin before matching it.

**In detail**: the entry admits `nix run .#realize-pin -- ` followed by a package name of lowercase letters, digits and hyphens and a version of letters, digits, `.`, `+`, `_` and `-`. The check renders with the `name` and `version` of every `pin.json` in the tree, and fails when any rendered command is not admitted or when no pin exists to render it with.

#### Scenario: A version string carries a shell metacharacter

- **WHEN** the check renders the task command with the version `1.0.0;id`
- **THEN** the rendered command is not admitted, and the check fails naming it

### Requirement: The pin contract and the realizer are each guarded by a small check with a declared size class

`checks.x86_64-linux.pin-contract` and `checks.x86_64-linux.realize-pin-tests` SHALL guard the pin type and the realizer without network access, and each SHALL be declared in `testSizes.checks` as `small`, with `measured = false` until three runs exist, so that it appears in `checks.x86_64-linux.test-size-classes`.

**In detail**: `pin-contract` evaluates the pin type against valid and malformed fixtures and against every `pin.json` in the tree; `realize-pin-tests` runs the realizer's basedpyright check and its offline unit tests with injected network, nix, git, file and fixed-output-hasher capabilities.

#### Scenario: The size classes are read

- **WHEN** `nix eval --json .#checks.x86_64-linux.test-size-classes` or the `testSizes.checks` option is read
- **THEN** both checks are listed with class `small`

### Requirement: A migrated package keeps no updater of its own

A package with a `pin.json` SHALL have no `update.sh` in its directory, no `passthru.updateScript`, and no `apps.update-<p>` entry in `modules/apps/updates.nix`.

#### Scenario: Stage 1 has landed

- **WHEN** the tree is searched after stage 1 lands
- **THEN** none of the six stage-1 packages has an `update.sh` or an `apps.update-*` entry

### Requirement: This capability states its own trust boundary

The properties above SHALL be read as guaranteeing only what the repository controls: the pin contract and its type, the fetch plan shared by build and realizer, what the realizer reads and writes, the Renovate configuration and allowlist entry the repository declares, and the checks that guard them.

**Outside the boundary**: they SHALL NOT be read as guaranteeing when Renovate runs or which releases it finds and how it orders them, what an upstream publishes or whether its checksum file matches its artifacts, the deployed Renovate's honouring of the configuration, or whether a release builds on a platform, which the build service's required checks on x86_64-linux and aarch64-darwin record, and which they record only while a builder for that platform is reachable.

#### Scenario: A guarantee outside the boundary is claimed

- **WHEN** a document cites this capability for a release having been proposed within a day, or for a darwin build of an updated package passing
- **THEN** that claim rests instead on world assumptions `A227` and `A229`, or on the build service's own record, and not on this capability
