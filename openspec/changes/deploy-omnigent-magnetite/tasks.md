## 1. S0 amend-plan

This ledger follows the S0–S3 contracts in `.atomic/workflows/runs/deploy-omnigent/omnigent-magnetite/d0064db1-3756-4e49-ae30-e03f23ca0bd7/`.
The `slice-N.json` references below resolve under that evidence root.
All checkboxes are pending controller acceptance, including the tracking work performed during binding.
Remote operations, including the Linear readback gate, builds on remote machines, version-control changes, and deployment belong to the controller, never to a scoped writer.
The `.#` examples below identify attributes, not substitutes for the current contracts' `__OMNIGENT_SOURCE__` input; the controller resolves that input before executing the literal S1–S3 gates.

- [ ] 1.1 Bind the HIL proposal to one CAM story in the new omnigent-magnetite project and extend only that project's registry entry — verify: Linear readback matches the proposal frontmatter and `openspec/linear.yaml`, with no design or task copy in Linear.
- [ ] 1.2 Amend `docs/notes/development/omnigent/deployment-plan.md` to add the host `environment` option and `PI_ACP_PI_COMMAND=atomic`, `PI_CODING_AGENT_DIR=/home/cameron/.atomic/agent`, and `OMNIGENT_RUNNER_ENV_PASSTHROUGH=PI_ACP_PI_COMMAND,PI_CODING_AGENT_DIR` — verify: all host-environment GrepAssert gates in `slice-0.json` pass.
- [ ] 1.3 Require foreground `omnigent host --server https://omni.scientistexperience.net`, reject both `--background` and `omnigent host enable`, and include the exact pinned ACP stanza with Atomic beside Pi in the catalogue — verify: the foreground and `acp:` gates in `slice-0.json` pass and the stanza matches the supplied ACP research.
- [ ] 1.4 Correct inventory placement to `modules/clan/inventory/services/omnigent.nix`, state that no two-role precedent exists in this repository, and replace Kanidm fork-URL citations with the local `/Users/crs58/ghq/github.com/kanidm/kanidm` checkout and the relevant recorded pin — verify: the inventory, precedent, local-source, and negative fork-citation gates in `slice-0.json` pass.
- [ ] 1.5 Set the planning admission decision to allowed-domains unset, administrator `cameron.ray.smith@gmail.com`, and Kanidm group-gated access; document one worker for in-memory CLI tickets and the WebView/system-browser `/auth/cli-login` flow using one confidential client — verify: the corresponding admission, worker, email, and mobile gates in `slice-0.json` pass.
- [ ] 1.6 Restate R9 that sandbox `read_paths` must include `/nix/store` for Nix executables and that this weakens isolation — verify: the R9 gate in `slice-0.json` passes without representing the initial native sessions as sandboxed.
- [ ] 1.7 Amend `packages/docs/src/content/docs/development/operations/identity/kanidm.md` to document accepted `yopass.se` delivery, workstation `clan vars get`, granting an existing person `omnigent_users` membership, and the scope-mapped `/ui/apps` tile with `originLanding` — verify: every identity-runbook GrepAssert in `slice-0.json` passes.
- [ ] 1.8 Complete the schema's remaining planning artifacts without inventing brainstorming output or human approval — verify: `openspec status --change deploy-omnigent-magnetite --json` shows every transitive planning dependency present, and `openspec validate deploy-omnigent-magnetite` exits zero.

## 2. S1 package

Depends on accepted S0.
Only `pkgs/by-name/omnigent/` is writable in this slice.

- [ ] 2.1 Add `pkgs/by-name/omnigent/package.nix` using the PyPI 0.12.0 wheel, `buildPythonApplication`, `psycopg[binary]`, `pythonRelaxDeps`, and a PYTHONPATH-only wrapper — verify: `nix eval --json .#packages.x86_64-linux.omnigent.version` returns `"0.12.0"` and the controller's remote package-build gate in `slice-1.json` passes with an observed source hash.
- [ ] 2.2 Exercise the built CLI rather than a source-tree executable — verify: the exact remote CLI command in `slice-1.json` exits zero and its stdout includes both `server` and `host`.

## 3. S2 server

Depends on accepted S1.
Only `modules/nixos/omnigent.nix`, `modules/nixos/kanidm.nix`, and `modules/terranix/cloudflare.nix` are writable in this slice.
Use the `extendModules` fixture from `slice-2.json`; the clan binding does not exist yet.

- [ ] 3.1 Add the plain server module, static omnigent account, shared PostgreSQL socket/peer connection, database ownership, memory limits, and ordering after and requiring `postgresql.target` — verify: fixture evaluations retain `omnigent`, `matrix-synapse`, and `buildbot` databases, PostgreSQL version starts with `16.`, and the ordering assertion in `slice-2.json` passes.
- [ ] 3.2 Configure confidential client `omnigent`, exact issuer `https://accounts.scientistexperience.net/oauth2/openid/omnigent`, group `omnigent_users`, callback and landing URLs, and scope map `[ "openid" "profile" "email" ]` — verify: the Kanidm group and exact scope-map fixture gates pass, while review confirms PKCE and email verification remain enabled and membership stays operational.
- [ ] 3.3 Declare `kanidm-oauth2-omnigent` with the shared secret and environment carriers and instance cookie generator `omnigent-cookie-secret-omnigent`, delivered through EnvironmentFile entries — verify: both generator-name gates and the cookie-generator fixture value pass, and review checks carrier ownership and both consumer restart units without printing secrets.
- [ ] 3.4 Configure one server worker, omit `OMNIGENT_OIDC_ALLOWED_DOMAINS`, and install the administrator roster containing `cameron.ray.smith@gmail.com` — verify: evaluate the rendered unit command/environment and roster source against these literals, in addition to the server acceptance review in `slice-2.json`.
- [ ] 3.5 Add the unproxied CNAME for `omni.scientistexperience.net` and the loopback nginx proxy with ACME, forced HTTPS, WebSockets, `proxy_read_timeout 1d;`, `proxy_send_timeout 1d;`, and `proxy_buffering off;` — verify: nginx fixture gates pass and `nix build --no-link .#checks.aarch64-darwin.terraform-validate` exits zero.
- [ ] 3.6 Evaluate the complete server fixture without building its machine closure — verify: the toplevel drvPath gate in `slice-2.json` returns a path matching `^/nix/store/.*\.drv$` and every remaining fixture gate passes.

## 4. S3 host-clan

Depends on accepted S2.
Only `modules/nixos/omnigent-host.nix`, `modules/clan/services/omnigent/`, and `modules/clan/inventory/services/omnigent.nix` are writable in this slice.

- [ ] 4.1 Add the plain host module with the environment option, explicit runtime PATH, home directory, memory limits, user `cameron`, foreground `--server` command, and the three S0 environment values — verify: real magnetite host option, unit User, Environment, and ExecStart gates in `slice-3.json` pass.
- [ ] 4.2 Retain `NoNewPrivileges = true` without `RestrictNamespaces`, `SystemCallFilter`, `ProtectKernelTunables`, `ProtectKernelLogs`, `ProtectHostname`, or `ProcSubset` — verify: the exact positive and six-key absence gates in `slice-3.json` pass.
- [ ] 4.3 Add the two-role clan service and its README, derive the host URL from the single server, keep the instance-scoped cookie generator, and bind both roles only to magnetite in the new inventory file — verify: `clan.modules` contains omnigent, both role machine sets equal `[ "magnetite" ]`, and all real server/host configuration gates in `slice-3.json` pass.
- [ ] 4.4 Reject a second server rather than selecting one implicitly — verify: the negative fixture in `slice-3.json` fails with exactly `Omnigent requires exactly one server`.
- [ ] 4.5 Run the single controller-owned remote machine-closure build after composition is complete — verify: the `NixBuildRemote` gate for `.#checks.x86_64-linux.nixos-magnetite` in `slice-3.json` succeeds, with its receipt retained and no duplicate unchanged-input build pass.

## 5. S4 deploy and accept

Depends on accepted S0–S3, reviewed content, controller-owned delivery changes, and the explicit deployment confirmations.
There is no supplied `slice-4.json`.
These tasks follow the `input.deploy` branch in `.atomic/workflows/deploy-omnigent.ts`, `.atomic/workflows/omnigent/deployment.ts`, and the wizard/probes in `.atomic/workflows/omnigent/tools.ts`.
They record future controller and human work, not permission for this writer to perform it.

- [ ] 5.1 Obtain operator confirmation, generate only `kanidm-oauth2-omnigent` and `omnigent-cookie-secret-omnigent`, and route only their generated files into the S3 delivery change — verify: `generate-vars` evidence confirms permitted paths and unchanged foreign content, followed by successful topology verification.
- [ ] 5.2 Resolve the exported omnigent-magnetite bookmark to the verified tip SHA and construct `git+file://<absolute-repository>?ref=omnigent-magnetite&rev=<observed-sha>` — verify: `resolve-deployment-source` records the matching bookmark and SHA and never deploys from `@` or an invented revision.
- [ ] 5.3 Plan DNS from that pinned source, require exactly one create for the Cloudflare CNAME named `omni.scientistexperience.net` and no other resource changes, obtain confirmation, and apply only the unchanged saved plan — verify: `plan-dns` and `apply-dns` receipts preserve the filtered summary and checked hash, with private saved plan files and no secret-bearing plan JSON in logs.
- [ ] 5.4 Activate magnetite with `clan machines update magnetite --flake "$SOURCE"` — verify: `update-machine` records the pinned source URL/SHA and differing before/after `/run/current-system` paths.
- [ ] 5.5 Run read-only deployment probes — verify: `probe-deployment` observes active omnigent, kanidm, and nginx units, the exact discovery issuer, and positive live nginx buffering/vhost counts without claiming those counts prove an end-to-end stream.
- [ ] 5.6 Have the operator run the interactive wizard to grant existing cameron access, copy Atomic credentials only after overwrite confirmation, seed the exact ACP configuration with backup, and log the runner in as cameron — verify: the operator confirms completion, secret values stay out of workflow logs, and subsequent runner probes report the required environment and foreground server command.
- [ ] 5.7 Observe the runner after wizard completion — verify: the active unit's current invocation journal reports `Connected as 'magnetite'` within the controller's 90-second deadline, rather than relying on an old invocation.

## 6. Integration Verification

- [ ] 6.1 Collect each literal controller checklist response for `laptop passkey login`, `/ui/apps tile`, `Android app login`, and `one acp:atomic session` — verify: retain each `passed`, `failed`, or `not tested` response verbatim as `human_attested`, separate from tool observations.
- [ ] 6.2 Preserve the acceptance outcome without weakening a gate — verify: any `failed` response blocks, any `not tested` response leaves acceptance incomplete with a caveat, and only four passed responses yield `human_attested`, never independently verified acceptance.
- [ ] 6.3 Reconcile the HIL ledger and Linear state from accepted evidence, preserving review gates — verify: the first checked task triggers In Progress, a genuine verify artifact triggers In Review, and Done is withheld until successful archive after human-steered code and documentation review.

## 7. Janette identity slice

This amendment leaves the historical S0–S4 ledger and Raquel preparation evidence unchanged.
The old Raquel activation candidate is superseded; no enrollment or activation is authorized here.
Checkboxes remain pending controller acceptance.

- [ ] 7.1 Replace only Raquel's experimental workers on magnetite and pyrite with disabled `janettesmith` workers and bind their Git/jj names and author mail through the Nix-only hook; retain both human profiles and Cameron's three workers.
- [ ] 7.2 Verify `omnigent-worker-inventory` and `omnigent-worker-capabilities` on `aarch64-darwin` and `x86_64-linux`, plus the existing platform-specific Darwin and Linux checks, including canonical identity and discriminating negative fixtures.
- [ ] 7.3 Controller: compare protected projections C1/C0 and J1/J0 against the original fixed baselines, allowing only Janette's asserted human Git-mail, jj-mail, signer-principal and GitHub-username differences and their generated artifacts; retain all other human, server, Cameron-worker and stibnite behavior.

## 8. Dedicated-worker credential slice

This amendment leaves identity delivery and historical phase gates unchanged.
The slice declares only selected static credentials and synthetic checks; real grant issuance, enrollment and worker enablement remain human/deploy-gated.
Checkboxes remain pending controller acceptance.

- [ ] 8.1 Add typed, default-off signing, GitHub, workspace-specific Linear and optional native Claude credential sources, delivered by host-local Clan hidden prompts as worker-owned `0400` services files; reject personal bundles, age-bridge enrollment and SSH forwarding.
- [ ] 8.2 Bind Git's absolute HTTPS helper to the token-reading `programs.gh.package`, render explicit Linear workspace mappings without human imports, and bind optional Claude injection at Omnigent's native executable resolution.
- [ ] 8.3 Require Linux delivery readiness and serialize Darwin's privileged activation/boot installer with a root-owned manifest/boot receipt before standalone Home Manager and host execution.
- [ ] 8.4 Verify canonical signing and mocked provider identities with the separately invoked `omnigent-worker-verify`; preserve tool-owned OAuth state through restart, redeploy, rollback and deletion.
- [ ] 8.5 Controller: build `omnigent-worker-credentials` on both systems, retain prior capability/platform/inventory checks, and compare candidate projections only with their matching fixed chain/integrated baselines.

## 9. Worker credential declarations

This follow-up declares sources without issuing grants, enrolling ciphertext, enabling workers or activating machines.
Controller acceptance remains separate.

- [ ] 9.1 Declare signing-key and GitHub-token generator/file sources and canonical expected identities for all five workers; leave Linear empty, Claude delivery off and worker execution disabled.
- [ ] 9.2 Evaluate the inventory against synthetic delivery fixtures and separately require the real unenrolled fleet to fail closed with the missing-source diagnostics for every worker; require real source assertions to pass after ciphertext enrollment.
- [ ] 9.3 Build inventory and credential checks on both systems, compare protected human/server projections with the credential run's fixed supplemental integrated baseline, and verify formatting and signed child routing.
- [ ] 9.4 Operator: approve scopes and recipients, run only the deployment plan's explicit per-machine GitHub generation and multiline signing-key set commands, route ciphertext, and re-evaluate before separately authorized activation.

## 10. Masked Linear declarations

This follow-up supersedes section 9's empty Linear mappings without enrolling material or enabling execution.
Controller acceptance remains separate.

- [ ] 10.1 Restrict `linearApiKeys` to masked `personal`/`work` labels; declare `<worker-user>-linear-<label>` generators with secret `key`, `workspace`, `workspace-id` and `viewer-email` files and runtime-only slug/identity resolution.
- [ ] 10.2 Select personal/work for Cameron on magnetite, pyrite and stibnite, and personal only for Janette on magnetite and pyrite; retain real unenrolled fail-closed assertions and serializable Clan settings.
- [ ] 10.3 Reject a synthetic literal-slug key before implementation, then verify synthetic file-backed rendering, runtime selection and identity rejection with the pinned resolver and existing Git-root/endpoint guards; build credentials/inventory checks on both systems and preserve protected human/server and capability/adapter projections.
- [ ] 10.4 Operator: follow deployment-plan section C2 to pipe only approved key/workspace entries into the named generators, prompt for identity metadata and Janette's own key, route ciphertext and verify identities before separately authorized activation.

## 11. GitHub resource-owner tokens

This follow-up replaces the single GitHub token without enrolling grants or enabling workers.
Controller acceptance remains separate.

- [ ] 11.1 Replace `githubToken` with default-off `githubTokens.<owner>` entries, owner-specific generators, fixed `token` files, per-entry expected person logins and nullable `defaultOwner`.
- [ ] 11.2 Select Git HTTPS credentials exactly by request path with `useHttpPath`; select gh tokens by explicit environment, GitHub origin, then default owner, rejecting repository override mismatches without reproducing gh's command grammar or remote heuristics.
- [ ] 11.3 Verify each token's login and two-owner synthetic selection, unknown-owner rejection, mismatch rejection and non-disclosure; build credentials/inventory checks on both platforms and preserve protected projections.
- [ ] 11.4 Operator: issue fine-grained PATs separately for each person/resource owner, inspect owner scope and 90-day expiry, enroll only the named host-local generators, then verify identity after separately authorized activation.

## 12. ZeroTier MSS lifecycle correction

This bounded follow-up permits configured Nix builder transport, not host activation, account changes, credential access or enrollment.
It preserves the Omnigent service and worker profile bindings; controller acceptance and live application acceptance remain separate.

- [x] 12.1 Record observed regression: successful cinnabar IPv4/IPv6 listings contain six copies of each exact rule, corroborated by pinned append-only startup/reload source. The pre-fix VM attempt timed out during dependency construction; the corrected-candidate runtime check passed, but no automated pre-fix lifecycle failure is claimed.
- [x] 12.2 Make installation and reload converge to one exact legacy-owned rule per family/direction, clean those rules on stop, preserve unrelated mangle rules/chains and propagate material failures; retain fixed MSS 1300 and role attachment. Verified by the isolated Linux VM, including startup migration and both TCP directions.
- [x] 12.3 Build both platform `zerotier-mss-clamp` checks and the Linux `zerotier-mss-clamp-runtime` lifecycle check; verify enabled/backend/IP-family variants, all NixOS members and unchanged Omnigent unit/Home Manager/profile projections, then run `nix develop -c prek run --all-files` with full logs and exits. All exited 0; evidence is indexed in `logs/zerotier-mss-acceptance-20260915.md`.
- [ ] 12.4 Controller: independently review the candidate, route one signed child of `fe29da8376188eb5e5edc1460860ba5cee236f03` while preserving the integrated join and peers, and build magnetite from that exact routed join revision.
- [ ] 12.5 Operator: separately approve normal `clan machines update magnetite` pinned to the final built join; ProxyJump remains an alternative. Require switch exit 0 and pending-work completion, one rule each across a firewall restart, fresh direct Cameron SSH and both workers; stop on a repeated logind race. Cinnabar cleanup remains a separate activation.

## 13. Capability refinement

These source slices preserve current inventory, credentials, server behavior and human aggregate membership.
Earlier disabled-worker tasks record preparation, not a request to disable the currently enabled fleet.
The current source delivery covers A3 after A1/A2; A4 authority-sensitive review remains separate, and no activation, enrollment, grant issuance or publication is authorized.
Checkboxes remain pending controller acceptance of the named evidence.

- [ ] 13.1 A1: record the refined contract and independently export existing OpenSpec/Mergify declarations, preserving module identity, human enablement and OpenSpec schemas/configuration; compare captured human package versions/settings/files/activation before and after, evaluate standalone default/disabled/enabled and duplicate-import fixtures without personal secrets or `osConfig`, and build focused generated-file checks on Darwin/Linux.
- [ ] 13.2 A2: extract repository-acquisition and engineering-tools groups plus the existing nix-development group; preserve human membership through constituent selection, compare matching human projections and exercise local lookup, structured-data processing, task execution and shell checking in disposable fixtures.
- [ ] 13.3 A3: explicitly select worker capabilities and close Git/jj's declared editor and git-xet dependencies in their owning features without the personal editor bundle; extend capability checks to exercise the generated supervisor PATH without login-shell initialization, schema resolution and local Git/jj/acquisition operations while retaining runtime precedence and procps selection.
- [ ] 13.4 A4: review Mergify's authentication adapter and any selected stack-land `GH_BIN` wrapper route without new grants; test synthetic owner selection and unknown-owner/ambient-agent/personal-secret rejection, then run existing capability, credential, inventory and platform-adapter checks on Darwin/Linux.
- [ ] 13.5 Controller/operator: review the exact signed source and evidence before separately authorized deployment; retain partial/untested live acceptance explicitly rather than treating evaluation/build success or the prior CLI deployment as acceptance of these new capabilities.

A2 source and focused verification evidence is indexed in `logs/capability-a2-evidence-20260916.md`.
It compares immutable human projections, including package versions, zoxide settings, enabled file definitions and activation DAG/scripts, with store hashes normalized explicitly rather than claiming byte-identical derivations or live activation equivalence.
The task checkbox remains pending controller review of that delivery.

A3 source and fixture verification evidence is indexed in `logs/capability-a3-evidence-20260916.md`.
Workers select the independent capabilities with plain Neovim and Git-owned xet dependencies; OpenSpec schema assets resolve from their owning flake, including system-integrated consumers.
Mergify is installed but authenticated external workflows remain unverified and reserved for A4.
The A3 checkbox remains pending controller review, not deployment or live acceptance.
