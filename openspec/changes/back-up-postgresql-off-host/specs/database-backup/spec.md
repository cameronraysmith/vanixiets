## ADDED Requirements

### Requirement: Every unparked service's data is copied off its host every night

Every night, each host that keeps service data for a service that is not a parked service SHALL complete one backup run, which leaves an off-host copy of every such service's service data, together with the service logins those services use to reach it, in backup storage. As long as backup runs succeed, the recovery point SHALL be at most 24 hours.

**Discharged by**: `database-backup-interface` requirements `The dump units cover the backup set`, `Roles are dumped beside the databases`, `The backup job reaches its R2 repository`, `The backup job runs nightly and catches up a missed night`, `The backup job uploads exactly the dump files` and `A host's backup set is pinned by a fleet obligation`; relies on A160, A161 and A163.

#### Scenario: a night on magnetite

- **WHEN** a night passes on magnetite while gitea, gitea-mq, matrix-synapse, nixbot, niks3 and omnigent are not parked
- **THEN** backup storage holds a new off-host copy of each of those six services' service data and of their service logins, taken that night

#### Scenario: a service gains its own service data

- **WHEN** a host's configuration gives a service that is not parked its own service data and leaves it out of the backup run
- **THEN** that host is refused before deploy, with the service's name

### Requirement: An off-host copy holds that night's data

Each off-host copy SHALL hold the service data as it stood during that night's backup run, never an earlier night's, and a backup run that cannot take that night's copy of any one service SHALL fail as a whole rather than store an older copy in its place.

**Discharged by**: `database-backup-interface` requirements `The dump units have no timer of their own`, `The backup job starts every dump` and `A restore test drops and restores from the backup job's own copy`.

#### Scenario: data written after yesterday's copy

- **WHEN** a service writes a record after the previous night's backup run and before tonight's
- **THEN** tonight's off-host copy contains that record

#### Scenario: one service cannot be copied

- **WHEN** tonight's copy of one service's service data cannot be taken
- **THEN** the backup run fails, backup storage gains no copy labelled tonight, and the operator receives a failure notice naming that service's copy

### Requirement: A parked service's data is left out until the service is revived

A parked service's service data SHALL be left out of the backup run while the service is parked, and SHALL be included from the first backup run after the service is revived; the revival SHALL NOT be deployable while its service data is left out.

**Discharged by**: `database-backup-interface` requirement `A host's backup set is pinned by a fleet obligation`.

#### Scenario: cognee is parked

- **WHEN** a backup run happens on magnetite while cognee is a parked service
- **THEN** cognee's service data is not in the off-host copy, and no failure or alert is raised for its absence

#### Scenario: cognee is revived

- **WHEN** a configuration reviving cognee is checked before deploy
- **THEN** it is accepted only if cognee's service data is in the backup run

### Requirement: Off-host copies are kept on a schedule

backup storage SHALL keep, for each host, the off-host copies of the last 7 nights, one per week for the last 4 weeks and one per month for the last 6 months, and SHALL NOT lose a kept copy to anything but this schedule; every night a sample of the stored copies SHALL be read back and checked.

**Discharged by**: `database-backup-interface` requirements `The backup job keeps 7 daily, 4 weekly and 6 monthly copies and checks a tenth each night` and `The backup bucket deletes nothing by age`; relies on A163.

#### Scenario: after eight nights

- **WHEN** eight nights of backup runs have succeeded on magnetite
- **THEN** backup storage holds the last 7 nights' copies and the copy kept for the current week, and the oldest daily copy is gone

#### Scenario: a damaged copy

- **WHEN** a nightly read-back finds a stored copy damaged
- **THEN** that night's backup run fails and the operator receives a failure notice

### Requirement: Off-host copies survive the loss of the host and are readable only with the operator's secrets

An off-host copy SHALL remain restorable after the host that made it and its disk are lost, using only the repository and the operator's own identity, and SHALL be unreadable to anyone holding backup storage's objects without the secrets the operator keeps.

**Discharged by**: `database-backup-interface` requirements `The backup job's R2 key is a clan var of its own` and `The repository password is a generated clan var`; relies on A162 and A163.

#### Scenario: magnetite is gone

- **WHEN** the operator, on a workstation, with a checkout of the repository and their own identity and without magnetite, restores the latest copy of omnigent's service data
- **THEN** the restored data matches what omnigent held at that copy's time

#### Scenario: the objects alone

- **WHEN** someone holds backup storage's objects but none of the operator's secrets
- **THEN** they cannot read any service's data from them

### Requirement: Service data can be restored from an off-host copy

The operator SHALL be able to restore one service's service data, or every service's together with their service logins, from any kept off-host copy into an empty database instance, following a documented procedure that an automated test exercises.

**Discharged by**: `database-backup-interface` requirement `A restore test drops and restores from the backup job's own copy`; relies on A161.

#### Scenario: one service is restored

- **WHEN** the operator restores nixbot's service data from last night's copy by following the procedure
- **THEN** nixbot's service data afterwards matches last night's, and no other service's data changes

#### Scenario: the test restores

- **WHEN** the automated restore test runs after the backup run's mechanism changed
- **THEN** it passes only if every record written before the test's backup run, including one written after an older copy existed, is present after the restore

### Requirement: A failed backup run reaches the operator

A backup run that fails, and each service copy within it that fails, SHALL reach the operator as a failure notice naming the host and what failed, and each such failure SHALL be reported once through that path.

**Discharged by**: `database-backup-interface` requirement `Every backup unit is a notified unit`.

#### Scenario: the upload fails

- **WHEN** a backup run on magnetite cannot reach backup storage
- **THEN** the operator receives a failure notice for magnetite's backup run

### Requirement: An overdue backup reaches the operator

When a host that keeps service data has had no successful backup run for 36 hours, including a host that has never had one since backups were configured on it, an alert SHALL reach the operator naming the host, and SHALL resolve after the next successful backup run.

**Discharged by**: `database-backup-interface` requirements `A successful run writes its time to the textfile collector`, `A host that never ran a backup is seeded` and `PostgresqlBackupStale fires when the last success is 36 h old`.

#### Scenario: the schedule never fires

- **WHEN** magnetite's nightly backup run does not start for two nights
- **THEN** an alert naming magnetite and pointing at the restore procedure reaches the operator within 36 hours and 15 minutes of the last success

#### Scenario: a run succeeds again

- **WHEN** a backup run then succeeds on magnetite
- **THEN** the alert resolves

### Requirement: Local rollback stays available

A host's local rollback of its service data SHALL keep its current depth (four hourly, three daily and one weekly point), alongside the off-host copies, and the nightly copies' working files SHALL NOT be kept by local rollback.

**Discharged by**: `database-backup-interface` requirement `The dumps live on their own dataset with auto-snapshot off`; relies on A165.

#### Scenario: the depth is read

- **WHEN** magnetite's local rollback points are read after backups are configured
- **THEN** its service data still has four hourly, three daily and one weekly point, and none of them holds the nightly copies' working files
