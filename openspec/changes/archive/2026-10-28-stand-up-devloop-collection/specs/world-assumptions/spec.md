## ADDED Requirements

### Requirement: A43 — nixbot's migrations create the build and attribute columns the dev-loop copy reads, and finish times are transaction start times

It is true of nixbot at `Mic92/nixbot@d020013fa`, independent of what this fleet builds, that its migrations create the columns the dev-loop queries read, that a restart overwrites an attribute's finish time, which is its transaction's start time, and that rows are kept 90 days.
Any requirement whose discharge depends on this fact SHALL name it explicitly, and SHALL be treated as losing its discharge once this assumption's violation condition below is observed.

**Evidence**: magnetite's deployed migrations `0001_initial.sql` to `0037_effect_when_changed.sql` are byte-identical to `b1f699803`'s, and `schema_migrations` records versions 1 to 37 with matching checksums (`logs/s2/grounding.md` §1.3); `d020013fa`, which PR #3536 pinned on 2026-10-21, adds no migration and changes no file under `nixbot/nixbot/migrations/` or `db_gen/` (`git diff --stat b1f699803 d020013fa`); finish times are written as `now()` (`nixbot/nixbot/db_gen/builds.py:257`, `:303`, `:352`, `:417`, `:436`) and reset to null on restart (`db_gen/events.py:97`); the prune is `retention_days`, 90 by default (`nixbot/nixbot/config.py:427-428`, `db_gen/maintenance.py:232-238`); the `devloop-queries` check at each input bump and `devloop-pg-grants`'s wait for its columns at each nixbot start are its monitors.

#### Scenario: A nixbot input bump changes the schema the copy reads

- **WHEN** a nixbot revision renames, drops or retypes a column the dev-loop queries or the reconcile read, drops the `(build_id, attr)` uniqueness, sets finish times from something other than the recording transaction, or changes its retention below the reconcile's window
- **THEN** this assumption is void, and the `devloop-collection` requirements `Every dev-loop event is recorded once and kept for a year`, `A gap in the dev-loop history reaches a person within a day` and `The past week of the dev loop can be asked about` lose the discharge argument that the export queries and the reconcile read the rows nixbot keeps

### Requirement: A44 — gitea-mq announces each batch transition in one of five exact journal messages

It is true of gitea-mq at `Mic92/gitea-mq@02264515b`, independent of what this fleet builds, that it journals each batch transition as one line whose `msg` is one of five exact values with fixed keys, with one `batch formed` and one `batch done` per batch number.
Any requirement whose discharge depends on this fact SHALL name it explicitly, and SHALL be treated as losing its discharge once this assumption's violation condition below is observed.

**Evidence**: the five messages and their keys are `batch formed` (`batch`, `branch`, `members`), `batch built` (`batch`, `build`, `sha`, `current`, `pending`), `batch landed` (`batch`, `sha`, `prs`), `batch bisecting` (`batch`, `build`, `failed_check`, `left`, `right`) and `batch done` (`batch`, `landed`, `ejected`, `builds`, `flaky`), written by slog's text handler to standard error (`internal/batch/batch.go:143`, `:228`, `:328`, `:391`, `:568`; `cmd/gitea-mq/main.go:52`); every one of the last 7 days' batch lines and the 9 retained `batch bisecting` lines carried exactly those keys, and `batch formed` and `batch done` occurred once per batch in the retained journal (`logs/s2/grounding.md` §2.1-§2.3); the four further messages beginning `batch ` at the pin do not equal any of the five; the reconcile's daily liveness comparison against nixbot's batch-branch builds is its monitor.

#### Scenario: gitea-mq renames a batch message or changes its keys

- **WHEN** a gitea-mq revision renames one of the five messages, drops or renames a key the dev-loop copy keeps, writes batch transitions elsewhere than its journal, or reuses a batch number
- **THEN** this assumption is void, and the `devloop-collection` requirements `Every dev-loop event is recorded once and kept for a year` and `The past week of the dev loop can be asked about` lose the discharge argument for batch events and formation-to-land, until the parser and the reconcile are revised

### Requirement: A45 — PostgreSQL on magnetite admits a local role named after the connecting system user without a password

It is true of PostgreSQL 16 as magnetite runs it, independent of what this fleet builds for the dev-loop copy, that a connection over the local socket is authenticated by peer, admitting the role whose name equals the connecting process's system user name and no other, with no password.
Any requirement whose discharge depends on this fact SHALL name it explicitly, and SHALL be treated as losing its discharge once this assumption's violation condition below is observed.

**Evidence**: `pg_hba_file_rules` on magnetite lists `local all all peer` after the `niks3` and `postgres` peer lines, and nixbot connects as `nixbot@/nixbot?host=/run/postgresql` (`logs/s2/grounding.md` §1.1); nixpkgs' module renders that default (`NixOS/nixpkgs@ac1faec44836:nixos/modules/services/databases/postgresql.nix:693`); `modules/nixos/gitea-mq.nix` relies on the same rule; the collector's first query after deploy and the reconcile's first run are its monitors.

#### Scenario: Local connections stop being peer-authenticated

- **WHEN** magnetite's PostgreSQL configuration requires a password on the local socket, maps system users to other role names, or admits a role whose name differs from the connecting user
- **THEN** this assumption is void, and the `devloop-collection` requirement `The build service's records are read without being changed and without a stored credential` loses the discharge argument that the readers hold no credential and act only as their own roles

### Requirement: A46 — GreptimeDB 1.2.1 keeps one row per key and time in a pre-created non-append table

It is true of GreptimeDB 1.2.1, independent of what this fleet builds, that a pre-created non-append table keeps one row per key and time, the last written, for OTLP logs through a pipeline, and that `auto_create_table=false` refuses a write to a missing table.
Any requirement whose discharge depends on this fact SHALL name it explicitly, and SHALL be treated as losing its discharge once this assumption's violation condition below is observed.

**Evidence**: a spike on magnetite with the deployed `greptimedb-bin` 1.2.1 and `otelcol-contrib` 0.155.0 wrote the same three rows three and four times through SQL and through OTLP with a pipeline, before and after flush and compaction, and kept three rows in every pre-created non-append table and nine to twelve in every append or write-created table; an extra pipeline field added a column; a missing table with the hint answered 400 (`logs/s2/spike-dedup.md`); the reconcile's daily comparison of stored keys with the source's, which fails on an unexplained extra row, is its monitor.

#### Scenario: A store upgrade changes deduplication or table creation

- **WHEN** a GreptimeDB release keeps more than one row per key and time in a non-append table, makes OTLP logs writes ignore a pre-created table's mode, or creates a missing table despite `auto_create_table=false`
- **THEN** this assumption is void, and the `devloop-collection` requirement `Every dev-loop event is recorded once and kept for a year` loses the discharge argument that re-read rows are stored once

### Requirement: A47 — The collector's sqlquery receiver resumes logs queries from the last row's tracking value

It is true of `otelcol-contrib` 0.155.0, independent of what this fleet builds, that its Development-stability `sqlquery` logs receiver resumes from the last row's tracking value, persisted across restarts, as its `journald` and `file_log` receivers persist their positions.
Any requirement whose discharge depends on this fact SHALL name it explicitly, and SHALL be treated as losing its discharge once this assumption's violation condition below is observed.

**Evidence**: the receiver's documentation at the pin states the body column, the parameterized tracking query and the storage property (`open-telemetry/opentelemetry-collector-contrib@aaf5045a2:receiver/sqlqueryreceiver/README.md:79-83`, `:158`, `:166-173`), and `otelcol-contrib components` on magnetite reports `sqlquery` logs at Development and names the file receiver `file_log` (`logs/s2/grounding.md` §4.2); the Development rating means the behaviour can change without a deprecation period; the on-demand container test at each collector bump and the reconcile's daily comparison are its monitors.

#### Scenario: A collector release changes how logs queries resume

- **WHEN** a collector release changes which row supplies the tracking value, stops binding it to the first parameter, stops persisting it, or stops persisting a journal or file read position
- **THEN** this assumption is void, and the `devloop-collection` requirement `Every dev-loop event is recorded once and kept for a year` loses the discharge argument that each source row is read at least once and no source is re-read from its beginning after a restart

### Requirement: A48 — magnetite's journal keeps gitea-mq's lines for longer than the reconcile's window

It is true of magnetite's journal, independent of what this fleet builds for the dev-loop copy, that it keeps gitea-mq's lines for at least two days after they are written.
Any requirement whose discharge depends on this fact SHALL name it explicitly, and SHALL be treated as losing its discharge once this assumption's violation condition below is observed.

**Evidence**: on 2026-10-21 the journal held gitea-mq lines from 2026-09-16 onwards in 1.9 GB, with no `SystemMaxUse` or `MaxRetentionSec` set (`logs/s2/grounding.md` §2.1); the reconcile, which counts the previous day's lines, fails if they are gone.

#### Scenario: The journal stops holding the previous day

- **WHEN** a journal size or retention limit, or a rotation, removes gitea-mq lines less than two days old
- **THEN** this assumption is void, and the `devloop-collection` requirement `A gap in the dev-loop history reaches a person within a day` loses the discharge argument that the reconcile can count the source side of batch events

### Requirement: A49 — NixOS and nix-darwin run activation snippets before the current system is relinked

It is true of NixOS and nix-darwin as pinned, independent of what this fleet builds, that each activation, including a NixOS boot, runs activation snippets with `$systemConfig` set before relinking `/run/current-system`, which then names the previous system or nothing.
Any requirement whose discharge depends on this fact SHALL name it explicitly, and SHALL be treated as losing its discharge once this assumption's violation condition below is observed.

**Evidence**: `NixOS/nixpkgs@ac1faec44836:nixos/modules/system/activation/activation-script.nix:55`, `:79`, and `nix-darwin/nix-darwin@4cff07de:modules/system/activation-scripts.nix:102`, `:140`, `:146` (ADR-005 Context); the on-demand container test's switch case and the reconcile's comparison of magnetite's latest record with its current system are its monitors.

#### Scenario: Activation relinks before the snippets run, or skips them

- **WHEN** a NixOS or nix-darwin release relinks `/run/current-system` before running activation snippets, stops exporting `$systemConfig` to them, or activates a system without running them
- **THEN** this assumption is void, and the `devloop-collection` requirement `A deploy can be attributed to the commits that built it` loses the discharge argument that each deploy record names the activated and the replaced closure

## MODIFIED Requirements

### Requirement: Grounded vocabulary for behavioral requirements

The corpus SHALL provide one designation record per content term this repository's `behavioral`-stratum requirements use, recording the term, the sense in which it is used when a term carries more than one, the world phenomenon it denotes, and whether that phenomenon is world-only, shared with the machine, or machine-only.
A term found to denote two distinct phenomena within this repository's vocabulary SHALL be recorded as two rows rather than collapsed into one.
Twenty-one terms carry two senses in this repository today and are disambiguated below rather than left to context: `session`, `package`, `policy`, `@`, `mutation`, `activation`, `probe`, `machine`, `host`, `interface`, `repository`, `build service`, `database`, `hostname`, `evaluator`, `person`, `writer`, `account`, `build`, `path`, and `credential`.

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
| closure | — | the complete built system a configuration produces for one host, identified by its store path | shared |
| collected host | — | a host whose deploy records a collector ships to the telemetry store, magnetite alone until the fleet's other collectors arrive | shared |
| error text | — | the free-form message the build service keeps when an attribute or a build fails, which can carry compiler output and repository content | shared |
| message body | — | the free text of a log record, as distinct from the named fields parsed out of it | shared |
| free text | — | any value whose content is not drawn from a fixed or bounded set, such as an error message or a whole log line | world-only |
| flaky attribute | — | within a window, an attribute whose one derivation both passed and failed on its own in builds there | shared |
| abandoned attribute | — | an optional attribute the build service stopped waiting for once the required attributes had settled, which this fleet's patch to it marks with fixed error text | shared |
| formation-to-land | — | for one batch, the interval from the merge queue forming it to the merge queue announcing it done | shared |
| queue wait | — | for one build, the interval from the build service accepting it to the build starting | shared |
| event | dev-loop | one occurrence in the dev loop, such as an attribute finishing, a build finishing, a batch transition or a deploy, that one dev-loop record describes | shared |
| field | — | one named value a dev-loop record or a source's entry carries | shared |
| credential | service database | a password or other secret that authenticates a reader to a service's own relational database | shared |

#### Scenario: A term resolves to two phenomena

- **WHEN** a content term used in a behavioral requirement denotes two distinct phenomena within this repository's vocabulary
- **THEN** this designation table records both senses as separate rows rather than collapsing them into one

#### Scenario: A behavioral requirement uses an unlisted term

- **WHEN** the designation lint finds a content noun in a behavioral requirement that resolves to no row in this table
- **THEN** the noun is either added here as a world or shared phenomenon, or the requirement using it is redirected toward the interface stratum, and neither disposition is applied silently
