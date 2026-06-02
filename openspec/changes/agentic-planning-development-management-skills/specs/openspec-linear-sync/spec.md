## ADDED Requirements

### Requirement: Drive Linear exclusively through linear-cli

The sync overlay SHALL drive every Linear operation through the linear-cli binary and SHALL recommend against the Linear MCP, which is disabled in this environment.
It SHALL compose the bundled linear-cli skill for the verbs and carry only link and sync policy itself.
Because linear-cli lacks --json on most create and update paths, the overlay SHALL capture entity ids via stdout parsing or a follow-up view, and SHALL force non-interactive automation (issue create --no-interactive, all required flags present, file-based content flags over inline), reserving linear api (GraphQL) only for fields the document subcommand cannot set.

#### Scenario: MCP is recommended against
- **WHEN** a Linear operation is needed
- **THEN** the overlay drives it through linear-cli and recommends against the disabled Linear MCP

#### Scenario: id capture without --json
- **WHEN** a create or update path lacks --json
- **THEN** the overlay captures the entity id via stdout parsing or a follow-up view, and uses linear api only for reparenting a document or reading back a freshly created entity's structured id

#### Scenario: composition target is a single linear-cli skill
- **WHEN** the overlay composes the verbs
- **THEN** it targets the single linear-cli skill directory (sixteen reference subfiles), accepting that this user-scoped composition target is present only for crs58 as the sole operator

### Requirement: Bind four forward transitions plus re-queue with invariants

The sync overlay SHALL bind the eight-artifact superpowers-bridge lifecycle to Linear's canonical states via four forward transitions, the shared re-queue, and the two terminal exits, covering every Linear state with none skipped.
proposal.md creation SHALL drive Backlog to Todo; the first tasks.md checked checkbox SHALL drive Todo to In Progress; verify.md creation SHALL drive In Progress to In Review; the successful archive step SHALL drive In Review to Done.
The overlay SHALL hold the invariants that the issue is never moved to Done before archive, that status, validate, sync, and edit operations never move the issue to Done, that comments stay at most two sentences, and that the archive ordering is readiness then sync deltas then archive then mirror then Done.

#### Scenario: transitions anchored on observable file milestones
- **WHEN** any of proposal.md, the first tasks.md checked checkbox, verify.md, or the archived change directory appears
- **THEN** the corresponding forward transition fires a short best-effort non-blocking comment

#### Scenario: never Done before archive
- **WHEN** a status, validate, sync, or edit operation runs
- **THEN** it never moves the issue to Done, and Done binds to archive rather than to the step6 PR

#### Scenario: state resolved by name not type
- **WHEN** a transition resolves the target Linear state
- **THEN** it passes the team's Linear state name (for example In Review) via linear-cli rather than the workflow-state type, because In Progress and In Review share the started type, and it degrades gracefully for teams lacking an In Review state by staying In Progress until Done

#### Scenario: re-queue fires on FAIL or rejection under bounded retries
- **WHEN** verify.md records a checked-FAIL Overall Decision or a sub-gate human rejection occurs
- **THEN** the In Review to In Progress re-queue fires, governed by the bounded-retries policy with escalation to the human PM layer on exhaustion

### Requirement: Local sync ledger as authoritative current-phase signal

The sync overlay SHALL maintain a minimal local sync ledger adjacent to the bridge, persisted as fields in openspec/linear.yaml, recording last_synced_state, last_synced_at, a review-round counter, and a short attempt log.
Local milestone-file existence (proposal.md, the first tasks.md checked checkbox, verify.md, the archived change directory) SHALL be the authoritative current-phase signal, with the Linear state treated as a best-effort projection that a catch-up reconciliation step corrects rather than trusting.
The overlay SHALL fire each transition only when the resolved Linear state is strictly behind the local milestone (a no-op if already at or past the target), post each milestone comment at most once per crossing, increment the review-round counter once per re-queue and reset it on archive, and record dropped best-effort writes in the attempt log so a never-attempted transition is distinguishable from a failed one.

#### Scenario: local milestone files are authoritative
- **WHEN** the local phase and the Linear state disagree
- **THEN** the catch-up reconciliation computes local phase from the milestone files, reads the Linear state, and fires the catch-up transition rather than assuming Linear is current

#### Scenario: idempotent re-runs
- **WHEN** apply and verify are re-invoked and a transition's target is already at or past the resolved Linear state
- **THEN** the transition is a no-op and the milestone comment is not re-posted, preventing re-runs from spamming the team-visible comment surface

#### Scenario: bounded-retries counter lives locally
- **WHEN** a re-queue occurs
- **THEN** the review-round counter in openspec/linear.yaml increments once per In Review to In Progress crossing, resets when the change archives, and on exhaustion posts a single escalation comment to the human PM layer and stops firing automatic re-queues

#### Scenario: attempt log distinguishes dropped from failed writes
- **WHEN** a best-effort Linear write is dropped
- **THEN** the attempt log records it so a human can see Linear is stale and tell a never-attempted transition from a failed one

### Requirement: Two-location story-to-change binding with write-before-read ordering

The sync overlay SHALL be the write-owner of the primary cross-reference binding from Linear story to OpenSpec change, persisted in two locations: openspec/linear.yaml and the proposal.md linear_story_* frontmatter.
At the Backlog to Todo bind it SHALL write linear_story_* into proposal.md frontmatter and write or update openspec/linear.yaml at the same bind, and SHALL write the documents map at archive.
Because apply reads the frontmatter, the write-before-read ordering is load-bearing and the bind step SHALL precede any apply read; in Manual mode, where there is no proposal.md, the Linear binding SHALL live in a beads issue field instead.

#### Scenario: bind writes both locations
- **WHEN** the Backlog to Todo bind occurs
- **THEN** linear_story_* is written into proposal.md frontmatter and openspec/linear.yaml is written or updated at the same bind

#### Scenario: bind precedes apply read
- **WHEN** apply reads the linear_story_* frontmatter
- **THEN** the sync overlay's bind step has already written it, honoring write-before-read ordering

#### Scenario: Manual mode binds via a beads field
- **WHEN** the issue is in Manual mode and has no proposal.md
- **THEN** the Linear binding lives in a beads issue field rather than in proposal.md frontmatter or openspec/linear.yaml

### Requirement: Archive-time document UPSERT with mirroring

The sync overlay SHALL run an archive-time document UPSERT entirely via the CLI: linear document list --project <p> --json to find the document by the deterministic title OpenSpec: <capability>, then linear document update <id> --title <t> --content-file <f> if matched, else linear document create --project <p> --title <t> --content-file <f> so the document is always created already-parented.
The document body SHALL be a disposable mirror fully replaced on each archive so re-archives update rather than duplicate, and archive-time SHALL be the only time spec content is mirrored to Linear.
The overlay SHALL never copy design.md or tasks.md to Linear.

#### Scenario: UPSERT matches by deterministic title
- **WHEN** the archive-time UPSERT runs
- **THEN** it lists documents by project, matches the title OpenSpec: <capability>, and updates the matched document or creates a new already-parented one

#### Scenario: re-archive updates rather than duplicates
- **WHEN** a change is re-archived
- **THEN** the disposable mirror body is fully replaced and no duplicate document is created

#### Scenario: design and tasks are never mirrored
- **WHEN** the document body is composed
- **THEN** it mirrors only the spec content and never copies design.md or tasks.md to Linear

### Requirement: One-question setup, never-auto-select, best-effort non-blocking

The sync overlay SHALL use a one-question setup with an explicit no-label option, SHALL never auto-select a Backlog candidate, SHALL mirror only at archive time, and SHALL make all Linear writes after setup best-effort and non-blocking so a failed or skipped Linear write never blocks local progress.

#### Scenario: setup asks one question with a no-label escape
- **WHEN** the overlay is set up for a change
- **THEN** it asks a single setup question and offers an explicit no-label option

#### Scenario: never auto-select a backlog candidate
- **WHEN** a Backlog candidate could be inferred
- **THEN** the overlay never auto-selects it and defers to the human

#### Scenario: writes are non-blocking
- **WHEN** a Linear write fails or is skipped after setup
- **THEN** local progress continues unblocked and the dropped write is recorded in the attempt log
