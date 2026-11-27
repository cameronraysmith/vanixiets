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
| disk | cloud session | the persistent storage of a cloud session's container, which survives into the environment snapshot, as distinct from memory-backed storage that does not | shared |
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
| fleet member | — | an apparatus enrolled by name in the fleet's overlay network and recorded in the host registry: a host, or a phone | shared |
| phone | — | a fleet member a person carries that runs no configuration this fleet builds | world-only |
| host kind | — | whether a fleet member is a NixOS host, a nix-darwin host or a phone, which decides how it is built and reached | shared |
| system | — | the processor architecture and operating system pair a host's configuration is built for, such as x86_64-linux or aarch64-darwin | shared |
| host registry | — | the one record per fleet member, kept in the repository, of its name, system and the other facts about it | shared |
| host fact | — | one property of a fleet member that the host registry records, such as its system, its memory or the account it is deployed as | shared |
| derived fact | — | a host fact computed from other host facts rather than written down | shared |
| fleet pin | — | the literal list of hosts and their kinds kept in the repository apart from the host registry, against which the registry's derived kinds are compared | shared |
| checked host | — | a host whose configuration the fleet's per-host checks evaluate before a change merges | shared |
| enrolled host | — | a host whose name a machine has taken, holding a machine key the fleet's secret store recognises | shared |
| cloud server | — | a rented virtual server at a cloud provider on which a host runs, which exists or not by the operator's decision | world-only |
| cloud machine type | — | a provider's named size of cloud server, which fixes its processors and memory | world-only |
| service role | — | the part a service gives one host or device, such as controller, peer, server or agent, which decides what that member does for the service | shared |
| role membership | — | the set of hosts that play one service role | shared |
| inventory tag | — | a label the operator gives hosts to select them as a group, both for a service role and for deploying several hosts in one command | shared |
| externally joined member | — | a fleet member that joins the overlay network with its own client rather than through the fleet's configuration, today the nix-darwin hosts and the phones | shared |
| state version | — | the release a host's stateful defaults were first set from, fixed when the host is installed and not changed afterwards | shared |
| graph store | — | the program on a host that keeps the fleet's graphs and answers queries and changes to them over the network, OmniGraph on magnetite | shared |
| graph | — | one named body of entities and their relations that the graph store keeps and answers questions about | shared |
| example graph | — | a graph whose content is example data recreated from its published seed, so its loss costs no one's work | world-only |
| seed | — | the published file of example data loaded once into a new example graph | shared |
| graph data | — | everything the graph store keeps for its graphs across restarts: the graphs, their history, their policies and the record of which writer holds them | shared |
| graph data name | — | the name that identifies one body of graph data in either storage location and records the storage format its graphs were created at | shared |
| storage format | — | the version of the on-disk layout the graph store wrote a graph in, which every later release that serves the graph must read | shared |
| entity count | — | the number of entities of a graph as the graph store reports it for its current version | shared |
| stored query | — | a named question declared with a graph, which the graph store answers on request | shared |
| writer | graph store | a running program that holds graph data open for change; the graph store admits one at a time | shared |
| direct writer | — | a writer the operator runs by hand against graph data, outside the graph store's own service | shared |
| writer claim | — | the record a writer leaves in graph data naming itself as its one writer, which any later writer must find absent before it starts | shared |
| stale writer claim | — | a writer claim left behind by a writer that is no longer running | shared |
| crash | — | the end of the graph store's run without its own orderly shutdown, by a kill, a fault or a loss of power | shared |
| boot | — | one period of a host's running between two starts of its operating system | shared |
| serving | — | the state in which the graph store answers for every graph it is configured with and none is blocked | shared |
| blocked graph | — | a graph the graph store is configured with but could not open at its last start | shared |
| storage location | — | where a host's graph store keeps its graph data: that host's disk or a bucket, one at a time | shared |
| bucket | — | a named container of objects at the fleet's object storage provider, Cloudflare R2, reached over the network with a credential | shared |
| disk | host | the storage attached to one host, which survives its reboots and is lost with the host | shared |
| local snapshot | — | a read-only image of graph data as it stood at one instant, kept on the host's disk and lost with it | shared |
| graph backup | — | a copy of graph data made from one local snapshot and held in a bucket away from the host, which survives the loss of the host and its disk | shared |
| runbook | — | the written procedure in the repository's operations docs that the operator follows for a named task | shared |
| recovery notice | — | a low-priority message on the fleet's notification service telling the operator that the graph store cleared a stale writer claim on a named host | shared |

#### Scenario: The terms with two senses are read

- **WHEN** the table is read for terms that carry two senses in this repository
- **THEN** twenty-seven terms carry more than one sense today and are disambiguated by separate rows rather than left to context: `session`, `package`, `policy`, `@`, `mutation`, `activation`, `probe`, `machine`, `host`, `interface`, `repository`, `build service`, `database`, `hostname`, `evaluator`, `person`, `writer`, `account`, `build`, `path`, `credential`, `identifier`, `browser`, `release`, `reader`, `closure`, and `disk`, of which `probe`, `release`, `credential`, `evaluator` and `writer` carry three and every other term two

#### Scenario: A term resolves to two phenomena

- **WHEN** a content term used in a behavioral requirement denotes two distinct phenomena within this repository's vocabulary
- **THEN** this designation table records both senses as separate rows rather than collapsing them into one

#### Scenario: A behavioral requirement uses an unlisted term

- **WHEN** the designation lint finds a content noun in a behavioral requirement that resolves to no row in this table
- **THEN** the noun is either added here as a world or shared phenomenon, or the requirement using it is redirected toward the interface stratum, and neither disposition is applied silently

## ADDED Requirements

### Requirement: A231 — OmniGraph admits one writer process per cluster and serves no read replicas

It is true of OmniGraph 0.16.0, independent of what this fleet builds, that one mutation-capable writer process may hold a cluster at a time, that read replicas and overlapping writers are not a supported topology, and that a cluster may live on a local filesystem, on S3-compatible object storage, or on Azure in preview.
Any requirement relying on this SHALL name it and SHALL lose its discharge once the condition below is observed.

**Evidence**: OmniGraph `docs/user/deployment.md` at v0.16.0, "Writer topology" and introduction.

#### Scenario: the assumption drifts
- **WHEN** a release supports read replicas or several writers
- **THEN** this assumption is void, and `graph-store` requirement `Graph data lives on the disk of the host that serves it` loses its discharge

### Requirement: A232 — A local OmniGraph cluster lock is a file that outlives a crash and that force-unlock removes by id alone

It is true of OmniGraph 0.16.0, independent of what this fleet builds, that a local root's lock file `__cluster/lock.json` records `version`, `lock_id`, `operation`, `created_at` and `pid` and nothing of host or boot, survives a kill, blocks every start and is never taken over, and that `cluster force-unlock <id>` removes it on a matching id without checking its holder.
Any requirement relying on this SHALL name it and SHALL lose its discharge once the condition below is observed.

**Evidence**: Crash probe on stibnite against the packaged 0.16.0 binary (2026-11-26): kill left the lock naming the dead pid, restart refused with `state_lock_held` in about 0.17 s, `force-unlock` with a live server's id removed its lock; leases apply only to S3 roots; the file is created only if absent; source `state_lock.rs:83-90,330`, `store.rs:1303`, `admission.rs:624`; `docs/user/operations/storage-failures.md:120-126`.

#### Scenario: the assumption drifts
- **WHEN** a release takes over a stale local lock itself, adds or removes a field of the record, or checks the holder in `force-unlock`
- **THEN** this assumption is void, and `graph-store` requirements `The graph store recovers from its own crash without a person`, `The graph store refuses to clear a writer claim it cannot prove stale` and `Graph data can be restored to identical answers` lose their discharge

### Requirement: A233 — An OmniGraph commit is whole or absent after a kill

It is true of OmniGraph 0.16.0 on a local root, independent of what this fleet builds, that a server killed during writes leaves each load either wholly committed or absent, and that the next start serves the committed state.
Any requirement relying on this SHALL name it and SHALL lose its discharge once the condition below is observed.

**Evidence**: Crash probe trials 1-5 (2026-11-26): five kills during concurrent loads; counts above baseline were always whole batches; one acknowledged-reply loss counted one extra committed row.

#### Scenario: the assumption drifts
- **WHEN** a restarted server serves a partial load, or fails to open a graph after a kill
- **THEN** this assumption is void, and `graph-store` requirement `The graph store recovers from its own crash without a person` loses its discharge

### Requirement: A234 — A file-by-file copy of a live OmniGraph root may not open, and every copy carries the lock

It is true of OmniGraph 0.16.0, independent of what this fleet builds, that a copy of a local root taken file by file while its server writes may reference files the copy lacks and fail to open, that a copy of a frozen state opens consistently, and that any copy carries the lock of the server it was taken from.
Any requirement relying on this SHALL name it and SHALL lose its discharge once the condition below is observed.

**Evidence**: Crash probe experiment 6 (2026-11-26): `cp -a` under write load opened 2 times of 8; copies with the server stopped by SIGSTOP opened 8 of 8; every copy carried `lock.json`. OmniGraph `docs/user/deployment.md`, "Upgrade and backup": back up the whole root.

#### Scenario: the assumption drifts
- **WHEN** a release documents a consistent online copy of a live root
- **THEN** this assumption is void, and the reason given by `graph-store` requirement `Graph data is copied off its host every night from an instant image` for forbidding file copies is void, and that requirement is reviewed

### Requirement: A235 — A ZFS snapshot is an instant read-only image that lives on its pool

It is true of OpenZFS, independent of what this fleet builds, that a snapshot captures a dataset atomically at one instant, is read-only and reachable under the dataset's `.zfs/snapshot/<name>`, and lives on the same pool and disks as the dataset, so it is lost with them.
Any requirement relying on this SHALL name it and SHALL lose its discharge once the condition below is observed.

**Evidence**: zfs-snapshot(8); magnetite's single disk (`modules/machines/nixos/magnetite/disko.nix`).

#### Scenario: the assumption drifts
- **WHEN** a graph backup made from a snapshot fails to open after restore while the frozen-copy case of A234 holds
- **THEN** this assumption is void, and `graph-store` requirements `Graph data is copied off its host every night from an instant image`, `Graph data can be restored to identical answers` and `Local snapshots stay available` lose their discharge

### Requirement: A236 — An R2 bucket's location is fixed when its name is first created

It is true of Cloudflare R2, independent of what this fleet builds, that a bucket's location hint applies only when the bucket is first created and cannot be changed later, so `sciexp` stays in eastern North America (`location = "enam"`).
Any requirement relying on this SHALL name it and SHALL lose its discharge once the condition below is observed.

**Evidence**: https://developers.cloudflare.com/r2/reference/data-location; `modules/terranix/cloudflare.nix`.

#### Scenario: the assumption drifts
- **WHEN** R2 offers moving an existing bucket
- **THEN** this assumption is void, and the latency reason in `graph-store` requirement `Graph data lives on the disk of the host that serves it` is reviewed

### Requirement: A237 — Hetzner Object Storage does not document conditional writes on unversioned buckets

It is true of Hetzner Object Storage as documented on 2026-11-26, independent of what this fleet builds, that conditional PUT and DELETE on versioned buckets are listed as unsupported, that unversioned buckets are not addressed, that storage is HDD-backed, and that its FAQ advises against many objects under 1 MB, frequent small reads and writes, and latency-sensitive use.
Any requirement relying on this SHALL name it and SHALL lose its discharge once the condition below is observed.

**Evidence**: https://docs.hetzner.com/storage/object-storage/supported-actions/ and …/faq/general/.

#### Scenario: the assumption drifts
- **WHEN** Hetzner documents `If-None-Match` and `If-Match` PUT on unversioned buckets and an SSD tier
- **THEN** this assumption is void, and the rejection of Hetzner Object Storage recorded with `graph-store` requirement `Graph data lives on the disk of the host that serves it` is reviewed

### Requirement: A238 — OmniGraph exposes readiness publicly and per-graph state only to a bearer token, and no metrics

It is true of OmniGraph 0.16.0, independent of what this fleet builds, that it serves no metrics endpoint, that `GET /readyz` needs no token and reports readiness and graph counts by state without graph names, and that `GET /graphs/{id}/snapshot` needs a bearer token and reports a graph's entity counts, manifest version and storage format.
Any requirement relying on this SHALL name it and SHALL lose its discharge once the condition below is observed.

**Evidence**: OmniGraph `crates/omnigraph-server/src/http_operations.rs:196-222`, `handlers.rs:62-226`, `omnigraph-api-types/src/lib.rs:447-468,2396-2440` (read on `main` after v0.16.0); `/readyz` answers 200 also when degraded, so a reader must use the counts; `modules/lib/omnigraph-readiness.nix` parses `/readyz`.

#### Scenario: the assumption drifts
- **WHEN** a release renames a readiness field, adds a metrics endpoint, or moves the snapshot read behind another action
- **THEN** this assumption is void, and `graph-store` requirements `The operator learns when the graph store is not serving` and `The graph store's state is visible on a dashboard` lose their discharge

### Requirement: A239 — OmniGraph's trace exporter trusts only public certificate authorities

It is true of OmniGraph 0.16.0, independent of what this fleet builds, that it exports OpenTelemetry traces only, over OTLP HTTP with `reqwest-rustls-webpki-roots`, so an HTTPS collector signed by a private authority fails verification.
Any requirement relying on this SHALL name it and SHALL lose its discharge once the condition below is observed.

**Evidence**: OmniGraph `crates/omnigraph-server/Cargo.toml:36-40`; `docs/user/operations/observability.md`.

#### Scenario: the assumption drifts
- **WHEN** a release accepts a configured certificate authority
- **THEN** this assumption is void, and the reason this fleet exports no OmniGraph traces is void and is reviewed

### Requirement: A240 — omnigraph cleanup runs only directly against storage

It is true of OmniGraph 0.16.0, independent of what this fleet builds, that `omnigraph cleanup` runs only as a direct writer, needs the cluster's lock and so the server stopped, and is destructive.
Any requirement relying on this SHALL name it and SHALL lose its discharge once the condition below is observed.

**Evidence**: OmniGraph `docs/user/operations/maintenance.md`, `docs/user/operations/recorded-operations.md:60-66`.

#### Scenario: the assumption drifts
- **WHEN** a release runs cleanup through the server
- **THEN** this assumption is void, and the reason this fleet schedules no cleanup is void and is reviewed

### Requirement: A241 — systemd 262 id-maps a DynamicUser state directory and hands a static user's root-owned one to that user

It is true of systemd 262, independent of what this fleet builds, that a `DynamicUser` unit's state directory is moved into `/var/lib/private` behind a symlink and, owned by root or `nobody`, id-mapped, which fails with a mount below it, and that a static-user unit moves it back out and chowns a root-owned one to that user at start.
Any requirement relying on this SHALL name it and SHALL lose its discharge once the condition below is observed.

**Evidence**: systemd.exec(5), `StateDirectory=`; systemd v262 `src/core/exec-invoke.c` `setup_exec_directory` (the private migration, the `nobody` and root-owned id-mapping branch, `path_chown_recursive`) and `src/core/namespace.c`; observed on magnetite 2026-11-26: `/var/lib/omnigraph -> private/omnigraph`; runtime test 2026-11-26: every omnigraph unit failed with `Failed to create an id-mapped mount: Device or resource busy` while a dataset was mounted at `/var/lib/private/omnigraph/clusters`; `vmTests.x86_64-linux.omnigraph-state-directory-transitions` (2026-11-26): the private directory moved back out at the first static-user start and stayed `65534:65534` behind an id-mapped mount, a root-owned dataset at `/var/lib/omnigraph` was chowned to the static user, and a `DynamicUser` start with that dataset mounted failed with status 238/STATE_DIRECTORY.

#### Scenario: the assumption drifts
- **WHEN** a systemd release leaves the state directory of a static-user unit behind the `/var/lib/private` symlink, leaves a root-owned one owned by root, or id-maps it
- **THEN** this assumption is void, and `graph-store` requirements `Graph data lives on the disk of the host that serves it` and `The storage location is chosen per host, and switching back serves what the bucket held` lose their discharge

### Requirement: A242 — omnigraph optimize run directly against a local root leaves its admission lock behind

It is true of OmniGraph 0.16.0, independent of what this fleet builds, that `omnigraph optimize` run directly against a local root exits with its cluster admission lock still in `__cluster/lock.json`, so that every later writer and server start meets `state_lock_held` until `cluster force-unlock` of that id.
Any requirement relying on this SHALL name it and SHALL lose its discharge once the condition below is observed.

**Evidence**: runtime test of 2026-11-26 against the packaged 0.16.0 binary: `omnigraph optimize --graph <first>` logged `cluster admission retained … use exact-ID cluster force-unlock; command completion alone does not release this lock`, and the next `omnigraph` command on the root failed with `[state_lock_held]`.

#### Scenario: the assumption drifts
- **WHEN** a release releases the admission lock when a direct `optimize` completes
- **THEN** this assumption is void, and the reason `graph-store-interface` requirement `Optimize is not enabled on a local root` forbids the optimize timer is void and is reviewed
