---
title: Nix module tree
created: 2026-08-25
---

## Nix module tree

Every `.nix` file under this directory is a flake-parts module, discovered automatically by `import-tree` rather than listed in an import set.
Files are organised by aspect — what a module configures — rather than by host, and a module assigns `deferredModule` values into class-organised namespaces such as `flake.modules.darwin.*`, `flake.modules.homeManager.*`, and `flake.modules.nixos.*`.

The consequence worth knowing before editing here is that adding a file is enough to activate it.
There is no registration step, so a file placed in this tree takes effect on the next evaluation whether or not that was intended.
A file must also be tracked by git before a flake build can see it, because flake sources are git-tracked only and an untracked file is absent from the build rather than an error.

## Children

- `apps/` — flake apps, invoked as `nix run .#<name>`.
- `brand/` — shared brand assets and palette definitions.
- `checks/` — flake checks; see `preferences-nix-checks-architecture` for the check taxonomy.
- `clan/` — clan inventory, services, and machine registration.
- `containers/` — OCI image definitions.
- `darwin/` — nix-darwin system aspects.
- `devshells/` — development shells surfaced through direnv.
- `effects/` — deployment effects run outside the build sandbox.
- `home/` — home-manager aspects; the largest subtree, indexed by its own README.
- `lib/` — helper functions shared across modules.
- `machines/` — per-machine composition, binding aspects to hosts.
- `nixos/` — NixOS system aspects.
- `nixpkgs/` — channel selection and the overlay stack.
- `system/` — cross-platform system aspects.
- `terranix/` — cloud resource definitions rendered to OpenTofu.
- `vm-tests/` — on-demand runtime tests exported as `vmTests.<system>.<name>`, outside PR gating: QEMU VM tests needing `kvm`, and systemd-nspawn container tests needing `uid-range`.

Top-level files configure the flake itself: `flake-parts.nix`, `formatting.nix`, `systems.nix`, `debug.nix`, `kubernetes.nix`, and `nixidy.nix`.

## Shared CLI capabilities

`system/cli-tools/` exports `cli-unix`, `cli-archives`, `cli-network`, and their `cli-tools` aggregate under each of `flake.modules.nixos`, `flake.modules.darwin`, and `flake.modules.homeManager`.
Import the export matching the consumer's module class; package selection uses that consumer's `pkgs`.
The aggregate adds jq through its configured Home Manager module or as a system package.
These exports are opt-in: Omnigent workers import `homeManager.cli-tools`, while human terminal declarations remain independent.
Worker profiles prefer procps' `kill` over coreutils' overlapping executable, matching the existing supervisor PATH; the shared capabilities impose no worker-specific package priorities.
`checks.<system>.omnigent-worker-capabilities` makes two Home Manager evaluations of the worker module: a positive worker home, whose assertions, generated PATH order, ACP settings, tools, skills and harnesses it compares, and one composite invalid home whose failed assertions must equal the four guard messages.
Its build confirms that the harness executables exist in the generated profile and that `playwright-cli` reports its packaged version; it runs no CLI adapters, archive or file utilities, or workflow-tool smoke tests.

## On-demand VM tests

`nixbot.toml` evaluates `checks`, which nixbot scopes to `checks.x86_64-linux` and, best-effort, `checks.aarch64-darwin`; VM tests instead live under `vmTests` and are not part of pull-request coverage.
The independent `checks.x86_64-linux.zerotier-mss-clamp` structural check remains gated; it compares zerotier controller and peer role membership with `TCPMSS --set-mss 1300` in each nixosConfiguration's firewall commands.
The fleet-alerting checks are gated the same way and need no runtime host.
`checks.x86_64-linux.fleet-alert` runs `promtool` over the rules rendered by `nixos/fleet-alert/rules.nix`, replays canned store answers through a loopback fixture server against the evaluator in `nixos/fleet-alert.nix` with a recording `ntfy-send`, and compares `nixos/fleet-alert/transition.jq` with a Python reference model under a derandomized Hypothesis test.
It also runs cinnabar's dead-man against a loopback ntfy stand-in and relates cinnabar's ntfy access entries and dead-man settings to magnetite's evaluator: anonymous writes to the heartbeat and alert topics are refused, `alerter` may write both, and the dead-man polls the topic the evaluator posts its heartbeat to.
The token wiring of every `fleet-*` publisher, `observability-notify@` from `nixos/observability-notify.nix` included, is asserted by those modules and by magnetite's and cinnabar's configurations, so evaluating either host fails when a publisher does not load the `ntfy-alerter` token by path.
`checks.x86_64-linux.ntfy-provisioning` runs the `ntfy-alerter` generator from `nixos/ntfy-alerter.nix` and cinnabar's `ntfy-alerter-env` generator in the sandbox, and checks the rendered token, password hash and cinnabar's access entries before ntfy could refuse them at start.
ntfy's enforcement of the access entries, its rate limiting and the rules against real series are verified at deployment, not by these checks.
A runtime test builds only on a builder advertising the features its derivation requires: QEMU VM tests need `kvm`, which only Pyrite advertises, and systemd-nspawn container tests need `uid-range`, which only Magnetite advertises.
Run one from a checkout of the intended revision on that host, or from a dispatcher such as Stibnite, which routes it to the only builder with those features:

```sh
nix build .#vmTests.x86_64-linux.zerotier-mss-clamp-runtime   # Pyrite, kvm
nix build .#vmTests.x86_64-linux.omnigent-worker-isolation    # Pyrite, kvm
nix build .#vmTests.x86_64-linux.greptimedb-pipeline          # Magnetite, uid-range
nix build .#vmTests.x86_64-linux.greptimedb-oom-order         # Pyrite, kvm
```

`omnigent-worker-isolation` establishes the runtime wiring of the Omnigent worker guards that no evaluation-time check can reach: that the private-home precondition is `ExecStartPre` on the real `omnigent-host-<owner>.service` and that violating the home's privacy at runtime prevents `ExecStart`, that the Nix daemon resolves a worker as untrusted, that two workers have separate accounts and mutually unreadable private homes, and that the unit's `User`, `UMask`, `NoNewPrivileges` and SSH-agent unsetting hold in the spawned process.
It is not a sandbox and establishes nothing about confining hostile code inside a worker account, it stubs `ExecStart` so it is no evidence about the Omnigent client, it declares no credentials so the Clan-vars-to-sops delivery path is out of scope, and it says nothing about Stibnite or any Darwin host because there is no Darwin NixOS test node type.
Because it lives in this lane and runs only when a KVM-capable builder is reachable, it is on-demand evidence and must not be described as coverage; `checks.x86_64-linux.omnigent-worker-linux` remains the fleet-wide regulator for the precondition script's own behaviour.

`greptimedb-pipeline` runs the telemetry store and both collector roles in one systemd-nspawn container, with credentials written at boot by Magnetite's own `greptimedb-users` generator script and Magnetite's databases and TTLs.
It establishes that the store answers `/health` and serves its embedded dashboard at `/dashboard/`, that the schema oneshot creates each database with its TTL and that a re-run with a changed TTL changes it, that no or wrong credentials are answered 401 while a write-only read and a read-only write, by `perses` and by `regulator`, are answered 403, that an OTLP point crosses the forward and routing connectors into `fleet` only and reads back through PromQL with `x-greptime-db-name` carrying `host_name`, that the systemd receiver reaches D-Bus under `DynamicUser` and stores an `omnigent-host-<owner>` unit only under its alias, and that a point emitted while the store is stopped arrives after it restarts.
It uses local `File` storage, so it establishes nothing about R2, and a container shares the build host's kernel, so it establishes nothing about OOM behaviour.

`greptimedb-oom-order` runs one QEMU VM in which three equally growing memory consumers exhaust memory: one behind the real `nix-eval-jobs` lock wrapper, one inside `greptimedb.service`'s cgroup at that unit's `oom_score_adj`, and a collector stand-in at the collector's evaluated `OOMScoreAdjust`.
It establishes that the kernel kills them in the order evaluator (900), store (500), collector (300), that systemd records the OOM kill in each owning unit, and that `greptimedb.service` fails with result `oom-kill` under the default `OOMPolicy=stop`.
The collector's own unit is not the third consumer, because its `MemoryMax` of 512M makes a consumer inside its cgroup die to the cgroup's own OOM first; the VM has no swap, unlike Magnetite's zram.

The test requires `kvm` and `nixos-test` builder features and forces KVM acceleration rather than falling back to TCG.
Unavailable hardware is a build failure if this command is requested, not a passed or silently skipped test.
Leaving this output outside PR gating allows operators to run it when a suitable host is available without making PR CI depend on a laptop.
Registering Pyrite as a remote builder does not put this output back into PR gating; automatic opportunistic scheduling remains deferred.
Every NixOS host imports `system/kvm-declaration.nix` and states `declaredKvm.present` explicitly, because NixOS advertises `kvm` in `nix.settings.system-features` unconditionally and that claim is true only on Pyrite: Cinnabar, Electrum, Galena, Magnetite, and Scheelite are cloud VMs without nested virtualisation.
Evaluation cannot inspect a machine's device nodes, so the option is an operator declaration rather than a detection, and a wrong declaration is visible at one line per host instead of inherited silently.
Corrected advertisements take effect only after each machine is activated.

Remote builders are one Clan service, `nix-builders` (`clan/services/nix-builders/`, instance in `clan/inventory/services/nix-builders.nix`).
A machine in the `builder` role runs `nix-grpc-daemon` from nix-grpc-store on TCP 50051 in front of its nix-daemon, reachable over ZeroTier only: NixOS opens the port on the `zt+` interfaces, and Darwin, which has no per-interface firewall, binds the daemon to its ZeroTier address.
The daemon requires a client certificate signed by the instance CA and grants the `trusted` role to each dispatcher's certificate CN; `trustClients` makes its proxy user a Nix trusted user so builds can import the unsigned paths a dispatcher sends.
The CA is the shared `nix-grpc-ca` clan var, whose private key is never deployed, and every machine of the service has a `nix-grpc-cert` var signed by it, named by machine name and, on builders, by ZeroTier address.
A machine in the `dispatcher` role loads the `grpc://` store plugin and gets a `nix.buildMachines` entry naming `grpc://[<zerotier address>]:50051` with the CA and its own certificate for every builder it does not exclude.
Stibnite dispatches x86_64-linux work to Magnetite and Pyrite, and Pyrite's entry is the only one advertising `kvm` for x86_64-linux.
Magnetite dispatches aarch64-darwin work, nixbot's best-effort darwin checks included, to Stibnite only, and excludes Pyrite.
Rosegold and Argentum stay excluded from Magnetite until the binary cache holds nixbot's darwin outputs; deleting a name from Magnetite's `exclude` and redeploying Magnetite re-admits that machine, whose builder side is already in place.
The Darwin builders are laptops and serve builds opportunistically.
They accept dispatched builds on battery or AC, and their nix-daemon runs at `Background` QoS with low-priority I/O so a dispatched build yields to the owner's work.
Unreachability is therefore ordinary, and nix 2.35 handles it in two distinct ways.
A build the caller or another builder can perform continues: the build hook logs `cannot build on '<store uri>'`, marks that machine disabled for the rest of its lifetime, and reconsiders the remaining machines or falls back to a local build.
A build no remaining machine can perform fails outright, as an x86_64-linux build requiring `kvm` does while Pyrite is offline, reporting `missing system features` with `Required features: {kvm}`, and never degrades into an unaccelerated or emulated build.
That second case is the intended behaviour: vmTests are opt-in and outside PR gating, so an offline laptop costs a manual re-run rather than a red pull request.
Every builder URI sets `connect-timeout=5`, so a sleeping or off-network laptop is declared unreachable in seconds instead of after the plugin's default 30; once a builder has answered, the plugin rides out a dropped connection for its default `restart-grace` of 120 seconds before failing the build.
`checks.<system>.nix-builders-wiring` pins the entries, store URIs, daemon TLS and access rules, the ZeroTier-only port, and the absence of the retired ssh build accounts across machines, which no single machine's evaluation can see.
A change takes effect only after both the dispatcher and the builder are activated.
New VM test modules belong in `vm-tests/` and assign `perSystem.vmTests`, using the same automatically discovered flake-parts composition as the other module directories.
