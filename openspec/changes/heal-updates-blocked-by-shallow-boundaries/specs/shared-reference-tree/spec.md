## ADDED Requirements

### Requirement: A refresh that fails with history held in part before upstream's says so and how to repair it

When a refresh fails and a commit the reference repository holds without that commit's history lies between its branch and upstream's, the writer's answer SHALL say so, SHALL name a repair that hides no history the reference repository holds, and SHALL say that a refresh still refused a fast-forward after that repair, without the same words, failed because upstream rewrote its branch; the refresh SHALL change nothing in the reference repository beyond what the failed refresh itself did.

#### Scenario: Upstream's branch moves onto a commit held without its history

- **WHEN** a participating account asks for a refresh of a reference repository whose branch upstream has moved past a commit held without its history
- **THEN** the refresh fails as before, and the answer names that commit and `ghq-sync --deepen 1000000 <path>` followed by `ghq-sync -u <path>`

#### Scenario: The named repair

- **WHEN** a participating account runs the named repair
- **THEN** every branch of the reference repository reaches every commit it reached before, and the next refresh succeeds unless upstream rewrote its branch

#### Scenario: Upstream rewrote its branch through history held in part

- **WHEN** a refresh fails because upstream rewrote its branch onto history passing a commit held without its history
- **THEN** the answer names that commit and the repair as above; after the repair the refresh still fails with git's fast-forward refusal, its answer without those words, which tells the reader that upstream rewrote its branch

#### Scenario: Upstream rewrote its branch elsewhere

- **WHEN** a refresh fails because upstream rewrote its branch, and no commit held without its history lies between the two branches
- **THEN** the answer says nothing of history held in part
