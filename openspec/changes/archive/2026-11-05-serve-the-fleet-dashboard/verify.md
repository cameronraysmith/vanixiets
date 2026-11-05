# Verification Report

> This file is produced by the `openspec-verify-change` skill after apply completes, to confirm that the
> implementation is consistent with the specs / design / tasks. Any failed check must be returned to its
> corresponding artifact for correction before re-running verify.

**Change**: `serve-the-fleet-dashboard`
**Verified at**: `2026-11-05 14:50 UTC`
**Verifier**: `Cam73Closeout (agent), writing tasks.md 6.1 read-only from tasks.md, design.md, proposal.md, plan/, specs/ and logs/cam73-evidence/; the done notes of tasks.md are authoritative, and every evidence file named below is under logs/cam73-evidence/, which is git-ignored, unless it names logs/ directly; it measured no cost and ran nothing on the hosts`

---

## 1. Structural Validation (`openspec validate serve-the-fleet-dashboard --strict`)

- [x] The change reports valid

**Result**:

`openspec validate serve-the-fleet-dashboard --strict` and plan Task 8 Step 2's discharge-name comparison ran on 2026-11-05 against the working copy, after the two statement fixes of the archive paragraph below:

```text
Change 'serve-the-fleet-dashboard' is valid
```

The comparison of every name quoted after `Discharges:` in `tasks.md` against the names this file quotes printed nothing, run with `LC_ALL=C sort -u` on both sides.

If any items fail, list their id and issues:

| Item | Type | Issues |
|---|---|---|
| — | — | none |

**At archive, 2026-11-05 (`openspec validate --all --strict`).**
The criterion is that the archive adds no strict failure, because the repository failed `--all --strict` before the sync for reasons outside this change.
Before the sync, at 14:43:20Z: 11 passed and 31 failed of 42 items (`6.3-validate-before-20261105T144320Z.json`).
The 14 failing changes are `adopt-queue-landing-protocol`, `annotate-discharge-evidence`, `capi-hetzner-cluster`, `declarative-cognee-endpoint`, `deploy-omnigent-magnetite`, `filter-check-sources-for-substitution`, `k3s-nixos-vm-tests`, `path-scope-plugin-releases`, `pyrite-bluetooth-boot`, `pyrite-dankgreeter`, `pyrite-dms-session`, `sso-gateway`, `stand-up-gitea-mq-on-magnetite` and `stand-up-nixbot-on-magnetite`.
The 17 failing specs are `agentic-workflow-routing`, `apple-laptop-hardware-support`, `bare-metal-install-path`, `encrypted-zfs-root`, `first-party-skill-distribution`, `graphical-desktop-session`, `openspec-linear-sync`, `pi-agent-environment`, `project-management-hub`, `requirements-stratification`, `satisfaction-argument-audit`, `shared-reference-tree`, `shared-reference-tree-interface`, `skill-corpus-interface`, `stratified-change-authoring`, `third-party-plugin-dependency` and `world-assumptions`.
`world-assumptions` failed before the sync with 12 warnings: its placeholder Purpose and 11 statements over 500 characters.
`telemetry-store`, `telemetry-store-interface` and this change passed.

A first sync, run on a copy of `openspec/`, added four failures, each one warning:

- spec `telemetry-store`, whose MODIFIED `The telemetry store runs a stable vendor release that serves its dashboard` had a 573-character statement; the delta drops the closing clause "; people read the fleet's signals through the dashboard service, which `fleet-dashboard` requires", which restates the proposal's reason and adds no obligation, so the statement keeps its three obligations;
- spec `telemetry-store-interface`, whose MODIFIED `Credentials exist only as activation-resolved files owned by non-worker users` had a 508-character statement; the delta drops ", the only unit that loads it", which the scenario `A credential is loaded by a unit outside its holders` already states;
- specs `fleet-dashboard` and `fleet-dashboard-interface`, created with the placeholder Purpose `openspec archive` writes; 6.3 writes each Purpose after the sync from the proposal's capability text, as the fleet-collection change did for `fleet-ingress-interface`.

After the archive, at 14:48:55Z: 12 passed and 31 failed of 43 items, with the same 31 failing items (`6.3-validate-after-20261105T144855Z.json`); this change left the list, the new `fleet-dashboard` and `fleet-dashboard-interface` pass with their Purposes written, `telemetry-store` and `telemetry-store-interface` pass, and `world-assumptions` keeps the same 12 warnings.
`rg -n 'perses\.scientistexperience' openspec/specs packages/docs/src/content/docs/development/traceability/satisfaction.md` printed nothing, exit 1.

---

## 2. Task Completion (`tasks.md`)

- [x] All `- [ ]` have been changed to `- [x]`

Every item is ticked; 2.5 and 5.3 were ticked on 2026-11-05 from their logs and the merged pull requests, the done notes of 4.4, 4.5 and 7.1 were amended from `7.1-gaps-20261105T142545Z.log`, and 6.1 to 6.3 were ticked at the archive.

**Incomplete tasks** (if any):

| Task | Reason incomplete | Blocks archive? |
|---|---|---|
| — | — | — |

---

## 3. Delta Spec Sync State

For each delta spec file under `openspec/changes/serve-the-fleet-dashboard/specs/`, compared against the corresponding main capability spec:

| Capability | Sync status | Notes |
|---|---|---|
| `fleet-dashboard` | created at archive | ADDS six requirements; 6.3 writes its Purpose. |
| `fleet-dashboard-interface` | created at archive | ADDS thirteen requirements; 6.3 writes its Purpose. |
| `telemetry-store` | synced at archive | MODIFIES `The telemetry store runs a stable vendor release that serves its dashboard`. |
| `telemetry-store-interface` | synced at archive | MODIFIES `Credentials exist only as activation-resolved files owned by non-worker users`. |
| `world-assumptions` | synced at archive | MODIFIES `Grounded vocabulary for behavioral requirements` (195 main rows, 202 in the delta); ADDS A56 to A60. |

All five synced on 2026-11-05, as `openspec archive` merges them; each main spec now reads as already synced.

---

## 4. Design / Specs Coherence Spot Check

| Sampled item | design description | specs correspondence | Gap |
|---|---|---|---|
| D4 | Kanidm client `perses` with the single scope map `perses_users`, a group stub without members, PKCE, and a session of at most 45 min refresh plus 15 min access | FDI `The identity provider admits only the dashboard group`; FD `A person removed from the dashboard group loses access within an hour` | none at evaluation (`3.4-assertions-20261105T010114Z.log`, `3.5-identity-20261105T010157Z.log`) and at deployment (`4.3-4.4-operator-20261105T140642Z.log`) |
| D5 | two GlobalDatasources with anchored endpoints and a six-header `allowHeaders`, the vhost stripping `x-greptime-auth` | FDI `The telemetry store is read only through two global datasources`, `The dashboard service listens on loopback behind one vhost` | none; the bypass control reaches the store as `admin` only without the allow-list (`3.7-container-20261105T011614Z.log`) |
| D9 | the SQL views chart the first numeric column at synthetic timestamps with labels dropped | FD `An admitted person views the fleet's signals and the dev-loop history by host` | drift recorded in tasks.md 3.3: the GreptimeDB plugin 0.2.1 keeps a timestamp column and treats the other columns as labels, so each SQL query selects `"ts"`, its value and a label column |

**Drift warnings** (non-blocking):

- D9 as above; the design text was not amended, and tasks.md 3.3's deviation (7) records the adapted queries.

---

## 5. Implementation Signal

- [x] All related commits have been pushed
- [ ] No unstaged files in the worktree

The change's pull requests, all merged to `main`:

| Pull request | Merged (UTC) | Content | tasks.md |
|---|---|---|---|
| #3718 | 2026-11-04T23:30Z | the planning pull request | — |
| #3719 | 2026-11-05T00:38Z | the plan corrected after its review | 1.1 |
| #3720 | 2026-11-05T00:59Z | pull request 1: the package, its updater and the lint check | 2.1–2.5 |
| #3721 | 2026-11-05T04:39Z | pull request 2: the service, its identity, resources, checks, container test and generated vars | 3.1–3.9 |
| #3723 | 2026-11-05T13:55Z | the terraform state holding `obs` | 4.1 |
| #3724 | 2026-11-05T14:26Z | pull request 3: the runbook, the decision records and the corpus under charter v28 | 5.1–5.3 |

nixbot passed #3720 with seven ignored failures, its `aarch64-darwin` builds, because no darwin builder was available on stibnite; the darwin package built locally (tasks.md 2.2, 2.5).
nixbot passed #3721 and #3724 with no failed or ignored builds.
The working copy also carries other agents' unmerged chains, which this verification did not inspect.

---

## 6. Front-Door Routing Leak Detector (warning, non-blocking)

```bash
ls docs/superpowers/specs/*.md 2>/dev/null
```

- [x] No files, or any existing files are legitimate residue from before schema installation

**Leak list** (if any):

| File | Content captured into change? | Recommended action |
|---|---|---|
| — | — | — |

---

## 7. Deferred Manual Dogfood vs Automated Test Equivalence

`plan.md` and `plan/task-*.md` have no row marked `[~]`, so this section is blank by the template's rule.
The operator-gated items were 3.6, 3.8, 4.1, 4.3, 4.4 and 7.1; §8b and §10 cite how each closed.

| Deferred dogfood (plan §) | Equivalent automated test | Coverage assessment | Real gap? |
|---|---|---|---|
| — | — | — | — |

---

## 8. Designation lint and discharge coherence

This section is agent-executed and non-blocking.

### 8a. Designation lint

#### 8a.1 Method

The proposal tags `fleet-dashboard` `behavioral` (`proposal.md:52`).
The pass read the title and statement of each of its six requirements, excluding scenarios and the `Discharged by` line.
Each content noun was looked up in the `Term` column of this change's `world-assumptions` delta table, 202 rows: main's 195, every one carried (§8a.3), and this change's seven.
Quantities and identifiers (`magnetite`, "256 MiB", "one hour") were not counted as nouns.

#### 8a.2 Result

Six nouns resolve to a row this change's delta adds: `dashboard service`, `view`, `dashboard group`, `admitted person`, `identity provider` and `browser`.
`chart` is added for the interface and the runbook and does not occur in the six statements.

These nouns resolve to a main row: `person` (the `service` sense), `fleet`, `signal`, `dev-loop history`, `host` (the `fleet` sense), `hostname` (the `service` sense in "its hostname", the `host` sense in "the name of the host"), `collected host` ("each collecting host"), `memory`, `compressed swap`, `process` ("per-process memory"), `out-of-memory` ("out-of-memory kills", "runs out of memory"), `file system`, `storage pool`, `unit`, `disk health`, `queue wait`, `formation-to-land`, `outcome` and `build` (the `build service` sense, in "build outcomes"), `deploy`, `repository` (the `forge-hosted` sense), `commit` ("a committed change"), `store credential`, `store account`, `telemetry store`, `path` and `query language` ("the query paths of its two query languages"), `envelope`, `kernel` and `failure notice`.

Three nouns resolve to no row:

| Noun | Requirement | Finding |
|---|---|---|
| datasource | FD `Nobody changes the views except by a committed change` (statement) | no row; a machine term in a behavioral statement, whose world sense is "where a view's charts read from"; recorded, not changed at archive |
| access | FD `A person removed from the dashboard group loses access within an hour` (title and statement) | no row; the statement grounds it through `admitted person` and `dashboard group`, so it reads as "is no longer admitted"; recorded, not changed at archive |
| member | FD `A person outside the dashboard group is refused` (statement) | no row; the `dashboard group` row defines the group as the people the identity provider lets in, so a member is one of those people; recorded, not changed at archive |

#### 8a.3 Archive-time row check (tasks.md 6.2)

Run on 2026-11-05 before the sync, after the rebase (`6.2-rebase-20261105T144333Z.log`):

```bash
row() { awk '/^\| /' "$1" | grep -vE '^\| *(Term|---)' | LC_ALL=C sort -u; }
LC_ALL=C comm -23 <(row openspec/specs/world-assumptions/spec.md) <(row openspec/changes/serve-the-fleet-dashboard/specs/world-assumptions/spec.md)
```

It printed nothing; `comm -13` printed exactly the seven added rows.
Main's `world-assumptions` spec last changed in `7b03c44ab` ("openspec: archive the external watch of the alert path"), which added `watch service`, `ping` and `email`.
Before the rebase the delta's `Grounded vocabulary for behavioral requirements` block differed from main's only by those three rows and this change's seven; the rebase inserted the three after `day`, in main's order, so the block now equals main's apart from the seven added rows, 202 in all.
This change's assumptions are numbered A56 to A60, after main's A53 to A55, so no renumbering was needed.

### 8b. Discharge coherence

Each behavioral requirement's `Discharged by` line names its interface requirements and world assumptions, and each `tasks.md` `Discharges:` clause names the requirements its task discharges.
Statuses name what was observed: "observed" with its window, "configured" where only the configuration is shown, and "not violated" where nothing exercised the assumption.

| Requirement | Discharged by (tasks, evidence) | Under (W) | Status |
|---|---|---|---|
| fleet-dashboard: `An admitted person views the fleet's signals and the dev-loop history by host` | tasks.md 3.3, 4.4, 7.1; lint over the six resources (`3.3-lint-20261105T005541Z.log`); all 23 committed queries succeed and every PromQL query returns series, and the mutant view query fails the case (`3.7-container-20261105T011614Z.log`); the operator's statement that `fleet-hosts` (all hosts, 6 h) and `devloop` (7 d) showed collected data (`4.3-4.4-operator-20261105T140642Z.log`); the store holds memory samples within 15 min for cinnabar, magnetite and pyrite (`7.1-gaps-20261105T142545Z.log`) | A58 | observed: the views with data between 14:02:08Z and 14:06:42Z, the store's three hosts at 14:25:45Z; the operator did not state per host that the view showed each of the three, and no reading of each host's latest point in the view was recorded |
| fleet-dashboard: `A person outside the dashboard group is refused` | tasks.md 3.4, 3.7, 4.3; the client and authentication clauses with their mutants (`3.2-config-20261105T011100Z.log`); 401 without a session in the container (`3.7-container-20261105T011614Z.log`) and on magnetite (`4.2-deploy-20261105T135344Z.log`); `perses_users` empty at 14:02:08Z and Kanidm's Access Denied, Operation ID `107ac7d5-cccd-4727-9f8e-7dd07937e624` (`4.3-4.4-operator-20261105T140642Z.log`) | A56, A57 | observed once at deployment, 2026-11-05 about 14:02Z |
| fleet-dashboard: `A person removed from the dashboard group loses access within an hour` | tasks.md 3.4; the session clause and the `24h` override failing magnetite's evaluation (`3.4-assertions-20261105T010114Z.log`); the `2-longRefresh`, `2-longAccess` and `2-unparsedTtl` mutants (`3.2-config-20261105T011100Z.log`) | A57, A58 | configured: 45 min refresh plus 15 min access; no removal was performed, so the hour was not observed |
| fleet-dashboard: `Nobody changes the views except by a committed change` | tasks.md 3.4, 3.7, 4.4; the permission, provisioning and wipe clauses with their mutants (`3.2-config-20261105T011100Z.log`); POST, PUT and DELETE 405 and the planted view gone after the restart (`3.7-container-20261105T011614Z.log`); an anonymous PUT to `fleet-hosts` on magnetite 405 (`7.1-gaps-20261105T142545Z.log`) | A58 | discharged at build and in the container; on magnetite the write route is observed absent at 14:25:45Z; a save attempted by an admitted person in the UI was not observed |
| fleet-dashboard: `No store credential reaches a person, and the dashboard service only reads` | tasks.md 3.2, 3.5, 3.7, 4.4; the datasource, credential and vhost clauses with their mutants (`3.2-config-20261105T011100Z.log`); the holder assertion's override (`3.5-identity-20261105T010157Z.log`); the proxy, header, refusal and bypass cases (`3.7-container-20261105T011614Z.log`) | A58, A59 | discharged at build and in the container; the browser's local and session storage on `obs.` were not observed |
| fleet-dashboard: `The dashboard service stays inside its memory envelope and its failures reach a person` | tasks.md 3.2, 3.5, 4.2, 4.5; the memory clause's `11-bigMemory` and `11-highAtMax` mutants (`3.2-config-20261105T011100Z.log`); the kill-order override (`3.5-identity-20261105T010157Z.log`); `OOMScoreAdjust=600` (`4.2-deploy-20261105T135344Z.log`); the kill at 14:06:43Z, the notice the same second (message `CEnLp5DWHqmq`) and the restart at 14:06:54Z (`4.5-kill-20261105T140642Z.log`); `MemoryCurrent` 29 MiB and `MemoryPeak` 56 MiB against `MemoryHigh` 192 MiB and `MemoryMax` 256 MiB (`7.1-gaps-20261105T142545Z.log`) | A31 | observed: the notice and the restart on 2026-11-05 14:06Z; from the restart at 14:06:54Z to 14:25:45Z the unit's peak was 56 MiB, inside the envelope; an out-of-memory kill order was not exercised |
| fleet-dashboard-interface: `The dashboard service runs the vendor's release with its pinned plugins` | tasks.md 2.2, 2.4; both builds, `percli version` 0.55.1 and the `Prometheus` 0.59.0 mutant failing the install check (`2.2-package-20261105T003659Z.log`); the plugin clause with its tmpfs mutant (`3.2-config-20261105T011100Z.log`) | — | discharged |
| fleet-dashboard-interface: `The dashboard service listens on loopback behind one vhost` | tasks.md 3.4, 4.2; the listener and vhost clauses with their mutants and the strip override failing (`3.2-config-20261105T011100Z.log`, `3.4-assertions-20261105T010114Z.log`); the header, bypass and metrics cases (`3.7-container-20261105T011614Z.log`); `127.0.0.1:8095` the only Perses listener, `/api/v1/projects` 401 and `/metrics` 404 (`4.2-deploy-20261105T135344Z.log`) | — | discharged; observed on magnetite at 2026-11-05 about 13:55Z |
| fleet-dashboard-interface: `The identity provider admits only the dashboard group` | tasks.md 3.4, 3.5, 4.3, 4.4; the client and authentication clauses with their mutants (`3.2-config-20261105T011100Z.log`); scope maps `["perses_users"]` and the stub without members (`3.5-identity-20261105T010157Z.log`); the login's 302 to Kanidm with `client_id=perses` and `code_challenge_method=S256` (`4.2-deploy-20261105T135344Z.log`); the running client's `scopeMaps` `perses_users` (`7.1-gaps-20261105T142545Z.log`); the refusal and the admission (`4.3-4.4-operator-20261105T140642Z.log`) | A56, A57 | discharged; refusal and admission observed once on 2026-11-05 |
| fleet-dashboard-interface: `Readers hold only read permission on a read-only server` | tasks.md 3.4, 3.7; the permission clauses with their mutants (`3.2-config-20261105T011100Z.log`); the three write cases (`3.7-container-20261105T011614Z.log`); the anonymous PUT 405 on magnetite (`7.1-gaps-20261105T142545Z.log`) | A58 | discharged |
| fleet-dashboard-interface: `The telemetry store is read only through two global datasources` | tasks.md 3.3; lint over both datasources (`3.3-lint-20261105T005541Z.log`); the datasource clauses with their mutants, among them `noEndpoints`, `unanchoredEnd`, `projectDatasource` and `projectSecret` (`3.2-config-20261105T011100Z.log`); the query, refusal, database-header and header cases (`3.7-container-20261105T011614Z.log`) | A58, A59 | discharged |
| fleet-dashboard-interface: `Committed files are the only source of views and datasources` | tasks.md 3.4; the provisioning clause with its mutant (`3.2-config-20261105T011100Z.log`); the planted-view case (`3.7-container-20261105T011614Z.log`) | A58 | discharged |
| fleet-dashboard-interface: `The dashboard service's secrets arrive only as credentials` | tasks.md 3.5, 3.8, 3.9; the credential clause with its mutants (`3.2-config-20261105T011100Z.log`); the holder override and `restartUnits` (`3.5-identity-20261105T010157Z.log`); the generated vars and `clan vars check` (`3.8-vars-20261105T042937Z.log`); the three `LoadCredential` paths (`3.9-eval-20261105T043008Z.log`) | — | discharged at evaluation |
| fleet-dashboard-interface: `The dashboard service runs inside a memory envelope and hands its failures to the notifier` | tasks.md 3.5, 4.5; as the memory row of `fleet-dashboard` above | — | discharged; observed as above |
| fleet-dashboard-interface: `The view files lint clean at the shipped plugins` | tasks.md 2.1, 2.4, 3.3; RED (`2.1-lint-red-20261105T003546Z.log`); the seven `rejected:` lines and bare lint accepting `extra-field.json` (`2.4-lint-20261105T003923Z.log`, `3.3-lint-20261105T005541Z.log`) | — | discharged |
| fleet-dashboard-interface: `The serving configuration is judged by one predicate` | tasks.md 3.1, 3.2; RED (`3.1-config-red-20261105T005016Z.log`); 47 `rejected:` lines, each naming its clause; cost 101,300,400 B (§9.1) | — | discharged |
| fleet-dashboard-interface: `The container runtime test exercises the read path` | tasks.md 3.7; every case `ok:` and the bypass control's `admin` (`3.7-container-20261105T011614Z.log`); the test is the monitor of A58 and A59 | — | discharged when run, 2026-11-05 at 01:16Z; it does not gate |
| fleet-dashboard-interface: `The dashboard hostname resolves to magnetite` | tasks.md 3.6, 4.1, 4.2; `obs` created (`logs/terraform-20261105-083708.log`, id `630ca8ce…`); the certificate for `CN=obs.scientistexperience.net` issued by Let's Encrypt and served at 4.2 (`4.2-deploy-20261105T135344Z.log`) | A60 | observed through issuance and HTTPS on 2026-11-05 about 13:55Z; no `dig +short obs.scientistexperience.net` output is in a 4.1 log (§10) |
| fleet-dashboard-interface: `This capability states its own trust boundary` | tasks.md 5.1, 6.1; the runbook's "Reaching the dashboard" (#3724); the requirement's own statement, §8d | — | discharged by statement |
| telemetry-store: `The telemetry store runs a stable vendor release that serves its dashboard` (MODIFIED) | tasks.md 3.4, 5.1; the vhost clause, which admits only the proxy to Perses and the refusal of `/metrics`, with its `otherUpstream` mutant (`3.2-config-20261105T011100Z.log`); the release regulator unchanged; the runbook keeps the SSH tunnel as the operator's fallback (#3724) | A30 | discharged at evaluation; the embedded dashboard over the tunnel was not opened again by this change |
| telemetry-store-interface: `Credentials exist only as activation-resolved files owned by non-worker users` (MODIFIED) | tasks.md 3.5; `perses-password = [ "perses" ]` in the holder assertion and its `fleet-alert` override failing; `restartUnits` holding `perses.service` (`3.5-identity-20261105T010157Z.log`); `greptimedb-users` unchanged by the generation (`3.8-vars-20261105T042937Z.log`) | — | discharged at evaluation; a rotation of `perses-password` was not exercised |
| world-assumptions: `Grounded vocabulary for behavioral requirements` (MODIFIED) | tasks.md 6.1, 6.2; the delta's table, §8a | — | discharged; three nouns have no row (§8a.2) |
| world-assumptions: `A56 — Kanidm refuses an authorization whose scopes no group of the person maps` | world assumption; tasks.md 4.3; Access Denied for `cameron` outside `perses_users` (`4.3-4.4-operator-20261105T140642Z.log`) | — | observed once on 2026-11-05 about 14:02Z |
| world-assumptions: `A57 — Dashboard-group membership is kept in the running identity provider` | world assumption; tasks.md 3.5, 4.3, 4.4; the stub with no members and `overwriteMembers = false` (`3.5-identity-20261105T010157Z.log`); no members at 14:02:08Z after the deploy restarted Kanidm at about 13:54Z, and `cameron` added by `kanidm group add-members` (`4.3-4.4-operator-20261105T140642Z.log`) | — | observed on 2026-11-05 from about 13:54Z to 14:03Z; not violated since; no later deploy re-read the membership |
| world-assumptions: `A58 — Perses 0.55.1 removes its write routes in read-only mode, proxies with the stored credential and fixed headers, and refreshes a session without depending on the identity provider's answer` | world assumption; tasks.md 2.1, 3.7; the probe at 0.55.1 matching 0.55.0 case by case (`2.1-probe-0551-20261105T003405Z.log`); the container's write, planted-view, header and route cases (`3.7-container-20261105T011614Z.log`); the anonymous PUT 405 on magnetite (`7.1-gaps-20261105T142545Z.log`) | — | observed in the probe and the container on 2026-11-05, and the write route on magnetite at 14:25:45Z; the refresh clause rests on the source read its evidence cites, and no session's lifetime was observed |
| world-assumptions: `A59 — GreptimeDB 1.2.1 reads x-greptime-auth before Authorization` | world assumption; tasks.md 3.7; `bypass reached the store as admin` (`3.7-container-20261105T011614Z.log`) | — | observed in the container on 2026-11-05 at 01:16Z |
| world-assumptions: `A60 — magnetite is reachable on public TCP port 80 for HTTP-01` | world assumption; tasks.md 4.2; `acme-obs.scientistexperience.net.service` started and the Let's Encrypt certificate valid to 2027-02-03 served (`4.2-deploy-20261105T135344Z.log`) | — | observed at issuance on 2026-11-05 about 13:54Z |

Every ADDED or MODIFIED requirement is discharged or carries its world-assumption status; none waits on a later observation.
Four observations the plan asked of the operator were not recorded and are not claimed: the browser's storage, a save attempted by an admitted person in the UI, the tile as the apps portal draws it, and each host's latest point in the view at the minute of a store query (§10).

### 8c. Alphabet check

FD `An admitted person views the fleet's signals and the dev-loop history by host` lists the host view's subjects by their world names, each with a row (§8a.2).
FD `The dashboard service stays inside its memory envelope and its failures reach a person` names magnetite by its identifier and states 256 MiB as a world quantity; recorded, not counted.
FD `Nobody changes the views except by a committed change` uses `datasource`, a machine term (§8a.2).
The FDI requirements name `perses_users`, `127.0.0.1:8095`, `obs.scientistexperience.net`, the TTL settings and the generators, all machine-observable at evaluation or on magnetite.

### 8d. Trust boundaries

One requirement states the trust boundary of the capability this change adds, and it is discharged by its own statement; no regulator applies.
Its scenarios state it as follows.

**fleet-dashboard-interface: `This capability states its own trust boundary`.**
The capability SHALL state what its properties guarantee and what they do not, and SHALL NOT be described as an end-to-end guarantee that a chart shows correct values or that only members of `perses_users` can ever read.

- Who is admitted is not guaranteed: Kanidm authenticates people and refuses non-members, membership is set in the running Kanidm outside the repository, and a removed member keeps access until the last access token issued from the refresh token expires, at most 1 h after login: 45 min of refresh token and 15 min of access token.
- The server's enforcement is not guaranteed: Perses enforces read-only mode, guest permissions, endpoint patterns and header allow-lists, the telemetry store refuses writes from `perses:ro`, and this machine only configures them and tests them in the container runtime test.
- The credentials' confinement is not guaranteed: any root process on magnetite can read the store credential and the client secret.
- A chart's values are not guaranteed correct: each committed view's query runs in the container runtime test against stored samples, and nothing here compares a rendered chart with the stored series.

---

## 9. Evaluation cost and observations

### 9.1 Evaluation cost of each changed check

The budget is 0.5 GiB, 536,870,912 bytes of `gc.totalBytes` (tasks.md preamble line 6).
The method is `NIX_SHOW_STATS=1 NIX_SHOW_STATS_PATH=<file> nix eval --option eval-cache false --raw .#.checks.x86_64-linux.<check>.drvPath`, reading `.gc.totalBytes` and `.cpuTime` from the stats file; each log prints the method or the revisions in its header.
1.2's "before" was taken at `main@origin` `674cdf4a7`; 2.4's at `main@origin` against the working copy; 3.9's "before" at the join `22edb67a9`, which held pull request 1, and its "after" in the working copy.

| Check | Point | `gc.totalBytes` | GiB | cpuTime (s) | Log |
|---|---|---|---|---|---|
| `package-perses-bin` (new) | before | absent | — | — | `2.4-lint-20261105T003923Z.log` |
| | after 2.2 | 100,559,808 | 0.094 | 0.25 | same |
| `perses-lint` (new) | before | absent | — | — | `2.4-lint-20261105T003923Z.log` |
| | after 2.4, over the fixture | 100,616,288 | 0.094 | 0.27 | same |
| | after 3.3, over the six resources | 100,656,240 | 0.094 | 0.27 | `3.9-costs-20261105T011226Z.log` |
| `perses-config` (new) | before | absent | — | — | `3.9-costs-20261105T011226Z.log` |
| | after 3.2 | 101,300,400 | 0.094 | 0.27 | same |
| `apps-build` (changed: the updater) | before: `main@origin` | 757,711,984 | 0.706 | 3.21 | `2.4-lint-20261105T003923Z.log` |
| | after 2.3 | 757,548,272 | 0.706 | 3.14 | same |
| `fleet-alert` (changed: magnetite's notified units) | before: the join `22edb67a9` | 352,089,776 | 0.328 | 1.01 | `3.9-costs-20261105T011226Z.log` |
| | after 3.5 | 351,928,512 | 0.328 | 1.01 | same |
| `terraform-validate` (changed: the `obs` record) | before: the join `22edb67a9` | 199,621,536 | 0.186 | 0.64 | `3.9-costs-20261105T011226Z.log` |
| | after 3.6 | 199,452,160 | 0.186 | 0.65 | same |
| `nixos-magnetite` (machine check) | before: `main@origin` `674cdf4a7` | 2,861,125,952 | 2.665 | 10.51 | `1.2-baseline-20261104T234432Z.log` |
| | before: the join `22edb67a9` | 2,861,433,456 | 2.665 | 11.06 | `3.9-costs-20261105T011226Z.log` |
| | after 3.5 | 2,865,514,512 | 2.669 | 10.97 | same |

The three new checks each cost between 18.7 % and 18.9 % of the budget.
`apps-build` was over the budget at `main@origin` and this change lowers it by 163,712 B; it builds on magnetite.
`fleet-alert` changes derivation through magnetite's notified units (3.5) and `terraform-validate` through the notified units and the DNS record (3.5, 3.6); both build on magnetite (`3.5-touched-checks-20261105T032134Z.log`).
The machine check is outside the 0.5 GiB budget, as for the earlier observability changes, and grew by 4,081,056 B, 0.14 %, against the join.
The costs were taken before 3.8 generated the vars; the generation adds var files and no Nix code, and the cost was not measured again after it.
`vmTests.x86_64-linux.perses-greptimedb` is not a flake check and its evaluation cost was not measured.

### 9.2 Acceptance and control times

| Event | Time (UTC) | Evidence |
|---|---|---|
| #3721 merged as `8a00ca70f` | 2026-11-05T04:39:29Z | tasks.md 3.9 |
| `obs` created by `just terraform` | 2026-11-05 about 13:37Z | `logs/terraform-20261105-083708.log` |
| magnetite deployed from `8a00ca70f`; certificate issued | 2026-11-05 about 13:54Z | `4.2-deploy-20261105T135344Z.log` |
| refusal of `cameron` (4.3) | `perses_users` empty at 14:02:08Z; Access Denied after it | `4.3-4.4-operator-20261105T140642Z.log` |
| admission and both views (4.4) | after 14:02:08Z, before 14:06:42Z | same |
| kill (4.5) | killed 14:06:43Z; notice the same second; restarted 14:06:54Z | `4.5-kill-20261105T140642Z.log` |
| gaps reading (4.4, 4.5, 7.1) | 14:25:45Z | `7.1-gaps-20261105T142545Z.log` |

---

## 10. Deviations and observed gaps

- **3.6, folded into 4.1.** The plan check of 3.6 needs `config.tf.json`, which only `just terraform` writes, so `just terraform-plan` failed at 3.6 (`3.6-terraform-plan-20261105T043213Z.log`) and the plan was read at 4.1 instead.
- **4.1, the terraform run.** `just terraform` planned 1 to add and 12 to change; each change was only `include_shadow_metadata = false`, in place, with no name or content change. After the apply the provider reported "Provider produced inconsistent result after apply" on 10 records, because Cloudflare bumped `modified_on`; every record resolved as before through `dig @1.1.1.1`, and the state was committed as #3723 (`logs/terraform-20261105-083708.log`). No `dig +short obs.scientistexperience.net` output was logged; the name's resolution is observed through the certificate's issuance and the HTTPS requests of 4.2.
- **3.8, run by the orchestrator.** Both generators are per-machine and take no prompt, so the orchestrator ran them with `CLAN_NO_COMMIT=1` rather than the operator; `greptimedb-users` was unchanged (`3.8-vars-20261105T042937Z.log`).
- **Plan deviations recorded in tasks.md's done notes.** 2.1: `percli lint` 0.55.1 prints each custom rule's message, so the plan review's observation of no message did not hold and the stop condition did not apply. 2.3: the updater ran in a scratch git repository rather than a worktree at 2.2's commit, and `update.sh` carries `# shellcheck disable=SC2016`. 3.2: clauses 2 and 3 fail with one message per setting, so the container test can accept exactly its native-login and provider-count failures. 3.3, deviation (7): the SQL views select `"ts"`, a value and a label column (§4). 3.4, deviations (1) to (3): the module is site-neutral with magnetite setting the `LoadCredential` entries; `vanixiets.perses.acceptedServingFailures` exists for the container test only; the resources folder is copied with `builtins.path` so a commit does not restart Perses. 3.7, deviations (4) to (6) and (8): the test sends `match[]`, converts its samples to OTLP protobuf, reads the store's identity with `SELECT current_user()`, and ran through magnetite as a remote builder.
- **4.2, notices not read.** The task asked that every alert and failure notice posted since the deploy started be read and explained; `4.2-deploy-20261105T135344Z.log` records none, and the one notice recorded is 4.5's.
- **4.3 and 4.4, evidence file names.** Both are in `4.3-4.4-operator-20261105T140642Z.log`, not in `4.3-refusal-<ts>.log` and `4.4-admission-<ts>.log`.
- **4.4 and 7.1, observations closed by command.** By the orchestrator's decision the operator's 4.4 statement that both views showed collected data stands for 7.1. `7.1-gaps-20261105T142545Z.log` then closed four gaps by command at 14:25:45Z: Perses' memory after the restart, the store's per-host memory samples over 15 min, an anonymous PUT answered 405, and the Kanidm client's `displayName`, `originLanding` and `scopeMaps`, which are the tile's source.
- **Observed gaps, not discharged.** The browser's local and session storage on `obs.`, a save attempted by an admitted person in the UI, the tile as the apps portal draws it, and the per-host reading of the view at the minute of the store query were not observed; the plan's 5 min bound in 7.1 was not checked, because the store was queried over 15 min.

---

## Overall Decision

Every `tasks.md` item is done; the requirements are discharged or carry their observed status as §8b states, with the deviations and the observed gaps of §10.
