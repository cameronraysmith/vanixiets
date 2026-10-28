# world-assumptions Specification

## Purpose
TBD - created by archiving change extract-world-assumptions. Update Purpose after archive.

## Requirements

### Requirement: A1 — No native permission system

It is true of Pi's execution environment, independent of what this fleet builds, that Pi ships no built-in mechanism to gate, approve, or defer a tool call pending human interactive confirmation.
Any requirement whose discharge depends on this fact SHALL name it explicitly rather than restating it as unattributed justification prose, and SHALL be treated as losing its discharge once this assumption's violation condition below is observed.

#### Scenario: Pi gains a native permission system

- **WHEN** a Pi release ships a built-in mechanism to gate, approve, or defer a tool call pending human interactive confirmation
- **THEN** this assumption is void, and the `pi-agent-environment` requirements `Permission-gate reuse`, `Non-Bash edit and write policy`, and `Fail-open policy` lose the discharge argument that currently rests on enforcing policy entirely through first-party and third-party extensions rather than a native mechanism

### Requirement: A2 — Unanswerable dialog stalls a session with UI but no human present

It is true of a Pi session that has a UI channel, independent of what this fleet builds, that a dialog left unanswered because no human is present to answer it stalls that session indefinitely, unless some other responder on the event bus answers in the human's place.
A session with no UI channel at all is not covered by this claim: no dialog is ever shown to a session without a UI, so the stall this assumption describes cannot arise there.
The reachable condition is therefore the inverse of headlessness — a UI channel present, a human absent — not the mere absence of a UI.
Any requirement whose discharge depends on this fact SHALL name it explicitly, and SHALL be treated as losing its discharge once this assumption's violation condition below is observed.

#### Scenario: An unanswerable dialog stops stalling a session with UI but no human present

- **WHEN** Pi or its host harness gains a way to hold an unresolved interactive prompt open on a session that has a UI channel but no human present, without blocking that session's progress, such as a default-on-timeout or a standing event-bus responder that answers in the human's place
- **THEN** this assumption is void, and the `pi-agent-environment` requirements `Additional shell policy`'s prompted decision class, `Non-Bash edit and write policy`'s notify-and-allow class, and `Fail-open policy`'s prohibition on requiring an interactive answer lose the discharge argument that currently rests on prompting being unsafe for a session with UI but no human present

### Requirement: A3 — Policy failure carries no safety evidence

It is true of the first-party and third-party policy machinery, independent of what this fleet builds, that a parser error, a core or adapter exception, an ambiguous repository state, or a missing or throwing capability establishes nothing about whether the mutation it was evaluating is actually unsafe.
Any requirement whose discharge depends on this fact SHALL name it explicitly, and SHALL be treated as losing its discharge, for the specific failure mode found to carry evidence, once this assumption's violation condition below is observed.

#### Scenario: A failure mode is shown to correlate with an unsafe mutation

- **WHEN** a specific parser, decision, adapter, repository, or capability failure mode is shown, by incident or audit, to correlate with an actually unsafe mutation rather than with an indeterminate but harmless state
- **THEN** this assumption is void for that specific failure mode, and the `pi-agent-environment` requirements `Non-Bash edit and write policy`, `Git default-branch boundary`, `Jj diamond boundary`, and `Fail-open policy` lose the discharge argument for treating that failure as announce-and-allow rather than refuse

### Requirement: A4 — Refusing on ambiguity has a real cost and prevents nothing

It is true of this fleet's operating history, independent of what is built, that refusing an edit or write on an ambiguous or indeterminate policy state has cost every edit and write in the affected repository while having prevented no unsafe mutation.
Any requirement whose discharge depends on this fact SHALL name it explicitly, and SHALL be treated as losing its discharge once this assumption's violation condition below is observed.

#### Scenario: A refusal on ambiguity is found to have prevented an unsafe mutation

- **WHEN** an audit of previously refused ambiguous cases finds at least one instance where the refusal actually prevented an unsafe mutation, rather than merely costing productivity
- **THEN** this assumption is void, and the `pi-agent-environment` requirements `Non-Bash edit and write policy` and `Fail-open policy` lose the discharge argument for preferring announce-and-allow over refuse on ambiguity

### Requirement: A5 — A tracked target is recoverable from repository history

It is true of a version-controlled repository, independent of what this fleet builds, that a target tracked by that repository's version control can be recovered from its history after an unwanted mutation.
This assumption does not extend to a target that is inside a repository's working tree but is both untracked and matched by an ignore rule, because no commit, stash, or reflog entry of that repository covers such a target; the sharp edge is recorded here rather than left implicit.
Any requirement whose discharge depends on this fact SHALL name it explicitly, and SHALL be treated as losing its discharge, for the targets it does not cover, whether or not this assumption's general form is ever violated.

#### Scenario: A mutation targets an untracked, gitignored file inside a repository

- **WHEN** a proposed mutation's target is inside a repository's working tree, is not tracked by that repository's version control, and is matched by an ignore rule, so no commit, stash, or reflog entry of that repository covers it
- **THEN** this assumption does not hold for that target, and the `pi-agent-environment` requirements `Non-Bash edit and write policy`, `Git default-branch boundary`, and `Jj diamond boundary` announce-and-allow a mutation their own governing text describes as refusable, because the target is in fact unrecoverable by the repository's history despite being inside the repository

### Requirement: A6 — Atomic inherits Pi's configuration root unconditionally

It is true of the atomic harness as currently released, independent of what this fleet builds, that atomic inherits Pi's configuration root and loads every extension in Pi's extension directory unconditionally, with no per-extension opt-out atomic itself exposes.
Any requirement whose discharge depends on this fact SHALL name it explicitly, and SHALL be treated as losing its discharge once this assumption's violation condition below is observed.

#### Scenario: Atomic gains conditional extension-directory loading

- **WHEN** a future atomic release adds its own configuration root, or makes loading Pi's extension directory conditional or opt-in rather than unconditional
- **THEN** this assumption is void, and the `pi-agent-environment` requirement `Non-Bash edit and write policy`'s obligation to declare Pi-only extensions as force-excludes to atomic loses the discharge argument for why that declaration is necessary at all

### Requirement: A7 — Pi's enumerated path forms are exhaustive

It is true of Pi's own path resolution, independent of what this fleet builds, that the forms this fleet's policy enumerates — the `@` prefix, a leading `~`, a `file://` URL, and Unicode space variants — are the complete set of forms Pi itself accepts when opening a tool-call target.
This is a measurement-fidelity assumption in Parnas' sense: the normalized path the policy computes is an input register standing in for the path Pi actually opens, and the two coincide only while this assumption holds.
Any requirement whose discharge depends on this fact SHALL name it explicitly, and SHALL be treated as losing its discharge once this assumption's violation condition below is observed.

#### Scenario: Pi accepts a path form outside the enumerated set

- **WHEN** Pi's own path resolution accepts a path form not among the `@` prefix, a leading `~`, a `file://` URL, or a Unicode space variant
- **THEN** the normalized register this assumption backs no longer matches the monitored quantity it stands in for, and the `pi-agent-environment` requirements `Non-Bash edit and write policy`, `Git default-branch boundary`, and `Jj diamond boundary` lose the discharge argument that the path the policy judges is the path the tool opens

### Requirement: A8 — Jj's outside-repository diagnostic is stable

It is true of the pinned jj release, independent of what this fleet builds, that jj's outside-repository diagnostic has a stable textual form followed by trailing `Hint:` advisory lines, and that this shape is what this fleet's Git-branch fallback and repository-health probes parse.
Any requirement whose discharge depends on this fact SHALL name it explicitly, and SHALL be treated as losing its discharge once this assumption's violation condition below is observed.

#### Scenario: Jj changes its outside-repository diagnostic shape

- **WHEN** a jj release changes the wording, exit code, or trailing `Hint:` line shape of its outside-repository diagnostic
- **THEN** this assumption is void, and the `pi-agent-environment` requirements `Git default-branch boundary` and `Jj diamond boundary` lose the discharge argument for falling through to the Git branch check or classifying repository health from that probe's output

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

### Requirement: A13 — Resuming this laptop from a suspended state is unreliable, and recovering a failed resume requires a person at the machine

It is true of this fleet's bare-metal Apple laptop, independent of what this fleet configures on it, that a host which enters a suspended state sometimes never runs again — measured at 7 failures against 30 successes across 14 boots, with no distinguishing record left behind and no identified mechanism — and that the duration of the suspended interval does not predict which outcome occurs.
It is further true of this host that its only remaining wake source is a physical control on the machine itself, so a host that fails to resume, and a host that resumes without anyone present to press that control, are indistinguishable from anywhere but the machine.
An automatic suspend is therefore a cost taken on behalf of a person who is by definition absent, and a deliberate suspend is a cost taken by someone standing there.
Any requirement whose discharge depends on this fact SHALL name it explicitly, and SHALL be treated as losing its discharge once this assumption's violation condition below is observed.

#### Scenario: Resume becomes reliable, or a wake source reachable from elsewhere appears

- **WHEN** this host is observed to resume from a suspended state across a run of attempts long enough to distinguish it from the recorded failure rate, or a wake source becomes available that a person not at the machine can trigger
- **THEN** this assumption is void, and the `graphical-desktop-session` requirement `The laptop does not suspend itself when nobody is using it` loses the reason it exists, becoming a preference about power use rather than an avoidance of a known harm

### Requirement: A29 — Cloudflare R2 behaves as S3-compatible object storage for the telemetry store's client

It is true of Cloudflare R2, independent of what this fleet builds, that it serves the S3 operations the telemetry store's client issues, addressed path-style with region `auto` and no instance metadata, under an Object Read & Write token minted for the `sciexp` bucket.
Any requirement whose discharge depends on this fact SHALL name it explicitly, and SHALL be treated as losing its discharge once this assumption's violation condition below is observed.

**Evidence**: the bucket's durability and the token's scope are set and provided by Cloudflare, and this machine does not assert them; no activation exercises this assumption before magnetite's first with the telemetry store, so that activation's confirmation and the hourly readiness probe are its monitors.

#### Scenario: R2 refuses or mishandles an operation the telemetry store's client issues

- **WHEN** R2 rejects a path-style request, a request naming region `auto`, or any object operation the telemetry store issues under its prefix, or the telemetry store fails to report ready after start because its object storage is unreachable
- **THEN** this assumption is void, and the `telemetry-store` requirement `A database keeps its series for its retention and no longer` and the `telemetry-store-interface` requirement `Object data lives under one prefix of one bucket` lose the discharge argument that rests on object data being kept in R2

### Requirement: A30 — nixpkgs channels lag the telemetry store's vendor releases and omit its dashboard

It is true of nixpkgs, independent of what this fleet builds, that its GreptimeDB package reaches the channels this fleet pins some time after the vendor publishes a release, and omits the web dashboard the vendor's release build embeds.
Any requirement whose discharge depends on this fact SHALL name it explicitly, and SHALL be treated as losing its discharge once this assumption's violation condition below is observed.

**Evidence**: on 2026-10-16 `nixpkgs-unstable` and `nixos-unstable` both carried GreptimeDB 1.1.4, while the vendor had published 1.2.1 on 2026-09-16 and nixpkgs master alone carried it; the nixpkgs source build depends on nightly-only Rust features enabled through `RUSTC_BOOTSTRAP`, one reason the channel package trails the vendor's release; and the vendor's release tarball is built with the `servers/dashboard` feature, serving the dashboard at `/dashboard/`, while the nixpkgs build omits that feature.

#### Scenario: The pinned channel carries the deployed release with the dashboard

- **WHEN** the nixpkgs revision this fleet pins carries a stable GreptimeDB release at or above the version the fleet deploys, built with the embedded dashboard
- **THEN** this assumption is void for that release, and the `telemetry-store` requirement `The telemetry store runs a stable vendor release that serves its dashboard` loses the discharge argument for running the vendor's own build instead of the channel's package; the evaluation-time release check then accepts either package once the channel's package declares the dashboard, and choosing between them is the operator's decision

### Requirement: A31 — magnetite's memory is finite and shared with the build service's evaluation work

It is true of magnetite, independent of what this fleet builds, that its memory is finite, that the build service's evaluation draws more of it than any other work there, and that pages moved into its compressed swap occupy memory no per-service ceiling accounts for.
Any requirement whose discharge depends on this fact SHALL name it explicitly, and SHALL be treated as losing its discharge once this assumption's violation condition below is observed.

**Evidence**: magnetite is a 16-vCPU cloud guest with 30.6 GiB of usable memory, and overlapping evaluations exhausted that memory and brought the host down on 2026-09-27 and 2026-10-01; a ceiling chosen for the telemetry store or the collector is therefore a share of a pool the evaluation already draws on, and sizing either in isolation establishes nothing about the host.

#### Scenario: The evaluation work stops sharing magnetite's memory, or magnetite's memory changes

- **WHEN** the build service's evaluation work moves to another host, or magnetite's memory is resized
- **THEN** this assumption no longer describes magnetite, and the `telemetry-store` requirement `The telemetry store stays inside a memory envelope that leaves build capacity to the build service` loses the sizing argument its ceilings and kill order rest on, until they are chosen again against the host as it then is

### Requirement: A32 — magnetite has no /dev/kvm, and the kernel's kill order does not depend on the host it runs on

It is true of magnetite, independent of what this fleet builds, that it exposes no `/dev/kvm` while pyrite does, and of the Linux kernel that it picks which process to kill for memory from declared kill preferences the same way in a virtual machine on pyrite as on magnetite.
Any requirement whose discharge depends on this fact SHALL name it explicitly, and SHALL be treated as losing its discharge once this assumption's violation condition below is observed.

**Evidence**: magnetite is a cloud guest and pyrite is bare-metal; magnetite can run tests in containers that share its kernel but cannot boot a virtual machine of its own, and a container cannot observe the kill order, because magnetite's own kernel, not one the test controls, kills a container's processes.

#### Scenario: magnetite gains /dev/kvm, or the kernel's kill order comes to depend on the host

- **WHEN** magnetite comes to expose `/dev/kvm`, or a kernel change makes the choice of victim under memory exhaustion depend on something other than the declared kill preferences that differs between a virtual machine on pyrite and magnetite
- **THEN** this assumption is void, and the `telemetry-store` requirement `The telemetry store stays inside a memory envelope that leaves build capacity to the build service` loses the discharge argument that a kill-order test run on pyrite establishes the order on magnetite

### Requirement: A33 — The fleet's notification service on cinnabar is reachable over ZeroTier and is the single delivery path

It is true of cinnabar, independent of what this fleet builds on magnetite, that it serves the fleet's notification service at `https://ntfy.zt` to members of the fleet's ZeroTier network, and that it is the only path by which a message posted on any host reaches a person.
Any requirement whose discharge depends on this fact SHALL name it explicitly, and SHALL be treated as losing its discharge once this assumption's violation condition below is observed.

**Evidence**: the name resolves through cinnabar's own resolver and caddy serves it only on the mesh addresses, so ZeroTier membership bounds who reaches it, and the notification service's access entries, not this assumption, bound who may publish to the fleet topics; while cinnabar or its notification service is down no message reaches a person, and nothing in the fleet reports that (ADR-009 Q5); the forced failure delivered at first activation and the weekly test alert are its monitors.

#### Scenario: Publishing to the notification service requires a credential, or the service becomes unreachable from magnetite

- **WHEN** once the access entries are in force the notification service refuses a publish to a `fleet-*` topic that carries the `alerter` credential, or refuses an anonymous publish to a topic named after a host, or `ntfy.zt` stops resolving or answering from magnetite, or cinnabar's notification service stops running
- **THEN** this assumption is void, and the `telemetry-store` requirement `The telemetry store's own failures reach a person`, the `host-metrics-collection` requirement `A failed collection or store job notifies a person` and every `fleet-alerting` requirement that ends in a person being told lose their discharge until the credential is accepted again or delivery is restored

#### Scenario: A second delivery path appears

- **WHEN** the fleet gains a path other than cinnabar's notification service by which an alert or a failure notice reaches a person, such as an external watch on cinnabar
- **THEN** this assumption no longer describes the fleet, and the `fleet-alerting-interface` trust-boundary statement that an outage of the notification service goes unreported is revised with it

### Requirement: A37 — ntfy provisions users, access entries and tokens from its declaration, and refuses to start on an undeclared user

It is true of ntfy 2.28.0, independent of what this fleet builds, that it provisions the users, access entries and tokens its configuration declares, deletes at its next start any entry no longer declared, and refuses to start when an access or token entry names an undeclared user or a token is malformed.
Any requirement whose discharge depends on this fact SHALL name it explicitly, and SHALL be treated as losing its discharge once this assumption's violation condition below is observed.

**Evidence**: declarative provisioning arrived in 2.14.0 through `auth-users`, `auth-access` and `auth-tokens`, or `NTFY_AUTH_USERS`, `NTFY_AUTH_ACCESS` and `NTFY_AUTH_TOKENS` (`binwiederhier/ntfy` `cmd/serve.go:61-63`); an entry naming a user missing from `auth-users` stops the server (`cmd/serve.go:714`, `:753`); a token must match `^tk_[-_A-Za-z0-9]{29}$` (`user/util.go:24`); removed entries are deleted at the next start (`docs/config.md:688-689`); the deployed binary's `ntfy serve --help` on cinnabar listed the three flags on 2026-10-18; the provisioning check before each deploy and the dead-man's anonymous-publish probe every 5 minutes are its monitors.

#### Scenario: ntfy stops honouring or enforcing its provisioning declaration

- **WHEN** a ntfy release on cinnabar starts with an access or token entry naming an undeclared user, keeps an entry the declaration no longer names, or ignores a declared user, access entry or token
- **THEN** this assumption is void, and the `fleet-alerting` requirement `Only the alerting credential publishes alerts and heartbeats`, the `fleet-alerting-interface` requirement `ntfy grants the fleet topics to alerter through declarative provisioning`, the `telemetry-store` requirement `The telemetry store's own failures reach a person` and the `host-metrics-collection` requirement `A failed collection or store job notifies a person` lose the discharge argument that the declaration is the whole of ntfy's access state and that the provisioning check guards its start

### Requirement: A38 — One ntfy access entry decides a request, a named user's before the anonymous one's

It is true of ntfy 2.28.0, independent of what this fleet builds, that one access entry decides each request: among the entries whose topic pattern matches, a named user's entry outranks the anonymous `*` entry and a longer pattern outranks a shorter one, and with no matching entry the default access applies.
Any requirement whose discharge depends on this fact SHALL name it explicitly, and SHALL be treated as losing its discharge once this assumption's violation condition below is observed.

**Evidence**: the access query orders matching rows `u.user DESC, LENGTH(topic) DESC, write DESC` and takes the first (`binwiederhier/ntfy` `user/manager.go:702-735`, `user/manager_sqlite.go:90-96`), so `alerter:fleet-*:rw` outranks `*:fleet-*:ro`, an anonymous write under `*:fleet-*:ro` is refused with 403, and a topic no entry matches keeps `auth-default-access`; the dead-man's anonymous-publish probe every 5 minutes and the acceptance publish to a host-named topic are its monitors.

#### Scenario: ntfy changes how it chooses among access entries

- **WHEN** a ntfy release on cinnabar lets the anonymous entry outrank a named user's, combines several matching entries, or applies something other than the default access to a topic no entry matches
- **THEN** this assumption is void, and the `fleet-alerting` requirement `Only the alerting credential publishes alerts and heartbeats` and the `fleet-alerting-interface` requirement `ntfy grants the fleet topics to alerter through declarative provisioning` lose the discharge argument that `alerter` alone writes the fleet topics while every other topic stays open

### Requirement: A39 — ntfy refuses a request whose token it does not know, even where anonymous access is allowed

It is true of ntfy 2.28.0, independent of what this fleet builds, that a request whose `Authorization` header fails authentication is refused with 401, even on a topic an anonymous client may write.
Any requirement whose discharge depends on this fact SHALL name it explicitly, and SHALL be treated as losing its discharge once this assumption's violation condition below is observed.

**Evidence**: the pinned source refuses a failed `Authorization` header before consulting access (`binwiederhier/ntfy@v2.28.0:server/server_auth.go:45-50`), so a sender may carry the token only once cinnabar has provisioned it, which is why the cutover provisions the user and token before any sender uses them; nothing monitors it at runtime, and a ntfy upgrade on cinnabar is the event at which it is read again.

#### Scenario: ntfy starts treating an unknown token as anonymous

- **WHEN** a ntfy release on cinnabar accepts a request carrying an unknown token where anonymous access is allowed, or refuses an unknown token with something other than 401
- **THEN** this assumption no longer describes ntfy, and the `fleet-alerting-interface` requirement `The alerter token travels only as a file` loses the reason its senders must not carry the token before cinnabar provisions it; the requirement still holds, but its ordering constraint becomes unnecessary

### Requirement: A40 — ntfy rate-limits a client by its address masked to a prefix, taken from a trusted proxy's forwarding header

It is true of ntfy 2.28.0, independent of what this fleet builds, that it rate-limits a client without a tier by its address, masked for IPv6 to `visitor-prefix-bits-ipv6` bits, 64 by default, and takes that address from `X-Forwarded-For` only with `behind-proxy` set and the peer in `proxy-trusted-hosts`.
Any requirement whose discharge depends on this fact SHALL name it explicitly, and SHALL be treated as losing its discharge once this assumption's violation condition below is observed.

**Evidence**: a visitor is keyed by user only when the user has a tier and otherwise by masked address (`binwiederhier/ntfy` `server/visitor.go:592-602`); without `behind-proxy` the address is the TCP peer (`server/util.go:84-92`); the default budget is a burst of 60 requests refilled at one per 5 s (`docs/config.md:1905-1910`); every ZeroTier member lies in `fddb:4344:343b:14b9::/64`, so at the default prefix the whole mesh is one visitor; the deployed binary's `ntfy serve --help` lists all three settings, the prefix defaulting to 64; the two-client visitor observation at the cutover's first cinnabar deploy is its monitor.

#### Scenario: ntfy changes how it identifies a rate-limited client

- **WHEN** a ntfy release on cinnabar keys a client without a tier by something other than its masked address, ignores `visitor-prefix-bits-ipv6`, or reads `X-Forwarded-For` from an untrusted peer or not at all
- **THEN** this assumption is void, and the `fleet-alerting` requirement `Each known failure class on a host reaches a person as an alert` and the `fleet-alerting-interface` requirement `ntfy counts each mesh client as its own visitor` lose the discharge argument that another client's burst cannot spend the evaluator's publishing budget

### Requirement: A41 — caddy reaches ntfy from ::1 and forwards the mesh client's address

It is true of caddy as cinnabar runs it, independent of what this fleet builds, that its reverse proxy for `ntfy.zt` connects to ntfy at `[::1]:2586` from `::1` and sets `X-Forwarded-For` to the address of the mesh client that connected to it.
Any requirement whose discharge depends on this fact SHALL name it explicitly, and SHALL be treated as losing its discharge once this assumption's violation condition below is observed.

**Evidence**: cinnabar's caddy serves `ntfy.zt` with `reverse_proxy [::1]:2586` (`modules/machines/nixos/cinnabar/caddy.nix:29-34`), so its upstream connection leaves from loopback, and caddy's `reverse_proxy` sets `X-Forwarded-For` to the client address by default; neither fact has yet been observed on cinnabar, and the two-client visitor observation at the cutover's first cinnabar deploy is its monitor.

#### Scenario: caddy's upstream source or forwarding header changes

- **WHEN** caddy on cinnabar connects to ntfy from an address other than `::1`, stops setting `X-Forwarded-For`, or sets it to something other than the connecting mesh client's address
- **THEN** this assumption is void, and the `fleet-alerting` requirement `Each known failure class on a host reaches a person as an alert` and the `fleet-alerting-interface` requirement `ntfy counts each mesh client as its own visitor` lose the discharge argument that ntfy sees each mesh client's own address

### Requirement: A42 — ntfy keeps a topic's messages for 12 hours and returns a recent window to a poll

It is true of ntfy 2.28.0 as cinnabar runs it, independent of what this fleet builds, that it keeps each published message for `cache-duration`, 12 hours by default, in a cache that survives a restart, and answers `GET /<topic>/json?poll=1&since=10m` with that topic's cached messages of the last 10 minutes.
Any requirement whose discharge depends on this fact SHALL name it explicitly, and SHALL be treated as losing its discharge once this assumption's violation condition below is observed.

**Evidence**: `cache-duration` defaults to 12h (`binwiederhier/ntfy` `docs/config.md:503`, `:2387`, read on `main` rather than the 2.28.0 tag), the NixOS module sets a persistent `cache-file`, and nothing in this repository overrides `cache-duration`; a poll with `since=<duration>` returns the cached messages of that window (`docs/subscribe/api.md:239-261`); 2.29.0, newer than cinnabar's release, fixed `poll=1` missing messages for up to 40 s under bursts, which at one heartbeat a minute leaves the 10-minute window full; the dead-man's own `AlertEvaluatorSilent`, which a cache that stopped answering would raise falsely, and R9.3's acceptance step of stopping and restarting the evaluator are its monitors.

#### Scenario: ntfy stops returning recent messages to a poll

- **WHEN** ntfy on cinnabar keeps messages for less than 10 minutes, loses its cache on restart and is polled before a new heartbeat arrives, or answers `poll=1&since=10m` without the messages of that window
- **THEN** this assumption is void, and the `fleet-alerting` requirement `A silent evaluator is reported from another host` and the `fleet-alerting-interface` requirement `The dead-man on cinnabar polls the heartbeat topic after an anonymous-publish probe` lose the discharge argument that an empty poll means no heartbeat was published

### Requirement: A34 — Git runs repository-local programs as the invoking account, and refuses foreign-owned repositories unless trusted

It is true of git as this fleet runs it, independent of what this fleet builds, that a repository-local setting such as `core.fsmonitor`, `core.hooksPath`, `core.pager`, `core.sshCommand`, `diff.external`, or a filter or textconv driver names a program that git runs as the account that invoked git in that repository, that such a setting outranks the same key in that account's own global configuration, and that git refuses to read the configuration of a repository owned by a different account unless a `safe.directory` entry in protected configuration admits it, where `*` admits every repository and a value ending in `/*` admits every repository beneath that directory.
A prompt that shows a repository's status invokes git whenever an account enters that repository, so a repository-local setting takes effect on entry rather than only on an explicit git command.
Any requirement whose discharge depends on this fact SHALL name it explicitly, and SHALL be treated as losing its discharge once this assumption's violation condition below is observed.

#### Scenario: Git stops running repository-local programs or stops refusing foreign-owned repositories

- **WHEN** a git release ships that no longer runs programs named by repository-local settings as the invoking account, lets an account's global configuration override them, or reads a foreign-owned repository's configuration without a matching `safe.directory` entry
- **THEN** this assumption is void, and the `shared-reference-tree` requirement `Only the writer changes the reference tree` loses the discharge argument that a single writer is what keeps one account from running code as another, and the `shared-reference-tree-interface` requirement `Readers trust the writer's tree and nothing broader` loses its reason for existing in its stated form

### Requirement: A35 — ghq resolves its root from the environment, then git configuration, then the home directory, through symlinks

It is true of ghq at the release this fleet pins, independent of what this fleet builds, that a nonempty `GHQ_ROOT` environment variable is its sole root, that otherwise every `ghq.root` value returned by `git config --get-all` is a root with the last one primary, that otherwise its root is `$HOME/ghq`, that a `ghq.<url>.root` value selects a root for matching URLs, and that every root is resolved through symbolic links before use.
Any requirement whose discharge depends on this fact SHALL name it explicitly, and SHALL be treated as losing its discharge once this assumption's violation condition below is observed.

#### Scenario: ghq changes its root resolution

- **WHEN** a ghq release changes the precedence among `GHQ_ROOT`, `ghq.root` and `$HOME/ghq`, stops honoring `ghq.root` from global git configuration, or stops resolving symbolic links in a root
- **THEN** this assumption is void, and the `shared-reference-tree` requirement `Every participating account reads one reference tree per host` and the `shared-reference-tree-interface` requirement `Each participating account resolves the shared root` lose the discharge argument that a git-configured root reaches every process an account starts

### Requirement: A36 — A host's administrator can act as any account on that host

It is true of the hosts this fleet runs, independent of what this fleet builds, that an account in a host's administrator group (`wheel` on NixOS, `admin` on darwin) can run any program as any other account on that host, including the writer and every participating account.
Any requirement whose discharge depends on this fact SHALL name it explicitly, and SHALL be treated as losing its discharge once this assumption's violation condition below is observed.

#### Scenario: Administrators lose the authority to act as other accounts

- **WHEN** a sharing host's administrator group no longer confers the authority to run programs as other accounts, for example because its sudo rule is removed or narrowed
- **THEN** this assumption is void, and the `shared-reference-tree` requirement `Moving per-account copies into the reference tree loses nothing and is reversible` loses the discharge argument that an administrator's per-account copies may enter the reference tree unaltered

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
