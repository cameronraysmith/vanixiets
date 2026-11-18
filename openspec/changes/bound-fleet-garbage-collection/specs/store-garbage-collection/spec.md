## ADDED Requirements

### Requirement: Every scheduled store cleanup ends within two hours

Each host's scheduled store cleanup SHALL end within two hours of starting, whether or not it obtained the store lock, so that a cleanup waiting on a store lock another process holds never stops the following day's cleanup from running.

**Discharged by**: `store-garbage-collection-interface` requirements `harmonia-gc's systemd unit is bounded by its start timeout` and `harmonia-gc's launchd job runs under timeout with its output in one log`, resting on world assumptions `A148 — Nix's store lock is waited on without a limit`, `A149 — launchd sets no time limit on a job's run` and `A150 — Stopping a store cleanup leaves the software store consistent`.

#### Scenario: another process holds the store lock

- **WHEN** a host's scheduled store cleanup starts while another process holds the store lock and keeps holding it
- **THEN** the cleanup ends no later than two hours after it started, the host records it as a failed run, and the next day's cleanup starts at its scheduled time

#### Scenario: a cleanup is ended while deleting

- **WHEN** a store cleanup is ended by its two-hour limit while it is removing software from the software store
- **THEN** the software store holds no partly removed software, the store lock is free once the cleanup has ended, and the next cleanup removes what the ended one did not reach

#### Scenario: the limit is removed from a host's configuration

- **WHEN** any host's configuration declares a scheduled store cleanup without the two-hour limit
- **THEN** that host's configuration check fails before it can be deployed

### Requirement: A darwin host keeps a readable record of each store cleanup

Each darwin host SHALL keep, in one log on that host, every log record its scheduled store cleanup emits, including that it is waiting for the store lock and how much it freed.

**Discharged by**: `store-garbage-collection-interface` requirement `harmonia-gc's launchd job runs under timeout with its output in one log`.

#### Scenario: the operator reads a laptop's last cleanup

- **WHEN** the operator reads the cleanup log on a darwin host the morning after its scheduled store cleanup
- **THEN** the log shows whether the cleanup waited for the store lock, whether it completed, and how much free space it made

#### Scenario: the log destination is removed from a host's configuration

- **WHEN** a darwin host's configuration declares its scheduled store cleanup without sending both its output and its errors to the cleanup log
- **THEN** that host's configuration check fails before it can be deployed

### Requirement: Each host keeps its rollback window

Each darwin host's store cleanup SHALL keep that host's generations for a rollback window of 7 days, and each NixOS host's for 10 days; every host SHALL keep its current generation and any software added to its software store within the last day regardless of age.

**Discharged by**: `store-garbage-collection-interface` requirement `The rollback window is set per platform`.

#### Scenario: a laptop rolls back

- **WHEN** a person on a darwin host asks to roll back to a generation made 6 days earlier
- **THEN** that generation is still present

#### Scenario: an old laptop generation is removed

- **WHEN** a darwin host's store cleanup runs and a generation other than the current one is older than 7 days
- **THEN** that generation is removed and the software only it needed becomes removable

### Requirement: A person's own generations expire after fourteen days without a second store cleanup

The generations of each person's personal environment on a host SHALL expire once they are older than 14 days, the current one excepted, and the host's scheduled store cleanup SHALL remain the only process that removes software from that host's software store.

**Discharged by**: `store-garbage-collection-interface` requirement `home-manager expires generations without collecting`, resting on world assumption `A151 — A store cleanup running as root does not see a person's own generations`.

#### Scenario: a person's generations age

- **WHEN** a person's personal environment on a host has generations older than 14 days and the daily expiry has run
- **THEN** those generations, except the current one, are gone, and the next scheduled store cleanup frees the software only they needed

#### Scenario: the expiry runs

- **WHEN** the daily expiry of a person's generations runs
- **THEN** it takes no store lock and removes no software from the software store

### Requirement: magnetite keeps a warm software store

magnetite's scheduled store cleanup SHALL stop once 40% of the file system holding its software store is free space, keeping the rest of the build service's recent outputs, and SHALL not compact the store's database afterwards.

**Discharged by**: `store-garbage-collection-interface` requirement `magnetite's cleanup stops at a free-space target and skips the vacuum`, resting on world assumption `A152 — A quota-bounded ZFS dataset reports its quota as its size`.

#### Scenario: magnetite's store has more than enough free space

- **WHEN** magnetite's scheduled store cleanup starts with more than 40% of its software store's file system free
- **THEN** it removes nothing, and outputs built the day before stay available to the build service

#### Scenario: magnetite's store is fuller than its target

- **WHEN** magnetite's scheduled store cleanup starts with less than 40% free space
- **THEN** it removes software until 40% is free and stops

### Requirement: A store cleanup that runs past its expected duration reaches a person

When a scheduled store cleanup on a host whose signals are collected is still running one hour after it started, an alert SHALL reach a person, and a cleanup ended by its two-hour limit SHALL reach a person as a failed run.

**Discharged by**: `store-garbage-collection-interface` requirement `An overrun rule reports a cleanup still running after an hour`, together with the existing failed-job and failed-unit alerts of `fleet-alerting`.

#### Scenario: a cleanup is stuck on the store lock

- **WHEN** a host's scheduled store cleanup has been waiting for the store lock for 70 minutes
- **THEN** one overrun alert for that host has reached a person

#### Scenario: a cleanup finishes in normal time

- **WHEN** a host's scheduled store cleanup ends 50 minutes after it started
- **THEN** no overrun alert is sent for it
