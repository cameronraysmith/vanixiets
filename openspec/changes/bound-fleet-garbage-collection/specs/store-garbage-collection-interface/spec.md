## ADDED Requirements

### Requirement: harmonia-gc's systemd unit is bounded by its start timeout

On every NixOS host the evaluated `systemd.services.harmonia-gc.serviceConfig.TimeoutStartSec` SHALL equal `flake.lib.harmoniaGcObligations.bound`, which is `"2h"`, and the unit SHALL keep upstream's `Type = "oneshot"` and `ExecStart` built from `services.harmonia-dev.gc.argv`.

#### Scenario: a NixOS host's unit is evaluated

- **WHEN** the `nixos-<host>` check evaluates a host whose `harmonia-gc` unit has no `TimeoutStartSec`, or one other than `"2h"`
- **THEN** the check fails with a fleet-obligation message naming the host and `harmoniaGcObligations`

#### Scenario: the unit reaches its timeout

- **WHEN** `harmonia-gc.service` is still activating two hours after it started
- **THEN** systemd stops it and records the unit as failed

### Requirement: harmonia-gc's launchd job runs under timeout with its output in one log

On every darwin host the evaluated `launchd.daemons.harmonia-gc.serviceConfig.ProgramArguments` SHALL equal `[ "<coreutils>/bin/timeout" "2h" ]` followed by exactly the evaluated `services.harmonia-dev.gc.argv`, and its `StandardOutPath` and `StandardErrorPath` SHALL both equal `flake.lib.harmoniaGcObligations.logPath`, which is `/var/log/harmonia-gc.log`.

#### Scenario: a darwin host's job is evaluated

- **WHEN** the `darwin-<host>` check evaluates a host whose job has no `timeout` wrapper, a duration other than `"2h"`, a wrapper around a list other than `argv`, or a missing or different `StandardOutPath` or `StandardErrorPath`
- **THEN** the check fails with a fleet-obligation message naming the host and each problem

#### Scenario: the judge is run over fixtures

- **WHEN** `checks.x86_64-linux.harmonia-gc-obligations` is built
- **THEN** the judge finds no problem in the accepted NixOS unit and darwin job, and exactly one problem in each mutant: missing `TimeoutStartSec`, a different duration, no wrapper, a wrapper around a different argument list, no `StandardOutPath`, no `StandardErrorPath`, and a log path elsewhere

### Requirement: The rollback window is set per platform

`services.harmonia-dev.gc.deleteOlderThan` SHALL evaluate to `"7d"` on every darwin host and `"10d"` on every NixOS host, and `keepRecent` to `"1d"` on every host.

#### Scenario: the windows are evaluated

- **WHEN** `services.harmonia-dev.gc` is evaluated for stibnite and for cinnabar
- **THEN** stibnite's `argv` carries `7d` and cinnabar's carries `10d`, and both carry `1d` for `keepRecent`

### Requirement: home-manager expires generations without collecting

Every home-manager configuration the fleet builds SHALL set `services.home-manager.autoExpire.enable = true`, `timestamp = "-14 days"`, `frequency = "daily"` and `store.cleanup = false`.

#### Scenario: a person's home is evaluated

- **WHEN** a home-manager configuration in a darwin or NixOS host is evaluated
- **THEN** its `autoExpire` settings are as stated, and its launchd agent or systemd user timer runs `home-manager expire-generations` without `nix-collect-garbage`

### Requirement: magnetite's cleanup stops at a free-space target and skips the vacuum

magnetite's evaluated `services.harmonia-dev.gc` SHALL set `ensureFree = "40%"` and `noVacuum = true`, and its `argv` SHALL carry the corresponding free-space and no-vacuum arguments inside the bound unit.

#### Scenario: magnetite is evaluated

- **WHEN** magnetite's configuration is evaluated
- **THEN** `services.harmonia-dev.gc.argv` contains `40%` as its free-space argument and the no-vacuum flag, and `TimeoutStartSec` is `"2h"`

### Requirement: An overrun rule reports a cleanup still running after an hour

The fleet's alert rules SHALL contain `GarbageCollectionOverrun`, firing when `launchd_job_state{launchd_label="org.nixos.harmonia-gc", launchd_state="running"}` or `systemd_unit_state{systemd_unit_name="harmonia-gc.service", systemd_unit_active_state="activating"}` has been 1 for 60 minutes, with presence declared on the darwin and NixOS hosts.

#### Scenario: the rule's cases run

- **WHEN** the fleet-alert rule check runs its overrun cases
- **THEN** a series held at 1 for 70 minutes fires exactly one `GarbageCollectionOverrun` for its host, and one that returns to 0 at 50 minutes fires none

### Requirement: This capability states its own trust boundary

This capability SHALL state what its properties guarantee and what they do not.
It guarantees that the evaluated unit, job, settings and rule have the values above and that a configuration lacking them fails its check.
It does not guarantee that systemd, launchd, `timeout` or harmonia-gc honour those values at run time, that the process holding the store lock ever releases it, that a bounded run frees enough space, or that a signal reaches the telemetry store from a host whose collection is off.

#### Scenario: a guarantee about run time is sought

- **WHEN** a reader asks whether a host's cleanup actually ended within two hours
- **THEN** this capability answers no: only the host's own records (journal, launchd state, `/var/log/harmonia-gc.log`) and the overrun and failure alerts on collecting hosts show it
