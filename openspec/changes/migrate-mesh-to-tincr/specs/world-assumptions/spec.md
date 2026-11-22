## RENAMED Requirements

- FROM: `### Requirement: A33 — The fleet's notification service on cinnabar is reachable over ZeroTier and is the single delivery path`
- TO: `### Requirement: A33 — The fleet's notification service on cinnabar is reachable over the overlay network and is the single delivery path`
- FROM: `### Requirement: A65 — A store-built binary on stibnite reaches the ingress over ZeroTier`
- TO: `### Requirement: A65 — A store-built binary on stibnite reaches the ingress over the overlay network`

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
| overlay network | — | the fleet's private network that its overlay members join over whatever networks they are attached to, membership of which lets a member reach another member's canonical names | world-only |
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
| overlay member | — | a host or other device, such as a phone, that the overlay network admits | world-only |
| overlay address | — | the address at which the overlay network reaches one overlay member, fixed by that member's name, from which the member's packets come | shared |
| canonical name | — | the one name under the fleet's private domain by which a person or service reaches an overlay member or a service, such as `cinnabar.vanixiets.internal` or `ntfy.vanixiets.internal` | shared |
| name service | — | the service that answers canonical names with overlay addresses for every overlay member and forwards other names outward | shared |
| recovery path | — | a way for the operator to reach and repair a host that does not pass through the overlay network | world-only |
| public address | — | an address on the internet at which a host can be dialled from anywhere, as the fleet's cloud servers have and its laptops and phones behind home or mobile routers do not | world-only |
| address-translating router | — | a router between a laptop or phone and the internet that rewrites its addresses and ports, so that nothing outside can dial the device until the device has sent out first | world-only |
| chat service | — | the fleet's Matrix homeserver, under whose name every person, bot and room it holds is identified | shared |
| phone | — | a person's mobile device that joins the overlay network to reach the fleet's services, administered by its owner rather than from the fleet | world-only |

#### Scenario: The terms with two senses are read

- **WHEN** the table is read for terms that carry two senses in this repository
- **THEN** twenty-four terms carry more than one sense today and are disambiguated by separate rows rather than left to context: `session`, `package`, `policy`, `@`, `mutation`, `activation`, `probe`, `machine`, `host`, `interface`, `repository`, `build service`, `database`, `hostname`, `evaluator`, `person`, `writer`, `account`, `build`, `path`, `credential`, `identifier`, `browser`, and `release`, of which `probe` carries three and every other term two

#### Scenario: A term resolves to two phenomena

- **WHEN** a content term used in a behavioral requirement denotes two distinct phenomena within this repository's vocabulary
- **THEN** this designation table records both senses as separate rows rather than collapsing them into one

#### Scenario: A behavioral requirement uses an unlisted term

- **WHEN** the designation lint finds a content noun in a behavioral requirement that resolves to no row in this table
- **THEN** the noun is either added here as a world or shared phenomenon, or the requirement using it is redirected toward the interface stratum, and neither disposition is applied silently

### Requirement: A33 — The fleet's notification service on cinnabar is reachable over the overlay network and is the single delivery path

It is true of cinnabar, independent of what this fleet builds on magnetite, that it serves the fleet's notification service at `https://ntfy.vanixiets.internal` to members of the fleet's overlay network, and that it is the only path by which a message posted on any host reaches a person.
Any requirement whose discharge depends on this fact SHALL name it explicitly, and SHALL be treated as losing its discharge once this assumption's violation condition below is observed.

**Evidence**: the name resolves through the overlay network's name service and caddy serves it only on cinnabar's overlay address, so overlay membership bounds who reaches it, and the notification service's access entries, not this assumption, bound who may publish to the fleet topics; while cinnabar or its notification service is down no alert or failure notice reaches a person, and the watch service's email reports that outage, not its content (CAM-76; ADR-009 Q5); the forced failure delivered at first activation, the weekly test alert and the watch service's email are its monitors.

#### Scenario: Publishing to the notification service requires a credential, or the service becomes unreachable from magnetite

- **WHEN** once the access entries are in force the notification service refuses a publish to a `fleet-*` topic that carries the `alerter` credential, or refuses an anonymous publish to a topic named after a host, or `ntfy.vanixiets.internal` stops resolving or answering from magnetite, or cinnabar's notification service stops running
- **THEN** this assumption is void, and the `telemetry-store` requirement `The telemetry store's own failures reach a person`, the `host-metrics-collection` requirement `A failed collection or store job notifies a person` and every `fleet-alerting` requirement that ends in a person being told lose their discharge until the credential is accepted again or delivery is restored, except `An outage of the alert path reaches the operator by email from outside the fleet`, which does not rest on this assumption and reports the violation

#### Scenario: A second delivery path appears

- **WHEN** the fleet gains a path other than cinnabar's notification service by which an alert or a failure notice reaches a person; the watch service's email is not such a path, because it reports only that the dead-man's pings stopped and carries no alert or failure notice
- **THEN** this assumption no longer describes the fleet, and the `fleet-alerting-interface` trust-boundary statement on an outage of the notification service is revised with it

### Requirement: A65 — A store-built binary on stibnite reaches the ingress over the overlay network

It is true of stibnite at macOS 26.7.1, independent of what this fleet builds, that a program built in the Nix store can open a TCP connection over the overlay network to the ingress on magnetite, which then refuses the connection at the TLS handshake only for want of a collection certificate.
Any requirement whose discharge depends on this fact SHALL name it explicitly, and SHALL be treated as losing its discharge once this assumption's violation condition below is observed.

**Evidence**: on 2026-11-05 a store-built curl 8.22.0 on stibnite reached the ingress over the previous overlay network and was refused with `tlsv13 alert certificate required`, as `/usr/bin/curl` was, against the note at `pkgs/by-name/ntfy-send/package.nix:5-6` that darwin blocks store binaries from TCP over that network's interface; on the current overlay network the daemon carrying stibnite's packets is itself a store-built program under launchd, and the same comparison of a store-built curl and `/usr/bin/curl` to `magnetite.vanixiets.internal:4318` is repeated at mirror acceptance and recorded before the overlay network carries the collector's exports; the collector's own first export after the flip is its monitor, and a macOS major-version upgrade or an endpoint-security change on stibnite is the event at which it is observed again.

#### Scenario: stibnite blocks store-built programs from the overlay network

- **WHEN** the store-built collector on stibnite cannot connect to the ingress while `/usr/bin/curl` can, or a macOS release or endpoint-security product blocks store-built programs from the overlay network's interface
- **THEN** this assumption is void, and the `host-metrics-collection` requirements `Each agent host contributes its own signals to the telemetry store` and `A failed collection or store job notifies a person`, whose notifier on stibnite is also store-built, and the `devloop-collection-interface` requirement `Each agent host's collector ships its own deploy records` lose the argument that stibnite's signals, notices and deploy records leave the host

## ADDED Requirements

### Requirement: A128 — `.internal` is reserved for private use and is never delegated

It is true of the internet's root zone, independent of what this fleet builds, that the top-level label `internal` is reserved for private-use applications and will not be delegated, so no public name ever ends in `.internal` and a name under `vanixiets.internal` cannot collide with one.
Any requirement whose discharge depends on this fact SHALL name it explicitly, and SHALL be treated as losing its discharge once this assumption's violation condition below is observed.

**Evidence**: ICANN's Board reserved `.INTERNAL` for private-use applications at its special meeting of 29 July 2024, following SSAC's SAC113 (approved resolutions of that meeting, read 2026-11-17).

#### Scenario: The reservation is withdrawn or a public name appears under it

- **WHEN** ICANN withdraws the reservation, or a public resolver answers a name ending in `.internal` from the root zone
- **THEN** this assumption is void, and the `fleet-mesh` requirement `Every overlay member reaches every fleet service by its canonical name` loses the argument that a canonical name cannot be answered from outside the fleet

### Requirement: A129 — A Matrix homeserver's server name cannot change once it holds data

It is true of tuwunel, independent of what this fleet builds, that its server name is the suffix of every user ID, room ID and alias it creates and cannot be changed after it holds data without wiping its database.
Any requirement whose discharge depends on this fact SHALL name it explicitly, and SHALL be treated as losing its discharge once this assumption's violation condition below is observed.

**Evidence**: `tuwunel-example.toml` on tuwunel's main branch, read 2026-11-17: "The server_name is the pretty name of this server. It is used as a suffix for user and room IDs/aliases … THIS CANNOT BE CHANGED AFTER WITHOUT A DATABASE WIPE."

#### Scenario: A rename becomes possible

- **WHEN** tuwunel or the chat service's software gains a supported procedure that renames a server name on an existing database
- **THEN** this assumption is void, and the `fleet-mesh` requirement `The chat service is identified by its canonical name` loses the argument that its name had to be chosen once, before it held data

### Requirement: A130 — Two tincr nodes behind address-translating routers reach each other directly by UDP when both routers keep a source port, and through another node otherwise

It is true of tincr, independent of what this fleet builds, that two nodes behind routers punch a direct UDP path from each other's observed addresses when each router keeps the source port, and otherwise exchange packets through a node both reach.
Any requirement whose discharge depends on this fact SHALL name it explicitly, and SHALL be treated as losing its discharge once this assumption's violation condition below is observed.

**Evidence**: once two nodes share a meta connection to a common node each learns the other's observed address and both send UDP toward it (tincr `docs/PROTOCOL.md:200,232`, `docs/ARCHITECTURE.md:196-213`); until a direct path forms, packets travel over the meta connection or are relayed, shown as "indirectly via" (`docs/OPERATING.md:158`); tincr's TCP simultaneous-open punching fails behind port-translating routers, a "known v1 limitation" (`docs/PUNCH.md:61-63`); all at HEAD `fd92f216` (2026-11-17); tincr's `nix/nixos-test-nat.nix` exercises the NAT case; the observation on pyrite and one Mac behind real address-translating routers is recorded at mirror acceptance.

#### Scenario: Two members behind routers never form a direct path, or lose the relay

- **WHEN** at mirror acceptance or later `tinc info` on pyrite or a Mac reports a member reachable only indirectly while both of their routers keep source ports, or reports it unreachable while a third member reachable by both is online
- **THEN** this assumption is void, and the `fleet-mesh` requirement `Members behind address-translating routers reach each other without a coordinating host` loses its discharge

### Requirement: A131 — tincr's subnet gossip is unsigned, and StrictSubnets accepts a subnet only from the node's own host file

It is true of tincr, independent of what this fleet builds, that any admitted node can advertise any subnet unless the receiving node runs `StrictSubnets = yes`, in which case the receiver accepts a subnet only as its local host file for that node declares it.
Any requirement whose discharge depends on this fact SHALL name it explicitly, and SHALL be treated as losing its discharge once this assumption's violation condition below is observed.

**Evidence**: tincr `docs/OPERATING.md:3-7` and `docs/SECURITY.md` at HEAD `fd92f216`; the mesh VM test's refusal case is its regulator.

#### Scenario: A subnet from an undeclared key is accepted

- **WHEN** the mesh VM test, or a later observation, shows a node with `StrictSubnets = yes` routing an address to a node whose host file does not declare it
- **THEN** this assumption is void, and the `fleet-mesh` requirement `Only members the operator declares are admitted, each only at its own overlay address` loses its discharge

### Requirement: A132 — A C-tinc client joins a tincr mesh only on tincr's default cipher and key exchange

It is true of tincr and C tinc 1.1, independent of what this fleet builds, that a link involving a C-tinc node, tincapp among them, works only on tincr's default cipher and key exchange.
Any requirement whose discharge depends on this fact SHALL name it explicitly, and SHALL be treated as losing its discharge once this assumption's violation condition below is observed.

**Evidence**: a C-tinc node needs `ExperimentalProtocol = yes`, and the post-quantum key exchange (`x25519-mlkem768`) and AES-256-GCM are tincr-only extensions both ends must share, so a link touching a C node stays on ChaCha20-Poly1305 and X25519 (tincr `README.md` "Compatibility" and `docs/COMPAT.md` at HEAD `fd92f216`); tincapp 0.48 (2026-11-13) is a C tinc 1.1 client.

#### Scenario: The phone client gains the extensions

- **WHEN** a published Android client of the overlay network supports tincr's post-quantum key exchange
- **THEN** this assumption no longer constrains the fleet, and the `fleet-mesh-interface` requirement `The mesh runs tincr's default crypto while a phone is a member` is revisited

### Requirement: A133 — tincapp configures its interface only from its network file

It is true of tincapp, independent of what this fleet builds, that it takes the phone's overlay address, routes and name servers only from `network.conf`, and that a `DNSServer` there resolves all the phone's names while connected.
Any requirement whose discharge depends on this fact SHALL name it explicitly, and SHALL be treated as losing its discharge once this assumption's violation condition below is observed.

**Evidence**: tincapp user documentation (`https://tincapp.euxane.eu/doc.html`, v0.47, read 2026-11-17), "Network interface" section.

#### Scenario: tincapp ignores or changes its network file

- **WHEN** a tincapp release stops honouring `DNSServer` or `SearchDomain`, or the phone resolves a canonical name through another resolver while connected
- **THEN** this assumption is void, and the `fleet-mesh` requirement `Every overlay member reaches every fleet service by its canonical name` loses its discharge for phones

### Requirement: A134 — macOS sends names under a domain to the name servers its resolver file for that domain lists

It is true of macOS on the fleet's darwin hosts, independent of what this fleet builds, that a file `/etc/resolver/<domain>` makes the system resolver send every query under `<domain>` to the name servers it lists, in order, and no other query.
Any requirement whose discharge depends on this fact SHALL name it explicitly, and SHALL be treated as losing its discharge once this assumption's violation condition below is observed.

**Evidence**: the fleet relies on the same mechanism today for `/etc/resolver/zt` (`modules/system/zt-dns.nix`); `scutil --dns` on each Mac after activation lists the resolver.

#### Scenario: A canonical name stops resolving on a Mac

- **WHEN** `scutil --dns` on a darwin host lists no resolver for `vanixiets.internal`, or a canonical name fails there while both name services answer it from another member
- **THEN** this assumption is void, and the `fleet-mesh` requirement `Every overlay member reaches every fleet service by its canonical name` loses its discharge for darwin hosts

### Requirement: A135 — macOS answers a name its hosts file lists from that file, before any name server

It is true of macOS on the fleet's darwin hosts, independent of what this fleet builds, that the system resolver answers a name `/etc/hosts` lists from that file before asking any name server, AAAA records included, and reads the file again when it is replaced.
Any requirement whose discharge depends on this fact SHALL name it explicitly, and SHALL be treated as losing its discharge once this assumption's violation condition below is observed.

**Evidence**: Apple's mDNSResponder source, cited in migrate-mesh-to-tincr design D19; task 15.6 observes it on stibnite.

#### Scenario: A listed name does not resolve from the file on a Mac

- **WHEN** on a darwin host whose `/etc/hosts` lists a canonical name, `getaddrinfo` without a fixed address family fails for that name or returns an address the file does not give it, or a replaced file's names are not answered until a restart
- **THEN** this assumption is void, and the `fleet-mesh` requirement `Every overlay member reaches every fleet service by its canonical name` and the `fleet-mesh-interface` requirement `Every NixOS and darwin member answers the zone from its hosts file` lose their discharge for darwin hosts

### Requirement: A142 — macOS asks a domain's name servers only for the address types its resolver file's flags line names

It is true of macOS on the fleet's darwin hosts, independent of what this fleet builds, that a resolver whose `/etc/resolver/<domain>` file has `flags aaaa` as its first `flags` line is asked for AAAA records only, and one with `flags a aaaa` for both.
Any requirement whose discharge depends on this fact SHALL name it explicitly, and SHALL be treated as losing its discharge once this assumption's violation condition below is observed.

**Evidence**: configd source, cited in migrate-mesh-to-tincr design "Open Questions" 1; `scutil --dns` on stibnite (2026-11-18); task 15.6's run after activation.

#### Scenario: A Mac's resolver ignores its flags line

- **WHEN** on a darwin host whose resolver files have been re-read after activation, `scutil --dns` shows for the `vanixiets.internal` or `zt` resolver flags other than its file's `flags` line names, or mDNSResponder sends an A question for a name under `vanixiets.internal`
- **THEN** this assumption is void, and the `fleet-mesh` requirement `Every overlay member reaches every fleet service by its canonical name` and the `fleet-mesh-interface` requirement `Every NixOS and darwin member answers the zone from its hosts file` lose their discharge for darwin hosts
