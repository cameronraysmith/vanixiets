## MODIFIED Requirements

### Requirement: Grounded vocabulary for behavioral requirements

The corpus SHALL provide one designation record per content term this repository's `behavioral`-stratum requirements use, recording the term, the sense in which it is used when a term carries more than one, the world phenomenon it denotes, and whether that phenomenon is world-only, shared with the machine, or machine-only.
A term found to denote two distinct phenomena within this repository's vocabulary SHALL be recorded as two rows rather than collapsed into one.

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
| collected host | — | a host whose deploy records a collector ships to the telemetry store: magnetite, cinnabar and pyrite, and not yet stibnite | shared |
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
| browser | — | the program on a person's own device through which the person views the dashboard service | world-only |

#### Scenario: The terms with two senses are read

- **WHEN** the table is read for terms that carry two senses in this repository
- **THEN** twenty-two terms carry two senses today and are disambiguated by separate rows rather than left to context: `session`, `package`, `policy`, `@`, `mutation`, `activation`, `probe`, `machine`, `host`, `interface`, `repository`, `build service`, `database`, `hostname`, `evaluator`, `person`, `writer`, `account`, `build`, `path`, `credential`, and `identifier`

#### Scenario: A term resolves to two phenomena

- **WHEN** a content term used in a behavioral requirement denotes two distinct phenomena within this repository's vocabulary
- **THEN** this designation table records both senses as separate rows rather than collapsing them into one

#### Scenario: A behavioral requirement uses an unlisted term

- **WHEN** the designation lint finds a content noun in a behavioral requirement that resolves to no row in this table
- **THEN** the noun is either added here as a world or shared phenomenon, or the requirement using it is redirected toward the interface stratum, and neither disposition is applied silently

## ADDED Requirements

### Requirement: A56 — Kanidm refuses an authorization whose scopes no group of the person maps

It is true of Kanidm 1.11.2, independent of what this fleet builds, that when a person asks an OAuth2 client for scopes outside the union of the scope maps of that person's groups, Kanidm answers Access Denied and issues no code.
Any requirement whose discharge depends on this fact SHALL name it explicitly, and SHALL be treated as losing its discharge once this assumption's violation condition below is observed.

**Evidence**: `kanidm/kanidm@v1.11.2:server/lib/src/idm/oauth2.rs:3473-3502`, called at `:2517-2519`; the same scope maps, with `displayName` and one `originLanding`, put the client's tile in a member's apps portal (`server/lib/src/idm/applinks.rs:6-69`); omnigent's and matrix's clients gate their groups this way (`modules/nixos/kanidm.nix:228-277`); the operator's recorded refusal of `cameron` before he joins `perses_users` is its monitor at deployment.

#### Scenario: Kanidm admits a person outside the scope maps

- **WHEN** a Kanidm upgrade issues a code to a person none of whose groups maps a requested scope, or the operator's refusal test is admitted
- **THEN** this assumption is void, and the `fleet-dashboard` requirement `A person outside the dashboard group is refused` loses its discharge until the dashboard service checks group membership itself

### Requirement: A57 — Dashboard-group membership is kept in the running identity provider

It is true of this fleet, independent of its configuration, that membership of `perses_users` is set by the operator in the running Kanidm with `kanidm group add-members` and `remove-members`, and that provisioning declares the group with no members and does not overwrite them.
Any requirement whose discharge depends on this fact SHALL name it explicitly, and SHALL be treated as losing its discharge once this assumption's violation condition below is observed.

**Evidence**: the repository provisions no person and declares each `*_users` group as a stub with `overwriteMembers = false` (`modules/nixos/kanidm.nix:196-226`); the runbook adds members by hand and records that a non-member sees Kanidm's Access Denied (`packages/docs/src/content/docs/development/operations/identity/kanidm.md:49`, `:63`).

#### Scenario: Membership becomes declarative

- **WHEN** the repository declares members of `perses_users`, or provisioning overwrites them
- **THEN** this assumption is void, and the `fleet-dashboard` requirements `A person outside the dashboard group is refused` and `A person removed from the dashboard group loses access within an hour` must be restated over the declared list

### Requirement: A58 — Perses 0.55.1 removes its write routes in read-only mode, proxies with the stored credential and fixed headers, and refreshes a session without depending on the identity provider's answer

It is true of Perses 0.55.1, independent of what this fleet builds, that read-only mode removes writes and sign-up, its proxy authenticates from a secret file, fixes configured headers, drops unlisted ones, refuses unmatched paths, provisioning never deletes, and a refresh ignores the identity provider's answer.
Any requirement whose discharge depends on this fact SHALL name it explicitly, and SHALL be treated as losing its discharge once this assumption's violation condition below is observed.

**Evidence**: read at v0.55.0 (`bfaf3ce2`): `perses/perses@v0.55.0:internal/api/core/server.go:63-93`, `internal/api/impl/v1/user/endpoint.go`, `internal/api/impl/proxy/http/http.go:157-306`, `internal/api/provisioning/service.go:43-120`, `internal/api/crypto/jwt.go:102-110` and `internal/api/impl/auth/auth.go:167-207`, where a refresh issues an access token valid for `access_token_ttl` from the refresh and returns the same refresh token, and calls Kanidm's token endpoint when an OIDC refresh cookie exists but ignores the answer, on failure only clearing the OIDC cookies; `perses/spec@v0.3.0-rc.1:go/datasource/proxy/http/http.go:89-93` for `allowHeaders`; the plan review's stub-upstream probe at 0.55.0 (`logs/cam73-evidence/1.1-runtime-probe-20261104T234415Z.log`), showing a caller's `x-greptime-auth` passed through a datasource without `allowHeaders` and dropped by one with it; 0.55.1 is a patch release, so Task 2's first step re-runs that probe at 0.55.1 before any code lands, and `vmTests.x86_64-linux.perses-greptimedb` is the monitor at 0.55.1 and at every upgrade.

#### Scenario: A Perses upgrade changes one of these behaviours

- **WHEN** the container runtime test or the probe finds a write route answering in read-only mode, a configured header passed from the caller, a caller header outside `allowHeaders` forwarded, an unmatched path forwarded, a planted resource kept after a restart with the wipe, or a session that outlives `refresh_token_ttl` plus `access_token_ttl`
- **THEN** this assumption is void for that version, and the `fleet-dashboard` requirements resting on it lose their discharge until the configuration or the assumption is restated

### Requirement: A59 — GreptimeDB 1.2.1 reads x-greptime-auth before Authorization

It is true of GreptimeDB 1.2.1, independent of what this fleet builds, that its HTTP authentication reads the `x-greptime-auth` header before `Authorization`, and that a present but unparsable value fails rather than falling back.
Any requirement whose discharge depends on this fact SHALL name it explicitly, and SHALL be treated as losing its discharge once this assumption's violation condition below is observed.

**Evidence**: `GreptimeTeam/greptimedb@179ff8e50:src/servers/src/http/authorize.rs:310-319`; the container runtime test's bypass negative control, through a datasource without `allowHeaders`, is its monitor.

#### Scenario: The store stops preferring the header

- **WHEN** a store upgrade reads `Authorization` first or ignores `x-greptime-auth`
- **THEN** this assumption is void, and neither the datasources' header allow-lists nor the strip in front of the dashboard service is then what keeps a person's credential away from the store; the `fleet-dashboard` requirement `No store credential reaches a person, and the dashboard service only reads` keeps its discharge through the proxy's own authorization only if the bypass control then shows the proxy's identity winning

### Requirement: A60 — magnetite is reachable on public TCP port 80 for HTTP-01

It is true of magnetite, independent of this change, that its public address accepts TCP port 80 from the certificate authority, so nginx's ACME HTTP-01 challenge for a name pointing at it succeeds.
Any requirement whose discharge depends on this fact SHALL name it explicitly, and SHALL be treated as losing its discharge once this assumption's violation condition below is observed.

**Evidence**: magnetite opens TCP 80 and 443 publicly and `security.acme.defaults.dnsProvider` evaluates to `null`, and the existing `accounts.`, `omni.` and `auth.` names hold certificates issued this way (`modules/terranix/cloudflare.nix:177-216`).

#### Scenario: HTTP-01 stops reaching magnetite

- **WHEN** a firewall or proxy change blocks port 80, or issuance for a magnetite name fails
- **THEN** this assumption is void, and the `fleet-dashboard-interface` requirement `The dashboard hostname resolves to magnetite` no longer yields a certificate a browser accepts until DNS-01 or another route is configured
