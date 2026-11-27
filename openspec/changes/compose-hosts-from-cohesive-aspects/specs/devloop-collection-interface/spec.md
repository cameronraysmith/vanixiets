## MODIFIED Requirements

### Requirement: Each activation appends one deploy record

`flake.modules.nixos.deploy-record`, as `system.activationScripts.deploy-record` without dry-activation support, and `flake.modules.darwin.deploy-record`, added last to `system.activationScripts.postActivation` at `flake.lib.activationOrder.deployRecord`, SHALL append to `/var/log/deploy-record.jsonl`, mode `0644`, one JSON line per activation with the fields the scenario "The record's fields" lists.

**Discharged by**: `devloop-reconcile`'s comparison of deploy records, resting on world assumptions A49 and A350; `vmTests.x86_64-linux.devloop-ingest`'s switch case; the operator's recorded deploy and boot lines at deploy.

#### Scenario: The record's fields

- **WHEN** an activation appends its line
- **THEN** it holds `host` the evaluated `networking.hostName`, `closure` the activated `$systemConfig`, `previous_closure` the target of `/run/current-system` when it exists, else absent, and `ts` from `date -u +%Y-%m-%dT%H:%M:%SZ`

#### Scenario: A darwin snippet follows the record

- **WHEN** `checks.x86_64-linux.deploy-record-order` judges its case `darwinSnippetAfterRecord`, a darwin script with another `postActivation` snippet between the record and the relink
- **THEN** `flake.lib.deployRecordObligations` finds exactly one problem, and on a real host the `darwin-<host>` machine check fails naming `deployRecordObligations`

#### Scenario: A node switches to a second system

- **WHEN** `devloop-ingest` switches its node from one system to another, the second its configuration extended by `extendModules`
- **THEN** exactly one line is appended, naming the second as `closure` and the first as `previous_closure`

#### Scenario: The configuration switch cannot run in a container

- **WHEN** the switch case finds no `switch-to-configuration` in the container's second system, as nixpkgs' nspawn container module builds it
- **THEN** the case runs that system's activation script, which sets `$systemConfig`, instead, and the limitation is recorded with the run

