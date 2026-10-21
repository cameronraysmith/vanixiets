## ADDED Requirements

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

## MODIFIED Requirements

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

### Requirement: Grounded vocabulary for behavioral requirements

The corpus SHALL provide one designation record per content term this repository's `behavioral`-stratum requirements use, recording the term, the sense in which it is used when a term carries more than one, the world phenomenon it denotes, and whether that phenomenon is world-only, shared with the machine, or machine-only.
A term found to denote two distinct phenomena within this repository's vocabulary SHALL be recorded as two rows rather than collapsed into one.
Fifteen terms carry two senses in this repository today and are disambiguated below rather than left to context: `session`, `package`, `policy`, `@`, `mutation`, `activation`, `probe`, `machine`, `host`, `interface`, `repository`, `build service`, `database`, `hostname`, and `evaluator`.

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
| writer | — | a person or service permitted to add series to a database | shared |
| reader | — | a person or service permitted to query a database's series | shared |
| store credential | — | a secret that authenticates a writer or reader to the telemetry store, or the telemetry store to its object storage | shared |
| object storage | — | the off-host bucket service in which the telemetry store keeps its series' data | shared |
| object data | — | the data the telemetry store keeps in object storage, where its series' data lives | shared |
| local state | — | the files a service keeps on its own host's disk | shared |
| unit | — | a supervised service or job on a host whose running state and restarts the host's supervisor records | shared |
| Omnigent worker | — | a service the fleet runs on behalf of one person to carry out Omnigent agent work, whose unit name carries that person's name | shared |
| person | — | a human being on whose behalf the fleet runs a service, or who uses one | world-only |
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

#### Scenario: A term resolves to two phenomena

- **WHEN** a content term used in a behavioral requirement denotes two distinct phenomena within this repository's vocabulary
- **THEN** this designation table records both senses as separate rows rather than collapsing them into one

#### Scenario: A behavioral requirement uses an unlisted term

- **WHEN** the designation lint finds a content noun in a behavioral requirement that resolves to no row in this table
- **THEN** the noun is either added here as a world or shared phenomenon, or the requirement using it is redirected toward the interface stratum, and neither disposition is applied silently

## RENAMED Requirements

- FROM: `### Requirement: A33 — The fleet's notification service on cinnabar is reachable over ZeroTier and accepts anonymous publishing`
- TO: `### Requirement: A33 — The fleet's notification service on cinnabar is reachable over ZeroTier and is the single delivery path`
