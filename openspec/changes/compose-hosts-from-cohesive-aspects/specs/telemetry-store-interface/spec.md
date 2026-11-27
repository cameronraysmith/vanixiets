## MODIFIED Requirements

### Requirement: The telemetry store and the collector run inside a declared envelope

The machine SHALL run `greptimedb.service` under the static user `greptimedb` with `MemoryHigh=3G`, `MemoryMax=4G`, `MemorySwapMax=0`, `OOMScoreAdjust=500` and a lower `CPUWeight`, magnetite's collector with `MemoryMax=512M` and `OOMScoreAdjust=300`, below the build service's evaluator at 900, and other NixOS agents' collectors with `MemoryMax=256M`.
The dataset `zroot/root/greptimedb` SHALL carry `quota=16G`, `reservation=12G` and `com.sun:auto-snapshot=false`, applied or asserted at boot.

**Discharged by**: the evaluation-time envelope check (R7.1) with its mutants, the agent role's limiter assertion on every NixOS host without the ingress role, `checks.x86_64-linux.otel-collector-darwin`'s clauses over stibnite's evaluated darwin fragment with the mutants `agentLimiterRaised`, `processSpikeRaised`, `c5LimitsSwapped` and `c5AgentLimitChanged`, `checks.x86_64-linux.otel-envelope`'s darwin memory cases with the mutants `c5WrongPid`, `c5ReadsRss` and `c5UnreadablePasses`, the hourly envelope regulator, the on-demand OOM-order test, and the operator's 24-hour memory measurement on stibnite, resting on world assumption `A70 — macOS top prints a process's physical footprint as unversioned text to an unprivileged account`.

#### Scenario: A darwin host's agent is bounded in memory

- **WHEN** a darwin host's agent, `otelcol-process` and `otel-envelope` are configured
- **THEN** On a darwin host, which launchd bounds in no memory, the agent SHALL run with a 150 MiB `memory_limiter` and 30 MiB spike and `otelcol-process` with 64 MiB and 16 MiB, and the darwin `otel-envelope` SHALL fail above 256 MiB and 128 MiB of physical footprint, the kernel's own accounting, which unlike the resident size excludes the mapped binary's clean file-backed pages.

#### Scenario: The evaluation-time envelope check runs with its mutants

- **WHEN** the evaluation-time envelope check (R7.1) runs against magnetite's configuration and against each of its mutants, which drop `MemoryMax`, swap the store's and the collector's `OOMScoreAdjust`, and remove the restart on rotation
- **THEN** it passes on magnetite's configuration, where it finds `MemoryHigh` below `MemoryMax`, `MemorySwapMax=0`, the evaluator's `oom_score_adj` above the store's and the store's above the collector's, and the collector's `memory_limiter` below the collector's `MemoryMax`, and it fails on every mutant; the listener, protocol, user-provider and usage-report properties are the store module's assertions, and the memory knobs ADR-007 names are literals of the store module whose effect R7.2 and the OOM-order test regulate

#### Scenario: Another agent's envelope is evaluated

- **WHEN** a NixOS host without the ingress role is evaluated
- **THEN** its collector runs with `MemoryMax=256M` and a `memory_limiter` of 150 MiB with a 30 MiB spike allowance, and the agent role's assertion fails the evaluation when the limiter is not below `MemoryMax`, as an override of pyrite's limiter to 300 MiB shows

#### Scenario: A darwin host's envelope is evaluated

- **WHEN** `checks.x86_64-linux.otel-collector-darwin` reads stibnite's evaluated darwin fragment
- **THEN** the agent's `memory_limiter` is 150 MiB with a 30 MiB spike and `otelcol-process`'s 64 MiB with a 16 MiB spike, each pipeline of both begins with `memory_limiter`, and the limits the fragment gives the darwin `otel-envelope` are 268,435,456 B for `org.nixos.otelcol` and 134,217,728 B for `org.nixos.otelcol-process`, whose failing and passing cases `fleet-ingress-interface` requirement `otel-envelope regulates each agent from its own collector` states; the mutants `agentLimiterRaised`, `processSpikeRaised`, `c5LimitsSwapped` and `c5AgentLimitChanged` each fail the check

#### Scenario: The darwin collectors' memory is measured

- **WHEN** the launchd alert rules are about to ship, and again once stibnite has collected for 24 hours
- **THEN** before the rules ship the operator confirms or changes the darwin `otel-envelope`'s two limits from a physical-footprint reading of each collector and the envelope's passing runs, and over the 24 hours the operator records both collectors' maximum physical footprint, and the maximum after a sleep when the window holds one

#### Scenario: The hourly envelope regulator finds the store over its envelope

- **WHEN** `greptimedb-envelope` runs as `regulator` and the store's cgroup `memory.stat` `anon` has reached `GREPTIMEDB_ENVELOPE_ANON_MAX_BYTES`, which is set from `MemoryHigh`, its `memory.events` `high`, `oom_kill` or `max` counters have increased within one store invocation, or, across invocations, the journal for `greptimedb.service` records a kernel OOM kill (`MESSAGE_ID=fe6faa94e7774663a0da52717891d8ef`) or `NRestarts` has increased (R7.2), the dataset's used space has reached 80% of its quota or the quota or reservation differs from its declared value (R7.3), or the summed SST size in `information_schema.region_statistics` has reached 50 GiB (R6.2)
- **THEN** the unit fails

#### Scenario: The memory regulator is shown able to fail

- **WHEN** at first activation the anonymous-memory threshold is set below the observed value and `greptimedb-envelope` runs
- **THEN** the unit fails, and the operator records the failed run

#### Scenario: Page cache alone does not fail the memory regulator

- **WHEN** the envelope's build-time rehearsal runs the R7.2 regulator over `memory.events` and `memory.stat` recorded on magnetite, with a threshold above `anon` but below `memory.peak`, and then with `memory.events` `high` raised within the same invocation
- **THEN** the first run passes and the second fails naming `high`, its baseline and its new value

#### Scenario: The OOM kill order is exercised

- **WHEN** the on-demand QEMU VM test on pyrite exhausts memory with processes at `OOMScoreAdjust` 900, 500 and 300
- **THEN** the kernel kills them in that order in host-wide OOM kills whose victim lines carry `,global_oom,`, each of the three units logs systemd's OOM-kill message, and `greptimedb.service` ends with result `oom-kill`

#### Scenario: The dataset properties are applied at boot and confirmed on magnetite

- **WHEN** magnetite boots, and when the operator reads the dataset's properties at first activation
- **THEN** `zfs-set-root-greptimedb-quota`, `zfs-set-root-greptimedb-reservation` and `zfs-assert-root-greptimedb-noautosnap`, generated from the greptimedb entries of `flake.lib.zfsBootInvariants.magnetite`, whose values the envelope check finds in `disko.nix` as well, `disko.nix` remaining an independent install-time declaration, succeed or fail visibly, and the operator records `quota`, `reservation` and `com.sun:auto-snapshot` on `zroot/root/greptimedb`

