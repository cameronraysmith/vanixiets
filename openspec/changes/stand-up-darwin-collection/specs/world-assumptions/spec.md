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
| collected host | — | a host whose deploy records a collector ships to the telemetry store: magnetite, cinnabar, pyrite and stibnite | shared |
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
| darwin host | — | an agent host that runs macOS under nix-darwin, stibnite today, whose jobs launchd starts and whose job states and disk health its probe reads, as distinct from the NixOS hosts | shared |
| launchd job | — | a job or service a darwin host's launchd starts from its declaration, whose state, runs and last exit code launchd reports for as long as it is loaded, and of which launchd reports nothing once it is not loaded | shared |
| kept-alive job | — | a launchd job that launchd restarts whenever it stops, so that it is expected to be running whenever its darwin host is awake | shared |
| probe | darwin host | the job on a darwin host that once a minute, while the host is awake, reads each allow-listed launchd job's state and the host's disk health and writes them where the collector gathers them | shared |
| sleep | — | a laptop's suspended state, in which it runs nothing and sends nothing until it wakes | world-only |
| dark wake | — | a brief wake of a sleeping laptop for maintenance, without its panel lit, after which it sleeps again | world-only |

#### Scenario: The terms with two senses are read

- **WHEN** the table is read for terms that carry two senses in this repository
- **THEN** twenty-two terms carry more than one sense today and are disambiguated by separate rows rather than left to context: `session`, `package`, `policy`, `@`, `mutation`, `activation`, `probe`, `machine`, `host`, `interface`, `repository`, `build service`, `database`, `hostname`, `evaluator`, `person`, `writer`, `account`, `build`, `path`, `credential`, and `identifier`, of which `probe` carries three and every other term two

#### Scenario: A term resolves to two phenomena

- **WHEN** a content term used in a behavioral requirement denotes two distinct phenomena within this repository's vocabulary
- **THEN** this designation table records both senses as separate rows rather than collapsing them into one

#### Scenario: A behavioral requirement uses an unlisted term

- **WHEN** the designation lint finds a content noun in a behavioral requirement that resolves to no row in this table
- **THEN** the noun is either added here as a world or shared phenomenon, or the requirement using it is redirected toward the interface stratum, and neither disposition is applied silently

## ADDED Requirements

### Requirement: A61 — launchd misses a StartInterval firing during sleep and coalesces missed StartCalendarInterval firings into one run at wake

It is true of launchd on macOS 26.7.1, independent of what this fleet builds, that a `StartInterval` firing due during sleep is skipped, and that `StartCalendarInterval` firings missed during sleep become one run at wake, with no time-zone field.
Any requirement whose discharge depends on this fact SHALL name it explicitly, and SHALL be treated as losing its discharge once this assumption's violation condition below is observed.

**Evidence**: `launchd.plist(5)` on stibnite at macOS 26.7.1, read on 2026-11-05, states at lines 441-445 that a `StartInterval` firing due while the system is asleep "will be missed due to shortcomings in kqueue(3)", and at lines 455-458 that, unlike cron, launchd starts a `StartCalendarInterval` job at the next wake and coalesces several missed intervals into one event (line numbers of the roff source `/usr/share/man/man5/launchd.plist.5`); its calendar fields are Minute, Hour, Day, Weekday and Month with no zone key, and the manual says nothing of clock or zone changes; stibnite's two calendar jobs, `harmonia-gc` daily at 03:15 and `nix-cleanup-gcroots` on Sunday at 03:30 in `America/New_York`, fall in neither the repeated nor the skipped hour of a daylight-saving change; a macOS major-version upgrade on stibnite is the event at which this manual is read again, and the absence of any `otel-envelope` run in stibnite's logs between a recorded sleep and its wake is its monitor.

#### Scenario: launchd changes how it treats sleep

- **WHEN** a macOS release starts a `StartInterval` job for intervals that fell due during sleep, starts a `StartCalendarInterval` job more than once at wake for coalesced firings or not at all, or adds a time zone to the calendar
- **THEN** this assumption is void, and the `fleet-ingress-interface` requirement `No darwin collection job runs on a calendar schedule`, the `fleet-alerting` requirement `An unreachable telemetry store or a silent host freezes alerts` and the `fleet-alerting-interface` requirement `Store errors and silent hosts freeze instance state` lose the argument that a sleeping darwin host runs no collection job and that its existing calendar jobs run once per due time

### Requirement: A62 — launchctl print reports a system job's state, runs and last exit code as unversioned text, and omits the exit code for some killed jobs

It is true of `launchctl` on macOS 26.7.1, independent of what this fleet builds, that `launchctl print system/<label>` prints a job's `state`, `runs` and `last exit code` as unversioned text, `Could not find service` when not loaded, and for some killed jobs no exit code.
Any requirement whose discharge depends on this fact SHALL name it explicitly, and SHALL be treated as losing its discharge once this assumption's violation condition below is observed.

**Evidence**: on stibnite on 2026-11-05, `launchctl print system/org.nixos.nix-daemon` printed `state = running`, `runs = 3`, `pid` and `last exit code = 0`, `launchctl print system/org.nixos.nix-cleanup-gcroots` printed `state = not running` and its calendar, and a label that is not loaded printed `Could not find service`; a read-only survey of the 441 jobs in the system domain found 98, among them the running `com.apple.tzlinkd`, that printed `last exit reason = JETSAM_REASON_MEMORY_IDLE_EXIT` and no `last exit code` line, found exit codes printed as bare integers or `(never exited)`, and found no job printing a signal; of 475 jobs in the operator's per-user domain one printed `last exit reason = JETSAM_REASON_MEMORY_PERPROCESSLIMIT` and no exit-code line; the same text was printed to an unprivileged account as to the operator's; `launchctl(1)` says its print output is not API; the probe's parser fixtures, recorded on stibnite at macOS 26.7.1, and `RuleSignalMissing` on the launchd selectors are its monitors, and a macOS major-version upgrade on stibnite is the event at which the fixtures are recorded again.

#### Scenario: launchctl changes what it prints

- **WHEN** a macOS release renames or reshapes the `state`, `runs` or `last exit code` lines, changes the answer for a label that is not loaded, or a re-recorded fixture differs from the recorded one
- **THEN** this assumption is void, and the `fleet-ingress-interface` requirement `The darwin probe reports each allow-listed launchd job and the host's disk health in a textfile` and the `fleet-alerting` requirement `Each known failure class on a host reaches a person as an alert` lose the discharge argument that the probe's series state each launchd job's state, runs and last exit code, until the parser is rewritten against the new text

### Requirement: A63 — stibnite's internal SSD answers the SMART health read without privilege at the pinned smartmontools

It is true of stibnite's internal `APPLE SSD AP4096Z`, `disk0`, independent of what this fleet builds, that smartmontools 7.5's `smartctl -j -H -A disk0` returns its NVMe health log, with its overall status, critical warning and wear, to an account without administrative authority.
Any requirement whose discharge depends on this fact SHALL name it explicitly, and SHALL be treated as losing its discharge once this assumption's violation condition below is observed.

**Evidence**: on 2026-11-05 at macOS 26.7.1 (25G241) on an Apple M5 Pro, smartctl 7.5 from the root pin (`NixOS/nixpkgs@3a32588c`) with exactly `-j -H -A disk0` exited 0 as `crs58` and as `nobody`, reporting protocol `NVMe`, `smart_status.passed` true, `critical_warning` 0 and `percentage_used` 0 for device `APPLE SSD AP4096Z`; the probe's own account, `_prometheus-node-exporter`, did not yet exist and is read before deploy; a smartmontools version change or a macOS major-version upgrade on stibnite is the event at which this read is repeated, and `RuleSignalMissing` on the disk-health selectors once stibnite is an expected host for them is its monitor.

#### Scenario: The SSD stops answering an unprivileged read

- **WHEN** a macOS update or a smartmontools bump makes the read fail without privilege, or the store holds no `smartctl_device_critical_warning_total` for stibnite while stibnite reports its memory signal
- **THEN** this assumption is void, and the `host-metrics-collection` requirement `Each agent host contributes its own signals to the telemetry store`, the `fleet-ingress-interface` requirement `A laptop's disk health is read on the host and served on loopback` and the `fleet-alerting` requirement `Each known failure class on a host reaches a person as an alert` lose the discharge argument for stibnite's disk health

### Requirement: A64 — stibnite sleeps and wakes in the dark many times a day

It is true of stibnite, independent of what this fleet builds, that with Power Nap on it sleeps and wakes about 90 to 140 times a day, most of those wakes being dark wakes of seconds in which its kept-alive jobs resume briefly before it sleeps again.
Any requirement whose discharge depends on this fact SHALL name it explicitly, and SHALL be treated as losing its discharge once this assumption's violation condition below is observed.

**Evidence**: on 2026-11-05 `pmset -g` on stibnite reported `sleep 1`, `standby 1`, `hibernatemode 3` and `powernap 1`, and its power log held 132 `Sleep`, 137 `Wake` and 124 `DarkWake` entries for 2026-11-03 and 92, 98 and 87 for 2026-11-04; the counts of `pmset -g log` across a lid-closed sleep and a natural overnight sleep at acceptance are its monitor, and a macOS major-version upgrade or a change of these power settings is the event at which they are counted again.

#### Scenario: stibnite's sleep pattern changes

- **WHEN** Power Nap is turned off or the power settings change, stibnite's power log shows a daily count of sleeps or dark wakes far outside this range, or a dark wake lasts long enough for the evaluator to see stibnite report on several consecutive passes
- **THEN** this assumption is void, and the `fleet-alerting` requirement `An unreachable telemetry store or a silent host freezes alerts` and the `fleet-alerting-interface` requirement `Store errors and silent hosts freeze instance state` lose the argument that their pending-time and freeze cases model stibnite's sleep, until those cases are re-derived from the new pattern

### Requirement: A65 — A store-built binary on stibnite reaches the ingress over ZeroTier

It is true of stibnite at macOS 26.7.1, independent of what this fleet builds, that a program built in the Nix store can open a TCP connection over the ZeroTier network to the ingress on magnetite, which then refuses the connection at the TLS handshake only for want of a collection certificate.
Any requirement whose discharge depends on this fact SHALL name it explicitly, and SHALL be treated as losing its discharge once this assumption's violation condition below is observed.

**Evidence**: on 2026-11-05 a store-built curl 8.22.0 on stibnite reached `[fddb:4344:343b:14b9:399:930f:39db:40d2]:4318` and was refused with `tlsv13 alert certificate required`, as `/usr/bin/curl` was, against the note at `pkgs/by-name/ntfy-send/package.nix:5-6` that darwin blocks store binaries from TCP over ZeroTier; stibnite's ZeroTier is the macOS ZeroTier One application, outside nix-darwin; the collector's own first export from stibnite after its activation is its monitor, and a macOS major-version upgrade or an endpoint-security change on stibnite is the event at which it is observed again.

#### Scenario: stibnite blocks store-built programs from the overlay network

- **WHEN** the store-built collector on stibnite cannot connect to the ingress while `/usr/bin/curl` can, or a macOS release or endpoint-security product blocks store-built programs from ZeroTier
- **THEN** this assumption is void, and the `host-metrics-collection` requirements `Each agent host contributes its own signals to the telemetry store` and `A failed collection or store job notifies a person`, whose notifier on stibnite is also store-built, and the `devloop-collection-interface` requirement `Each agent host's collector ships its own deploy records` lose the argument that stibnite's signals, notices and deploy records leave the host

### Requirement: A66 — ntfy refuses an anonymous post to a fleet topic from stibnite

It is true of ntfy as cinnabar runs it, independent of stibnite's configuration, that a post to a `fleet-*` topic from stibnite over ZeroTier without a token is refused with 403, because cinnabar's access entries let `alerter` alone write the `fleet-*` topics and everyone else only read them.
Any requirement whose discharge depends on this fact SHALL name it explicitly, and SHALL be treated as losing its discharge once this assumption's violation condition below is observed.

**Evidence**: on 2026-11-05 an anonymous POST from stibnite over ZeroTier to a `fleet-*` topic was refused with 403, under cinnabar's entries `alerter:fleet-*:rw` and `*:fleet-*:ro`, which A38 orders; so stibnite's senders need the `alerter` token, which stibnite reads as the seventh reader of the existing shared `ntfy-alerter` generator, and a compromised stibnite holding it can post to any `fleet-*` topic, as pyrite can today; the anonymous POST repeated at acceptance is its monitor, and a ntfy version change on cinnabar is the event at which it is repeated.

#### Scenario: An anonymous post from stibnite is accepted

- **WHEN** an anonymous post from stibnite to a `fleet-*` topic is accepted, or cinnabar's access entries for the `fleet-*` topics change
- **THEN** this assumption is void, and the `fleet-alerting-interface` requirements `The alerter token travels only as a file` and `This capability states its own trust boundary` and the `host-metrics-collection` requirement `A failed collection or store job notifies a person` lose the argument that stibnite's notices need the `alerter` token and that holding it is the extent of stibnite's exposure

### Requirement: A70 — macOS top prints a process's physical footprint as unversioned text to an unprivileged account

It is true of `/usr/bin/top` on macOS 26.7.1, independent of what this fleet builds, that `top -l 1 -pid <pid> -stats pid,mem` prints a process's physical footprint as unversioned text, a MEM field with a `B`, `K`, `M` or `G` suffix, to an unprivileged account for a root-owned process too, as `top` is setuid.
Any requirement whose discharge depends on this fact SHALL name it explicitly, and SHALL be treated as losing its discharge once this assumption's violation condition below is observed.

**Evidence**: on stibnite on 2026-11-06, `top(1)` described `mem` as "Physical memory footprint of the process" and `/usr/bin/top` was `-r-sr-xr-x root wheel`; run as `_otelcol` it printed `102M` for the root-owned `otelcol-process` and `134M` for the agent, where `/usr/bin/footprint` as root printed `phys_footprint: 102 MB` and `134 MB` and `ps -o rss=` 183,792 KiB and 223,664 KiB, while `/usr/bin/footprint` as `_otelcol` found no process for the root-owned pid; across all processes it printed values with the suffixes `K`, `M` and `G`, a second sample (`-l 2`) appended `+` or `-` to a changed value, and a pid that does not exist printed the header with no `PID MEM` line (`logs/s5-evidence/c5-top-recording-20261106T052605Z.log`); the recorded texts are `otel-envelope`'s fixtures, every darwin envelope run is its monitor, and a macOS major-version upgrade is the event at which it is recorded again.

#### Scenario: top changes what it prints

- **WHEN** a macOS release reshapes `top`'s logging-mode output or its MEM field, measures MEM other than as the physical footprint, or stops answering an unprivileged account for another account's process
- **THEN** this assumption is void, and the `fleet-ingress-interface` requirement `otel-envelope regulates each agent from its own collector` and the `telemetry-store-interface` requirement `The telemetry store and the collector run inside a declared envelope` lose the argument that the darwin envelope bounds each collector's physical footprint, until the memory clause is rewritten against the new text; an unreadable field already fails the clause

### Requirement: A77 — macOS resident size counts each process's mapped share of the shared cache, so ordinary processes read tens to hundreds of MiB

It is true of macOS 26.7.1, independent of what this fleet builds, that the darwin process scraper's resident size counts mapped shared-cache pages, so ordinary daemons read 65-300 MiB, and that its process name is the kernel's `p_comm`.
Any requirement whose discharge depends on this fact SHALL name it explicitly, and SHALL be treated as losing its discharge once this assumption's violation condition below is observed.

**Source**: the value is `proc_pidinfo`'s `pti_resident_size` (`contrib@v0.155.0:receiver/hostmetricsreceiver/internal/scraper/processscraper/process_scraper.go:321-326`; `gopsutil@v4.26.5:process/process_darwin.go:477-492`), and the name is `p_comm` (`process_darwin.go:65-87`).

**Evidence**: stibnite's stored `process_memory_usage_bytes` from 2026-11-06T05:17Z to 21:14Z, as `regulator` (`logs/s5-evidence/cam72-stibnite-names-*.log`, `cam72-hourly-floors-*.log`), held 82 names above the 64 MiB floor, among them `WindowServer` at most 296 MiB, `corespotlightd` 243 MiB, `loginwindow` 193 MiB, `mds_stores` 135 MiB, `logd` 78 MiB and `otelcol-contrib` 230 MiB, the last against a physical footprint `top` printed as 102M and 134M (A70); the hourly distinct-name peak was 70 at 64 MiB, 43 at 128, 31 at 192, 21 at 256, 12 at 384 and 9 at 512 MiB, where pyrite peaked at 15 and magnetite at 37 at 64 MiB, and `otel-envelope` on magnetite failed B3 with `stibnite process_executable_name 63` from 15:00Z; `ps -o comm=` on stibnite showed `nix` for `org.nixos.nix-daemon`, `python3.14` for `org.nixos.omnigent-host-cameron` and `node_exporter` and `dnscrypt-proxy` as the children of their `-start` wrappers; `process.minBytes.darwin` and `process.darwinFleetExecutables` rest on it, and B3 over stibnite's rows is its monitor; a macOS major-version upgrade or a contrib pin that reports another memory figure is the event at which the distribution is read again.

#### Scenario: darwin resident size no longer counts the shared cache, or names change

- **WHEN** the darwin process scraper reports a figure other than `pti_resident_size`, a macOS release stops counting shared-cache pages in it, or a fleet daemon's process reports a name other than its `process.darwinFleetExecutables` entry
- **THEN** this assumption is void, and the `host-metrics-collection` requirement `Series cardinality stays bounded` loses the argument that a 384 MiB darwin floor with the fleet's executables kept holds stibnite at or below 20 names an hour, and the argument that every fleet executable stays visible below the floor, until the distribution is measured again and the floor and map follow it
