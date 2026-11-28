## ADDED Requirements

### Requirement: A refresh that history held in part blocks says why and how to repair it

When a refresh fails because upstream's branch has moved past a commit the reference repository holds without that commit's history, the writer's answer SHALL say so and SHALL name a repair that hides no history the reference repository holds, and the refresh SHALL change nothing in the reference repository beyond what the failed refresh itself did.

#### Scenario: Upstream's branch moves onto a commit held without its history

- **WHEN** a participating account asks for a refresh of a reference repository whose branch upstream has moved past a commit held without its history
- **THEN** the refresh fails as before, and the answer says why and names `ghq-sync --deepen 1000000 <path>` followed by `ghq-sync -u <path>`

#### Scenario: The named repair

- **WHEN** a participating account runs the named repair
- **THEN** every branch of the reference repository reaches every commit it reached before, and the next refresh succeeds

#### Scenario: A refresh that fails for another reason

- **WHEN** a refresh fails because upstream rewrote its branch
- **THEN** the answer says nothing of history held in part
