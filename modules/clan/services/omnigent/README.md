# Omnigent clan service

The `server` role enables the plain Omnigent NixOS module; the `host` role connects a foreground runner to that server's HTTPS domain.
Magnetite is the only server and the always-on co-located host; stibnite is the Darwin host, and pyrite is the third host, an intermittently available NixOS laptop.
Each host requires exactly one server in its instance.
On NixOS, `perMachine` imports both plain modules once even when a machine holds both roles.
On Darwin, the host role imports `flake.modules.darwin.omnigent-host`; its legacy agent selects the existing primary user by default.
The legacy host retains its fixed name; dedicated workers use one platform supervisor per worker key within the same clan instance.

The server interface exposes `domain` and `port`.
It uses the confidential Kanidm client `omnigent`, the `kanidm-oauth2-omnigent` environment file, and an instance-scoped cookie generator.
The host interface exposes a nullable `user`, non-secret `environment` values and `extraPackages`, a list of nixpkgs attribute names that defaults to `[ ]`.
Use names such as `"hello"` or dotted paths such as `"python3Packages.requests"`; each platform resolves them against the host's `pkgs` and appends them to the required host and runner PATH.
Names keep the clan role interface JSON-serializable; the plain `services.omnigent-host.extraPackages` option accepts package values directly.
Set `roles.host.machines.<machine>.settings.user` to select an existing account on that machine; the default `null` leaves account selection to the platform.
NixOS selects the unique normal `wheel` user with a Home Manager configuration and requires an explicit user when there are zero or multiple candidates.
Darwin retains `system.primaryUser` as its default.
Pinned Clan treats each machine's inventory `settings` as one non-mergeable value: add `user` inside its existing settings block, or replace the complete block while preserving its environment values.
An independent module cannot add only `settings.user` beside an existing machine settings definition.
The shared inventory `extraModules` entry runs on both NixOS and Darwin and derives `PI_CODING_AGENT_DIR` from the selected account's actual home.
Role settings carry only the home-independent environment pair.

The NixOS host supplies the same environment through both `systemd.services.omnigent-host.environment` and `serviceConfig.Environment`.
The S3 contract inspects the latter, but pinned nixpkgs renders the former directly into unit text rather than populating that key (`nixos/lib/systemd-lib.nix:779-793`).
Both carriers derive from one attribute set and use nixpkgs' JSON quoting, so the repeated assignments have identical values.

## Runner state

The NixOS runner reads the selected existing account's credentials; both magnetite and pyrite currently select `cameron`, while stibnite selects `crs58`.
Both platforms derive HOME and working directory from `config.users.users.${cfg.user}.home`; the shared inventory uses that home for Atomic state, and Darwin also uses it for logs.
The aliases map reuses `crs58`'s Home Manager content under `cameron`; it does not rename Unix accounts.
Home Manager enables `programs.omnigent` with the same package and merges `host.name` and the shared ACP definitions into writable `~/.omnigent/config.yaml`.
The merge preserves undeclared runtime state, including `host.host_id`; it must not become a Nix-store symlink.
All three hosts use the exact shared `Atomic` / `bunx pi-acp@0.0.33` and `Oh My Pi` / `omp acp` rows from `modules/home/ai/omnigent/acp.nix`.
Both rows disable `omnigent_mcp` and `inject_system_prompt`; Atomic allows `PI_ACP_PI_COMMAND` and `PI_CODING_AGENT_DIR`, while omp's `env_passthrough` is exactly empty so Atomic state does not reach omp.

The host environment carries `PI_ACP_PI_COMMAND=atomic`, `PI_CODING_AGENT_DIR=<selected-home>/.atomic/agent`, and `OMNIGENT_RUNNER_ENV_PASSTHROUGH=PI_ACP_PI_COMMAND,PI_CODING_AGENT_DIR`.
Do not set a conflicting `ATOMIC_CODING_AGENT_DIR`.
Credentials, sessions and host IDs remain local to each runner; never copy state between hosts or publish tokens.

The NixOS module supplies memory limits and `NoNewPrivileges`.
Do not add namespace or mount restrictions that prevent unprivileged bubblewrap from running.
Native sessions are initially unsandboxed; Linux sandboxed sessions need `/nix/store` in `read_paths`, which exposes unrelated store contents and still requires a runtime test.

## NixOS lifecycle

Systemd owns the foreground `omnigent host --server <server-url>` system unit, enabled through `multi-user.target` with `After` and `Wants` on `network-online.target`.
Do not also run `omnigent host enable`, a manual host, or a background daemon.
The required store PATH always contains repository Claude Code and Atomic; llm-agents Codex, Pi and omp; and nixpkgs Bun, Node.js 22, Python 3, tmux, Git, uv and bubblewrap, even with `extraPackages = [ ]`.
It never depends on the user's profile or shell initialization.

Pyrite goes offline on suspend/hibernate and must reconnect automatically on resume or network return without manual restart.
`network-online.target` orders initial boot only; it does not trigger reconnection on resume.
The foreground host's remote reconnect loop repairs outages while the process survives suspend; `Restart=on-failure` and `RestartSec=5` retry nonzero exits.
Five-second retries do not exhaust systemd's default start limit of five starts in ten seconds.
There are no sleep conflicts, suspend hooks or inhibitors, and no network `Requires` or `BindsTo` coupling.
The separate `pyrite-never-sleep` change owns machine sleep policy; this runner neither depends on nor changes that policy and must work whether or not pyrite sleeps.
Authentication expiry is separate from network loss and requires renewed `omnigent login` as the selected user.

## Legacy Darwin lifecycle

Home Manager alone owns `launchd.agents.omnigent-host`, label `org.nix-community.home.omnigent-host`, in the selected user's `user/<uid>` domain.
It waits for `/nix/store` and executes the foreground argv `[ omnigent host --server <server-url> ]` using the configured package's absolute executable.
Do not run `omnigent host enable`, use `--background`, invoke upstream `service_entry`, or install a second plist.
The agent sets `RunAtLoad=true`, `KeepAlive.SuccessfulExit=false`, `ThrottleInterval=5`, and `ProcessType=Standard`.
Launchd's throttle limits respawning; it is not identical to systemd's post-exit `RestartSec` delay.
The user-domain session type may be `Background`, but process QoS must not be `ProcessType=Background`, which can starve runner deadlines.

The explicit store PATH always contains repository Claude Code and Atomic; llm-agents Codex, Pi and omp; and nixpkgs Bun, Node.js 22, Python 3, tmux, Git and uv.
Extra packages follow those requirements, then `/usr/bin:/bin:/usr/sbin:/sbin` supplies native macOS utilities.
Darwin gets no bubblewrap and relies on neither a profile PATH, shell initialization nor `launchctl setenv`.
Both output streams go to `<selected-home>/.omnigent/logs/host/service.log`.
Home Manager creates the private log directory with mode `0700` after `writeBoundary` and `omnigentMergeConfig`, before `setupLaunchAgents`.

A sleeping laptop shows offline and reconnects automatically on wake or network return; offline is expected, not a fault.
There is no network-state load restriction or disabled restart.
An expired login after the roughly 30-day refresh grant can cause throttled foreground restart loops, unlike upstream `service_entry`'s permanent-failure exit mapping.
Inspect the declared log and run `omnigent login https://omni.scientistexperience.net` again as the selected user to renew credentials.

`NoNewPrivileges` has no launchd analogue.
`MemoryHigh` and `MemoryMax` have no aggregate process-tree equivalent on launchd; per-process RSS is not a cgroup limit.
Neither changing plist owner nor setting `ResidentSetSize` restores those Linux guarantees.
Availability before first login, after logout/reboot, Keychain access and macOS Background Items approval remain runtime checks, not evaluation guarantees.

## Human activation and acceptance

Follow this order on stibnite after selecting the configured `services.omnigent-host.user`:

1. Inspect any existing `ai.omnigent.host` agent or manually launched host and deliberately retire competing lifecycle ownership without overwriting state.
2. Log in locally with `omnigent login https://omni.scientistexperience.net`, using the same Omnigent identity as magnetite.
3. Preserve and verify vendor logins, Pi's `~/.pi/agent`, Atomic's `~/.atomic/agent` and omp's `~/.omp/agent`; approve credential replacement explicitly.
4. Only after controller gates and independent review, activate the pinned stibnite configuration through the existing workstation process.
   This workflow's deploy phase still targets magnetite; it does not activate stibnite.
5. Inspect `launchctl print user/$(id -u)/org.nix-community.home.omnigent-host`, its argv/environment and the declared log without publishing tokens.
   Verify the writable configuration has name `stibnite` and a distinct persistent `host_id`, and that magnetite and stibnite appear in the authenticated UI.
6. Explicitly select stibnite and test native Claude/Codex/Pi and ACP Atomic/omp turns, Files after Resume, approvals, independent state roots, sleep/network recovery and logout/reboot recovery.
   Record each outcome as human attestation; evaluations and builds do not prove runtime success.

The controller first builds `checks.aarch64-darwin.package-omnigent`, then `checks.aarch64-darwin.darwin-stibnite` locally after the evaluation gates pass.
The Darwin package and magnetite server configuration are unchanged by this extension.

For pyrite, the controller evaluates S8's account, unit, PATH and shared-settings gates, inspects the actual HM activation's store YAML, and rehearses its merge while preserving a seeded runtime `host.host_id`.
It builds `checks.x86_64-linux.nixos-pyrite` once on magnetite, not pyrite; inspecting the rendered YAML must not require another machine build.
Implementation and these gates do not activate pyrite or establish live acceptance.
The current contract's whole-settings G5 override evaluates successfully; the deployment plan records the earlier partial-override failure and its reconciliation.
Controller artifact/build gates and human acceptance remain separate obligations.

Before later human-controlled activation, select pyrite's configured `services.omnigent-host.user` and follow this order:

1. Retire competing manual, user-unit or background host lifecycles deliberately without overwriting local state.
2. Preserve and verify Omnigent login under the same identity as magnetite, and local vendor, Pi, Atomic and omp credentials in that selected user's home.
   Renew login locally if needed; never copy another host's tokens, configuration or host ID.
3. After controller gates and independent review, use the existing pinned `clan machines update pyrite` process targeting `root@pyrite.zt` as a separate human-controlled operation.
   This workflow's deploy phase activates only magnetite, never either laptop.
4. Inspect `systemctl status omnigent-host` and `journalctl -u omnigent-host`, and verify writable configuration name `pyrite` with a distinct persistent `host_id`, without publishing tokens.
5. Record whether pyrite appears online in the UI host list, an explicitly selected pyrite session completes a turn, and pyrite returns online automatically after suspend/resume without manual restart.
   Only human attestation establishes these live outcomes; also test ordinary network loss and return, keeping expired-login failures separate.

## Dedicated Linux workers

The plain `services.omnigent-host.workers` interface prepares integrated Home Manager configurations for explicitly declared accounts even when each worker's `enable` remains false.
It requires `owner` and `user`; derives home, UID, group and state from the account; and defaults `hostName` to `<machine>-<key>` and `workspaceRoot` to `<home>/projects`.
`owner` records intended association, not application authorization.
No worker inherits the legacy privileged-user selector, human secrets, signing agent, cache-upload credentials, or Nix trusted-user authority.
Accounts require separate private homes, no administrative groups or sudo grants, and ordinary Nix daemon access.
The host checks actual home ownership and mode before starting.

Clan exposes serializable `workers` settings and `legacyEnable`, which defaults to true.
Worker `extraPackages` are nixpkgs attribute names in clan settings and package values in the plain module.
`extraHomeModules` is available only in the plain module.
Keep each machine's clan settings in one complete value, preserving legacy environment additions.
Do not set `legacyEnable = false` until an explicit migration; adding a disabled worker does not retire the old host.

Each enabled worker runs `omnigent-host-<key>.service` as its dedicated account with `UMask=0077`, `NoNewPrivileges`, and the existing restart and memory policy.
Its `Requires` and `After` dependencies on that account's Home Manager system activation prevent startup after failed activation.
Home Manager activation also receives a private umask and `NoNewPrivileges`.
Network-online remains a soft boot dependency, with no sleep or network-lifetime coupling.
The worker PATH orders required runtime packages, its actual Home Manager profile, then extras; neither shell initialization nor a global user profile supplies it.
Atomic retains its ACP-only directory routing, and omp retains independent state.
`autoApproveDirenv` defaults to false; opting in trusts project code under `workspaceRoot` as that worker.

For the first rollout, the user explicitly accepted upstream `sandbox: none` on Linux and Darwin on 2026-09-10.
The dedicated Unix account is the whole-worker boundary, including auxiliaries, terminals and project hooks; this is not child, namespace, or filesystem confinement.
There are no child-sandbox path grants to configure in this mode: normal account permissions govern access, including visibility of approved project inputs in the shared `/nix/store` and the worker profile.
Additional child sandboxing is deferred and must use a supported upstream policy mechanism, not an unused host setting or an inference from bubblewrap's presence.
Credential grants and application-admin permissions remain external authority.
`checks.x86_64-linux.omnigent-worker-linux` covers module composition and configured boundaries; actual selected-harness identity, protected-canary, devshell and lifecycle checks remain required after authorized activation.

## Dedicated Darwin workers

Each enabled worker runs as `system/org.nixos.omnigent-host-<key>`, with the dedicated account in the plist's `UserName`.
The native `/bin/sh` entry waits for `/nix/store`, then invokes an executable launcher that checks private HOME/log directories, activates standalone Home Manager as the worker, and executes the foreground host only on success.
An activation failure exits nonzero even if a previous activation succeeded.
The daemon retains `ProcessType=Standard`, five-second throttling, failure restart and normal sleep behavior.
It requires no worker graphical login, sleep inhibitor, or network-state load condition.

Account declarations remain separate.
They must provide a managed non-root UID, home and group without administrative or Nix-trusted membership.
Before loading launchd jobs, system activation runs preparation as the worker, verifies the allocated UID/GID and creates owner-only HOME, `.omnigent`, `logs`, and `host` parents.
It refuses mismatched ownership and symlink directories rather than taking them over.
The generation is retained at `/etc/omnigent/workers/<key>` even while execution is disabled; authorized onboarding can activate that generation as the worker before enrollment.
The same generation supplies the daemon's activation and profile PATH.
Do not also register the worker in integrated `home-manager.users` or add worker Home Manager launch agents.
The adapter suppresses HM's otherwise unconditional Darwin LaunchAgent reconciliation and disables desktop application copying/linking for these standalone homes.

`checks.aarch64-darwin.omnigent-worker-darwin` follows the realized plist to its launcher, activation generation, profile and declared YAML.
It exercises private-directory preparation and launcher failure handling with disposable state; account lookup and effectful HM activation are controlled test boundaries, not live account tests.
Wrong-user/domain and missing-runtime/profile module fixtures must fail inspection.
The upstream native Pi and configured ACP generation checks retain the accepted `sandbox: none` policy, with no child path grants or namespace-confinement claim.

Keep the human HM agent unchanged until explicit inventory migration retires it.
Before enablement, audit actual UID/GID and effective sudo authority, including numeric grants, aliases and unmanaged macOS memberships that declarations do not resolve.
Static group/trust guards do not prove runtime privilege exclusion; this adapter does not parse arbitrary sudoers text.
Daemon-context authentication, offline activation, actual logout/reboot/wake behavior and selected-harness canaries remain post-deploy acceptance checks.

See the [deployment plan](../../../../docs/notes/development/omnigent/deployment-plan.md) for the exact gates and platform acceptance limits.
