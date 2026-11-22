# claude-sandbox-bootstrap Specification

## Purpose

What a Claude Code cloud session started on the operator's cloud environment has from its first prompt (user context, skill corpus, required tools, repository context, Linear credentials), how that environment is defined and renewed from one closure of this repository, and the bounds on its setup step: it never blocks a session, finishes inside the snapshot window, is idempotent and additive, keeps no secret at rest, and always reports.

## Requirements

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

Each environment snapshot SHALL hold one closure of this repository and record its commit.
Unless the operator pins one closure, it SHALL be the closure of the newest of the main branch's 5 newest commits that the binary cache already holds.
The setup step SHALL only fetch and activate a closure, never build one, and its text SHALL NOT change with new commits.
While pinned, the setup step SHALL be renewed at least every 30 days.

#### Scenario: Two sessions on one closure

- **WHEN** two cloud sessions start from environment snapshots that hold the same closure
- **THEN** they receive the same user context, skill corpus and required tools

#### Scenario: Updating the environment

- **WHEN** a commit on the main branch changes what cloud sessions receive and the binary cache holds its closure
- **THEN** the next environment snapshot of a cloud environment that is not pinned holds that closure, with no change to the setup step

#### Scenario: A month without changes

- **WHEN** 30 days pass since a pinned setup step was last renewed
- **THEN** the setup step has been renewed to name a newer closure, so its closure is still in the fleet's binary cache; a cloud environment that is not pinned needs no renewal

#### Scenario: The newest commit is not yet published

- **WHEN** an environment snapshot is made after a commit reaches the main branch and before the binary cache holds its closure
- **THEN** the snapshot holds the closure of the newest earlier commit, among the 5 newest, that the binary cache holds, and its bootstrap report names the commit used, its distance from the newest and why each newer commit was skipped

#### Scenario: None of the 5 newest commits is published

- **WHEN** the binary cache holds the closure of none of the main branch's 5 newest commits
- **THEN** the cloud session still starts, without the profile, and its bootstrap report says so; this risk is accepted

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

The user context, skill corpus and repository context a cloud session receives SHALL be the same ones this repository generates for the operator's other agents, so that a change to one reaches both.

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

### Requirement: Sessions report how far behind the main branch they are

At each start, a cloud session SHALL record in its bootstrap report its closure's commit, how far that commit was behind the main branch's newest commit when the environment snapshot was made, and whether the main branch has moved on since.
Recording it SHALL change nothing else: the session SHALL keep the closure of its environment snapshot.

#### Scenario: A session behind the main branch

- **WHEN** a cloud session starts from an environment snapshot made two commits behind the main branch's newest commit, and the main branch has moved on since
- **THEN** its bootstrap report records the distance two and that the main branch has moved on, and the session runs that snapshot's closure

### Requirement: Every input source stays in the binary cache

Every change to this repository's flake inputs SHALL leave the input source of every flake input in the fleet's binary cache, so that a cloud session can follow the main branch without fetching any input source through the GitHub gate.

#### Scenario: A lock change lands

- **WHEN** a commit that changes the flake inputs reaches the main branch and the build service has published its outputs
- **THEN** the binary cache holds every input source of that commit's flake inputs
