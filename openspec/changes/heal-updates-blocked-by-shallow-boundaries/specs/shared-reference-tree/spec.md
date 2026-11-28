## ADDED Requirements

### Requirement: A refresh succeeds when upstream's branch has moved past history the reference repository holds only in part

When the writer refreshes a reference repository whose history stops at a commit that upstream's branch has since moved past, and that branch still contains the reference repository's branch, the refresh SHALL succeed, bringing the branch to upstream's tip, unless the missing history is larger than the writer fetches within one acquisition request.
The commits it brought in SHALL be readable as for any other refresh.

#### Scenario: Upstream's branch moves onto a tag's commit fetched without its history

- **WHEN** the writer has fetched a reference repository's tags, one of them without its history, upstream's branch later moves onto that tag's commit, and a participating account asks for a refresh
- **THEN** the refresh succeeds, the reference repository's branch is at upstream's tip, and every participating account reads what each commit the refresh brought in changed

#### Scenario: Upstream's branch moves past a commit fetched alone

- **WHEN** a reference repository holding its branch's whole history also holds a later commit of upstream's branch without that commit's history, upstream's branch moves past it, and a participating account asks for a refresh
- **THEN** the refresh succeeds, and the branch is at upstream's tip

#### Scenario: Later refreshes

- **WHEN** a refresh has succeeded this way and upstream's branch moves on
- **THEN** each later refresh succeeds as for any reference repository

### Requirement: Moving past history held in part never hides history a reference repository held

Every commit any of a reference repository's branches reached before a refresh or a deepening SHALL still be in that branch's history after it, whether it succeeds or not.

#### Scenario: A refresh moves past a commit fetched alone

- **WHEN** a refresh of a reference repository holding its branches' whole history succeeds past a commit it held without that commit's history
- **THEN** the refreshed branch, and every other branch, reaches every commit it reached before

#### Scenario: A deepen reaches history the reference repository already held

- **WHEN** a participating account deepens a reference repository whose history it holds in full below a commit fetched without its history, by exactly the number of commits between that commit and the branch's tip
- **THEN** the deepen succeeds and the branch, and every other branch, reaches every commit it reached before

### Requirement: A refresh that cannot move past history held in part leaves the reference repository as it was

When the writer cannot bring a reference repository's branch past a commit it holds without that commit's history, the refresh SHALL fail as before, the branches SHALL stay where they were, and the writer's answer SHALL say why.

#### Scenario: Upstream rewrote its branch

- **WHEN** upstream's branch no longer contains the reference repository's branch tip, and a participating account asks for a refresh
- **THEN** the refresh fails, the reference repository's branches stay where they were with every commit they reached, and the writer's answer says that upstream's branch does not contain the reference repository's

#### Scenario: The missing history is too large

- **WHEN** the history missing between the reference repository's branch and upstream's tip is larger than the writer fetches within one acquisition request
- **THEN** the refresh fails, the branches stay where they were, and the writer's answer says the missing history was too large
