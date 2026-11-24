## Purpose

This capability (stratum: `behavioral`) states what people outside the fleet receive from this repository's skill marketplace: an apm consumer installs every published plugin group; a Claude user installs every skill group with all its first-party skills and follows the published skills without versions; a skills CLI user installs each first-party skill; and publication never changes what the fleet's hosts receive.

## ADDED Requirements

### Requirement: An apm consumer installs every published plugin group

An apm consumer who registers the marketplace from the main branch MUST be able to install each plugin group the marketplace lists, and each installed plugin group MUST give that consumer every skill the plugin group contains as a separately named skill, together with the skills of its declared dependencies.
The marketplace SHALL list every plugin group of the skill corpus, the plugin groups of agent instructions included.
This requirement relies on A213, A214 and A216.

#### Scenario: A plugin group of skills is installed

- **WHEN** an apm consumer registers the marketplace and installs one plugin group of skills
- **THEN** each skill of that plugin group is present for the consumer under its own name, identical to the skill as committed on the main branch

#### Scenario: A plugin group of agent instructions is installed

- **WHEN** an apm consumer installs one of the plugin groups of agent instructions
- **THEN** the consumer receives that plugin group's instructions, ready to be composed into the consumer's own repository context

#### Scenario: A plugin group is added to the skill corpus

- **WHEN** a new plugin group reaches the main branch
- **THEN** the marketplace lists it in the same commit, or the commit is refused before it reaches the main branch

---

### Requirement: A Claude user installs every skill group with all its first-party skills

A Claude user who adds the marketplace by this repository's forge name MUST be offered every plugin group that contains skills, and installing one MUST give the Claude user every skill that the plugin group itself contains.
The marketplace offered to a Claude user SHALL NOT offer the plugin groups of agent instructions, and SHALL NOT promise the skills that a plugin group takes from a dependency.
This requirement relies on A217 and A218.

#### Scenario: A skill group is installed in a Claude app

- **WHEN** a Claude user installs one plugin group from the marketplace
- **THEN** the Claude app lists exactly that plugin group's own skills, each under the plugin group's name

#### Scenario: A dependency's skills are wanted

- **WHEN** a Claude user wants the skills a plugin group takes from a dependency
- **THEN** the marketplace does not install it, and the Claude user installs it from wherever its upstream publishes it

---

### Requirement: A Claude user follows the published skills without versions

A Claude user's installed plugin groups MUST follow the main branch: an update offered by the Claude app SHALL bring the plugin group's skills as of the newest commit, and no plugin group SHALL carry a version that holds an install at an older commit.
This requirement relies on A219.

#### Scenario: A skill changes on the main branch

- **WHEN** a commit that changes a skill reaches the main branch and a Claude user updates the plugin group that contains it
- **THEN** the Claude user receives the changed skill

---

### Requirement: Publication never changes what the fleet's hosts receive

Changing how the marketplace is published MUST NOT change any skill the skill corpus delivers to the fleet's hosts.

#### Scenario: The published layout changes

- **WHEN** a change to the marketplace's files reaches the main branch
- **THEN** every skill delivered to a host after its next activation is identical to the one delivered before

---

### Requirement: A skills CLI user installs each first-party skill

A user of the skills CLI who adds this repository by its forge name MUST be offered every first-party skill under its own name, and SHALL be able to install any one of them alone.
The skills CLI SHALL NOT be offered the skills a plugin group takes from a dependency.
This requirement relies on A220.

#### Scenario: The skills are listed

- **WHEN** a skills CLI user lists the skills of this repository
- **THEN** every first-party skill is listed once under its name, and no skill of a dependency is listed

#### Scenario: One skill is selected

- **WHEN** a skills CLI user installs one skill by name
- **THEN** only that skill is installed, identical to the skill as committed on the main branch
