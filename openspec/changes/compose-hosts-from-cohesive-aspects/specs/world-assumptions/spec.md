## ADDED Requirements

### Requirement: A350 — nix-darwin concatenates postActivation snippets by order priority, stably within a priority

It is true of nix-darwin at the locked revision, independent of what this fleet builds, that `postActivation.text` definitions are ordered by `mkOrder` priority, keeping merge order within a priority, and that `postActivation` runs after every other snippet and before `/run/current-system` is relinked.
Any requirement whose discharge depends on this fact SHALL name it explicitly, and SHALL lose its discharge once the violation below is observed.

**Evidence**: nix-darwin `663d8b962a11` `modules/system/activation-scripts.nix:114-151` (the activate script splices every snippet's `text` in a fixed order, `postActivation` at `:140` after the last of the others at `:138`, then relinks `/run/current-system` at `:146`) and `modules/lib/write-text.nix:25-31` (each snippet's `text` is `types.lines`); nixpkgs `bd5b7d01ccc4` (which nix-darwin follows) `lib/types.nix:794-813` (`lines` joins the merged definitions with `"\n"` in list order) and `lib/modules.nix:1417-1422,1652-1668` (when any definition carries `mkOrder`, definitions are sorted by `builtins.sort` on priority, default `1000`, which keeps merge order among equal priorities).

#### Scenario: Read at the source at apply

- **WHEN** nix-darwin `663d8b96` `modules/system/activation-scripts.nix:114-158` and the `lines` merge in nixpkgs `lib/types.nix` and `lib/modules.nix` are read (task 1.5)
- **THEN** snippets are ordered by priority, then by merge order, and `postActivation` precedes the relink

#### Scenario: nix-darwin reorders activation

- **WHEN** a nix-darwin update moves `postActivation` after the relink, or orders `lines` other than by priority
- **THEN** this assumption is void; the `host-composition` requirement `A darwin host's deploy record is the last thing its activation writes` loses its discharge until the activation order is restated

### Requirement: A351 — The module system applies a module once per key, and a flake-parts module value carries no key

It is true of the nixpkgs module system and flake-parts at the locked revisions, independent of what this fleet builds, that modules are collected once per `key`, that a module given as a value without one gets a key derived from its importer, and that flake-parts' `flake.modules` values carry no `key`, so one imported from two parents applies twice.
Any requirement whose discharge depends on this fact SHALL name it explicitly, and SHALL lose its discharge once the violation below is observed.

**Evidence**: nixpkgs `bd5b7d01ccc4` `lib/modules.nix:543-546` (an imported module gets the fallback key `<importer's key>:anon-<index>`), `:765,783` (a module's own `key` replaces the fallback), `:463-468` (a path import's key is its path) and `:594-614` (`filterModules` keeps one module per key through `builtins.genericClosure`); flake-parts `ea2630b74709` `extras/modules.nix:12-28,72` (every non-`generic` `flake.modules` value is wrapped in a function returning `_class`, `_file` and `imports`, with `# TODO: set key?` at `:24` and no `key`); nixpkgs `lib/types.nix:1992-1998` (a `deferredModule` merges to `{ imports = [ … ]; }`, with no `key`).

#### Scenario: Read at the source at apply

- **WHEN** nixpkgs `lib/modules.nix:602-611` and its anonymous-key assignment, and flake-parts `extras/modules.nix:24-26` (`# TODO: set key?`), are read (task 1.5)
- **THEN** collection is keyed and the flake-parts values set `_class` and `_file` but no `key`

#### Scenario: Observed by the drvPath diff

- **WHEN** the commit that keys the dual-exported home modules is compared with its parent
- **THEN** every home's derivation is identical, the modules that stop applying twice having set only booleans

#### Scenario: flake-parts starts keying module values

- **WHEN** a flake-parts update sets a `key` on `flake.modules` values
- **THEN** this assumption is void; `exportAs`'s keys and the rule that no server aspect imports another are restated, and the `host-composition` requirement `Each host's deployed system is unchanged apart from declared differences` is rechecked by a drvPath diff

### Requirement: A352 — The module system merges definitions in breadth-first import order

It is true of the nixpkgs module system at the locked revision, independent of what this fleet builds, that a configuration's modules are collected breadth-first over the import tree and that definitions merge in that order, so a definition's place in a list option depends on its import depth as well as on its order among its siblings.
Any requirement whose discharge depends on this fact SHALL name it explicitly, and SHALL lose its discharge once the violation below is observed.

**Evidence**: nixpkgs `bd5b7d01ccc4` `lib/modules.nix:594-614` (`filterModules` returns the modules in `builtins.genericClosure` order, starting from the top-level imports and expanding each module's `modules`) and `lib/types.nix:1992-1998` (`deferredModuleWith` merges its definitions into one `imports` list in definition order); the breadth-first order is the evaluator's, not nixpkgs': Nix 2.35.6 returns `a b c d` for `genericClosure` over `a → [b c]`, `b → [d]` (evaluated 2026-11-27).

#### Scenario: Measured on this fleet

- **WHEN** `darwin.base`, `nixos.base` and `homeManager.ai` were rewritten on 2026-11-27 as named import lists in path order, which puts each part one or more import levels deeper
- **THEN** argentum's system packages and every home importing `ai` changed; a key added by wrapping a module (`{ key; imports = [ m ]; }`) changed the claude-sandbox and ubuntu homes, and the same key set on the module itself changed nothing

#### Scenario: Observed by the drvPath diff

- **WHEN** a commit that moves definitions between a host module and its imports, or turns an aggregate into a named import list, is compared with its parent
- **THEN** a host or home derivation changes wherever a moved list definition now sits at a different import depth, and is identical otherwise

#### Scenario: The merge order changes

- **WHEN** a nixpkgs update changes the order in which modules are collected or a deferred module's definitions merge
- **THEN** this assumption is void; the `host-composition` requirement `Each host's deployed system is unchanged apart from declared differences` loses its discharge until every commit relying on today's order is re-measured

### Requirement: A353 — nix-darwin writes a list nix setting as one space-joined line, keeping duplicates

It is true of nix-darwin at the locked revision, independent of what this fleet builds, that `nix.settings.substituters` and `trusted-public-keys` are `listOf str`, that every definition's elements are kept, duplicates included, and that `/etc/nix/nix.conf` renders each list as one line of space-joined values.
Any requirement whose discharge depends on this fact SHALL name it explicitly, and SHALL lose its discharge once the violation below is observed.

**Evidence**: nix-darwin `663d8b962a11` `modules/nix/default.nix:38-50` (`mkValueString` renders a list with `toString`), `:622-657` (the two options), `:947-949` (nix-darwin's own cache.nixos.org entries).

#### Scenario: Observed at apply

- **WHEN** each Mac's `nix.settings.substituters` is evaluated before and after the duplicate writer is removed
- **THEN** before it holds each of the ten caches twice and after once

#### Scenario: nix-darwin deduplicates

- **WHEN** a nix-darwin update removes duplicate list entries itself
- **THEN** this assumption is void, and the `host-composition` requirement `Each darwin host consults each binary cache once` is met without this change's edit, which then changes no derivation

### Requirement: A354 — nix-darwin's activation reloads the Nix daemon when nix.conf changes

It is true of nix-darwin at the locked revision, independent of what this fleet builds, that activation sends `nix-daemon` `HUP` when `/etc/nix/nix.conf` differs from the running system's, so a changed cache list takes effect at the deploy.
Any requirement whose discharge depends on this fact SHALL name it explicitly, and SHALL lose its discharge once the violation below is observed.

**Evidence**: nix-darwin `663d8b962a11` `modules/nix/default.nix:935` (the `diff` of `/etc/nix/nix.conf` against the running system's), `:937` (`launchctl kill HUP system/org.nixos.nix-daemon`).

#### Scenario: Observed at deploy

- **WHEN** a Mac is deployed with the single-copy `nix.conf`
- **THEN** its activation output says it is reloading nix-daemon, and the deployed `nix.conf` lists each cache once

#### Scenario: The daemon is not reloaded

- **WHEN** a deploy's activation does not reload the daemon after `nix.conf` changed
- **THEN** this assumption is void; the `host-composition` requirement `Each darwin host consults each binary cache once` is discharged only after the daemon restarts

### Requirement: A355 — Neither srvos nor clan-core forces the darwin documentation options or GRUB's enable

It is true of srvos and clan-core at the locked revisions, independent of what this fleet builds, that neither the srvos modules this fleet imports nor clan-core's `clanCore` defaults sets the darwin documentation options, `programs.{info,man}.enable` or `boot.loader.grub.enable` above `mkDefault` priority, so a plain host value wins.
Any requirement whose discharge depends on this fact SHALL name it explicitly, and SHALL lose its discharge once the violation below is observed.

**Evidence**: the srvos modules this fleet imports are `server` (NixOS and darwin), `mixins-nginx`, `hardware-hetzner-cloud` and, in pyrite, the file `shared/common/well-known-hosts.nix` (`rg -n srvos modules lib`, 2026-11-27); of every srvos file those import, at srvos `e151e24ac800`, only these set an option named here: `shared/server.nix:26-29` (`documentation.{enable,doc.enable,info.enable,man.enable}` set with `mkDefault`), `darwin/server/default.nix:14-15` (`programs.{info,man}.enable` set with `mkDefault`); `nixos/hardware/hetzner-cloud/default.nix:16` sets `boot.loader.grub.devices` with `mkDefault`, not `grub.enable`, and `shared/common/well-known-hosts.nix` sets only `programs.ssh.knownHosts`. clan-core `78d5de23bd56` `nixosModules/clanCore/defaults.nix:38-45` (`documentation.{doc,info}.enable = mkDefault false` in a NixOS module, under `enableRecommendedDefaults`).

#### Scenario: Read at the source at apply

- **WHEN** srvos `e151e24a` `shared/server.nix:26-29`, `darwin/server/default.nix:14-15` and `nixos/hardware/hetzner-cloud/default.nix:16`, and clan-core `78d5de23` `nixosModules/clanCore/defaults.nix:42,45`, are read (task 1.5)
- **THEN** srvos sets those options with `mkDefault`, its Hetzner module sets `grub.devices` and not `grub.enable`, and clan-core's `mkDefault false` documentation settings are a NixOS-only module

#### Scenario: Observed by evaluation

- **WHEN** the documentation options are written plainly once and GRUB's enable without `mkForce`
- **THEN** every Mac's documentation options and each of electrum's, galena's and scheelite's `boot.loader.grub.enable` evaluate to their values before the change

#### Scenario: An input starts forcing them

- **WHEN** an srvos or clan-core update sets one of these options with a priority above a plain definition
- **THEN** this assumption is void; evaluation fails with conflicting definitions, or the drvPath diff shows the host changed, and the `host-composition` requirement `A capability several hosts run is declared once` is restated for that option

### Requirement: A356 — import-tree skips paths with an underscore-prefixed component

It is true of import-tree at the locked revision, independent of what this fleet builds, that a file whose path under the imported directory has a component beginning with `_` is not imported as a module.
Any requirement whose discharge depends on this fact SHALL name it explicitly, and SHALL lose its discharge once the violation below is observed.

**Evidence**: import-tree `eb1b52eaecc5` `default.nix:64-68,83-87` (the default filter keeps `.nix` files whose path relative to the imported directory has no `/_` infix, unless the caller replaces the initial filter); `modules/_disabled/` relies on it today.

#### Scenario: Observed at apply

- **WHEN** the flake is evaluated with `clan/services/otel-collector/_shared.nix` present
- **THEN** it is not evaluated as a flake-parts module, and only the three files that import it read it

#### Scenario: import-tree changes its filter

- **WHEN** an import-tree update imports underscore-prefixed paths
- **THEN** this assumption is void; evaluation fails on `_shared.nix`'s arguments, and the shared file is moved out of the tree

### Requirement: A357 — Setting a ZFS property to its current value changes nothing

It is true of ZFS, independent of what this fleet builds, that `zfs set <property>=<value> <dataset>` succeeds and changes nothing when the dataset already has that value, and that disko applies dataset options only when it creates the dataset.
Any requirement whose discharge depends on this fact SHALL name it explicitly, and SHALL lose its discharge once the violation below is observed.

**Evidence**: the comment above magnetite's oneshots (`machines/nixos/magnetite/default.nix:222-228` at the time of writing) and the oneshots' runs at each boot, which succeed.

#### Scenario: A boot oneshot fails on an unchanged value

- **WHEN** a `zfs-set-*` or `zfs-assert-*` oneshot fails on a boot where the dataset already held the value
- **THEN** this assumption is void; the `host-composition` requirement `magnetite's boot-enforced dataset properties are stated once` keeps its statement but its boot enforcement must be restated

### Requirement: A358 — Each Mac's recorded state version is the one it was first set up with

It is true of argentum, blackphos, rosegold and stibnite, independent of what this repository declares, that each was first activated with nix-darwin state version 4, which fixed defaults (among them the `nixbld` group id) that existing state depends on.
Any requirement whose discharge depends on this fact SHALL name it explicitly, and SHALL lose its discharge once the violation below is observed.

**Evidence**: the three `mkForce 4` lines this change removes and the registry's values (`modules/lib/hosts.nix:328-367`); `darwin/base.nix:43-52`'s note that every host was installed with the 350 `nixbld` gid.

#### Scenario: A Mac is reinstalled

- **WHEN** a Mac is reinstalled or replaced, so its first-setup version is no longer 4
- **THEN** this assumption is void for that host; its registry value is changed in the same commit, and the `host-composition` requirement `A Mac's state version is declared once` holds again only after that edit

### Requirement: A359 — The cloud servers run at the providers the registry records

It is true of the fleet, independent of what this repository declares, that cinnabar, electrum and magnetite run on Hetzner Cloud and galena and scheelite on Google Cloud, and that each provider names its servers' uplink interfaces so that `en*` (Hetzner) and `en* eth*` (Google) match them.
Any requirement whose discharge depends on this fact SHALL name it explicitly, and SHALL lose its discharge once the violation below is observed.

**Evidence**: `flake.lib.cloudMachines` and the registry's derived `cloud.provider`; the hosts' working uplinks; the comments at galena's and scheelite's imports.

#### Scenario: A server moves provider

- **WHEN** a cloud server is moved to another provider, or a provider renames its interfaces
- **THEN** this assumption is void; the `host-composition` requirement `A cloud server takes its provider's shape from one declaration` holds only after the registry, the host's provider aspect and, if needed, the aspect's match are changed together

## MODIFIED Requirements

### Requirement: Grounded vocabulary for behavioral requirements

The corpus SHALL provide one designation record per content term this repository's `behavioral`-stratum requirements use, recording the term, the sense in which it is used when a term carries more than one, the world phenomenon it denotes, and whether that phenomenon is world-only, shared with the machine, or machine-only.
A term found to denote two distinct phenomena within this repository's vocabulary SHALL be recorded as two rows rather than collapsed into one.

#### Scenario: The designation records are read

- **WHEN** the designation records are read
- **THEN** they are the rows of this table, one per term and sense

| Term | Sense | World phenomenon it denotes | Status |
|---|---|---|---|
| session | autonomous | a bounded episode during which an agent acts without a human present to answer a prompt | world-only |
| session | Pi-persisted | Pi's own stored record of a run (a session file, or the absence of one under `--no-session`) | machine-only |
| package | fleet | a named unit of externally sourced code with recorded provenance (commit, hash, license) this fleet vets before use | world-only |
| package | nix | a Nix derivation output with a store path | machine-only |
| policy | fleet | the organization's decision about which mutations are acceptable, independent of what enforces it | world-only |
| policy | machine | the running decision core (permission-gate, or the first-party pure core) that classifies a tool call | machine-only |
| `@` | Pi | Pi's own path-prefix sigil in its path-resolution grammar | machine-only |
| `@` | jj | jj's revset symbol for the current working-copy commit | machine-only |
| mutation | world | an irreversible-to-a-person change made to a file or a repository someone maintains | world-only |
| mutation | machine | the specific tool-call class the policy core classifies (`edit`, `write`, a semantic HTTP verb) | machine-only |
| activation | world | the human act of authorizing a new configuration to take effect on a real machine | world-only |
| activation | machine | the nix-darwin system-profile-link switch a `just activate` run performs | machine-only |
| probe | measurement | the act of interrogating actual repository state to learn something true about it | shared |
| probe | machine | a specific subprocess invocation (for example `jj --ignore-working-copy log ...`) with a literal argv and exit code | machine-only |
| machine | WRSPM | M, whatever executes the program, in this framework's own vocabulary | machine-only |
| machine | fleet | a nix-darwin laptop or cloud server this fleet manages | world-only |
| host | fleet | a physical or virtual machine in the fleet that runs a configuration | world-only |
| host | nix | the build or target platform designation nixpkgs cross-compilation vocabulary uses (`buildHost`/`hostPlatform`) | machine-only |
| interface | WRSPM | the alphabet of phenomena shared between world and machine, at which the specification is stated | shared |
| interface | nix/code | a module option interface, or a TypeScript interface type in extension source | machine-only |
| permission system | — | a native mechanism that gates a tool call pending human interactive approval | world-only |
| dialog | — | an interactive prompt awaiting a human's answer | world-only |
| UI channel | — | the means by which a Pi session can present a dialog to a human at all, independent of whether one is actually present to answer it | world-only |
| repository | recoverability | a version-controlled tree whose history can potentially recover a prior state of a file within it | shared |
| repository | forge-hosted | a version-controlled tree kept on a forge, whose declared outputs a build service can be asked to build | shared |
| history | — | the sequence of recorded prior states a repository's version-control system retains | shared |
| target | — | the file or path a proposed mutation would act on | shared |
| path | — | the string identifying a target's location, in whatever form the tool that opens it accepts | shared |
| untracked file | — | a file present in a repository's working tree that its version-control system has never recorded | shared |
| gitignored file | — | a file a repository's ignore rules exclude from being tracked even if added | shared |
| diagnostic | — | the textual output a probe emits describing the state it found | shared |
| `Hint:` line | — | a trailing advisory line jj appends after certain diagnostics | machine-only |
| configuration root | — | the directory atomic inherits from Pi and treats as the source of its own settings | machine-only |
| extension directory | — | the directory Pi loads extensions from unconditionally once a harness inherits its configuration root | machine-only |
| build service | fleet | a service that evaluates a forge-hosted repository's declared outputs, builds them, and publishes the outcome back to that forge | world-only |
| build service | machine | one running service unit and the state it owns, distinguished by its own user, database, and state directory | machine-only |
| forge | — | the hosted service where a forge-hosted repository lives, which announces its events and displays the outcomes published about it | world-only |
| forge application | — | a registered identity on a forge through which a build service acts, whose installation selection bounds the repositories that identity can see | shared |
| delivery | — | a message a forge sends a build service announcing that something happened in a repository | shared |
| check run | — | a named pass-or-fail outcome a build service publishes on a forge against a repository's commit | shared |
| required check | — | the repository's own forge-side configuration naming which check runs must pass before a change may merge | world-only |
| hostname | service | the public name at which a person reaches a service over the network | shared |
| hostname | host | the name the fleet gives one of its hosts, such as `magnetite`, which a requirement also writes as the host's name or the name of the host | shared |
| certificate | — | the credential that lets a hostname be served over a connection a browser accepts without warning | shared |
| forge credential | — | a secret value that authenticates a build service to a forge, or authenticates a forge's delivery to that service | shared |
| build capacity | — | the finite memory, processor time, and store disk available on one host at one time, shared by everything running on it | world-only |
| operator | — | the person who maintains this fleet's hosts and holds the credentials its services use | world-only |
| suspended state | — | a low-power state in which a host stops running entirely and does nothing further until a wake source rouses it | world-only |
| inactivity | — | an elapsed interval during which no person operates a host's own keyboard, pointer, or panel | world-only |
| wake source | — | a physical or electrical event a suspended host will resume for, such as a control pressed on the machine itself | shared |
| panel | — | the display built into a laptop, which is the surface a person standing at that machine looks at | shared |
| login screen | — | the state in which a host displays a credential prompt at its panel and no person is logged in | shared |
| desktop session | — | the state in which a person is logged in at a host's panel and interacting with a graphical desktop | shared |
| settings panel | — | the interface a desktop offers a person for changing that desktop's own settings, at the machine | shared |
| power source | — | whether a laptop is drawing from mains power or from its own battery | shared |
| telemetry store | — | the one service that keeps the fleet's series and answers queries over them | shared |
| signal | — | a measurable quantity of a host or of a service on it, such as available memory, a unit's restart count, or a pool's health | world-only |
| memory | — | the finite working store a host's processes draw on, whose available and used amounts are signals of that host | shared |
| out-of-memory | — | the event in which the kernel kills a process because its host's memory, or a service's memory ceiling, ran out; an out-of-memory signal counts those events on a host | shared |
| service | — | a program a host runs continuously on behalf of people or of other services, such as the forge, the build service, or the telemetry store | shared |
| source | — | the place on a host a collector reads a signal from, such as the host's own kernel counters or an endpoint on which a service publishes its own signals | shared |
| log record | — | a timestamped text record of one event a host or a service emits, one of the two kinds of telemetry that are not series | shared |
| trace | — | a record of one request's path through one or more services as a tree of timed spans, the other kind of telemetry that is not a series | shared |
| series | — | a named sequence of timestamped measurements of one signal, distinguished by its labels, kept in one database of the telemetry store | shared |
| database | telemetry | a named partition of the telemetry store whose series share one retention and are queried together | shared |
| database | service-state | a relational database a service keeps its own state in, on the host's database instance | machine-only |
| part of a database | — | a table within one of the telemetry store's databases, holding some of that database's series, which can carry a retention of its own that overrides the database's | shared |
| retention | — | the age past which a database's series are no longer kept or returned to a reader | shared |
| envelope | — | the ceilings on memory, disk, and processor share a service may draw on its host, together with its place in the order the kernel kills processes under memory pressure | shared |
| throttle | — | the kernel's slowing of a service once its memory reaches a level set below its memory ceiling, by reclaiming that service's memory before granting it more | shared |
| parallelism | — | the number of tasks a service runs at once | shared |
| memory pressure | — | the condition in which a host's demand for memory exceeds what it has, so the kernel must reclaim or kill | world-only |
| evaluation | build service | the part of a build service's work that computes a repository's declared outputs, which draws the most memory of any work on its host | world-only |
| collector | — | the service on a host that gathers that host's signals and writes them to the telemetry store | shared |
| queued interval | — | measurements a collector has gathered but the telemetry store has not yet accepted | shared |
| gap | — | an interval within a series for which measurements were gathered, or were due to be, but none are stored | shared |
| cardinality | — | the number of distinct series one signal produces | shared |
| writer | database | a person or service permitted to add series to a database | shared |
| writer | reference tree | the one account permitted to change a host's reference tree, held by no person and no agent | shared |
| reader | — | a person or service permitted to query a database's series | shared |
| store credential | — | a secret that authenticates a writer or reader to the telemetry store, or the telemetry store to its object storage | shared |
| object storage | — | the off-host bucket service in which the telemetry store keeps its series' data | shared |
| object data | — | the data the telemetry store keeps in object storage, where its series' data lives | shared |
| local state | — | the files a service keeps on its own host's disk | shared |
| unit | — | a supervised service or job on a host whose running state and restarts the host's supervisor records | shared |
| Omnigent worker | — | a service the fleet runs on behalf of one person to carry out Omnigent agent work, whose unit name carries that person's name | shared |
| person | service | a human being on whose behalf the fleet runs a service, or who uses one | world-only |
| person | account | a human who works under an account on a host | world-only |
| alias | — | a fixed name the fleet assigns one person, stored in place of that person's name | shared |
| failure notice | — | a message on the fleet's notification service telling a person that a named unit on a named host failed | shared |
| notification service | — | the fleet's push-message service, which delivers a message posted to a topic to every device subscribed to it | world-only |
| notifier | — | the job on a host that posts a failure notice to the fleet's notification service when a unit there fails | shared |
| credential | notification service | a secret a publisher presents to the fleet's notification service to be allowed to post to a topic that requires one | shared |
| vendor | — | the organization that publishes the telemetry store's software | world-only |
| release | vendor | a version of the telemetry store's software its vendor publishes; stable when its version carries no prerelease suffix | world-only |
| build | vendor | the packaged program of a release that its vendor publishes, as distinct from a package a channel builds from the vendor's source | world-only |
| channel | — | a nixpkgs branch this fleet pins packages from, which carries a vendor's release some time after the vendor publishes it | world-only |
| usage report | — | data a vendor's software sends back to its vendor about its own installation and use | shared |
| binary cache | — | a service that serves build outputs to hosts that would otherwise build them | world-only |
| web front end | — | the service on a host that terminates connections for its hostnames and forwards them to the services behind it | shared |
| overlay network | — | the fleet's private ZeroTier network, membership of which lets a host reach another host's mesh-only names | world-only |
| store account | — | a named identity the telemetry store authenticates, holding one store credential and one fixed permission to write, to read, or both | shared |
| watched list | — | the fleet's single list of units whose running state and restarts the collector records | shared |
| regulator | — | a check that fails when the property it watches does not hold, whether run when a host's configuration is evaluated or periodically on the host | shared |
| mutant | — | a deliberately broken variant of a configuration or regulator input, used to show that a regulator can fail | shared |
| runtime test | — | an on-demand test that runs services together in a container or a virtual machine and observes their behavior | shared |
| configuration | — | the declared settings from which a host's running system is built and activated | shared |
| kernel | — | the operating-system core of a host, which allocates its memory and kills a process when memory runs out | shared |
| kill preference | — | the weight a process declares for being chosen first or last when the kernel must kill a process for memory | shared |
| compressed swap | — | a swap device held compressed in a host's own memory, into which the kernel moves pages under memory pressure | shared |
| process | — | one running program on a host, identified to a reader only by its program name | shared |
| identifier | per-process | a value a series carries that tells one process apart from another process with the same program name | shared |
| process number | — | the number a host's kernel assigns a process when it starts, which differs for each process started | shared |
| command line | — | the program name and arguments with which a process was started | shared |
| memory floor | — | the least memory a process must hold for the collector to record a series for it | shared |
| storage pool | — | the pool of disks on a host from which every dataset on that host draws its space | shared |
| disk share | — | the portion of a host's storage pool set aside for one service, with a cap on what it may use and an amount held for it | shared |
| automatic snapshot | — | a copy of a disk share's contents a host takes on a schedule, which keeps holding the space it references | shared |
| query language | — | a language in which a reader asks the telemetry store for series, such as PromQL or SQL | shared |
| dashboard | — | the web pages a telemetry store serves through which a reader views its series as panels | shared |
| alert | — | a message on the fleet's notification service telling a person that an alert instance has started firing, is still firing, or has resolved | shared |
| alert rule | — | a named condition over a signal's series, with a severity and a holding time, whose truth on a host means one known failure class is present there | shared |
| alert instance | — | one alert rule's condition holding for one host and one set of labels, from the time it first holds until it resolves | shared |
| severity | — | the urgency an alert rule declares, critical, warning or info, which decides how loudly and how often a person is told | shared |
| evaluator | alerting | the job on magnetite that once a minute checks every alert rule against the telemetry store and posts alerts, each such check being one pass of the evaluator | shared |
| evaluator | build service | the build service's program that performs its evaluation, the first process the kernel kills on magnetite under memory pressure | shared |
| heartbeat | — | the minimum-priority message each completed pass of the evaluator posts, whose absence shows the evaluator has gone silent | shared |
| dead-man | — | the job on cinnabar that raises an alert when no heartbeat has reached the notification service for 10 minutes | shared |
| topic | — | a named channel on the fleet's notification service to which a publisher posts and from which every subscribed device receives | shared |
| alert budget | — | the number of firing alerts and failure notices, info alerts excluded, that may be posted in a rolling 24 hours across the fleet and from any one laptop before the excess is itself reported | shared |
| agent | — | software that works under an account on a person's behalf, without that person present | world-only |
| account | world | the standing under which a person, or an agent acting for a person, works on a host, with its own private home and its own credentials | shared |
| account | nix | a `users.users.<name>` declaration in a host's configuration | machine-only |
| private home | — | an account's own directory on a host, which no other account without administrative authority can read | shared |
| reference repository | — | a copy of an upstream project's source kept on a host so that accounts there can read it, as opposed to a repository someone maintains | shared |
| reference tree | — | the one location on a host holding every reference repository that host's participating accounts read | shared |
| participating account | — | an account the operator has declared as reading a host's reference tree | shared |
| acquisition request | — | a participating account's ask that a reference repository be added to, refreshed in, or deepened within the reference tree | shared |
| repository-local setting | — | a setting stored inside one repository that names a program git runs as whichever account uses that repository | shared |
| per-account copy | — | a reference repository an account held in its own private home before the reference tree was shared | shared |
| administrator | — | an account on a host that can run any program as any other account on that host | shared |
| failure class | — | a kind of fault a host or a service on it can be in, such as a degraded storage pool or a failed unit, which one alert rule is written to detect | shared |
| condition | alerting | the statement over a signal's series, or over dev-loop records, that an alert rule checks on each pass of the evaluator, and which either holds or does not | shared |
| holding time | — | how long an alert rule's condition must hold on every pass of the evaluator before its alert instance fires | shared |
| publisher | — | a person or service that posts a message to a topic of the fleet's notification service | shared |
| fleet | — | the set of hosts this repository configures, together with the services they run for the people who use them | world-only |
| pass | evaluator | one run of the evaluator over every alert rule, once a minute | shared |
| memory incident | — | an episode of memory pressure on a host, ending in reclaim or in the kernel killing a process | world-only |
| path | alert delivery | the chain of services an alert travels from the telemetry store, through the evaluator and the notification service, to a person's device | shared |
| time zone | — | a region's rule for converting an instant into a person's local clock time, including its daylight-saving changes | world-only |
| always-on host | — | a host the fleet expects to report its memory signal at all times, such as magnetite, whose silence is itself reported | shared |
| dev-loop history | — | the fleet's lasting record of how changes moved through the build service, the merge queue and deploys, kept in the telemetry store's dev-loop database for 365 days | shared |
| dev-loop record | — | one entry of the dev-loop history describing one event: an attribute's outcome in a build, a finished build, a batch event or a deploy | shared |
| build | build service | one run of the build service over one commit of a forge-hosted repository, from the time the build service accepts it until it finishes | shared |
| attribute | — | one declared output of a forge-hosted repository that a build evaluates and builds, and whose outcome the build service records | shared |
| derivation | — | the recipe from which one attribute's output is built, named by a store path, so that the same derivation in two builds means the same inputs | shared |
| outcome | — | how an attribute ended in one build: passed, failed on its own, failed because something it depends on failed, was cancelled, or was abandoned | shared |
| commit | — | one recorded state of a forge-hosted repository's history, named by its hash | shared |
| pull request | — | a proposed change to a forge-hosted repository, which the build service builds before the change may merge | shared |
| merge queue | — | the service that groups approved pull requests into batches, builds each batch and lands the batches that pass | shared |
| batch | — | a group of pull requests the merge queue builds and lands together | shared |
| batch event | — | one of the five transitions the merge queue announces for a batch: formed, built, landed, bisecting and done | shared |
| deploy | — | one activation, in the machine sense, of a configuration on a host, including the one each NixOS boot performs | shared |
| deploy record | — | the entry a host writes at each deploy naming the host, the closure it activated, the closure it replaced and the time | shared |
| closure | host | the complete built system a configuration produces for one host, identified by its store path | shared |
| closure | home | the complete set of built files and programs one account's home configuration produces, which a cloud session's setup step fetches from the binary cache and activates without producing it | shared |
| collected host | — | a host whose deploy records a collector ships to the telemetry store: magnetite, cinnabar, pyrite and stibnite | shared |
| error text | — | the free-form message the build service keeps when an attribute or a build fails, which can carry compiler output and repository content | shared |
| message body | — | the free text of a log record, as distinct from the named fields parsed out of it | shared |
| free text | — | any value whose content is not drawn from a fixed or bounded set, such as an error message or a whole log line | world-only |
| flaky attribute | — | within a window, an attribute whose one derivation both passed and failed on its own in builds there | shared |
| abandoned attribute | — | an optional attribute the build service stopped waiting for once the required attributes had settled, which this fleet's patch to it marked with fixed error text until 2026-11-25; stored rows from before then still carry it | shared |
| formation-to-land | — | for one batch, the interval from the merge queue forming it to the merge queue announcing it done | shared |
| queue wait | — | for one build, the interval from the build service accepting it to the build starting | shared |
| event | dev-loop | one occurrence in the dev loop, such as an attribute finishing, a build finishing, a batch transition or a deploy, that one dev-loop record describes | shared |
| field | — | one named value a dev-loop record or a source's entry carries | shared |
| credential | service database | a password or other secret that authenticates a reader to a service's own relational database | shared |
| credential | Linear | a key that lets an agent act in one of the operator's Linear workspaces, kept in a secret file that only the readers named for it can open | shared |
| agent host | — | a host of the fleet that runs a collector of its own, which gathers that host's signals and sends them on to the telemetry store | shared |
| provisioned host | — | a host of the fleet that currently exists and runs, as opposed to one that is only configured and is created on demand | world-only |
| ingress | — | the part of magnetite's collector that alone accepts other hosts' signals and writes them to the telemetry store | shared |
| collection certificate | — | the credential each agent host presents to the ingress, issued by the fleet's own collection authority, without which the ingress refuses the connection | shared |
| laptop | — | a portable host of the fleet, such as pyrite, that sleeps, travels and is powered off in ordinary use, so that its silence is not a fault | world-only |
| file system | — | a mounted dataset of a host's storage pool, whose used and free space are signals of that host | shared |
| disk health | — | the condition a physical disk reports about itself, such as a critical warning, its wear, its spare capacity and its media errors | shared |
| back-pressure | — | the ingress refusing signals for a while because it cannot pass them on, which the sending collector answers by keeping them and trying again | shared |
| notifier instance | — | one run of the notifier for one failed unit on one host, which the host's supervisor records as a unit of its own | shared |
| identifier | collector start | a value the collector's signals about itself carry that differs at each start of the collector | shared |
| owner | — | the person an Omnigent worker runs for, whose name the worker's unit name carries | world-only |
| collection | — | a collector's continuing gathering of its host's signals | shared |
| job | — | a unit that runs to completion each time it is started, by a timer or by another unit's failure, such as a regulator or the notifier | shared |
| expected host | — | for one alert rule, a host from which the fleet expects its signal: every collecting host, or for the disk-health rules each collecting host with a disk-health source | shared |
| silent | — | of a host or a job, having sent nothing it is expected to send for a stated time: a host no memory signal, the evaluator no heartbeat | shared |
| day | — | a UTC calendar day, the period the reconcile compares | shared |
| watch service | — | a monitoring service run by a third party outside the fleet, healthchecks.io, that expects a ping from the dead-man at a set period and emails the operator when one is late | world-only |
| ping | — | the request the dead-man sends the watch service at the end of a run in which it found the path working, which the watch service counts as the dead-man being alive | shared |
| email | — | a message the watch service sends to the operator's mailbox, delivered by a mail provider that runs on no host of the fleet | world-only |
| dashboard service | — | the service at its own hostname through which an admitted person views the fleet's signals and the dev-loop history, as distinct from the dashboard the telemetry store itself serves | shared |
| view | — | one named page of the dashboard service, holding charts over one subject, committed to the repository | shared |
| chart | — | one plot or table within a view, drawn from one query of the telemetry store | shared |
| dashboard group | — | the group of people the identity provider lets into the dashboard service | shared |
| admitted person | — | a person the identity provider has let into the dashboard service as a member of the dashboard group | shared |
| identity provider | — | the service that authenticates the fleet's people and tells another service who they are and whether to let them in, Kanidm here | shared |
| browser | dashboard | the program on a person's own device through which the person views the dashboard service | world-only |
| browser | relay | the program on a host of the fleet, Helium, in which the person works with their own browser profiles, signed-in sites and browser extensions such as the password manager | shared |
| browser profile | — | one separate set of a browser's signed-in sites, browser extensions and their settings, of which a person may keep several in one browser | shared |
| browser extension | — | a program a browser profile runs alongside the pages it shows, with the access to them the person grants it | shared |
| password manager | — | the browser extension, Bitwarden here, from which the person fills their stored sign-in details into sites | world-only |
| browser policy | — | a setting imposed on a browser from outside it, which the person cannot change from within that browser | shared |
| relay | — | the part of the agent that listens on the person's host for the relay extension and passes the agent's browser requests to it | shared |
| relay extension | — | the browser extension through which the relay drives tabs of the person's browser, published with each agent release | shared |
| extension folder | — | the one folder in an account's private home from which a browser profile loads the relay extension and into which the relay writes a newer release of it | shared |
| unpacked load | — | the person's act, once in a browser profile, of telling the browser to run a browser extension from a folder on the host rather than from the browser's extension catalogue | world-only |
| extension identity | — | the identifier a browser assigns a loaded browser extension, under which a browser profile keeps that extension's settings and permissions | shared |
| tab | — | one page a browser profile shows, which the person, or an agent through the relay, can open, read and act on | shared |
| browser request | — | an agent's request to open, read or act on a page, carried out in a browser the agent runs for itself or, when the request asks for the relay, in the person's browser | shared |
| release | agent | a version of the agent's software its publisher ships, together with the relay extension of the same version | world-only |
| darwin host | — | an agent host that runs macOS under nix-darwin, stibnite today, whose jobs launchd starts and whose job states and disk health its probe reads, as distinct from the NixOS hosts | shared |
| launchd job | — | a job or service a darwin host's launchd starts from its declaration, whose state, runs and last exit code launchd reports for as long as it is loaded, and of which launchd reports nothing once it is not loaded | shared |
| kept-alive job | — | a launchd job that launchd restarts whenever it stops, so that it is expected to be running whenever its darwin host is awake | shared |
| probe | darwin host | the job on a darwin host that once a minute, while the host is awake, reads each allow-listed launchd job's state and the host's disk health and writes them where the collector gathers them | shared |
| sleep | — | a laptop's suspended state, in which it runs nothing and sends nothing until it wakes | world-only |
| dark wake | — | a brief wake of a sleeping laptop for maintenance, without its panel lit, after which it sleeps again | world-only |
| watched launchd jobs | — | the fleet's single list of launchd job labels whose state, runs and last exit code a darwin host's probe reads, each job on it an allow-listed launchd job | shared |
| secret | — | a value whose disclosure would let someone act as the fleet, its operator, or a person in it | world-only |
| secret file | — | a file in the repository holding secrets, protected so that only its readers can recover them | shared |
| reader | secret file | a key whose holder can recover a secret file's contents | shared |
| operator credential | — | a secret that authenticates the operator to an outside service such as the forge, a DNS provider or a binary cache | world-only |
| operator identity | — | the personal key the operator uses day to day to read secrets | shared |
| recovery key | — | a key kept offline whose only use is to regain access to secrets when every other reader is lost | world-only |
| personal key | — | the private key a person holds to read the secrets meant for them | shared |
| machine key | — | the private key a host holds to read the secrets meant for it, distinct from its host key | shared |
| host key | — | the key a host proves its identity with over SSH, which the fleet pins for its hosts | shared |
| public key | — | the non-secret half of a key pair, from which anyone can encrypt to its holder or verify the holder's identity | shared |
| key store | — | the password manager in which the operator keeps people's SSH key pairs | world-only |
| workstation | — | a host a person logs into and works at, and which holds that person's personal key | world-only |
| retired host | — | a host that no longer exists, or a host's earlier hardware after the host was moved to new hardware | world-only |
| maintenance tool | — | a command the operator runs by hand to change the fleet's keys, readers or secrets | shared |
| working tree | — | the files of a repository's checkout on disk, tracked or not | shared |
| automated runner | — | an unattended run on a forge's or provider's machines that holds its own key to read the secrets it needs | shared |
| change | repository | a set of edits proposed to a repository and pushed to its forge for checking before it is accepted | shared |
| reader rule | — | the repository's own statement of which readers each secret file must have | shared |
| procedure | documentation | a sequence of steps the documentation tells a person to perform | world-only |
| documentation | — | the prose the fleet publishes describing how its hosts and secrets are arranged and how to operate them | world-only |
| correspondence | key | the fact that a public key the repository names is the public half of the key the named person or host actually holds | world-only |
| key | — | the secret half of a key pair, or the pair itself, held by a person or a host; qualified as personal key, machine key, host key, recovery key or public key wherever the sense matters | world-only |
| hardware | host | the physical machine a host runs on, which a host can outlive when it is moved to new hardware | world-only |
| item | key store | one named entry in the key store, holding a key pair or a credential and the fields that describe it | world-only |
| command | — | an instruction a person or a maintenance tool runs, named in the documentation or the repository, to act on a host, a secret file or the key store | shared |
| dependency updater | — | the service that looks for newer releases of a forge-hosted repository's dependencies and proposes each update to that repository as an update pull request | shared |
| hosted updater | — | the vendor-operated instance of the dependency updater's software that served this repository before the fleet ran its own, and which runs no update tasks for it | world-only |
| run | dependency updater | one pass of the dependency updater over the repository, started by its schedule or by the operator | shared |
| dry run | — | a run of the dependency updater that performs every step up to writing, records what it would have committed and opened, and writes nothing to the forge | shared |
| dependency | — | an externally sourced component a forge-hosted repository declares at a chosen version, such as a flake input or an npm package | shared |
| release | dependency | a version of a dependency that its upstream publishes, which the dependency updater can propose moving to | world-only |
| declaration | — | the place in a forge-hosted repository that states which version of a dependency it wants, such as a flake input's reference or a package's version range | shared |
| lock file | — | a file in a forge-hosted repository that records the exact versions its declarations resolved to, or a projection of another lock file into the form the build consumes | shared |
| derived pin | — | a declaration the repository requires to equal the version of another dependency rather than choosing its own | shared |
| npm Playwright pin | — | the version the documentation package declares for the npm `playwright` and `@playwright/test` packages, a derived pin | shared |
| Playwright flake input | — | the flake input that provides the Playwright driver and browsers the documentation tests run against, whose driver version the npm Playwright pin must equal | shared |
| consistent commit | — | a commit in which every lock file agrees with the declarations it records and every derived pin equals its source | shared |
| update pull request | — | a pull request the dependency updater opens to move one or more dependencies to newer releases | shared |
| update task | — | a command the repository asks the dependency updater to run in its copy of the repository after it changes a declaration and before it commits | shared |
| allowlist | — | the operator's list of patterns naming the commands the dependency updater may run as update tasks | shared |
| branch | — | a named, movable reference to a commit in a forge-hosted repository, on which a pull request proposes its change | shared |
| push | — | the act of sending commits to a branch of a forge-hosted repository, after which the build service evaluates the new tip | shared |
| follow-up commit | — | a commit pushed to a pull request after its first push to repair what the first push left inconsistent | shared |
| application key | — | the long-lived private key of a forge application, from which short-lived forge credentials for its installation are minted | shared |
| merge authorization | — | a person's act on a pull request that tells the merge queue to land it once its required checks pass, such as applying the queue's label or enabling auto-merge | shared |
| bypass | — | standing on the forge that exempts an identity from a repository's required checks and branch rules | shared |
| dependency dashboard | — | the issue on the forge in which the dependency updater lists the updates it has pending, held or awaiting approval | shared |
| flake input | — | a dependency a forge-hosted repository's flake declares by reference, whose exact version the flake lock file records | shared |
| comment | — | a message a person or service posts on a pull request or an issue on the forge | shared |
| Renovate instance | — | one running copy of the dependency updater's software, writing to the forge under one forge identity; the hosted updater and the fleet's updater are two instances | shared |
| flake-input updater | — | the dependency updater that refreshes the locked revisions of branch-tracking flake inputs, one pull request per input, apart from Renovate | shared |
| branch-tracking flake input | — | a flake input whose declaration names a branch, or no reference at all, so its locked revision moves whenever that branch does | shared |
| cloud session | — | a Claude Code conversation that runs in a container Anthropic hosts, started from claude.ai/code, the command line or another cloud session | shared |
| cloud environment | — | a named definition the operator owns on Anthropic's platform (allowed hosts, variables, setup step) from which cloud sessions start | shared |
| container | — | the virtual machine one cloud session runs in, either freshly built or started from an environment snapshot | shared |
| setup step | — | the shell script a cloud environment defines, which the platform runs as root in a freshly built container after cloning the attached repositories and before the model starts | shared |
| environment snapshot | — | the platform's saved copy of a container's disk after a successful setup step, from which later cloud sessions on the same cloud environment start without running it | shared |
| first prompt | — | the first turn of a cloud session, whose context the model reads before any of its tools runs | shared |
| user context | — | the instructions this repository generates for the operator's agents to follow in every repository they work in | shared |
| skill corpus | — | the named agent skills this repository composes for the operator's agents, first-party and vendored | shared |
| skill | — | one named set of instructions in the skill corpus, which an agent lists in its context and reads in full when it uses it | shared |
| required tool | — | a command-line program a skill tells the agent to run and cannot do its work without | shared |
| agent's shell | — | the shell in which a cloud session's agent runs commands | shared |
| attached repository | — | a repository selected when a cloud session starts, which the platform clones into its container and serves through the GitHub gate | shared |
| repository context | — | the instructions a repository carries for agents working in it, as distinct from the user context | shared |
| harness-owned state | — | the files and programs the platform places in a container and manages itself, such as its launcher settings, its hooks, its synced skills and the Claude Code program | shared |
| GitHub gate | — | the platform's filter on a cloud session's GitHub traffic, which refuses archive, codeload and API requests for repositories not attached to the session and serves anonymous git reads | world-only |
| pinned revision | — | one commit of this repository named by its full hash | shared |
| bootstrap run | — | one execution, inside a container, of the work this repository defines to install the user context, the skill corpus, the required tools and the repository context | shared |
| bootstrap report | — | a record a bootstrap run leaves in the container, stating what it installed, what it could not install and why, readable by the operator from the cloud session | shared |
| controller session | — | a cloud session the operator starts to create other cloud sessions on its cloud environment, change that environment's setup step and read what the other sessions report | shared |
| approval card | — | the prompt the platform shows the operator before it applies a change to a cloud environment that a cloud session proposes | shared |
| operator action | — | an act the operator performs by hand, such as starting a cloud session with a prompt, as distinct from accepting an approval card | world-only |
| Linear workspace | — | a named organisation on Linear in which the operator's issues, projects and documents live, reached with a key that workspace issues | world-only |
| disk | — | the persistent storage of a cloud session's container, which survives into the environment snapshot, as distinct from memory-backed storage that does not | shared |
| interactive terminal | — | a terminal screen a person watches and types into while a program runs, as distinct from a shell that only runs commands and returns their output | world-only |
| clipboard | — | the copy-and-paste buffer of a person's desktop session | world-only |
| main branch | — | this repository's default branch on the forge, whose newest commits the build service builds and publishes, and which a cloud environment that is not pinned follows | shared |
| input source | — | the fetched contents of one flake input at the version the flake lock file records, which evaluating the flake needs before anything is built | shared |
| plugin group | — | a named set of skills, or of agent instructions, that this repository publishes as one installable unit | shared |
| marketplace | — | the catalogue of plugin groups this repository publishes, which a person registers once in a tool to browse and install plugin groups from it | shared |
| apm consumer | — | a person, outside this fleet or in it, who registers the marketplace with apm and installs plugin groups into a project of their own | world-only |
| Claude app | — | Anthropic's Claude Code program or Claude desktop application, in which a person can add a marketplace by the forge name of its repository | world-only |
| Claude user | — | a person who has added the marketplace in a Claude app and installs plugin groups from it | world-only |
| skills CLI | — | the `skills` command-line program (vercel-labs/skills, run as `npx skills`), which clones a repository by its forge name and installs the individual skills it finds there | world-only |
| skills CLI user | — | a person who lists or installs skills from this repository with the skills CLI | world-only |
| evaluator | Nix | the program that computes the derivations a commit's declarations describe: stock Nix, or an alternative implementation such as iets answering to the same command name | shared |
| home configuration | — | the declared settings from which one user's environment on one platform is built and activated, separately from any host's configuration | shared |
| check | — | a test the build service builds for a pull request whose inputs it depends on, publishing its outcome as a check run | shared |
| refactor | — | a change to the repository whose author states that it alters no host's configuration, home configuration, check or runtime test, or only those it names as declared differences | shared |
| declared difference | — | a host's configuration, home configuration, check or runtime test that a refactor names, with its reason, before it is accepted, as one it changes, adds or removes, either certainly or possibly | shared |
| base commit | — | the commit a refactor starts from, against which its effect is judged | shared |
| candidate commit | — | the commit that carries a refactor's edits | shared |
| comparison | refactor | setting the derivations of every host's configuration, home configuration, check and runtime test at a refactor's base commit beside those at its candidate commit | shared |
| evaluation cost | — | the processor time, memory and work an evaluator spends computing one derivation, or the names of a set of them, from a commit's declarations | shared |
| cost measurement | — | one computation, by a fresh evaluator process, whose evaluation cost is recorded together with the evaluator, host and other work running at the time | shared |
| baseline | evaluation cost | the cost measurements of an unchanged commit, kept in the repository, against which a later claim about evaluation cost is compared | shared |
| primary user | — | the person a host belongs to and is set up around, at most one per host, whose account on it is that person's own | shared |
| admin account | — | the one account on a darwin host through which the operator administers it and under which its system-wide steps that act for a user run, which may or may not belong to the host's primary user | shared |
| person-account correspondence | — | the fixed pairing between a person and the one account name under which the fleet keeps that person's home configuration and keys, which for cameron is crs58 and for every other person is the person's own name | world-only |
| private settings | — | the part of a person's home configuration that only that person's own accounts may hold, such as the references to that person's secrets and personal choices | shared |
| fleet description | — | the repository's statement of the fleet's hosts, people, packages and inputs, from which every host and home configuration is built | shared |
| checked system | — | a platform, x86_64-linux or aarch64-darwin, for which the fleet's checks are built | shared |
| capability | fleet | a service or facility a host provides to people or to other hosts, such as a telemetry store, a reference tree or a provider's network setup | world-only |
| aspect | nix | a named module under `flake.modules.<class>.<name>` that a host configuration imports to take up one capability or shared shape | machine-only |
| cloud server | — | a host the fleet rents as a virtual machine from a cloud provider | world-only |
| cloud provider | — | the company whose infrastructure runs a cloud server, Hetzner Cloud or Google Cloud | world-only |
| network uplink | — | the network interface through which a cloud server reaches the internet | shared |
| state version | — | the release of a host's system tooling it was first set up with, which fixes defaults existing state depends on | shared |
| dataset | ZFS | a named file system in a host's storage pool, carrying properties such as quota, reservation and whether it is snapshotted | shared |
| install-time declaration | — | the statement of a host's disk layout from which it was installed, which later deploys do not reapply | shared |
| activation step | — | one ordered piece of work a darwin host performs while a new configuration takes effect | shared |

#### Scenario: The terms with two senses are read

- **WHEN** the table is read for terms that carry two senses in this repository
- **THEN** twenty-six terms carry more than one sense today and are disambiguated by separate rows rather than left to context: `session`, `package`, `policy`, `@`, `mutation`, `activation`, `probe`, `machine`, `host`, `interface`, `repository`, `build service`, `database`, `hostname`, `evaluator`, `person`, `writer`, `account`, `build`, `path`, `credential`, `identifier`, `browser`, `release`, `reader`, and `closure`, of which `probe`, `release`, `credential` and `evaluator` carry three and every other term two

#### Scenario: A term resolves to two phenomena

- **WHEN** a content term used in a behavioral requirement denotes two distinct phenomena within this repository's vocabulary
- **THEN** this designation table records both senses as separate rows rather than collapsing them into one

#### Scenario: A behavioral requirement uses an unlisted term

- **WHEN** the designation lint finds a content noun in a behavioral requirement that resolves to no row in this table
- **THEN** the noun is either added here as a world or shared phenomenon, or the requirement using it is redirected toward the interface stratum, and neither disposition is applied silently

