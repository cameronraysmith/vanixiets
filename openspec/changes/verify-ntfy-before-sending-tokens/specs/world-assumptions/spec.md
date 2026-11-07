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
| service authority | — | the private key that signs the certificates of the fleet's mesh-only names, `ntfy.zt` among them, together with the root certificate that identifies it, both kept as cinnabar's encrypted clan vars from which cinnabar's caddy loads them | shared |
| verified connection | — | a connection to a mesh-only name on which the connecting host has checked that the server's certificate chains to a root the repository keeps, so that only a holder of the service authority's key can answer it | shared |

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

### Requirement: A78 — cinnabar's caddy signs ntfy.zt's certificate under the root kept as cinnabar's caddy-root-ca vars

It is true of cinnabar, independent of the clients, that caddy serves `ntfy.zt` under the root it was configured with or holds in storage, and that this root is the certificate at `vars/per-machine/cinnabar/caddy-root-ca/root.crt/value`, valid to 2035-12-06T14:29:17Z.
Any requirement whose discharge depends on this fact SHALL name it explicitly, and SHALL be treated as losing its discharge once this assumption's violation condition below is observed.

**Evidence**: on 2026-11-06 the sha256 fingerprint of cinnabar's stored root, `7E:78:F6:7C:83:BD:DC:81:51:FF:EB:8F:82:1A:68:5D:02:89:9F:93:27:33:7F:9B:F2:41:9B:F9:3B:AA:2E:82`, equalled the repository's copy at `modules/machines/nixos/cinnabar/pki/caddy-root-ca.crt`, and the stored file, `/var/lib/caddy/.local/share/caddy/pki/authorities/local/root.crt`, named `CN=Caddy Local Authority - 2026 ECC Root`, was written 2026-01-27T14:29:17Z; the same day the store curl 8.22.0 on stibnite fetched `https://ntfy.zt/v1/health` with `--cacert` on that copy, answering HTTP 200 with verification result 0 (`logs/s5-evidence/7.3-ntfy-curl-proof-20261106T220636Z.log`); the import step records the var's fingerprint equal to it, cinnabar's build-time check compares the var with the recorded fingerprint, and the weekly `caddy-root-check` and every verified post are its monitors.

#### Scenario: caddy serves under another root

- **WHEN** the chain caddy serves for `ntfy.zt` does not verify against the var's root, or a client with `--cacert` on the var is refused by `ntfy.zt` with curl's exit 60
- **THEN** this assumption is void, and the `fleet-alerting` requirement `A host posts to the notification service only over a verified connection` holds only by every post being refused, so every `fleet-alerting` requirement that ends in a person being told loses its discharge, except `An outage of the alert path reaches the operator by email from outside the fleet`, which reports the violation

### Requirement: A79 — caddy loads a configured root from its files, never mints or renews it, and derives intermediates from it

It is true of caddy 2.11.7 that it loads a configured `pki` root from its files, refusing a mismatched key, never mints or renews it, issues intermediates under it while loading a stored one unchecked, and mints a new root when none is configured or stored.
Any requirement whose discharge depends on this fact SHALL name it explicitly, and SHALL be treated as losing its discharge once this assumption's violation condition below is observed.

**Evidence**: `caddyserver/caddy@v2.11.7:caddyconfig/httpcaddyfile/pkiapp.go:32-55`, `:126-153` parse `pki { ca local { root { cert key } } }`; `modules/caddypki/ca.go:150-158` loads a configured root with `KeyPair.Load`, which checks the key against the first certificate (`crypto.go:91-118`); `maintain.go:68-76` skips root maintenance for a configured root; `ca.go:175`, `:345-375` and `maintain.go:78-100` with `ca.go:277-284` issue, load and renew intermediates from the configured files; `ca.go:285-293` mints a root only when none is configured or stored, and `:170-173` stops the authority once the root has less than the 7-day intermediate lifetime left, from 2035-11-29T14:29:17Z; `vmTests.x86_64-linux.caddy-root-from-vars` exercises the configured and the minting cases; a caddy version change on cinnabar is the event at which this is read again.

#### Scenario: caddy's root handling changes

- **WHEN** a caddy release on cinnabar ignores, renews or replaces a configured root, stops deriving intermediates from it, changes the `pki` syntax, or keeps issuing past the root's expiry
- **THEN** this assumption is void, and the `fleet-alerting` requirements `A reinstall of cinnabar keeps the service authority`, `The service authority's expiry reaches a person 180 days ahead` and `Replacing the service authority loses no post` lose the argument that the root changes only when the operator replaces the vars

### Requirement: A80 — curl given a CA file trusts only that file's certificates, any of them, and -k disables verification

It is true of curl 8.22.0 on Linux and darwin that `--cacert <file>` makes it accept only a server whose chain ends at a certificate in that file, any of several, ignoring the system bundle and the keychain and exiting 60 otherwise, and that `-k` disables this.
Any requirement whose discharge depends on this fact SHALL name it explicitly, and SHALL be treated as losing its discharge once this assumption's violation condition below is observed.

**Evidence**: on 2026-11-06 on stibnite, the store curl as `_otelcol` answered `ntfy.zt` with verification result 0 under the repository's root and exited 60 both with no CA option and with `otel-ca`'s certificate as the CA, although `modules/darwin/zt-services-trust.nix` had installed the root into the System keychain (`logs/s5-evidence/7.3-ntfy-curl-proof-20261106T220636Z.log`); `curl/curl@curl-8_22_0:docs/cmdline-opts/cacert.md` and `insecure.md` state the option semantics; `ntfy-send`'s `tls-verification` test exercises a one-root and a two-root file on every build, and a curl version change in the root pin is the event at which its cases are read again.

#### Scenario: curl's verification changes

- **WHEN** a curl release in the root pin accepts a server outside the given file, consults another trust store as well, rejects a chain to the second certificate of a two-certificate file, or exits with a code other than 60 for an untrusted chain
- **THEN** this assumption is void, and the `fleet-alerting-interface` requirement `ntfy-send verifies ntfy.zt against caddy's root and fails closed` and the `fleet-alerting` requirements `A host posts to the notification service only over a verified connection` and `Replacing the service authority loses no post` lose the argument that the file alone decides which server a host trusts

### Requirement: A81 — caddy's root key is readable only by cinnabar's root and caddy accounts and by the sops recipients of its var

It is true of the fleet that caddy's root key exists only as cinnabar's deployed var and caddy's stored copy, both readable only by `caddy` and root, and as the repository's sops-encrypted var, whose recipients are `machines/cinnabar` and the importing admin's age key.
Any requirement whose discharge depends on this fact SHALL name it explicitly, and SHALL be treated as losing its discharge once this assumption's violation condition below is observed.

**Evidence**: the deployed var is owned by `caddy` with mode `0400` (design D10); on 2026-11-06 `stat` on cinnabar showed caddy's stored `root.key` written 2026-01-27T14:29:17Z, owner `caddy`, mode `600`, on `zroot/root/nixos`; `clan vars set` encrypts a secret to the machine, the machine's default groups and the running admin's user entry, and to no other sops user (`clan-core@dbae2101:pkgs/clan-cli/clan_cli/secrets/secrets.py:170-235`, `clan_lib/vars/secret_modules/sops.py:183-214`); `sops/users/` holds `cameron`, `christophersmith`, `crs58`, `janettesmith` and `raquel`, of which `cameron` and `crs58` hold the same age key, the importing admin's, so the var's reader entries are `machines/cinnabar` and one of `users/cameron` or `users/crs58`, and `christophersmith`, `janettesmith` and `raquel` are not recipients unless someone adds them; cinnabar's per-machine secrets are encrypted to `machines/cinnabar` and `users/cameron` (`vars/per-machine/cinnabar/otel-cert/key.pem/`); the import step records the new var's reader entries and stops on any other; a change of the sops users, a reinstall of cinnabar, or a copy of the key made during a rotation is the event at which this is read again.

#### Scenario: The root key reaches someone else

- **WHEN** the key is decrypted or copied by anyone outside cinnabar's root and `caddy` accounts and the var's recipients, a recipient's private key is lost, or the var gains a recipient
- **THEN** this assumption is void, and the `fleet-alerting` requirement `A host posts to the notification service only over a verified connection` no longer implies that only cinnabar can answer a verified connection, until the root is rotated

### Requirement: A82 — A store-built curl on stibnite reaches ntfy.zt over ZeroTier from a launchd job's account

It is true of stibnite at macOS 26.7.1, independent of what this fleet builds, that a curl built in the Nix store, run as `_otelcol`, the account of stibnite's envelope job, opens a TLS connection over the ZeroTier network to `ntfy.zt` and completes it with verification.
Any requirement whose discharge depends on this fact SHALL name it explicitly, and SHALL be treated as losing its discharge once this assumption's violation condition below is observed.

**Evidence**: on 2026-11-06 the store curl 8.22.0 (`darwinConfigurations.stibnite.pkgs.curl`) run as `_otelcol` fetched `https://ntfy.zt/v1/health` with HTTP 200 and verification result 0 (`logs/s5-evidence/7.3-ntfy-curl-proof-20261106T220636Z.log`), as the store-built collector reached the ingress under A65; stibnite's posts after its activation in this change's window are its monitor, and a macOS major-version upgrade or an endpoint-security change on stibnite is the event at which it is observed again.

#### Scenario: stibnite blocks the store curl from the overlay network

- **WHEN** a post from stibnite's `ntfy-send` fails to connect while `/usr/bin/curl` connects, or a macOS release or endpoint-security product blocks store-built programs from ZeroTier
- **THEN** this assumption is void, and the `host-metrics-collection` requirement `A failed collection or store job notifies a person` loses the argument that stibnite's envelope notices leave the host, until `ntfy-send` on darwin is given a curl that connects

### Requirement: A83 — clan neither regenerates an imported generator nor stores a value other than what clan vars set received

It is true of clan-core `dbae2101` that `clan vars set` stores exactly the bytes it reads from stdin, sops-encrypting a secret to its recipients, and that a generator without `validation` whose files all exist counts as current, so neither `clan vars generate` nor `clan machines update` runs its script.
Any requirement whose discharge depends on this fact SHALL name it explicitly, and SHALL be treated as losing its discharge once this assumption's violation condition below is observed.

**Evidence**: `clan-core@dbae2101:pkgs/clan-cli/clan_lib/vars/set.py:38-72` honours `CLAN_NO_COMMIT` through its commit helper and reads stdin with `sys.stdin.buffer.read()` and calls the file's store; `_types.py:400-409` treats a missing hash on both sides as valid; `generator.py:443-459` counts a generator present when every file exists and its hash is valid; the import step's fingerprint and public-key comparisons, and cinnabar's build-time check of the var's fingerprint, are its monitors; a clan-core bump is the event at which it is read again.

#### Scenario: clan regenerates or alters the imported root

- **WHEN** a clan command runs the `caddy-root-ca` script although both files exist, or the var's fingerprint after a clan command differs from the recorded one
- **THEN** this assumption is void, and the `fleet-alerting` requirement `A reinstall of cinnabar keeps the service authority` loses its discharge until the vars are imported again; the generator's script only fails, so a regeneration stops the deploy instead of minting a root
