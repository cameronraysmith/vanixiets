# Plan review of bind-mesh-writes-to-their-host

This is the plan review of `tasks.md` 1.1, run on 2026-11-07 against `design.md`, `tasks.md`, `plan.md`, `plan/` and `specs/` as they stood at `main@origin` `1bdc59782d29`.
One read-only subagent of the default `task` agent type answered the four questions; it reported running on `anthropic/claude-opus-5-5`.
Claims marked [INFERENCE] were not verified against source or a running system.
The baseline log the review cites under R19 is the 1.2 evidence, `logs/cam81-evidence/1.2-baseline-20261107T213705Z.log`.

## Severity summary

- Critical: 1 (R1).
- Significant: 13 (R2, R3, R4, R5, R6, R7, R9, R10, R13, R14, R15, R16, R17).
- Minor: 11 (R8, R11, R12, R18, R19, R20, R21, R22, R23, R24, R25).

## 1. Critical oversights

1. R1 (critical): caddy's admin API on `127.0.0.1:2019` lets any local account reload caddy's whole configuration, which breaks the binding (design.md:110, :119; plan.md:51; plan/task-4.md:93; specs/fleet-ingress-interface/spec.md:289).
   An unauthenticated `POST /load` can remove the 403 or set `header_up X-Vanixiets-Host` to any host, so design D3's "no local process but caddy can post a forged identity header" is false [INFERENCE: caddy admin API docs, https://caddyserver.com/docs/api, and `admin.go`].
   magnetite runs a buildbot worker and nixbot (modules/machines/nixos/magnetite/default.nix:47-49, :64-65), so pull-request builds run there, and a fixed-output build shares the host network [INFERENCE: Nix sandbox semantics].
   Disposition: in design D3, plan.md:51 and plan/task-4.md Step 4, move the admin endpoint to a Unix socket readable only by root and caddy (or turn it off).
   Serve `metrics` from a separate loopback site that has only the `metrics` handler.
   Rewrite FII "The ingress proxy runs inside a declared envelope" so it names the socket.
   Add a magnetite assertion that caddy's `admin` is not a TCP address.
2. R2 (significant): with `DynamicUser`, the socket directory ends up in the wrong group (plan/task-4.md:72-85; design.md:116).
   `RuntimeDirectory` belongs to the unit's own User and Group, so a setgid directory passes on the dynamic group, not `otelcol-mesh` [INFERENCE: systemd.exec(5)].
   caddy then cannot connect and every mesh write gets 502.
   The collector does run as `DynamicUser` (modules/clan/services/otel-collector/flake-module.nix:375).
   Disposition: in plan/task-4.md Step 4, set `Group = "otelcol-mesh"` on the collector, a static group that systemd uses in place of a dynamic one, or give the collector a static user.
   Drop the "the plan review's disposition decides" clause at :85.
3. R3 (significant): a collecting host that is absent during rounds 3 to 5 comes back still holding its old certificate and gets 403 (tasks.md:37, :50-52; plan/task-5.md:4).
   Because 403 is permanent (design D6), its exporter drops up to 24 h of queued data.
   The gates check only "present" hosts.
   Disposition: in tasks.md 3.4 and 5.2, require every host expected to return (pyrite, and stibnite when asleep) to hold its reissued certificate before 5.3.
   Otherwise state in design Risks that its backlog will be lost, and get the operator's decision.
4. R4 (significant): a mesh writer chooses the destination database and devloop table through resource attributes (flake-module.nix:793-797, :850-854).
   The binding filters check only host names, so a key holder on a collecting host can write `ci_build`, `batch_event` and `ci_attribute` rows and `devloop` metrics, none of which have a host column.
   Honest mesh traffic is always `fleet` metrics or `devloop`/`deploy_record` logs (flake-module.nix:299-308, :546-556).
   Disposition: add to design D5, FII "A mesh write is stored only under the host that sent it" and plan/task-4.md Step 4 a database and table allow-list condition in each binding filter.
   Add a container leg and a 1.5 probe case for it.
   Correct the trust-boundary scenarios that say root on a collecting host writes only "as that host".
5. R5 (significant): the SAN and the stored host name come from different values (design.md:143).
   The SAN uses `machine.name`, but the agent stamps `host.name` from `config.networking.hostName` (flake-module.nix:150, :301-302), and deploy records use it too (modules/system/deploy-record.nix:103-106, :120-123).
   Each machine sets `networking.hostName` as its own literal (for example modules/machines/nixos/pyrite/default.nix:128; modules/machines/darwin/stibnite/default.nix:66).
   Nothing in D7 relates the two, so design D5's "a configuration fault that D7's checks catch" has no regulator.
   Disposition: add to the agent role (nixos and darwin) an assertion that `networking.hostName == machine.name`, with an override that makes it fail.
   Alternatively, render the SAN from `networking.hostName`.
   Correct the wording at design.md:143.
6. R6 (significant): the specs promise detection the design cannot deliver (specs/host-metrics-collection/spec.md:12, :22; design.md:29).
   HMC says that when a copied key is used "from any overlay member other than cinnabar ... the operator is told within one regulator period".
   But a copy used from a spoofed pinned address never completes TCP, so neither caddy nor C6 sees it.
   Design Goal :29 ("every refused ... write fails ... otel-envelope") also leaves out handshake refusals, which caddy does not count as 403 (FII :94).
   Disposition: narrow HMC :22 and design.md:29 to refusals that reach HTTP, and state in the FII trust boundary that handshake-level and spoofed-address attempts go undetected.
7. R7 (significant): the container test's identities conflict with the neighbour rendering, and the interface contract has no override for caddy's listen address (plan/task-4.md:61, :134; plan.md:47, :51-52).
   `meshIdentities` set to `127.0.0.x` and `::1` feeds `zerotierMac`, which asserts eight groups (plan/task-2.md Step 2 body), and also feeds `meshTableAgreement`'s LinkLayerAddress clause.
   The `store` container therefore fails to evaluate.
   caddy's site is fixed at `[${flake.lib.hosts.magnetite.zt}]:4318`, but the test needs `127.0.0.1` and `[::1]`.
   Disposition: in plan.md's interface contract, separate the neighbour set (an rfc4193-only option or a flag that turns it off in the test) from the identity map.
   Add a `meshListen` option, and update plan/task-4.md Steps 3 to 5.
8. R8 (minor): the C6 snippet in plan/task-4.md:22-41 has several defects.
   `prev` returns the word `absent`, not an empty string (modules/lib/otel-envelope.nix:365-367), so `$(( ... ${was:-0} ))` fails under nounset in `writeShellApplication` (:320).
   `jq` is not in `runtimeInputs` (:322-327).
   A failed caddy curl leaves `$tmp/caddy` missing, which aborts the run.
   Unlike C4, it has no baseline guard (:464), so a lost state file reports the full counter values as rises.
   Disposition: rewrite the snippet in plan/task-4.md Step 1 on C4's pattern (an `absent` check, awk comparison and the baseline skip), add `jq` and `iproute2` to `runtimeInputs`, and treat a missing caddy file as "metrics unanswered".

## 2. Significant architecture improvements

1. R9 (significant): turn the one-shot filter probe and most of the binding legs into a gating check.
   A `runCommand` derivation would run the pinned `otelcol-contrib`, and caddy with the test PKI, on loopback inside the build sandbox.
   It would use magnetite's rendered filter and Caddyfile, with source addresses `127.0.0.x`.
   Today the binding's behaviour is judged only by the non-gating `vmTests` lane (modules/vm-tests/fleet-ingress.nix:21-23, :34) and the one-shot probe in tasks.md 1.5.
   Nothing ties the conditions rendered in 4.4 to the probed text, and nothing re-judges after a nixpkgs bump.
   Disposition: add a task 4.x check, for example `checks.x86_64-linux.mesh-binding`, measured against the 536,870,912 B budget.
   Keep `fleet-ingress` for the neighbour and socket legs, and make 1.5 the first run of that check.
2. R10 (significant): A75 and A76 can only be violated when a version moves, yet no gating trigger fires when caddy or `otelcol-contrib` moves with the next `flake.lock` update (specs/world-assumptions/spec.md:294-295, :297-302).
   Disposition: add version tripwire assertions in the ingress role, `pkgs.caddy.version == "2.11.7"` and the collector's version `== "0.155.0"`, following modules/checks/pyrite-desktop.nix:222.
   Their messages should require rerunning `fleet-ingress` (or R9's check) and updating the assumptions.
3. R11 (minor): extend the 1.5 probe to caddy before the C6 fixtures are written (tasks.md:41; design.md:159; plan/task-4.md:16, :33).
   C6's caddy series and its `server="mesh"` label are written before caddy has run anywhere.
   The same probe should confirm three caddy behaviours this design relies on: the map with no default inside a `vars` matcher, certificate selection for an IP-addressed site when the client sends no SNI [INFERENCE: certmagic falls back to the local IP], and the `{$CREDENTIALS_DIRECTORY}` placeholder.
   Disposition: add caddy cases to tasks.md 1.5 and plan/task-1.md Step 5, and source 4.1's caddy fixtures from that output.
4. R12 (minor): the network id `db4344343b14b903` is written as a literal in four places (plan.md:33; plan/task-2.md:43; plan/task-4.md:134; the 2.1 prefix), but it exists as a public var (`vars/shared/zerotier-network-zerotier/network-id/value`).
   Disposition: read it from that file in the 2.1 form clause and in the neighbour rendering, so the /88 prefix gets an independent source.
5. R13 (significant, see section 3 item 1): key the controller's external members by name.
   For example, `externalMembers = { stibnite = "…"; … }` with `allowedIps = attrValues externalMembers` in modules/clan/inventory/services/zerotier.nix.
   The address clause can then compare stibnite by name.
6. R22 (minor): `meshIdentities` is a public option that exists for the test, and nothing relates magnetite's evaluated value to `observabilityHosts` joined with `flake.lib.hosts` (plan.md:50).
   Disposition: add that relation as an OCC clause with a mutant (magnetite overrides one address).
   Alternatively, after R7, make the option internal to the test.

## 3. Checks that cannot fail, restating clauses and uncovered properties

1. R13 (significant): the address clause cannot attribute an `allowedIps` entry to stibnite, because the host names are only comments (modules/clan/inventory/services/zerotier.nix:16-23).
   plan/task-2.md:17's "the entry whose comment names the host" cannot be evaluated, so the clause reduces to a membership test.
   The mutant `externalAddressDiffers` sets stibnite to blackphos's listed address (plan/task-2.md:20), so it passes membership and survives, while the spec's mutant uses an unlisted address (specs/fleet-ingress-interface/spec.md:31-32).
   Disposition: apply the R13 restructuring, or redefine the mutant and the spec scenario as membership-only and record the weaker property.
2. R14 (significant): `meshTableAgreement` restates its own rendering, and implementing it costs more than the invariant it protects (plan/task-4.md:51; plan.md:55; specs/fleet-ingress-interface/spec.md:159, :233).
   The map, the filters and the neighbours are all rendered from `meshIdentities` in one module, and "LinkLayerAddress equals `zerotierMac` of its address" is the same expression as the rendering.
   `mapLineSwapped` needs the assertion to parse caddy's `extraConfig` text back.
   Disposition: render all three from one `let`-bound list, delete the assertion and its two overrides, and name R9's check or the container binding legs as the discharge in the FII requirements.
3. R15 (significant): `meshSocketGroup` restates `users.groups.otelcol-mesh.members = [ "caddy" ]` (plan/task-4.md:52, :72).
   It also cannot hold as written, because a `DynamicUser` collector is not a group member.
   And it misses the real ways in: any unit's `Group=`, its `SupplementaryGroups=`, and any user's `extraGroups`.
   Disposition: redefine it to scan every `systemd.services.*.serviceConfig.{Group,SupplementaryGroups}` and `users.users.*.extraGroups` for `otelcol-mesh`, requiring exactly the collector and caddy.
   Point the `extraSocketMember` override at another unit's `SupplementaryGroups`.
4. R16 (significant): reading an absent counter as zero (design.md:159) makes C6 unable to fail after a series rename or a wrong fixture name.
   C6 would report `ok` for ever, and the only judge, `fleet-ingress`, does not gate.
   Disposition: in design D6 and plan/task-4.md Step 1, have C6 also require a liveness series for each input once the mesh has carried traffic.
   Candidates are `otelcol_processor_incoming_items{processor="filter/mesh-host-*"}` and caddy's request count for server `mesh`, with a fixture case and a mutant.
5. R17 (significant): the `noPinnedEntries` mutant's result depends on a neighbour-solicitation race, not on pinning (plan/task-4.md:131-133; tasks.md:45).
   Without an existing entry the unsolicited override advertisement is ignored, because Linux creates no entry from an untracked advertisement (net/ipv6/ndisc.c:1074-1079, cited in tasks.md 6.2).
   When the store then solicits, the victim and the attacker both answer, so the negative control's outcome is nondeterministic.
   It is also unverified whether `ip netns add` works inside a systemd-nspawn container [INFERENCE].
   Disposition: have the mutant ping the victim first so the entry is REACHABLE, as Task 6 Step 2 does live, and add the netns feasibility to the 1.4 rehearsal.
6. R18 (minor): three verifies restate the line they judge.
   These are 2.3's `nix eval` of `validation` (plan/task-2.md:98), 4.5's `nix eval` of the neighbours list (plan/task-4.md:135) and 2.2's single-pair `nix eval`, which duplicates the MAC clause (plan/task-2.md:86).
   Disposition: label them smoke readings in tasks.md, and leave the 2.4 `openssl` reading and the MAC clause as the regulators.
7. R19 (minor): two verifies compare against values task 1.2 never recorded.
   The baseline 1.2 log (logs/cam81-evidence/1.2-baseline-20261107T213705Z.log) holds only the `ca.crt` hash, not the `otel-ca` generator evaluation that 2.3 compares against (plan/task-2.md:98).
   It also lacks cinnabar's `otel-envelope` `ExecStart`, which 4.1 compares against (plan/task-4.md:45), and `main` moves before 4.1 in any case.
   Disposition: compare each against `nix eval` at the change's parent commit in the same step, not against 1.2.
8. R20 (minor): networkd's `[Neighbor]` installation on the ZeroTier link is never exercised before deploy.
   The container leg installs its entries with `ip -6 neigh replace` (plan/task-4.md:131), so only C6 and task 6.1 judge the real path.
   Disposition: state this in the D10 "Boundary" and in A73's discharge, and keep 6.1 as the operator-present step.
9. R21 (minor): the form clause checks eight groups and no leading zero, but not lower case or RFC 5952 `::` compression (plan/task-2.md:17).
   A hex digit in the wrong case in `hosts.nix` would make every write from that host get 403 [INFERENCE: caddy's `remote.host` uses Go's `IP.String`, which is lower-case].
   The 4.5 neighbour rendering then feeds `ip`'s output to C6's string comparison.
   Disposition: add a lower-case check, and require the address to equal its own canonical rendering.

## 4. Mechanisms costing more than their invariant

1. R14 (see section 3 item 2): parsing caddy's rendered map back out of `extraConfig` costs more than checking three renderings of one attribute set.
2. R23 (minor): duplicated regulators, and drift between design and tasks.
   `tracesMeshUnfiltered` duplicates OCC R3.1's "a traces pipeline" clause (modules/checks/otel-collector-config.nix:308-311).
   Design D8's assertion that "no collector endpoint is off loopback" (design.md:175) duplicates the revised R3.1 endpoint clause, and tasks.md 4.2 already leaves it out.
   Disposition: drop the traces override and the D8 endpoint sentence, and name R3.1 as the regulator.
3. R19 (see section 3 item 7): proving cross-commit store-path equality for every envelope costs more than one same-commit comparison against the parent.
4. R24 (minor): the existing OCC mutants `meshWildcard`, `secondMeshReceiver` and `ztAddressOther` (modules/checks/otel-collector-config.nix:391-398) are written against `otlp/mesh`'s TCP endpoint.
   That endpoint stops existing once `otlp/mesh` moves to the socket, and the plan says nothing about these mutants.
   Disposition: in plan/task-4.md Step 4, name each one to be rewritten or removed, as part of the clean cutover.
5. R25 (minor): the rollback is slower and less complete than it looks (plan/task-5.md:93-102; design.md:134, :258).
   It reverts through the merge queue while magnetite may be cut off.
   A static neighbour that networkd manages may come back on the next link event after `ip neigh del` [INFERENCE].
   Disposition: deploy the pre-PR-2 commit directly from `$DEPLOY` over the public path first, then revert through the queue.
   Have 5.5 confirm afterwards that the entry is gone.

## Clause list

| Item | Kind | Task | Source A | Source B | Independent? |
|---|---|---|---|---|---|
| address clause, clan peers | check clause | 2.1 | `flake.lib.hosts.<h>.zt` (modules/lib/hosts.nix) | `vars/shared/zerotier-ip-<h>-zerotier/ip/value` (clan-generated) | yes |
| address clause, stibnite | check clause | 2.1 | `flake.lib.hosts.stibnite.zt` | `allowedIps` list (zerotier.nix:16-23) | no: the list has no host key, so only membership can be tested (R13) |
| address form sub-clause | check clause | 2.1 | each `hosts` address | prefix literal in the check | partly: the constant is not read from the network-id var, and case is not checked (R12, R21) |
| `addressDigitChanged` | mutant | 2.1 | pyrite address altered | vars file | yes |
| `externalAddressDiffers` | mutant | 2.1 | stibnite set to blackphos's listed address | `allowedIps` | no: survives a membership test (R13) |
| MAC clause | check clause | 2.2 | `flake.lib.zerotierMac` | `zerotier-macs.json`, read live on 2026-11-06 | yes |
| `macBytesReversed` | mutant | 2.2 | reversed function output | fixture | yes |
| stibnite MAC `nix eval` | verify | 2.2 | function | one fixture pair | no: duplicates the MAC clause (R18) |
| `validation` eval | verify | 2.3 | edited generator line | same line | no: restates (R18) |
| `otel-ca` definition unchanged | verify | 2.3 | evaluation at commit | 1.2 baseline | no: 1.2 did not record it (R19) |
| URI SAN reading | command | 2.4 | delivered `cert.pem` via `openssl` | expected SAN string in spec | yes |
| `openssl verify` | command | 2.4 | `cert.pem` | `ca.crt` | yes |
| CA and token hash equality | command | 2.4 | hashes after | hashes before | yes |
| C6 filter case | fixture case | 4.1 | telemetry `.prom` with names from the 1.5 probe | C6 awk pattern | yes, if copied from 1.5 output |
| C6 refusal case | fixture case | 4.1 | caddy `.prom` | C6 awk pattern | no: no caddy run precedes it, so both are plan-authored (R11, R16) |
| C6 neighbour good/bad | fixture case | 4.1 | `ip -j` neighbour JSON | `binding.neighbours` | partly: the JSON shape is live, but its MACs come from the function the input is rendered with |
| C6 absent and reset cases | fixture case | 4.1 | fixture | C4 convention (otel-envelope.nix:450-469) | yes |
| `c6IgnoresFilter`, `c6IgnoresRefusal`, `c6IgnoresNeighbour` | mutants | 4.1 | mutated script | fixtures | yes |
| C2 caddy target | envelope clause | 4.1 | `binding.caddyMetricsUrl` | caddy `admin` literal | no: the same literal written twice; render both from one binding (R1 moves it) |
| cinnabar envelope unchanged | verify | 4.1 | `ExecStart` at commit | 1.2 baseline | no: not recorded, and `main` moves (R19) |
| `meshPipelineCoverage` | assertion | 4.2 | pipeline set, including future CAM-74 edits | binding-prefix rule | yes |
| `meshInIngress`, `logsMeshUnfiltered` | overrides | 4.2 | mutated pipelines | rule | yes |
| `tracesMeshUnfiltered` | override | 4.2 | traces pipeline | rule | no: OCC R3.1 already rejects any traces pipeline (R23) |
| `meshTableAgreement` | assertion | 4.2 | three renderings | `meshIdentities` | no: rendered from the same set, and the MAC clause repeats the rendering expression (R14) |
| `mapLineSwapped`, `neighbourDropped` | overrides | 4.2 | hand-made divergence | `meshIdentities` | no: the single rendering cannot produce it (R14) |
| `meshSocketGroup` | assertion | 4.2 | `users.groups.otelcol-mesh.members` | literal in the assertion | no: restates the line, and misses `DynamicUser` and `SupplementaryGroups` (R15) |
| `extraSocketMember` | override | 4.2 | `members` plus `nobody` | literal | no: as above (R15) |
| kill order with caddy (`caddyBelowPerses`) | assertion | 4.2 | caddy's `OOMScoreAdjust` (ingress role) | evaluator and Perses values (magnetite/default.nix:734-740, nix-eval-lock.sh) | yes |
| `bindingMatch` | container case | 4.3 | test PKI SAN and curl source | `meshIdentities` map, judged by the vendored caddy and collector | yes |
| `bindingWrongAddress` | container case | 4.3 | electrum certificate from 127.0.0.2 | map | yes |
| `bindingNoSan` | container case | 4.3 | `nosan` certificate | map | yes |
| `bindingOutsider` | container case | 4.3 | `outsider` SAN | map | yes |
| `bindingUnlisted` | container case | 4.3 | source 127.0.0.9 | map | yes |
| `bindingHeaderForged` | container case | 4.3 | client header | caddy `header_up` | yes |
| `bindingHostMismatch` | container case | 4.3 | resource `host.name` | header, via the vendored filter | yes |
| `bindingRecordMismatch` | container case | 4.3 | record `host` | header | yes |
| `bindingPointAttribute` | container case | 4.3 | point `host_name` | filter | yes |
| `bindingBackPressure` | container case | 4.3 | `limiterRefusing` | agent's status through caddy | yes |
| `socketAccess` | container case | 4.3 | `nobody` | runtime directory group and mode | yes (positive side is `bindingMatch`; see R2) |
| `caddy validate` | command | 4.4 | rendered Caddyfile | vendored parser | yes, syntax only |
| R3.1 caddy site address | check clause | 4.4 | caddy site (from `hosts.magnetite.zt`) | `zerotier-ip-magnetite` vars file | yes (also implied by the address clause) |
| R3.1 collector endpoints | check clause | 4.4 | collector settings | loopback or socket predicate | yes; duplicated by design D8 (R23) |
| `meshTcpEndpoint`, `caddyWildcard` | mutants | 4.4 | mutated settings | clause | yes |
| `neighbourPinned` | container case | 4.5 | kernel with a permanent entry | attacker's override advertisement | yes; entries installed by `ip`, not networkd (R20) |
| `noPinnedEntries` | container mutant | 4.5 | no entry | solicitation race | no: nondeterministic (R17) |
| `09-zerotier` neighbours eval | verify | 4.5 | rendering | same rendering | no: restates (R18) |
| evaluation-cost records | measurement | 2.5, 4.6 | cost after | cost before and budget | yes |
| `meshIdentities` default | interface contract | 4 | magnetite's evaluated value | `observabilityHosts` joined with `hosts` | no: no clause relates them (R22) |
| filter conditions, OTTL header form | interface contract, probe 1.5 | 1, 4 | probe configuration | vendored `otelcol-contrib` 0.155.0 | yes for the probe; no clause ties 4.4's rendering to it (R9) |

## Dispositions

The operator decides each row; an accepted finding is applied to the planning artifacts before gate 1.3 lets any implementation commit through.
On 2026-11-07 the operator approved every Recommended entry; `accept` adopts the row's Recommended column, including its modifications.

| Finding | Severity | Disposition | Recommended | Operator decision |
|---|---|---|---|---|
| R1 | critical | design D3, plan.md:51, plan/task-4.md Step 4, FII envelope requirement: admin on a root/caddy-only Unix socket or off; metrics on a separate loopback site; assertion that admin is not TCP. | accept-modified: `admin off` with `services.caddy.enableReload = false`, and caddy's metrics served by a `metrics` handler on a loopback site `http://127.0.0.1:2019` bound to `127.0.0.1`; see "R1 recommended design"; with no admin endpoint there is nothing left to restrict. | accept |
| R2 | significant | plan/task-4.md Step 4: `Group = "otelcol-mesh"` (static) on the collector or a static collector user; delete :85's deferral. | accept-modified: decide the socket ownership before 4.4 by a run, not by source: `systemd.tmpfiles` creates `/run/otelcol-mesh` as `root:otelcol-mesh` mode 2770, the collector gets `SupplementaryGroups = [ "otelcol-mesh" ]` and `ReadWritePaths` on it; the `socketAccess` case and a socket case in 1.5 judge it; the reviewer's static `Group=` beside `DynamicUser` is the fallback; neither form's interaction with `DynamicUser` has been run. | accept |
| R3 | significant | tasks.md 3.4 and 5.2: require every returning collecting host to be reissued before 5.3, or record the operator's acceptance of backlog loss in design Risks. | accept-modified: 3.4 and 5.1 list every collecting row of `flake.lib.observabilityHosts`; each is either seen holding its reissued certificate or carries an operator decision accepting the loss of its queued backlog, recorded before 5.3. | accept |
| R4 | significant | design D5, FII "stored only under the host", plan/task-4.md Step 4, 1.5 probe: database and table allow-list in the binding filters with a container leg; correct the trust-boundary scenarios. | accept-modified: the allow-list is rendered from the `vanixiets.database` and `vanixiets.table` values the agents' evaluated configurations set, not written as literals, so a new honest stream extends it with its agent; a 1.5 probe case and a container case show a forged `ci_build` row dropped. | accept |
| R5 | significant | agent role (nixos and darwin): assertion `networking.hostName == machine.name` with an override, or render the SAN from `hostName`; correct design.md:143. | accept | accept |
| R6 | significant | HMC :22, design.md:29, FII trust boundary: scope detection to HTTP-level refusals and state that handshake and spoofed-address attempts go undetected. | accept | accept |
| R7 | significant | plan.md interface contract and plan/task-4.md Steps 3-5: separate the rfc4193 neighbour set from the identity map; add a listen-address option. | accept | accept |
| R8 | minor | plan/task-4.md Step 1: rewrite C6 on C4's `absent` and baseline pattern; add `jq` and `iproute2`; handle a missing caddy scrape. | accept | accept |
| R9 | significant | new task 4.x: gating sandbox check running the pinned collector and caddy over magnetite's rendered configuration; 1.5 becomes its first run. | accept-modified: a separate gating check runs only the pinned `otelcol-contrib` over the filter text 4.4 renders, with 1.5's cases as its first run; caddy stays in the `fleet-ingress` container; kept apart from `otel-collector-config` so its cost is measured on its own. | accept |
| R10 | significant | ingress role: caddy and otelcol version tripwire assertions whose messages require rerunning the binding tests; cite in A75 and A76. | accept-modified: a version tripwire for caddy only; the collector's filter behaviour is re-judged on every bump by R9's check, so a tripwire there would only block lock updates without adding a judgement. | accept |
| R11 | minor | tasks.md 1.5 and plan/task-1.md Step 5: probe caddy's metric names, IP-site certificate selection without SNI, map with no default and credential placeholder before 4.1. | accept | accept |
| R12 | minor | plan/task-2.md Step 1 and plan/task-4.md Step 5: read the network id from `vars/shared/zerotier-network-zerotier/network-id/value`. | accept | accept |
| R13 | significant | modules/clan/inventory/services/zerotier.nix keyed by name (in plan/task-2.md), or redefine the mutant and FII :31-32 as membership-only. | accept-modified: take the restructuring, `externalMembers` keyed by name in `modules/clan/inventory/services/zerotier.nix` in pull request 1, rather than weakening the clause and FII's scenario to membership. | accept |
| R14 | significant | plan/task-4.md Step 2, plan.md:55, FII :159 and :233: delete `meshTableAgreement` and its overrides; render from one list; name R9's check or the container legs as the discharge. | accept | accept |
| R15 | significant | plan/task-4.md Step 2: redefine `meshSocketGroup` over every unit's Group and SupplementaryGroups and every user's extraGroups; retarget `extraSocketMember`. | accept | accept |
| R16 | significant | design D6 and plan/task-4.md Step 1: C6 requires a liveness series per input after mesh traffic, with a fixture case and a mutant. | accept | accept |
| R17 | significant | plan/task-4.md Step 5 and tasks.md 4.5: make the mutant create a REACHABLE entry first; rehearse `ip netns` inside nspawn in 1.4. | accept-modified: the mutant pings the victim first; drop the proposed 1.4 addition, because 1.4 rehearses the read-only blocks of Tasks 3, 5 and 6 on hosts, and the first `fleet-ingress` run of 4.5, which must see the case fail before the entries exist, already shows whether `ip netns` works in the container. | accept |
| R18 | minor | tasks.md 2.2, 2.3 and 4.5: label the restating evals as smoke readings, not regulators. | accept | accept |
| R19 | minor | plan/task-2.md Step 3 and plan/task-4.md Step 1: compare against `nix eval` at the parent commit, not 1.2. | accept | accept |
| R20 | minor | design D10 "Boundary" and A73's discharge: state that networkd's installation path is judged only by C6 and task 6.1. | accept | accept |
| R21 | minor | plan/task-2.md Step 1: require lower case and canonical RFC 5952 form. | accept | accept |
| R22 | minor | OCC clause relating magnetite's `meshIdentities` to `observabilityHosts` joined with `hosts`, with a mutant, or make the option test-internal after R7. | accept-modified: no new clause; after R7 and R14 make `meshIdentities` `internal = true` and set only in the container test, since a clause comparing magnetite's value with its own default expression would restate it. | accept |
| R23 | minor | plan/task-4.md Step 2 and design D8: drop `tracesMeshUnfiltered` and the D8 endpoint sentence; name OCC R3.1. | accept | accept |
| R24 | minor | plan/task-4.md Step 4: state the rewrite or removal of `meshWildcard`, `secondMeshReceiver` and `ztAddressOther`. | accept | accept |
| R25 | minor | plan/task-5.md Step 5 and design "Rollback": deploy the pre-PR-2 commit directly over the public path first; confirm the entry stays deleted. | accept-modified: the first rollback deploys from `$DEPLOY` detached at the merge-base before pull request 2, with `--target-host root@magnetite.scientistexperience.net`, as a named exception in plan Global Constraints to the deploy-from-`origin/main` rule; the revert then lands through the queue and is deployed normally; 5.5 confirms the entries stay absent after the rollback deploy. | accept |
| F1 | minor | The 1.2 baseline first recorded `otel-collector-config` at 595,199,600 B, because its script evaluated `#checks.x86_64-linux.<check>.drvPath` without the dot, so nix also searched `packages` and `legacyPackages`; measured as `#.checks…` at `1bdc59782d29` it is 477,941,968 B. | resolved: measuring error, budget holds. | resolved |
| F2 | minor | `nixos-magnetite` evaluates to 2,983,798,736 B, a whole-machine figure that no budget of 536,870,912 B can hold, yet 2.5 and 4.6 require each changed check's cost below that budget. | accept-modified: keep the budget for the checks this change adds or changes; for the machine checks record the cost before and after with the same method and put any rise to the operator, and say so in 2.5 and 4.6. | accept |
| F3 | minor | A flake reference written without the dot after `#` makes nix search `packages` and `legacyPackages` before `checks`, which added about 117.5 MB to an evaluation-cost reading. The cost commands of design.md:18 and :218, plan.md:26, tasks.md:7 and plan/task-1.md:25 already carry `.#.checks`; the four `nix build .#checks…` verifies, tasks.md 2.1 and 4.1, plan/task-2.md:22 and plan/task-4.md:19, do not. | accept-modified: write `.#.checks.x86_64-linux.<check>` in those four as well, so every check reference has one form and a cost reading copied from a verify cannot pick up the extra search. | accept |

## Where each accepted finding is applied

Locations name the section, step or item as edited on 2026-11-07, not line numbers, because the edits moved the lines the findings cite.
FII is `specs/fleet-ingress-interface/spec.md`, HMC `specs/host-metrics-collection/spec.md` and WA `specs/world-assumptions/spec.md`.

| Finding | Applied in |
|---|---|
| R1 | design D3 (Choice with `enableReload = false`, `admin off` and the metrics site; "No admin endpoint" with the reload trade-off; Regulator; Failure prevented; Alternatives, the admin socket among them), D10 new legs, Risks / Trade-offs (restart trade-off); FII `The ingress proxy runs inside a declared envelope` (text, discharge `adminLoadIgnored`, scenario `A local account posts a configuration to caddy`); plan.md Architecture, Service and Container cases rows; plan/task-1.md Step 5 Caddyfile; plan/task-4.md Steps 3 and 4; tasks.md 4.3 and 4.4; the assertion that admin is not TCP is not added, because no admin endpoint remains |
| R2 | design D3 socket paragraph; FII `The ingress receiver accepts only certificate holders on magnetite's ZeroTier address` (text, discharge); plan.md Socket row; plan/task-1.md Step 5 socket test; plan/task-4.md Step 4 (tmpfiles form, fallback, deferral removed); tasks.md 1.5 and 4.4 |
| R3 | design Risks / Trade-offs, Migration Plan steps 4 and 5; plan.md Gates; plan/task-3.md Step 5; plan/task-5.md Step 1; tasks.md 3.4 and 5.1 |
| R4 | design attacker table, D5 (Choice, Rationale), D10 new legs; FII `A mesh write is stored only under the host that sent it` (text, discharge, scenario `A write names a database or table no agent writes`) and trust-boundary scenarios `The properties above are read as a set` and `A guarantee about a certificate holder is sought`; proposal trust boundary; plan.md Architecture, Pipelines and Container cases rows; plan/task-1.md Step 5 conditions and posts; plan/task-4.md Steps 3 and 4; tasks.md 1.5, 4.3 and 4.4 |
| R5 | design D5 Rationale, D11, Migration Plan pull request 1; FII `The collection CA issues each agent host one certificate` (text, discharge `hostNameDiffers`); plan.md Architecture and Assertion row; plan/task-2.md Files and Step 3; tasks.md 2.3 |
| R6 | design Goals, Risks / Trade-offs; FII `A guarantee about a copied key is sought`; HMC `A collection certificate is copied to another overlay member`; proposal trust boundary |
| R7 | design D3 (`meshListen`), D4 Choice (`meshPinNeighbours`), D10 Choice; plan.md Options and Networkd rows; plan/task-4.md Steps 3, 4 and 5 (the neighbour leg's eight-group addresses); tasks.md 4.3, 4.4 and 4.5 |
| R8 | plan/task-4.md Step 1 (fixtures, cases, the rewritten clause, `runtimeInputs`); tasks.md 4.1 |
| R9 | design Layout, D7, D11; FII `A mesh write is stored only under the host that sent it` discharge and `This capability states its own trust boundary`; WA A76 evidence and scenario; plan.md Check row; plan/task-1.md Step 5; plan/task-4.md Files, Steps 3, 4 and 6; tasks.md 1.5, 4.3, 4.4 and 4.6 |
| R10 | design D3 Regulator, D9; WA A75 evidence; plan.md Assertions row; plan/task-4.md Step 2 (`caddyVersion`, `caddyVersionMoved`); tasks.md 4.2 |
| R11 | plan/task-1.md Step 5 caddy probe; plan/task-4.md Step 1 caddy fixtures; tasks.md 1.5 and 4.1 |
| R12 | design D4 Choice, D7; FII `One host table declares the agent hosts and what each reports`; plan.md Addresses constraint and Check clauses row; plan/task-2.md Interfaces and Step 1; plan/task-4.md Step 5; tasks.md 2.1 and 4.5 |
| R13 | design Layout, D7 (Choice, Mutants); FII `One host table declares the agent hosts and what each reports` (text, scenario `An agent host's overlay address disagrees with its second source`); proposal Regulation; plan.md Architecture and Inventory row; plan/task-2.md Files, Interfaces and Step 1; tasks.md 2.1 |
| R14 | design Layout, D3 Regulator, D7 (Choice, Mutants), D11; FII discharges of `A mesh write is accepted only from the host its certificate names, at that host's overlay address` and `magnetite pins each collecting host's neighbour entry`; plan.md Assertions row; plan/task-4.md Steps 2 and 4; tasks.md 4.2 and 4.4 |
| R15 | design D11; FII `The ingress receiver accepts only certificate holders on magnetite's ZeroTier address` discharge; plan.md Assertions row; plan/task-4.md Step 2; tasks.md 4.2 |
| R16 | design D6 (Choice, Regulator); FII `otel-envelope on the ingress host fails when the binding refuses or drops a write` (text, discharge, scenario `A liveness series disappears`); plan.md Architecture and Check row; plan/task-4.md Step 1; tasks.md 4.1 |
| R17 | design D10 Neighbour leg; plan/task-4.md Step 5; tasks.md 4.5; 1.4 is unchanged |
| R18 | plan/task-2.md Steps 2 and 3; plan/task-4.md Step 5; tasks.md 2.2, 2.3 and 4.5 |
| R19 | plan/task-2.md Step 3; plan/task-4.md Step 1; tasks.md 2.3 and 4.1 |
| R20 | design D4 Boundary, D10 Boundary; FII `magnetite pins each collecting host's neighbour entry` discharge; WA A73 evidence and scenario; plan/task-4.md Step 5 |
| R21 | design D7; FII `One host table declares the agent hosts and what each reports`; plan.md `flake.lib.hosts` row; plan/task-2.md Step 1; tasks.md 2.1 |
| R22 | design D7; plan.md Options row; plan/task-4.md Steps 3 and 4 |
| R23 | design D8; FII `A mesh write is stored only under the host that sent it` (discharge, scenario `A pipeline receives mesh writes without the binding`); plan.md Assertions row; plan/task-4.md Step 2; tasks.md 4.2 |
| R24 | plan/task-4.md Step 4; tasks.md 4.4 |
| R25 | design D4 Rollback, Risks / Trade-offs, Migration Plan "Rollback"; plan.md Global Constraints (rollback exception) and Rollback; plan/task-5.md Step 5; tasks.md 5.5 |
| F2 | design D11; plan.md Evaluation cost; plan/task-2.md Step 5; plan/task-4.md Step 6; tasks.md 2.5 and 4.6 |
| F3 | plan/task-2.md Step 1; plan/task-4.md Step 1; tasks.md 2.1 and 4.1 |

## R1 recommended design

caddy's global options become `admin off`, and `services.caddy.enableReload = false`, because nixpkgs' `reload` path needs the admin API (`nixos/modules/services/web-servers/caddy/default.nix:326-339`, `:462-483` at the root pin).
caddy's metrics move from the admin endpoint to an ordinary site, `http://127.0.0.1:2019` with `bind 127.0.0.1` and only the `metrics` handler (`modules/metrics/metrics.go:31-33` in caddy 2.11.7), so C2's probe URL and C6's scrape keep their address and no handler on that site can change configuration.
A container case posts `POST /load` to `127.0.0.1:2019` and reads that the mesh site's 403 and header behaviour are unchanged after it.
The trade-off is that every Caddyfile change restarts caddy instead of reloading it.
A restart refuses mesh connections until caddy has started again, a duration not yet measured; the agents retry from their file-backed queues, the same as on the certificate `restartUnits` restart the design already accepts.
The alternative keeps reloads: `admin unix//run/caddy/admin.sock|0200`, which caddy creates owned by its own account with mode 0200 (`internal/sockets.go:34-55`), with `RuntimeDirectory = "caddy"`.
Only caddy's account and root can then reach the admin API, and `caddy reload` from `ExecReload` runs as that account.
It costs a socket path and its mode as one more property to judge, for zero-downtime reloads that a configuration changed only by deploys does not need.

