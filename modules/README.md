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

Top-level files configure the flake itself: `flake-parts.nix`, `formatting.nix`, `systems.nix`, `debug.nix`, `kubernetes.nix`, `nixidy.nix`, and `k3d-cluster-config.nix` (the ctlptl configuration of the local k3d cluster, whose node image follows nixpkgs' `k3s`).

## Shared CLI capabilities

`system/cli-tools/` exports `cli-unix`, `cli-archives`, `cli-network`, `cli-host-inspection`, and their `cli-tools` aggregate under each of `flake.modules.nixos`, `flake.modules.darwin`, and `flake.modules.homeManager`.
Import the export matching the consumer's module class; package selection uses that consumer's `pkgs`.
The aggregate adds jq through its configured Home Manager module or as a system package.
These exports are opt-in: Omnigent workers import `homeManager.cli-tools`, while human terminal declarations remain independent.
`cli-host-inspection` is the exception, because it serves whoever lands on a host, person or agent: `fastfetch` (`fastfetch --format json`), `nix-info`, and on Linux `pciutils` and `usbutils`, all of which report without root.
The NixOS and nix-darwin `base` aspects import it, putting it on the system PATH of every account on every machine, root included, and `homeManager.engineering-tools` imports it, reaching every home, among them the standalone `claude-sandbox` and `ubuntu` profiles that have no system configuration.
Worker profiles prefer procps' `kill` over coreutils' overlapping executable, matching the existing supervisor PATH; the shared capabilities impose no worker-specific package priorities.
`checks.<system>.omnigent-worker-capabilities` makes two Home Manager evaluations of the worker module: a positive worker home, whose assertions, generated PATH order, ACP settings, tools, skills and harnesses it compares, and one composite invalid home whose failed assertions must equal the four guard messages.
Its build confirms that the harness executables exist in the generated profile and that `playwright-cli` reports its packaged version; it runs no CLI adapters, archive or file utilities, or workflow-tool smoke tests.

## Host registry

Each fleet member is one typed record, `flake.fleet.hosts.<name>` (`lib/hosts.nix`), and `flake.lib.hosts` is its read-only alias.
A record declares the host's `system` (null for a phone), endpoints, deploy user, services, ZeroTier address, memory, `nixClassic`, `checked` and `stateVersion`; `class`, `fqdn`, `address`, `targetHost`, `memoryGiB`, `enrolled` (its clan machine key is committed), `cloud` (from `flake.lib.cloudMachines`) and `primaryUser` are derived.
`flake.lib.machineSystems`, the inventory's `machineClass` and NixOS `deploy.targetHost`, `flake.clan.machines` with its `nixpkgs.hostPlatform`, the collector rows' `platform`, the NixOS names of `flake.lib.hostKeys` and the ZeroTier controller's external members are generated from it; the inventory keeps each host's tags and description.
A service role's members are `flake.lib.inventoryMembers` (`lib/inventory-members.nix`), clan's own rule over the declared inventory.

The accounts people hold on a host are declared once, as `flake.fleet.hosts.<name>.users.<account>` (`lib/host-users.nix`): whether the account is the host's primary person or nix-darwin's admin, its darwin uid, whether its age key is bridged (NixOS), and the pair's extra home modules and overrides.
From them are generated the clan user instances' machine lists (`flake.lib.hostsOfAccount`), `primaryUser`, and, through `flake.modules.{nixos,darwin}.home-manager-integration` (`system/home-manager-integration.nix`), each attached account's home, the `hm-sops-bridge` users, `system.primaryUser` and the darwin uids; `checks/home.nix` derives its standalone home checks from them.
A host gains a person's account by adding an attachment, never by writing `home-manager.users` or `hm-sops-bridge.users` in its body.
Omnigent worker accounts are a separate relation, `flake.fleet.workers.<owner>` (`lib/fleet-workers.nix`), from which the omnigent inventory's host roles, `flake.lib.workerAccountsOn` and the fleet deployer's requesters are generated.

## Secrets

A module declares the secrets it owns and reads the ones it uses through one option, `vanixiets.secrets.<name>` on the NixOS and nix-darwin classes (`system/secrets.nix`), where `<name>` is the generator name: `vanixiets.secrets.<name> = { files.<f> = { owner = …; }; runtimeInputs = …; script = …; }` to declare, `config.vanixiets.secrets.<name>.files.<f>.path` (or `.value`, `.exists`, `.placeholder`) to read.
The secrets module translates each entry into clan vars with only the fields a module set, so clan's defaults decide the rest, and reads clan's values back; `resolved` is the generator as clan evaluated it, for judges of custody.
A generator that one of clan's own services declares, such as sshd's `openssh`, is read as a provided entry: `provided = true` and its files by name only.
`nixos.base` and `darwin.base` import the secrets module; a module also imports it itself when something evaluates it without the base aspect, as clan service modules and the modules runtime tests import directly do.
Homes see a view of the host's secrets with a file their user owns, `config.vanixiets.secrets.<name>.files.<f>.{path,placeholder}`, set by `nixos/hm-sops-bridge.nix`; a standalone home sees `{ }`.
Committed public values are read through `flake.lib.vars` (`lib/vars.nix`), and judges that need clan's whole generator tree read `flake.lib.secretsBackend.generatorsOf`.
`checks.x86_64-linux.secrets-seam-confinement` fails when a module outside these two files names `clan.core.vars` or spells the committed `vars/` layout; its list holds the checks and runtime tests that must pin clan itself, each with its reason.

## Evaluators

A host's memory decides its many-attribute evaluator, and nothing else does.
`flake.fleet.hosts.<name>.memoryGiB` (`lib/hosts.nix`) is required for every member that runs Nix, `"unknown"` where nobody has read it; a cloud host's follows from its machine type through `flake.lib.cloudMachineMemoryGiB` (`lib/cloud-machines.nix`).
`flake.lib.nixEvalJobsBoundRules` (`lib/nix-eval-jobs-host.nix`) turns it into a bound, by the first rule for the host's platform that its memory reaches.
A host with a bound gets iets as `nix-eval-jobs`, capped at the bound's workers and, on Linux, its per-worker `--max-memory-size`: the bound is the default when the caller gives none and the ceiling when it asks for more.
Stock is beside it as `nix-eval-jobs-stock`.
A host without a bound keeps stock as `nix-eval-jobs` and gets nothing else.
On NixOS, `nixos/nix-eval-lock.nix` is imported by every host and enabled wherever iets is (an assertion), and both names are lock-wrapped: iets fails a whole evaluation when the OOM killer takes one of its workers, so it must not overlap another evaluation.
On darwin, `darwin/nix-eval-jobs.nix` installs both names at system level.
Homes install whatever their host chose (`home/development/nix-tools.nix`), so the user profile never shadows it, and a standalone home gets stock.

| host | memory | evaluator | bound | lock |
|---|---|---|---|---|
| magnetite | 32 GiB | iets | 5 workers x 3072 MiB | yes |
| galena, scheelite | 32, 30 GiB (declared, not provisioned) | iets | 5 x 3072 | yes |
| pyrite | 16 GiB | iets | 1 worker x 2048 MiB | yes |
| cinnabar, electrum | 16 GiB (declared) | iets | 1 x 2048 | yes, new on cinnabar |
| stibnite | 64 GiB | iets | 3 workers | none on darwin |
| argentum, rosegold | 8 GiB | iets | 1 worker | none on darwin |
| blackphos | unknown | stock | | none |

Measured on 2026-11-23 at trunk `b9889f23`, nixbot's arguments, through each host's lock, as cgroup `memory.peak`.
- magnetite, `checks.x86_64-linux` (226 attributes), 5 x 3072: stock 121-131 s, iets 41-43 s. The two-system set (338 attributes): stock 198 s, iets 69 s. Both peak at 10.1 GiB, which is magnetite's `user.slice` `MemoryHigh` (`nixos/magnetite-user-slice-guard.nix`), so user evaluations there are throttled rather than bounded by the evaluator. nixbot's own unit is not a user evaluation: its 5 x 3072 iets peaks at 68-72 % of its 20 GiB `MemoryHigh` (`nixos/nixbot.nix`), and that unthrottled figure is what the 30 GiB rule assumes for galena and scheelite.
- pyrite, `checks.x86_64-linux`: stock at the remote lane's 2 x 2048 took 424-738 s and peaked at 4.0-4.6 GiB. iets took 85-94 s at 2 x 2048 (5.1-5.5 GiB) and 140 s at 1 x 2048 (3.2 GiB). The two-system set (338 attributes): stock 759 s and 4.0 GiB, iets 172 s and 2.7 GiB at 1 x 2048, 119 s and 4.5 GiB at 2 x 2048. One worker keeps iets below what the stock lane already takes there, which is all a 16 GiB host with a desktop, QEMU tests and, on cinnabar, ntfy, DNS and Caddy is assumed to spare.
- argentum (8 GiB) at 1 worker: `checks.aarch64-darwin` iets 15.6 s and 4.8 GiB against stock's 68-74 s and 12.6 GiB at 4 workers; both systems iets 62-111 s (12.8 GiB footprint, 5.3 GiB of swap) against stock's 232-354 s (14.4 GiB). Two iets workers exceeded the swap guard on both systems.
- On Linux, iets' `--max-memory-size` does restart workers: at 256 MiB magnetite's run used 97 worker processes for 5 workers, against 5 at 3072, and peaked 2 GiB lower. On macOS it is inert.

Every iets run gave the same drvPath, system, outputs and error status as stock on every attribute.

`nix-eval-jobs-stock` is the escape hatch for what iets refuses.
iets rejects `--help` ("error: unknown flag '--help'"), `--override-input` and `--override-flake` ("… is not supported by iets: iets evaluates locked flakes only …"), and `--repair`, each with exit 1.
It also refuses import-from-derivation ("import from derivation is not supported: … is not built").
nixbot's arguments and nix-fast-build's (`--gc-roots-dir`, `--force-recurse`, `--max-memory-size`, `--workers`, `--option`, `--flake`, `--check-cache-status`, and `--impure`, `--select` or `--reference-lock-file` when asked) are all accepted.
nix-fast-build passes `--override-input` only when its own `--override-input` is given, which no recipe does.
nixbot keeps its own evaluator, `config.services.nixEvalLock.wrap config.vanixiets.nixbot.ietsEvaluator` (`nixos/nixbot.nix`), unbounded by the host table and unchanged in derivation.

`just check-fast` evaluates with the evaluating host's `nix-eval-jobs`: locally through `--nix-eval-jobs`, because nix-fast-build puts stock first on its own PATH, and remotely through the bare name on the remote's PATH, because nix-fast-build ignores `--nix-eval-jobs` on `--remote`.
`just check-ifd` runs `nix-eval-jobs` from PATH.
Both say which evaluator ran.
`apps/nix-eval-jobs-identity` (`just eval-identity [systems] [rev] [workers] [evaluators]`) is the drvPath-identity oracle: it runs the host's `nix-eval-jobs-stock` and `nix-eval-jobs` over `checks.<system>` of one commit, behind the lock where there is one, and fails unless every attribute has the same drvPath, system and outputs.
By default it runs the two evaluators the host's configuration has at that commit (`vanixiets.nixEvalJobs` on darwin, `services.nixEvalLock` on NixOS, whose packages are lock-wrapped), built with stock Nix, so a bump of the `iets` input is tested with the iets the commit pins; `evaluators=path` (`--evaluators path`) runs the deployed names on PATH instead.
It prints the evaluator store paths and the iets revision the commit's lock pins.
It compares two evaluators at one commit; a change across commits is judged with `just drv-diff <before> <after> [allow]` (`apps/drv-diff`), which holds the evaluator fixed and diffs the drvPath of every host toplevel, home `activationPackage`, `checks.<system>` and `vmTests.<system>` between the two commits against the change's declared differences.
Every machine check (`checks.<system>.nixos-<host>`, `darwin-<host>`) judges its host's evaluators with `flake.lib.nixEvalJobsObligations`: its bound is the table's, its system PATH holds iets at that bound and `nix-eval-jobs-stock` exactly where there is one, the lock is enabled where iets is, no home installs another evaluator, and nixbot evaluates with lock-wrapped iets at the host's bound and names it in its records; the lock module's own assertion rejects any unwrapped evaluator on a profile or service PATH.
`checks.x86_64-linux.nix-eval-jobs-iets` holds what does not depend on a host: the rules (a Linux bound without a memory limit fails it), the lock's judgement (an unlocked iets on nixbot's PATH or an unlocked stock alias fails it), the per-host judgement over a magnetite fixture and its mutants, and the bounded wrapper run against a stub.

For the primary user of a host listed in `flake.lib.hosts.<name>.nixClassic` (`lib/hosts.nix`; stibnite only, as a trial), `home/development/nix-classic.nix` makes `nix` iets' classic mode wherever a person or an agent types it, on the user PATH and in this repository's default dev shell alike: `nix eval`, `nix build`, `nix develop` and `nix derivation show` evaluate in iets, and anything classic does not implement (`nix flake …`, `nix run`, `--json`, `--apply`, `--profile`, `--version` among others) falls back to the real Nix with the line `iets: falling back to nix: <reason>`.
The wrapper is `flake.lib.nixClassic` over `flake.lib.fleetNix`, the one value the hosts' `nix.package` and the dev shell also take; the dev shell carries it on every host, and it evaluates with iets only when `~/.config/nix-classic/enabled` exists and the caller is not root, otherwise execing the fleet's Nix with the same arguments and environment, so CI, the cloud sandbox and other users see no change.
A call iets evaluates itself prints `setting 'accept-flake-config' is ignored`; `nix-stock` is always the real Nix; deleting `~/.config/nix-classic/enabled` turns classic off at once for every shell and agent until the next home activation, `IETS_NIX_FALLBACK=always` does so for one environment, and disabling the option does so for good.
Classic only evaluates with `plugin-files` emptied, which the wrapper does for iets alone: a fallback and `nix-stock` run the real Nix with its own configuration, the grpc dispatcher plugin included, and builds go through the daemon, which dispatches them to the remote builders as before.
The tracing cache is off (`IETS_CACHE=1` turns it on for one run), so every call is a full, still several times faster, evaluation.
What a host, a cluster or a gate consumes is still evaluated by stock Nix: nh (in the `.#darwin`, `.#os` and `.#home` apps behind `just activate*` and in the dev shell) and nixidy (`packages.nixidy` and the `nixidy-*` apps) are `flake.lib.withFleetNix`, with the fleet's Nix first on their PATH, and `just agents-skills-index`, `k3d-up` and `k3d-down` call `{{nix_stock}}`; `checks.x86_64-linux.deploy-stock-nix` asserts both lists against the wrapper.
`darwin-rebuild` sets its own PATH, `clan` prepends its own Nix, `nix-fast-build` its stock evaluator's, the bootstrap and cloud-sandbox apps carry `pkgs.nix`, and `nix run` itself always falls back.
Every home's nix-direnv is `flake.lib.nixDirenv`, which calls the fleet's Nix by absolute path instead of the `nix` on PATH: each of its calls carries `--no-warn-dirty`, which classic hands to the real Nix with one notice per call, about 95 lines per dev shell rebuild here; `deploy-stock-nix` checks it too.
iets prints that notice unconditionally (`log::line`, no quiet setting), so a caller that only ever falls back is pinned rather than its notices hidden.
`just eval-identity` also runs `apps/nix-classic-identity`, which evaluates every host system, every home activation package and the default dev shell with stock Nix and with classic and fails unless drvPaths and whole `.drv` closures agree; every bump of the `iets` input must re-run it before the trial continues.
Upstream's open numtide/iets#359 lists evaluation differences: in each, iets either fails where Nix succeeds, which the oracle would report, or succeeds where Nix fails, on constructs (`${''…''}` names in `rec`, `<nix/derivation.nix>`, `__json`, `fetchClosure`, `nix-instantiate`'s walk) that this repository's modules do not use and that the classic wrapper does not reach (it takes over `nix` only), so for configurations stock Nix evaluates without error none changes a result.

## On-demand VM tests

`nixbot.toml` evaluates `checks`, which nixbot scopes to `checks.x86_64-linux` and `checks.aarch64-darwin`, both required; VM tests instead live under `vmTests`, and nixbot never runs them.
Every pull request evaluates each `vmTests.x86_64-linux` test through its `checks.x86_64-linux.vm-test-evaluates-<name>` (`checks/vm-test-evaluates.nix`), a text file holding the test's drvPath whose build builds nothing of the test, so a test that stops evaluating fails the gate; a new runtime test needs a `testSizes.checks` entry for that check in the module's literal set as well as its own `testSizes.vmTests` entry.
The independent `checks.x86_64-linux.zerotier-mss-clamp` structural check remains gated; it compares zerotier controller and peer role membership with `TCPMSS --set-mss 1300` in each nixosConfiguration's firewall commands.
The fleet-alerting checks are gated the same way and need no runtime host.
`checks.x86_64-linux.fleet-alert` runs `promtool` over the PromQL rules rendered by `nixos/fleet-alert/rules.nix`, replays canned PromQL and SQL answers per rule database through a loopback fixture server against the evaluator in `nixos/fleet-alert.nix` with a recording `ntfy-send`, and compares `nixos/fleet-alert/transition.jq` with a Python reference model under a derandomized Hypothesis test.
It also runs the dead-man against a loopback ntfy stand-in, with a configuration rendered from the module's option defaults, and keeps only the relations between the two hosts: the dead-man polls the heartbeat topic the evaluator posts to, both post to the same alert topic, and the dead-man watches magnetite's evaluator.
Relations within one host are module and host assertions, so evaluating that host fails when they break: on the host that enables the dead-man, its URL is ntfy's listener, ntfy's access entries refuse anonymous writes to the heartbeat and alert topics, let `alerter` write both and decide no host-named topic, and the dead-man is ordered after `ntfy-sh`, `caddy` and `zerotierone` without wanting them; and with a token set, `nixos/observability-notify.nix` requires every notified unit's resolve hooks to run under the token file.
`checks.x86_64-linux.ntfy-provisioning` runs the `ntfy-alerter` generator from `nixos/ntfy-alerter.nix` and cinnabar's `ntfy-alerter-env` generator in the sandbox, and checks the rendered token, password hash and cinnabar's access entries before ntfy could refuse them at start.
ntfy's enforcement of the access entries, its rate limiting and the rules against real series are verified at deployment, not by these checks.
`checks.x86_64-linux.ntfy-tls-verification` scans `modules/` and `pkgs/` for an `ntfy.zt` client passing `-k` or `--insecure` or undeclared, and runs `flake.lib.caddyRootCheck` over roots made in the sandbox; it does not observe the chain caddy serves, which cinnabar's weekly `caddy-root-check` verifies.
Its clause D reads, at evaluation, the `NTFY_URL` each darwin sender's `ntfy-send` exports (each Mac's launchd notify jobs and each home-manager user's tools and hooks) and fails naming any sender whose host is a `.zt` name, because macOS Local Network privacy refuses ZeroTier's `feth` to a store binary whose responsible program holds no grant, such as an agent session under herdr; Macs use `ntfy.vanixiets.internal` over tincr's tunnel (`pkgs/by-name/ntfy-send/package.nix`).
`caddy-root-from-vars`, built with cinnabar's toplevel, adapts caddy's configuration and compares the configured root with the vars and the recorded fingerprint; `vmTests.x86_64-linux.caddy-root-from-vars` shows a caddy with empty storage serving under a configured root.
The dev-loop checks are gated the same way and need no runtime host.
`checks.x86_64-linux.devloop-queries` applies the nixbot input's migrations to a sandboxed PostgreSQL, creates the two reader roles with the column grants rendered by `nixos/devloop-collection.nix`, loads fixture rows, and runs the two export queries as `opentelemetry-collector` and the reconcile's queries as `devloop-reconcile`; it requires `abandoned` to be true only for the row carrying `flake.lib.devloopCollection.abandonMarker`, which nixbot wrote until 2026-11-25 and which now only reads stored history, no result cell to contain a fixture error string, `outputs_out` to be empty for a null `outputs`, and the five-minute overlap and tied rows to be read, and it rejects the mutants `renameCached`, `selectError`, `grantWithoutError`, `errorUnderAlias`, `reconcileGrantWithoutFinishedAt` and `currentFinishIgnoresDuplicates`.
`checks.x86_64-linux.fleet-alert` also replays `PullRequestQueueWaitBurn` against `devloop` through the fixture server's `/v1/sql` and requires each rule's query to reach its own database.
Every judge a machine check asserts is registered once, in the module that defines its `flake.lib` export, as `fleetObligations.<key> = { classes; failures; }` (`lib/fleet-obligations.nix`, a flake-parts option and not a flake output). `checks/machines.nix` folds, for each NixOS and darwin configuration, every entry whose `classes` (default both) contain that configuration's class, and fails with `Fleet obligations unmet on <host>:` and one `<key>: <message>` line per unmet message, followed by the host's own failing assertions. Adding a judge is its registration plus its key in the literal `registeredObligations` list in `checks/machines.nix`, which every machine check asserts equals the registry's keys. A check that runs a judge over fixtures and mutants counts each case's problems through `flake.lib.mkJudgeCheck` or `flake.lib.judgeCases` (`lib/judge-check.nix`), which name each wrong case with its expected and actual count and the judge's messages.
The five x86_64-linux NixOS machine checks (cinnabar, electrum, galena, magnetite, pyrite) require the deploy-record snippet in the machine's activation through `flake.lib.deployRecordObligations`; the darwin machine checks require it too, and scheelite, whose record sets `checked = false`, carries the snippet with no machine check.
The same judge requires the rendered activation to read the previous system before anything relinks `/run/current-system`: on NixOS the record runs before the relink, and on darwin `preActivation` reads it before launchd reloads nix-darwin's `activate-system`, which links `/run/current-system` to the already updated profile (F86). On darwin it also requires the record to be the last `postActivation` snippet, with only blank or comment lines between it and the relink, so the record is written after every other `postActivation` snippet. `checks.x86_64-linux.deploy-record-order` runs that judge over fixtures and its mutants, and runs the record script with and without the earlier read.
The darwin machine checks also require, through `flake.lib.resolverReloadObligations`, a `touch -h` of each managed `/etc/resolver` file after the `/etc` link loop in the rendered activation script, so that configd rereads the files (`darwin/resolver-reload.nix`); `checks.x86_64-linux.darwin-resolver-reload` runs that judge over fixtures and its mutants on every pull request.
Every NixOS and darwin machine check also requires, through `flake.lib.meshHostsObligations`, that the machine's hosts entries map every name under `vanixiets.internal` or `.zt` to exactly the registry's addresses (`system/mesh-hosts.nix`); `checks.x86_64-linux.mesh-hosts-obligations` runs that judge over fixtures and its mutants on every pull request.
Every NixOS and darwin machine check also requires, through `flake.lib.networkTargetObligations`, that every network export clan may reach the machine through logs in as its `flake.lib.hosts.<name>.deployUser` (`lib/network-targets.nix`, finding F36). It also requires that the machine's `clan.core.networking.targetHost` is `flake.lib.hosts.<name>.targetHost`, the single deploy address the fleet deployer probes first (F83), and that no darwin machine sets an inventory `deploy.targetHost`, which would bypass the network peers. `checks.x86_64-linux.network-target-obligations` runs that judge over fixtures and its mutants on every pull request.
The receivers, the store's pipelines and `devloop-reconcile` against the real store are verified by `devloop-ingest` below and at deployment, not by these checks.
The collector's envelope check is gated the same way and needs no running collector.
`checks.x86_64-linux.otel-envelope` runs the script of `flake.lib.otelEnvelope`, which `otel-envelope.service` runs on every agent host, against recorded collector telemetry served by a loopback stub, one case per sequence of runs on a fresh state directory.
It establishes each envelope clause, `C1` to `C4`, against the recorded counters, queues and targets, and the darwin `C5` against recorded `top` text, requires each marked mutant of the script to fail its case, and holds the hourly budget clauses to minute `00` and to a host given a `budget`.
The real collector's telemetry and the budget's queries against a real store are verified by `fleet-ingress` below and at deployment, not by this check.
The darwin collection check is gated the same way and needs no darwin host.
`checks.x86_64-linux.otel-collector-darwin` renders stibnite's agent and `otelcol-process` configurations from `flake.lib.otelCollectorDarwin` with `flake.lib` data only and validates each with the root pin's Linux `otelcol-contrib`, the same version the darwin jobs run.
It establishes R3.1's darwin clauses over those configurations (loopback listeners, the six disabled process attributes, no listener or credential in `otelcol-process`, the strict disk and filesystem include lists), the probe's label selection and its parser over `launchctl print` and `smartctl` output recorded on stibnite, the notifier wrapper's `FAILED` and `RESOLVED` episodes over a recording `ntfy-send`, and the process filter keeping the fleet's own executables below the darwin floor, each with a mutant that must fail its own case.
It establishes nothing about a darwin process starting: launchd loading the jobs, the collector running on macOS and reaching the ingress over ZeroTier are observed at stibnite's activation, and relations within stibnite are assertions in `darwin/otel-collector-agent.nix`, which stibnite's evaluation and nixbot's `checks.aarch64-darwin` evaluate.
A runtime test builds only on a builder advertising the features its derivation requires: QEMU VM tests need `kvm`, which only Pyrite advertises, and systemd-nspawn container tests need `uid-range`, which Pyrite and Magnetite advertise (Pyrite once deployed with its `auto-allocate-uids` settings; `nix-builders-wiring` holds each Linux builder's settings to what it advertises).
Run one from a checkout of the intended revision on that host, or from a dispatcher such as Stibnite, which routes a kvm test to Pyrite and a container test to whichever of the two is less loaded, Magnetite on a tie for its higher `speedFactor` (nix's `build-remote`).
To keep a container test off the store host, run it on Pyrite with `--builders ''`, without which Pyrite's own daemon dispatches it to Magnetite.
Run it on Pyrite itself, `ssh pyrite.vanixiets.internal nix build --builders '' '<source>#vmTests.x86_64-linux.<name>'`, against a source already on Pyrite: a checkout there, or the store path `nix flake archive --to ssh-ng://pyrite.vanixiets.internal "git+file://$PWD?rev=<commit>"` prints.
`nix build --store ssh-ng://pyrite… --builders ''` from another host does not keep the build on Pyrite: the flag does not reach Pyrite's daemon, which on 2026-11-24 handed such a `fleet-ingress` build to Magnetite (`logs/tsc-1-fleet-ingress-20261124-111732.log`).
The commands below are as run in a checkout on the host that builds them:

```sh
nix build .#vmTests.x86_64-linux.zerotier-mss-clamp-runtime   # Pyrite, kvm
nix build .#vmTests.x86_64-linux.omnigent-worker-isolation    # Pyrite, kvm
nix build .#vmTests.x86_64-linux.greptimedb-pipeline          # Pyrite or Magnetite, uid-range
nix build .#vmTests.x86_64-linux.devloop-ingest               # Pyrite or Magnetite, uid-range
nix build .#vmTests.x86_64-linux.devloop-ingest-reconcile     # Pyrite or Magnetite, uid-range; enormous, announce first
nix build .#vmTests.x86_64-linux.fleet-ingress                # Pyrite or Magnetite, uid-range
nix build .#vmTests.x86_64-linux.fleet-ingress-outage         # Pyrite or Magnetite, uid-range; enormous, announce first
nix build .#vmTests.x86_64-linux.perses-greptimedb            # Pyrite or Magnetite, uid-range
nix build .#vmTests.x86_64-linux.caddy-root-from-vars         # Pyrite or Magnetite, uid-range
nix build .#vmTests.x86_64-linux.greptimedb-oom-order         # Pyrite, kvm
nix build .#vmTests.x86_64-linux.tincr-mesh                   # Pyrite, kvm
nix build .#vmTests.x86_64-linux.tincr-mesh-partition         # Pyrite, kvm
nix build .#vmTests.x86_64-linux.fleet-deployer               # Pyrite, kvm
```

Each test declares its size class in `testSizes.vmTests` beside its definition (`checks/test-sizes.nix` declares the option and `flake.lib.testSizeLimits`), and `vm-tests/default.nix` passes every test through the test framework's `extend` with `globalTimeout` set to its class limit: small 60 s, medium 300 s, large 900 s, enormous 3,600 s, the driver's default.
A test with no entry fails evaluation, naming it.
The driver starts the timer just before the test script and, when it fires, logs `timeout reached; test terminating...`, releases every VM and container and fails the build; the driver and node builds are outside it.
A test no run has measured is declared medium with `measured = false`, the three `vmTests.aarch64-linux` tests because the fleet has no aarch64-linux builder.
`flake.lib.enormousTests` lists the enormous x86_64-linux tests, `devloop-ingest-reconcile` and `fleet-ingress-outage`.
Every check on `checks.x86_64-linux` and `checks.aarch64-darwin` declares its class the same way in `testSizes.checks`, and `checks/test-size-classes.nix` fails the gate on a check with no entry, an entry naming no attribute, an enormous check or a large check with no `reason`; on x86_64-linux it also compares the `vmTests` names of x86_64-linux and aarch64-linux with their entries, which is why `omnigent-worker-isolation.nix` and `zerotier-mss-clamp-runtime.nix` key their tests on `system` rather than on `pkgs`.
`flake.lib.checkSizes` lists every gated check's class and `measured` by its full attribute path, from which fleet-alert's `CheckOutgrewItsClass` renders its per-check limits; that rule would post, at low priority, a check whose recent nixbot builds outgrew its class (`nixos/fleet-alert/rules.nix`), and is withdrawn from the deployed rules since 2026-11-25, when its query exceeded the store's query memory limit (`checks/fleet-alert.nix`'s `withdrawnClause`).
`flake.lib.runtimeTestSizes` gives every x86_64-linux runtime test's class and limit; Pyrite's weekly `enormous-tests.service` (`nixos/enormous-tests.nix`, Sundays 03:00 America/New_York) reads it from the `main` it builds and records it beside each test's result in `devloop.runtime_test_result`, where fleet-alert's `RuntimeTestCostDrift` and `EnormousTestStale` judge the records, and `checks/enormous-tests.nix` runs the service's script against a stub `nix` and `nix-eval-jobs`.

`fleet-deployer` runs the fleet deployer's request path end to end, in two QEMU VMs.
- **What it imports:** the deployer imports `flake.modules.nixos.fleet-deployer`. Its forge is a local bare repository, its cache is a `file://` store, its ntfy is a recording `ntfy-send`, and stubs replace the commit's evaluation, `clan vars check` and `clan machines update`, which switch the target to the closure a test commit names. The target has the deploy record and `fleet-deploy-watch`, plus three specialisations: `next`, `broken` (a failing unit) and `isolated` (a firewall dropping the deployer's SSH).
- **What it establishes:** requests through sshd's forced command:
  - a merged deploy confirmed;
  - a request run with a hostile inherited environment (another user's `XDG_RUNTIME_DIR`, no `HOME`, an unwritable `TMPDIR`), which still deploys, because the request command replaces its environment with the account's own (`HOME`, `XDG_RUNTIME_DIR`, `XDG_CACHE_HOME` and `TMPDIR` under `/var/lib/fleet-deployer`, the directories 0700). Every stub refuses to run without a usable `HOME`, `XDG_RUNTIME_DIR` and `TMPDIR`, as clan and nix need;
  - refusals that never touch the target;
  - busy, unreachable within 15 s, concurrent requests serialised;
  - an unhealthy deploy kept;
  - an activation that writes its deploy record and exits 0 without switching, ended as unhealthy because the running system is not the deployed closure;
  - a deploy that cuts SSH rolled back by the target itself, reported rolled back once the deployer reads the target on its previous closure;
  - one notice per request;
  - the key check failing on a widened key file.
- **What it does not establish:** anything about clan, the forge, niks3, ntfy or darwin.

The fleet deployer's evaluation-time regulators are in the PR lane:
- every NixOS and darwin machine check asserts `flake.lib.fleetDeployer.failures`: a primary user's account, the deployer's key only on targets' deploy accounts, the deployer account and key modes only on cinnabar, and on darwin targets a rollback watcher job declared in launchd's system domain, run as root and not kept alive (F84);
- the machine checks module asserts `flake.lib.fleetDeployer.problems` (no disabled or excluded target, no reach outside the role policy);
- `checks.x86_64-linux.fleet-deployer-obligations` runs both judges over fixtures and mutants;
- `checks.x86_64-linux.fleet-deploy-request` runs the forced command's parser, and deploys to a darwin fixture target whose failed confirmation is `unconfirmed` (9) while it keeps the deployed closure and `rolled-back` (8) only once it runs its previous closure;
- `checks.x86_64-linux.fleet-deploy-watch` runs the rollback watcher against a fixture root, as on NixOS and as the darwin job: a confirmed deploy of the running closure ends it promptly without a rollback (F90), as does a confirmed change; an unconfirmed change rolls back; an unchanged, unconfirmed system ends after the activation wait;
- `checks.x86_64-linux.sops-correspondence` bounds the deployer's sops reach to its targets.

`omnigent-worker-isolation` establishes the runtime wiring of the Omnigent worker guards that no evaluation-time check can reach: that the private-home precondition is `ExecStartPre` on the real `omnigent-host-<owner>.service` and that violating the home's privacy at runtime prevents `ExecStart`, that the Nix daemon resolves a worker as untrusted, that two workers have separate accounts and mutually unreadable private homes, and that the unit's `User`, `UMask`, `NoNewPrivileges` and SSH-agent unsetting hold in the spawned process.
It is not a sandbox and establishes nothing about confining hostile code inside a worker account, it stubs `ExecStart` so it is no evidence about the Omnigent client, it declares no credentials so the Clan-vars-to-sops delivery path is out of scope, and it says nothing about Stibnite or any Darwin host because there is no Darwin NixOS test node type.
Because it lives in this lane and runs only when a KVM-capable builder is reachable, it is on-demand evidence and must not be described as coverage; `checks.x86_64-linux.omnigent-worker-linux` remains the fleet-wide regulator for the precondition script's own behaviour.

`greptimedb-pipeline` runs the telemetry store and both collector roles in one systemd-nspawn container, with credentials written at boot by Magnetite's own `greptimedb-users` generator script and Magnetite's databases and TTLs.
It establishes that the store answers `/health` and serves its embedded dashboard at `/dashboard/`, that the schema oneshot creates each database with its TTL and that a re-run with a changed TTL changes it, that no or wrong credentials are answered 401 while a write-only read and a read-only write, by `perses` and by `regulator`, are answered 403, that an OTLP point crosses the forward and routing connectors into `fleet` only and reads back through PromQL with `x-greptime-db-name` carrying `host_name`, that the systemd receiver reaches D-Bus under `DynamicUser` and stores an `omnigent-host-<owner>` unit only under its alias, and that a point emitted while the store is stopped arrives after it restarts.
It uses local `File` storage, so it establishes nothing about R2, and a container shares the build host's kernel, so it establishes nothing about OOM behaviour.

`devloop-ingest` and `devloop-ingest-reconcile` are built from one systemd-nspawn container running PostgreSQL with the nixbot input's migrations and fixture rows, the telemetry store with its schema job, the collector with the dev-loop logs path, a stub `gitea-mq.service` printing fixture batch lines, and `devloop-reconcile`.
`devloop-ingest` runs every case but `reconcile`, a medium run (247.33 s of script, 264 s for the whole build on Pyrite on 2026-11-24, with `sizeRule` and `runtimeRules`); `devloop-ingest-reconcile` runs `firstStart`, its readiness precondition, then `reconcile`, an enormous run (1,490.54 s of script, 1,506 s for the whole build), which starts at least 30 minutes before 00:00 UTC or waits for the next UTC day.
Together they establish that each `otlp_http/devloop_<table>` exporter's first send succeeds after the schema job, and fails when the job omits its table, that every table's columns equal the allow-list with no `body` column, that rows re-read on three polls are stored once, that an activation appends exactly one deploy-record line naming both closures, that each `devloop-reconcile` clause fails on its mutant and passes on the fixture day, that `PullRequestQueueWaitBurn`'s query returns a row only for its firing fixture, that `IetsEvaluationUnhealthy`'s query returns a row for each killed or crashed iets evaluation record and none for a clean one, that `CheckOutgrewItsClass`'s query returns exactly the fixture checks over their limit, the unmeasured one with three runs and the one with a run over an hour, that runtime-test result lines written to the weekly run's file reach `runtime_test_result` and `RuntimeTestCostDrift` and `EnormousTestStale` return exactly their firing fixtures, and that the three documented questions return their fixture answers.
They use fixture nixbot rows and a stub gitea-mq, so the backfill's size, the widest `finished_at` tie and a change in gitea-mq's real messages are observed only on magnetite, at deployment and by `devloop-reconcile`; and a container shares the build host's kernel, so they establish nothing about memory limits.
`devloop-ingest`'s activation case runs the activation script of an `extendModules` variant of the container's system, because the container's systems carry no `switch-to-configuration`, and prints a `limitation:` line.
Run `devloop-ingest` before merging any change to the dev-loop receivers, pipelines, allow-list or reconcile, or to `PullRequestQueueWaitBurn`'s, `IetsEvaluationUnhealthy`'s, `CheckOutgrewItsClass`'s, `RuntimeTestCostDrift`'s or `EnormousTestStale`'s SQL in `modules/nixos/fleet-alert/rules.nix`, which only its `burnRule`, `ietsHealthRule`, `sizeRule` and `runtimeRules` cases run on a real store, and, after a run notice, `devloop-ingest-reconcile` before merging any change to the receivers, pipelines or reconcile; name each log in the pull request.

`fleet-ingress` runs the telemetry store, a collector of both roles with its `otlp/mesh` receiver on loopback, and Electrum's evaluated non-ingress collector exporting to it over mutual TLS with throwaway certificates, in one systemd-nspawn container.
It establishes that the receiver refuses a client without a certificate, with a rogue CA's certificate or at TLS 1.2, that metrics and deploy records cross the ingress into the store, that back-pressure from a stopped store or a refusing limiter fills the agent's queue without loss, that each envelope clause fails on its negative control when run as its unit, and that each budget fixture fails its clause on the ingress host's unit.
It stands the container's loopback in for Magnetite's ZeroTier address and generates its own certificates, so it establishes nothing about the real address, the `zt+` firewall opening, the deployed certificates or the refusal over the mesh, which are observed at deployment.

`caddy-root-from-vars` runs three systemd-nspawn containers: `restored`, a caddy importing `flake.modules.nixos.caddy-local-root` with a root and key made in the test and empty storage, `minting`, the same caddy without the module, and a client.
It establishes that the client's curl, given the test root, gets 200 from `restored`, whose served intermediate verifies against that root and whose storage never holds `root.crt`, and exit 60 from `minting`, which mints a root of its own.
It uses a test root, so it establishes nothing about cinnabar's deployed vars, their sops delivery or the root caddy serves on `ntfy.zt`, which cinnabar's build-time check, its deploy and `caddy-root-check` cover.

`perses-greptimedb` runs the telemetry store with Magnetite's databases, devloop tables and store accounts, Perses from `flake.modules.nixos.perses`, and nginx with the module's vhost on plain HTTP, in one systemd-nspawn container.
No Kanidm runs: the test replaces the providers with native login, adds a test-only provisioning folder holding one native `User` and `greptimedb-sql-open` (the SQL datasource without `allowHeaders`), and holds the module's assertion to exactly the serving-predicate failures those overrides explain.
It establishes that a request without a session is answered 401, that dashboard writes are refused and a planted view is gone after a restart, that both datasources read data with the caller's database header overwritten, that every committed view's query succeeds and a view with a missing series fails that case, that the store refuses an `INSERT`, that the four out-of-pattern routes are refused by Perses before any request, that a caller's `x-greptime-auth` reaches the store as `perses` through nginx and directly but as `admin` through `greptimedb-sql-open` (the negative control), and that `/metrics` is 404 at the vhost.
It establishes nothing about Kanidm's refusal or admission, TLS and ACME, R2 storage, OOM behaviour, or what a chart renders.
Run it on Magnetite before merging any change to `modules/nixos/perses.nix`, its resources or `perses-bin`, and name its log in the pull request.

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
launchd orders no job after another, so a Darwin builder's job runs `/bin/wait4path` on the store, then polls once a second, for at most 60 seconds, for every daemon argument that is one of the machine's sops secrets or templates (its TLS key) before it execs the daemon, rather than failing once at boot while sops-install-secrets has yet to write the key; `/bin/wait4path` re-checks only when the mount table changes, so it is right for the store volume and can wait forever for a file. A key that never appears costs the 60 seconds, after which the daemon fails and is relaunched as before (`flake.lib.launchdSecretPoll`).
The daemon requires a client certificate signed by the instance CA and grants the `trusted` role to each dispatcher's certificate CN; `trustClients` makes its proxy user a Nix trusted user so builds can import the unsigned paths a dispatcher sends.
The CA is the shared `nix-grpc-ca` clan var, whose private key is never deployed, and every machine of the service has a `nix-grpc-cert` var signed by it, named by machine name and, on builders, by ZeroTier address.
A machine in the `dispatcher` role loads the `grpc://` store plugin and gets a `nix.buildMachines` entry naming `grpc://[<zerotier address>]:50051` with the CA and its own certificate for every builder it does not exclude.
Its plugin set also carries a build for the nix that `clan` wraps, taken from clan-core's own nixpkgs, because the plugin loads only into the libnixstore version it was built for and `clan` runs from a different nixpkgs than the system.
Stibnite dispatches x86_64-linux work to Magnetite and Pyrite, and Pyrite's entry is the only one advertising `kvm` for x86_64-linux.
Magnetite dispatches aarch64-darwin work, nixbot's required darwin checks included, to Stibnite only, and excludes Pyrite.
Rosegold and Argentum stay excluded from Magnetite until the binary cache holds nixbot's darwin outputs; deleting a name from Magnetite's `exclude` and redeploying Magnetite re-admits that machine, whose builder side is already in place.
The Darwin builders are laptops and serve builds opportunistically.
They accept dispatched builds on battery or AC, and their nix-daemon runs at `Background` QoS with low-priority I/O so a dispatched build yields to the owner's work.
Unreachability is therefore ordinary, and nix 2.35 handles it in two distinct ways.
A build the caller or another builder can perform continues: the build hook logs `cannot build on '<store uri>'`, marks that machine disabled for the rest of its lifetime, and reconsiders the remaining machines or falls back to a local build.
A build no remaining machine can perform fails outright, as an x86_64-linux build requiring `kvm` does while Pyrite is offline, reporting `missing system features` with `Required features: {kvm}`, and never degrades into an unaccelerated or emulated build.
That second case is the intended behaviour: vmTests are opt-in and outside PR gating, so an offline laptop costs a manual re-run rather than a red pull request.
Every builder URI sets `connect-timeout=5`, so a sleeping or off-network laptop is declared unreachable in seconds instead of after the plugin's default 30; once a builder has answered, the plugin rides out a dropped connection for its default `restart-grace` of 120 seconds before failing the build.
`checks.<system>.nix-builders-wiring` pins the entries, store URIs, daemon TLS and access rules, the port opened only on the mesh interfaces, the absence of the retired ssh build accounts across machines, which no single machine's evaluation can see, and that each Darwin builder's job waits for the store and polls, bounded, for every daemon argument under `/run` before the exec.
A change takes effect only after both the dispatcher and the builder are activated.
New VM test modules belong in `vm-tests/` and assign `perSystem.vmTests`, using the same automatically discovered flake-parts composition as the other module directories.
