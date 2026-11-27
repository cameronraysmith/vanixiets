## ADDED Requirements

### Requirement: A refreshed or deepened reference repository shows what each commit it gained changed

When the writer refreshes, deepens or fetches the tags of a reference repository whose file contents the reference tree holds only in part, every participating account SHALL be able to read what each commit thereby brought into its branches' history changed, with no further acquisition request, unless the writer's answer says it could not make them readable then.
Adding a reference repository SHALL take no more history and no more file contents than before.

#### Scenario: A reference repository is refreshed

- **WHEN** the writer refreshes a reference repository and the commits it brings in are few enough to make readable then
- **THEN** every participating account reads what each of those commits changed, with no further acquisition request, and the reference tree is written by the writer alone

#### Scenario: A refresh brings in more than the writer makes readable at once

- **WHEN** the writer refreshes a reference repository and the commits it brings in are too many to make readable then
- **THEN** the refresh succeeds, and the writer's answer says that their changes were not made readable and names the acquisition request that makes a revision readable

#### Scenario: A reference repository is deepened

- **WHEN** the writer deepens a reference repository
- **THEN** every participating account reads what each commit the deepening brought in changed, except the deepest commits the reference repository now holds, with no further acquisition request

#### Scenario: A deepening also brings in what upstream gained

- **WHEN** the writer deepens a reference repository whose upstream has gained commits since its last refresh, and the deepening brings those commits in as well
- **THEN** every participating account reads what each of those commits changed, as for a refresh, with no further acquisition request

#### Scenario: Making the changes readable fails

- **WHEN** the writer refreshes a reference repository and cannot fetch the file contents that make its new commits' changes readable, or a later step of the same acquisition request fails
- **THEN** the refresh's own outcome is unchanged by the failure to make them readable, and the writer's answer says whether making them readable succeeded or failed

#### Scenario: A reference repository is added

- **WHEN** a participating account makes an acquisition request for a reference repository absent from the reference tree
- **THEN** the reference repository arrives with the same history and the same file contents as before this requirement, in no more time

### Requirement: A tag's commit fetched without its history is readable once requested

When the writer fetches a reference repository's tags, a tag's commit it fetches without that commit's history SHALL be excepted from what the writer makes readable: what that commit changed SHALL become readable once an acquisition request makes that tag readable.

#### Scenario: Tags are fetched

- **WHEN** the writer fetches a reference repository's tags, bringing in the upstream branch's new commits and a tag's commit without its history
- **THEN** every participating account reads what each of the branch's new commits changed, and reading what the tag's commit changed fails at once until an acquisition request makes that tag readable

### Requirement: A read that needs content the reference tree lacks fails at once

A participating account's read of a reference repository that needs file contents the reference tree lacks SHALL fail at once, naming the missing content, SHALL NOT attempt to write to the reference tree, and SHALL succeed once the account's acquisition requests have made each revision the read compares readable.

#### Scenario: A participating account reads what an older commit changed

- **WHEN** a participating account reads what a commit changed whose file contents, or whose parents' file contents, the reference tree lacks
- **THEN** the read fails at once, naming the missing content, without any refusal of a write, and after acquisition requests making that commit and each of its parents readable the same read succeeds
