## MODIFIED Requirements

### Requirement: A missing reference repository can be requested without a person

A participating account SHALL be able to make an acquisition request for a reference repository the reference tree lacks, to refresh or deepen one it holds, or to make one it holds readable at a revision it holds, and the writer SHALL carry out a well-formed acquisition request without a person intervening.
An acquisition request SHALL NOT let the requesting account choose anything beyond which reference repository is acted on, which of those actions applies, and which revision.

#### Scenario: A participating account needs a reference repository the tree lacks

- **WHEN** a participating account makes an acquisition request for a reference repository absent from the reference tree
- **THEN** the reference repository appears in the reference tree, written by the writer, and is readable by every participating account on that host

#### Scenario: A participating account needs to read a reference repository at an earlier revision

- **WHEN** a participating account makes an acquisition request to make a reference repository readable at a revision whose history the reference tree holds but whose content it lacks
- **THEN** every participating account on that host can read the reference repository at that revision without any further write to the reference tree

#### Scenario: An acquisition request asks for more than adding, refreshing or deepening

- **WHEN** an acquisition request names anything beyond a reference repository, whether to add, refresh, deepen or make it readable at a revision, and that revision
- **THEN** the writer refuses it and the reference tree is unchanged

## ADDED Requirements

### Requirement: Every participating account reads a reference repository as committed

On each sharing host, every participating account and the writer SHALL see each reference repository's files as committed upstream, including a file the upstream stores outside the repository's history, which every account SHALL see as the committed reference to that content rather than the content itself, so that reading a reference repository writes nothing and refreshing it is never refused as overwriting a change nobody made.

#### Scenario: A reference repository stores a large file outside its history

- **WHEN** a participating account reads a reference repository whose upstream stores a file outside the repository's history, and the writer later refreshes that repository after the upstream changed that file
- **THEN** the account sees the file's committed reference, reports no change to it, writes nothing to the reference tree, and the refresh succeeds
