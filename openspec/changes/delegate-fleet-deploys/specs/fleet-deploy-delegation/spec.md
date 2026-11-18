## ADDED Requirements

### Requirement: A requester can have a host redeployed at a merged commit and learn the outcome

A requester's agent session SHALL be able, without the operator present and without holding any machine key, to have the deployer deploy one deployable host at one merged commit, and SHALL receive in the same exchange the deploy's log and one outcome that also covers the host's health check after a settle period.

**Discharged by**: `fleet-deploy-delegation-interface` requirements `The deployer answers only its forced command`, `Each request ends in one exit status` and `The deployer deploys with clan to the commit's own target`, resting on world assumptions `A155 — A host's machine key opens every secret meant for that host` and `A156 — clan sends a host its keys at every deploy and checks every host first`.

#### Scenario: a session deploys magnetite at the head of the main branch
- **WHEN** an agent session of cameron's sends a deploy request for magnetite naming no commit while stibnite is asleep
- **THEN** the deployer deploys magnetite at the main branch's newest commit, and the session receives the log and an outcome stating that magnetite answers, runs the deployed configuration and reports no failed service

#### Scenario: a deploy activates but a service fails
- **WHEN** a deploy activates on its host and one of the host's services has failed by the end of the settle period
- **THEN** the requester receives an outcome stating the host is deployed but unhealthy, naming the failed service, and the host keeps the deployed configuration

#### Scenario: a session holds no machine key
- **WHEN** any file readable by a requester's agent session is tried as a reader of any host's machine key
- **THEN** no machine key is recovered

### Requirement: Only merged commits are deployed

The deployer SHALL deploy a host only at a merged commit, taken from the repository by the deployer itself, and SHALL deploy a NixOS host only from a configuration the build service has already built.

**Discharged by**: `fleet-deploy-delegation-interface` requirement `Only merged commits are deployed, and a NixOS host only from a built closure`, resting on world assumption `A158 — The build service builds darwin configurations only when a Mac is reachable`.

#### Scenario: a request names an unmerged commit
- **WHEN** a deploy request names a commit that the main branch does not contain
- **THEN** the deploy request is refused, no host is contacted, and the refusal is recorded and announced

#### Scenario: a NixOS configuration was not built
- **WHEN** a deploy request names a merged commit whose configuration for the named NixOS host is not in the binary cache
- **THEN** the deploy request is refused without contacting the host

### Requirement: A requester deploys only the hosts allowed to them

The deployer SHALL deploy a host for a requester only when that host is a deployable host the requester may reach. A deployable host that belongs to no one SHALL be reachable by every operator (cameron and janettesmith). A deployable host that belongs to a person SHALL be reachable by that person and by cameron as administrator. Today cameron reaches argentum, cinnabar, magnetite, pyrite and rosegold, and janettesmith reaches cinnabar, magnetite and rosegold.

**Discharged by**: `fleet-deploy-delegation-interface` requirement `Reach is the role policy over each machine's primary user`.

#### Scenario: janettesmith asks for pyrite
- **WHEN** a deploy request sent with janettesmith's request credential names pyrite, which belongs to cameron
- **THEN** the deploy request is refused, and the refusal is recorded and announced with janettesmith as requester

#### Scenario: janettesmith asks for magnetite
- **WHEN** a deploy request sent with janettesmith's request credential names magnetite, which belongs to no one
- **THEN** the deploy proceeds as for any other requester

#### Scenario: who may deploy what is widened
- **WHEN** a requester's reach is widened
- **THEN** the widening exists only as a change to the repository that passed the merge queue

### Requirement: Every deploy request is recorded and announced

The deployer SHALL record every deploy request it receives, refused or not, with its requester, the session the request names, the host, the commit, the closure when one was built, and the outcome; and SHALL post one message per deploy request to the notification service, with refusals, unhealthy outcomes and rollbacks posted at high priority.

**Discharged by**: `fleet-deploy-delegation-interface` requirement `Every request is written to the request log and posted to ntfy`.

#### Scenario: the operator reviews a day's deploys
- **WHEN** the operator reads the deployer's records and the deploy topic for a day
- **THEN** every deploy record a deployable host wrote that day for a deploy the deployer ran matches one recorded request, and every recorded request appears once on the topic

### Requirement: Two deploys of the same host never overlap

The deployer SHALL run at most one deploy per host at a time. A deploy request for a host already being deployed SHALL wait at most ten minutes and then end as busy, without contacting the host.

**Discharged by**: `fleet-deploy-delegation-interface` requirement `Deploys hold a per-host lock and one of two slots`.

#### Scenario: two sessions ask for the same host
- **WHEN** two deploy requests for pyrite arrive one second apart
- **THEN** the second waits until the first's outcome is sent before contacting pyrite, or ends as busy after ten minutes

### Requirement: A sleeping or unreachable host is reported without a deploy

When a deployable host is an unreachable host at the moment its deploy request is handled, the deployer SHALL end the request as unreachable, without sending anything to the host and without keeping the request for later.

**Discharged by**: `fleet-deploy-delegation-interface` requirement `Each request ends in one exit status`, resting on world assumption `A157 — Laptops are often unreachable`.

#### Scenario: rosegold is asleep
- **WHEN** a deploy request names rosegold while rosegold is asleep
- **THEN** the requester receives the outcome unreachable within one minute, and rosegold's configuration is unchanged when it wakes

### Requirement: A host that stops answering after a deploy returns to its previous configuration

A deployable host that stops answering the deployer after a deploy changes its configuration SHALL perform a rollback on its own within ten minutes of the change. A host that answers SHALL keep the deployed configuration whatever its health check finds.

**Discharged by**: `fleet-deploy-delegation-interface` requirement `The target arms its own rollback before the deploy`, resting on world assumption `A159 — A job handed to the host's service manager outlives the connection that started it`.

#### Scenario: a deploy cuts the connection
- **WHEN** a deploy changes a host's configuration and the deployer cannot reach the host for the five minutes that follow
- **THEN** the host returns to the configuration it ran before the deploy, writes a deploy record for that return, and the requester receives the outcome rolled back

#### Scenario: a deploy never activates
- **WHEN** a deploy fails before the host's configuration changes
- **THEN** the host keeps its configuration and makes no rollback

### Requirement: stibnite and blackphos are never deployed by the deployer

The deployer SHALL hold neither a key that reads stibnite's or blackphos's machine key nor a way to log in to either host, and SHALL refuse any deploy request that names either.

**Discharged by**: `fleet-deploy-delegation-interface` requirements `Deploy targets are derived from the enabled machines` and `Only deploy targets accept the deployer's key`; `secret-custody` requirement `The deployer reads only the machine keys of the hosts it deploys`.

#### Scenario: a request names stibnite
- **WHEN** a deploy request from cameron names stibnite
- **THEN** the request is refused before any connection, and the deployer's key recovers no secret meant for stibnite

### Requirement: A disabled host is never deployed by the deployer

A host the fleet has not provisioned SHALL NOT be a deployable host. It SHALL become one, with no other change, when it is provisioned again, unless it is stibnite or blackphos.

**Discharged by**: `fleet-deploy-delegation-interface` requirements `Deploy targets are derived from the enabled machines` and `Only deploy targets accept the deployer's key`.

#### Scenario: electrum is disabled
- **WHEN** a deploy request from cameron names electrum while electrum is not provisioned
- **THEN** the request is refused before any connection, and no account on electrum's configuration accepts the deployer's key

#### Scenario: galena is provisioned again
- **WHEN** galena is provisioned again
- **THEN** galena becomes a deployable host that every operator may reach, with no other change to who may deploy what
