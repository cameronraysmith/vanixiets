## ADDED Requirements

### Requirement: Linear Method ontology spine

The PM hub SHALL adopt the Linear Method ontology as its spine: Initiative greater than Project greater than Milestone greater than Issue, with Cycles as an orthogonal scheduling overlay rather than a decomposition layer.
The hub SHALL synthesize this ontology from the Linear Method and CCPM references rather than copying their text, and SHALL NOT adopt CCPM's .claude/prds plus .claude/epics filesystem or its bash scripts.
The hub SHALL document the issue-body convention that the Linear issue body carries only a TL;DR, Deliverables, and Acceptance Criteria, with status and progress in fields and comments and never in the body.

#### Scenario: ontology partitions the PM design space
- **WHEN** a human reasons about project or issue structure
- **THEN** the hub presents Initiative, Project, Milestone, and Issue as the decomposition spine with Cycles as an orthogonal overlay

#### Scenario: issue body excludes status
- **WHEN** an issue body is authored
- **THEN** it contains only TL;DR, Deliverables, and Acceptance Criteria, and status and progress live in Linear fields and comments

#### Scenario: synthesis without copied text
- **WHEN** the hub documents Linear Method or CCPM principles
- **THEN** it synthesizes the principles in original prose and does not copy upstream text, and does not introduce a parallel .claude/prds or .claude/epics filesystem

### Requirement: Four flat one-level reference areas

The PM hub SHALL organize its references as a single flat one-level references directory whose four sub-areas (linear, github, beads, method) are expressed as filename prefixes and presented via a Contents table grouped by prefix, with no two-level nesting.
The method sub-area SHALL be a committed area (not optional) covering the Initiative-Project-Milestone-Issue ontology, Cycles-as-overlay, issue sizing and estimation, triage versus backlog versus deferral, and the SYNC and NOSYNC section markers.
The beads sub-area SHALL document beads as an optional local drill-down sublayer and the Manual-mode task ledger, and SHALL route to the existing issues-beads skill rather than duplicating it.

#### Scenario: references stay one level deep
- **WHEN** the hub's references are laid out
- **THEN** all four sub-areas live as filename prefixes in one flat references directory, presented via a prefix-grouped Contents table, with no nested subdirectories

#### Scenario: method area is committed
- **WHEN** a human consults the method sub-area
- **THEN** it covers the ontology, Cycles-as-overlay, sizing and estimation, triage and backlog and deferral, and the SYNC and NOSYNC markers

#### Scenario: beads area documents the optional sublayer
- **WHEN** a human consults the beads sub-area
- **THEN** it presents beads as the optional local drill-down sublayer and the Manual-mode task ledger, routing to issues-beads without duplicating it

#### Scenario: github area frames the terminal artifact
- **WHEN** a human consults the github sub-area
- **THEN** it documents the PR, buildbot, and Mergify surface as one realization of the terminal artifact (the archived OpenSpec change)

### Requirement: Linear workspace safety gate keyed on confirmed credentials

The PM hub SHALL encode the Linear workspace safety gate as the hardest constraint: never propose a Linear mutation until the correct personal-versus-work workspace is confirmed via linear auth whoami (optionally linear auth whoami --workspace <slug>).
Every mutation SHALL pass an explicit --workspace <slug> or rely on the confirmed credentials.toml default key.
The gate SHALL NOT be keyed on LINEAR_WORKSPACE, and the hub SHALL NOT run mutating linear auth commands because credentials are nix-managed and immutable, rendered into a read-only (0400) inline credentials.toml (an OS-keyring mode is supported but not in use).

#### Scenario: mutation blocked before whoami confirmation
- **WHEN** a Linear mutation is proposed before linear auth whoami confirms the workspace
- **THEN** the gate refuses the mutation until the correct workspace is confirmed

#### Scenario: explicit workspace flag on every mutation
- **WHEN** a confirmed mutation is issued
- **THEN** it passes an explicit --workspace <slug> or relies on the confirmed credentials.toml default key

#### Scenario: gate ignores LINEAR_WORKSPACE
- **WHEN** the workspace identity is established
- **THEN** the gate keys on linear auth whoami plus an explicit --workspace rather than on the env-overridable LINEAR_WORKSPACE, and never runs a mutating linear auth command
