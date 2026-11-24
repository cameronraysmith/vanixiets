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
| abandoned attribute | — | an optional attribute the build service stopped waiting for once the required attributes had settled, which this fleet's patch to it marks with fixed error text | shared |
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

#### Scenario: The terms with two senses are read

- **WHEN** the table is read for terms that carry two senses in this repository
- **THEN** twenty-six terms carry more than one sense today and are disambiguated by separate rows rather than left to context: `session`, `package`, `policy`, `@`, `mutation`, `activation`, `probe`, `machine`, `host`, `interface`, `repository`, `build service`, `database`, `hostname`, `evaluator`, `person`, `writer`, `account`, `build`, `path`, `credential`, `identifier`, `browser`, `release`, `reader`, and `closure`, of which `probe`, `release` and `credential` carry three and every other term two

#### Scenario: A term resolves to two phenomena

- **WHEN** a content term used in a behavioral requirement denotes two distinct phenomena within this repository's vocabulary
- **THEN** this designation table records both senses as separate rows rather than collapsing them into one

#### Scenario: A behavioral requirement uses an unlisted term

- **WHEN** the designation lint finds a content noun in a behavioral requirement that resolves to no row in this table
- **THEN** the noun is either added here as a world or shared phenomenon, or the requirement using it is redirected toward the interface stratum, and neither disposition is applied silently

### Requirement: A13 — Resuming this laptop from a suspended state is unreliable, and recovering a failed resume requires a person at the machine

It is true of pyrite, this fleet's bare-metal Apple laptop, independent of its configuration, that a suspend sometimes never resumes, that only a control on the machine wakes it, and that it no longer suspends in use, falling silent instead by power-off, reboot or leaving the network.
Any requirement whose discharge depends on this fact SHALL name it explicitly, and SHALL be treated as losing its discharge once this assumption's violation condition below is observed.

**Evidence**: a host which entered a suspended state sometimes never ran again, measured at 7 failures against 30 successes across 14 boots, with no distinguishing record left behind and no identified mechanism, and the duration of the suspended interval did not predict which outcome occurred; its only remaining wake source is a physical control on the machine itself, so a host that fails to resume and a host that resumes without anyone present to press that control are indistinguishable from anywhere but the machine, an automatic suspend is a cost taken on behalf of a person who is by definition absent, and a deliberate suspend a cost taken by someone standing there; on 2026-10-27 its logind set `HandleLidSwitch=lock` and `HandleLidSwitchExternalPower=lock`, its last `systemd-suspend` entry across 75 journal boots was dated 2026-09-09, and on 2026-10-25 it booted seven times between 23:42 and 23:58 EDT (`journalctl -b all -u systemd-suspend.service` and `journalctl --list-boots` on pyrite; `logs/s4/brainstorm-prep.md` C4).

#### Scenario: Resume becomes reliable, or a wake source reachable from elsewhere appears

- **WHEN** this host is observed to resume from a suspended state across a run of attempts long enough to distinguish it from the recorded failure rate, or a wake source becomes available that a person not at the machine can trigger
- **THEN** this assumption is void, and the `graphical-desktop-session` requirement `The laptop does not suspend itself when nobody is using it` loses the reason it exists, becoming a preference about power use rather than an avoidance of a known harm

#### Scenario: pyrite suspends in use again

- **WHEN** pyrite's journal records `systemd-suspend` runs during ordinary use, or its lid switch suspends it again
- **THEN** this assumption is void for its silence, and the `fleet-alerting` requirement `A missing signal is itself reported` loses the argument that pyrite's silence comes from power-off, reboot or leaving the network, on which its acceptance by taking pyrite offline rests

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

**Evidence**: the name resolves through cinnabar's own resolver and caddy serves it only on the mesh addresses, so ZeroTier membership bounds who reaches it, and the notification service's access entries, not this assumption, bound who may publish to the fleet topics; while cinnabar or its notification service is down no alert or failure notice reaches a person, and the watch service's email reports that outage, not its content (CAM-76; ADR-009 Q5); the forced failure delivered at first activation, the weekly test alert and the watch service's email are its monitors.

#### Scenario: Publishing to the notification service requires a credential, or the service becomes unreachable from magnetite

- **WHEN** once the access entries are in force the notification service refuses a publish to a `fleet-*` topic that carries the `alerter` credential, or refuses an anonymous publish to a topic named after a host, or `ntfy.zt` stops resolving or answering from magnetite, or cinnabar's notification service stops running
- **THEN** this assumption is void, and the `telemetry-store` requirement `The telemetry store's own failures reach a person`, the `host-metrics-collection` requirement `A failed collection or store job notifies a person` and every `fleet-alerting` requirement that ends in a person being told lose their discharge until the credential is accepted again or delivery is restored, except `An outage of the alert path reaches the operator by email from outside the fleet`, which does not rest on this assumption and reports the violation

#### Scenario: A second delivery path appears

- **WHEN** the fleet gains a path other than cinnabar's notification service by which an alert or a failure notice reaches a person; the watch service's email is not such a path, because it reports only that the dead-man's pings stopped and carries no alert or failure notice
- **THEN** this assumption no longer describes the fleet, and the `fleet-alerting-interface` trust-boundary statement on an outage of the notification service is revised with it

### Requirement: A37 — ntfy provisions users, access entries and tokens from its declaration, and refuses to start on an undeclared user

It is true of ntfy 2.31.0, which cinnabar runs, independent of what this fleet builds, that it provisions the users, access entries and tokens its configuration declares, deletes at its next start any entry no longer declared, and refuses to start when an access or token entry names an undeclared user or a token is malformed.
Any requirement whose discharge depends on this fact SHALL name it explicitly, and SHALL be treated as losing its discharge once this assumption's violation condition below is observed.

**Evidence**: declarative provisioning arrived in 2.14.0 through `auth-users`, `auth-access` and `auth-tokens`, or `NTFY_AUTH_USERS`, `NTFY_AUTH_ACCESS` and `NTFY_AUTH_TOKENS` (`binwiederhier/ntfy@v2.31.0:cmd/serve.go:61-63`); an entry naming a user missing from `auth-users` stops the server (`cmd/serve.go:714`, `:753`); a token must match `^tk_[-_A-Za-z0-9]{29}$` (`user/util.go:24`); removed entries are deleted at the next start (`docs/config.md:688-689`); these lines were read at the v2.31.0 tag, the source cinnabar's package builds from, on 2026-11-01, and their text is unchanged from 2.28.0, at which this assumption was first read (`logs/s4-evidence/12.4-ntfy-2.31-20261101T183920Z.log`); cinnabar has run 2.31.0 since 2026-10-25T16:09:05Z, its `ntfy serve --help` listed the three flags on 2026-11-01, and ntfy started at 2026-11-01T06:03:17Z under 2.31.0 with its declared access entries `alerter:fleet-*:rw` and `*:fleet-*:ro`; the provisioning check before each deploy and the dead-man's anonymous-publish probe every 5 minutes are its monitors.

#### Scenario: ntfy stops honouring or enforcing its provisioning declaration

- **WHEN** a ntfy release on cinnabar starts with an access or token entry naming an undeclared user, keeps an entry the declaration no longer names, or ignores a declared user, access entry or token
- **THEN** this assumption is void, and the `fleet-alerting` requirement `Only the alerting credential publishes alerts and heartbeats`, the `fleet-alerting-interface` requirement `ntfy grants the fleet topics to alerter through declarative provisioning`, the `telemetry-store` requirement `The telemetry store's own failures reach a person` and the `host-metrics-collection` requirement `A failed collection or store job notifies a person` lose the discharge argument that the declaration is the whole of ntfy's access state and that the provisioning check guards its start

### Requirement: A38 — One ntfy access entry decides a request, a named user's before the anonymous one's

It is true of ntfy 2.31.0, which cinnabar runs, independent of what this fleet builds, that one access entry decides each request: among the entries whose topic pattern matches, a named user's entry outranks the anonymous `*` entry and a longer pattern outranks a shorter one, and with no matching entry the default access applies.
Any requirement whose discharge depends on this fact SHALL name it explicitly, and SHALL be treated as losing its discharge once this assumption's violation condition below is observed.

**Evidence**: the access query orders matching rows `u.user DESC, LENGTH(topic) DESC, write DESC` and takes the first (`binwiederhier/ntfy@v2.31.0:user/manager.go:702-735`, `user/manager_sqlite.go:90-96`), so `alerter:fleet-*:rw` outranks `*:fleet-*:ro`, an anonymous write under `*:fleet-*:ro` is refused with 403, and a topic no entry matches keeps `auth-default-access`; the in-memory access cache keeps the query's order (`user/access_cache.go:55-58`) and is off unless `auth-access-cache` is set, which cinnabar's configuration does not set; these lines were read at the v2.31.0 tag on 2026-11-01, and the query and the cache are unchanged from 2.28.0 (`logs/s4-evidence/12.4-ntfy-2.31-20261101T183920Z.log`); under 2.31.0 the dead-man's anonymous-publish probe was refused with 403 on each of its 1,088 runs from 2026-10-29T00:00Z to 2026-11-01T18:39Z, and it and the acceptance publish to a host-named topic are its monitors.

#### Scenario: ntfy changes how it chooses among access entries

- **WHEN** a ntfy release on cinnabar lets the anonymous entry outrank a named user's, combines several matching entries, or applies something other than the default access to a topic no entry matches
- **THEN** this assumption is void, and the `fleet-alerting` requirement `Only the alerting credential publishes alerts and heartbeats` and the `fleet-alerting-interface` requirement `ntfy grants the fleet topics to alerter through declarative provisioning` lose the discharge argument that `alerter` alone writes the fleet topics while every other topic stays open

### Requirement: A39 — ntfy refuses a request whose token it does not know, even where anonymous access is allowed

It is true of ntfy 2.31.0, which cinnabar runs, independent of what this fleet builds, that a request whose `Authorization` header fails authentication is refused with 401, even on a topic an anonymous client may write.
Any requirement whose discharge depends on this fact SHALL name it explicitly, and SHALL be treated as losing its discharge once this assumption's violation condition below is observed.

**Evidence**: the pinned source refuses a failed `Authorization` header before consulting access (`binwiederhier/ntfy@v2.31.0:server/server_auth.go:45-50`, a file identical to 2.28.0's), so a sender may carry the token only once cinnabar has provisioned it, which is why the cutover provisions the user and token before any sender uses them; nothing monitors it at runtime, and a ntfy upgrade on cinnabar is the event at which it is read again; the upgrade to 2.31.0 reached cinnabar on 2026-10-25 through a nixpkgs update, and this reading followed on 2026-11-01 (`logs/s4-evidence/12.4-ntfy-2.31-20261101T183920Z.log`).

#### Scenario: ntfy starts treating an unknown token as anonymous

- **WHEN** a ntfy release on cinnabar accepts a request carrying an unknown token where anonymous access is allowed, or refuses an unknown token with something other than 401
- **THEN** this assumption no longer describes ntfy, and the `fleet-alerting-interface` requirement `The alerter token travels only as a file` loses the reason its senders must not carry the token before cinnabar provisions it; the requirement still holds, but its ordering constraint becomes unnecessary

### Requirement: A40 — ntfy rate-limits a client by its address masked to a prefix, taken from a trusted proxy's forwarding header

It is true of ntfy 2.31.0, which cinnabar runs, independent of what this fleet builds, that it rate-limits a client without a tier by its address, masked for IPv6 to `visitor-prefix-bits-ipv6` bits, 64 by default, and takes that address from `X-Forwarded-For` only with `behind-proxy` set and the peer in `proxy-trusted-hosts`.
Any requirement whose discharge depends on this fact SHALL name it explicitly, and SHALL be treated as losing its discharge once this assumption's violation condition below is observed.

**Evidence**: a visitor is keyed by user only when the user has a tier and otherwise by masked address (`binwiederhier/ntfy@v2.31.0:server/visitor.go:592-602`); without `behind-proxy` the address is the TCP peer (`server/util.go:84-92`); the default budget is a burst of 60 requests refilled at one per 5 s (`docs/config.md:1905-1910`); these lines were read at the v2.31.0 tag on 2026-11-01, and `visitorID`, `extractIPAddress` and the rate-limit paragraph are unchanged from 2.28.0 (`logs/s4-evidence/12.4-ntfy-2.31-20261101T183920Z.log`); every ZeroTier member lies in `fddb:4344:343b:14b9::/64`, so at the default prefix the whole mesh is one visitor; the deployed 2.31.0 binary's `ntfy serve --help` listed all three settings on 2026-11-01, the prefix defaulting to 64; the two-client visitor observation at the cutover's first cinnabar deploy, made under 2.28.0 and not repeated under 2.31.0, is its monitor.

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

### Requirement: A42 — ntfy keeps a topic's messages for a week and returns a recent window to a poll

It is true of ntfy 2.31.0, which cinnabar runs, independent of what this fleet builds, that it keeps each published message for the `cache-duration` it is given, which cinnabar sets to 168 hours, in a cache that survives a restart, and answers `GET /<topic>/json?poll=1&since=10m` with that topic's cached messages of the last 10 minutes.
Any requirement whose discharge depends on this fact SHALL name it explicitly, and SHALL be treated as losing its discharge once this assumption's violation condition below is observed.

**Evidence**: cinnabar's running `ntfy serve` is the `ntfy-sh-2.31.0` store path, observed on 2026-11-01; `cache-duration` defaults to 12h (`binwiederhier/ntfy` `docs/config.md:503`, `:2387`, read on `main` rather than the 2.31.0 tag), `modules/machines/nixos/cinnabar/ntfy.nix` sets it to `168h` by the operator's decision of 2026-11-01 (charter v24), and the NixOS module sets a persistent `cache-file`; a poll with `since=<duration>` returns the cached messages of that window (`docs/subscribe/api.md:239-261`); 2.29.0, older than cinnabar's 2.31.0, fixed `poll=1` missing messages for up to 40 s under bursts, and without that fix one heartbeat a minute would still leave the 10-minute window full; the dead-man's own `AlertEvaluatorSilent`, which a cache that stopped answering would raise falsely, and R9.3's acceptance step of stopping and restarting the evaluator are its monitors.

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

### Requirement: A50 — electrum, galena and scheelite exist only while provisioned on demand

It is true of the fleet's cloud hosts electrum, galena and scheelite, independent of what their configurations hold, that each exists only while the operator provisions it on demand and is destroyed afterwards, so most of the time it is configured but runs nowhere.
Any requirement whose discharge depends on this fact SHALL name it explicitly, and SHALL be treated as losing its discharge once this assumption's violation condition below is observed.

**Evidence**: the terranix machine tables set `enabled = false` for electrum (`modules/terranix/hetzner.nix:18`) and for galena and scheelite (`modules/terranix/gcp.nix:32`, `:40`), while cinnabar and magnetite are `enabled = true`; ADR-009's Context records the same split, and their absence from the `fleet` database's `count by (host_name) (system_memory_usage_bytes)` on 2026-10-27 is its monitor.

#### Scenario: One of them is provisioned to run permanently

- **WHEN** electrum, galena or scheelite is set to `enabled = true` in its terranix table, or runs for more than a week
- **THEN** this assumption is void for that host, and the `fleet-alerting` requirement `A missing signal is itself reported` and the `host-metrics-collection` requirement `Each agent host contributes its own signals to the telemetry store` lose the argument that its silence is normal and its signals unobserved, until it is added to the always-on hosts

### Requirement: A51 — pyrite's NVMe controller answers the SMART health log at the pinned smartmontools

It is true of pyrite's `APPLE SSD AP0512J` controller at firmware `16.14.01`, independent of what this fleet builds, that it answers smartmontools 7.5's NVMe health log, with its critical warning, spare, wear, media errors and temperature, to a reader allowed to open its controller device.
Any requirement whose discharge depends on this fact SHALL name it explicitly, and SHALL be treated as losing its discharge once this assumption's violation condition below is observed.

**Evidence**: `smartctl -j -H -A /dev/nvme0` with the store's smartmontools 7.5 exited 0 as root on pyrite on 2026-10-27, reporting `Critical Warning 0x00`, `Available Spare 90%`, `Available Spare Threshold 2%`, `Percentage Used 11%`, `Media and Data Integrity Errors 0` and `Temperature 32 Celsius` (`logs/s4/brainstorm-prep.md` §2); the controller rejects the Error Information log page with `Invalid Log Page (0x109)`, which smartctl_exporter 0.15.0 requests with `--log=error` and on which it dropped the device (`logs/s4-evidence/5.3-smart-20261101T060029Z.log`), so the exporter reads the health log through #3668's `--smartctl.path` wrapper, which removes that one argument; through it the store held pyrite's SMART samples every minute from 2026-11-01T06:28:38Z to 17:32:38Z (`logs/s4-evidence/5.7-pyrite-replay-20261101T173317Z.log`); the exporter's read and `RuleSignalMissing` on `smartctl_device_critical_warning_total` are its monitors.

#### Scenario: The controller stops answering the health log

- **WHEN** a firmware update or a smartmontools bump leaves the store without pyrite's `smartctl_device_critical_warning_total` while pyrite reports its memory signal
- **THEN** this assumption is void, and the `host-metrics-collection` requirement `Each agent host contributes its own signals to the telemetry store` and the `fleet-alerting` requirement `Each known failure class on a host reaches a person as an alert` lose the discharge argument for pyrite's disk health, which `RuleSignalMissing` reports within 30 minutes

### Requirement: A52 — The collector answers back-pressure with a retryable refusal and keeps its persistent queue across an outage and a restart

It is true of `otelcol-contrib` 0.155.0, independent of what this fleet builds, that a receiver whose queue is full or whose memory limiter refuses answers HTTP 503, which its exporter retries, and that a `file_storage` queue keeps its items across an outage of the receiver and a restart of its collector.
Any requirement whose discharge depends on this fact SHALL name it explicitly, and SHALL be treated as losing its discharge once this assumption's violation condition below is observed.

**Evidence**: on magnetite on 2026-10-28 a spike ingress with a two-request queue toward an absent store, and then with a refusing limiter, answered `503` with `{"code":14,...}`, the agent logged `Will retry`, its queue grew from 28 to 59 requests across an outage and its own restart, and every one of the 783 points it scraped arrived once the ingress recovered, while the ingress counted the same points as refused and enqueue-failed (`logs/s4/grounding.md` §2); `vmTests.x86_64-linux.fleet-ingress`'s back-pressure case, run before any collector bump merges, is its monitor.

#### Scenario: A collector bump changes the refusal or the queue

- **WHEN** a collector version answers a full queue or a refusing limiter with a status its exporter treats as permanent, or loses persistent-queue items across a restart
- **THEN** this assumption is void, and the `host-metrics-collection` requirement `Collection survives a telemetry store restart without losing the queued interval` and the `fleet-ingress-interface` requirement `otel-envelope regulates each agent from its own collector` lose the argument that the ingress's refusals are back-pressure rather than loss

### Requirement: A53 — healthchecks.io counts a ping by its URL and emails when pings stop for longer than a check's period and grace

It is true of healthchecks.io, independent of what this fleet builds, that a ping to `https://hc-ping.com/<uuid>` is answered `OK` only when that check exists and is not rate-limited, and that a check left without a ping for its period plus grace is reported by email, as is its next ping.
Any requirement whose discharge depends on this fact SHALL name it explicitly, and SHALL be treated as losing its discharge once this assumption's violation condition below is observed.

**Evidence**: the Pinging API documentation (https://healthchecks.io/docs/http_api/, read on 2026-11-01) states that the UUID is assigned by the service and cannot be chosen, that an unknown check is answered `200` with `OK (not found)` and a rate-limited ping `200` with `OK (rate limited)`, and that more than 5 pings a minute to one check may be dropped; the free tier includes email (https://healthchecks.io/pricing/); the ping step's `OK` check at every run, and the acceptance stop of the notification service, which must produce the down and up emails, are its monitors.

#### Scenario: The service changes how it answers or when it emails

- **WHEN** a ping to an unknown or a rate-limited check is answered with exactly `OK`, the ping URL's form changes, the email integration leaves the free tier, or a check left without pings for its period plus grace produces no email
- **THEN** this assumption is void, and the `fleet-alerting` requirement `An outage of the alert path reaches the operator by email from outside the fleet` and the `fleet-alerting-interface` requirement `The dead-man pings the watch service only after a passing run` lose the discharge argument that a missing ping becomes an email and an accepted ping is counted

### Requirement: A54 — healthchecks.io runs outside the fleet, on Hetzner in Germany

It is true of healthchecks.io, independent of what this fleet builds, that it runs on no host of the fleet and depends on none of the fleet's services, and that its hosting provider is Hetzner with servers in Germany, a region that may or may not be `fsn1`, where cinnabar and magnetite run.
Any requirement whose discharge depends on this fact SHALL name it explicitly, and SHALL be treated as losing its discharge once this assumption's violation condition below is observed.

**Evidence**: the service's privacy page names Hetzner as its host (https://healthchecks.io/privacy/) and its comparison page places its servers in Germany (https://healthchecks.io/docs/healthchecks_sentry_comparison/), both read on 2026-11-01; cinnabar and magnetite are in `fsn1` (`modules/terranix/hetzner.nix`); the operator accepted on 2026-11-01 that an outage of that region may silence the service together with the hosts it watches.

#### Scenario: The service and the fleet fail together

- **WHEN** an outage takes down healthchecks.io at the same time as cinnabar, or the service moves onto infrastructure the fleet depends on
- **THEN** this assumption is void for that outage, the `fleet-alerting` requirement `An outage of the alert path reaches the operator by email from outside the fleet` loses its discharge for its duration, and the weekly test alert remains the only report

### Requirement: A55 — The operator's mailbox is reached without the fleet

It is true of the operator's mailbox, independent of what this fleet builds, that its mail provider receives and delivers mail from healthchecks.io without passing through any host or service of the fleet, and that the operator reads it on a device that does not depend on the fleet's ZeroTier network.
Any requirement whose discharge depends on this fact SHALL name it explicitly, and SHALL be treated as losing its discharge once this assumption's violation condition below is observed.

**Evidence**: no host of the fleet runs a mail service, and the address set in the watch service's email integration is chosen at the check's creation to be hosted off the fleet; the acceptance down and up emails, read on the operator's device, are its monitors.

#### Scenario: Mail comes to depend on the fleet

- **WHEN** the address the watch service emails is moved to a mail service hosted on the fleet, or the operator reads it only through the fleet's network, or mail from healthchecks.io stops being delivered
- **THEN** this assumption is void, and the `fleet-alerting` requirement `An outage of the alert path reaches the operator by email from outside the fleet` loses the discharge argument that the email reaches the operator when the fleet cannot

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

### Requirement: A67 — Helium identifies an unpacked extension by the resolved path of its folder

It is true of Helium, the Chromium-based browser this fleet installs on its darwin hosts, at release 0.20.3.1 where it was observed, independent of what this fleet builds, that a browser extension loaded unpacked is recorded under the fully resolved path of the folder it was loaded from, symbolic links followed, and that when its manifest carries no `key` its extension identity is derived from that recorded path, so one folder path keeps one extension identity however the folder's contents change, and a symbolic link whose target changes yields a new extension identity.
Any requirement whose discharge depends on this fact SHALL name it explicitly, and SHALL be treated as losing its discharge once this assumption's violation condition below is observed.

**Evidence**: on stibnite, loading a symbolic link to a store path unpacked made Helium record the store path, not the link, and assign the extension identity derived from the store path; Chromium derives an unpacked extension's identity from a hash of its absolute path when the manifest has no `key`.

#### Scenario: Helium stops identifying an unpacked extension by its resolved folder path

- **WHEN** a Helium release records an unpacked extension under the path as given rather than resolved, or derives its extension identity from anything other than that path when the manifest has no `key`
- **THEN** this assumption is void, and the `browser-relay-delivery` requirements `Each browser profile loads the relay extension once` and `The loaded relay extension follows the agent release without being reloaded by hand` lose the discharge argument that a fixed extension folder keeps one extension identity across agent releases

### Requirement: A68 — omp's relay refreshes only its own extension folder, only toward a newer release, and then reloads the extension

It is true of omp at the release this fleet deploys, 18.16.0 when this was recorded, independent of what this fleet builds, that when a relay extension reporting an older release than the relay's own is connected to omp's relay and no client is using it, the relay rewrites its extension folder, but only if the extension identity derived from that folder's resolved path equals the connected extension's identity and the folder does not already hold a newer release than the relay's own, deferring the update while a client or an attached tab is using the extension; that the rewrite leaves files whose content is already identical untouched; that after the rewrite the relay tells the extension to reload; that the extension reloads itself on that message; and that no setting disables this.
Any requirement whose discharge depends on this fact SHALL name it explicitly, and SHALL be treated as losing its discharge once this assumption's violation condition below is observed.

**Evidence**: omp source at `github.com/can1357/oh-my-pi` (`v18.16.0-620-gb7221d9948`): `packages/coding-agent/src/tools/browser/relay/server.ts:49-62` (identity and folder-version tests before `writeRelayExtension`), `extension-files.ts:50-53` (identical files skipped), `bridge.ts:786-823` (update only for an outdated extension with no client or attached tab, deferred otherwise) and `bridge.ts:816` (reload message), extension `background.ts:283-285` (reload on that message).

#### Scenario: omp's relay stops refreshing or reloading the loaded extension

- **WHEN** an omp release stops rewriting the extension folder for a connected extension of an older release, changes the identity test so the folder a person loaded no longer matches, or stops sending or obeying the reload
- **THEN** this assumption is void, and the `browser-relay-delivery` requirement `The loaded relay extension follows the agent release without being reloaded by hand` loses its discharge, leaving each browser profile on the older relay extension until the person reloads it

### Requirement: A69 — omp's default relay extension folder is `~/.omp/browser-relay/extension` while no XDG data folder or profile for omp exists

It is true of omp at the release this fleet deploys, independent of what this fleet builds, that its relay extension folder is `<getBrowserRelayDir()>/extension` with `getBrowserRelayDir()` resolving `dirs.rootSubdir("browser-relay", "data")`, which for an account whose `$XDG_DATA_HOME/omp` does not exist and which runs omp under no profile is `~/.omp/browser-relay/extension`.
Any requirement whose discharge depends on this fact SHALL name it explicitly, and SHALL be treated as losing its discharge once this assumption's violation condition below is observed.

**Evidence**: `packages/utils/src/dirs.ts:450` and `:811-812` and `packages/coding-agent/src/tools/browser/relay/extension-files.ts:31` at the same revision; on stibnite for `crs58`, `$XDG_DATA_HOME/omp` did not exist and `~/.omp` was a real directory when this was recorded.

#### Scenario: omp's relay extension folder moves

- **WHEN** an account's `$XDG_DATA_HOME/omp` comes to exist, omp runs under a profile, or an omp release changes where `getBrowserRelayDir()` or the `extension` subfolder resolves
- **THEN** this assumption is void, and the `browser-relay-delivery` requirements `The relay extension is present for every account that runs the agent on a macOS host` and `The loaded relay extension follows the agent release without being reloaded by hand` lose the discharge argument that the folder the fleet fills and a browser profile loads is the folder omp's relay writes

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

**Evidence**: on stibnite on 2026-11-05, `launchctl print system/org.nixos.nix-daemon` printed `state = running`, `runs = 3`, `pid` and `last exit code = 0`, `launchctl print system/org.nixos.nix-cleanup-gcroots` printed `state = not running` and its calendar, and a label that is not loaded printed `Could not find service`; a read-only survey of the 441 jobs in the system domain found 98, among them the running `com.apple.tzlinkd`, that printed `last exit reason = JETSAM_REASON_MEMORY_IDLE_EXIT` and no `last exit code` line, found exit codes printed as bare integers or `(never exited)`, and found no job printing a signal; of 475 jobs in the operator's per-user domain one printed `last exit reason = JETSAM_REASON_MEMORY_PERPROCESSLIMIT` and no exit-code line; on 2026-11-07, after `kill -KILL` of `org.nixos.otelcol-process`'s pid, launchd relaunched it and `launchctl print` as `nobody` printed `runs = 2`, a new `pid`, `last terminating signal = Killed: 9` and neither a `last exit code` nor a `last exit reason` line, which the probe wrote as -1, and after `launchctl kickstart -k` it printed `last exit code = 0` (`logs/s5-evidence/8.4-signal-20261107T054220Z.log`), so a signal kill omits the exit code without naming a reason; the same text was printed to an unprivileged account as to the operator's; `launchctl(1)` says its print output is not API; the probe's parser fixtures, recorded on stibnite at macOS 26.7.1, among them that signal-killed reply as `org.nixos.signal-killed`, and `RuleSignalMissing` on the launchd selectors are its monitors, and a macOS major-version upgrade on stibnite is the event at which the fixtures are recorded again.

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

It is true of stibnite, independent of what this fleet builds, that with Power Nap on it sleeps and wakes about 20 to 140 times a day, most of those wakes being dark wakes of seconds in which its kept-alive jobs resume briefly before it sleeps again.
Any requirement whose discharge depends on this fact SHALL name it explicitly, and SHALL be treated as losing its discharge once this assumption's violation condition below is observed.

**Evidence**: on 2026-11-05 `pmset -g` on stibnite reported `sleep 1`, `standby 1`, `hibernatemode 3` and `powernap 1`, and its power log held 132 `Sleep`, 137 `Wake` and 124 `DarkWake` entries for 2026-11-03 and 92, 98 and 87 for 2026-11-04; on 2026-11-07 its power log held 37, 22, 69, 132, 92, 38 and 66 `Sleep` entries for the local days 2026-10-31 to 2026-11-06, and `pmset -g` printed `sleep 0 (sleep prevented by omp, …)`, agent sessions' power assertions keeping stibnite awake; the counts of `pmset -g log` across a lid-closed sleep and a natural overnight sleep at acceptance are its monitor, and a macOS major-version upgrade or a change of these power settings is the event at which they are counted again.

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

### Requirement: A116 — Only clan's deployment and upload commands install a host's machine key

It is true of clan-core at the pinned revision, independent of what this fleet builds, that `/var/lib/sops-nix/key.txt` is written to a host only by `clan machines update`, `clan machines install` or `clan vars upload <machine>`, never by local activation.
Any requirement whose discharge depends on this fact SHALL name it explicitly, and SHALL lose its discharge once the violation condition below is observed.

**Evidence**: clan-core `dbae21013aca`, `pkgs/clan-cli/clan_lib/vars/upload.py` (`upload_secret_vars` uploads phases activation, users and services); `pkgs/clan-cli/clan_lib/vars/secret_modules/sops.py:243-260` (`populate_dir` decrypts `<machine>-age.key` as the admin user and writes `key.txt` mode 0600 for the users and services phases) and `:302-315` (`upload`, over SSH as root); `pkgs/clan-cli/clan_lib/machines/update.py:612` (`clan machines update` calls `upload_secret_vars`). This fleet's darwin activation path is `nh darwin switch` (`modules/darwin/app.nix:81`), which calls none of them.

#### Scenario: Activation starts installing the machine key, or upload stops
- **WHEN** a pinned clan-core or nix-darwin starts writing the machine key during local activation, or `clan vars upload` stops writing `key.txt` for a machine whose `<machine>-age.key` exists
- **THEN** this assumption is void, and the `secret-custody` requirement `A darwin host is not activated without its machine key` loses the argument that the remedy it names is the only one, and the `secret-custody-interface` guard's message must be re-examined

### Requirement: A117 — clan-core points sops-nix at the uploaded machine key exactly when the repository holds one

It is true of clan-core at the pinned revision, independent of what this fleet builds, that its sops vars backend sets `sops.age.keyFile` to `<secretUploadDirectory>/key.txt`, `/var/lib/sops-nix/key.txt` by default, whenever `sops/secrets/<machine>-age.key/secret` exists in the flake, and leaves it unset otherwise.
Any requirement whose discharge depends on this fact SHALL name it explicitly, and SHALL lose its discharge once the violation condition below is observed.

**Evidence**: clan-core `dbae21013aca`, `nixosModules/clanCore/vars/secret/sops/default.nix:52-54`; `nix eval --raw .#darwinConfigurations.stibnite.config.sops.age.keyFile` printed `/var/lib/sops-nix/key.txt` on 2026-11-16.

#### Scenario: The key path or its condition changes
- **WHEN** a pinned clan-core sets `sops.age.keyFile` to another path, or sets it for a machine without `<machine>-age.key`, or stops setting it
- **THEN** this assumption is void, and the `secret-custody-interface` requirement `The .#darwin app refuses activation without the host's machine key` checks the wrong file or the wrong hosts

### Requirement: A118 — sops-nix fails to install secrets when its configured age key file cannot be read

It is true of sops-nix at the pinned revision, independent of what this fleet builds, that `sops-install-secrets` returns an error, installing no secret, when the manifest names an `ageKeyFile` it cannot read.
Any requirement whose discharge depends on this fact SHALL name it explicitly, and SHALL lose its discharge once the violation condition below is observed.

**Evidence**: sops-nix `fe7b4228405a`, `pkgs/sops-install-secrets/main.go:1434-1440` (`cannot read keyfile '%s'`). The diagnosis of 2026-11-16 traced the consequences on darwin: `omnigent-host.nix:474` exits activation non-zero when it has credential deliveries, and the otelcol job waits in `wait4path` (`otel-collector-agent.nix:140-142`).

#### Scenario: Missing keys become non-fatal
- **WHEN** a pinned sops-nix skips an unreadable key file and installs what it can
- **THEN** this assumption is void, and the reason the `secret-custody` requirement `A darwin host is not activated without its machine key` stops activation, rather than letting it proceed, must be re-examined

### Requirement: A119 — ssh-to-age maps one ed25519 key to one age key, deterministically

It is true of ssh-to-age 1.3.0, independent of what this fleet builds, that the same ed25519 SSH key always yields the same age key pair, whose private half decrypts for its public half, and that every other key type is rejected.
Any requirement whose discharge depends on this fact SHALL name it explicitly, and SHALL lose its discharge once the violation condition below is observed.

**Evidence**: ssh-to-age 1.3.0 `convert.go:22-29` (private key: SHA-512 of the seed), `:32-58` (public key: the birational Edwards-to-Montgomery map, `edwards25519.Point.BytesMontgomery`, bech32 `age`), `:19` (`only ed25519 keys are supported`); nixpkgs `6dadaf4375be` ships 1.3.0.

#### Scenario: The conversion stops being deterministic or changes form
- **WHEN** a pinned ssh-to-age yields a different age key for the same SSH key, or its private and public conversions stop corresponding
- **THEN** this assumption is void, and the `secret-custody` requirements `Every public key the repository names corresponds to the person or machine it names` and `A workstation's personal key is derived from the person's SSH key in the key store` lose their discharge, because both compare ssh-to-age images

### Requirement: A120 — sops updatekeys keeps a file's data key, and only sops rotate renews it

It is true of sops 3.13.3, independent of what this fleet builds, that `sops updatekeys` re-wraps a file's existing data key for its rule's recipients without changing it, and that `sops rotate` generates a new data key and re-encrypts every value with it.
Any requirement whose discharge depends on this fact SHALL name it explicitly, and SHALL lose its discharge once the violation condition below is observed.

**Evidence**: getsops.io, "Key management" (https://getsops.io/docs/usage/key-management/): "When removing keys, it is recommended to rotate the data key using -r, otherwise, owners of the removed key may have add access to the data key in the past", and the compromised-key procedure `sops updatekeys` then `sops rotate --in-place`; "Use updatekeys if you want to add a key without rotating the data key". So a former recipient that held the old data key can read values written after `updatekeys` until `rotate` runs, and earlier ciphertext in git history stays readable by its recipients of that time. sops 3.13.3 is the devshell's version.

#### Scenario: updatekeys starts rotating, or rotate stops renewing
- **WHEN** a pinned sops renews the data key during `updatekeys`, or `rotate` keeps the old data key
- **THEN** this assumption is void, and the `secret-custody` requirement `Narrowing a secret file's readers keeps every reader still in use and renews its protection` loses the argument for, or the sufficiency of, the separate rotate step

### Requirement: A121 — A Bitwarden SSH key item carries its key pair in the sshKey fields

It is true of Bitwarden's SSH key item type, independent of what this fleet builds, that `bw get item <name>` for such an item returns JSON whose `.sshKey.privateKey` holds the OpenSSH private key and `.sshKey.publicKey` the public key.
Any requirement whose discharge depends on this fact SHALL name it explicitly, and SHALL lose its discharge once the violation condition below is observed.

**Evidence**: `justfile` `provision-bridge-key` reads these fields and produced `secrets/bridge/crs58-age-key.enc` and `secrets/bridge/tara-age-key.enc`, whose decrypted keys the NixOS hosts use; the diagnosis of 2026-11-16 confirmed the field names on the operator's vault. This evidence is observational, not from Bitwarden's source; the client choice is being researched separately and may replace `bw`.

#### Scenario: The item shape changes
- **WHEN** the key-store client in use returns the key pair under other fields, or a key item stops carrying the private key
- **THEN** this assumption is void, and the `secret-custody` requirement `A workstation's personal key is derived from the person's SSH key in the key store` loses its documented procedure until the procedure is updated

### Requirement: A136 — apm installs a locked remote dependency from apm_modules without fetching

It is true of apm 0.38.0, independent of what this fleet builds, that `apm install` with a lock recording a remote dependency and that dependency's tree in `apm_modules` installs it without git or network.
Any requirement relying on this SHALL name it and SHALL lose its discharge once the condition below is observed.

**Evidence**: 2026-11-18 spike and magnetite sandbox runs under 0.36.x, 10/10 `(cached)` (`logs/apm-sandboxlinux-compose-*`); on 2026-11-23 the composition, which refuses to run with git on its path, built under apm 0.38.0 on aarch64-darwin and in the x86_64-linux sandbox on magnetite.

#### Scenario: apm stops reusing apm_modules

- **WHEN** the pinned apm leaves 0.38.x before this evidence is re-run, or an offline install with a matching lock and tree attempts a fetch
- **THEN** this assumption is void, and `third-party-plugin-dependency` requirement `The composition installs remote apm dependencies offline from the download` loses its discharge

### Requirement: A137 — apm installs a virtual-subdirectory dependency as that directory alone

It is true of apm 0.38.0 that an `owner/repo/<path>#<sha>` dependency installs only `<path>` as the package root, so files outside it, hooks included, are never seen.
Any requirement relying on this SHALL name it and SHALL lose its discharge once the condition below is observed.

**Evidence**: experiments E3, E9 and E10 and the v7.0.2 addendum run f1 under 0.36.x (`logs/apm-superpowersd1-*`); on 2026-11-23 the composition under apm 0.38.0 was byte-identical to 0.36.0's, superpowers' and agency's skills included, and its `.claude/settings.json` was unchanged.

#### Scenario: a subdirectory dependency brings repository files

- **WHEN** the pinned apm leaves 0.38.x before this evidence is re-run, or a subdirectory dependency installs a hook or file from outside its path
- **THEN** this assumption is void, and `third-party-plugin-dependency` requirement `superpowers and agency are consumed per skill directory` loses its discharge

### Requirement: A138 — apm removes a downloaded package whose content no longer matches its lock

It is true of apm 0.38.0 that an installed package whose tree differs from its lock's content hash is deleted and re-fetched rather than used.
Any requirement relying on this SHALL name it and SHALL lose its discharge once the condition below is observed.

**Evidence**: F6 under 0.36.x, `apm_cli/install/phases/integrate.py:281-300` (`logs/apm-verify-f5f6v-*`). Re-observed under 0.38.0 on 2026-11-23 in the compose's layout (the download's `apm_modules` and lock, an isolated HOME): after one line was appended to `apm_modules/obra/superpowers/skills/brainstorming/SKILL.md`, `apm install` reported "Content hash mismatch ... Re-downloading from the locked source". Offline (no usable git) the re-fetch failed, the install failed and rolled back ("Deployed files restored to their previous state"), and the deployed `brainstorming` stayed unedited; unlike 0.36, which deleted the copy before fetching, the edited copy stayed in `apm_modules` (`logs/apm-verify-f5f6-038-20261123-151020.log`). With git and the network the same install re-fetched it, passed, and left the copy byte-identical to the download (`logs/apm-verify-f6-online-038-20261123-151107.log`). The edited download is never used, so the assumption holds.

#### Scenario: an edited download is used

- **WHEN** the pinned apm leaves 0.38.x before this evidence is re-run, or an install uses a package whose tree differs from its locked hash
- **THEN** this assumption is void, and `third-party-plugin-dependency` requirement `Upstream tool skills are delivered unmodified` loses its discharge

### Requirement: A139 — apm's download bytes change only with apm's version

It is true of apm that, for full-SHA refs, its download is byte-identical across runs and platforms for one apm version, and differs between versions only through apm's own normalization (0.36 carries each repository LICENSE into every skill; 0.37 moved the lock to format v4, which changes its bytes).
Any requirement relying on this SHALL name it and SHALL lose its discharge once the condition below is observed.

**Evidence**: U1, R2 and R3 (`logs/apm-verify-r3-*`, `logs/apm-sandboxlinux-deps-*`); on 2026-11-23 the download under apm 0.38.0 had the same hash on aarch64-darwin and x86_64-linux, and rebuilt to the same hash with `--rebuild`.

#### Scenario: the same apm version yields different bytes

- **WHEN** a cold build of the download under an unchanged apm version reports a hash mismatch
- **THEN** this assumption is void, and `third-party-plugin-dependency` requirement `Remote apm dependencies are downloaded in one guarded fixed-output derivation` loses its discharge

### Requirement: A140 — apm lock records commits and content hashes but no deployed files

It is true of apm 0.38.0 that `apm lock` writes, per remote dependency, its resolved commit and content hash, with no deployed-files records, so `--frozen` cannot install from it.
Any requirement relying on this SHALL name it and SHALL lose its discharge once the condition below is observed.

**Evidence**: U3 and F5 under 0.36.x (`logs/apm-verify-f5f6v-*`); on 2026-11-23 a frozen install of the composition under apm 0.38.0 (forced by `CI=true`) failed because the lock records no deployed files for the local packages. Re-observed for the remote entries under 0.38.0 on 2026-11-23: the download's lock, written by `apm lock`, has 26 remote entries, each with `resolved_commit` and `content_hash`, none with `deployed_files`; a plain offline install from it deploys 177 skills per tree and records `deployed_files` for all 26; `apm install --frozen` with those 26 entries as `apm lock` wrote them (local entries taken from the plain install) fails with "apm.lock.yaml does not record everything this install deploys" and 102 "deployed by this install but not recorded" lines (`logs/apm-verify-f5f6-038-20261123-151020.log`). The assumption holds.

#### Scenario: the lock shape changes

- **WHEN** the pinned apm leaves 0.38.x before this evidence is re-run, or its `apm lock` output gains deployed files or loses commits or content hashes
- **THEN** this assumption is void, and the `third-party-plugin-dependency` requirements `Remote apm dependencies are downloaded in one guarded fixed-output derivation` and `The composition installs remote apm dependencies offline from the download` lose their discharge

### Requirement: A141 — GitHub serves a shallow, blobless fetch of a commit by its SHA

It is true of GitHub that `git fetch --depth 1 --filter=blob:none <url> <sha>` retrieves that commit's tree without a branch or tag naming it.
Any requirement relying on this SHALL name it and SHALL lose its discharge once the condition below is observed.

**Evidence**: to be observed by this change's first task inside the fixed-output sandbox; apm's own full-SHA fetches succeeded there (R1, R2).

#### Scenario: GitHub refuses a fetch by SHA

- **WHEN** the download's superpowers-list step fails to fetch the declared commit while GitHub is reachable
- **THEN** this assumption is void, and `third-party-plugin-dependency` requirement `superpowers and agency are consumed per skill directory` loses the discharge of its upstream-list scenario

### Requirement: A167 — Context and skills written by the setup step reach a cloud session's first prompt

It is true of a cloud session, independent of what this fleet builds, that a user context file the setup step writes at `/root/.claude/CLAUDE.md` and a skill it writes under `/root/.claude/skills/` are shown and listed in the first prompt.
Any requirement whose discharge depends on this fact SHALL name it explicitly, and SHALL lose its discharge once the violation below is observed.

#### Scenario: Measured on 2026-11-21

- **WHEN** a setup step writes a marker into the user context file and a marker skill, and a cloud session starts
- **THEN** the session reports both markers in its first context; observed in probe session 1 (file written 19:12:47.145, session state created 19:12:47.8) and in probe session 2's children A, A2, B and B2, each of which also loaded the skill on use

#### Scenario: Setup-written context or skills stop reaching the first prompt

- **WHEN** a cloud session started after such a setup step does not show that context or list that skill in its first prompt
- **THEN** this assumption is void, and the `claude-sandbox-bootstrap` requirement `Context and skills from the first prompt` loses its discharge

### Requirement: A168 — A later cloud session starts from the environment snapshot without running the setup step

It is true of a cloud environment, independent of what this fleet builds, that once its setup step has succeeded, a later cloud session on it starts from the environment snapshot, with that run's files, without running the setup step again.
Any requirement whose discharge depends on this fact SHALL name it explicitly, and SHALL lose its discharge once the violation below is observed.

#### Scenario: Measured on 2026-11-21

- **WHEN** a second cloud session is created on an unchanged cloud environment after a successful setup step
- **THEN** it runs within about 10 seconds with no new setup run; observed for child A2 (booted 19:23:32, one setup run 19:22:17–19:22:52) and child B2 (booted 19:32:44, one run 19:25:26–19:31:27)

#### Scenario: A later session re-runs the setup step

- **WHEN** a cloud session started on an unchanged cloud environment whose setup step already succeeded runs it again, or lacks the files it wrote
- **THEN** this assumption is void, and the `claude-sandbox-bootstrap` requirements `Context and skills from the first prompt` and `Setup finishes within the snapshot window` lose their discharge

### Requirement: A169 — A 360-second setup step completes and is snapshotted

It is true of a cloud environment, independent of what this fleet builds, that a 360-second setup step is neither cut off nor left uncached, contrary to the documented five-minute bound; the actual ceiling is unknown.
Any requirement whose discharge depends on this fact SHALL name it explicitly, and SHALL lose its discharge once the violation below is observed.

#### Scenario: Measured on 2026-11-21

- **WHEN** a setup step sleeps until it has run for 360 seconds
- **THEN** the session waits for it and later sessions start from its snapshot; observed for child B (`nix_run_rc=0 secs=360`, 19:25:26–19:31:26, agent at 19:31:35) and child B2

#### Scenario: A setup step of 360 seconds or less is cut off or not cached

- **WHEN** a setup step of at most 360 seconds is terminated before it finishes, or the next session on the unchanged cloud environment runs it again
- **THEN** this assumption is void, and the `claude-sandbox-bootstrap` requirement `Setup finishes within the snapshot window` loses its discharge

### Requirement: A170 — A setup step that exits non-zero prevents the cloud session from starting

It is true of a cloud environment, independent of what this fleet builds, that a setup step exiting non-zero leaves the cloud session unable to start or recover, whatever `CCR_SETUP_SCRIPT_FAILURE_CONTINUES` holds.
Any requirement whose discharge depends on this fact SHALL name it explicitly, and SHALL lose its discharge once the violation below is observed.

#### Scenario: Measured on 2026-11-21

- **WHEN** a setup step exits 3 on purpose
- **THEN** the session never starts its model; observed for child D: exit 3 at 19:34:36, `last_init_error` "Setup script failed" with `recoverable=false`, still pending at 19:35:42, `num_turns=0`, with `CCR_SETUP_SCRIPT_FAILURE_CONTINUES` present in the setup step's environment

#### Scenario: A failed setup step no longer blocks the session

- **WHEN** a cloud session whose setup step exited non-zero starts its model anyway
- **THEN** this assumption is void, and the `claude-sandbox-bootstrap` requirement `Setup never prevents a session from starting` loses the reason it rests on, though not its discharge

### Requirement: A171 — The setup step runs twice on a cloud environment's first use

It is true of a cloud environment, independent of what this fleet builds, that the first session after a setup script change runs the setup step twice: in the session's container and in one that builds the environment snapshot.
Any requirement whose discharge depends on this fact SHALL name it explicitly, and SHALL lose its discharge once the violation below is observed.

#### Scenario: Measured on 2026-11-21

- **WHEN** a cloud session is created right after a setup script change
- **THEN** two runs occur; observed for child A, whose run ended 19:22:40 while the run in A2's snapshot started the same second and ended 19:22:52, and the platform logged "Saving setup for next time" with `setup_source=building_checkpoint` for A and for D

#### Scenario: The setup step runs a different number of times

- **WHEN** a setup script change is followed by more than two runs before a later session starts from a snapshot, or the two runs share a container
- **THEN** this assumption is void, and the `claude-sandbox-bootstrap` requirement `Idempotent setup without external side effects` must be re-argued against the observed runs

### Requirement: A172 — The setup step runs as root after attached repositories are cloned, without the environment's variables or secrets

It is true of a cloud environment, independent of what this fleet builds, that the setup step runs as root in `/home/user` after the attached repositories are cloned there, and cannot read the environment's variables or secrets.
Any requirement whose discharge depends on this fact SHALL name it explicitly, and SHALL lose its discharge once the violation below is observed.

#### Scenario: Measured on 2026-11-21

- **WHEN** a setup step logs its identity, directory and the repositories present
- **THEN** probe session 1 recorded `id=root pwd=/home/user repos=/home/user/vanixiets/` and no session identifier among the variable names; the platform's `update_environment` description states "The script cannot read the environment's saved variables or secrets"

#### Scenario: The setup step's identity, order or inputs change

- **WHEN** the setup step runs as another account, before the attached repositories are cloned, or with the environment's variables or secrets readable
- **THEN** this assumption is void, and the `claude-sandbox-bootstrap` requirements `Context and skills from the first prompt`, `No secret at rest` and `Attached repositories get their repository context` lose their discharge

### Requirement: A173 — The agent's shell inherits neither login profiles nor setup-step exports

It is true of a cloud session, independent of what this fleet builds, that the agent's shell is a non-login bash from a saved shell snapshot that `/etc/profile.d` and `.bashrc` do not reach, with `CLAUDE_ENV_FILE` unset outside hooks.
Any requirement whose discharge depends on this fact SHALL name it explicitly, and SHALL lose its discharge once the violation below is observed.

#### Scenario: Measured on 2026-11-21

- **WHEN** a setup step writes exports to `/etc/profile.d` and `/root/.bashrc` and the agent's shell prints its environment
- **THEN** probe session 1 (P4) found both exports unset, `login_shell` off, `CLAUDE_ENV_FILE` unset, `NIX_PROFILES`, `NIX_SSL_CERT_FILE`, `HOME` and `PATH` set, and `USER` unset

#### Scenario: The agent's shell environment changes

- **WHEN** the agent's shell starts as a login shell, picks up profile or bashrc exports, or loses `NIX_PROFILES`
- **THEN** this assumption is void, and the `claude-sandbox-bootstrap` requirement `Required tools present` must be re-argued against how tools then reach the shell

### Requirement: A174 — A cloud session's container has one filesystem with about 64 GB free

It is true of a cloud session's container, independent of what this fleet builds, that `/`, `/nix`, `/home` and `/tmp` share one filesystem with about 64 GB free, more than the documented 30 GB.
Any requirement whose discharge depends on this fact SHALL name it explicitly, and SHALL lose its discharge once the violation below is observed.

#### Scenario: Measured on 2026-11-21

- **WHEN** the agent's shell measures free space and writes a large file
- **THEN** probe session 1 (P9) measured 64,375,160,832 bytes available on `/dev/vda` and `fallocate -l 35G` succeeded; no quota mechanism was observed

#### Scenario: Available disk shrinks

- **WHEN** a fresh container has less free space than the bootstrap's closure needs, or a write within the measured size fails
- **THEN** this assumption is void, and the `claude-sandbox-bootstrap` requirements `Context and skills from the first prompt` and `Required tools present` lose their discharge for closures larger than the space available

### Requirement: A175 — The GitHub gate refuses unattached repositories' archives while channels, allowlisted caches and anonymous git reads are served

It is true of the operator's limited-network cloud environments, independent of what this fleet builds, that the GitHub gate refuses `github:` flake inputs, while anonymous git reads, `channels.nixos.org` and the allowlisted binary caches are served.
Any requirement whose discharge depends on this fact SHALL name it explicitly, and SHALL lose its discharge once the violation below is observed.

#### Scenario: Measured on 2026-11-21

- **WHEN** a cloud session fetches an unattached repository's archive, the same repository over git, the registry's `nixpkgs`, and the binary caches
- **THEN** the archive got 403 "GitHub access to this repository is not enabled for this session", `nix flake prefetch git+https://github.com/vic/import-tree` succeeded, `nix path-info --store` answered from `cache.nixos.org` and `cache.scientistexperience.net` (V11, V12, V22), and `nixpkgs` resolved to `https://channels.nixos.org/nixpkgs-unstable/nixexprs.tar.zst` with no 403 (probe session 1, P8)

#### Scenario: The gate or the allowlist changes

- **WHEN** anonymous git reads of public repositories are refused, the channels or an allowlisted cache stop answering, or the gate stops refusing archives
- **THEN** this assumption is void, and the `claude-sandbox-bootstrap` requirements `One closure defines the environment` and `Attached repositories get their repository context` lose their discharge, or in the last case gain simpler designs

### Requirement: A176 — A pinned remote `git+https` sub-flake runs from the setup step in about 23 seconds

It is true of a cloud environment, independent of what this fleet builds, that its setup step can `nix run` a pinned `git+https` sub-flake of this repository whose only input is a `channels.nixos.org` tarball, in about 23 seconds.
Any requirement whose discharge depends on this fact SHALL name it explicitly, and SHALL lose its discharge once the violation below is observed.

#### Scenario: Measured on 2026-11-21

- **WHEN** the setup step runs `nix run "git+https://github.com/cameronraysmith/vanixiets?rev=7fffbd2c2464f7663348fde7882541b430507714&shallow=1&dir=bootstrap/claude-sandbox"` (branch `claude-sandbox-dev`)
- **THEN** child A's setup log records the fetch, 50 paths (30.6 MiB) from `cache.nixos.org`, the build of `claude-sandbox-probe`, and `nix_run_rc=0 secs=23`

#### Scenario: The pinned remote run fails or slows

- **WHEN** a pinned `git+https` run of a channels-only sub-flake fails from the setup step, or takes long enough that the bootstrap exceeds the measured setup bound
- **THEN** this assumption is void; since Q91 (2026-11-21) the setup step names a closure instead of running a sub-flake, so no `claude-sandbox-bootstrap` requirement rests on it

### Requirement: A177 — Nix is preinstalled single-user, with root trusted and only cache.nixos.org configured

It is true of a cloud session's base image, independent of what this fleet builds, that Nix 2.34.6 is preinstalled without a daemon, on a local store, trusting root, with only `cache.nixos.org` configured and flakes enabled.
Any requirement whose discharge depends on this fact SHALL name it explicitly, and SHALL lose its discharge once the violation below is observed.

#### Scenario: Measured on 2026-11-21

- **WHEN** a cloud session reads Nix's version, configuration and install receipt
- **THEN** it finds the NixOS nix-installer's receipt, no `nix-daemon`, `Store URL: local`, `trusted-users = root`, `substituters` and `trusted-public-keys` naming only `cache.nixos.org`, and `accept-flake-config = false` (V8, V13, V14), and probe session 1 recorded `nix (Nix) 2.34.6`; reports from 2026-03 to 2026-09 describe other installers, so the image has changed before

#### Scenario: The base image's Nix changes

- **WHEN** a fresh container's Nix version, installer, store, trusted users or configured caches differ from the above
- **THEN** this assumption is void, and the `claude-sandbox-bootstrap` requirements `One closure defines the environment` and `Setup finishes within the snapshot window` must be re-checked against the new base image

### Requirement: A178 — The platform owns part of `/root/.claude` and leaves setup-written files beside it

It is true of a cloud session, independent of what this fleet builds, that the platform writes and manages its own files under `/root/.claude`, and that files the setup step writes beside them survive into the session.
Any requirement whose discharge depends on this fact SHALL name it explicitly, and SHALL lose its discharge once the violation below is observed.

#### Scenario: Measured on 2026-11-21

- **WHEN** a cloud session lists `/root/.claude` and edits the platform's files
- **THEN** it finds `launcher-settings.json` (an edit "was blocked by a deny rule"), `session-start-setup-script-failure.sh`, `stop-hook-git-check.sh`, `environment-manager/` and `skills/{session-start-hook,synced}` (V6, C18); in A2, `skills/synced` was rewritten at 19:23:38, after the snapshot, while the setup-written skill kept its 19:22:52 time

#### Scenario: The platform rewrites setup-written files

- **WHEN** a file the setup step wrote under `/root/.claude` is missing or replaced when the session starts, or the platform claims a path the bootstrap writes
- **THEN** this assumption is void, and the `claude-sandbox-bootstrap` requirements `Context and skills from the first prompt` and `Additive to harness-owned state` lose their discharge

### Requirement: A179 — A controller session can start cloud sessions, change the setup step, and read what they push

It is true of a cloud session, independent of what this fleet builds, that it can create cloud sessions on its cloud environment, replace that environment's setup script behind one approval card per change, and read new branches of any name they push.
Any requirement whose discharge depends on this fact SHALL name it explicitly, and SHALL lose its discharge once the violation below is observed.

#### Scenario: Measured on 2026-11-21

- **WHEN** a controller session runs `create_session`, `update_environment`, `get_session` and `git fetch`
- **THEN** probe session 2's controller created children A, A2, B, B2 and D, made four `update_environment` calls each answered `"setup_script_replaced":true` after one approval card, and read reports from `claude/sandbox-reports-s2A`, `-s2A2`, `-s2B` and `-s2B2`; probe session 1 pushed the new branches `claude/sandbox-reports` and `sandbox-reports-plain`

#### Scenario: Session control or pushing is withdrawn

- **WHEN** a cloud session can no longer create sessions, change its environment's setup script, or push a new branch, or each change needs more than one approval card
- **THEN** this assumption is void, and the `claude-sandbox-bootstrap` requirements `One operator action per development iteration` and `Every bootstrap run reports` lose their discharge

### Requirement: A180 — Packages activated as root reach the agent's shell through the image's default Nix profile

It is true of a cloud session's base image, independent of what this fleet builds, that home-manager activated as root installs its packages into `/nix/var/nix/profiles/default`, whose `bin` is on the agent's shell `PATH`, and that the image's Nix, in the same profile, still runs afterwards.
Any requirement whose discharge depends on this fact SHALL name it explicitly, and SHALL lose its discharge once the violation below is observed.

#### Scenario: Measured on 2026-11-21

- **WHEN** session 3's children C1 and C2 start on a setup step that activated `claude-sandbox`'s activation package, and their agent's shell prints `PATH` and runs `command -v` on 18 tools
- **THEN** `PATH` is the platform's `rm-guard` directory, then `/nix/var/nix/profiles/default/bin`, then system directories; all 18 tools (openspec, linear, jj, git, gh, ghq, mergify, jq, jaq, rg, fd, duckdb, just, uv, pandoc, sops, age, wt) resolve under `/nix/var/nix/profiles/default/bin`; `/root/.nix-profile` points at `per-user/root/profile` and `/root/.local/state/nix/profiles` does not exist; and the setup step read `nix=2.34.6` after activating, which is indirect evidence that Nix survived

#### Scenario: The base image's Nix layout changes

- **WHEN** a fresh container's Nix installer, default profile or harness `PATH` differ from the above (PA3: they changed between 2026-03 and 2026-09), a required tool no longer resolves under `/nix/var/nix/profiles/default/bin`, or `command -v nix` fails after activation
- **THEN** this assumption is void, and the `claude-sandbox-bootstrap` requirement `Required tools present` loses its discharge and needs a `PATH` route of its own (a `CLAUDE_ENV_FILE` line from a SessionStart hook, or links into `/usr/local/bin`)

### Requirement: A181 — The setup step runs when a container is claimed for a session, not when it boots

It is true of a cloud environment, independent of what this fleet builds, that the platform keeps pre-warmed containers and runs the setup step when one is claimed for a session, using the setup script current at that moment.
Any requirement whose discharge depends on this fact SHALL name it explicitly, and SHALL lose its discharge once the violation below is observed.

#### Scenario: Measured on 2026-11-21

- **WHEN** session 4's controller created children E1, E3 and E4 and swapped the setup script between E2's and E4's creation
- **THEN** E1, E3 and E4 each reported an `uptime -s` earlier than their `create_session` (E1 booted 22:06:32, created 22:08:28); E4 booted at 22:10:30 while the real script was installed, yet its only `setup.log` line is the broken script's run at 22:12:28Z, after its creation at 22:12:22

#### Scenario: Setup runs at boot

- **WHEN** a container's `setup.log` holds a run of a setup script that was replaced before the container was claimed
- **THEN** this assumption is void, and the `claude-sandbox-bootstrap` requirement `One closure defines the environment` loses its discharge, because a session could start on a superseded closure

### Requirement: A182 — A snapshot can come from a sibling container, not the cold session's own

It is true of a cloud environment, independent of what this fleet builds, that the environment snapshot later sessions start from can be taken from a sibling container that ran the setup step alongside the cold session, rather than from the cold session's own container.
Any requirement whose discharge depends on this fact SHALL name it explicitly, and SHALL lose its discharge once the violation below is observed.

#### Scenario: Measured on 2026-11-21

- **WHEN** a snapshot-started session reads its `setup.log` and compares it with the cold session's
- **THEN** session 4's E2 holds one line stamped 22:09:04Z with `activate=0/3s`, while E1's is 22:09:03Z with `activate=0/2s`; session 3's C2 holds 21:19:26Z, `realise=0/16s activate=0/4s`, while C1's is 21:19:25Z, `0/17s`, `0/3s`

#### Scenario: The snapshot depends on the cold session's own run

- **WHEN** a snapshot-started session holds only the cold session's own setup run, or a failure in a sibling's run leaves a snapshot the cold session never had
- **THEN** this assumption is void, and the `claude-sandbox-bootstrap` requirement `Idempotent setup without external side effects` must be re-argued, since it relies on every run of the same script ending in the same state

### Requirement: A183 — The workspace directory is not the session account's home

It is true of a cloud session, independent of what this fleet builds, that `/home/user`, where the setup step starts and attached repositories are cloned, belongs to no account: no passwd entry `user` exists, `/home/user` is `root:root` 755, and the session runs as root with home `/root`.
Any requirement whose discharge depends on this fact SHALL name it explicitly, and SHALL lose its discharge once the violation below is observed.

#### Scenario: Measured on 2026-11-21

- **WHEN** task 7.2's child session on the Default cloud environment runs `getent passwd user`, `stat /home/user` and `id`
- **THEN** they print "no passwd entry named user", `root:root 755 /home/user` and `uid=0(root) gid=0(root) groups=0(root)`

#### Scenario: The workspace gains its own account or moves

- **WHEN** a cloud session runs as an account whose home is `/home/user`, or attached repositories are cloned elsewhere
- **THEN** this assumption is void, and the `claude-sandbox-bootstrap` requirement `Attached repositories get their repository context` loses its discharge until the workspace directory the profile names is re-measured

### Requirement: A184 — A cloud session evaluates the main branch from the caches without the GitHub gate

It is true of a cloud session on the operator's limited-network cloud environments, independent of what this fleet builds, that it can evaluate this repository's `main` over anonymous git with every input source it needs substituted from the fleet's binary cache or `cache.nixos.org`, in under a minute and about 1 GiB.
Any requirement whose discharge depends on this fact SHALL name it explicitly, and SHALL lose its discharge once the violation below is observed.

#### Scenario: Measured on 2026-11-22

- **WHEN** a session on the Default environment evaluated `claude-sandbox@x86_64-linux`'s activation package path from `git+https://github.com/cameronraysmith/vanixiets?ref=main&shallow=1` at `5967d3ab41d4`, with the two caches passed as a bash array
- **THEN** it printed `d96f192x7b6r0gwahpdy877nsv2a6ad9-home-manager-generation` with rc=0 in 46 s at 964,788 kB peak, copying 19 sources (18 from `cache.scientistexperience.net`, 1 from `cache.nixos.org`), with no 403 and no other GitHub fetch

#### Scenario: Evaluation needs the GitHub gate or slows

- **WHEN** evaluating `main` in a cloud session fetches an input source from GitHub, fails with 403, or exceeds the setup step's time budget with every source cached
- **THEN** this assumption is void, and the `claude-sandbox-bootstrap` requirement `One closure defines the environment` loses its discharge for a cloud environment that is not pinned

### Requirement: A185 — The platform documents that it rebuilds an environment snapshot after about seven days

It is documented by Anthropic, and assumed here without measurement, that a cloud environment's snapshot is rebuilt when its setup script or allowed hosts change and after about seven days, and otherwise reused.
Any requirement whose discharge depends on this fact SHALL name it explicitly, and SHALL lose its discharge once the violation below is observed.

#### Scenario: Documented, not yet measured

- **WHEN** the platform's documentation on environment caching is read (record C12 of the session of 2026-11-21)
- **THEN** it says the setup script "runs again to rebuild the cache when you change the environment's setup script or allowed network hosts, and when the cache reaches its expiry after roughly seven days"; the expiry has not been observed

#### Scenario: A snapshot outlives or undercuts seven days

- **WHEN** a session started more than about seven days after its snapshot's setup run still starts from that snapshot, or a snapshot is rebuilt with no change and well within seven days
- **THEN** this assumption is void, and the `claude-sandbox-bootstrap` requirement `Sessions report how far behind the main branch they are` must be re-read against the measured expiry, since it is how the operator learns a refresh is due

### Requirement: A186 — The harness applies its own git configuration beside the profile's

It is true of a cloud session, independent of what this fleet builds, that the harness writes `/root/.gitconfig` after the setup step and injects `GIT_CONFIG_COUNT` with three `GIT_CONFIG_KEY_n`/`GIT_CONFIG_VALUE_n` overrides, while the profile's `/root/.config/git/config` still applies for every key the harness does not set.
Any requirement whose discharge depends on this fact SHALL name it explicitly, and SHALL lose its discharge once the violation below is observed.

#### Scenario: Measured on 2026-11-22

- **WHEN** the Q97 probe session listed the git environment variable names and the git configuration files, and asked git where `ghq.root` comes from
- **THEN** it found `GIT_CONFIG_COUNT` and `GIT_CONFIG_KEY_0`–`_2` and `GIT_CONFIG_VALUE_0`–`_2`, `/root/.gitconfig` written at 22:48 after the 22:47 activation, and `file:/root/.config/git/config	/home/user/ghq`

#### Scenario: The harness overrides a key the profile relies on

- **WHEN** a key the profile sets in `/root/.config/git/config` is shadowed by the harness's file or its environment overrides
- **THEN** this assumption is void for that key, and the `claude-sandbox-bootstrap` requirement `One source for agent context and skills` must be re-checked for any instruction that depends on it

### Requirement: A187 — The platform refuses a setup-script line wider than 200 columns

It is true of a cloud environment, independent of what this fleet builds, that the platform refuses a setup script holding any line wider than 200 columns, a tab counting 8, before an approval card is shown, so the script never changes.
Any requirement whose discharge depends on this fact SHALL name it explicitly, and SHALL lose its discharge once the violation below is observed.

#### Scenario: Measured on 2026-11-22

- **WHEN** task 5.3's controller sent Default a setup script whose line 2 was 402 columns
- **THEN** `update_environment` answered `setup_script line 2 is 402 columns wide (a tab counts 8); keep each line to at most 200 (split long commands with "\" continuations) so the person approving can read all of it`, and nothing was changed

#### Scenario: The platform's limit changes

- **WHEN** the platform accepts a wider line, or refuses one of 200 columns or fewer
- **THEN** this assumption is void, and the `claude-sandbox-interface` requirement `The setup box holds a fixed bootstrap` and the `claude-sandbox-setup-script` check's 200-column limit must be revised to the observed limit

### Requirement: A105 — omnigent refuses a login grant's refresh once its age reaches a lifetime fixed at server start, and later purges it

It is true of omnigent 0.22.0, independent of what this fleet builds, that the server refuses to refresh a login grant once the time since its approval reaches the grant lifetime it read at start, and that a later refresh deletes every redeemed or revoked grant of that age.
Any requirement whose discharge depends on this fact SHALL name it explicitly, and SHALL lose its discharge once the violation condition below is observed.

**Evidence**: `omnigent/server/routes/device_auth.py:522-525` returns `expired_token` once `now - approved_at` reaches the lifetime; `:123-156` make the lifetime `OMNIGENT_GRANT_MAX_LIFETIME_DAYS` whole days when that is a positive integer and 30 days otherwise; `:408` reads it once when the token router is mounted; `:288` and `omnigent/server/device_grant_store.py:586-640` purge aged grants at most every 300 s on a refresh; `device_auth.py:529-545` keeps a login grant's refresh token for its whole life; `:118` makes access tokens last 3,600 s, so workers refresh hourly.

#### Scenario: An upgrade changes the lifetime's rule

- **WHEN** an omnigent upgrade changes how the lifetime is computed, read or enforced, or stops purging aged grants
- **THEN** this assumption is void, and the 90-day lifetime and the purge-first deploy of this change must be re-derived from the new source

#### Scenario: The server is restarted with a longer lifetime

- **WHEN** the server starts with a lifetime longer than the age of a grant it has not yet purged
- **THEN** that grant becomes refreshable again, which is why every superseded grant is purged before the lifetime is raised

### Requirement: A106 — A login grant is revocable only by presenting its own token

It is true of omnigent 0.22.0, independent of what this fleet builds, that a login grant can be revoked only by presenting its refresh token or an access token naming it, so a grant whose tokens no holder keeps ends only at its lifetime.
Any requirement whose discharge depends on this fact SHALL name it explicitly, and SHALL lose its discharge once the violation condition below is observed.

**Evidence**: `omnigent/server/routes/device_auth.py:582-610` is the only revocation route; the server has no administrative revocation, and the 0.22.0 CLI never calls `/oauth/revoke`, read on magnetite on 2026-11-14.

#### Scenario: omnigent gains administrative revocation

- **WHEN** an omnigent release lets an administrator revoke a grant by owner or by identifier
- **THEN** this assumption is void, and superseded grants can be revoked rather than purged before the lifetime is raised

### Requirement: A213 — apm deploys a package's `.apm/skills` children flat whatever plugin manifest sits beside them

It is true of apm 0.38.0 that a package whose `apm.yml` sits beside an `.apm/` directory is typed `apm_package` before any plugin-manifest rule applies, and that at project scope each child of its `.apm/skills/` is deployed flat under each target's skills root, with or without a root `plugin.json`.
Any requirement whose discharge depends on this fact SHALL name it explicitly, and SHALL lose its discharge once the violation below is observed.

**Evidence**: apm `models/format_detection.py:455-497` (an "eligible" `apm.yml` wins, read at the 0.38 checkout); on 2026-11-23 the composition built from a scratch copy of this repository with all 22 root `plugin.json` files removed emitted 177 skill directories in each tree, with `nix hash path` `sha256-YI99ZQcB/QhiCWYZqs1OMcs0yPuNkiLJTKT8ue+B8F0=` for both, equal to the composition with the files; a third-party consumer of the same tree received `nix-build-operations` and `planning-and-development` flat and byte-identical to their sources.

#### Scenario: Observed on 2026-11-23

- **WHEN** the composition and a third-party consumer install ran with apm 0.38.0 over groups that carry no plugin manifest
- **THEN** every first-party skill was deployed flat and byte-identical to its source

#### Scenario: apm changes its package typing or deployment

- **WHEN** an apm release types such a package otherwise, deploys it whole into `.agents/plugins/`, or deploys fewer than all children of `.apm/skills/`
- **THEN** this assumption is void, and the `first-party-skill-distribution` requirement `Build-time apm composition of first-party skills` and the `skill-marketplace-publication` requirement `An apm consumer installs every published plugin group` lose their discharge until the composition's tree comparison passes again

### Requirement: A214 — apm deploys a Claude-plugin dependency flat when the dependency selects its skills

It is true of apm 0.38.0 that, at project scope with the `claude` target, a dependency typed as a marketplace plugin with a `.claude-plugin/plugin.json` is deployed whole into `.agents/plugins/` unless its entry carries a `skills:` selection, which deploys the selected skills flat; and that the selection `["*"]` matches no skill.
Any requirement whose discharge depends on this fact SHALL name it explicitly, and SHALL lose its discharge once the violation below is observed.

**Evidence**: apm `claude_plugins/admission.py:465-511` (`plan_native_claude_plugin` returns no plan at project scope when a skill subset is set); on 2026-11-23 mattpocock/skills without a selection was deployed to `.agents/plugins/` and `tdd` was missing from `.claude/skills`; with its 25 skills listed the composition was byte-identical to apm 0.36.0's; `skills: ["*"]` failed with "Skill selection matched no available skills".

#### Scenario: Observed on 2026-11-23

- **WHEN** the composition ran with apm 0.38.0 and mattpocock/skills listed by skill name
- **THEN** its 25 skills were deployed flat and nothing was written under `.agents/plugins/`

#### Scenario: apm deploys a selected plugin whole, or accepts the wildcard

- **WHEN** an apm release deploys a dependency with a `skills:` selection into `.agents/plugins/`, or `["*"]` starts selecting every skill
- **THEN** this assumption is void, and the `third-party-plugin-dependency` requirement `A whole-plugin upstream is consumed through a skill list equal to its plugin manifest` loses its discharge (for the wildcard case, the explicit list may be replaced)

### Requirement: A215 — apm requires a version in every package manifest and inherits it into its marketplace files

It is true of apm 0.38.0 that installing a package whose `apm.yml` has no `version` fails ("Missing required field 'version'"), and that `apm pack` fills a local marketplace entry's version and description from the package's own `apm.yml` when the marketplace entry omits them, and omits `version` only when the package has none.
Any requirement whose discharge depends on this fact SHALL name it explicitly, and SHALL lose its discharge once the violation below is observed.

**Evidence**: on 2026-11-23 the composition with every group's `version: 0.0.0` removed failed for `agent-orchestration-and-meta-tooling` with that message; `apm pack --offline` over the root manifest with `packages[].version` removed wrote a file identical (`jq -S`) to the committed one; apm `marketplace/output_mappers.py` (`_apply_field_with_precedence` for local entries).

#### Scenario: Observed on 2026-11-23

- **WHEN** the composition and `apm pack` ran with apm 0.38.0 over the manifests described above
- **THEN** the version-free group failed to install and the version-free marketplace entries inherited `0.0.0`

#### Scenario: apm drops the requirement or stops inheriting

- **WHEN** an apm release installs a version-free package, or stops filling marketplace entries from the package manifest
- **THEN** this assumption is void, and the `skill-marketplace-publication-interface` requirement `Each fact about a plugin group is authored once` is re-examined: the group version may become removable, or the published list may need its descriptions back

### Requirement: A216 — apm's marketplace client reads the first of three marketplace files and accepts Claude-only fields

It is true of apm 0.38.0 and 0.36.0 that `apm marketplace add` reads `marketplace.json`, then `.github/plugin/marketplace.json`, then `.claude-plugin/marketplace.json`, the first present; that it reads both the Claude and the Copilot formats; and that it ignores the entry fields `skills` and `strict` and a missing `version`.
Any requirement whose discharge depends on this fact SHALL name it explicitly, and SHALL lose its discharge once the violation below is observed.

**Evidence**: apm `marketplace/client.py:97-101`; on 2026-11-23 a served copy of this repository holding only the Claude-ready `.claude-plugin/marketplace.json` registered 18 plugins and installed `nix-build-operations` and `planning-and-development` flat and byte-identical, and a copy also holding a Copilot-profile `.github/plugin/marketplace.json` registered 22 and installed those two and `agent-context-core`, under apm 0.38.0 and 0.36.0 (served through a `url.insteadOf` rewrite of an `https://` URL; apm refuses `file://` marketplace sources' relative paths).

#### Scenario: Observed on 2026-11-23

- **WHEN** a third-party consumer registered each served copy and installed from it
- **THEN** registration and installs succeeded as described

#### Scenario: apm changes its probe order or rejects the fields

- **WHEN** an apm release prefers `.claude-plugin/marketplace.json`, stops reading the Copilot format, or rejects an entry with `skills`, `strict` or no `version`
- **THEN** this assumption is void, and the `skill-marketplace-publication` requirement `An apm consumer installs every published plugin group` loses its discharge until the consumer checks pass again

### Requirement: A217 — Claude Code installs a manifest-free marketplace entry whose skills sit in a hidden directory

It is true of Claude Code 2.1.330 that a marketplace entry with a relative `source`, no `.claude-plugin/plugin.json` in that directory, `strict: false` and `skills: ["./.apm/skills"]` validates, installs, and lists each child of `.apm/skills/` as a skill of the plugin, from a local directory marketplace and offline.
Any requirement whose discharge depends on this fact SHALL name it explicitly, and SHALL lose its discharge once the violation below is observed.

**Documentation**: Claude's documentation describes a manifest-free entry as the plugin's manifest (`plugins/marketplace-reference.md:105`) and requires `skills` paths to start with `./` (`plugins-reference.md:392-394`), but neither allows nor forbids a hidden directory there; this assumption is an observation, not a documented promise.

**Evidence**: on 2026-11-23, with an isolated configuration directory, all 18 entries of the generated marketplace installed and listed 126 skills, each plugin's names equal to its `.apm/skills` children; the same install-and-count ran inside a Linux build sandbox on magnetite with no network.

#### Scenario: Observed on 2026-11-23

- **WHEN** Claude Code 2.1.330 installed every entry of the generated marketplace
- **THEN** every plugin listed exactly its group's skills

#### Scenario: Claude Code stops honouring the entry

- **WHEN** a Claude Code release rejects a hidden `skills` path or a manifest-free entry, or installs such a plugin with fewer skills than its directory holds
- **THEN** this assumption is void, and the `skill-marketplace-publication` requirement `A Claude user installs every skill group with all its first-party skills` loses its discharge until the skills move to the documented `skills/` layout

### Requirement: A218 — The Claude desktop app installs the same entries as Claude Code

It is true of the Claude desktop app as the operator used it on 2026-11-23 that its Add marketplace dialog, given a public GitHub repository name, lists, installs and shows every skill of a plugin laid out as in A217, at `modules/home/ai/plugins/<group>` depth.
Any requirement whose discharge depends on this fact SHALL name it explicitly, and SHALL lose its discharge once the violation below is observed.

**Documentation**: the desktop documentation names `skills/<name>/SKILL.md` and a `.claude-plugin/plugin.json` manifest for Chat and Cowork (`plugins/build.md:21,39,56`); this assumption is an observation, not a documented promise.

**Evidence**: the operator's test of `cameronraysmith/skills-marketplace-test` (commit 2542b08) on 2026-11-23: all three layouts tested, including the manifest-free entry with `skills: ["./.apm/skills"]` and `strict: false`, listed, installed and showed five skills. On the real repository with Claude 6.28899.6 (2f5fc5, 2026-11-20T22:01:14Z) on 2026-11-23, the operator added `cameronraysmith/vanixiets` (`main` 43a4ac7d): the dialog listed exactly 18 plugins, none `agent-context-*`, and the installed `nix-build-operations` and `planning-and-development` showed 5 and 16 skills, every skill of their `.apm/skills`. After those installs, on stibnite, `~/.claude/plugins/installed_plugins.json` and `enabledPlugins` in `~/.claude/settings.json` held no vanixiets entry: the desktop installs did not appear in Claude Code's plugin state on that machine (observed, not explained).

#### Scenario: Observed on 2026-11-23

- **WHEN** the operator added the test marketplace in the desktop app and installed each layout's plugin
- **THEN** each showed all five skills

#### Scenario: The desktop app stops honouring the entry

- **WHEN** a desktop release, re-tested by hand with the fixture repository `cameronraysmith/skills-marketplace-test` (add it as a marketplace, install each layout's plugin, count its skills), lists fewer skills than the plugin directory holds or refuses the entry
- **THEN** this assumption is void, and the `skill-marketplace-publication` requirement `A Claude user installs every skill group with all its first-party skills` loses its discharge for the desktop app

### Requirement: A219 — Claude versions a plugin without a declared version by its commit

It is true of Claude Code that a plugin's version comes from its plugin manifest, else its marketplace entry, else the commit of the marketplace's git source (`plugins/marketplace-reference.md`), so a plugin with no version anywhere installs at, and updates to, the marketplace's current commit, while `0.0.0` pins it.
Any requirement whose discharge depends on this fact SHALL name it explicitly, and SHALL lose its discharge once the violation below is observed.

**Evidence**: Claude Code 2.1.330 on 2026-11-23: a git marketplace without versions installed at `6832a512c2fe`, a local git checkout at `9b57e72a448b`, an entry with `0.0.0` at `0.0.0`, and an entry without version beside a root `plugin.json` with `0.0.0` at `0.0.0` (the root manifest was read although the documentation names only `.claude-plugin/plugin.json`). The desktop app, Claude 6.28899.6 (2f5fc5) on 2026-11-23: the `but` rename (#4188) reached `main` after the operator added `cameronraysmith/vanixiets`, and the version-free `version-control-and-forge` entry then offered "v2 · current" and "v1" in its Files tab, v2 holding `/.apm/skills/but/SKILL.md` (21 files): the app took a content change without any version change and numbered the versions itself (screenshot seen by the orchestrator). The "Version 0.0.0" on that page is the `but` skill's own frontmatter, not a marketplace version.

#### Scenario: Observed on 2026-11-23

- **WHEN** Claude Code installed plugins from marketplaces with and without versions
- **THEN** the installed versions were as listed

#### Scenario: Claude stops following commits

- **WHEN** a Claude release installs a version-free plugin as `unknown` from a git marketplace, or, re-tested by hand with `cameronraysmith/skills-marketplace-test` (push a skill edit without a version change, then check for updates), does not offer the newer commit as an update
- **THEN** this assumption is void, and the `skill-marketplace-publication` requirement `A Claude user follows the published skills without versions` loses its discharge

### Requirement: A220 — The skills CLI finds skills in the directories a root skills.sh.json lists

It is true of the skills CLI 1.9.0 that it walks each directory listed in the `paths` of a repository's root `skills.sh.json` three levels deep and lists every skill found there by its frontmatter `name`.
Any requirement whose discharge depends on this fact SHALL name it explicitly, and SHALL lose its discharge once the violation below is observed.

**Evidence**: the vercel-labs/skills 57217cf source (`src/skills.ts:261-319`, `src/constants.ts:6`, `src/skills-sh-config.ts:20-61`: the search root at depth 1, the default containers, and the `skills.sh.json` paths to depth 3) and the 2026-11-23 runs (`logs/s5-npx-skills-proof-*`).

#### Scenario: Observed on 2026-11-23

- **WHEN** skills 1.9.0 listed this repository at `main` c8b35ddb, which has no `skills.sh.json`, then a copy with the generated file listing the 18 `.apm/skills` directories, then a copy whose file lists only `./modules/home/ai/plugins`
- **THEN** it found no skills, then the 126 first-party skills and none of the remote ones (`--skill openspec-explore` installed that skill alone), then no skills

#### Scenario: The skills CLI stops reading skills.sh.json

- **WHEN** a skills release pinned by `llm-agents` lists fewer skills than the first-party directories in the `skills-cli-discovery` check, or `npx skills add cameronraysmith/vanixiets --list` from GitHub does
- **THEN** this assumption is void, and the `skill-marketplace-publication` requirement `A skills CLI user installs each first-party skill` loses its discharge
