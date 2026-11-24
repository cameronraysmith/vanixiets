## ADDED Requirements

### Requirement: A whole-plugin upstream is consumed through a skill list equal to its plugin manifest

A remote apm dependency on a repository that publishes a Claude plugin manifest (today `mattpocock/skills`) SHALL be declared with a `skills:` list naming exactly the skill directories that upstream's `.claude-plugin/plugin.json` lists at the declared commit, so that apm deploys them flat rather than the whole plugin.
The fixed-output download SHALL fail when the declared list differs from upstream's.

**Relies on**: A214.

#### Trust boundary

The download's build establishes that the declared list equals upstream's manifest at the declared commit. It does not establish that every listed skill is wanted, or that upstream's list is complete with respect to its repository.

#### Scenario: the list diverges from upstream

- **WHEN** the declared commit is bumped to one whose plugin manifest adds or removes a skill and the `skills:` list is not updated to match, or a name is removed from the list
- **THEN** the build of the fixed-output download fails, naming the skills listed upstream but not declared, or declared but not listed upstream

#### Scenario: the selection is removed

- **WHEN** the `skills:` list is removed from the entry
- **THEN** the composition fails because the plugin's skills are missing from the flat trees
