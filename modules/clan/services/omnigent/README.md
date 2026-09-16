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

## Dedicated-worker inventory

The inventory prepares Cameron and Janette on magnetite and pyrite, and Cameron alone on stibnite.
All five workers initially have `enable = false`; their accounts and Home Manager generations remain declared while stopped.
Linux account declarations live in `inventory/services/users/omnigent-workers.nix` and use normal UID/private-group allocation with locked passwords and `0700` homes.
Stibnite declares `omnigent-cameron` with UID/GID `551` and a private `/Users/omnigent-cameron` home, without changing `system.primaryUser`.
The deployment plan records the operator's allocation approval and separate declared/live collision evidence.
No provider identity, model grant, SSH key or signing credential is inherited or enrolled by these declarations.

Janette's canonical profile and worker owner are `janettesmith`; her Linux account is `omnigent-janettesmith`, with host names `magnetite-janettesmith` and `pyrite-janettesmith`.
Her primary/SSO mail is `janette.a.smith@gmail.com`, her GitHub username is `janetteasmith`, and her Git/jj author mail is `125711642+janetteasmith@users.noreply.github.com`.
The existing `github-email` helper verified that author address during read-only B1 research, recorded in `.atomic/workflows/runs/fan-out-and-synthesize-47eef966-2b3f-4a5b-8a3e-57860db40b96/branch-01-b1-janette-identity-and-sso-mapping.md`.
Evaluation and activation use the recorded constant, never a GitHub lookup.
`meta.gitEmail` defaults to `meta.email` for other profiles; Janette's human author mail and `allowed_signers` principal use her explicit Git address without changing signing authority.
Her Git configuration also derives `[github] user = "janetteasmith"` from `meta.githubUser`, following the existing human-profile convention.
Only her non-secret name and Git address reach worker HM through `extraHomeModules`; neither her human modules nor `contentPrivate` are imported.
Both Janette's and Raquel's human profiles remain, as do Cameron's three workers.
The historical Raquel preparation matrix and activation candidate are superseded, not Janette activation evidence or a current activation target.

`checks.<system>.omnigent-worker-inventory` evaluates the actual fleet modules, the exact five-worker matrix, private accounts, prepared Home Manager ownership and ordinary Nix access.
Its negative fixtures cover missing or extra workers, wrong owner, shared home, administrative/Nix-trusted authority, denied Nix access, SSH keys and signing inheritance.
It checks clan settings serialization without `extraHomeModules`, preserves server behavior when workers are toggled, and exercises both disabled and enabled supervision as fixtures.
The identity phase additionally requires all five real workers to remain disabled through credential preparation and asserts Janette's canonical author and signer principal.
Controller gates compare complete protected projections against fixed, same-role chain and integrated baselines, allowing only Janette's asserted Git/jj mail, signer principal, GitHub username and their generated artifacts.
Live Linux collisions, allocated IDs, effective sudo/trust and actual home permissions must still be checked before authorized activation or enablement as specified in the deployment plan.

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

## Selected static credentials

`workers.<name>.credentials` is a typed interface on both plain host modules and the serializable Clan role.
`signingKey` and `claudeSetupToken` have independent default-off `enable` flags and explicit `generator`/`file` names.
`githubTokens` is keyed by lowercase resource-owner login; each default-off entry selects `<worker-user>-github-token-<owner>`, fixed file `token`, and the authenticated person's `expectedLogin`.
Every enabled GitHub entry must expect the same person; resource owners are not authenticated user identities.
`linearApiKeys` is keyed only by the masked labels `personal` and `work`; each default-off entry names a generator `<worker-user>-linear-<label>` with fixed files `key`, `workspace`, `workspace-id` and `viewer-email`.
All four files are secret services files: the workspace slug and verifier identities must never be Nix literals.
Enabled sources declare per-person shared hidden-prompt Clan generators (`share = true`), with secret services files owned by the worker and mode `0400` on each host.
They do not enroll values automatically.
The adapters check the declared ciphertext source and consume `files.<name>.path`; personal bundles, age identities and `hm-sops-bridge` enrollment remain prohibited.
All five inventory workers now declare signing-key and GitHub-token sources while execution remains disabled.
Signing generators use `<worker-user>-signing-key` (file `key`); GitHub generators use `<worker-user>-github-token-<owner>` (file `token`), with canonical expected identities derived from person metadata.
Cameron's workers select GitHub owners `sciexp` and `cameronraysmith`, with `defaultOwner = "cameronraysmith"`; Janette's select only `sciexp`, also her `defaultOwner`.
Cameron's workers select `personal` and `work`; Janette's select only `personal`.
Claude setup-token delivery remains disabled.
These declarations do not enroll ciphertext: the real machine configuration must fail its credential source assertions until the operator enrolls every selected source under `vars/shared`.
Worker `enable = false` does not bypass that prerequisite for building or deploying the machine.
The inventory check evaluates the five declarations with explicitly synthetic delivery files, retains non-secret Clan inputs, and separately requires the real configuration's missing-source diagnostics for each unenrolled worker.
After authorized enrollment commits the ciphertext, the real configuration's source assertions must pass instead; the check accepts that transition without relaxing production guards.
See the deployment plan's enrollment sequence for the exact generator and multiline signing-key commands.

Git and jj sign with the selected private-key file, using the declared public key and canonical Git email for `allowed_signers`.
Git's absolute HTTPS helper uses the token-reading `programs.gh.package` wrapper.
The worker sets `credential."https://github.com".useHttpPath = true`; its helper chooses only the token whose owner exactly matches the request path's first segment.
Unknown owners, absent repository paths and non-GitHub/non-HTTPS requests return no credential, with no default-owner or ambient-token fallback.
The helper does not persist or erase credentials.

For other `gh` commands, token selection uses `OMNIGENT_GH_OWNER`, then the owner in `git remote get-url origin` when it names github.com, then `defaultOwner`.
An unknown selected owner or no selection fails closed; worker Home Manager sets no `OMNIGENT_GH_OWNER` default.
Use `OMNIGENT_GH_OWNER=sciexp gh pr create` to select the organization grant explicitly.
Any `GH_REPO` or `-R`/`--repo` owner must match the selection, or the wrapper fails with an `OMNIGENT_GH_OWNER` diagnostic.
The wrapper passes arguments and repository selection through unchanged; the origin shortcut is not gh's upstream/base-repository resolution.
Positional targets and API paths can still address other owners; the selected fine-grained token has no access there and GitHub returns 404/403.
This boundary depends on issuing genuinely owner-scoped fine-grained tokens, not classic PATs; the identity verifier checks login, not grant scope.

Linear's system-SOPS template substitutes both workspace names and API keys from the selected secret files, matching the human personal/work masking pattern without importing human credentials.
It renders only under `/run/secrets/rendered/omnigent-<worker-user>-linear`, owned by the worker with mode `0400`; SOPS must not create paths inside worker homes.
Home Manager owns `~/.config/linear/credentials.toml` through an out-of-store symlink, so credentials are read at runtime rather than copied into the Nix store.
Pinned `schpet/linear-cli` v2.6.0 has no credentials-file override: `src/credentials.ts:26-42,136-143` resolves the file through `XDG_CONFIG_HOME` or `HOME` and reads it at runtime (see local: `/Users/crs58/ghq/github.com/schpet/linear-cli`).
Readiness checks the rendered file before Home Manager creates its link; Linux's SOPS dependencies and Darwin's delivery receipt remain unchanged.
The wrapper accepts exactly one explicit `--workspace` slug from the delivered workspace files, not a label; it disables `.env` loading, strips endpoint overrides and rejects competing `api_key` sources, including the effective Git root.
Optional native Claude token injection replaces the required runtime executable, not merely a shadowed profile entry.
Competing Claude credentials fail closed.
Process-scoped injection limits incidental inheritance; it does not hide grants from code running as the worker or from host administrators.

Credential-dependent Linux Home Manager activation and host startup check required files and depend on the SOPS service when it owns delivery.
Darwin serializes activation and boot invocations of the maintained privileged installer, then publishes a root-owned manifest/boot receipt only after successful delivery.
The worker requires that receipt and readable files before standalone Home Manager and host execution, including after reboot.
No network verification runs at startup, and workers never invoke privileged decryption.

The separately invoked `omnigent-worker-verify` queries `gh api user` with each selected owner token and compares its login with that entry's `expectedLogin`.
It compares other authenticated provider responses with `credentials.expected` and reads each Linear grant's expected slug, viewer email and workspace ID from its delivered files at runtime.
Linear prompts persist to their secret files, so `--no-regenerate` reuses pre-enrolled metadata and prompts only for missing values.
Invoke it only during authorized enrollment; local `owner` labels are not identity evidence.
Grant issuance, Kanidm person provisioning, recipient/scope approval, real enrollment, renewal and provider-side revocation remain human/deploy-gated.
Static grants are shared across the person's referencing hosts, never across people; GitHub grants remain separate for each resource owner and Linear grants for each masked label.
Rotate a static file with one authorized `CLAN_NO_COMMIT=1 clan vars set magnetite <generator>/<file>`, route the ciphertext, then redeploy every referencing host.
Clan resolves the shared generator's complete machine recipient list; adding a referencing machine requires the authorized Clan generation/fix step to re-encrypt existing shared secrets before deployment.
See the deployment plan's shared-credential migration section for pinned Clan source citations and the old-ciphertext migration procedure.

Atomic, native Pi, independent omp, Codex and Omnigent retain their tool-owned mutable OAuth directories and existing selectors.
There is no seed import or restoration after logout, deletion, redeploy, restart or rollback.
The accepted execution mode remains `sandbox:none`, with same-UID/admin access and shared-store visibility for approved projects.
`checks.<system>.omnigent-worker-credentials` uses synthetic material and mocked provider/delivery effects; live acceptance remains separate.
The designated follow-up is systemd `LoadCredential`, optionally `LoadCredentialEncrypted` after hardware verification, not an implementation in this slice.

## Worker model login and renewal

Run `nix run .#omnigent-worker-login -- HOST OWNER TOOL` from an administrative workstation.
The helper selects the dedicated account and its installed profile, clears inherited credentials and agents, and runs the tool from the worker's home.
It does not change the human account's authentication or synchronize OAuth files.
The current matrix is Cameron on magnetite, pyrite and stibnite, and Janette on magnetite and pyrite.
Use `cameron` or `janettesmith` as `OWNER`.

```sh
nix run .#omnigent-worker-login -- pyrite cameron claude
nix run .#omnigent-worker-login -- pyrite janettesmith atomic
nix run .#omnigent-worker-login -- stibnite cameron codex
```

`claude` starts subscription login; `codex` starts device login.
`atomic`, `omp` and `pi` open their interactive interfaces, where `/login` selects the intended provider.
Each login receives its own refresh state even when the underlying subscription is shared.
`verify` runs the GitHub, Linear, signing-key and Omnigent identity verifier; it does not attest model login or a model turn.
Remote access uses SSH without agent forwarding; local Stibnite access uses sudo.
The operator must already have the required administrative access.

Do not rsync, merge or bidirectionally synchronize rotating OAuth records between active workers.
Codex can reject a reused refresh token, so filesystem synchronization is not an authentication-renewal protocol.
Selected static credentials continue to use shared Clan vars.
Omnigent's first-party non-rotating grants may be distributed to the same person's workers with explicit approval, coupling revocation and expiry; never copy host IDs or whole configuration directories.
