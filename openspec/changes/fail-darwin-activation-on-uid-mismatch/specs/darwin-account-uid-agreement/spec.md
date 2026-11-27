## ADDED Requirements

### Requirement: A host is not deployed while an attached account has a uid other than its recorded uid

A deploy of a nix-darwin host SHALL fail, before it changes anything on the host, when any attached account on that host exists with a uid other than its recorded uid, and the failure SHALL name the host and, for every such account, the account, its recorded uid and its uid. An attached account that does not yet exist on the host SHALL NOT fail the deploy. This relies on A370, A371 and A374.

#### Scenario: Every attached account has its recorded uid

- **WHEN** the operator deploys a nix-darwin host whose attached accounts all have their recorded uids
- **THEN** the deploy proceeds as it did before this requirement

#### Scenario: A recorded uid is wrong

- **WHEN** the operator deploys a nix-darwin host on which one attached account has a uid other than its recorded uid
- **THEN** the deploy fails before it changes anything on the host, naming the host, that account, its recorded uid and its uid, and no warning-and-continue outcome is possible

#### Scenario: Two recorded uids are wrong

- **WHEN** two attached accounts on one host have uids other than their recorded uids
- **THEN** one failed deploy names both accounts

#### Scenario: A new attached account

- **WHEN** the operator deploys a host on which an attached account does not yet exist
- **THEN** the deploy does not fail on that account, and the account is created with its recorded uid

#### Scenario: Another host

- **WHEN** one host's recorded uid is wrong
- **THEN** deploys of every other host are unaffected

### Requirement: The operator can run the comparison before a deploy, and a disagreement stops it before the host changes

The operator SHALL be able to run a deploy check on a nix-darwin host that makes the same uid comparison as a deploy, before any step that changes the host, and reports the same failure; on a disagreement it stops there with the host unchanged, and on agreement it goes on to activate the new configuration without setting the system profile. This relies on A373.

#### Scenario: A deploy check before the first deploy

- **WHEN** the operator runs a deploy check on a nix-darwin host after this requirement lands and before deploying it
- **THEN** if an attached account has a uid other than its record, it stops with the same named failure a deploy would report, before any step that changes the host; otherwise it exits 0 without an `ok` line, having activated the new configuration without setting the system profile
