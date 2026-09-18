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

The 0.12.0 literals in 2.1–2.2 record what S1 verified at the time.
`pkgs/by-name/omnigent/package.nix` has since moved to 0.13.0 and 0.14.0 (`a7c0bd99d`, `2e530409a`) and carries the registered-ACP-harness readiness patch (`421dcf23c`); those bumps travelled on this branch without a row here and are not gated by this ledger.

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

## 14. Worker-only OMP ACP auto-approval

The operator selected the interim `omp acp --approval-mode yolo` launcher policy, explicitly skipping ordinary ACP consent checkpoints without sandboxing or safe-command filtering.
This follow-up authorizes one scoped source commit and controller-owned deployment/UAT after source review; it does not reopen the historical workflow gates above.

- [x] 14.1 Change only the dedicated-worker OMP ACP command and add an exact worker/human preservation regression; observe the pre-fix assertion failure and build `omnigent-worker-capabilities` on `aarch64-darwin` and `x86_64-linux` successfully.
- [x] 14.2 Controller: review the signed source, compare worker/human settings projections, build the affected full systems and activate the reviewed integrated revision.
- [ ] 14.3 Operator/controller: record UAT from fresh worker sessions separately; the operator accepts basic Omnigent function in interactive use, and the two named checks below remain untested.

14.2 evidence: the reviewed source built all three systems (`logs/omp-yolo-system-builds-20260917.log`), and the two-platform projection shows only the worker OMP command gaining `--approval-mode yolo` while the human command stays `omp acp` (`logs/omp-yolo-projection-20260917-012229.log`).
Magnetite and pyrite were updated and stibnite activated, each deployed generation's rendered worker registration reading `omp acp --approval-mode yolo` (`logs/omp-yolo-magnetite-{deploy,verify}-20260917.log`, `logs/omp-yolo-pyrite-{deploy,verify}-20260917.log`, `logs/omp-yolo-stibnite-{activation,verify,verify-final}-20260917.log`).
14.3 is partial and stays open: the operator's acceptance is a human attestation about ordinary interactive use, not a tool observation, and it substitutes for neither remaining check.
The fresh-session OMP approval check on stibnite, the intended Darwin-side coverage, was never run and is untested.
Per-OS Atomic ACP execution with a runtime-confirmed model and effort was never run and is untested; its effort half is also not observable today, because Omnigent 0.14.0's ACP client keeps only the `model` config option's `currentValue` and drops every other advertised option's value, including a thinking or effort level (`omnigent/inner/acp_executor.py`, `_note_config_options`), so the UI cannot confirm effort whatever OMP reports.

## 15. Worker-check evaluator reduction

These incident slices reuse the A-labels of section 13's capability slices and are distinct from them; they authorize no publication or deployment.

- [x] 15.1 Incident A1: reduce redundant inventory and platform evaluations; pass focused Linux, Darwin and inventory evaluations/builds and the assertion-filter regression on signed `1eede68cdf966b098a64e9fafd1feaa43ee26c86`.
- [x] 15.2 Incident A2: share the exact reserved-environment predicate between production adapters, replace selector fanout with literal policy tables, and verify adapter sensitivity, effective configuration preservation and bounded focused gates.
- [ ] 15.3 Controller: review A2 and separately establish full-CI resource fit; focused evaluator measurements do not establish aggregate CI headroom.
- [x] 15.4 Incident A3: replace the remaining whole-system mutation matrices with a small maintained suite — narrow literal inventory obligations on the real machines without synthetic delivery copies, one composite Linux invalid configuration, Darwin copied-artifact mutants only, one credential fixture with its positives and the full Python fixtures — and record the sacrificed negative, migration and synthetic-fleet coverage in the service README.
- [x] 15.5 Incident A4: stop evaluating the three real machine configurations a second time for their fleet facts — own the obligations in `flake.lib.omnigentFleetObligations` and assert them from `modules/checks/machines.nix` on the configuration each per-machine toplevel check already forces, leaving `omnigent-worker-inventory` only the cases that need no machine evaluation.
- [x] 15.6 Incident A5: apply the A3 composite treatment to `omnigent-worker-capabilities`, which A3 skipped — replace the ten paired guard-removal rejections with one composite invalid home asserting a sorted literal expected-message set, keep every authority rejection input, the positive homes, the CLI adapters and the runtime probes, and record the sacrificed per-input attribution in the service README.

A1 evidence is indexed in `logs/omnigent-a1-coverage-20260917.md`.
Completed Linux evaluations measured 409 seconds/6,441,902,080 peak bytes before A1 and 259 seconds/5,526,016,000 bytes after A1 under the same 600-second, 8 GiB, zero-swap, 200% CPU service bounds.
These evaluator-only observations exclude daemon memory and retain cache/order confounds; inventory peaked at 8,360,685,568 bytes, close to its 8 GiB limit.
Credentials and capability checks were unchanged and were not rerun for A1; no full-CI pass is claimed.
A2 evidence is indexed in `logs/omnigent-a2-evidence-20260918.md`; its inventory resource gate was superseded by the A3 and A4 reductions.
A3 removed the synthetic inventory delivery fixture and its three extended machine copies, four inventory mutation fixtures, nineteen Linux and ten Darwin whole-system negative fixtures, the leaking disclosure and disclosure-clean systems, the Linux SOPS readiness system, nine paired credential rejection evaluations, the credential fixture's duplicate positive projections and two oversized capability fixtures; the retained runtime probes are unchanged and the Linux gate still produces A2's derivation and output.
Capped probes on magnetite (8 GiB, zero swap, 200% CPU, 600 s, eval cache off, max-jobs 0, no builders, no substitution): Linux 42 s/1,790,222,336 bytes; credentials 254 s/7,214,161,920 before the reduction and 37 s/1,539,985,408 after; inventory 108 s/4,220,223,488 before the relocation and 90 CPU seconds/4,298,604,544 after.
Credentials now meets the ~2 GB/60 s budget; inventory does not, because evaluating the three real machine configurations is itself about 4.3 GB, and those configurations are the faithful source of the fleet and credential facts, so reducing it further means dropping real-fleet obligations rather than optimising fixtures.
Lost coverage is catalogued in `modules/clan/services/omnigent/README.md`: per-guard negative attribution on both platforms, the sudo numeric/alias matrix, the assertion-filter regression, per-real-host Home Manager projections, the server-unit independence comparison, the fleet cache-download fold, human profile/author projections, the credential rejection pairs, Linux SOPS readiness ordering, and evaluation-time disclosure detection.
A3 evidence is indexed in `logs/omnigent-a3-small-suite-20260918.md`; no full-CI pass, publication or deployment is claimed.
A4 moved every real-machine obligation out of `omnigent-worker-inventory` into `modules/lib/omnigent-fleet-obligations.nix`, asserted by `checks.x86_64-linux.nixos-magnetite`, `checks.x86_64-linux.nixos-pyrite` and `checks.aarch64-darwin.darwin-stibnite`; each host's obligations are now checked only on that host's own system, and `aarch64-linux` no longer evaluates any machine for Omnigent.
That distribution is not purely a saving: nixbot evaluates only `checks.x86_64-linux`, so stibnite's obligations left CI coverage entirely and are now verified only by whoever evaluates `aarch64-darwin` locally, which the service README records as accepted rather than repaired.
Machine configurations evaluated across the omnigent-related checks fell from thirteen to four (x86_64-linux five to two, aarch64-darwin five to two, aarch64-linux three to zero); the one remaining duplicate is stibnite in the Darwin credentials check, which A4 leaves unchanged.
Capped probes on magnetite (8 GiB, zero swap, 200% CPU, 600 s, eval cache off, max-jobs 0, no builders, no substitution, with import-from-derivation paths warmed beforehand): inventory 115 s/4,299,153,408 bytes before and 3 s/192,364,544 after; `nixos-magnetite` 64 s/2,784,165,888 before and 65 s/2,792,300,544 after; `nixos-pyrite` 66 s/2,877,292,544 before and 67 s/2,878,234,624 after.
The obligations therefore cost about 0.3% of the machine check they now ride on, and the inventory check meets the ~2 GB/60 s budget; the machine checks exceed it on the pre-existing cost of evaluating a whole system, which A4 neither created nor changed.
Each machine check's derivation is bit-identical to the plain toplevel in the same tree, verified by `drvPath` equality, so the assertion adds no build input.
Ten obligation cases were verified to discriminate, each mutation tripping exactly its own case; the per-case report attribute the inventory check published for these cases is gone, and a failure now names its case in the machine check's assertion message.
A4 evidence is indexed in `logs/omnigent-o1-obligations-20260918.md`; no full-CI pass, publication or deployment is claimed.

A follow-up correction pass appended each host's own failing assertion messages to the obligation assertion, so a mutation breaking both an obligation and a module guard reports the case names and the module's diagnostics together; gated the per-owner cases on the worker being declared, so dropping a declared worker fails as `workerRoster` instead of aborting with a missing-attribute error; and removed the `enrollmentDiagnostics` case, which duplicated the forced toplevel once enrolled and tolerated failures that the forced toplevel throws anyway while unenrolled.
`enrollmentDiagnostics` is the only member of the earlier discrimination set that is gone; the two corrections were re-probed by mutation, baselines for the three obligated machines remain empty, and each machine check's `drvPath` remains equal to its plain toplevel.
Correction-pass evidence is indexed in `logs/omnigent-corrections-20260918.md`; no full-CI pass, publication or deployment is claimed.

A5 replaced the capability check's ten `rejected` calls — each of which evaluated the worker home twice, once to observe the rejection and once with that guard filtered out of `assertions` — with one composite invalid home whose failing-assertion messages must equal the four authority messages exactly, removing about twenty Home Manager evaluations while keeping every rejected input, the positive homes, the CLI Home Manager and system adapters and every runtime and artifact probe.
The composite reads the failure set through an `assertions` apply that records and neutralises failures, because Home Manager throws before `config` is readable when any assertion fails; messages are forced only for assertions that already failed, so the lazy-message hazard seen earlier on this branch does not apply.
What is lost is per-input attribution: each of the four signing inputs and each of the four foreign-reference inputs previously failed its own named case, and the composite now proves only that the four guards fire together on a home carrying all ten inputs.
Each of the ten inputs was individually verified to fire exactly its own guard and no other, and the unmutated home produces no failures; deleting the SSH-socket guard from `modules/home/ai/omnigent/worker.nix` reduced the composite to three messages and failed the check, and an extra guard firing only on the invalid fixture raised it to five messages and failed the check.
Capped probes on magnetite (8 GiB, zero swap, 200% CPU, 600 s, eval cache off, `max-jobs 0`, no builders, no substitution, one at a time on an idle host, both trees identical except this file): before, OOM-killed at the 8,589,934,592-byte cap after 104 s and 73.7 CPU seconds; after, success at 5,696,696,320 bytes in 74 s and 50.5 CPU seconds with zero swap.
`checks.x86_64-linux.omnigent-worker-capabilities` then built successfully on magnetite from the same source, and both platforms' derivations evaluate with every case passing.
The check still exceeds the ~2 GB/60 s budget: what remains is the positive worker home, the clean home, the wrapped-credential home, the CLI Home Manager home, the two `git-xet` ownership homes, the duplicate-capability composition, the two positive control homes, the composite invalid home and one whole `nixosSystem`/`darwinSystem` for the CLI system adapter.
A5 evidence is indexed in `logs/omnigent-a5-capability-composite-20260918.md`; no full-CI pass, publication or deployment is claimed.

Full-CI resource fit, which 15.3 asks for, remains unestablished: `logs/nixbot-oom-root-cause-report-20260917-203600.md` records nixbot build 497 failing at `2dfb25332` with an evaluator SIGKILL and explicitly declines to promote any local success to a full-CI claim, and no full-CI run after the A3–A5 reductions is recorded here.
