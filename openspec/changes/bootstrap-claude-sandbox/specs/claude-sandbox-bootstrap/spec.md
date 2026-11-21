## ADDED Requirements

### Requirement: Context and skills from the first prompt

A cloud session started on the operator's cloud environment SHALL have the user context in its first prompt and every skill of the skill corpus listed there.
Providing them SHALL take no work in that cloud session beyond reading files already in its container.

#### Scenario: A session starts from the environment snapshot

- **WHEN** a cloud session starts on the operator's cloud environment from its environment snapshot
- **THEN** its first prompt shows the user context and lists the skill corpus before any tool runs

#### Scenario: A session starts in a freshly built container

- **WHEN** a cloud session starts in a container whose setup step has just run
- **THEN** its first prompt shows the user context and lists the skill corpus

### Requirement: One closure defines the environment

The cloud environment's setup step SHALL name one closure, the cloud-session activation package, by store path, with its source revision as provenance.
Everything a session receives from this repository SHALL come from that closure, and the setup step SHALL NOT evaluate a flake.
The setup step SHALL be renewed at least every 30 days, while the binary cache still holds the closure.

#### Scenario: Two sessions on one closure

- **WHEN** two cloud sessions start on cloud environments whose setup steps name the same store path
- **THEN** they receive the same user context, skill corpus and required tools

#### Scenario: Updating the environment

- **WHEN** the operator updates what cloud sessions receive
- **THEN** the only change to the cloud environment is its setup step, replaced by the one generated for a new pinned revision, which names that revision's closure

#### Scenario: A month without changes

- **WHEN** 30 days pass since the setup step was last renewed
- **THEN** the setup step has been regenerated and swapped, so its closure is still in the fleet's binary cache

### Requirement: Setup never prevents a session from starting

The setup step SHALL finish with success whatever part of the bootstrap run fails, so that a cloud session always starts.
A failed part SHALL leave the cloud session with less than intended and a bootstrap report saying so, never without a session.

#### Scenario: The binary cache lacks what the bootstrap run needs

- **WHEN** the fleet's binary cache does not hold what the pinned revision's bootstrap run would install
- **THEN** the setup step still succeeds, the cloud session starts, and its bootstrap report names what degraded and why

### Requirement: Setup finishes within the snapshot window

The setup step SHALL finish within 360 seconds, the longest duration measured to be snapshotted, so that later cloud sessions start from the environment snapshot.

#### Scenario: The setup step is timed

- **WHEN** the setup step runs in a freshly built container on a revision whose closure the fleet's binary cache holds
- **THEN** it finishes within 360 seconds and the next cloud session on that cloud environment starts without running it

### Requirement: Additive to harness-owned state

A bootstrap run SHALL only add files beside the harness-owned state.
It SHALL NOT modify, replace or remove any harness-owned state, including the platform's launcher settings, its hooks, its synced skills and the Claude Code program.

#### Scenario: Harness-owned state is compared

- **WHEN** the harness-owned state of a container is compared before and after a bootstrap run
- **THEN** it is unchanged

### Requirement: No secret at rest

No secret SHALL appear in the setup step's text, in the environment snapshot or in any bootstrap report.
A secret a cloud session uses SHALL reach the container only after the cloud session starts, and SHALL NOT be written to the container's disk.

#### Scenario: The snapshot and reports are searched

- **WHEN** the setup step, the environment snapshot and every bootstrap report are searched for the operator's credentials
- **THEN** none is found

### Requirement: Every bootstrap run reports

Every bootstrap run SHALL leave a bootstrap report in the container that the operator can read from the cloud session.
The report SHALL state the pinned revision, what was installed, what degraded and why, and how long each part took.

#### Scenario: A degraded run

- **WHEN** a bootstrap run cannot install part of what its pinned revision defines
- **THEN** its bootstrap report names that part, the reason, and the pinned revision

#### Scenario: A successful run

- **WHEN** a bootstrap run installs everything its pinned revision defines
- **THEN** its bootstrap report lists what was installed and how long each part took

### Requirement: Attached repositories get their repository context

Each attached repository that defines a repository context SHALL have that repository context generated in its working tree when the cloud session starts.
Generating it SHALL make no request the GitHub gate refuses.

#### Scenario: A session with an attached repository

- **WHEN** a cloud session starts with an attached repository that defines a repository context
- **THEN** that repository's repository context is present in its working tree before the agent's first command, and no request was refused by the GitHub gate

### Requirement: User context is not repeated in repository context

Where the user context is present, an attached repository's generated repository context SHALL contain only that repository's own instructions and SHALL NOT repeat the user context.

#### Scenario: Both tiers are present

- **WHEN** a cloud session has the user context and an attached repository's repository context was generated in it
- **THEN** no instruction of the user context appears in that repository context

### Requirement: One operator action per development iteration

Trying a candidate pinned revision SHALL take one operator action, starting a controller session with a prompt, plus one approval card for each setup step change.
The results SHALL come back as bootstrap reports the controller session reads.

#### Scenario: A candidate revision is tried

- **WHEN** the operator tries a candidate pinned revision
- **THEN** the operator starts one controller session and accepts its approval cards, and does nothing else by hand to obtain the candidate's bootstrap reports

### Requirement: Idempotent setup without external side effects

Running the setup step any number of times in a container SHALL leave the same result as running it once.
A bootstrap run SHALL change nothing outside its container.

#### Scenario: The setup step runs twice

- **WHEN** the setup step runs twice for one setup step change, in the cloud session's container and in the one that builds the environment snapshot
- **THEN** both containers end in the same state, and neither run pushed, published, uploaded or changed anything outside its container

### Requirement: Required tools present

Every required tool of the skill corpus that can work in a cloud session SHALL run by name in the agent's shell.
These include openspec, linear, jj, git, gh, ghq, mergify, jq, jaq, rg, fd, duckdb, nix, just, playwright-cli, typst, d2, mmdc, pandoc and uv.
Tools that need an interactive terminal, a clipboard or the fleet's overlay network, and bd and but, are excluded.

#### Scenario: Required tools are called by name

- **WHEN** the agent's shell runs each included required tool's version command by bare name
- **THEN** every one of them runs

### Requirement: One source for agent context and skills

The user context, skill corpus and repository context a cloud session receives SHALL be produced by the same definitions in this repository that produce them for the operator's other agents, so that a change to one reaches both.

#### Scenario: A context fragment changes

- **WHEN** an instruction in the user context is changed in this repository and a new pinned revision is used
- **THEN** cloud sessions and the operator's other agents receive the same changed instruction

### Requirement: Linear skills in cloud sessions

A cloud session SHALL be able to use the skills that act on the operator's Linear workspaces.
The credential that enables this SHALL open only those workspaces' keys, and the operator SHALL be able to revoke it without changing any other secret.

#### Scenario: A Linear skill runs

- **WHEN** a cloud session started with the operator's credential configured runs a Linear skill's workspace check
- **THEN** the check confirms the operator's Linear workspace

#### Scenario: The credential is revoked

- **WHEN** the operator revokes the cloud sessions' credential
- **THEN** new cloud sessions can no longer read the Linear workspaces' keys, and every other secret is unchanged
